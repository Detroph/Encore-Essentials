-- Encore-QoL: enemy bars. Every enemy player in the battleground as a bar, sorted by kill priority. Left-click
-- targets, right-click focuses, also in combat. No panel behind the bars; enemies further than nameplate range
-- fade. Health shows in every battleground except Alterac Valley (too many players to keep it right).
--
-- The rows are secure buttons with /targetexact and /focus macros. Those can only be set up out of combat, so in
-- combat the order holds; health, range and the glow on the best target still update. Idea from HighGround (MIT);
-- no HighGround code is used.
local _, ns = ...
local Q = ns.QoL
local W = Q.W
local BG = Q.BG

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local FLAG_ICON = "|TInterface\\WorldStateFrame\\%sFlag:0|t "
local HEALER_SPECS = { Holy = true, Discipline = true, Restoration = true, Mistweaver = true, Preservation = true }
local CAN_HEAL = { PRIEST = true, DRUID = true, PALADIN = true, SHAMAN = true, MONK = true, EVOKER = true }
local MAX_ROWS = 40
local hpText -- set further down
-- Power colours (the game's own when it has them) and each class's usual power before it's been seen.
local POWER_COLOR = { MANA = { 0, 0.44, 0.87 }, RAGE = { 1, 0, 0 }, ENERGY = { 1, 1, 0 }, FOCUS = { 1, 0.5, 0.25 }, RUNIC_POWER = { 0, 0.82, 1 } }
if type(PowerBarColor) == "table" then
    for k in pairs(POWER_COLOR) do
        local c = PowerBarColor[k]
        if type(c) == "table" and c.r then POWER_COLOR[k] = { c.r, c.g, c.b } end
    end
end
local CLASS_POWER = { WARRIOR = "RAGE", ROGUE = "ENERGY", DEATHKNIGHT = "RUNIC_POWER" }

local function inBattleground()
    local _, kind = IsInInstance()
    return kind == "pvp"
end

local function classColor(token)
    local c = token and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(token)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]))
    if c then return c.r, c.g, c.b end
    return 0.6, 0.6, 0.6
end

local function className(token)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or (token and token:sub(1, 1) .. token:sub(2):lower()) or "?"
end

---------------------------------------------------------------------------
-- Who's out there
---------------------------------------------------------------------------
local enemies = {}   -- name -> { name, class, spec, hp, hpAt, nearAt, dead }
local flagCarrier    -- enemy name carrying our flag (Warsong Gulch)

local function myFactionIndex()
    -- Score tables use 0 for Horde and 1 for Alliance.
    if GetBattlefieldArenaFaction then
        local v = GetBattlefieldArenaFaction()
        if v == 0 or v == 1 then return v end
    end
    return UnitFactionGroup("player") == "Horde" and 0 or 1
end

local function scoreRow(i)
    if C_PvP and C_PvP.GetScoreInfo then
        local s = C_PvP.GetScoreInfo(i)
        if type(s) == "table" and s.name then return s.name, s.faction, s.classToken, s.talentSpec end
    end
    if not GetBattlefieldScore then return nil end
    local v = { GetBattlefieldScore(i) }
    local token
    for k = 8, 11 do
        if type(v[k]) == "string" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[v[k]] then token = v[k] break end
    end
    local spec = v[#v]
    return v[1], v[6], token, type(spec) == "string" and spec or nil
end

local function readScores()
    if not GetNumBattlefieldScores then return end
    local mine = myFactionIndex()
    local seen = {}
    for i = 1, GetNumBattlefieldScores() do
        local name, faction, token, spec = scoreRow(i)
        if name and faction ~= nil and faction ~= mine then
            name = Ambiguate(name, "none")
            seen[name] = true
            local e = enemies[name]
            if not e then e = { name = name }; enemies[name] = e end
            e.class = token or e.class
            if spec and spec ~= "" then e.spec = spec end
        end
    end
    for name in pairs(enemies) do if not seen[name] then enemies[name] = nil end end
end

local function unitName(unit)
    local n = Q.FullName(unit)
    return n and Ambiguate(n, "none")
end

local function readUnit(unit, near)
    if not UnitExists(unit) or not UnitIsPlayer(unit) or not UnitIsEnemy("player", unit) then return end
    local e = enemies[unitName(unit)]
    if not e then return end
    local now = GetTime()
    local max = UnitHealthMax(unit)
    e.dead = UnitIsDeadOrGhost(unit)
    if max and max > 0 then
        local cur = e.dead and 0 or UnitHealth(unit)
        e.hp = math.floor(cur / max * 100 + 0.5)
        e.hpCur, e.hpMax, e.hpAt = cur, max, now
    end
    local ptype, ptoken = UnitPowerType(unit)
    local pmax = UnitPowerMax(unit, ptype)
    if pmax and pmax > 0 then e.pp = e.dead and 0 or UnitPower(unit, ptype) / pmax; e.ptoken = ptoken end
    if near then e.nearAt = now end
    if not e.class then e.class = select(2, UnitClass(unit)) end
end

local function scanUnits()
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
            local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if unit then readUnit(unit, true) end
        end
    end
    for _, unit in ipairs({ "target", "focus", "mouseover" }) do readUnit(unit, false) end
end

local function onFlagMessage(_, msg)
    if type(msg) ~= "string" then return end
    local who = msg:match("[Ff]lag was picked up by (.+)!")
    if who then
        who = Ambiguate(who, "none")
        if enemies[who] then flagCarrier = who end
        return
    end
    if msg:find("dropped", 1, true) or msg:find("captured", 1, true) or msg:find("returned", 1, true) then
        -- Only clear when it's our flag's carrier that is named or the message names no one.
        local named = msg:match("by (.+)!")
        if not named or (flagCarrier and Ambiguate(named, "none") == flagCarrier) then flagCarrier = nil end
    end
end

---------------------------------------------------------------------------
-- Kill priority
---------------------------------------------------------------------------
local function priority(e, kind, now)
    local s, why = 0, {}
    if e.spec and HEALER_SPECS[e.spec] then
        s = s + 40; why[#why + 1] = "+40 healer (" .. e.spec .. ")"
    elseif not e.spec and CAN_HEAL[e.class or ""] then
        s = s + 20; why[#why + 1] = "+20 can heal"
    end
    if e.name == flagCarrier then s = s + 60; why[#why + 1] = "+60 carries the flag" end
    if kind ~= "AV" and e.hp and e.hpAt and now - e.hpAt < 10 and e.hp < 50 and not e.dead then
        local p = math.floor((50 - e.hp) * 0.9 + 0.5)
        s = s + p; why[#why + 1] = ("+%d at %d%% health"):format(p, e.hp)
    end
    if e.nearAt and now - e.nearAt < 1.5 then
        s = s + 10; why[#why + 1] = "+10 in range"
    else
        why[#why + 1] = "out of range or not seen"
    end
    if e.dead then s = s - 100; why[#why + 1] = "dead" end
    return s, why
end

---------------------------------------------------------------------------
-- Preview sample
---------------------------------------------------------------------------
local SAMPLE = {
    { "Corwin Ashe", "WARRIOR", "Arms" }, { "Aldric Vane", "PRIEST", "Holy" }, { "Edda Morrow", "DRUID", "Restoration" },
    { "Mira Thorne", "PALADIN", "Holy" }, { "Lyssa Brook", "MAGE" }, { "Gareth Pike", "HUNTER" }, { "Ivo Marsh", "MAGE" },
    { "Tobin Hale", "ROGUE" }, { "Selene Ward", "WARLOCK" }, { "Brann Kettle", "WARRIOR" }, { "Oswin Reed", "PRIEST", "Shadow" },
    { "Hedda Croft", "ROGUE" }, { "Piers Fell", "PALADIN", "Retribution" }, { "Wynn Stone", "HUNTER" }, { "Rook Garrow", "WARLOCK" },
    { "Tamsin Lark", "DRUID", "Feral" }, { "Bram Holt", "WARRIOR" }, { "Ilse Quill", "MAGE" }, { "Cade Dunmore", "ROGUE" }, { "Nell Bray", "PRIEST", "Discipline" },
}
local function sampleList(count, now)
    local list = {}
    for i = 1, count do
        local s = SAMPLE[(i - 1) % #SAMPLE + 1]
        local name = i > #SAMPLE and s[1] .. " " .. math.ceil(i / #SAMPLE) or s[1]
        local wave = math.sin(now / 3 + i)
        local e = { name = name, class = s[2], spec = s[3], hp = math.max(5, math.floor(55 + 45 * wave)), hpMax = 3000 + i * 137, hpAt = now, pp = 0.5 + 0.45 * math.cos(now / 4 + i), ptoken = CLASS_POWER[s[2]] or "MANA",
            nearAt = (i % 4 ~= 0) and now or nil, sample = true }
        list[#list + 1] = e
    end
    return list
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local holder, f
local rows = {}
local layoutKey

local function savedPos()
    local t = Q.db.frames.enemyBars
    if type(t) ~= "table" then t = {}; Q.db.frames.enemyBars = t end
    return t
end

local function placeHolder()
    holder:ClearAllPoints()
    local p = savedPos().point
    if type(p) == "table" and p[1] then holder:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else holder:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -220) end
end

local function showTip(btn)
    local e = btn.enemy
    if not e then return end
    GameTooltip:SetOwner(btn, "ANCHOR_CURSOR")
    GameTooltip:SetText(e.name, classColor(e.class))
    local line = className(e.class) .. (e.spec and (" · " .. e.spec) or "")
    if BG.kind ~= "AV" and e.hp then line = line .. (" · %d%% health"):format(e.hp) end
    GameTooltip:AddLine(line, W.INK[1], W.INK[2], W.INK[3])
    for _, w in ipairs(btn.why or {}) do GameTooltip:AddLine(w, W.DIM[1], W.DIM[2], W.DIM[3]) end
    if not e.sample then GameTooltip:AddLine("Left-click: target · Right-click: focus", W.GOLD[1], W.GOLD[2], W.GOLD[3]) end
    GameTooltip:Show()
end

local function makeRow(i)
    local b = CreateFrame("Button", "EncoreQoLEnemy" .. i, holder, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp")
    b:Hide()
    local v = CreateFrame("Frame", nil, b)
    v:SetAllPoints()
    b.vis = v
    b.rank = v:CreateFontString(nil, "OVERLAY")
    b.rank:SetJustifyH("RIGHT")
    b.icon = v:CreateTexture(nil, "ARTWORK")
    b.track = v:CreateTexture(nil, "BACKGROUND")
    b.track:SetColorTexture(0, 0, 0, 0.35)
    b.fill = v:CreateTexture(nil, "ARTWORK")
    b.pfill = v:CreateTexture(nil, "ARTWORK")
    b.pfill:SetTexture(WHITE)
    b.ptrack = v:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.ptrack:SetColorTexture(0, 0, 0, 0.55)
    b.fill:SetTexture(WHITE)
    b.rankBox = v:CreateTexture(nil, "ARTWORK", nil, 2)
    b.rankBox:SetColorTexture(0, 0, 0, 0.65)
    b.inRank = v:CreateFontString(nil, "OVERLAY")
    b.name = v:CreateFontString(nil, "OVERLAY")
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.hp = v:CreateFontString(nil, "OVERLAY")
    b.hp:SetJustifyH("RIGHT")
    b.glow = CreateFrame("Frame", nil, v)
    b.glow:SetPoint("TOPLEFT", b.track, -1, 1)
    b.glow:SetPoint("BOTTOMRIGHT", b.track, 1, -1)
    W.Border(b.glow, W.GOLD, 1, "OVERLAY")
    b.glow:Hide()
    b:HookScript("OnEnter", showTip)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = b
    return b
end

local function setIcon(tex, token)
    local atlas = token and ("classicon-" .. token:lower())
    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas)
        return
    end
    tex:SetTexture(CLASS_TEX)
    local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token or ""]
    if c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) else tex:SetTexCoord(0, 1, 0, 1) end
end

-- Size and place every row. Out of combat only (the rows are secure).
local function arrange(count, cfg)
    local h, w, fs = cfg.height, cfg.width, cfg.font
    local ph = cfg.power and cfg.powerH or 0
    local extra = ph > 0 and ph + 1 or 0     -- the power strip sits under the health bar
    local rh = h + extra                     -- whole row height
    local iconW = cfg.icon and (rh + 3) or 0
    local cols = cfg.style == "class"
    local rankW = cols and math.floor(fs * 1.6) + 4 or 0
    local rowW = rankW + iconW + w
    local gap = math.max(1, math.floor(h / 8 + 0.5))
    local per, groupsPerRow
    if cols then
        per = (cfg.split and count > 10) and 10 or math.max(count, 1)
        groupsPerRow = 8
    else
        per = 5
        groupsPerRow = math.max(1, cfg.perRow)
    end
    local colGap = cols and 14 or 8
    local groupH = per * rh + (per - 1) * gap
    local rowGap = cols and 0 or gap * 3
    local maxX, maxY = 0, 0
    for i = 1, MAX_ROWS do
        local b = rows[i]
        if i <= count then
            b = b or makeRow(i)
            local g = math.floor((i - 1) / per)
            local inG = (i - 1) % per
            local gx, gy = g % groupsPerRow, math.floor(g / groupsPerRow)
            local x = gx * (rowW + colGap)
            local y = gy * (groupH + rowGap) + inG * (rh + gap)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -y)
            b:SetSize(rowW, rh)
            maxX, maxY = math.max(maxX, x + rowW), math.max(maxY, y + rh)
            -- Pieces inside the row.
            local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
            b.rank:SetFont(W.FONT_TITLE, fs, "OUTLINE")
            b.rank:ClearAllPoints()
            b.rank:SetPoint("RIGHT", b, "LEFT", rankW - 4, 0)
            b.rank:SetShown(cols)
            b.icon:ClearAllPoints()
            b.icon:SetPoint("LEFT", b, "LEFT", rankW, 0)
            b.icon:SetSize(rh, rh)
            b.icon:SetShown(cfg.icon and true or false)
            b.track:ClearAllPoints()
            b.track:SetPoint("TOPLEFT", b, "TOPLEFT", rankW + iconW, 0)
            b.track:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, extra)
            b.ptrack:ClearAllPoints()
            b.ptrack:SetPoint("TOPLEFT", b.track, "BOTTOMLEFT", 0, -1)
            b.ptrack:SetPoint("TOPRIGHT", b.track, "BOTTOMRIGHT", 0, -1)
            b.ptrack:SetHeight(math.max(1, ph))
            b.ptrack:SetShown(ph > 0)
            b.pfill:ClearAllPoints()
            b.pfill:SetPoint("TOPLEFT", b.ptrack)
            b.pfill:SetPoint("BOTTOMLEFT", b.ptrack)
            b.pfill:SetShown(ph > 0)
            b.fill:ClearAllPoints()
            b.fill:SetPoint("TOPLEFT", b.track)
            b.fill:SetPoint("BOTTOMLEFT", b.track)
            local boxW = math.max(16, h)
            b.rankBox:ClearAllPoints()
            b.rankBox:SetPoint("TOPLEFT", b.track)
            b.rankBox:SetPoint("BOTTOMLEFT", b.track)
            b.rankBox:SetWidth(boxW)
            b.rankBox:SetShown(not cols)
            b.inRank:SetFont(W.FONT_TITLE, fs, "OUTLINE")
            b.inRank:ClearAllPoints()
            b.inRank:SetPoint("CENTER", b.rankBox)
            b.inRank:SetShown(not cols)
            W.Color(b.inRank, W.GOLD)
            b.name:SetFont(font, fs, "OUTLINE")
            b.name:ClearAllPoints()
            b.name:SetPoint("LEFT", b.track, "LEFT", cols and 5 or boxW + 4, 0)
            local room = ({ none = 0.5, pct = 3, value = 3.6, both = 7 })[cfg.hpText] or 3
            b.name:SetPoint("RIGHT", b.track, "RIGHT", -(fs * room), 0)
            b.hp:SetFont(font, math.max(8, fs - 1), "OUTLINE")
            b.hp:ClearAllPoints()
            b.hp:SetPoint("RIGHT", b.track, "RIGHT", -4, 0)
            b.barW = w
            b:Show()
        elseif b then
            b:Hide()
            b.enemy, b.who = nil, nil
        end
    end
    holder:SetSize(math.max(maxX, 40), math.max(maxY, 20))
end

-- Point each row's macros at its enemy. Out of combat only.
local function bindRows(list, previewing)
    for i, e in ipairs(list) do
        local b = rows[i]
        if b and b.who ~= e.name then
            b.who = e.name
            if previewing or e.sample then
                b:SetAttribute("type1", nil)
                b:SetAttribute("type2", nil)
            else
                b:SetAttribute("type1", "macro")
                b:SetAttribute("macrotext1", "/targetexact " .. e.name)
                b:SetAttribute("type2", "macro")
                b:SetAttribute("macrotext2", "/focus " .. e.name)
            end
        end
    end
end

-- Health, range and text. Safe in combat.
local function paint(b, e, rank, kind, now, cfg, best)
    b.enemy = e
    local r, g, bl = classColor(e.class)
    local showHP = kind ~= "AV"
    local pct = (showHP and e.hp) and e.hp / 100 or 1
    if e.dead then pct = 0 end
    b.fill:SetVertexColor(r, g, bl, 0.9)
    b.fill:SetWidth(math.max(0.01, b.barW * pct))
    b.rank:SetText(rank)
    W.Color(b.rank, W.GOLD)
    b.inRank:SetText(rank)
    local mark = ""
    if e.name == flagCarrier then mark = FLAG_ICON:format(UnitFactionGroup("player") == "Horde" and "Horde" or "Alliance") end
    if (e.spec and HEALER_SPECS[e.spec]) then mark = mark .. "|cff40ff40+|r " end
    b.name:SetText(mark .. e.name)
    b.name:SetTextColor(1, 1, 1)
    b.hp:SetText(e.dead and "dead" or (showHP and hpText(e, cfg.hpText)) or "")
    if cfg.icon then setIcon(b.icon, e.class) end
    local near = e.nearAt and now - e.nearAt < 1.5
    if not f.fadeKnown then near = true end
    b.vis:SetAlpha(near and 1 or 0.32)
    b.glow:SetShown(best and true or false)
    if cfg.power then
        local c = (e.ptoken and POWER_COLOR[e.ptoken]) or POWER_COLOR[CLASS_POWER[e.class or ""] or "MANA"]
        local known = showHP and e.pp
        b.pfill:SetVertexColor(c[1], c[2], c[3], known and 0.95 or 0.35)
        b.pfill:SetWidth(math.max(0.01, b.barW * (known and e.pp or 1)))
    end
    local _, why = priority(e, kind, now)
    b.why = why
end

-- Health text: "pct" (76%), "value" (4.2k), "both" (4.2k · 76%) or "none".
local function short(n)
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 10000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
end
hpText = function(e, mode)
    if not e.hp or mode == "none" then return nil end
    local cur = e.hpCur or (e.hpMax and e.hpMax * e.hp / 100)
    if mode == "value" and cur then return short(cur) end
    if mode == "both" and cur then return short(cur) .. " · " .. e.hp .. "%" end
    return e.hp .. "%"
end

local function config()
    return {
        style = f:Live("style"), max = tonumber(f:Live("maxShown")) or 15,
        height = tonumber(f:Live("height")) or 20, width = tonumber(f:Live("width")) or 210, font = tonumber(f:Live("font")) or 12,
        icon = f:Live("icon") and true or false, split = f:Live("split") and true or false, perRow = tonumber(f:Live("perRow")) or 2,
        hpText = f:Live("hpText") or "pct",
        power = f:Live("power") and true or false, powerH = tonumber(f:Live("powerH")) or 4,
    }
end

local function ranked(now, kind)
    local list = {}
    for _, e in pairs(enemies) do list[#list + 1] = e end
    for _, e in ipairs(list) do e.score = priority(e, kind, now) end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.name < b.name
    end)
    return list
end

local function update()
    if not holder or not f then return end
    local now = GetTime()
    local live = f.active and inBattleground()
    local previewing = not live and f.previewing
    if not live and not previewing then
        if not InCombatLockdown() then holder:Hide() end
        return
    end
    local kind = BG.kind or (previewing and (f:Saved().editBG or "WSG")) or "other"
    local cfg = config()
    local list
    if live then
        f.fadeKnown = not (C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("nameplateShowEnemies") == false)
        list = ranked(now, kind)
    else
        f.fadeKnown = true
        list = sampleList(math.min(cfg.max, 20), now)
        for _, e in ipairs(list) do e.score = priority(e, kind, now) end
        table.sort(list, function(a, b) return a.score > b.score end)
    end
    local count = math.min(#list, cfg.max, MAX_ROWS)

    if not InCombatLockdown() then
        -- Out of combat: rows follow the priority order.
        local key = table.concat({ count, cfg.style, cfg.height, cfg.width, cfg.font, tostring(cfg.icon), tostring(cfg.split), cfg.perRow, tostring(cfg.power), cfg.powerH, cfg.hpText }, ":")
        if key ~= layoutKey then
            layoutKey = key
            arrange(count, cfg)
        end
        bindRows(list, previewing)
        for i = 1, count do paint(rows[i], list[i], i, kind, now, cfg, false) end
        holder.mover:SetShown(not f:Get("locked"))
        holder:Show()
    else
        -- In combat: the rows keep their enemy; the best one glows.
        local best, bestScore
        for i = 1, count do
            local b = rows[i]
            local e = b and b.who and (enemies[b.who] or (b.enemy and b.enemy.sample and b.enemy))
            if e then
                local s = priority(e, kind, now)
                if not bestScore or s > bestScore then best, bestScore = i, s end
            end
        end
        for i = 1, count do
            local b = rows[i]
            local e = b and b.who and (enemies[b.who] or b.enemy)
            if e and b:IsShown() then paint(b, e, i, kind, now, cfg, i == best and best ~= 1) end
        end
        holder.mover:Hide()
    end
end

local function makeHolder()
    holder = CreateFrame("Frame", "EncoreQoLEnemyBars", UIParent)
    holder:SetSize(240, 200)
    holder:SetFrameStrata("MEDIUM")
    holder:SetClampedToScreen(true)
    holder:SetMovable(true)
    holder:Hide()
    -- While unlocked a cover lies over the rows: drag it to move the bars (out of combat).
    local m = CreateFrame("Frame", nil, holder)
    m:SetPoint("TOPLEFT", -4, 4)
    m:SetPoint("BOTTOMRIGHT", 4, -4)
    m:SetFrameLevel(holder:GetFrameLevel() + 30)
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    local shade = m:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(1, 0.82, 0, 0.06)
    W.Border(m, W.GOLD, 0.9, "OVERLAY")
    local tag = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tag:SetPoint("BOTTOM", m, "TOP", 0, 3)
    tag:SetText("Drag to move · lock it in Encore-QoL options")
    m:SetScript("OnDragStart", function() if not InCombatLockdown() then holder:StartMoving() end end)
    m:SetScript("OnDragStop", function()
        holder:StopMovingOrSizing()
        local p, _, rp, x, y = holder:GetPoint(1)
        savedPos().point = { p, rp, x, y }
    end)
    m:Hide()
    holder.mover = m
    placeHolder()
end

---------------------------------------------------------------------------
-- Feature
---------------------------------------------------------------------------
f = Q.PvPScoped({
    id = "enemyBars", tab = "pvp", section = "Enemies", name = "Enemy bars",
    desc = "Every enemy as a class-coloured bar, best kill first: healers, the flag carrier and low health go up, enemies in range a little. Left-click targets, right-click focuses, also in combat (the order then holds and the new best target glows). Enemies out of nameplate range fade; health shows everywhere except Alterac Valley.",
    defaults = { style = "class", maxShown = 15, height = 20, width = 210, font = 12, icon = true, split = false, perRow = 2, power = true, powerH = 4, hpText = "pct", locked = false },
    detect = { { addon = "HighGround" } },
    options = {
        { kind = "group", text = "Look" },
        { kind = "choice", key = "style", name = "Style", choices = { { "class", "Class bars" }, { "five", "Columns of five" } } },
        { kind = "slider", key = "maxShown", name = "Show at most", min = 5, max = 40, step = 1, fmt = function(v) return v .. " enemies" end },
        { kind = "slider", key = "height", name = "Bar height", min = 10, max = 32, step = 1, fmt = function(v) return v .. " px" end },
        { kind = "slider", key = "width", name = "Bar width", min = 80, max = 280, step = 5, fmt = function(v) return v .. " px" end },
        { kind = "slider", key = "font", name = "Font size", min = 8, max = 18, step = 1, fmt = function(v) return v .. " pt" end },
        { kind = "check", key = "icon", name = "Class icon in front of the bar" },
        { kind = "choice", key = "hpText", name = "Health text", choices = { { "pct", "Percent (76%)" }, { "value", "Real value (4.2k)" }, { "both", "Both (4.2k · 76%)" }, { "none", "None" } } },
        { kind = "check", key = "power", name = "Mana, rage and energy bar under the health" },
        { kind = "slider", key = "powerH", name = "Power bar height", min = 2, max = 12, step = 1, fmt = function(v) return v .. " px" end },
        { kind = "group", text = "Class bars", when = function(self) return self:Get("style") == "class" end },
        { kind = "check", key = "split", name = "Columns of 10 (two columns at 20 enemies)" },
        { kind = "group", text = "Columns of five", when = function(self) return self:Get("style") == "five" end },
        { kind = "slider", key = "perRow", name = "Columns of five per row", min = 1, max = 8, step = 1 },
        { kind = "group", text = "Position" },
        { kind = "check", key = "locked", name = "Lock position" },
        { kind = "button", name = "Preview", always = true, onClick = function(self) self:Preview(not self.previewing) end },
        { kind = "button", name = "Reset position", always = true, onClick = function() savedPos().point = nil if holder and not InCombatLockdown() then placeHolder() end end },
        { kind = "note", text = "Unlocked, drag the bars to move them (out of combat). Right-click on a bar is focus, so lock them here." },
    },
}, { "style", "maxShown", "height", "width", "font", "icon", "split", "perRow", "power", "powerH", "hpText" })

function f:Preview(on)
    if InCombatLockdown() then Q:Print("Enemy bars: preview after combat.") return end
    if not holder then makeHolder() end
    self.previewing = on
    layoutKey = nil
    if on then
        self.previewTicker = self.previewTicker or C_Timer.NewTicker(0.5, update)
    elseif self.previewTicker then
        self.previewTicker:Cancel()
        self.previewTicker = nil
    end
    update()
end

local lastInBG
local function zone()
    local inside = inBattleground()
    if inside ~= lastInBG then
        lastInBG = inside
        wipe(enemies)
        flagCarrier = nil
        layoutKey = nil
        if inside and RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
    end
    update()
end

function f:Enable()
    if not holder then makeHolder() end
    BG:Use()
    lastInBG = nil
    self:On("PLAYER_ENTERING_WORLD", zone)
    self:On("ZONE_CHANGED_NEW_AREA", zone)
    self:On("UPDATE_BATTLEFIELD_SCORE", function() if inBattleground() then readScores() end end)
    self:On("CHAT_MSG_BG_SYSTEM_ALLIANCE", onFlagMessage)
    self:On("CHAT_MSG_BG_SYSTEM_HORDE", onFlagMessage)
    self:On("CHAT_MSG_BG_SYSTEM_NEUTRAL", onFlagMessage)
    self:On("PLAYER_REGEN_ENABLED", function() layoutKey = nil update() end)
    self:Ticker(5, function() if inBattleground() and RequestBattlefieldScoreData then RequestBattlefieldScoreData() end end)
    self:Ticker(0.25, function()
        if inBattleground() then scanUnits() end
        update()
    end)
    zone()
end

function f:OnOption()
    layoutKey = nil
    if not InCombatLockdown() then update() end
end

function f:Disable()
    BG:Release()
    if holder and not self.previewing and not InCombatLockdown() then holder:Hide() end
end

Q:Feature(f)

-- For tests.
Q.EnemyData = { enemies = enemies, readScores = readScores, priority = priority, onFlag = onFlagMessage, flag = function() return flagCarrier end }
