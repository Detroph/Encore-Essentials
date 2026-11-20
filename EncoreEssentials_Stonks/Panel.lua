-- Encore-Stonks graph panel: a separate window that shows the selected item's price history.
-- It docks to the right of the auction house (or of the Stonks browser) and follows the item selected in the
-- auction house (Browse and Auctions tabs), Auctionator (Shopping and Selling) or the Stonks browser.
-- Modes: Trend (price over time with a 3/7/14-day moving average), By weekday, By hour; a shopping list shows
-- its items with their trend.
local _, ns = ...
local Stonks = ns.Stonks
local U = ns.UI

local TEAL, TEAL_SOFT, COPPER, GOLD, INK, DIM, GRID, WHITE = U.TEAL, U.TEAL_SOFT, U.COPPER, U.GOLD, U.INK, U.DIM, U.GRID, U.WHITE
local setColor, gradient, coin, coinShort, pctText = U.setColor, U.gradient, U.coin, U.coinShort, U.pctText
local itemName, itemIcon, itemQualityColor, linkFor = U.itemName, U.itemIcon, U.itemQualityColor, U.linkFor

local WEEKDAYS = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
local WEEKDAYS_SHORT = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local MODES = { { "time", "Trend", 62 }, { "week", "By weekday", 84 }, { "hour", "By hour", 66 } }
local AVERAGES = { 3, 7, 14 }
local RANGE_OPTIONS = { { 7, "Last 7 days" }, { 14, "Last 14 days" }, { 30, "Last 30 days" }, { 0, "Everything" } }
local MARKET = "__market"
local EMPTY_TEXT = "Select an item or a shopping list to display historic data."

local frame, chart, header, listBox, listHead, backButton
local modeButtons, avgButtons = {}, {}
local render, applyPage, createTabs
local PAGES = {
    { "graphs", "Graphs", 58, "Price history of the selected item, shopping list or the whole market." },
    { "history", "History", 58, "Sync history: when and from whom you received guild scans, login summaries and shared items or scans." },
}
local pageTabs, pages = {}, {}

local state = {
    view = nil,    -- nil (nothing selected), "item", "list" or "market"
    key = nil,     -- item key
    list = nil,    -- shopping list name
    fromList = nil,
    tab = "time",
    page = "graphs", -- title-bar tab: "graphs" or "history"
    avg = 7,       -- moving average shown on the trend (3, 7, 14 or nil)
    range = 0,
}

local function settings()
    local s = Stonks:Settings()
    if type(s.panel) ~= "table" then s.panel = {} end
    return s.panel
end

-- Shopping list column sort, saved with the panel settings. Default: by name.
local function listSort()
    local p = settings()
    if type(p.listSort) ~= "table" or not p.listSort.id then p.listSort = { id = "name", desc = false } end
    return p.listSort
end

local pools = { tex = {}, line = {}, text = {} }
local used = { tex = 0, line = 0, text = 0 }

local function resetPools()
    for kind, pool in pairs(pools) do
        for _, obj in ipairs(pool) do obj:Hide() end
        used[kind] = 0
    end
end

local function tex(layer, sub)
    used.tex = used.tex + 1
    local t = pools.tex[used.tex]
    if not t then
        t = chart.canvas:CreateTexture(nil, "ARTWORK")
        pools.tex[used.tex] = t
    end
    t:SetDrawLayer(layer or "ARTWORK", sub or 0)
    t:ClearAllPoints()
    t:SetRotation(0)
    t:SetGradient("VERTICAL", WHITE, WHITE) -- clear a gradient left by an earlier bar
    t:Show()
    return t
end

local function line(x1, y1, x2, y2, c, thickness, layer)
    used.line = used.line + 1
    local l = pools.line[used.line]
    if not l then
        l = chart.canvas:CreateLine(nil, "ARTWORK")
        pools.line[used.line] = l
    end
    l:SetDrawLayer(layer or "ARTWORK", 1)
    l:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    l:SetThickness(thickness or 1)
    l:SetStartPoint("BOTTOMLEFT", chart.canvas, x1, y1)
    l:SetEndPoint("BOTTOMLEFT", chart.canvas, x2, y2)
    l:Show()
    return l
end

local function text(str, x, y, point, c, font)
    used.text = used.text + 1
    local f = pools.text[used.text]
    if not f then
        f = chart.canvas:CreateFontString(nil, "OVERLAY")
        pools.text[used.text] = f
    end
    f:SetFontObject(font or "GameFontHighlightSmall")
    f:ClearAllPoints()
    f:SetPoint(point or "CENTER", chart.canvas, "BOTTOMLEFT", x, y)
    f:SetText(str)
    setColor(f, c or DIM)
    f:Show()
    return f
end

local function rect(x, y, w, h, c, layer)
    local t = tex(layer or "ARTWORK")
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    t:SetPoint("BOTTOMLEFT", chart.canvas, "BOTTOMLEFT", x, y)
    t:SetSize(math.max(1, w), math.max(1, h))
    return t
end

local function dot(x, y, size, c)
    local t = tex("OVERLAY", 2)
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    t:SetSize(size, size)
    t:SetPoint("CENTER", chart.canvas, "BOTTOMLEFT", x, y)
    t:SetRotation(math.rad(45))
    return t
end

local function message(str)
    chart.message:SetText(str)
    chart.message:Show()
end

-- Hover handling: hits = array of { x1, x2, tooltip = function(tt) end, mark = function() end }
local hits, hoverIndex = {}, nil
local function setHits(h)
    hits, hoverIndex = h or {}, nil
    chart.guide:Hide()
end

local function onCanvasUpdate(self)
    if not self:IsMouseOver() or #hits == 0 then
        if hoverIndex then
            hoverIndex = nil
            chart.guide:Hide()
            chart.marker:Hide()
            GameTooltip:Hide()
        end
        return
    end
    local x = GetCursorPosition() / self:GetEffectiveScale() - self:GetLeft()
    local best
    for i, h in ipairs(hits) do
        if x >= h.x1 and x <= h.x2 then best = i break end
    end
    if best == hoverIndex then return end
    hoverIndex = best
    if not best then
        chart.guide:Hide()
        chart.marker:Hide()
        GameTooltip:Hide()
        return
    end
    local h = hits[best]
    chart.guide:ClearAllPoints()
    chart.guide:SetPoint("BOTTOM", self, "BOTTOMLEFT", h.cx or (h.x1 + h.x2) / 2, chart.plot.bottom)
    chart.guide:SetHeight(chart.plot.top - chart.plot.bottom)
    chart.guide:Show()
    if h.my then
        chart.marker:ClearAllPoints()
        chart.marker:SetPoint("CENTER", self, "BOTTOMLEFT", h.cx, h.my)
        chart.marker:Show()
    else
        chart.marker:Hide()
    end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    h.tooltip(GameTooltip)
    GameTooltip:Show()
end

local function plotArea()
    local w, h = chart.canvas:GetWidth(), chart.canvas:GetHeight()
    local p = { left = 74, right = w - 16, bottom = 34, top = h - 12 }
    p.w, p.h = p.right - p.left, p.top - p.bottom
    chart.plot = p
    return p
end

local function rangeStart()
    if state.range and state.range > 0 then return time() - state.range * 86400 end
    return 0
end

local function filterRange(points)
    local from = rangeStart()
    if from == 0 then return points end
    local out = {}
    for _, pt in ipairs(points) do
        if pt.t >= from then out[#out + 1] = pt end
    end
    return out
end


---------------------------------------------------------------------------
-- Price over time
---------------------------------------------------------------------------
local function niceSteps(lo, hi, count)
    local span = hi - lo
    if span <= 0 then span = math.max(1, hi * 0.1) end
    local raw = span / count
    local mag = 10 ^ math.floor(math.log10(raw))
    local step = mag
    for _, m in ipairs({ 1, 2, 2.5, 5, 10 }) do
        if raw <= m * mag then step = m * mag break end
    end
    local first = math.floor(lo / step) * step
    local last = math.ceil(hi / step) * step
    return first, last, step
end

local function drawTimeline(points, profile, history)
    local p = plotArea()
    if #points == 0 then
        setHits(nil)
        return message("No prices in this range yet. Scan the auction house with Auctionator and they appear here.")
    end
    local tMin, tMax = points[1].t, points[#points].t
    if tMax - tMin < 6 * 3600 then tMin, tMax = tMin - 3 * 3600, tMax + 3 * 3600 end
    local pMin, pMax, qMax = math.huge, 0, 0
    for _, pt in ipairs(points) do
        pMin, pMax = math.min(pMin, pt.p), math.max(pMax, pt.p)
        if pt.q and pt.q > qMax then qMax = pt.q end
    end
    local lo, hi, step = niceSteps(pMin * 0.95, pMax * 1.05, 4)
    lo = math.max(0, lo)
    local function X(t) return p.left + (t - tMin) / (tMax - tMin) * p.w end
    local function Y(v) return p.bottom + (v - lo) / (hi - lo) * p.h end

    -- Grid and price labels
    for v = lo, hi + step / 2, step do
        local y = Y(v)
        line(p.left, y, p.right, y, GRID, 1, "BACKGROUND")
        text(coinShort(v), p.left - 6, y, "RIGHT")
    end
    -- Day labels: about one per 90 px
    local days = math.max(1, (tMax - tMin) / 86400)
    local every = math.max(1, math.ceil(days / math.max(1, p.w / 90)))
    local d0 = date("*t", tMin)
    local t = time({ year = d0.year, month = d0.month, day = d0.day, hour = 0 }) + 86400
    local n = 0
    while t < tMax do
        if n % every == 0 then
            local x = X(t)
            line(x, p.bottom, x, p.top, GRID, 1, "BACKGROUND")
            text(WEEKDAYS_SHORT[Stonks.WeekdayIndex(t)] .. " " .. date("%d", t), x, p.bottom - 12, "CENTER")
        end
        n = n + 1
        t = t + 86400
    end

    -- Units on sale: faint bars along the bottom fifth
    if qMax > 0 then
        local bw = math.max(2, math.min(10, p.w / #points * 0.6))
        for _, pt in ipairs(points) do
            if pt.q and pt.q > 0 then
                rect(X(pt.t) - bw / 2, p.bottom, bw, pt.q / qMax * p.h * 0.2, { TEAL[1], TEAL[2], TEAL[3], 0.18 }, "BORDER")
            end
        end
    end

    -- Normal price
    if profile.normal then
        local y = Y(profile.normal)
        for x = p.left, p.right - 6, 12 do line(x, y, math.min(x + 6, p.right), y, { GOLD[1], GOLD[2], GOLD[3], 0.45 }, 1) end
        text("normal", p.right - 2, y + 8, "RIGHT", GOLD)
    end

    -- Price line and points (teal: Stonks' own samples, copper: Auctionator's daily lows)
    local prev
    for _, pt in ipairs(points) do
        local x, y = X(pt.t), Y(pt.p)
        if prev then line(prev[1], prev[2], x, y, { TEAL[1], TEAL[2], TEAL[3], 0.85 }, 2) end
        prev = { x, y }
        dot(x, y, 5, pt.src == "s" and TEAL_SOFT or COPPER)
    end

    -- Moving average chosen with the 3/7/14 day buttons, worked out over the whole history
    local avgLine
    if state.avg and history then
        avgLine = {}
        local prev
        for _, e in ipairs(Stonks.MovingAverage(history, state.avg)) do
            if e.t >= tMin and e.t <= tMax then
                local x, y = X(e.t), Y(e.v)
                if prev then line(prev[1], prev[2], x, y, { GOLD[1], GOLD[2], GOLD[3], 0.9 }, 2, "OVERLAY") end
                prev = { x, y }
            end
            avgLine[#avgLine + 1] = e
        end
    end
    local function averageAt(t)
        if not avgLine then return nil end
        local v
        for _, e in ipairs(avgLine) do
            if e.t <= t + 43200 then v = e.v else break end
        end
        return v
    end

    -- Hover: nearest point
    local h = {}
    for i, pt in ipairs(points) do
        local x = X(pt.t)
        local left = i > 1 and (X(points[i - 1].t) + x) / 2 or p.left
        local right = i < #points and (X(points[i + 1].t) + x) / 2 or p.right
        h[#h + 1] = {
            x1 = left, x2 = right, cx = x, my = Y(pt.p),
            tooltip = function(tt)
                if pt.src == "s" then
                    tt:SetText(WEEKDAYS[Stonks.WeekdayIndex(pt.t)] .. date(" %d %b, %H:00", pt.t))
                else
                    tt:SetText(WEEKDAYS[Stonks.WeekdayIndex(pt.t)] .. date(" %d %b", pt.t))
                end
                tt:AddDoubleLine("Lowest buyout", coin(pt.p), 1, 1, 1, 1, 1, 1)
                if pt.q then tt:AddDoubleLine("Units on sale", tostring(pt.q), 1, 1, 1, 1, 1, 1) end
                if profile.normal then
                    tt:AddDoubleLine("Vs normal", pctText((pt.p / profile.normal - 1) * 100), 1, 1, 1, 1, 1, 1)
                end
                local avg = averageAt(pt.t)
                if avg then tt:AddDoubleLine(state.avg .. "-day average", coin(avg), GOLD[1], GOLD[2], GOLD[3], 1, 1, 1) end
                if pt.src == "a" then
                    tt:AddLine("Auctionator's lowest price that day (no time of day).", DIM[1], DIM[2], DIM[3], true)
                end
            end,
        }
    end
    setHits(h)
end

---------------------------------------------------------------------------
-- Weekday and hour bars
---------------------------------------------------------------------------
local function drawBars(buckets, first, count, labels, profile, isMarket, describe)
    local p = plotArea()
    local maxAbs, any = 5, false
    for i = first, first + count - 1 do
        local pct = Stonks.BucketValue(buckets[i], profile.normal)
        if pct then
            any = true
            maxAbs = math.max(maxAbs, math.abs(pct))
        end
    end
    if not any then
        setHits(nil)
        if describe == "hour" then
            return message("No hourly prices yet. Stonks records the hour of each Auctionator scan from now on; scan at different times of day to fill this in.")
        end
        return message("Not enough prices yet. Each scan on a new day adds to this chart.")
    end
    -- Item charts use a gold axis (each bar is the typical price at that time, labelled with its % vs normal);
    -- the whole market mixes items of every price, so it stays in percent.
    local gold = not isMarket and profile.normal
    local Y, base
    if gold then
        local lo, hi = profile.normal, profile.normal
        for i = first, first + count - 1 do
            local _, price = Stonks.BucketValue(buckets[i], profile.normal)
            if price then lo, hi = math.min(lo, price), math.max(hi, price) end
        end
        local step
        lo, hi, step = niceSteps(lo * 0.96, hi * 1.04, 4)
        lo = math.max(0, lo)
        Y = function(v) return p.bottom + (v - lo) / (hi - lo) * p.h end
        base = p.bottom
        for v = lo, hi + step / 2, step do
            local y = Y(v)
            line(p.left, y, p.right, y, GRID, 1, "BACKGROUND")
            text(coinShort(v), p.left - 6, y, "RIGHT")
        end
        local ny = Y(profile.normal)
        for x = p.left, p.right - 6, 12 do line(x, ny, math.min(x + 6, p.right), ny, { GOLD[1], GOLD[2], GOLD[3], 0.55 }, 1, "OVERLAY") end
        text("normal " .. coinShort(profile.normal), p.right - 2, ny + 8, "RIGHT", GOLD)
    else
        maxAbs = math.ceil(maxAbs / 5) * 5
        local mid = p.bottom + p.h / 2
        local scale = (p.h / 2) / maxAbs
        Y = function(pct) return mid + pct * scale end
        base = mid
        for _, v in ipairs({ -maxAbs, -maxAbs / 2, 0, maxAbs / 2, maxAbs }) do
            local y = Y(v)
            line(p.left, y, p.right, y, v == 0 and { GOLD[1], GOLD[2], GOLD[3], 0.5 } or GRID, 1, "BACKGROUND")
            text(v == 0 and "normal" or ("%+g%%"):format(v), p.left - 6, y, "RIGHT", v == 0 and GOLD or DIM)
        end
        text("pricier", p.left + 4, p.top - 4, "TOPLEFT", COPPER)
        text("cheaper", p.left + 4, p.bottom + 4, "BOTTOMLEFT", TEAL_SOFT)
    end

    local slot = p.w / count
    local bw = math.max(4, math.min(48, slot * 0.62))
    local labelEvery = (slot < 22) and 3 or 1
    local h = {}
    local maxN = 1
    for i = first, first + count - 1 do maxN = math.max(maxN, buckets[i].n) end
    for idx = 0, count - 1 do
        local key = first + idx
        local b = buckets[key]
        local cx = p.left + slot * (idx + 0.5)
        local pct, price = Stonks.BucketValue(b, profile.normal)
        if idx % labelEvery == 0 then text(labels[key], cx, p.bottom - 12, "CENTER") end
        if pct then
            local c = pct >= 0 and COPPER or TEAL
            local alpha = 0.45 + 0.55 * math.min(1, b.n / math.max(3, maxN * 0.5)) -- thin data is drawn fainter
            local y1 = gold and Y(price) or Y(pct)
            local bottom, height = math.min(base, y1), math.abs(y1 - base)
            local bar = rect(cx - bw / 2, bottom, bw, math.max(1, height), { c[1], c[2], c[3], alpha })
            if y1 >= base then
                gradient(bar, "VERTICAL", c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, alpha, c[1], c[2], c[3], alpha)
            else
                gradient(bar, "VERTICAL", c[1], c[2], c[3], alpha, c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, alpha)
            end
            if slot >= 24 then
                local above = gold or pct >= 0
                text(pctText(pct), cx, above and (math.max(y1, base) + 8) or (y1 - 8), "CENTER", pct >= 0 and COPPER or TEAL_SOFT)
            end
        else
            rect(cx - bw / 2, base - 1, bw, 2, { DIM[1], DIM[2], DIM[3], 0.35 })
        end
        h[#h + 1] = {
            x1 = cx - slot / 2, x2 = cx + slot / 2, cx = cx,
            tooltip = function(tt)
                if describe == "hour" then
                    tt:SetText(("%02d:00 - %02d:59"):format(key, key))
                else
                    tt:SetText(WEEKDAYS[key])
                end
                if not pct then
                    tt:AddLine("No prices recorded here yet.", 1, 1, 1)
                    return
                end
                tt:AddDoubleLine("Vs normal", pctText(pct), 1, 1, 1, 1, 1, 1)
                if not isMarket and price then
                    tt:AddDoubleLine("Typical price", coin(price), 1, 1, 1, 1, 1, 1)
                    tt:AddDoubleLine("Normal price", coin(profile.normal), DIM[1], DIM[2], DIM[3], DIM[1], DIM[2], DIM[3])
                end
                local unit = isMarket and "items" or (describe == "hour" and "samples" or "days")
                tt:AddDoubleLine("Based on", b.n .. " " .. unit, DIM[1], DIM[2], DIM[3], DIM[1], DIM[2], DIM[3])
                if not isMarket and b.n < 3 then
                    tt:AddLine("Few samples: treat this as a hint.", DIM[1], DIM[2], DIM[3], true)
                end
            end,
        }
    end
    setHits(h)
end


local HOUR_LABELS, HOUR_NAMES = {}, {}
for i = 0, 23 do
    HOUR_LABELS[i] = ("%02d"):format(i)
    HOUR_NAMES[i] = ("%02d:00"):format(i)
end

---------------------------------------------------------------------------
-- Shopping list view: the list's items that Stonks has prices for, with their trend.
---------------------------------------------------------------------------
local function initListRow(row)
    if row.built then return end
    row.built = true
    row:SetHeight(24)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.9, 0.6, 0.08)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 4, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", -190, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.last = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.last:SetPoint("RIGHT", -120, 0)
    row.avg = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.avg:SetPoint("RIGHT", -50, 0)
    row.trend = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.trend:SetPoint("RIGHT", -6, 0)
    row:SetScript("OnClick", function(self)
        if self.key then Stonks:ShowItem(self.key, { fromList = state.list }) end
    end)
    U.tooltip(row, function(tt, self)
        local link = self.key and linkFor(self.key)
        if link then tt:SetHyperlink(link) else tt:SetText(itemName(self.key)) end
        tt:AddLine("Click to show its price history.", TEAL_SOFT[1], TEAL_SOFT[2], TEAL_SOFT[3])
    end)
end

local function fillListRow(row, d)
    initListRow(row)
    row.key = d.key
    row.icon:Show()
    row.icon:SetTexture(itemIcon(d.key))
    row.name:SetText(itemName(d.key))
    row.name:SetTextColor(itemQualityColor(d.key))
    row.last:SetText(coinShort(d.st and d.st.last))
    row.avg:SetText(coinShort(d.st and d.st.avg7))
    local pct = d.st and d.st.last and d.st.avg14 and (d.st.last / d.st.avg14 - 1) * 100 or nil
    row.trend:SetText(U.pctColored(pct))
end

local function renderList()
    local match = ns.Browse.ShoppingListMatcher(state.list)
    local rows = {}
    if match then
        for _, key in ipairs(Stonks:AllKeys()) do
            local name = itemName(key)
            if match(name) then rows[#rows + 1] = { key = key, name = name, st = Stonks:ItemStats(key) } end
        end
        U.SortRows(rows, listSort(), function(d, id)
            if id == "name" then return d.name end
            local st = d.st
            if not st then return nil end
            if id == "trend" then return st.last and st.avg14 and (st.last / st.avg14 - 1) or nil end
            return st[id]
        end)
    end
    listBox:SetDataProvider(CreateDataProvider(rows))
    listBox:Show()
    listHead:Show()
    if #rows == 0 then
        message("No prices yet for the items on this list. Scan or search them with Auctionator.")
    end
    return #rows
end

---------------------------------------------------------------------------
-- Header and controls
---------------------------------------------------------------------------
local function updateButtons()
    local item = state.view == "item"
    for _, b in ipairs(modeButtons) do
        b:SetShown(item or (state.view == "market" and b.key ~= "time"))
        b:SetOn(b.key == state.tab)
    end
    for _, b in ipairs(avgButtons) do
        b:SetShown(item and state.tab == "time")
        b:SetOn(state.avg == b.days)
    end
    frame.avgLabel:SetShown(item and state.tab == "time")
    backButton:SetShown(item and state.fromList ~= nil)
end

local function setStats(st)
    header.stats.data = st
    if st then
        local spread = (st.q25 and st.q75) and (" (" .. coinShort(st.q25) .. " - " .. coinShort(st.q75) .. ")") or ""
        header.stats.text:SetText(("Last %s   3d %s   7d %s   14d %s   Median %s%s"):format(
            coinShort(st.last), coinShort(st.avg3), coinShort(st.avg7), coinShort(st.avg14), coinShort(st.median or st.mean), spread))
    else
        header.stats.text:SetText("")
    end
end

local function extremes(buckets, first, count, labels, normal)
    local lowK, lowV, highK, highV
    for i = first, first + count - 1 do
        local pct = Stonks.BucketValue(buckets[i], normal)
        if pct then
            if not lowV or pct < lowV then lowK, lowV = i, pct end
            if not highV or pct > highV then highK, highV = i, pct end
        end
    end
    if not lowK or lowK == highK then return "" end
    return ("Cheapest: |cff7ad1cc%s (%s)|r   Priciest: |cffeb9339%s (%s)|r"):format(labels[lowK], pctText(lowV), labels[highK], pctText(highV))
end

function render()
    if not frame or not frame:IsShown() then return end
    resetPools()
    chart.message:Hide()
    chart.marker:Hide()
    listBox:Hide()
    listHead:Hide()
    GameTooltip:Hide()
    setHits(nil)
    updateButtons()
    header.icon:Show()
    header.extra:SetText("")
    setStats(nil)

    if not state.view then
        header.icon:Hide()
        header.name:SetText("")
        header.sub:SetText("")
        return message(EMPTY_TEXT)
    end

    if state.view == "list" then
        header.icon:SetTexture(U.TEX.market)
        header.name:SetText(state.list)
        setColor(header.name, GOLD)
        local n = renderList()
        header.sub:SetText(("Auctionator shopping list: %d items with prices. Click one for its history."):format(n))
        return
    end

    if state.view == "market" then
        header.icon:SetTexture(U.TEX.market)
        header.name:SetText("Whole market")
        setColor(header.name, GOLD)
        if state.tab == "time" then state.tab = "week"; updateButtons() end
        local m = Stonks:CachedMarket()
        if not m then
            header.sub:SetText("Working out the market averages...")
            message("Averaging every item...")
            Stonks:BuildMarket(function() render() end, function(done, total)
                if chart.message:IsShown() then chart.message:SetText(("Averaging every item... %d of %d"):format(done, total)) end
            end)
            return
        end
        header.sub:SetText(("%d items. Bars: how far the whole market sits above or below normal."):format(m.items))
        if state.tab == "week" then
            header.extra:SetText(extremes(m.week, 1, 7, WEEKDAYS, nil))
            drawBars(m.week, 1, 7, WEEKDAYS_SHORT, {}, true, "week")
        else
            header.extra:SetText(extremes(m.hour, 0, 24, HOUR_NAMES, nil))
            drawBars(m.hour, 0, 24, HOUR_LABELS, {}, true, "hour")
        end
        return
    end

    local key = state.key
    local all = Stonks:ItemSeries(key)
    setStats(Stonks:ItemStats(key, all))
    local points = filterRange(all)
    local profile = Stonks.Profile(points, state.range == 0 and Stonks:ItemAgg(key) or nil)
    header.icon:SetTexture(itemIcon(key))
    header.name:SetText(itemName(key))
    header.name:SetTextColor(itemQualityColor(key))
    if #all == 0 and profile.folded == 0 then
        header.sub:SetText("")
        return message("Stonks has no prices for this item yet. Scan it with Auctionator and it appears here.")
    end
    local stonks = 0
    for _, pt in ipairs(points) do if pt.src == "s" then stonks = stonks + 1 end end
    header.sub:SetText(profile.normal and ("Normal %s.  %d prices (%d with the hour)."):format(coin(profile.normal), #points, stonks) or "No prices in this period.")
    if state.tab == "time" then
        header.extra:SetText(state.avg and ("|cffffd100Gold line|r: %d-day average   |cff7ad1ccteal|r: Stonks   |cffeb9339copper|r: Auctionator daily low"):format(state.avg)
            or "|cff7ad1ccTeal|r: Stonks (with hour)   |cffeb9339Copper|r: Auctionator daily low")
        drawTimeline(points, profile, all)
    elseif state.tab == "week" then
        header.extra:SetText(extremes(profile.week, 1, 7, WEEKDAYS, profile.normal))
        drawBars(profile.week, 1, 7, WEEKDAYS_SHORT, profile, false, "week")
    else
        header.extra:SetText(extremes(profile.hour, 0, 24, HOUR_NAMES, profile.normal))
        drawBars(profile.hour, 0, 24, HOUR_LABELS, profile, false, "hour")
    end
end

---------------------------------------------------------------------------
-- Docking: right of the auction house when it is open, else right of the Stonks browser.
---------------------------------------------------------------------------
local function ahFrame()
    local f = _G.AuctionFrame or _G.AuctionHouseFrame
    if f and f:IsShown() then return f end
    return nil
end

function Stonks:DockPanel()
    if not frame then return end
    local anchor = ahFrame()
    local browser = _G.EncoreStonksFrame
    if not anchor and browser and browser:IsShown() then anchor = browser end
    if anchor then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 12, 0)
        frame.docked = true
    elseif frame.docked then
        frame.docked = nil
        frame:RestorePosition(300)
    end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function openOptions(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Period")
        for _, o in ipairs(RANGE_OPTIONS) do
            root:CreateRadio(o[2], function(v) return state.range == v end, function(v)
                state.range = v
                settings().range = v
                render()
            end, o[1])
        end
        root:CreateDivider()
        root:CreateTitle("Keep hourly detail for")
        for _, d in ipairs(Stonks.KEEP_DAYS_OPTIONS) do
            root:CreateRadio(d .. " days", function(v) return Stonks:KeepDays() == v end, function(v)
                Stonks:SetKeepDays(v)
                Stonks:InvalidateMarket()
                render()
            end, d)
        end
        root:CreateDivider()
        root:CreateCheckbox("Also use Auctionator's daily history", function() return Stonks:Settings().useAuctionator == true end, function()
            Stonks:Settings().useAuctionator = not Stonks:Settings().useAuctionator
            Stonks:InvalidateMarket()
            render()
        end)
        root:CreateCheckbox("Open beside the auction house", function() return Stonks:Settings().dockAH ~= false end, function()
            Stonks:Settings().dockAH = Stonks:Settings().dockAH == false
        end)
        root:CreateCheckbox("Show averages in item tooltips", function() return Stonks:Settings().tooltip ~= false end, function()
            Stonks:Settings().tooltip = Stonks:Settings().tooltip == false
        end)
        root:CreateDivider()
        root:CreateButton("Reset window size and position", function() frame:ResetSize(); Stonks:DockPanel() end)
    end)
end

---------------------------------------------------------------------------
-- Title-bar tabs: Graphs and History
---------------------------------------------------------------------------
function applyPage(id)
    if id == "history" and not pages.history then
        local view = ns.SyncHistoryView
        pages.history = view and view.Build(frame) or nil
        if not pages.history then id = "graphs" end
    end
    state.page = id
    frame.graphPage:SetShown(id == "graphs")
    if pages.history then pages.history:SetShown(id == "history") end
    for _, b in ipairs(pageTabs) do b:SetOn(b.page == id) end
end

local function setPage(id)
    if not frame then return end
    local was = state.page
    GameTooltip:Hide()
    applyPage(id)
    if state.page == "graphs" and was ~= "graphs" then render() end
end

function createTabs()
    local x = 60
    for _, p in ipairs(PAGES) do
        local b = U.ToggleButton(frame, p[2], p[3])
        b:SetHeight(18)
        b.page = p[1]
        b:SetPoint("TOPLEFT", x, -2)
        x = x + p[3] + 3
        b:SetScript("OnClick", function() setPage(p[1]) end)
        U.tooltip(b, function(tt)
            tt:SetText(p[2])
            tt:AddLine(p[4], 1, 1, 1, true)
        end)
        frame:KeepOnTop(b)
        pageTabs[#pageTabs + 1] = b
    end
    applyPage("graphs")
end

local function createPanel()
    frame = U.CreateWindow({
        name = "EncoreStonksPanel", title = "Encore-Stonks", width = 560, height = 470, minW = 470, minH = 400,
        settingsKey = "panel", onOptions = openOptions, defaultX = 300,
    })
    local saved = settings()
    if tonumber(saved.range) then state.range = tonumber(saved.range) end
    if saved.tab == "time" or saved.tab == "week" or saved.tab == "hour" then state.tab = saved.tab end
    if saved.avg == false then state.avg = nil elseif tonumber(saved.avg) then state.avg = tonumber(saved.avg) end

    -- Everything below the title bar belongs to a page: Graphs (built here) or History (the sync history,
    -- built by Sync/HistoryView.lua the first time its tab is clicked). The tabs sit in the title bar, left of the title.
    local graphs = CreateFrame("Frame", nil, frame)
    graphs:SetAllPoints()
    frame.graphPage = graphs
    createTabs()

    header = CreateFrame("Frame", nil, graphs)
    header:SetPoint("TOPLEFT", 62, -28)
    header:SetPoint("TOPRIGHT", -12, -28)
    header:SetHeight(36)
    header.icon = header:CreateTexture(nil, "ARTWORK")
    header.icon:SetSize(30, 30)
    header.icon:SetPoint("TOPLEFT", 0, 0)
    header.name = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header.name:SetPoint("TOPLEFT", header.icon, "TOPRIGHT", 8, 0)
    header.name:SetPoint("RIGHT", -96, 0)
    header.name:SetJustifyH("LEFT")
    header.name:SetWordWrap(false)
    header.sub = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.sub:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -3)
    header.sub:SetPoint("RIGHT", 0, 0)
    header.sub:SetJustifyH("LEFT")
    header.sub:SetWordWrap(false)
    setColor(header.sub, INK)
    local iconButton = CreateFrame("Button", nil, header)
    iconButton:SetAllPoints(header.icon)
    iconButton:SetScript("OnClick", function()
        local l = state.view == "item" and linkFor(state.key)
        if l then HandleModifiedItemClick(l) end
    end)
    iconButton:SetScript("OnEnter", function(self)
        local l = state.view == "item" and linkFor(state.key)
        if not l then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(l)
        GameTooltip:Show()
    end)
    iconButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    backButton = U.ToggleButton(graphs, "Back to list", 90)
    backButton:SetPoint("TOPRIGHT", -12, -30)
    backButton:SetScript("OnClick", function() if state.fromList then Stonks:ShowList(state.fromList) end end)

    -- Statistics line (hover for the full Auctioneer-style breakdown)
    header.stats = CreateFrame("Frame", nil, graphs)
    header.stats:SetPoint("TOPLEFT", 14, -68)
    header.stats:SetPoint("TOPRIGHT", -14, -68)
    header.stats:SetHeight(14)
    header.stats.text = header.stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.stats.text:SetAllPoints()
    header.stats.text:SetJustifyH("LEFT")
    header.stats.text:SetWordWrap(false)
    setColor(header.stats.text, INK)
    header.stats:SetScript("OnEnter", function(self)
        local st = self.data
        if not st then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText("Price statistics")
        local function row(label, v) if v then GameTooltip:AddDoubleLine(label, coin(v), 1, 1, 1, 1, 1, 1) end end
        row("Last seen (lowest that day)", st.last)
        row("3-day average", st.avg3)
        row("7-day average", st.avg7)
        row("14-day average", st.avg14)
        row("Median", st.median)
        if st.q25 and st.q75 then GameTooltip:AddDoubleLine("Middle 50%", coin(st.q25) .. " - " .. coin(st.q75), 1, 1, 1, 1, 1, 1) end
        row("Mean", st.mean)
        row("Standard deviation", st.sd)
        GameTooltip:AddDoubleLine("Days seen", tostring(st.days), DIM[1], DIM[2], DIM[3], DIM[1], DIM[2], DIM[3])
        GameTooltip:AddLine("Each day counts once with its lowest buyout. Averages move with each day seen; median and mean lean towards the last month. Prices more than 5x away from the 14-day average are ignored.", DIM[1], DIM[2], DIM[3], true)
        GameTooltip:Show()
    end)
    header.stats:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Mode buttons on the left, average buttons on the right
    local x = 14
    for _, m in ipairs(MODES) do
        local b = U.ToggleButton(graphs, m[2], m[3])
        b.key = m[1]
        b:SetPoint("TOPLEFT", x, -88)
        x = x + m[3] + 4
        b:SetScript("OnClick", function()
            state.tab = m[1]
            settings().tab = m[1]
            render()
        end)
        modeButtons[#modeButtons + 1] = b
    end
    local prev
    for i = #AVERAGES, 1, -1 do
        local days = AVERAGES[i]
        local b = U.ToggleButton(graphs, days .. "d", 38)
        b.days = days
        if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", -14, -88) end
        prev = b
        b:SetScript("OnClick", function()
            state.avg = (state.avg ~= days) and days or nil
            settings().avg = state.avg or false
            render()
        end)
        U.tooltip(b, function(tt)
            tt:SetText(days .. "-day moving average")
            tt:AddLine("Draws the average of the daily lows as a gold line on the trend. Click again to hide it.", 1, 1, 1, true)
        end)
        avgButtons[#avgButtons + 1] = b
    end
    frame.avgLabel = graphs:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.avgLabel:SetPoint("RIGHT", prev, "LEFT", -6, 0)
    frame.avgLabel:SetText("Average")

    header.extra = graphs:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.extra:SetPoint("TOPLEFT", 14, -114)
    header.extra:SetPoint("TOPRIGHT", -14, -114)
    header.extra:SetJustifyH("LEFT")
    header.extra:SetWordWrap(false)
    setColor(header.extra, DIM)

    -- Chart well
    local pane = U.well(graphs)
    pane:SetPoint("TOPLEFT", 10, -130)
    pane:SetPoint("BOTTOMRIGHT", -10, 28)
    chart = CreateFrame("Frame", nil, pane)
    chart:SetAllPoints()
    chart.canvas = CreateFrame("Frame", nil, chart)
    chart.canvas:SetPoint("TOPLEFT", 4, -4)
    chart.canvas:SetPoint("BOTTOMRIGHT", -4, 4)
    chart.canvas:SetScript("OnUpdate", onCanvasUpdate)
    chart.canvas:SetScript("OnHide", function() GameTooltip:Hide() end)
    chart.guide = chart.canvas:CreateTexture(nil, "BORDER")
    chart.guide:SetWidth(1)
    chart.guide:SetColorTexture(1, 0.9, 0.6, 0.25)
    chart.guide:Hide()
    chart.marker = chart.canvas:CreateTexture(nil, "OVERLAY", nil, 6)
    chart.marker:SetSize(9, 9)
    chart.marker:SetColorTexture(1, 0.95, 0.8, 1)
    chart.marker:SetRotation(math.rad(45))
    chart.marker:Hide()
    chart.message = chart.canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    chart.message:SetPoint("CENTER")
    chart.message:SetWidth(360)
    setColor(chart.message, DIM)
    chart.message:Hide()
    local pending = false
    chart.canvas:SetScript("OnSizeChanged", function()
        if pending or not frame:IsShown() then return end
        pending = true
        C_Timer.After(0.1, function()
            pending = false
            render()
        end)
    end)

    -- Shopping list rows (shown in the same well)
    listHead = CreateFrame("Frame", nil, pane)
    listHead:SetPoint("TOPLEFT", 3, -3)
    listHead:SetPoint("TOPRIGHT", -17, -3)
    listHead:SetHeight(18)
    local headBg = listHead:CreateTexture(nil, "BACKGROUND")
    headBg:SetAllPoints()
    gradient(headBg, "VERTICAL", 0.09, 0.06, 0.04, 1, 0.17, 0.13, 0.09, 1)
    U.SortHeader(listHead, {
        { id = "name", label = "Item", point = "LEFT", x = 28, width = 150, tip = "Item name." },
        { id = "last", label = "Last", point = "RIGHT", x = -120, width = 64, desc = true, tip = "Lowest buyout on the last day seen." },
        { id = "avg7", label = "7-day avg", point = "RIGHT", x = -50, width = 66, desc = true, tip = "Moving average of the daily lows over 7 days." },
        { id = "trend", label = "Trend", point = "RIGHT", x = -6, width = 42, desc = true, tip = "Last price against the 14-day average." },
    }, listSort(), function() render() end)
    listHead:Hide()
    listBox = CreateFrame("Frame", nil, pane, "WowScrollBoxList")
    listBox:SetPoint("TOPLEFT", 3, -23)
    listBox:SetPoint("BOTTOMRIGHT", -14, 3)
    local bar = CreateFrame("EventFrame", nil, pane, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 2, -2)
    bar:SetPoint("BOTTOMLEFT", listBox, "BOTTOMRIGHT", 2, 2)
    bar:SetHideIfUnscrollable(true)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(24)
    view:SetElementInitializer("EncoreStonksItemRowTemplate", fillListRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(listBox, bar, view)
    listBox:Hide()

    local credit = graphs:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    credit:SetPoint("BOTTOMLEFT", 16, 9)
    credit:SetText("Prices from your Auctionator scans. Times in your computer's time zone.")
    setColor(credit, DIM)

    -- Item names arrive from the server a moment after they are asked for.
    local namesPending = false
    local watcher = CreateFrame("Frame", nil, frame)
    watcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    watcher:SetScript("OnEvent", function()
        if namesPending or not frame:IsShown() then return end
        namesPending = true
        C_Timer.After(0.5, function()
            namesPending = false
            render()
        end)
    end)

    frame:HookScript("OnShow", function()
        Stonks:DockPanel()
        render()
    end)
    frame:HookScript("OnHide", function()
        GameTooltip:Hide()
        applyPage("graphs") -- the panel always opens on its graphs
    end)
end

local function showPanel()
    if not frame then createPanel() end
    if not frame:IsShown() then frame:Show() else Stonks:DockPanel(); render() end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
-- Show an item's history: key, item ID, link or Auctionator item info. opts.fromList keeps a "Back to list" button.
function Stonks:ShowItem(item, opts)
    local key = U.keyFrom(item)
    if not key then return end
    state.view, state.key = "item", key
    state.fromList = opts and opts.fromList or nil
    showPanel()
    if not (opts and opts.follow) then setPage("graphs") end
    if self.OnPanelItem then self:OnPanelItem(key) end
end

function Stonks:ShowList(name, opts)
    if type(name) ~= "string" or name == "" then return end
    state.view, state.list, state.fromList = "list", name, nil
    showPanel()
    if not (opts and opts.follow) then setPage("graphs") end
end

function Stonks:ShowMarket()
    state.view, state.fromList = "market", nil
    showPanel()
    setPage("graphs")
end

function Stonks:ShowPanel() showPanel() end
-- Opens the panel on a page: "graphs" or "history".
function Stonks:ShowPage(id)
    showPanel()
    setPage(id)
end
function Stonks:HidePanel() if frame then frame:Hide() end end
function Stonks:PanelShown() return frame and frame:IsShown() end
function Stonks:PanelKey() return state.view == "item" and state.key or nil end

-- New prices while the panel is open: redraw a moment after the scan settles.
local refreshTimer
function Stonks:OnData()
    if self.OnBrowserData then self:OnBrowserData() end
    if not frame or not frame:IsShown() or refreshTimer then return end
    refreshTimer = C_Timer.NewTimer(3, function()
        refreshTimer = nil
        render()
    end)
end
