-- Encore-Stonks guild sharing: what gets shared, when, and how it is merged.
--  * Hourly scans: the first player to finish a scan in a UTC hour claims that hour on the guild channel and
--    broadcasts only the items that changed since the last shared hour. Everyone else keeps their scan to themselves.
--  * Login summary: a minute after login, out of combat, the player says HELLO; the best-placed guildmate (AFK
--    players first, then freshest data) offers, the asker accepts one offer, and the summary arrives by whisper in
--    self-contained blocks. If the sender goes away, the asker resumes from the last item it got with someone else.
--  * Received prices are kept apart from your own: guild samples in realm.guild (same format as your own samples,
--    your own hour always wins, at most one guild sample per item per 4 hours unless the price moved more than 2%),
--    summaries in realm.baseline, which fades out as your own data grows.
--  * Sharing is on by default; /stonksync receive or off turns it down.
local _, ns = ...
local Stonks = ns.Stonks
local Codec, Comm = Stonks.SyncCodec, Stonks.SyncComm
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
    -- On by default (since 2026-11-19). Saved data from the first test build said "off" without anyone choosing it,
    -- so that is switched on once; an explicit /stonksync off after this sticks.
    if sync.v ~= 2 then
        if sync.mode ~= "receive" then sync.mode = "share" end
        sync.v = 2
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
    local rec = { id = id, days = st.days }
    rec.med, rec.q25, rec.q75 = floor(st.median + 0.5), floor((st.q25 or st.median) + 0.5), floor((st.q75 or st.median) + 0.5)
    rec.a3, rec.a7, rec.a14 = floor(st.avg3 + 0.5), floor(st.avg7 + 0.5), floor(st.avg14 + 0.5)
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
    local rec = Codec.decodeSummary(text)
    if not rec then Comm.Reject(); return false end
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

    function Stonks:ItemStats(key, points)
        local own = origItemStats(self, key, points)
        local b = baselineRec(key)
        if not b then return own end
        local days = own and own.days or 0
        if days >= BASELINE_FULL_DAYS then return own end
        local base = { avg3 = b.a3, avg7 = b.a7, avg14 = b.a14, mean = b.med, sd = 0, median = b.med, q25 = b.q25, q75 = b.q75,
            days = b.days, guild = true }
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
    if not f or #f ~= 3 then return Comm.Reject() end
    local hour, count, hash = Codec.dec(f[1]), Codec.dec(f[2]), Codec.dec(f[3])
    if not hour or not count or not hash or math.abs(hour - hourNow()) > 1 then return Comm.Reject() end
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
    if not hour or not rest then return Comm.Reject() end
    if live and math.abs(hour - hourNow()) > 1 then return Comm.Reject() end
    if not live and (hour > hourNow() or hour < hourNow() - Stonks:KeepDays() * 24) then return Comm.Reject() end
    local list = Codec.decodeObs(rest)
    if not list then return Comm.Reject() end
    for _, o in ipairs(list) do
        local key = tostring(o[1])
        Sync.AddGuildSample(key, hour, o[2], o[3], sender)
        if live then lastSlot[o[1]] = { o[2], o[3] } end
    end
    Sync.Touched()
    return list
end
Sync.acceptObsMessage = acceptObsMessage

Comm.On("S", function(body, sender, channel)
    if channel == "GUILD" then
        local hour = Codec.dec(body:match("^([^:]+):") or "")
        local c = hour and claims[hour]
        if c and c.name ~= sender then return end -- only the claimer of that hour is listened to
        if not c and hour then claims[hour] = { name = sender, hash = 0 } end
        acceptObsMessage(body, sender, true)
    elseif channel == "WHISPER" and Sync.Links and Sync.Links.ExpectScan(sender, body) then
        acceptObsMessage(body, sender, false)
    end
end)

---------------------------------------------------------------------------
-- Login summary handshake
---------------------------------------------------------------------------
local ask -- our request: { since, resume, offers = {}, chosen, lastBlock, tries }
local offerTimers = {} -- [asker] = timer handle (we are waiting to offer)
local serving -- { asker }
local pendingOffers = {} -- [asker] = { since, resume, at }: offers we made and wait to hear back on

local function startAsk(resume)
    if mode() == "off" or not IsInGuild() then return end
    if Comm.Busy() then C_Timer.After(30, function() startAsk(resume) end); return end
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
            ask.tries = ask.tries + 1
            local wait = RETRY[ask.tries]
            if wait then C_Timer.After(wait, function() startAsk() end) else ask = nil end
        end
    end)
end
Sync.StartAsk = startAsk

local function pickOffer()
    if not ask or ask.chosen or #ask.offers == 0 then return end
    table.sort(ask.offers, function(a, b)
        if a.afk ~= b.afk then return a.afk end
        if a.asOf ~= b.asOf then return a.asOf > b.asOf end
        return a.name < b.name
    end)
    local best = ask.offers[1]
    ask.chosen, ask.asOf, ask.lastBlock = best.name, best.asOf, Comm.now()
    Comm.Send("1A" .. best.name, "GUILD")
    local function watch()
        if not ask or ask.chosen ~= best.name then return end
        if Comm.now() - ask.lastBlock > BLOCK_TIMEOUT then
            -- Sender went quiet (logged off, disconnected): keep what we have and ask someone else to continue.
            local resume = ask.resume
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
    if channel ~= "GUILD" or not sharing() then return end
    local f = Codec.fields(body, 2)
    local since, resume = f and Codec.dec(f[1]), f and Codec.dec(f[2])
    if not since or not resume then return Comm.Reject() end
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
        Comm.Send("1O" .. sender .. "," .. Codec.enc(asOf) .. "," .. (afk and "1" or "0"), "GUILD")
        pendingOffers[sender] = { since = since, resume = resume, at = Comm.now() }
    end)
end)

-- An offer: if it is for us, collect it; if it is for someone we were about to answer, stand down.
Comm.On("O", function(body, sender, channel)
    if channel ~= "GUILD" then return end
    local f = Codec.fields(body, 3)
    if not f or #f ~= 3 then return Comm.Reject() end
    local asker, asOf = Codec.cleanName(f[1]), Codec.dec(f[2])
    if not asker or not asOf or (f[3] ~= "0" and f[3] ~= "1") then return Comm.Reject() end
    if asker == Comm.Me() then
        if ask and not ask.chosen then
            ask.offers[#ask.offers + 1] = { name = sender, asOf = asOf, afk = f[3] == "1" }
            if #ask.offers == 1 then C_Timer.After(2, pickOffer) end
        end
    elseif offerTimers[asker] then
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

Comm.On("A", function(body, sender, channel)
    if channel ~= "GUILD" then return end
    local chosen = Codec.cleanName(body)
    if not chosen then return Comm.Reject() end
    local p = pendingOffers[sender]
    if p then
        pendingOffers[sender] = nil
        if chosen == Comm.Me() and not serving then serve(sender, p.since, p.resume) end
    end
end)

Comm.On("Y", function(body, sender, channel)
    if channel ~= "WHISPER" or not ask or ask.chosen ~= sender then return end
    ask.lastBlock = Comm.now()
    for text in (body .. ";"):gmatch("([^;]*);") do
        if Sync.AddSummary(text, sender) then
            local id = Codec.dec(text:match("^([^,]+)") or "")
            if id and id >= ask.resume then ask.resume = id + 1 end
        end
    end
    Sync.Touched()
end)

Comm.On("Z", function(_, sender, channel)
    if channel ~= "WHISPER" or not ask or ask.chosen ~= sender then return end
    local r = realm()
    r.sync.since, r.sync.from, r.sync.at = ask.asOf, sender, time()
    ask = nil
end)

---------------------------------------------------------------------------
-- Header filter: drop what we don't want before it is even queued.
---------------------------------------------------------------------------
Comm.accept = function(kind, sender, channel)
    local m = mode()
    if isMuted(sender) then return false end
    -- Chat-link traffic is manual on both ends (posted by one player, confirmed by the other), so it works even
    -- with automatic sharing off.
    if channel == "WHISPER" and (kind == "L" or kind == "R" or kind == "S" or kind == "E") then return true end
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
