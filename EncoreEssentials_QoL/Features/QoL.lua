-- Encore-QoL: Quality of life tab. Automation and small time savers; holding Shift skips any automation for
-- that one click. Ideas from Leatrix Plus and Enhance QoL (both All Rights Reserved): own code on the WoW API.
local _, ns = ...
local Q = ns.QoL

local function hidePopup(which) if StaticPopup_Hide then StaticPopup_Hide(which) end end

-- Item, spell and unit tooltips. TooltipDataProcessor on modern clients, OnTooltipSet* scripts on older ones.
-- Hooks can't be removed, so each one asks its feature whether it is still on.
local tooltipHooks = { item = {}, spell = {}, unit = {} }
local hooked = false
local function runHooks(kind, tooltip, data)
    for _, fn in ipairs(tooltipHooks[kind]) do
        local ok, err = pcall(fn, tooltip, data)
        if not ok then geterrorhandler()(err) end
    end
end
function Q.TooltipHook(kind, fn)
    tooltipHooks[kind][#tooltipHooks[kind] + 1] = fn
    if hooked then return end
    hooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data) runHooks("item", tt, data) end)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tt, data) runHooks("spell", tt, data) end)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt, data) runHooks("unit", tt, data) end)
    else
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
            tt:HookScript("OnTooltipSetItem", function(self) runHooks("item", self) end)
            tt:HookScript("OnTooltipSetSpell", function(self) runHooks("spell", self) end)
            tt:HookScript("OnTooltipSetUnit", function(self) runHooks("unit", self) end)
        end
    end
end

local function tooltipItemLink(tt, data)
    if data and data.hyperlink then return data.hyperlink end
    if data and data.id then return "item:" .. data.id end
    if tt.GetItem then return select(2, tt:GetItem()) end
end

---------------------------------------------------------------------------
-- Vendors
---------------------------------------------------------------------------
Q:Feature{
    id = "autoRepair", tab = "qol", section = "Vendors", name = "Auto repair",
    desc = "Repairs all your gear when you open a vendor that can repair, and says what it cost.",
    defaults = { guild = true },
    options = { { kind = "check", key = "guild", name = "Use guild bank money first when allowed" } },
    detect = { { eqol = "autoRepair" }, { leatrix = "AutoRepairGear" } },
    Enable = function(f)
        f:On("MERCHANT_SHOW", function()
            if Q.Skip() or not CanMerchantRepair or not CanMerchantRepair() then return end
            local cost, can = GetRepairAllCost()
            if not can or not cost or cost <= 0 then return end
            if f:Get("guild") and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
                RepairAllItems(true)
                Q:Print("Repaired for %s (guild bank).", Q.Coins(cost))
            elseif GetMoney() >= cost then
                RepairAllItems()
                Q:Print("Repaired for %s.", Q.Coins(cost))
            else
                Q:Print("Not enough money to repair (%s).", Q.Coins(cost))
            end
        end)
    end,
}

local function keepList(text)
    local keep = {}
    for id in tostring(text or ""):gmatch("%d+") do keep[tonumber(id)] = true end
    return keep
end

-- Sell junk is ported from Dejunk's seller (src/services/seller.lua, Dejunk 3.5.1 by moody,
-- https://github.com/moody/Dejunk, MIT licence, see NOTICE.txt), cut down to grey items only.
-- What it keeps from Dejunk: start 0.1 s after the vendor opens; one item per tick at network latency
-- (at least 0.2 s); every sale re-checks the slot still holds the same item, unlocked and not refundable;
-- sold slots are remembered and the bags are scanned again in batches; the run stops when the vendor closes
-- or says it doesn't buy; Safe sell stops after 12 items, all of which the vendor's Buyback tab can return.
local SAFE_SELL_LIMIT = 12
local ERR_DOESNT_BUY = _G.ERR_VENDOR_DOESNT_BUY

local function atMerchant() return (MerchantFrame and MerchantFrame:IsShown()) or false end

local function latency()
    local _, _, home, world = GetNetStats()
    return math.max(math.max(home or 0, world or 0) * 0.001, 0.2)
end

local function itemLocation(bag, slot)
    return ItemLocation and ItemLocation.CreateFromBagAndSlot and ItemLocation:CreateFromBagAndSlot(bag, slot)
end

local function isLocked(bag, slot, info)
    local loc = itemLocation(bag, slot)
    if loc and C_Item and C_Item.IsLocked then
        local ok, locked = pcall(C_Item.IsLocked, loc)
        if ok then return locked end
        return true
    end
    return info and info.isLocked or false
end

local function isRefundable(bag, slot)
    local fn = (C_Container and C_Container.GetContainerItemPurchaseInfo) or _G.GetContainerItemPurchaseInfo
    if not fn then return false end
    local ok, a, b, c, d, e, f, refundSeconds = pcall(fn, bag, slot, false)
    if not ok then return false end
    if type(a) == "table" then refundSeconds = a.refundSeconds end
    return (refundSeconds or 0) > 0
end

local function containerItemID(bag, slot)
    if C_Container and C_Container.GetContainerItemID then return C_Container.GetContainerItemID(bag, slot) end
    local info = Q.GetContainerItemInfo(bag, slot)
    return type(info) == "table" and info.itemID or nil
end

Q:Feature{
    id = "sellJunk", tab = "qol", section = "Vendors", name = "Sell junk",
    desc = "Sells your grey items at any vendor and says how much they brought in. Only ever grey (Poor) items.",
    defaults = { keep = "", safeSell = true },
    options = {
        { kind = "check", key = "safeSell", name = "Safe sell (12 at most)", tip = "Sells at most 12 items per visit, so every one of them can be bought back from the vendor's Buyback tab." },
        { kind = "edit", key = "keep", name = "Never sell (item IDs)", tip = "Item IDs separated by commas, e.g. 6256, 2901. Turn on Tooltip IDs on this tab to see them." },
    },
    detect = { { eqol = "vendorPoorEnable" }, { leatrix = "AutoSellJunk" } },
    Enable = function(f)
        local run = { id = 0, attempted = {}, count = 0, batch = 0, total = 0 }

        -- Junk is grey twice over: the bag slot and the item's own info must both say Poor (quality 0),
        -- it must have a sell price and must not be on the keep list.
        local function junkAt(bag, slot, keep)
            local info = Q.GetContainerItemInfo(bag, slot)
            if type(info) ~= "table" or info.quality ~= 0 or info.hasNoValue or not info.itemID or keep[info.itemID] then return nil end
            local _, _, quality, _, _, _, _, _, _, _, price = Q.GetItemInfo(info.itemID)
            if quality ~= 0 or (price or 0) <= 0 then return nil end
            return { bag = bag, slot = slot, id = info.itemID, price = price * (info.stackCount or 1) }
        end

        local function stop()
            if run.ticker then run.ticker:Cancel() run.ticker = nil end
            run.id = run.id + 1
            if run.count > 0 then
                Q:Print("Sold %d junk item%s for %s.", run.count, run.count == 1 and "" or "s", Q.Coins(run.total))
            end
            run.count, run.batch, run.total, run.attempted = 0, 0, 0, {}
        end

        local function fetch()
            local keep = keepList(f:Get("keep"))
            local list = {}
            for bag = 0, NUM_BAG_SLOTS or 4 do
                for slot = 1, Q.GetContainerNumSlots(bag) or 0 do
                    local item = junkAt(bag, slot, keep)
                    if item and run.attempted[bag .. ":" .. slot] ~= item.id then list[#list + 1] = item end
                end
            end
            -- Cheapest last, so table.remove sells the most valuable first (as Dejunk does).
            table.sort(list, function(a, b) return a.price < b.price end)
            return list, keep
        end

        local sellBatch
        sellBatch = function()
            if not atMerchant() then return stop() end
            local list, keep = fetch()
            if #list == 0 then return stop() end
            run.batch = 0
            run.ticker = C_Timer.NewTicker(latency(), function()
                if not atMerchant() or (f:Get("safeSell") and run.count >= SAFE_SELL_LIMIT) then return stop() end
                local item = table.remove(list)
                if not item then
                    if run.ticker then run.ticker:Cancel() run.ticker = nil end
                    if run.batch == 0 then return stop() end
                    -- Let the bags settle, then look again for anything left.
                    local id = run.id
                    C_Timer.After(0.4, function() if run.id == id and f.active then sellBatch() end end)
                    return
                end
                -- Still the same grey item in that slot, not locked, not refundable: only then sell.
                local now = junkAt(item.bag, item.slot, keep)
                if now and now.id == item.id and containerItemID(item.bag, item.slot) == item.id
                    and not isLocked(item.bag, item.slot) and not isRefundable(item.bag, item.slot) then
                    Q.UseContainerItem(item.bag, item.slot)
                    run.attempted[item.bag .. ":" .. item.slot] = item.id
                    run.count, run.batch, run.total = run.count + 1, run.batch + 1, run.total + now.price
                end
            end)
        end

        f:On("MERCHANT_SHOW", function()
            stop()
            if Q.Skip() then return end
            local id = run.id
            C_Timer.After(0.1, function() if run.id == id and f.active then sellBatch() end end)
        end)
        f:On("MERCHANT_CLOSED", stop)
        f:On("UI_ERROR_MESSAGE", function(_, _, msg)
            if ERR_DOESNT_BUY and msg == ERR_DOESNT_BUY then stop() end
        end)
    end,
}

---------------------------------------------------------------------------
-- Quests and NPCs
---------------------------------------------------------------------------
Q:Feature{
    id = "autoQuests", tab = "qol", section = "Quests and NPCs", name = "Auto quests",
    desc = "Accepts quests and turns them in. Skips repeatable quests and any reward you have to choose.",
    defaults = { accept = true, turnIn = true },
    options = {
        { kind = "check", key = "accept", name = "Accept quests" },
        { kind = "check", key = "turnIn", name = "Turn in finished quests" },
    },
    detect = { { eqol = "autoChooseQuest" }, { leatrix = "AutomateQuests" } },
    Enable = function(f)
        f:On("QUEST_DETAIL", function()
            if Q.Skip() or not f:Get("accept") then return end
            if QuestGetAutoAccept and QuestGetAutoAccept() then
                if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
            else
                AcceptQuest()
            end
        end)
        f:On("QUEST_ACCEPT_CONFIRM", function()
            if Q.Skip() or not f:Get("accept") then return end
            ConfirmAcceptQuest()
            hidePopup("QUEST_ACCEPT")
        end)
        f:On("QUEST_PROGRESS", function()
            if Q.Skip() or not f:Get("turnIn") then return end
            if IsQuestCompletable() then CompleteQuest() end
        end)
        f:On("QUEST_COMPLETE", function()
            if Q.Skip() or not f:Get("turnIn") then return end
            local choices = GetNumQuestChoices()
            if choices <= 1 then GetQuestReward(choices) end
        end)
        f:On("QUEST_GREETING", function()
            if Q.Skip() then return end
            if f:Get("turnIn") then
                for i = 1, GetNumActiveQuests() do
                    local _, complete = GetActiveTitle(i)
                    if complete then SelectActiveQuest(i) return end
                end
            end
            if f:Get("accept") then
                for i = 1, GetNumAvailableQuests() do
                    local trivial, frequency, repeatable = GetAvailableQuestInfo(i)
                    if not repeatable and (frequency == nil or frequency == 0 or frequency == 1) then SelectAvailableQuest(i) return end
                end
            end
        end)
        f:On("GOSSIP_SHOW", function()
            if Q.Skip() or not C_GossipInfo then return end
            if f:Get("turnIn") then
                for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
                    if q.isComplete then C_GossipInfo.SelectActiveQuest(q.questID) return end
                end
            end
            if f:Get("accept") then
                for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
                    if not q.repeatable and not q.isTrivial then C_GossipInfo.SelectAvailableQuest(q.questID) return end
                end
            end
        end)
    end,
}

Q:Feature{
    id = "autoGossip", tab = "qol", section = "Quests and NPCs", name = "Auto gossip",
    desc = "Picks the only talk option when an NPC has just one (flight master, banker, innkeeper).",
    detect = { { eqol = "autoChooseGossip" }, { leatrix = "AutomateGossip" } },
    Enable = function(f)
        f:On("GOSSIP_SHOW", function()
            if Q.Skip() or not C_GossipInfo then return end
            if #(C_GossipInfo.GetActiveQuests() or {}) > 0 or #(C_GossipInfo.GetAvailableQuests() or {}) > 0 then return end
            local options = C_GossipInfo.GetOptions() or {}
            if #options == 1 and options[1].gossipOptionID then C_GossipInfo.SelectOption(options[1].gossipOptionID) end
        end)
    end,
}

Q:Feature{
    id = "autoDismount", tab = "qol", section = "Quests and NPCs", name = "Auto dismount",
    desc = "Gets you off your mount when a spell can't be cast mounted, and when you talk to a flight master.",
    detect = { { leatrix = "AutoDismount" } },
    Enable = function(f)
        local errors = {}
        for _, k in ipairs({ "SPELL_FAILED_NOT_MOUNTED", "ERR_NOT_WHILE_MOUNTED", "ERR_ATTACK_MOUNTED", "ERR_TAXIPLAYERALREADYMOUNTED", "SPELL_FAILED_NO_MOUNTS_ALLOWED" }) do
            if _G[k] then errors[_G[k]] = true end
        end
        f:On("UI_ERROR_MESSAGE", function(_, _, message)
            if errors[message] and IsMounted() and not UnitOnTaxi("player") then Dismount() end
        end)
        f:On("TAXIMAP_OPENED", function()
            if IsMounted() then Dismount() end
        end)
    end,
}

---------------------------------------------------------------------------
-- Loot and bags
---------------------------------------------------------------------------
Q:Feature{
    id = "fastLoot", tab = "qol", section = "Loot and bags", name = "Faster auto loot",
    desc = "Takes everything in the loot window at once when auto loot is on.",
    detect = { { eqol = "autoQuickLoot" }, { leatrix = "FasterLooting" } },
    Enable = function(f)
        local last = 0
        f:On("LOOT_READY", function()
            if GetTime() - last < 0.3 then return end
            local auto = C_CVar.GetCVarBool("autoLootDefault")
            if auto == IsModifiedClick("AUTOLOOTTOGGLE") then return end
            last = GetTime()
            for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
        end)
    end,
}

Q:Feature{
    id = "easyDelete", tab = "qol", section = "Loot and bags", name = "Easy delete",
    desc = "Fills in DELETE for you when you throw away a good item. You still press Okay.",
    detect = { { eqol = "deleteItemFillDialog" } },
    Enable = function(f)
        f:Hook("StaticPopup_Show", function(which)
            if which ~= "DELETE_GOOD_ITEM" and which ~= "DELETE_GOOD_QUEST_ITEM" then return end
            local popup = StaticPopup_FindVisible and StaticPopup_FindVisible(which)
            local box = popup and (popup.editBox or popup.EditBox or (popup.GetEditBox and popup:GetEditBox()))
            if box then box:SetText(DELETE_ITEM_CONFIRM_STRING or "DELETE") end
        end)
    end,
}

Q:Feature{
    id = "freeSlots", tab = "qol", section = "Loot and bags", name = "Free bag slots",
    desc = "Shows how many bag slots are free on the backpack button.",
    Enable = function(f)
        if C_CVar.GetCVar("displayFreeBagSlots") ~= nil then
            Q.SetCVar("displayFreeBagSlots", "1")
            f.usedCVar = true
            return
        end
        local button = _G.MainMenuBarBackpackButton
        if not button then return end
        f.text = f.text or button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        f.text:SetPoint("BOTTOMRIGHT", -2, 2)
        f.text:Show()
        local function update()
            local free = 0
            for bag = 0, NUM_BAG_SLOTS or 4 do
                local n, family = Q.GetContainerNumFreeSlots(bag)
                if family == 0 then free = free + (n or 0) end
            end
            f.text:SetText(free)
        end
        f:On("BAG_UPDATE_DELAYED", update)
        update()
    end,
    Disable = function(f)
        if f.usedCVar then Q.RestoreCVar("displayFreeBagSlots") end
        if f.text then f.text:Hide() end
    end,
}

Q:Feature{
    id = "vendorPrice", tab = "qol", section = "Loot and bags", name = "Vendor price in tooltip",
    desc = "Adds what an item sells for to its tooltip, for the whole stack too.",
    detect = { { leatrix = "ShowVendorPrice" } },
    Enable = function(f)
        if f.hooked then return end
        f.hooked = true
        Q.TooltipHook("item", function(tt, data)
            if not f.active or tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
            local money = _G[tt:GetName() .. "MoneyFrame1"]
            if money and money:IsShown() then return end -- the game already shows it
            local link = tooltipItemLink(tt, data)
            if not link then return end
            local price = select(11, Q.GetItemInfo(link))
            if not price or price <= 0 then return end
            local owner = tt:GetOwner()
            local count = owner and (owner.count or (owner.Count and tonumber(owner.Count:GetText()))) or 1
            count = tonumber(count) or 1
            if count > 1 then
                tt:AddDoubleLine("Sells for", Q.Coins(price) .. "   (" .. count .. ": " .. Q.Coins(price * count) .. ")", 1, 0.82, 0, 1, 1, 1)
            else
                tt:AddDoubleLine("Sells for", Q.Coins(price), 1, 0.82, 0, 1, 1, 1)
            end
            tt:Show()
        end)
    end,
}

Q:Feature{
    id = "tooltipIDs", tab = "qol", section = "Loot and bags", name = "Tooltip IDs",
    desc = "Item, spell and NPC IDs at the bottom of tooltips.",
    detect = { { eqol = function(p) return p.TooltipShowItemID or p.TooltipShowSpellID or p.TooltipShowNPCID end } },
    Enable = function(f)
        if f.hooked then return end
        f.hooked = true
        local function add(tt, label, id)
            if not f.active or not id then return end
            tt:AddDoubleLine(label, tostring(id), 0.64, 0.57, 0.47, 1, 1, 1)
            tt:Show()
        end
        Q.TooltipHook("item", function(tt, data)
            local link = tooltipItemLink(tt, data)
            add(tt, "Item ID", (data and data.id) or (link and tonumber(link:match("item:(%d+)"))))
        end)
        Q.TooltipHook("spell", function(tt, data)
            add(tt, "Spell ID", (data and data.id) or (tt.GetSpell and select(2, tt:GetSpell())))
        end)
        Q.TooltipHook("unit", function(tt, data)
            local guid = data and data.guid
            if not guid and tt.GetUnit then
                local _, unit = tt:GetUnit()
                guid = unit and UnitGUID(unit)
            end
            local kind, _, _, _, _, npc = strsplit("-", guid or "")
            if kind == "Creature" or kind == "Vehicle" then add(tt, "NPC ID", npc) end
        end)
    end,
}

---------------------------------------------------------------------------
-- Social
---------------------------------------------------------------------------
local function isFriendOrGuild(name, guid)
    if guid and C_FriendList and C_FriendList.IsFriend and C_FriendList.IsFriend(guid) then return true end
    if guid and IsGuildMember and IsGuildMember(guid) then return true end
    if C_BattleNet and C_BattleNet.GetAccountInfoByGUID and guid and C_BattleNet.GetAccountInfoByGUID(guid) then return true end
    if name and C_FriendList and C_FriendList.GetFriendInfo and C_FriendList.GetFriendInfo(name) then return true end
    return false
end

Q:Feature{
    id = "summonsRes", tab = "qol", section = "Social", name = "Accept summons and resurrections",
    desc = "Accepts a warlock summon or a resurrection while you're out of combat.",
    defaults = { summon = true, res = true },
    options = {
        { kind = "check", key = "summon", name = "Accept summons" },
        { kind = "check", key = "res", name = "Accept resurrections" },
    },
    detect = { { eqol = function(p) return p.autoAcceptSummon or p.autoAcceptResurrection end },
        { leatrix = "AutoAcceptSummon" }, { leatrix = "AutoAcceptRes" } },
    Enable = function(f)
        f:On("CONFIRM_SUMMON", function()
            if Q.Skip() or not f:Get("summon") or UnitAffectingCombat("player") then return end
            C_Timer.After(1, function()
                if not f.active or UnitAffectingCombat("player") then return end
                if C_SummonInfo and C_SummonInfo.ConfirmSummon then C_SummonInfo.ConfirmSummon() elseif ConfirmSummon then ConfirmSummon() end
                hidePopup("CONFIRM_SUMMON")
            end)
        end)
        f:On("RESURRECT_REQUEST", function()
            if Q.Skip() or not f:Get("res") or UnitAffectingCombat("player") then return end
            AcceptResurrect()
            hidePopup("RESURRECT")
            hidePopup("RESURRECT_NO_SICKNESS")
            hidePopup("RESURRECT_NO_TIMER")
        end)
    end,
}

Q:Feature{
    id = "invites", tab = "qol", section = "Social", name = "Invites",
    desc = "Accepts party invites from friends and guild members, and invites anyone who whispers you a keyword.",
    defaults = { accept = true, keyword = "inv" },
    options = {
        { kind = "check", key = "accept", name = "Accept invites from friends and guild" },
        { kind = "edit", key = "keyword", name = "Whisper keyword (empty = off)" },
    },
    detect = { { eqol = "autoAcceptGroupInvite" }, { leatrix = "AcceptPartyFriends" }, { leatrix = "InviteFromWhisper" } },
    Enable = function(f)
        f:On("PARTY_INVITE_REQUEST", function(_, name, _, _, _, _, _, guid)
            if Q.Skip() or not f:Get("accept") then return end
            if isFriendOrGuild(name, guid) then
                AcceptGroup()
                hidePopup("PARTY_INVITE")
            end
        end)
        f:On("CHAT_MSG_WHISPER", function(_, text, sender)
            if _G.issecretvalue and (_G.issecretvalue(text) or _G.issecretvalue(sender)) then return end -- secret chat values can't be read
            local key = strtrim(tostring(f:Get("keyword") or "")):lower()
            if key == "" or strtrim(text or ""):lower() ~= key then return end
            if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then return end
            if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(sender) elseif InviteUnit then InviteUnit(sender) end
        end)
    end,
}

Q:Feature{
    id = "blocks", tab = "qol", section = "Social", name = "Blocks",
    desc = "Declines duels, guild charters and party invites from people who aren't friends or guild members.",
    defaults = { duels = true, charters = true, strangers = false },
    options = {
        { kind = "check", key = "duels", name = "Block duels" },
        { kind = "check", key = "charters", name = "Block guild charters" },
        { kind = "check", key = "strangers", name = "Block party invites from strangers" },
    },
    detect = { { eqol = function(p) return p.blockDuelRequests or p.blockPartyInvites end },
        { leatrix = "NoDuelRequests" }, { leatrix = "NoPartyInvites" } },
    Enable = function(f)
        f:On("DUEL_REQUESTED", function()
            if not f:Get("duels") then return end
            CancelDuel()
            hidePopup("DUEL_REQUESTED")
        end)
        f:On("PETITION_SHOW", function()
            if not f:Get("charters") then return end
            ClosePetition()
        end)
        f:On("PARTY_INVITE_REQUEST", function(_, name, _, _, _, _, _, guid)
            if not f:Get("strangers") or isFriendOrGuild(name, guid) then return end
            DeclineGroup()
            hidePopup("PARTY_INVITE")
        end)
    end,
}

---------------------------------------------------------------------------
-- Reading and travel
---------------------------------------------------------------------------
local READING_FONTS = { "QuestFont", "QuestFontNormalSmall", "MailTextFontNormal", "ItemTextFontNormal", "InvoiceTextFontNormal" }

Q:Feature{
    id = "readingText", tab = "qol", section = "Reading and travel", name = "Bigger reading text",
    desc = "Larger font for quest, mail and book text.",
    defaults = { size = 15 },
    options = { { kind = "slider", key = "size", name = "Text size", min = 11, max = 22, step = 1 } },
    Enable = function(f)
        f.old = f.old or {}
        for _, name in ipairs(READING_FONTS) do
            local font = _G[name]
            if font and font.GetFont then
                local path, size, flags = font:GetFont()
                if not f.old[name] then f.old[name] = { path, size, flags } end
                font:SetFont(path, f:Get("size"), flags)
            end
        end
    end,
    OnOption = function(f) f:Enable() end,
    Disable = function(f)
        for name, o in pairs(f.old or {}) do
            local font = _G[name]
            if font and o[1] then font:SetFont(o[1], o[2], o[3]) end
        end
    end,
}

Q:Feature{
    id = "flightTimes", tab = "qol", section = "Reading and travel", name = "Flight times",
    desc = "A bar with the time left on a flight path. Each route is timed the first time you fly it.",
    Enable = function(f)
        local times = f:Saved()
        if type(times.routes) ~= "table" then times.routes = {} end
        local route, started
        local bar = f.bar
        if not bar then
            bar = CreateFrame("StatusBar", nil, UIParent)
            bar:SetSize(220, 16)
            bar:SetPoint("TOP", 0, -120)
            bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            bar:SetStatusBarColor(0.92, 0.58, 0.22)
            local bg = bar:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0.7)
            Q.W.Border(bar, Q.W.COPPER)
            bar.text = Q.W.Text(bar, "GameFontHighlightSmall", "")
            bar.text:SetPoint("CENTER")
            bar:Hide()
            f.bar = bar
        end
        f:Hook("TakeTaxiNode", function(index)
            local from
            for i = 1, NumTaxiNodes() do
                if TaxiNodeGetType(i) == "CURRENT" then from = TaxiNodeName(i) end
            end
            route = (from or "?") .. " > " .. (TaxiNodeName(index) or "?")
            started = nil
        end)
        f:On("PLAYER_CONTROL_LOST", function()
            if route then
                C_Timer.After(0.5, function()
                    if UnitOnTaxi("player") then started = GetTime() end
                end)
            end
        end)
        f:On("PLAYER_CONTROL_GAINED", function()
            if route and started then times.routes[route] = math.floor(GetTime() - started + 0.5) end
            route, started = nil, nil
            bar:Hide()
        end)
        f:Ticker(0.5, function()
            if not (route and started and UnitOnTaxi("player")) then bar:Hide() return end
            local total = times.routes[route]
            local elapsed = GetTime() - started
            if total and total > 0 then
                local left = math.max(0, total - elapsed)
                bar:SetMinMaxValues(0, total)
                bar:SetValue(elapsed)
                bar.text:SetFormattedText("%d:%02d left", left / 60, left % 60)
            else
                bar:SetMinMaxValues(0, 1)
                bar:SetValue(1)
                bar.text:SetFormattedText("%d:%02d (timing this route)", elapsed / 60, elapsed % 60)
            end
            bar:Show()
        end)
    end,
    Disable = function(f) if f.bar then f.bar:Hide() end end,
}
