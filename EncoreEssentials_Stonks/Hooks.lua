-- Encore-Stonks hooks: open the graph panel beside the auction house and follow the item selected there.
-- Sources: the game's auction house (WoW Forever uses the modern one, Blizzard_AuctionHouseUI: Browse results,
-- the buy screens and the Sell tab; the legacy AuctionFrame is handled too) and Auctionator (Shopping results,
-- Selling items, shopping list searches).
local _, ns = ...
local Stonks = ns.Stonks
local U = ns.UI

-- Errors in these hooks are reported once each in chat (many players have Lua errors hidden).
local reported = {}
local function safe(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok and not reported[err] then
            reported[err] = true
            print("|cffd9a066Encore-Stonks|r error: " .. tostring(err))
        end
    end
end

local function docking() return Stonks:Settings().dockAH ~= false end
local function active() return docking() or Stonks:PanelShown() end

local function ahShown()
    local f = _G.AuctionFrame or _G.AuctionHouseFrame
    return f and f:IsShown()
end

-- Several sources can fire for one click; show each item only once per change.
local trace = false
local seen = {}
local function note(what, detail)
    seen[what] = (seen[what] or 0) + 1
    if trace then print("|cffd9a066Encore-Stonks|r trace: " .. what .. (detail and (" " .. tostring(detail)) or "")) end
end

local function follow(item)
    note("follow", type(item) == "table" and "(table)" or item)
    if not active() then return end
    local key = U.keyFrom(item)
    if not key or key == Stonks:PanelKey() then return end
    Stonks:ShowItem(key)
end

---------------------------------------------------------------------------
-- Auction house open and close
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
-- Registering an event the client doesn't have is an error (NEW_AUCTION_UPDATE exists only with the legacy
-- auction house, not on WoW Forever), so each one is registered on its own and missing ones are skipped.
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "NEW_AUCTION_UPDATE", "PLAYER_LOGIN", "ADDON_LOADED" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", safe(function(_, event, arg1)
    if event ~= "ADDON_LOADED" then note(event) end
    if event == "AUCTION_HOUSE_SHOW" then
        if not docking() then return end
        -- Wait a frame so the auction house window is shown and can be anchored to
        Stonks:HookAuctionHouse()
        C_Timer.After(0, safe(function()
            Stonks:ShowPanel()
            Stonks:DockPanel()
        end))
    elseif event == "AUCTION_HOUSE_CLOSED" then
        C_Timer.After(0, safe(function()
            if not Stonks:PanelShown() then return end
            local browser = _G.EncoreStonksFrame
            if browser and browser:IsShown() then Stonks:DockPanel() else Stonks:HidePanel() end
        end))
    elseif event == "NEW_AUCTION_UPDATE" then
        -- An item was put into the sell slot (Auctions tab)
        if GetAuctionSellItemInfo then
            local link = select(10, GetAuctionSellItemInfo())
            if link then follow(link) end
        end
    elseif event == "PLAYER_LOGIN" then
        Stonks:HookAuctionator()
        Stonks:HookAuctionHouse()
    elseif event == "ADDON_LOADED" then
        if arg1 == "Blizzard_AuctionHouseUI" then Stonks:HookAuctionHouse() end
        if arg1 == "Auctionator" then Stonks:HookAuctionator() end
    end
end))

---------------------------------------------------------------------------
-- Game auction house: selecting a row in Browse, Bids or Auctions
---------------------------------------------------------------------------
if type(SetSelectedAuctionItem) == "function" and GetAuctionItemLink then
    hooksecurefunc("SetSelectedAuctionItem", safe(function(listType, index)
        if not index or index == 0 then return end
        follow(GetAuctionItemLink(listType, index))
    end))
end

---------------------------------------------------------------------------
-- Modern auction house (Blizzard_AuctionHouseUI, loads when the auction house first opens)
---------------------------------------------------------------------------
local function itemFromLocation(location)
    if type(location) ~= "table" or not (location.IsValid and location:IsValid()) then return nil end
    return C_Item.GetItemLink and C_Item.GetItemLink(location) or (C_Item.GetItemID and C_Item.GetItemID(location))
end

local ahHooked
function Stonks:HookAuctionHouse()
    local ah = _G.AuctionHouseFrame
    if ahHooked or type(ah) ~= "table" then return end
    ahHooked = true
    -- Browse: clicking a result (opens the item or commodity buy screen)
    if ah.SelectBrowseResult then
        hooksecurefunc(ah, "SelectBrowseResult", safe(function(_, result)
            if type(result) == "table" then follow(result.itemKey) end
        end))
    end
    -- Buy screens opened any other way (Auctionator, links, favourites)
    if ah.ItemBuyFrame and ah.ItemBuyFrame.SetItemKey then
        hooksecurefunc(ah.ItemBuyFrame, "SetItemKey", safe(function(_, itemKey) follow(itemKey) end))
    end
    if ah.CommoditiesBuyFrame and ah.CommoditiesBuyFrame.SetItemIDAndPrice then
        hooksecurefunc(ah.CommoditiesBuyFrame, "SetItemIDAndPrice", safe(function(_, itemID) follow(itemID) end))
    end
    -- Sell tab: an item put into the sell slot
    for _, sell in ipairs({ ah.ItemSellFrame, ah.CommoditiesSellFrame }) do
        if sell and sell.SetItem then
            hooksecurefunc(sell, "SetItem", safe(function(_, location)
                local item = itemFromLocation(location)
                if item then follow(item) end
            end))
        end
    end
    -- Auctions tab: selecting one of your own auctions
    local auctions = ah.AuctionsFrame
    if auctions and auctions.SelectAuction then
        hooksecurefunc(auctions, "SelectAuction", safe(function(_, info)
            if type(info) == "table" then follow(info.itemLink or info.itemKey) end
        end))
    end
end

---------------------------------------------------------------------------
-- Auctionator: Shopping and Selling tabs
---------------------------------------------------------------------------
local function listName(arg)
    if type(arg) == "string" then return arg end
    if type(arg) == "table" then
        if type(arg.GetName) == "function" then
            local ok, name = pcall(arg.GetName, arg)
            if ok and type(name) == "string" then return name end
        end
        if type(arg.name) == "string" then return arg.name end
    end
    return nil
end

local auctionatorHooked
function Stonks:HookAuctionator()
    if auctionatorHooked then return end
    local A = _G.Auctionator
    if not (A and A.EventBus and A.EventBus.Register) then return end

    local itemEvents, listEvents = {}, {}
    local function add(t, group, name)
        local e = group and group.Events and group.Events[name]
        if e then t[e] = true end
    end
    -- Modern AH Auctionator (WoW Forever): ShowItemBuy / ShowCommodityBuy (rowData with itemKey),
    -- SellSearchStart (itemKey, itemLink), BagItemClicked (info with itemLink). Legacy AH: ShowForShopping, AuctionFocussed.
    add(itemEvents, A.Selling, "BagItemClicked")
    add(itemEvents, A.Selling, "SellSearchStart")
    add(itemEvents, A.Buying, "ShowItemBuy")
    add(itemEvents, A.Buying, "ShowCommodityBuy")
    add(itemEvents, A.Buying, "ShowForShopping")
    add(itemEvents, A.Buying, "AuctionFocussed")
    if A.Shopping and A.Shopping.Tab then add(listEvents, A.Shopping.Tab, "ListSearchRequested") end

    local all = {}
    for e in pairs(itemEvents) do all[#all + 1] = e end
    for e in pairs(listEvents) do all[#all + 1] = e end
    if #all == 0 then return end

    local listener = {}
    listener.ReceiveEvent = safe(function(_, eventName, arg, arg2)
        if itemEvents[eventName] then
            -- Auctionator passes item info tables ({ itemLink, itemKey, ... }), links or item keys
            if type(arg) == "table" and arg.itemKey == nil and arg.itemLink == nil and arg.itemID == nil and arg[1] then
                arg = arg[1]
            end
            if U.keyFrom(arg) == nil and arg2 ~= nil then arg = arg2 end
            follow(arg)
        elseif listEvents[eventName] then
            if not active() then return end
            local name = listName(arg)
            if name then Stonks:ShowList(name) end
        end
    end)
    local ok = pcall(A.EventBus.Register, A.EventBus, listener, all)
    auctionatorHooked = ok
end

-- Auctionator may load after us
if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Auctionator") then
    C_Timer.After(0, safe(function() Stonks:HookAuctionator() end))
end

-- The AH might already be open when the module loads (loaded from the hub while at the auctioneer)
if ahShown() and docking() then
    C_Timer.After(0, safe(function()
        Stonks:HookAuctionHouse()
        Stonks:ShowPanel()
        Stonks:DockPanel()
    end))
end

---------------------------------------------------------------------------
-- Item tooltips (bags, auction house, chat links, everywhere): the 3, 7 and 14-day averages with the last
-- price's % against each. Only items with prices; stats are cached until new prices arrive.
---------------------------------------------------------------------------
local tipCache = {}
hooksecurefunc(Stonks, "OnData", function() wipe(tipCache) end)
if Stonks.SetKeepDays then hooksecurefunc(Stonks, "SetKeepDays", function() wipe(tipCache) end) end

local function tipStats(key)
    local st = tipCache[key]
    if st == nil then
        st = Stonks:ItemStats(key) or false
        tipCache[key] = st
    end
    return st or nil
end

local function addTooltipLines(tooltip, itemID)
    if Stonks:Settings().tooltip == false or not itemID then return end
    if tooltip.encoreStonksID == itemID then return end -- already added for this item (tooltips refresh often)
    local st = tipStats(tostring(itemID))
    if not st or not (st.avg3 or st.avg7 or st.avg14) then return end
    tooltip.encoreStonksID = itemID
    local function line(label, avg)
        if not avg then return end
        local pct = st.last and (st.last / avg - 1) * 100 or nil
        tooltip:AddDoubleLine("|cffeb9339Stonks|r " .. label, U.coinShort(avg) .. "  " .. U.pctColored(pct), 0.85, 0.75, 0.6, 1, 1, 1)
    end
    line("3-day avg", st.avg3)
    line("7-day avg", st.avg7)
    line("14-day avg", st.avg14)
    if tooltip:IsShown() then tooltip:Show() end -- resize to the new lines
end

local function clearMark(tooltip) tooltip.encoreStonksID = nil end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, safe(function(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        local id = data and data.id
        if not id and tooltip.GetItem then
            local _, link = tooltip:GetItem()
            id = link and tonumber(link:match("item:(%d+)"))
        end
        addTooltipLines(tooltip, id)
    end))
else
    local function onSetItem(tooltip)
        local _, link = tooltip:GetItem()
        addTooltipLines(tooltip, link and tonumber(link:match("item:(%d+)")))
    end
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt and tt.HookScript then pcall(tt.HookScript, tt, "OnTooltipSetItem", safe(onSetItem)) end
    end
end
for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tt and tt.HookScript then tt:HookScript("OnTooltipCleared", clearMark); tt:HookScript("OnHide", clearMark) end
end

---------------------------------------------------------------------------
-- /stonks debug | trace | show: what the hooks see, for testing in game
---------------------------------------------------------------------------
local function yes(v) return v and "|cff66ff66yes|r" or "|cffff6666no|r" end
local function report()
    local P = "|cffd9a066Encore-Stonks|r "
    print(P .. "debug, files: Panel " .. yes(Stonks.ShowPanel) .. ", Browser " .. yes(Stonks.ToggleWindow)
        .. ", Hooks " .. yes(Stonks.HookAuctionHouse) .. ", UI " .. yes(U and U.CreateWindow))
    local ah = _G.AuctionHouseFrame
    print(P .. "AuctionHouseFrame " .. yes(ah) .. (ah and (", shown " .. yes(ah:IsShown())) or "")
        .. ", AuctionFrame " .. yes(_G.AuctionFrame) .. ", AH hooks " .. yes(ahHooked)
        .. ", Auctionator hooks " .. yes(auctionatorHooked))
    print(P .. "dock beside AH " .. yes(docking()) .. ", recording " .. yes(Stonks:IsRecording()))
    local panel = _G.EncoreStonksPanel
    if panel then
        print(P .. ("panel shown %s, docked %s, at %s,%s, size %dx%d, strata %s, alpha %.2f, scale %.2f"):format(
            yes(panel:IsShown()), yes(panel.docked), tostring(panel:GetLeft() and math.floor(panel:GetLeft())),
            tostring(panel:GetTop() and math.floor(panel:GetTop())), panel:GetWidth(), panel:GetHeight(),
            tostring(panel:GetFrameStrata()), panel:GetAlpha() or 0, panel:GetEffectiveScale() or 0))
    else
        print(P .. "panel not created yet")
    end
    local list = {}
    for k, v in pairs(seen) do list[#list + 1] = k .. "=" .. v end
    table.sort(list)
    print(P .. "seen: " .. (#list > 0 and table.concat(list, ", ") or "nothing"))
end

SLASH_ENCORESTONKS1 = "/stonks"
SlashCmdList.ENCORESTONKS = function(input)
    local cmd = (input or ""):lower():match("^%s*(%S*)")
    if cmd == "trace" then
        trace = not trace
        print("|cffd9a066Encore-Stonks|r trace " .. (trace and "on" or "off"))
    elseif cmd == "show" then
        local ok, err = pcall(function() Stonks:HookAuctionHouse(); Stonks:ShowPanel(); Stonks:DockPanel() end)
        if not ok then print("|cffd9a066Encore-Stonks|r error: " .. tostring(err)) end
        report()
    elseif cmd == "debug" then
        report()
    else
        Stonks:Toggle()
    end
end
