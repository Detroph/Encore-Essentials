-- Encore-QoL: core. Saved settings, the feature list and the switch logic.
--
-- Every feature is registered with Q:Feature{...} by a file under Features/, PvP/ or Professions/. A feature
-- does nothing and hooks nothing until it is switched on. Before it runs, its conflict check (Detect.lua) asks
-- whether another addon already does the same thing; if one does, Encore stays out and the switch is locked
-- with that addon named. Encore never changes another addon's settings.
local addonName, ns = ...

local Q = {}
ns.QoL = Q
_G.EncoreQoL = Q

local tocVersion = C_AddOns.GetAddOnMetadata(addonName, "Version")
Q.version = (tocVersion and not tocVersion:find("@", 1, true)) and tocVersion or "dev"
Q.SCHEMA = 1
Q.MEDIA = "Interface\\AddOns\\EncoreEssentials\\Media\\"
Q.ICON = Q.MEDIA .. "encore-qol-icon"

local CHAT_PREFIX = "|cffeb9339Encore-QoL|r: "
function Q:Print(fmt, ...)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. (select("#", ...) > 0 and fmt:format(...) or fmt))
end

-- Tabs in window order. "overview" is built by the window itself.
Q.TABS = {
    { id = "overview", name = "Overview" },
    { id = "qol", name = "Quality of life" },
    { id = "interface", name = "Interface" },
    { id = "visual", name = "Visual & audio" },
    { id = "combat", name = "Combat" },
    { id = "pvp", name = "PvP" },
    { id = "professions", name = "Professions" },
}

---------------------------------------------------------------------------
-- Saved data. EncoreQoLDB is account-wide. Professions keeps its own table (EncoreQoLProfDB) so the tab can
-- move into its own addon later and keep its settings.
--   db.features[id] = { on = true|nil, <option> = value, ... }
---------------------------------------------------------------------------
local function initTable(name)
    local t = _G[name]
    if type(t) ~= "table" then t = {}; _G[name] = t end
    t.schema = t.schema or Q.SCHEMA
    if type(t.features) ~= "table" then t.features = {} end
    if type(t.frames) ~= "table" then t.frames = {} end
    return t
end

function Q:InitDB()
    self.db = initTable("EncoreQoLDB")
    self.profDB = initTable("EncoreQoLProfDB")
    if type(self.db.window) ~= "table" then self.db.window = {} end
    if type(self.db.seen) ~= "table" then self.db.seen = {} end
end

---------------------------------------------------------------------------
-- Events: one frame, any number of listeners per event.
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local listeners = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = listeners[event]
    if not list then return end
    for i = #list, 1, -1 do
        local entry = list[i]
        if entry then
            local ok, err = pcall(entry.fn, event, ...)
            if not ok then geterrorhandler()(err) end
        end
    end
end)

-- Q:On("EVENT", fn [, unit1, unit2]) returns a handle for Q:Off.
function Q:On(event, fn)
    local list = listeners[event]
    if not list then
        list = {}
        listeners[event] = list
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    local entry = { fn = fn, event = event }
    list[#list + 1] = entry
    return entry
end

function Q:Off(entry)
    local list = entry and listeners[entry.event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == entry then table.remove(list, i) end
    end
    if #list == 0 then
        listeners[entry.event] = nil
        pcall(eventFrame.UnregisterEvent, eventFrame, entry.event)
    end
end

-- Work that must wait until combat ends (protected frames, bindings).
local afterCombat = {}
function Q:AfterCombat(key, fn)
    if not InCombatLockdown() then
        fn()
        return
    end
    afterCombat[key] = fn
end
Q:On("PLAYER_REGEN_ENABLED", function()
    local queue = afterCombat
    afterCombat = {}
    for _, fn in pairs(queue) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end)

---------------------------------------------------------------------------
-- Features
---------------------------------------------------------------------------
Q.features = {}  -- id -> feature
Q.order = {}     -- registration order

local Feature = {}
Feature.__index = Feature

-- Saved table for this feature (in the Professions table for the Professions tab).
function Feature:Saved()
    local root = (self.tab == "professions") and Q.profDB or Q.db
    local t = root.features[self.id]
    if type(t) ~= "table" then t = {}; root.features[self.id] = t end
    return t
end

function Feature:Get(key)
    local v = self:Saved()[key]
    if v == nil and self.defaults then v = self.defaults[key] end
    return v
end

function Feature:Set(key, value)
    self:Saved()[key] = value
    if self.active and self.OnOption then
        local ok, err = pcall(self.OnOption, self, key, value)
        if not ok then geterrorhandler()(err) end
    end
    Q:Changed(self)
end

-- Listeners and timers made through the feature are dropped automatically when it turns off.
function Feature:On(event, fn)
    self._events = self._events or {}
    local entry = Q:On(event, function(...) if self.active then fn(...) end end)
    self._events[#self._events + 1] = entry
    return entry
end

function Feature:Ticker(seconds, fn)
    self._tickers = self._tickers or {}
    local t = C_Timer.NewTicker(seconds, function() if self.active then fn() end end)
    self._tickers[#self._tickers + 1] = t
    return t
end

-- hooksecurefunc can't be undone, so the hook is made once and only does something while the feature is on.
-- f:Hook("GlobalFunction", fn) or f:Hook(table, "method", fn).
function Feature:Hook(target, method, fn)
    if fn == nil then target, method, fn = _G, target, method end
    if type(target) ~= "table" or type(target[method]) ~= "function" then return end
    self._hooked = self._hooked or {}
    local key = tostring(target) .. ":" .. method
    if self._hooked[key] then return end
    self._hooked[key] = true
    local wrapped = function(...) if self.active then fn(...) end end
    if target == _G then hooksecurefunc(method, wrapped) else hooksecurefunc(target, method, wrapped) end
end

function Feature:HookScript(frame, script, fn)
    if not frame then return end
    self._scripts = self._scripts or {}
    local key = tostring(frame) .. ":" .. script
    if self._scripts[key] then return end
    self._scripts[key] = true
    frame:HookScript(script, function(...) if self.active then fn(...) end end)
end

local function cleanup(f)
    for _, e in ipairs(f._events or {}) do Q:Off(e) end
    for _, t in ipairs(f._tickers or {}) do t:Cancel() end
    f._events, f._tickers = nil, nil
end

-- Q:Feature{ id, tab, section, name, desc, defaults = {}, options = {...},
--            detect = {...} (see Detect.lua), Enable = fn(self), Disable = fn(self), OnOption = fn(self, key, v),
--            needsReload = true when turning off can't be undone without /reload }
function Q:Feature(def)
    assert(def.id and def.tab and def.name, "feature needs id, tab and name")
    local f = setmetatable(def, Feature)
    f.status = "off"
    self.features[f.id] = f
    self.order[#self.order + 1] = f
    if self.ready then self:Apply(f) end
    return f
end

-- Status: "off", "on" (Encore runs it), "locked" (f.owner names the addon), "replaced", "error".
function Q:Apply(f)
    local wanted = f:Saved().on == true
    local owner, replaced = self:DetectOwner(f)
    if owner then
        f.owner, f.replaced = owner, replaced
        if f.active then self:Stop(f) end
        f.status = replaced and "replaced" or "locked"
        return
    end
    f.owner, f.replaced = nil, nil
    if wanted and not f.active then
        self:Start(f)
    elseif not wanted and f.active then
        self:Stop(f)
    end
    if not f.active and f.status ~= "error" then f.status = "off" end
end

function Q:Start(f)
    f.active = true
    f.status = "on"
    if f.Enable then
        local ok, err = pcall(f.Enable, f)
        if not ok then
            f.active = false
            f.status = "error"
            f.error = err
            cleanup(f)
            geterrorhandler()(err)
        end
    end
end

function Q:Stop(f)
    f.active = false
    if f.Disable then
        local ok, err = pcall(f.Disable, f)
        if not ok then geterrorhandler()(err) end
    end
    cleanup(f)
    f.status = "off"
end

-- Called by the window's switch.
function Q:SetEnabled(id, on)
    local f = self.features[id]
    if not f then return end
    if f.owner then return end -- locked: turn it off in the other addon first
    f:Saved().on = on and true or nil
    self:Apply(f)
    if not on and f.needsReload then self:Print("%s is off. A /reload puts the game's own version fully back.", f.name) end
    self:Changed(f)
end

function Q:IsEnabled(id)
    local f = self.features[id]
    return f and f.active == true
end

function Q:Get(id, key)
    local f = self.features[id]
    return f and f:Get(key)
end

-- The window listens for this to redraw.
Q.callbacks = {}
function Q:Changed(f)
    for _, cb in ipairs(self.callbacks) do pcall(cb, f) end
end

function Q:Recheck()
    for _, f in ipairs(self.order) do self:Apply(f) end
    self:Changed()
end

---------------------------------------------------------------------------
-- Helpers used by several features
---------------------------------------------------------------------------
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

-- Money as gold, silver and copper with coin icons; zero parts left out.
function Q.Coins(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = BreakUpLargeNumbers and BreakUpLargeNumbers(g) .. GOLD_ICON or g .. GOLD_ICON end
    if s > 0 then parts[#parts + 1] = s .. SILVER_ICON end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. COPPER_ICON end
    return table.concat(parts, " ")
end

Q.GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
Q.GetContainerNumSlots = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
Q.GetContainerNumFreeSlots = (C_Container and C_Container.GetContainerNumFreeSlots) or _G.GetContainerNumFreeSlots
Q.GetContainerItemInfo = (C_Container and C_Container.GetContainerItemInfo) or _G.GetContainerItemInfo
Q.UseContainerItem = (C_Container and C_Container.UseContainerItem) or _G.UseContainerItem

function Q.SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id)) or nil
end

-- A unit's whole name. On WoW Forever UnitName gives the first name and the surname apart, while chat and addon
-- messages carry them joined ("Berya Ebonlocke"); elsewhere the second value is the realm and is left off.
function Q.FullName(unit)
    local name, second = UnitName(unit or "player")
    if not name then return nil end
    if second and second ~= "" and RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
        local consts = Constants and Constants.CharacterNameSeparatorConsts
        return name .. (consts and consts.CHARACTERNAME_SURNAME_SEPARATOR or " ") .. second
    end
    return name
end

-- Shift held means "not this time" for every automation.
function Q.Skip() return IsShiftKeyDown() end

-- Party or raid chat for announcements, never say.
function Q.GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

-- Remembers a CVar's value the first time Encore changes it, and puts it back later.
-- The original is kept in the saved data (EncoreQoLDB.cvars), because the game saves CVars across sessions: a
-- value kept only in memory was lost at the next /reload, and turning the feature off then changed nothing.
-- temporary = true for short boosts (fishing sound): those are put back at logout, and at the next login if the
-- game closed without one.
local memoryCVars = {}
local function cvarStore()
    local db = Q.db
    if not db then return memoryCVars, {} end
    if type(db.cvars) ~= "table" then db.cvars = {} end
    if type(db.cvarTemp) ~= "table" then db.cvarTemp = {} end
    return db.cvars, db.cvarTemp
end
function Q.SetCVar(name, value, temporary)
    local current = C_CVar.GetCVar(name)
    if current == nil then return false end
    local originals, temp = cvarStore()
    if originals[name] == nil then originals[name] = current end
    if temporary then temp[name] = true end
    C_CVar.SetCVar(name, tostring(value))
    return true
end
function Q.RestoreCVar(name)
    local originals, temp = cvarStore()
    if originals[name] ~= nil then
        C_CVar.SetCVar(name, tostring(originals[name]))
        originals[name] = nil
    end
    temp[name] = nil
end
-- Puts back every temporary change (logout, or a login after the game closed without one).
function Q.RestoreTemporaryCVars()
    local _, temp = cvarStore()
    for name in pairs(temp) do Q.RestoreCVar(name) end
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------
Q:On("ADDON_LOADED", function(_, name)
    if name == addonName then
        Q:InitDB()
    elseif Q.ready then
        -- An addon loaded late may own a feature now.
        C_Timer.After(0.5, function() Q:Recheck() end)
    end
end)

Q:On("PLAYER_LOGIN", function()
    if not Q.db then Q:InitDB() end
    Q.ready = true
    Q.RestoreTemporaryCVars() -- left over when the game closed during a boost
    for _, f in ipairs(Q.order) do Q:Apply(f) end
    if Q.ReportNewOverlaps then Q:ReportNewOverlaps() end
    local Encore = _G.EncoreEssentials
    if Encore and Encore.RegisterModule then Encore:RegisterModule("QoL", Q) end
end)

Q:On("PLAYER_LOGOUT", function() Q.RestoreTemporaryCVars() end)

function Q:Toggle()
    if self.ToggleWindow then self:ToggleWindow() end
end

SLASH_ENCOREQOL1 = "/eqol"
SLASH_ENCOREQOL2 = "/encoreqol"
SlashCmdList.ENCOREQOL = function(input)
    local cmd = strtrim(input or ""):lower()
    if cmd == "check" then
        Q:Recheck()
        Q:Print("Checked all features against your other addons again.")
    elseif cmd == "rolls" and Q.RollDebug then
        Q:RollDebug()
    elseif cmd == "preview" and Q.TogglePreview then
        Q:TogglePreview()
    elseif cmd == "selftest" and Q.SelfTest then
        Q.SelfTest.Show(Q.SelfTest.Run())
    elseif cmd == "bgpoi" and Q.BG and Q.BG.DumpPOIs then
        Q.BG:DumpPOIs()
    else
        Q:Toggle()
    end
end
