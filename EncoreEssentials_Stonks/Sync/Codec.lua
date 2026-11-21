-- Encore-Stonks guild sharing: wire format.
-- Everything that travels between players is plain numbers written in a 64-character alphabet, so a message can
-- only ever turn into numbers. Nothing received is run, loaded as code or turned into arbitrary tables: each field
-- is read with a fixed pattern and range-checked, and one bad field throws out the whole message.
local _, ns = ...
local Stonks = ns.Stonks
local Codec = {}
Stonks.SyncCodec = Codec

local floor = math.floor
local ALPHA = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz*="
local VALUE = {}
for i = 1, #ALPHA do VALUE[ALPHA:byte(i)] = i - 1 end
Codec.ALPHA = ALPHA
Codec.VERSION = "1"

-- Limits for everything we accept.
Codec.MAX_ITEM_ID = 1000000
Codec.MAX_PRICE = 100000000000 -- 10 million gold in copper
Codec.MAX_QTY = 1000000
Codec.MAX_DAYS = 100000
Codec.MAX_COUNT = 100000
Codec.MAX_SUM = 100000000 -- |sum of log ratios x 1000|
Codec.MAX_NAME = 48

function Codec.enc(n)
    n = floor(n)
    if n <= 0 then return "0" end
    local out = {}
    while n > 0 do
        local r = n % 64
        out[#out + 1] = ALPHA:sub(r + 1, r + 1)
        n = (n - r) / 64
    end
    local s = {}
    for i = #out, 1, -1 do s[#s + 1] = out[i] end
    return table.concat(s)
end

-- Unsigned number, or nil when the text is empty, too long or has any character outside the alphabet.
function Codec.dec(s)
    if type(s) ~= "string" then return nil end
    local len = #s
    if len == 0 or len > 8 then return nil end
    local n = 0
    for i = 1, len do
        local v = VALUE[s:byte(i)]
        if not v then return nil end
        n = n * 64 + v
    end
    return n
end

function Codec.encSigned(n)
    n = floor(n + 0.5)
    if n < 0 then return "-" .. Codec.enc(-n) end
    return Codec.enc(n)
end

function Codec.decSigned(s)
    if type(s) ~= "string" then return nil end
    if s:sub(1, 1) == "-" then
        local v = Codec.dec(s:sub(2))
        return v and -v or nil
    end
    return Codec.dec(s)
end

local function inRange(v, lo, hi) return v and v >= lo and v <= hi end

-- A player name from a message field: no separators, escape codes or control characters, not too long.
function Codec.cleanName(s)
    if type(s) ~= "string" or #s == 0 or #s > Codec.MAX_NAME then return nil end
    -- WoW Forever names have a first and last name ("Berya Ebonlocke"), so single spaces inside are fine; field
    -- separators, escape codes, control characters, and spaces at the ends or doubled are not.
    if s:find("[%c|,:;]") or s:find("^ ") or s:find(" $") or s:find("  ", 1, true) then return nil end
    return s
end

-- Text that is safe to show in chat or the window: escape codes removed.
function Codec.safeText(s)
    s = tostring(s or "")
    s = s:gsub("|", "")
    return s:sub(1, 80)
end

---------------------------------------------------------------------------
-- Scan observations: "id,price,qty;id,price,qty;..." with each id written as the gap from the one before it in
-- the same message (the first one in full). Each message stands alone, so a lost message loses only its items.
---------------------------------------------------------------------------
function Codec.encodeObs(prevId, id, price, qty)
    return Codec.enc(id - prevId) .. "," .. Codec.enc(price) .. "," .. Codec.enc(qty) .. ";"
end

-- Returns a list of { id, price, qty } or nil (and a reason) if anything is wrong.
function Codec.decodeObs(body)
    if type(body) ~= "string" or #body == 0 or #body > 255 then return nil, "size" end
    if body:find("[^0-9A-Za-z*=,;]") then return nil, "chars" end
    local list, id, pos = {}, 0, 1
    while pos <= #body do
        local s, e, g, p, q = body:find("^([^,;]+),([^,;]+),([^,;]+);", pos)
        if not s then return nil, "format" end
        local gap, price, qty = Codec.dec(g), Codec.dec(p), Codec.dec(q)
        if not gap or (#list > 0 and gap < 1) then return nil, "id" end
        id = id + gap
        if not inRange(id, 1, Codec.MAX_ITEM_ID) then return nil, "id" end
        if not inRange(price, 1, Codec.MAX_PRICE) then return nil, "price" end
        if not inRange(qty, 0, Codec.MAX_QTY) then return nil, "qty" end
        list[#list + 1] = { id, price, qty }
        pos = e + 1
    end
    return list
end

---------------------------------------------------------------------------
-- Item summaries (past data): "id,median,q25,q75,avg3,avg7,avg14,days,buckets" where buckets is a "."-separated
-- list of <index><count>/<sum>: index is one alphabet character, 0-6 = Monday-Sunday, 7-30 = hour 0-23; count is
-- the number of samples and sum the sum of log(price / normal) x 1000 (signed).
---------------------------------------------------------------------------
local SUMMARY_FIELDS = { "med", "q25", "q75", "a3", "a7", "a14" }
Codec.SUMMARY_FIELDS = SUMMARY_FIELDS

-- rec = { id, med, q25, q75, a3, a7, a14, days, week = {[1..7] = {n, sum}}, hour = {[0..23] = {n, sum}} }
function Codec.encodeSummary(rec)
    local parts = { Codec.enc(rec.id) }
    for _, f in ipairs(SUMMARY_FIELDS) do parts[#parts + 1] = Codec.enc(rec[f] or 0) end
    parts[#parts + 1] = Codec.enc(rec.days or 0)
    local b = {}
    for i = 1, 7 do
        local x = rec.week and rec.week[i]
        if x and x.n > 0 then b[#b + 1] = ALPHA:sub(i, i) .. Codec.enc(x.n) .. "/" .. Codec.encSigned(x.sum * 1000) end
    end
    for h = 0, 23 do
        local x = rec.hour and rec.hour[h]
        if x and x.n > 0 then b[#b + 1] = ALPHA:sub(h + 8, h + 8) .. Codec.enc(x.n) .. "/" .. Codec.encSigned(x.sum * 1000) end
    end
    parts[#parts + 1] = table.concat(b, ".")
    return table.concat(parts, ",")
end

-- One record, strictly checked. Returns the record or nil and a reason.
function Codec.decodeSummary(str)
    if type(str) ~= "string" or #str == 0 or #str > 600 then return nil, "size" end
    if str:find("[^0-9A-Za-z*=,%./%-]") then return nil, "chars" end
    local f = {}
    for v in (str .. ","):gmatch("([^,]*),") do f[#f + 1] = v end
    if #f ~= 9 then return nil, "format" end
    local rec = { id = Codec.dec(f[1]), week = {}, hour = {} }
    if not inRange(rec.id, 1, Codec.MAX_ITEM_ID) then return nil, "id" end
    for i, name in ipairs(SUMMARY_FIELDS) do
        local v = Codec.dec(f[i + 1])
        if not inRange(v, 1, Codec.MAX_PRICE) then return nil, name end
        rec[name] = v
    end
    rec.days = Codec.dec(f[8])
    if not inRange(rec.days, 1, Codec.MAX_DAYS) then return nil, "days" end
    if not (rec.q25 <= rec.med and rec.med <= rec.q75) then return nil, "order" end
    for i = 1, 7 do rec.week[i] = { n = 0, sum = 0 } end
    for h = 0, 23 do rec.hour[h] = { n = 0, sum = 0 } end
    if f[9] ~= "" then
        local seen = {}
        for entry in (f[9] .. "."):gmatch("([^%.]*)%.") do
            local idx, n, s = entry:match("^([0-9A-Za-z*=])([0-9A-Za-z*=]+)/(%-?[0-9A-Za-z*=]+)$")
            if not idx then return nil, "bucket" end
            local i = VALUE[idx:byte()]
            local count, sum = Codec.dec(n), Codec.decSigned(s)
            if i > 30 or seen[i] or not inRange(count, 1, Codec.MAX_COUNT) or not inRange(sum, -Codec.MAX_SUM, Codec.MAX_SUM) then
                return nil, "bucket"
            end
            seen[i] = true
            local target = i < 7 and rec.week[i + 1] or rec.hour[i - 7]
            target.n, target.sum = count, sum / 1000
        end
    end
    return rec
end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
-- Deterministic hash for tie-breaks (same on every client).
function Codec.hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 16777216 end
    return h
end

-- Splits a header field list "a,b,c" into plain strings (at most n fields).
function Codec.fields(s, n)
    local out = {}
    for v in ((s or "") .. ","):gmatch("([^,]*),") do
        out[#out + 1] = v
        if #out > n then return nil end
    end
    return out
end
