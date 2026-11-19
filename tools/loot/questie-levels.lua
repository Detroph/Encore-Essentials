-- Reads NPC levels and ranks from QuestieDB's WoW Forever database and prints them as JSON for
-- tools/loot/questie-levels.mjs.
-- Usage: lua questie-levels.lua <QuestieDB checkout>
--
-- Same layers, in the same order, as the quest export (tools/quests/sources/questie-extract.lua): the base data
-- (data/Forever/foreverNpcDB.lua), the inherited corrections (src/corrections/Forever/legacy), then the Forever
-- layers (generated delta-base from Wowhead Forever, QuestieTrace recordings, hand-written Forever fixes).
-- Output: { "<npc id>": [minLevel, maxLevel, rank], ... }. Rank is cmangos's: 0 normal, 1 elite, 2 rare elite,
-- 3 boss, 4 rare.
local root = assert(arg[1], "usage: lua questie-levels.lua <QuestieDB checkout>")
root = root:gsub("[/\\]$", "")
local function path(p) return root .. "/" .. p end

-- A stand-in for whatever the providers touch that this export does not need.
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

-- Real enums where values matter: ranks and zones.
local Lib = { Enum = {} }
for _, p in ipairs({ "src/corrections/enum/npcs.lua", "src/corrections/enum/zones.lua" }) do
    local f = loadfile(path(p))
    if f then pcall(f, nil, Lib) end
end

local names = setmetatable({}, { __index = function(_, k) return k end }) -- npcKeys.minLevel -> "minLevel"
local zero = setmetatable({}, { __index = function() return 0 end })
local QuestieDB = setmetatable({
    questKeys = names, npcKeys = names, itemKeys = names, objectKeys = names,
    npcRanks = Lib.Enum.npcRanks or { NORMAL = 0, ELITE = 1, RARE_ELITE = 2, BOSS = 3, RARE = 4 },
    raceKeys = zero, classKeys = zero, sortKeys = zero, specialFlags = zero, factionIDs = zero,
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

local npcs = {}

-- Base data: positional rows named by the file's own key enum.
do
    local f = assert(loadfile(path("data/Forever/foreverNpcDB.lua")), "no data/Forever/foreverNpcDB.lua")
    QuestieDB.npcKeys, QuestieDB.npcData = nil, nil
    f()
    local keys, data = rawget(QuestieDB, "npcKeys"), rawget(QuestieDB, "npcData")
    QuestieDB.npcKeys = names
    local rows = assert(loadstring(data))()
    for id, row in pairs(rows) do
        npcs[id] = { minLevel = row[keys.minLevel], maxLevel = row[keys.maxLevel], rank = row[keys.rank] }
    end
end

-- Later layers override earlier ones field by field.
local function layer(p, name)
    local f = loadfile(path(p))
    if not f then return end
    f()
    local m = modules[name]
    if not (m and m.Load) then return end
    local ok, t = pcall(m.Load, m)
    if not ok then
        if io and io.stderr then io.stderr:write(p .. ": " .. tostring(t) .. "\n") end
        return
    end
    for id, fields in pairs(t or {}) do
        if type(fields) == "table" then
            local e = npcs[id] or {}
            npcs[id] = e
            for _, k in ipairs({ "minLevel", "maxLevel", "rank" }) do
                if type(fields[k]) == "number" then e[k] = fields[k] end
            end
        end
    end
end
layer("src/corrections/Forever/legacy/classicNPCFixes.lua", "QuestieNPCFixes")
layer("src/corrections/Forever/generated/foreverBaseNpc.lua", "ForeverBaseNpc")
layer("src/corrections/Forever/traces/foreverNpcTraces.lua", "ForeverNpcTraces")
layer("src/corrections/Forever/foreverNPCFixes.lua", "ForeverNpcFixes")

local out = {}
for id, e in pairs(npcs) do
    local lo, hi = e.minLevel, e.maxLevel
    if type(lo) == "number" or type(hi) == "number" then
        lo = lo or hi; hi = hi or lo
        if hi < lo then hi = lo end -- a layer raised minLevel only
        out[#out + 1] = ('"%d":[%d,%d,%d]'):format(id, lo, hi, tonumber(e.rank) or 0)
    end
end
io.write("{" .. table.concat(out, ",") .. "}")
