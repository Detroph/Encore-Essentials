-- Encore Essentials: wishlist. Alt-click an item in Encore-DB to wish for it (again to remove it). Encore then tells
-- you when it comes up for a loot roll, is in a corpse you loot, is linked in chat, or Encore-Stonks sees it at the
-- auction house, and its tooltip says it is on the list. Saved in EncoreEssentialsDB.wishlist (account-wide, kept
-- by /encore reset).
local _, ns = ...
local Encore = ns.Encore
local L = ns.L

local function list()
    local db = Encore.db
    if not db then return {} end
    if type(db.wishlist) ~= "table" then db.wishlist = {} end
    return db.wishlist
end

function Encore:IsWished(id) return id ~= nil and list()[tonumber(id) or id] ~= nil end
function Encore:WishCount()
    local n = 0
    for _ in pairs(list()) do n = n + 1 end
    return n
end
function Encore:Wishlist() return list() end

local function itemName(id)
    local get = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    local name, link
    if get then name, link = get(id) end -- not `get and get(id)`: that keeps only the first value
    return link or name or ("item " .. id)
end

function Encore:ToggleWish(id)
    id = tonumber(id)
    if not id then return end
    local t = list()
    if t[id] then
        t[id] = nil
        self:Print(L.WISH_REMOVED, itemName(id))
    else
        t[id] = time()
        self:Print(L.WISH_ADDED, itemName(id))
    end
    if self.OnWishlistChanged then self:OnWishlistChanged(id) end
end

-- Opens Encore-DB on its Wishlist tab (key binding, /encore wishlist).
function Encore:ShowWishlist()
    local db = self:LoadModule("DB", "EncoreEssentials_DB")
    if db and db.ShowTab then db:ShowTab("wishlist") elseif db then db:Toggle() end
end

local function alertsOn() return not (Encore.db and Encore.db.settings.wishAlerts == false) end

-- One alert per item per place a minute at most (chat links and AH scans repeat).
local lastAlert = {}
local function alert(kind, id, text, loud)
    if not alertsOn() then return end
    local key = kind .. id
    if lastAlert[key] and GetTime() - lastAlert[key] < 60 then return end
    lastAlert[key] = GetTime()
    Encore:Print(text)
    if loud then
        if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
            RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo.RAID_WARNING)
        end
        PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
    end
end

local function idFromLink(link) return link and tonumber(link:match("item:(%d+)")) end

local f = CreateFrame("Frame")
local CHAT = { "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_INSTANCE_CHAT" }

f:SetScript("OnEvent", function(_, event, a1, a2)
    local ok, err = pcall(function()
        if event == "START_LOOT_ROLL" then
            local link = GetLootRollItemLink and GetLootRollItemLink(a1)
            local id = idFromLink(link)
            if Encore:IsWished(id) then alert("roll", id, L.WISH_ROLL:format(link), true) end
        elseif event == "LOOT_OPENED" then
            for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
                local link = GetLootSlotLink(slot)
                local id = idFromLink(link)
                if Encore:IsWished(id) then alert("loot", id, L.WISH_LOOT:format(link), true) end
            end
        elseif event == "PLAYER_LOGIN" then
            for _, e in ipairs(CHAT) do f:RegisterEvent(e) end
            local stonks = Encore.modules.Stonks
            if stonks and type(stonks.Record) == "function" then
                hooksecurefunc(stonks, "Record", function(_, key, price)
                    local id = tonumber(key)
                    if Encore:IsWished(id) and price then
                        local coins = Encore.UI.Coins(price)
                        alert("ah", id, L.WISH_AH:format(itemName(id), coins))
                    end
                end)
            end
        elseif type(a1) == "string" and a1:find("|Hitem:", 1, true) then
            if next(list()) == nil then return end
            for id in a1:gmatch("|Hitem:(%d+)") do
                id = tonumber(id)
                if Encore:IsWished(id) then
                    local who = Ambiguate and Ambiguate(a2 or "", "short") or a2
                    alert("chat", id, L.WISH_CHAT:format(who or "?", itemName(id)))
                end
            end
        end
    end)
    if not ok then geterrorhandler()(err) end
end)
f:RegisterEvent("START_LOOT_ROLL")
f:RegisterEvent("LOOT_OPENED")
f:RegisterEvent("PLAYER_LOGIN")

-- Tooltip line on wished items, everywhere.
local function tipLine(tooltip, id)
    if not Encore:IsWished(id) or tooltip.encoreWishID == id then return end
    tooltip.encoreWishID = id
    tooltip:AddLine("|cffeb9339Encore|r " .. L.WISH_TIP, 1, 0.82, 0)
    if tooltip:IsShown() then tooltip:Show() end
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        local id = data and data.id
        if not id and tooltip.GetItem then id = idFromLink(select(2, tooltip:GetItem())) end
        pcall(tipLine, tooltip, id)
    end)
else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt and tt.HookScript then
            tt:HookScript("OnTooltipSetItem", function(self) pcall(tipLine, self, idFromLink(select(2, self:GetItem()))) end)
        end
    end
end
for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tt and tt.HookScript then
        local clear = function(self) self.encoreWishID = nil end
        tt:HookScript("OnTooltipCleared", clear)
        tt:HookScript("OnHide", clear)
    end
end
