-- Encore-Stonks guild sharing: /stonksync settings, status and the "no impact" numbers.
local _, ns = ...
local Stonks = ns.Stonks
local Codec, Comm, Sync = Stonks.SyncCodec, Stonks.SyncComm, Stonks.Sync

local P = "|cffd9a066Encore-Stonks|r "
local MODES = {
    off = "off: nothing is sent or received automatically (chat links still work). /stonksync share turns it back on.",
    receive = "receive only: you get guild scans and your login summary, and send only the small login request.",
    share = "share: you also share your scans and answer guildmates' login requests.",
}

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function status()
    local s = Sync.Settings()
    print(P .. "sharing is " .. MODES[s.mode])
    print(P .. "Only item, price, quantity on sale and the hour are ever sent. Your auctions, gold and bags never are.")
    local r = Stonks.realmData
    if r then
        print(P .. ("guild prices for %d items, guild summaries for %d items."):format(count(r.guild), count(r.baseline)))
        if r.sync and r.sync.at then
            print(P .. ("last login summary from %s at %s."):format(Codec.safeText(r.sync.from), date("%d %b %H:%M", r.sync.at)))
        end
    end
    if Sync.lastBroadcast then
        local b = Sync.lastBroadcast
        print(P .. ("you last shared the %s scan: %d changed items in %d messages."):format(date("%H:00", b.hour * 3600), b.items, b.messages))
    end
    if s.lowEnd then print(P .. "low-end mode is on: hourly guild scans are not received.") end
    local seen = {}
    for name in pairs(Comm.seen) do seen[#seen + 1] = Codec.safeText(name) end
    table.sort(seen)
    if #seen > 0 then
        print(P .. "guildmates heard from this session: " .. table.concat(seen, ", ") .. ".")
    else
        print(P .. "no guildmate's Encore-Stonks heard from yet this session. /stonksync who asks who has it.")
    end
    local muted = {}
    for name in pairs(s.muted) do muted[#muted + 1] = Codec.safeText(name) end
    for name, sc in pairs(Sync.score) do if sc.muted then muted[#muted + 1] = Codec.safeText(name) .. " (auto)" end end
    if #muted > 0 then print(P .. "muted: " .. table.concat(muted, ", ")) end
end

local function perf()
    local p = Comm.perf
    local mins = math.max(1, (time() - p.since) / 60)
    print(P .. ("since login (%.0f min): sent %.1f KB in %d messages (%.0f B/min), received %.1f KB in %d messages (%.0f B/min)."):format(
        mins, p.sentBytes / 1024, p.sentMsgs, p.sentBytes / mins, p.recvBytes / 1024, p.recvMsgs, p.recvBytes / mins))
    print(P .. ("work: %.1f ms in total, at most %.2f ms in one frame (budget %.1f ms). Queued to send: %d, jobs: %d."):format(
        p.workMs, p.maxFrameMs, Comm.FrameBudget(), Comm.QueueLength(), Comm.JobCount()))
    print(P .. ("sent in combat: %d (should be 0). Dropped at the size caps: %d. Rejected as malformed: %d."):format(p.sentInCombat, p.dropped, p.rejected))
    local busy, why = Comm.Busy()
    if busy then print(P .. "paused right now: " .. why .. ".") end
    if Comm.lastError then print(P .. "last error: " .. Codec.safeText(Comm.lastError)) end
    if p.rejected > 0 then
        local parts = {}
        for key, n in pairs(p.reasons) do parts[#parts + 1] = ("%s x%d"):format(key, n) end
        table.sort(parts)
        print(P .. "rejected by type and reason: " .. table.concat(parts, ", ") .. ".")
        local l = p.lastReject
        if l then
            print(P .. ("last rejected: %s from %s on %s at %s: %s"):format(l.key, Codec.safeText(l.sender), tostring(l.channel),
                date("%H:%M", l.t), Codec.safeText(l.body)))
        end
    end
end

local function whoReport(replies)
    local names = {}
    for name in pairs(replies) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then
        print(P .. "no guildmate answered. Older versions (0.1.4 and before) don't answer this; /stonksync status lists anyone heard from.")
        return
    end
    local hourNow = math.floor(time() / 3600)
    for _, name in ipairs(names) do
        local r = replies[name]
        local scan = (r.asOf or 0) > 0 and (hourNow - r.asOf < 1 and "scanned this hour" or ("last scan %s"):format(date("%d %b %H:00", r.asOf * 3600))) or "no scan yet"
        print(P .. ("%s: %s, sharing %s, %s."):format(Codec.safeText(name), Codec.safeText(r.version), r.mode, scan))
    end
end

SLASH_ENCORESTONKSSYNC1 = "/stonksync"
SlashCmdList.ENCORESTONKSSYNC = function(input)
    input = input or ""
    local cmd, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    local s = Sync.Settings()
    if MODES[cmd] then
        s.mode = cmd
        print(P .. "sharing is " .. MODES[cmd])
        if cmd ~= "off" then Sync.StartAsk() end
    elseif cmd == "lowend" then
        s.lowEnd = not s.lowEnd
        print(P .. "low-end mode " .. (s.lowEnd and "on: hourly guild scans are no longer received." or "off."))
    elseif cmd == "mute" and rest ~= "" then
        s.muted[rest] = true
        print(P .. "muted " .. Codec.safeText(rest) .. ".")
    elseif cmd == "unmute" and rest ~= "" then
        s.muted[rest] = nil
        if Sync.score[rest] then Sync.score[rest] = nil end
        print(P .. "unmuted " .. Codec.safeText(rest) .. ".")
    elseif cmd == "link" then
        local what, arg = rest:match("^(%S+)%s*(.-)$")
        if what == "scan" then Stonks.Sync.Links.PostScan()
        elseif what == "item" then Stonks.Sync.Links.PostItem(arg)
        else print(P .. "usage: /stonksync link scan  or  /stonksync link item <shift-click an item>") end
    elseif cmd == "history" then
        Stonks:ShowPage("history")
    elseif cmd == "perf" then
        perf()
    elseif cmd == "status" then
        status()
    elseif cmd == "who" then
        if Sync.Who(whoReport) then print(P .. "asking the guild who runs Encore-Stonks...") else print(P .. "you are not in a guild.") end
    else
        print(P .. "guild sharing: /stonksync off | receive | share | status | who | perf | lowend | mute <name> | unmute <name> | link scan | link item <item> | history")
        status()
    end
end
