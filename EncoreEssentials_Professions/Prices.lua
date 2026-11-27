-- Encore-Professions: what a reagent costs. Vendor reagents at the vendor's price (the client's buy prices, and
-- every price you see at a merchant); everything else at the last Auctionator scan, checked against the 7-day
-- average from Encore-Stonks: a scan more than half off that average uses the average instead.
local _, ns = ...
local P = ns.P
local Encore = _G.EncoreEssentials

local CALLER = "Encore-Professions"
local GetItemCount = (C_Item and C_Item.GetItemCount) or _G.GetItemCount

function P.HasAuctionator()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    return api and api.GetAuctionPriceByItemID and api or nil
end

function P.VendorPrice(item)
    local learned = P:DB().vendor[item]
    if learned then return learned end
    return ns.VendorPrices and ns.VendorPrices[item]
end

local function auctionator(item)
    local api = P.HasAuctionator()
    if not api then return nil end
    local ok, p = pcall(api.GetAuctionPriceByItemID, CALLER, item)
    if ok and type(p) == "number" and p > 0 then
        local okAge, age = pcall(api.GetAuctionAgeByItemID, CALLER, item)
        return p, okAge and type(age) == "number" and age or nil
    end
end

local function stonks(item)
    local s = Encore and Encore.modules and Encore.modules.Stonks
    if not (s and s.ItemStats) then return nil end
    local ok, st = pcall(s.ItemStats, s, tostring(item))
    if ok and type(st) == "table" then return st.avg7 or st.avg3 or st.avg14 end
end

-- copper, source ("vendor" or "auction"), info { last, age (days), avg7 } or nil when there is no price.
function P.Price(item)
    local v = P.VendorPrice(item)
    if v then return v, "vendor" end
    local last, age = auctionator(item)
    local avg = stonks(item)
    if last and avg and (last > avg * 1.5 or last < avg * 0.5) then
        return avg, "auction", { last = last, age = age, avg7 = avg, spike = true }
    end
    if last then return last, "auction", { last = last, age = age, avg7 = avg } end
    if avg then return avg, "auction", { avg7 = avg } end
end

-- What a crafted item is worth to you: its auction price (as P.Price reads it), or what a vendor pays for it.
-- copper, source ("auction" or "vendor"), or nil when neither is known.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
function P.Worth(item)
    local last = auctionator(item)
    local avg = stonks(item)
    if last and avg and (last > avg * 1.5 or last < avg * 0.5) then return avg, "auction" end
    if last or avg then return last or avg, "auction" end
    local sell = GetItemInfo and select(11, GetItemInfo(item))
    if type(sell) == "number" and sell > 0 then return sell, "vendor" end
end

-- The auction price on one basis, for the Selling guide: "last" the newest Auctionator scan, "avg" the
-- Encore-Stonks 7-day average; each falls back to the other. copper, or nil when neither is known.
function P.MarketPrice(item, basis)
    local last = auctionator(item)
    local avg = stonks(item)
    if basis == "avg" then return avg or last end
    return last or avg
end

-- How far the last scan is from the 7-day average, in whole percent (+12 = 12% dearer today), or nil.
function P.Trend(item)
    local last, avg = auctionator(item), stonks(item)
    if last and avg and avg > 0 then return math.floor((last / avg - 1) * 100 + 0.5) end
end

-- The age of the newest Auctionator scan of an item, in days, or nil.
function P.ScanAge(item)
    local _, age = auctionator(item)
    return age
end

-- What a vendor pays for one of the item (the client's sell price), or nil while the item isn't loaded.
function P.SellPrice(item)
    local sell = GetItemInfo and select(11, GetItemInfo(item))
    if type(sell) == "number" then return sell end
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(item) end
end

function P.Have(item) return GetItemCount and GetItemCount(item, true) or 0 end

---------------------------------------------------------------------------
-- Prices seen at merchants (unlimited stock only)
---------------------------------------------------------------------------
local function scanMerchant()
    local n = GetMerchantNumItems and GetMerchantNumItems() or 0
    local db = P:DB().vendor
    for i = 1, n do
        local price, quantity, available, extended
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local info = C_MerchantFrame.GetItemInfo(i)
            if info then price, quantity, available, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
        else
            local _
            _, _, price, quantity, available, _, _, extended = GetMerchantItemInfo(i)
        end
        local link = GetMerchantItemLink and GetMerchantItemLink(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id and price and price > 0 and (available or -1) < 0 and not extended then
            db[id] = math.floor(price / math.max(1, quantity or 1) + 0.5)
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("MERCHANT_SHOW")
f:SetScript("OnEvent", function()
    local ok, err = pcall(scanMerchant)
    if not ok then geterrorhandler()(err) end
end)
