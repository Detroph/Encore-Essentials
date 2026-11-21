-- Encore-Stonks: a small saved summary per item (last price, 7- and 14-day averages, days with a price), so the
-- browser can list and sort thousands of items without working out every item's history when it opens
-- (Det, 2026-11-21: opening Stonks froze a few frames).
--
-- The full history is untouched; the summary is only a cache of Stonks:ItemStats. Each entry remembers a cheap
-- signature of the data it was computed from (lengths of the item's saved strings, this hour's sample, the
-- Auctionator setting) and the day it was computed. When either no longer matches (new prices, a guild sync,
-- folding, a new day) the old values still show and the item is queued; a background worker recomputes queued
-- items a few milliseconds per frame. After login the worker also warms every item up once.
--
-- Saved as realms[realm].sum[key] = "signature|day|last|avg7|avg14|days" (copper rounded to whole numbers).
local _, ns = ...
local Stonks = ns.Stonks

local FRAME_BUDGET_MS = 4 -- work per frame, so the game never stalls (8 while the browser is open)
local WARMUP_DELAY = 20   -- seconds after login (folding old samples starts at 10)

local mem = {}            -- [key] = { sig, day, last, avg7, avg14, days }
local queue, queued = {}, {}
local worker
local listeners = {}

local function today() return math.floor(time() / 86400) end

local function signature(key)
    local r = Stonks.realmData
    local a = r and r.items[key]
    local g = r and r.agg[key]
    local s = r and r.stat[key]
    local p = Stonks:Pending(key)
    return (a and #a or 0) .. "." .. (g and #g or 0) .. "." .. (s and #s or 0) .. "."
        .. (p and (p[1] .. "-" .. p[2]) or "") .. "." .. (Stonks:Settings().useAuctionator and 1 or 0)
end

local function round(v) return v and math.floor(v + 0.5) or nil end
local function num(s) return s ~= "" and tonumber(s) or nil end

local function loadEntry(key)
    local e = mem[key]
    if e ~= nil then return e or nil end
    local r = Stonks.realmData
    local str = r and r.sum and r.sum[key]
    if type(str) == "string" then
        local sig, day, last, avg7, avg14, days = strsplit("|", str)
        e = { sig = sig, day = tonumber(day), last = num(last), avg7 = num(avg7), avg14 = num(avg14), days = tonumber(days) or 0 }
    end
    mem[key] = e or false
    return e
end

local function compute(key)
    local sig = signature(key)
    local st = Stonks:ItemStats(key)
    local e = {
        sig = sig, day = today(),
        last = round(st and st.last), avg7 = round(st and st.avg7), avg14 = round(st and st.avg14), days = st and st.days or 0,
    }
    mem[key] = e
    local r = Stonks.realmData
    if r then
        r.sum = r.sum or {}
        r.sum[key] = table.concat({ sig, e.day, e.last or "", e.avg7 or "", e.avg14 or "", e.days }, "|")
    end
    return e
end

local function fresh(key, e)
    return e and e.day == today() and e.sig == signature(key)
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
            if not fresh(key, loadEntry(key)) then compute(key) end
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
    return compute(key)
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
        if not fresh(key, loadEntry(key)) then enqueue(key) end
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
