-- Encore-Stonks guild sharing: the sync history, a log of what you received, when, and from whom.
-- One entry per delivery: an hourly guild scan, a login summary, a shared item or a shared scan (chat link).
-- Messages of one delivery add up in the same entry; it is marked done when the sender's end message arrives.
-- Saved per realm in realm.syncLog, newest last, at most MAX_ENTRIES entries and KEEP_DAYS days.
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

local function entries()
    local r = Stonks.realmData
    if not r then return nil end
    if type(r.syncLog) ~= "table" then r.syncLog = {} end
    return r.syncLog
end
Log.Entries = function() return entries() or {} end

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
local function findOpen(list, from, kind, match)
    for i = #list, math.max(1, #list - OPEN_LOOKBACK), -1 do
        local e = list[i]
        if type(e) == "table" and e.from == from and e.kind == kind and e.match == match and not e.done
            and time() - (tonumber(e.last) or 0) < STALE then return e end
    end
    return nil
end

-- Adds to (or starts) the entry for one delivery. fields: got, kept (numbers to add), hour, id, med, done.
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
    if fields.stopped then e.stopped = true end
    if fields.expected then e.expected = fields.expected end
    changed()
end

function Log.Clear()
    local list = entries()
    if list then wipe(list) end
    changed()
end
