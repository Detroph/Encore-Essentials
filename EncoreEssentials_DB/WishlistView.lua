-- Encore-DB Wishlist tab: the items you Alt-clicked anywhere in Encore-DB (EncoreEssentials Wishlist.lua keeps the
-- list and gives the alerts). Left: all wished items, or one dungeon / vendor / world drops. Right: the items with
-- where they come from; click one to go there. Window.lua calls in here (it is near Lua's local limit).
local _, ns = ...
local Encore = _G.EncoreEssentials
local View = {}
ns.WishlistView = View

local function ui() return ns.UI end

-- { [groupKey] = { text, items = { id, ... } } } and the order of the groups, from where each item comes first.
local function grouped()
    local groups, order = {}, {}
    for id in pairs(Encore:Wishlist()) do
        local where = ns.LootData.Where(id)
        local s = where and where[1]
        local key, text
        if s and s.tab == "dungeons" then
            local inst = ns.Loot.instances[s.inst]
            key, text = "i" .. tostring(inst and inst.key), inst and inst.name or "?"
        elseif s and s.tab == "world" then
            key, text = "world", "World drops"
        elseif s then
            key, text = "v" .. tostring(s.vendor), (s.text:gsub("^Sold by ", ""))
        else
            key, text = "other", "Not in Encore-DB"
        end
        if not groups[key] then
            groups[key] = { key = key, text = text, items = {} }
            order[#order + 1] = groups[key]
        end
        table.insert(groups[key].items, id)
    end
    table.sort(order, function(a, b)
        if (a.key == "other") ~= (b.key == "other") then return b.key == "other" end
        return a.text < b.text
    end)
    return order
end

function View.tree(pick)
    local st = ui().state
    local entries = {
        { kind = "leaf", text = "All wished items", right = tostring(Encore:WishCount()), selected = st.wishGroup == nil,
            onClick = function() st.wishGroup = nil; pick() end },
    }
    for _, g in ipairs(grouped()) do
        entries[#entries + 1] = {
            kind = "leaf", text = g.text, right = tostring(#g.items), selected = st.wishGroup == g.key,
            onClick = function() st.wishGroup = g.key; pick() end,
        }
    end
    return { { key = "wishlist", text = "Wishlist", entries = entries } }
end

function View.sections(rows) end

function View.blocks()
    local U = ui()
    local st = U.state
    if Encore:WishCount() == 0 then
        return { U.emptyLine("Your wishlist is empty. Alt-click any item in Encore-DB to add it; Encore tells you when it drops, comes up for a roll, is linked in chat or is seen at the auction house.") }, "Wishlist"
    end
    local blocks, shown = {}, 0
    for _, g in ipairs(grouped()) do
        if st.wishGroup == nil or st.wishGroup == g.key then
            local cells = {}
            for _, id in ipairs(g.items) do
                local info = U.itemInfo(id)
                local where = ns.LootData.Where(id)
                local s = where and where[1]
                local chance = s and s.chance and (("%.1f%%"):format(s.chance)) or nil
                cells[#cells + 1] = U.cellFromInfo(id, info, { from = s and s.text, chance = chance, where = s })
            end
            shown = shown + #cells
            blocks[#blocks + 1] = U.heading(g.text)
            blocks[#blocks + 1] = U.grid(cells, { from = "From" })
        end
    end
    return blocks, ("Wishlist: %d items. Alt-click an item to remove it."):format(shown)
end

-- Redraw when an item is added or removed (Alt-click here, or from another addon calling Encore:ToggleWish).
local previous = Encore.OnWishlistChanged
function Encore:OnWishlistChanged(id)
    if previous then previous(self, id) end
    local U = ui()
    if U and U.isShown() then
        if U.state.tab == "wishlist" then U.renderAll() else U.renderLoot(true) end
    end
end
