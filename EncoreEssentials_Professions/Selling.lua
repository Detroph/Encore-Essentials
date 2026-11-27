-- Encore-Professions: the Selling guide, the guide panel's second tab. One list in four sections for the profession
-- on show, from the recipes you know, with every material bought (vendor materials at the vendor, the rest at the
-- auction house: the last Auctionator scan or the Encore-Stonks 7-day average):
--   Auction house: what sells there for more than its materials, after the 5% cut.
--   Vendor: what a vendor pays more for than its materials.
--   Waylaid Crates: items you can craft that other players buy to fill their Waylaid Crates, sold on the
--     auction house: crafting cost against the price after the 5% cut.
--   Craftsman's Writs: items you can craft that other players buy for their Craftsman's Writs, the same way.
-- Along the top, the best profit of each section (click one to open its section on that row). Each section folds
-- (remembered), sorts on every column, and shows the clicked row's breakdown in the pane on the right.
local _, ns = ...
local P = ns.P
local Encore = _G.EncoreEssentials

local CUT = 0.95 -- what the auction house leaves you of a sale
local ROW, HEAD, COLHEAD, GAP, BAR = 18, 21, 18, 4, 22
local TILES = 40 -- the row of totals along the top
local SECTIONS = {
    { key = "ah", title = "Auction house", empty = "No recipe you know sells on the auction house for more than its materials." },
    { key = "ven", title = "Vendor", empty = "No recipe you know sells to a vendor for more than its materials." },
    { key = "crate", title = "Waylaid Crates", empty = "No recipe you know makes an item players buy for Waylaid Crates." },
    { key = "writ", title = "Craftsman's Writs", empty = "No recipe you know makes an item players buy for Craftsman's Writs." },
}
local OPEN = { ah = true, ven = true, crate = false, writ = false }

local function UI() return Encore.UI end

local function itemName(id)
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not n and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return n or ("item " .. id)
end

local function coins(c) return P.Coins(c) end
local function signed(c)
    if not c then return "" end
    return (c > 0 and "+" or "") .. P.Coins(c)
end
local function netColour(c)
    if not c then return UI().DIM end
    if c > 0 then return UI().GREEN end
    if c < 0 then return { 1, 0.42, 0.31 } end
    return UI().DIM
end

-- Saved choices: which sections are open, how each sorts, and the price basis ("last" or "avg").
local function sdb()
    local db = P:DB()
    local s = db.selling
    if type(s) ~= "table" then s = {}; db.selling = s end
    if s.basis ~= "avg" then s.basis = "last" end
    if type(s.open) ~= "table" then s.open = {} end
    for k, v in pairs(OPEN) do if s.open[k] == nil then s.open[k] = v end end
    if type(s.sort) ~= "table" then s.sort = {} end
    for _, sec in ipairs(SECTIONS) do
        if type(s.sort[sec.key]) ~= "table" then s.sort[sec.key] = { key = "net", desc = true } end
    end
    return s
end
P.SellingDB = sdb

---------------------------------------------------------------------------
-- Prices and crafting costs
---------------------------------------------------------------------------
-- What one costs to buy: vendor price, else the auction price on the chosen basis. copper, source.
local function buyPrice(item, basis)
    local v = P.VendorPrice(item)
    if v then return v, "vendor" end
    local p = P.MarketPrice(item, basis)
    if p then return p, "auction" end
end

local recipeCost
-- One of the item: bought, or made by a recipe you know when nobody sells it. copper, source ("vendor",
-- "auction", "craft") or nil.
local function unitCost(item, ctx, depth)
    local c = ctx.cache[item]
    if c then return c.p, c.s end
    c = {}
    ctx.cache[item] = c -- a placeholder first, so a recipe that needs its own product stops here
    local p, s = buyPrice(item, ctx.basis)
    local made = ctx.madeBy[item]
    if not p and made and (depth or 0) < 2 then
        local total = recipeCost(made.r, ctx, (depth or 0) + 1)
        if total then p, s = total / math.max(1, made.r[8] or 1), "craft" end
    end
    c.p, c.s = p, s
    return p, s
end

-- One craft's materials, or nil while a material has no price.
recipeCost = function(r, ctx, depth)
    local total = 0
    for i = 1, #r[9], 2 do
        local p = unitCost(r[9][i], ctx, depth)
        if not p then return nil end
        total = total + p * r[9][i + 1]
    end
    return total
end

-- The recipes you know of the profession on show, with their reagents: { id, name, r } (r as in ns.Recipes).
local clientRecipes = {}
local function learnedRecipes(prof)
    local out = {}
    local T = C_TradeSkillUI
    if T and T.GetAllRecipeIDs and T.GetRecipeInfo then
        for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
            local info = T.GetRecipeInfo(id)
            if info and info.learned and not info.isDummyRecipe then
                local r = P.RecipeFor(prof, id)
                if not r then
                    r = clientRecipes[id]
                    if r == nil then
                        r = P.RecipeFromClient(id) or false
                        clientRecipes[id] = r
                    end
                end
                if r and r[7] and #r[9] > 0 then out[#out + 1] = { id = id, name = info.name or r[2] or itemName(r[7]), r = r } end
            end
        end
    else
        for _, r in ipairs(ns.Recipes[prof] or {}) do
            if r[7] and (r[10] == "a" or P.Knows(r[1])) then out[#out + 1] = { id = r[1], name = r[2], r = r } end
        end
    end
    return out
end

local function materials(r, crafts, ctx)
    local lines = {}
    for i = 1, #r[9], 2 do
        local item, n = r[9][i], r[9][i + 1] * crafts
        local p, s = unitCost(item, ctx)
        lines[#lines + 1] = { item = item, n = n, each = p, total = p and p * n, source = s }
    end
    return lines
end

-- Every row of the four sections for this profession and basis.
function P.SellingRows(prof, basis)
    local ctx = { basis = basis, cache = {}, madeBy = {} }
    local known = learnedRecipes(prof)
    for _, L in ipairs(known) do
        local item = L.r[7]
        if not ctx.madeBy[item] then ctx.madeBy[item] = L end
    end
    local out = { ah = {}, ven = {}, crate = {}, writ = {}, known = #known, ctx = ctx }

    for _, L in ipairs(known) do
        local r = L.r
        local item, count = r[7], math.max(1, r[8] or 1)
        local cost = recipeCost(r, ctx)
        if cost then
            local price = not P.VendorPrice(item) and P.MarketPrice(item, basis)
            if price then
                local net = price * count * CUT - cost
                if net > 0 then
                    out.ah[#out.ah + 1] = { kind = "ah", id = "ah" .. L.id, name = L.name, item = item, count = count,
                        L = L, cost = cost, price = price * count, each = price, net = net, trend = P.Trend(item),
                        margin = cost > 0 and math.floor(net / cost * 100 + 0.5) or nil }
                end
            end
            local sell = P.SellPrice(item)
            if sell and sell > 0 then
                local net = sell * count - cost
                if net > 0 then
                    out.ven[#out.ven + 1] = { kind = "ven", id = "ven" .. L.id, name = L.name, item = item, count = count,
                        L = L, cost = cost, sell = sell * count, each = sell, net = net,
                        margin = cost > 0 and math.floor(net / cost * 100 + 0.5) or nil }
                end
            end
        end
    end

    -- Items other players buy for their own turn-ins, sold to them on the auction house: one row an item.
    local function forTurnIn(list, L, use)
        local item = L.r[7]
        local row = list.byItem[item]
        if not row then
            local per = recipeCost(L.r, ctx)
            local cost = per and per / math.max(1, L.r[8] or 1)
            local price = P.MarketPrice(item, basis)
            row = { kind = list.kind, id = list.kind .. item, name = itemName(item), item = item, L = L, uses = {},
                cost = cost, price = price, net = cost and price and (price * CUT - cost) or nil }
            list.byItem[item] = row
            out[list.kind][#out[list.kind] + 1] = row
        end
        row.uses[#row.uses + 1] = use
    end
    local crates = { kind = "crate", byItem = {} }
    for _, c in ipairs(ns.Crates or {}) do
        local bundles = c[4]
        for i = 1, #bundles, 2 do
            local L = ctx.madeBy[bundles[i]]
            if L then forTurnIn(crates, L, { crate = c, k = bundles[i + 1] }) end
        end
    end

    local byName = {}
    for _, L in ipairs(known) do
        byName[L.name] = byName[L.name] or L
        local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(L.r[7])
        if n then byName[n] = byName[n] or L end
    end
    local writs = { kind = "writ", byItem = {} }
    for _, w in ipairs(ns.Writs or {}) do
        local L = ctx.madeBy[w[3]] or byName[w[4]]
        if L then forTurnIn(writs, L, { writ = w }) end
    end
    for _, row in ipairs(out.writ) do
        local lo
        for _, u in ipairs(row.uses) do lo = math.min(lo or 9, u.writ[7]) end
        row.rank = lo
    end
    return out
end

---------------------------------------------------------------------------
-- Columns
---------------------------------------------------------------------------
local COLS = {
    ah = { { key = "name", head = "Recipe" }, { key = "cost", head = "Cost", w = 60 }, { key = "price", head = "Sells", w = 60 },
        { key = "net", head = "Profit", w = 66 }, { key = "trend", head = "7 days", w = 46 } },
    ven = { { key = "name", head = "Recipe" }, { key = "cost", head = "Cost", w = 60 }, { key = "sell", head = "Vendor", w = 60 },
        { key = "net", head = "Profit", w = 66 }, { key = "margin", head = "Margin", w = 46 } },
    crate = { { key = "name", head = "Item" }, { key = "crate", head = "Players need", w = 104 }, { key = "cost", head = "Cost", w = 60 },
        { key = "price", head = "Sells", w = 60 }, { key = "net", head = "Profit", w = 66 } },
    writ = { { key = "name", head = "Item" }, { key = "zone", head = "Writ", w = 104 }, { key = "cost", head = "Cost", w = 60 },
        { key = "price", head = "Sells", w = 60 }, { key = "net", head = "Profit", w = 66 } },
}
local MAXCOLS = 5

local function crateName(c) return (ns.SellRanks[c[2]] or "") .. " " .. c[3] end

local function cellText(row, key)
    if key == "name" then
        if row.kind == "crate" or row.kind == "writ" then return row.name end
        local n = row.name or ""
        if (row.count or 1) > 1 then n = n .. " ×" .. row.count end
        return n
    elseif key == "crate" then
        local u = row.uses[1]
        return u.k .. " for " .. crateName(u.crate) .. (#row.uses > 1 and (" +" .. (#row.uses - 1)) or ""), UI().DIM
    elseif key == "zone" then
        return (ns.SellRanks[row.rank] or "") .. (#row.uses > 1 and (" ×" .. #row.uses) or ""), UI().DIM
    elseif key == "trend" or key == "margin" then
        local v = row[key]
        if not v then return "", UI().DIM end
        return (v > 0 and "+" or "") .. v .. "%", netColour(v)
    elseif key == "net" then
        if not row.net then return "no price", { 1, 0.5, 0.25 } end
        return signed(row.net), netColour(row.net)
    end
    local v = row[key]
    if not v then return "no price", UI().DIM end
    return coins(v)
end

local function sortValue(row, key)
    if key == "name" then return cellText(row, "name") end
    if key == "crate" then local c = row.uses[1].crate; return c[2] * 100 + (c[1] % 100) end
    if key == "zone" then return row.rank * 100 + #row.uses end
    return row[key]
end

---------------------------------------------------------------------------
-- The breakdown under a row
---------------------------------------------------------------------------
local SOURCE = { vendor = "vendor", auction = "auction house", craft = "crafted" }

local function breakdown(row, basis, ctx)
    local lines = {} -- { left, right, colour of the right, bold }
    local function add(l, r, c, strong) lines[#lines + 1] = { l, r or "", c, strong } end
    local function mats(crafts)
        for _, m in ipairs(materials(row.L.r, crafts, ctx)) do
            add(("%d × %s |cffa39178(%s)|r"):format(m.n, itemName(m.item), m.source and SOURCE[m.source] or "no price"),
                m.total and coins(m.total) or "no price", not m.total and { 1, 0.5, 0.25 } or nil)
        end
    end
    local basisName = basis == "avg" and "7-day average" or "last scan"
    if row.kind == "ah" then
        mats(1)
        add("Crafting cost", signed(-row.cost), netColour(-1))
        add(("Auction house, %s"):format(basisName), signed(row.price), netColour(1))
        add("Auction house cut 5%", signed(-row.price * (1 - CUT)), netColour(-1))
        add("Profit", signed(row.net), netColour(row.net), true)
    elseif row.kind == "ven" then
        mats(1)
        add("Crafting cost", signed(-row.cost), netColour(-1))
        add("A vendor pays", signed(row.sell), netColour(1))
        add("Profit", signed(row.net), netColour(row.net), true)
    elseif row.kind == "crate" or row.kind == "writ" then
        mats(1)
        local count = math.max(1, row.L.r[8] or 1)
        add(count > 1 and ("Crafting cost (one of %d)"):format(count) or "Crafting cost",
            row.cost and signed(-row.cost) or "no price", netColour(row.cost and -1))
        add(("Auction house, %s"):format(basisName), row.price and signed(row.price) or "no price", netColour(row.price and 1))
        if row.price then add("Auction house cut 5%", signed(-row.price * (1 - CUT)), netColour(-1)) end
        add("Profit each", row.net and signed(row.net) or "no price", netColour(row.net), true)
        add(" ")
        if row.kind == "crate" then
            add("Players buy it to fill a Waylaid Crate:")
            for _, u in ipairs(row.uses) do
                add(("  %d for a %s crate"):format(u.k, crateName(u.crate)),
                    row.net and signed(row.net * u.k) or "", netColour(row.net))
            end
            add("List it in stacks of what a crate takes.", nil, nil)
        else
            add("Players buy it to hand in a Craftsman's Writ:")
            for _, u in ipairs(row.uses) do
                local w = u.writ
                add(("  %s writ, %s"):format(ns.SellRanks[w[7]] or "", (w[5] and (w[5] .. ", ") or "") .. w[6]))
            end
        end
    end
    return lines
end


---------------------------------------------------------------------------
-- The view: the four sections on the left, the clicked row's breakdown on the right
---------------------------------------------------------------------------
local view
local state = { sel = nil }
local ICON_W = ROW - 1

local function itemIcon(id)
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function pool(list, i, make)
    local f = list[i]
    if not f then f = make(); list[i] = f end
    f:Show()
    return f
end

local function widths(cols, total)
    local fixed = 0
    for _, c in ipairs(cols) do fixed = fixed + (c.w or 0) end
    local out = {}
    for i, c in ipairs(cols) do out[i] = c.w or (total - fixed - GAP * (#cols - 1)) end
    return out
end

local function tip(frame, fn)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        if fn(self, GameTooltip) ~= false then GameTooltip:Show() else GameTooltip:Hide() end
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local layout

local function makeHead(parent)
    local h = CreateFrame("Button", nil, parent)
    h:SetHeight(HEAD - 1)
    h.bg = h:CreateTexture(nil, "BACKGROUND")
    h.bg:SetAllPoints()
    UI().Fade(h.bg, "VERTICAL", 0.09, 0.06, 0.04, 1, 0.17, 0.13, 0.09, 1)
    UI().NavRow(h)
    h.sum = UI().Text(h, "GameFontHighlightSmall", "", UI().DIM)
    h.sum:SetPoint("RIGHT", -6, 0)
    h.sum:SetJustifyH("RIGHT")
    h:SetScript("OnClick", function(self)
        local s = sdb()
        s.open[self.key] = not s.open[self.key]
        layout()
    end)
    return h
end

local function makeColHead(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(COLHEAD)
    f.buttons = {}
    for i = 1, MAXCOLS do
        local b = CreateFrame("Button", nil, f)
        b:SetHeight(COLHEAD)
        b.text = UI().Text(b, "GameFontNormalSmall", "", UI().GOLD)
        b.text:SetAllPoints()
        b:SetScript("OnClick", function(self)
            local sort = sdb().sort[f.key]
            if sort.key == self.col.key then sort.desc = not sort.desc
            else sort.key, sort.desc = self.col.key, self.col.key ~= "name" and self.col.key ~= "crate" and self.col.key ~= "zone" end
            layout()
        end)
        f.buttons[i] = b
    end
    return f
end

local function makeRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW)
    r:RegisterForClicks("LeftButtonUp")
    r.stripe = r:CreateTexture(nil, "BACKGROUND")
    r.stripe:SetAllPoints()
    r.stripe:SetColorTexture(1, 1, 1, 0.04)
    r.selBg = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.selBg:SetAllPoints()
    r.selBg:SetColorTexture(UI().TEAL[1], UI().TEAL[2], UI().TEAL[3], 0.14)
    r.selBar = r:CreateTexture(nil, "ARTWORK")
    r.selBar:SetPoint("TOPLEFT"); r.selBar:SetPoint("BOTTOMLEFT"); r.selBar:SetWidth(2)
    r.selBar:SetColorTexture(UI().TEAL[1], UI().TEAL[2], UI().TEAL[3], 1)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(UI().COPPER[1], UI().COPPER[2], UI().COPPER[3], 0.12)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ROW - 4, ROW - 4)
    r.icon:SetPoint("LEFT", 4, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.cells = {}
    for i = 1, MAXCOLS do
        local fs = UI().Text(r, "GameFontHighlightSmall", "")
        fs:SetWordWrap(false)
        r.cells[i] = fs
    end
    r:SetScript("OnClick", function(self)
        if not self.data then return end
        state.sel = self.data.id
        layout()
    end)
    tip(r, function(self, tt)
        local d = self.data
        if not d then return false end
        tt:SetItemByID(d.item)
        if d.kind == "crate" or d.kind == "writ" then
            tt:AddLine(" ")
            tt:AddLine(d.kind == "crate" and "Players buy it to fill a Waylaid Crate:" or "Players buy it to hand in a Craftsman's Writ:", 1, 0.82, 0)
            for _, u in ipairs(d.uses) do
                if u.crate then
                    tt:AddLine(("%d for a %s crate"):format(u.k, crateName(u.crate)), 1, 1, 1)
                else
                    tt:AddLine(("%s writ, %s"):format(ns.SellRanks[u.writ[7]] or "", (u.writ[5] and (u.writ[5] .. ", ") or "") .. u.writ[6]), 1, 1, 1)
                end
            end
        end
        if d.net then tt:AddDoubleLine((d.kind == "crate" or d.kind == "writ") and "Profit each" or "Profit", signed(d.net), 0.64, 0.57, 0.47, unpack(netColour(d.net))) end
        tt:AddLine("Click for the breakdown on the right.", 0.64, 0.57, 0.47)
    end)
    return r
end

-- The breakdown lines in the right pane.
local function fillLines(f, lines, width)
    local y = 0
    for i, l in ipairs(lines) do
        local left = f.left[i]
        if not left then
            left = UI().Text(f, "GameFontHighlightSmall", "")
            left:SetWordWrap(true)
            f.left[i] = left
            local right = UI().Text(f, "GameFontHighlightSmall", "")
            right:SetJustifyH("RIGHT")
            right:SetWordWrap(false)
            f.right[i] = right
        end
        local right = f.right[i]
        local hasRight = l[2] ~= ""
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", 0, y)
        left:SetWidth(hasRight and (width - 84 - 6) or width)
        left:SetText(l[4] and ("|cffffffff" .. l[1] .. "|r") or l[1])
        UI().Color(left, hasRight and UI().INK or UI().DIM)
        left:Show()
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", 0, y)
        right:SetWidth(84)
        right:SetText(l[2])
        UI().Color(right, l[3] or UI().INK)
        right:SetShown(hasRight)
        y = y - math.max(13, (left:GetStringHeight() or 12) + 3)
    end
    for i = #lines + 1, #f.left do f.left[i]:Hide(); f.right[i]:Hide() end
end

local function bestOf(rows)
    local best
    for _, r in ipairs(rows) do if r.net and (not best or r.net > best.net) then best = r end end
    return best
end

local function summary(rows)
    if #rows == 0 then return "none" end
    local best
    for _, r in ipairs(rows) do if r.net and (not best or r.net > best) then best = r.net end end
    if not best then return tostring(#rows) end
    return ("%d · best %s"):format(#rows, (best > 0 and "|cff73d966" or "|cffff6b4f") .. signed(best) .. "|r")
end

local function sortRows(rows, sort)
    local pos = {}
    for i, e in ipairs(rows) do pos[e] = i end
    local key, desc = sort.key, sort.desc
    table.sort(rows, function(a, b)
        local x, y = sortValue(a, key), sortValue(b, key)
        if x == nil or y == nil then
            if x == nil and y == nil then return pos[a] < pos[b] end
            return y == nil
        end
        if type(x) ~= type(y) then x, y = tostring(x), tostring(y) end
        if x == y then return pos[a] < pos[b] end
        if desc then return x > y end
        return x < y
    end)
end

local KIND_SUB = { ah = "Auction house", ven = "Sell to a vendor" }

local function showPane(d)
    local pane = view.pane
    pane.data = d
    if not d then
        pane.icon:Hide()
        pane.title:SetText("")
        pane.sub:SetText("")
        pane.empty:Show()
        fillLines(pane.body, {}, pane.width)
        pane.select:Hide(); pane.shop:Hide()
        return
    end
    pane.empty:Hide()
    pane.icon:SetTexture(itemIcon(d.item))
    pane.icon:Show()
    pane.title:SetText(cellText(d, "name"))
    local sub
    if d.kind == "ah" then
        sub = "Auction house" .. (d.trend and (" · %s%d%% vs 7-day average"):format(d.trend > 0 and "+" or "", d.trend) or "")
    elseif d.kind == "crate" then
        sub = "Sells to players filling Waylaid Crates"
    elseif d.kind == "writ" then
        sub = "Sells to players handing in Craftsman's Writs"
    else
        sub = KIND_SUB[d.kind] or ""
    end
    pane.sub:SetText(sub)
    fillLines(pane.body, breakdown(d, sdb().basis, view.data.ctx), pane.width)
    pane.select:Show()
    pane.shop:Show()
    pane.shop:SetEnabled(P.HasShoppingAPI())
end

-- The materials for the row on show, less what the bags and bank hold, on the Auctionator list "Encore: Selling".
local function shopForPane()
    local d = view and view.pane.data
    if not d then return end
    local crafts = d.kind == "crate" and math.ceil(d.uses[1].k / math.max(1, d.L.r[8] or 1)) or 1
    local list = {}
    for _, m in ipairs(materials(d.L.r, crafts, view.data.ctx)) do
        local count = m.n - P.Have(m.item)
        if m.source == "auction" and count > 0 then list[#list + 1] = { item = m.item, count = count } end
    end
    local ok = P.ShoppingListFor("Encore: Selling", list)
    if ok then P.Print("Auctionator list \"Encore: Selling\": %d to buy for %s.", #list, cellText(d, "name")) end
end

layout = function()
    local v = view
    if not (v and v.data) then return end
    local s = sdb()
    local W = v.width
    local child = v.child
    local y = 0
    local nHead, nCol, nRow, nMsg = 0, 0, 0, 0
    local selRow, firstRow, jumpY
    for _, sec in ipairs(SECTIONS) do
        local rows = v.data[sec.key]
        nHead = nHead + 1
        local h = pool(v.heads, nHead, function() return makeHead(child) end)
        h.key = sec.key
        h:SetWidth(W)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, y)
        UI().NavSet(h, { text = sec.title, head = true, open = s.open[sec.key] })
        h.label:SetPoint("RIGHT", h.sum, "LEFT", -6, 0)
        h.sum:SetText(summary(rows))
        y = y - HEAD
        if s.open[sec.key] then
            if #rows == 0 then
                nMsg = nMsg + 1
                local m = pool(v.msgs, nMsg, function()
                    local fs = UI().Text(child, "GameFontHighlightSmall", "", UI().DIM)
                    fs:SetWordWrap(true)
                    return fs
                end)
                m:SetWidth(W - 16)
                m:ClearAllPoints()
                m:SetPoint("TOPLEFT", 8, y - 3)
                m:SetText(sec.empty)
                y = y - math.max(18, (m:GetStringHeight() or 12) + 8)
            else
                local cols = COLS[sec.key]
                local ws = widths(cols, W - 8 - ICON_W)
                local sort = s.sort[sec.key]
                nCol = nCol + 1
                local ch = pool(v.colHeads, nCol, function() return makeColHead(child) end)
                ch.key = sec.key
                ch:SetWidth(W)
                ch:ClearAllPoints()
                ch:SetPoint("TOPLEFT", 0, y)
                local x = 4
                for i, b in ipairs(ch.buttons) do
                    local c = cols[i]
                    b:SetShown(c ~= nil)
                    if c then
                        local w = ws[i] + (i == 1 and ICON_W or 0)
                        b:ClearAllPoints()
                        b:SetPoint("TOPLEFT", x, 0)
                        b:SetWidth(w)
                        b.col = c
                        b.text:SetJustifyH(i == 1 and "LEFT" or "RIGHT")
                        if c.key == "crate" or c.key == "zone" then b.text:SetJustifyH("LEFT") end
                        b.text:SetText(c.head .. (sort.key == c.key and (sort.desc and " v" or " ^") or ""))
                        x = x + w + GAP
                    end
                end
                y = y - COLHEAD
                sortRows(rows, sort)
                for idx, d in ipairs(rows) do
                    firstRow = firstRow or d
                    if state.sel == d.id then selRow = d end
                    if state.jump == d.id then jumpY = y end
                    nRow = nRow + 1
                    local r = pool(v.rows, nRow, function() return makeRow(child) end)
                    r.data = d
                    r:SetWidth(W)
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", 0, y)
                    r.stripe:SetShown(idx % 2 == 0)
                    local on = state.sel == d.id
                    r.selBg:SetShown(on); r.selBar:SetShown(on)
                    r.icon:SetTexture(itemIcon(d.item))
                    x = 4 + ICON_W
                    for i, fs in ipairs(r.cells) do
                        local c = cols[i]
                        fs:SetShown(c ~= nil)
                        if c then
                            local text, colour = cellText(d, c.key)
                            fs:ClearAllPoints()
                            fs:SetPoint("LEFT", x, 0)
                            fs:SetWidth(ws[i])
                            fs:SetJustifyH((i == 1 or c.key == "crate" or c.key == "zone") and "LEFT" or "RIGHT")
                            fs:SetText(text or "")
                            UI().Color(fs, colour or UI().INK)
                            x = x + ws[i] + GAP
                        end
                    end
                    y = y - ROW
                end
            end
        end
        y = y - 3
    end
    for i = nHead + 1, #v.heads do v.heads[i]:Hide() end
    for i = nCol + 1, #v.colHeads do v.colHeads[i]:Hide() end
    for i = nRow + 1, #v.rows do v.rows[i]:Hide(); v.rows[i].data = nil end
    for i = nMsg + 1, #v.msgs do v.msgs[i]:Hide() end
    child:SetHeight(math.max(10, -y))
    if jumpY then
        state.jump = nil
        local max = math.max(0, -y - (v.scroll:GetHeight() or 0))
        v.scroll:SetVerticalScroll(math.min(max, math.max(0, -jumpY - 2 * ROW)))
    end
    -- The pane shows the clicked row, or the first row on show until one is clicked.
    if not selRow and firstRow then
        state.sel = firstRow.id
        return layout()
    end
    showPane(selRow)
end

-- Builds the view in the guide's dark pane. inner: the pane's width less its padding; pad: that padding;
-- right: the width of the breakdown pane on the right.
function P.BuildSellingView(parent, inner, pad, right)
    right = right or 262
    local v = CreateFrame("Frame", nil, parent)
    v:SetPoint("TOPLEFT", pad, -pad)
    v:SetPoint("BOTTOMRIGHT", -pad, pad)
    view = v
    P.sellingView = v
    local listW = inner - right - 8
    v.width = listW - BAR
    -- The row of totals: the best of each section
    v.tiles = {}
    local tileW = (inner - 3 * 4) / 4
    for i, sec in ipairs(SECTIONS) do
        local t = CreateFrame("Button", nil, v)
        t:SetSize(tileW, TILES - 4)
        t:SetPoint("TOPLEFT", (i - 1) * (tileW + 4), 0)
        t.well = UI().Well(t)
        t.well:SetAllPoints()
        t.key = sec.key
        t.label = UI().Text(t, "GameFontHighlightSmall", sec.key == "ah" and "Best at the auction house"
            or sec.key == "ven" and "Best at a vendor" or "Best for " .. sec.title, UI().DIM)
        t.label:SetPoint("TOPLEFT", 6, -4)
        t.label:SetWidth(tileW - 12)
        t.label:SetWordWrap(false)
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetSize(14, 14)
        t.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        t.value = UI().Text(t, "GameFontNormalSmall", "")
        t.value:SetPoint("BOTTOMLEFT", 6, 5)
        t.value:SetWordWrap(false)
        t.name = UI().Text(t, "GameFontNormalSmall", "", UI().INK)
        t.icon:SetPoint("LEFT", t.value, "RIGHT", 4, 0)
        t.name:SetPoint("LEFT", t.icon, "RIGHT", 3, 0)
        t.name:SetPoint("RIGHT", -6, 0)
        t.name:SetWordWrap(false)
        t:SetScript("OnClick", function(self)
            if not self.row then return end
            sdb().open[self.key] = true
            state.sel, state.jump = self.row.id, self.row.id
            layout()
        end)
        tip(t, function(self, tt)
            tt:SetText(self.label:GetText(), 1, 0.82, 0)
            if self.row then
                tt:AddDoubleLine(cellText(self.row, "name"), signed(self.row.net), 1, 1, 1, unpack(netColour(self.row.net)))
                tt:AddLine("Click to open the section on this row.", 0.64, 0.57, 0.47, true)
            else
                tt:AddLine("Nothing in this section yet.", 1, 1, 1, true)
            end
        end)
        v.tiles[i] = t
    end

    v.sub = UI().Text(v, "GameFontHighlightSmall", "Recipes you know, with materials bought", UI().DIM)
    v.sub:SetPoint("TOPLEFT", 0, -TILES)
    v.sub:SetWidth(listW)
    v.subHit = CreateFrame("Frame", nil, v)
    v.subHit:SetPoint("TOPLEFT", v.sub)
    v.subHit:SetPoint("BOTTOMRIGHT", v.sub)
    tip(v.subHit, function(_, tt)
        tt:SetText("Selling guide", 1, 0.82, 0)
        tt:AddLine("Every recipe you know of this profession. Materials are bought: vendor materials at the vendor's price, the rest at the auction house. A material made by a recipe you know counts at its crafting cost only when nobody sells it.", 1, 1, 1, true)
        tt:AddLine("Auction house and Vendor show only what makes a profit. Waylaid Crates and Craftsman's Writs show every item you can make that other players buy for their crates and writs, profit or loss, priced as an auction house sale.", 1, 1, 1, true)
    end)
    v.none = UI().Text(v, "GameFontHighlightSmall", "", UI().DIM)
    v.none:SetPoint("TOPLEFT", 0, -TILES - 22)
    v.none:SetWidth(listW)
    v.scroll = CreateFrame("ScrollFrame", nil, v, "UIPanelScrollFrameTemplate")
    v.scroll:SetPoint("TOPLEFT", 0, -TILES - 18)
    v.scroll:SetPoint("BOTTOMRIGHT", v, "BOTTOMLEFT", listW - BAR, 18)
    v.child = CreateFrame("Frame", nil, v.scroll)
    v.child:SetSize(v.width, 10)
    v.scroll:SetScrollChild(v.child)
    v.heads, v.colHeads, v.rows, v.msgs = {}, {}, {}, {}
    v.foot = UI().Text(v, "GameFontHighlightSmall", "", UI().DIM)
    v.foot:SetPoint("BOTTOMLEFT", 0, 0)
    v.footRight = UI().Text(v, "GameFontHighlightSmall", "", UI().DIM)
    v.footRight:SetPoint("BOTTOMRIGHT", v, "BOTTOMLEFT", listW, 0)
    v.footRight:SetJustifyH("RIGHT")

    -- The breakdown pane
    local pane = UI().Well(v)
    v.pane = pane
    pane:SetPoint("TOPLEFT", listW + 8, -TILES)
    pane:SetPoint("BOTTOMRIGHT", 0, 0)
    pane.width = right - 16
    pane.icon = pane:CreateTexture(nil, "ARTWORK")
    pane.icon:SetSize(28, 28)
    pane.icon:SetPoint("TOPLEFT", 8, -8)
    pane.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    pane.title = UI().Text(pane, "GameFontNormal", "", UI().INK)
    pane.title:SetPoint("TOPLEFT", pane.icon, "TOPRIGHT", 6, 0)
    pane.title:SetWidth(right - 16 - 34)
    pane.title:SetWordWrap(false)
    pane.sub = UI().Text(pane, "GameFontHighlightSmall", "", UI().DIM)
    pane.sub:SetPoint("TOPLEFT", pane.title, "BOTTOMLEFT", 0, -2)
    pane.sub:SetWidth(right - 16 - 34)
    pane.sub:SetWordWrap(false)
    pane.empty = UI().Text(pane, "GameFontHighlightSmall", "Click a row to see where the money goes.", UI().DIM)
    pane.empty:SetPoint("TOPLEFT", 8, -10)
    pane.empty:SetWidth(right - 16)
    pane.body = CreateFrame("Frame", nil, pane)
    pane.body:SetPoint("TOPLEFT", 8, -46)
    pane.body:SetPoint("BOTTOMRIGHT", -8, 34)
    pane.body.left, pane.body.right = {}, {}
    pane.select = UI().Button(pane, "Select recipe", function()
        local d = pane.data
        local box = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RecipeList
            and ProfessionsFrame.CraftingPage.RecipeList.SearchBox
        if d and box then box:SetText(d.L.name or "") end
    end, 100)
    pane.select:SetHeight(20)
    pane.select:SetPoint("BOTTOMLEFT", 8, 8)
    tip(pane.select, function(_, tt)
        tt:SetText("Select recipe", 1, 0.82, 0)
        tt:AddLine("Finds the recipe in the list on the left of the profession window. Click it there to craft.", 1, 1, 1, true)
    end)
    pane.shop = UI().Button(pane, "Shopping list", shopForPane, 100)
    pane.shop:SetHeight(20)
    pane.shop:SetPoint("LEFT", pane.select, "RIGHT", 6, 0)
    pane.shop:SetMotionScriptsWhileDisabled(true)
    tip(pane.shop, function(_, tt)
        tt:SetText("Auctionator shopping list", 1, 0.82, 0)
        tt:AddLine("Puts the auction house materials for this craft in Auctionator's list \"Encore: Selling\", less what your bags and bank hold.", 1, 1, 1, true)
        if not P.HasShoppingAPI() then tt:AddLine("Requires Auctionator.", 1, 0.3, 0.3) end
    end)
    v:Hide()
    return v
end

-- Fills the view for the profession on show (o from P:Open()).
function P.ShowSelling(o)
    local v = view
    if not v then return end
    local s = sdb()
    if v.prof ~= o.name then state.sel = nil; v.prof = o.name end
    v.data = P.SellingRows(o.name, s.basis)
    local any = v.data.known > 0
    v.scroll:SetShown(any)
    v.pane:SetShown(any)
    v.none:SetShown(not any)
    if not any then
        v.none:SetText(("%s has no recipes you know that make an item."):format(o.shown or o.name))
    end
    v.sub:SetText(("%s recipes you know, with materials bought"):format(o.shown or o.name))
    for _, t in ipairs(v.tiles) do
        local row = any and bestOf(v.data[t.key]) or nil
        t.row = row
        if row then
            t.value:SetText(signed(row.net))
            UI().Color(t.value, netColour(row.net))
            t.icon:SetTexture(itemIcon(row.item))
            t.icon:Show()
            t.name:SetText(cellText(row, "name"))
        else
            t.value:SetText("none")
            UI().Color(t.value, UI().DIM)
            t.icon:Hide()
            t.name:SetText("")
        end
    end
    if P.HasAuctionator() then
        v.foot:SetText(s.basis == "avg" and "Prices: Encore-Stonks 7-day average" or "Prices: last Auctionator scan")
    else
        v.foot:SetText("|cffff8040Auctionator not found: no auction prices|r")
    end
    local stonks = Encore and Encore.modules and Encore.modules.Stonks
    v.footRight:SetText(stonks and "" or "Encore-Stonks off: no 7-day average")
    if any then layout() end
end

-- Item names arrive from the server a moment after they are asked for; draw the list again once they have.
local pending
local f = CreateFrame("Frame")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
f:SetScript("OnEvent", function()
    if pending or not (view and view:IsVisible()) then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        if view and view:IsVisible() then
            local ok, err = pcall(P.Refresh, P)
            if not ok then geterrorhandler()(err) end
        end
    end)
end)
