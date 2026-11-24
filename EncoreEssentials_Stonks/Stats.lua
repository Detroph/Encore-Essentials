-- Encore-Stonks: turns recorded samples into chart data.
-- Weekday and hour charts compare each price with the item's normal price (the median of everything shown for it),
-- so a bar of -8% means the item was usually 8% cheaper at that time. Averages are taken on a log scale, so one
-- silly listing (a 1-copper mistake or a 10x posting) can't drag a whole bar around.
local _, ns = ...
local Stonks = ns.Stonks

local log, exp, floor = math.log, math.exp, math.floor
local MIN_RATIO, MAX_RATIO = 0.2, 5 -- ignore prices more than 5x away from normal

-- Local time without date(): date("*t") builds a new table on every call, and these run for every price of every
-- item, which made Stonks churn through hundreds of MB of short-lived tables (Det, 2026-11-23). The offset from
-- UTC is looked up once per UTC hour (daylight saving switches on the hour) and kept.
local tzOffsets, tzCount = {}, 0
local function tzOffset(t)
    local h = floor(t / 3600)
    local off = tzOffsets[h]
    if not off then
        local u = date("!*t", h * 3600)
        u.isdst = date("*t", h * 3600).isdst
        off = h * 3600 - time(u)
        if tzCount > 5000 then tzOffsets, tzCount = {}, 0 end
        tzOffsets[h], tzCount = off, tzCount + 1
    end
    return off
end
-- Days since 1 Jan 1970 in local time (one number per local date), and the local hour of day.
local function localDay(t) return floor((t + tzOffset(t)) / 86400) end
local function localHour(t) return floor((t + tzOffset(t)) / 3600) % 24 end
Stonks.LocalDay, Stonks.LocalHour = localDay, localHour

-- Monday first (1 Jan 1970 was a Thursday).
function Stonks.WeekdayIndex(t)
    return (localDay(t) + 3) % 7 + 1
end

local dayKey = localDay

-- WoW Forever's launch week, 4 to 11 November 2026 (local dates, both days included), is left out of every
-- average, median and weekday/hour bar (Det, 2026-11-22): launch prices were nothing like normal ones. The prices
-- stay saved and still show as points on the trend. Pinned to 2026 only.
local SKIP_FROM = time({ year = 2026, month = 11, day = 4, hour = 0 })
local SKIP_UNTIL = time({ year = 2026, month = 11, day = 12, hour = 0 })
function Stonks.Skipped(t) return t >= SKIP_FROM and t < SKIP_UNTIL end
local skipped = Stonks.Skipped

local function median(values)
    local n = #values
    if n == 0 then return nil end
    local sorted = {}
    for i = 1, n do sorted[i] = values[i] end
    table.sort(sorted)
    if n % 2 == 1 then return sorted[(n + 1) / 2] end
    return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
end
Stonks.Median = median

-- Auctionator's own day entries for an item, or nil.
local function auctionatorEntry(key)
    local a = _G.Auctionator
    local database = a and a.Database
    local data = database and database.db
    local entry = type(data) == "table" and data[key]
    if type(entry) == "table" and type(entry.h) == "table" then return entry end
    return nil
end

local function auctionatorDay0()
    local a = _G.Auctionator
    local c = a and a.Constants
    return (c and c.SCAN_DAY_0) or time({ year = 2020, month = 1, day = 1, hour = 0 })
end

---------------------------------------------------------------------------
-- Folded totals
-- Per item, one string: "u<hour>;" (samples before that hour were folded) then one entry per bucket with data,
-- "<bucket>:<count>:<sum>;" where bucket 1-7 is Monday-Sunday and a-x is hour 0-23, count is base 36 and sum is
-- the sum of log(price / normal) times 1000, base 36 with a sign. At most 31 entries, so the size is fixed.
---------------------------------------------------------------------------
local HOUR_CHARS = "abcdefghijklmnopqrstuvwx"

local function signed36(n)
    n = floor(n + 0.5)
    if n < 0 then return "-" .. Stonks.b36(-n) end
    return Stonks.b36(n)
end

-- { untilHour, week = {[1..7] = {sum, n}}, hour = {[0..23] = {sum, n}} }
function Stonks.ParseAgg(str)
    local agg = { untilHour = 0, week = {}, hour = {} }
    for i = 1, 7 do agg.week[i] = { sum = 0, n = 0 } end
    for i = 0, 23 do agg.hour[i] = { sum = 0, n = 0 } end
    if type(str) ~= "string" then return agg end
    local u = str:match("^u(%w+);")
    agg.untilHour = u and tonumber(u, 36) or 0
    for idx, n, s in str:gmatch("(%w):(%w+):(%-?%w+);") do
        -- tonumber(x, 36) mishandles a minus sign in Lua 5.1, so the sign is read separately
        local count = tonumber(n, 36)
        local sum = s:sub(1, 1) == "-" and -(tonumber(s:sub(2), 36) or 0) or tonumber(s, 36)
        if count and sum then
            local b
            local w = tonumber(idx)
            if w then b = agg.week[w] else
                local h = HOUR_CHARS:find(idx, 1, true)
                b = h and agg.hour[h - 1]
            end
            if b then b.n, b.sum = count, sum / 1000 end
        end
    end
    return agg
end

local function encodeAgg(agg)
    local parts = { "u" .. Stonks.b36(agg.untilHour) .. ";" }
    for i = 1, 7 do
        local b = agg.week[i]
        if b.n > 0 then parts[#parts + 1] = i .. ":" .. Stonks.b36(b.n) .. ":" .. signed36(b.sum * 1000) .. ";" end
    end
    for i = 0, 23 do
        local b = agg.hour[i]
        if b.n > 0 then parts[#parts + 1] = HOUR_CHARS:sub(i + 1, i + 1) .. ":" .. Stonks.b36(b.n) .. ":" .. signed36(b.sum * 1000) .. ";" end
    end
    return table.concat(parts)
end

-- Folds the samples in oldStr into the item's totals. The normal price is the median of all the item's samples
-- at that moment (old and kept), so the totals follow the price as it drifts over the months.
function Stonks:Fold(key, oldStr, keptStr, cutoffHour)
    local r = self.realmData
    if not r then return end
    local old, prices = {}, {}
    Stonks.EachSample(oldStr, function(h, p)
        local t = h * 3600 + 1800
        if not skipped(t) then old[#old + 1] = { t = t, p = p }; prices[#prices + 1] = p end
    end)
    Stonks.EachSample(keptStr, function(h, p) if not skipped(h * 3600 + 1800) then prices[#prices + 1] = p end end)
    local normal = Stonks.Median(prices)
    local agg = Stonks.ParseAgg(r.agg[key])
    agg.untilHour = math.max(agg.untilHour, cutoffHour)
    if normal and normal > 0 then
        local dayMin, dayTime = {}, {}
        for _, pt in ipairs(old) do
            local ratio = pt.p / normal
            if ratio >= MIN_RATIO and ratio <= MAX_RATIO then
                local b = agg.hour[localHour(pt.t)]
                b.sum, b.n = b.sum + log(ratio), b.n + 1
            end
            local k = dayKey(pt.t)
            if not dayMin[k] or pt.p < dayMin[k] then dayMin[k], dayTime[k] = pt.p, pt.t end
        end
        for k, p in pairs(dayMin) do
            local ratio = p / normal
            if ratio >= MIN_RATIO and ratio <= MAX_RATIO then
                local b = agg.week[Stonks.WeekdayIndex(dayTime[k])]
                b.sum, b.n = b.sum + log(ratio), b.n + 1
            end
        end
    end
    r.agg[key] = encodeAgg(agg)

    -- Running statistics take every day before the cutoff (Stonks' own and Auctionator's), once.
    local st = Stonks.ParseStat(r.stat[key])
    local cutoffTime = cutoffHour * 3600
    local days = Stonks.DailyLows(self:ItemSeries(key), function(pt) return pt.t < cutoffTime end)
    for _, d in ipairs(days) do Stonks.StatAdd(st, d.day, d.p) end
    if st.n > 0 then r.stat[key] = Stonks.EncodeStat(st) end
end

---------------------------------------------------------------------------
-- Auctioneer-style statistics, kept as a few running numbers per item instead of raw scans:
--  * 3, 7 and 14 day moving averages (exponential, one step per day seen), like Stat-Simple
--  * mean and standard deviation, weighted towards the last month, like Stat-StdDev
--  * a price histogram in 4% steps for the median and the middle 50% range, like Stat-Histogram
-- Each day counts once, with its lowest buyout. Prices more than 5x away from the 14-day average are ignored.
-- Saved as "day:n:e3:e7:e14:mean:sd|bin:count;bin:count;..." in base 36, about 100 bytes per item.
---------------------------------------------------------------------------
local BIN_STEP = log(1.04)
local MAX_BINS, HIST_CAP = 24, 120
local SD_ALPHA = 1 / 15 -- about a month of memory for the mean and spread

local function day0()
    local a = _G.Auctionator
    local c = a and a.Constants
    return (c and c.SCAN_DAY_0) or time({ year = 2020, month = 1, day = 1, hour = 0 })
end
function Stonks.DayNumber(t) return floor((t - day0()) / 86400) end

-- Lowest price per day, oldest first: { day = n, p = copper, t = time of that price }. filter(pt) (optional) picks the points used.
function Stonks.DailyLows(points, filter)
    local byDay, byTime = {}, {}
    for _, pt in ipairs(points) do
        if not skipped(pt.t) and (not filter or filter(pt)) then
            local d = Stonks.DayNumber(pt.t)
            if not byDay[d] or pt.p < byDay[d] then byDay[d], byTime[d] = pt.p, pt.t end
        end
    end
    local list = {}
    for d, p in pairs(byDay) do list[#list + 1] = { day = d, p = p, t = byTime[d] } end
    table.sort(list, function(a, b) return a.day < b.day end)
    return list
end

function Stonks.ParseStat(str)
    local st = { day = -1, n = 0, hist = {} }
    if type(str) ~= "string" then return st end
    local head, hist = str:match("^([^|]*)|?(.*)$")
    local f = {}
    for v in (head or ""):gmatch("[^:]+") do f[#f + 1] = tonumber(v, 36) end
    if #f >= 7 then
        st.day, st.n, st.e3, st.e7, st.e14, st.m = f[1], f[2], f[3], f[4], f[5], f[6]
        st.v = f[7] * f[7]
    end
    for bin, c in (hist or ""):gmatch("(%w+):(%w+);") do st.hist[tonumber(bin, 36)] = tonumber(c, 36) end
    return st
end

function Stonks.EncodeStat(st)
    local b = Stonks.b36
    local parts = { table.concat({ b(st.day), b(st.n), b(st.e3), b(st.e7), b(st.e14), b(st.m), b(math.sqrt(math.max(0, st.v))) }, ":"), "|" }
    for bin, c in pairs(st.hist) do parts[#parts + 1] = b(bin) .. ":" .. b(c) .. ";" end
    return table.concat(parts)
end

function Stonks.CopyStat(st)
    local c = {}
    for k, v in pairs(st) do c[k] = v end
    c.hist = {}
    for k, v in pairs(st.hist) do c.hist[k] = v end
    return c
end

-- Adds one day's lowest price. Days at or before the last one added are skipped, so feeding a day twice is safe.
function Stonks.StatAdd(st, day, x)
    if not x or x <= 0 or day <= st.day then return end
    if st.e14 and (x > st.e14 * MAX_RATIO or x < st.e14 * MIN_RATIO) then return end
    st.day, st.n = day, st.n + 1
    if not st.e3 then
        st.e3, st.e7, st.e14, st.m, st.v = x, x, x, x, 0
    else
        st.e3 = st.e3 + 2 / 4 * (x - st.e3)
        st.e7 = st.e7 + 2 / 8 * (x - st.e7)
        st.e14 = st.e14 + 2 / 15 * (x - st.e14)
        local d = x - st.m
        local inc = SD_ALPHA * d
        st.m = st.m + inc
        st.v = (1 - SD_ALPHA) * (st.v + d * inc)
    end
    local bin = floor(log(x) / BIN_STEP)
    st.hist[bin] = (st.hist[bin] or 0) + 1
    -- Keep the histogram small and recent: halve it when it fills up, and drop the emptiest bins.
    local total, count = 0, 0
    for _, c in pairs(st.hist) do total, count = total + c, count + 1 end
    if total > HIST_CAP then
        for k, c in pairs(st.hist) do
            c = floor(c / 2)
            st.hist[k] = c > 0 and c or nil
        end
    end
    while count > MAX_BINS do
        local minK, minC
        for k, c in pairs(st.hist) do
            if k ~= bin and (not minC or c < minC) then minK, minC = k, c end
        end
        st.hist[minK] = nil
        count = count - 1
    end
end

-- Price at a fraction (0..1) of the histogram, interpolated inside its 4% bin. bins: the histogram's bins, sorted
-- (one list shared by the three percentiles an item needs); total: the sum of its counts.
local function histPercentile(hist, bins, total, frac)
    if total == 0 then return nil end
    local target, acc = frac * total, 0
    for _, k in ipairs(bins) do
        local c = hist[k]
        if acc + c >= target then
            local within = c > 0 and (target - acc) / c or 0.5
            return exp((k + within) * BIN_STEP)
        end
        acc = acc + c
    end
    return exp((bins[#bins] + 1) * BIN_STEP)
end
local histBins = {}

-- Statistics for an item: the saved running numbers brought up to date with the recent days.
-- Returns nil without data, else { avg3, avg7, avg14, mean, sd, median, q25, q75, days, last }.
-- Lowest price per day for an item, straight from the saved strings into two reused tables, without building a
-- table per price like ItemSeries does. Same prices as Stonks.DailyLows(self:ItemSeries(key)) with guild sharing
-- (Sync/Sync.lua): your own samples, guild samples in hours you have none, and Auctionator's days on dates you
-- have no sample of your own. Fills lowDays (sorted day numbers) and lowPrice[day]; returns the count.
local lowPrice, lowDays, ownHours, ownDays = {}, {}, {}, {}
local function addLow(t, p)
    if skipped(t) then return end
    local d = Stonks.DayNumber(t)
    local cur = lowPrice[d]
    if not cur then lowDays[#lowDays + 1] = d end
    if not cur or p < cur then lowPrice[d] = p end
end

local function leanDailyLows(self, key)
    wipe(lowPrice); wipe(lowDays); wipe(ownHours); wipe(ownDays)
    local r = self.realmData
    local str = r and r.items[key]
    if type(str) == "string" then
        for h, p in str:gmatch("(%w+):(%w+):%w+;") do
            h, p = tonumber(h, 36), tonumber(p, 36)
            local t = h * 3600 + 1800
            ownHours[h] = true
            ownDays[localDay(t)] = true
            addLow(t, p)
        end
    end
    local pend = self:Pending(key)
    if pend then
        local t = pend[1] * 3600 + 1800
        ownHours[pend[1]] = true
        ownDays[localDay(t)] = true
        addLow(t, pend[2])
    end
    local guild = r and r.guild and r.guild[key]
    if type(guild) == "string" then
        for h, p in guild:gmatch("(%w+):(%w+):%w+;") do
            h = tonumber(h, 36)
            if not ownHours[h] then addLow(h * 3600 + 1800, tonumber(p, 36)) end
        end
    end
    if self:Settings().useAuctionator then
        local entry = auctionatorEntry(key)
        if entry then
            local d0 = auctionatorDay0()
            for day, high in pairs(entry.h) do
                local d = tonumber(day)
                local price = tonumber((type(entry.l) == "table" and entry.l[day]) or high)
                if d and price then
                    local t = d * 86400 + d0 + 12 * 3600
                    if not ownDays[localDay(t)] then addLow(t, price) end
                end
            end
        end
    end
    table.sort(lowDays)
    return #lowDays
end

function Stonks:ItemStats(key, points)
    key = tostring(key)
    local r = self.realmData
    local st = Stonks.ParseStat(r and r.stat[key]) -- a fresh table every call, safe to change
    local last
    if points then
        for _, d in ipairs(Stonks.DailyLows(points)) do
            Stonks.StatAdd(st, d.day, d.p)
            last = d.p
        end
    else
        for i = 1, leanDailyLows(self, key) do
            local d = lowDays[i]
            Stonks.StatAdd(st, d, lowPrice[d])
            last = lowPrice[d]
        end
    end
    if st.n == 0 then return nil end
    wipe(histBins)
    local total = 0
    for k, c in pairs(st.hist) do histBins[#histBins + 1] = k; total = total + c end
    table.sort(histBins)
    return {
        avg3 = st.e3, avg7 = st.e7, avg14 = st.e14,
        mean = st.m, sd = math.sqrt(math.max(0, st.v)),
        median = histPercentile(st.hist, histBins, total, 0.5), q25 = histPercentile(st.hist, histBins, total, 0.25),
        q75 = histPercentile(st.hist, histBins, total, 0.75),
        days = st.n, last = last,
    }
end

function Stonks:ItemAgg(key)
    local r = self.realmData
    local str = r and r.agg[tostring(key)]
    return str and Stonks.ParseAgg(str) or nil
end

-- All points for an item, oldest first: { t = seconds, p = copper, q = units, src = "s" (Stonks) or "a" (Auctionator) }.
-- Auctionator's days fill in only dates Stonks has no sample for (before Stonks was installed, mostly).
function Stonks:ItemSeries(key)
    key = tostring(key)
    local points, seenDays = {}, {}
    local function add(h, p, q)
        local t = h * 3600 + 1800 -- middle of the hour
        points[#points + 1] = { t = t, p = p, q = q, src = "s" }
        seenDays[dayKey(t)] = true
    end
    local r = self.realmData
    if r then Stonks.EachSample(r.items[key], add) end
    local pend = self:Pending(key)
    if pend then add(pend[1], pend[2], pend[3]) end

    if self:Settings().useAuctionator then
        local entry = auctionatorEntry(key)
        -- Days already folded into Stonks' totals still show on the time chart, but are marked so the weekday
        -- chart doesn't count them twice.
        local foldedUntil = r and r.agg[key] and (tonumber(r.agg[key]:match("^u(%w+);") or "0", 36) or 0) * 3600 or 0
        if entry then
            local day0 = auctionatorDay0()
            for day, high in pairs(entry.h) do
                local d = tonumber(day)
                local price = (type(entry.l) == "table" and entry.l[day]) or high
                if d and tonumber(price) then
                    local t = d * 86400 + day0 + 12 * 3600 -- local noon of that day
                    if not seenDays[dayKey(t)] then
                        local q = type(entry.a) == "table" and entry.a[day] or nil
                        points[#points + 1] = { t = t, p = tonumber(price), q = tonumber(q), src = "a", folded = t < foldedUntil or nil }
                    end
                end
            end
        end
    end
    table.sort(points, function(a, b) return a.t < b.t end)
    return points
end

local function newBuckets(n, first)
    local b = {}
    for i = first, first + n - 1 do b[i] = { sum = 0, n = 0 } end
    return b
end

-- Profile of one item's points: normal price, and the weekday (1..7, Monday first) and hour (0..23) buckets.
-- Each bucket has sum (of log ratios) and n (samples); see Stonks.BucketValue. agg (optional): folded totals
-- from older samples, added to the buckets.
function Stonks.Profile(points, agg)
    local prices = {}
    for _, pt in ipairs(points) do if not skipped(pt.t) then prices[#prices + 1] = pt.p end end
    local normal = median(prices)
    local profile = { normal = normal, week = newBuckets(7, 1), hour = newBuckets(24, 0), count = #points, days = 0, hours = 0, folded = 0 }
    if agg then
        for _, set in ipairs({ { agg.week, profile.week }, { agg.hour, profile.hour } }) do
            for idx, b in pairs(set[1]) do
                if b.n > 0 then
                    local target = set[2][idx]
                    target.sum, target.n = target.sum + b.sum, target.n + b.n
                    profile.folded = profile.folded + b.n
                end
            end
        end
    end
    if not normal or normal <= 0 then return profile end

    local function ratio(p)
        local r = p / normal
        if r < MIN_RATIO or r > MAX_RATIO then return nil end
        return log(r)
    end

    -- Weekdays: the lowest price of each date, so a day scanned five times counts once.
    local dayMin, dayTime = {}, {}
    for _, pt in ipairs(points) do
        if not skipped(pt.t) then
            local k = dayKey(pt.t)
            if not pt.folded and (not dayMin[k] or pt.p < dayMin[k]) then dayMin[k], dayTime[k] = pt.p, pt.t end
            -- Hours: only Stonks' own samples know their hour.
            if pt.src == "s" then
                local lr = ratio(pt.p)
                if lr then
                    local b = profile.hour[localHour(pt.t)]
                    b.sum, b.n = b.sum + lr, b.n + 1
                    profile.hours = profile.hours + 1
                end
            end
        end
    end
    for k, p in pairs(dayMin) do
        local lr = ratio(p)
        if lr then
            local b = profile.week[Stonks.WeekdayIndex(dayTime[k])]
            b.sum, b.n = b.sum + lr, b.n + 1
            profile.days = profile.days + 1
        end
    end
    return profile
end

-- Percent above (+) or below (-) normal for a bucket, and the typical price there; nil when it has no samples.
function Stonks.BucketValue(bucket, normal)
    if not bucket or bucket.n == 0 then return nil end
    local f = exp(bucket.sum / bucket.n)
    return (f - 1) * 100, normal and floor(normal * f + 0.5) or nil
end

-- Every item key with data on this realm (Stonks, pending, and Auctionator's when it is used).
function Stonks:AllKeys()
    local keys, seen = {}, {}
    local function add(k)
        k = tostring(k)
        if not seen[k] then seen[k] = true; keys[#keys + 1] = k end
    end
    local r = self.realmData
    if r then
        for k in pairs(r.items) do add(k) end
        for k in pairs(r.agg) do add(k) end
    end
    for k in pairs(self.PendingKeys and self:PendingKeys() or {}) do add(k) end
    if self:Settings().useAuctionator then
        local a = _G.Auctionator
        local data = a and a.Database and a.Database.db
        if type(data) == "table" then
            for k, v in pairs(data) do
                if type(v) == "table" and type(v.h) == "table" then add(k) end
            end
        end
    end
    return keys
end

---------------------------------------------------------------------------
-- Whole market: every item's profile, averaged so each item counts once per bucket. Worked out over several
-- frames (about 7,000 items) and kept until new prices come in.
---------------------------------------------------------------------------
local market, marketRunning, marketCallbacks = nil, false, {}

function Stonks:InvalidateMarket() market = nil end
function Stonks:CachedMarket() return market end

-- One item's weekday and hour profile for the market, the same as Stonks.Profile(self:ItemSeries(key),
-- self:ItemAgg(key)) but written into reused arrays instead of a table per price and per bucket: building the
-- market used to make about 400 MB of short-lived tables for 33,000 items (Det, 2026-11-23). Returns false when
-- the market would skip the item (fewer than 3 prices and no folded totals); otherwise the buckets are in
-- mWeekSum/mWeekN[1..7] and mHourSum/mHourN[0..23].
local mT, mP, mOwn, mFolded, mSorted = {}, {}, {}, {}, {}
local mWeekSum, mWeekN, mHourSum, mHourN = {}, {}, {}, {}
local mDayMin = {}
local AGG_HOURS = {}
for i = 1, #HOUR_CHARS do AGG_HOURS[HOUR_CHARS:sub(i, i)] = i - 1 end

local function marketProfile(self, key)
    for i = 1, 7 do mWeekSum[i], mWeekN[i] = 0, 0 end
    for i = 0, 23 do mHourSum[i], mHourN[i] = 0, 0 end
    wipe(ownHours); wipe(ownDays); wipe(mDayMin)
    local n = 0
    local function add(t, p, own, folded)
        n = n + 1
        mT[n], mP[n], mOwn[n], mFolded[n] = t, p, own, folded
    end
    local r = self.realmData
    local str = r and r.items[key]
    if type(str) == "string" then
        for h, p in str:gmatch("(%w+):(%w+):%w+;") do
            h = tonumber(h, 36)
            local t = h * 3600 + 1800
            ownHours[h] = true
            ownDays[localDay(t)] = true
            add(t, tonumber(p, 36), true, false)
        end
    end
    local pend = self:Pending(key)
    if pend then
        local t = pend[1] * 3600 + 1800
        ownHours[pend[1]] = true
        ownDays[localDay(t)] = true
        add(t, pend[2], true, false)
    end
    local aggStr = r and r.agg[key]
    if self:Settings().useAuctionator then
        local entry = auctionatorEntry(key)
        if entry then
            local foldedUntil = aggStr and (tonumber(aggStr:match("^u(%w+);") or "0", 36) or 0) * 3600 or 0
            local d0 = auctionatorDay0()
            for day, high in pairs(entry.h) do
                local d = tonumber(day)
                local price = tonumber((type(entry.l) == "table" and entry.l[day]) or high)
                if d and price then
                    local t = d * 86400 + d0 + 12 * 3600
                    if not ownDays[localDay(t)] then add(t, price, false, t < foldedUntil) end
                end
            end
        end
    end
    local guild = r and r.guild and r.guild[key]
    if type(guild) == "string" then
        for h, p in guild:gmatch("(%w+):(%w+):%w+;") do
            h = tonumber(h, 36)
            if not ownHours[h] then add(h * 3600 + 1800, tonumber(p, 36), true, false) end
        end
    end

    -- Folded totals: your own, or the guild baseline's buckets when you have none (as ItemAgg does).
    local hasAgg = false
    if type(aggStr) == "string" then
        hasAgg = true
        for idx, cnt, sum in aggStr:gmatch("(%w):(%w+):(%-?%w+);") do
            local count = tonumber(cnt, 36)
            local v = sum:sub(1, 1) == "-" and -(tonumber(sum:sub(2), 36) or 0) or tonumber(sum, 36)
            if count and v and count > 0 then
                local w = tonumber(idx)
                if w and w >= 1 and w <= 7 then
                    mWeekSum[w], mWeekN[w] = v / 1000, count
                else
                    local hr = AGG_HOURS[idx]
                    if hr then mHourSum[hr], mHourN[hr] = v / 1000, count end
                end
            end
        end
    else
        local agg = self:ItemAgg(key) -- guild baseline (Sync/Sync.lua), or nil
        if agg then
            hasAgg = true
            for i = 1, 7 do local b = agg.week[i]; if b and b.n > 0 then mWeekSum[i], mWeekN[i] = b.sum, b.n end end
            for i = 0, 23 do local b = agg.hour[i]; if b and b.n > 0 then mHourSum[i], mHourN[i] = b.sum, b.n end end
        end
    end
    if n < 3 and not hasAgg then return false end

    local m = 0
    for i = 1, n do
        if not skipped(mT[i]) then m = m + 1; mSorted[m] = mP[i] end
    end
    if m == 0 then return true end
    for i = m + 1, #mSorted do mSorted[i] = nil end
    table.sort(mSorted)
    local normal = m % 2 == 1 and mSorted[(m + 1) / 2] or (mSorted[m / 2] + mSorted[m / 2 + 1]) / 2
    if not normal or normal <= 0 then return true end

    for i = 1, n do
        local t, p = mT[i], mP[i]
        if not skipped(t) then
            local d = localDay(t)
            if not mFolded[i] and (not mDayMin[d] or p < mDayMin[d]) then mDayMin[d] = p end
            if mOwn[i] then
                local ratio = p / normal
                if ratio >= MIN_RATIO and ratio <= MAX_RATIO then
                    local h = localHour(t)
                    mHourSum[h], mHourN[h] = mHourSum[h] + log(ratio), mHourN[h] + 1
                end
            end
        end
    end
    for d, p in pairs(mDayMin) do
        local ratio = p / normal
        if ratio >= MIN_RATIO and ratio <= MAX_RATIO then
            local w = (d + 3) % 7 + 1
            mWeekSum[w], mWeekN[w] = mWeekSum[w] + log(ratio), mWeekN[w] + 1
        end
    end
    return true
end

function Stonks:BuildMarket(callback, progress)
    if market then return callback(market) end
    marketCallbacks[#marketCallbacks + 1] = callback
    if marketRunning then return end
    marketRunning = true
    local keys = self:AllKeys()
    local result = { week = newBuckets(7, 1), hour = newBuckets(24, 0), items = 0, total = #keys }
    local i = 1
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        for _ = 1, 60 do -- about 2 seconds for 7,000 items without a visible stutter
            local key = keys[i]
            if not key then
                ticker:Cancel()
                marketRunning = false
                market = result
                local cbs = marketCallbacks
                marketCallbacks = {}
                for _, cb in ipairs(cbs) do cb(result) end
                return
            end
            if marketProfile(self, key) then
                local used = false
                for idx = 1, 7 do
                    if mWeekN[idx] > 0 then
                        local target = result.week[idx]
                        target.sum, target.n = target.sum + mWeekSum[idx] / mWeekN[idx], target.n + 1
                        used = true
                    end
                end
                for idx = 0, 23 do
                    if mHourN[idx] > 0 then
                        local target = result.hour[idx]
                        target.sum, target.n = target.sum + mHourSum[idx] / mHourN[idx], target.n + 1
                        used = true
                    end
                end
                if used then result.items = result.items + 1 end
            end
            i = i + 1
        end
        if progress then progress(i - 1, #keys) end
    end)
end

-- Moving average (exponential, one step per day seen) over the daily lows: { { t, value }, ... }.
function Stonks.MovingAverage(points, days)
    local out, e = {}, nil
    local alpha = 2 / (days + 1)
    for _, d in ipairs(Stonks.DailyLows(points)) do
        e = e and (e + alpha * (d.p - e)) or d.p
        out[#out + 1] = { t = d.t, v = e }
    end
    return out
end

---------------------------------------------------------------------------
-- Saved data version 2 (v0.2.2): running statistics saved by version 1 may hold days from 4-11 Nov 2026. They
-- are rebuilt from the dated prices still saved (Auctionator's days before each item's fold point), leaving that
-- week out, and the saved summaries are dropped so they are worked out again. Nothing else is deleted.
-- Runs from the saved-data version step at login (Recorder.lua), and only moves the version to 2 when every item
-- is done; after that the step never runs it again. Folded weekday/hour totals need nothing: Stonks' own samples
-- start after launch week.
---------------------------------------------------------------------------
function Stonks:MigrateLaunchWeek(onDone)
    local r = self.realmData
    if not r then return end
    -- Auctionator's dated days are the source; without them now, the version stays at 1 and this runs next login.
    local a = _G.Auctionator
    if self:Settings().useAuctionator and not (a and a.Database and type(a.Database.db) == "table") then return end
    for _, realm in pairs(self.db.realms) do
        if type(realm) == "table" then realm.sum = {} end
    end
    local keys = {}
    for k in pairs(r.stat) do keys[#keys + 1] = k end
    local i = 1
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        for _ = 1, 100 do
            local key = keys[i]
            if not key then
                ticker:Cancel()
                onDone()
                return
            end
            local cutoffTime = Stonks.ParseAgg(r.agg[key]).untilHour * 3600
            local st = Stonks.ParseStat(nil)
            if cutoffTime > 0 then
                local days = Stonks.DailyLows(self:ItemSeries(key), function(pt) return pt.t < cutoffTime end)
                for _, d in ipairs(days) do Stonks.StatAdd(st, d.day, d.p) end
            end
            r.stat[key] = st.n > 0 and Stonks.EncodeStat(st) or nil
            i = i + 1
        end
    end)
end
