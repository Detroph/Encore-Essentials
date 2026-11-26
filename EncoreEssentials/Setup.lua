-- Encore Essentials: the setup window. Lists the Encore modules as tiles, explains each one, and lets the player
-- turn any of them off. Nothing changes until the button at the bottom: "Done" when every module is as it was,
-- "Reload UI" when something changed (the game only loads or unloads addons on a reload).
--
-- Shown on the first login after installing Encore, and once on the first login after a full release from
-- SETUP_FROM for players who already had Encore; both times in place of the What's new window (WhatsNew.lua).
-- /encore setup opens it any time. The window has one fixed size: the description box scrolls instead of growing.
local _, ns = ...
local L = ns.L
local Encore = ns.Encore

local MEDIA = "Interface\\AddOns\\EncoreEssentials\\Media\\"

-- Every module the window can list, in tile order. A module whose folder isn't installed is left out.
-- needs: the folder this one depends on; while that one is off, this one can't load either.
local MODULES = {
    { folder = "EncoreEssentials_DB", name = "Encore-DB", icon = MEDIA .. "encore-db-icon",
      short = L.SETUP_DB_SHORT, text = L.SETUP_DB_TEXT, note = L.SETUP_DB_NOTE },
    { folder = "EncoreEssentials_Stonks", name = "Encore-Stonks", icon = MEDIA .. "encore-stonks-icon",
      short = L.SETUP_STONKS_SHORT, text = L.SETUP_STONKS_TEXT, auctionator = true },
    { folder = "EncoreEssentials_QoL", name = "Encore-QoL", icon = MEDIA .. "encore-qol-icon",
      short = L.SETUP_QOL_SHORT, text = L.SETUP_QOL_TEXT, note = L.SETUP_QOL_NOTE },
    { folder = "EncoreEssentials_PvP", name = "Encore-PvP", icon = MEDIA .. "encore-pvp-icon",
      short = L.SETUP_PVP_SHORT, text = L.SETUP_PVP_TEXT, needs = "EncoreEssentials_QoL" },
    { folder = "EncoreEssentials_Alts", name = "Encore-Alts", icon = MEDIA .. "encore-alts-icon",
      short = L.SETUP_ALTS_SHORT, text = L.SETUP_ALTS_TEXT },
    { folder = "EncoreEssentials_Professions", name = "Encore-Professions", icon = MEDIA .. "encore-professions-icon",
      short = L.SETUP_PROF_SHORT, text = L.SETUP_PROF_TEXT },
}
Encore.SETUP_MODULES = MODULES
Encore.SETUP_FROM = "0.2.6" -- the first full release that shows the window to players who already have Encore

local WIDTH, HEIGHT = 664, 620
local SIDE, COLUMNS, TILE_H, GAP = 16, 3, 142, 8
local TILE_W = math.floor((WIDTH - 2 * SIDE - (COLUMNS - 1) * GAP) / COLUMNS)
local TILES_TOP = 100
local GREEN = { 0.45, 0.85, 0.40 }
local RED = { 1, 0.42, 0.36 }
local DIM = { 0.64, 0.57, 0.47 }

local frame
local list = {}      -- installed modules shown as tiles
local byFolder = {}
local state = { selected = nil, notes = nil, showNotes = false, localOnly = false }

local function playerName() return (UnitName("player")) end

-- Enabled for this character, either just for it or for all characters.
local function isEnabled(folder)
    local ok, s = pcall(C_AddOns.GetAddOnEnableState, folder, playerName())
    if ok and type(s) == "number" then return s > 0 end
    return C_AddOns.IsAddOnLoaded(folder) and true or false
end

-- What the player has picked, after dependencies: a module whose required module is off is off too.
local function effective(m)
    if not m.wanted then return false end
    local need = m.needs and byFolder[m.needs]
    if need then return effective(need) end
    return true
end

local function changes()
    local off, on = {}, {}
    for _, m in ipairs(list) do
        if m.wanted ~= m.was then
            if m.wanted then on[#on + 1] = m.name else off[#off + 1] = m.name end
        elseif m.needs and byFolder[m.needs] and not effective(m) and m.was then
            off[#off + 1] = m.name -- stops loading because the module it needs is turned off
        end
    end
    return off, on
end

local function apply()
    local character = state.localOnly and playerName() or nil
    local changed = false
    for _, m in ipairs(list) do
        if m.wanted ~= m.was then
            changed = true
            if m.wanted then
                pcall(C_AddOns.EnableAddOn, m.folder, character)
            else
                pcall(C_AddOns.DisableAddOn, m.folder, character)
            end
        end
    end
    if not changed then
        frame:Hide()
        return
    end
    if C_AddOns.SaveAddOns then pcall(C_AddOns.SaveAddOns) end
    ReloadUI()
end

local function statusLine(m)
    if m.needs and m.wanted and not effective(m) then
        return L.SETUP_OFF_BECAUSE:format(byFolder[m.needs].name), RED
    end
    if m.auctionator then
        if C_AddOns.DoesAddOnExist("Auctionator") then return L.SETUP_AUCTIONATOR_FOUND, GREEN end
        return L.SETUP_AUCTIONATOR_MISSING, RED
    end
    if m.needs then return L.SETUP_NEEDS:format(byFolder[m.needs] and byFolder[m.needs].name or m.needs), DIM end
    if m.note then return m.note, DIM end
    return nil
end

local function showDetail()
    local d = frame.detail
    if state.showNotes and state.notes then
        d.icon:SetTexture(MEDIA .. "encore-crest")
        d.name:SetText(L.SETUP_WHATSNEW:format(state.version or Encore.version))
        d.status:SetText("")
        local lines = {}
        for _, e in ipairs(state.notes) do
            if #state.notes > 1 then lines[#lines + 1] = "|cffeb9339" .. e.version .. "|r" end
            for _, t in ipairs(e.lines) do lines[#lines + 1] = "|cffeb9339•|r " .. t end
        end
        d.text:SetText(table.concat(lines, "\n"))
    else
        local m = state.selected or list[1]
        if not m then return end
        d.icon:SetTexture(m.icon)
        d.name:SetText(m.name)
        local s, c = statusLine(m)
        d.status:SetText(s or "")
        if c then d.status:SetTextColor(c[1], c[2], c[3]) end
        d.text:SetText(m.text)
    end
    d.child:SetHeight(d.text:GetStringHeight() + 4)
    d.scroll:SetVerticalScroll(0)
end

local function refresh()
    for _, m in ipairs(list) do
        local t = m.tile
        local on = effective(m)
        t.icon:SetDesaturated(not on)
        t.icon:SetVertexColor(on and 1 or 0.6, on and 1 or 0.6, on and 1 or 0.6)
        if on then
            t.name:SetTextColor(1, 0.82, 0)
            t.short:SetTextColor(0.95, 0.90, 0.81)
            t.switch:SetText(L.SETUP_ON)
            t.switch:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
            t.switchBox:SetBorderColor(GREEN, 0.55)
        else
            t.name:SetTextColor(0.54, 0.49, 0.41)
            t.short:SetTextColor(DIM[1], DIM[2], DIM[3])
            t.switch:SetText(L.SETUP_OFF)
            t.switch:SetTextColor(RED[1], RED[2], RED[3])
            t.switchBox:SetBorderColor(RED, 0.5)
        end
        t.selected:SetShown(not state.showNotes and state.selected == m)
    end
    local off, on = changes()
    local who = state.localOnly and L.SETUP_WHO_CHAR or L.SETUP_WHO_ALL
    local parts = {}
    if #off > 0 then parts[#parts + 1] = L.SETUP_TURN_OFF:format(who, "|cffff6a5c" .. table.concat(off, ", ") .. "|r") end
    if #on > 0 then parts[#parts + 1] = L.SETUP_TURN_ON:format(who, "|cff73d966" .. table.concat(on, ", ") .. "|r") end
    if #parts > 0 then
        frame.message:SetText(table.concat(parts, " ") .. " " .. L.SETUP_RELOADS)
        frame.message:SetFontObject(GameFontHighlightSmall)
        frame.go:SetText(L.SETUP_RELOAD)
    else
        frame.message:SetText(L.SETUP_CORE_ON)
        frame.message:SetFontObject(GameFontDisableSmall)
        frame.go:SetText(L.SETUP_DONE)
    end
    showDetail()
end

local function selectModule(m)
    if state.selected == m and not state.showNotes then return end
    state.selected = m
    state.showNotes = false
    refresh()
end

local function createTile(m, index)
    local UI = Encore.UI
    local col = (index - 1) % COLUMNS
    local line = math.floor((index - 1) / COLUMNS)
    local t = CreateFrame("Button", nil, frame)
    t:SetSize(TILE_W, TILE_H)
    t:SetPoint("TOPLEFT", SIDE + col * (TILE_W + GAP), -(TILES_TOP + line * (TILE_H + GAP)))
    local bg = t:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)
    local hl = t:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.92, 0.58, 0.2, 0.14)
    t.selected = CreateFrame("Frame", nil, t)
    t.selected:SetAllPoints()
    UI.Border(t.selected, UI.COPPER, 0.55)

    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(48, 48)
    t.icon:SetPoint("TOP", 0, -10)
    t.icon:SetTexture(m.icon)

    t.name = t:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t.name:SetPoint("TOP", t.icon, "BOTTOM", 0, -5)
    t.name:SetWidth(TILE_W - 12)
    t.name:SetWordWrap(false)
    t.name:SetText(m.name)

    t.short = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.short:SetPoint("TOP", t.name, "BOTTOM", 0, -4)
    t.short:SetWidth(TILE_W - 16)
    t.short:SetJustifyH("CENTER")
    t.short:SetText(m.short)

    t.switchBox = CreateFrame("Frame", nil, t)
    t.switchBox:SetSize(46, 16)
    t.switchBox:SetPoint("BOTTOM", 0, 8)
    UI.Border(t.switchBox, GREEN, 0.55)
    t.switch = t.switchBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.switch:SetPoint("CENTER")

    t:SetScript("OnEnter", function() selectModule(m) end)
    t:SetScript("OnClick", function()
        state.selected = m
        state.showNotes = false
        local need = m.needs and byFolder[m.needs]
        if need and not effective(need) then
            refresh() -- can't be switched while the module it needs is off; the detail box says why
            return
        end
        m.wanted = not effective(m)
        PlaySound(m.wanted and (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
            or (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857))
        refresh()
    end)
    m.tile = t
end

local function createDetail()
    local UI = Encore.UI
    local d = CreateFrame("Frame", nil, frame)
    d:SetPoint("TOPLEFT", SIDE, -(TILES_TOP + 2 * TILE_H + GAP + 10))
    d:SetPoint("BOTTOMRIGHT", -SIDE, 50)
    local bg = d:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.45)
    UI.Border(d, UI.COPPER, 0.25)

    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(36, 36)
    d.icon:SetPoint("TOPLEFT", 10, -10)
    d.name = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 12, 0)
    d.status = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.status:SetPoint("LEFT", d.name, "RIGHT", 8, 0)

    d.scroll = CreateFrame("ScrollFrame", nil, d, "UIPanelScrollFrameTemplate")
    d.scroll:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 12, -18)
    d.scroll:SetPoint("BOTTOMRIGHT", -30, 8)
    d.child = CreateFrame("Frame", nil, d.scroll)
    d.child:SetSize(WIDTH - 2 * SIDE - 100, 10)
    d.scroll:SetScrollChild(d.child)
    d.text = d.child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.text:SetPoint("TOPLEFT")
    d.text:SetWidth(WIDTH - 2 * SIDE - 100)
    d.text:SetJustifyH("LEFT")
    d.text:SetSpacing(2)
    frame.detail = d
end

local function createWindow()
    local UI = Encore.UI
    frame = CreateFrame("Frame", "EncoreEssentialsSetupFrame", UIParent, "PortraitFrameTemplate")
    frame:Hide()
    tinsert(UISpecialFrames, "EncoreEssentialsSetupFrame") -- Escape closes it and keeps every module as it is
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetTitle then frame:SetTitle("|cffeb9339Encore|r Essentials") end
    if frame.CloseButton then frame.CloseButton:SetScript("OnClick", function() frame:Hide() end) end
    UI.Skin(frame) -- the shared Encore frame with the Encore crest

    frame.intro = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.intro:SetPoint("TOPLEFT", 70, -34)
    frame.intro:SetWidth(WIDTH - 70 - SIDE)
    frame.intro:SetJustifyH("LEFT")
    frame.intro:SetSpacing(2)

    for _, m in ipairs(MODULES) do
        if C_AddOns.DoesAddOnExist(m.folder) then
            list[#list + 1] = m
            byFolder[m.folder] = m
        end
    end
    for i, m in ipairs(list) do createTile(m, i) end
    createDetail()

    -- After an update: brings the release notes back into the description box after hovering a tile.
    frame.notesLink = CreateFrame("Button", nil, frame.detail)
    frame.notesLink:SetPoint("TOPRIGHT", -10, -8)
    frame.notesLink:SetSize(200, 16)
    local link = frame.notesLink:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    link:SetPoint("RIGHT")
    UI.Color(link, UI.COPPER)
    frame.notesLink.text = link
    frame.notesLink:SetScript("OnClick", function()
        state.showNotes = true
        refresh()
    end)
    frame.notesLink:SetScript("OnEnter", function() link:SetTextColor(1, 0.82, 0) end)
    frame.notesLink:SetScript("OnLeave", function() UI.Color(link, UI.COPPER) end)

    local only = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    only:SetSize(24, 24)
    only:SetPoint("BOTTOMLEFT", SIDE - 2, 14)
    local onlyText = only.Text or only.text or only:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    onlyText:ClearAllPoints()
    onlyText:SetPoint("LEFT", only, "RIGHT", 2, 0)
    onlyText:SetFontObject(GameFontHighlightSmall)
    onlyText:SetText(L.SETUP_THIS_CHAR)
    only:SetScript("OnClick", function(self)
        state.localOnly = self:GetChecked() and true or false
        refresh()
    end)
    UI.Tooltip(only, L.SETUP_THIS_CHAR, L.SETUP_THIS_CHAR_TIP)
    frame.only = only

    frame.go = UI.Button(frame, L.SETUP_DONE, apply, 110)
    frame.go:SetPoint("BOTTOMRIGHT", -SIDE, 16)

    frame.message = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.message:SetPoint("LEFT", onlyText, "RIGHT", 14, 0)
    frame.message:SetPoint("RIGHT", frame.go, "LEFT", -12, 0)
    frame.message:SetJustifyH("LEFT")
    frame.message:SetHeight(28)

    frame:SetScript("OnShow", function(self)
        self:ClearAllPoints()
        self:SetPoint("CENTER")
        PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839)
    end)
    frame:SetScript("OnHide", function() PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE or 840) end)
end

-- notes: What's new entries to show in the description box (the update launch), or nil.
-- update: true on the launch after an update, which changes the opening line.
function Encore:ShowSetup(notes, update)
    if not frame then createWindow() end
    for _, m in ipairs(list) do
        m.was = isEnabled(m.folder)
        m.wanted = m.was
    end
    state.notes = (notes and #notes > 0) and notes or nil
    state.showNotes = state.notes ~= nil
    state.version = self.version
    state.selected = list[1]
    state.localOnly = false
    frame.only:SetChecked(false)
    frame.intro:SetText(update and L.SETUP_INTRO_UPDATE:format(self.version) or L.SETUP_INTRO)
    frame.notesLink:SetShown(state.notes ~= nil)
    frame.notesLink.text:SetText(L.SETUP_WHATSNEW:format(self.version))
    frame.notesLink:SetWidth(frame.notesLink.text:GetStringWidth() + 4)
    refresh()
    frame:Show()
end
