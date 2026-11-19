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
        showLoginMessage = true,
        minimap = {
            hide = false, -- the button sits below the day/night indicator, so no position is saved
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

function Encore:ResetDB()
    EncoreEssentialsDB = {}
    self:InitDB()
    if self.RefreshMinimapButton then self:RefreshMinimapButton() end
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
    DEFAULT_CHAT_FRAME:AddMessage(L.HELP_MINIMAP)
    DEFAULT_CHAT_FRAME:AddMessage(L.HELP_INFO)
    DEFAULT_CHAT_FRAME:AddMessage(L.HELP_RESET)
end

local COMMANDS = {
    [""] = showHelp,
    help = showHelp,
    info = function() Encore:ShowInfo() end,
    reset = function()
        Encore:ResetDB()
        Encore:Print(L.RESET_DONE)
    end,
    db = function() Encore:ToggleDB() end,
    stonks = function() Encore:ToggleStonks() end,
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
    end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
