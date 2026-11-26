-- Encore-Alts: remembers each of your characters (account-wide, EncoreAltsDB): class, level, gold, rested
-- experience, professions and their cooldowns, raid lockouts, and what is in their bags and bank. Item tooltips
-- say how many of an item your other characters have. Nothing is sent anywhere.
local addonName, ns = ...
local Encore = _G.EncoreEssentials
local A = {}
ns.Alts = A
_G.EncoreAlts = A

local C = C_Container or {}
local GetNumSlots = C.GetContainerNumSlots or _G.GetContainerNumSlots
local GetItemCount = (C_Item and C_Item.GetItemCount) or _G.GetItemCount

local tocVersion = C_AddOns.GetAddOnMetadata(addonName, "Version")
A.version = (tocVersion and not tocVersion:find("@", 1, true)) and tocVersion or "dev"

local function Print(fmt, ...)
    DEFAULT_CHAT_FRAME:AddMessage("|cffeb9339Encore-Alts|r: " .. (select("#", ...) > 0 and fmt:format(...) or fmt))
end
A.Print = Print

-- Profession cooldowns worth knowing on every character (spell IDs; transmutes share one cooldown).
A.COOLDOWNS = {
    { key = "transmute", name = "Transmute", spells = { 17187, 11479, 11480, 17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566 } },
    { key = "mooncloth", name = "Mooncloth", spells = { 18560 } },
}
A.ITEM_COOLDOWNS = {
    { key = "saltShaker", name = "Salt Shaker", item = 15846 },
}

---------------------------------------------------------------------------
-- Saved data: EncoreAltsDB.chars["Name - Realm"] = { ... }
---------------------------------------------------------------------------
local me -- this character's table

local function fullName()
    local name, second = UnitName("player")
    if second and second ~= "" and RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
        local consts = Constants and Constants.CharacterNameSeparatorConsts
        name = name .. (consts and consts.CHARACTERNAME_SURNAME_SEPARATOR or " ") .. second
    end
    return name
end

function A:Key() return fullName() .. " - " .. (GetRealmName() or "?") end

function A:Chars()
    if type(EncoreAltsDB) ~= "table" then EncoreAltsDB = {} end
    if type(EncoreAltsDB.chars) ~= "table" then EncoreAltsDB.chars = {} end
    return EncoreAltsDB.chars
end

function A:Forget(key)
    local chars = self:Chars()
    for k in pairs(chars) do
        if k == key or k:lower():find(key:lower(), 1, true) == 1 then
            chars[k] = nil
            Print("Forgot %s.", k)
            if self.Refresh then self:Refresh() end
            return true
        end
    end
    Print("No character named %s.", key)
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------
local function scanBags(first, last)
    local counts = {}
    for bag = first, last do
        for slot = 1, (GetNumSlots and GetNumSlots(bag) or 0) do
            local id, n
            if C.GetContainerItemInfo then
                local info = C.GetContainerItemInfo(bag, slot)
                if info then id, n = info.itemID, info.stackCount end
            else
                local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
                id, n = link and tonumber(link:match("item:(%d+)")), count
            end
            if id then counts[id] = (counts[id] or 0) + (n or 1) end
        end
    end
    return counts
end

function A:ScanBags()
    if not me then return end
    me.bags = scanBags(0, NUM_BAG_SLOTS or 4)
end

function A:ScanBank()
    if not me then return end
    local bank = scanBags(BANK_CONTAINER or -1, BANK_CONTAINER or -1)
    local first = (NUM_BAG_SLOTS or 4) + 1
    local more = scanBags(first, first + (NUM_BANKBAGSLOTS or 6) - 1)
    for id, n in pairs(more) do bank[id] = (bank[id] or 0) + n end
    me.bank = bank
end

function A:ScanProfessions()
    if not me then return end
    local list = {}
    -- Primary professions can be unlearned; the secondary ones are known by their spell names (any language).
    local secondary = {}
    local spellName = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end
    for _, id in ipairs({ 2550, 3273, 7620 }) do
        local n = spellName(id)
        if n then secondary[n] = true end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, header, _, rank, _, _, maxRank, abandonable = GetSkillLineInfo(i)
            if name and not header and (abandonable or secondary[name]) then
                list[#list + 1] = { name = name, rank = rank, max = maxRank }
            end
        end
    end
    me.profs = list
end

local GetSpellCooldown = function(id)
    if C_Spell and C_Spell.GetSpellCooldown then
        local cd = C_Spell.GetSpellCooldown(id)
        if cd then return cd.startTime, cd.duration end
    elseif _G.GetSpellCooldown then
        return _G.GetSpellCooldown(id)
    end
end

local function knows(id) return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) end

function A:ScanCooldowns()
    if not me then return end
    local cds = {}
    local now, clock = time(), GetTime()
    for _, c in ipairs(self.COOLDOWNS) do
        for _, id in ipairs(c.spells) do
            if knows(id) then
                local start, dur = GetSpellCooldown(id)
                local left = (start and dur and dur > 1.5) and (start + dur - clock) or 0
                cds[c.key] = now + math.max(0, math.floor(left))
                break
            end
        end
    end
    for _, c in ipairs(self.ITEM_COOLDOWNS) do
        if (GetItemCount(c.item) or 0) > 0 then
            local get = (C_Container and C_Container.GetItemCooldown) or _G.GetItemCooldown
            local start, dur = get and get(c.item)
            local left = (start and dur and dur > 1.5) and (start + dur - clock) or 0
            cds[c.key] = now + math.max(0, math.floor(left))
        end
    end
    me.cooldowns = cds
end

function A:ScanLockouts()
    if not me then return end
    local list = {}
    for i = 1, (GetNumSavedInstances and GetNumSavedInstances() or 0) do
        local name, _, reset, _, locked = GetSavedInstanceInfo(i)
        if name and locked and reset and reset > 0 then list[#list + 1] = { name = name, reset = time() + reset } end
    end
    me.lockouts = list
end

function A:ScanBasics()
    if not me then return end
    local _, class = UnitClass("player")
    me.name, me.realm, me.class = fullName(), GetRealmName(), class
    me.level, me.money, me.seen = UnitLevel("player"), GetMoney(), time()
    me.faction = UnitFactionGroup("player")
    me.xp, me.xpMax, me.rested = UnitXP("player"), UnitXPMax("player"), GetXPExhaustion and GetXPExhaustion() or 0
    me.resting = IsResting() and true or nil
end

-- Rested experience now: what was stored, plus what builds while logged out (5% of a level per 8 hours in an
-- inn or city, a quarter of that elsewhere), up to one and a half levels.
function A.RestedNow(c)
    if not (c and c.xpMax and c.xpMax > 0) then return nil end
    local hours = math.max(0, (time() - (c.seen or time())) / 3600)
    local rate = (c.resting and 0.05 or 0.0125) / 8
    local cap = c.xpMax * 1.5
    return math.min(cap, (c.rested or 0) + c.xpMax * rate * hours), c.xpMax
end

---------------------------------------------------------------------------
-- Item tooltips: how many your other characters have
---------------------------------------------------------------------------
local CLASS_HEX = {}
local function classHex(class)
    if CLASS_HEX[class or ""] then return CLASS_HEX[class or ""] end
    local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[class or ""]
    local hex = c and ("%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) or "ffffff"
    CLASS_HEX[class or ""] = hex
    return hex
end
A.ClassHex = classHex

local function tipOn() return not (EncoreAltsDB and EncoreAltsDB.tooltip == false) end

local function addLines(tooltip, id)
    if not (id and tipOn()) or tooltip.encoreAltsID == id then return end
    local lines, total = {}, 0
    local key = A:Key()
    for k, c in pairs(A:Chars()) do
        local bags = c.bags and c.bags[id] or 0
        local bank = c.bank and c.bank[id] or 0
        if bags + bank > 0 and k ~= key then
            local where = bank > 0 and (bags > 0 and ("bags %d, bank %d"):format(bags, bank) or ("bank %d"):format(bank)) or ("bags %d"):format(bags)
            lines[#lines + 1] = { "|cff" .. classHex(c.class) .. (c.name or k) .. "|r", (bags + bank) .. "  |cff9d9d9d" .. where .. "|r" }
            total = total + bags + bank
        end
    end
    if #lines == 0 then return end
    tooltip.encoreAltsID = id
    table.sort(lines, function(a, b) return a[1] < b[1] end)
    tooltip:AddLine("|cffeb9339Encore-Alts|r", 1, 1, 1)
    for _, l in ipairs(lines) do tooltip:AddDoubleLine("   " .. l[1], l[2], 1, 1, 1, 1, 1, 1) end
    if tooltip:IsShown() then tooltip:Show() end
end

local function idOf(tooltip, data)
    local id = data and data.id
    if not id and tooltip.GetItem then
        local _, link = tooltip:GetItem()
        id = link and tonumber(link:match("item:(%d+)"))
    end
    return id
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        local ok, err = pcall(addLines, tooltip, idOf(tooltip, data))
        if not ok then geterrorhandler()(err) end
    end)
else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt and tt.HookScript then
            tt:HookScript("OnTooltipSetItem", function(self)
                local ok, err = pcall(addLines, self, idOf(self))
                if not ok then geterrorhandler()(err) end
            end)
        end
    end
end
for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tt and tt.HookScript then
        local clear = function(self) self.encoreAltsID = nil end
        tt:HookScript("OnTooltipCleared", clear)
        tt:HookScript("OnHide", clear)
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
local bagsDirty = false
f:SetScript("OnEvent", function(self, event)
    local ok, err = pcall(function()
        if event == "PLAYER_LOGIN" then
            local chars = A:Chars()
            local key = A:Key()
            chars[key] = chars[key] or {}
            me = chars[key]
            A:ScanBasics()
            A:ScanBags()
            C_Timer.After(5, function()
                A:ScanProfessions()
                A:ScanCooldowns()
                if RequestRaidInfo then RequestRaidInfo() end
            end)
            for _, e in ipairs({ "PLAYER_MONEY", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING",
                "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED", "UPDATE_INSTANCE_INFO",
                "SKILL_LINES_CHANGED", "TRADE_SKILL_UPDATE", "SPELL_UPDATE_COOLDOWN", "PLAYER_LOGOUT" }) do
                pcall(self.RegisterEvent, self, e)
            end
        elseif event == "PLAYER_MONEY" or event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_UPDATE_RESTING" then
            A:ScanBasics()
        elseif event == "BAG_UPDATE_DELAYED" then
            if not bagsDirty then
                bagsDirty = true
                C_Timer.After(1, function() bagsDirty = false; A:ScanBags() end)
            end
        elseif event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED" then
            C_Timer.After(0.5, function() A:ScanBank() end)
        elseif event == "UPDATE_INSTANCE_INFO" then
            A:ScanLockouts()
        elseif event == "SKILL_LINES_CHANGED" then
            A:ScanProfessions()
        elseif event == "TRADE_SKILL_UPDATE" or event == "SPELL_UPDATE_COOLDOWN" then
            if not A.cdPending then
                A.cdPending = true
                C_Timer.After(2, function() A.cdPending = false; A:ScanCooldowns() end)
            end
        elseif event == "PLAYER_LOGOUT" then
            A:ScanBasics()
        end
        if A.Refresh then A:Refresh() end
    end)
    if not ok then geterrorhandler()(err) end
end)
f:RegisterEvent("PLAYER_LOGIN")

if Encore and Encore.RegisterModule then Encore:RegisterModule("Alts", A) end

SLASH_ENCOREALTS1 = "/ealts"
SLASH_ENCOREALTS2 = "/encorealts"
SlashCmdList.ENCOREALTS = function(input)
    local cmd, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "forget" and rest ~= "" then
        A:Forget(rest)
    elseif cmd == "tooltip" then
        if type(EncoreAltsDB) ~= "table" then EncoreAltsDB = {} end
        if EncoreAltsDB.tooltip == false then EncoreAltsDB.tooltip = nil else EncoreAltsDB.tooltip = false end
        Print("Item counts in tooltips: %s.", EncoreAltsDB.tooltip == false and "off" or "on")
    else
        A:Toggle()
    end
end
