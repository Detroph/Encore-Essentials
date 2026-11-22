-- Encore-Stonks: the History tab of the graph panel. Lists the sync history (Sync/Log.lua) in two tabs:
-- Received (when and from whom you received hourly guild scans, your login summary, and items or scans shared by
-- chat link) and Sent (your hourly scans to the guild, login summaries you sent to guildmates, and items or scans
-- you shared). Above the list: data size cards (today, 7 days, 30 days) and a bar chart of bytes per day.
-- Panel.lua calls Build(panel) the first time the History tab is clicked.
local _, ns = ...
local Stonks = ns.Stonks
local U = ns.UI
local Codec, Log, Sync = Stonks.SyncCodec, Stonks.SyncLog, Stonks.Sync
local View = {}
ns.SyncHistoryView = View

local TEAL, TEAL_SOFT, COPPER, INK, DIM = U.TEAL, U.TEAL_SOFT, U.COPPER, U.INK, U.DIM
local STALE = 300 -- an unfinished delivery quiet for 5 minutes is shown as incomplete
local BAR_DAYS = 30

local FILTERS = {
    { "all", "All", 40 },
    { "hourly", "Hourly scans", 88 },
    { "summary", "Login summaries", 104 },
    { "shared", "Shared by link", 98 },
}
local TABS = {
    { "rec", "Received", 96 },
    { "sent", "Sent", 96 },
}
local MODE_TEXT = { share = "on (sharing and receiving)", receive = "receive only", off = "off (chat links only)" }

local page, summary, footer, requestBtn, chart, chartLabel
local note, noteUntil -- a short message from the Request sync button, shown in the footer for a while
local filterButtons, tabButtons, cards, bars = {}, {}, {}, {}
local lists = {} -- [tab] = { box, head, empty }

local function settings()
    local s = Stonks:Settings()
    if type(s.history) ~= "table" then s.history = {} end
    local h = s.history
    if type(h.sort) ~= "table" then h.sort = { id = "when", desc = true } end
    if type(h.sortSent) ~= "table" then h.sortSent = { id = "when", desc = true } end
    if not h.filter then h.filter = "all" end
    if h.tab ~= "rec" and h.tab ~= "sent" then h.tab = "rec" end
    return h
end

-- "512 B", "4.2 KB", "38 KB", "1.27 MB"
local function sizeText(b)
    b = tonumber(b) or 0
    if b < 1024 then return ("%d B"):format(b) end
    if b < 10240 then return ("%.1f KB"):format(b / 1024) end
    if b < 1048576 then return ("%d KB"):format(math.floor(b / 1024 + 0.5)) end
    return ("%.2f MB"):format(b / 1048576)
end
View.sizeText = sizeText

local function who(e) return e.from or e.to or "" end

local function status(e, sent)
    if sent then
        if e.done then return "done", "Complete." end
        if time() - (e.last or e.t or 0) > STALE then return "incomplete", "Incomplete: not all of it went out (the guildmate went away, you lost the hourly claim, or you logged off or reloaded)." end
        return "receiving", "Still sending."
    end
    if e.stopped and e.silent then return "stopped", "Nothing arrived: they offered but never sent anything. They probably run Encore-Stonks 0.1.4 or older, which can't send to names with a space; someone else was asked instead." end
    if e.stopped then return "stopped", "Stopped: the sender went quiet; the rest came from someone else." end
    if e.done then return "done", "Complete." end
    if time() - (e.last or e.t or 0) > STALE then return "incomplete", "Incomplete: the end message never arrived (logged off or reloaded)." end
    return "receiving", "Still receiving."
end

local function whatText(e)
    if e.kind == "item" then
        return e.id and U.itemName(tostring(e.id)) or "Item"
    end
    return ("%d items"):format(e.got or 0)
end

local function keptText(e)
    if e.kind == "item" then return (e.kept or 0) > 0 and "|cff7ad1ccYes|r" or "|cffeb9339No|r" end
    return tostring(e.kept or 0)
end

---------------------------------------------------------------------------
-- Rows (one template for both tabs; row.sent says which tab it is filled for)
---------------------------------------------------------------------------
local function initRow(row)
    if row.built then return end
    row.built = true
    row:SetHeight(20)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.9, 0.6, 0.08)
    local function cell(point, x, width, justify)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint(point, x, 0)
        if width then fs:SetWidth(width) end
        fs:SetJustifyH(justify or "LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    row.when = cell("LEFT", 6, 90)
    row.who = cell("LEFT", 100, 84)
    row.kind = cell("LEFT", 188, 78)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 270, 0)
    row.what = cell("LEFT", 270)
    row.kept = cell("RIGHT", -58, 40, "RIGHT")
    row.size = cell("RIGHT", -6, 48, "RIGHT")
    U.setColor(row.size, DIM)
    row:SetScript("OnClick", function(self)
        local e = self.entry
        if e and e.kind == "item" and e.id then Stonks:ShowItem(tostring(e.id)) end
    end)
    U.tooltip(row, function(tt, self)
        local e = self.entry
        if not e then return end
        local sent = self.sent
        tt:SetText(Log.KINDS[e.kind] or e.kind)
        local function line(label, value) tt:AddDoubleLine(label, value, DIM[1], DIM[2], DIM[3], 1, 1, 1) end
        line(sent and "To" or "From", Codec.safeText(who(e)))
        line(sent and "Sent" or "Received", date("%a %d %b %H:%M", e.t))
        if e.last and e.last - e.t >= 60 then line("Last message", date("%a %d %b %H:%M", e.last)) end
        if e.hour then
            local label = e.kind == "summary" and (sent and "Your data up to" or "Their data up to") or "Scan from"
            line(label, date("%d %b %H:00", e.hour * 3600))
        end
        if e.kind == "item" then
            if e.id then
                local link = U.linkFor(tostring(e.id))
                line("Item", link or U.itemName(tostring(e.id)))
            end
            if e.med then line(sent and "Your median price" or "Their median price", U.coin(e.med)) end
            if not sent then line("Imported", (e.kept or 0) > 0 and "yes" or "no, too far from your own prices") end
        else
            line(e.kind == "summary" and "Item summaries" or "Item prices", tostring(e.got or 0))
            if e.expected and e.expected ~= e.got then line(sent and "Announced" or "Sender announced", tostring(e.expected)) end
            if not sent then line("Kept", tostring(e.kept or 0)) end
        end
        line("Size", sizeText(e.bytes))
        if not sent and e.kind ~= "item" then
            tt:AddLine("Prices are skipped when you already have your own price for that hour, when they barely moved since the last guild price, or when they are more than 5x away from your own.", DIM[1], DIM[2], DIM[3], true)
        end
        local _, text = status(e, sent)
        tt:AddLine(text, INK[1], INK[2], INK[3], true)
        if e.kind == "item" and e.id then tt:AddLine("Click to show its price history.", TEAL_SOFT[1], TEAL_SOFT[2], TEAL_SOFT[3]) end
    end)
end

local function fillRow(row, e, sent)
    initRow(row)
    row.entry, row.sent = e, sent
    row.when:SetText(date("%a %d %b %H:%M", e.t))
    row.who:SetText(Codec.safeText(who(e)))
    row.kind:SetText(Log.KINDS[e.kind] or e.kind)
    if e.kind == "item" and e.id then
        local key = tostring(e.id)
        row.icon:SetTexture(U.itemIcon(key))
        row.icon:Show()
        row.what:SetPoint("LEFT", 288, 0)
        row.what:SetTextColor(U.itemQualityColor(key))
    else
        row.icon:Hide()
        row.what:SetPoint("LEFT", 270, 0)
        U.setColor(row.what, INK)
    end
    row.what:SetPoint("RIGHT", sent and -58 or -102, 0)
    row.what:SetText(whatText(e))
    row.kept:SetShown(not sent)
    row.kept:SetText(sent and "" or keptText(e))
    row.size:SetText(e.bytes and sizeText(e.bytes) or "-")
    local st = status(e, sent)
    local c = (st == "done" or st == "receiving") and INK or (st == "stopped" and COPPER or DIM)
    U.setColor(row.when, c); U.setColor(row.kind, c)
    if sent and e.to == "Guild" then U.setColor(row.who, TEAL_SOFT) else U.setColor(row.who, c) end
end

---------------------------------------------------------------------------
-- Stat cards and the bytes-per-day chart
---------------------------------------------------------------------------
local function layoutBars()
    if not chart then return end
    local w, h = chart:GetWidth() - 12, chart:GetHeight() - 20
    if w <= 0 or h <= 0 then return end
    local dir = settings().tab
    local values, top = {}, 1
    for i = 1, BAR_DAYS do
        local v = Log.DayBytes(dir, BAR_DAYS - i)
        values[i] = v
        if v > top then top = v end
    end
    local step = w / BAR_DAYS
    for i, b in ipairs(bars) do
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", 6 + (i - 1) * step, 4)
        b:SetSize(math.max(1, step), h)
        b.tealBar:SetShown(dir == "rec")
        b.copperBar:SetShown(dir ~= "rec")
        b.bar = dir == "rec" and b.tealBar or b.copperBar
        b.bar:SetWidth(math.max(1, step - 2))
        b.bar:SetHeight(values[i] > 0 and math.max(2, values[i] / top * h) or 1)
        b.bar:SetAlpha(values[i] > 0 and 1 or 0.35)
        b.daysAgo = BAR_DAYS - i
    end
end

local function refreshStats()
    local dir = settings().tab
    for _, c in ipairs(cards) do c.value:SetText(sizeText(Log.Bytes(dir, c.days))) end
    chartLabel:SetText((dir == "rec" and "Received" or "Sent") .. " per day, last 30 days")
    layoutBars()
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local function matches(e, filter)
    if filter == "all" then return true end
    if filter == "shared" then return e.kind == "item" or e.kind == "scan" end
    return e.kind == filter
end

local function lastSentHourly()
    local list = Log.Entries("sent")
    for i = #list, 1, -1 do
        local e = list[i]
        if type(e) == "table" and e.kind == "hourly" then return e end
    end
    return nil
end

local function refresh()
    if not page or not page:IsShown() then return end
    local h = settings()
    local tab = h.tab
    local sent = tab == "sent"
    local sort = sent and h.sortSent or h.sort
    local all = Log.Entries(tab)
    local rows = {}
    for _, e in ipairs(all) do
        if type(e) == "table" and e.t and matches(e, h.filter) then
            rows[#rows + 1] = { entry = e, name = who(e) }
        end
    end
    U.SortRows(rows, sort, function(d, id)
        local e = d.entry
        if id == "when" then return e.t end
        if id == "who" then return who(e) end
        if id == "kind" then return Log.KINDS[e.kind] end
        if id == "what" then return e.kind == "item" and whatText(e) or ("~" .. ("%09d"):format(e.got or 0)) end
        if id == "kept" then return e.kept end
        if id == "size" then return e.bytes or 0 end
    end)
    local list = {}
    for i, d in ipairs(rows) do list[i] = d.entry end
    for id, l in pairs(lists) do
        l.pane:SetShown(id == tab)
    end
    local l = lists[tab]
    l.box:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    l.empty:SetShown(#list == 0)
    for _, b in ipairs(filterButtons) do b:SetOn(b.filter == h.filter) end
    for _, b in ipairs(tabButtons) do b:SetOn(b.tab == tab) end
    page.sub:SetText(sent and "When and to whom you sent your prices." or "When and from whom you received guild prices.")

    local r = Stonks.realmData
    local mode = Sync and Sync.Mode and Sync.Mode() or "off"
    local extra = ""
    if sent then
        local e = lastSentHourly()
        if e then extra = ("   Last hourly scan sent: %s, to the guild."):format(date("%d %b %H:%M", e.t)) end
    elseif r and r.sync and r.sync.at then
        extra = ("   Last login summary: %s, %s."):format(Codec.safeText(r.sync.from), date("%d %b %H:%M", r.sync.at))
    end
    summary:SetText("Guild sharing is " .. (MODE_TEXT[mode] or mode) .. "." .. extra)
    if note and time() < (noteUntil or 0) then
        footer:SetText(note)
    else
        footer:SetText(("%d deliveries kept (the last 30 days). Times in your computer's time zone."):format(#all))
    end
    refreshStats()
end

local pending = false
local function refreshSoon()
    if pending or not page or not page:IsShown() then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        refresh()
    end)
end
Log.OnChange(refreshSoon)

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function statCard(parent, label, days, x)
    local c = U.well(parent)
    c:SetSize(84, 44)
    c:SetPoint("TOPLEFT", x, -96)
    c.days = days
    c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.label:SetPoint("TOPLEFT", 8, -7)
    c.label:SetText(label)
    U.setColor(c.label, DIM)
    c.value = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    c.value:SetPoint("TOPLEFT", c.label, "BOTTOMLEFT", 0, -3)
    c:EnableMouse(true)
    U.tooltip(c, function(tt)
        local dir = settings().tab
        tt:SetText((dir == "rec" and "Received" or "Sent") .. (days == 1 and ", today" or (", last %d days"):format(days)))
        local function line(a, b) tt:AddDoubleLine(a, b, DIM[1], DIM[2], DIM[3], 1, 1, 1) end
        line("Received", sizeText(Log.Bytes("rec", days)))
        line("Sent", sizeText(Log.Bytes("sent", days)))
        tt:AddLine("Every Encore-Stonks guild message, as it goes over the wire (already compressed), including the short ones that set up a sync.", DIM[1], DIM[2], DIM[3], true)
    end)
    cards[#cards + 1] = c
    return c
end

local function buildList(tab)
    local sent = tab == "sent"
    local pane = U.well(page)
    pane:SetPoint("TOPLEFT", 10, -190)
    pane:SetPoint("BOTTOMRIGHT", -10, 28)
    local head = CreateFrame("Frame", nil, pane)
    head:SetPoint("TOPLEFT", 3, -3)
    head:SetPoint("TOPRIGHT", -17, -3)
    head:SetHeight(18)
    local headBg = head:CreateTexture(nil, "BACKGROUND")
    headBg:SetAllPoints()
    U.gradient(headBg, "VERTICAL", 0.09, 0.06, 0.04, 1, 0.17, 0.13, 0.09, 1)
    local cols = {
        { id = "when", label = "When", point = "LEFT", x = 6, width = 88, desc = true, tip = sent and "When the first message of it went out." or "When the first message of it arrived." },
        { id = "who", label = sent and "To" or "From", point = "LEFT", x = 100, width = 84, tip = sent and "Guild for your hourly scans, the guildmate's name for whispers." or "The guildmate who sent it." },
        { id = "kind", label = "Type", point = "LEFT", x = 188, width = 78, tip = "Hourly guild scan, login summary, or an item or scan shared by chat link." },
        { id = "what", label = sent and "Sent" or "Received", point = "LEFT", x = 270, width = 70, desc = true, tip = "Number of item prices, or the shared item." },
    }
    if not sent then
        cols[#cols + 1] = { id = "kept", label = "Kept", point = "RIGHT", x = -58, width = 40, desc = true, tip = "How many of them were added to your data." }
    end
    cols[#cols + 1] = { id = "size", label = "Size", point = "RIGHT", x = -6, width = 48, desc = true, tip = "Data size of this delivery, as it went over the wire (already compressed)." }
    local h = settings()
    U.SortHeader(head, cols, sent and h.sortSent or h.sort, refresh)

    local box = CreateFrame("Frame", nil, pane, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", 3, -23)
    box:SetPoint("BOTTOMRIGHT", -14, 3)
    local bar = CreateFrame("EventFrame", nil, pane, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 2, -2)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 2, 2)
    bar:SetHideIfUnscrollable(true)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(20)
    view:SetElementInitializer("EncoreStonksSyncRowTemplate", function(row, e) fillRow(row, e, sent) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)

    local empty = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("CENTER", 0, -10)
    empty:SetWidth(360)
    empty:SetText(sent
        and "Nothing sent yet. Your hourly guild scans, login summaries you send to guildmates and prices you share by chat link show up here."
        or "Nothing received yet. Guild scans, your login summary and prices shared by chat link show up here.")
    U.setColor(empty, DIM)
    lists[tab] = { pane = pane, box = box, empty = empty }
end

function View.Build(panel)
    if page then return page end
    page = CreateFrame("Frame", nil, panel)
    page:SetAllPoints()
    page:Hide()

    local icon = page:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30)
    icon:SetPoint("TOPLEFT", 62, -28)
    icon:SetTexture(U.TEX.market)
    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 0)
    title:SetText("Sync history")
    local sub = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    sub:SetPoint("RIGHT", page, "RIGHT", -14, 0)
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(false)
    U.setColor(sub, INK)
    page.sub = sub

    -- Received / Sent: the two big tabs, with a copper line under them.
    local x = 14
    for _, t in ipairs(TABS) do
        local b = U.ToggleButton(page, t[2], t[3])
        b:SetHeight(24)
        b.text:SetFontObject("GameFontNormal")
        b.tab = t[1]
        b:SetPoint("BOTTOMLEFT", page, "TOPLEFT", x, -90)
        x = x + t[3] + 3
        b:SetScript("OnClick", function()
            settings().tab = t[1]
            GameTooltip:Hide()
            refresh()
        end)
        U.tooltip(b, function(tt)
            tt:SetText(t[2])
            if t[1] == "rec" then
                tt:AddLine("What guildmates sent you: hourly scans, your login summary and shared items or scans.", 1, 1, 1, true)
            else
                tt:AddLine("What you sent: your hourly scans to the guild, login summaries you sent to guildmates and items or scans you shared.", 1, 1, 1, true)
            end
            tt:AddDoubleLine("Last 30 days", sizeText(Log.Bytes(t[1], 30)), DIM[1], DIM[2], DIM[3], 1, 1, 1)
        end)
        tabButtons[#tabButtons + 1] = b
    end
    local rule = page:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(COPPER[1], COPPER[2], COPPER[3], 0.5)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 10, -90)
    rule:SetPoint("TOPRIGHT", -10, -90)

    -- Data size: today, 7 days, 30 days, and a bar per day.
    statCard(page, "Today", 1, 10)
    statCard(page, "7 days", 7, 98)
    statCard(page, "30 days", 30, 186)
    chart = U.well(page)
    chart:SetPoint("TOPLEFT", 274, -96)
    chart:SetPoint("TOPRIGHT", -10, -96)
    chart:SetHeight(44)
    chartLabel = chart:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chartLabel:SetPoint("TOPLEFT", 6, -4)
    chartLabel:SetPoint("RIGHT", -6, 0)
    chartLabel:SetJustifyH("LEFT")
    chartLabel:SetWordWrap(false)
    U.setColor(chartLabel, DIM)
    for i = 1, BAR_DAYS do
        local b = CreateFrame("Frame", nil, chart)
        b.tealBar = b:CreateTexture(nil, "ARTWORK")
        b.tealBar:SetPoint("BOTTOMLEFT")
        U.gradient(b.tealBar, "VERTICAL", TEAL[1], TEAL[2], TEAL[3], 0.35, TEAL_SOFT[1], TEAL_SOFT[2], TEAL_SOFT[3], 1)
        b.copperBar = b:CreateTexture(nil, "ARTWORK")
        b.copperBar:SetPoint("BOTTOMLEFT")
        U.gradient(b.copperBar, "VERTICAL", COPPER[1], COPPER[2], COPPER[3], 0.35, 1, 0.75, 0.4, 1)
        b.bar = b.tealBar
        b:EnableMouse(true)
        U.tooltip(b, function(tt, self)
            local dir = settings().tab
            local bytes, t = Log.DayBytes(dir, self.daysAgo or 0)
            tt:SetText(self.daysAgo == 0 and "Today" or date("%a %d %b", t))
            tt:AddDoubleLine(dir == "rec" and "Received" or "Sent", sizeText(bytes), DIM[1], DIM[2], DIM[3], 1, 1, 1)
        end)
        bars[i] = b
    end
    chart:SetScript("OnSizeChanged", layoutBars)

    summary = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", 14, -150)
    summary:SetPoint("TOPRIGHT", -14, -150)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(false)
    U.setColor(summary, INK)

    x = 14
    for _, f in ipairs(FILTERS) do
        local b = U.ToggleButton(page, f[2], f[3])
        b.filter = f[1]
        b:SetPoint("TOPLEFT", x, -164)
        x = x + f[3] + 4
        b:SetScript("OnClick", function()
            settings().filter = f[1]
            refresh()
        end)
        filterButtons[#filterButtons + 1] = b
    end

    buildList("rec")
    buildList("sent")

    -- Request sync: asks the guild once more for your login summary (what changed since your last one).
    requestBtn = U.ToggleButton(page, "Request sync", 118)
    requestBtn:SetPoint("BOTTOMLEFT", 10, 4)
    local function setNote(text)
        note, noteUntil = text, time() + 20
        refresh()
    end
    local function updateRequest()
        local wait = Sync.ManualWait and Sync.ManualWait() or 0
        if wait > 0 then
            requestBtn.text:SetText(("Request sync %d:%02d"):format(math.floor(wait / 60), wait % 60))
            requestBtn.text:SetTextColor(DIM[1], DIM[2], DIM[3])
        else
            requestBtn:SetOn(false)
            requestBtn.text:SetText("Request sync")
        end
    end
    requestBtn:SetScript("OnClick", function()
        if not Sync.RequestNow then return end
        local _, msg = Sync.RequestNow()
        setNote(msg)
        updateRequest()
    end)
    U.tooltip(requestBtn, function(tt)
        tt:SetText("Request sync")
        tt:AddLine("Asks the guild for your login summary again: one guildmate whispers you the prices that changed since your last summary. Light on the guild, like logging in. Once an hour.", 1, 1, 1, true)
    end)
    Sync.onManual = function(result)
        if result == "none" then setNote("Nobody answered: no guildmate online has newer prices than you, or nobody shares.") end
    end
    local elapsed = 0
    requestBtn:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        updateRequest()
        if note and time() >= (noteUntil or 0) then note = nil; refresh() end
    end)
    updateRequest()

    footer = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", requestBtn, "BOTTOMRIGHT", 8, 5)
    footer:SetPoint("RIGHT", page, "BOTTOMRIGHT", -100, 0)
    footer:SetJustifyH("LEFT")
    footer:SetWordWrap(false)
    U.setColor(footer, DIM)

    local clear = U.ToggleButton(page, "Clear", 60)
    clear:SetPoint("BOTTOMRIGHT", -26, 4) -- clear of the resize grip
    clear:SetScript("OnClick", function()
        if IsShiftKeyDown() then Log.Clear(settings().tab) end
    end)
    U.tooltip(clear, function(tt)
        local sent = settings().tab == "sent"
        tt:SetText(sent and "Clear the sent history" or "Clear the received history")
        tt:AddLine("Shift-click to empty this tab and its data size counts. Your prices stay.", 1, 1, 1, true)
    end)

    -- Item names arrive from the server a moment after they are asked for.
    page:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    page:SetScript("OnEvent", refreshSoon)
    page:SetScript("OnShow", refresh)
    return page
end
