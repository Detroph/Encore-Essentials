-- Encore-Stonks: shared look (same frame, copper border and colours as Encore-DB) and item helpers,
-- used by the browser window (Browser.lua) and the graph panel (Panel.lua).
local _, ns = ...
local Stonks = ns.Stonks
local U = {}
ns.UI = U

U.TEX = {
    crest = "Interface\\AddOns\\EncoreEssentials\\Media\\encore-crest",
    cog = "Interface\\AddOns\\EncoreEssentials_DB\\Media\\cogwheel",
    market = "Interface\\AddOns\\EncoreEssentials\\Media\\encore-stonks-icon",
    questionMark = 134400,
}

-- Colours from the Encore-DB mock-up
U.TEAL = { 0.07, 0.78, 0.78 }
U.TEAL_SOFT = { 0.48, 0.82, 0.80 }
U.COPPER = { 0.92, 0.58, 0.22 }
U.GOLD = { 1, 0.82, 0 }
U.INK = { 0.95, 0.90, 0.81 }
U.DIM = { 0.64, 0.57, 0.47 }
U.GRID = { 0.92, 0.58, 0.22, 0.12 }
U.WHITE = CreateColor(1, 1, 1, 1)

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local GetItemIconByID = (C_Item and C_Item.GetItemIconByID) or _G.GetItemIcon

function U.setColor(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end

function U.addBorder(f, r, g, b, a, layer)
    local t = {}
    for i = 1, 4 do
        t[i] = f:CreateTexture(nil, layer or "BORDER")
        t[i]:SetColorTexture(r, g, b, a or 1)
    end
    t[1]:SetPoint("TOPLEFT"); t[1]:SetPoint("TOPRIGHT"); t[1]:SetHeight(1)
    t[2]:SetPoint("BOTTOMLEFT"); t[2]:SetPoint("BOTTOMRIGHT"); t[2]:SetHeight(1)
    t[3]:SetPoint("TOPLEFT"); t[3]:SetPoint("BOTTOMLEFT"); t[3]:SetWidth(1)
    t[4]:SetPoint("TOPRIGHT"); t[4]:SetPoint("BOTTOMRIGHT"); t[4]:SetWidth(1)
    return t
end

-- Textures given a gradient keep it, so each gets its gradient once and is only shown, hidden or faded after.
function U.gradient(tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    tex:SetColorTexture(1, 1, 1, 1)
    tex:SetGradient(orientation, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
end

function U.gem(parent, point, x, y)
    local COPPER, TEAL = U.COPPER, U.TEAL
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(18, 18)
    f:SetPoint("CENTER", parent, point, x, y)
    f:SetFrameLevel(parent:GetFrameLevel() + 30)
    local sizes = { { 15, 0, 0, 0 }, { 13, COPPER[1], COPPER[2], COPPER[3] }, { 9, TEAL[1], TEAL[2], TEAL[3] } }
    for i, s in ipairs(sizes) do
        local t = f:CreateTexture(nil, "OVERLAY", nil, i)
        t:SetColorTexture(s[2], s[3], s[4], 1)
        t:SetSize(s[1], s[1])
        t:SetPoint("CENTER")
        t:SetRotation(math.rad(45))
    end
    local shine = f:CreateTexture(nil, "OVERLAY", nil, 5)
    shine:SetColorTexture(0.75, 1, 1, 0.9)
    shine:SetSize(3, 3)
    shine:SetPoint("CENTER", -1.5, 1.5)
    shine:SetRotation(math.rad(45))
end

-- A dark inset pane with a black edge and a faint copper inner edge.
function U.well(parent)
    local COPPER = U.COPPER
    local f = CreateFrame("Frame", nil, parent)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.016, 0.012, 0.008, 0.72)
    U.addBorder(f, 0, 0, 0, 1)
    local inner = U.addBorder(f, COPPER[1], COPPER[2], COPPER[3], 0.22)
    inner[1]:SetPoint("TOPLEFT", 1, -1); inner[1]:SetPoint("TOPRIGHT", -1, -1)
    inner[2]:SetPoint("BOTTOMLEFT", 1, 1); inner[2]:SetPoint("BOTTOMRIGHT", -1, 1)
    inner[3]:SetPoint("TOPLEFT", 1, -1); inner[3]:SetPoint("BOTTOMLEFT", 1, 1)
    inner[4]:SetPoint("TOPRIGHT", -1, -1); inner[4]:SetPoint("BOTTOMRIGHT", -1, 1)
    return f
end

function U.tooltip(owner, build)
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        build(GameTooltip, self)
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Coin text with gold, silver and copper icons, like the auction house: "12[g] 34[s] 5[c]", zero parts left out.
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
local function coinParts(copper, short)
    copper = math.floor((copper or 0) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = (BreakUpLargeNumbers and BreakUpLargeNumbers(g) or tostring(g)) .. GOLD_ICON end
    -- Short form (axes, lists): at most two parts, and only gold from 100g up
    if s > 0 and not (short and g >= 100) then out[#out + 1] = s .. SILVER_ICON end
    if c > 0 and not (short and g > 0) then out[#out + 1] = c .. COPPER_ICON end
    if #out == 0 then out[1] = "0" .. COPPER_ICON end
    return table.concat(out, " ")
end

function U.coin(copper) return coinParts(copper, false) end

-- Short coin text for axes and lists: "12g 34s", "56s 7c", "8c" (with icons).
function U.coinShort(copper)
    if not copper then return "-" end
    return coinParts(copper, true)
end

function U.pctText(pct)
    if not pct then return "no data" end
    if math.abs(pct) < 0.5 then return "normal" end
    return ("%+.0f%%"):format(pct)
end

-- Coloured % text: copper when dearer, teal when cheaper.
function U.pctColored(pct)
    if not pct then return "|cff9a8a72-|r" end
    if math.abs(pct) < 0.5 then return "|cff9a8a72=|r" end
    return (pct > 0 and "|cffeb9339%+.0f%%|r" or "|cff7ad1cc%+.0f%%|r"):format(pct)
end

---------------------------------------------------------------------------
-- Items (keys are Auctionator's: an item ID, or "gr:<id>:<suffix>" for random-suffix gear)
---------------------------------------------------------------------------
function U.itemIDOf(key)
    return tonumber(key) or tonumber(tostring(key):match("^gr:(%d+)"))
end

local names = {}
function U.itemName(key)
    if names[key] then return names[key] end
    local id = U.itemIDOf(key)
    local name = id and GetItemInfo(id)
    if name then
        local suffix = tostring(key):match("^gr:%d+:(.+)$")
        if suffix then name = name .. " " .. suffix end
        names[key] = name
        return name
    end
    if tostring(key):match("^p:") then return "Battle pet " .. key:sub(3) end
    return "Item " .. tostring(id or key)
end

function U.itemQualityColor(key)
    local id = U.itemIDOf(key)
    local q = id and select(3, GetItemInfo(id))
    if q and C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(q)
        if r then return r, g, b end
    end
    return U.INK[1], U.INK[2], U.INK[3]
end

function U.itemIcon(key)
    local id = U.itemIDOf(key)
    return (id and GetItemIconByID and GetItemIconByID(id)) or U.TEX.questionMark
end

function U.linkFor(key)
    local id = U.itemIDOf(key)
    if not id then return nil end
    return select(2, GetItemInfo(id))
end

-- Item key from a link, item ID or Auctionator item info.
function U.keyFrom(item)
    if type(item) == "number" then return tostring(item) end
    if type(item) == "string" then
        local id = item:match("|Hitem:(%d+)") or item:match("^item:(%d+)") or item:match("^(%d+)$")
        return id
    end
    if type(item) == "table" then
        if item.itemLink then return U.keyFrom(item.itemLink) end
        if type(item.itemKey) == "table" and item.itemKey.itemID then return tostring(item.itemKey.itemID) end
        if item.itemID then return tostring(item.itemID) end
    end
    return nil
end

---------------------------------------------------------------------------
-- Sortable column header: every column sorts on click, a second click reverses it.
-- columns = { { id, label, point ("LEFT"/"RIGHT"), x, width, desc (first click sorts descending) } }
-- sort = { id = ..., desc = bool } (kept by the caller, e.g. in saved settings); onChange() re-renders.
---------------------------------------------------------------------------
function U.SortHeader(head, columns, sort, onChange)
    local buttons = {}
    local function refresh()
        for _, b in ipairs(buttons) do
            local on = sort.id == b.col.id
            b.arrow:SetShown(on)
            if on then
                if sort.desc then b.arrow:SetTexCoord(0, 0.5625, 0, 1) else b.arrow:SetTexCoord(0, 0.5625, 1, 0) end
            end
            b.label:SetTextColor(on and 1 or 1, on and 0.92 or 0.82, on and 0.6 or 0)
        end
    end
    for _, col in ipairs(columns) do
        local b = CreateFrame("Button", nil, head)
        b.col = col
        b:SetHeight(head:GetHeight() > 0 and head:GetHeight() or 18)
        b:SetWidth(col.width or 70)
        b:SetPoint(col.point, col.x, 0)
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.label:SetText(col.label)
        b.arrow = b:CreateTexture(nil, "OVERLAY")
        b.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
        b.arrow:SetSize(9, 8)
        if col.point == "RIGHT" then
            b.label:SetPoint("RIGHT", 0, 0)
            b.label:SetJustifyH("RIGHT")
            b.arrow:SetPoint("RIGHT", b.label, "LEFT", -2, 0)
        else
            b.label:SetPoint("LEFT", 0, 0)
            b.label:SetJustifyH("LEFT")
            b.arrow:SetPoint("LEFT", b.label, "RIGHT", 2, 0)
        end
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.9, 0.6, 0.08)
        b:SetScript("OnClick", function()
            if sort.id == col.id then sort.desc = not sort.desc else sort.id, sort.desc = col.id, col.desc and true or false end
            refresh()
            onChange()
        end)
        if col.tip then
            U.tooltip(b, function(tt)
                tt:SetText(col.label)
                tt:AddLine(col.tip, 1, 1, 1, true)
                tt:AddLine("Click to sort, click again to reverse.", 0.6, 0.55, 0.45)
            end)
        end
        buttons[#buttons + 1] = b
    end
    refresh()
    return refresh, buttons
end

-- Sort rows by a column. value(row, id) returns a number or string (nil sorts last); ties fall back to name.
function U.SortRows(rows, sort, value)
    local id, desc = sort.id, sort.desc
    table.sort(rows, function(a, b)
        local va, vb = value(a, id), value(b, id)
        if va ~= vb then
            if va == nil then return false end
            if vb == nil then return true end
            if type(va) == "string" then va, vb = va:lower(), tostring(vb):lower() end
            if va ~= vb then
                if desc then return va > vb end
                return va < vb
            end
        end
        if a.name and b.name and a.name ~= b.name then return a.name < b.name end
        return tostring(a.key or a.name or "") < tostring(b.key or b.name or "")
    end)
end

---------------------------------------------------------------------------
-- Window chrome: Encore portrait frame with copper border, title, cogwheel, resize grip, Escape to close.
-- opts = { name, title, width, height, minW, minH, settingsKey, onOptions(owner), onMoved() }
---------------------------------------------------------------------------
function U.CreateWindow(opts)
    local s = Stonks:Settings()
    if type(s[opts.settingsKey]) ~= "table" then s[opts.settingsKey] = {} end
    local saved = s[opts.settingsKey]
    local frame = CreateFrame("Frame", opts.name, UIParent, "PortraitFrameTemplate")
    frame:Hide()
    tinsert(UISpecialFrames, opts.name)
    local size = type(saved.size) == "table" and saved.size or {}
    frame:SetSize(math.max(opts.minW, tonumber(size[1]) or opts.width), math.max(opts.minH, tonumber(size[2]) or opts.height))
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(opts.minW, opts.minH)
    elseif frame.SetMinResize then frame:SetMinResize(opts.minW, opts.minH) end
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    function frame:SavePosition()
        if self.docked then return end -- anchored to another window, not a free position
        local point, _, relPoint, x, y = self:GetPoint(1)
        if point then saved.point = { point, relPoint, x, y } end
    end
    function frame:RestorePosition(defaultX)
        self:ClearAllPoints()
        local p = saved.point
        if type(p) == "table" and p[1] then
            self:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
        else
            self:SetPoint("CENTER", UIParent, "CENTER", defaultX or 0, 0)
        end
    end
    function frame:ResetSize()
        saved.size, saved.point = nil, nil
        self:SetSize(opts.width, opts.height)
        self:RestorePosition()
    end
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.docked = nil
        self:SavePosition()
        if opts.onMoved then opts.onMoved() end
    end)
    frame:SetTitle(opts.title)
    if frame.CloseButton then frame.CloseButton:SetScript("OnClick", function() frame:Hide() end) end

    -- Keep the title-bar and corner buttons above the window border (see Encore-DB's Window.lua).
    local onTop = {}
    local function keepOnTop()
        local level = frame:GetFrameLevel() + 40
        if frame.NineSlice then level = math.max(level, frame.NineSlice:GetFrameLevel() + 5) end
        if frame.CloseButton then level = math.max(level, frame.CloseButton:GetFrameLevel()) end
        for _, b in ipairs(onTop) do b:SetFrameLevel(level) end
    end
    frame:HookScript("OnShow", keepOnTop)
    frame:HookScript("OnMouseDown", keepOnTop)
    hooksecurefunc(frame, "Raise", keepOnTop)
    hooksecurefunc(frame, "SetFrameLevel", keepOnTop)
    -- Other title-bar buttons (the panel's Graphs / History tabs) ask to be kept on top the same way.
    function frame:KeepOnTop(button)
        onTop[#onTop + 1] = button
        keepOnTop()
    end

    if opts.onOptions then
        local cog = CreateFrame("Button", nil, frame)
        onTop[#onTop + 1] = cog
        cog:SetSize(18, 18)
        if frame.CloseButton then cog:SetPoint("RIGHT", frame.CloseButton, "LEFT", -2, 0) else cog:SetPoint("TOPRIGHT", -30, -4) end
        local function cogTexture(layer)
            local t = cog:CreateTexture(nil, layer, nil, 7)
            t:SetAllPoints()
            if not C_AddOns.DoesAddOnExist("EncoreEssentials_DB") or t:SetTexture(U.TEX.cog) == false then
                t:SetTexture("Interface\\Icons\\Trade_Engineering")
                t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            return t
        end
        cogTexture("OVERLAY")
        local lit = cogTexture("HIGHLIGHT")
        lit:SetBlendMode("ADD")
        lit:SetAlpha(0.5)
        cog:SetScript("OnClick", function(self) opts.onOptions(self) end)
        U.tooltip(cog, function(tt) tt:SetText("Encore-Stonks options") end)
    end

    local portrait = frame.GetPortrait and frame:GetPortrait() or frame.portrait
    if portrait then
        portrait:SetTexture(U.TEX.crest)
        portrait:SetTexCoord(0, 1, 0, 1)
    end
    if frame.NineSlice then
        for _, region in ipairs({ frame.NineSlice:GetRegions() }) do
            if region.SetVertexColor then region:SetVertexColor(1, 0.74, 0.5) end
        end
    end
    U.gem(frame, "BOTTOMLEFT", 3, 3)

    -- Resize grip, sized by hand from the cursor (StartSizing snaps to maximum size on some clients)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -5, 5)
    onTop[#onTop + 1] = grip
    keepOnTop()
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    local sizing
    local function stopSizing()
        if not sizing then return end
        sizing = nil
        grip:SetScript("OnUpdate", nil)
        saved.size = { math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5) }
        frame:SavePosition()
    end
    local function cursor()
        local x, y = GetCursorPosition()
        local sc = frame:GetEffectiveScale()
        return x / sc, y / sc
    end
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local left, top = frame:GetLeft(), frame:GetTop()
        if not left or not top then return end
        if not frame.docked then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        local ratio = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
        local cx, cy = cursor()
        sizing = {
            x = cx, y = cy, w = frame:GetWidth(), h = frame:GetHeight(),
            maxW = math.max(opts.minW, UIParent:GetWidth() * ratio - left),
            maxH = math.max(opts.minH, top),
        }
        grip:SetScript("OnUpdate", function()
            if not IsMouseButtonDown("LeftButton") then return stopSizing() end
            local x, y = cursor()
            frame:SetSize(math.min(sizing.maxW, math.max(opts.minW, sizing.w + (x - sizing.x))),
                math.min(sizing.maxH, math.max(opts.minH, sizing.h + (sizing.y - y))))
        end)
    end)
    grip:SetScript("OnMouseUp", stopSizing)
    grip:SetScript("OnHide", stopSizing)
    U.tooltip(grip, function(tt) tt:SetText("Drag to resize") end)

    frame:RestorePosition(opts.defaultX)
    return frame
end

-- A small copper-edged toggle button (chart mode and average buttons, the panel's title-bar tabs).
function U.ToggleButton(parent, label, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 64, 20)
    b.bgOn = b:CreateTexture(nil, "BACKGROUND")
    b.bgOn:SetPoint("TOPLEFT", 1, -1); b.bgOn:SetPoint("BOTTOMRIGHT", -1, 1)
    U.gradient(b.bgOn, "VERTICAL", 0.23, 0.01, 0, 1, 0.76, 0.08, 0.05, 1)
    b.bgOff = b:CreateTexture(nil, "BACKGROUND")
    b.bgOff:SetPoint("TOPLEFT", 1, -1); b.bgOff:SetPoint("BOTTOMRIGHT", -1, 1)
    U.gradient(b.bgOff, "VERTICAL", 0.09, 0.06, 0.04, 1, 0.17, 0.13, 0.09, 1)
    U.addBorder(b, U.COPPER[1], U.COPPER[2], U.COPPER[3], 0.8)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 0.9, 0.6, 0.08)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    function b:SetOn(on)
        self.bgOn:SetShown(on)
        self.bgOff:SetShown(not on)
        self.text:SetTextColor(on and 1 or 0.84, on and 0.95 or 0.73, on and 0.85 or 0.54)
    end
    b:SetOn(false)
    return b
end
