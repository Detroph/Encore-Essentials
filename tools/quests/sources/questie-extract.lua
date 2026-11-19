-- Reads QuestieDB's WoW Forever layers and prints them as JSON for tools/quests/sources/questie.mjs.
-- Usage (from anywhere): lua questie-extract.lua <QuestieDB checkout> [full|forever]
--
-- full (default): QuestieDB's whole Forever database, in its own order: the base data (data/Forever, Questie's
-- Classic data converted to Forever's maps), the inherited corrections (src/corrections/Forever/legacy), then
-- the Forever layers below.
-- forever: only the Forever-specific layers:
--   src/corrections/Forever/generated/foreverBase{Quest,Npc}.lua   (Forever delta-base: Wowhead Forever and traces)
--   src/corrections/Forever/traces/forever{Quest,QuestRelation,Npc}Traces.lua  (QuestieTrace, recorded in Forever)
--   src/corrections/Forever/forever{Quest,NPC}Fixes.lua            (hand-written Forever corrections)
-- plus enums and Forever zone support (area -> uiMap). Field keys are kept as their names.
local root = assert(arg[1], "usage: lua questie-extract.lua <QuestieDB checkout> [full|forever]")
local scope = arg[2] or "full"
root = root:gsub("[/\\]$", "")
local function path(p) return root .. "/" .. p end

-- A stand-in for anything the providers touch that this export does not need: indexing, calling and arithmetic
-- all work and give nothing useful.
local Any
Any = setmetatable({}, {
    __index = function() return Any end,
    __newindex = function() end,
    __call = function(_, a) return a end,
    __add = function() return 0 end,
    __unm = function() return 0 end,
    __lt = function() return false end,
    __le = function() return false end,
    __eq = function() return false end,
})

-- Real enums where values matter: zones, races, and the field names themselves.
local Lib = { Enum = {} }
local function loadEnum(p) local f = assert(loadfile(path(p))); f(nil, Lib) end
loadEnum("src/corrections/enum/zones.lua")
pcall(loadEnum, "src/corrections/enum/expansions.lua")
local foreverEnums = Lib.Enum.byExpansion and Lib.Enum.byExpansion.Forever or {}
local raceKeys = foreverEnums.raceKeys or {}

local names = setmetatable({}, { __index = function(_, k) return k end }) -- questKeys.name -> "name"
local zero = setmetatable({}, { __index = function() return 0 end })
local sortKeys = setmetatable({}, { __index = function() return -1 end }) -- a quest category, not an area

local QuestieDB = setmetatable({
    questKeys = names, npcKeys = names, itemKeys = names, objectKeys = names,
    raceKeys = setmetatable(raceKeys, { __index = function() return 0 end }),
    classKeys = zero, sortKeys = sortKeys, specialFlags = zero, factionIDs = zero,
}, { __index = function() return Any end })
local ZoneDB = setmetatable({ zoneIDs = Lib.Enum.zoneIDs or zero, private = {} }, { __index = function() return Any end })

local modules = {}
_G.QuestieLoader = {
    CreateModule = function(_, name) local m = {}; modules[name] = m; return m end,
    ImportModule = function(_, name)
        if name == "QuestieDB" then return QuestieDB end
        if name == "ZoneDB" then return ZoneDB end
        return Any
    end,
}
_G.Questie = Any
_G.UnitFactionGroup = function() return "Horde" end

local function provider(p, name)
    local f = loadfile(path(p))
    if not f then return {} end
    f()
    local m = modules[name]
    if not (m and m.Load) then return {} end
    local ok, t = pcall(m.Load, m)
    if not ok then
        if io and io.stderr then io.stderr:write(p .. ": " .. tostring(t) .. "\n") end
        return {}
    end
    return t or {}
end

-- Later layers override earlier ones field by field; "_add" fields add to a list field.
local function apply(into, layer)
    for id, fields in pairs(layer) do
        local e = into[id] or {}
        into[id] = e
        for k, v in pairs(fields) do
            if type(k) == "string" then e[k] = v end
        end
    end
end

local quests, npcs = {}, {}

-- Base data: positional rows; the file's own key enum gives each position's field name.
local function baseData(p, keysField, dataField, into)
    local f = loadfile(path(p))
    if not f then return end
    QuestieDB[keysField], QuestieDB[dataField] = nil, nil
    f()
    local keys, data = rawget(QuestieDB, keysField), rawget(QuestieDB, dataField)
    QuestieDB[keysField], QuestieDB[dataField] = names, nil
    if type(keys) ~= "table" or type(data) ~= "string" then return end
    local byIndex = {}
    for name, i in pairs(keys) do byIndex[i] = name end
    local rows = assert(loadstring(data))()
    for id, row in pairs(rows) do
        local e = {}
        for i, v in pairs(row) do if byIndex[i] then e[byIndex[i]] = v end end
        into[id] = e
    end
end

if scope == "full" then
    baseData("data/Forever/foreverQuestDB.lua", "questKeys", "questData", quests)
    baseData("data/Forever/foreverNpcDB.lua", "npcKeys", "npcData", npcs)
    apply(quests, provider("src/corrections/Forever/legacy/classicQuestFixes.lua", "QuestieQuestFixes"))
    apply(npcs, provider("src/corrections/Forever/legacy/classicNPCFixes.lua", "QuestieNPCFixes"))
end
for _, p in ipairs({
    { "src/corrections/Forever/generated/foreverBaseQuest.lua", "ForeverBaseQuest" },
    { "src/corrections/Forever/traces/foreverQuestTraces.lua", "ForeverQuestTraces" },
    { "src/corrections/Forever/traces/foreverQuestRelationTraces.lua", "ForeverQuestRelationTraces" },
    { "src/corrections/Forever/foreverQuestFixes.lua", "ForeverQuestFixes" },
}) do apply(quests, provider(p[1], p[2])) end
for _, p in ipairs({
    { "src/corrections/Forever/generated/foreverBaseNpc.lua", "ForeverBaseNpc" },
    { "src/corrections/Forever/traces/foreverNpcTraces.lua", "ForeverNpcTraces" },
    { "src/corrections/Forever/foreverNPCFixes.lua", "ForeverNpcFixes" },
}) do apply(npcs, provider(p[1], p[2])) end

-- AreaTable ID -> uiMap (Forever client DBC relationships)
local areaToMap = {}
do
    local f = loadfile(path("support/Forever/Zones/areaIdToUiMapId.lua"))
    if f then
        pcall(f)
        for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
            local src = ZoneDB.private[key]
            if type(src) == "string" then
                local ok, t = pcall(assert(loadstring(src)))
                if ok and type(t) == "table" then for a, m in pairs(t) do areaToMap[a] = m end end
            end
        end
    end
end

-- Dungeon areas (support/Forever/Zones/dungeons.lua): [areaId] = { name, alternative area IDs }
local dungeons = {}
do
    local f = loadfile(path("support/Forever/Zones/dungeons.lua"))
    if f then
        local ok, err = pcall(f)
        if not ok and io and io.stderr then io.stderr:write("dungeons.lua: " .. tostring(err) .. "\n") end
        local captured = ZoneDB.private.dungeons
        if type(captured) == "table" then
            for area, d in pairs(captured) do
                if type(d) == "table" and type(d[1]) == "string" then dungeons["#" .. area] = { d[1], d[2] } end
            end
        end
    end
end

-- Zone symbol names, so instances can be matched by name ("KROL_DOK_STRONGHOLD" -> 17780)
local zoneNames = {}
for name, id in pairs(Lib.Enum.zoneIDs or {}) do
    if type(id) == "number" then zoneNames[tostring(id)] = name end
end

-- Minimal JSON writer
local function json(v)
    local t = type(v)
    if t == "nil" then return "null" end
    if t == "boolean" then return tostring(v) end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        return (math.floor(v) == v and ("%d"):format(v)) or ("%.4f"):format(v)
    end
    if t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c)
            local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
            return map[c] or ("\\u%04x"):format(c:byte())
        end) .. '"'
    end
    if t == "table" then
        if v == Any then return "null" end
        local n, max, isList = 0, 0, true
        for k in pairs(v) do
            n = n + 1
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then isList = false elseif k > max then max = k end
        end
        local out = {}
        if isList and n > 0 and (n == max or max <= 2 * n + 2) then -- dense enough to be a list (nil holes allowed)
            for i = 1, max do out[i] = json(v[i]) end -- nil holes become null
            return "[" .. table.concat(out, ",") .. "]"
        end
        for k, x in pairs(v) do out[#out + 1] = json(tostring(k)) .. ":" .. json(x) end
        return "{" .. table.concat(out, ",") .. "}"
    end
    return "null"
end

-- ID maps are written with string keys so they stay JSON objects. Only quests and the NPCs that start or end
-- them are needed.
local function byId(t, keep)
    local o = {}
    for id, v in pairs(t) do
        if not keep or keep[id] then o["#" .. tostring(id)] = v end
    end
    return o
end
local wantNpc = {}
for _, q in pairs(quests) do
    for _, k in ipairs({ "startedBy", "finishedBy", "startedBy_add", "finishedBy_add" }) do
        local npcList = type(q[k]) == "table" and q[k][1]
        if type(npcList) == "table" then for _, n in pairs(npcList) do wantNpc[n] = true end end
    end
end
for id, n in pairs(npcs) do
    for _, k in ipairs({ "questStarts", "questEnds", "questStarts_add", "questEnds_add" }) do
        if type(n[k]) == "table" and next(n[k]) then wantNpc[id] = true end
    end
end
local slimNpcs = {}
for id in pairs(wantNpc) do
    local n = npcs[id]
    if n then slimNpcs[id] = { name = n.name, spawns = n.spawns, zoneID = n.zoneID, questStarts = n.questStarts,
        questEnds = n.questEnds, questStarts_add = n.questStarts_add, questEnds_add = n.questEnds_add } end
end
local out = json({ scope = scope, quests = byId(quests), npcs = byId(slimNpcs), areaToMap = byId(areaToMap), zoneNames = zoneNames, dungeons = dungeons })
if io and io.write then io.write(out) end
return out
