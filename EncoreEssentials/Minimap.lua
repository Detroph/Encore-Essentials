-- Encore Essentials: minimap button and the Encore options menu.
-- Left-click the button to open the Encore Essentials window (Hub.lua); right-click it for the options menu.
--
-- The button sits on the minimap ring directly below the day/night indicator (sun/moon), one indicator-width
-- further round the ring, and is drawn at that indicator's size. It is deliberately NOT a LibDBIcon button and NOT a child of the Minimap, so minimap
-- button collectors leave it alone:
--   * EnhanceQoL's button sink collects every named Button returned by Minimap:GetChildren(), plus LibDBIcon buttons.
--   * MinimapButtonBag-style addons scan the children of Minimap / MinimapBackdrop and LibDBIcon10_* buttons.
-- So the button is parented to UIParent, has no LibDBIcon10_ name and no "Minimap" in its name, and is only
-- anchored to the indicator. Because a UIParent child does not inherit the minimap's scale, its scale is set
-- from the indicator's effective scale, so it keeps the same size at any resolution, UI scale or minimap scale.
--
-- From the right-click menu the button can also be detached ("Unlock button"): it can then be dragged anywhere,
-- locked in place, and drawn as a larger rounded square instead. "Reattach to minimap" puts it back below the sun.
-- The square button has a resize knob while unlocked.
-- Saved account-wide in EncoreEssentialsDB.settings.minimap: detached, locked, square, size, point.
local _, ns = ...
local L = ns.L
local Encore = ns.Encore

local ICON = "Interface\\AddOns\\EncoreEssentials\\Media\\encore-icon"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- The button art is the classic minimap button (31x31 frame, 53x53 tracking border at its top-left).
-- The visible ring is about ART_SIZE units wide.
local FRAME_SIZE = 31
local ART_SIZE = 33
local ICON_OFFSET_X, ICON_OFFSET_Y = 1.5, 0.5 -- ring centre (17, -15 from the top-left) minus frame centre
local STEP = 1.1 -- distance from the indicator's centre to the button's, in indicator widths
-- The detached square button, in UI units (follows the UI scale like any other window). It can be resized with a
-- knob at its bottom-right corner, up to the width of two standard 36px action button icons at 100% UI scale.
local SQUARE_SIZE, SQUARE_MIN, SQUARE_MAX = 40, 24, 72
local SQUARE_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local button

---------------------------------------------------------------------------
-- The options menu (Blizzard's Menu system, so it looks like the game's own menus)
---------------------------------------------------------------------------
function Encore:OpenMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        self:ToggleHub() -- no menu system: fall back to the main window
        return
    end
    GameTooltip:Hide()
    MenuUtil.CreateContextMenu(owner or UIParent, function(_, root)
        root:CreateTitle("|cffeb9339Encore|r Essentials")
        root:CreateButton(L.MENU_HUB, function() Encore:ToggleHub() end)
        root:CreateDivider()
        local settings = Encore.db.settings.minimap
        if settings.detached then
            root:CreateCheckbox(L.MENU_LOCK_BUTTON,
                function() return Encore.db.settings.minimap.locked end,
                function() Encore:SetMinimapButtonLocked(not Encore.db.settings.minimap.locked) end)
            root:CreateCheckbox(L.MENU_SQUARE_BUTTON,
                function() return Encore.db.settings.minimap.square end,
                function() Encore:SetMinimapButtonSquare(not Encore.db.settings.minimap.square) end)
            root:CreateButton(L.MENU_REATTACH, function() Encore:ReattachMinimapButton() end)
        else
            root:CreateButton(L.MENU_UNLOCK_BUTTON, function() Encore:DetachMinimapButton(false) end)
            root:CreateButton(L.MENU_SQUARE_BUTTON_DETACH, function() Encore:DetachMinimapButton(true) end)
        end
        root:CreateDivider()
        if Encore.optionsCategory then root:CreateButton(L.MENU_OPTIONS, function() Encore:OpenOptions() end) end
        root:CreateButton(L.MENU_INFO, function() Encore:ShowInfo() end)
        root:CreateCheckbox(L.MENU_LOGIN_MESSAGE,
            function() return Encore.db.settings.showLoginMessage end,
            function()
                local settings = Encore.db.settings
                settings.showLoginMessage = not settings.showLoginMessage
            end)
        root:CreateButton(L.MENU_HIDE_BUTTON, function()
            Encore:SetMinimapButtonShown(false)
            Encore:Print(L.MINIMAP_HIDDEN)
        end)
    end)
end

---------------------------------------------------------------------------
-- Size and position
---------------------------------------------------------------------------
-- The day/night indicator (sun/moon).
-- WoW Forever draws it with an unnamed frame inside MinimapCluster.MinimapContainer, created by
-- Blizzard_Minimap/Camelot/Diel.lua ("diel" = day and night). It has no global name or parentKey, so it is found
-- by the file that created it, or failing that by its shape: an unnamed child of the container with a
-- .Background key and a square size. On clients where it is the classic GameTimeFrame, that is used instead.
-- (On WoW Forever the name GameTimeFrame belongs to the calendar button, so it is only the last resort.)
local dielFrame
local function isUsable(f)
    return f and f:IsShown() and (f:GetWidth() or 0) > 0 and f:GetCenter() ~= nil
end

local function findDiel()
    if dielFrame then return dielFrame end
    local container = _G.MinimapCluster and MinimapCluster.MinimapContainer
    if not container then return end
    local byShape
    for _, child in ipairs({ container:GetChildren() }) do
        if child ~= Minimap and not child:GetName() then
            local source = child.GetSourceLocation and child:GetSourceLocation()
            if type(source) == "string" and source:find("Diel%.lua") then
                dielFrame = child
                break
            end
            local w, h = child:GetSize()
            if not byShape and child.Background and w and w > 0 and math.abs(w - h) < 1 then byShape = child end
        end
    end
    dielFrame = dielFrame or byShape
    if dielFrame then
        dielFrame:HookScript("OnSizeChanged", function() Encore:RelayoutMinimapButton() end)
        dielFrame:HookScript("OnShow", function() Encore:RelayoutMinimapButton() end)
        dielFrame:HookScript("OnHide", function() Encore:RelayoutMinimapButton() end)
        hooksecurefunc(dielFrame, "SetScale", function() Encore:RelayoutMinimapButton() end)
    end
    return dielFrame
end

local function indicator()
    local diel = findDiel()
    if isUsable(diel) then return diel end
    if not diel and isUsable(_G.GameTimeFrame) then return GameTimeFrame end
end

local lastKey
local function setLayout(key, scale, point, relativeTo, relativePoint, x, y)
    if key == lastKey then return end
    lastKey = key
    button:SetScale(scale)
    button:ClearAllPoints()
    button:SetPoint(point, relativeTo, relativePoint, x, y)
end

local applyStyle

-- Detached: a plain UIParent child at UI scale, at its saved spot.
local function squareSize()
    local size = tonumber(Encore.db.settings.minimap.size) or SQUARE_SIZE
    return math.max(SQUARE_MIN, math.min(SQUARE_MAX, size))
end

local function layoutFree()
    local settings = Encore.db.settings.minimap
    local p = settings.point
    local key = ("free:%s:%s:%s:%s:%s:%s:%s"):format(tostring(settings.square), tostring(settings.locked), squareSize(),
        p and p[1] or "", p and p[2] or "", p and p[3] or "", p and p[4] or "")
    if key == lastKey then return end
    lastKey = key
    applyStyle(settings.square)
    if settings.square then button:SetSize(squareSize(), squareSize()) end
    button.grip:SetShown(settings.square and not settings.locked)
    button:SetScale(1)
    button:ClearAllPoints()
    if type(p) == "table" and p[1] then
        button:SetPoint(p[1], UIParent, p[2] or p[1], tonumber(p[3]) or 0, tonumber(p[4]) or 0)
    else
        button:SetPoint("CENTER")
    end
end

local function layout()
    if not button then return end
    if button.moving or button.sizing then return end
    if Encore.db.settings.minimap.detached then return layoutFree() end
    applyStyle(false)
    button.grip:Hide()
    local uiScale = UIParent:GetEffectiveScale()
    local gt = indicator()
    local mmX, mmY = Minimap:GetCenter()
    if not mmX then return end
    if gt and gt:GetCenter() then
        -- Make the ring as wide on screen as the indicator: ART_SIZE * ourScale * uiScale == width * gtScale
        local gtScale = gt:GetEffectiveScale()
        local diameter = gt:GetWidth() * gtScale -- on screen
        local scale = diameter / (ART_SIZE * uiScale)
        local unit = scale * uiScale -- screen pixels per button unit

        -- Place it on the minimap ring, one indicator-width further round from the indicator, going down.
        -- Everything is measured in screen pixels, so other addons' minimap scale or shape changes don't matter.
        local mmScale = Minimap:GetEffectiveScale()
        local cx, cy = mmX * mmScale, mmY * mmScale
        local gx, gy = gt:GetCenter()
        gx, gy = gx * gtScale, gy * gtScale
        local dx, dy = gx - cx, gy - cy
        local radius = math.sqrt(dx * dx + dy * dy)
        local x, y
        if radius > diameter then
            local angle = math.atan2(dy, dx)
            local step = diameter * STEP / radius
            angle = (dx >= 0) and (angle - step) or (angle + step) -- clockwise on the right side, so downwards
            x, y = math.cos(angle) * radius, math.sin(angle) * radius
        else
            -- Indicator sits in the middle of the minimap (unusual layout): just put the button below it
            x, y = dx, dy - diameter * STEP
        end
        -- The ring's visual centre is ICON_OFFSET_X/Y units from the frame centre
        x = x / unit - ICON_OFFSET_X
        y = y / unit - ICON_OFFSET_Y
        setLayout(("gt:%.4f:%.1f:%.1f"):format(scale, x, y), scale, "CENTER", Minimap, "CENTER", x, y)
    else
        -- No indicator (hidden by the player or another addon): top-right of the minimap, at minimap scale.
        local scale = Minimap:GetEffectiveScale() / uiScale
        setLayout(("mm:%.4f"):format(scale), scale, "CENTER", Minimap, "TOPRIGHT", -8, -8)
    end
end

local function relayout()
    lastKey = nil
    layout()
end

function Encore:RelayoutMinimapButton()
    relayout()
end

-- Follow the minimap: hide with it, and re-measure whenever anything up the chain is rescaled or resized.
local hooked
local function hookSources()
    if hooked then return end
    hooked = true
    for _, f in ipairs({ _G.MinimapCluster, Minimap, _G.GameTimeFrame }) do
        if f then
            hooksecurefunc(f, "SetScale", relayout)
            f:HookScript("OnSizeChanged", relayout)
        end
    end
    if _G.GameTimeFrame then
        GameTimeFrame:HookScript("OnShow", relayout)
        GameTimeFrame:HookScript("OnHide", relayout)
    end
    Minimap:HookScript("OnShow", function()
        if not Encore.db.settings.minimap.hide and button then button:Show() end
        relayout()
    end)
    Minimap:HookScript("OnHide", function()
        if button and not Encore.db.settings.minimap.detached then button:Hide() end
    end)

    local events = CreateFrame("Frame")
    events:SetScript("OnEvent", relayout)
    events:RegisterEvent("UI_SCALE_CHANGED")
    events:RegisterEvent("DISPLAY_SIZE_CHANGED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
end

---------------------------------------------------------------------------
-- The button (same look as other classic minimap buttons)
---------------------------------------------------------------------------
local function createButton()
    -- Parent UIParent and a name without "Minimap"/"LibDBIcon": see the top of this file.
    button = CreateFrame("Button", "EncoreEssentialsCrestButton", UIParent, "BackdropTemplate")
    button:SetSize(FRAME_SIZE, FRAME_SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetClampedToScreen(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    -- Round style: the classic minimap button art
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)

    -- The crest's red disc and infinity sign, cut to a circle (its own gold ring is left out).
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.18, 0.82, 0.18, 0.82)
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    local mask = button:CreateMaskTexture()
    mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    button.round = { background, icon, border }

    -- Square style: the whole crest in a rounded, gold-edged square
    local squareIcon = button:CreateTexture(nil, "ARTWORK")
    squareIcon:SetTexture(ICON)
    squareIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    squareIcon:SetPoint("TOPLEFT", 4, -4)
    squareIcon:SetPoint("BOTTOMRIGHT", -4, 4)
    button.squareIcon = squareIcon

    button:SetScript("OnClick", function(self, mouseButton)
        if self.justDragged then
            self.justDragged = nil
            return
        end
        if mouseButton == "RightButton" then
            Encore:OpenMenu(self)
        else
            GameTooltip:Hide()
            Encore:ToggleHub()
        end
    end)
    button:SetScript("OnMouseDown", function(self)
        self.icon:SetPoint("TOPLEFT", 8, -6)
        self.squareIcon:SetPoint("TOPLEFT", 5, -5)
        self.squareIcon:SetPoint("BOTTOMRIGHT", -3, 3)
    end)
    button:SetScript("OnMouseUp", function(self)
        self.icon:SetPoint("TOPLEFT", 7, -5)
        self.squareIcon:SetPoint("TOPLEFT", 4, -4)
        self.squareIcon:SetPoint("BOTTOMRIGHT", -4, 4)
    end)
    -- Dragging: only when detached and unlocked
    button:SetScript("OnDragStart", function(self)
        local settings = Encore.db.settings.minimap
        if not settings.detached or settings.locked then return end
        GameTooltip:Hide()
        self.moving = true
        self:StartMoving()
    end)
    button:SetScript("OnDragStop", function(self)
        if not self.moving then return end
        self:StopMovingOrSizing()
        self.moving = nil
        self.justDragged = true
        C_Timer.After(0, function() self.justDragged = nil end)
        Encore:SaveMinimapButtonPosition()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cffeb9339Encore|r Essentials")
        GameTooltip:AddLine(L.MINIMAP_TIP_CLICK, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_TIP_RIGHTCLICK, 1, 1, 1)
        local settings = Encore.db.settings.minimap
        if settings.detached and not settings.locked then GameTooltip:AddLine(L.MINIMAP_TIP_DRAG, 0, 1, 0) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Safety net for changes no hook sees (another addon reparenting the minimap, etc.): cheap re-check twice a second.
    local elapsedSince = 0
    button:SetScript("OnUpdate", function(_, elapsed)
        elapsedSince = elapsedSince + elapsed
        if elapsedSince < 0.5 then return end
        elapsedSince = 0
        layout()
    end)

    -- Resize knob for the square button (shown only while detached, square and unlocked)
    local grip = CreateFrame("Button", nil, button)
    grip:SetSize(12, 12)
    grip:SetPoint("BOTTOMRIGHT", 2, -2)
    grip:SetFrameLevel(button:GetFrameLevel() + 5)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:Hide()
    button.grip = grip
    local sizing
    local function cursor()
        local x, y = GetCursorPosition()
        local scale = button:GetEffectiveScale()
        return x / scale, y / scale
    end
    local function stopSizing()
        if not sizing then return end
        sizing = nil
        button.sizing = nil
        grip:SetScript("OnUpdate", nil)
        Encore.db.settings.minimap.size = math.floor(button:GetWidth() + 0.5)
        Encore:SaveMinimapButtonPosition()
    end
    grip:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        local left, top = button:GetLeft(), button:GetTop()
        if not left then return end
        GameTooltip:Hide()
        -- Pin the top-left corner so only the bottom-right corner follows the cursor
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        local x, y = cursor()
        sizing = { x = x, y = y, size = button:GetWidth() }
        button.sizing = true
        grip:SetScript("OnUpdate", function()
            if not IsMouseButtonDown("LeftButton") then return stopSizing() end
            local cx, cy = cursor()
            local delta = math.max(cx - sizing.x, sizing.y - cy) -- whichever way the cursor moved further
            local size = math.max(SQUARE_MIN, math.min(SQUARE_MAX, sizing.size + delta))
            button:SetSize(size, size)
        end)
    end)
    grip:SetScript("OnMouseUp", stopSizing)
    grip:SetScript("OnHide", stopSizing)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.MINIMAP_TIP_RESIZE)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    hookSources()
end

-- Switches the button between the round minimap look and the larger rounded square.
local currentStyle
function applyStyle(square)
    square = square and true or false
    if currentStyle == square then return end
    currentStyle = square
    for _, region in ipairs(button.round) do region:SetShown(not square) end
    button.squareIcon:SetShown(square)
    if square then
        button:SetSize(SQUARE_SIZE, SQUARE_SIZE)
        button:SetBackdrop(SQUARE_BACKDROP)
        button:SetBackdropColor(0.07, 0.03, 0.02, 0.9)
        button:SetBackdropBorderColor(0.92, 0.58, 0.2, 1) -- Encore gold
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        local hl = button:GetHighlightTexture()
        hl:ClearAllPoints()
        hl:SetPoint("TOPLEFT", 3, -3)
        hl:SetPoint("BOTTOMRIGHT", -3, 3)
    else
        button:SetSize(FRAME_SIZE, FRAME_SIZE)
        button:SetBackdrop(nil)
        button:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
        local hl = button:GetHighlightTexture()
        hl:ClearAllPoints()
        hl:SetAllPoints()
    end
end

-- Creates, places and shows or hides the button from the saved settings. Safe to call again after a reset.
function Encore:RefreshMinimapButton()
    local settings = self.db.settings.minimap
    if settings.hide then
        if button then button:Hide() end
        return
    end
    if not button then createButton() end
    relayout()
    button:SetShown(settings.detached or Minimap:IsShown())
end

-- Saves where a detached button was dropped, as an offset of its centre from the screen's bottom-left.
function Encore:SaveMinimapButtonPosition()
    if not button then return end
    local x, y = button:GetCenter()
    if not x then return end
    local ratio = button:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local p = { "CENTER", "BOTTOMLEFT", math.floor(x * ratio + 0.5), math.floor(y * ratio + 0.5) }
    self.db.settings.minimap.point = p
    button:SetUserPlaced(false) -- our own saved spot, not the game's layout cache
    relayout()
end

-- Detaches the button where it is now (optionally as the square), unlocked so it can be dragged straight away.
function Encore:DetachMinimapButton(square)
    local settings = self.db.settings.minimap
    if not button then createButton() end
    settings.detached = true
    settings.locked = false
    settings.square = square and true or false
    self:SaveMinimapButtonPosition()
    self:RefreshMinimapButton()
    self:Print(L.MINIMAP_UNLOCKED)
end

function Encore:SetMinimapButtonLocked(locked)
    self.db.settings.minimap.locked = locked and true or false
    self:Print(locked and L.MINIMAP_LOCKED or L.MINIMAP_UNLOCKED)
    relayout()
end

function Encore:SetMinimapButtonSquare(square)
    self.db.settings.minimap.square = square and true or false
    relayout()
end

-- Back below the sun/moon on the minimap, round again.
function Encore:ReattachMinimapButton()
    local settings = self.db.settings.minimap
    settings.detached = false
    settings.locked = false
    settings.square = false
    self:RefreshMinimapButton()
end

function Encore:SetMinimapButtonShown(shown)
    self.db.settings.minimap.hide = not shown
    self:RefreshMinimapButton()
end

---------------------------------------------------------------------------
-- Addon compartment entry (named in the .toc as AddonCompartmentFunc)
---------------------------------------------------------------------------
function EncoreEssentials_OnAddonCompartmentClick()
    -- Open on the next frame: the compartment's own menu is still closing during this click.
    C_Timer.After(0, function() Encore:ToggleHub() end)
end
