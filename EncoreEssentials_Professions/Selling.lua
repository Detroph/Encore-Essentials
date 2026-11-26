-- Encore-Professions: the Selling guide, the guide panel's second tab. One list in four sections for the profession
-- on show, from the recipes you know, with every material bought (vendor materials at the vendor, the rest at the
-- auction house: the last Auctionator scan or the Encore-Stonks 7-day average):
--   Auction house: what sells there for more than its materials, after the 5% cut.
--   Vendor: what a vendor pays more for than its materials.
--   Waylaid Crates: the crate bundles you can craft, and what crafting one costs per Merchant's Favor.
--   Craftsman's Writs: the writ items you can craft, against the writ's Coin Pouch.
-- Each section folds (remembered), sorts on every column, and opens a breakdown under a row on click.
local _, ns = ...
local P = ns.P
local Encore = _G.EncoreEssentials

local CUT = 0.95 -- what the auction house leaves you of a sale
local ROW, HEAD, COLHEAD, GAP, BAR = 18, 21, 18, 4, 22
local CAMP = {
    Horde = "Durotar Supply and Logistics, outside the Crossroads",
    Alliance = "Azeroth Commerce Authority, Three Corners in Redridge",
}
local SECTIONS = {
    { key = "ah", title = "Auction house", empty = "No recipe you know sells on the auction house for more than its materials." },
    { key = "ven", title = "Vendor", empty = "No recipe you know sells to a vendor for more than its materials." },
    { key = "crate", title = "Waylaid Crates", empty = "No recipe you know makes a Waylaid Crate bundle." },
    { key = "writ", title = "Craftsman's Writs", empty = "No recipe you know makes a Craftsman's Writ item." },
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
                        L = L, cost = cost, price = price * count, each = price, net = net }
                end
            end
            local sell = P.SellPrice(item)
            if sell and sell > 0 then
                local net = sell * count - cost
                if net > 0 then
                    out.ven[#out.ven + 1] = { kind = "ven", id = "ven" .. L.id, name = L.name, item = item, count = count,
                        L = L, cost = cost, sell = sell * count, each = sell, net = net }
                end
            end
        end
    end

    for _, c in ipairs(ns.Crates or {}) do
        local bundles = c[4]
        for i = 1, #bundles, 2 do
            local item, k = bundles[i], bundles[i + 1]
            local L = ctx.madeBy[item]
            if L then
                local per = recipeCost(L.r, ctx)
                local crafts = math.ceil(k / math.max(1, L.r[8] or 1))
                local cost = per and per * crafts
                local price = P.MarketPrice(item, basis)
                local value = price and price * k * CUT
                local favor = ns.CrateFavor[c[2]] or 10
                out.crate[#out.crate + 1] = { kind = "crate", id = "crate" .. c[1] .. ":" .. item, name = itemName(item),
                    item = item, k = k, crafts = crafts, crate = c, L = L, cost = cost, value = value,
                    net = cost and value and (value - cost) or nil, favor = favor, per = cost and cost / favor or nil }
            end
        end
    end

    local byName = {}
    for _, L in ipairs(known) do
        byName[L.name] = byName[L.name] or L
        local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(L.r[7])
        if n then byName[n] = byName[n] or L end
    end
    local seen = {}
    for _, w in ipairs(ns.Writs or {}) do
        local L = ctx.madeBy[w[3]] or byName[w[4]]
        if L and not seen[L.r[7]] then
            seen[L.r[7]] = true
            local per = recipeCost(L.r, ctx)
            local cost = per and per / math.max(1, L.r[8] or 1)
            local pouch, rep = ns.WritPouch[w[7]] or 0, ns.WritRep[w[7]] or 0
            local net = cost and (pouch - cost) or nil
            local per100
            if net then per100 = net >= 0 and 0 or math.floor(-net / math.max(1, rep) + 0.5) * 100 end
            out.writ[#out.writ + 1] = { kind = "writ", id = "writ" .. w[1], name = w[4], item = L.r[7], writ = w, L = L,
                cost = cost, pouch = pouch, rep = rep, net = net, per100 = per100 }
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Columns
---------------------------------------------------------------------------
local COLS = {
    ah = { { key = "name", head = "Recipe" }, { key = "cost", head = "Cost", w = 62 }, { key = "price", head = "Sells", w = 62 },
        { key = "net", head = "Profit", w = 70 } },
    ven = { { key = "name", head = "Recipe" }, { key = "cost", head = "Cost", w = 62 }, { key = "sell", head = "Vendor", w = 62 },
        { key = "net", head = "Profit", w = 70 } },
    crate = { { key = "name", head = "Item" }, { key = "crate", head = "Crate", w = 84 }, { key = "net", head = "Net", w = 66 },
        { key = "per", head = "Per Favor", w = 62 } },
    writ = { { key = "name", head = "Item" }, { key = "rep", head = "Rep", w = 30 }, { key = "net", head = "Net", w = 72 },
        { key = "per100", head = "Per 100 rep", w = 72 } },
}

local function crateName(c) return (ns.SellRanks[c[2]] or "") .. " " .. c[3] end

local function cellText(row, key)
    if key == "name" then
        if row.kind == "crate" then return row.k .. " × " .. itemName(row.item) end
        if row.kind == "writ" then return row.name end
        local n = row.name or ""
        if (row.count or 1) > 1 then n = n .. " ×" .. row.count end
        return n
    elseif key == "crate" then
        return crateName(row.crate), UI().DIM
    elseif key == "rep" then
        return tostring(row.rep)
    elseif key == "per100" then
        if not row.per100 then return "no price", UI().DIM end
        if row.per100 == 0 then return "free", UI().GREEN end
        return coins(row.per100)
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
    if key == "crate" then return row.crate[2] * 100 + (row.crate[1] % 100) end
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
    elseif row.kind == "crate" then
        mats(row.crafts)
        add(("Crafting cost (%d crafts)"):format(row.crafts), row.cost and signed(-row.cost) or "no price", netColour(row.cost and -1))
        add(("Or sell the %d on the auction house, after the cut"):format(row.k), row.value and signed(row.value) or "no price", netColour(row.value and 1))
        add("Net", row.net and signed(row.net) or "no price", netColour(row.net), true)
        add(("Fills a %s crate: %d Merchant's Favor%s"):format(crateName(row.crate), row.favor,
            row.per and (", " .. coins(row.per) .. " per Favor") or ""))
        local others = {}
        local b = row.crate[4]
        for i = 1, #b, 2 do
            if b[i] ~= row.item then others[#others + 1] = b[i + 1] .. " " .. itemName(b[i]) end
        end
        if #others > 0 then add("Or fill it with " .. table.concat(others, ", ") .. ".") end
        local faction = UnitFactionGroup and UnitFactionGroup("player")
        if CAMP[faction] then add("Hand in: " .. CAMP[faction] .. ".") end
    elseif row.kind == "writ" then
        local w = row.writ
        mats(1)
        local count = math.max(1, row.L.r[8] or 1)
        add(count > 1 and ("Crafting cost (one of %d)"):format(count) or "Crafting cost", row.cost and signed(-row.cost) or "no price", netColour(row.cost and -1))
        add("Coin Pouch, average", signed(row.pouch), netColour(1))
        add("Net", row.net and signed(row.net) or "no price", netColour(row.net), true)
        add(("%s writ: %d reputation"):format(ns.SellRanks[w[7]] or "", row.rep))
        add("Hand in: " .. (w[5] and (w[5] .. ", ") or "") .. w[6] .. ".")
        local writAH, itemAH = P.MarketPrice(w[1], basis), P.MarketPrice(row.item, basis)
        if writAH or itemAH then
            add(("Not counted: the writ sells for %s, the finished item for %s."):format(
                writAH and coins(writAH) or "?", itemAH and coins(itemAH) or "?"))
        end
    end
    return lines
end

---------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------
local view
local state = { sel = nil }

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
    for i = 1, 4 do
        local b = CreateFrame("Button", nil, f)
        b:SetHeight(COLHEAD)
        b.text = UI().Text(b, "GameFontNormalSmall", "", UI().GOLD)
        b.text:SetAllPoints()
        b:SetScript("OnClick", function(self)
            local sort = sdb().sort[f.key]
            if sort.key == self.col.key then sort.desc = not sort.desc
            else sort.key, sort.desc = self.col.key, self.col.key ~= "name" and self.col.key ~= "crate" end
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
    r.selBg:SetColorTexture(UI().TEAL[1], UI().TEAL[2], UI().TEAL[3], 0.12)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(UI().COPPER[1], UI().COPPER[2], UI().COPPER[3], 0.12)
    r.cells = {}
    for i = 1, 4 do
        local fs = UI().Text(r, "GameFontHighlightSmall", "")
        fs:SetWordWrap(false)
        r.cells[i] = fs
    end
    r:SetScript("OnClick", function(self)
        if not self.data then return end
        state.sel = state.sel ~= self.data.id and self.data.id or nil
        layout()
    end)
    tip(r, function(self, tt)
        local d = self.data
        if not d then return false end
        tt:SetItemByID(d.item)
        tt:AddLine(state.sel == d.id and "Click to close the breakdown." or "Click for the breakdown.", 0.64, 0.57, 0.47)
    end)
    return r
end

local function makeDetail(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(UI().TEAL[1], UI().TEAL[2], UI().TEAL[3], 0.06)
    f.bar = f:CreateTexture(nil, "ARTWORK")
    f.bar:SetPoint("TOPLEFT"); f.bar:SetPoint("BOTTOMLEFT"); f.bar:SetWidth(2)
    f.bar:SetColorTexture(UI().TEAL[1], UI().TEAL[2], UI().TEAL[3], 0.9)
    f.left, f.right = {}, {}
    return f
end

local function fillDetail(f, lines, width)
    local y = -4
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
        left:SetPoint("TOPLEFT", 10, y)
        left:SetWidth(hasRight and (width - 10 - 90 - 6) or (width - 16))
        left:SetText(l[4] and ("|cffffffff" .. l[1] .. "|r") or l[1])
        UI().Color(left, hasRight and UI().INK or UI().DIM)
        left:Show()
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", -6, y)
        right:SetWidth(90)
        right:SetText(l[2])
        UI().Color(right, l[3] or UI().INK)
        right:SetShown(hasRight)
        y = y - math.max(14, (left:GetStringHeight() or 12) + 2)
    end
    for i = #lines + 1, #f.left do f.left[i]:Hide(); f.right[i]:Hide() end
    f:SetHeight(-y + 4)
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

layout = function()
    local v = view
    if not (v and v.data) then return end
    local s = sdb()
    local W = v.width
    local child = v.child
    local y = 0
    local nHead, nCol, nRow, nDetail, nMsg = 0, 0, 0, 0, 0
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
                local ws = widths(cols, W - 8)
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
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", x, 0)
                    b:SetWidth(ws[i])
                    b.col = c
                    b.text:SetJustifyH(i == 1 and "LEFT" or "RIGHT")
                    b.text:SetText(c.head .. (sort.key == c.key and (sort.desc and " v" or " ^") or ""))
                    x = x + ws[i] + GAP
                end
                y = y - COLHEAD
                sortRows(rows, sort)
                for idx, d in ipairs(rows) do
                    nRow = nRow + 1
                    local r = pool(v.rows, nRow, function() return makeRow(child) end)
                    r.data = d
                    r:SetWidth(W)
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", 0, y)
                    r.stripe:SetShown(idx % 2 == 0)
                    r.selBg:SetShown(state.sel == d.id)
                    x = 4
                    for i, fs in ipairs(r.cells) do
                        local c = cols[i]
                        local text, colour = cellText(d, c.key)
                        fs:ClearAllPoints()
                        fs:SetPoint("LEFT", x, 0)
                        fs:SetWidth(ws[i])
                        fs:SetJustifyH(i == 1 and "LEFT" or "RIGHT")
                        fs:SetText(text or "")
                        UI().Color(fs, colour or UI().INK)
                        x = x + ws[i] + GAP
                    end
                    y = y - ROW
                    if state.sel == d.id then
                        nDetail = nDetail + 1
                        local f = pool(v.details, nDetail, function() return makeDetail(child) end)
                        f:SetWidth(W)
                        f:ClearAllPoints()
                        f:SetPoint("TOPLEFT", 0, y)
                        fillDetail(f, breakdown(d, s.basis, v.data.ctx), W)
                        y = y - f:GetHeight() - 2
                    end
                end
            end
        end
        y = y - 3
    end
    for i = nHead + 1, #v.heads do v.heads[i]:Hide() end
    for i = nCol + 1, #v.colHeads do v.colHeads[i]:Hide() end
    for i = nRow + 1, #v.rows do v.rows[i]:Hide(); v.rows[i].data = nil end
    for i = nDetail + 1, #v.details do v.details[i]:Hide() end
    for i = nMsg + 1, #v.msgs do v.msgs[i]:Hide() end
    child:SetHeight(math.max(10, -y))
end

-- Builds the view in the guide's dark pane. inner: the pane's width less its padding; pad: that padding.
function P.BuildSellingView(parent, inner, pad)
    local v = CreateFrame("Frame", nil, parent)
    v:SetPoint("TOPLEFT", pad, -pad)
    v:SetPoint("BOTTOMRIGHT", -pad, pad)
    view = v
    P.sellingView = v
    v.width = inner - BAR
    v.sub = UI().Text(v, "GameFontHighlightSmall", "Recipes you know, with materials bought", UI().DIM)
    v.sub:SetPoint("TOPLEFT", 0, 0)
    v.sub:SetWidth(inner)
    v.none = UI().Text(v, "GameFontHighlightSmall", "", UI().DIM)
    v.none:SetPoint("TOPLEFT", 0, -22)
    v.none:SetWidth(inner)
    v.scroll = CreateFrame("ScrollFrame", nil, v, "UIPanelScrollFrameTemplate")
    v.scroll:SetPoint("TOPLEFT", 0, -18)
    v.scroll:SetPoint("BOTTOMRIGHT", -BAR, 18)
    v.child = CreateFrame("Frame", nil, v.scroll)
    v.child:SetSize(v.width, 10)
    v.scroll:SetScrollChild(v.child)
    v.heads, v.colHeads, v.rows, v.details, v.msgs = {}, {}, {}, {}, {}
    v.foot = UI().Text(v, "GameFontHighlightSmall", "", UI().DIM)
    v.foot:SetPoint("BOTTOMLEFT", 0, 0)
    v.footRight = UI().Text(v, "GameFontHighlightSmall", "", UI().DIM)
    v.footRight:SetPoint("BOTTOMRIGHT", 0, 0)
    v.footRight:SetJustifyH("RIGHT")
    v.subHit = CreateFrame("Frame", nil, v)
    v.subHit:SetPoint("TOPLEFT", v.sub)
    v.subHit:SetPoint("BOTTOMRIGHT", v.sub)
    tip(v.subHit, function(_, tt)
        tt:SetText("Selling guide", 1, 0.82, 0)
        tt:AddLine("Every recipe you know of this profession. Materials are bought: vendor materials at the vendor's price, the rest at the auction house. A material made by a recipe you know counts at its crafting cost only when nobody sells it.", 1, 1, 1, true)
        tt:AddLine("Auction house and Vendor show only what makes a profit. Waylaid Crates and Craftsman's Writs show every item you can make for them, profit or loss.", 1, 1, 1, true)
    end)
    v:Hide()
    return v
end

-- Fills the view for the profession on show (o from P:Open()).
function P.ShowSelling(o)
    local v = view
    if not v then return end
    local s = sdb()
    v.data = P.SellingRows(o.name, s.basis)
    local any = v.data.known > 0
    v.scroll:SetShown(any)
    v.none:SetShown(not any)
    if not any then
        v.none:SetText(("%s has no recipes you know that make an item."):format(o.shown or o.name))
    end
    v.sub:SetText(("%s recipes you know, with materials bought"):format(o.shown or o.name))
    if P.HasAuctionator() then
        v.foot:SetText(s.basis == "avg" and "Prices: Encore-Stonks 7-day average" or "Prices: last Auctionator scan")
    else
        v.foot:SetText("|cffff8040Auctionator not found: no auction prices|r")
    end
    local stonks = Encore and Encore.modules and Encore.modules.Stonks
    v.footRight:SetText(stonks and "" or "Encore-Stonks off: no 7-day average")
    layout()
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
