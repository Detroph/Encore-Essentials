-- Encore-Stonks guild sharing: chat links, WeakAuras style.
-- "/stonksync link item <item>" or "/stonksync link scan" puts plain text like [Stonks: Black Lotus #i13468] into
-- the chat box (the server strips custom link codes, so plain text is what travels). Players with Stonks see it as
-- a clickable link; clicking asks to confirm, and only then is the data requested from the poster by whisper.
-- Anyone can share this way, at any rank, and nothing is ever imported without that click and confirmation.
local _, ns = ...
local Stonks = ns.Stonks
local Codec, Comm, Sync, Log = Stonks.SyncCodec, Stonks.SyncComm, Stonks.Sync, Stonks.SyncLog
local Links = {}
Sync.Links = Links

local P = "|cffd9a066Encore-Stonks|r "
local POSTED_FOR = 3600 -- we answer requests for a link we posted for an hour
local ASK_GAP = 10 -- one answer per asker every 10 seconds
local IMPORT_FOR = 300

local posted = {} -- [kind .. arg] = time we posted it
local answered = {} -- [asker] = time
local expecting = {} -- [sender] = { kind, arg, untilTime }

-- Puts the link text in the chat box (guild chat when the box wasn't already open), ready to send with Enter.
local function insertChat(text)
    local box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if box then box:Insert(text); return end
    if not ChatFrame_OpenChat then return end
    ChatFrame_OpenChat(text)
    box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if box and IsInGuild() then
        box:SetAttribute("chatType", "GUILD")
        if ChatEdit_UpdateHeader then ChatEdit_UpdateHeader(box) end
    end
end

function Links.PostItem(input)
    local id = tonumber(input) or tonumber((input or ""):match("item:(%d+)"))
    if not id then return print(P .. "usage: /stonksync link item <shift-click an item>") end
    if not Sync.BuildSummary(tostring(id)) then return print(P .. "you have no price history for that item yet.") end
    local name = Codec.safeText((GetItemInfo(id)) or ("item " .. id)):gsub("[%[%]#]", "")
    posted["i" .. id] = time()
    insertChat("[Stonks: " .. name .. " #i" .. id .. "]")
end

-- Our own samples for one hour: { id, price, qty }, sorted.
local function ownScan(hour)
    local r = Stonks.realmData
    local list, b = {}, Stonks.b36(hour) .. ":"
    for key, str in pairs(r.items) do
        local id = tonumber(key)
        if id and math.floor(id) == id then
            local p, q = str:match("^" .. b .. "(%w+):(%w+);")
            if not p then p, q = str:match(";" .. b .. "(%w+):(%w+);") end
            if p then list[#list + 1] = { id, tonumber(p, 36), tonumber(q, 36) } end
        end
    end
    for key, s in pairs(Stonks:PendingKeys()) do
        local id = tonumber(key)
        if id and math.floor(id) == id and s[1] == hour then list[#list + 1] = { id, s[2], s[3] } end
    end
    table.sort(list, function(x, y) return x[1] < y[1] end)
    return list
end
Links.ownScan = ownScan

function Links.PostScan()
    local r = Stonks.realmData
    if not r or not r.last then return print(P .. "you have no scan to share yet.") end
    local hour = math.floor(r.last / 3600)
    local count = #ownScan(hour)
    if count == 0 then return print(P .. "you have no scan to share yet.") end
    posted["s" .. hour] = time()
    insertChat(("[Stonks: scan %s, %d items #s%s]"):format(date("%d %b %H:00", hour * 3600), count, Codec.enc(hour)))
end

---------------------------------------------------------------------------
-- Turning the text into a link for players who have Stonks
---------------------------------------------------------------------------
local PATTERN = "%[Stonks: ([^%]#|]-) #([is])([0-9A-Za-z*=]+)%]"

local function filter(_, _, msg, author, ...)
    if type(msg) ~= "string" or not msg:find("[Stonks: ", 1, true) then return false end
    local sender = Codec.cleanName(Comm.Ambiguate(author))
    if not sender then return false end
    local out = msg:gsub(PATTERN, function(label, kind, arg)
        return ("|Hgarrmission:encorestonks:%s:%s:%s|h|cffeb9339[Stonks: %s]|r|h"):format(kind, arg, sender, Codec.safeText(label))
    end)
    return false, out, author, ...
end

for _, event in ipairs({ "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL" }) do
    ChatFrame_AddMessageEventFilter(event, filter)
end

StaticPopupDialogs["ENCORE_STONKS_IMPORT"] = {
    text = "Import Encore-Stonks prices from %s?\n\n%s",
    button1 = "Import",
    button2 = CANCEL or "Cancel",
    OnAccept = function(_, data) Links.Request(data.sender, data.kind, data.arg) end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function Links.Click(link)
    local kind, arg, sender = link:match("^garrmission:encorestonks:([is]):([0-9A-Za-z*=]+):([^:]+)$")
    sender = Codec.cleanName(sender)
    if not kind or not sender then return end
    if sender == Comm.Me() then return print(P .. "that is your own link.") end
    local what
    if kind == "i" then
        local id = tonumber(arg)
        if not id then return end
        what = ("Price history for %s (one or two messages)."):format(Codec.safeText((GetItemInfo(id)) or ("item " .. id)))
    else
        local hour = Codec.dec(arg)
        if not hour then return end
        what = ("Their auction scan from %s (about 40 KB, a minute or two in the background)."):format(date("%d %b %H:00", hour * 3600))
    end
    StaticPopup_Show("ENCORE_STONKS_IMPORT", Codec.safeText(sender), what, { sender = sender, kind = kind, arg = arg })
end

if hooksecurefunc and SetItemRef then
    hooksecurefunc("SetItemRef", function(link) if type(link) == "string" then Links.Click(link) end end)
end

---------------------------------------------------------------------------
-- Requests and answers (whisper)
---------------------------------------------------------------------------
function Links.Request(sender, kind, arg)
    if Sync.IsMuted(sender) then return print(P .. "you muted " .. Codec.safeText(sender) .. ".") end
    expecting[sender] = { kind = kind, arg = arg, untilTime = time() + IMPORT_FOR }
    Comm.Send("1L" .. kind .. arg, "WHISPER", sender)
    print(P .. "asked " .. Codec.safeText(sender) .. " for the data; it arrives in the background.")
end

function Links.ExpectScan(sender, body)
    local e = expecting[sender]
    if not e or e.kind ~= "s" or time() > e.untilTime then return false end
    local hs = body:match("^([^:]+):")
    return hs == e.arg
end

Comm.On("L", function(body, asker, channel)
    if channel ~= "WHISPER" then return end
    local kind, arg = body:match("^([is])([0-9A-Za-z*=]+)$")
    if not kind then return Comm.Reject() end
    local at = posted[kind .. (kind == "s" and tostring(Codec.dec(arg)) or arg)]
    if not at or time() - at > POSTED_FOR then return end
    if answered[asker] and time() - answered[asker] < ASK_GAP then return end
    answered[asker] = time()
    if kind == "i" then
        local rec = Sync.BuildSummary(arg)
        if rec then Comm.Send("1R" .. rec, "WHISPER", asker) end
    else
        local hour = Codec.dec(arg)
        Comm.AddJob(function()
            local list = ownScan(hour)
            coroutine.yield()
            Sync.packObs("1S" .. arg .. ":", list, function(msg) Comm.Send(msg, "WHISPER", asker) end)
            Comm.Send("1E" .. arg .. "," .. Codec.enc(#list), "WHISPER", asker)
        end, "link")
    end
end)

Comm.On("R", function(body, sender, channel)
    local e = expecting[sender]
    if channel ~= "WHISPER" or not e or e.kind ~= "i" or time() > e.untilTime then return end
    expecting[sender] = nil
    local rec = Codec.decodeSummary(body)
    local ok = Sync.AddSummary(body, sender)
    Log.Add("item", sender, nil, { got = rec and 1 or 0, kept = ok and 1 or 0, id = rec and rec.id or tonumber(e.arg), med = rec and rec.med, done = true })
    if ok then
        print(P .. "imported price history from " .. Codec.safeText(sender) .. ".")
        Sync.Touched()
    else
        print(P .. "the prices from " .. Codec.safeText(sender) .. " were too far from yours and were not imported.")
    end
end)

Comm.On("E", function(body, sender, channel)
    local f = Codec.fields(body, 2)
    local hour, count = f and Codec.dec(f[1]), f and Codec.dec(f[2] or "")
    if channel == "GUILD" then
        -- End of an hourly guild scan: close its sync history entry.
        if hour then Log.Finish("hourly", sender, hour, { expected = count }) end
        return
    end
    local e = expecting[sender]
    if channel == "WHISPER" and e and e.kind == "s" and body:match("^([^,]+)") == e.arg then
        expecting[sender] = nil
        if hour then Log.Finish("scan", sender, hour, { expected = count }) end
        print(P .. "imported the scan from " .. Codec.safeText(sender) .. ".")
    end
end)
