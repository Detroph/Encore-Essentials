-- Encore-DB quest source: the QuestieDB addon (https://github.com/Questie/QuestieDB, GPL-3.0), read live through
-- its public API (LibQuestieDB; QuestieDB's docs/api.md). No QuestieDB data is bundled with Encore: players get
-- every QuestieDB update without a new Encore release, as QuestieDB's authors ask of addons that use it.
--
-- QuestieDB is a required dependency on CurseForge (the CurseForge app installs it) but only an optional one in
-- the .toc, so the loot, recipe and vendor pages work without it; the Quests rows then say how to get it.
--
-- What it gives the quest data layer (QuestData.lua), as a source in its usual format, priority 10 (above the
-- Wowhead Forever fill-ins):
--   each instance's quests (a quest's category is the instance's area; quests new in Forever that QuestieDB files
--   under a zone are placed by the instance name in their text), titles, levels, faction, objectives, where they
--   start and end, the chains around them, reward items, reputation, and XP (QuestieDB's quest XP table, recorded
--   in WoW Forever).
-- The quests are read a slice at a time over a few frames after Encore-DB loads, so opening the window never
-- stalls; the window redraws when they are in.
--
-- Boss levels: QuestieDB's Forever NPC levels replace the bundled ones for every boss with an NPC ID (the bundled
-- Wowhead Forever levels stay for bosses QuestieDB does not know).
local _, ns = ...
local DB = ns.DB

-- state: "missing" (no QuestieDB), "old" (too old for this API), "loading", "ready", "failed"
local Live = { state = "missing" }
DB.QuestieLive = Live

local CONTRACT = 3          -- Enum.factionRaceMasks and Enum.raceMaskById
local FIRST_FOREVER_ID = 90000
local PER_SLICE = 250       -- entities read per frame
local URL = "https://github.com/Questie/QuestieDB"

local Lib = _G.LibQuestieDB
local QuestDB, NpcDB, ItemDB, ObjectDB

local function metadata(addon, key)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    if not get then return nil end
    local ok, v = pcall(get, addon, key)
    return ok and v or nil
end

-- Why there are no quests, for the window: nil when there is nothing to say.
function Live:Notice()
    if self.state == "missing" then
        return "Dungeon quests come from the QuestieDB addon. Install QuestieDB (CurseForge) and reload to see them."
    elseif self.state == "old" then
        return "Your QuestieDB is too old for Encore-DB's quests. Update QuestieDB and reload."
    elseif self.state == "failed" then
        return "Encore-DB could not read the quests from QuestieDB. " .. tostring(self.message or "")
    elseif self.state == "loading" then
        return "Reading the dungeon quests from QuestieDB..."
    end
end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function slug(s)
    s = s:lower():gsub("['\226\128\153]", ""):gsub("[^a-z0-9]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    return s
end
local function flat(s) return (slug(s):gsub("^the%-", ""):gsub("%-", "")) end
local ALIAS = { stockade = "stormwindstockade", templeofatalhakkar = "sunkentemple" }

local function ids(v)
    if type(v) == "number" then return v ~= 0 and { v } or {} end
    if type(v) ~= "table" then return {} end
    local out = {}
    for _, x in pairs(v) do if type(x) == "number" and x ~= 0 then out[#out + 1] = x end end
    return out
end

local function round1(v) return math.floor(v * 10 + 0.5) / 10 end

-- Bit n of a mask wider than 32 bits, without 32-bit bit operations (Skyborne races sit at bits 32 and 33).
local function hasBit(mask, bitValue) return math.floor(mask / bitValue) % 2 == 1 end

local function loadTable(src)
    if type(src) == "table" then return src end
    if type(src) ~= "string" then return nil end
    local f = loadstring(src)
    if not f then return nil end
    local ok, t = pcall(f)
    return ok and type(t) == "table" and t or nil
end

---------------------------------------------------------------------------
-- Boss levels (cheap: one NPC read per boss, done at load)
---------------------------------------------------------------------------
local function applyBossLevels()
    local n = 0
    for _, inst in ipairs((ns.Loot and ns.Loot.instances) or {}) do
        for _, boss in ipairs(inst.bosses or {}) do
            if boss.npc and NpcDB.Exists(boss.npc) then
                local lo, hi, rank = NpcDB.minLevel(boss.npc), NpcDB.maxLevel(boss.npc), NpcDB.rank(boss.npc)
                if lo ~= 0 or hi ~= 0 then
                    if lo == 0 then lo = hi end
                    if hi < lo then hi = lo end
                    boss.level = rank == 3 and -1 or hi -- rank 3: boss, the skull
                    boss.levelMin = lo
                    n = n + 1
                end
            end
        end
    end
    Live.bossLevels = n
end

---------------------------------------------------------------------------
-- The quest source
---------------------------------------------------------------------------
local function build()
    local Support = Lib.Support
    local ZoneDB = Support and Support.Get and Support.Get("ZoneDB") or {}
    local zprivate = ZoneDB.private or {}
    local XP = Support and Support.Get and Support.Get("QuestXP")
    local xpDB = XP and XP.db or {}

    -- AreaTable ID -> uiMap, for the map pins.
    local areaToMap = {}
    for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
        for a, m in pairs(loadTable(zprivate[key]) or {}) do areaToMap[a] = m end
    end

    -- The instances Encore-DB knows, by their flattened name.
    local instances, byFlat = {}, {}
    for _, inst in ipairs((ns.Loot and ns.Loot.instances) or {}) do
        if inst.key and inst.name then
            local I = { key = (inst.key:gsub("/.*", "")), name = inst.name }
            instances[#instances + 1] = I
            byFlat[flat(inst.name)] = byFlat[flat(inst.name)] or I
        end
    end
    local function match(name)
        local f = flat(name)
        return byFlat[ALIAS[f] or f]
    end
    -- Area -> instance: QuestieDB's dungeon list (and the dungeons' other area IDs), then its zone symbols.
    local areaInstance = {}
    for area, d in pairs(type(zprivate.dungeons) == "table" and zprivate.dungeons or {}) do
        local I = type(d) == "table" and type(d[1]) == "string" and match(d[1])
        if I then
            areaInstance[area] = I
            for _, alt in ipairs(type(d[2]) == "table" and d[2] or {}) do areaInstance[alt] = I end
        end
    end
    for sym, area in pairs(ZoneDB.zoneIDs or (Lib.Enum and Lib.Enum.zoneIDs) or {}) do
        if type(sym) == "string" and type(area) == "number" and not areaInstance[area] then
            local I = match((sym:gsub("_", " ")))
            if I then areaInstance[area] = I end
        end
    end

    -- Faction from the race mask.
    local raceMask = Lib.Enum.raceMaskById or {}
    local fmask = Lib.Enum.factionRaceMasks or {}
    local function side(mask)
        if type(mask) ~= "number" or mask == 0 then return nil end
        local a, h = false, false
        for _, b in pairs(raceMask) do
            if hasBit(mask, b) then
                if fmask.Alliance and hasBit(fmask.Alliance, b) then a = true end
                if fmask.Horde and hasBit(fmask.Horde, b) then h = true end
            end
        end
        if a and not h then return "A" elseif h and not a then return "H" end
        return nil
    end

    -- Pass 1: every quest's instance and links (the reverse links need every quest).
    local named, links, byInstance = {}, {}, {}
    local allQuests = QuestDB.GetAllIds()
    for i, id in ipairs(allQuests) do
        local name = QuestDB.name(id)
        if name then
            named[id] = true
            for _, p in ipairs(ids(QuestDB.preQuestSingle(id))) do links[#links + 1] = { p, id } end
            for _, p in ipairs(ids(QuestDB.preQuestGroup(id))) do links[#links + 1] = { p, id } end
            for _, p in ipairs(ids(QuestDB.breadcrumbs(id))) do links[#links + 1] = { p, id } end
            for _, n in ipairs(ids(QuestDB.nextQuestInChain(id))) do links[#links + 1] = { id, n } end
            for _, n in ipairs(ids(QuestDB.childQuests(id))) do links[#links + 1] = { id, n } end
            for _, n in ipairs(ids(QuestDB.breadcrumbForQuestId(id))) do links[#links + 1] = { id, n } end
            local zone = QuestDB.zoneOrSort(id)
            local I = zone > 0 and areaInstance[zone]
            if not I and id >= FIRST_FOREVER_ID then
                local text = (name .. " " .. table.concat(QuestDB.objectivesText(id) or {}, " ")):lower()
                for _, cand in ipairs(instances) do
                    local iname = cand.name:lower()
                    if #iname >= 6 and text:find(iname, 1, true) then I = cand; break end
                end
            end
            if I then
                byInstance[I.key] = byInstance[I.key] or {}
                table.insert(byInstance[I.key], id)
            end
        end
        if i % PER_SLICE == 0 then coroutine.yield() end
    end
    local prev, nxt = {}, {}
    local function add(map, a, b)
        local s = map[a]
        if not s then s = {}; map[a] = s end
        s[b] = true
    end
    for _, l in ipairs(links) do
        local a, b = l[1], l[2]
        if a ~= b and named[a] and named[b] then
            add(nxt, a, b)
            add(prev, b, a)
        end
    end
    local function sorted(set)
        local out = {}
        for k in pairs(set or {}) do out[#out + 1] = k end
        table.sort(out)
        return out
    end

    -- Where a quest starts or ends: the first NPC (with a map spot), else object, else item.
    local function spot(spawns)
        if type(spawns) ~= "table" then return nil end
        local areas = sorted(spawns)
        for _, area in ipairs(areas) do
            local map = areaToMap[area]
            local list = spawns[area]
            if map and map ~= 0 and type(list) == "table" then
                for _, p in ipairs(list) do
                    if type(p) == "table" and type(p[1]) == "number" and p[1] > 0 then return map, p[1], p[2] end
                end
            end
        end
    end
    local function who(g)
        if type(g) ~= "table" then return nil end
        local n, o, it = ids(g[1]), ids(g[2]), ids(g[3])
        local kind, id, E
        if n[1] then kind, id, E = "npc", n[1], NpcDB
        elseif o[1] then kind, id, E = "object", o[1], ObjectDB
        elseif it[1] then kind, id, E = "item", it[1], ItemDB
        else return nil end
        local w = { kind, id, E.name(id) }
        if E ~= ItemDB then
            local map, x, y = spot(E.spawns(id))
            if map then w[4], w[5], w[6] = map, round1(x), round1(y) end
        end
        return w
    end

    -- Pass 2: the instances' quests and every quest chained to them.
    local quests, todo, count = {}, {}, 0
    for _, list in pairs(byInstance) do for _, id in ipairs(list) do todo[#todo + 1] = id end end
    while #todo > 0 do
        local id = table.remove(todo)
        if not quests[id] then
            local q = { title = QuestDB.name(id) }
            if id >= FIRST_FOREVER_ID then q.new = true end
            local lvl, req = QuestDB.questLevel(id), QuestDB.requiredLevel(id)
            if lvl > 0 then q.level = lvl end
            if req > 0 then q.minLevel = req end
            q.side = side(QuestDB.requiredRaces(id))
            local obj = table.concat(QuestDB.objectivesText(id) or {}, " "):gsub("^%s+", ""):gsub("%s+$", "")
            if obj ~= "" then q.objective = obj end
            q.start = who(QuestDB.startedBy(id))
            q.finish = who(QuestDB.finishedBy(id))
            local p, n = sorted(prev[id]), sorted(nxt[id])
            if #p > 0 then q.prev = p end
            if #n > 0 then q.next = n end
            local rep = {}
            for _, r in ipairs(QuestDB.reputationReward(id) or {}) do
                if type(r) == "table" and type(r[1]) == "number" and r[1] > 0 and type(r[2]) == "number" and r[2] ~= 0 then
                    rep[#rep + 1] = { r[1], r[2] }
                end
            end
            if #rep > 0 then q.rep = rep end
            local xp = xpDB[id]
            if type(xp) == "table" and type(xp[2]) == "number" and xp[2] > 0 then q.xp = xp[2] end
            quests[id] = q
            count = count + 1
            for _, x in ipairs(p) do if not quests[x] then todo[#todo + 1] = x end end
            for _, x in ipairs(n) do if not quests[x] then todo[#todo + 1] = x end end
            if count % PER_SLICE == 0 then coroutine.yield() end
        end
    end

    -- Pass 3: reward items. QuestieDB keeps them on the item (the quests it rewards), so every item is read once.
    local items = {}
    for i, id in ipairs(ItemDB.GetAllIds()) do
        local rewards = ItemDB.questRewards(id)
        if rewards then
            for _, qid in ipairs(ids(rewards)) do
                local q = quests[qid]
                if q then
                    q.rewardItems = q.rewardItems or {}
                    table.insert(q.rewardItems, id)
                    if not items[id] then items[id] = { ItemDB.name(id) } end
                end
            end
        end
        if i % (PER_SLICE * 2) == 0 then coroutine.yield() end
    end

    -- Each instance's quests by level, then ID.
    for _, list in pairs(byInstance) do
        table.sort(list, function(a, b)
            local la, lb = quests[a].level or 0, quests[b].level or 0
            if la ~= lb then return la < lb end
            return a < b
        end)
    end

    local version = metadata("QuestieDB", "Version")
    return {
        id = "questie", name = "QuestieDB", url = URL,
        credit = "Quest data from the QuestieDB addon by the Questie team (" .. URL .. ")",
        version = "QuestieDB " .. tostring(version or "?"), priority = 10,
        instances = byInstance, quests = quests, items = items,
    }, count
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
local function redraw()
    local U = ns.UI
    if U and U.isShown and U.isShown() and U.renderAll then U.renderAll() end
end

function Live:Start()
    if self.state ~= "missing" then return end
    -- An installed QuestieDB normally loads at login; load it now if it is installed as load-on-demand.
    if not _G.LibQuestieDB then
        local load = (C_AddOns and C_AddOns.LoadAddOn) or _G.LoadAddOn
        if load then pcall(load, "QuestieDB") end
    end
    Lib = _G.LibQuestieDB
    if type(Lib) ~= "table" or not Lib.RequireContract or not Lib.Quest then return end
    local ok, msg = Lib.RequireContract(CONTRACT)
    if not ok then
        self.state, self.message = "old", msg
        return
    end
    QuestDB, NpcDB, ItemDB, ObjectDB = Lib.Quest, Lib.Npc, Lib.Item, Lib.Object
    local okLevels, err = pcall(applyBossLevels)
    if not okLevels then self.levelError = err end

    self.state = "loading"
    local co = coroutine.create(build)
    local function step()
        local okStep, src, count = coroutine.resume(co)
        if not okStep then
            self.state, self.message = "failed", tostring(src)
            redraw()
            return
        end
        if coroutine.status(co) == "dead" then
            self.state, self.count = "ready", count
            DB.Quests:AddSource(src)
            redraw()
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0, step)
        else
            step()
        end
    end
    step()
end

Live:Start()
