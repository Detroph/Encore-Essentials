-- Encore-QoL: Professions tab, one-button fishing. Kept in its own folder and saved table (EncoreQoLProfDB),
-- so it can move into a separate "Encore - Professions" addon later with its settings.
--
-- How it works: one key, set in Options > Keybindings > Encore-QoL (no key by default). With no bobber out it
-- casts Fishing. While the bobber is out the same key becomes Interact with your soft target, which is the
-- bobber, so pressing it at the splash reels in. The game doesn't allow pressing it for you. Key changes are
-- only allowed out of combat, so all of this works out of combat only.
-- Ideas from EzFishing Forever (MIT), Better Fishing and Angleur (All Rights Reserved); own code.
local _, ns = ...
local Q = ns.QoL
local W = Q.W

local FISHING_ID = 7620
local POLE_CLASS, POLE_SUBCLASS = 2, 20
-- Lures by skill bonus, best first.
local LURES = { { 6533, 100 }, { 34861, 100 }, { 6532, 75 }, { 7307, 75 }, { 6530, 50 }, { 6811, 50 }, { 6529, 25 } }

local BUTTON = "EncoreQoLFishButton"
_G.BINDING_HEADER_ENCOREQOL = "Encore-QoL"
_G["BINDING_NAME_CLICK " .. BUTTON .. ":LeftButton"] = "One-button fishing"

local function fishingName() return Q.SpellName(FISHING_ID) or "Fishing" end

local function isPole(link)
    if not link then return false end
    local classID, subClassID = select(6, C_Item.GetItemInfoInstant(link))
    return classID == POLE_CLASS and subClassID == POLE_SUBCLASS
end

local function bagItems(fn)
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, Q.GetContainerNumSlots(bag) or 0 do
            local info = Q.GetContainerItemInfo(bag, slot)
            if type(info) == "table" and info.itemID then fn(info, bag, slot) end
        end
    end
end

local function bestPole()
    local best, bestLevel
    bagItems(function(info)
        if isPole(info.hyperlink or info.itemID) then
            local level = select(4, Q.GetItemInfo(info.itemID)) or 0
            if not best or level > bestLevel then best, bestLevel = info.itemID, level end
        end
    end)
    return best
end

local function bestLure()
    local have = {}
    bagItems(function(info) have[info.itemID] = true end)
    for _, l in ipairs(LURES) do if have[l[1]] then return l[1] end end
end

local function lureLeft()
    local has, expires = GetWeaponEnchantInfo()
    if has and expires then return expires / 1000 end
    return 0
end

-- The secure button exists from the start so the key binding always has something to click; it only gets a
-- spell while the feature is on.
local button = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate")
button:SetSize(1, 1)
button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
button:RegisterForClicks(C_CVar.GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")

local bindOwner = CreateFrame("Frame")
local clickOwner = CreateFrame("Frame")

local function fishingKeys()
    local keys = { GetBindingKey("CLICK " .. BUTTON .. ":LeftButton") }
    return keys
end

local fish -- the feature, set below

local function setInteract(on)
    if InCombatLockdown() then return end
    if on then
        Q.SetCVar("SoftTargetInteract", "3")
        for _, key in ipairs(fishingKeys()) do SetOverrideBinding(bindOwner, true, key, "INTERACTTARGET") end
    else
        ClearOverrideBindings(bindOwner)
    end
end

-- Louder splash and auto loot only while you fish; put back after a while without casting.
local boosted = false
local function boost(on)
    if on == boosted or not fish then return end
    boosted = on
    if on then
        if fish:Get("loud") then
            Q.SetCVar("Sound_SFXVolume", "1")
            Q.SetCVar("Sound_EnableSFX", "1")
            Q.SetCVar("Sound_MusicVolume", "0")
            Q.SetCVar("Sound_AmbienceVolume", "0")
        end
        if fish:Get("autoLoot") then Q.SetCVar("autoLootDefault", "1") end
    else
        for _, c in ipairs({ "Sound_SFXVolume", "Sound_EnableSFX", "Sound_MusicVolume", "Sound_AmbienceVolume", "autoLootDefault" }) do Q.RestoreCVar(c) end
    end
end

-- Weapons you had before the pole went on.
local function restoreWeapons()
    local saved = fish and fish:Saved().weapons
    if type(saved) ~= "table" then return end
    if saved[1] then EquipItemByName(saved[1], INVSLOT_MAINHAND or 16) end
    if saved[2] then EquipItemByName(saved[2], INVSLOT_OFFHAND or 17) end
    fish:Saved().weapons = nil
end

local function prepareClick()
    if InCombatLockdown() or not fish or not fish.active then return end
    button:SetAttribute("type", "spell")
    button:SetAttribute("spell", fishingName())
    button:SetAttribute("item", nil)
    button:SetAttribute("target-slot", nil)
    local main = GetInventoryItemLink("player", INVSLOT_MAINHAND or 16)
    if not isPole(main) then
        if fish:Get("equip") then
            local pole = bestPole()
            if pole then
                fish:Saved().weapons = { main and C_Item.GetItemInfoInstant(main) or nil, GetInventoryItemID("player", INVSLOT_OFFHAND or 17) }
                button:SetAttribute("type", "item")
                button:SetAttribute("item", "item:" .. pole)
                return
            end
        end
        return
    end
    if fish:Get("lure") and lureLeft() <= 0 then
        local lure = bestLure()
        if lure then
            button:SetAttribute("type", "item")
            button:SetAttribute("item", "item:" .. lure)
            button:SetAttribute("target-slot", INVSLOT_MAINHAND or 16)
        end
    end
end
button:SetScript("PreClick", prepareClick)

---------------------------------------------------------------------------
-- Catch log: catches per zone, saved in the Professions table.
---------------------------------------------------------------------------
local function catchDB()
    local t = fish and fish:Saved()
    if not t then return {} end
    if type(t.catches) ~= "table" then t.catches = {} end
    if type(t.time) ~= "table" then t.time = {} end
    if type(t.escaped) ~= "table" then t.escaped = {} end
    return t
end

local session = { catches = 0, start = nil }

local function zoneName() return GetSubZoneText() ~= "" and GetSubZoneText() or GetRealZoneText() or "?" end

local function recordLoot()
    if not (IsFishingLoot and IsFishingLoot()) then return end
    local db, zone = catchDB(), zoneName()
    db.catches[zone] = db.catches[zone] or {}
    for i = 1, GetNumLootItems() do
        local link = GetLootSlotLink(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then
            local _, _, quantity = GetLootSlotInfo(i)
            db.catches[zone][id] = (db.catches[zone][id] or 0) + (quantity or 1)
            session.catches = session.catches + (quantity or 1)
        end
    end
end

---------------------------------------------------------------------------
-- Fishing bar: skill, lure time left and this session's catches while a pole is equipped.
---------------------------------------------------------------------------
local function fishingSkill()
    if GetProfessions then
        local _, _, _, fishIndex = GetProfessions()
        if fishIndex then
            local _, _, rank, max, _, _, _, modifier = GetProfessionInfo(fishIndex)
            return rank, max, modifier
        end
    end
    if GetNumSkillLines then
        local name = fishingName()
        for i = 1, GetNumSkillLines() do
            local skill, _, _, rank, _, modifier, max = GetSkillLineInfo(i)
            if skill == name then return rank, max, modifier end
        end
    end
end

local bar
local function makeBar()
    bar = CreateFrame("Frame", "EncoreQoLFishingBar", UIParent)
    bar:SetSize(230, 44)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetClampedToScreen(true)
    W.Panel(bar, 0.88)
    local strip = bar:CreateTexture(nil, "BORDER")
    strip:SetPoint("TOPLEFT", 1, -1); strip:SetPoint("TOPRIGHT", -1, -1); strip:SetHeight(18)
    strip:SetColorTexture(0.7, 0.04, 0.03, 0.7)
    bar.title = W.Text(bar, "GameFontNormalSmall", "Fishing", W.GOLD)
    bar.title:SetPoint("TOPLEFT", 6, -4)
    bar.skill = W.Text(bar, "GameFontHighlightSmall", "")
    bar.skill:SetPoint("TOPRIGHT", -6, -4)
    bar.line = W.Text(bar, "GameFontHighlightSmall", "")
    bar.line:SetPoint("BOTTOMLEFT", 6, 6)
    bar.line:SetWidth(218)
    local p = Q.profDB.frames.fishingBar
    if type(p) == "table" and p[1] then bar:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else bar:SetPoint("BOTTOM", 0, 220) end
    bar:SetScript("OnDragStart", bar.StartMoving)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, b, x, y = self:GetPoint(1)
        Q.profDB.frames.fishingBar = { a, b, x, y }
    end)
    bar:Hide()
end

local function updateBar()
    if not fish or not fish.active or not fish:Get("bar") or not Q.PoleEquipped() then
        if bar then bar:Hide() end
        return
    end
    if not bar then makeBar() end
    local rank, max, modifier = fishingSkill()
    if rank then
        bar.skill:SetText(("Skill %d%s / %d"):format(rank, (modifier and modifier > 0) and ("+" .. modifier) or "", max or 0))
    else
        bar.skill:SetText("")
    end
    local lure = lureLeft()
    local lureText = lure > 0 and ("Lure %d:%02d"):format(lure / 60, lure % 60) or "|cffff9d8fNo lure|r"
    bar.line:SetText(lureText .. "     Caught this session: " .. session.catches)
    bar:Show()
end

---------------------------------------------------------------------------
-- The feature
---------------------------------------------------------------------------
local lastCast = 0
local lureWarned = false

fish = Q:Feature{
    id = "fishing", tab = "professions", section = "Fishing", name = "One-button fishing",
    desc = "One key casts Fishing, and the same key reels in when the bobber splashes. Set the key in Options > Keybindings > Encore-QoL; none is set by default. Out of combat only.",
    idea = "EzFishing Forever, Better Fishing, Angleur",
    defaults = { doubleClick = false, loud = true, autoLoot = true, equip = false, lure = false, lureWarn = true, bar = true },
    options = {
        { kind = "note", text = function()
            local key = GetBindingKey("CLICK " .. BUTTON .. ":LeftButton")
            return key and ("Fishing key: |cffffd100" .. GetBindingText(key) .. "|r") or "Fishing key: |cffa39278not set|r (Options > Keybindings > Encore-QoL)"
        end },
        { kind = "check", key = "doubleClick", name = "Also cast on a double right-click (pole equipped)" },
        { kind = "check", key = "loud", name = "Louder splash: effects to full, music and ambience off while fishing" },
        { kind = "check", key = "autoLoot", name = "Auto loot while fishing" },
        { kind = "check", key = "equip", name = "Put on your best pole when you press the key; weapons back in combat" },
        { kind = "check", key = "lure", name = "Apply your best lure when none is on" },
        { kind = "check", key = "lureWarn", name = "Warn 30 seconds before the lure ends" },
        { kind = "check", key = "bar", name = "Fishing bar while a pole is equipped (drag to move)" },
        { kind = "button", name = "Open catch log", always = true, onClick = function() Q:ToggleCatchLog() end },
        { kind = "button", name = "Put my weapons back", onClick = function() if not InCombatLockdown() then restoreWeapons() end end },
    },
    detect = {
        { addon = "BetterFishing", var = "BetterFishingDB", key = "autoLoot" },
        { addon = "BetterFishing" },
        { addon = "EzFishing" }, { addon = "EzFishingForever" }, { addon = "Angleur" }, { addon = "OneCast" },
        { addon = "FishingBuddy" },
    },
    Enable = function(f)
        Q:AfterCombat("fishButton", function()
            button:SetAttribute("type", "spell")
            button:SetAttribute("spell", fishingName())
        end)
        f:On("UNIT_SPELLCAST_CHANNEL_START", function(_, unit, _, spellID)
            if unit ~= "player" or Q.SpellName(spellID) ~= fishingName() then return end
            lastCast = GetTime()
            session.start = session.start or GetTime()
            f.castStart = GetTime()
            boost(true)
            setInteract(true)
        end)
        f:On("UNIT_SPELLCAST_CHANNEL_STOP", function(_, unit, _, spellID)
            if unit ~= "player" or Q.SpellName(spellID) ~= fishingName() then return end
            C_Timer.After(0.3, function() setInteract(false) end)
            if f.castStart then
                local db, zone = catchDB(), zoneName()
                db.time[zone] = (db.time[zone] or 0) + (GetTime() - f.castStart)
                f.castStart = nil
            end
        end)
        f:On("LOOT_OPENED", recordLoot)
        f:On("UI_ERROR_MESSAGE", function(_, _, msg)
            if msg == ERR_FISH_ESCAPED or msg == ERR_FISH_NOT_HOOKED then
                local db, zone = catchDB(), zoneName()
                db.escaped[zone] = (db.escaped[zone] or 0) + 1
            end
        end)
        f:On("PLAYER_REGEN_DISABLED", function()
            boost(false)
            if f:Get("equip") then restoreWeapons() end
        end)
        f:On("PLAYER_EQUIPMENT_CHANGED", function(_, slot)
            if slot == (INVSLOT_MAINHAND or 16) and not Q.PoleEquipped() then boost(false) end
            updateBar()
        end)
        f:Ticker(1, function()
            if boosted and GetTime() - lastCast > 30 then boost(false) end
            if f:Get("lureWarn") and Q.PoleEquipped() then
                local left = lureLeft()
                if left > 0 and left < 30 and not lureWarned then
                    lureWarned = true
                    Q:Print("Your lure runs out in %d seconds.", left)
                    PlaySound(SOUNDKIT.RAID_WARNING or 8959, "Master")
                elseif left > 30 then
                    lureWarned = false
                end
            end
            updateBar()
        end)
        -- Double right-click casts while a pole is equipped (not on top of an existing bobber).
        f:HookScript(WorldFrame, "OnMouseDown", function(_, mouse)
            if mouse ~= "RightButton" or not f:Get("doubleClick") or InCombatLockdown() or not Q.PoleEquipped() then return end
            if UnitChannelInfo("player") then return end
            local now = GetTime()
            if f.lastRight and now - f.lastRight < 0.4 then
                f.lastRight = nil
                SetOverrideBindingClick(clickOwner, true, "BUTTON2", BUTTON)
                C_Timer.After(0.6, function() if not InCombatLockdown() then ClearOverrideBindings(clickOwner) end end)
            else
                f.lastRight = now
            end
        end)
        updateBar()
    end,
    Disable = function()
        boost(false)
        Q:AfterCombat("fishButton", function()
            button:SetAttribute("type", nil)
            button:SetAttribute("spell", nil)
            ClearOverrideBindings(bindOwner)
            ClearOverrideBindings(clickOwner)
        end)
        Q.RestoreCVar("SoftTargetInteract")
        if bar then bar:Hide() end
    end,
}

---------------------------------------------------------------------------
-- Catch log window: one sortable table, every column sorts on click.
---------------------------------------------------------------------------
local log
local logSort = { key = "count", desc = true }
local COLS = {
    { key = "item", title = "Catch", width = 190 },
    { key = "zone", title = "Zone", width = 150 },
    { key = "count", title = "Caught", width = 60 },
    { key = "perHour", title = "Per hour", width = 70 },
    { key = "escaped", title = "Got away", width = 70 },
}

local function logRows()
    local db, rows = catchDB(), {}
    for zone, items in pairs(db.catches or {}) do
        local hours = (db.time[zone] or 0) / 3600
        for id, count in pairs(items) do
            local name = Q.GetItemInfo(id) or ("item " .. id)
            rows[#rows + 1] = { item = name, zone = zone, count = count, perHour = hours > 0.01 and math.floor(count / hours) or 0, escaped = db.escaped[zone] or 0 }
        end
    end
    table.sort(rows, function(a, b)
        local x, y = a[logSort.key], b[logSort.key]
        if x == y then return a.item < b.item end
        if logSort.desc then return x > y end
        return x < y
    end)
    return rows
end

local function drawLog()
    local rows = logRows()
    for i, r in ipairs(rows) do
        local line = log.lines[i]
        if not line then
            line = CreateFrame("Frame", nil, log.content)
            line:SetSize(540, 18)
            line:SetPoint("TOPLEFT", 0, -(i - 1) * 18)
            line.cells = {}
            local x = 4
            for c, col in ipairs(COLS) do
                local fs = W.Text(line, "GameFontHighlightSmall", "")
                fs:SetPoint("LEFT", x, 0)
                fs:SetWidth(col.width - 6)
                fs:SetWordWrap(false)
                line.cells[c] = fs
                x = x + col.width
            end
            log.lines[i] = line
        end
        for c, col in ipairs(COLS) do line.cells[c]:SetText(tostring(r[col.key])) end
        line:Show()
    end
    for i = #rows + 1, #log.lines do log.lines[i]:Hide() end
    log.content:SetHeight(math.max(18, #rows * 18))
    log.empty:SetShown(#rows == 0)
end

function Q:ToggleCatchLog()
    if not log then
        log = CreateFrame("Frame", "EncoreQoLCatchLog", UIParent, "PortraitFrameTemplate")
        tinsert(UISpecialFrames, "EncoreQoLCatchLog")
        log:SetSize(580, 420)
        log:SetPoint("CENTER")
        log:SetFrameStrata("HIGH")
        log:SetMovable(true)
        log:EnableMouse(true)
        log:RegisterForDrag("LeftButton")
        log:SetScript("OnDragStart", log.StartMoving)
        log:SetScript("OnDragStop", log.StopMovingOrSizing)
        log:SetTitle("Encore-QoL: catch log")
        if log.CloseButton then log.CloseButton:SetScript("OnClick", function() log:Hide() end) end
        local portrait = log.GetPortrait and log:GetPortrait() or log.portrait
        if portrait then portrait:SetTexture(Q.ICON) portrait:SetTexCoord(0, 1, 0, 1) end
        local x = 20
        for _, col in ipairs(COLS) do
            local b = CreateFrame("Button", nil, log)
            b:SetSize(col.width, 20)
            b:SetPoint("TOPLEFT", x, -64)
            b.text = W.Text(b, "GameFontNormalSmall", col.title, W.GOLD)
            b.text:SetPoint("LEFT", 4, 0)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(0.92, 0.58, 0.2, 0.15)
            b:SetScript("OnClick", function()
                if logSort.key == col.key then logSort.desc = not logSort.desc else logSort.key, logSort.desc = col.key, col.key ~= "item" and col.key ~= "zone" end
                drawLog()
            end)
            x = x + col.width
        end
        local scroll = CreateFrame("ScrollFrame", nil, log, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -86)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        log.content = CreateFrame("Frame", nil, scroll)
        log.content:SetSize(540, 18)
        scroll:SetScrollChild(log.content)
        log.lines = {}
        log.empty = W.Text(log, "GameFontHighlight", "No catches yet. Fish with one-button fishing on and they show up here.", W.DIM)
        log.empty:SetPoint("TOP", 0, -110)
        log:SetScript("OnShow", drawLog)
        log:Hide()
    end
    log:SetShown(not log:IsShown())
end
