-- Encore-QoL: the window, laid out like the game's Options window. A tree on the left (Overview, then each tab
-- with its sections), a page on the right with one block per feature: a header bar with the switch, the name and
-- its status, a line on what it does, then label and setting rows in groups. Drag the corner to resize.
-- Everything is built from the feature list, so new features show up here, in search and in the Overview.
local _, ns = ...
local Q = ns.QoL
local W = Q.W

local MIN_W, MIN_H, MAX_W, MAX_H = 720, 440, 1600, 1100
local DEFAULT_W, DEFAULT_H = 900, 620
local TREE_W = 210
local ROW_H = 26

local frame, treeScroll, tree, pageScroll, page, search
local crumb, title, overview
local blocks, nodes, tabHeads = {}, {}, {}
local needsLayout = false

local TAB_NAME = {}
for _, t in ipairs(Q.TABS) do TAB_NAME[t.id] = t.name end

local function saved() return Q.db.window end

---------------------------------------------------------------------------
-- Option groups: a "group" option starts a heading; when(f) decides if the group shows.
---------------------------------------------------------------------------
local function optionGroups(f)
    local groups, g = {}, { items = {} }
    for _, o in ipairs(f.options or {}) do
        if o.kind == "group" then
            if #g.items > 0 or g.title then groups[#groups + 1] = g end
            g = { title = o.text, when = o.when, items = {} }
        else
            g.items[#g.items + 1] = o
        end
    end
    if #g.items > 0 or g.title then groups[#groups + 1] = g end
    return groups
end

local function groupShown(f, g)
    if not g.when then return true end
    local ok, v = pcall(g.when, f)
    return ok and v and true or false
end

---------------------------------------------------------------------------
-- Controls (all on one row: the label sits in the left column)
---------------------------------------------------------------------------
local function noteText(f, o)
    local t = o.text
    if type(t) == "function" then t = t(f) end
    return type(t) == "string" and t or ""
end

local function buildControl(parent, f, o)
    local c
    if o.kind == "check" then
        c = W.Check(parent, "")
        c.onChange = function(v) f:Set(o.key, v) end
        c.Refresh = function(self) self:SetChecked(f:Get(o.key) == true) end
        c.fixed = true
    elseif o.kind == "slider" then
        c = W.Slider(parent, nil, {
            inline = true, width = 300, min = o.min, max = o.max, step = o.step, fmt = o.fmt, marker = o.marker,
            onChange = function(v) f:Set(o.key, v) end,
        })
        c.Refresh = function(self) self:SetValue(tonumber(f:Get(o.key)) or o.min) end
        c.maxW = 320
    elseif o.kind == "choice" then
        c = W.Choice(parent, "", type(o.choices) == "function" and o.choices() or o.choices, function(v) f:Set(o.key, v) end)
        c.Refresh = function(self) self:SetValue(f:Get(o.key)) end
        c.maxW = 220
        c.Resize = function(self, w) self:SetWidth(w) self.button:SetWidth(w) end
    elseif o.kind == "color" then
        c = W.Swatch(parent, "", function(v) f:Set(o.key, v) end)
        c:SetWidth(40)
        c.Refresh = function(self) self:SetValue(f:Get(o.key) or { 1, 1, 1 }) end
        c.fixed = true
    elseif o.kind == "edit" then
        c = W.Edit(parent, "", function(v) f:Set(o.key, v) end)
        c.Refresh = function(self) self:SetValue(f:Get(o.key)) end
        c.maxW = 220
    elseif o.kind == "button" then
        c = W.Button(parent, o.name, function() o.onClick(f) end, o.width or 160)
        c.always = o.always -- usable while the feature is off (e.g. Preview)
        c.fixed = true
    elseif o.kind == "note" then
        c = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c:SetJustifyH("LEFT")
        W.Color(c, W.DIM)
        c.Refresh = function(self) self:SetText(noteText(f, o)) end
        c.always = true
    end
    if c then c.kind = o.kind end
    if c and o.tip and c.HookScript then W.Tooltip(c.button or c.slider or c, o.name, o.tip) end
    return c
end

---------------------------------------------------------------------------
-- Feature blocks
---------------------------------------------------------------------------
local function buildBlock(f)
    local b = CreateFrame("Frame", nil, page)
    b.feature = f

    -- Header bar: copper wash fading right, a copper edge on the left.
    b.head = CreateFrame("Frame", nil, b)
    b.head:SetHeight(28)
    b.head:SetPoint("TOPLEFT")
    b.head:SetPoint("TOPRIGHT")
    local wash = b.head:CreateTexture(nil, "BACKGROUND")
    wash:SetAllPoints()
    wash:SetColorTexture(1, 1, 1, 1)
    if not pcall(wash.SetGradient, wash, "HORIZONTAL", CreateColor(0.92, 0.58, 0.22, 0.22), CreateColor(0.92, 0.58, 0.22, 0)) then
        wash:SetColorTexture(0.92, 0.58, 0.22, 0.12)
    end
    local edge = b.head:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT"); edge:SetPoint("BOTTOMLEFT"); edge:SetWidth(2)
    edge:SetColorTexture(W.COPPER[1], W.COPPER[2], W.COPPER[3], 1)
    b.switch = W.Switch(b.head)
    b.switch:SetPoint("LEFT", 10, 0)
    b.switch.onChange = function(v) Q:SetEnabled(f.id, v) end
    W.Tooltip(b.switch, function() return f.owner and f.owner or (f:Saved().on and "Turn off" or "Turn on") end, function()
        if f.owner then return "That addon already does this. Turn it off there and this switch unlocks." end
    end)
    b.badge = W.Badge(b.head)
    b.badge:SetPoint("RIGHT", -8, 0)
    W.Tooltip(b.badge, function()
        if f.status == "locked" or f.status == "replaced" then return f.owner end
        if f.status == "on" then return "On in Encore" end
        if f.status == "error" then return "Error" end
        return "Off"
    end, function()
        if f.status == "replaced" then return "That addon replaced this frame, so Encore leaves it alone." end
        if f.status == "locked" then return "That addon already does this. Turn it off there and this switch unlocks." end
        if f.status == "on" then return "Encore runs this feature." end
        if f.status == "error" then return "Something went wrong turning this on. Type /console scriptErrors 1 and /reload to see the error." end
        return "Nobody runs this yet. Use the switch to turn it on."
    end)
    b.name = W.Text(b.head, "GameFontNormal", f.name, W.GOLD)
    b.name:SetPoint("LEFT", b.switch, "RIGHT", 10, 0)
    b.name:SetPoint("RIGHT", b.badge, "LEFT", -8, 0)
    b.name:SetWordWrap(false)

    b.desc = W.Text(b, "GameFontHighlightSmall", f.desc or "", W.DIM)

    b.lock = CreateFrame("Frame", nil, b)
    W.Panel(b.lock, 0.85)
    b.lock.text = W.Text(b.lock, "GameFontHighlightSmall", "", W.INK)
    b.lock.text:SetPoint("TOPLEFT", 8, -6)

    b.groups = optionGroups(f)
    b.controls = {}
    for _, g in ipairs(b.groups) do
        if g.title then
            g.heading = W.Text(b, "GameFontNormalSmall", g.title:upper(), W.COPPER)
            g.heading:SetSpacing(2)
        end
        g.rows = {}
        for _, o in ipairs(g.items) do
            local c = buildControl(b, f, o)
            if c then
                local row = { o = o, control = c }
                if o.kind ~= "note" and o.kind ~= "button" then
                    row.label = W.Text(b, "GameFontHighlight", o.name or "", W.INK)
                    row.label:SetWordWrap(true)
                end
                row.sep = b:CreateTexture(nil, "BACKGROUND")
                row.sep:SetHeight(1)
                row.sep:SetColorTexture(1, 1, 1, 0.06)
                g.rows[#g.rows + 1] = row
                b.controls[#b.controls + 1] = c
            end
        end
    end

    -- Lays the block out at this width; returns its height.
    function b:Layout(width)
        self:SetWidth(width)
        local y = -32
        self.desc:ClearAllPoints()
        self.desc:SetPoint("TOPLEFT", 12, y)
        self.desc:SetWidth(width - 24)
        y = y - math.max(12, self.desc:GetStringHeight() or 12) - 6
        if f.owner then
            self.lock.text:SetWidth(width - 40)
            self.lock.text:SetText(("%s already does this, so Encore leaves it alone. Turn it off in %s and this switch unlocks.")
                :format(f.owner, f.owner))
            local h = (self.lock.text:GetStringHeight() or 12) + 12
            self.lock:ClearAllPoints()
            self.lock:SetPoint("TOPLEFT", 12, y)
            self.lock:SetSize(width - 24, h)
            self.lock:Show()
            y = y - h - 6
        else
            self.lock:Hide()
        end
        local labelX = 12
        local ctrlX = labelX + math.floor((width - labelX) * 0.44)
        local ctrlW = width - ctrlX - 10
        self.visibleGroups = ""
        for gi, g in ipairs(self.groups) do
            local shown = groupShown(f, g)
            self.visibleGroups = self.visibleGroups .. (shown and "1" or "0")
            if g.heading then g.heading:SetShown(shown) end
            for _, row in ipairs(g.rows) do
                row.control:SetShown(shown)
                if row.label then row.label:SetShown(shown) end
                row.sep:SetShown(shown)
            end
            if shown then
                if g.heading then
                    y = y - (gi > 1 and 8 or 2)
                    g.heading:ClearAllPoints()
                    g.heading:SetPoint("TOPLEFT", labelX, y)
                    y = y - 16
                end
                local bx -- buttons in a row share one line
                for ri, row in ipairs(g.rows) do
                    local o, c = row.o, row.control
                    c:ClearAllPoints()
                    if o.kind == "button" then
                        local nextIsButton = g.rows[ri + 1] and g.rows[ri + 1].o.kind == "button"
                        if not bx then y = y - 4 bx = labelX end
                        c:SetPoint("TOPLEFT", bx, y)
                        bx = bx + c:GetWidth() + 8
                        row.sep:Hide()
                        if not nextIsButton then y = y - 26 bx = nil end
                    elseif o.kind == "note" then
                        c:SetWidth(width - 24)
                        if c.Refresh then c:Refresh() end
                        local h = math.max(12, c:GetStringHeight() or 12)
                        c:SetPoint("TOPLEFT", labelX, y - 4)
                        row.sep:Hide()
                        y = y - h - 8
                    else
                        row.label:SetWidth(ctrlX - labelX - 10)
                        local lh = math.max(14, row.label:GetStringHeight() or 14)
                        local h = math.max(ROW_H, lh + 10)
                        row.label:ClearAllPoints()
                        row.label:SetPoint("LEFT", self, "TOPLEFT", labelX, y - h / 2)
                        if not c.fixed then
                            local w = math.max(80, math.min(c.maxW or 220, ctrlW))
                            if c.Resize then c:Resize(w) else c:SetWidth(w) end
                        end
                        c:SetPoint("LEFT", self, "TOPLEFT", ctrlX, y - h / 2)
                        row.sep:ClearAllPoints()
                        row.sep:SetPoint("TOPLEFT", labelX, y - h)
                        row.sep:SetPoint("TOPRIGHT", -10, y - h)
                        y = y - h
                    end
                end
            end
        end
        local h = -y + 6
        self:SetHeight(h)
        return h
    end

    function b:Refresh()
        self.switch:SetChecked(f:Saved().on == true and not f.owner)
        self.switch:SetLocked(f.owner ~= nil)
        self.badge:SetStatus(f)
        for _, c in ipairs(self.controls) do
            if c.Refresh then c:Refresh() end
            if c.SetLocked then
                -- Settings can be changed while a feature is off; buttons act, so they need it on (unless always).
                local locked = f.owner ~= nil or (c.kind == "button" and not c.always and not f.active)
                c:SetLocked(locked)
            end
        end
    end

    -- True when a group appears or disappears (e.g. Custom rules after picking Custom).
    function b:GroupsChanged()
        local s = ""
        for _, g in ipairs(self.groups) do s = s .. (groupShown(f, g) and "1" or "0") end
        return s ~= self.visibleGroups
    end
    return b
end

local function blockFor(f)
    local b = blocks[f.id]
    if not b then
        b = buildBlock(f)
        blocks[f.id] = b
    end
    return b
end

---------------------------------------------------------------------------
-- Overview page: every feature that is on or run by another addon, sortable by any column.
---------------------------------------------------------------------------
local OV_COLS = {
    { key = "name", title = "Feature", share = 0.36 },
    { key = "tab", title = "Tab", share = 0.2 },
    { key = "status", title = "Status", share = 0.16 },
    { key = "owner", title = "Addon", share = 0.28 },
}
local STATUS_TEXT = { on = "On · Encore", locked = "Locked", replaced = "Replaced", error = "Error", off = "Off" }
local ovSort = { key = "status", desc = false }

local function buildOverview()
    overview = CreateFrame("Frame", nil, page)
    overview.summary = W.Text(overview, "GameFontHighlight", "", W.INK)
    overview.summary:SetPoint("TOPLEFT", 4, -4)
    overview.heads = {}
    for _, col in ipairs(OV_COLS) do
        local b = CreateFrame("Button", nil, overview)
        b:SetHeight(20)
        b.text = W.Text(b, "GameFontNormalSmall", col.title, W.GOLD)
        b.text:SetPoint("LEFT", 4, 0)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.92, 0.58, 0.2, 0.15)
        b:SetScript("OnClick", function()
            if ovSort.key == col.key then ovSort.desc = not ovSort.desc else ovSort.key, ovSort.desc = col.key, false end
            Q:RefreshWindow(true)
        end)
        overview.heads[#overview.heads + 1] = b
    end
    overview.line = overview:CreateTexture(nil, "ARTWORK")
    overview.line:SetHeight(1)
    overview.line:SetColorTexture(W.COPPER[1], W.COPPER[2], W.COPPER[3], 0.6)
    overview.lines = {}
end

local function overviewLine(i)
    local l = overview.lines[i]
    if l then return l end
    l = CreateFrame("Button", nil, overview)
    l:SetHeight(20)
    local bg = l:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
    local hl = l:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.92, 0.58, 0.2, 0.15)
    l.cells = {}
    for c = 1, #OV_COLS do
        local fs = W.Text(l, "GameFontHighlightSmall", "")
        fs:SetWordWrap(false)
        l.cells[c] = fs
    end
    l:SetScript("OnClick", function(self) if self.feature then Q:ShowFeature(self.feature) end end)
    overview.lines[i] = l
    return l
end

local function layoutOverview(width)
    if not overview then buildOverview() end
    overview:SetWidth(width)
    local list, on, locked = {}, 0, 0
    for _, f in ipairs(Q.order) do
        if f.status == "on" then on = on + 1 end
        if f.status == "locked" or f.status == "replaced" then locked = locked + 1 end
        if f.status ~= "off" then
            list[#list + 1] = { f = f, name = f.name, tab = TAB_NAME[f.tab] or f.tab, status = STATUS_TEXT[f.status] or f.status, owner = f.owner or "Encore" }
        end
    end
    overview.summary:SetWidth(width - 8)
    overview.summary:SetText(("%d features. %d on in Encore, %d run by another addon (those switches stay locked until you turn them off there). Click a column to sort, a line to open that feature.")
        :format(#Q.order, on, locked))
    local top = -(math.max(14, overview.summary:GetStringHeight() or 14) + 14)
    local x, widths = 4, {}
    for i, col in ipairs(OV_COLS) do
        widths[i] = math.floor((width - 8) * col.share)
        local b = overview.heads[i]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x, top)
        b:SetWidth(widths[i])
        b.text:SetText(col.title .. (ovSort.key == col.key and (ovSort.desc and " v" or " ^") or ""))
        x = x + widths[i]
    end
    overview.line:ClearAllPoints()
    overview.line:SetPoint("TOPLEFT", 4, top - 20)
    overview.line:SetPoint("TOPRIGHT", -4, top - 20)
    table.sort(list, function(a, b)
        local p, q = tostring(a[ovSort.key]), tostring(b[ovSort.key])
        if p == q then return a.name < b.name end
        if ovSort.desc then return p > q end
        return p < q
    end)
    local function place(l, i)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", 4, top - 22 - (i - 1) * 20)
        l:SetWidth(width - 8)
        local cx = 4
        for c, fs in ipairs(l.cells) do
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", cx, 0)
            fs:SetWidth(widths[c] - 8)
            cx = cx + widths[c]
        end
    end
    for i, item in ipairs(list) do
        local l = overviewLine(i)
        place(l, i)
        l.feature = item.f
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
        place(l, 1)
        l.feature = nil
        l.cells[1]:SetText("Nothing is on yet.")
        for c = 2, #OV_COLS do l.cells[c]:SetText("") end
        l:Show()
    end
    local h = -top + 26 + math.max(1, #list) * 20
    overview:SetHeight(h)
    return h
end

---------------------------------------------------------------------------
-- Tree: Overview, then each tab (opens and closes) with its sections.
---------------------------------------------------------------------------
local function sectionsOf(tab)
    local list, seen = {}, {}
    for _, f in ipairs(Q.order) do
        if f.tab == tab and f.section and not seen[f.section] then
            seen[f.section] = true
            list[#list + 1] = f.section
        end
    end
    return list
end

-- Side list rows in the shared Encore look (as in Encore-DB): EncoreEssentials/UI/Kit.lua UI.NavRow.
local function treeButton(kind)
    local b = CreateFrame("Button", nil, tree)
    b:SetHeight(kind == "tab" and 22 or 20)
    _G.EncoreEssentials.UI.NavRow(b)
    b.kind = kind
    return b
end

local function isPage(tab, section)
    local s = saved()
    return (search:GetText() or "") == "" and s.tab == tab and s.section == section
end

local function layoutTree()
    local y = -2
    local function place(b)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 2, y)
        b:SetPoint("RIGHT", tree, "RIGHT", -2, 0)
        b:Show()
        y = y - b:GetHeight() - 1
    end
    nodes.overview = nodes.overview or treeButton("top")
    _G.EncoreEssentials.UI.NavSet(nodes.overview, { text = "Overview", selected = isPage("overview", nil), indent = -14 })
    nodes.overview:SetScript("OnClick", function() Q:ShowPage("overview") end)
    place(nodes.overview)
    for _, t in ipairs(Q.TABS) do
        -- A tab without features (PvP when Encore-PvP isn't installed) isn't listed
        if t.id ~= "overview" and #sectionsOf(t.id) > 0 then
            local head = tabHeads[t.id]
            if not head then
                head = treeButton("tab")
                head:SetScript("OnClick", function()
                    local open = saved().open
                    open[t.id] = not open[t.id]
                    if open[t.id] then
                        local first = sectionsOf(t.id)[1]
                        if first then Q:ShowPage(t.id, first) return end
                    end
                    layoutTree()
                end)
                tabHeads[t.id] = head
            end
            local open = saved().open[t.id]
            _G.EncoreEssentials.UI.NavSet(head, { text = t.name, head = true, open = open })
            place(head)
            for _, section in ipairs(sectionsOf(t.id)) do
                local key = t.id .. "\001" .. section
                local leaf = nodes[key]
                if not leaf then
                    leaf = treeButton("leaf")
                    leaf:SetScript("OnClick", function() Q:ShowPage(t.id, section) end)
                    nodes[key] = leaf
                end
                if open then
                    _G.EncoreEssentials.UI.NavSet(leaf, { text = section, selected = isPage(t.id, section), indent = 4 })
                    place(leaf)
                else
                    leaf:Hide()
                end
            end
        end
    end
    tree:SetHeight(-y + 4)
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local secHeads = {}
local function secHead(i)
    local h = secHeads[i]
    if not h then
        h = CreateFrame("Frame", nil, page)
        h:SetHeight(24)
        h.text = W.Text(h, "GameFontNormalLarge", "", W.GOLD)
        h.text:SetPoint("BOTTOMLEFT", 2, 4)
        local line = h:CreateTexture(nil, "ARTWORK")
        line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
        line:SetColorTexture(W.COPPER[1], W.COPPER[2], W.COPPER[3], 0.6)
        secHeads[i] = h
    end
    return h
end

local function matches(f, text)
    local hay = (f.name .. " " .. (f.desc or "") .. " " .. (f.section or "") .. " " .. (TAB_NAME[f.tab] or "")):lower()
    for _, o in ipairs(f.options or {}) do hay = hay .. " " .. (o.name or o.text and type(o.text) == "string" and o.text or ""):lower() end
    return hay:find(text, 1, true) ~= nil
end

local function layoutPage()
    needsLayout = false
    if not frame then return end
    for _, b in pairs(blocks) do b:Hide() end
    for _, h in ipairs(secHeads) do h:Hide() end
    if overview then overview:Hide() end

    local width = math.max(300, math.floor(pageScroll:GetWidth() - 6))
    page:SetWidth(width)
    local s = saved()
    local text = strtrim(search:GetText() or ""):lower()
    local y = -2
    title:SetWidth(width - 8)
    if text ~= "" then
        crumb:SetText("Search")
        title:SetText(("Results for \"%s\""):format(search:GetText()))
    elseif s.tab == "overview" then
        crumb:SetText("Encore-QoL")
        title:SetText("Overview")
    else
        crumb:SetText(TAB_NAME[s.tab] or "")
        title:SetText(s.section or "")
    end
    y = y - 16 - 26

    if text == "" and s.tab == "overview" then
        local h = layoutOverview(width)
        overview:ClearAllPoints()
        overview:SetPoint("TOPLEFT", 0, y)
        overview:Show()
        y = y - h
    else
        local hi, lastTab = 0, nil
        for _, f in ipairs(Q.order) do
            local show
            if text ~= "" then show = matches(f, text) else show = f.tab == s.tab and f.section == s.section end
            if show then
                if text ~= "" and f.tab ~= lastTab then
                    hi = hi + 1
                    local h = secHead(hi)
                    h.text:SetText((TAB_NAME[f.tab] or f.tab) .. "  ·  " .. (f.section or ""))
                    h:ClearAllPoints()
                    h:SetPoint("TOPLEFT", 0, y)
                    h:SetWidth(width)
                    h:Show()
                    y = y - 30
                    lastTab = f.tab
                end
                local b = blockFor(f)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 0, y)
                b:Refresh()
                local h = b:Layout(width)
                b:Show()
                y = y - h - 10
            end
        end
        if text ~= "" and hi == 0 then
            hi = 1
            local h = secHead(1)
            h.text:SetText("Nothing matches. Try another word.")
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 0, y)
            h:SetWidth(width)
            h:Show()
            y = y - 30
        end
    end
    page:SetHeight(math.max(10, -y + 10))
    layoutTree()
end

-- Cheap refresh after a setting changes: switches, badges and values; a full layout only when groups appear or go.
local function refreshPage()
    local relayout = false
    for _, b in pairs(blocks) do
        if b:IsShown() then
            b:Refresh()
            if b:GroupsChanged() then relayout = true end
        end
    end
    if relayout or (overview and overview:IsShown()) then layoutPage() end
end

function Q:RefreshWindow(full)
    if not (frame and frame:IsShown()) then return end
    if full then layoutPage() else refreshPage() end
end

function Q:ShowPage(tab, section)
    local s = saved()
    s.tab, s.section = tab, section
    if tab ~= "overview" then s.open[tab] = true end
    if not frame then self:ToggleWindow() return end
    if search then search:SetText("") end
    if not frame:IsShown() then frame:Show() end
    layoutPage()
    pageScroll:SetVerticalScroll(0)
end

-- Opens the page that holds this feature and scrolls to it.
function Q:ShowFeature(f)
    self:ShowPage(f.tab, f.section)
    local b = blocks[f.id]
    if b and b:IsShown() then
        local top = page:GetTop() and b:GetTop() and (page:GetTop() - b:GetTop()) or 0
        pageScroll:SetVerticalScroll(math.max(0, math.min(top - 4, pageScroll:GetVerticalScrollRange())))
    end
end

-- Older callers: a tab opens its first section.
function Q:ShowTab(id)
    if id == "overview" then return self:ShowPage("overview") end
    self:ShowPage(id, sectionsOf(id)[1])
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function create()
    local s = saved()
    if type(s.open) ~= "table" then s.open = {} end
    if not s.tab or (s.tab ~= "overview" and not TAB_NAME[s.tab]) then s.tab, s.section = "overview", nil end

    frame = CreateFrame("Frame", "EncoreQoLFrame", UIParent, "PortraitFrameTemplate")
    frame:Hide()
    tinsert(UISpecialFrames, "EncoreQoLFrame")
    frame:SetSize(math.max(MIN_W, math.min(MAX_W, tonumber(s.w) or DEFAULT_W)), math.max(MIN_H, math.min(MAX_H, tonumber(s.h) or DEFAULT_H)))
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    else
        if frame.SetMinResize then frame:SetMinResize(MIN_W, MIN_H) end
        if frame.SetMaxResize then frame:SetMaxResize(MAX_W, MAX_H) end
    end
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        saved().point = { p, rp, x, y }
    end)
    local p = s.point
    if type(p) == "table" and p[1] then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else frame:SetPoint("CENTER") end
    frame:SetTitle("Encore-QoL")
    if frame.CloseButton then frame.CloseButton:SetScript("OnClick", function() frame:Hide() end) end
    -- The shared Encore frame with the Encore-QoL icon, as Encore-DB has it (EncoreEssentials/UI/Kit.lua)
    _G.EncoreEssentials.UI.Skin(frame, Q.ICON)

    -- Search across every setting
    search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    search:SetSize(TREE_W - 24, 22)
    search:SetPoint("TOPLEFT", 18, -62)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function() if frame:IsShown() then layoutPage() pageScroll:SetVerticalScroll(0) end end)
    if type(search.Instructions) == "table" then search.Instructions:SetText("Search all settings") end

    -- Tree
    treeScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    treeScroll:SetPoint("TOPLEFT", 10, -92)
    treeScroll:SetPoint("BOTTOMLEFT", 10, 30)
    treeScroll:SetWidth(TREE_W - 36) -- its scroll bar sits in the gap before the divider
    tree = CreateFrame("Frame", nil, treeScroll)
    tree:SetSize(TREE_W - 36, 10)
    treeScroll:SetScrollChild(tree)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", TREE_W, -58)
    divider:SetPoint("BOTTOMLEFT", TREE_W, 26)
    divider:SetWidth(1)
    divider:SetColorTexture(W.COPPER[1], W.COPPER[2], W.COPPER[3], 0.6)

    -- Page heading
    crumb = W.Text(frame, "GameFontNormalSmall", "", W.DIM)
    crumb:SetPoint("TOPLEFT", TREE_W + 16, -62)
    title = W.Text(frame, "GameFontNormalLarge", "", W.GOLD)
    title:SetPoint("TOPLEFT", crumb, "BOTTOMLEFT", 0, -4)
    title:SetWordWrap(false) -- the game's large gold font, as Encore-DB's headings

    pageScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    pageScroll:SetPoint("TOPLEFT", TREE_W + 14, -104)
    pageScroll:SetPoint("BOTTOMRIGHT", -30, 30)
    page = CreateFrame("Frame", nil, pageScroll)
    page:SetSize(400, 10)
    pageScroll:SetScrollChild(page)

    local version = W.Text(frame, "GameFontNormalSmall", "v" .. Q.version .. "  ·  /eqol", W.DIM)
    version:SetPoint("BOTTOMLEFT", 16, 10)

    -- Resize grip, bottom right
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -6, 6)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        local st = saved()
        st.w, st.h = math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5)
        local pp, _, rp, x, y = frame:GetPoint(1)
        st.point = { pp, rp, x, y }
        layoutPage()
    end)
    W.Tooltip(grip, "Resize", "Drag to make the window bigger or smaller.")

    -- Lay out again while resizing, at most once a frame.
    frame:SetScript("OnSizeChanged", function() needsLayout = true end)
    frame:SetScript("OnUpdate", function() if needsLayout then layoutPage() end end)
    frame:SetScript("OnShow", function()
        Q:Recheck()
        layoutPage()
    end)
    Q.callbacks[#Q.callbacks + 1] = function() Q:RefreshWindow() end
end

function Q:ToggleWindow()
    if not self.ready then return end
    if not frame then create() end
    frame:SetShown(not frame:IsShown())
end

-- Self-test (SelfTest.lua): builds the window and every feature's settings block without showing them.
-- Returns { [feature id or "window"] = error } and how many blocks were built.
function Q:SelfTestWindow()
    local errors, built = {}, 0
    if not frame then
        local ok, err = pcall(create)
        if not ok then errors.window = err return errors, 0 end
    end
    for _, f in ipairs(Q.order) do
        local ok, err = pcall(function()
            local b = blockFor(f)
            if b.Refresh then b:Refresh() end
        end)
        if ok then built = built + 1 else errors[f.id] = err end
    end
    return errors, built
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
