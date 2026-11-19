-- Encore-Stonks: auction price history recorder.
-- Auctionator keeps one price per item per day for 21 days and no time of day, so on its own it can't show
-- hourly swings. Stonks listens to every price Auctionator records (full scans and normal searches) and keeps its
-- own copy with the hour it was seen: the lowest unit buyout and the most units on sale, per item per hour.
-- Auctionator's own data is read live and never copied.
--
-- Size: hourly samples are kept for 7 days (up to 30). Older samples are folded into 31 running totals per item
-- (7 weekdays, 24 hours: see Stats.lua), so the weekday and hour charts keep learning while the saved data stays
-- bounded: for 7,000 items about 0.6 MB of totals plus 0.55 MB of hourly detail per daily scan (1.2 MB at one
-- full scan a day, 2.3 MB at three).
-- Only Auctionator's documented behaviour is relied on where possible; the hook on Auctionator.Database:SetPrice
-- is internal to Auctionator, so it is guarded and Stonks just stops recording if it goes away.
local addonName, ns = ...
local Encore = _G.EncoreEssentials
local Stonks = Encore:RegisterModule("Stonks", {})
ns.Stonks = Stonks

Stonks.SCHEMA = 1
Stonks.KEEP_DAYS_OPTIONS = { 7, 14, 30 }
local DEFAULT_KEEP_DAYS = 7
local SCAN_GAP = 120 -- seconds without a price before the next price counts as a new scan

---------------------------------------------------------------------------
-- Compact sample strings
-- Each item is one string of samples "hour:price:quantity;" in base 36, oldest first. The hour is hours since
-- 1970 (UTC), so weekday and hour of day are worked out in the player's own time zone when charts are drawn.
-- 7,000 items with one sample a day for 45 days is about 4 MB of saved data.
---------------------------------------------------------------------------
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
    n = math.floor(n)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local r = n % 36
        s = DIGITS:sub(r + 1, r + 1) .. s
        n = (n - r) / 36
    end
    return s
end
Stonks.b36 = b36

-- Calls fn(hour, price, quantity) for each sample in the string, oldest first.
function Stonks.EachSample(str, fn)
    if type(str) ~= "string" then return end
    for h, p, q in str:gmatch("(%w+):(%w+):(%w+);") do
        fn(tonumber(h, 36), tonumber(p, 36), tonumber(q, 36))
    end
end

local function hourNow() return math.floor(time() / 3600) end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
local db, realmData
local pending = {} -- [dbKey] = { hour, price, qty }: this hour's sample, merged until the hour changes

local function realmKey()
    local a = _G.Auctionator
    if a and a.State and type(a.State.CurrentRealm) == "string" then return a.State.CurrentRealm end
    return (GetRealmName() or "?") .. " " .. (UnitFactionGroup("player") or "")
end

local function initDB()
    if type(EncoreStonksDB) ~= "table" then EncoreStonksDB = {} end
    db = EncoreStonksDB
    db.schema = db.schema or Stonks.SCHEMA
    if type(db.settings) ~= "table" then db.settings = {} end
    local keep = db.settings.keepDays
    if keep ~= 7 and keep ~= 14 and keep ~= 30 then db.settings.keepDays = DEFAULT_KEEP_DAYS end
    if db.settings.useAuctionator == nil then db.settings.useAuctionator = true end
    if type(db.realms) ~= "table" then db.realms = {} end
    Stonks.db = db
end

local function openRealm()
    local key = realmKey()
    local r = db.realms[key]
    if type(r) ~= "table" then
        r = { items = {}, scans = {}, since = time() }
        db.realms[key] = r
    end
    if type(r.items) ~= "table" then r.items = {} end
    if type(r.agg) ~= "table" then r.agg = {} end -- [dbKey] = folded weekday/hour totals (Stats.lua)
    if type(r.stat) ~= "table" then r.stat = {} end -- [dbKey] = Auctioneer-style running statistics (Stats.lua)
    if type(r.scans) ~= "table" then r.scans = {} end
    realmData = r
    Stonks.realm = key
    Stonks.realmData = r
end

function Stonks:Settings() return db and db.settings or {} end

function Stonks:KeepDays()
    local d = tonumber(self:Settings().keepDays) or DEFAULT_KEEP_DAYS
    return math.max(7, math.min(30, d))
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
local function flush(key, s)
    realmData.items[key] = (realmData.items[key] or "") .. b36(s[1]) .. ":" .. b36(s[2]) .. ":" .. b36(s[3]) .. ";"
end

function Stonks:FlushPending()
    if not realmData then return end
    for key, s in pairs(pending) do flush(key, s) end
    wipe(pending)
end

-- Pending sample for an item (this hour, not yet written to its string).
function Stonks:Pending(key) return pending[key] end
function Stonks:PendingKeys() return pending end

local lastPriceAt = 0
function Stonks:Record(key, price, available)
    if not realmData or type(key) ~= "string" and type(key) ~= "number" then return end
    price = tonumber(price)
    if not price or price <= 0 then return end
    key = tostring(key)
    local qty = math.max(0, math.floor(tonumber(available) or 0))
    local now = time()
    local h = math.floor(now / 3600)

    if now - lastPriceAt > SCAN_GAP then
        realmData.scans[#realmData.scans + 1] = now -- a new scan (or search session) starts
    end
    lastPriceAt = now
    realmData.last = now

    local s = pending[key]
    if s and s[1] == h then
        if price < s[2] then s[2] = price end
        if qty > s[3] then s[3] = qty end
        return
    end
    if s then flush(key, s) end
    pending[key] = { h, price, qty }
    if self.InvalidateMarket then self:InvalidateMarket() end
    if self.OnData then self:OnData() end
end

local hooked = false
local function hookAuctionator()
    if hooked then return true end
    local a = _G.Auctionator
    local database = a and a.Database
    if type(database) ~= "table" or type(database.SetPrice) ~= "function" then return false end
    hooksecurefunc(database, "SetPrice", function(_, dbKey, buyoutPrice, available)
        Stonks:Record(dbKey, buyoutPrice, available)
    end)
    hooked = true
    return true
end

function Stonks:IsRecording() return hooked end
function Stonks:HasAuctionator() return C_AddOns.IsAddOnLoaded("Auctionator") end

---------------------------------------------------------------------------
-- Folding: samples older than the kept number of days go into the item's running totals, a few hundred items
-- per frame after login.
---------------------------------------------------------------------------
-- Splits a sample string at the cutoff hour: older part, kept part (either may be nil).
local function splitAt(str, cutoff)
    local pos = 1
    while true do
        local s, e, h = str:find("^(%w+):%w+:%w+;", pos)
        if not s or tonumber(h, 36) >= cutoff then break end
        pos = e + 1
    end
    if pos == 1 then return nil, str end
    if pos > #str then return str, nil end
    return str:sub(1, pos - 1), str:sub(pos)
end

function Stonks:Prune()
    if not realmData then return end
    local cutoff = hourNow() - self:KeepDays() * 24
    local cutoffTime = cutoff * 3600
    local scans = realmData.scans
    local first = 1
    while scans[first] and scans[first] < cutoffTime do first = first + 1 end
    if first > 1 then
        local kept = {}
        for i = first, #scans do kept[#kept + 1] = scans[i] end
        realmData.scans = kept
    end

    local keys = {}
    for k in pairs(realmData.items) do keys[#keys + 1] = k end
    local i = 1
    local items = realmData.items
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        for _ = 1, 400 do
            local k = keys[i]
            if not k then
                ticker:Cancel()
                return
            end
            local v = items[k]
            if type(v) == "string" then
                local old, kept = splitAt(v, cutoff)
                if old then Stonks:Fold(k, old, kept, cutoff) end
                items[k] = kept
            else
                items[k] = nil
            end
            i = i + 1
        end
    end)
end

function Stonks:SetKeepDays(days)
    self:Settings().keepDays = days
    self:Prune()
end

---------------------------------------------------------------------------
-- Events (handler is set before any registration)
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        initDB()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        openRealm()
        if not hookAuctionator() then
            -- Auctionator missing, disabled or changed: try once more after its own late setup.
            C_Timer.After(2, hookAuctionator)
        end
        C_Timer.After(10, function() Stonks:Prune() end)
    elseif event == "PLAYER_LOGOUT" then
        Stonks:FlushPending()
    end
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")

function Stonks:Toggle()
    if self.ToggleWindow then
        self:ToggleWindow()
    else
        Encore:Print("Encore-Stonks: the window did not load. Check for Lua errors.")
    end
end
