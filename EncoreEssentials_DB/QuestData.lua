-- Encore-DB quest data layer. The window asks this layer for quests and never reads a data file itself, so the
-- data can be rebuilt from another database without touching the window (see tools/quests/README.md).
--
-- A quest source is a table in the source-neutral format that tools/quests/build-quests.mjs writes:
--   { id, name, url, credit, version, priority,
--     instances = { [instance key] = { quest IDs } },
--     quests = { [quest ID] = { title, level, minLevel, side, objective, text, start, finish, prev, next,
--                               xp, money, rewards, choice, rewardItems, rep, new } },
--     items = { [item ID] = { name, quality } } }
-- Sources come from Data\*.lua (ns.QuestSources) and from any other addon that fills the global
-- EncoreEssentials_QuestSources before Encore-DB loads (a separate data addon can update quests on its own).
-- When two sources know the same quest, the one with the higher priority wins field by field.
-- rewards/choice are the reward items split into given and pick-one; rewardItems (QuestieDB) is the same items
-- unsplit, for quests no source has split yet. Above every source sit the rewards your own game showed you
-- (EncoreEssentials/QuestRewards.lua, saved per account): exact XP, money and items.
local _, ns = ...
local DB = ns.DB

local Quests = { sources = {}, merged = nil, cache = {} }
DB.Quests = Quests

local LIST_FIELDS = { prev = true, next = true }

function Quests:AddSource(src)
    if type(src) ~= "table" or type(src.quests) ~= "table" then return false end
    for _, s in ipairs(self.sources) do
        if s == src then return true end
    end
    src.priority = src.priority or 0
    self.sources[#self.sources + 1] = src
    table.sort(self.sources, function(a, b) return a.priority > b.priority end)
    self.merged, self.cache = nil, {}
    return true
end

-- Every source's credit line, for the window's credits.
function Quests:Credits()
    local out = {}
    for _, s in ipairs(self.sources) do
        if s.credit then out[#out + 1] = s.credit end
    end
    return out
end

local function merge(self)
    if self.merged then return self.merged end
    local quests, instances, items = {}, {}, {}
    -- Lowest priority first, so higher ones overwrite field by field. prev/next lists are joined.
    for i = #self.sources, 1, -1 do
        local s = self.sources[i]
        for id, q in pairs(s.quests or {}) do
            local m = quests[id]
            if not m then
                m = { id = id }
                quests[id] = m
            end
            for k, v in pairs(q) do
                if LIST_FIELDS[k] and m[k] then
                    local seen, joined = {}, {}
                    for _, x in ipairs(m[k]) do seen[x] = true; joined[#joined + 1] = x end
                    for _, x in ipairs(v) do if not seen[x] then joined[#joined + 1] = x end end
                    m[k] = joined
                else
                    m[k] = v
                end
            end
        end
        for key, list in pairs(s.instances or {}) do
            local m = instances[key] or {}
            instances[key] = m
            for _, id in ipairs(list) do
                if not m[id] then
                    m[id] = true
                    m[#m + 1] = id
                end
            end
        end
        for id, it in pairs(s.items or {}) do items[id] = it end
    end
    -- [quest] = the instance keys that list it
    local where = {}
    for key, list in pairs(instances) do
        for _, id in ipairs(list) do
            where[id] = where[id] or {}
            table.insert(where[id], key)
        end
    end
    self.merged = { quests = quests, instances = instances, items = items, where = where }
    self.gameDone = nil
    return self.merged
end

-- What the game showed for this quest (quest giver or quest log), laid over the sources' data. XP seen more than
-- five levels above the quest is less than full, so it only counts when no source has XP.
local seenVersion
local function overlayGame(self)
    local QR = _G.EncoreEssentials and _G.EncoreEssentials.QuestRewards
    if not QR then return end
    if seenVersion == QR.version and self.gameDone then return end
    seenVersion, self.gameDone = QR.version, true
    local quests = self.merged.quests
    for id, g in pairs(QR:All()) do
        local q = quests[id]
        if q and type(g) == "table" then
            q.base = q.base or { xp = q.xp, money = q.money, rewards = q.rewards, choice = q.choice }
            local b = q.base
            local full = g.xp and (not q.level or not g.lvl or g.lvl <= q.level + 5)
            q.xp = (full and g.xp) or b.xp or g.xp
            q.money = g.money or b.money
            if g.rewards or g.choice then
                q.rewards, q.choice, q.seen = g.rewards, g.choice, true
            else
                -- The game showed no reward items, which is exact: the unsplit rewardItems list is not shown.
                q.rewards, q.choice, q.seen = nil, nil, true
            end
        end
    end
end

function Quests:Get(id)
    local data = merge(self)
    overlayGame(self)
    return data.quests[id]
end

-- The instance keys whose quest lists hold this quest (nil when none).
function Quests:Instances(id)
    return merge(self).where[id]
end

function Quests:ItemFallback(id)
    return merge(self).items[id]
end

-- The game's name for a quest the data has no title for; asks the server once when it does not know it yet.
local asked = {}
function Quests:Title(id)
    local q = self:Get(id)
    if q and q.title then return q.title end
    local title
    if C_QuestLog then
        if C_QuestLog.GetTitleForQuestID then title = C_QuestLog.GetTitleForQuestID(id) end
        if not title and C_QuestLog.GetQuestInfo then title = C_QuestLog.GetQuestInfo(id) end
        if not title and not asked[id] and C_QuestLog.RequestLoadQuestByID then
            asked[id] = true
            pcall(C_QuestLog.RequestLoadQuestByID, id)
        end
    end
    return title
end

-- Wing instances (Data\Wings.lua: "dire-maul/east") show the quests of the whole instance.
local function instanceKey(inst)
    if inst.parent then return inst.parent end
    if inst.key then return (inst.key:gsub("/.*", "")) end
    return (inst.name or ""):lower():gsub("['\226\128\153]", ""):gsub("[^a-z0-9]+", "-"):gsub("^-", ""):gsub("-$", "")
end

-- Orders a chain so every quest comes after the quests before it (ties: lower level, then lower ID).
local function orderChain(set, quests)
    local indeg, ids = {}, {}
    for id in pairs(set) do
        ids[#ids + 1] = id
        indeg[id] = 0
    end
    for _, id in ipairs(ids) do
        for _, n in ipairs((quests[id] and quests[id].next) or {}) do
            if set[n] then indeg[n] = indeg[n] + 1 end
        end
    end
    local function before(a, b)
        local la, lb = (quests[a] and quests[a].level) or 0, (quests[b] and quests[b].level) or 0
        if la ~= lb then return la < lb end
        return a < b
    end
    local out, ready, done = {}, {}, {}
    for _, id in ipairs(ids) do if indeg[id] == 0 then ready[#ready + 1] = id end end
    while #out < #ids do
        if #ready == 0 then
            -- A loop in the links: carry on from the lowest quest not placed yet.
            for _, id in ipairs(ids) do if not done[id] then ready[1] = id; break end end
        end
        table.sort(ready, before)
        local id = table.remove(ready, 1)
        if not done[id] then
            done[id] = true
            out[#out + 1] = id
            for _, n in ipairs((quests[id] and quests[id].next) or {}) do
                if set[n] and not done[n] then
                    indeg[n] = indeg[n] - 1
                    if indeg[n] <= 0 then ready[#ready + 1] = n end
                end
            end
        end
    end
    return out
end

local MAX_HOPS = 6 -- how far a chain is followed out of the dungeon in each direction

-- An instance's quests, grouped into chains:
--   { count, chains, inside = { [id] = true }, groups = { { steps = { quest IDs in order } }, ... } }
-- A group with one step is a single quest.
function Quests:ForInstance(inst)
    if not inst then return nil end
    local key = instanceKey(inst)
    if self.cache[key] then return self.cache[key] end
    local data = merge(self)
    local list = data.instances[key]
    local result = { count = 0, chains = 0, inside = {}, groups = {} }
    self.cache[key] = result
    if not list then return result end
    local quests = data.quests
    for _, id in ipairs(list) do
        result.inside[id] = true
        result.count = result.count + 1
    end
    local placed = {}
    for _, start in ipairs(list) do
        if not placed[start] then
            -- Follow prev and next links from this quest, up to MAX_HOPS steps out of the dungeon.
            local set, todo = {}, { { start, 0 } }
            while #todo > 0 do
                local id, hops = unpack(table.remove(todo))
                if not set[id] then
                    set[id] = true
                    local q = quests[id]
                    local nextHops = result.inside[id] and 0 or hops + 1
                    if q and nextHops <= MAX_HOPS then
                        for _, n in ipairs(q.prev or {}) do if quests[n] or result.inside[n] then todo[#todo + 1] = { n, nextHops } end end
                        for _, n in ipairs(q.next or {}) do if quests[n] or result.inside[n] then todo[#todo + 1] = { n, nextHops } end end
                    end
                end
            end
            for id in pairs(set) do placed[id] = true end
            local steps = orderChain(set, quests)
            result.groups[#result.groups + 1] = { steps = steps }
            if #steps > 1 then result.chains = result.chains + 1 end
        end
    end
    -- Chains first, then single quests; each by the lowest level of its quests in the dungeon.
    local function groupLevel(g)
        local lv
        for _, id in ipairs(g.steps) do
            local l = result.inside[id] and quests[id] and quests[id].level
            if l and (not lv or l < lv) then lv = l end
        end
        return lv or 999
    end
    table.sort(result.groups, function(a, b)
        local ca, cb = #a.steps > 1, #b.steps > 1
        if ca ~= cb then return ca end
        local la, lb = groupLevel(a), groupLevel(b)
        if la ~= lb then return la < lb end
        return a.steps[1] < b.steps[1]
    end)
    return result
end

for _, src in ipairs(ns.QuestSources or {}) do Quests:AddSource(src) end
for _, src in ipairs(_G.EncoreEssentials_QuestSources or {}) do Quests:AddSource(src) end
