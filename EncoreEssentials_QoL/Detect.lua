-- Encore-QoL: conflict detection. Answers "does another addon already do this, and which one?"
--
-- A feature lists checks in f.detect, tried in order; the first that finds an owner wins:
--   { eqol = "autoRepair" }                      Enhance QoL setting on in the character's profile
--   { eqol = function(profile) return bool end }  any test on that profile
--   { leatrix = "AutoRepairGear" }               Leatrix Plus setting set to "On"
--   { addon = "BetterFishing", var = "BetterFishingDB", key = "autoLoot" }   another addon's saved value is truthy
--   { addon = "KelaGraphics" }                   the addon being loaded is enough
--   { addon = "Bartender4", replaced = true }    the addon replaces the frame ("Replaced")
--   { fn = function(f) return "Addon name" or nil end }
-- Only saved settings are read; Encore never changes them.
local _, ns = ...
local Q = ns.QoL

local IsLoaded = C_AddOns.IsAddOnLoaded

local titleCache = {}
function Q.AddonTitle(folder)
    if titleCache[folder] then return titleCache[folder] end
    local title = C_AddOns.GetAddOnMetadata(folder, "Title") or folder
    title = title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    title = strtrim(title)
    if title == "" then title = folder end
    titleCache[folder] = title
    return title
end

-- Enhance QoL keeps one profile per character, picked by GUID.
function Q.EQoLProfile()
    if not IsLoaded("EnhanceQoL") then return nil end
    local db = _G.EnhanceQoLDB
    if type(db) ~= "table" or type(db.profiles) ~= "table" then return nil end
    local keys = type(db.profileKeys) == "table" and db.profileKeys or {}
    local name = keys[UnitGUID("player") or ""] or keys[(UnitName("player") or "") .. " - " .. (GetRealmName() or "")] or "Default"
    return db.profiles[name] or db.profiles.Default
end

local function leatrix(key)
    if not IsLoaded("Leatrix_Plus") then return false end
    local db = _G.LeaPlusDB
    return type(db) == "table" and db[key] == "On"
end

local function savedValue(var, key)
    local t = _G[var]
    if type(t) ~= "table" then return nil end
    if type(key) == "table" then
        for _, k in ipairs(key) do
            if type(t) ~= "table" then return nil end
            t = t[k]
        end
        return t
    end
    return t[key]
end

local function check(f, d)
    if d.eqol then
        local profile = Q.EQoLProfile()
        if not profile then return nil end
        local on
        if type(d.eqol) == "function" then on = d.eqol(profile) else on = profile[d.eqol] == true end
        if on then return "Enhance QoL" end
    elseif d.leatrix then
        if leatrix(d.leatrix) then return "Leatrix Plus" end
    elseif d.addon then
        if IsLoaded(d.addon) then
            if d.var then
                local v = savedValue(d.var, d.key)
                if d.test then
                    if d.test(v) then return Q.AddonTitle(d.addon), d.replaced end
                elseif v and v ~= 0 and v ~= "Off" then
                    return Q.AddonTitle(d.addon), d.replaced
                end
            else
                return Q.AddonTitle(d.addon), d.replaced
            end
        end
    elseif d.fn then
        local ok, owner, replaced = pcall(d.fn, f)
        if ok and owner then return owner, replaced end
    end
    return nil
end

function Q:DetectOwner(f)
    if type(f.detect) ~= "table" then return nil end
    for _, d in ipairs(f.detect) do
        local owner, replaced = check(f, d)
        if owner then return owner, replaced end
    end
    return nil
end

-- Names the addon that replaced a global function, for hooks no list knows about (e.g. GetMinimapShape).
function Q.TaintOwner(name)
    local secure, owner = issecurevariable(name)
    if secure then return nil end
    if owner and owner ~= "" and owner ~= "EncoreEssentials_QoL" then return Q.AddonTitle(owner) end
    return nil
end

-- At most one chat line a day: features you turned on that another addon now runs.
function Q:ReportNewOverlaps()
    local today = date("%Y-%m-%d")
    if self.db.seen.overlapDay == today then return end
    local names = {}
    for _, f in ipairs(self.order) do
        if f:Saved().on and f.owner then names[#names + 1] = f.name .. " (" .. f.owner .. ")" end
    end
    if #names == 0 then return end
    self.db.seen.overlapDay = today
    self:Print("Another addon already runs: %s. Turn it off there to use Encore's. /eqol shows the overview.",
        table.concat(names, ", "))
end
