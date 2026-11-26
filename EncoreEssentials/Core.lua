-- Encore Essentials: core module.
-- Owns saved data, the /encore slash command and loading of optional modules such as Encore-DB.
local addonName, ns = ...
local L = ns.L

local Encore = {}
ns.Encore = Encore
_G.EncoreEssentials = Encore -- public handle for Encore modules (EncoreEssentials_DB and later ones)

local tocVersion = C_AddOns.GetAddOnMetadata(addonName, "Version")
-- The packager replaces @project-version@ with the release tag; a copy straight from git shows "dev".
Encore.version = (tocVersion and not tocVersion:find("@", 1, true)) and tocVersion or "dev"
Encore.tocInterface = 16001
Encore.SCHEMA = 1

local CHAT_PREFIX = "|cffeb9339Encore|r: "
function Encore:Print(fmt, ...)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. (select("#", ...) > 0 and fmt:format(...) or fmt))
end

---------------------------------------------------------------------------
-- Saved data
-- Only plain values are stored (strings, numbers, booleans, tables of those).
-- WoW writes this table to disk on logout or /reload, not on a crash.
---------------------------------------------------------------------------
local DEFAULTS = {
    schema = Encore.SCHEMA,
    settings = {
        showLoginMessage = false,
        minimap = {
            hide = false,
            detached = false, -- false: on the minimap below the day/night indicator; true: free on screen
            locked = false,   -- detached only: can't be dragged
            square = false,   -- detached only: larger rounded-square button
            size = 40,        -- square button size in UI units (24 to 72)
            -- point = { "CENTER", "BOTTOMLEFT", x, y }, saved when a detached button is dropped
        },
    },
    stats = {
        logins = 0,
    },
}

local function fillDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            fillDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function migrate(db)
    db.schema = db.schema or 1
    -- Future schema upgrades go here, one step per version:
    -- if db.schema < 2 then ... db.schema = 2 end
end

function Encore:InitDB()
    if type(EncoreEssentialsDB) ~= "table" then EncoreEssentialsDB = {} end
    migrate(EncoreEssentialsDB)
    fillDefaults(EncoreEssentialsDB, DEFAULTS)
    self.db = EncoreEssentialsDB
end

-- Settings only. What Encore has learned is kept: quest rewards seen at quest givers (questRewards), login count
-- and Encore-DB's boss portrait cache.
function Encore:ResetDB()
    local db = EncoreEssentialsDB
    if type(db) ~= "table" then db = {} end
    local old = type(db.settings) == "table" and db.settings or {}
    local dbWindow = type(old.dbWindow) == "table" and old.dbWindow or nil
    db.settings = {}
    if dbWindow and type(dbWindow.displays) == "table" then
        db.settings.dbWindow = { displays = dbWindow.displays, displaysBuild = dbWindow.displaysBuild }
    end
    EncoreEssentialsDB = db
    self:InitDB()
    if self.RefreshMinimapButton then self:RefreshMinimapButton() end
end

-- Forgets the quest rewards Encore noted at quest givers and in the quest log (Encore-DB falls back to its data).
function Encore:ForgetQuestRewards()
    if type(EncoreEssentialsDB) == "table" then EncoreEssentialsDB.questRewards = {} end
    if self.QuestRewards then self.QuestRewards.version = self.QuestRewards.version + 1 end
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------
Encore.modules = {}

-- Called by each module file when it loads.
function Encore:RegisterModule(name, module)
    self.modules[name] = module
    return module
end

-- Loads a load-on-demand module folder if needed, then returns its module table.
function Encore:LoadModule(name, folder, missingMessage)
    if self.modules[name] then return self.modules[name] end
    if not C_AddOns.DoesAddOnExist(folder) then
        self:Print(missingMessage or L.DB_MISSING)
        return nil
    end
    local loaded, reason = C_AddOns.LoadAddOn(folder)
    if not loaded then
        self:Print(L.MODULE_FAILED, folder, _G["ADDON_" .. tostring(reason)] or tostring(reason))
        return nil
    end
    return self.modules[name]
end

-- Opens or closes Encore-DB, loading it first if needed.
function Encore:ToggleDB()
    local db = self:LoadModule("DB", "EncoreEssentials_DB")
    if db then db:Toggle() end
end

-- Opens or closes Encore-Stonks (auction price graphs). It loads with the game so it can record every scan.
function Encore:ToggleStonks()
    local stonks = self:LoadModule("Stonks", "EncoreEssentials_Stonks", L.STONKS_MISSING)
    if stonks then stonks:Toggle() end
end

-- Opens or closes the Encore-QoL window. It loads with the game, since its features run from login.
function Encore:ToggleQoL()
    local qol = self.modules.QoL or _G.EncoreQoL
    if not qol then
        self:Print(L.QOL_MISSING)
        return
    end
    qol:Toggle()
end

function Encore:ShowInfo()
    local build, buildNumber, _, interface = GetBuildInfo()
    self:Print(L.INFO_ADDON, self.version, self.db.schema)
    self:Print(L.INFO_GAME, build .. "." .. buildNumber, interface, self.tocInterface)
    if interface ~= self.tocInterface then self:Print(L.INFO_MISMATCH) end
    self:Print(L.INFO_LOGINS, self.db.stats.logins)
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
local function showHelp()
    Encore:Print(L.HELP_HEADER)
    DEFAULT_CHAT_FRAME:AddMessage(L.HELP_DB)
    DEFAULT_CHAT_FRAME:AddMessage(L.HELP_STONKS)
    DEFAULT_CHAT_FRAME:AddMessage(L.HELP_QOL)
    DEFAULT_CHAT_FRAME:AddMessage(L.HELP_MINIMAP)
    DEFAULT_CHAT_FRAME:AddMessage(L.HELP_OPTIONS)
    DEFAULT_CHAT_FRAME:AddMessage(L.HELP_INFO)
    DEFAULT_CHAT_FRAME:AddMessage(L.HELP_RESET)
    DEFAULT_CHAT_FRAME:AddMessage(L.HELP_FORGET_QUESTS)
    DEFAULT_CHAT_FRAME:AddMessage(L.HELP_WHATSNEW)
    DEFAULT_CHAT_FRAME:AddMessage(L.HELP_MODULES)
end

local COMMANDS = {
    [""] = showHelp,
    help = showHelp,
    info = function() Encore:ShowInfo() end,
    reset = function()
        Encore:ResetDB()
        Encore:Print(L.RESET_DONE)
    end,
    forgetquests = function()
        Encore:ForgetQuestRewards()
        Encore:Print(L.FORGET_QUESTS_DONE)
    end,
    whatsnew = function() Encore:ShowWhatsNew() end,
    db = function() Encore:ToggleDB() end,
    stonks = function() Encore:ToggleStonks() end,
    qol = function() Encore:ToggleQoL() end,
    options = function() Encore:OpenOptions() end,
    config = function() Encore:OpenOptions() end,
    minimap = function()
        local show = Encore.db.settings.minimap.hide
        Encore:SetMinimapButtonShown(show)
        Encore:Print(show and L.MINIMAP_SHOWN or L.MINIMAP_HIDDEN)
    end,
}

SLASH_ENCOREESSENTIALS1 = "/encore"
SlashCmdList.ENCOREESSENTIALS = function(input)
    local cmd = strtrim(input or ""):lower():match("^(%S*)")
    local handler = COMMANDS[cmd]
    if handler then handler() else Encore:Print(L.UNKNOWN, cmd) end
end

---------------------------------------------------------------------------
-- Events (handler is set before any registration)
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        Encore:InitDB()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        Encore.db.stats.logins = Encore.db.stats.logins + 1
        Encore:RefreshMinimapButton()
        if Encore.db.settings.showLoginMessage then
            Encore:Print(L.LOADED, "Encore Essentials " .. Encore.version, "/encore")
        end
        C_Timer.After(4, function() Encore:CheckWhatsNew() end)
        local dbw = Encore.db.settings.dbWindow
        if type(dbw) == "table" and dbw.loadAtLogin and C_AddOns.DoesAddOnExist("EncoreEssentials_DB") then
            C_Timer.After(2, function() C_AddOns.LoadAddOn("EncoreEssentials_DB") end)
        end
    end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
