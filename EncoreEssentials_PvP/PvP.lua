-- Encore-PvP: the module itself. Its features (timers, frames, enemy bars, resurrection timer, helpers) register
-- into Encore-QoL and show on the PvP page of the Encore-QoL window, with their settings kept in EncoreQoLDB as
-- before. This file adds the module's hub tile, /epvp, and Battleground history (saved in EncorePvPDB).
local addonName = ...
local Q = _G.EncoreQoL
local Encore = _G.EncoreEssentials
local P = {}
_G.EncorePvP = P

local tocVersion = C_AddOns.GetAddOnMetadata(addonName, "Version")
P.version = (tocVersion and not tocVersion:find("@", 1, true)) and tocVersion or "dev"

function P:Toggle()
    if Q and Q.ready and Q.ShowTab then Q:ShowTab("pvp") end
end

local function db()
    if type(EncorePvPDB) ~= "table" then EncorePvPDB = {} end
    local d = EncorePvPDB
    if type(d.history) ~= "table" then d.history = {} end
    if type(d.window) ~= "table" then d.window = {} end
    return d
end

---------------------------------------------------------------------------
-- Battleground history: one line per finished battleground
---------------------------------------------------------------------------
local KEEP = 300 -- default for "Games kept"
local match -- the battleground being played: { map, start }
local saved -- true once this match was written

local function myScore()
    local first = UnitName("player")
    local full = Q.FullName and Q.FullName("player") or first
    for i = 1, (GetNumBattlefieldScores and GetNumBattlefieldScores() or 0) do
        local name, kb, hk, deaths, honor = GetBattlefieldScore(i)
        local short = name and Ambiguate(name, "short")
        if name and (name == full or short == full or name == first or short == first) then
            return kb, hk, deaths, honor
        end
    end
end

local function finish(f)
    if saved or not match then return end
    local winner = GetBattlefieldWinner and GetBattlefieldWinner()
    if winner == nil then return end
    saved = true
    local side = UnitFactionGroup("player") == "Horde" and 0 or 1
    local kb, hk, deaths, honor = myScore()
    local h = db().history
    table.insert(h, 1, {
        t = time(), map = match.map, won = (winner == side) or nil, draw = (winner ~= 0 and winner ~= 1) or nil,
        secs = math.floor(GetTime() - match.start), kb = kb, hk = hk, deaths = deaths, honor = honor and math.floor(honor),
    })
    P.TrimHistory(f:Get("keep"))
    if f:Get("chat") then
        local e = h[1]
        Q:Print("%s: %s in %d:%02d, %d honorable kills, %d honor.", tostring(e.map), e.won and "won" or (e.draw and "draw" or "lost"),
            math.floor(e.secs / 60), e.secs % 60, e.hk or 0, e.honor or 0)
    end
    if P.RefreshHistory then P.RefreshHistory() end
end

-- Drops the oldest games beyond the limit.
function P.TrimHistory(keep)
    keep = math.max(1, math.floor(tonumber(keep) or KEEP))
    local h = db().history
    for i = #h, keep + 1, -1 do h[i] = nil end
    if P.RefreshHistory then P.RefreshHistory() end
end

function P.ClearHistory()
    db().history = {}
    if P.RefreshHistory then P.RefreshHistory() end
    Q:Print("Battleground history deleted.")
end

StaticPopupDialogs["ENCORE_PVP_CLEAR_HISTORY"] = {
    text = "Delete your whole battleground history? This cannot be undone.",
    button1 = YES, button2 = NO,
    OnAccept = function() P.ClearHistory() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function zone(f)
    local inside, kind = IsInInstance()
    if inside and kind == "pvp" then
        local name = GetInstanceInfo()
        if not match or match.map ~= name then
            match, saved = { map = name, start = GetTime() }, false
        end
    else
        match = nil
    end
end

---------------------------------------------------------------------------
-- History window: summary per battleground and every match, all columns click-to-sort
---------------------------------------------------------------------------
local COLS = {
    { key = "t", head = "Date", w = 110 },
    { key = "map", head = "Battleground", w = 150 },
    { key = "result", head = "Result", w = 60 },
    { key = "secs", head = "Time", w = 54, right = true },
    { key = "kb", head = "KB", w = 36, right = true },
    { key = "hk", head = "HK", w = 40, right = true },
    { key = "deaths", head = "Deaths", w = 50, right = true },
    { key = "honor", head = "Honor", w = 56, right = true },
}
local ROW_H = 18
local win

local function resultOf(e) return e.won and "Won" or (e.draw and "Draw" or "Lost") end

local function sortValue(e, key)
    if key == "result" then return e.won and 2 or (e.draw and 1 or 0) end
    local v = e[key]
    if v == nil then return key == "map" and "" or -1 end
    return v
end

local function cellText(e, key)
    if key == "t" then return date("%Y-%m-%d %H:%M", e.t) end
    if key == "result" then return resultOf(e) end
    if key == "secs" then return ("%d:%02d"):format(math.floor((e.secs or 0) / 60), (e.secs or 0) % 60) end
    local v = e[key]
    return v ~= nil and tostring(v) or "-"
end

local function summary(list)
    local per, order = {}, {}
    for _, e in ipairs(list) do
        local s = per[e.map or "?"]
        if not s then s = { map = e.map or "?", n = 0, won = 0 }; per[s.map] = s; order[#order + 1] = s end
        s.n, s.won = s.n + 1, s.won + (e.won and 1 or 0)
    end
    table.sort(order, function(a, b) return a.n > b.n end)
    local parts = {}
    for _, s in ipairs(order) do
        parts[#parts + 1] = ("%s %d/%d (%d%%)"):format(s.map, s.won, s.n, math.floor(s.won / s.n * 100 + 0.5))
    end
    return #parts > 0 and ("Won: " .. table.concat(parts, "   ")) or "No battlegrounds recorded yet. Turn on Battleground history and play one."
end

local function buildWindow()
    local UI = Encore.UI
    local width = 28
    for _, c in ipairs(COLS) do width = width + c.w + 6 end
    win = UI.Window({ name = "EncorePvPHistory", title = "Battleground history", width = width, height = 440,
        icon = UI.MEDIA .. "encore-pvp-icon" })
    win.sort = db().window.sort or { key = "t", desc = true }
    win.summary = UI.Text(win.content, "GameFontHighlightSmall", "")
    win.summary:SetPoint("TOPLEFT", 0, 0)
    win.summary:SetPoint("RIGHT", 0, 0)
    win.summary:SetWordWrap(true)
    win.heads = {}
    local x = 0
    for _, c in ipairs(COLS) do
        local b = CreateFrame("Button", nil, win.content)
        b:SetSize(c.w, 18)
        b:SetPoint("TOPLEFT", x, -34)
        b.text = UI.Text(b, "GameFontNormalSmall", c.head, UI.GOLD)
        b.text:SetAllPoints()
        b.text:SetJustifyH(c.right and "RIGHT" or "LEFT")
        b:SetScript("OnClick", function()
            if win.sort.key == c.key then win.sort.desc = not win.sort.desc else win.sort.key, win.sort.desc = c.key, c.key ~= "map" end
            db().window.sort = win.sort
            P.RefreshHistory()
        end)
        b.col = c
        win.heads[#win.heads + 1] = b
        x = x + c.w + 6
    end
    local scroll = CreateFrame("ScrollFrame", nil, win.content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -56)
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(x, 10)
    scroll:SetScrollChild(child)
    win.child, win.rows = child, {}
end

local function row(i)
    local r = win.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, win.child)
    r:SetSize(win.child:GetWidth(), ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    if i % 2 == 0 then
        local bg = r:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.04)
    end
    r.cells = {}
    local x = 0
    for k, c in ipairs(COLS) do
        local fs = Encore.UI.Text(r, "GameFontHighlightSmall", "")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(c.w)
        fs:SetJustifyH(c.right and "RIGHT" or "LEFT")
        fs:SetWordWrap(false)
        r.cells[k] = fs
        x = x + c.w + 6
    end
    win.rows[i] = r
    return r
end

function P.RefreshHistory()
    if not (win and win:IsShown()) then return end
    local list = {}
    for i, e in ipairs(db().history) do list[i] = e end
    local key, desc = win.sort.key, win.sort.desc
    table.sort(list, function(a, b)
        local x, y = sortValue(a, key), sortValue(b, key)
        if type(x) ~= type(y) then x, y = tostring(x), tostring(y) end
        if x == y then return (a.t or 0) > (b.t or 0) end
        if desc then return x > y end
        return x < y
    end)
    win.summary:SetText(summary(list))
    for _, b in ipairs(win.heads) do
        local arrow = (b.col.key == key) and (desc and " v" or " ^") or ""
        b.text:SetText(b.col.head .. arrow)
    end
    for i, e in ipairs(list) do
        local r = row(i)
        for k, c in ipairs(COLS) do
            r.cells[k]:SetText(cellText(e, c.key))
            if c.key == "result" then
                local col = e.won and Encore.UI.GREEN or (e.draw and Encore.UI.DIM or Encore.UI.RED)
                Encore.UI.Color(r.cells[k], col)
            end
        end
        r:Show()
    end
    for i = #list + 1, #win.rows do win.rows[i]:Hide() end
    win.child:SetHeight(math.max(10, #list * ROW_H))
end

function P:ShowHistory()
    if not win then buildWindow() end
    win:Show()
    P.TrimHistory(Q:Get("bgHistory", "keep"))
    P.RefreshHistory()
end

Q:Feature{
    id = "bgHistory", tab = "pvp", section = "Battleground helpers", name = "Battleground history",
    desc = "Keeps a line for every battleground you finish: which one, won or lost, how long, killing blows, honorable kills, deaths and honor. Only the newest games are kept, as many as you set.",
    defaults = { chat = true, keep = KEEP },
    options = {
        { kind = "check", key = "chat", name = "Sum up each match in chat" },
        { kind = "slider", key = "keep", name = "Games kept", min = 25, max = 1000, step = 25,
            tip = "How many battlegrounds the history keeps. When it is full, the oldest game goes. Lowering it deletes the oldest games at once." },
        { kind = "button", name = "Open history", always = true, onClick = function() P:ShowHistory() end },
        { kind = "button", name = "Delete history", always = true, onClick = function() StaticPopup_Show("ENCORE_PVP_CLEAR_HISTORY") end },
    },
    OnOption = function(f, key, value)
        if key == "keep" then P.TrimHistory(value) end
    end,
    Enable = function(f)
        f:On("PLAYER_ENTERING_WORLD", function() zone(f) end)
        f:On("ZONE_CHANGED_NEW_AREA", function() zone(f) end)
        f:On("UPDATE_BATTLEFIELD_SCORE", function() finish(f) end)
        f:On("UPDATE_BATTLEFIELD_STATUS", function()
            if match and not saved and GetBattlefieldWinner and GetBattlefieldWinner() ~= nil then
                if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
                C_Timer.After(1, function() finish(f) end)
            end
        end)
        zone(f)
    end,
}

---------------------------------------------------------------------------
-- Module registration and /epvp
---------------------------------------------------------------------------
if Encore and Encore.RegisterModule then Encore:RegisterModule("PvP", P) end

SLASH_ENCOREPVP1 = "/epvp"
SLASH_ENCOREPVP2 = "/encorepvp"
SlashCmdList.ENCOREPVP = function(input)
    local cmd = strtrim(input or ""):lower()
    if cmd == "history" then
        P:ShowHistory()
    elseif cmd == "history clear" then
        StaticPopup_Show("ENCORE_PVP_CLEAR_HISTORY")
    elseif cmd == "bgpoi" and Q.BG and Q.BG.DumpPOIs then
        Q.BG:DumpPOIs()
    else
        P:Toggle()
    end
end
