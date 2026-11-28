-- Encore-Stonks guild sharing: what gets shared, when, and how it is merged.
--  * Hourly scans: the first player to finish a scan in a UTC hour claims that hour on the guild channel and
--    broadcasts only the items that changed since the last shared hour. Everyone else keeps their scan to themselves.
--  * Login summary: a minute after login, out of combat, the player says HELLO; the best-placed guildmate (AFK
--    players first, then freshest data) offers, the asker accepts one offer, and the summary arrives by whisper in
--    self-contained blocks. If the sender goes away, the asker resumes from the last item it got with someone else.
--  * One delivery at a time: an hourly scan waits while a login summary runs, and a hello waits while an hourly
--    scan is coming in.
--  * Received prices are kept apart from your own: guild samples in realm.guild (same format as your own samples,
--    your own hour always wins, at most one guild sample per item per 4 hours unless the price moved more than 2%),
--    summaries in realm.baseline, which fades out as your own data grows.
--  * Sharing is on by default; /stonksync receive or off turns it down.
local _, ns = ...
local Stonks = ns.Stonks
local Codec, Comm, Log = Stonks.SyncCodec, Stonks.SyncComm, Stonks.SyncLog
local Sync = {}
Stonks.Sync = Sync

local floor, random = math.floor, math.random
local P = "|cffd9a066Encore-Stonks|r "
local HELLO_DELAY = 60 -- seconds after login
local CLAIM_MIN_ITEMS = 300 -- a "scan" for sharing: at least this many items seen in one hour
local THIN_HOURS, THIN_CHANGE = 4, 0.02
local DELTA_CHANGE = 0.01
local OUTLIER = 5 -- a price more than 5x away from your own normal price is not accepted
local BASELINE_FULL_DAYS = 20 -- the guild baseline fades out as your own days of data reach this
local MUTE_MIN_CHECKS, MUTE_RATIO = 50, 0.3
local ASK_TIMEOUT, BLOCK_TIMEOUT = 15, 60
local RETRY = { 60, 120, 240, 480, 900 }
-- One delivery at a time in the guild: an hourly scan waits while a login summary runs, and a login summary request
-- waits while an hourly scan is coming in, so nobody gets both at once.
local SUMMARY_HOLD = 300 -- seconds after a summary is accepted (about 120 KB at 400 bytes a second)
local HELLO_HOLD = 30 -- seconds after a hello: the accept follows within about 20 seconds, or nothing does
local SCAN_QUIET = 20 -- seconds without an hourly scan message before it counts as over
local CLAIM_LATEST = 300 -- seconds before the end of the hour: from then on a claim no longer waits
local HOLD_RETRY = 30

local function hourNow() return floor(time() / 3600) end

-- New guild data: refresh the market cache, the browser and the graph, at most every 5 seconds.
local dirty = false
function Sync.Touched() dirty = true end
local function refresh()
    if not dirty then return end
    dirty = false
    if Stonks.InvalidateMarket then Stonks:InvalidateMarket() end
    if Stonks.OnData then Stonks:OnData() end
end
local function settings()
    local s = Stonks:Settings()
    if type(s.sync) ~= "table" then s.sync = {} end
    local sync = s.sync
    -- On by default. The first login with this version switches sharing on once for everyone (whatever was saved
    -- before), so the whole guild shares; an explicit /stonksync off or receive after that sticks.
    if (tonumber(sync.v) or 0) < 3 then
        sync.mode = "share"
        sync.v = 3
    end
    if sync.mode ~= "share" and sync.mode ~= "receive" and sync.mode ~= "off" then sync.mode = "share" end
    if type(sync.muted) ~= "table" then sync.muted = {} end
    return sync
end
Sync.Settings = settings

local function realm()
    local r = Stonks.realmData
    if not r then return nil end
    if type(r.guild) ~= "table" then r.guild = {} end -- [itemID] = "hour:price:qty;" (base 36, like r.items)
    if type(r.baseline) ~= "table" then r.baseline = {} end -- [itemID] = summary record text (Codec format)
    if type(r.sync) ~= "table" then r.sync = {} end -- { since = hour of the last complete summary, from = name }
    return r
end

local function mode() return Stonks.db and settings().mode or "off" end
function Sync.Mode() return mode() end
local function sharing() return mode() == "share" end

---------------------------------------------------------------------------
-- Senders: muting and the quiet score (how often a sender's prices fall far from ours)
---------------------------------------------------------------------------
local score = {} -- [name] = { checks, outliers }

local function isMuted(name) return settings().muted[name] or (score[name] and score[name].muted) end
Sync.IsMuted = isMuted

local function note(name, outlier)
    local s = score[name]
    if not s then s = { checks = 0, outliers = 0 }; score[name] = s end
    s.checks = s.checks + 1
    if outlier then s.outliers = s.outliers + 1 end
    if not s.muted and s.checks >= MUTE_MIN_CHECKS and s.outliers / s.checks > MUTE_RATIO then
        s.muted = true
        print(P .. ("stopped accepting prices from %s: too many of them were far from yours. /stonksync unmute %s to undo."):format(Codec.safeText(name), Codec.safeText(name)))
    end
end
Sync.score = score

-- Your own normal price for an item, cheaply: the 14-day average from the saved statistics, else your last sample.
local function ownReference(key)
    local r = Stonks.realmData
    if not r then return nil end
    local st = r.stat[key]
    if st then
        local s = Stonks.ParseStat(st)
        if s.n >= 5 and s.e14 then return s.e14 end
    end
    return nil
end

local function isOutlier(key, price)
    local ref = ownReference(key)
    if not ref or ref <= 0 then return false, false end
    local ratio = price / ref
    return ratio > OUTLIER or ratio < 1 / OUTLIER, true
end

---------------------------------------------------------------------------
-- Merging guild samples
---------------------------------------------------------------------------
local b36 = Stonks.b36

-- Last sample "hour, price" in a sample string.
local function lastSample(str)
    if type(str) ~= "string" then return nil end
    local h, p = str:match("(%w+):(%w+):%w+;$")
    if not h then return nil end
    return tonumber(h, 36), tonumber(p, 36)
end

local function ownHasHour(key, hour)
    local pend = Stonks:Pending(key)
    if pend and pend[1] == hour then return true end
    local str = Stonks.realmData.items[key]
    if type(str) ~= "string" then return false end
    return str:find("^" .. b36(hour) .. ":") ~= nil or str:find(";" .. b36(hour) .. ":") ~= nil
end

-- Adds one guild observation. Returns true when it was kept.
function Sync.AddGuildSample(key, hour, price, qty, sender)
    local r = realm()
    if not r then return false end
    local outlier, checked = isOutlier(key, price)
    if checked and sender then note(sender, outlier) end
    if outlier then return false end
    if ownHasHour(key, hour) then return false end
    local str = r.guild[key]
    local lh, lp = lastSample(str)
    local entry = b36(hour) .. ":" .. b36(price) .. ":" .. b36(qty) .. ";"
    if not lh or hour > lh then
        if lh and hour - lh < THIN_HOURS and math.abs(price - lp) / lp <= THIN_CHANGE then return false end
        r.guild[key] = (str or "") .. entry
        return true
    end
    -- Older than our newest guild sample (an imported scan): insert in order, once per hour.
    local list, kept = {}, false
    Stonks.EachSample(str, function(h, p, q)
        if not kept and hour < h then list[#list + 1] = entry; kept = true end
        if h == hour then kept = true end
        list[#list + 1] = b36(h) .. ":" .. b36(p) .. ":" .. b36(q) .. ";"
    end)
    if not kept then list[#list + 1] = entry end
    r.guild[key] = table.concat(list)
    return true
end

-- Drops guild samples older than the kept number of days.
function Sync.PruneGuild()
    local r = realm()
    if not r then return end
    local cutoff = hourNow() - Stonks:KeepDays() * 24
    local keys = {}
    for k in pairs(r.guild) do keys[#keys + 1] = k end
    Comm.AddJob(function()
        for i, k in ipairs(keys) do
            local str = r.guild[k]
            if type(str) == "string" then
                local parts = {}
                Stonks.EachSample(str, function(h, p, q)
                    if h >= cutoff then parts[#parts + 1] = b36(h) .. ":" .. b36(p) .. ":" .. b36(q) .. ";" end
                end)
                r.guild[k] = #parts > 0 and table.concat(parts) or nil
            else
                r.guild[k] = nil
            end
            Comm.MaybeYield()
        end
    end, "prune")
end

---------------------------------------------------------------------------
-- Summaries (past data)
---------------------------------------------------------------------------
local origItemStats, origItemAgg, origItemSeries, origAllKeys

-- Builds the summary record for one of our items, or nil when we have nothing useful.
function Sync.BuildSummary(key)
    local id = tonumber(key)
    if not id or id < 1 or id > Codec.MAX_ITEM_ID or floor(id) ~= id then return nil end
    local st = origItemStats(Stonks, key)
    if not st or not st.median or not st.days or st.days < 1 then return nil end
    -- The averages are plain means over the last 3/7/14 days, so an item without a recent price has none: the
    -- record (whose format needs all three) then carries the longer window's average, or the median.
    local a14 = st.avg14 or st.median
    local a7 = st.avg7 or a14
    local a3 = st.avg3 or a7
    local rec = { id = id, days = st.days }
    rec.med, rec.q25, rec.q75 = floor(st.median + 0.5), floor((st.q25 or st.median) + 0.5), floor((st.q75 or st.median) + 0.5)
    rec.a3, rec.a7, rec.a14 = floor(a3 + 0.5), floor(a7 + 0.5), floor(a14 + 0.5)
    if rec.q25 > rec.med then rec.q25 = rec.med end
    if rec.q75 < rec.med then rec.q75 = rec.med end
    for _, f in ipairs(Codec.SUMMARY_FIELDS) do if rec[f] < 1 then return nil end end
    local agg = Stonks.realmData.agg[key] and Stonks.ParseAgg(Stonks.realmData.agg[key])
    if agg then rec.week, rec.hour = agg.week, agg.hour end
    return Codec.encodeSummary(rec)
end

-- Stores a received summary record. Returns true when kept.
function Sync.AddSummary(text, sender)
    local r = realm()
    if not r then return false end
    local rec, why = Codec.decodeSummary(text)
    if not rec then Comm.Reject("summary " .. tostring(why)); return false end
    local key = tostring(rec.id)
    local outlier, checked = isOutlier(key, rec.med)
    if checked and sender then note(sender, outlier) end
    if outlier then return false end
    r.baseline[key] = text
    return true
end

-- The newest hour of our own data for an item (to send only what changed since the asker's last summary).
local function ownLastHour(key)
    local pend = Stonks:Pending(key)
    if pend then return pend[1] end
    local h = lastSample(Stonks.realmData.items[key])
    return h or 0
end

---------------------------------------------------------------------------
-- What the charts see: your own data first, guild data filling the gaps.
---------------------------------------------------------------------------
local function baselineRec(key)
    local r = Stonks.realmData
    local text = r and r.baseline and r.baseline[tostring(key)]
    return text and Codec.decodeSummary(text) or nil
end

local function installViews()
    origItemStats, origItemAgg, origItemSeries, origAllKeys = Stonks.ItemStats, Stonks.ItemAgg, Stonks.ItemSeries, Stonks.AllKeys

    function Stonks:ItemSeries(key)
        local points = origItemSeries(self, key)
        local r = self.realmData
        local str = r and r.guild and r.guild[tostring(key)]
        if not str then return points end
        local own = {}
        for _, pt in ipairs(points) do if pt.src == "s" then own[floor(pt.t / 3600)] = true end end
        local added = false
        Stonks.EachSample(str, function(h, p, q)
            if not own[h] then
                points[#points + 1] = { t = h * 3600 + 1800, p = p, q = q, src = "s", guild = true }
                added = true
            end
        end)
        if added then table.sort(points, function(a, b) return a.t < b.t end) end
        return points
    end

    function Stonks:ItemStats(key, points, beforeDay)
        local own = origItemStats(self, key, points, beforeDay)
        local days = own and own.days or 0
        if days >= BASELINE_FULL_DAYS then return own end -- checked first: no need to decode the baseline then
        local r = self.realmData
        local med, q25, q75, a3, a7, a14, bdays = Codec.summaryPrices(r and r.baseline and r.baseline[tostring(key)])
        if not med then return own end
        local base = { avg3 = a3, avg7 = a7, avg14 = a14, mean = med, sd = 0, median = med, q25 = q25, q75 = q75,
            days = bdays, guild = true }
        if not own then return base end
        local w = 1 - days / BASELINE_FULL_DAYS
        local out = {}
        for k, v in pairs(own) do out[k] = v end
        for _, f in ipairs({ "avg3", "avg7", "avg14", "median", "q25", "q75" }) do
            if own[f] and base[f] then out[f] = own[f] * (1 - w) + base[f] * w end
        end
        return out
    end

    function Stonks:ItemAgg(key)
        local own = origItemAgg(self, key)
        if own then return own end
        local b = baselineRec(key)
        if not b then return nil end
        return { untilHour = 0, week = b.week, hour = b.hour, guild = true }
    end

    function Stonks:AllKeys()
        local keys = origAllKeys(self)
        local r = self.realmData
        if not r or (not r.guild and not r.baseline) then return keys end
        local seen = {}
        for _, k in ipairs(keys) do seen[k] = true end
        for _, t in ipairs({ r.guild or {}, r.baseline or {} }) do
            for k in pairs(t) do
                if not seen[k] then seen[k] = true; keys[#keys + 1] = k end
            end
        end
        return keys
    end
end

---------------------------------------------------------------------------
-- Hourly scans
---------------------------------------------------------------------------
local claims = {} -- [hour] = { name = claimer, hash = tie-break }
local myClaim -- { hour, hash, at }
local lastSlot = {} -- [itemID] = { price, qty } as last shared, for deltas
local handledHour
local helloAt, acceptAt, liveScanAt = 0, 0, 0 -- Comm.now() of the last guild hello, accept and hourly scan message
local serving -- { asker }: the login summary we are sending (see the handshake below)
local ask -- our request: { since, resume, offers = {}, chosen, lastBlock, tries }

-- A login summary is being asked for or sent somewhere in the guild (or by us).
local function summaryRunning()
    local t = Comm.now()
    return serving ~= nil or (ask ~= nil and ask.chosen ~= nil) or t - acceptAt < SUMMARY_HOLD or t - helloAt < HELLO_HOLD
end
Sync.SummaryRunning = summaryRunning

-- Someone's hourly scan is coming in on the guild channel right now.
local function hourlyIncoming() return Comm.now() - liveScanAt < SCAN_QUIET end
Sync.HourlyIncoming = hourlyIncoming

local function scanItemsFor(hour)
    local list = {}
    for key, s in pairs(Stonks:PendingKeys()) do
        local id = tonumber(key)
        if id and s[1] == hour and floor(id) == id and id >= 1 and id <= Codec.MAX_ITEM_ID then list[#list + 1] = { id, s[2], s[3] } end
    end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    return list
end

-- Packs observations into self-contained messages: header .. body, at most 255 bytes each.
local function packObs(header, list, emit)
    local body, prev = {}, 0
    local len = #header
    for _, o in ipairs(list) do
        local piece = Codec.encodeObs(prev, o[1], o[2], o[3])
        if len + #piece > 250 then
            emit(header .. table.concat(body))
            body, prev, len = {}, 0, #header
            piece = Codec.encodeObs(0, o[1], o[2], o[3])
        end
        body[#body + 1] = piece
        len = len + #piece
        prev = o[1]
    end
    if #body > 0 then emit(header .. table.concat(body)) end
end
Sync.packObs = packObs

local function broadcastScan(hour)
    local list = scanItemsFor(hour)
    local delta = {}
    for _, o in ipairs(list) do
        local prev = lastSlot[o[1]]
        if not prev or prev[2] ~= o[3] or math.abs(o[2] - prev[1]) / prev[1] > DELTA_CHANGE then delta[#delta + 1] = o end
        lastSlot[o[1]] = { o[2], o[3] }
    end
    local header = "1S" .. Codec.enc(hour) .. ":"
    local sent = 0
    packObs(header, delta, function(msg) Comm.Send(msg, "GUILD"); sent = sent + 1 end)
    Comm.Send("1E" .. Codec.enc(hour) .. "," .. Codec.enc(#delta), "GUILD")
    Sync.lastBroadcast = { hour = hour, items = #delta, messages = sent }
end

local function myHash(hour) return Codec.hash((Comm.Me() or "") .. hour) end

local function tryClaim(hour)
    if not sharing() or claims[hour] or not IsInGuild() then return end
    if Comm.Busy() then
        C_Timer.After(30, function() tryClaim(hour) end)
        return
    end
    -- A login summary is running: share the scan after it, while there is still time left in the hour.
    if summaryRunning() and (hour + 1) * 3600 - time() > CLAIM_LATEST then
        C_Timer.After(HOLD_RETRY, function() tryClaim(hour) end)
        return
    end
    local list = scanItemsFor(hour)
    if #list < CLAIM_MIN_ITEMS then return end
    myClaim = { hour = hour, hash = myHash(hour) }
    claims[hour] = { name = Comm.Me(), hash = myClaim.hash }
    Comm.Send("1C" .. Codec.enc(hour) .. "," .. Codec.enc(#list) .. "," .. Codec.enc(myClaim.hash), "GUILD", nil, function()
        -- Give a crossing claim 3 seconds to arrive; the lower hash wins.
        C_Timer.After(3, function()
            if myClaim and myClaim.hour == hour and claims[hour] and claims[hour].name == Comm.Me() then broadcastScan(hour) end
        end)
    end)
end

-- Every 15 seconds: did we just finish a scan this hour that nobody has shared yet?
local function checkScan()
    local r = Stonks.realmData
    if not r or not r.last or not sharing() then return end
    local quiet = time() - r.last
    if quiet < 60 or quiet > 1800 then return end
    local hour = floor(r.last / 3600)
    if hour ~= hourNow() or handledHour == hour then return end
    handledHour = hour
    C_Timer.After(5 + random() * 25, function() tryClaim(hour) end)
end

Comm.On("C", function(body, sender)
    local f = Codec.fields(body, 3)
    if not f or #f ~= 3 then return Comm.Reject("fields") end
    local hour, count, hash = Codec.dec(f[1]), Codec.dec(f[2]), Codec.dec(f[3])
    if not hour or not count or not hash then return Comm.Reject("fields") end
    if math.abs(hour - hourNow()) > 1 then return Comm.Reject("hour") end
    liveScanAt = Comm.now()
    local c = claims[hour]
    -- Two claims for one hour: the lower hash (then the lower name) keeps it.
    if c and c.name ~= sender and (hash > c.hash or (hash == c.hash and sender > c.name)) then return end
    claims[hour] = { name = sender, hash = hash }
    if myClaim and myClaim.hour == hour then
        myClaim = nil
        local h = "1S" .. Codec.enc(hour) .. ":"
        Comm.Cancel(function(msg, channel) return channel == "GUILD" and (msg:sub(1, #h) == h or msg:sub(1, 2) == "1E") end)
    end
end)

local function acceptObsMessage(body, sender, live)
    local hs, rest = body:match("^([^:]+):(.*)$")
    local hour = Codec.dec(hs)
    if not hour or not rest then return Comm.Reject("header") end
    if live and math.abs(hour - hourNow()) > 1 then return Comm.Reject("hour") end
    if not live and (hour > hourNow() or hour < hourNow() - Stonks:KeepDays() * 24) then return Comm.Reject("hour") end
    local list, why = Codec.decodeObs(rest)
    if not list then return Comm.Reject(why) end
    local kept = 0
    for _, o in ipairs(list) do
        local key = tostring(o[1])
        if Sync.AddGuildSample(key, hour, o[2], o[3], sender) then kept = kept + 1 end
        if live then lastSlot[o[1]] = { o[2], o[3] } end
    end
    Sync.Touched()
    -- Sync history: an hourly guild scan, or a scan shared by chat link (whisper).
    Log.Add(live and "hourly" or "scan", sender, hour, { got = #list, kept = kept, hour = hour })
    return list, kept
end
Sync.acceptObsMessage = acceptObsMessage

Comm.On("S", function(body, sender, channel)
    if channel == "GUILD" then
        local hour = Codec.dec(body:match("^([^:]+):") or "")
        local c = hour and claims[hour]
        if c and c.name ~= sender then return end -- only the claimer of that hour is listened to
        liveScanAt = Comm.now()
        if not c and hour then claims[hour] = { name = sender, hash = 0 } end
        acceptObsMessage(body, sender, true)
    elseif channel == "WHISPER" and Sync.Links and Sync.Links.ExpectScan(sender, body) then
        acceptObsMessage(body, sender, false)
    end
end)

---------------------------------------------------------------------------
-- Login summary handshake
---------------------------------------------------------------------------
local offerTimers = {} -- [asker] = timer handle (we are waiting to offer)
local pendingOffers = {} -- [asker] = { since, resume, at }: offers we made and wait to hear back on
local noServe = {} -- [name] = true: offered but never sent anything this session (an older version that can't
                   -- read our name, or gone), passed over while anyone else offers

local function startAsk(resume)
    if mode() == "off" or not IsInGuild() then return end
    if Comm.Busy() then C_Timer.After(30, function() startAsk(resume) end); return end
    -- An hourly scan is coming in: ask once it is over, so the two don't arrive at the same time.
    if hourlyIncoming() then C_Timer.After(HOLD_RETRY, function() startAsk(resume) end); return end
    local r = realm()
    if not r then return end
    ask = ask or { tries = 0 }
    ask.since = r.sync.since or 0
    ask.resume = resume or ask.resume or 0
    ask.offers, ask.chosen, ask.askedAt = {}, nil, Comm.now()
    Comm.Send("1H" .. Codec.enc(ask.since) .. "," .. Codec.enc(ask.resume), "GUILD")
    local thisAsk = ask.askedAt
    C_Timer.After(ASK_TIMEOUT, function()
        if ask and ask.askedAt == thisAsk and not ask.chosen and #ask.offers == 0 then
            if ask.manual then
                -- A request from the button: say so, and don't keep asking.
                ask = nil
                if Sync.onManual then Sync.onManual("none") end
                return
            end
            ask.tries = ask.tries + 1
            local wait = RETRY[ask.tries]
            if wait then C_Timer.After(wait, function() startAsk() end) else ask = nil end
        end
    end)
end
Sync.StartAsk = startAsk

-- The "Request sync" button: one more login-summary request, at most once an hour (kept over a /reload). It costs the guild what
-- a login does: one small hello, a few small offers, and one guildmate whispering only what changed since your last
-- summary.
local MANUAL_COOLDOWN = 3600
function Sync.ManualWait()
    return math.max(0, (tonumber(settings().manualAt) or 0) + MANUAL_COOLDOWN - time())
end
function Sync.RequestNow()
    if mode() == "off" then return false, "Guild sharing is off. /stonksync share turns it on." end
    if not IsInGuild() then return false, "You are not in a guild." end
    if Sync.ManualWait() > 0 then return false, ("You can ask again in %d minutes."):format(math.ceil(Sync.ManualWait() / 60)) end
    if ask and ask.chosen then return false, "A login summary is already coming in from " .. Codec.safeText(ask.chosen) .. "." end
    settings().manualAt = time()
    ask = { tries = #RETRY, manual = true }
    startAsk(0)
    return true, "Asked the guild. If someone has newer prices than you, they show up here in a minute or two."
end

local function pickOffer()
    if not ask or ask.chosen or #ask.offers == 0 then return end
    table.sort(ask.offers, function(a, b)
        -- Senders that say they can serve any name (0.1.8 and later) first.
        if a.cap ~= b.cap then return a.cap end
        if a.afk ~= b.afk then return a.afk end
        if a.asOf ~= b.asOf then return a.asOf > b.asOf end
        return a.name < b.name
    end)
    local best = ask.offers[1]
    ask.chosen, ask.asOf, ask.lastBlock, ask.gotBlock = best.name, best.asOf, Comm.now(), false
    Comm.Send("1A" .. best.name, "GUILD")
    -- Sync history: the login summary starts now, so an attempt that never delivers is visible too.
    Log.Add("summary", best.name, "login", { got = 0, kept = 0, hour = best.asOf })
    local function watch()
        if not ask or ask.chosen ~= best.name then return end
        if Comm.now() - ask.lastBlock > BLOCK_TIMEOUT then
            -- Sender went quiet (logged off, disconnected): keep what we have and ask someone else to continue.
            local resume = ask.resume
            if not ask.gotBlock then noServe[best.name] = true end
            Log.Finish("summary", best.name, "login", { stopped = true, silent = not ask.gotBlock })
            ask.chosen = nil
            startAsk(resume)
        else
            C_Timer.After(10, watch)
        end
    end
    C_Timer.After(10, watch)
end

-- Someone logged in and asks for past data.
Comm.On("H", function(body, sender, channel)
    if channel ~= "GUILD" then return end
    helloAt = Comm.now()
    if not sharing() then return end
    local f = Codec.fields(body, 2)
    local since, resume = f and Codec.dec(f[1]), f and Codec.dec(f[2])
    if not since or not resume then return Comm.Reject("fields") end
    if serving or offerTimers[sender] or Comm.Busy() then return end
    local r = Stonks.realmData
    local asOf = r and r.last and floor(r.last / 3600) or 0
    if asOf <= since then return end
    local afk = UnitIsAFK("player") and true or false
    local freshness = math.min(1, (hourNow() - asOf) / 48) -- 0 = scanned this hour
    local delay = (afk and 0 or 1) + (afk and 1 or 4) * (0.5 * freshness + 0.5 * random())
    offerTimers[sender] = C_Timer.NewTimer(delay, function()
        offerTimers[sender] = nil
        if serving or Comm.Busy() then return end
        -- The 4th field says "this version can serve players named with a space"; 0.1.4 and older can't.
        Comm.Send("1O" .. sender .. "," .. Codec.enc(asOf) .. "," .. (afk and "1" or "0") .. ",2", "GUILD")
        pendingOffers[sender] = { since = since, resume = resume, at = Comm.now() }
    end)
end)

-- An offer: if it is for us, collect it; if it is for someone we were about to answer, stand down.
Comm.On("O", function(body, sender, channel)
    if channel ~= "GUILD" then return end
    local f = Codec.fields(body, 4)
    if not f or (#f ~= 3 and #f ~= 4) then return Comm.Reject("fields") end
    local asker, asOf = Codec.cleanName(f[1]), Codec.dec(f[2])
    if not asker or not asOf or (f[3] ~= "0" and f[3] ~= "1") then return Comm.Reject(asker and "fields" or "name") end
    if Comm.IsMe(asker) then
        if ask and not ask.chosen and not noServe[sender] then
            ask.offers[#ask.offers + 1] = { name = sender, asOf = asOf, afk = f[3] == "1", cap = f[4] == "2" }
            -- Wait 2 seconds for better offers, 6 when the first one is from an old version that may not deliver.
            if #ask.offers == 1 then C_Timer.After(f[4] == "2" and 2 or 6, pickOffer) end
        end
    elseif offerTimers[asker] and f[4] == "2" then
        -- Only a sender that can serve every name makes us stand down: an old version's offer may never deliver.
        offerTimers[asker]:Cancel()
        offerTimers[asker] = nil
    end
end)

local function serve(asker, since, resume)
    serving = { asker = asker }
    local r = Stonks.realmData
    local keys = {}
    for k in pairs(r.items) do keys[#keys + 1] = k end
    for k in pairs(r.agg) do if not r.items[k] then keys[#keys + 1] = k end end
    local ids = {}
    for _, k in ipairs(keys) do
        local id = tonumber(k)
        if id and floor(id) == id and id >= resume then ids[#ids + 1] = id end
    end
    table.sort(ids)
    Comm.AddJob(function()
        local header, body, len, count = "1Y", {}, 2, 0
        for i, id in ipairs(ids) do
            if not serving or serving.asker ~= asker then return end
            local key = tostring(id)
            if since == 0 or ownLastHour(key) > since then
                local rec = Sync.BuildSummary(key)
                if rec then
                    if len + #rec + 1 > 250 then
                        Comm.Send(header .. table.concat(body, ";"), "WHISPER", asker)
                        body, len = {}, 2
                    end
                    body[#body + 1] = rec
                    len = len + #rec + 1
                    count = count + 1
                end
            end
            -- Don't build far ahead of what the throttle can send.
            while Comm.QueueLength() > 20 do Comm.Wait() end
            Comm.MaybeYield()
        end
        if #body > 0 then Comm.Send(header .. table.concat(body, ";"), "WHISPER", asker) end
        Comm.Send("1Z" .. Codec.enc(count), "WHISPER", asker, function() serving = nil end)
    end, "serve")
end

-- The asker went offline (three "No player named ..." lines): stop serving them.
Comm.OnGone(function(name)
    if serving and Comm.IsGone(serving.asker) then serving = nil end
end)

Comm.On("A", function(body, sender, channel)
    if channel ~= "GUILD" then return end
    acceptAt = Comm.now()
    local chosen = Codec.cleanName(body)
    if not chosen then return Comm.Reject("name") end
    local p = pendingOffers[sender]
    if p then
        pendingOffers[sender] = nil
        if Comm.IsMe(chosen) and not serving then serve(sender, p.since, p.resume) end
    end
end)

Comm.On("Y", function(body, sender, channel)
    if channel ~= "WHISPER" or not ask or ask.chosen ~= sender then return end
    ask.lastBlock, ask.gotBlock = Comm.now(), true
    local got, kept = 0, 0
    for text in (body .. ";"):gmatch("([^;]*);") do
        got = got + 1
        if Sync.AddSummary(text, sender) then
            kept = kept + 1
            local id = Codec.dec(text:match("^([^,]+)") or "")
            if id and id >= ask.resume then ask.resume = id + 1 end
        end
    end
    Log.Add("summary", sender, "login", { got = got, kept = kept, hour = ask.asOf })
    Sync.Touched()
end)

Comm.On("Z", function(body, sender, channel)
    if channel ~= "WHISPER" or not ask or ask.chosen ~= sender then return end
    Log.Finish("summary", sender, "login", { expected = Codec.dec(body) })
    local r = realm()
    r.sync.since, r.sync.from, r.sync.at = ask.asOf, sender, time()
    ask = nil
end)

---------------------------------------------------------------------------
-- Who runs Encore-Stonks: /stonksync who asks the guild, every guildmate with sharing not off answers by whisper.
---------------------------------------------------------------------------
local MODE_CODE = { share = "s", receive = "r", off = "o" }
local CODE_MODE = { s = "share", r = "receive", o = "off" }
local who -- { at, replies = { [name] = { mode, asOf, version } }, done = fn }

local function myVersion()
    local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("EncoreEssentials_Stonks", "Version")
    v = tostring(v or "?"):gsub("[^%w%.%-]", "")
    if v == "" or v:find("project") then v = "dev" end
    return v:sub(1, 20)
end

function Sync.Who(done)
    if not IsInGuild() then return false end
    who = { at = time(), replies = {}, done = done }
    Comm.Send("1W", "GUILD")
    local thisWho = who
    C_Timer.After(8, function()
        if who == thisWho then
            who = nil
            if thisWho.done then thisWho.done(thisWho.replies) end
        end
    end)
    return true
end

Comm.On("W", function(_, sender, channel)
    if channel ~= "GUILD" or mode() == "off" then return end
    local r = Stonks.realmData
    local asOf = r and r.last and floor(r.last / 3600) or 0
    C_Timer.After(random() * 4, function()
        Comm.Send("1V" .. MODE_CODE[mode()] .. "," .. Codec.enc(asOf) .. "," .. myVersion(), "WHISPER", sender)
    end)
end)

Comm.On("V", function(body, sender, channel)
    if channel ~= "WHISPER" or not who then return end
    local f = Codec.fields(body, 3)
    if not f or #f ~= 3 or not CODE_MODE[f[1]] or not Codec.dec(f[2]) or not f[3]:match("^[%w%.%-]+$") then
        return Comm.Reject("fields")
    end
    who.replies[sender] = { mode = CODE_MODE[f[1]], asOf = Codec.dec(f[2]), version = f[3] }
end)

---------------------------------------------------------------------------
-- Header filter: drop what we don't want before it is even queued.
---------------------------------------------------------------------------
Comm.accept = function(kind, sender, channel)
    local m = mode()
    if isMuted(sender) then return false end
    -- Chat-link traffic is manual on both ends (posted by one player, confirmed by the other), so it works even
    -- with automatic sharing off.
    if channel == "WHISPER" and (kind == "L" or kind == "R" or kind == "S" or kind == "E" or kind == "V") then return true end
    if m == "off" then return false end
    if channel == "GUILD" and kind == "S" and settings().lowEnd then return false end
    if kind == "H" or kind == "A" then return m == "share" end
    if kind == "O" then return true end
    return true
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------
installViews()

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function()
            realm()
            Sync.PruneGuild()
        end)
        C_Timer.After(HELLO_DELAY, function() startAsk() end)
        C_Timer.NewTicker(15, checkScan)
        C_Timer.NewTicker(5, refresh)
    end
end)
events:RegisterEvent("PLAYER_LOGIN")
