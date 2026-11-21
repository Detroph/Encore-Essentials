-- Encore-Stonks guild sharing: sending, receiving and the background work queue.
-- Rules that keep sharing invisible during play:
--  * We send at most 400 bytes a second (half of what other addons usually allow themselves), through
--    ChatThrottleLib at its lowest priority when another addon has loaded it, so DBM, PallyPower or Spy always go
--    first.
--  * Nothing is sent in combat, in dungeons, raids, battlegrounds or arenas, or while an auction house scan runs.
--  * The receive handler only checks the header and queues the message. Reading and saving happen later, in a
--    work queue that uses at most 1 ms per frame (0.5 ms below 30 fps) and nothing at all in combat.
local _, ns = ...
local Stonks = ns.Stonks
local Codec = Stonks.SyncCodec
local Comm = {}
Stonks.SyncComm = Comm

Comm.PREFIX = "EncStk"
local RATE = 400 -- bytes per second
local BURST = 800
local OVERHEAD = 40 -- what the server and ChatThrottleLib count per message on top of the text
local INBOX_MAX = 3000
local SENDER_BYTES_PER_HOUR = 120 * 1024

local outbox = {} -- { msg, channel, target, onSent }
local tokens, lastRefill = BURST, 0
local backoffUntil, backoffStep = 0, 0
local inbox, inboxFirst, inboxLast = {}, 1, 0
local senderBytes, senderHour = {}, 0
local jobs = {}
local handlers = {}

-- Counters for /stonksync perf
local perf = { sentBytes = 0, sentMsgs = 0, recvBytes = 0, recvMsgs = 0, dropped = 0, rejected = 0,
    sentInCombat = 0, workMs = 0, maxFrameMs = 0, frames = 0, since = 0, reasons = {} }
Comm.perf = perf

local now = function() return GetTime() end
Comm.now = now

local function me()
    local name = UnitName("player")
    return name
end
Comm.Me = me

-- True when a name from a message is us: "Name", or "Name-Realm" as a guildmate on another realm writes it.
function Comm.IsMe(name)
    local mine = me()
    if not name or not mine then return false end
    if name == mine then return true end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if realm and name == mine .. "-" .. realm then return true end
    local base = name:match("^([^%-]+)%-")
    return base == mine and realm == nil
end

-- Guildmates whose Encore-Stonks we heard this session: seen[name] = { t = time, kind = last message type }.
Comm.seen = {}

function Comm.Ambiguate(name)
    if not name then return nil end
    if Ambiguate then return Ambiguate(name, "none") end
    return (name:gsub("%-.*$", ""))
end

-- True when we must not send (or do background work) right now.
function Comm.Busy()
    if InCombatLockdown() or UnitAffectingCombat("player") then return true, "combat" end
    local inInstance, kind = IsInInstance()
    if inInstance and kind ~= "none" then return true, "instance" end
    local r = Stonks.realmData
    if r and r.last and time() - r.last < 60 then return true, "scanning" end
    return false
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
function Comm.Send(msg, channel, target, onSent)
    if #msg > 255 then error("Encore-Stonks: message too long") end
    outbox[#outbox + 1] = { msg, channel, target, onSent }
end

function Comm.QueueLength() return #outbox end

-- Drops everything queued for one target (a whisper partner who went away, or a broadcast we lost a claim on).
function Comm.Cancel(filter)
    local kept = {}
    for _, m in ipairs(outbox) do
        if not filter(m[1], m[2], m[3]) then kept[#kept + 1] = m end
    end
    outbox = kept
end

local function rawSend(msg, channel, target)
    local ctl = _G.ChatThrottleLib
    if ctl and ctl.SendAddonMessage then
        ctl:SendAddonMessage("BULK", Comm.PREFIX, msg, channel, target)
        return true
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, Comm.PREFIX, msg, channel, target)
    if not ok then return false end
    -- Newer clients return a result code (0 = success), older ones true/false or nothing.
    if result == false or (type(result) == "number" and result ~= 0) then return false end
    return true
end

local function pumpOutbox()
    if #outbox == 0 then return end
    local t = now()
    if t < backoffUntil then return end
    if Comm.Busy() then return end
    tokens = math.min(BURST, tokens + (t - lastRefill) * RATE)
    lastRefill = t
    while outbox[1] do
        local m = outbox[1]
        local cost = #m[1] + OVERHEAD
        if tokens < cost then return end
        if not rawSend(m[1], m[2], m[3]) then
            -- Throttled or refused: wait 1, 2, 4 ... 60 seconds before trying again.
            backoffStep = math.min(backoffStep + 1, 6)
            backoffUntil = t + math.min(60, 2 ^ (backoffStep - 1))
            return
        end
        backoffStep = 0
        if InCombatLockdown() then perf.sentInCombat = perf.sentInCombat + 1 end
        table.remove(outbox, 1)
        tokens = tokens - cost
        perf.sentBytes, perf.sentMsgs = perf.sentBytes + #m[1], perf.sentMsgs + 1
        if m[4] then m[4]() end
    end
end

---------------------------------------------------------------------------
-- Receiving: header check and queue only.
---------------------------------------------------------------------------
-- Message types the sync code handles: handlers[type] = function(body, sender, channel)
function Comm.On(kind, fn) handlers[kind] = fn end

-- accept(kind, sender, channel) -> false to drop at the header (sharing off, muted sender, low-end mode...)
Comm.accept = function() return true end

function Comm.Receive(prefix, msg, channel, sender)
    if prefix ~= Comm.PREFIX or type(msg) ~= "string" then return end
    sender = Comm.Ambiguate(sender)
    if not sender or Comm.IsMe(sender) then return end
    if msg:sub(1, 1) ~= Codec.VERSION then return end -- other protocol versions are ignored
    local kind = msg:sub(2, 2)
    Comm.seen[sender] = { t = time(), kind = kind, channel = channel }
    if not handlers[kind] or not Comm.accept(kind, sender, channel) then return end
    local hour = math.floor(time() / 3600)
    if hour ~= senderHour then senderHour = hour; wipe(senderBytes) end
    local used = (senderBytes[sender] or 0) + #msg
    senderBytes[sender] = used
    if used > SENDER_BYTES_PER_HOUR or inboxLast - inboxFirst + 1 >= INBOX_MAX then
        perf.dropped = perf.dropped + 1
        return
    end
    perf.recvBytes, perf.recvMsgs = perf.recvBytes + #msg, perf.recvMsgs + 1
    inboxLast = inboxLast + 1
    inbox[inboxLast] = { kind, msg:sub(3), sender, channel }
end

-- A message we threw out. reason says which check failed; /stonksync perf lists them by message type and reason.
local current -- the message being handled right now: { kind, body, sender, channel }
function Comm.Reject(reason)
    perf.rejected = perf.rejected + 1
    local kind = current and current[1] or "?"
    local key = kind .. " " .. (reason or "bad")
    perf.reasons[key] = (perf.reasons[key] or 0) + 1
    perf.lastReject = { key = key, sender = current and current[3], channel = current and current[4],
        body = current and current[2] and current[2]:sub(1, 60), t = time() }
end

---------------------------------------------------------------------------
-- Work queue: inbox first, then jobs (coroutines that yield between small steps).
---------------------------------------------------------------------------
function Comm.AddJob(fn, name)
    jobs[#jobs + 1] = { co = coroutine.create(fn), name = name }
end

function Comm.JobCount() return #jobs end

local function frameBudget()
    local fps = GetFramerate and GetFramerate() or 60
    return fps < 30 and 0.5 or 1.0
end
Comm.FrameBudget = frameBudget

function Comm.Step()
    pumpOutbox()
    if InCombatLockdown() or UnitAffectingCombat("player") then return end
    if inboxLast < inboxFirst and #jobs == 0 then return end
    local start = debugprofilestop()
    local budget = frameBudget()
    frameStart, frameBudgetMs = start, budget
    local what
    while debugprofilestop() - start < budget do
        if inboxFirst <= inboxLast then
            local m = inbox[inboxFirst]
            inbox[inboxFirst] = nil
            inboxFirst = inboxFirst + 1
            what = m[1]
            current = m
            local ok, err = pcall(handlers[m[1]], m[2], m[3], m[4])
            if not ok then Comm.Reject("error"); Comm.lastError = err end
            current = nil
        elseif jobs[1] then
            local job = jobs[1]
            what = job.name
            local ok, err = coroutine.resume(job.co)
            if not ok then Comm.lastError = err end
            if coroutine.status(job.co) == "dead" then
                table.remove(jobs, 1)
            elseif err == "wait" then
                -- The job is waiting (for the send queue to drain): move it to the back and stop for this frame.
                table.remove(jobs, 1)
                jobs[#jobs + 1] = job
                break
            end
        else
            break
        end
    end
    local used = debugprofilestop() - start
    perf.workMs = perf.workMs + used
    perf.frames = perf.frames + 1
    if used > perf.maxFrameMs then perf.maxFrameMs, perf.maxWhat = used, what end
end

-- Coroutine helpers for jobs: MaybeYield pauses as soon as this frame's budget is used up; Wait pauses until the
-- next frame (use it when waiting for something, so the work queue doesn't spin).
function Comm.Wait() coroutine.yield("wait") end
local frameStart, frameBudgetMs = 0, 1
function Comm.MaybeYield()
    if debugprofilestop() - frameStart >= frameBudgetMs then coroutine.yield() end
end

local frame = CreateFrame("Frame")
Comm.frame = frame
frame:SetScript("OnUpdate", function() Comm.Step() end)
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then Comm.Receive(...) end
end)
frame:RegisterEvent("CHAT_MSG_ADDON")
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(Comm.PREFIX) end
perf.since = time()
