-- Encore Essentials: the main window. Opens in the middle of the screen from the minimap button
-- (left-click) or the addon compartment, and lists the Encore modules. Click a module to open it.
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

local WIDTH = 420
local TOP = 64      -- room for the title bar and portrait
local ROW_H = 64
local ROW_GAP = 6
local BOTTOM = 36   -- room for the footer hint
local ICON_SIZE = 48

local frame

local function isInstalled(module)
    return not module.folder or C_AddOns.DoesAddOnExist(module.folder)
end

local function createRow(parent, module, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 16, -(TOP + (index - 1) * (ROW_H + ROW_GAP)))
    row:SetPoint("TOPRIGHT", -16, -(TOP + (index - 1) * (ROW_H + ROW_GAP)))

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.92, 0.58, 0.2, 0.15) -- Encore gold

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexture(module.icon)
    row.icon = icon

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -6)
    name:SetPoint("RIGHT", -10, 0)
    name:SetJustifyH("LEFT")
    name:SetText(module.name)
    row.name = name

    local desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    desc:SetPoint("RIGHT", -10, 0)
    desc:SetJustifyH("LEFT")
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
    local count = #Encore.MODULE_LIST
    frame:SetSize(WIDTH, TOP + count * ROW_H + (count - 1) * ROW_GAP + BOTTOM)
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
    -- Copper frame, like the Encore-DB window
    if frame.NineSlice then
        for _, region in ipairs({ frame.NineSlice:GetRegions() }) do
            if region.SetVertexColor then region:SetVertexColor(1, 0.74, 0.5) end
        end
    end

    local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    heading:SetPoint("TOPLEFT", 70, -36)
    heading:SetText(L.HUB_MODULES)

    frame.rows = {}
    for i, module in ipairs(Encore.MODULE_LIST) do
        frame.rows[i] = createRow(frame, module, i)
    end

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", 0, 14)
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
