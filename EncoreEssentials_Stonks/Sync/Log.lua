-- Encore-Stonks guild sharing: the sync history, a log of what you received and what you sent, when, and with whom.
-- One entry per delivery: an hourly guild scan, a login summary, a shared item or a shared scan (chat link).
-- Messages of one delivery add up in the same entry; it is marked done when the end message arrives (or goes out).
-- Saved per realm, newest last, at most MAX_ENTRIES entries and KEEP_DAYS days each:
--   realm.syncLog   what you received (entries have .from)
--   realm.syncSent  what you sent (entries have .to: "Guild" for broadcasts, the guildmate for whispers)
--   realm.syncBytes = { r = { ["2026-11-22"] = bytes }, s = { ... } }: every addon message of ours per day, both
--                     directions, control messages included (the stat cards and daily bars of the history page)
-- Sizes are the addon message text in bytes, as it goes over the wire (already compressed by the encoding).
local _, ns = ...
local Stonks = ns.Stonks
local Codec = Stonks.SyncCodec
local Log = {}
Stonks.SyncLog = Log

local MAX_ENTRIES = 300
local KEEP_DAYS = 30
local OPEN_LOOKBACK = 40 -- how many recent entries are searched for an open delivery to add to
local STALE = 600 -- a delivery quiet this long (sender gone, or a reload) is not added to any more

Log.KINDS = {
    hourly = "Hourly scan",
    summary = "Login summary",
    item = "Shared item",
    scan = "Shared scan",
}

local listeners = {}
function Log.OnChange(fn) listeners[#listeners + 1] = fn end
local function changed()
    for _, fn in ipairs(listeners) do pcall(fn) end
end

local LIST_KEY = { rec = "syncLog", sent = "syncSent" }
local BYTES_KEY = { rec = "r", sent = "s" }

-- dir: "rec" (default) or "sent"
local function entries(dir)
    local r = Stonks.realmData
    if not r then return nil end
    local k = LIST_KEY[dir or "rec"] or "syncLog"
    if type(r[k]) ~= "table" then r[k] = {} end
    return r[k]
end
Log.Entries = function(dir) return entries(dir) or {} end

---------------------------------------------------------------------------
-- Bytes per day
---------------------------------------------------------------------------
local function dayKey(t) return date("%Y-%m-%d", t or time()) end
Log.DayKey = dayKey

local function byteDays(dir)
    local r = Stonks.realmData
    if not r then return nil end
    if type(r.syncBytes) ~= "table" then r.syncBytes = {} end
    local k = BYTES_KEY[dir] or "r"
    if type(r.syncBytes[k]) ~= "table" then r.syncBytes[k] = {} end
    return r.syncBytes[k]
end

local function countBytes(dir, n)
    local days = byteDays(dir)
    if not days or not n or n <= 0 then return end
    local key = dayKey()
    if not days[key] then
        -- A new day: drop days older than the history keeps (ISO dates sort as text).
        local cutoff = dayKey(time() - (KEEP_DAYS + 1) * 86400)
        for k in pairs(days) do
            if type(k) ~= "string" or k < cutoff then days[k] = nil end
        end
    end
    days[key] = (tonumber(days[key]) or 0) + n
end

-- Bytes in the last `days` calendar days (1 = today), for "rec" or "sent".
function Log.Bytes(dir, days)
    local list = byteDays(dir)
    if not list then return 0 end
    local total, now = 0, time()
    for i = 0, (days or 1) - 1 do
        total = total + (tonumber(list[dayKey(now - i * 86400)]) or 0)
    end
    return total
end

-- Bytes of one calendar day, i days ago (0 = today), and that day's date.
function Log.DayBytes(dir, i)
    local list = byteDays(dir)
    local t = time() - (i or 0) * 86400
    return list and tonumber(list[dayKey(t)]) or 0, t
end

local function trim(list)
    local cutoff = time() - KEEP_DAYS * 86400
    local first = 1
    while list[first] and (type(list[first]) ~= "table" or (tonumber(list[first].t) or 0) < cutoff) do first = first + 1 end
    first = math.max(first, #list - MAX_ENTRIES + 1)
    if first > 1 then
        local keep = {}
        for i = first, #list do keep[#keep + 1] = list[i] end
        wipe(list)
        for i, e in ipairs(keep) do list[i] = e end
    end
end

-- The open entry for this delivery (same sender, kind and match key), or nil.
local function findOpen(list, from, kind, match, field)
    field = field or "from"
    for i = #list, math.max(1, #list - OPEN_LOOKBACK), -1 do
        local e = list[i]
        if type(e) == "table" and e[field] == from and e.kind == kind and e.match == match and not e.done
            and time() - (tonumber(e.last) or 0) < STALE then return e end
    end
    return nil
end

-- Size of the received message being handled right now (0 outside a message handler, e.g. from a timer).
local function currentSize()
    local Comm = Stonks.SyncComm
    return Comm and Comm.CurrentSize and Comm.CurrentSize() or 0
end

-- Received: adds to (or starts) the entry for one delivery. fields: got, kept (numbers to add), hour, id, med, done.
-- match tells deliveries of the same sender and kind apart (the scan hour, the login request...).
function Log.Add(kind, from, match, fields)
    local list = entries()
    if not list or not Log.KINDS[kind] or type(from) ~= "string" then return nil end
    from = Codec.cleanName(from) or Codec.safeText(from)
    fields = fields or {}
    local now = time()
    local e = match ~= nil and findOpen(list, from, kind, match) or nil
    if not e then
        e = { t = now, from = from, kind = kind, match = match, got = 0, kept = 0 }
        list[#list + 1] = e
        trim(list)
    end
    e.last = now
    e.bytes = (e.bytes or 0) + currentSize()
    e.got = e.got + (fields.got or 0)
    e.kept = e.kept + (fields.kept or 0)
    if fields.hour then e.hour = fields.hour end
    if fields.id then e.id = fields.id end
    if fields.med then e.med = fields.med end
    if fields.expected then e.expected = fields.expected end
    if fields.done then e.done = true; e.match = nil end
    if fields.stopped then e.stopped = true; e.done = true; e.match = nil end
    changed()
    return e
end

-- Closes an open delivery (end message received, or the sender went quiet).
function Log.Finish(kind, from, match, fields)
    local list = entries()
    if not list then return end
    from = Codec.cleanName(from) or from
    local e = findOpen(list, from, kind, match)
    if not e then return end
    fields = fields or {}
    e.done, e.match, e.last = true, nil, time()
    e.bytes = (e.bytes or 0) + currentSize()
    if fields.stopped then e.stopped = true end
    if fields.silent then e.silent = true end
    if fields.expected then e.expected = fields.expected end
    changed()
end

---------------------------------------------------------------------------
-- Sent: Comm calls Log.Sent for every message that actually went out, and the entries are worked out from the
-- message type, so the sending code needs no changes.
---------------------------------------------------------------------------
local function addSent(kind, to, match, fields, bytes)
    local list = entries("sent")
    if not list then return nil end
    local now = time()
    local e = match ~= nil and findOpen(list, to, kind, match, "to") or nil
    if not e then
        if fields.finish then
            -- An end message with nothing before it (an hourly scan with no changed prices): log it as done.
            e = { t = now, to = to, kind = kind, got = 0 }
        else
            e = { t = now, to = to, kind = kind, match = match, got = 0 }
        end
        list[#list + 1] = e
        trim(list)
    end
    e.last = now
    e.bytes = (e.bytes or 0) + bytes
    e.got = e.got + (fields.got or 0)
    if fields.hour then e.hour = fields.hour end
    if fields.id then e.id = fields.id end
    if fields.med then e.med = fields.med end
    if fields.expected then e.expected = fields.expected end
    if fields.finish or fields.done then e.done = true; e.match = nil end
    return e
end

function Log.Sent(msg, channel, target)
    if type(msg) ~= "string" then return end
    local bytes = #msg
    countBytes("sent", bytes)
    local kind = msg:sub(2, 2)
    local to = channel == "GUILD" and "Guild" or (Codec.cleanName(target or "") or Codec.safeText(target or "?"))
    local logKind = channel == "GUILD" and "hourly" or "scan"
    if kind == "S" then
        local hs, rest = msg:match("^..([^:]+):(.*)$")
        if not hs then return end
        local list = Codec.decodeObs(rest)
        addSent(logKind, to, hs, { got = list and #list or 0, hour = Codec.dec(hs) }, bytes)
    elseif kind == "E" then
        local hs, cs = msg:match("^..([^,]+),(.*)$")
        if not hs then return end
        addSent(logKind, to, hs, { finish = true, expected = Codec.dec(cs or ""), hour = Codec.dec(hs) }, bytes)
    elseif kind == "Y" then
        local _, semis = msg:gsub(";", "")
        addSent("summary", to, "login", { got = #msg > 2 and semis + 1 or 0 }, bytes)
    elseif kind == "Z" then
        addSent("summary", to, "login", { finish = true, expected = Codec.dec(msg:sub(3)) }, bytes)
    elseif kind == "R" then
        local rec = Codec.decodeSummary(msg:sub(3))
        addSent("item", to, nil, { got = 1, done = true, id = rec and rec.id, med = rec and rec.med }, bytes)
    else
        return -- control messages (claims, hellos, offers...) only count in the daily bytes
    end
    changed()
end

-- Every message of ours that arrived (before the work queue reads it), for the daily bytes.
function Log.Received(bytes)
    countBytes("rec", bytes)
end

-- Empties one tab: its deliveries and its daily bytes.
function Log.Clear(dir)
    dir = dir or "rec"
    local list = entries(dir)
    if list then wipe(list) end
    local days = byteDays(dir)
    if days then wipe(days) end
    changed()
end
