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

-- saved data version; 2 = launch week left out of the saved statistics (Stats.lua), 3 = one sample per item per
-- hour and base-36 summaries (Stonks:MigrateCompact below)
Stonks.SCHEMA = 3
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
local DIGIT_BYTES = { DIGITS:byte(1, 36) }
local b36buf = {}
-- Builds only the finished string (adding one digit at a time made a new string per digit).
local function b36(n)
    n = math.floor(n)
    if n <= 0 then return "0" end
    local len = 0
    while n > 0 do
        local r = n % 36
        len = len + 1
        b36buf[len] = DIGIT_BYTES[r + 1]
        n = (n - r) / 36
    end
    for i = 1, math.floor(len / 2) do
        b36buf[i], b36buf[len + 1 - i] = b36buf[len + 1 - i], b36buf[i]
    end
    return string.char(unpack(b36buf, 1, len))
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
-- Writes a pending sample. A sample for the same hour may already be saved (written at logout or a reload earlier
-- in that hour): then the two are merged, lowest price and most units, instead of saving the hour twice. Up to
-- 0.2.3 the hour was saved again, which was a quarter of all saved samples (Det, 2026-11-23).
local function flush(key, s)
    local str = realmData.items[key] or ""
    local lh, lp, lq = str:match("(%w+):(%w+):(%w+);$")
    if lh and tonumber(lh, 36) == s[1] then
        local p, q = math.min(tonumber(lp, 36), s[2]), math.max(tonumber(lq, 36), s[3])
        realmData.items[key] = str:sub(1, #str - #lh - #lp - #lq - 3) .. b36(s[1]) .. ":" .. b36(p) .. ":" .. b36(q) .. ";"
        return
    end
    realmData.items[key] = str .. b36(s[1]) .. ":" .. b36(s[2]) .. ":" .. b36(s[3]) .. ";"
end

function Stonks:FlushPending()
    if not realmData then return end
    for key, s in pairs(pending) do flush(key, s) end
    wipe(pending)
end

-- Pending sample for an item (this hour, not yet written to its string).
function Stonks:Pending(key) return pending[key] end
function Stonks:PendingKeys() return pending end

---------------------------------------------------------------------------
-- Neutral auction houses (Booty Bay, Gadgetzan, Everlook) are not recorded (Det, 2026-11-21): their prices
-- would mix into the faction auction house's history and pull its averages up. Told apart by the auctioneer,
-- who belongs to no faction there, with the zones as a fallback.
---------------------------------------------------------------------------
local NEUTRAL_MAPS = { [1434] = true, [1446] = true, [1452] = true } -- Stranglethorn Vale, Tanaris, Winterspring
local NEUTRAL_TOWNS = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true }
local atNeutral = false

local function isNeutralAH()
    if UnitExists("npc") then
        local faction = UnitFactionGroup("npc")
        if faction == "Horde" or faction == "Alliance" then return false end
        if faction == nil and UnitIsPlayer and not UnitIsPlayer("npc") then return true end
    end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if map and NEUTRAL_MAPS[map] then return true end
    return NEUTRAL_TOWNS[GetSubZoneText and GetSubZoneText() or ""] or NEUTRAL_TOWNS[GetZoneText and GetZoneText() or ""] or false
end

function Stonks:AtNeutralAH() return atNeutral end

local ahEvents = CreateFrame("Frame")
pcall(ahEvents.RegisterEvent, ahEvents, "AUCTION_HOUSE_SHOW")
pcall(ahEvents.RegisterEvent, ahEvents, "AUCTION_HOUSE_CLOSED")
ahEvents:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        local ok, neutral = pcall(isNeutralAH)
        atNeutral = ok and neutral == true
        if atNeutral and not Stonks.neutralNoted then
            Stonks.neutralNoted = true
            Encore:Print("Encore-Stonks: neutral auction house, prices here are not recorded.")
        end
    else
        atNeutral = false
    end
end)

local lastPriceAt = 0
function Stonks:Record(key, price, available)
    if not realmData or type(key) ~= "string" and type(key) ~= "number" then return end
    if atNeutral then return end
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
-- Saved data version 3 (v0.2.4): every item's samples get one entry per hour (duplicates from before are merged,
-- lowest price and most units, the same as recording does within an hour; no hour is dropped), and the saved
-- summaries are dropped so they are saved again in the smaller base-36 form. Runs over every realm, a few hundred
-- items per frame, and only moves the version to 3 when every item is done.
---------------------------------------------------------------------------
local function compactSamples(str)
    local byHour, hours = {}, {}
    local dup = false
    for h, p, q in str:gmatch("(%w+):(%w+):(%w+);") do
        local hn, pn, qn = tonumber(h, 36), tonumber(p, 36), tonumber(q, 36)
        if hn and pn and qn then
            local s = byHour[hn]
            if s then
                dup = true
                if pn < s[1] then s[1] = pn end
                if qn > s[2] then s[2] = qn end
            else
                byHour[hn] = { pn, qn }
                hours[#hours + 1] = hn
            end
        end
    end
    if not dup then return str end
    table.sort(hours)
    local parts = {}
    for i, h in ipairs(hours) do
        local s = byHour[h]
        parts[i] = b36(h) .. ":" .. b36(s[1]) .. ":" .. b36(s[2]) .. ";"
    end
    return table.concat(parts)
end
Stonks.CompactSamples = compactSamples

function Stonks:MigrateCompact(onDone)
    local jobs = {}
    for _, realm in pairs(db.realms) do
        if type(realm) == "table" then
            realm.sum = {}
            if type(realm.items) == "table" then
                for k in pairs(realm.items) do jobs[#jobs + 1] = { realm.items, k } end
            end
        end
    end
    local i = 1
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        for _ = 1, 300 do
            local job = jobs[i]
            if not job then
                ticker:Cancel()
                onDone()
                return
            end
            local items, k = job[1], job[2]
            if type(items[k]) == "string" then items[k] = compactSamples(items[k]) end
            i = i + 1
        end
    end)
end

-- Runs the saved-data version steps in order, each one only once its version is reached.
function Stonks:MigrateSavedData()
    local v = tonumber(db.schema) or 1
    if v < 3 then
        -- Saved summaries are only a cache; old ones are in the earlier decimal form, so they go right away.
        for _, realm in pairs(db.realms) do
            if type(realm) == "table" then realm.sum = {} end
        end
    end
    if v < 2 then
        C_Timer.After(5, function()
            Stonks:MigrateLaunchWeek(function()
                db.schema = 2
                Stonks:MigrateSavedData()
            end)
        end)
    elseif v < 3 then
        C_Timer.After(5, function() Stonks:MigrateCompact(function() db.schema = 3 end) end)
    end
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
        Stonks:MigrateSavedData()
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
