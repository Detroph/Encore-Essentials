-- Encore-Professions: the levelling route of a crafting profession. Recipes come only from trainers and from
-- vendors that sell them for gold (no drops, quests, reputation or Merchant's Favor), as What's Training? lists
-- them. For every skill point the planner takes the recipe with the lowest expected cost: reagents divided by the
-- skill-up chance, plus a third of the price of learning it. Fewest crafts takes the highest chance first.
-- Skill-up chance: orange 100%; yellow and green (grey - skill) / (grey - yellow), plus Working Overtime.
local _, ns = ...
local P = ns.P

local UNKNOWN = 5000 -- copper planned for one reagent with no price at all (no vendor, no scan): keeps it last

local function chance(r, s, bonus)
    local yellow, grey = r[4], r[6]
    if s < yellow then return 1 end
    if s >= grey then return 0 end
    return math.min(1, (grey - s) / math.max(1, grey - yellow) + bonus)
end
P.Chance = chance

local function colour(r, s)
    if s < r[4] then return "o" end
    if s < r[5] then return "y" end
    if s < r[6] then return "g" end
    return "x"
end
P.Colour = colour

-- The price used for planning: the reagent's own price, or what making it costs when it is made by this
-- profession (a bolt of cloth, a leather) and nobody sells it.
local function priceFor(item, madeBy, cache, depth)
    if cache[item] ~= nil then return cache[item] or nil, cache[item .. "s"] end
    local p, source = P.Price(item)
    if not p and madeBy[item] and (depth or 0) < 2 then
        local r = madeBy[item]
        local total = 0
        for i = 1, #r[9], 2 do
            local q = priceFor(r[9][i], madeBy, cache, (depth or 0) + 1)
            if not q then total = nil break end
            total = total + q * r[9][i + 1]
        end
        if total then p, source = total / math.max(1, r[8] or 1), "craft" end
    end
    cache[item] = p or false
    cache[item .. "s"] = source
    return p, source
end

local function reagentCost(r, madeBy, cache)
    local total, unknown = 0, false
    for i = 1, #r[9], 2 do
        local p = priceFor(r[9][i], madeBy, cache)
        if not p then p, unknown = UNKNOWN, true end
        total = total + p * r[9][i + 1]
    end
    return total, unknown
end

-- Plan from `start` to the last rank's cap. o = { mode = "cheap"|"fast", bonus, cap (current), known(spell) }.
function P.Plan(prof, start, o)
    local recipes = ns.Recipes[prof] or {}
    local ranks = ns.Ranks[prof] or {}
    local bonus, mode = o.bonus or 0, o.mode or "cheap"
    local known = o.known or P.Knows
    local cap = o.cap or 75
    local top = 75
    for _, r in ipairs(ranks) do top = math.max(top, r.cap) end

    local madeBy, cache = {}, {}
    for _, r in ipairs(recipes) do if r[7] and not madeBy[r[7]] then madeBy[r[7]] = r end end
    local cost, unknown, learnCost, isKnown = {}, {}, {}, {}
    for _, r in ipairs(recipes) do
        cost[r], unknown[r] = reagentCost(r, madeBy, cache)
        isKnown[r] = r[10] == "a" or known(r[1])
        learnCost[r] = isKnown[r] and 0 or (r[11] or 0)
    end

    local steps, s, nextRank = {}, start, 1
    local planned = {}
    while nextRank <= #ranks and ranks[nextRank].cap <= cap do nextRank = nextRank + 1 end
    while s < top do
        -- Train the next rank once the skill allows it, or when the cap stops the route.
        local rank = ranks[nextRank]
        if rank and (s >= rank.skill and rank.cap > cap) then
            steps[#steps + 1] = { kind = "rank", at = s, rank = rank, name = rank.name, cost = rank.cost or 0 }
            cap = rank.cap
            nextRank = nextRank + 1
        end
        if s >= cap then break end
        local best, bestKey, bestKey2, bestChance
        for _, r in ipairs(recipes) do
            if r[3] <= s then
                local c = chance(r, s, bonus)
                if c > 0 then
                    local learn = (isKnown[r] or planned[r]) and 0 or learnCost[r] / 3
                    local exp = cost[r] / c + learn
                    local key, key2 = exp, 0
                    if mode == "fast" then key, key2 = 1 / c, exp end
                    if not best or key < bestKey or (key == bestKey and key2 < bestKey2) then
                        best, bestKey, bestKey2, bestChance = r, key, key2, c
                    end
                end
            end
        end
        if not best then
            steps[#steps + 1] = { kind = "gap", from = s, to = cap }
            break
        end
        local last = steps[#steps]
        if not (last and last.kind == "craft" and last.spell == best[1]) then
            last = { kind = "craft", spell = best[1], name = best[2], from = s, to = s, expect = 0, mat = cost[best],
                unknown = unknown[best] or nil, reag = best[9], makes = best[7], how = best[10],
                learn = planned[best] and 0 or learnCost[best], learnAt = s, colours = {} }
            steps[#steps + 1] = last
            planned[best] = true
        end
        last.expect = last.expect + 1 / bestChance
        last.to = s + 1
        local col = colour(best, s)
        last.colours[col] = (last.colours[col] or 0) + 1
        s = s + 1
    end

    local total, crafts, prices = 0, 0, {}
    for _, st in ipairs(steps) do
        if st.kind == "craft" then
            st.crafts = math.max(1, math.ceil(st.expect - 0.05))
            st.total = st.crafts * st.mat
            local most, n = "o", -1
            for c, k in pairs(st.colours) do if k > n then most, n = c, k end end
            st.colour, st.colours, st.expect = most, nil, nil
            total = total + st.total + (st.learn or 0)
            crafts = crafts + st.crafts
            for i = 1, #st.reag, 2 do
                local p = cache[st.reag[i]]
                if p then prices[st.reag[i]] = math.floor(p + 0.5) end
            end
        elseif st.kind == "rank" then
            total = total + (st.cost or 0)
        end
    end
    return { made = time(), prof = prof, mode = mode, bonus = bonus, start = start, top = top, steps = steps,
        total = total, crafts = crafts, prices = prices }
end

-- Where the player is on a route: the index of the first step not done yet.
function P.Progress(route, skill, cap)
    for i, st in ipairs(route.steps) do
        if st.kind == "craft" and skill < st.to then return i end
        if st.kind == "rank" and (cap or 0) < st.rank.cap then return i end
        if st.kind == "gap" then return i end
    end
    return #route.steps + 1
end

-- Crafts still to do in a step at this skill.
function P.CraftsLeft(st, skill)
    if skill <= st.from then return st.crafts end
    if skill >= st.to then return 0 end
    return math.max(1, math.ceil(st.crafts * (st.to - skill) / math.max(1, st.to - st.from)))
end

-- How much the remaining reagents' prices moved since the route was made (0.2 = 20% dearer).
function P.Drift(route, from)
    local thenSum, nowSum = 0, 0
    for i = from or 1, #route.steps do
        local st = route.steps[i]
        if st.kind == "craft" then
            for k = 1, #st.reag, 2 do
                local item, n = st.reag[k], st.reag[k + 1] * st.crafts
                local was = route.prices[item]
                local now = was and P.Price(item)
                if was and now then thenSum, nowSum = thenSum + was * n, nowSum + now * n end
            end
        end
    end
    if thenSum <= 0 then return 0 end
    return nowSum / thenSum - 1
end

-- Why a route should be planned again, or nil.
function P.Stale(route, from)
    if not route then return nil end
    local days = (time() - (route.made or 0)) / 86400
    if days > P.ROUTE_OLD_DAYS then return ("Route is %d days old."):format(math.floor(days)) end
    local d = P.Drift(route, from)
    if math.abs(d) > P.PRICE_DRIFT then
        return ("Reagent prices moved %d%% since this route was made."):format(math.floor(math.abs(d) * 100 + 0.5))
    end
end
