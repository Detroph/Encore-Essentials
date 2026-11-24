-- Encore-QoL: resurrection timer. Every graveyard's spirit healer resurrects the dead waiting there in waves 30
-- seconds apart, and each graveyard keeps its own beat. Encore learns a graveyard's beat when you (or a group
-- member running Encore) wait at its spirit healer, and shares it with the group by graveyard name. You come back
-- at the nearest graveyard your side holds, so that one leads: as a single timer, a timer with the graveyard's
-- name, or a list of all your side's graveyards. In the last 3 seconds it turns red and a "Die now" box shows
-- underneath. Idea from HighGround (MIT); no HighGround code is used.
local _, ns = ...
local Q = ns.QoL
local W = Q.W
local BG = Q.BG

local WAVE = 30
local LATE = 3
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local BOX_BG = { 0.08, 0.06, 0.04 }
local RED = { 1, 0.29, 0.23 }
local RED_TEXT = { 1, 0.54, 0.48 }

local function inBattleground()
    local _, kind = IsInInstance()
    return kind == "pvp"
end

---------------------------------------------------------------------------
-- Graveyard clocks
---------------------------------------------------------------------------
-- Starting graveyards that aren't map nodes.
local START_GY = { AB = { A = "Trollbane Hall", H = "Defiler's Den" } }

local clocks = {}      -- lower-case name -> { name, at = GetTime() of a wave, firstHand, x, y }
local lastSent = {}
local area = { left = nil, seen = 0, name = nil }
local answeredAt = 0

local function keyOf(name) return name and name:lower() end

local function leftOf(c, now)
    if not (c and c.at) then return nil end
    local l = WAVE - ((now - c.at) % WAVE)
    if l > WAVE - 0.05 then l = 0 end
    return l
end

local function playerPos()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    local p = map and C_Map.GetPlayerMapPosition(map, "player")
    if type(p) == "table" and p.GetXY then
        local x, y = p:GetXY()
        if x and y and (x > 0 or y > 0) then return x, y end
    end
end

local function encode(c, now)
    return ("%s~%.1f~%.4f~%.4f"):format(c.name, leftOf(c, now) or 0, c.x or -1, c.y or -1)
end

-- Sends clocks as "g:name~left~x~y;..." in pieces that fit an addon message.
local function sendClocks(list, now)
    local buf = ""
    for _, c in ipairs(list) do
        local item = encode(c, now)
        if #buf + #item + 3 > 240 then BG:Send("g:" .. buf) buf = "" end
        buf = buf == "" and item or (buf .. ";" .. item)
    end
    if buf ~= "" then BG:Send("g:" .. buf) end
end

local function learn(name, secondsLeft, firstHand, x, y)
    local k = keyOf(name)
    if not k then return end
    local c = clocks[k]
    if not c then c = { name = name }; clocks[k] = c end
    if x and x >= 0 and not (c.x and c.firstHand and not firstHand) then c.x, c.y = x, y end
    if c.firstHand and not firstHand then return end -- our own spirit healer beats a relayed time
    local now = GetTime()
    c.at = now + secondsLeft
    c.firstHand = firstHand or c.firstHand
    if firstHand and now - (lastSent[k] or 0) > 10 then
        lastSent[k] = now
        sendClocks({ c }, now)
    end
end

BG.onMessage.g = function(rest)
    answeredAt = GetTime()
    for item in rest:gmatch("[^;]+") do
        local name, l, x, y = item:match("^(.-)~([%d%.]+)~([%-%d%.]+)~([%-%d%.]+)$")
        l, x, y = tonumber(l), tonumber(x), tonumber(y)
        if name and name ~= "" and l and l >= 0 and l <= WAVE then
            learn(name, l, false, (x and x >= 0) and x or nil, (y and y >= 0) and y or nil)
        end
    end
end

-- "gr": someone just came in and asks for the clocks. One answer is enough, so wait a moment and stay quiet if
-- somebody else answers first.
BG.onMessage.gr = function()
    if not next(clocks) then return end
    local asked = GetTime()
    C_Timer.After(0.5 + math.random() * 2, function()
        if answeredAt >= asked then return end
        local list = {}
        for _, c in pairs(clocks) do if c.at then list[#list + 1] = c end end
        if #list > 0 then sendClocks(list, GetTime()) end
    end)
end

-- The graveyard you stand at: a map node whose name matches the subzone, or the subzone itself.
local function graveyardHere()
    local sub = GetSubZoneText and GetSubZoneText() or ""
    if sub == "" and GetMinimapZoneText then sub = GetMinimapZoneText() or "" end
    if sub == "" then return "Graveyard" end
    local low = sub:lower()
    for name in pairs(BG.nodes or {}) do
        local n = name:lower()
        if n == low or n:find(low, 1, true) or low:find(n, 1, true) then return name end
    end
    return sub
end

local function checkSpiritHealer()
    if not GetAreaSpiritHealerTime then return end
    local l = GetAreaSpiritHealerTime()
    if not (l and l > 0) then return end
    local now = GetTime()
    local name = graveyardHere()
    area.left, area.seen, area.name = l, now, name
    local c = clocks[keyOf(name)]
    local known = leftOf(c, now)
    if not (c and c.firstHand) or not known or math.abs(known - l) > 0.6 then
        local x, y = playerPos()
        learn(name, l, true, x, y)
    end
end

-- Your side's graveyards, the one you'd come back at first: nearest by map position, else soonest wave.
local function ourGraveyards(now)
    local me = BG:MySide()
    local list, seen = {}, {}
    local function add(name, x, y)
        local k = keyOf(name)
        if not k or seen[k] then return end
        seen[k] = true
        local c = clocks[k]
        list[#list + 1] = { name = name, left = leftOf(c, now), x = x or (c and c.x), y = y or (c and c.y) }
    end
    local start = START_GY[BG.kind or ""]
    if start then add(start[me]) end
    for name, n in pairs(BG.nodes or {}) do
        if (n.kind == "base" or n.kind == "gy") and n.owner == me and not n.contestedBy and not n.destroyed then
            add(name, n.pos and n.pos[1], n.pos and n.pos[2])
        end
    end
    -- Graveyards learned here that aren't map nodes (Warsong Gulch, starting graveyards, other battlegrounds).
    for k, c in pairs(clocks) do
        if not seen[k] and not (BG.nodes and BG.nodes[c.name]) then add(c.name) end
    end
    local px, py = playerPos()
    for _, g in ipairs(list) do g.d = (px and g.x) and ((g.x - px) ^ 2 + (g.y - py) ^ 2) or nil end
    table.sort(list, function(a, b)
        if a.d and b.d then return a.d < b.d end
        if a.d or b.d then return a.d ~= nil end
        if a.left and b.left then return a.left < b.left end
        if a.left or b.left then return a.left ~= nil end
        return a.name < b.name
    end)
    return list
end

local SAMPLE = {
    WSG = { { "Graveyard", 26 } },
    AB = { { "Lumber Mill", 4 }, { "Farm", 13 }, { "Gold Mine", nil }, { "Defiler's Den", 9 } },
    AV = { { "Iceblood Graveyard", 11 }, { "Frostwolf Graveyard", 22 }, { "Frostwolf Relief Hut", 6 }, { "Snowfall Graveyard", nil } },
}
local function sampleGraveyards(kind, now, start)
    local list = {}
    for _, s in ipairs(SAMPLE[kind] or SAMPLE.AB) do
        list[#list + 1] = { name = s[1], left = s[2] and (WAVE - ((now - start + WAVE - s[2]) % WAVE)) or nil }
    end
    return list
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local holder, f

local function font(fs, size, title)
    fs:SetFont(title and W.FONT_TITLE or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"), size, "OUTLINE")
end

local function circle(parent, layer, size, c, a, sub)
    local t = parent:CreateTexture(nil, layer, nil, sub or 0)
    t:SetTexture(CIRCLE)
    t:SetSize(size, size)
    t:SetPoint("CENTER")
    t:SetVertexColor(c[1], c[2], c[3], a or 1)
    return t
end

local function box(parent, w, h)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(w, h)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(BOX_BG[1], BOX_BG[2], BOX_BG[3], 0.92)
    W.Border(b, W.COPPER, 0.85)
    return b
end

local function buildRing(square)
    local r = CreateFrame("Frame", nil, holder)
    r:SetSize(84, 84)
    r:SetPoint("TOP")
    -- A 3 px copper border around a dark background, round or square.
    if square then
        local edge = r:CreateTexture(nil, "BACKGROUND", nil, 0)
        edge:SetColorTexture(W.COPPER[1], W.COPPER[2], W.COPPER[3], 0.95)
        edge:SetSize(78, 78)
        edge:SetPoint("CENTER")
        local fill = r:CreateTexture(nil, "BACKGROUND", nil, 1)
        fill:SetColorTexture(BOX_BG[1], BOX_BG[2], BOX_BG[3], 0.95)
        fill:SetSize(72, 72)
        fill:SetPoint("CENTER")
    else
        circle(r, "BACKGROUND", 82, W.COPPER, 0.95, 0)
        circle(r, "BACKGROUND", 76, BOX_BG, 0.95, 1)
    end
    local track = CreateFrame("Frame", nil, r)
    track:SetAllPoints()
    track:SetFrameLevel(r:GetFrameLevel() + 2)
    circle(track, "ARTWORK", 56, { 0, 0, 0 }, 0.65)
    local cd = CreateFrame("Cooldown", nil, track, "CooldownFrameTemplate")
    -- The template fills its whole parent; without this the swipe covers the border too.
    cd:ClearAllPoints()
    cd:SetSize(56, 56)
    cd:SetPoint("CENTER")
    if cd.SetSwipeTexture then cd:SetSwipeTexture(CIRCLE) end
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    cd:SetFrameLevel(track:GetFrameLevel() + 1)
    local top = CreateFrame("Frame", nil, r)
    top:SetAllPoints()
    top:SetFrameLevel(cd:GetFrameLevel() + 2)
    circle(top, "ARTWORK", 49, BOX_BG, 1)
    local num = top:CreateFontString(nil, "OVERLAY")
    font(num, 18, true)
    num:SetPoint("CENTER", 0, -1)
    num:SetWidth(44)
    num:SetJustifyH("CENTER")
    r.cd, r.num = cd, num
    function r:Draw(l, late)
        local waveStart = GetTime() + l - WAVE
        if not self.start or math.abs(self.start - waveStart) > 0.2 then
            self.start = waveStart
            self.cd:SetCooldown(waveStart, WAVE)
        end
        local c = late and RED or W.GOLD
        if self.cd.SetSwipeColor then self.cd:SetSwipeColor(c[1], c[2], c[3], 1) end
        self.num:SetText(math.ceil(l))
        W.Color(self.num, late and RED_TEXT or W.GOLD)
    end
    return r
end

local MAX_LIST = 10
local ROW_H = 22

-- The graveyard list: your side's graveyards, the one you'd come back at on top in gold.
local function buildList()
    local b = box(holder, 210, 30)
    b:SetPoint("TOP")
    local title = b:CreateFontString(nil, "OVERLAY")
    font(title, 13, true)
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("Resurrection")
    W.Color(title, W.GOLD)
    b.rows = {}
    for i = 1, MAX_LIST do
        local r = CreateFrame("Frame", nil, b)
        r:SetSize(194, ROW_H)
        r:SetPoint("TOPLEFT", 8, -24 - (i - 1) * ROW_H)
        r.mark = r:CreateFontString(nil, "OVERLAY")
        font(r.mark, 11, false)
        r.mark:SetPoint("TOPLEFT", 0, -3)
        r.mark:SetText(">")
        r.name = r:CreateFontString(nil, "OVERLAY")
        font(r.name, 12, false)
        r.name:SetPoint("TOPLEFT", 12, -3)
        r.name:SetSize(146, 14)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.time = r:CreateFontString(nil, "OVERLAY")
        font(r.time, 13, true)
        r.time:SetPoint("TOPRIGHT", 0, -2)
        r.time:SetSize(32, 15)
        r.time:SetJustifyH("RIGHT")
        r.track = r:CreateTexture(nil, "ARTWORK")
        r.track:SetColorTexture(0, 0, 0, 0.6)
        r.track:SetPoint("BOTTOMLEFT", 12, 2)
        r.track:SetPoint("BOTTOMRIGHT", -36, 2)
        r.track:SetHeight(3)
        r.fill = r:CreateTexture(nil, "ARTWORK", nil, 1)
        r.fill:SetTexture(WHITE)
        r.fill:SetPoint("TOPLEFT", r.track)
        r.fill:SetPoint("BOTTOMLEFT", r.track)
        r:Hide()
        b.rows[i] = r
    end
    function b:DrawList(list)
        local n = math.min(#list, MAX_LIST)
        for i = 1, MAX_LIST do
            local r, g = self.rows[i], list[i]
            if i <= n then
                local l = g.left
                local late = l and l <= LATE
                local c = (late and RED_TEXT) or (i == 1 and W.GOLD) or W.INK
                r.mark:SetShown(i == 1)
                W.Color(r.mark, W.GOLD)
                r.name:SetText(g.name)
                W.Color(r.name, c)
                r.time:SetText(l and math.ceil(l) or "?")
                W.Color(r.time, (late and RED_TEXT) or (l and W.GOLD) or W.DIM)
                local fc = late and RED or (i == 1 and W.GOLD) or { 0.64, 0.54, 0.32 }
                r.fill:SetVertexColor(fc[1], fc[2], fc[3], 1)
                r.fill:SetWidth(math.max(0.01, 146 * (l and (1 - l / WAVE) or 0)))
                r:Show()
            else
                r:Hide()
            end
        end
        self:SetHeight(28 + math.max(n, 1) * ROW_H)
    end
    return b
end

local BUILD = { round = function() return buildRing(false) end, square = function() return buildRing(true) end, list = buildList }

local function savedPos()
    local t = Q.db.frames.resTimer
    if type(t) ~= "table" then t = {}; Q.db.frames.resTimer = t end
    return t
end

local function placeHolder()
    holder:ClearAllPoints()
    local p = savedPos().point
    if type(p) == "table" and p[1] then holder:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else holder:SetPoint("CENTER", UIParent, "CENTER", 0, 160) end
end

local function makeHolder()
    holder = CreateFrame("Frame", "EncoreQoLResTimer", UIParent)
    holder:SetSize(80, 80)
    holder:SetFrameStrata("MEDIUM")
    holder:SetClampedToScreen(true)
    holder:SetMovable(true)
    holder:EnableMouse(true)
    holder:RegisterForDrag("LeftButton")
    holder:Hide()
    holder.styles = {}
    holder:SetScript("OnDragStart", function(self) if not f:Get("locked") then self:StartMoving() end end)
    holder:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        savedPos().point = { p, rp, x, y }
    end)
    -- Right-click locks or unlocks.
    holder:SetScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" then return end
        local lock = not f:Get("locked")
        f:Set("locked", lock)
        Q:Print(lock and "Resurrection timer locked. Right-click it again to move it." or "Resurrection timer unlocked: drag it to move it, right-click to lock.")
    end)

    -- Dashed-look outline and a label while unlocked.
    holder.mover = CreateFrame("Frame", nil, holder)
    holder.mover:SetPoint("TOPLEFT", -4, 4)
    holder.mover:SetPoint("BOTTOMRIGHT", 4, -4)
    holder.mover:SetFrameLevel(holder:GetFrameLevel() + 20)
    W.Border(holder.mover, W.GOLD, 0.9, "OVERLAY")
    local tag = holder.mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tag:SetPoint("BOTTOM", holder.mover, "TOP", 0, 3)
    tag:SetText("Drag to move · right-click to lock")

    holder.die = box(holder, 96, 24)
    holder.die:SetPoint("TOP", holder, "BOTTOM", 0, -6)
    local dt = holder.die:CreateFontString(nil, "OVERLAY")
    font(dt, 13, true)
    dt:SetPoint("CENTER")
    dt:SetText("Die now")
    W.Color(dt, RED)
    holder.die:Hide()

    holder:SetScript("OnUpdate", function(self, elapsed)
        self.acc = (self.acc or 0) + elapsed
        if self.acc < 0.05 then return end
        self.acc = 0
        if f then f:Draw() end
    end)
    placeHolder()
end

---------------------------------------------------------------------------
-- Feature
---------------------------------------------------------------------------
local previewAt

f = Q.PvPScoped({
    id = "resTimer", tab = "pvp", section = "Battleground timers", name = "Resurrection timer",
    desc = "Each graveyard's spirit healer brings the dead back every 30 seconds on its own clock. A list of your side's graveyards counts down to each one's next wave, dead or alive, with the one you'd come back at (the nearest) on top. Red in the last 3 seconds with a \"Die now\" box underneath. Clocks are learned at the spirit healer and shared with your battleground group; a graveyard nobody has waited at yet shows \"?\".",
    defaults = { scale = 100, dieNow = true, onlyDead = false, wsgRing = true, ringBg = "round", locked = false },
    detect = { { addon = "HighGround" } },
    options = {
        { kind = "group", text = "Look" },
        { kind = "slider", key = "scale", name = "Size", min = 50, max = 200, step = 5, fmt = function(v) return v .. "%" end },
        { kind = "check", key = "dieNow", name = "\"Die now\" box in the last 3 seconds" },
        { kind = "check", key = "onlyDead", name = "Show only while I'm dead" },
        { kind = "group", text = "Warsong Gulch" },
        { kind = "check", key = "wsgRing", name = "Round timer instead of the list" },
        { kind = "choice", key = "ringBg", name = "Timer background", choices = { { "round", "Round" }, { "square", "Square" } } },
        { kind = "group", text = "Position" },
        { kind = "check", key = "locked", name = "Lock position" },
        { kind = "button", name = "Preview", always = true, onClick = function(self) self:Preview(not self.previewing) end },
        { kind = "button", name = "Reset position", always = true, onClick = function() savedPos().point = nil if holder then placeHolder() end end },
        { kind = "note", text = "Unlocked, drag the timer to move it. Right-click the timer to lock or unlock it. Preview shows the battleground picked above under Customize for each battleground (Warsong Gulch when that's off)." },
    },
}, { "scale", "dieNow", "onlyDead" })

local function show(name)
    for k, s in pairs(holder.styles) do if k ~= name then s:Hide() end end
    local s = holder.styles[name]
    if not s then
        s = BUILD[name]()
        holder.styles[name] = s
    end
    s:Show()
    return s
end

function f:Draw()
    if not holder then return end
    local now = GetTime()
    local live = self.active and inBattleground()
    local dead = UnitIsDeadOrGhost("player")
    local kind, list
    if live then
        if not dead and self:Live("onlyDead") then holder:Hide() return end
        kind = BG.kind
        list = ourGraveyards(now)
        if #list == 0 then holder:Hide() return end
    elseif self.previewing then
        kind = self:Saved().perBG and (self:Saved().editBG or "WSG") or "WSG"
        previewAt = previewAt or now
        list = sampleGraveyards(kind, now, previewAt)
        dead = false
    else
        holder:Hide()
        return
    end

    local first = list[1]
    local ring = kind == "WSG" and self:Get("wsgRing")
    local s
    if ring then
        if not first.left then holder:Hide() return end
        s = show(self:Get("ringBg") == "square" and "square" or "round")
        s:Draw(first.left, first.left <= LATE)
    else
        s = show("list")
        s:DrawList(list)
    end
    holder:SetSize(s:GetWidth(), s:GetHeight())
    local scale = (tonumber(self:Live("scale")) or 100) / 100
    if math.abs(holder:GetScale() - scale) > 0.001 then holder:SetScale(scale) end
    local late = first.left and first.left <= LATE
    holder.die:SetShown(late and not dead and self:Live("dieNow") and true or false)
    holder.mover:SetShown(not self:Get("locked"))
    holder:Show()
end

function f:Preview(on)
    if not holder then makeHolder() end
    self.previewing = on
    previewAt = nil
    self:Draw()
end

local lastInBG
local function zone()
    local inside = inBattleground()
    local here = inside and (select(8, GetInstanceInfo()) or 0) or false
    if here ~= lastInBG then
        lastInBG = here
        wipe(clocks)
        wipe(lastSent)
        if inside then C_Timer.After(4, function() if inBattleground() and not next(clocks) then BG:Send("gr") end end) end
    end
end

function f:Enable()
    if not holder then makeHolder() end
    BG:Use()
    lastInBG = nil
    zone()
    self:On("PLAYER_ENTERING_WORLD", zone)
    self:On("ZONE_CHANGED_NEW_AREA", zone)
    -- Coming back to life at a spirit healer means that graveyard's wave just happened.
    local function alive()
        if inBattleground() and area.left and GetTime() - area.seen < 2 and area.left < 2 then learn(area.name, 0, true, playerPos()) end
        area.left = nil
    end
    self:On("PLAYER_ALIVE", alive)
    self:On("PLAYER_UNGHOST", alive)
    self:On("AREA_SPIRIT_HEALER_IN_RANGE", checkSpiritHealer)
    self:Ticker(0.25, function()
        if inBattleground() and UnitIsDeadOrGhost("player") then checkSpiritHealer() end
        self:Draw()
    end)
    self:Draw()
end

function f:OnOption() self:Draw() end

function f:Disable()
    BG:Release()
    if holder and not self.previewing then holder:Hide() end
end

Q:Feature(f)

-- For tests.
Q.ResClocks = clocks
Q.ResLearn = learn
Q.ResGraveyards = ourGraveyards
