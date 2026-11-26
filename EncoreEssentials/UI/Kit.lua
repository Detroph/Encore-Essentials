-- Encore Essentials: the shared look for every Encore window (the copper-tinted portrait frame with the Encore crest
-- or the module icon, copper-edged buttons, dark wells, gold title).
-- Modules reach it as EncoreEssentials.UI. Built from plain frames so it works on every client.
local _, ns = ...
local Encore = ns.Encore
local UI = {}
Encore.UI = UI

UI.COPPER = { 0.92, 0.58, 0.22 }
UI.GOLD = { 1, 0.82, 0 }
UI.INK = { 0.95, 0.90, 0.81 }
UI.DIM = { 0.64, 0.57, 0.47 }
UI.RED = { 0.78, 0.15, 0.11 }
UI.GREEN = { 0.45, 0.85, 0.40 }
UI.TEAL = { 0.07, 0.78, 0.78 }
UI.BG = { 0.08, 0.06, 0.04 }

UI.FONT_TITLE = "Interface\\AddOns\\EncoreEssentials\\Media\\MarcellusSC.ttf"

function UI.Color(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end

-- Money as the game shows it: "12[g] 34[s] 5[c]" with the gold, silver and copper coin icons, zero parts left out.
-- Built here because WoW Forever has no GetCoinTextureString. short: no copper once there is gold.
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
function UI.Coins(copper, short)
    copper = math.floor((tonumber(copper) or 0) + 0.5)
    local neg = copper < 0
    if neg then copper = -copper end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = (BreakUpLargeNumbers and BreakUpLargeNumbers(g) or tostring(g)) .. GOLD_ICON end
    if s > 0 then out[#out + 1] = s .. SILVER_ICON end
    if c > 0 and not (short and g > 0) then out[#out + 1] = c .. COPPER_ICON end
    if #out == 0 then out[1] = "0" .. COPPER_ICON end
    return (neg and "-" or "") .. table.concat(out, " ")
end

-- Title text in the Encore title font, or the game's large font when that file isn't there.
function UI.TitleFont(fs, size)
    local ok = fs:SetFont(UI.FONT_TITLE, size or 16, "")
    if not ok then fs:SetFontObject(GameFontNormalLarge) end
    UI.Color(fs, UI.GOLD)
end

-- A 1-unit edge on all four sides, kept at least one real screen pixel at small UI scales.
function UI.Border(f, c, a, layer)
    local t = {}
    for i = 1, 4 do
        t[i] = f:CreateTexture(nil, layer or "BORDER")
        t[i]:SetColorTexture(c[1], c[2], c[3], a or 1)
        if t[i].SetSnapToPixelGrid then t[i]:SetSnapToPixelGrid(false); t[i]:SetTexelSnappingBias(0) end
    end
    t[1]:SetPoint("TOPLEFT"); t[1]:SetPoint("TOPRIGHT")
    t[2]:SetPoint("BOTTOMLEFT"); t[2]:SetPoint("BOTTOMRIGHT")
    t[3]:SetPoint("TOPLEFT"); t[3]:SetPoint("BOTTOMLEFT")
    t[4]:SetPoint("TOPRIGHT"); t[4]:SetPoint("BOTTOMRIGHT")
    local function thickness()
        local size = 1
        local scale = f.GetEffectiveScale and f:GetEffectiveScale()
        if PixelUtil and PixelUtil.GetNearestPixelSize and scale and scale > 0 then
            size = PixelUtil.GetNearestPixelSize(1, scale, 1)
        end
        t[1]:SetHeight(size); t[2]:SetHeight(size); t[3]:SetWidth(size); t[4]:SetWidth(size)
    end
    thickness()
    if f.HookScript then f:HookScript("OnShow", thickness) end
    function f:SetBorderColor(c2, a2) for _, x in ipairs(t) do x:SetColorTexture(c2[1], c2[2], c2[3], a2 or 1) end end
    return t
end

-- The same edge from separate colour values (Encore-DB and Encore-Stonks call it this way).
function UI.Edges(f, r, g, b, a, layer) return UI.Border(f, { r, g, b }, a, layer) end

function UI.Panel(f, alpha)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(UI.BG[1], UI.BG[2], UI.BG[3], alpha or 0.94)
    UI.Border(f, UI.COPPER, 0.8)
    return bg
end

function UI.Text(parent, template, text, c)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    if c then UI.Color(fs, c) end
    return fs
end

-- Tooltip that follows the mouse. title and body can be strings or functions of the frame.
function UI.Tooltip(frame, title, body)
    frame:HookScript("OnEnter", function(self)
        local t = title
        if type(t) == "function" then t = t(self) end
        if type(t) ~= "string" and type(t) ~= "number" then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(t, UI.GOLD[1], UI.GOLD[2], UI.GOLD[3])
        local b = body
        if type(b) == "function" then b = b(self) end
        if type(b) == "string" then GameTooltip:AddLine(b, UI.INK[1], UI.INK[2], UI.INK[3], true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Vertical colour fade, bottom colour first (each texture gets its gradient once, then is only shown or hidden).
local function fade(tex, bottom, top)
    tex:SetColorTexture(1, 1, 1, 1)
    if tex.SetGradient and CreateColor then
        tex:SetGradient("VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1))
    else
        tex:SetColorTexture(top[1], top[2], top[3], 1)
    end
end

-- The Encore button: copper edge, red fade when it is the main action (or a toggle that is on), dark when it is
-- not. style "dark" starts it dark. b:SetOn(on) switches between the two (mode buttons, tabs).
function UI.Button(parent, text, onClick, width, style)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, 22)
    b.bgOn = b:CreateTexture(nil, "BACKGROUND")
    b.bgOn:SetPoint("TOPLEFT", 1, -1); b.bgOn:SetPoint("BOTTOMRIGHT", -1, 1)
    fade(b.bgOn, { 0.23, 0.01, 0 }, { 0.76, 0.08, 0.05 })
    b.bgOff = b:CreateTexture(nil, "BACKGROUND")
    b.bgOff:SetPoint("TOPLEFT", 1, -1); b.bgOff:SetPoint("BOTTOMRIGHT", -1, 1)
    fade(b.bgOff, { 0.09, 0.06, 0.04 }, { 0.17, 0.13, 0.09 })
    UI.Border(b, UI.COPPER, 0.8)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 0.9, 0.6, 0.10)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 4, 0); fs:SetPoint("RIGHT", -4, 0)
    fs:SetWordWrap(false)
    b:SetFontString(fs)
    b:SetNormalFontObject(GameFontHighlightSmall)
    b:SetHighlightFontObject(GameFontHighlightSmall)
    b:SetDisabledFontObject(GameFontDisableSmall)
    b:SetPushedTextOffset(1, -1)
    function b:SetOn(on)
        self.on = on and true or false
        self.bgOn:SetShown(self.on)
        self.bgOff:SetShown(not self.on)
    end
    b:SetScript("OnEnable", function(self) self.bgOn:SetAlpha(1); self.bgOff:SetAlpha(1) end)
    b:SetScript("OnDisable", function(self) self.bgOn:SetAlpha(0.4); self.bgOff:SetAlpha(0.6) end)
    b:SetOn(style ~= "dark")
    b:SetText(text or "")
    b:SetScript("OnClick", function(self, button) if onClick then onClick(self, button) end end)
    return b
end

-- A dark inset pane with a black edge and a faint copper inner edge (sections inside a window).
function UI.Well(parent)
    local f = CreateFrame("Frame", nil, parent)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.016, 0.012, 0.008, 0.72)
    UI.Border(f, { 0, 0, 0 }, 1)
    local inner = UI.Border(f, UI.COPPER, 0.22)
    inner[1]:SetPoint("TOPLEFT", 1, -1); inner[1]:SetPoint("TOPRIGHT", -1, -1)
    inner[2]:SetPoint("BOTTOMLEFT", 1, 1); inner[2]:SetPoint("BOTTOMRIGHT", -1, 1)
    inner[3]:SetPoint("TOPLEFT", 1, -1); inner[3]:SetPoint("BOTTOMLEFT", 1, 1)
    inner[4]:SetPoint("TOPRIGHT", -1, -1); inner[4]:SetPoint("BOTTOMRIGHT", -1, 1)
    return f
end

-- The teal gem in a copper setting that sits on the corner of every Encore window.
function UI.Gem(parent, point, x, y)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(18, 18)
    f:SetPoint("CENTER", parent, point, x, y)
    f:SetFrameLevel(parent:GetFrameLevel() + 30)
    local sizes = { { 15, 0, 0, 0 }, { 13, UI.COPPER[1], UI.COPPER[2], UI.COPPER[3] }, { 9, UI.TEAL[1], UI.TEAL[2], UI.TEAL[3] } }
    for i, sz in ipairs(sizes) do
        local t = f:CreateTexture(nil, "OVERLAY", nil, i)
        t:SetColorTexture(sz[2], sz[3], sz[4], 1)
        t:SetSize(sz[1], sz[1])
        t:SetPoint("CENTER")
        if t.SetRotation then t:SetRotation(math.rad(45)) end
    end
    local shine = f:CreateTexture(nil, "OVERLAY", nil, 5)
    shine:SetColorTexture(0.75, 1, 1, 0.9)
    shine:SetSize(3, 3)
    shine:SetPoint("CENTER", -1.5, 1.5)
    if shine.SetRotation then shine:SetRotation(math.rad(45)) end
    return f
end

UI.MEDIA = "Interface\\AddOns\\EncoreEssentials\\Media\\"
UI.CREST = UI.MEDIA .. "encore-crest"

-- The Encore frame on a PortraitFrameTemplate frame (as Encore-DB, Encore-Stonks and the Encore window have it):
-- the icon in the portrait (the Encore crest unless given), the frame tinted copper, the gem in the bottom corner.
-- frame.title is the title text, so frame.title:SetText() works on every Encore window.
function UI.Skin(f, icon)
    local portrait = f.GetPortrait and f:GetPortrait() or f.portrait
    if portrait then
        portrait:SetTexture(icon or UI.CREST)
        portrait:SetTexCoord(0, 1, 0, 1)
    end
    if f.NineSlice then
        for _, region in ipairs({ f.NineSlice:GetRegions() }) do
            if region.SetVertexColor then region:SetVertexColor(1, 0.74, 0.5) end
        end
    end
    f.title = (f.GetTitleText and f:GetTitleText()) or (f.TitleContainer and f.TitleContainer.TitleText) or f.TitleText
    if not f.title then
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOP", 0, -5)
    end
    f.gem = UI.Gem(f, "BOTTOMLEFT", 3, 3)
end

-- UI.Window{ name = "GlobalName", title = "Title", width = 400, height = 300, icon = texture path }
-- A movable Encore window with a close button and Escape to close. Put things in window.content; window.header is
-- the strip beside the portrait, under the title.
function UI.Window(o)
    local f = CreateFrame("Frame", o.name, UIParent, "PortraitFrameTemplate")
    f:Hide()
    f:SetSize(o.width or 400, (o.height or 300) + 16)
    f:SetPoint("CENTER", 0, o.y or 80)
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI.Skin(f, o.icon)
    f.title:SetText(o.title or "")
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
    f.closeButton = f.CloseButton

    f.header = CreateFrame("Frame", nil, f)
    f.header:SetPoint("TOPLEFT", 66, -28)
    f.header:SetPoint("TOPRIGHT", -14, -28)
    f.header:SetHeight(26)

    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", 14, -60)
    f.content:SetPoint("BOTTOMRIGHT", -14, 14)

    if o.name then tinsert(UISpecialFrames, o.name) end
    return f
end

-- Text in a scroll box that can be selected and copied (Ctrl+A, Ctrl+C). Read-only unless editable is true.
function UI.ScrollText(parent, editable)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlightSmall)
    box:SetWidth(200)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self, byUser)
        if byUser and not editable then self:SetText(self.shown or "") end
    end)
    scroll:SetScrollChild(box)
    scroll:SetScript("OnSizeChanged", function(self, w) box:SetWidth(math.max(50, w - 4)) end)
    function scroll:SetText(text)
        box.shown = text
        box:SetText(text)
        box:SetCursorPosition(0)
        self:SetVerticalScroll(0)
    end
    scroll.box = box
    return scroll
end

-- A list with a heading per column; every column sorts on click (again to reverse), like every Encore list.
-- cols = { { key, head, w, right }, ... }. t:SetRows(rows, text(row, key) -> text [, colour], value(row, key) -> sort value)
-- opts.sort = { key, desc } (kept and changed in place), opts.rowHeight, opts.onRowClick(row, button).
function UI.Table(parent, cols, opts)
    opts = opts or {}
    local t = CreateFrame("Frame", nil, parent)
    t.sort = opts.sort or { key = cols[1].key, desc = false }
    local rowH = opts.rowHeight or 18
    local width, heads = 0, {}
    for _, c in ipairs(cols) do
        local b = CreateFrame("Button", nil, t)
        b:SetSize(c.w, 18)
        b:SetPoint("TOPLEFT", width, 0)
        b.text = UI.Text(b, "GameFontNormalSmall", c.head, UI.GOLD)
        b.text:SetAllPoints()
        b.text:SetJustifyH(c.right and "RIGHT" or "LEFT")
        b:SetScript("OnClick", function()
            if t.sort.key == c.key then t.sort.desc = not t.sort.desc else t.sort.key, t.sort.desc = c.key, c.right == true end
            if opts.onSort then opts.onSort(t.sort) end
            t:Refresh()
        end)
        b.col = c
        heads[#heads + 1] = b
        width = width + c.w + 6
    end
    local scroll = CreateFrame("ScrollFrame", nil, t, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -22)
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width, 10)
    scroll:SetScrollChild(child)
    local rows = {}

    local function row(i)
        local r = rows[i]
        if r then return r end
        r = CreateFrame("Button", nil, child)
        r:SetSize(width, rowH)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        if i % 2 == 0 then
            local bg = r:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.04)
        end
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(UI.COPPER[1], UI.COPPER[2], UI.COPPER[3], 0.12)
        r.cells = {}
        local x = 0
        for k, c in ipairs(cols) do
            local fs = UI.Text(r, "GameFontHighlightSmall", "")
            fs:SetPoint("LEFT", x, 0)
            fs:SetWidth(c.w)
            fs:SetJustifyH(c.right and "RIGHT" or "LEFT")
            fs:SetWordWrap(false)
            r.cells[k] = fs
            x = x + c.w + 6
        end
        r:SetScript("OnClick", function(self, button) if opts.onRowClick and self.data then opts.onRowClick(self.data, button) end end)
        if opts.tooltip then
            r:SetScript("OnEnter", function(self)
                if not self.data then return end
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                if opts.tooltip(self.data, GameTooltip) ~= false then GameTooltip:Show() end
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        rows[i] = r
        return r
    end

    function t:SetRows(list, text, value)
        self.list, self.text, self.value = list, text, value
        self:Refresh()
    end

    function t:Refresh()
        local list = {}
        for i, e in ipairs(self.list or {}) do list[i] = e end
        local key, desc, value = self.sort.key, self.sort.desc, self.value
        local pos = {}
        for i, e in ipairs(list) do pos[e] = i end
        table.sort(list, function(a, b)
            local x, y = value(a, key), value(b, key)
            if x == nil or y == nil then
                if x == nil and y == nil then return pos[a] < pos[b] end
                return y == nil
            end
            if type(x) ~= type(y) then x, y = tostring(x), tostring(y) end
            if x == y then return pos[a] < pos[b] end
            if desc then return x > y end
            return x < y
        end)
        for _, b in ipairs(heads) do
            b.text:SetText(b.col.head .. ((b.col.key == key) and (desc and " v" or " ^") or ""))
        end
        for i, e in ipairs(list) do
            local r = row(i)
            r.data = e
            for k, c in ipairs(cols) do
                local s, colour = self.text(e, c.key)
                r.cells[k]:SetText(s or "")
                UI.Color(r.cells[k], colour or UI.INK)
            end
            r:Show()
        end
        for i = #list + 1, #rows do rows[i]:Hide(); rows[i].data = nil end
        child:SetHeight(math.max(10, #list * rowH))
    end

    t.width = width
    return t
end
