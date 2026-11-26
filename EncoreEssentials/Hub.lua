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
        status = function()
            if Encore.modules.DB then return L.STATUS_DB_READY, "good" end
            return L.STATUS_DB_IDLE, "dim"
        end,
    },
    {
        name = "Encore-Stonks",
        folder = "EncoreEssentials_Stonks",
        icon = MEDIA .. "encore-stonks-icon",
        desc = L.MODULE_STONKS_DESC,
        missing = L.STONKS_MISSING,
        open = function() Encore:ToggleStonks() end,
        status = function()
            local s = Encore.modules.Stonks
            if not s then return nil end
            if s.HasAuctionator and not s:HasAuctionator() then return L.STATUS_STONKS_OFF, "bad" end
            if s.IsRecording and s:IsRecording() then return L.STATUS_STONKS_ON, "good" end
            return L.STATUS_STONKS_WAIT, "dim"
        end,
    },
    {
        name = "Encore-QoL",
        folder = "EncoreEssentials_QoL",
        icon = MEDIA .. "encore-qol-icon",
        desc = L.MODULE_QOL_DESC,
        missing = L.QOL_MISSING,
        open = function() Encore:ToggleQoL() end,
        status = function()
            local q = Encore.modules.QoL
            if not (q and q.order) then return nil end
            local on, bad = 0, 0
            for _, f in ipairs(q.order) do
                if f.active then on = on + 1 end
                if f.status == "error" then bad = bad + 1 end
            end
            if bad > 0 then return L.STATUS_QOL_ERR:format(on, bad), "bad" end
            return L.STATUS_QOL:format(on), on > 0 and "good" or "dim"
        end,
    },
    {
        name = "Encore-PvP",
        folder = "EncoreEssentials_PvP",
        icon = "Interface\\Icons\\Ability_DualWield",
        desc = L.MODULE_PVP_DESC,
        missing = L.PVP_MISSING,
        open = function()
            local p = Encore:LoadModule("PvP", "EncoreEssentials_PvP", L.PVP_MISSING)
            if p then p:Toggle() end
        end,
        status = function()
            local p = Encore.modules.PvP
            local q = Encore.modules.QoL
            if not (p and q and q.features) then return nil end
            local h = q.features.bgHistory
            local list = type(EncorePvPDB) == "table" and EncorePvPDB.history
            if h and h.active and type(list) == "table" then return L.STATUS_PVP:format(#list), "good" end
            return nil
        end,
    },
    {
        name = "Encore-Alts",
        folder = "EncoreEssentials_Alts",
        icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
        desc = L.MODULE_ALTS_DESC,
        missing = L.ALTS_MISSING,
        open = function()
            local a = Encore:LoadModule("Alts", "EncoreEssentials_Alts", L.ALTS_MISSING)
            if a then a:Toggle() end
        end,
        status = function()
            local a = Encore.modules.Alts
            if not (a and a.Chars) then return nil end
            local n, gold = 0, 0
            for _, c in pairs(a:Chars()) do n = n + 1; gold = gold + (c.money or 0) end
            return L.STATUS_ALTS:format(n, math.floor(gold / 10000)), "good"
        end,
    },
    {
        name = "Encore-Professions",
        folder = "EncoreEssentials_Professions",
        icon = "Interface\\Icons\\INV_Misc_Note_01",
        desc = L.MODULE_PROFESSIONS_DESC,
        missing = L.PROFESSIONS_MISSING,
        open = function()
            local p = Encore:LoadModule("Professions", "EncoreEssentials_Professions", L.PROFESSIONS_MISSING)
            if not p then return end
            if not p:IsOn() then p:SetOn(true) end
            Encore:Print(L.PROFESSIONS_HOW)
        end,
        status = function()
            local p = Encore.modules.Professions
            if not (p and p.IsOn) then return nil end
            if p:IsOn() then return L.STATUS_PROFESSIONS_ON, "good" end
            return L.STATUS_PROFESSIONS_OFF, "dim"
        end,
    },
}

-- Modules are laid out as tiles, left to right, starting a new row after COLUMNS tiles.
local COLUMNS = 5
local TILE_W = 150
local TILE_H = 156
local TILE_GAP = 8
local SIDE = 16     -- left/right padding
local TOP = 64      -- room for the title bar and portrait
local BOTTOM = 36   -- room for the footer hint
local MIN_WIDTH = 340
local ICON_SIZE = 56

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
    -- Center the grid when the window is wider than the tiles need
    local left = math.max(SIDE, (parent:GetWidth() - gridWidth()) / 2)

    local row = CreateFrame("Button", nil, parent)
    row:SetSize(TILE_W, TILE_H)
    row:SetPoint("TOPLEFT", left + col * (TILE_W + TILE_GAP), -(TOP + line * (TILE_H + TILE_GAP)))

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.92, 0.58, 0.2, 0.15) -- Encore gold

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
    desc:SetPoint("BOTTOM", 0, 22)
    desc:SetWidth(TILE_W - 12)
    desc:SetJustifyH("CENTER")
    desc:SetJustifyV("TOP")
    desc:SetText(module.desc or "")
    row.desc = desc

    -- What the module is doing right now (filled in each time the window opens)
    local status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOM", 0, 8)
    status:SetWidth(TILE_W - 12)
    status:SetJustifyH("CENTER")
    status:SetWordWrap(false)
    row.status = status

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
        local text, tone
        if installed and row.module.status then
            local ok, t, c = pcall(row.module.status)
            if ok then text, tone = t, c end
        end
        local c = tone == "good" and { 0.45, 0.85, 0.40 } or tone == "bad" and { 1, 0.35, 0.3 } or { 0.64, 0.57, 0.47 }
        row.status:SetTextColor(c[1], c[2], c[3])
        row.status:SetText(text or "")
    end
    if frame.hint then
        if Encore.newerVersion then
            frame.hint:SetText(L.HUB_NEWER:format(Encore.newerVersion))
            frame.hint:SetFontObject(GameFontNormalSmall)
        else
            frame.hint:SetText(L.HUB_HINT)
            frame.hint:SetFontObject(GameFontDisableSmall)
        end
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
    frame.hint = hint

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
