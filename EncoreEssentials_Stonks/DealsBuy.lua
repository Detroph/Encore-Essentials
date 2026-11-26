-- Encore-Stonks: the buy prompt of the Deals tab (Deals.lua). It opens on the Deals tab itself, so the auction
-- house stays on that tab (Det, 2026-11-26: like Auctionator's Shopping, without switching tabs).
--
-- For each item it runs a fresh search (the way Auctionator's Shopping tab does, so stale results don't end in
-- "item not found") and offers only listings still under the limit: below the vendor price, or at least the
-- chosen percentage under the market average. WoW lets an addon buy only on a real click, one purchase per click,
-- so the Buy button buys one listing (an item) or the whole qualifying amount (a commodity) per press.
--   * Items: C_AuctionHouse.PlaceBid(auctionID, buyout) on the listing found by the fresh search. Its price
--     can't change, so the limit is checked against that listing.
--   * Commodities: StartCommoditiesPurchase asks the server for the real price first. When the quote is above
--     what the search showed, or above the limit, the purchase is cancelled and the item searched again;
--     otherwise the button turns into Confirm, and only that click buys.
-- Listings sold in the meantime fail on the server and are skipped; nothing is spent on them.
local _, ns = ...
local Stonks = ns.Stonks
local U = ns.UI
local Deals = Stonks.Deals
if not Deals then return end

local safe = Deals.safe
local floor, max = math.floor, math.max
local coin, coinShort = U.coin, U.coinShort
local DIM = U.DIM
local ROW_H = 20
local SEARCH_TIMEOUT = 8

local B = { items = {}, phase = "idle" }
Deals.buy = B
local dlg, shade, list, titleText, capText, totText, msgText, buyButton
local events = CreateFrame("Frame")

local SORTS = {
    { sortOrder = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0, reverseSort = false },
    { sortOrder = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Buyout) or 4, reverseSort = false },
}

local EVENTS = {
    "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
    "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
    "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
}

local function under(item, price)
    if not item.limit then return false end
    if item.strict then return price < item.limit end
    return price <= item.limit
end

local function current() return B.items[B.index or 0] end

local function gainEach(item, unit)
    return (item.ref or 0) - unit
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local STATE_TEXT = {
    waiting = "|cff9a8a72Waiting|r", searching = "|cff9a8a72Searching...|r", ready = "",
    bought = "|cff7ad1ccBought|r", skipped = "|cffeb9339Sold already, skipped|r", over = "|cff9a8a72Not under the limit|r",
    none = "|cff9a8a72Nothing under the limit now|r", notfound = "|cffeb9339Not found|r", done = "|cff7ad1ccDone|r",
}

local function nextOffer(item)
    if not item or not item.offers then return nil end
    for _, o in ipairs(item.offers) do
        if o.state == "ready" then return o end
    end
end

-- Commodities are bought as one amount: every qualifying offer, cheapest first.
local function commodityAmount(item)
    local qty, total = 0, 0
    for _, o in ipairs(item.offers or {}) do
        if o.state == "ready" then qty, total = qty + o.qty, total + o.unit * o.qty end
    end
    return qty, total
end

local function displayRows()
    local rows = {}
    local cur = current()
    for _, item in ipairs(B.items) do
        if item == cur and item.offers and #item.offers > 0 then
            for _, o in ipairs(item.offers) do rows[#rows + 1] = { item = item, offer = o } end
        else
            rows[#rows + 1] = { item = item }
        end
    end
    for i, r in ipairs(rows) do r.index = i end
    return rows
end

local function initRow(btn)
    if btn.built then return end
    btn.built = true
    btn:SetHeight(ROW_H)
    btn.stripe = btn:CreateTexture(nil, "BACKGROUND")
    btn.stripe:SetAllPoints()
    btn.stripe:SetColorTexture(1, 1, 1, 0.03)
    btn.next = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    btn.next:SetAllPoints()
    btn.next:SetColorTexture(U.TEAL[1], U.TEAL[2], U.TEAL[3], 0.14)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(16, 16)
    btn.icon:SetPoint("LEFT", 4, 0)
    btn.name = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.name:SetPoint("LEFT", btn.icon, "RIGHT", 5, 0)
    btn.name:SetWidth(150)
    btn.name:SetJustifyH("LEFT")
    btn.name:SetWordWrap(false)
    local function cell(x, w)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH("RIGHT")
        fs:SetWordWrap(false)
        return fs
    end
    btn.qty = cell(176, 40)
    btn.each = cell(220, 70)
    btn.gain = cell(294, 66)
    btn.state = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.state:SetPoint("LEFT", 370, 0)
    btn.state:SetPoint("RIGHT", -4, 0)
    btn.state:SetJustifyH("LEFT")
    btn.state:SetWordWrap(false)
    U.tooltip(btn, function(tt, self)
        local item = self.data and self.data.item
        if not item then return end
        if item.link then tt:SetHyperlink(item.link) elseif item.itemID then tt:SetItemByID(item.itemID) else tt:SetText(item.name or "?") end
        tt:AddLine(" ")
        tt:AddDoubleLine(item.strict and "Buys below" or "Buys at or below", coin(item.limit) .. " each", 1, 0.82, 0, 1, 1, 1)
    end)
end

local function fillRow(btn, d)
    initRow(btn)
    btn.data = d
    local item, o = d.item, d.offer
    btn.stripe:SetShown(d.index % 2 == 0)
    local cur = current()
    local nxt = item == cur and o and (item.commodity and o.state == "ready" or o == nextOffer(item))
    btn.next:SetShown(nxt and true or false)
    btn.icon:SetTexture(item.icon or U.itemIcon(item.key))
    btn.name:SetText(item.name or "")
    local r, g, b = 1, 1, 1
    local q = item.quality
    if type(q) == "number" and q >= 0 and C_Item and C_Item.GetItemQualityColor then
        local ok, qr, qg, qb = pcall(C_Item.GetItemQualityColor, q)
        if ok and qr then r, g, b = qr, qg, qb end
    end
    btn.name:SetTextColor(r, g, b)
    local dimmed = o and (o.state == "bought" or o.state == "skipped" or o.state == "over")
    btn:SetAlpha(dimmed and 0.55 or 1)
    if o then
        btn.qty:SetText(tostring(o.qty))
        btn.each:SetText(coinShort(o.unit))
        local gain = gainEach(item, o.unit)
        btn.gain:SetText(gain > 0 and ("|cff7ad1cc" .. coinShort(gain) .. "|r") or "|cffeb9339-|r")
        btn.state:SetText(STATE_TEXT[o.state] or "")
    else
        btn.qty:SetText(item.boughtQty > 0 and tostring(item.boughtQty) or "")
        btn.each:SetText("")
        btn.gain:SetText(item.gained > 0 and ("|cff7ad1cc" .. coinShort(item.gained) .. "|r") or "")
        local st = item.state
        if st == "done" and item.boughtQty > 0 then
            btn.state:SetText(("|cff7ad1ccBought %d|r"):format(item.boughtQty))
        else
            btn.state:SetText(STATE_TEXT[st] or "")
        end
    end
end

local function setButton(text, enabled)
    buyButton:SetText(text)
    buyButton:SetEnabled(enabled and true or false)
end

local function redraw()
    if not dlg or not dlg:IsShown() then return end
    list:SetDataProvider(CreateDataProvider(displayRows()), ScrollBoxConstants.RetainScrollPosition)
    local spent, gained, bought = 0, 0, 0
    for _, item in ipairs(B.items) do
        spent, gained, bought = spent + item.spent, gained + item.gained, bought + item.boughtQty
    end
    totText:SetText(("Bought |cffffffff%d|r   Spent |cffffffff%s|r   %s |cff7ad1cc%s|r"):format(
        bought, coin(spent), B.mode == "vendor" and "Profit at vendor" or "Saved", coin(gained)))

    local item = current()
    local phase = B.phase
    if phase == "done" or not item then
        setButton("Nothing left to buy", false)
    elseif phase == "searching" then
        setButton("Searching...", false)
    elseif phase == "quote" then
        setButton("Checking price...", false)
    elseif phase == "buying" then
        setButton("Buying...", false)
    elseif phase == "retry" then
        setButton("Search again", true)
    elseif phase == "confirm" then
        setButton(("Confirm %d for %s"):format(B.quote.qty, coin(B.quote.total)), B.quote.total <= GetMoney())
    elseif item.commodity then
        local qty, total = commodityAmount(item)
        if qty == 0 then setButton("Nothing left to buy", false)
        elseif total > GetMoney() then setButton("Not enough gold", false)
        else setButton(("Buy %d for %s"):format(qty, coin(total)), true) end
    else
        local o = nextOffer(item)
        if not o then setButton("Nothing left to buy", false)
        elseif o.total > GetMoney() then setButton("Not enough gold", false)
        else setButton(("Buy %d for %s"):format(o.qty, coin(o.total)), true) end
    end
end

local function message(text) if msgText then msgText:SetText(text or "") end end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------
local advance -- forward

local function ready()
    return not (C_AuctionHouse.IsThrottledMessageSystemReady) or C_AuctionHouse.IsThrottledMessageSystemReady()
end

local timeoutTimer
local function send(fn)
    B.pending = fn
    if ready() then B.pending = nil; fn() end
    if timeoutTimer then timeoutTimer:Cancel() end
    local token = {}
    B.searchToken = token
    timeoutTimer = C_Timer.NewTimer(SEARCH_TIMEOUT, safe(function()
        if B.searchToken == token and B.phase == "searching" then
            B.phase = "retry"
            message("The auction house didn't answer. Press Search again.")
            redraw()
        end
    end))
end

local function searchKey(item, itemKey)
    item.lastKey = itemKey
    send(function() C_AuctionHouse.SendSearchQuery(itemKey, SORTS, true) end)
end

local function search(item, itemKey)
    item.state, item.offers = "searching", nil
    B.phase = "searching"
    searchKey(item, itemKey or item.lastKey or C_AuctionHouse.MakeItemKey(item.itemID))
    redraw()
end

-- Gear with random suffixes may need the exact item key: look the name up like the Buy tab does and search each
-- matching result.
local function browseForKeys(item)
    if item.browsed or not C_AuctionHouse.SendBrowseQuery or not item.baseName then return false end
    item.browsed = true
    B.phase = "searching"
    send(function()
        C_AuctionHouse.SendBrowseQuery({ searchString = item.baseName, sorts = {}, filters = {}, itemClassFilters = {} })
    end)
    return true
end

local function offersFromCommodity(item)
    local offers = {}
    local id = item.itemID
    for i = 1, (C_AuctionHouse.GetNumCommoditySearchResults(id) or 0) do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
        if r and r.unitPrice and r.quantity and r.quantity > 0 then
            local ok = under(item, r.unitPrice) and not r.containsOwnerItem
            offers[#offers + 1] = { qty = r.quantity, unit = r.unitPrice, total = r.unitPrice * r.quantity, state = ok and "ready" or "over" }
            if not ok then break end -- sorted by price: one row shows where the limit ends
        end
    end
    return offers
end

local function offersFromItems(item, itemKey)
    local offers = {}
    for i = 1, (C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0) do
        local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if r and r.buyoutAmount and r.buyoutAmount > 0 and (r.quantity or 0) > 0 then
            local unit = r.buyoutAmount / r.quantity
            local own = r.containsOwnerItem or r.containsAccountItem
            local ok = under(item, unit) and not own
            offers[#offers + 1] = { qty = r.quantity, unit = unit, total = r.buyoutAmount, auctionID = r.auctionID, state = ok and "ready" or "over" }
        end
    end
    table.sort(offers, function(a, b) return a.unit < b.unit end)
    -- keep the qualifying ones and the first one over the limit
    local out, shownOver = {}, false
    for _, o in ipairs(offers) do
        if o.state == "ready" then out[#out + 1] = o
        elseif not shownOver then out[#out + 1] = o; shownOver = true end
    end
    return out
end

-- Nothing (more) to buy under this item key: the next key of a random-suffix item, or the next item.
local function exhausted(item)
    if item.keyQueue and #item.keyQueue > 0 then
        search(item, table.remove(item.keyQueue, 1))
        return
    end
    item.state = item.boughtQty > 0 and "done" or "none"
    advance()
end

local function gotOffers(item, offers)
    item.offers = offers
    if timeoutTimer then timeoutTimer:Cancel(); timeoutTimer = nil end
    if nextOffer(item) then
        item.state = "ready"
        B.phase = "ready"
        redraw()
    else
        exhausted(item)
    end
end

---------------------------------------------------------------------------
-- Moving through the items
---------------------------------------------------------------------------
advance = function()
    local item = current()
    if item and item.state ~= "done" and item.state ~= "none" and item.state ~= "notfound" then
        item.state = "done"
    end
    if item then item.offers = nil end
    B.index = (B.index or 0) + 1
    local nxt = current()
    if not nxt then
        B.phase = "done"
        local any = false
        for _, it in ipairs(B.items) do if it.boughtQty > 0 then any = true end end
        message(any and "All done." or "Nothing left under the limit.")
        redraw()
        return
    end
    search(nxt)
end

local function record(item, qty, total)
    item.boughtQty = item.boughtQty + qty
    item.spent = item.spent + total
    item.gained = item.gained + max(0, (item.ref or 0) * qty - total)
end

---------------------------------------------------------------------------
-- Buy button
---------------------------------------------------------------------------
local function onBuy()
    local item = current()
    if not item then return end
    if B.phase == "retry" then search(item); return end
    if B.phase == "confirm" then
        local q = B.quote
        B.phase = "buying"
        C_AuctionHouse.ConfirmCommoditiesPurchase(q.itemID, q.qty)
        redraw()
        return
    end
    if B.phase ~= "ready" then return end
    if item.commodity then
        local qty, total = commodityAmount(item)
        if qty == 0 then return end
        B.quote = { itemID = item.itemID, qty = qty, expected = total }
        B.phase = "quote"
        C_AuctionHouse.StartCommoditiesPurchase(item.itemID, qty)
        message("")
    else
        local o = nextOffer(item)
        if not o then return end
        if not under(item, o.unit) then o.state = "over"; redraw(); return end
        B.buying = o
        B.phase = "buying"
        C_AuctionHouse.PlaceBid(o.auctionID, o.total)
        message("")
    end
    redraw()
end

local function cancelQuote()
    if B.phase == "quote" or B.phase == "confirm" then
        pcall(C_AuctionHouse.CancelCommoditiesPurchase)
    end
    B.quote = nil
end

---------------------------------------------------------------------------
-- Auction house events
---------------------------------------------------------------------------
events:SetScript("OnEvent", safe(function(_, event, a1, a2)
    if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if B.pending then local fn = B.pending; B.pending = nil; fn() end
        return
    end
    local item = current()
    if not item then return end
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        if B.phase == "searching" and a1 == item.itemID then
            item.commodity = true
            gotOffers(item, offersFromCommodity(item))
        end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        if B.phase == "searching" and type(a1) == "table" and a1.itemID == item.itemID then
            item.commodity = false
            local offers = offersFromItems(item, a1)
            if #offers == 0 and C_AuctionHouse.GetNumItemSearchResults(a1) == 0 then
                -- nothing under this key: try the keys a name search finds (random-suffix gear)
                if item.keyQueue and #item.keyQueue > 0 then
                    search(item, table.remove(item.keyQueue, 1))
                    return
                elseif browseForKeys(item) then
                    return
                end
                item.state = item.boughtQty > 0 and "done" or "notfound"
                advance()
                return
            end
            gotOffers(item, offers)
        end
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        if B.phase == "searching" and item.browsed and not item.keyQueue then
            item.keyQueue = {}
            for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
                if r.itemKey and r.itemKey.itemID == item.itemID then item.keyQueue[#item.keyQueue + 1] = r.itemKey end
            end
            if #item.keyQueue > 0 then
                search(item, table.remove(item.keyQueue, 1))
            else
                item.state = item.boughtQty > 0 and "done" or "notfound"
                advance()
            end
        end
    elseif event == "COMMODITY_PRICE_UPDATED" then
        local q = B.quote
        if B.phase ~= "quote" or not q then return end
        local unitPrice, total = a1, a2
        if total and total <= q.expected and unitPrice and under(item, unitPrice) then
            q.total = total
            B.phase = "confirm"
            message(("Price checked: %s for %d (%s each)."):format(coin(total), q.qty, coin(unitPrice)))
        else
            pcall(C_AuctionHouse.CancelCommoditiesPurchase)
            B.quote = nil
            message(("|cffeb9339The price went up to %s. Searching again.|r"):format(coin(total)))
            search(item)
            return
        end
        redraw()
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        if B.phase ~= "quote" then return end
        cancelQuote()
        message("|cffeb9339Those listings are gone. Searching again.|r")
        search(item)
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        local q = B.quote
        if B.phase ~= "buying" or not q then return end
        record(item, q.qty, q.total or q.expected)
        message(("Bought %d %s for %s."):format(q.qty, item.name or "", coin(q.total or q.expected)))
        B.quote = nil
        search(item) -- more may have been listed under the limit
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        if B.phase ~= "buying" then return end
        B.quote = nil
        message("|cffeb9339That purchase failed. Searching again.|r")
        search(item)
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        local o = B.buying
        if B.phase ~= "buying" or not o or (a1 and o.auctionID and a1 ~= o.auctionID) then return end
        o.state = "bought"
        B.buying = nil
        record(item, o.qty, o.total)
        message(("Bought %d %s for %s."):format(o.qty, item.name or "", coin(o.total)))
        if nextOffer(item) then B.phase = "ready"; redraw() else exhausted(item) end
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
        if B.phase == "buying" and B.buying then
            B.buying.state = "skipped"
            B.buying = nil
            message("|cffeb9339That listing sold before the buy went through. Skipped, nothing spent.|r")
            if nextOffer(item) then B.phase = "ready"; redraw() else search(item) end
        elseif B.phase == "buying" and B.quote then
            B.quote = nil
            search(item)
        end
    end
end))

local function listen(on)
    for _, e in ipairs(EVENTS) do
        if on then pcall(events.RegisterEvent, events, e) else pcall(events.UnregisterEvent, events, e) end
    end
end

---------------------------------------------------------------------------
-- The prompt
---------------------------------------------------------------------------
local function build()
    local tab = Deals.tab
    shade = CreateFrame("Frame", nil, tab)
    shade:SetAllPoints(tab)
    shade:SetFrameLevel(tab:GetFrameLevel() + 60)
    shade:EnableMouse(true)
    local bg = shade:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    shade:SetScript("OnMouseDown", function() Deals.CloseBuy() end)
    shade:Hide()

    dlg = CreateFrame("Frame", "EncoreStonksDealsBuy", tab)
    dlg:SetSize(520, 330)
    dlg:SetPoint("CENTER", tab, "CENTER", 0, 6)
    dlg:SetFrameLevel(shade:GetFrameLevel() + 5)
    dlg:EnableMouse(true)
    local UI = _G.EncoreEssentials and _G.EncoreEssentials.UI
    if UI and UI.Panel then UI.Panel(dlg, 0.98) else
        local t = dlg:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints(); t:SetColorTexture(0.08, 0.06, 0.04, 0.98)
    end
    titleText = dlg:CreateFontString(nil, "OVERLAY")
    if UI and UI.TitleFont then UI.TitleFont(titleText, 15) else titleText:SetFontObject("GameFontNormalLarge") end
    titleText:SetPoint("TOPLEFT", 12, -10)
    titleText:SetPoint("RIGHT", -34, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    local close = CreateFrame("Button", nil, dlg, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() Deals.CloseBuy() end)

    capText = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    capText:SetPoint("TOPLEFT", 12, -34)
    capText:SetPoint("RIGHT", -12, 0)
    capText:SetJustifyH("LEFT")

    local well = U.well(dlg)
    well:SetPoint("TOPLEFT", 10, -52)
    well:SetPoint("TOPRIGHT", -10, -52)
    well:SetHeight(176)
    local head = CreateFrame("Frame", nil, well)
    head:SetPoint("TOPLEFT", 3, -3)
    head:SetPoint("TOPRIGHT", -3, -3)
    head:SetHeight(18)
    local hbg = head:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    U.gradient(hbg, "VERTICAL", 0.09, 0.06, 0.04, 1, 0.17, 0.13, 0.09, 1)
    local function headText(text, x, w, justify)
        local fs = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH(justify or "RIGHT")
        fs:SetText(text)
        return fs
    end
    headText("Item", 6, 150, "LEFT")
    headText("Qty", 176, 40)
    headText("Each", 220, 70)
    dlg.gainHead = headText("Profit each", 294, 66)
    headText("", 370, 100, "LEFT")

    -- header stays put; only the rows scroll
    local box = CreateFrame("Frame", nil, well, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", 3, -23)
    box:SetPoint("BOTTOMRIGHT", -15, 3)
    local bar = CreateFrame("EventFrame", nil, well, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 3, -2)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 3, 2)
    bar:SetHideIfUnscrollable(true)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("EncoreStonksDealBuyRowTemplate", fillRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    list = box

    totText = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    totText:SetPoint("TOPLEFT", well, "BOTTOMLEFT", 2, -8)
    U.setColor(totText, DIM)
    msgText = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    msgText:SetPoint("TOPLEFT", totText, "BOTTOMLEFT", 0, -6)
    msgText:SetPoint("RIGHT", dlg, "RIGHT", -12, 0)
    msgText:SetJustifyH("LEFT")

    buyButton = _G.EncoreEssentials.UI.Button(dlg)
    buyButton:SetSize(210, 26)
    buyButton:SetPoint("BOTTOMRIGHT", -12, 12)
    buyButton:SetScript("OnClick", safe(onBuy))
    local closeButton = _G.EncoreEssentials.UI.Button(dlg)
    closeButton:SetSize(80, 26)
    closeButton:SetPoint("RIGHT", buyButton, "LEFT", -8, 0)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function() Deals.CloseBuy() end)
    local hint = dlg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 12, 14)
    hint:SetPoint("RIGHT", closeButton, "LEFT", -10, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("One purchase per click. Prices are checked again right before each buy; anything at or above the limit is skipped.")

    dlg:SetScript("OnHide", function() shade:Hide() end)
    dlg:Hide()
end

function Deals.CloseBuy()
    if not dlg then return end
    cancelQuote()
    if timeoutTimer then timeoutTimer:Cancel(); timeoutTimer = nil end
    listen(false)
    B.phase, B.items, B.index, B.pending, B.buying = "idle", {}, nil, nil, nil
    dlg:Hide()
    shade:Hide()
end

-- rows: Deals tab rows (several per item when it is listed at several prices). mode: "vendor" or "market".
function Deals.OpenBuy(rows, mode)
    if not (Deals.tab and C_AuctionHouse) then return end
    if not dlg then build() end
    Deals.CloseBuy()
    local s = Deals.Settings()
    local byKey, items = {}, {}
    for _, row in ipairs(rows) do
        local limit, strict = Deals.Limit(row, mode)
        if limit and limit > 0 then
            local it = byKey[row.key]
            if not it then
                local ref = mode == "vendor" and row.vendor or (row.avg and row.avg[s.avg])
                it = {
                    key = row.key, itemID = row.itemID, link = row.link, name = row.name, icon = row.icon,
                    quality = row.quality, limit = limit, strict = strict, ref = ref, rank = 0,
                    boughtQty = 0, spent = 0, gained = 0, state = "waiting",
                    baseName = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(row.itemID) or nil,
                }
                byKey[row.key] = it
                items[#items + 1] = it
            end
            it.rank = it.rank + max(0, (it.ref or 0) - row.unit) * row.qty
        end
    end
    if #items == 0 then return end
    table.sort(items, function(a, b) return a.rank > b.rank end)
    B.items, B.mode, B.index = items, mode, 0

    if #items == 1 then
        titleText:SetText("Buy " .. (items[1].name or "?"))
        if mode == "vendor" then
            capText:SetText(("Limit: below the vendor price of %s each."):format(coin(items[1].limit)))
        else
            capText:SetText(("Limit: at least %d%% under the %d-day average, so up to %s each."):format(s.pct, s.avg, coin(items[1].limit)))
        end
    else
        titleText:SetText(("Buy all under vendor price (%d items)"):format(#items))
        capText:SetText("Limit: below each item's vendor price. Items are searched one after the other.")
    end
    dlg.gainHead:SetText(mode == "vendor" and "Profit each" or "Saving each")
    message("")
    listen(true)
    shade:Show()
    dlg:Show()
    advance()
end
