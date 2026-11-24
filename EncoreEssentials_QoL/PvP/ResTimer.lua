-- Encore-QoL: resurrection timer. Spirit healers in a battleground resurrect everyone waiting in one 30 second
-- wave, and the waves keep the same beat for the whole battleground. Once Encore knows the beat (from your own
-- spirit healer, or from a group member running Encore), it counts down to the next wave all the time: while you
-- are dead, and while you are alive, so you can die just before a wave. In the last 3 seconds it turns red and a
-- "Die now" box shows underneath. Idea from HighGround (MIT); no HighGround code is used.
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
-- The beat
---------------------------------------------------------------------------
local beat = { at = nil, firstHand = false } -- at = GetTime() of a wave
local lastSent, lastAreaLeft, lastAreaSeen = 0, nil, 0
local answeredAt = 0

local function left(now)
    if not beat.at then return nil end
    local l = WAVE - ((now - beat.at) % WAVE)
    if l > WAVE - 0.05 then l = 0 end
    return l
end

local function learn(secondsLeft, firstHand)
    local now = GetTime()
    beat.at = now + secondsLeft
    beat.firstHand = firstHand or beat.firstHand
    if firstHand and now - lastSent > 10 then
        lastSent = now
        BG:Send(("r:%.1f"):format(left(now) or secondsLeft))
    end
end

BG.onMessage.r = function(rest)
    local l = tonumber(rest)
    if not l or l < 0 or l > WAVE then return end
    answeredAt = GetTime()
    if beat.firstHand then return end -- our own spirit healer beats a relayed time
    learn(l, false)
end

-- "rr": someone just came in and asks for the beat. One answer is enough, so wait a moment and stay quiet if
-- somebody else answers first.
BG.onMessage.rr = function()
    if not beat.at then return end
    local asked = GetTime()
    C_Timer.After(0.5 + math.random() * 2, function()
        if answeredAt >= asked or not beat.at then return end
        BG:Send(("r:%.1f"):format(left(GetTime())))
    end)
end

local function checkSpiritHealer()
    if not GetAreaSpiritHealerTime then return end
    local l = GetAreaSpiritHealerTime()
    if l and l > 0 then
        lastAreaLeft, lastAreaSeen = l, GetTime()
        local known = left(GetTime())
        if not beat.firstHand or not known or math.abs(known - l) > 0.6 then learn(l, true) end
    end
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
    r:SetSize(80, 80)
    r:SetPoint("TOP")
    if square then
        local b = box(r, 70, 70)
        b:SetPoint("CENTER")
        b:SetFrameLevel(r:GetFrameLevel())
    else
        circle(r, "BACKGROUND", 76, W.COPPER, 0.9, 0)
        circle(r, "BACKGROUND", 73, BOX_BG, 0.95, 1)
    end
    local track = CreateFrame("Frame", nil, r)
    track:SetAllPoints()
    track:SetFrameLevel(r:GetFrameLevel() + 2)
    circle(track, "ARTWORK", 56, { 0, 0, 0 }, 0.65)
    local cd = CreateFrame("Cooldown", nil, track, "CooldownFrameTemplate")
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
    circle(top, "ARTWORK", 44, BOX_BG, 1)
    local num = top:CreateFontString(nil, "OVERLAY")
    font(num, 18, true)
    num:SetPoint("CENTER", 0, -1)
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

local function buildBar()
    local b = box(holder, 200, 36)
    b:SetPoint("TOP")
    local label = b:CreateFontString(nil, "OVERLAY")
    font(label, 13, true)
    label:SetPoint("TOPLEFT", 8, -6)
    label:SetText("Resurrection")
    W.Color(label, W.GOLD)
    local time = b:CreateFontString(nil, "OVERLAY")
    font(time, 14, true)
    time:SetPoint("TOPRIGHT", -8, -5)
    local track = b:CreateTexture(nil, "ARTWORK")
    track:SetColorTexture(0, 0, 0, 0.6)
    track:SetPoint("BOTTOMLEFT", 8, 6)
    track:SetPoint("BOTTOMRIGHT", -8, 6)
    track:SetHeight(6)
    local fill = b:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetTexture(WHITE)
    fill:SetPoint("TOPLEFT", track)
    fill:SetPoint("BOTTOMLEFT", track)
    b.time, b.fill, b.track = time, fill, track
    function b:Draw(l, late)
        self.time:SetText(("0:%02d"):format(math.ceil(l)))
        W.Color(self.time, late and RED_TEXT or W.GOLD)
        local c = late and RED or W.GOLD
        self.fill:SetVertexColor(c[1], c[2], c[3], 1)
        self.fill:SetWidth(math.max(0.01, (self.track:GetWidth() or 184) * (1 - l / WAVE)))
    end
    return b
end

local function buildBox()
    local b = box(holder, 210, 32)
    b:SetPoint("TOP")
    local text = b:CreateFontString(nil, "OVERLAY")
    font(text, 15, true)
    text:SetPoint("CENTER")
    b.text = text
    function b:Draw(l, late)
        self.text:SetText(("Time to resurrect %02d:%02d"):format(0, math.ceil(l)))
        W.Color(self.text, late and RED_TEXT or W.GOLD)
        self:SetBorderColor(late and RED or W.COPPER, 0.9)
        if late then self.bg:SetColorTexture(0.27, 0.03, 0.02, 0.94) else self.bg:SetColorTexture(BOX_BG[1], BOX_BG[2], BOX_BG[3], 0.92) end
        self:SetWidth(math.max(150, (self.text:GetStringWidth() or 190) + 28))
    end
    return b
end

local BUILD = { round = function() return buildRing(false) end, square = function() return buildRing(true) end, bar = buildBar, box = buildBox }

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

local function styleFrame(style)
    local s = holder.styles[style]
    if not s then
        s = (BUILD[style] or BUILD.round)()
        holder.styles[style] = s
    end
    return s
end

---------------------------------------------------------------------------
-- Feature
---------------------------------------------------------------------------
local previewAt

f = Q.PvPScoped({
    id = "resTimer", tab = "pvp", section = "Battleground timers", name = "Resurrection timer",
    desc = "Counts down to the next spirit healer wave in every battleground, dead or alive. Turns red in the last 3 seconds with a \"Die now\" box underneath, so you can die just in time to come straight back. The timer is shared with your battleground group, so it runs even before you've died once.",
    defaults = { style = "round", scale = 100, dieNow = true, onlyDead = false, locked = false },
    detect = { { addon = "HighGround" } },
    options = {
        { kind = "group", text = "Look" },
        { kind = "choice", key = "style", name = "Timer", choices = {
            { "round", "Ring, round background" }, { "square", "Ring, square background" }, { "bar", "Small bar" }, { "box", "Time box" } } },
        { kind = "slider", key = "scale", name = "Size", min = 50, max = 200, step = 5, fmt = function(v) return v .. "%" end },
        { kind = "check", key = "dieNow", name = "\"Die now\" box in the last 3 seconds" },
        { kind = "check", key = "onlyDead", name = "Show only while I'm dead" },
        { kind = "group", text = "Position" },
        { kind = "check", key = "locked", name = "Lock position" },
        { kind = "button", name = "Preview", always = true, onClick = function(self) self:Preview(not self.previewing) end },
        { kind = "button", name = "Reset position", always = true, onClick = function() savedPos().point = nil if holder then placeHolder() end end },
        { kind = "note", text = "Unlocked, drag the timer to move it. Right-click the timer to lock or unlock it." },
    },
}, { "style", "scale", "dieNow", "onlyDead" })

function f:Draw()
    if not holder then return end
    local now = GetTime()
    local live = self.active and inBattleground()
    local l
    if live then l = left(now) end
    local dead = UnitIsDeadOrGhost("player")
    local show = live and l and (dead or not self:Live("onlyDead"))
    if not show and self.previewing then
        previewAt = previewAt or now + 26
        l = WAVE - ((now - previewAt) % WAVE)
        show, dead = true, false
    end
    if not show then holder:Hide() return end

    local style = self:Live("style")
    for k, s in pairs(holder.styles) do if k ~= style then s:Hide() end end
    local s = styleFrame(style)
    s:Show()
    local late = l <= LATE
    s:Draw(l, late)
    holder:SetSize(s:GetWidth(), s:GetHeight())
    local scale = (tonumber(self:Live("scale")) or 100) / 100
    if math.abs(holder:GetScale() - scale) > 0.001 then holder:SetScale(scale) end
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
    if inside ~= lastInBG then
        lastInBG = inside
        beat.at, beat.firstHand = nil, false
        if inside then C_Timer.After(4, function() if inBattleground() and not beat.at then BG:Send("rr") end end) end
    end
end

function f:Enable()
    if not holder then makeHolder() end
    BG:Use()
    lastInBG = nil
    zone()
    self:On("PLAYER_ENTERING_WORLD", zone)
    self:On("ZONE_CHANGED_NEW_AREA", zone)
    -- Coming back to life at a spirit healer means a wave just happened.
    local function alive()
        if inBattleground() and lastAreaLeft and GetTime() - lastAreaSeen < 2 and lastAreaLeft < 2 then learn(0, true) end
        lastAreaLeft = nil
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
Q.ResBeat = beat
Q.ResLearn = learn
