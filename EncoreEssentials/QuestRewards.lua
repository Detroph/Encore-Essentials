-- Encore Essentials: remembers quest rewards the game shows you, for Encore-DB's quest list.
-- When a quest giver offers a quest or hands out its reward, and for the quests in your log, the game knows the
-- exact XP, money and reward items (and which of them are a choice). This file notes them in the saved data
-- (EncoreEssentialsDB.questRewards), so Encore-DB can show them even for quests you are not on any more.
-- It lives in the core addon because Encore-DB only loads when you open it.
local _, ns = ...
local Encore = ns.Encore

local QR = {}
Encore.QuestRewards = QR
QR.version = 0 -- goes up with every change, so Encore-DB knows to read the notes again

local function store()
    local db = _G.EncoreEssentialsDB
    if type(db) ~= "table" then return nil end
    if type(db.questRewards) ~= "table" then db.questRewards = {} end
    return db.questRewards
end

function QR:All()
    return store() or {}
end

local function itemIdFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- One list of reward items: { { itemID, count }, ... } read with the given API functions.
local function readList(n, link, info)
    local out = {}
    for i = 1, n or 0 do
        local id = itemIdFromLink(link(i))
        local count = 1
        local ok, name, _, c, _, _, infoId = pcall(info, i)
        if ok then
            count = tonumber(c) or 1
            id = id or tonumber(infoId)
        end
        if not id then return nil end -- not loaded yet; try again another time
        out[#out + 1] = count > 1 and { id, count } or id
    end
    return out
end

local function save(questID, rec)
    local all = store()
    if not all or not questID or questID <= 0 or not rec then return end
    rec.at = time()
    rec.lvl = UnitLevel and UnitLevel("player") or nil
    local old = all[questID]
    -- Keep XP seen at a lower level: XP falls once the quest is grey for you.
    if old and old.xp and old.lvl and rec.lvl and old.lvl < rec.lvl then
        rec.xp, rec.lvl = old.xp, old.lvl
    end
    all[questID] = rec
    QR.version = QR.version + 1
end

local function numberOrNil(v)
    v = tonumber(v)
    return (v and v > 0) and v or nil
end

-- The quest giver's window (offer or turn-in).
local function fromGiver()
    local questID = GetQuestID and GetQuestID()
    if not questID or questID == 0 then return end
    local rewards = readList(GetNumQuestRewards and GetNumQuestRewards() or 0,
        function(i) return GetQuestItemLink("reward", i) end,
        function(i) return GetQuestItemInfo("reward", i) end)
    local choice = readList(GetNumQuestChoices and GetNumQuestChoices() or 0,
        function(i) return GetQuestItemLink("choice", i) end,
        function(i) return GetQuestItemInfo("choice", i) end)
    if not rewards or not choice then return end
    save(questID, {
        xp = numberOrNil(GetRewardXP and GetRewardXP()),
        money = numberOrNil(GetRewardMoney and GetRewardMoney()),
        rewards = #rewards > 0 and rewards or nil,
        choice = #choice > 0 and choice or nil,
    })
end

-- A quest in the log. The log's reward functions read the selected quest, so the selection is put back after.
local function fromLog(questID)
    if not (C_QuestLog and C_QuestLog.SetSelectedQuest and C_QuestLog.GetSelectedQuest) then return end
    if not GetNumQuestLogRewards or not GetQuestLogItemLink then return end
    local before = C_QuestLog.GetSelectedQuest()
    C_QuestLog.SetSelectedQuest(questID)
    local rewards = readList(GetNumQuestLogRewards(),
        function(i) return GetQuestLogItemLink("reward", i) end,
        function(i) return GetQuestLogRewardInfo(i) end)
    local choice = readList(GetNumQuestLogChoices and GetNumQuestLogChoices() or 0,
        function(i) return GetQuestLogItemLink("choice", i) end,
        function(i) return GetQuestLogChoiceInfo(i) end)
    local xp = GetQuestLogRewardXP and GetQuestLogRewardXP()
    local money = GetQuestLogRewardMoney and GetQuestLogRewardMoney()
    if before and before ~= questID then C_QuestLog.SetSelectedQuest(before) end
    if not rewards or not choice then return end
    save(questID, {
        xp = numberOrNil(xp), money = numberOrNil(money),
        rewards = #rewards > 0 and rewards or nil,
        choice = #choice > 0 and choice or nil,
    })
end

local function scanLog()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return end
    -- Not while the quest log or map is open: changing the selection would show in it.
    if (QuestLogFrame and QuestLogFrame:IsShown()) or (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and info.questID > 0 then
            pcall(fromLog, info.questID)
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("QUEST_DETAIL")
f:RegisterEvent("QUEST_COMPLETE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("QUEST_ACCEPTED")
f:SetScript("OnEvent", function(_, event, a)
    if event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then
        pcall(fromGiver)
        -- Item links can arrive a moment later; read again once they are in.
        C_Timer.After(1, function() pcall(fromGiver) end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(5, scanLog)
    elseif event == "QUEST_ACCEPTED" then
        C_Timer.After(1, scanLog)
    end
end)
