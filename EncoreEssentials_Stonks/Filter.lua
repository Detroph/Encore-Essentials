-- Encore-Stonks browser filters, like the auction house's Filter dropdown (Det, 2026-11-20):
-- level range (required level), Uncollected Only, Usable Only and the rarity checkboxes Poor to Legendary.
-- Choices are saved in Stonks' settings. Browser.lua asks Filter.Pass(key) for every listed item and calls
-- Filter.Attach once to put the Filter button beside the Name search.
local _, ns = ...
local Stonks = ns.Stonks
local U = ns.UI

local Filter = {}
ns.Filter = Filter

local QUALITIES = { 0, 1, 2, 3, 4, 5 } -- Poor, Common, Uncommon, Rare, Epic, Legendary
local QUALITY_NAMES = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary" }

---------------------------------------------------------------------------
-- Settings: { minLevel, maxLevel, uncollected, usable, hideQuality = { [q] = true } }
---------------------------------------------------------------------------
local function settings()
    local s = Stonks:Settings()
    if type(s.filters) ~= "table" then s.filters = {} end
    local f = s.filters
    if type(f.hideQuality) ~= "table" then f.hideQuality = {} end
    return f
end

function Filter.IsActive()
    local f = settings()
    if f.minLevel or f.maxLevel or f.uncollected or f.usable then return true end
    for _, q in ipairs(QUALITIES) do
        if f.hideQuality[q] then return true end
    end
    return false
end

function Filter.Reset()
    local s = Stonks:Settings()
    s.filters = { hideQuality = {} }
end

---------------------------------------------------------------------------
-- Usable / collected, read from the item's tooltip (red lines = you can't use it; "Already known").
-- Cached per item until the character changes (level, spells, skills, collections).
---------------------------------------------------------------------------
local scanTip
local usableCache, knownCache = {}, {}

local function isRed(fs)
    if not (fs and fs:IsShown()) then return false end
    local text = fs:GetText()
    if not text or text == "" then return false end
    local r, g, b = fs:GetTextColor()
    return r > 0.95 and g < 0.2 and b < 0.2
end

local KNOWN_TEXTS = {}
for _, k in ipairs({ "ITEM_SPELL_KNOWN", "TRANSMOGRIFY_TOOLTIP_APPEARANCE_KNOWN", "TRANSMOGRIFY_TOOLTIP_ITEM_UNKNOWN_APPEARANCE_KNOWN" }) do
    if type(_G[k]) == "string" then KNOWN_TEXTS[_G[k]] = true end
end
KNOWN_TEXTS["Already known"] = true

-- Returns usable, known; nil when the game hasn't loaded the item yet.
local function scan(id)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "EncoreStonksScanTip", UIParent, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    if scanTip.SetItemByID then
        scanTip:SetItemByID(id)
    else
        scanTip:SetHyperlink("item:" .. id)
    end
    local n = scanTip:NumLines() or 0
    if n == 0 then
        scanTip:Hide()
        return nil
    end
    local usable, known = true, false
    for i = 2, n do
        local left, right = _G["EncoreStonksScanTipTextLeft" .. i], _G["EncoreStonksScanTipTextRight" .. i]
        if isRed(left) or isRed(right) then usable = false end
        local text = left and left:GetText()
        if text and KNOWN_TEXTS[text] then known = true end
    end
    scanTip:Hide()
    return usable, known
end

local function scanCached(id)
    if usableCache[id] == nil then
        local usable, known = scan(id)
        if usable == nil then return nil end
        usableCache[id], knownCache[id] = usable, known
    end
    return usableCache[id], knownCache[id]
end

local function isCollected(id)
    local _, known = scanCached(id)
    if known then return true end
    if C_TransmogCollection and C_TransmogCollection.PlayerHasTransmog then
        local ok, has = pcall(C_TransmogCollection.PlayerHasTransmog, id)
        if ok and has then return true end
    end
    if PlayerHasToy then
        local ok, has = pcall(PlayerHasToy, id)
        if ok and has then return true end
    end
    return false
end

local changes = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LEVEL_UP", "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED", "SKILL_LINES_CHANGED",
    "NEW_PET_ADDED", "NEW_MOUNT_ADDED", "NEW_TOY_ADDED", "TRANSMOG_COLLECTION_UPDATED", "COMPANION_LEARNED" }) do
    pcall(changes.RegisterEvent, changes, ev) -- some of these don't exist on every client
end
changes:SetScript("OnEvent", function()
    wipe(usableCache)
    wipe(knownCache)
end)

---------------------------------------------------------------------------
-- The filter itself. Items the game hasn't loaded yet pass; the browser re-renders when they arrive.
---------------------------------------------------------------------------
function Filter.Pass(key)
    local f = settings()
    if not Filter.IsActive() then return true end
    local id = U.itemIDOf(key)
    if not id then return true end
    local _, _, quality, _, reqLevel = GetItemInfo(id)
    if quality == nil then return true end
    if f.hideQuality[quality] then return false end
    reqLevel = reqLevel or 0
    if f.minLevel and reqLevel < f.minLevel then return false end
    if f.maxLevel and reqLevel > f.maxLevel then return false end
    if f.usable then
        if reqLevel > (UnitLevel("player") or 0) then return false end
        local usable = scanCached(id)
        if usable == false then return false end
    end
    if f.uncollected and isCollected(id) then return false end
    return true
end

---------------------------------------------------------------------------
-- Filter button and dropdown
---------------------------------------------------------------------------
local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function qualityColor(q)
    if C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(q)
        if r then return r, g, b end
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function header(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 12, y)
    fs:SetText(text)
    return fs
end

local function checkRow(parent, text, y, get, set, r, g, b)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", 10, y)
    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    label:SetText(text)
    if r then label:SetTextColor(r, g, b) end
    cb:SetHitRectInsets(0, -(label:GetStringWidth() + 6), 0, 0)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb.Refresh = function(self) self:SetChecked(get()) end
    return cb
end

local function levelBox(parent, field, onChange)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(30, 20)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(2)
    box:SetJustifyH("CENTER")
    box:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local v = tonumber(self:GetText())
        settings()[field] = (v and v > 0) and v or nil
        onChange()
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTabPressed", function(self)
        if self.next then self.next:SetFocus() else self:ClearFocus() end
    end)
    box.Refresh = function(self)
        local v = settings()[field]
        self:SetText(v and tostring(v) or "")
    end
    return box
end

-- Puts the Filter button after the search box and moves countText after it.
-- onChange() re-renders the results.
function Filter.Attach(frame, searchBox, countText, onChange)
    local button = U.ToggleButton(frame, "Filter", 76)
    button:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    button.text:ClearAllPoints()
    button.text:SetPoint("CENTER", -5, 0)
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetRotation(-math.pi / 2)

    -- Red cross to clear all filters, shown while any is on (as on the auction house's Filter button)
    local clear = CreateFrame("Button", nil, button)
    clear:SetSize(14, 14)
    clear:SetPoint("CENTER", button, "TOPRIGHT", -2, -2)
    clear:SetFrameLevel(button:GetFrameLevel() + 2)
    local clearTex = clear:CreateTexture(nil, "ARTWORK")
    clearTex:SetAllPoints()
    if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("auctionhouse-ui-filter-redx")
        and pcall(clearTex.SetAtlas, clearTex, "auctionhouse-ui-filter-redx")) then
        clearTex:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    end
    clear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    U.tooltip(clear, function(tt) tt:SetText("Clear filters") end)

    countText:ClearAllPoints()
    countText:SetPoint("LEFT", button, "RIGHT", 14, 0)
    countText:SetPoint("RIGHT", -40, 0)

    local popup = CreateFrame("Frame", "EncoreStonksFilterDropdown", frame, "BackdropTemplate")
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetBackdrop(BACKDROP)
    popup:SetBackdropColor(0, 0, 0, 0.92)
    popup:SetBackdropBorderColor(1, 0.82, 0, 1)
    popup:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    popup:SetWidth(170)
    popup:Hide()

    local controls = {}
    local function changed()
        button:SetOn(Filter.IsActive())
        clear:SetShown(Filter.IsActive())
        onChange()
    end
    local function refreshAll()
        for _, c in ipairs(controls) do c:Refresh() end
        button:SetOn(Filter.IsActive())
        clear:SetShown(Filter.IsActive())
    end

    local y = -10
    header(popup, "Level Range", y)
    y = y - 20
    local minBox = levelBox(popup, "minLevel", changed)
    minBox:SetPoint("TOPLEFT", 18, y)
    local dash = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dash:SetPoint("LEFT", minBox, "RIGHT", 4, 0)
    dash:SetText("-")
    local maxBox = levelBox(popup, "maxLevel", changed)
    maxBox:SetPoint("LEFT", dash, "RIGHT", 8, 0)
    minBox.next = maxBox
    controls[#controls + 1], controls[#controls + 2] = minBox, maxBox
    y = y - 30

    controls[#controls + 1] = checkRow(popup, "Uncollected Only", y,
        function() return settings().uncollected end,
        function(v) settings().uncollected = v or nil; changed() end)
    y = y - 22
    controls[#controls + 1] = checkRow(popup, "Usable Only", y,
        function() return settings().usable end,
        function(v) settings().usable = v or nil; changed() end)
    y = y - 30

    header(popup, "Rarity", y)
    y = y - 18
    for _, q in ipairs(QUALITIES) do
        local name = _G["ITEM_QUALITY" .. q .. "_DESC"] or QUALITY_NAMES[q]
        local r, g, b = qualityColor(q)
        controls[#controls + 1] = checkRow(popup, name, y,
            function() return not settings().hideQuality[q] end,
            function(v) settings().hideQuality[q] = (not v) or nil; changed() end,
            r, g, b)
        y = y - 22
    end
    popup:SetHeight(-y + 10)

    -- Close on a click anywhere else
    pcall(popup.RegisterEvent, popup, "GLOBAL_MOUSE_DOWN")
    popup:SetScript("OnEvent", function(self)
        if not self:IsShown() then return end
        if self:IsMouseOver() or button:IsMouseOver() then return end
        self:Hide()
    end)
    popup:SetScript("OnHide", function()
        minBox:ClearFocus()
        maxBox:ClearFocus()
    end)

    button:SetScript("OnClick", function()
        if popup:IsShown() then
            popup:Hide()
        else
            refreshAll()
            popup:Show()
        end
    end)
    U.tooltip(button, function(tt)
        tt:SetText("Filter")
        tt:AddLine("Level range, usable, uncollected and rarity, like the auction house's filter.", 1, 1, 1, true)
    end)
    clear:SetScript("OnClick", function()
        Filter.Reset()
        refreshAll()
        onChange()
    end)

    refreshAll()
    return button
end
