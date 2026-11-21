-- Offline tests for Encore-Stonks guild sharing (Lua 5.1, no game needed):
--   lua5.1 tools/stonks-sync/sim.lua            (from the repository root)
-- Loads the real addon files into many simulated clients that talk over a fake guild channel, and checks the
-- wire format, the login handshake, hourly claims, resume after a sender leaves, and the per-frame work budget.
local ROOT = "EncoreEssentials_Stonks/"
local FILES = { "Recorder.lua", "Stats.lua", "Sync/Codec.lua", "Sync/Comm.lua", "Sync/Log.lua", "Sync/Sync.lua", "Sync/Links.lua", "Sync/Slash.lua", "Sync/Buttons.lua" }

local clock = 1763560000 -- a fixed start time (seconds)
local queue = {} -- timed callbacks { at, fn }
local clients = {}
local failures, checks = 0, 0

local function check(cond, what)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL: " .. what) else print("ok   " .. what) end
end

local function schedule(delay, fn) queue[#queue + 1] = { at = clock + delay, fn = fn } end

local function newClient(name)
    local c = { name = name, frames = {}, online = true, combat = false, afk = false, sent = {}, printed = {} }
    local env = setmetatable({}, { __index = _G })
    c.env = env
    env._G = env
    env.print = function(s) c.printed[#c.printed + 1] = s end
    env.time = function(t) if t then return os.time(t) end return math.floor(clock) end
    env.date = function(fmt, t) return os.date(fmt, t or math.floor(clock)) end
    env.GetTime = function() return clock end
    env.debugprofilestop = function() return os.clock() * 1000 end
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.hooksecurefunc = function(t, k, fn)
        if type(t) == "string" then return end
        local orig = t[k]
        t[k] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
    end
    env.CreateFrame = function()
        local f = { scripts = {}, events = {} }
        function f:SetScript(k, fn) self.scripts[k] = fn end
        function f:RegisterEvent(e) self.events[e] = true end
        function f:UnregisterEvent(e) self.events[e] = nil end
        c.frames[#c.frames + 1] = f
        return f
    end
    local function timer(delay, fn, repeating)
        local t = { cancelled = false }
        function t:Cancel() self.cancelled = true end
        local function fire()
            if t.cancelled or not c.online then return end
            fn(t)
            if repeating then schedule(delay, fire) end
        end
        schedule(delay, fire)
        return t
    end
    env.C_Timer = {
        After = function(d, fn) timer(d, fn) end,
        NewTimer = function(d, fn) return timer(d, fn) end,
        NewTicker = function(d, fn) return timer(d, fn, true) end,
    }
    env.C_AddOns = { IsAddOnLoaded = function() return false end, GetAddOnMetadata = function() return "test" end }
    env.GetRealmName = function() return "Test" end
    env.UnitFactionGroup = function() return "Horde" end
    env.UnitName = function() return name end
    env.InCombatLockdown = function() return c.combat end
    env.UnitAffectingCombat = function() return c.combat end
    env.IsInInstance = function() return false, "none" end
    env.IsInGuild = function() return true end
    env.UnitIsAFK = function() return c.afk end
    env.GetFramerate = function() return 60 end
    env.Ambiguate = function(n) return (n:gsub("%-.*$", "")) end
    env.ChatFrame_AddMessageEventFilter = function() end
    env.StaticPopupDialogs = {}
    env.SlashCmdList = {}
    env.GetItemInfo = function(id) return "Item " .. id end
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() end,
        SendAddonMessage = function(prefix, msg, channel, target)
            assert(#msg <= 255, "message over 255 bytes")
            c.sent[#c.sent + 1] = { msg = msg, channel = channel, target = target, at = clock, combat = c.combat }
            for _, other in ipairs(clients) do
                if other ~= c and other.online and (channel == "GUILD" or other.name == target) then
                    schedule(0.1, function() other:event("CHAT_MSG_ADDON", prefix, msg, channel, name .. "-Test") end)
                end
            end
            return true
        end,
    }
    env.ChatEdit_GetActiveWindow = function() return nil end
    env.EncoreEssentials = { RegisterModule = function(_, _, m) return m end, Print = function() end }
    function c:event(e, ...)
        if not self.online then return end
        for _, f in ipairs(self.frames) do
            if f.events[e] and f.scripts.OnEvent then f.scripts.OnEvent(f, e, ...) end
        end
    end
    function c:update()
        for _, f in ipairs(self.frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.1) end end
    end
    local ns = {}
    for _, file in ipairs(FILES) do
        local chunk = assert(loadfile(ROOT .. file))
        setfenv(chunk, env)
        chunk("EncoreEssentials_Stonks", ns)
    end
    c.Stonks = ns.Stonks
    c:event("ADDON_LOADED", "EncoreEssentials_Stonks")
    c:event("PLAYER_LOGIN")
    clients[#clients + 1] = c
    return c
end

-- Runs the world for some seconds at 10 frames a second.
local maxFrame, maxWhat = 0, nil
local frameSamples = {}
local function run(seconds)
    local stop = clock + seconds
    while clock < stop do
        clock = clock + 0.1
        local due = {}
        local rest = {}
        for _, e in ipairs(queue) do if e.at <= clock then due[#due + 1] = e else rest[#rest + 1] = e end end
        queue = rest
        table.sort(due, function(a, b) return a.at < b.at end)
        for _, e in ipairs(due) do e.fn() end
        for _, c in ipairs(clients) do
            if c.online then
                local p0 = c.Stonks.SyncComm.perf.workMs
                c:update()
                local d = c.Stonks.SyncComm.perf.workMs - p0
                if d > 0 then frameSamples[#frameSamples + 1] = d end
                local p = c.Stonks.SyncComm.perf
                if p.maxFrameMs > maxFrame then maxFrame, maxWhat = p.maxFrameMs, c.name .. " " .. tostring(p.maxWhat) end
            end
        end
    end
end

-- Gives a client a week of history for n items: one sample a day, ending a few hours ago.
local function giveData(c, n, scannedHoursAgo, priceFactor)
    local S = c.Stonks
    local r = S.realmData
    local nowHour = math.floor(clock / 3600)
    for id = 1, n do
        local base = 1000 + (id * 7919) % 500000
        local parts = {}
        for day = 7, 0, -1 do
            local h = nowHour - scannedHoursAgo - day * 24
            parts[#parts + 1] = S.b36(h) .. ":" .. S.b36(math.floor(base * (priceFactor or 1) * (0.9 + 0.2 * ((id + day) % 5) / 4))) .. ":" .. S.b36(5 + id % 20) .. ";"
        end
        r.items[tostring(id + 100)] = table.concat(parts)
    end
    r.last = (nowHour - scannedHoursAgo) * 3600 + 600
end

local function setMode(c, m) c.Stonks.db.settings.sync = c.Stonks.db.settings.sync or {}; c.Stonks.db.settings.sync.mode = m; c.Stonks.db.settings.sync.v = 3 end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end return n end
local function sentOfKind(kind, channel)
    local n = 0
    for _, c in ipairs(clients) do
        for _, s in ipairs(c.sent) do if s.msg:sub(2, 2) == kind and (not channel or s.channel == channel) then n = n + 1 end end
    end
    return n
end

---------------------------------------------------------------------------
print("== Wire format")
do
    local fresh = newClient("Fresh")
    check(fresh.Stonks.Sync.Mode() == "share", "sharing is on by default")
    fresh.Stonks.db.settings.sync.mode = "off"
    check(fresh.Stonks.Sync.Mode() == "off", "an explicit off sticks")
    fresh.online = false
end
local probe = newClient("Probe")
local Codec = probe.Stonks.SyncCodec
for _, n in ipairs({ 0, 1, 63, 64, 4095, 123456789, 99999999999 }) do
    check(Codec.dec(Codec.enc(n)) == n, "number " .. n .. " round-trips")
end
check(Codec.decSigned(Codec.encSigned(-4321)) == -4321, "signed number round-trips")
local list = Codec.decodeObs(Codec.encodeObs(0, 13468, 250000, 12) .. Codec.encodeObs(13468, 13469, 99, 0))
check(list and list[2][1] == 13469 and list[2][2] == 99, "observations round-trip with id gaps")
check(Codec.decodeObs("1,2,3;|cffff0000|r") == nil, "escape codes are rejected")
check(Codec.decodeObs("loadstring(\"x\")") == nil, "code-looking text is rejected")
check(Codec.decodeObs("1,0,3;") == nil, "zero price is rejected")
check(Codec.decodeObs("1,2,3;0,2,3;") == nil, "repeated item id is rejected")
check(Codec.decodeObs("ZZZZZZZZZ,2,3;") == nil, "oversized number is rejected")
local rec = { id = 13468, med = 1000, q25 = 900, q75 = 1200, a3 = 1010, a7 = 1005, a14 = 1001, days = 9,
    week = { [1] = { n = 3, sum = -0.08 } }, hour = { [20] = { n = 4, sum = 0.12 } } }
local text = Codec.encodeSummary(rec)
local back = Codec.decodeSummary(text)
check(back and back.med == 1000 and back.week[1].n == 3 and math.abs(back.hour[20].sum - 0.12) < 1e-9, "summary round-trips: " .. text)
check(Codec.decodeSummary(text:gsub("^[^,]+", "-1")) == nil, "negative item id in summary is rejected")
check(Codec.decodeSummary("1,9,1,2,1,1,1,1,") == nil, "summary with median outside its range is rejected")
check(#text < 120, "a summary record is under 120 bytes (" .. #text .. ")")
probe.online = false

---------------------------------------------------------------------------
print("== 200 online: a new player logs in")
local holders = {}
for i = 1, 200 do
    local c = newClient("P" .. i)
    setMode(c, "share")
    c.Stonks.realmData.sync = { since = math.floor(clock / 3600) } -- already up to date
    if i <= 15 then giveData(c, i == 1 and 7000 or 2000, 2 + i % 5); holders[#holders + 1] = c end
end
local afkName = holders[2].name
holders[2].afk = true -- an AFK guildmate with data
run(120) -- everyone's own login hello passes
local offersBefore = sentOfKind("O")
local newbie = newClient("Newbie")
setMode(newbie, "receive")
run(90)
local offers = sentOfKind("O") - offersBefore
check(offers >= 1 and offers <= 3, "1 to 3 offers for the newcomer, not 200 (" .. offers .. ")")
local accepted
for _, s in ipairs(newbie.sent) do if s.msg:sub(1, 2) == "1A" then accepted = s.msg:sub(3) end end
check(accepted == afkName, "the AFK guildmate is chosen (" .. tostring(accepted) .. ")")
run(1500)
local got = count(newbie.Stonks.realmData.baseline)
check(got == 2000, "newcomer received the full summary (" .. got .. " items)")
check(newbie.Stonks.realmData.sync.from == afkName, "summary marked complete")
local function logOf(c, kind)
    local out = {}
    for _, e in ipairs(c.Stonks.realmData.syncLog or {}) do if e.kind == kind then out[#out + 1] = e end end
    return out
end
local nl = logOf(newbie, "summary")
check(#nl == 1 and nl[1].from == afkName and nl[1].done and nl[1].kept == 2000 and nl[1].expected == 2000,
    "sync history: one complete login summary from " .. afkName .. " (" .. tostring(nl[1] and nl[1].kept) .. " kept)")
local st = newbie.Stonks:ItemStats("150")
check(st and st.guild and st.median and st.median > 0, "charts see the guild baseline for an item the newcomer never scanned")

---------------------------------------------------------------------------
print("== Sender leaves mid-transfer")
local late = newClient("Late")
setMode(late, "receive")
holders[2].afk = false
run(75) -- hello, offers, accept
local server = late.Stonks.Sync and nil
for _, s in ipairs(late.sent) do if s.msg:sub(1, 2) == "1A" then server = s.msg:sub(3) end end
run(60)
local partial = count(late.Stonks.realmData.baseline)
for _, c in ipairs(clients) do if c.name == server then c.online = false end end
run(2400)
local final = count(late.Stonks.realmData.baseline)
check(server ~= nil and partial > 0 and partial < final, ("resumed after %s left (%d items before, %d after)"):format(tostring(server), partial, final))
check(final >= 1990, "late player ends with (nearly) everything (" .. final .. ")")
local ll = logOf(late, "summary")
check(#ll >= 2 and ll[1].from == server and ll[1].stopped and ll[#ll].done and not ll[#ll].stopped and ll[#ll].from ~= server,
    "sync history: the summary from " .. tostring(server) .. " is marked stopped, the resume from someone else complete (" .. #ll .. " entries)")

---------------------------------------------------------------------------
print("== Hourly claim: 4 players finish a scan in the same hour")
local nowHour = math.floor(clock / 3600)
if clock - nowHour * 3600 > 2400 then run(nowHour * 3600 + 3600 - clock + 30); nowHour = math.floor(clock / 3600) end
local scanners = { clients[5], clients[6], clients[7], clients[8] }
for _, c in ipairs(scanners) do
    for id = 1, 1200 do c.Stonks:Record(tostring(id + 100), 5000 + id, 3) end
end
local sBefore = sentOfKind("S", "GUILD")
run(180)
local claimers = {}
for _, c in ipairs(scanners) do
    for _, s in ipairs(c.sent) do if s.msg:sub(1, 2) == "1S" and s.at > clock - 200 then claimers[c.name] = true end end
end
check(count(claimers) == 1, "exactly one player broadcasts the hour (" .. count(claimers) .. ")")
local msgs = sentOfKind("S", "GUILD") - sBefore
check(msgs > 0 and msgs < 120, "1,200 items fit in " .. msgs .. " messages")
local watcher = clients[150]
local g = watcher.Stonks.realmData.guild["600"]
check(g ~= nil, "a bystander stored the guild price")
local claimer = next(claimers)
local wl = logOf(watcher, "hourly")
check(#wl == 1 and wl[1].from == claimer and wl[1].done and wl[1].got == 1200 and wl[1].hour == nowHour,
    "sync history: the bystander logged one complete hourly scan from " .. tostring(claimer) .. " (" .. tostring(wl[1] and wl[1].got) .. " items)")

---------------------------------------------------------------------------
print("== Never in combat, outliers rejected")
local fighter = clients[9]
fighter.combat = true
local before = #fighter.sent
fighter.Stonks.SyncComm.Send("1C" .. Codec.enc(1) .. ",1,1", "GUILD")
run(30)
check(#fighter.sent == before, "nothing sent while in combat")
fighter.combat = false
run(5)
check(#fighter.sent == before + 1, "queued message goes out after combat")
local totalCombat = 0
for _, c in ipairs(clients) do for _, s in ipairs(c.sent) do if s.combat then totalCombat = totalCombat + 1 end end end
check(totalCombat == 0, "no message from anyone was sent in combat")

local judge = clients[2]
judge.Stonks.realmData.stat["9001"] = judge.Stonks.EncodeStat({ day = 10, n = 10, e3 = 1000, e7 = 1000, e14 = 1000, m = 1000, v = 0, hist = {} })
check(judge.Stonks.Sync.AddGuildSample("9001", nowHour, 999999, 1, "Troll") == false, "a 1000x price is not accepted")
check(judge.Stonks.Sync.AddGuildSample("9001", nowHour, 1100, 1, "Fair") == true, "a normal price is accepted")

print("== Chat links (manual import, works with sharing off)")
local poster, clicker = clients[20], newClient("Clicker")
setMode(clicker, "off")
for id = 1, 300 do poster.Stonks:Record(tostring(id + 5000), 7000 + id, 4) end
run(70)
local chat
poster.env.ChatFrame_OpenChat = function(t) chat = t end
poster.Stonks.Sync.Links.PostScan()
check(chat and chat:find("^%[Stonks: scan .- #s"), "scan link text: " .. tostring(chat))
local hourArg = chat:match("#s([0-9A-Za-z*=]+)%]")
clicker.Stonks.Sync.Links.Request(poster.name, "s", hourArg)
run(120)
check(clicker.Stonks.realmData.guild["5100"] ~= nil, "clicker imported the linked scan")
poster.Stonks.Sync.Links.PostItem("item:150")
clicker.Stonks.Sync.Links.Request(poster.name, "i", "150")
run(20)
check(clicker.Stonks.realmData.baseline["150"] ~= nil, "clicker imported the linked item")
clicker.Stonks.Sync.Links.Request(poster.name, "i", "151")
run(20)
check(clicker.Stonks.realmData.baseline["151"] == nil, "an item the poster never linked is not sent")
local cs, ci = logOf(clicker, "scan"), logOf(clicker, "item")
check(#cs == 1 and cs[1].from == poster.name and cs[1].done and cs[1].got == 300, "sync history: the linked scan is logged (" .. tostring(cs[1] and cs[1].got) .. " items)")
check(#ci == 1 and ci[1].id == 150 and ci[1].kept == 1 and ci[1].med and ci[1].med > 0, "sync history: the linked item is logged with its price")

---------------------------------------------------------------------------
print("== Who has it, sharing switched on once, names from other realms, reject reasons")
do
    local asker, other = newClient("WhoA"), newClient("WhoB")
    other.Stonks.realmData.last = math.floor(clock / 3600) * 3600 + 5
    local replies
    asker.Stonks.Sync.Who(function(r) replies = r end)
    run(15)
    check(replies and replies.WhoB and replies.WhoB.mode == "share" and replies.WhoB.version == "test", "/stonksync who: a guildmate answers with mode and version")
    check(asker.Stonks.SyncComm.seen.WhoB ~= nil, "status: guildmates heard from are listed")

    local old = newClient("OldSave")
    old.Stonks.db.settings.sync = { mode = "off", v = 2, muted = {} }
    check(old.Stonks.Sync.Mode() == "share", "first login with this version switches sharing on, even from off")
    old.Stonks.db.settings.sync.mode = "receive"
    check(old.Stonks.Sync.Mode() == "receive", "a choice made after that sticks")
    old.online = false

    local Comm = asker.Stonks.SyncComm
    check(Comm.IsMe("WhoA") and Comm.IsMe("WhoA-Othrealm") and not Comm.IsMe("WhoB-Othrealm"), "own name is recognised with a realm suffix")
    asker.env.GetNormalizedRealmName = function() return "Home" end
    check(Comm.IsMe("WhoA-Home") and not Comm.IsMe("WhoA-Othrealm"), "with the realm known, only our own realm matches")
    asker.env.GetNormalizedRealmName = nil

    local before = Comm.perf.rejected
    Comm.Receive(Comm.PREFIX, "1Cbad", "GUILD", "WhoB-Test")
    run(1)
    check(Comm.perf.rejected == before + 1 and Comm.perf.reasons["C fields"] == 1 and Comm.perf.lastReject.sender == "WhoB",
        "a rejected message is counted with its type, reason and sender")
    asker.online, other.online = false, false

    -- WoW Forever names have a first and last name: the login handshake must work with them.
    local holder = newClient("Croq Madame")
    giveData(holder, 50, 1)
    local spaced = newClient("Berya Ebonlocke")
    run(150)
    local r = spaced.Stonks.realmData
    check(r.sync.from ~= nil and count(r.baseline) > 0, "a player named with a space gets a login summary (from " .. tostring(r.sync.from) .. ")")
    check(spaced.Stonks.SyncComm.perf.rejected == 0, "and nothing is rejected (" .. spaced.Stonks.SyncComm.perf.rejected .. ")")
    holder.online, spaced.online = false, false

    for _, c in ipairs(clients) do c.online = false end
    -- An old guildmate (0.1.4) offers but never serves a player named with a space: the attempt shows in the
    -- history, and the summary then comes from someone who can send it.
    local old = newClient("Old Timer")
    giveData(old, 40, 0)
    old.afk = true -- AFK offers are picked first, so the old one is tried first
    local oldSend = old.Stonks.SyncComm.Send
    old.Stonks.SyncComm.Send = function(msg, ...)
        if msg:sub(1, 2) == "1O" then msg = msg:gsub(",2$", "") end -- 0.1.4 offers have no 4th field
        return oldSend(msg, ...)
    end
    old.Stonks.SyncComm.On("A", function() end) -- and can't read the accept
    -- Only the old one online: the failed attempt is in the history; then a capable sender logs in.
    local lone = newClient("Lone Asker")
    run(140)
    local le = logOf(lone, "summary")
    check(#le == 1, "the silent sender is not asked again and again (" .. #le .. " tries)")
    check(#le >= 1 and le[1].from == "Old Timer" and le[1].stopped and le[1].silent and le[1].got == 0,
        "an offer that never delivers shows in the history as nothing arrived")
    local good = newClient("Good Sender")
    giveData(good, 40, 2)
    run(400)
    local got
    for _, e in ipairs(logOf(lone, "summary")) do if e.from == "Good Sender" and e.done and (e.got or 0) > 0 then got = e end end
    check(got ~= nil, "the next try passes over the silent sender and gets the summary")

    -- Both online from the start: the offer that says it can serve is taken, even though the old one is AFK.
    local newbie = newClient("New Comer")
    run(150)
    local silent, done
    for _, e in ipairs(logOf(newbie, "summary")) do
        if e.from == "Old Timer" then silent = e end
        if e.from == "Good Sender" and e.done and (e.got or 0) > 0 then done = e end
    end
    check(silent == nil and done ~= nil, "an offer from a version that can serve is preferred over an old AFK one")
    old.Stonks.SyncComm.Send = oldSend
    old.online, good.online, newbie.online, lone.online = false, false, false, false

    -- Request sync button: asks once more, gets what changed since the last summary, then waits an hour.
    local S = newbie.Stonks
    local hourNow = math.floor(clock / 3600)
    good.online = true
    good.Stonks.realmData.items["9001"] = good.Stonks.b36(hourNow) .. ":" .. good.Stonks.b36(5000) .. ":" .. good.Stonks.b36(3) .. ";"
    good.Stonks.realmData.last = hourNow * 3600 + 30
    newbie.online = true
    local before = #logOf(newbie, "summary")
    local ok = S.Sync.RequestNow()
    run(60)
    local after = logOf(newbie, "summary")
    check(ok and #after == before + 1 and after[#after].done and newbie.Stonks.realmData.baseline["9001"] ~= nil,
        "Request sync gets the newer prices and logs it")
    local again, msg = S.Sync.RequestNow()
    check(not again and S.Sync.ManualWait() > 3500, "Request sync waits an hour before the next one (" .. tostring(msg) .. ")")
    local none
    S.Sync.onManual = function(r) none = r end
    run(1800)
    check(not S.Sync.RequestNow(), "still waiting after 30 minutes")
    run(1800)
    check(S.Sync.RequestNow() and true, "after an hour it can ask again")
    run(30)
    check(none == "none", "with nothing newer anywhere it says nobody answered")
    good.online, newbie.online = false, false
end

table.sort(frameSamples)
local p99 = frameSamples[math.max(1, math.floor(#frameSamples * 0.99))] or 0
local p999 = frameSamples[math.max(1, math.floor(#frameSamples * 0.999))] or 0
print(("frames with sync work: %d, 99th percentile %.2f ms, 99.9th %.2f ms, worst %.2f ms (%s)"):format(#frameSamples, p99, p999, maxFrame, tostring(maxWhat)))

-- One guild scan message, processed 2,000 times on one client, with garbage collection done first.
local bench = clients[40]
local body = Codec.enc(nowHour) .. ":"
local prev = 0
for id = 3001, 3020 do body = body .. Codec.encodeObs(prev, id, 4000 + id, 2); prev = id end
collectgarbage("collect")
local t0 = os.clock()
for i = 1, 2000 do bench.Stonks.Sync.acceptObsMessage(body, "Bench" .. (i % 7), true) end
local perMsg = (os.clock() - t0) / 2000 * 1000
print(("one 20-item scan message takes %.3f ms to read and store"):format(perMsg))
check(perMsg < 0.5, "a scan message costs well under the 1 ms frame budget")
check(p99 <= 1.5, ("99%% of frames with sync work stay near the 1 ms budget (%.2f ms)"):format(p99))
print(("\n%d checks, %d failed"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
