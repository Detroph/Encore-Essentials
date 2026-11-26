-- Encore-QoL: small controls in the Encore look (copper, gold, dark panels), built from plain frames so they
-- work on every client without depending on Blizzard option templates.
local _, ns = ...
local Q = ns.QoL
local W = {}
Q.W = W

-- Colours, edges, panels, text and tooltips come from the shared Encore look (EncoreEssentials/UI/Kit.lua).
local UI = _G.EncoreEssentials.UI
W.COPPER, W.GOLD, W.INK, W.DIM, W.RED, W.TEAL = UI.COPPER, UI.GOLD, UI.INK, UI.DIM, UI.RED, UI.TEAL
W.HORDE = { 1, 0.62, 0.56 }
W.ALLIANCE = { 0.56, 0.78, 1 }
W.FONT_TITLE = UI.FONT_TITLE
W.Color = UI.Color
W.Border = UI.Border
W.Text = UI.Text
W.Tooltip = UI.Tooltip
function W.Panel(f, alpha) return UI.Panel(f, alpha or 0.9) end

-- Checkbox with a label. cb.onChange(value) is called on click.
function W.Check(parent, label)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.label = W.Text(cb, "GameFontHighlight", label)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    if cb.Text then cb.Text:SetText("") end
    cb:SetHitRectInsets(0, -math.min(220, (cb.label:GetStringWidth() or 0) + 6), 0, 0)
    cb:SetScript("OnClick", function(self)
        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if self.onChange then self.onChange(self:GetChecked() == true) end
    end)
    function cb:SetLocked(locked)
        self:SetEnabled(not locked)
        W.Color(self.label, locked and W.DIM or W.INK)
    end
    return cb
end

-- Slider: { min, max, step, fmt(value) -> text, onChange(value), marker = value (a tick, e.g. the menu cap) }
function W.Slider(parent, label, o)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(o.width or 300, o.inline and 18 or 34)
    f.label = W.Text(f, "GameFontHighlightSmall", label or "")
    f.label:SetPoint("TOPLEFT")
    f.value = W.Text(f, "GameFontNormalSmall", "", W.GOLD)
    local s = CreateFrame("Slider", nil, f)
    f.slider = s
    s:SetOrientation("HORIZONTAL")
    if o.inline then
        -- One row: track, then the value at the right.
        f.label:Hide()
        f.value:SetPoint("RIGHT")
        f.value:SetWidth(52)
        f.value:SetJustifyH("RIGHT")
        s:SetPoint("LEFT", 0, 0)
        s:SetPoint("RIGHT", -58, 0)
    else
        f.value:SetPoint("TOPRIGHT")
        s:SetPoint("TOPLEFT", 0, -16)
        s:SetPoint("TOPRIGHT", 0, -16)
    end
    s:SetHeight(14)
    s:SetMinMaxValues(o.min, o.max)
    s:SetValueStep(o.step or 1)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(6)
    track:SetColorTexture(0, 0, 0, 1)
    local fill = s:CreateTexture(nil, "BORDER")
    fill:SetPoint("LEFT"); fill:SetHeight(4)
    fill:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.85)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 16)
    thumb:SetColorTexture(1, 0.88, 0.54, 1)
    s:SetThumbTexture(thumb)
    if o.marker then
        local tick = s:CreateTexture(nil, "ARTWORK")
        tick:SetSize(2, 12)
        tick:SetColorTexture(W.COPPER[1], W.COPPER[2], W.COPPER[3], 1)
        f.tick = tick
    end
    local function place()
        local w = s:GetWidth()
        if not w or w <= 0 then return end
        local v = s:GetValue()
        fill:SetWidth(math.max(1, w * (v - o.min) / math.max(1e-6, o.max - o.min)))
        if f.tick then f.tick:SetPoint("CENTER", s, "LEFT", w * (o.marker - o.min) / math.max(1e-6, o.max - o.min), 0) end
    end
    s:SetScript("OnSizeChanged", place)
    s:SetScript("OnValueChanged", function(self, v, user)
        local step = o.step or 1
        v = math.floor(v / step + 0.5) * step
        f.value:SetText(o.fmt and o.fmt(v) or tostring(v))
        place()
        if user ~= false and f.ready and o.onChange then o.onChange(v) end
    end)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, d)
        if not self:IsEnabled() then return end
        self:SetValue(self:GetValue() + d * (o.step or 1))
    end)
    function f:SetValue(v)
        self.ready = false
        s:SetValue(v)
        f.value:SetText(o.fmt and o.fmt(v) or tostring(v))
        place()
        self.ready = true
    end
    function f:SetLocked(locked)
        s:SetEnabled(not locked)
        W.Color(self.label, locked and W.DIM or W.INK)
        thumb:SetAlpha(locked and 0.4 or 1)
    end
    f.ready = true
    return f
end

-- Choice button: shows the current value; click opens a menu of { value, label } choices (the shared Encore one).
W.Choice = UI.Choice

function W.Button(parent, text, onClick, width)
    local b = _G.EncoreEssentials.UI.Button(parent)
    b:SetSize(width or 140, 22)
    b:SetText(text)
    b:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
    function b:SetLocked(locked) self:SetEnabled(not locked) end
    return b
end

-- Colour swatch. value is { r, g, b }.
function W.Swatch(parent, label, onChange)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(300, 22)
    f.label = W.Text(f, "GameFontHighlightSmall", label)
    f.label:SetPoint("LEFT")
    local b = CreateFrame("Button", nil, f)
    b:SetSize(36, 16)
    b:SetPoint("RIGHT")
    local sw = b:CreateTexture(nil, "ARTWORK")
    sw:SetPoint("TOPLEFT", 1, -1); sw:SetPoint("BOTTOMRIGHT", -1, 1)
    W.Border(b, W.COPPER)
    function f:SetValue(c)
        self.current = c
        sw:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
    end
    b:SetScript("OnClick", function()
        local c = f.current or { 1, 1, 1 }
        local function apply(restore)
            local r, g, bl
            if restore then r, g, bl = restore[1], restore[2], restore[3] else r, g, bl = ColorPickerFrame:GetColorRGB() end
            local v = { r, g, bl }
            f:SetValue(v)
            if onChange then onChange(v) end
        end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = c[1], g = c[2], b = c[3], hasOpacity = false,
                swatchFunc = function() apply() end,
                cancelFunc = function() apply(c) end,
            })
        else
            ColorPickerFrame.func = function() apply() end
            ColorPickerFrame.cancelFunc = function() apply(c) end
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame:SetColorRGB(c[1], c[2], c[3])
            ColorPickerFrame:Show()
        end
    end)
    function f:SetLocked(locked)
        b:SetEnabled(not locked)
        W.Color(self.label, locked and W.DIM or W.INK)
    end
    return f
end

-- One-line text box. onChange(text) on Enter or focus lost.
function W.Edit(parent, label, onChange)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(300, 22)
    f.label = W.Text(f, "GameFontHighlightSmall", label)
    f.label:SetPoint("LEFT")
    local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    e:SetSize(160, 20)
    e:SetPoint("RIGHT", -4, 0)
    e:SetAutoFocus(false)
    local function commit(self)
        self:ClearFocus()
        if onChange then onChange(self:GetText()) end
    end
    e:SetScript("OnEnterPressed", commit)
    e:SetScript("OnEditFocusLost", function(self) if onChange then onChange(self:GetText()) end end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    function f:SetValue(v) e:SetText(v or "") e:SetCursorPosition(0) end
    function f:SetLocked(locked)
        e:SetEnabled(not locked)
        W.Color(self.label, locked and W.DIM or W.INK)
    end
    return f
end

-- On/off switch: a small track with a knob, teal when on. sw.onChange(value) on click.
function W.Switch(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(36, 18)
    local track = b:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    local edge = W.Border(b, W.DIM, 1)
    local knob = b:CreateTexture(nil, "ARTWORK")
    knob:SetSize(12, 12)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.12)
    function b:SetChecked(on)
        self.checked = on == true
        knob:ClearAllPoints()
        if self.checked then
            knob:SetPoint("RIGHT", -3, 0)
            knob:SetColorTexture(W.TEAL[1], W.TEAL[2], W.TEAL[3], 1)
            track:SetColorTexture(0.03, 0.2, 0.2, 1)
            self:SetBorderColor(W.TEAL)
        else
            knob:SetPoint("LEFT", 3, 0)
            knob:SetColorTexture(W.DIM[1], W.DIM[2], W.DIM[3], 1)
            track:SetColorTexture(0.04, 0.03, 0.02, 1)
            self:SetBorderColor(W.DIM)
        end
    end
    function b:GetChecked() return self.checked end
    function b:SetLocked(locked)
        self:SetEnabled(not locked)
        self:SetAlpha(locked and 0.45 or 1)
    end
    b:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        PlaySound(self.checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if self.onChange then self.onChange(self.checked) end
    end)
    b:SetChecked(false)
    return b
end

-- Copper badge that names the addon owning a feature.
function W.Badge(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(18)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    b.bg = bg
    W.Border(b, W.COPPER, 0.9)
    b.text = W.Text(b, "GameFontNormalSmall", "")
    b.text:SetPoint("CENTER", 0, 0)
    function b:SetStatus(f)
        local s, c, fill = "Off", W.DIM, { 0, 0, 0, 0.5 }
        if f.status == "on" then s, c, fill = "On · Encore", W.TEAL, { 0.03, 0.2, 0.2, 0.8 }
        elseif f.status == "locked" then s, c, fill = "On in " .. (f.owner or "another addon"), W.GOLD, { 0.35, 0.18, 0.05, 0.85 }
        elseif f.status == "replaced" then s, c, fill = "Replaced by " .. (f.owner or "another addon"), W.GOLD, { 0.35, 0.18, 0.05, 0.85 }
        elseif f.status == "error" then s, c, fill = "Error, see /console", W.HORDE, { 0.3, 0.02, 0.01, 0.85 } end
        self.text:SetText(s)
        W.Color(self.text, c)
        self.bg:SetColorTexture(unpack(fill))
        self:SetWidth((self.text:GetStringWidth() or 40) + 14)
    end
    return b
end
