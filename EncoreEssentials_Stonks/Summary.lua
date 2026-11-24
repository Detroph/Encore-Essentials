-- Encore-Stonks: a small saved summary per item (last price, 7- and 14-day averages, days with a price), so the
-- browser can list and sort thousands of items without working out every item's history when it opens
-- (Det, 2026-11-21: opening Stonks froze a few frames).
--
-- The full history is untouched; the summary is only a cache of Stonks:ItemStats. Each entry remembers a cheap
-- signature of the data it was computed from (lengths of the item's saved strings, guild data, Auctionator's days,
-- this hour's sample, the Auctionator setting) and the day it was computed. When the signature no longer matches
-- (new prices, a guild sync, folding, Auctionator dropping an old day) the old values still show and the item is
-- queued; a background worker recomputes queued items a few milliseconds per frame. After login the worker also
-- checks every item once.
--
-- Saved as realms[realm].sum[key] = "signature|day|last|avg7|avg14|days", numbers in base 36 (copper rounded to
-- whole numbers; saved-data version 3, Recorder.lua). Only items asked for (browser rows, tooltips) are kept as
-- tables, in a weak cache the garbage collector empties once nothing shows them (Det, 2026-11-23: one table per
-- item for 33,000 items was about 15 MB that never went away).
local _, ns = ...
local Stonks = ns.Stonks

local FRAME_BUDGET_MS = 4 -- work per frame, so the game never stalls (8 while the browser is open)
local WARMUP_DELAY = 20   -- seconds after login (folding old samples starts at 10)

local mem = setmetatable({}, { __mode = "v" }) -- [key] = { sig, day, last, avg7, avg14, days }, weak
local queue, queued = {}, {}
local worker
local listeners = {}

local function today() return math.floor(time() / 86400) end
local b36 = Stonks.b36

local function signature(key)
    local r = Stonks.realmData
    local a = r and r.items[key]
    local g = r and r.agg[key]
    local s = r and r.stat[key]
    local gu = r and r.guild and r.guild[key]
    local ba = r and r.baseline and r.baseline[key]
    local p = Stonks:Pending(key)
    -- Auctionator's days for the item (it adds and drops days on its own): how many, and the newest.
    local ac, an = 0, 0
    local au = _G.Auctionator
    local entry = Stonks:Settings().useAuctionator and au and au.Database and type(au.Database.db) == "table" and au.Database.db[key]
    if type(entry) == "table" and type(entry.h) == "table" then
        for d in pairs(entry.h) do
            ac = ac + 1
            d = tonumber(d) or 0
            if d > an then an = d end
        end
    end
    return b36(ac) .. "-" .. b36(an) .. "." .. b36(a and #a or 0) .. "." .. b36(g and #g or 0) .. "." .. b36(s and #s or 0) .. "." .. b36(gu and #gu or 0)
        .. "." .. b36(ba and #ba or 0) .. "." .. (p and (b36(p[1]) .. "-" .. b36(p[2])) or "")
        .. "." .. (Stonks:Settings().useAuctionator and 1 or 0)
end

local function round(v) return v and math.floor(v + 0.5) or nil end
local function num(s) return s ~= "" and tonumber(s, 36) or nil end
local function enc(v) return v and b36(v) or "" end

local function loadEntry(key)
    local e = mem[key]
    if e then return e end
    local r = Stonks.realmData
    local str = r and r.sum and r.sum[key]
    if type(str) == "string" then
        local sig, day, last, avg7, avg14, days = strsplit("|", str)
        e = { sig = sig, day = tonumber(day, 36), last = num(last), avg7 = num(avg7), avg14 = num(avg14), days = tonumber(days or "", 36) or 0 }
        mem[key] = e
    end
    return e
end

-- Whether the saved summary is up to date, read straight from the saved string (no table).
local function savedFresh(key)
    local r = Stonks.realmData
    local str = r and r.sum and r.sum[key]
    if type(str) ~= "string" then return false end
    local sig = signature(key)
    return str:find(sig, 1, true) == 1 and str:byte(#sig + 1) == 124 -- "|"
end

-- Works out and saves an item's summary. Returns it as a table only when asked (want) or when something is showing
-- the item already; the background refresh of thousands of items only writes the saved string.
local function compute(key, want)
    local sig = signature(key)
    local st = Stonks:ItemStats(key)
    local day = today()
    local last, avg7, avg14, days = round(st and st.last), round(st and st.avg7), round(st and st.avg14), st and st.days or 0
    local r = Stonks.realmData
    if r then
        r.sum = r.sum or {}
        r.sum[key] = sig .. "|" .. b36(day) .. "|" .. enc(last) .. "|" .. enc(avg7) .. "|" .. enc(avg14) .. "|" .. b36(days)
    end
    if not want and not mem[key] then return nil end
    local e = { sig = sig, day = day, last = last, avg7 = avg7, avg14 = avg14, days = days }
    mem[key] = e
    return e
end

-- Up to date when the data it came from is unchanged (the signature covers everything ItemStats reads, so the
-- summaries of items without new prices are not worked out again every day).
local function fresh(key, e)
    return e and e.sig == signature(key)
end

local function finish()
    if worker then worker:Cancel(); worker = nil end
    local cbs = listeners
    listeners = {}
    for _, cb in ipairs(cbs) do pcall(cb) end
    if Stonks.OnSummaries then Stonks:OnSummaries() end
end

local function startWorker()
    if worker or #queue == 0 then return end
    worker = C_Timer.NewTicker(0, function()
        local t0 = debugprofilestop()
        while #queue > 0 do
            local key = table.remove(queue)
            queued[key] = nil
            if not savedFresh(key) then compute(key) end
            local budget = (Stonks.BrowserShown and Stonks:BrowserShown()) and FRAME_BUDGET_MS * 2 or FRAME_BUDGET_MS
            if debugprofilestop() - t0 > budget then return end
        end
        finish()
    end)
end

local function enqueue(key)
    if queued[key] then return end
    queued[key] = true
    queue[#queue + 1] = key
end

-- The item's summary as last worked out (it may be a little out of date: if so it is queued for a refresh), or nil
-- when there is none yet. Fields: last, avg7, avg14, days.
function Stonks:Summary(key)
    key = tostring(key)
    local e = loadEntry(key)
    if not fresh(key, e) then
        enqueue(key)
        startWorker()
    end
    return e
end

-- Works out the summary right now (the item the player clicked, for instance).
function Stonks:SummaryNow(key)
    key = tostring(key)
    local e = loadEntry(key)
    if fresh(key, e) then return e end
    return compute(key, true)
end

-- True while summaries are being refreshed in the background.
function Stonks:SummariesBusy() return worker ~= nil end

-- Calls fn once the queued summaries are done (right away when nothing is queued).
function Stonks:WhenSummariesDone(fn)
    if not worker and #queue == 0 then return fn() end
    listeners[#listeners + 1] = fn
end

-- Warm-up: queue every item once, then drop saved summaries of items that are gone.
function Stonks:WarmSummaries()
    local r = self.realmData
    if not r then return end
    r.sum = r.sum or {}
    local keys = self:AllKeys()
    local alive = {}
    for _, key in ipairs(keys) do
        alive[key] = true
        if not savedFresh(key) then enqueue(key) end
    end
    for key in pairs(r.sum) do
        if not alive[key] then r.sum[key] = nil; mem[key] = nil end
    end
    startWorker()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    C_Timer.After(WARMUP_DELAY, function()
        if not InCombatLockdown() then Stonks:WarmSummaries() else
            C_Timer.After(30, function() Stonks:WarmSummaries() end)
        end
    end)
end)
