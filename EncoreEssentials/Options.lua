-- Encore Essentials: the game's Options > AddOns tab.
-- One "Encore Essentials" category for the hub and minimap button, with a subcategory per module.
-- Encore-DB loads on demand, so its page is built here and edits its saved settings directly; when the DB window
-- is already loaded it is told to redraw. Encore-Stonks loads with the game and adds its own page (Stonks
-- Options.lua) through Encore:AddOptionsPage.
--
-- Uses the game's Settings API (vertical layout, proxy settings). Every setting reads and writes the same saved
-- values as the right-click menus, so both stay in step. If the client has no Settings API, nothing is added.
local _, ns = ...
local L = ns.L
local Encore = ns.Encore

local S = _G.Settings
local available = type(S) == "table" and S.RegisterVerticalLayoutCategory and S.RegisterProxySetting
    and S.RegisterAddOnCategory and S.CreateCheckbox

local VAR = (S and S.VarType) or { Boolean = "boolean", Number = "number", String = "string" }

local root -- the "Encore Essentials" category

-- Options built from a short description list, so modules don't each repeat the Settings boilerplate.
--   { kind = "header", text = ... }
--   { kind = "checkbox", key = ..., name = ..., tooltip = ..., get = fn, set = fn(value), default = bool,
--     parent = key of a checkbox this one depends on (greyed out while that one is off) }
--   { kind = "dropdown", key = ..., name = ..., tooltip = ..., get = fn, set = fn(value), default = v,
--     options = { { value, label }, ... }, varType = "number" | "string" }
--   { kind = "button", name = ..., text = ..., tooltip = ..., onClick = fn }
local function build(category, layout, list)
    local byKey = {}
    for _, o in ipairs(list) do
        if o.kind == "header" then
            if CreateSettingsListSectionHeaderInitializer then
                layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(o.text))
            end
        elseif o.kind == "checkbox" then
            local setting = S.RegisterProxySetting(category, "EncoreEssentials_" .. o.key, VAR.Boolean, o.name,
                o.default == true, function() return o.get() == true end, function(v) o.set(v == true) end)
            local init = S.CreateCheckbox(category, setting, o.tooltip)
            byKey[o.key] = { init = init, get = o.get }
            local parent = o.parent and byKey[o.parent]
            if parent and init and init.SetParentInitializer then
                init:SetParentInitializer(parent.init, function() return parent.get() == true end)
            end
        elseif o.kind == "dropdown" and S.CreateDropdown then
            local setting = S.RegisterProxySetting(category, "EncoreEssentials_" .. o.key,
                o.varType == "string" and VAR.String or VAR.Number, o.name, o.default, o.get, o.set)
            local function options()
                local container = S.CreateControlTextContainer()
                for _, choice in ipairs(o.options) do container:Add(choice[1], choice[2]) end
                return container:GetData()
            end
            S.CreateDropdown(category, setting, options, o.tooltip)
        elseif o.kind == "button" and CreateSettingsButtonInitializer then
            layout:AddInitializer(CreateSettingsButtonInitializer(o.name or "", o.text, o.onClick, o.tooltip, true))
        end
    end
end

-- Adds a module page under "Encore Essentials". Returns the subcategory, or nil without a Settings API.
function Encore:AddOptionsPage(name, list)
    if not root then return nil end
    local ok, result = pcall(function()
        local category, layout = S.RegisterVerticalLayoutSubcategory(root, name)
        build(category, layout, list)
        S.RegisterAddOnCategory(category)
        return category
    end)
    if not ok then
        geterrorhandler()(result)
        return nil
    end
    return result
end

-- Opens Options > AddOns > Encore Essentials (or a module page from AddOptionsPage).
function Encore:OpenOptions(category)
    category = category or root
    if not category then
        self:Print(L.OPTIONS_MISSING)
        return
    end
    if S.OpenToCategory then S.OpenToCategory(category:GetID()) end
end

---------------------------------------------------------------------------
-- Encore Essentials (hub and minimap button)
---------------------------------------------------------------------------
local function minimap() return Encore.db.settings.minimap end

local MAIN = {
    { kind = "header", text = L.OPT_GENERAL },
    { kind = "checkbox", key = "LoginMessage", name = L.MENU_LOGIN_MESSAGE, tooltip = L.OPT_LOGIN_MESSAGE_TIP, default = true,
        get = function() return Encore.db.settings.showLoginMessage end,
        set = function(v) Encore.db.settings.showLoginMessage = v end },
    { kind = "button", text = L.MENU_HUB, tooltip = L.OPT_HUB_TIP, onClick = function()
        HideUIPanel(SettingsPanel)
        Encore:ToggleHub()
    end },
    { kind = "header", text = L.OPT_MINIMAP },
    { kind = "checkbox", key = "MinimapShown", name = L.OPT_MINIMAP_SHOWN, tooltip = L.OPT_MINIMAP_SHOWN_TIP, default = true,
        get = function() return not minimap().hide end,
        set = function(v) Encore:SetMinimapButtonShown(v) end },
    { kind = "checkbox", key = "MinimapDetached", name = L.OPT_MINIMAP_DETACHED, tooltip = L.OPT_MINIMAP_DETACHED_TIP, default = false,
        parent = "MinimapShown",
        get = function() return minimap().detached end,
        set = function(v)
            if v == (minimap().detached == true) then return end
            if v then Encore:DetachMinimapButton(false) else Encore:ReattachMinimapButton() end
        end },
    { kind = "checkbox", key = "MinimapLocked", name = L.MENU_LOCK_BUTTON, tooltip = L.OPT_MINIMAP_LOCKED_TIP, default = false,
        parent = "MinimapDetached",
        get = function() return minimap().locked end,
        set = function(v) Encore:SetMinimapButtonLocked(v) end },
    { kind = "checkbox", key = "MinimapSquare", name = L.MENU_SQUARE_BUTTON, tooltip = L.OPT_MINIMAP_SQUARE_TIP, default = false,
        parent = "MinimapDetached",
        get = function() return minimap().square end,
        set = function(v) Encore:SetMinimapButtonSquare(v) end },
}

---------------------------------------------------------------------------
-- Encore-DB (load on demand: saved in EncoreEssentialsDB.settings.dbWindow, read by Window.lua when it opens)
---------------------------------------------------------------------------
local function dbSettings()
    local s = Encore.db.settings
    if type(s.dbWindow) ~= "table" then s.dbWindow = {} end
    return s.dbWindow
end

-- Tells a loaded DB window about a change; Window.lua defines DB:ApplyOption.
local function dbChanged(key)
    local db = Encore.modules.DB
    if db and db.ApplyOption then db:ApplyOption(key) end
end

local DB_PAGE = {
    { kind = "header", text = L.OPT_DB_DISPLAY },
    { kind = "dropdown", key = "DBIconSize", name = L.OPT_DB_ICONS, tooltip = L.OPT_DB_ICONS_TIP, default = "normal", varType = "string",
        options = { { "small", L.OPT_SMALL }, { "normal", L.OPT_NORMAL }, { "large", L.OPT_LARGE } },
        get = function()
            local v = dbSettings().iconSize
            return (v == "small" or v == "large") and v or "normal"
        end,
        set = function(v) dbSettings().iconSize = v; dbChanged("iconSize") end },
    { kind = "dropdown", key = "DBHighlight", name = L.OPT_DB_HIGHLIGHT, tooltip = L.OPT_DB_HIGHLIGHT_TIP, default = 1,
        options = { { 1, L.OPT_DB_HIGHLIGHT_1 }, { 2, L.OPT_DB_HIGHLIGHT_2 }, { 3, L.OPT_DB_HIGHLIGHT_3 } },
        get = function()
            local h = tonumber(dbSettings().highlight)
            return (h and h >= 1 and h <= 3) and h or 1
        end,
        set = function(v) dbSettings().highlight = v; dbChanged("highlight") end },
    { kind = "checkbox", key = "DBRandomOpen", name = L.OPT_DB_RANDOM, tooltip = L.OPT_DB_RANDOM_TIP, default = false,
        get = function() return dbSettings().randomOpen == true end,
        set = function(v) dbSettings().randomOpen = v or nil; dbChanged("randomOpen") end },
    { kind = "checkbox", key = "DBPrices", name = L.OPT_DB_PRICES, tooltip = L.OPT_DB_PRICES_TIP, default = true,
        get = function() return dbSettings().ahPrices ~= false end,
        set = function(v)
            if v then dbSettings().ahPrices = nil else dbSettings().ahPrices = false end
            dbChanged("ahPrices")
        end },
    { kind = "header", text = L.OPT_DB_TOOLTIPS },
    { kind = "checkbox", key = "DBTooltipSources", name = L.OPT_DB_SOURCES, tooltip = L.OPT_DB_SOURCES_TIP, default = true,
        get = function() return dbSettings().tooltipSources ~= false end,
        set = function(v) if v then dbSettings().tooltipSources = nil else dbSettings().tooltipSources = false end end },
    { kind = "checkbox", key = "DBLoadAtLogin", name = L.OPT_DB_LOGIN, tooltip = L.OPT_DB_LOGIN_TIP, default = false,
        get = function() return dbSettings().loadAtLogin == true end,
        set = function(v)
            dbSettings().loadAtLogin = v or nil
            if v then Encore:LoadModule("DB", "EncoreEssentials_DB") end
        end },
    { kind = "header", text = L.OPT_DB_DUNGEONS },
    { kind = "checkbox", key = "DBSplitBRS", name = L.OPT_DB_BRS, tooltip = L.OPT_DB_BRS_TIP, default = false,
        get = function() return dbSettings().splitBRS == true end,
        set = function(v) dbSettings().splitBRS = v or nil; dbChanged("splitBRS") end },
    { kind = "header", text = L.OPT_WINDOW },
    { kind = "button", text = L.OPT_OPEN_DB, onClick = function()
        HideUIPanel(SettingsPanel)
        Encore:ToggleDB()
    end },
    { kind = "button", text = L.OPT_RESET_WINDOW, tooltip = L.OPT_RESET_WINDOW_TIP, onClick = function()
        local s = dbSettings()
        s.size, s.point = nil, nil
        dbChanged("resetWindow")
    end },
}

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
if available then
    local ok, err = pcall(function()
        local category, layout = S.RegisterVerticalLayoutCategory("Encore Essentials")
        build(category, layout, MAIN)
        S.RegisterAddOnCategory(category)
        root = category
        Encore.optionsCategory = category
    end)
    if not ok then
        root = nil
        geterrorhandler()(err)
    elseif C_AddOns.DoesAddOnExist("EncoreEssentials_DB") then
        Encore:AddOptionsPage("Encore-DB", DB_PAGE)
    end
end
