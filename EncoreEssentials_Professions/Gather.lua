-- Encore-Professions: where to farm. Mining and Herbalism rank zones by their nodes that still give skill-ups
-- (node places and skill levels from GatherLite by Wuild, MIT), Skinning by the beasts you can skin there and
-- their levels (read from the QuestieDB addon), Fishing by the zone's level and what is caught there (GatherLite's catch reports).
-- Show nodes turns on GatherLite's minimap and world map markers for that kind of node.
local _, ns = ...
local P = ns.P

-- Gathering chance for a node or beast with levels { orange, yellow, green, grey }.
local function gatherChance(levels, s)
    if #levels < 4 or s < levels[1] then return 0 end
    if s < levels[2] then return 1 end
    if s >= levels[4] then return 0 end
    return (levels[4] - s) / math.max(1, levels[4] - levels[2])
end

local function colourOf(levels, s)
    if s < levels[2] then return "o" end
    if s < levels[3] then return "y" end
    if s < levels[4] then return "g" end
    return "x"
end
P.NodeColour = colourOf

-- Skinning: the skill a beast of this level needs.
local function skinSkill(level)
    if level <= 10 then return 1 end
    if level <= 20 then return (level - 10) * 10 end
    return level * 5
end
P.SkinSkill = skinSkill

-- Zones by side (Classic territories, uiMap IDs). Zones not listed are contested and open to both sides.
-- Enemy territory is never suggested; your own side's zones get a small bonus because nobody attacks you there.
local SIDE = {
    [1411] = "H", [1412] = "H", [1413] = "H", [1420] = "H", [1421] = "H", [1454] = "H", [1456] = "H", [1458] = "H",
    [1426] = "A", [1429] = "A", [1432] = "A", [1436] = "A", [1438] = "A", [1439] = "A", [1453] = "A", [1455] = "A", [1457] = "A",
}
local STARTING = { H = { 1411, 1412, 1420 }, A = { 1429, 1426, 1438 } } -- Durotar, Mulgore, Tirisfal / Elwynn, Dun Morogh, Teldrassil
local CITIES = { H = { 1454, 1456, 1458 }, A = { 1453, 1455, 1457 } } -- Orgrimmar, Thunder Bluff, Undercity / Stormwind, Ironforge, Darnassus
local OWN_BONUS = 1.25

local function sideOf(map) return SIDE[map] end
P.ZoneSide = sideOf

-- false for the other side's territory; true for your own and contested zones.
local function allowed(map, side)
    local z = SIDE[map]
    return not (side and z and z ~= side)
end

local function top3(scores, extra)
    local list = {}
    for map, score in pairs(scores) do
        if score > 0 then list[#list + 1] = { map = map, score = score, info = extra[map] } end
    end
    table.sort(list, function(a, b) return a.score > b.score end)
    for i = #list, 4, -1 do list[i] = nil end
    return list
end

-- Mining or Herbalism at skill s: { nodes (giving skill-ups, best first), picks (3 zones), next (node to unlock) }.
local function nodePicks(prof, s)
    local nodes = ns.Nodes[prof] or {}
    local useful, scores, extra, nextNode = {}, {}, {}, nil
    local side = P.MySide()
    for _, n in ipairs(nodes) do
        local c = gatherChance(n.levels, s)
        if c > 0 then
            useful[#useful + 1] = { node = n, chance = c, colour = colourOf(n.levels, s) }
            for i = 1, #n.zones, 2 do
                local map, count = n.zones[i], n.zones[i + 1]
                if allowed(map, side) then
                    scores[map] = (scores[map] or 0) + count * c * (SIDE[map] == side and OWN_BONUS or 1)
                    extra[map] = extra[map] or { nodes = 0, names = {} }
                    extra[map].nodes = extra[map].nodes + count
                    extra[map].names[#extra[map].names + 1] = n.name
                end
            end
        elseif #n.levels >= 4 and n.levels[1] > s and (not nextNode or n.levels[1] < nextNode.levels[1]) then
            nextNode = n
        end
    end
    table.sort(useful, function(a, b) return a.chance > b.chance end)
    return { nodes = useful, picks = top3(scores, extra), nextNode = nextNode }
end

local function skinPicks(s)
    local scores, extra = {}, {}
    local maxReq = s
    local side = P.MySide()
    for map, z in pairs(ns.Zones or {}) do
        local b = allowed(map, side) and z.beasts
        if b then
            for i = 1, #b, 2 do
                local level, spawns = b[i], b[i + 1]
                local req = skinSkill(level)
                if req <= maxReq then
                    local c = gatherChance({ req, req + 25, req + 50, req + 100 }, s)
                    if c > 0 then
                        scores[map] = (scores[map] or 0) + spawns * c * (SIDE[map] == side and OWN_BONUS or 1)
                        local e = extra[map] or { lo = level, hi = level, spawns = 0 }
                        e.lo, e.hi, e.spawns = math.min(e.lo, level), math.max(e.hi, level), e.spawns + spawns
                        extra[map] = e
                    end
                end
            end
        end
    end
    local maxLevel = s < 100 and math.floor(10 + s / 10) or math.floor(s / 5)
    return { picks = top3(scores, extra), maxLevel = maxLevel }
end

-- Fishing: zones whose wild mobs are about a fifth of your skill in level, where fish are caught. Your side's
-- starting zones count as one place ("Starting zones"), and so do your side's capital cities ("Cities", fished
-- like a starting zone). The other side's zones are left out; your own side's get a bonus at the same level.
local CITY_LO, CITY_HI = 1, 10

local function mergeInto(groups, key, map, z, lo, hi)
    local g = groups[key]
    if not g then
        g = { lo = lo, hi = hi, fish = {}, seen = {}, maps = {} }
        groups[key] = g
    end
    g.lo, g.hi = math.min(g.lo, lo), math.max(g.hi, hi)
    g.maps[#g.maps + 1] = map
    for _, id in ipairs(z.fish) do
        if not g.seen[id] then g.seen[id] = true; g.fish[#g.fish + 1] = id end
    end
end

local function fishPicks(s)
    local side = P.MySide()
    local want = s / 5
    local inGroup = {}
    for key, list in pairs({ start = STARTING[side] or {}, city = CITIES[side] or {} }) do
        for _, map in ipairs(list) do inGroup[map] = key end
    end
    local function score(lo, hi, nFish, own)
        local mid = (lo + hi) / 2
        if mid > math.max(want, 8) + 5 then return nil end
        return 100 - math.abs(mid - want) + nFish / 10 + (own and 10 or 0)
    end
    local scores, extra, groups = {}, {}, {}
    for map, z in pairs(ns.Zones or {}) do
        if z.fish and allowed(map, side) then
            local key = inGroup[map]
            if key == "city" then
                mergeInto(groups, "city", map, z, CITY_LO, CITY_HI)
            elseif key == "start" and z.lo then
                mergeInto(groups, "start", map, z, z.lo, z.hi)
            elseif z.lo then
                local sc = score(z.lo, z.hi, #z.fish, SIDE[map] == side)
                if sc then
                    scores[map] = sc
                    extra[map] = { lo = z.lo, hi = z.hi, fish = z.fish }
                end
            end
        end
    end
    for key, g in pairs(groups) do
        local sc = score(g.lo, g.hi, #g.fish, true)
        if sc then
            local has, maps = {}, {}
            for _, m in ipairs(g.maps) do has[m] = true end
            for _, m in ipairs((key == "start" and STARTING or CITIES)[side]) do
                if has[m] then maps[#maps + 1] = m end -- in the fixed order: Durotar or Elwynn first
            end
            scores[key] = sc - (key == "city" and 0.5 or 0) -- a starting zone first when both fit
            extra[key] = { lo = g.lo, hi = g.hi, fish = g.fish, maps = maps, city = key == "city",
                name = key == "start" and "Starting zones" or "Cities", first = maps[1] }
        end
    end
    local picks = top3(scores, extra)
    for _, pk in ipairs(picks) do
        if type(pk.map) == "string" then pk.name, pk.maps, pk.map = pk.info.name, pk.info.maps, pk.info.first end
    end
    return { picks = picks }
end

function P.FarmPicks(prof, s)
    if prof == "Mining" or prof == "Herbalism" then return nodePicks(prof, s) end
    if prof == "Skinning" then return skinPicks(s) end
    if prof == "Fishing" then return fishPicks(s) end
end

-- The next rank to train or learn for a profession at this cap, or nil.
function P.NextRank(prof, cap)
    for _, r in ipairs(ns.Ranks[prof] or {}) do
        if r.cap > (cap or 0) then return r end
    end
end

---------------------------------------------------------------------------
-- GatherLite
---------------------------------------------------------------------------
function P.HasGatherLite()
    return GatherLite and type(GatherLite.SetNodeTracking) == "function"
end

function P.ShowNodes(kind)
    if not P.HasGatherLite() then return false end
    for _, target in ipairs({ "minimap", "worldmap" }) do
        local ok, err = pcall(GatherLite.SetNodeTracking, GatherLite, target, kind, true)
        if not ok then geterrorhandler()(err) return false end
    end
    P.Print("GatherLite now shows %s nodes on the minimap and world map.", kind)
    return true
end

---------------------------------------------------------------------------
-- Encore-QoL Fishing
---------------------------------------------------------------------------
function P.HasQoL() return _G.EncoreQoL and type(_G.EncoreQoL.ShowPage) == "function" end

function P.OpenQoLFishing()
    local q = _G.EncoreQoL
    if not (q and q.ShowPage) then return false end
    q:ShowPage("professions", "Fishing")
    return true
end
