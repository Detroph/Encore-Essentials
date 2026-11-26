-- Encore-Professions: a levelling guide beside the profession window. Crafting professions get a route of trainer
-- and vendor recipes (cheapest, or fewest crafts), planned once and kept until you press Recalculate. Gathering
-- professions and fishing get where to farm. Saved in EncoreProfessionsDB (account-wide, routes per character).
-- Ideas from What's Training? (Fusionpit, MIT) and SkillUp Forever (cjber, GPL-3.0-or-later); see NOTICE.txt.
local addonName, ns = ...
local Encore = _G.EncoreEssentials
local P = {}
ns.P = P
_G.EncoreProfessions = P

local tocVersion = C_AddOns.GetAddOnMetadata(addonName, "Version")
P.version = (tocVersion and not tocVersion:find("@", 1, true)) and tocVersion or "dev"

function P.Print(fmt, ...)
    DEFAULT_CHAT_FRAME:AddMessage("|cffeb9339Encore-Professions|r: " .. (select("#", ...) > 0 and fmt:format(...) or fmt))
end

P.GATHERING = { Mining = "mining", Herbalism = "herbalism", Skinning = "skinning" }
P.ROUTE_OLD_DAYS = 3
P.PRICE_DRIFT = 0.15
P.WO_PER_POINT = 0.04
P.WO_MAX = 5

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
local function fullName()
    local name, second = UnitName("player")
    if second and second ~= "" and RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
        local consts = Constants and Constants.CharacterNameSeparatorConsts
        name = name .. (consts and consts.CHARACTERNAME_SURNAME_SEPARATOR or " ") .. second
    end
    return name or "?"
end

function P:DB()
    if type(EncoreProfessionsDB) ~= "table" then EncoreProfessionsDB = {} end
    local db = EncoreProfessionsDB
    if db.on == nil then db.on = true end
    db.mode = db.mode == "fast" and "fast" or "cheap"
    if db.shopping == nil then db.shopping = true end
    if type(db.chars) ~= "table" then db.chars = {} end
    if type(db.vendor) ~= "table" then db.vendor = {} end
    if type(db.lists) ~= "table" then db.lists = {} end
    return db
end

function P:Char()
    local db = self:DB()
    local key = fullName() .. " - " .. (GetRealmName() or "?")
    local c = db.chars[key]
    if type(c) ~= "table" then c = {}; db.chars[key] = c end
    if type(c.routes) ~= "table" then c.routes = {} end
    if type(c.wo) ~= "table" then c.wo = {} end
    return c
end

---------------------------------------------------------------------------
-- The profession on show
---------------------------------------------------------------------------
-- Forever reports its own profession IDs, so professions are known by name: the English one, or the name of the
-- profession's spell in other languages.
local SPELLS = { Alchemy = 2259, Blacksmithing = 2018, Enchanting = 7411, Engineering = 4036, Herbalism = 2366,
    Leatherworking = 2108, Mining = 2575, Skinning = 8613, Tailoring = 3908, Cooking = 2550, ["First Aid"] = 3273,
    Fishing = 7620 }
local byName
local function englishName(name)
    if not name or name == "" then return nil end
    if SPELLS[name] then return name end
    if not byName then
        byName = {}
        local get = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end
        for en, id in pairs(SPELLS) do
            local n = get(id)
            if n then byName[n] = en end
        end
    end
    return byName[name]
end
P.EnglishName = englishName

-- { name (English), shown (the client's name), skill, base, max } for the profession in the window, or nil.
function P:Open()
    local info = Professions and Professions.GetProfessionInfo and Professions.GetProfessionInfo()
    if not info then
        local base = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
        info = base
    end
    if type(info) ~= "table" then return nil end
    local shown = info.parentProfessionName or info.professionName
    local name = englishName(shown)
    if not name or not info.skillLevel then return nil end
    local modifier = info.skillModifier or 0
    return { name = name, shown = shown, base = info.skillLevel, skill = info.skillLevel + modifier,
        max = (info.maxSkillLevel and info.maxSkillLevel > 0) and info.maxSkillLevel or 75 }
end

function P.Knows(spell)
    if IsPlayerSpell and IsPlayerSpell(spell) then return true end
    local info = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(spell)
    return info and info.learned and true or false
end

---------------------------------------------------------------------------
-- Working Overtime (Legacy talent node 110290, tree 1187): +4% skill-up chance per point on yellow and green.
-- How the server adds it is not confirmed; this is the additive estimate SkillUp Forever uses (its #741).
-- Reading the rank follows SkillUp Forever's Core.lua (cjber, GPL-3.0-or-later).
---------------------------------------------------------------------------
local WO_NODE, WO_TREE = 110290, 1187

function P.TalentPoints()
    if type(C_Traits) ~= "table" or not C_Traits.GetConfigIDByTreeID then return 0 end
    local legacy = Constants and Constants.LegacyConsts
    local tree = legacy and legacy.LEGACY_TREE_PROFESSIONS_ID or WO_TREE
    local ok, configID = pcall(C_Traits.GetConfigIDByTreeID, tree)
    if not ok or not configID then return 0 end
    local ok2, info = pcall(C_Traits.GetNodeInfo, configID, WO_NODE)
    if not ok2 or type(info) ~= "table" then return 0 end
    local rank = tonumber(info.activeRank) or tonumber(info.currentRank) or 0
    local max = tonumber(info.maxRanks) or 0
    if max <= 0 then max = P.WO_MAX end
    return math.min(math.max(rank, 0), max)
end

-- use, points: what the guide plans with. Until you change it, it follows your talent.
function P:WorkingOvertime()
    local wo = self:Char().wo
    local talent = P.TalentPoints()
    local points = wo.points or talent
    local use = wo.use
    if use == nil then use = talent > 0 end
    return use, points, talent
end

function P:SetWorkingOvertime(use, points)
    local wo = self:Char().wo
    if use ~= nil then wo.use = use and true or false end
    if points then wo.points = math.max(0, math.min(P.WO_MAX, points)) end
end

function P:Bonus()
    local use, points = self:WorkingOvertime()
    return use and points * P.WO_PER_POINT or 0
end

---------------------------------------------------------------------------
-- Places
---------------------------------------------------------------------------
function P.ZoneName(map)
    local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    return info and info.name or ("map " .. tostring(map))
end

local function continentOf(map)
    for _ = 1, 8 do
        local info = map and C_Map.GetMapInfo(map)
        if not info then return nil end
        if Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Continent then return map end
        map = info.parentMapID
        if not map or map == 0 then return nil end
    end
end

function P.MySide()
    local f = UnitFactionGroup("player")
    return f == "Alliance" and "A" or f == "Horde" and "H" or nil
end

-- The nearest of these places for your side: on your map, then your continent, then anywhere.
function P.Nearest(list, filter)
    local side = P.MySide()
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local cont = here and continentOf(here)
    local best, bestScore
    for _, e in ipairs(list or {}) do
        if (not e.side or e.side == side) and (not filter or filter(e)) then
            local score = 3
            if e.map == here then score = 1 elseif cont and continentOf(e.map) == cont then score = 2 end
            if not bestScore or score < bestScore then best, bestScore = e, score end
        end
    end
    return best
end

function P:Trainer(prof, cap)
    return P.Nearest(ns.Trainers and ns.Trainers[prof], function(t) return (t.cap or 300) >= (cap or 0) end)
end

function P.PlaceText(e)
    if not (e and e.map) then return "" end
    return ("%s (%.0f, %.0f)"):format(P.ZoneName(e.map), e.x or 0, e.y or 0)
end

function P.Waypoint(map, x, y, title)
    if not (map and x and y) then return end
    if TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(map, x / 100, y / 100, { title = title, from = "Encore-Professions" })
        return
    end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
        if ok then
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
            P.Print("Waypoint set: %s, %s.", title or "?", P.PlaceText({ map = map, x = x, y = y }))
            return
        end
    end
    P.Print("%s: %s.", title or "?", P.PlaceText({ map = map, x = x, y = y }))
end

function P.ShowMap(map)
    if not map then return end
    if WorldMapFrame and not WorldMapFrame:IsShown() and ToggleWorldMap then ToggleWorldMap() end
    if WorldMapFrame and WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(map) end
end

-- Gold, silver and copper with the coin icons (copper left out once there is gold).
function P.Coins(copper)
    return _G.EncoreEssentials.UI.Coins(copper, true)
end

function P.Ago(t)
    local s = time() - (t or 0)
    if s < 120 then return "just now" end
    if s < 3600 then return math.floor(s / 60) .. " min ago" end
    if s < 86400 then return math.floor(s / 3600) .. " h ago" end
    local d = math.floor(s / 86400)
    return d .. (d == 1 and " day ago" or " days ago")
end

---------------------------------------------------------------------------
-- On / off
---------------------------------------------------------------------------
function P:IsOn() return self:DB().on end

function P:SetOn(on)
    self:DB().on = on and true or false
    if self.Refresh then self:Refresh() end
end

if Encore and Encore.RegisterModule then Encore:RegisterModule("Professions", P) end

SLASH_ENCOREPROFESSIONS1 = "/eprof"
SLASH_ENCOREPROFESSIONS2 = "/encoreprofessions"
SlashCmdList.ENCOREPROFESSIONS = function(input)
    local cmd = strtrim(input or ""):lower()
    if cmd == "recalc" or cmd == "recalculate" then
        if P.Recalculate and P:Recalculate() then return end
        P.Print("Open a profession first.")
    elseif cmd == "on" or cmd == "off" then
        P:SetOn(cmd == "on")
        P.Print("Guide %s.", cmd)
    elseif cmd == "help" then
        P.Print("/eprof turns the guide on or off. /eprof recalc plans the open profession's route again.")
    else
        P:SetOn(not P:IsOn())
        P.Print("Guide %s. It opens beside the profession window.", P:IsOn() and "on" or "off")
    end
end
