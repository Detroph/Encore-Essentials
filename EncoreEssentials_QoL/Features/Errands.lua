-- Encore-QoL: errands. Open all mail, restock what you always carry, and a ready-check look at your own buffs.
local _, ns = ...
local Q = ns.QoL

local GetItemCount = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
local GetSpellName = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end

---------------------------------------------------------------------------
-- Open all mail
---------------------------------------------------------------------------
Q:Feature{
    id = "openMail", tab = "qol", section = "Errands", name = "Open all mail",
    desc = "An Open all button on the mailbox takes the money and items from every letter, one at a time. Letters with cash on delivery are skipped. Stops when your bags are full. Shift-click opens only letters with money.",
    detect = { { leatrix = "ShowMailOpenAllButton" } },
    Enable = function(f)
        local running, moneyOnly
        local function stop(reason)
            running = false
            if reason then Q:Print(reason) end
            if f.button then f.button:SetText("Open all") end
        end
        local function step()
            if not running then return end
            if not (InboxFrame and InboxFrame:IsVisible()) then return stop() end
            local n = GetInboxNumItems()
            for i = n, 1, -1 do
                local _, _, _, _, money, cod, _, hasItem = GetInboxHeaderInfo(i)
                if (cod or 0) == 0 then
                    if (money or 0) > 0 then
                        TakeInboxMoney(i)
                        C_Timer.After(0.35, step)
                        return
                    end
                    if hasItem and not moneyOnly then
                        for a = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
                            if GetInboxItem(i, a) then
                                TakeInboxItem(i, a)
                                C_Timer.After(0.45, step)
                                return
                            end
                        end
                    end
                end
            end
            stop("Mail: everything taken that can be.")
        end
        f:On("UI_ERROR_MESSAGE", function(_, _, msg)
            if running and (msg == ERR_INV_FULL or msg == ERR_ITEM_MAX_COUNT) then stop("Mail: your bags are full.") end
        end)
        f:On("MAIL_CLOSED", function() stop() end)
        if not f.button and InboxFrame then
            local b = _G.EncoreEssentials.UI.Button(InboxFrame)
            b:SetSize(90, 22)
            b:SetPoint("BOTTOM", InboxFrame, "BOTTOM", -10, 98)
            b:SetText("Open all")
            b:SetScript("OnClick", function(self)
                if running then return stop() end
                running, moneyOnly = true, IsShiftKeyDown()
                self:SetText("Stop")
                step()
            end)
            f.button = b
        end
        if f.button then f.button:Show() end
    end,
    Disable = function(f) if f.button then f.button:Hide() end end,
}

---------------------------------------------------------------------------
-- Restock
---------------------------------------------------------------------------
local function parseList(text)
    local want = {}
    for id, n in tostring(text or ""):gmatch("(%d+)%s*[:=x]%s*(%d+)") do want[tonumber(id)] = tonumber(n) end
    return want
end

Q:Feature{
    id = "restock", tab = "qol", section = "Errands", name = "Restock at vendors",
    desc = "Buys what you always carry up to the amount you set, at any vendor that sells it: reagents, ammunition, poisons, food. Never spends more than the limit per visit. Shift held: nothing is bought.",
    defaults = { list = "", limit = 50 },
    options = {
        { kind = "edit", key = "list", name = "Items and amounts", tip = "Item ID and how many to carry, separated by commas, e.g. 17020:20, 2512:1000. Turn on Tooltip IDs to see item IDs." },
        { kind = "slider", key = "limit", name = "Spend at most (gold per visit)", min = 1, max = 500, step = 1 },
    },
    Enable = function(f)
        f:On("MERCHANT_SHOW", function()
            if Q.Skip() then return end
            local want = parseList(f:Get("list"))
            if next(want) == nil then return end
            local budget = (tonumber(f:Get("limit")) or 50) * 10000
            local spent, bought = 0, {}
            for i = 1, GetMerchantNumItems() do
                local id = GetMerchantItemID and GetMerchantItemID(i)
                local target = id and want[id]
                if target then
                    local _, _, price, stack, available = GetMerchantItemInfo(i)
                    local need = target - (GetItemCount(id, false) or 0)
                    local maxStack = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(i)) or 20
                    stack = math.max(1, stack or 1)
                    local unit = (price or 0) / stack
                    while need > 0 do
                        local n = math.min(need, maxStack)
                        if available and available >= 0 then n = math.min(n, available) end
                        local cost = math.ceil(unit * n)
                        if n <= 0 or spent + cost > budget or cost > GetMoney() then break end
                        BuyMerchantItem(i, n)
                        spent, need = spent + cost, need - n
                        bought[#bought + 1] = n .. "x " .. (GetMerchantItemLink(i) or ("item " .. id))
                        if available and available >= 0 then available = available - n end
                    end
                end
            end
            if #bought > 0 then Q:Print("Restocked %s for %s.", table.concat(bought, ", "), Q.Coins(spent)) end
        end)
    end,
}

---------------------------------------------------------------------------
-- Ready check: your own buffs
---------------------------------------------------------------------------
-- Flasks and the battle elixirs most often used in Classic-era raids (spell IDs of the buffs).
local ELIXIRS = { 17626, 17627, 17628, 17629, 17538, 11405, 11334, 11390, 11396, 11474, 26276, 17539, 17535, 3593, 11348, 24363, 24361 }
local WELL_FED = 19705

local function buffsOn()
    local ids, names = {}, {}
    for i = 1, 40 do
        local name, spellId
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if a then name, spellId = a.name, a.spellId end
        else
            local n, _, _, _, _, _, _, _, _, id = UnitBuff("player", i)
            name, spellId = n, id
        end
        if not name then break end
        if spellId then ids[spellId] = true end
        names[name] = true
    end
    return ids, names
end

Q:Feature{
    id = "readyCheck", tab = "qol", section = "Errands", name = "Ready check: my buffs",
    desc = "On a ready check, tells you (only you) what you are missing: a food buff, a flask or battle elixir, a weapon enhancement (poison, oil, sharpening stone).",
    defaults = { raidsOnly = true, food = true, elixir = true, weapon = false },
    options = {
        { kind = "check", key = "raidsOnly", name = "Only in raids" },
        { kind = "check", key = "food", name = "Food buff" },
        { kind = "check", key = "elixir", name = "Flask or battle elixir" },
        { kind = "check", key = "weapon", name = "Weapon enhancement" },
    },
    Enable = function(f)
        f:On("READY_CHECK", function()
            if f:Get("raidsOnly") and select(2, IsInInstance()) ~= "raid" then return end
            local ids, names = buffsOn()
            local missing = {}
            if f:Get("food") then
                local fed = GetSpellName(WELL_FED)
                if not (fed and names[fed]) then missing[#missing + 1] = "food buff" end
            end
            if f:Get("elixir") then
                local has = false
                for _, id in ipairs(ELIXIRS) do if ids[id] then has = true break end end
                if not has then missing[#missing + 1] = "flask or battle elixir" end
            end
            if f:Get("weapon") and GetWeaponEnchantInfo then
                local mh = GetWeaponEnchantInfo()
                if not mh then missing[#missing + 1] = "weapon enhancement" end
            end
            if #missing > 0 then
                local text = "Missing: " .. table.concat(missing, ", ") .. "."
                Q:Print(text)
                if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
                    RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo.RAID_WARNING)
                end
            end
        end)
    end,
}
