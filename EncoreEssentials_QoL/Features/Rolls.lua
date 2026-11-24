-- Encore-QoL: "Who rolled what". A small window beside each group loot roll that lists who picked Need, Greed,
-- Disenchant or Pass, the number each one rolled and who won. It reads the game's own loot roll chat lines (with
-- the client's own text, so any language works) and stays on screen a little while after the roll ends.
local _, ns = ...
local Q = ns.QoL
local W = Q.W

local CHOICE = {
    need = { text = "Need", icon = "Interface\\Buttons\\UI-GroupLoot-Dice-Up", color = { 0.25, 0.9, 0.3 }, order = 1 },
    greed = { text = "Greed", icon = "Interface\\Buttons\\UI-GroupLoot-Coin-Up", color = { 1, 0.82, 0 }, order = 2 },
    de = { text = "Disenchant", icon = "Interface\\Buttons\\UI-GroupLoot-DE-Up", color = { 0.7, 0.5, 1 }, order = 3 },
    pass = { text = "Pass", icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", color = { 0.6, 0.6, 0.6 }, order = 4 },
}

-- Turns a game format string ("%s has selected Need for: %s", "%1$s ...") into a Lua pattern and the order of its
-- values, so the same code reads every client language.
local function pattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local order, n = {}, 0
    local p = fmt:gsub("[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    p = p:gsub("%%%%(%d)%%%$([sd])", function(i, k)
        order[#order + 1] = tonumber(i)
        return k == "d" and "(%d+)" or "(.+)"
    end)
    p = p:gsub("%%%%([sd])", function(k)
        n = n + 1
        order[#order + 1] = n
        return k == "d" and "(%d+)" or "(.+)"
    end)
    return "^" .. p .. "$", order
end

-- { global name, what it means, which values: player, item, roll }
local LINES = {
    { "LOOT_ROLL_NEED", "need", { "who", "item" } },
    { "LOOT_ROLL_GREED", "greed", { "who", "item" } },
    { "LOOT_ROLL_DISENCHANT", "de", { "who", "item" } },
    { "LOOT_ROLL_PASSED", "pass", { "who", "item" } },
    { "LOOT_ROLL_PASSED_AUTO", "pass", { "who", "item" } },
    { "LOOT_ROLL_PASSED_AUTO_FEMALE", "pass", { "who", "item" } },
    { "LOOT_ROLL_NEED_SELF", "need", { "item" }, self = true },
    { "LOOT_ROLL_GREED_SELF", "greed", { "item" }, self = true },
    { "LOOT_ROLL_DISENCHANT_SELF", "de", { "item" }, self = true },
    { "LOOT_ROLL_PASSED_SELF", "pass", { "item" }, self = true },
    { "LOOT_ROLL_PASSED_SELF_AUTO", "pass", { "item" }, self = true },
    { "LOOT_ROLL_ROLLED_NEED", "rolled", { "roll", "item", "who" }, choice = "need" },
    { "LOOT_ROLL_ROLLED_GREED", "rolled", { "roll", "item", "who" }, choice = "greed" },
    { "LOOT_ROLL_ROLLED_DE", "rolled", { "roll", "item", "who" }, choice = "de" },
    { "LOOT_ROLL_WON", "won", { "who", "item" } },
    { "LOOT_ROLL_YOU_WON", "won", { "item" }, self = true },
    { "LOOT_ROLL_ALL_PASSED", "allpassed", { "item" } },
}
local parsers
local function buildParsers()
    parsers = {}
    for _, l in ipairs(LINES) do
        local p, order = pattern(_G[l[1]])
        if p then parsers[#parsers + 1] = { pat = p, order = order, kind = l[2], fields = l[3], self = l.self, choice = l.choice } end
    end
    -- Longest first, so "automatically passed on" is tried before "passed on".
    table.sort(parsers, function(a, b) return #a.pat > #b.pat end)
end

local function parse(msg)
    if not parsers then buildParsers() end
    for _, p in ipairs(parsers) do
        local caps = { msg:match(p.pat) }
        if caps[1] then
            local out = { kind = p.kind, choice = p.choice }
            -- order[c] = which value of the format the c-th capture is
            for c, arg in ipairs(p.order) do
                local field = p.fields[arg]
                if field then out[field] = caps[c] end
            end
            if p.self then out.who = Q.FullName("player") end
            if out.who then out.who = Ambiguate(out.who, "none") end
            out.roll = tonumber(out.roll)
            return out
        end
    end
end

local function itemID(link) return link and tonumber(link:match("item:(%d+)")) end

---------------------------------------------------------------------------
-- Rolls: one per rollID while the game shows it, kept a while after it ends.
---------------------------------------------------------------------------
local rolls = {}   -- rollID -> roll
local order = {}   -- open rolls, oldest first

local function roster()
    local list = {}
    local function add(unit)
        local name = Q.FullName(unit)
        if name then
            local _, class = UnitClass(unit)
            list[name] = class or false
        end
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do add("raid" .. i) end
    else
        add("player")
        for i = 1, GetNumSubgroupMembers() do add("party" .. i) end
    end
    return list
end

-- The roll a chat line belongs to: same item, oldest first, preferring one where this player hasn't chosen yet.
local function rollFor(link, who)
    local id = itemID(link)
    local fallback
    for _, r in ipairs(order) do
        if r.itemID == id and not r.over then
            if not who or not r.players[who] then return r end
            fallback = fallback or r
        end
    end
    if fallback then return fallback end
    -- Results can arrive just after the game closes the roll.
    for i = #order, 1, -1 do
        local r = order[i]
        if r.itemID == id then return r end
    end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local pool = {}
local WIDTH, ROW = 230, 18

local function lootFrameFor(rollID)
    local container = _G.GroupLootContainer
    if type(container) == "table" and type(container.rollFrames) == "table" then
        for _, fr in pairs(container.rollFrames) do
            if fr and fr.rollID == rollID and fr:IsShown() then return fr end
        end
    end
    for i = 1, tonumber(NUM_GROUP_LOOT_FRAMES) or 4 do
        local fr = _G["GroupLootFrame" .. i]
        if fr and fr.rollID == rollID and fr:IsShown() then return fr end
    end
end

local function newWindow()
    local w = CreateFrame("Frame", nil, UIParent)
    w:SetSize(WIDTH, 60)
    w:SetFrameStrata("HIGH")
    W.Panel(w, 0.92)
    w:EnableMouse(true)
    w:SetMovable(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() self.moved = true end)

    w.icon = CreateFrame("Button", nil, w)
    w.icon:SetSize(22, 22)
    w.icon:SetPoint("TOPLEFT", 6, -6)
    w.icon.tex = w.icon:CreateTexture(nil, "ARTWORK")
    w.icon.tex:SetAllPoints()
    w.icon:SetScript("OnEnter", function(self)
        if not w.roll then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(w.roll.link)
        GameTooltip:Show()
    end)
    w.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    w.title = W.Text(w, "GameFontNormalSmall", "")
    w.title:SetPoint("TOPLEFT", w.icon, "TOPRIGHT", 6, -1)
    w.title:SetPoint("RIGHT", -24, 0)
    w.title:SetWordWrap(false)
    w.status = W.Text(w, "GameFontHighlightSmall", "", W.DIM)
    w.status:SetPoint("TOPLEFT", w.title, "BOTTOMLEFT", 0, -2)
    w.status:SetPoint("RIGHT", -8, 0)
    w.status:SetWordWrap(false)
    w.close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    w.close:SetSize(20, 20)
    w.close:SetPoint("TOPRIGHT", 0, 0)
    w.close:SetScript("OnClick", function() if w.roll then w.roll.dismissed = true end w:Hide() end)
    w.rows = {}
    return w
end

local function rowFor(w, i)
    local r = w.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, w)
    r:SetSize(WIDTH - 12, ROW)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT", 2, 0)
    r.name = W.Text(r, "GameFontHighlightSmall", "")
    r.name:SetPoint("LEFT", 20, 0)
    r.name:SetPoint("RIGHT", -70, 0)
    r.name:SetWordWrap(false)
    r.choice = W.Text(r, "GameFontHighlightSmall", "")
    r.choice:SetPoint("RIGHT", -30, 0)
    r.roll = W.Text(r, "GameFontNormal", "", W.GOLD)
    r.roll:SetPoint("RIGHT", -2, 0)
    r.roll:SetJustifyH("RIGHT")
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(self.tip[1], 1, 0.82, 0)
        for i = 2, #self.tip do GameTooltip:AddLine(self.tip[i], 0.95, 0.9, 0.81, true) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    w.rows[i] = r
    return r
end

local function classColor(class)
    local c = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
    return c and { c.r, c.g, c.b } or W.INK
end

local feature

local function draw(r)
    local w = r.window
    if not w then
        w = table.remove(pool) or newWindow()
        r.window, w.roll, w.moved = w, r, false
    end
    -- Beside the game's roll frame while it shows; afterwards it stays where it was.
    if not w.moved then
        local lf = lootFrameFor(r.id)
        if lf then
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", lf, "TOPRIGHT", 4, 0)
            r.anchored = true
        elseif not r.anchored then
            w:ClearAllPoints()
            local idx = 0
            for i, o in ipairs(order) do if o == r then idx = i end end
            w:SetPoint("TOPLEFT", UIParent, "CENTER", 220, 200 - (idx - 1) * 110)
            r.anchored = true
        elseif w:GetNumPoints() > 0 then
            local left, top = w:GetLeft(), w:GetTop()
            if left and top then
                w:ClearAllPoints()
                w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
        end
    end

    local name, _, quality = Q.GetItemInfo(r.link)
    local qualityColor = (C_Item and C_Item.GetItemQualityColor) or _G.GetItemQualityColor
    local hex = qualityColor and select(4, qualityColor(quality or 1))
    w.icon.tex:SetTexture(r.texture or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.itemID)) or 134400)
    w.title:SetText((hex and ("|c" .. hex) or "") .. (name or r.link or "?") .. "|r")

    local list, members = {}, roster()
    for who, p in pairs(r.players) do list[#list + 1] = { who = who, p = p } end
    table.sort(list, function(a, b)
        if a.p.won ~= b.p.won then return a.p.won == true end
        local ca, cb = CHOICE[a.p.choice].order, CHOICE[b.p.choice].order
        if ca ~= cb then return ca < cb end
        if (a.p.roll or -1) ~= (b.p.roll or -1) then return (a.p.roll or -1) > (b.p.roll or -1) end
        return a.who < b.who
    end)
    local waiting = {}
    if feature:Get("waiting") and not r.over then
        for who in pairs(members) do if not r.players[who] then waiting[#waiting + 1] = who end end
        table.sort(waiting)
    end

    if r.winner then
        w.status:SetText((r.winner == Q.FullName("player") and "You won" or (r.winner .. " won")))
        W.Color(w.status, W.GOLD)
    elseif r.allPassed then
        w.status:SetText("Everyone passed")
        W.Color(w.status, W.DIM)
    else
        local left = r.ends and math.max(0, math.floor(r.ends - GetTime())) or nil
        w.status:SetText((#waiting > 0 and (#waiting .. " still choosing") or "Waiting for the rolls") .. (left and not r.over and ("  ·  " .. left .. " s") or ""))
        W.Color(w.status, W.DIM)
    end

    local y = -34
    local n = 0
    for _, e in ipairs(list) do
        n = n + 1
        local row = rowFor(w, n)
        local c = CHOICE[e.p.choice]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, y)
        row.icon:SetTexture(c.icon)
        row.icon:SetDesaturated(false)
        row.name:SetText(e.who == Q.FullName("player") and (e.who .. " (you)") or e.who)
        W.Color(row.name, classColor(members[e.who]))
        row.choice:SetText(c.text)
        W.Color(row.choice, c.color)
        row.roll:SetText(e.p.roll and tostring(e.p.roll) or (e.p.choice == "pass" and "" or "…"))
        row.bg:SetColorTexture(1, 0.82, 0, e.p.won and 0.18 or 0)
        row.tip = { e.who, c.text .. (e.p.roll and (", rolled " .. e.p.roll) or ""), e.p.won and "Won the item." or nil }
        row:Show()
        y = y - ROW
    end
    for _, who in ipairs(waiting) do
        n = n + 1
        local row = rowFor(w, n)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, y)
        row.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Up")
        row.icon:SetDesaturated(true)
        row.name:SetText(who)
        W.Color(row.name, W.DIM)
        row.choice:SetText("choosing")
        W.Color(row.choice, W.DIM)
        row.roll:SetText("")
        row.bg:SetColorTexture(0, 0, 0, 0)
        row.tip = { who, "Hasn't picked Need, Greed or Pass yet." }
        row:Show()
        y = y - ROW
    end
    for i = n + 1, #w.rows do w.rows[i]:Hide() end
    w:SetHeight(-y + 6)
    w:Show()
end

local function release(r)
    if r.window then
        r.window:Hide()
        r.window.roll = nil
        pool[#pool + 1] = r.window
        r.window = nil
    end
    rolls[r.id] = nil
    for i, o in ipairs(order) do if o == r then table.remove(order, i) break end end
end

local function finish(r)
    if r.over then return end
    r.over = true
    local keep = feature:Get("keep") or 20
    r.doneAt = GetTime()
    C_Timer.After(keep, function()
        if rolls[r.id] == r then release(r) end
    end)
end

local function redraw(r)
    if r.dismissed then return end
    local ok, err = pcall(draw, r)
    if not ok then geterrorhandler()(err) end
end

feature = Q:Feature{
    id = "whoRolled", tab = "qol", section = "Loot and bags", name = "Who rolled what",
    desc = "A small window next to each group loot roll: who picked Need, Greed or Pass, what each one rolled, who won, and who is still choosing.",
    defaults = { keep = 20, waiting = true },
    options = {
        { kind = "check", key = "waiting", name = "Show who is still choosing" },
        { kind = "slider", key = "keep", name = "Stays after the roll ends", min = 5, max = 120, step = 5, fmt = function(v) return v .. " s" end },
        { kind = "note", text = "Drag a window to move it; the cross closes it. Hover the item for its tooltip." },
    },
    detect = { { addon = "RollTracker" }, { addon = "RollTrackerClassic" }, { addon = "LootRollTracker" } },
    Enable = function(f)
        f:On("START_LOOT_ROLL", function(_, rollID, rollTime)
            local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
            if not link then return end
            local texture = GetLootRollItemInfo and GetLootRollItemInfo(rollID)
            local r = { id = rollID, link = link, itemID = itemID(link), texture = texture, players = {}, ends = rollTime and (GetTime() + rollTime / 1000) or nil }
            rolls[rollID] = r
            order[#order + 1] = r
            -- The game places its frame a moment later.
            C_Timer.After(0.05, function() if rolls[rollID] == r then redraw(r) end end)
        end)
        f:On("CANCEL_LOOT_ROLL", function(_, rollID)
            local r = rolls[rollID]
            if r then
                -- Results keep arriving for a few seconds; the window stays put.
                C_Timer.After(8, function() if rolls[rollID] == r then finish(r) end end)
            end
        end)
        f:On("CHAT_MSG_LOOT", function(_, msg)
            local m = msg and parse(msg)
            if not m or not m.item then return end
            local r = rollFor(m.item, (m.kind ~= "rolled" and m.kind ~= "won") and m.who or nil)
            if not r then return end
            if m.kind == "allpassed" then
                r.allPassed = true
                finish(r)
            elseif m.kind == "won" then
                r.winner = m.who
                local p = r.players[m.who] or { choice = "need" }
                p.won = true
                r.players[m.who] = p
                finish(r)
            elseif m.kind == "rolled" then
                local p = r.players[m.who] or {}
                p.choice, p.roll = m.choice, m.roll
                r.players[m.who] = p
            elseif m.who then
                local p = r.players[m.who] or {}
                p.choice = m.kind
                r.players[m.who] = p
            end
            redraw(r)
        end)
        f:Ticker(1, function()
            for _, r in ipairs(order) do
                if not r.over and r.window and r.window:IsShown() then redraw(r) end
            end
        end)
    end,
    Disable = function()
        for i = #order, 1, -1 do release(order[i]) end
    end,
}

-- For the preview in tests: parse one chat line.
Q.ParseRollLine = parse
