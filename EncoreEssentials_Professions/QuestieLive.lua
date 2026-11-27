-- Encore-Professions: what it takes from the QuestieDB addon (https://github.com/Questie/QuestieDB, GPL-3.0), read
-- live through QuestieDB's public API (LibQuestieDB) instead of a bundled copy, as QuestieDB's authors ask:
--   ns.Trainers     profession trainers (trainer flag and title), where they stand, their side and highest rank
--   ns.Zones        each outdoor zone's wild mob levels (for fishing) and skinnable beasts' levels (lo, hi, beasts);
--                   the fish caught there stay GatherLite's (Data\World.lua)
--   ns.Ranks        the names and places of the rank books' vendors and the rank quests' givers
--   ns.RecipeVendors  recipe vendors' places, where QuestieDB knows the NPC (Encore-DB's ForeverDB places otherwise)
-- Trainers and zones need a pass over every NPC, so they are worked out a slice per frame a few seconds after
-- login and kept in EncoreProfessionsDB until QuestieDB (or this format) changes. Without QuestieDB the guide still
-- plans routes; trainer places and the zone suggestions for skinning and fishing are left out.
local _, ns = ...
local P = ns.P

local Live = { state = "missing" } -- "missing", "old", "loading", "ready", "failed"
ns.QuestieLive = Live

local CONTRACT = 3
local FORMAT = 1         -- bump when the cached shape changes
local PER_SLICE = 300
local START_DELAY = 5    -- seconds after login

ns.Trainers = ns.Trainers or {}
ns.Zones = ns.Zones or {}

-- Profession trainers by their (English) title. Specialisation trainers teach no ranks and are left out.
local TRAINER_TITLE = {
    ["Alchemy"] = { "%f[%a]Alchemist%f[%A]", "^Alchemy Trainer$" },
    ["Blacksmithing"] = { "^Journeyman Blacksmith$", "^Expert Blacksmith$", "^Artisan Blacksmith$", "^Master Blacksmith$", "^Blacksmithing Trainer$" },
    ["Enchanting"] = { "%f[%a]Enchanter%f[%A]", "^Enchanting Trainer$" },
    ["Engineering"] = { "^Journeyman Engineer$", "^Expert Engineer$", "^Artisan Engineer$", "^Master Engineer$", "^Engineering Trainer$" },
    ["Leatherworking"] = { "^Journeyman Leatherworker$", "^Expert Leatherworker$", "^Artisan Leatherworker$", "^Master Leatherworker$", "^Leatherworking Trainer$" },
    ["Tailoring"] = { "^Journeyman Tailor$", "^Expert Tailor$", "^Artisan Tailor$", "^Master Tailor$", "^Tailoring Trainer$" },
    ["Cooking"] = { "^Cooking Trainer$", "^Cook$", "^Chef$" },
    ["First Aid"] = { "^First Aid Trainer$", "^Physician$", "^Surgeon$" },
    ["Fishing"] = { "^Fishing Trainer$", "^Fisherman$", "^Superior Fisherman$" },
    ["Herbalism"] = { "^Herbalism Trainer$", "^Herbalist$", "^Superior Herbalist$" },
    ["Mining"] = { "^Mining Trainer$", "^Miner$" },
    ["Skinning"] = { "^Skinning Trainer$", "^Skinner$" },
}
local NOT_TRAINER = { "Supplies", "Supplier", "Shadoweave", "Mooncloth", "Spellfire", "Dragonscale", "Elemental", "Tribal", "Gnom", "Goblin", "World" }

-- Skinnable beasts, by name (QuestieDB has no creature type). Names only pick the mobs to count.
local BEAST_WORDS = { "Wolf", "Worg", "Boar", "Bear", "Grizzly", "Cat", "Lion", "Lioness", "Panther", "Tiger", "Leopard",
    "Lynx", "Sabercat", "Saber", "Stalker", "Prowler", "Raptor", "Crocolisk", "Basilisk", "Hyena", "Gorilla", "Ape",
    "Silverback", "Scorpid", "Spider", "Widow", "Lurker", "Tarantula", "Recluse", "Crab", "Turtle", "Tortoise", "Snapjaw",
    "Kodo", "Thunder Lizard", "Thunderhead", "Lizard", "Strider", "Plainstrider", "Tallstrider", "Hawk", "Owl", "Vulture",
    "Buzzard", "Carrion Bird", "Bat", "Wind Serpent", "Serpent", "Yeti", "Stag", "Deer", "Ram", "Goat", "Coyote", "Jackal",
    "Hippogryph", "Chimaera", "Devilsaur", "Stegodon", "Pterrordax", "Diemetradon", "Shardtooth", "Frostsaber",
    "Nightsaber", "Mountain Lion", "Felstalker", "Bloodfang", "Mastiff", "Hound", "Gnoll Hound", "Swoop", "Wildkin",
    "Thistlefur Bear", "Ashenvale Bear", "Thrasher", "Ravager", "Ridge", "Ironjaw", "Mosshoof", "Moonkin",
    "Bristleback Boar", "Elk" }

local function anyMatch(s, patterns)
    for _, p in ipairs(patterns) do if s:find(p) then return true end end
    return false
end
local function anyPlain(s, words)
    for _, w in ipairs(words) do if s:find(w, 1, true) then return true end end
    return false
end
local function isBeast(name)
    for _, w in ipairs(BEAST_WORDS) do
        if name:find("%f[%w]" .. w:gsub(" ", "%%s") .. "%f[%W]") then return true end
    end
    return false
end

local function outdoor(map) return (map >= 1411 and map <= 1458) or map >= 2000 end
local function round1(v) return math.floor(v * 10 + 0.5) / 10 end

local function loadTable(src)
    if type(src) == "table" then return src end
    if type(src) ~= "string" then return nil end
    local f = loadstring(src)
    if not f then return nil end
    local ok, t = pcall(f)
    return ok and type(t) == "table" and t or nil
end

local function metadata(addon, key)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    if not get then return nil end
    local ok, v = pcall(get, addon, key)
    return ok and v or nil
end

---------------------------------------------------------------------------
-- Reading QuestieDB
---------------------------------------------------------------------------
local Lib, NpcDB, QuestDB, areaToMap

local function sortedKeys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- An NPC's first spawn on a map: map, x, y.
local function place(spawns)
    if type(spawns) ~= "table" then return nil end
    for _, area in ipairs(sortedKeys(spawns)) do
        local map, list = areaToMap[area], spawns[area]
        if map and map ~= 0 and type(list) == "table" then
            for _, p in ipairs(list) do
                if type(p) == "table" and type(p[1]) == "number" and p[1] >= 0 and type(p[2]) == "number" then
                    return map, round1(p[1]), round1(p[2])
                end
            end
        end
    end
end

local function npcPlace(id)
    if not (id and NpcDB.Exists(id)) then return nil end
    local map, x, y = place(NpcDB.spawns(id))
    if not map then return nil end
    return { npc = id, name = NpcDB.name(id), map = map, x = x, y = y }
end

-- Rank books' vendors and rank quests' givers: names and places (the IDs come from What's Training?).
local function fillRanks()
    for _, list in pairs(ns.Ranks or {}) do
        for _, r in ipairs(list) do
            for _, v in ipairs(r.vendors or {}) do
                local pl = npcPlace(v.npc)
                if pl then v.name, v.map, v.x, v.y = pl.name, pl.map, pl.x, pl.y end
            end
            for _, q in ipairs(r.quests or {}) do
                if q.id and QuestDB.Exists(q.id) then
                    q.name = QuestDB.name(q.id) or q.name
                    if not q.level then
                        local lvl = QuestDB.requiredLevel(q.id)
                        if lvl > 0 then q.level = lvl end
                    end
                    local by = QuestDB.startedBy(q.id)
                    local npc = by and type(by[1]) == "table" and by[1][1]
                    local pl = npcPlace(npc)
                    if pl then q.npc, q.by, q.map, q.x, q.y = npc, pl.name, pl.map, pl.x, pl.y end
                end
            end
        end
    end
end

-- Recipe vendors: QuestieDB's place where it has the NPC.
local function fillVendors()
    for _, list in pairs(ns.RecipeVendors or {}) do
        for _, v in ipairs(list) do
            local pl = npcPlace(v.npc)
            if pl then v.map, v.x, v.y = pl.map, pl.x, pl.y end
        end
    end
end

-- One pass over every NPC: trainers, and each outdoor zone's wild mobs and beasts. Bulk reads use GetRaw (base data,
-- not cached), so this pass does not leave thousands of NPCs in QuestieDB's cache; titles stay English that way too.
local function scan()
    local trainerFlag = (Lib.Enum.npcFlags and Lib.Enum.npcFlags.TRAINER) or 16
    local trainers = {}
    local mobs, beasts = {}, {}
    local raw = NpcDB.GetRaw
    for i, id in ipairs(NpcDB.GetAllIds()) do
        local title = raw(id, "subName")
        local friendly = raw(id, "friendlyToFaction")
        if type(title) == "string" and title ~= "" then
            local flags = raw(id, "npcFlags") or 0
            if math.floor(flags / trainerFlag) % 2 == 1 and not anyPlain(title, NOT_TRAINER) then
                for prof, pats in pairs(TRAINER_TITLE) do
                    if anyMatch(title, pats) then
                        local map, x, y = place(NpcDB.spawns(id))
                        if map then
                            local cap = title:find("^Journeyman") and 150 or title:find("^Expert") and 225 or 300
                            trainers[prof] = trainers[prof] or {}
                            table.insert(trainers[prof], { npc = id, name = NpcDB.name(id), title = title, map = map, x = x, y = y,
                                side = (friendly == "A" or friendly == "H") and friendly or nil, cap = cap })
                        end
                        break
                    end
                end
            end
        elseif not friendly or friendly == "" then
            local rank = raw(id, "rank") or 0
            local lo, hi = raw(id, "minLevel"), raw(id, "maxLevel")
            if (rank == 0 or rank == 1) and type(lo) == "number" and type(hi) == "number" and hi > 0 and hi <= 63 then
                local spawns = raw(id, "spawns")
                if type(spawns) == "table" then
                    local mid = math.floor((lo + hi) / 2)
                    local beast = isBeast(raw(id, "name") or "")
                    for area, coords in pairs(spawns) do
                        local map = areaToMap[area]
                        if map and map ~= 0 and outdoor(map) then
                            local k = math.max(1, type(coords) == "table" and #coords or 0)
                            local m = mobs[map]
                            if not m then m = {}; mobs[map] = m end
                            for _ = 1, k do m[#m + 1] = mid end
                            if beast then
                                local b = beasts[map]
                                if not b then b = {}; beasts[map] = b end
                                b[mid] = (b[mid] or 0) + k
                            end
                        end
                    end
                end
            end
        end
        if i % PER_SLICE == 0 then coroutine.yield() end
    end
    for _, list in pairs(trainers) do
        table.sort(list, function(a, b) if a.map ~= b.map then return a.map < b.map end return a.npc < b.npc end)
    end
    local zones = {}
    for map, levels in pairs(mobs) do
        if #levels >= 20 then
            table.sort(levels)
            local z = { lo = levels[math.floor(#levels * 0.15) + 1], hi = levels[math.floor(#levels * 0.85) + 1] }
            local b = beasts[map]
            if b then
                local bl = {}
                for _, lvl in ipairs(sortedKeys(b)) do bl[#bl + 1] = lvl; bl[#bl + 1] = b[lvl] end
                z.beasts = bl
            end
            zones[map] = z
        end
    end
    return trainers, zones
end

local function apply(trainers, zones)
    for prof, list in pairs(trainers or {}) do ns.Trainers[prof] = list end
    for map, z in pairs(zones or {}) do
        local e = ns.Zones[map]
        if not e then e = {}; ns.Zones[map] = e end
        e.lo, e.hi, e.beasts = z.lo, z.hi, z.beasts
    end
end

local function refresh()
    if P and P.Refresh then pcall(P.Refresh, P) end
end

function Live:Start()
    if self.state ~= "missing" then return end
    if not _G.LibQuestieDB then
        local load = (C_AddOns and C_AddOns.LoadAddOn) or _G.LoadAddOn
        if load then pcall(load, "QuestieDB") end
    end
    Lib = _G.LibQuestieDB
    if type(Lib) ~= "table" or not Lib.RequireContract or not Lib.Npc then return end
    local ok, msg = Lib.RequireContract(CONTRACT)
    if not ok then
        self.state, self.message = "old", msg
        return
    end
    NpcDB, QuestDB = Lib.Npc, Lib.Quest
    local ZoneDB = Lib.Support and Lib.Support.Get and Lib.Support.Get("ZoneDB") or {}
    local zp = ZoneDB.private or {}
    areaToMap = {}
    for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
        for a, m in pairs(loadTable(zp[key]) or {}) do areaToMap[a] = m end
    end

    local okFill, err = pcall(function() fillRanks(); fillVendors() end)
    if not okFill then self.fillError = err end

    -- Trainers and zones: from the saved copy while QuestieDB is the same version, else worked out again.
    local version = tostring(metadata("QuestieDB", "Version") or "?") .. "/" .. FORMAT
    local db = P and P.DB and P:DB() or {}
    local saved = type(db.questie) == "table" and db.questie
    if saved and saved.version == version and type(saved.trainers) == "table" and type(saved.zones) == "table" then
        apply(saved.trainers, saved.zones)
        self.state = "ready"
        refresh()
        return
    end
    self.state = "loading"
    local co = coroutine.create(scan)
    local function step()
        local okStep, trainers, zones = coroutine.resume(co)
        if not okStep then
            self.state, self.message = "failed", tostring(trainers)
            return
        end
        if coroutine.status(co) == "dead" then
            apply(trainers, zones)
            db.questie = { version = version, trainers = trainers, zones = zones }
            self.state = "ready"
            refresh()
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0, step)
        else
            step()
        end
    end
    step()
end

if CreateFrame then
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(START_DELAY, function() Live:Start() end)
        else
            Live:Start()
        end
    end)
end
