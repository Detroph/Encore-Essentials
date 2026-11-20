-- Encore Essentials: the main window. Opens in the middle of the screen from the minimap button
-- (left-click) or the addon compartment, and shows the Encore modules as tiles, four to a row.
-- Click a module to open it.
local _, ns = ...
local L = ns.L
local Encore = ns.Encore

local MEDIA = "Interface\\AddOns\\EncoreEssentials\\Media\\"
local CREST = MEDIA .. "encore-crest"

-- The modules shown in the window, in order. New modules are added here.
Encore.MODULE_LIST = {
    {
        name = "Encore-DB",
        folder = "EncoreEssentials_DB",
        icon = MEDIA .. "encore-db-icon",
        desc = L.MODULE_DB_DESC,
        open = function() Encore:ToggleDB() end,
    },
    {
        name = "Encore-Stonks",
        folder = "EncoreEssentials_Stonks",
        icon = MEDIA .. "encore-stonks-icon",
        desc = L.MODULE_STONKS_DESC,
        missing = L.STONKS_MISSING,
        open = function() Encore:ToggleStonks() end,
    },
}

-- Modules are laid out as tiles, left to right, starting a new row after COLUMNS tiles.
local COLUMNS = 4
local TILE_W = 150
local TILE_H = 156
local TILE_GAP = 8
local SIDE = 16     -- left/right padding
local TOP = 64      -- room for the title bar and portrait
local BOTTOM = 36   -- room for the footer hint
local MIN_WIDTH = 340
local ICON_SIZE = 56
local PANE_PAD = 8  -- space between the pane's edge and the tiles

local frame

local function isInstalled(module)
    return not module.folder or C_AddOns.DoesAddOnExist(module.folder)
end

-- Columns actually used: never more than COLUMNS, never more than the module count.
local function gridColumns()
    return math.max(1, math.min(COLUMNS, #Encore.MODULE_LIST))
end

local function gridWidth()
    local cols = gridColumns()
    return cols * TILE_W + (cols - 1) * TILE_GAP
end

local function createRow(parent, module, index)
    local col = (index - 1) % COLUMNS
    local line = math.floor((index - 1) / COLUMNS)
    -- parent is the Auction House-style pane; center the grid in it
    local left = math.max(PANE_PAD, (parent:GetWidth() - gridWidth()) / 2)

    local row = CreateFrame("Button", nil, parent)
    row:SetSize(TILE_W, TILE_H)
    row:SetPoint("TOPLEFT", left + col * (TILE_W + TILE_GAP), -(PANE_PAD + line * (TILE_H + TILE_GAP)))

    -- Each module is a tile drawn like an auction house list entry: a row stripe, the gold hover glow
    -- and a thin gold frame
    Encore.Theme.AHRow(row)
    Encore.Theme.Border(row, { 0.72, 0.56, 0.30 }, 0.45)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("TOP", 0, -10)
    icon:SetTexture(module.icon)
    row.icon = icon

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOP", icon, "BOTTOM", 0, -6)
    name:SetWidth(TILE_W - 12)
    name:SetJustifyH("CENTER")
    name:SetWordWrap(false)
    name:SetText(module.name)
    row.name = name

    local desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOP", name, "BOTTOM", 0, -4)
    desc:SetPoint("BOTTOM", 0, 6)
    desc:SetWidth(TILE_W - 12)
    desc:SetJustifyH("CENTER")
    desc:SetJustifyV("TOP")
    desc:SetText(module.desc or "")
    row.desc = desc

    row:SetScript("OnClick", function()
        if not isInstalled(module) then
            Encore:Print(module.missing or L.DB_MISSING)
            return
        end
        frame:Hide()
        module.open()
    end)
    row.module = module
    return row
end

local function refreshRows()
    for _, row in ipairs(frame.rows) do
        local installed = isInstalled(row.module)
        row.icon:SetDesaturated(not installed)
        row.icon:SetAlpha(installed and 1 or 0.5)
        row.name:SetTextColor(installed and 1 or 0.5, installed and 0.82 or 0.5, installed and 0 or 0.5)
        row.desc:SetText(installed and (row.module.desc or "") or L.MODULE_MISSING)
    end
end

local function createWindow()
    frame = CreateFrame("Frame", "EncoreEssentialsHubFrame", UIParent, "PortraitFrameTemplate")
    frame:Hide()
    tinsert(UISpecialFrames, "EncoreEssentialsHubFrame") -- Escape closes it
    local lines = math.max(1, math.ceil(#Encore.MODULE_LIST / COLUMNS))
    frame:SetSize(math.max(MIN_WIDTH, gridWidth() + 2 * SIDE),
        TOP + lines * TILE_H + (lines - 1) * TILE_GAP + BOTTOM)
    frame:SetPoint("CENTER")
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetTitle then frame:SetTitle("|cffeb9339Encore|r Essentials") end
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)
    end

    local portrait = frame.GetPortrait and frame:GetPortrait() or frame.portrait
    if portrait then
        portrait:SetTexture(CREST)
        portrait:SetTexCoord(0, 1, 0, 1)
    end
    -- Parchment window with the red border and title bar; the modules sit in an Auction House-style pane
    Encore.Theme.ApplyWindow(frame)

    local heading = frame:CreateFontString(nil, "OVERLAY", "EncoreTitle")
    heading:SetPoint("TOPLEFT", 70, -36)
    heading:SetText(L.HUB_MODULES)

    local pane = CreateFrame("Frame", nil, frame)
    pane:SetPoint("TOPLEFT", SIDE - PANE_PAD, -(TOP - PANE_PAD))
    pane:SetPoint("BOTTOMRIGHT", -(SIDE - PANE_PAD), BOTTOM - PANE_PAD)
    Encore.Theme.AHPane(pane, "auctionhouse-background-index")

    frame.rows = {}
    for i, module in ipairs(Encore.MODULE_LIST) do
        frame.rows[i] = createRow(pane, module, i)
    end

    local hint = frame:CreateFontString(nil, "OVERLAY", "EncoreInkSmall")
    hint:SetPoint("BOTTOM", 0, 10)
    hint:SetText(L.HUB_HINT)

    frame:SetScript("OnShow", function(self)
        -- Always open in the middle of the screen
        self:ClearAllPoints()
        self:SetPoint("CENTER")
        refreshRows()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839)
    end)
    frame:SetScript("OnHide", function()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE or 840)
    end)
end

function Encore:ToggleHub()
    if not frame then createWindow() end
    frame:SetShown(not frame:IsShown())
end
