-- Encore-Stonks: the History tab of the graph panel. Lists the sync history (Sync/Log.lua): when and from whom
-- you received hourly guild scans, your login summary, and items or scans shared by chat link.
-- Panel.lua calls Build(panel) the first time the History tab is clicked.
local _, ns = ...
local Stonks = ns.Stonks
local U = ns.UI
local Codec, Log, Sync = Stonks.SyncCodec, Stonks.SyncLog, Stonks.Sync
local View = {}
ns.SyncHistoryView = View

local TEAL_SOFT, COPPER, INK, DIM = U.TEAL_SOFT, U.COPPER, U.INK, U.DIM
local STALE = 300 -- an unfinished delivery quiet for 5 minutes is shown as incomplete

local FILTERS = {
    { "all", "All", 40 },
    { "hourly", "Hourly scans", 88 },
    { "summary", "Login summaries", 104 },
    { "shared", "Shared by link", 98 },
}
local MODE_TEXT = { share = "on (sharing and receiving)", receive = "receive only", off = "off (chat links only)" }

local page, box, summary, footer
local filterButtons = {}

local function settings()
    local s = Stonks:Settings()
    if type(s.history) ~= "table" then s.history = {} end
    local h = s.history
    if type(h.sort) ~= "table" then h.sort = { id = "when", desc = true } end
    if not h.filter then h.filter = "all" end
    return h
end

local function status(e)
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
-- Rows
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
    row.when = cell("LEFT", 6, 104)
    row.from = cell("LEFT", 112, 92)
    row.kind = cell("LEFT", 206, 96)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 304, 0)
    row.what = cell("LEFT", 304)
    row.what:SetPoint("RIGHT", -58, 0)
    row.kept = cell("RIGHT", -6, 48, "RIGHT")
    row:SetScript("OnClick", function(self)
        local e = self.entry
        if e and e.kind == "item" and e.id then Stonks:ShowItem(tostring(e.id)) end
    end)
    U.tooltip(row, function(tt, self)
        local e = self.entry
        if not e then return end
        tt:SetText(Log.KINDS[e.kind] or e.kind)
        local function line(label, value) tt:AddDoubleLine(label, value, DIM[1], DIM[2], DIM[3], 1, 1, 1) end
        line("From", Codec.safeText(e.from))
        line("Received", date("%a %d %b %H:%M", e.t))
        if e.last and e.last - e.t >= 60 then line("Last message", date("%a %d %b %H:%M", e.last)) end
        if e.hour then
            line(e.kind == "summary" and "Their data up to" or "Scan from", date("%d %b %H:00", e.hour * 3600))
        end
        if e.kind == "item" then
            if e.id then
                local link = U.linkFor(tostring(e.id))
                line("Item", link or U.itemName(tostring(e.id)))
            end
            if e.med then line("Their median price", U.coin(e.med)) end
            line("Imported", (e.kept or 0) > 0 and "yes" or "no, too far from your own prices")
        else
            line(e.kind == "summary" and "Item summaries" or "Item prices", tostring(e.got or 0))
            if e.expected and e.expected ~= e.got then line("Sender announced", tostring(e.expected)) end
            line("Kept", tostring(e.kept or 0))
            tt:AddLine("Prices are skipped when you already have your own price for that hour, when they barely moved since the last guild price, or when they are more than 5x away from your own.", DIM[1], DIM[2], DIM[3], true)
        end
        local _, text = status(e)
        tt:AddLine(text, INK[1], INK[2], INK[3], true)
        if e.kind == "item" and e.id then tt:AddLine("Click to show its price history.", TEAL_SOFT[1], TEAL_SOFT[2], TEAL_SOFT[3]) end
    end)
end

local function fillRow(row, e)
    initRow(row)
    row.entry = e
    row.when:SetText(date("%a %d %b %H:%M", e.t))
    row.from:SetText(Codec.safeText(e.from))
    row.kind:SetText(Log.KINDS[e.kind] or e.kind)
    if e.kind == "item" and e.id then
        local key = tostring(e.id)
        row.icon:SetTexture(U.itemIcon(key))
        row.icon:Show()
        row.what:SetPoint("LEFT", 322, 0)
        row.what:SetTextColor(U.itemQualityColor(key))
    else
        row.icon:Hide()
        row.what:SetPoint("LEFT", 304, 0)
        U.setColor(row.what, INK)
    end
    row.what:SetText(whatText(e))
    row.kept:SetText(keptText(e))
    local st = status(e)
    local c = (st == "done" or st == "receiving") and INK or (st == "stopped" and COPPER or DIM)
    U.setColor(row.when, c); U.setColor(row.from, c); U.setColor(row.kind, c)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local function matches(e, filter)
    if filter == "all" then return true end
    if filter == "shared" then return e.kind == "item" or e.kind == "scan" end
    return e.kind == filter
end

local function refresh()
    if not page or not page:IsShown() then return end
    local h = settings()
    local rows = {}
    for _, e in ipairs(Log.Entries()) do
        if type(e) == "table" and e.t and matches(e, h.filter) then
            rows[#rows + 1] = { entry = e, name = e.from or "" }
        end
    end
    U.SortRows(rows, h.sort, function(d, id)
        local e = d.entry
        if id == "when" then return e.t end
        if id == "from" then return e.from end
        if id == "kind" then return Log.KINDS[e.kind] end
        if id == "what" then return e.kind == "item" and whatText(e) or ("~" .. ("%09d"):format(e.got or 0)) end
        if id == "kept" then return e.kept end
    end)
    local list = {}
    for i, d in ipairs(rows) do list[i] = d.entry end
    box:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    page.empty:SetShown(#list == 0)
    for _, b in ipairs(filterButtons) do b:SetOn(b.filter == h.filter) end

    local r = Stonks.realmData
    local mode = Sync and Sync.Mode and Sync.Mode() or "off"
    local last = r and r.sync and r.sync.at and ("   Last login summary: %s, %s."):format(Codec.safeText(r.sync.from), date("%d %b %H:%M", r.sync.at)) or ""
    summary:SetText("Guild sharing is " .. (MODE_TEXT[mode] or mode) .. "." .. last)
    footer:SetText(("%d deliveries kept (the last 30 days). Times in your computer's time zone."):format(#Log.Entries()))
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
    sub:SetText("When and from whom you received guild prices.")
    U.setColor(sub, INK)

    summary = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", 14, -68)
    summary:SetPoint("TOPRIGHT", -14, -68)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(false)
    U.setColor(summary, INK)

    local x = 14
    for _, f in ipairs(FILTERS) do
        local b = U.ToggleButton(page, f[2], f[3])
        b.filter = f[1]
        b:SetPoint("TOPLEFT", x, -88)
        x = x + f[3] + 4
        b:SetScript("OnClick", function()
            settings().filter = f[1]
            refresh()
        end)
        filterButtons[#filterButtons + 1] = b
    end

    local pane = U.well(page)
    pane:SetPoint("TOPLEFT", 10, -114)
    pane:SetPoint("BOTTOMRIGHT", -10, 28)
    local head = CreateFrame("Frame", nil, pane)
    head:SetPoint("TOPLEFT", 3, -3)
    head:SetPoint("TOPRIGHT", -17, -3)
    head:SetHeight(18)
    local headBg = head:CreateTexture(nil, "BACKGROUND")
    headBg:SetAllPoints()
    U.gradient(headBg, "VERTICAL", 0.09, 0.06, 0.04, 1, 0.17, 0.13, 0.09, 1)
    U.SortHeader(head, {
        { id = "when", label = "When", point = "LEFT", x = 6, width = 100, desc = true, tip = "When the first message of it arrived." },
        { id = "from", label = "From", point = "LEFT", x = 112, width = 90, tip = "The guildmate who sent it." },
        { id = "kind", label = "Type", point = "LEFT", x = 206, width = 94, tip = "Hourly guild scan, login summary, or an item or scan shared by chat link." },
        { id = "what", label = "Received", point = "LEFT", x = 304, width = 90, desc = true, tip = "Number of item prices received, or the shared item." },
        { id = "kept", label = "Kept", point = "RIGHT", x = -6, width = 48, desc = true, tip = "How many of them were added to your data." },
    }, settings().sort, refresh)

    box = CreateFrame("Frame", nil, pane, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", 3, -23)
    box:SetPoint("BOTTOMRIGHT", -14, 3)
    local bar = CreateFrame("EventFrame", nil, pane, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 2, -2)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 2, 2)
    bar:SetHideIfUnscrollable(true)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(20)
    view:SetElementInitializer("EncoreStonksSyncRowTemplate", fillRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)

    page.empty = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    page.empty:SetPoint("CENTER", 0, -10)
    page.empty:SetWidth(360)
    page.empty:SetText("Nothing received yet. Guild scans, your login summary and prices shared by chat link show up here.")
    U.setColor(page.empty, DIM)

    footer = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", 16, 9)
    footer:SetPoint("RIGHT", page, "BOTTOMRIGHT", -100, 0)
    footer:SetJustifyH("LEFT")
    footer:SetWordWrap(false)
    U.setColor(footer, DIM)

    local clear = U.ToggleButton(page, "Clear", 60)
    clear:SetPoint("BOTTOMRIGHT", -26, 4) -- clear of the resize grip
    clear:SetScript("OnClick", function()
        if IsShiftKeyDown() then Log.Clear() end
    end)
    U.tooltip(clear, function(tt)
        tt:SetText("Clear the sync history")
        tt:AddLine("Shift-click to empty this list. The prices you received stay.", 1, 1, 1, true)
    end)

    -- Item names arrive from the server a moment after they are asked for.
    page:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    page:SetScript("OnEvent", refreshSoon)
    page:SetScript("OnShow", refresh)
    return page
end
