-- Encore-Professions: the Auctionator shopping list "Encore: <profession>". It holds the auction reagents still
-- missing for the next 3 steps of the route (what the bags and bank don't have), and is written again when a step
-- is done, when the bags change and when the route is recalculated. Vendor reagents stay off it.
-- Uses Auctionator's public API the way SkillUp Forever does (cjber, GPL-3.0-or-later).
local _, ns = ...
local P = ns.P

local CALLER = "Encore-Professions"
local STEPS = 3

local function api()
    local a = Auctionator and Auctionator.API and Auctionator.API.v1
    return a and a.CreateShoppingList and a.ConvertToSearchString and a or nil
end
P.HasShoppingAPI = function() return api() ~= nil end

function P.ListName(prof) return "Encore: " .. prof end

-- { { item, count }, ... } for the next STEPS craft steps from index `from`.
function P.Missing(route, from, skill)
    local need, order, n = {}, {}, 0
    for i = from, #route.steps do
        local st = route.steps[i]
        if st.kind == "craft" then
            n = n + 1
            local left = P.CraftsLeft(st, skill)
            for k = 1, #st.reag, 2 do
                local item = st.reag[k]
                if not need[item] then order[#order + 1] = item end
                need[item] = (need[item] or 0) + st.reag[k + 1] * left
            end
            if n >= STEPS then break end
        elseif st.kind == "gap" then
            break
        end
    end
    local list = {}
    for _, item in ipairs(order) do
        local _, source = P.Price(item)
        local count = need[item] - P.Have(item)
        if source ~= "vendor" and count > 0 then list[#list + 1] = { item = item, count = count } end
    end
    return list
end

local pendingNames = 0
function P:UpdateShopping(prof, route, from, skill)
    local a = api()
    if not (a and route and self:DB().shopping) then return end
    local list = P.Missing(route, from, skill)
    local searches, sig = {}, {}
    for _, e in ipairs(list) do
        local name = C_Item.GetItemNameByID(e.item)
        if not name then
            if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(e.item) end
            if pendingNames < 5 then
                pendingNames = pendingNames + 1
                C_Timer.After(1, function() pendingNames = pendingNames - 1; P:UpdateShopping(prof, route, from, skill) end)
            end
            return
        end
        local ok, s = pcall(a.ConvertToSearchString, CALLER, { searchString = name, isExact = true, quantity = e.count })
        if ok and s then searches[#searches + 1] = s; sig[#sig + 1] = e.item .. "x" .. e.count end
    end
    local name = P.ListName(prof)
    local key = table.concat(sig, ",")
    local lists = self:DB().lists
    if lists[name] == key then return end
    -- An empty list is only written over a list Encore made before, never created.
    if #searches == 0 and lists[name] == nil then return end
    local ok, err = pcall(a.CreateShoppingList, CALLER, name, searches)
    if ok then
        lists[name] = key
        self.shoppingCount = #searches
    else
        geterrorhandler()(err)
    end
end
