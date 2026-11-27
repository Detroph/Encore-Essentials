-- Encore Essentials: dungeon prep. Group members with Encore tell each other which quests are in their quest log
-- (quest IDs only, in party, raid or instance chat), so Encore-DB's dungeon quest lists can show who in the group
-- has each quest. Sent when you join a group and when your quest log changes, at most every 5 seconds.
local _, ns = ...
local Encore = ns.Encore

local PREFIX = "EncoreQL"
local MAX = 240
local members = {} -- [short name] = { [questID] = true }
local building = {}
Encore.groupQuests = members

local function channel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

local function myQuests()
    local ids = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID and info.questID > 0 then ids[#ids + 1] = info.questID end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, GetNumQuestLogEntries() do
            local _, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
            if not isHeader and id and id > 0 then ids[#ids + 1] = id end
        end
    end
    return ids
end

local function send()
    local ch = channel()
    if not ch then return end
    local ids = myQuests()
    local chunks, cur = {}, {}
    local len = 0
    for _, id in ipairs(ids) do
        local s = tostring(id)
        if len + #s + 1 > MAX then chunks[#chunks + 1] = table.concat(cur, ","); cur, len = {}, 0 end
        cur[#cur + 1] = s
        len = len + #s + 1
    end
    chunks[#chunks + 1] = table.concat(cur, ",")
    for i, c in ipairs(chunks) do
        local head = (i == 1 and "L" or "+") .. (i == #chunks and "." or "")
        C_ChatInfo.SendAddonMessage(PREFIX, head .. c, ch)
    end
end

local pending = false
local function sendSoon(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay or 5, function() pending = false; send() end)
end

local function short(name) return Ambiguate and Ambiguate(name or "", "short") or name end

local function onMessage(prefix, msg, _, sender)
    if prefix ~= PREFIX or type(msg) ~= "string" then return end
    local who = short(sender)
    -- Our own messages come back with the whole name on WoW Forever ("Berya Ebonlocke"), not UnitName's first name.
    if who == short(Encore.FullName("player")) or who == short(UnitName("player")) then return end
    if msg == "?" then sendSoon(1 + math.random() * 2) return end
    local kind, last, body = msg:match("^([L%+])(%.?)(.*)$")
    if not kind then return end
    if kind == "L" then building[who] = {} end
    local t = building[who]
    if not t then return end
    for id in body:gmatch("%d+") do t[tonumber(id)] = true end
    if last == "." then
        members[who], building[who] = t, nil
        if Encore.OnGroupQuests then Encore:OnGroupQuests(who) end
    end
end

-- Group members (short names) who have this quest in their log.
function Encore:GroupQuestHolders(id)
    local list = {}
    for who, t in pairs(members) do if t[id] then list[#list + 1] = who end end
    table.sort(list)
    return list
end

local f = CreateFrame("Frame")
local wasInGroup = false
f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    local ok, err = pcall(function()
        if event == "CHAT_MSG_ADDON" then
            onMessage(a1, a2, a3, a4)
        elseif event == "PLAYER_LOGIN" then
            if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
            for _, e in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
                pcall(f.RegisterEvent, f, e)
            end
            wasInGroup = channel() ~= nil
            if wasInGroup then sendSoon(8) end
        elseif event == "GROUP_ROSTER_UPDATE" then
            local inGroup = channel() ~= nil
            -- Forget players who left
            for who in pairs(members) do
                if not (UnitInParty(who) or UnitInRaid(who)) then members[who] = nil end
            end
            if inGroup and not wasInGroup then
                sendSoon(2)
                C_Timer.After(2.5, function() local ch = channel() if ch then C_ChatInfo.SendAddonMessage(PREFIX, "?", ch) end end)
            end
            if not inGroup then wipe(members) end
            wasInGroup = inGroup
        else
            sendSoon(5)
        end
    end)
    if not ok then geterrorhandler()(err) end
end)
f:RegisterEvent("PLAYER_LOGIN")
