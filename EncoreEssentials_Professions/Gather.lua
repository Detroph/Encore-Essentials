-- Encore-Professions: where to farm. Mining and Herbalism rank zones by their nodes that still give skill-ups
-- (node places and skill levels from GatherLite by Wuild, MIT), Skinning by the beasts you can skin there and
-- their levels (QuestieDB), Fishing by the zone's level and what is caught there (GatherLite's catch reports).
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
    for _, n in ipairs(nodes) do
        local c = gatherChance(n.levels, s)
        if c > 0 then
            useful[#useful + 1] = { node = n, chance = c, colour = colourOf(n.levels, s) }
            for i = 1, #n.zones, 2 do
                local map, count = n.zones[i], n.zones[i + 1]
                scores[map] = (scores[map] or 0) + count * c
                extra[map] = extra[map] or { nodes = 0, names = {} }
                extra[map].nodes = extra[map].nodes + count
                extra[map].names[#extra[map].names + 1] = n.name
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
    for map, z in pairs(ns.Zones or {}) do
        local b = z.beasts
        if b then
            for i = 1, #b, 2 do
                local level, spawns = b[i], b[i + 1]
                local req = skinSkill(level)
                if req <= maxReq then
                    local c = gatherChance({ req, req + 25, req + 50, req + 100 }, s)
                    if c > 0 then
                        scores[map] = (scores[map] or 0) + spawns * c
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

-- Fishing: zones whose wild mobs are about a fifth of your skill in level, where fish are caught.
local function fishPicks(s)
    local scores, extra = {}, {}
    local want = s / 5
    for map, z in pairs(ns.Zones or {}) do
        if z.fish and z.lo then
            local mid = (z.lo + z.hi) / 2
            if mid <= math.max(want, 8) + 5 then
                scores[map] = 100 - math.abs(mid - want) + #z.fish / 10
                extra[map] = { lo = z.lo, hi = z.hi, fish = z.fish }
            end
        end
    end
    return { picks = top3(scores, extra) }
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
