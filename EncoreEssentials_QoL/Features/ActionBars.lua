-- Encore-QoL: Interface tab, action bars. When each Blizzard bar shows and how see-through it is, plus the
-- text on the buttons (keybind, macro name, count, cooldown), range tint and borders.
--
-- Bars are faded with SetAlpha, which the game allows at any time, even in combat; a bar faded to 0 still
-- takes clicks. Only Blizzard bars: with Bartender4, Dominos or ElvUI the rows show "Replaced".
-- Bar numbers follow the game's: 1 main bar, 2 bottom left, 3 bottom right, 4 right, 5 right 2, 6 bar 6.
local _, ns = ...
local Q = ns.QoL

local BAR_ADDONS = {
    { addon = "Bartender4", replaced = true }, { addon = "Dominos", replaced = true },
    { addon = "ElvUI", replaced = true }, { addon = "ConsolePort_Bar", replaced = true },
}

local BARS = {
    { id = "bar1", name = "Action bar 1", note = "main bar", frames = { "MainActionBar", "MainMenuBar" }, eqol = "mouseoverActionBar1", buttons = "ActionButton", count = 12 },
    { id = "bar2", name = "Action bar 2", frames = { "MultiBarBottomLeft" }, eqol = "mouseoverActionBar2", buttons = "MultiBarBottomLeftButton", count = 12 },
    { id = "bar3", name = "Action bar 3", frames = { "MultiBarBottomRight" }, eqol = "mouseoverActionBar3", buttons = "MultiBarBottomRightButton", count = 12 },
    { id = "bar4", name = "Action bar 4", frames = { "MultiBarRight" }, eqol = "mouseoverActionBar4", buttons = "MultiBarRightButton", count = 12 },
    { id = "bar5", name = "Action bar 5", frames = { "MultiBarLeft" }, eqol = "mouseoverActionBar5", buttons = "MultiBarLeftButton", count = 12 },
    { id = "bar6", name = "Action bar 6", frames = { "MultiBar5" }, eqol = "mouseoverActionBar6", buttons = "MultiBar5Button", count = 12 },
    { id = "barPet", name = "Pet bar", frames = { "PetActionBar", "PetActionBarFrame" }, eqol = "mouseoverActionBarPet", buttons = "PetActionButton", count = 10 },
    { id = "barStance", name = "Stance bar", frames = { "StanceBar", "StanceBarFrame", "ShapeshiftBarFrame" }, eqol = "mouseoverActionBarStanceBar", buttons = "StanceButton", count = 10 },
}

local function barFrame(bar)
    for _, name in ipairs(bar.frames) do
        if _G[name] then return _G[name] end
    end
end

-- Every Blizzard action button, for the text and tint features.
local function eachButton(fn)
    for _, bar in ipairs(BARS) do
        for i = 1, bar.count do
            local b = _G[bar.buttons .. i]
            if b then fn(b, bar) end
        end
    end
end
Q.EachActionButton = eachButton

-- Enhance QoL keeps a visibility rule per bar, or one shared rule that bars can follow.
local function anyTrue(t)
    if type(t) ~= "table" then return t == true end
    for _, v in pairs(t) do if v == true then return true end end
    return false
end
local function eqolBarRule(key)
    return function(p)
        if anyTrue(p[key]) then return true end
        local useGlobal = type(p.actionBarVisibilityUseGlobal) == "table" and p.actionBarVisibilityUseGlobal[key]
        return useGlobal and anyTrue(p.actionBarVisibilityGlobal) or false
    end
end

---------------------------------------------------------------------------
-- Visibility rules
---------------------------------------------------------------------------
local function poleEquipped()
    local id = GetInventoryItemID("player", INVSLOT_MAINHAND or 16)
    if not id then return false end
    local classID, subClassID = select(6, C_Item.GetItemInfoInstant(id))
    return classID == 2 and subClassID == 20
end
Q.PoleEquipped = poleEquipped

local function safe(fn) local ok, v = pcall(fn) return ok and v end

local CONDITIONS = {
    combat = function() return InCombatLockdown() or UnitAffectingCombat("player") end,
    target = function() return UnitExists("target") end,
    drag = function() return GetCursorInfo() ~= nil end,
    group = function() return IsInGroup() end,
    casting = function() return UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil end,
    resting = function() return IsResting() end,
    lowHealth = function() return safe(function() return UnitHealth("player") / math.max(1, UnitHealthMax("player")) < 0.5 end) end,
    fishing = poleEquipped,
    mounted = function() return IsMounted() end,
    taxi = function() return UnitOnTaxi("player") end,
    vehicle = function() return UnitInVehicle and UnitInVehicle("player") end,
}

local function wantedAlpha(f, frame)
    local mode = f:Get("mode")
    local inCombat = CONDITIONS.combat()
    local shown
    if mode == "always" then shown = true
    elseif mode == "never" then shown = false
    elseif mode == "combat" then shown = inCombat
    elseif mode == "ooc" then shown = not inCombat
    elseif mode == "mouseover" then shown = false
    else -- custom: show when any ticked condition is true
        shown = false
        for _, key in ipairs({ "combat", "target", "drag", "group", "casting", "resting", "lowHealth" }) do
            if f:Get("show_" .. key) and CONDITIONS[key]() then shown = true break end
        end
    end
    local mouse = frame:IsMouseOver() or (SpellFlyout and SpellFlyout:IsShown() and SpellFlyout:IsMouseOver())
    if mouse and (mode == "mouseover" or mode == "custom" and f:Get("show_mouse")) then
        shown = true
        f.lingerUntil = GetTime() + (f:Get("linger") or 0)
    elseif not shown and f.lingerUntil and GetTime() < f.lingerUntil then
        shown = true
    end
    for _, key in ipairs({ "fishing", "mounted", "taxi", "vehicle" }) do
        if f:Get("hide_" .. key) and CONDITIONS[key]() then shown = false break end
    end
    if not shown then return 0 end
    return (inCombat and f:Get("alphaIn") or f:Get("alphaOut")) / 100
end

local fading = {}
local fader = CreateFrame("Frame")
local elapsedSince = 0
fader:Hide()
fader:SetScript("OnUpdate", function(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < 0.05 then return end
    local dt = elapsedSince
    elapsedSince = 0
    for f in pairs(fading) do
        local frame = f.frame
        if frame then
            local target = wantedAlpha(f, frame)
            local current = frame:GetAlpha()
            if math.abs(current - target) > 0.01 then
                local speed = 1 / math.max(0.05, f:Get("fade") or 0.2)
                local step = speed * dt
                if current < target then current = math.min(target, current + step) else current = math.max(target, current - step) end
                frame:SetAlpha(current)
            elseif current ~= target then
                frame:SetAlpha(target)
            end
        end
    end
end)

local MODE_CHOICES = {
    { "always", "Always (game)" }, { "never", "Never" }, { "combat", "In combat" },
    { "ooc", "Out of combat" }, { "mouseover", "Mouseover" }, { "custom", "Custom rules" },
}

for _, bar in ipairs(BARS) do
    local detect = { { eqol = eqolBarRule(bar.eqol) } }
    for _, d in ipairs(BAR_ADDONS) do detect[#detect + 1] = d end
    Q:Feature{
        id = bar.id, tab = "interface", section = "Action bars",
        name = bar.name .. (bar.note and (" (" .. bar.note .. ")") or ""),
        desc = "When this bar shows, and how see-through it is in and out of combat.",
        defaults = {
            mode = "mouseover", alphaIn = 100, alphaOut = 100, fade = 0.2, linger = 0.5,
            show_mouse = true, show_combat = true, hide_fishing = false, hide_mounted = false, hide_taxi = true, hide_vehicle = true,
        },
        options = {
            { kind = "choice", key = "mode", name = "Shows", choices = MODE_CHOICES },
            { kind = "note", text = "Custom: show when any of these is true" },
            { kind = "check", key = "show_combat", name = "In combat" },
            { kind = "check", key = "show_mouse", name = "Mouse over the bar" },
            { kind = "check", key = "show_target", name = "You have a target" },
            { kind = "check", key = "show_drag", name = "Dragging a spell or item" },
            { kind = "check", key = "show_group", name = "In a group" },
            { kind = "check", key = "show_casting", name = "Casting" },
            { kind = "check", key = "show_resting", name = "Resting" },
            { kind = "check", key = "show_lowHealth", name = "Below half health" },
            { kind = "note", text = "Hide anyway when (any mode)" },
            { kind = "check", key = "hide_fishing", name = "Fishing pole equipped" },
            { kind = "check", key = "hide_mounted", name = "Mounted" },
            { kind = "check", key = "hide_taxi", name = "On a flight path" },
            { kind = "check", key = "hide_vehicle", name = "In a vehicle" },
            { kind = "slider", key = "alphaIn", name = "Alpha in combat", min = 0, max = 100, step = 5, fmt = function(v) return v .. "%" end },
            { kind = "slider", key = "alphaOut", name = "Alpha out of combat", min = 0, max = 100, step = 5, fmt = function(v) return v .. "%" end },
            { kind = "slider", key = "fade", name = "Fade time", min = 0, max = 2, step = 0.1, fmt = function(v) return ("%.1f s"):format(v) end },
            { kind = "slider", key = "linger", name = "Stays after the mouse leaves", min = 0, max = 5, step = 0.5, fmt = function(v) return ("%.1f s"):format(v) end },
        },
        detect = detect,
        Enable = function(f)
            f.frame = barFrame(bar)
            if not f.frame then return end
            fading[f] = true
            fader:Show()
        end,
        Disable = function(f)
            fading[f] = nil
            if f.frame then f.frame:SetAlpha(1) end
            if not next(fading) then fader:Hide() end
        end,
    }
end

---------------------------------------------------------------------------
-- Button text
---------------------------------------------------------------------------
local FONTS = {
    { "default", "Game default" },
    { "Interface\\AddOns\\EncoreEssentials_QoL\\Media\\MarcellusSC.ttf", "Marcellus SC (Encore)" },
    { "Fonts\\FRIZQT__.TTF", "Friz Quadrata" },
    { "Fonts\\ARIALN.TTF", "Arial Narrow" },
    { "Fonts\\MORPHEUS.TTF", "Morpheus" },
    { "Fonts\\SKURRI.TTF", "Skurri" },
}
local OUTLINES = { { "", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick outline" } }
local ANCHORS = {
    { "TOPLEFT", "Top left" }, { "TOP", "Top" }, { "TOPRIGHT", "Top right" }, { "LEFT", "Left" }, { "CENTER", "Centre" },
    { "RIGHT", "Right" }, { "BOTTOMLEFT", "Bottom left" }, { "BOTTOM", "Bottom" }, { "BOTTOMRIGHT", "Bottom right" },
}

local function textRegion(button, which)
    if which == "hotkey" then return button.HotKey or _G[button:GetName() .. "HotKey"] end
    if which == "macro" then return button.Name or _G[button:GetName() .. "Name"] end
    if which == "count" then return button.Count or _G[button:GetName() .. "Count"] end
    if which == "cooldown" then
        local cd = button.cooldown or _G[button:GetName() .. "Cooldown"]
        if cd and cd.GetRegions then
            for _, r in ipairs({ cd:GetRegions() }) do
                if r.GetObjectType and r:GetObjectType() == "FontString" then return r end
            end
        end
    end
end

local originals = {}
local function remember(fs)
    if originals[fs] then return end
    local path, size, flags = fs:GetFont()
    local p, rel, rp, x, y = fs:GetPoint(1)
    originals[fs] = { font = { path, size, flags }, point = p and { p, rel, rp, x, y }, color = { fs:GetTextColor() } }
end

local TEXTS = {
    { id = "textHotkey", which = "hotkey", name = "Keybind text", anchor = "TOPRIGHT", x = -2, y = -3, size = 12,
        detect = { { eqol = function(p) return p.actionBarHotkeyFontOverride or (type(p.actionBarHiddenHotkeys) == "table" and next(p.actionBarHiddenHotkeys) ~= nil) end } }, perBar = true },
    { id = "textMacro", which = "macro", name = "Macro name text", anchor = "BOTTOM", x = 0, y = 2, size = 10,
        detect = { { eqol = function(p) return p.actionBarMacroFontOverride or p.hideMacroNames end } } },
    { id = "textCount", which = "count", name = "Stack and charge count", anchor = "BOTTOMRIGHT", x = -2, y = 2, size = 14,
        detect = { { eqol = function(p) return p.actionBarCountFontOverride or p.hideChargeText end } } },
    { id = "textCooldown", which = "cooldown", name = "Cooldown numbers", anchor = "CENTER", x = 0, y = 0, size = 16,
        detect = { { eqol = function(p) return p.actionBarCooldownFontOverride or p.hideCooldownText end } } },
}

for _, t in ipairs(TEXTS) do
    local options = {
        { kind = "check", key = "show", name = "Show this text" },
        { kind = "choice", key = "font", name = "Font", choices = FONTS },
        { kind = "slider", key = "size", name = "Size", min = 6, max = 28, step = 1 },
        { kind = "choice", key = "outline", name = "Outline", choices = OUTLINES },
        { kind = "color", key = "color", name = "Colour" },
        { kind = "choice", key = "anchor", name = "Position", choices = ANCHORS },
        { kind = "slider", key = "x", name = "Move left or right", min = -20, max = 20, step = 1 },
        { kind = "slider", key = "y", name = "Move up or down", min = -20, max = 20, step = 1 },
    }
    if t.perBar then
        options[#options + 1] = { kind = "note", text = "Hide keybinds on" }
        for _, bar in ipairs(BARS) do options[#options + 1] = { kind = "check", key = "hide_" .. bar.id, name = bar.name } end
    end
    local detect = { unpack(t.detect) }
    for _, d in ipairs(BAR_ADDONS) do detect[#detect + 1] = d end

    local function style(f, button, bar)
        local fs = textRegion(button, t.which)
        if not fs then return end
        remember(fs)
        local shown = f:Get("show") and not (t.perBar and f:Get("hide_" .. bar.id))
        fs:SetAlpha(shown and 1 or 0)
        if not shown then return end
        local o = originals[fs]
        local font = f:Get("font")
        if font == "default" then font = o.font[1] end
        if not fs:SetFont(font, f:Get("size"), f:Get("outline")) then fs:SetFont(o.font[1], f:Get("size"), f:Get("outline")) end
        local c = f:Get("color")
        if type(c) == "table" and t.which ~= "hotkey" then fs:SetTextColor(c[1], c[2], c[3]) end
        fs:ClearAllPoints()
        fs:SetPoint(f:Get("anchor"), button, f:Get("anchor"), f:Get("x"), f:Get("y"))
    end

    Q:Feature{
        id = t.id, tab = "interface", section = "Action bar text", name = t.name,
        desc = "Font, size, outline, colour and position of this text on every Blizzard action button.",
        defaults = { show = true, font = "default", size = t.size, outline = "OUTLINE", color = { 1, 1, 1 }, anchor = t.anchor, x = t.x, y = t.y },
        options = options,
        detect = detect,
        Apply = function(f) eachButton(function(b, bar) style(f, b, bar) end) end,
        Enable = function(f)
            f:Apply()
            f:On("PLAYER_ENTERING_WORLD", function() f:Apply() end)
            f:On("UPDATE_BINDINGS", function() C_Timer.After(0, function() f:Apply() end) end)
            if t.which == "hotkey" then
                -- The game recolours keybinds for range; keep ours after it.
                f:Hook("ActionButton_UpdateHotkeys", function(button)
                    local c = f:Get("color")
                    local fs = textRegion(button, "hotkey")
                    if fs and type(c) == "table" then fs:SetVertexColor(c[1], c[2], c[3]) end
                end)
                f:Hook("ActionButton_UpdateRangeIndicator", function(button, checksRange, inRange)
                    local c = f:Get("color")
                    local fs = textRegion(button, "hotkey")
                    if fs and type(c) == "table" and not (checksRange and not inRange) then fs:SetVertexColor(c[1], c[2], c[3]) end
                end)
            elseif t.which == "cooldown" then
                Q.SetCVar("countdownForCooldowns", "1")
            end
        end,
        OnOption = function(f) f:Apply() end,
        Disable = function(f)
            eachButton(function(button)
                local fs = textRegion(button, t.which)
                local o = fs and originals[fs]
                if o then
                    fs:SetAlpha(1)
                    fs:SetFont(o.font[1], o.font[2], o.font[3])
                    if o.point then fs:ClearAllPoints(); fs:SetPoint(unpack(o.point)) end
                    fs:SetTextColor(unpack(o.color))
                end
            end)
            if t.which == "cooldown" then Q.RestoreCVar("countdownForCooldowns") end
        end,
    }
end

---------------------------------------------------------------------------
-- Range tint and borders
---------------------------------------------------------------------------
local function resetIcon(button)
    local icon = button.icon or _G[button:GetName() .. "Icon"]
    if not icon or not button.action then return end
    local usable, noMana = IsUsableAction(button.action)
    if usable then icon:SetVertexColor(1, 1, 1)
    elseif noMana then icon:SetVertexColor(0.5, 0.5, 1)
    else icon:SetVertexColor(0.4, 0.4, 0.4) end
end

Q:Feature{
    id = "rangeTint", tab = "interface", section = "Action bar text", name = "Range tint",
    desc = "The whole button turns a colour when your target is out of range, not just the keybind.",
    defaults = { color = { 0.85, 0.15, 0.1 } },
    options = { { kind = "color", key = "color", name = "Out of range colour" } },
    detect = { { eqol = "actionBarFullRangeColoring" }, unpack(BAR_ADDONS) },
    Enable = function(f)
        local function tint(button, checksRange, inRange)
            local icon = button.icon or (button.GetName and _G[button:GetName() .. "Icon"])
            if not icon then return end
            if checksRange and inRange == false then
                local c = f:Get("color")
                icon:SetVertexColor(c[1], c[2], c[3])
            end
        end
        f:Hook("ActionButton_UpdateRangeIndicator", tint)
        f:Hook("ActionButton_UpdateUsable", function(button)
            if not button.action then return end
            local inRange = IsActionInRange(button.action)
            if inRange == false then tint(button, true, false) end
        end)
        eachButton(function(button)
            if button.UpdateUsable then f:Hook(button, "UpdateUsable", function(b)
                if b.action and IsActionInRange(b.action) == false then tint(b, true, false) end
            end) end
        end)
    end,
    Disable = function() eachButton(resetIcon) end,
}

Q:Feature{
    id = "hideBorders", tab = "interface", section = "Action bar text", name = "Hide button borders",
    desc = "Takes the frame art off action buttons, leaving just the icons.",
    detect = { { eqol = "actionBarHideBorders" }, { addon = "MasqueBlizzBars" }, unpack(BAR_ADDONS) },
    Enable = function()
        eachButton(function(button)
            local n = button.GetNormalTexture and button:GetNormalTexture()
            if n then n:SetAlpha(0) end
            if button.Border then button.Border:SetAlpha(0) end
        end)
    end,
    Disable = function()
        eachButton(function(button)
            local n = button.GetNormalTexture and button:GetNormalTexture()
            if n then n:SetAlpha(1) end
            if button.Border then button.Border:SetAlpha(1) end
        end)
    end,
}
