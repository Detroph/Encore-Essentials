-- Encore-Stonks: adds when Auctionator's price was seen to Auctionator's own "Auction" tooltip line, e.g.
-- "Auction    12g 30s (22 Nov 14:05)" (Det, 2026-11-22). Auctionator keeps one price per item per day and no time
-- of day; Stonks records the hour of every price Auctionator saves (Recorder.lua), so it knows when the price came in.
--
-- How: Stonks hooks two of Auctionator's tooltip functions (post-hooks, nothing of Auctionator is replaced or
-- copied). When Auctionator adds its Auction line, the line's number is noted; once Auctionator has finished the
-- item's lines, the time is appended to that line's right text. Everything is guarded: if Auctionator changes and
-- the functions or the line can't be found, the tooltip is left exactly as Auctionator made it.
local _, ns = ...
local Stonks = ns.Stonks

local DIM = "|cff9d9d9d"
local SCAN_LEAD = 600 -- a scan that started up to 10 minutes before the sample's hour still counts as its scan

local function enabled() return Stonks:Settings().auctionatorTime ~= false end

---------------------------------------------------------------------------
-- When the price was seen
---------------------------------------------------------------------------
local seenAt = {} -- [dbKey] = exact time, for prices seen this session

hooksecurefunc(Stonks, "Record", function(_, key, price)
    if Stonks:AtNeutralAH() or not (tonumber(price) and tonumber(price) > 0) then return end
    if key ~= nil then seenAt[tostring(key)] = time() end
end)

-- The newest hour Stonks has for an item from your own scans (guild data is kept apart and not used here).
local function lastOwnHour(key)
    local pend = Stonks:Pending(key)
    if pend then return pend[1] end
    local r = Stonks.realmData
    local str = r and r.items and r.items[key]
    if type(str) ~= "string" then return nil end
    local h = str:match("(%w+):%w+:%w+;$")
    return h and tonumber(h, 36) or nil
end

-- The start of the scan that holds the sample hour (scans are saved with their exact start time).
local function scanTime(hour)
    local scans = Stonks.realmData and Stonks.realmData.scans
    if type(scans) ~= "table" then return nil end
    local from, to = hour * 3600 - SCAN_LEAD, hour * 3600 + 3599
    for i = #scans, 1, -1 do
        local t = scans[i]
        if type(t) == "number" and t <= to then
            if t >= from then return t end
            return nil
        end
    end
    return nil
end

local function midnight(t)
    local d = date("*t", t)
    d.hour, d.min, d.sec = 0, 0, 0
    return time(d)
end

local function daysAgo(t)
    return math.floor((midnight(time()) - midnight(t)) / 86400 + 0.5)
end

-- Auctionator's own age of its price in days (internal function, so guarded).
local function auctionatorAge(key)
    local d = _G.Auctionator and _G.Auctionator.Database
    if not (d and type(d.GetPriceAge) == "function") then return nil end
    local ok, age = pcall(d.GetPriceAge, d, key)
    return ok and tonumber(age) or nil
end

local function hasAuctionatorPrice(key)
    local d = _G.Auctionator and _G.Auctionator.Database
    if not (d and type(d.GetPrice) == "function") then return true end
    local ok, p = pcall(d.GetPrice, d, key)
    return not ok or p ~= nil
end

-- Text to append for the item, or nil. Date and time when Stonks saw the price, date only when Auctionator has a
-- newer day than Stonks saw (prices from before Stonks was installed, or while it was off).
function Stonks:AuctionatorPriceTime(dbKeys)
    if type(dbKeys) ~= "table" then return nil end
    local key
    for _, k in ipairs(dbKeys) do -- the same key Auctionator takes its price from: the first one with a price
        if hasAuctionatorPrice(k) then key = tostring(k); break end
    end
    if not key then return nil end

    local t = seenAt[key]
    if not t then
        local h = lastOwnHour(key)
        if h then t = scanTime(h) or h * 3600 end
    end
    local age = auctionatorAge(key)
    if t and (age == nil or age >= daysAgo(t)) then
        return date("%d %b %H:%M", t)
    end
    if age then
        return date("%d %b", midnight(time()) - age * 86400 + 43200) -- noon of that day, safe across clock changes
    end
    return nil
end

---------------------------------------------------------------------------
-- Auctionator hooks
---------------------------------------------------------------------------
local mark -- { tooltip, line, left text } of the Auction line Auctionator just added

local function lineTexts(tooltip, n)
    local name = tooltip and tooltip.GetName and tooltip:GetName()
    if not name then return nil end
    return _G[name .. "TextLeft" .. n], _G[name .. "TextRight" .. n]
end

local function afterAuctionTip(tooltip, auctionPrice, _, cannotAuction)
    mark = nil
    if not enabled() or cannotAuction or auctionPrice == nil then return end
    if not (tooltip and tooltip.NumLines) then return end
    local n = tooltip:NumLines()
    local left = lineTexts(tooltip, n)
    if not left then return end
    mark = { tooltip, n, left:GetText() }
end

local function afterItemTip(tooltip, dbKeys)
    local m = mark
    mark = nil
    if not m or m[1] ~= tooltip or not enabled() then return end
    local left, right = lineTexts(tooltip, m[2])
    if not (left and right) or left:GetText() ~= m[3] then return end
    local text = right:GetText()
    if type(text) ~= "string" or text == "" or text:find(DIM .. "(", 1, true) then return end
    local when = Stonks:AuctionatorPriceTime(dbKeys)
    if not when then return end
    right:SetText(text .. " " .. DIM .. "(" .. when .. ")|r")
    if tooltip:IsShown() then tooltip:Show() end -- resize to the longer line
end

local reported = false
local function safe(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok and not reported then
            reported = true
            print("|cffd9a066Encore-Stonks|r tooltip time error: " .. tostring(err))
        end
    end
end

local hooked = false
local function hook()
    if hooked then return true end
    local tip = _G.Auctionator and _G.Auctionator.Tooltip
    if type(tip) ~= "table" or type(tip.AddAuctionTip) ~= "function"
        or type(tip.ShowTipWithPricingDBKey) ~= "function" then
        return false
    end
    hooksecurefunc(tip, "AddAuctionTip", safe(afterAuctionTip))
    hooksecurefunc(tip, "ShowTipWithPricingDBKey", safe(afterItemTip))
    hooked = true
    return true
end
Stonks.HookAuctionatorTooltip = hook

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not hook() then C_Timer.After(2, hook) end
end)
events:RegisterEvent("PLAYER_LOGIN")
