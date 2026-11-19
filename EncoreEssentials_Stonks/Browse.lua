-- Encore-Stonks: what the item list can be narrowed to.
--  * Auction house categories: the game's own AuctionCategories table when the auction house UI has loaded (the
--    same categories, order and filters as WoW Forever's auction house), otherwise built from item classes in
--    the same order as the auction house.
--  * Auctionator shopping lists ("watchlists"), read through Auctionator's public API.
local _, ns = ...
local Browse = {}
ns.Browse = Browse

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
local GetItemClassInfo = (C_Item and C_Item.GetItemClassInfo) or _G.GetItemClassInfo
local GetItemSubClassInfo = (C_Item and C_Item.GetItemSubClassInfo) or _G.GetItemSubClassInfo
local GetInventoryType = C_Item and C_Item.GetItemInventoryTypeByID

local CALLER = "Encore-Stonks"

-- Same order as the auction house: Weapons, Armor, Containers, Consumables, Trade Goods, Ammo, Quivers, Recipes,
-- Reagents, Quest Items, Miscellaneous, then anything else.
local CLASS_ORDER = { 2, 4, 1, 0, 7, 6, 11, 9, 5, 12, 15, 13, 3, 8, 16, 17, 18, 19 }

-- classID, subClassID, inventoryType of an item ID (all instant, no server round trip).
local info = {}
function Browse.ItemClass(id)
    if not id then return nil end
    local c = info[id]
    if c == nil then
        local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(id)
        local inv = GetInventoryType and GetInventoryType(id) or nil
        c = classID and { classID, subClassID, inv } or false
        info[id] = c
    end
    return c or nil
end

local function filterMatches(filters, c)
    if not filters then return false end
    for _, f in ipairs(filters) do
        if f.classID == c[1]
            and (f.subClassID == nil or f.subClassID == c[2])
            and (f.inventoryType == nil or f.inventoryType == c[3]) then
            return true
        end
    end
    return false
end

-- From the game's AuctionCategories (Blizzard_AuctionUI / Blizzard_AuctionHouseUI).
local function fromGame(categories)
    local function convert(cat)
        if cat.implicitFilter or cat.flags and cat.flags.WOW_TOKEN_FLAG then return nil end
        local node = { name = cat.name, filters = cat.filters, children = {} }
        for _, sub in ipairs(cat.subCategories or {}) do
            local child = convert(sub)
            if child then node.children[#node.children + 1] = child end
        end
        node.match = function(c) return filterMatches(node.filters, c) end
        return node
    end
    local tree = {}
    for _, cat in ipairs(categories) do
        local node = cat.name and convert(cat)
        if node then tree[#tree + 1] = node end
    end
    return tree
end

-- From item classes seen in the data, when the auction house hasn't been opened this session.
local function fromClasses(keys, idOf)
    local present = {}
    for _, key in ipairs(keys) do
        local c = Browse.ItemClass(idOf(key))
        if c then
            present[c[1]] = present[c[1]] or {}
            present[c[1]][c[2] or -1] = true
        end
    end
    local order, seen = {}, {}
    for _, id in ipairs(CLASS_ORDER) do order[#order + 1] = id; seen[id] = true end
    for id in pairs(present) do if not seen[id] then order[#order + 1] = id end end
    local tree = {}
    for _, classID in ipairs(order) do
        local subs = present[classID]
        local name = subs and GetItemClassInfo and GetItemClassInfo(classID)
        if name then
            local node = { name = name, children = {}, match = function(c) return c[1] == classID end }
            local subIDs = {}
            for sub in pairs(subs) do if sub >= 0 then subIDs[#subIDs + 1] = sub end end
            table.sort(subIDs)
            for _, sub in ipairs(subIDs) do
                local subName = GetItemSubClassInfo and GetItemSubClassInfo(classID, sub)
                if subName and subName ~= name then
                    node.children[#node.children + 1] = {
                        name = subName, children = {},
                        match = function(c) return c[1] == classID and c[2] == sub end,
                    }
                end
            end
            tree[#tree + 1] = node
        end
    end
    return tree
end

function Browse.Categories(keys, idOf)
    local game = _G.AuctionCategories
    if type(game) == "table" and #game > 0 then return fromGame(game) end
    return fromClasses(keys, idOf)
end

---------------------------------------------------------------------------
-- Auctionator shopping lists
---------------------------------------------------------------------------
function Browse.ShoppingLists()
    local names = {}
    local lists = _G.AUCTIONATOR_SHOPPING_LISTS
    if type(lists) == "table" then
        for _, l in ipairs(lists) do
            if type(l) == "table" and type(l.name) == "string" and not l.isTemporary then names[#names + 1] = l.name end
        end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

-- A matcher for item names in a shopping list: exact terms ("Iron Ore" in quotes) match the whole name,
-- others match any name that contains them, like Auctionator's own search.
function Browse.ShoppingListMatcher(listName)
    local api = _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
    if not (api and api.GetShoppingListItems and api.ConvertFromSearchString) then return nil end
    local ok, items = pcall(api.GetShoppingListItems, CALLER, listName)
    if not ok or type(items) ~= "table" then return nil end
    local exact, partial = {}, {}
    for _, s in ipairs(items) do
        local okTerm, term = pcall(api.ConvertFromSearchString, CALLER, s)
        if okTerm and type(term) == "table" and type(term.searchString) == "string" and term.searchString ~= "" then
            local t = term.searchString:lower()
            if term.isExact then exact[t] = true else partial[#partial + 1] = t end
        end
    end
    return function(name)
        if not name then return false end
        name = name:lower()
        if exact[name] then return true end
        for _, t in ipairs(partial) do
            if name:find(t, 1, true) then return true end
        end
        return false
    end
end
