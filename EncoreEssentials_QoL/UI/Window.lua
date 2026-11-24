-- Encore-QoL: the window. Encore portrait frame, tabs down the left, a search box across every option, and an
-- Overview tab that lists who runs what. Rows are built from the feature list, so new features show up here
-- (and in search and the Overview) without extra code.
local _, ns = ...
local Q = ns.QoL
local W = Q.W

local WIDTH, HEIGHT = 860, 600
local SIDEBAR = 160
local CONTENT_W = WIDTH - SIDEBAR - 60

local frame, scroll, content, search, tabButtons, overview
local currentTab = "overview"
local rows = {}

local TAB_NAME = {}
for _, t in ipairs(Q.TABS) do TAB_NAME[t.id] = t.name end

---------------------------------------------------------------------------
-- Feature rows
---------------------------------------------------------------------------
local function optionLocked(f) return not f.active end

local function buildControl(row, f, o)
    local c
    if o.kind == "check" then
        c = W.Check(row, o.name)
        c.onChange = function(v) f:Set(o.key, v) end
        c.Refresh = function(self) self:SetChecked(f:Get(o.key) == true) end
        c.height = 24
    elseif o.kind == "slider" then
        c = W.Slider(row, o.name, {
            width = CONTENT_W - 60, min = o.min, max = o.max, step = o.step, fmt = o.fmt, marker = o.marker,
            onChange = function(v) f:Set(o.key, v) end,
        })
        c.Refresh = function(self) self:SetValue(tonumber(f:Get(o.key)) or o.min) end
        c.height = 36
    elseif o.kind == "choice" then
        c = W.Choice(row, o.name, type(o.choices) == "function" and o.choices() or o.choices, function(v) f:Set(o.key, v) end)
        c:SetWidth(CONTENT_W - 60)
        c.Refresh = function(self) self:SetValue(f:Get(o.key)) end
        c.height = 26
    elseif o.kind == "color" then
        c = W.Swatch(row, o.name, function(v) f:Set(o.key, v) end)
        c:SetWidth(CONTENT_W - 60)
        c.Refresh = function(self) self:SetValue(f:Get(o.key) or { 1, 1, 1 }) end
        c.height = 24
    elseif o.kind == "edit" then
        c = W.Edit(row, o.name, function(v) f:Set(o.key, v) end)
        c:SetWidth(CONTENT_W - 60)
        c.Refresh = function(self) self:SetValue(f:Get(o.key)) end
        c.height = 24
    elseif o.kind == "button" then
        c = W.Button(row, o.name, function() o.onClick(f) end, o.width or 180)
        c.height = 26
        c.always = o.always -- usable while the feature is off (e.g. Preview)
    elseif o.kind == "note" then
        c = CreateFrame("Frame", nil, row)
        c:SetSize(CONTENT_W - 60, 16)
        c.text = W.Text(c, "GameFontNormalSmall", "", W.DIM)
        c.text:SetPoint("TOPLEFT")
        c.text:SetWidth(CONTENT_W - 60)
        c.Refresh = function(self) self.text:SetText(type(o.text) == "function" and o.text(f) or o.text) end
        c:Refresh()
        c.height = math.max(16, (c.text:GetStringHeight() or 12) + 4)
        c.always = true
    end
    if c and o.tip then W.Tooltip(c.button or c.slider or c, o.name, o.tip) end
    return c
end

local function buildRow(f)
    local row = CreateFrame("Frame", nil, content)
    row:SetWidth(CONTENT_W)
    row.feature = f
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.3)

    row.switch = W.Check(row, "")
    row.switch:SetPoint("TOPLEFT", 6, -6)
    row.switch.onChange = function(v) Q:SetEnabled(f.id, v) end
    row.name = W.Text(row, "GameFontNormal", f.name, W.GOLD)
    row.name:SetPoint("LEFT", row.switch, "RIGHT", 4, 0)
    row.badge = W.Badge(row)
    row.badge:SetPoint("TOPRIGHT", -8, -9)
    W.Tooltip(row.badge, function()
        if f.status == "locked" or f.status == "replaced" then return f.owner end
    end, function()
        if f.status == "replaced" then return "That addon replaced this frame, so Encore leaves it alone." end
        if f.status == "locked" then return "That addon already does this. Turn it off there and this switch unlocks." end
    end)

    local y = -32
    row.desc = W.Text(row, "GameFontHighlightSmall", f.desc or "", W.INK)
    row.desc:SetPoint("TOPLEFT", 36, y)
    row.desc:SetWidth(CONTENT_W - 50)
    y = y - math.max(12, row.desc:GetStringHeight() or 12) - 4
    if f.idea then
        row.idea = W.Text(row, "GameFontNormalSmall", "Idea from " .. f.idea, W.DIM)
        row.idea:SetPoint("TOPLEFT", 36, y)
        y = y - 14
    end

    row.controls = {}
    for _, o in ipairs(f.options or {}) do
        local c = buildControl(row, f, o)
        if c then
            y = y - 4
            c:SetPoint("TOPLEFT", 36, y)
            y = y - c.height
            row.controls[#row.controls + 1] = c
        end
    end
    row:SetHeight(-y + 8)

    function row:Refresh()
        self.switch:SetChecked(f:Saved().on == true and not f.owner)
        self.switch:SetLocked(f.owner ~= nil)
        self.badge:SetStatus(f)
        for _, c in ipairs(self.controls) do
            if c.Refresh then c:Refresh() end
            if c.SetLocked then c:SetLocked(not c.always and optionLocked(f)) end
        end
    end
    return row
end

local function rowFor(f)
    local row = rows[f.id]
    if not row then
        row = buildRow(f)
        rows[f.id] = row
    end
    return row
end

local headers = {}
local function header(i)
    local h = headers[i]
    if not h then
        h = CreateFrame("Frame", nil, content)
        h:SetSize(CONTENT_W, 26)
        h.text = W.Text(h, "GameFontNormalLarge", "", W.GOLD)
        h.text:SetPoint("BOTTOMLEFT", 2, 4)
        local fontPath = h.text:GetFont()
        if h.text:SetFont(W.FONT_TITLE, 16, "") == false and fontPath then h.text:SetFont(fontPath, 16, "") end
        local line = h:CreateTexture(nil, "ARTWORK")
        line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
        line:SetColorTexture(W.COPPER[1], W.COPPER[2], W.COPPER[3], 0.6)
        headers[i] = h
    end
    return h
end

---------------------------------------------------------------------------
-- Overview: every feature that is on or owned by another addon, sortable by any column.
---------------------------------------------------------------------------
local OV_COLS = {
    { key = "name", title = "Feature", width = 230 },
    { key = "tab", title = "Tab", width = 120 },
    { key = "status", title = "Status", width = 110 },
    { key = "owner", title = "Addon", width = 160 },
}
local STATUS_TEXT = { on = "On · Encore", locked = "Locked", replaced = "Replaced", error = "Error", off = "Off" }
local ovSort = { key = "status", desc = false }

local function buildOverview()
    overview = CreateFrame("Frame", nil, content)
    overview:SetWidth(CONTENT_W)
    overview.summary = W.Text(overview, "GameFontHighlight", "", W.INK)
    overview.summary:SetPoint("TOPLEFT", 4, -4)
    overview.summary:SetWidth(CONTENT_W - 8)
    local x = 4
    overview.heads = {}
    for _, col in ipairs(OV_COLS) do
        local b = CreateFrame("Button", nil, overview)
        b:SetSize(col.width, 20)
        b:SetPoint("TOPLEFT", x, -44)
        b.text = W.Text(b, "GameFontNormalSmall", col.title, W.GOLD)
        b.text:SetPoint("LEFT", 4, 0)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.92, 0.58, 0.2, 0.15)
        b:SetScript("OnClick", function()
            if ovSort.key == col.key then ovSort.desc = not ovSort.desc else ovSort.key, ovSort.desc = col.key, false end
            Q:RefreshWindow()
        end)
        x = x + col.width
        overview.heads[#overview.heads + 1] = b
    end
    overview.lines = {}
end

local function overviewLine(i)
    local l = overview.lines[i]
    if l then return l end
    l = CreateFrame("Button", nil, overview)
    l:SetSize(CONTENT_W - 8, 20)
    l:SetPoint("TOPLEFT", 4, -64 - (i - 1) * 20)
    local bg = l:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
    local hl = l:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.92, 0.58, 0.2, 0.15)
    l.cells = {}
    local x = 4
    for c, col in ipairs(OV_COLS) do
        local fs = W.Text(l, "GameFontHighlightSmall", "")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(col.width - 8)
        fs:SetWordWrap(false)
        l.cells[c] = fs
        x = x + col.width
    end
    l:SetScript("OnClick", function(self) if self.tab then Q:ShowTab(self.tab) end end)
    overview.lines[i] = l
    return l
end

local function refreshOverview()
    local list, on, locked = {}, 0, 0
    for _, f in ipairs(Q.order) do
        if f.status == "on" then on = on + 1 end
        if f.status == "locked" or f.status == "replaced" then locked = locked + 1 end
        if f.status ~= "off" then
            list[#list + 1] = { f = f, name = f.name, tab = TAB_NAME[f.tab] or f.tab, status = STATUS_TEXT[f.status] or f.status, owner = f.owner or "Encore" }
        end
    end
    overview.summary:SetText(("%d features. %d on in Encore, %d run by another addon (those switches stay locked until you turn them off there). Click a column to sort, a line to open its tab.")
        :format(#Q.order, on, locked))
    table.sort(list, function(a, b)
        local x, y = tostring(a[ovSort.key]), tostring(b[ovSort.key])
        if x == y then return a.name < b.name end
        if ovSort.desc then return x > y end
        return x < y
    end)
    for i, item in ipairs(list) do
        local l = overviewLine(i)
        l.tab = item.f.tab
        l.cells[1]:SetText(item.name)
        l.cells[2]:SetText(item.tab)
        l.cells[3]:SetText(item.status)
        W.Color(l.cells[3], item.f.status == "on" and W.TEAL or W.GOLD)
        l.cells[4]:SetText(item.owner)
        l:Show()
    end
    for i = #list + 1, #overview.lines do overview.lines[i]:Hide() end
    if #list == 0 then
        local l = overviewLine(1)
        l.tab = nil
        l.cells[1]:SetText("Nothing is on yet.")
        for c = 2, 4 do l.cells[c]:SetText("") end
        l:Show()
    end
    overview:SetHeight(70 + math.max(1, #list) * 20)
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
local function matches(f, text)
    if text == "" then return true end
    local hay = (f.name .. " " .. (f.desc or "") .. " " .. (f.section or "")):lower()
    for _, o in ipairs(f.options or {}) do hay = hay .. " " .. (o.name or ""):lower() end
    return hay:find(text, 1, true) ~= nil
end

local function layout()
    for _, r in pairs(rows) do r:Hide() end
    for _, h in ipairs(headers) do h:Hide() end
    if overview then overview:Hide() end

    local text = search and strtrim(search:GetText() or ""):lower() or ""
    local y, hi = -4, 0
    if text == "" and currentTab == "overview" then
        if not overview then buildOverview() end
        overview:ClearAllPoints()
        overview:SetPoint("TOPLEFT", 0, y)
        refreshOverview()
        overview:Show()
        y = y - overview:GetHeight()
    else
        local lastSection
        for _, f in ipairs(Q.order) do
            if (text ~= "" or f.tab == currentTab) and matches(f, text) then
                local section = text ~= "" and (TAB_NAME[f.tab] or f.tab) or f.section
                if section and section ~= lastSection then
                    hi = hi + 1
                    local h = header(hi)
                    h.text:SetText(section)
                    h:ClearAllPoints()
                    h:SetPoint("TOPLEFT", 0, y)
                    h:Show()
                    y = y - 30
                    lastSection = section
                end
                local row = rowFor(f)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, y)
                row:Refresh()
                row:Show()
                y = y - row:GetHeight() - 6
            end
        end
        if text ~= "" and hi == 0 then
            hi = 1
            local h = header(1)
            h.text:SetText("Nothing matches \"" .. text .. "\"")
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 0, y)
            h:Show()
            y = y - 30
        end
    end
    content:SetHeight(math.max(10, -y + 10))
    for id, b in pairs(tabButtons) do b:SetSelected(text == "" and id == currentTab) end
end

function Q:RefreshWindow()
    if frame and frame:IsShown() then layout() end
end

function Q:ShowTab(id)
    currentTab = id
    if search then search:SetText("") end
    if not frame then self:ToggleWindow() return end
    if not frame:IsShown() then frame:Show() end
    layout()
    if scroll then scroll:SetVerticalScroll(0) end
end

local function create()
    frame = CreateFrame("Frame", "EncoreQoLFrame", UIParent, "PortraitFrameTemplate")
    frame:Hide()
    tinsert(UISpecialFrames, "EncoreQoLFrame")
    frame:SetSize(WIDTH, HEIGHT)
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        Q.db.window.point = { p, rp, x, y }
    end)
    local p = Q.db.window.point
    if type(p) == "table" and p[1] then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else frame:SetPoint("CENTER") end
    frame:SetTitle("Encore-QoL")
    if frame.CloseButton then frame.CloseButton:SetScript("OnClick", function() frame:Hide() end) end
    local portrait = frame.GetPortrait and frame:GetPortrait() or frame.portrait
    if portrait then
        portrait:SetTexture(Q.ICON)
        portrait:SetTexCoord(0, 1, 0, 1)
    end
    if frame.NineSlice then
        for _, region in ipairs({ frame.NineSlice:GetRegions() }) do
            if region.SetVertexColor then region:SetVertexColor(1, 0.74, 0.5) end
        end
    end
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetPoint("TOPLEFT", 4, -22); bg:SetPoint("BOTTOMRIGHT", -4, 4)
    bg:SetColorTexture(0.07, 0.05, 0.04, 0.96)

    -- Search box across all tabs
    search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    search:SetSize(SIDEBAR - 16, 22)
    search:SetPoint("TOPLEFT", 16, -64)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function() layout() end)

    -- Tabs down the left
    tabButtons = {}
    local y = -96
    for _, t in ipairs(Q.TABS) do
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(SIDEBAR - 12, 26)
        b:SetPoint("TOPLEFT", 10, y)
        local sel = b:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetColorTexture(0.7, 0.04, 0.03, 0.6)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.92, 0.58, 0.2, 0.15)
        b.text = W.Text(b, "GameFontNormal", t.name, W.GOLD)
        b.text:SetPoint("LEFT", 10, 0)
        function b:SetSelected(on)
            sel:SetShown(on)
            W.Color(self.text, on and W.GOLD or W.INK)
        end
        b:SetScript("OnClick", function() Q:ShowTab(t.id) end)
        tabButtons[t.id] = b
        y = y - 28
    end
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", SIDEBAR + 4, -60)
    divider:SetPoint("BOTTOMLEFT", SIDEBAR + 4, 12)
    divider:SetWidth(1)
    divider:SetColorTexture(W.COPPER[1], W.COPPER[2], W.COPPER[3], 0.6)

    local version = W.Text(frame, "GameFontNormalSmall", "v" .. Q.version, W.DIM)
    version:SetPoint("BOTTOMLEFT", 16, 12)

    scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", SIDEBAR + 14, -64)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 10)
    scroll:SetScrollChild(content)

    frame:SetScript("OnShow", function()
        Q:Recheck()
        layout()
    end)
    Q.callbacks[#Q.callbacks + 1] = function() Q:RefreshWindow() end
end

function Q:ToggleWindow()
    if not self.ready then return end
    if not frame then create() end
    frame:SetShown(not frame:IsShown())
end

-- Options > AddOns > Encore Essentials > Encore-QoL: a short page that opens the window.
local Encore = _G.EncoreEssentials
if Encore and Encore.AddOptionsPage then
    Q.optionsCategory = Encore:AddOptionsPage("Encore-QoL", {
        { kind = "header", text = "Encore-QoL" },
        { kind = "button", text = "Open Encore-QoL", tooltip = "All Encore-QoL features are in their own window. /eqol opens it too.",
            onClick = function()
                HideUIPanel(SettingsPanel)
                Q:ToggleWindow()
            end },
    })
end
