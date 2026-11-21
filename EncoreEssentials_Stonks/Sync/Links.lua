-- Encore-Stonks guild sharing: chat links, WeakAuras style.
-- "/stonksync link item <item>" or "/stonksync link scan" puts plain text like [Stonks: Black Lotus #i13468] into
-- the chat the player has open (whisper, party, raid, guild...). The server strips custom link codes, so plain
-- text is what travels. Players with Stonks see it as a clickable link; clicking asks to confirm, and only then is the data requested from the poster by whisper.
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

-- Chat types that make no sense for a shared link; for these we send to guild instead.
local PUBLIC = { SAY = true, YELL = true, EMOTE = true }

-- The chat the player last had open (its box, chat type, whisper target and channel). Clicking Share takes focus
-- from the chat box, and the game may close it and reset it to its default type before the button runs, so we
-- remember it all the time while the player has a chat box focused.
local lastChat
local restoring = false

local function remember(box)
    if restoring or not box or not box.GetAttribute or not (box.HasFocus and box:HasFocus()) then return end
    local chatType = box:GetAttribute("chatType")
    if not chatType then return end
    lastChat = { box = box, chatType = chatType, tellTarget = box:GetAttribute("tellTarget"),
        channelTarget = box:GetAttribute("channelTarget") }
end

-- Every chat edit box: the numbered chat frames and any whisper windows (CHAT_FRAMES lists them all).
local function chatBoxes()
    local list, seen = {}, {}
    local function add(box) if box and not seen[box] then seen[box] = true; list[#list + 1] = box end end
    for _, name in ipairs(CHAT_FRAMES or {}) do
        local frame = _G[name]
        add(frame and (frame.editBox or _G[name .. "EditBox"]))
    end
    for i = 1, NUM_CHAT_WINDOWS or 10 do add(_G["ChatFrame" .. i .. "EditBox"]) end
    return list
end

local hooked = {}
local function hookBoxes()
    for _, box in ipairs(chatBoxes()) do
        if not hooked[box] and box.HookScript then
            hooked[box] = true
            box:HookScript("OnEditFocusGained", remember)
            box:HookScript("OnTextChanged", remember)
        end
    end
end
hookBoxes()
if hooksecurefunc then
    if ChatEdit_UpdateHeader then hooksecurefunc("ChatEdit_UpdateHeader", remember) end
    if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", hookBoxes) end
end
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", hookBoxes)

local function setChat(box, chatType, tellTarget, channelTarget)
    restoring = true
    box:SetAttribute("chatType", chatType)
    if tellTarget then box:SetAttribute("tellTarget", tellTarget) end
    if channelTarget then box:SetAttribute("channelTarget", channelTarget) end
    if ChatEdit_UpdateHeader then ChatEdit_UpdateHeader(box) end
    restoring = false
end

local function activate(box)
    restoring = true
    if ChatEdit_ActivateChat then ChatEdit_ActivateChat(box) else box:Show(); box:SetFocus() end
    restoring = false
end

-- Puts the link text into the chat the player has open, ready to send with Enter:
-- 1. a chat box that has focus: the link goes in at the cursor;
-- 2. else the chat the player last had open (whisper target, party, raid, guild, officer, channel): that box is
--    opened again with that chat and the link is added to whatever was typed;
-- 3. else a new chat box, in guild chat when the default would be say, yell or emote.
-- Note: ChatFrame_OpenChat only fills its text on the next frame, so text inserted right after it is wiped;
-- that is why 0.1.3 opened an empty guild box. We open boxes with ChatEdit_ActivateChat instead.
local function insertChat(text)
    hookBoxes()
    for _, box in ipairs(chatBoxes()) do
        if box:HasFocus() then box:Insert(text); return end
    end
    local saved = lastChat
    if saved and saved.box then
        local box = saved.box
        activate(box)
        setChat(box, saved.chatType, saved.tellTarget, saved.channelTarget)
        if PUBLIC[saved.chatType] and IsInGuild() then setChat(box, "GUILD") end
        -- Insert a moment later too, in case the game fills or clears the reopened box on its next frame.
        box:Insert(text)
        if C_Timer then
            C_Timer.After(0.05, function()
                if not (box:GetText() or ""):find(text, 1, true) then box:Insert(text) end
            end)
        end
        return
    end
    if not ChatFrame_OpenChat then return end
    restoring = true
    ChatFrame_OpenChat(text)
    restoring = false
    -- The box shows its default chat; move it to guild when that is say, yell or emote.
    local function fixType()
        for _, box in ipairs(chatBoxes()) do
            if box:HasFocus() then
                local chatType = box:GetAttribute("chatType")
                if (not chatType or PUBLIC[chatType]) and IsInGuild() then setChat(box, "GUILD") end
                return
            end
        end
    end
    fixType()
    if C_Timer then C_Timer.After(0, fixType) end
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
