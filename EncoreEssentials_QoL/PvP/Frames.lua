-- Encore-QoL: the in-battle frames, in Encore's look made small: thin copper border, red title strip, the
-- crest, gold Marcellus SC, icons over text. Four styles for Alterac Valley and four for Arathi Basin; each
-- player picks one. Right-click a frame for Lock and a Scale slider; unlocked frames can be dragged.
local _, ns = ...
local Q = ns.QoL
local W = Q.W
local BG = Q.BG

local CREST = Q.MEDIA .. "encore-crest"
local TITLE_FONT = W.FONT_TITLE
local BODY_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local ICON = {
    general = "Interface\\Icons\\INV_Crown_01",
    captain = "Interface\\Icons\\INV_Sword_04",
    officer = "Interface\\Icons\\INV_Shield_06",
    attacked = "Interface\\Icons\\Ability_Warrior_Rampage",
    tower = "Interface\\Icons\\INV_BannerPVP_02",
    gy = "Interface\\Icons\\Spell_Holy_Resurrection",
    mine = "Interface\\Icons\\Trade_Mining",
    Stables = "Interface\\Icons\\Ability_Mount_RidingHorse",
    Farm = "Interface\\Icons\\INV_Misc_Food_11",
    Blacksmith = "Interface\\Icons\\Trade_BlackSmithing",
    ["Lumber Mill"] = "Interface\\Icons\\INV_TradeskillItem_01",
    ["Gold Mine"] = "Interface\\Icons\\INV_Pick_02",
}
local TEAM = { A = { 0.18, 0.45, 0.82 }, H = { 0.78, 0.15, 0.11 } }
local TEAM_TEXT = { A = W.ALLIANCE, H = W.HORDE }
local TEAM_NAME = { A = "Alliance", H = "Horde" }
local SHORT = {
    ["Dun Baldar North Bunker"] = "DB North Bunker", ["Dun Baldar South Bunker"] = "DB South Bunker",
    ["East Frostwolf Tower"] = "East FW Tower", ["West Frostwolf Tower"] = "West FW Tower",
    ["Stormpike Aid Station"] = "SP Aid Station", ["Stormpike Graveyard"] = "Stormpike GY",
    ["Stonehearth Graveyard"] = "Stonehearth GY", ["Snowfall Graveyard"] = "Snowfall GY",
    ["Iceblood Graveyard"] = "Iceblood GY", ["Frostwolf Graveyard"] = "Frostwolf GY", ["Frostwolf Relief Hut"] = "FW Relief Hut",
}
local function short(name) return SHORT[name] or name end
local function clock(sec)
    sec = math.max(0, math.floor(sec or 0))
    return ("%d:%02d"):format(sec / 60, sec % 60)
end

---------------------------------------------------------------------------
-- Renderer: each update draws the frame again from pooled pieces, so styles stay short.
---------------------------------------------------------------------------
local Renderer = {}
Renderer.__index = Renderer

local function newRenderer(holder)
    return setmetatable({ holder = holder, pools = { tex = {}, text = {}, icon = {}, hot = {} }, used = { tex = 0, text = 0, icon = 0, hot = 0 } }, Renderer)
end

---------------------------------------------------------------------------
-- Tooltips on icons and bars. tip = { title, color, lines = { text or { text, color } } }, follows the cursor.
---------------------------------------------------------------------------
local function showTip(fr)
    local tip = fr.tip
    if not tip then return end
    GameTooltip:SetOwner(fr, "ANCHOR_CURSOR")
    local c = tip.color or W.GOLD
    GameTooltip:SetText(tip.title or "", c[1], c[2], c[3])
    for _, l in ipairs(tip.lines or {}) do
        if type(l) == "table" then
            local lc = l[2] or W.INK
            GameTooltip:AddLine(l[1], lc[1], lc[2], lc[3], true)
        else
            GameTooltip:AddLine(l, W.INK[1], W.INK[2], W.INK[3], true)
        end
    end
    GameTooltip:Show()
end

-- Hover only: clicks and drags still reach the frame underneath (move, right-click menu).
local function hoverable(fr, holder)
    if fr.SetMouseClickEnabled and fr.SetMouseMotionEnabled then
        fr:SetMouseMotionEnabled(true)
        fr:SetMouseClickEnabled(false)
    else
        fr:EnableMouse(true)
        fr:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and not holder:Saved().locked then holder:StartMoving() end
        end)
        fr:SetScript("OnMouseUp", function(_, button)
            local stop = holder:GetScript("OnDragStop")
            if button == "LeftButton" and stop then stop(holder) end
            local up = holder:GetScript("OnMouseUp")
            if up then up(holder, button) end
        end)
    end
    fr:SetScript("OnEnter", showTip)
    fr:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function setTip(fr, tip)
    fr.tip = tip
    if GameTooltip:IsOwned(fr) then
        if tip then showTip(fr) else GameTooltip:Hide() end
    end
end

-- Invisible hover area over a bar or a row.
function Renderer:Hot(x, y, w, h, tip)
    local fr = self:_take("hot", function()
        local f = CreateFrame("Frame", nil, self.holder)
        f:SetFrameLevel(self.holder:GetFrameLevel() + 1)
        hoverable(f, self.holder)
        return f
    end)
    fr:SetPoint("TOPLEFT", self.holder, "TOPLEFT", x, -y)
    fr:SetSize(math.max(1, w), math.max(1, h))
    setTip(fr, tip)
    return fr
end

function Renderer:Begin() for k in pairs(self.used) do self.used[k] = 0 end end

function Renderer:End(w, h)
    for kind, pool in pairs(self.pools) do
        for i = self.used[kind] + 1, #pool do
            if pool[i].tip and GameTooltip:IsOwned(pool[i]) then GameTooltip:Hide() end
            pool[i]:Hide()
        end
    end
    self.holder:SetSize(math.max(20, w), math.max(10, h))
end

local function take(self, kind, make)
    self.used[kind] = self.used[kind] + 1
    local obj = self.pools[kind][self.used[kind]]
    if not obj then
        obj = make()
        self.pools[kind][self.used[kind]] = obj
    end
    obj:ClearAllPoints()
    obj:Show()
    return obj
end
function Renderer:_take(kind, make) return take(self, kind, make) end

function Renderer:Rect(x, y, w, h, r, g, b, a, layer)
    local t = take(self, "tex", function() return self.holder:CreateTexture(nil, "BACKGROUND") end)
    t:SetDrawLayer(layer or "BACKGROUND", 1)
    t:SetTexture(nil)
    t:SetColorTexture(r, g, b, a or 1)
    pcall(t.SetGradient, t, "HORIZONTAL", CreateColor(r, g, b, a or 1), CreateColor(r, g, b, a or 1))
    t:SetPoint("TOPLEFT", self.holder, "TOPLEFT", x, -y)
    t:SetSize(math.max(1, w), math.max(1, h))
    return t
end

function Renderer:Gradient(x, y, w, h, c1, c2, layer)
    local t = self:Rect(x, y, w, h, 1, 1, 1, 1, layer)
    t:SetColorTexture(1, 1, 1, 1)
    if not pcall(t.SetGradient, t, "HORIZONTAL", CreateColor(unpack(c1)), CreateColor(unpack(c2))) then
        t:SetColorTexture(c1[1], c1[2], c1[3], (c1[4] or 1) * 0.6)
    end
    return t
end

function Renderer:Text(x, y, text, size, color, opts)
    opts = opts or {}
    local fs = take(self, "text", function() return self.holder:CreateFontString(nil, "OVERLAY") end)
    local font = opts.title and TITLE_FONT or BODY_FONT
    if not fs:SetFont(font, size or 12, opts.outline or "") then fs:SetFont(BODY_FONT, size or 12, opts.outline or "") end
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetText(text or "")
    fs:SetTextColor((color or W.INK)[1], (color or W.INK)[2], (color or W.INK)[3], 1)
    fs:SetJustifyH(opts.justify or "LEFT")
    fs:SetWordWrap(false)
    if opts.width then fs:SetWidth(opts.width) else fs:SetWidth(0) end
    local anchor = opts.justify == "RIGHT" and "TOPRIGHT" or (opts.justify == "CENTER" and "TOP" or "TOPLEFT")
    fs:SetPoint(anchor, self.holder, "TOPLEFT", x, -y)
    return fs
end

-- Square icon with a team-coloured frame; dead = greyed with a red cross, glow = red outer glow.
function Renderer:Icon(x, y, size, tex, team, opts)
    opts = opts or {}
    local f = take(self, "icon", function()
        local fr = CreateFrame("Frame", nil, self.holder)
        fr.border = fr:CreateTexture(nil, "BORDER")
        fr.border:SetAllPoints()
        fr.icon = fr:CreateTexture(nil, "ARTWORK")
        fr.icon:SetPoint("TOPLEFT", 2, -2)
        fr.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        fr.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        fr.cross = fr:CreateTexture(nil, "OVERLAY")
        fr.cross:SetAllPoints(fr.icon)
        fr.cross:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        fr.glow = fr:CreateTexture(nil, "BACKGROUND")
        fr.glow:SetPoint("TOPLEFT", -3, 3)
        fr.glow:SetPoint("BOTTOMRIGHT", 3, -3)
        fr.glow:SetColorTexture(1, 0.23, 0.17, 0.55)
        fr.half = fr:CreateTexture(nil, "OVERLAY", nil, 2)
        fr.half:SetPoint("TOPLEFT", fr, "TOPLEFT", 0, 0)
        fr.half:SetPoint("BOTTOMRIGHT", fr, "TOP", 0, -3)
        fr:SetFrameLevel(self.holder:GetFrameLevel() + 2)
        hoverable(fr, self.holder)
        return fr
    end)
    f:SetSize(size, size)
    f:SetPoint("TOPLEFT", self.holder, "TOPLEFT", x, -y)
    local c = TEAM[team] or { 0.79, 0.47, 0.18 }
    f.border:SetColorTexture(c[1], c[2], c[3], 1)
    f.icon:SetTexture(tex)
    if opts.full then f.icon:SetTexCoord(0, 1, 0, 1) else f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    f.icon:SetDesaturated(opts.dead == true)
    f.icon:SetAlpha(opts.dead and 0.5 or 1)
    f.cross:SetShown(opts.dead == true)
    f.glow:SetShown(opts.glow == true)
    -- contested: a strip of the attacker's colour across the top
    local cc = opts.contestedBy and TEAM[opts.contestedBy]
    f.half:SetShown(cc ~= nil)
    if cc then f.half:SetColorTexture(cc[1], cc[2], cc[3], 1) end
    setTip(f, opts.tip)
    return f
end

-- Progress bar: background, fill and a thin copper frame.
function Renderer:Bar(x, y, w, h, frac, team)
    self:Rect(x, y, w, h, 0.36, 0.26, 0.15, 1, "BORDER")
    self:Rect(x + 1, y + 1, w - 2, h - 2, 0, 0, 0, 1, "BORDER")
    local c = TEAM[team] or W.GOLD
    if frac > 0 then self:Rect(x + 1, y + 1, math.max(1, (w - 2) * math.min(1, frac)), h - 2, c[1], c[2], c[3], 1, "ARTWORK") end
end

-- Encore card: copper outline, dark body, red title strip with crest and gold title.
function Renderer:Card(w, h, title, right, rightColor)
    self:Rect(0, 0, w, h, 0.79, 0.47, 0.18, 1, "BACKGROUND")
    self:Rect(1, 1, w - 2, h - 2, 0.1, 0.075, 0.055, 0.92, "BACKGROUND")
    if title then
        self:Gradient(1, 1, w - 2, 24, { 0.7, 0.04, 0.03, 0.85 }, { 0, 0, 0, 0.25 }, "BORDER")
        self:Rect(1, 25, w - 2, 1, 0.92, 0.58, 0.22, 0.4, "BORDER")
        self:Icon(4, 4, 18, CREST, nil, { full = true })
        self:Text(26, 7, title, 13, W.GOLD, { title = true })
        if right then self:Text(w - 8, 7, right, 12, rightColor or W.GOLD, { justify = "RIGHT" }) end
        return 30
    end
    return 6
end

---------------------------------------------------------------------------
-- Holder frames: drag, lock, scale (right-click menu).
---------------------------------------------------------------------------
local menu
local function showMenu(holder)
    if not menu then
        menu = CreateFrame("Frame", "EncoreQoLFrameMenu", UIParent)
        menu:SetSize(220, 108)
        menu:SetFrameStrata("DIALOG")
        menu:EnableMouse(true)
        W.Panel(menu, 0.96)
        menu.title = W.Text(menu, "GameFontNormal", "", W.GOLD)
        menu.title:SetPoint("TOP", 0, -8)
        menu.lock = W.Check(menu, "Lock")
        menu.lock:SetPoint("TOPLEFT", 10, -26)
        menu.scale = W.Slider(menu, "Scale", { width = 196, min = 50, max = 200, step = 5, fmt = function(v) return v .. "%" end,
            onChange = function(v) if menu.holder then menu.holder:SetSavedScale(v / 100) end end })
        menu.scale:SetPoint("TOPLEFT", 12, -54)
        local close = W.Button(menu, "Done", function() menu:Hide() end, 70)
        close:SetPoint("BOTTOMRIGHT", -8, 6)
        local reset = W.Button(menu, "Reset position", function() if menu.holder then menu.holder:ResetPosition() end end, 120)
        reset:SetPoint("BOTTOMLEFT", 8, 6)
        menu.lock.onChange = function(v)
            if not menu.holder then return end
            menu.holder:Saved().locked = v or nil
            menu.scale:SetShown(not v)
        end
        tinsert(UISpecialFrames, "EncoreQoLFrameMenu")
    end
    menu.holder = holder
    menu.title:SetText("Encore: " .. holder.title)
    local locked = holder:Saved().locked == true
    menu.lock:SetChecked(locked)
    menu.scale:SetValue(math.floor((holder:Saved().scale or 1) * 100 + 0.5))
    menu.scale:SetShown(not locked)
    menu:ClearAllPoints()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 8, y / s - 8)
    menu:Show()
end

local function makeHolder(key, title, defaultPoint)
    local h = CreateFrame("Frame", "EncoreQoL" .. key .. "Frame", UIParent)
    h.key, h.title = key, title
    h:SetSize(200, 40)
    h:SetFrameStrata("MEDIUM")
    h:SetClampedToScreen(true)
    h:SetMovable(true)
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    h:Hide()
    function h:Saved()
        local t = Q.db.frames[key]
        if type(t) ~= "table" then t = {}; Q.db.frames[key] = t end
        return t
    end
    function h:SetSavedScale(s)
        self:Saved().scale = s
        self:SetScale(s)
    end
    function h:ResetPosition()
        local t = self:Saved()
        t.point, t.scale = nil, nil
        self:SetScale(1)
        self:ClearAllPoints()
        self:SetPoint(unpack(defaultPoint))
    end
    h:SetScript("OnDragStart", function(self) if not self:Saved().locked then self:StartMoving() end end)
    h:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        self:Saved().point = { p, rp, x, y }
    end)
    h:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then showMenu(self) end end)
    h:SetScript("OnMouseWheel", function(self, d)
        if self:Saved().locked then return end
        self:SetSavedScale(math.max(0.5, math.min(2, (self:Saved().scale or 1) + d * 0.05)))
    end)
    h:EnableMouseWheel(true)
    local t = h:Saved()
    h:SetScale(t.scale or 1)
    if type(t.point) == "table" and t.point[1] then h:SetPoint(t.point[1], UIParent, t.point[2], t.point[3], t.point[4]) else h:SetPoint(unpack(defaultPoint)) end
    h.render = newRenderer(h)
    return h
end

---------------------------------------------------------------------------
-- Alterac Valley styles
---------------------------------------------------------------------------
local function avData(data)
    local me = BG:MySide()
    local enemy = me == "H" and "A" or "H"
    local officers = { mine = {}, theirs = {}, attacked = {} }
    for _, o in ipairs(BG.OFFICERS) do
        local state
        if data.preview then
            local h = data.health[o.id]
            state = (h and h.pct == 0) and "dead" or ((h and h.pct < 100) and "attacked" or "alive")
            if o.tower and data.nodes[o.tower] and data.nodes[o.tower].destroyed then state = "dead" end
        else
            state = BG:OfficerState(o)
        end
        local entry = { o = o, state = state }
        if o.side == enemy then officers.theirs[#officers.theirs + 1] = entry else officers.mine[#officers.mine + 1] = entry end
        if o.side == me and state == "attacked" then officers.attacked[#officers.attacked + 1] = entry end
    end
    local timers, now = {}, GetTime()
    for _, n in pairs(data.nodes) do if n.ends and n.ends > now then timers[#timers + 1] = n end end
    table.sort(timers, function(a, b) return a.ends < b.ends end)
    local function general(side)
        local g = BG.GENERALS[side]
        local h = data.health[g.id]
        return g, h and h.pct, h and (now - h.at)
    end
    local alive = 0
    for _, e in ipairs(officers.theirs) do if e.state ~= "dead" then alive = alive + 1 end end
    return { me = me, enemy = enemy, officers = officers, timers = timers, general = general, alive = alive, score = data.score, now = now, health = data.health, nodes = data.nodes }
end

local function nodeIcon(n) return ICON[n.kind] or ICON.tower end

-- Tooltip text for the frames' icons and bars.
local function seen(age)
    if not age then return nil end
    age = math.floor(age)
    if age < 3 then return "just now" end
    if age < 60 then return age .. " s ago" end
    return clock(age) .. " ago"
end

local function nodeKind(n)
    if n.kind == "tower" then return n.name:find("Bunker") and "Bunker" or "Tower" end
    return ({ gy = "Graveyard", mine = "Mine", base = "Base" })[n.kind] or "Objective"
end

local function nodeTip(n, now, capTime)
    local lines = {}
    local kind = nodeKind(n)
    if n.destroyed then
        lines[#lines + 1] = { kind .. ", destroyed" .. (n.owner and (" by the " .. TEAM_NAME[n.owner]) or ""), W.DIM }
    elseif n.owner then
        lines[#lines + 1] = { kind .. ", held by the " .. TEAM_NAME[n.owner], TEAM_TEXT[n.owner] }
    else
        lines[#lines + 1] = { kind .. ", nobody holds it", W.DIM }
    end
    if n.contestedBy and n.ends and n.ends > now then
        local done = n.kind == "tower" and "destroyed" or "taken"
        lines[#lines + 1] = { ("%s assaulted it: %s in %s unless it's defended."):format(TEAM_NAME[n.contestedBy], done, clock(n.ends - now)), TEAM_TEXT[n.contestedBy] }
    elseif n.contestedBy then
        lines[#lines + 1] = { TEAM_NAME[n.contestedBy] .. " assaulted it.", TEAM_TEXT[n.contestedBy] }
    end
    if n.kind == "tower" then
        for _, o in ipairs(BG.OFFICERS) do
            if o.tower == n.name then lines[#lines + 1] = { o.name .. " stands here and dies when it is destroyed.", W.DIM } end
        end
    elseif n.kind == "base" then
        lines[#lines + 1] = { "Each base held adds to its side's score. Capping takes " .. (capTime or 60) .. " s.", W.DIM }
    end
    return { title = n.name, lines = lines }
end

local function generalTip(team, g, pct, age, d)
    local lines = { { TEAM_NAME[team] .. " general", TEAM_TEXT[team] } }
    if pct then
        lines[#lines + 1] = ("Health %d%% (seen %s)"):format(pct, seen(age) or "?")
    else
        lines[#lines + 1] = { "Health not seen yet. It shows as soon as someone in your group or a Capping user targets him.", W.DIM }
    end
    if team == d.enemy then
        lines[#lines + 1] = ("Enemy officers still alive: %d of %d. Each one alive makes him stronger."):format(d.alive, #d.officers.theirs)
    end
    return { title = g.name, color = TEAM_TEXT[team], lines = lines }
end

local function officerTip(e, d)
    local o = e.o
    local role = o.captain and "captain" or (o.side == "A" and "marshal" or "warmaster")
    local lines = { { TEAM_NAME[o.side] .. " " .. role .. (o.tower and (", " .. o.tower) or ""), TEAM_TEXT[o.side] } }
    local h = d.health and d.health[o.id]
    if e.state == "dead" then
        lines[#lines + 1] = { o.tower and d.nodes and d.nodes[o.tower] and d.nodes[o.tower].destroyed and ("Dead: " .. o.tower .. " was destroyed.") or "Dead", W.DIM }
    elseif e.state == "attacked" then
        lines[#lines + 1] = { ("Under attack: %d%% health (seen %s)"):format(h and h.pct or 0, seen(h and (d.now - h.at)) or "?"), W.HORDE }
    else
        lines[#lines + 1] = "Alive"
    end
    if o.tower then
        lines[#lines + 1] = { "Dies when " .. o.tower .. " is destroyed, or when killed.", W.DIM }
    end
    return { title = o.name, color = TEAM_TEXT[o.side], lines = lines }
end

local AV_STYLES = {}

-- 1 Compact list: one small card; sections appear only when something is happening.
AV_STYLES.compact = function(r, d, f)
    local W_ = 250
    local g, pct, age = d.general(d.enemy)
    local hasGeneral = pct ~= nil
    local rows = (hasGeneral and 1 or 0) + 1 + #d.officers.attacked + (f:Get("timers") and #d.timers or 0)
    local h = 30 + rows * 26 + 6
    local reinf = (d.score.reinfH or d.score.reinfA) and (("|cffff9d8f%s|r  |cff8fc8ff%s|r"):format(d.score.reinfH or "?", d.score.reinfA or "?")) or nil
    local y = r:Card(W_, h, "Alterac Valley", reinf)
    if hasGeneral then
        r:Icon(8, y, 22, ICON.general, d.enemy, { tip = generalTip(d.enemy, g, pct, age, d) })
        r:Hot(36, y, W_ - 44, 22, generalTip(d.enemy, g, pct, age, d))
        r:Text(36, y, g.name, 12, TEAM_TEXT[d.enemy])
        r:Text(W_ - 40, y, pct .. "%", 12, W.INK, { justify = "RIGHT" })
        if age and age > 3 then r:Text(W_ - 8, y + 1, math.floor(age) .. "s", 10, W.DIM, { justify = "RIGHT" }) end
        r:Bar(36, y + 15, W_ - 46, 6, pct / 100, d.enemy)
        y = y + 26
    end
    local x = 8
    for _, e in ipairs(d.officers.theirs) do
        r:Icon(x, y, 22, e.o.captain and ICON.captain or ICON.officer, d.enemy, { dead = e.state == "dead", glow = e.state == "attacked", tip = officerTip(e, d) })
        x = x + 25
    end
    r:Text(W_ - 8, y + 5, d.alive .. " left", 11, TEAM_TEXT[d.enemy], { justify = "RIGHT" })
    y = y + 26
    for _, e in ipairs(d.officers.attacked) do
        r:Rect(6, y, W_ - 12, 22, 0.7, 0.04, 0.03, 0.3, "BORDER")
        r:Hot(6, y, W_ - 12, 22, officerTip(e, d))
        r:Icon(8, y + 1, 20, ICON.attacked, d.me, { tip = officerTip(e, d) })
        r:Text(34, y + 5, e.o.name .. " under attack", 12, TEAM_TEXT[d.me])
        y = y + 26
    end
    if f:Get("timers") then
        for _, n in ipairs(d.timers) do
            local left = n.ends - d.now
            local tip = nodeTip(n, d.now, BG.CAP_TIME.AV)
            r:Icon(8, y, 22, nodeIcon(n), n.contestedBy, { tip = tip })
            r:Hot(36, y, W_ - 44, 22, tip)
            r:Text(36, y, short(n.name), 12, W.INK)
            r:Text(W_ - 8, y, clock(left), 12, W.GOLD, { justify = "RIGHT" })
            r:Bar(36, y + 15, W_ - 46, 5, 1 - left / (BG.CAP_TIME.AV or 240), n.contestedBy)
            y = y + 26
        end
    end
    return W_, h
end

-- 2 Slim strip: one line, icons only.
AV_STYLES.strip = function(r, d, f)
    local x, H = 6, 36
    local g, pct, age = d.general(d.enemy)
    local w = 60 + 140 + #d.officers.theirs * 23 + (f:Get("timers") and #d.timers * 64 or 0) + 70
    r:Card(w, H)
    r:Icon(x, 9, 18, CREST, nil, { full = true })
    x = x + 24
    r:Icon(x, 7, 22, ICON.general, d.enemy, { tip = generalTip(d.enemy, g, pct, age, d) })
    r:Hot(x + 26, 4, 106, 28, generalTip(d.enemy, g, pct, age, d))
    x = x + 26
    r:Text(x, 6, g.name .. " " .. (pct and pct .. "%" or "?"), 11, TEAM_TEXT[d.enemy])
    r:Bar(x, 22, 104, 6, (pct or 100) / 100, d.enemy)
    x = x + 114
    for _, e in ipairs(d.officers.theirs) do
        r:Icon(x, 8, 20, e.o.captain and ICON.captain or ICON.officer, d.enemy, { dead = e.state == "dead", glow = e.state == "attacked", tip = officerTip(e, d) })
        x = x + 23
    end
    x = x + 6
    if f:Get("timers") then
        for _, n in ipairs(d.timers) do
            r:Icon(x, 8, 20, nodeIcon(n), n.contestedBy, { tip = nodeTip(n, d.now, BG.CAP_TIME.AV) })
            r:Text(x + 23, 12, clock(n.ends - d.now), 11, W.GOLD)
            x = x + 64
        end
    end
    for _, e in ipairs(d.officers.attacked) do
        r:Icon(x, 8, 20, ICON.attacked, d.me, { glow = true, tip = officerTip(e, d) })
        x = x + 24
    end
    r:Text(x + 4, 12, ("|cffff9d8f%s|r |cff8fc8ff%s|r"):format(d.score.reinfH or "?", d.score.reinfA or "?"), 12, W.INK)
    x = x + 70
    r:End(x, H)
    return x, H
end

-- 3 Two sides: Alliance left, Horde right, each with its general, officers and the caps it is making.
AV_STYLES.sides = function(r, d, f)
    local W_, col = 420, 210
    local function side(team, x)
        local y = 34
        local g, pct, age = d.general(team)
        r:Text(x + 8, y, TEAM_NAME[team], 13, TEAM_TEXT[team])
        r:Text(x + col - 10, y, tostring((team == "A" and d.score.reinfA or d.score.reinfH) or "?"), 13, TEAM_TEXT[team], { justify = "RIGHT" })
        y = y + 20
        r:Icon(x + 8, y, 20, ICON.general, team, { tip = generalTip(team, g, pct, age, d) })
        r:Hot(x + 34, y, col - 44, 20, generalTip(team, g, pct, age, d))
        r:Bar(x + 34, y + 7, col - 80, 7, (pct or 100) / 100, team)
        r:Text(x + col - 10, y + 3, pct and pct .. "%" or "?", 11, W.INK, { justify = "RIGHT" })
        y = y + 26
        local ix = x + 8
        for _, e in ipairs(team == d.enemy and d.officers.theirs or d.officers.mine) do
            r:Icon(ix, y, 20, e.o.captain and ICON.captain or ICON.officer, team, { dead = e.state == "dead", glow = e.state == "attacked", tip = officerTip(e, d) })
            ix = ix + 23
        end
        y = y + 26
        if f:Get("timers") then
            for _, n in ipairs(d.timers) do
                if n.contestedBy == team then
                    local tip = nodeTip(n, d.now, BG.CAP_TIME.AV)
                    r:Icon(x + 8, y, 20, nodeIcon(n), team, { tip = tip })
                    r:Hot(x + 34, y, col - 44, 20, tip)
                    r:Text(x + 34, y + 3, short(n.name), 11, W.INK)
                    r:Text(x + col - 10, y + 3, clock(n.ends - d.now), 11, W.GOLD, { justify = "RIGHT" })
                    y = y + 24
                end
            end
        end
        return y
    end
    local count = { A = 0, H = 0 }
    for _, n in ipairs(d.timers) do if n.contestedBy then count[n.contestedBy] = count[n.contestedBy] + 1 end end
    local h = 34 + 20 + 26 + 26 + (f:Get("timers") and math.max(count.A, count.H) * 24 or 0) + 8
    r:Card(W_, h, "Alterac Valley")
    r:Gradient(1, 27, col - 1, h - 28, { 0.18, 0.45, 0.82, 0.16 }, { 0.18, 0.45, 0.82, 0 }, "BORDER")
    r:Gradient(col, 27, col - 1, h - 28, { 0.78, 0.15, 0.11, 0.18 }, { 0.78, 0.15, 0.11, 0 }, "BORDER")
    r:Rect(col, 27, 1, h - 28, 0.36, 0.26, 0.15, 1, "BORDER")
    side("A", 0)
    side("H", col)
    return W_, h
end

-- 4 Timer bars: no window. Boss health always on top, enemy general first, then timers soonest first.
AV_STYLES.bars = function(r, d, f)
    local W_, H = 260, 24
    local y = 0
    local function bar(team, frac, icon, label, right, glowRed, tip)
        r:Hot(0, y, W_, H, tip)
        r:Rect(0, y, W_, H, glowRed and 0.78 or 0.79, glowRed and 0.15 or 0.47, glowRed and 0.11 or 0.18, 1, "BACKGROUND")
        r:Rect(1, y + 1, W_ - 2, H - 2, 0.055, 0.04, 0.03, 0.9, "BACKGROUND")
        local c = TEAM[team] or W.GOLD
        if frac and frac > 0 then r:Rect(1, y + 1, (W_ - 2) * math.min(1, frac), H - 2, c[1], c[2], c[3], 0.45, "BORDER") end
        r:Icon(3, y + 3, 18, icon, team, { tip = tip })
        r:Text(26, y + 6, label, 12, W.INK)
        if right then r:Text(W_ - 6, y + 6, right, 12, W.GOLD, { justify = "RIGHT" }) end
        y = y + H + 4
    end
    for _, team in ipairs({ d.enemy, d.me }) do
        local g, pct, age = d.general(team)
        if pct or team == d.enemy then
            bar(team, (pct or 100) / 100, ICON.general, g.name .. " " .. (pct and pct .. "%" or "?"), age and age > 3 and (math.floor(age) .. "s") or nil, nil, generalTip(team, g, pct, age, d))
        end
    end
    if y > 0 then
        r:Gradient(4, y - 2, W_ - 8, 1, { 0.79, 0.47, 0.18, 0 }, { 0.79, 0.47, 0.18, 1 }, "BORDER")
        y = y + 2
    end
    for _, e in ipairs(d.officers.attacked) do bar(d.me, 1, ICON.attacked, e.o.name .. " attacked", nil, true, officerTip(e, d)) end
    if f:Get("timers") then
        for _, n in ipairs(d.timers) do
            local left = n.ends - d.now
            bar(n.contestedBy, 1 - left / (BG.CAP_TIME.AV or 240), nodeIcon(n), short(n.name), clock(left), nil, nodeTip(n, d.now, BG.CAP_TIME.AV))
        end
    end
    r:Rect(0, y, W_, 20, 0.79, 0.47, 0.18, 1, "BACKGROUND")
    r:Rect(1, y + 1, W_ - 2, 18, 0.055, 0.04, 0.03, 0.9, "BACKGROUND")
    r:Icon(3, y + 2, 16, CREST, nil, { full = true })
    local names = {}
    for _, e in ipairs(d.officers.theirs) do
        names[#names + 1] = { e.o.name .. ": " .. (e.state == "dead" and "dead" or e.state == "attacked" and "under attack" or "alive"), e.state == "dead" and W.DIM or TEAM_TEXT[d.enemy] }
    end
    names[#names + 1] = { ("Reinforcements: Horde %s, Alliance %s"):format(d.score.reinfH or "?", d.score.reinfA or "?"), W.INK }
    r:Hot(0, y, W_, 20, { title = "Enemy officers", color = TEAM_TEXT[d.enemy], lines = names })
    r:Text(24, y + 4, ("Officers left: %d of %d"):format(d.alive, #d.officers.theirs), 11, TEAM_TEXT[d.enemy])
    r:Text(W_ - 6, y + 4, ("|cffff9d8f%s|r  |cff8fc8ff%s|r"):format(d.score.reinfH or "?", d.score.reinfA or "?"), 11, W.INK, { justify = "RIGHT" })
    y = y + 20
    return W_, y
end

---------------------------------------------------------------------------
-- Arathi Basin styles
---------------------------------------------------------------------------
local function abData(data)
    local s = data.score
    local saved = BG.score
    BG.score = s
    local winner, t, finalA, finalH = BG:Prediction()
    local need = BG:BasesNeeded()
    BG.score = saved
    local now = GetTime()
    local soonest
    for _, n in pairs(data.nodes) do if n.ends and n.ends > now and (not soonest or n.ends < soonest.ends) then soonest = n end end
    return { s = s, winner = winner, t = t, finalA = finalA, finalH = finalH, need = need, nodes = data.nodes, soonest = soonest, now = now }
end

local function predictionText(d)
    if not d.winner then return "No bases held" end
    return ("%s in %s"):format(TEAM_NAME[d.winner], clock(d.t))
end

local function pips(r, x, y, size, d, gap)
    for _, name in ipairs(BG.AB_NODES) do
        local n = d.nodes[name] or {}
        n.name, n.kind = n.name or name, n.kind or "base"
        r:Icon(x, y, size, ICON[name], n.owner, { contestedBy = n.contestedBy, tip = nodeTip(n, d.now, BG.CAP_TIME.AB) })
        x = x + size + (gap or 4)
    end
    return x
end

local function split(r, x, y, w, h, d)
    local total = math.max(1, d.s.H + d.s.A)
    r:Rect(x, y, w, h, 0.36, 0.26, 0.15, 1, "BORDER")
    local hw = (w - 2) * d.s.H / total
    if hw > 0 then r:Rect(x + 1, y + 1, hw, h - 2, TEAM.H[1], TEAM.H[2], TEAM.H[3], 1, "ARTWORK") end
    if w - 2 - hw > 0 then r:Rect(x + 1 + hw, y + 1, w - 2 - hw, h - 2, TEAM.A[1], TEAM.A[2], TEAM.A[3], 1, "ARTWORK") end
end

local AB_STYLES = {}

-- 1 Compact card: score, prediction and the five bases.
AB_STYLES.compact = function(r, d, f)
    local W_, h = 280, 30 + 10 + 18 + 30 + 4
    local y = r:Card(W_, h, "Arathi Basin", f:Get("prediction") and predictionText(d) or nil, d.winner and TEAM_TEXT[d.winner])
    split(r, 8, y, W_ - 16, 7, d)
    y = y + 11
    r:Text(8, y, "Horde " .. d.s.H, 12, W.HORDE)
    if f:Get("prediction") and d.winner then r:Text(W_ / 2, y, ("ends %d : %d"):format(d.finalH, d.finalA), 11, W.DIM, { justify = "CENTER" }) end
    r:Text(W_ - 8, y, d.s.A .. " Alliance", 12, W.ALLIANCE, { justify = "RIGHT" })
    y = y + 18
    pips(r, 8, y, 24, d)
    if f:Get("timers") and d.soonest then r:Text(W_ - 8, y + 6, clock(d.soonest.ends - d.now), 13, W.GOLD, { justify = "RIGHT" }) end
    return W_, h
end

-- 2 Score bar: one slim bar, Horde score, the five bases, Alliance score; the prediction underneath.
AB_STYLES.scorebar = function(r, d, f)
    local H = 36
    local x = 6
    local w = 30 + 46 + 5 * 26 + (f:Get("timers") and d.soonest and 40 or 0) + 50
    r:Card(w, H)
    r:Icon(x, 9, 18, CREST, nil, { full = true })
    x = x + 24
    r:Text(x, 10, tostring(d.s.H), 15, W.HORDE)
    x = x + 44
    x = pips(r, x, 6, 23, d, 3)
    if f:Get("timers") and d.soonest then
        r:Text(x + 2, 11, clock(d.soonest.ends - d.now), 12, W.GOLD)
        x = x + 40
    end
    r:Text(x + 6, 10, tostring(d.s.A), 15, W.ALLIANCE)
    if f:Get("prediction") and d.winner then
        r:Text(0, H + 4, ("%s wins %d : %d in %s"):format(TEAM_NAME[d.winner], d.finalH, d.finalA, clock(d.t)), 12, TEAM_TEXT[d.winner], { outline = "OUTLINE" })
    end
    return w, H
end

-- 3 Base list: a narrow column, one line per base with its owner or its timer.
AB_STYLES.list = function(r, d, f)
    local W_ = 210
    local h = 30 + 18 + 12 + 5 * 24 + 4
    local y = r:Card(W_, h, "Arathi Basin")
    r:Text(8, y, tostring(d.s.H), 12, W.HORDE)
    if f:Get("prediction") then r:Text(W_ / 2, y, predictionText(d), 11, W.GOLD, { justify = "CENTER" }) end
    r:Text(W_ - 8, y, tostring(d.s.A), 12, W.ALLIANCE, { justify = "RIGHT" })
    y = y + 18
    split(r, 8, y, W_ - 16, 7, d)
    y = y + 12
    for _, name in ipairs(BG.AB_NODES) do
        local n = d.nodes[name] or {}
        n.name, n.kind = n.name or name, n.kind or "base"
        local tip = nodeTip(n, d.now, BG.CAP_TIME.AB)
        r:Icon(8, y, 20, ICON[name], n.owner, { contestedBy = n.contestedBy, tip = tip })
        r:Hot(32, y, W_ - 40, 20, tip)
        r:Text(34, y + 4, name, 12, W.INK)
        if f:Get("timers") and n.ends and n.ends > d.now then
            r:Text(W_ - 8, y + 4, clock(n.ends - d.now), 12, W.GOLD, { justify = "RIGHT" })
        else
            r:Text(W_ - 8, y + 4, n.owner and TEAM_NAME[n.owner] or "—", 12, n.owner and TEAM_TEXT[n.owner] or W.DIM, { justify = "RIGHT" })
        end
        y = y + 24
    end
    return W_, h
end

-- 4 Floating: no window, the prediction and base icons on a soft shadow.
AB_STYLES.floating = function(r, d, f)
    local W_, h = 230, 62
    r:Gradient(0, 0, W_, h, { 0, 0, 0, 0.55 }, { 0, 0, 0, 0 }, "BACKGROUND")
    if f:Get("prediction") and d.winner then
        r:Text(8, 4, TEAM_NAME[d.winner], 18, TEAM_TEXT[d.winner], { title = true, outline = "OUTLINE" })
        r:Text(96, 7, "in " .. clock(d.t), 15, W.GOLD, { outline = "OUTLINE" })
    end
    r:Text(W_ - 8, 8, ("|cffff9d8f%d|r : |cff8fc8ff%d|r"):format(d.s.H, d.s.A), 13, W.INK, { justify = "RIGHT", outline = "OUTLINE" })
    local x = pips(r, 8, 30, 24, d)
    if f:Get("timers") and d.soonest then r:Text(x + 4, 36, clock(d.soonest.ends - d.now), 13, W.GOLD, { outline = "OUTLINE" }) end
    return W_, h
end

---------------------------------------------------------------------------
-- Features
---------------------------------------------------------------------------
local function frameFeature(def)
    local styles = def.kind == "AV" and AV_STYLES or AB_STYLES
    local holder
    local function draw(f)
        if not holder then return end
        local live = BG.kind == def.kind
        if not (live or f.previewing) then holder:Hide() return end
        if live and f:Get("onlyClose") and def.kind == "AB" then
            local diff = math.abs((BG.score.A or 0) - (BG.score.H or 0))
            if diff > 300 then holder:Hide() return end
        end
        local data = live and { nodes = BG.nodes, health = BG.health, score = BG.score } or BG:Sample(def.kind)
        data.preview = not live
        local style = styles[f:Get("style")] or styles[def.default]
        local r = holder.render
        r:Begin()
        local prepared = def.kind == "AV" and avData(data) or abData(data)
        local ok, w, h = pcall(style, r, prepared, f)
        if not ok then geterrorhandler()(w) w, h = 200, 40 end
        r:End(w or 200, h or 40)
        holder:SetAlpha((f:Get("opacity") or 100) / 100)
        holder:Show()
    end
    local options = {
        { kind = "choice", key = "style", name = "Style", choices = def.choices },
        { kind = "check", key = "timers", name = def.kind == "AB" and "Show base timers" or "Show tower, bunker and graveyard timers" },
    }
    if def.kind == "AB" then
        options[#options + 1] = { kind = "check", key = "prediction", name = "Show win prediction" }
        options[#options + 1] = { kind = "check", key = "onlyClose", name = "Show only when the score is close" }
    end
    options[#options + 1] = { kind = "slider", key = "opacity", name = "Opacity", min = 20, max = 100, step = 5, fmt = function(v) return v .. "%" end }
    options[#options + 1] = { kind = "button", name = "Preview", always = true, onClick = function(f) f:Preview(not f.previewing) end }
    options[#options + 1] = { kind = "button", name = "Reset position", always = true, onClick = function() if holder then holder:ResetPosition() end end }
    options[#options + 1] = { kind = "note", text = "Right-click the frame to lock it or change its size. Unlocked, drag it to move it or use the mouse wheel to scale. Timers and boss health are shared with your battleground group (and with Capping users) whenever this is on." }

    return Q:Feature{
        id = def.id, tab = "pvp", section = def.section, name = def.name, desc = def.desc,
        defaults = { style = def.default, timers = true, prediction = true, onlyClose = false, opacity = 100 },
        options = options,
        detect = { { addon = "Capping" } },
        Preview = function(f, on)
            if not holder then holder = makeHolder(def.kind, def.name, def.point) end
            f.previewing = on
            if on then
                f.previewTicker = f.previewTicker or C_Timer.NewTicker(0.5, function() draw(f) end)
            elseif f.previewTicker then
                f.previewTicker:Cancel()
                f.previewTicker = nil
            end
            draw(f)
        end,
        Enable = function(f)
            if not holder then holder = makeHolder(def.kind, def.name, def.point) end
            BG:Use()
            f.listener = f.listener or function() if f.active then draw(f) end end
            if not tContains(BG.listeners, f.listener) then table.insert(BG.listeners, f.listener) end
            f:Ticker(0.25, function() if BG.kind == def.kind then draw(f) end end)
            draw(f)
        end,
        OnOption = function(f) draw(f) end,
        Disable = function(f)
            BG:Release()
            for i = #BG.listeners, 1, -1 do if BG.listeners[i] == f.listener then table.remove(BG.listeners, i) end end
            if not f.previewing and holder then holder:Hide() end
        end,
    }
end

frameFeature{
    id = "avFrame", kind = "AV", section = "Battleground timers", name = "Alterac Valley frame",
    desc = "Enemy general's health, enemy captain and officers as icons, your own officers only when they're attacked, and tower, bunker and graveyard timers only while something is being capped.",
    default = "bars", point = { "TOPRIGHT", UIParent, "TOPRIGHT", -220, -200 },
    choices = { { "compact", "Compact list" }, { "strip", "Slim strip" }, { "sides", "Two sides" }, { "bars", "Timer bars" } },
}

frameFeature{
    id = "abFrame", kind = "AB", section = "Battleground timers", name = "Arathi Basin frame",
    desc = "Score, who wins and when, the five bases with their owner, and a timer on each base being assaulted.",
    default = "compact", point = { "TOP", UIParent, "TOP", 0, -110 },
    choices = { { "compact", "Compact card" }, { "scorebar", "Score bar" }, { "list", "Base list" }, { "floating", "Floating" } },
}

function Q:TogglePreview()
    for _, id in ipairs({ "avFrame", "abFrame", "resTimer", "enemyBars" }) do
        local f = self.features[id]
        if f and f.Preview then f:Preview(not f.previewing) end
    end
end
