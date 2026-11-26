-- Encore-Alts window: one row per character, every column sortable. Hover a row for its professions,
-- cooldowns and lockouts; right-click a row (not the one you play) to forget that character.
local _, ns = ...
local A = ns.Alts
local Encore = _G.EncoreEssentials

local COLS = {
    { key = "name", head = "Character", w = 150 },
    { key = "level", head = "Level", w = 40, right = true },
    { key = "money", head = "Gold", w = 110, right = true },
    { key = "rested", head = "Rested", w = 60, right = true },
    { key = "profs", head = "Professions", w = 190 },
    { key = "cds", head = "Cooldowns", w = 110 },
    { key = "locks", head = "Lockouts", w = 60, right = true },
    { key = "seen", head = "Last seen", w = 80, right = true },
}

local win

local function ago(t)
    local s = time() - (t or 0)
    if s < 120 then return "now" end
    if s < 3600 then return math.floor(s / 60) .. " min" end
    if s < 86400 then return math.floor(s / 3600) .. " h" end
    return math.floor(s / 86400) .. " days"
end

local function untilText(t)
    local s = (t or 0) - time()
    if s <= 0 then return "ready" end
    if s < 3600 then return math.ceil(s / 60) .. " min" end
    if s < 86400 then return math.floor(s / 3600) .. " h" end
    return math.floor(s / 86400) .. " d " .. math.floor(s % 86400 / 3600) .. " h"
end

local function coins(c) return Encore.UI.Coins(c, true) end

local function activeLocks(c)
    local n = 0
    for _, l in ipairs(c.lockouts or {}) do if (l.reset or 0) > time() then n = n + 1 end end
    return n
end

local function cdSummary(c)
    local parts, soonest = {}, nil
    for _, def in ipairs(A.COOLDOWNS) do
        local at = c.cooldowns and c.cooldowns[def.key]
        if at then parts[#parts + 1] = def.name .. " " .. untilText(at); soonest = math.min(soonest or at, at) end
    end
    for _, def in ipairs(A.ITEM_COOLDOWNS) do
        local at = c.cooldowns and c.cooldowns[def.key]
        if at then parts[#parts + 1] = def.name .. " " .. untilText(at); soonest = math.min(soonest or at, at) end
    end
    return table.concat(parts, ", "), soonest
end

local function text(c, key)
    local UI = Encore.UI
    if key == "name" then return "|cff" .. A.ClassHex(c.class) .. (c.name or "?") .. "|r" end
    if key == "level" then return tostring(c.level or "?") end
    if key == "money" then return coins(c.money) end
    if key == "rested" then
        local r, max = A.RestedNow(c)
        if not r or (c.level or 0) >= (MAX_PLAYER_LEVEL or 60) then return "-", UI.DIM end
        return math.floor(r / max * 100 + 0.5) .. "%", r >= max * 1.5 and UI.GREEN or nil
    end
    if key == "profs" then
        local parts = {}
        for _, p in ipairs(c.profs or {}) do parts[#parts + 1] = p.name .. " " .. (p.rank or 0) end
        return table.concat(parts, ", ")
    end
    if key == "cds" then
        local s, soonest = cdSummary(c)
        return s, (soonest and soonest <= time()) and UI.GREEN or nil
    end
    if key == "locks" then
        local n = activeLocks(c)
        return n > 0 and tostring(n) or "-", n == 0 and UI.DIM or nil
    end
    if key == "seen" then return ago(c.seen), UI.DIM end
end

local function value(c, key)
    if key == "name" then return (c.name or ""):lower() end
    if key == "rested" then local r, max = A.RestedNow(c); return r and max and r / max or nil end
    if key == "profs" then return c.profs and c.profs[1] and c.profs[1].name or nil end
    if key == "cds" then local _, s = cdSummary(c); return s end
    if key == "locks" then return activeLocks(c) end
    return c[key]
end

local function tooltip(c, tt)
    tt:SetText("|cff" .. A.ClassHex(c.class) .. (c.name or "?") .. "|r  " .. (c.realm or ""))
    tt:AddLine(("Level %s  %s"):format(tostring(c.level or "?"), coins(c.money)), 1, 1, 1)
    for _, p in ipairs(c.profs or {}) do tt:AddDoubleLine(p.name, ("%d / %d"):format(p.rank or 0, p.max or 0), 1, 0.82, 0, 1, 1, 1) end
    local s = cdSummary(c)
    if s ~= "" then tt:AddLine(s, 0.95, 0.9, 0.81, true) end
    for _, l in ipairs(c.lockouts or {}) do
        if (l.reset or 0) > time() then tt:AddDoubleLine(l.name, "resets in " .. untilText(l.reset), 0.64, 0.57, 0.47, 0.64, 0.57, 0.47) end
    end
    if c.name and (c.name .. " - " .. (c.realm or "")) ~= A:Key() then tt:AddLine("Right-click to forget this character.", 0.64, 0.57, 0.47) end
end

local function build()
    local UI = Encore.UI
    local width = 30
    for _, c in ipairs(COLS) do width = width + c.w + 6 end
    win = UI.Window({ name = "EncoreAltsWindow", title = "Encore-Alts", width = width + 12, height = 380,
        icon = UI.MEDIA .. "encore-alts-icon" })
    if type(EncoreAltsDB) ~= "table" then EncoreAltsDB = {} end
    EncoreAltsDB.sort = EncoreAltsDB.sort or { key = "name", desc = false }
    win.total = UI.Text(win.header, "GameFontHighlight", "")
    win.total:SetPoint("LEFT", 0, 0)
    local well = UI.Well(win.content)
    well:SetAllPoints()
    win.table = UI.Table(win.content, COLS, {
        sort = EncoreAltsDB.sort,
        tooltip = tooltip,
        onRowClick = function(c, button)
            if button == "RightButton" and c.name and (c.name .. " - " .. (c.realm or "")) ~= A:Key() then
                A:Forget(c.name .. " - " .. (c.realm or ""))
            end
        end,
    })
    win.table:SetPoint("TOPLEFT", 6, -6)
    win.table:SetPoint("BOTTOMRIGHT", -4, 6)
    win:HookScript("OnShow", function() A:Refresh() end)
end

function A:Refresh()
    if not (win and win:IsShown()) then return end
    local list, gold = {}, 0
    for _, c in pairs(self:Chars()) do
        if c.name then list[#list + 1] = c; gold = gold + (c.money or 0) end
    end
    win.total:SetText(("%d characters, %s in all"):format(#list, coins(gold)))
    win.table:SetRows(list, text, value)
end

function A:Toggle()
    if not win then build() end
    win:SetShown(not win:IsShown())
end
