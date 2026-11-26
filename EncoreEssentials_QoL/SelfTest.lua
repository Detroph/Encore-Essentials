-- Encore-QoL: self-test. In beta, alpha and git ("dev") copies it runs by itself a few seconds after login and
-- opens a window when something is wrong; /eqol selftest runs it in any version. It only reads: it never turns a
-- feature on or off, changes a game option or sells anything.
--
-- What it checks: Lua errors and blocked actions from any Encore addon since the game loaded (and later in the
-- session), that every installed Encore addon loaded and all are the same version, that every feature is
-- registered correctly and none failed to start, that every option's text and choices can be worked out, that
-- the Encore-QoL window and every feature's settings can be built, and that saved data looks right.
local _, ns = ...
local Q = ns.QoL
local T = { errors = {}, order = {} }
Q.SelfTest = T

local ADDONS = { "EncoreEssentials", "EncoreEssentials_QoL", "EncoreEssentials_Stonks", "EncoreEssentials_DB" }
local OPTION_KINDS = { check = true, slider = true, choice = true, color = true, edit = true, button = true,
    note = true, group = true }
local NEEDS_KEY = { check = true, slider = true, choice = true, color = true, edit = true }

function T.IsTestBuild()
    local v = tostring(Q.version or ""):lower()
    return v == "dev" or v:find("beta", 1, true) ~= nil or v:find("alpha", 1, true) ~= nil
end

---------------------------------------------------------------------------
-- Catching errors. The game's error handler is wrapped (and BugGrabber listened to, when it holds the handler),
-- so errors are seen even when the game is set to hide Lua errors.
---------------------------------------------------------------------------
local function isOurs(text) return type(text) == "string" and text:find("EncoreEssentials", 1, true) ~= nil end

local function record(kind, msg, stack)
    msg = tostring(msg or "?")
    -- An error naming another addon's file is that addon's, even when Encore code is further up the stack.
    local owner = msg:match("AddOns[\\/]([^\\/]+)[\\/]")
    if owner and not isOurs(owner) then return end
    if not (isOurs(msg) or isOurs(stack)) then return end
    local key = kind .. "\n" .. msg
    local e = T.errors[key]
    if e then
        e.count = e.count + 1
        return
    end
    e = { kind = kind, msg = msg, stack = stack, count = 1, at = GetTime() }
    T.errors[key] = e
    T.order[#T.order + 1] = e
    if T.OnNewError then T.OnNewError(e) end
end

local function trimStack(stack)
    if type(stack) ~= "string" then return nil end
    local keep = {}
    for line in stack:gmatch("[^\n]+") do
        if isOurs(line) and #keep < 4 then keep[#keep + 1] = "    " .. line end
    end
    return #keep > 0 and table.concat(keep, "\n") or nil
end

local wrapped = {}
local function wrapHandler()
    local current = geterrorhandler()
    if wrapped[current] then return end
    local handler = function(msg, ...)
        pcall(record, "Lua error", msg, trimStack(debugstack and debugstack(2) or nil))
        return current(msg, ...)
    end
    wrapped[handler] = true
    seterrorhandler(handler)
end
wrapHandler()

local bugGrabberHooked = false
local function hookBugGrabber()
    local bg = _G.BugGrabber
    if bugGrabberHooked or type(bg) ~= "table" or type(bg.RegisterCallback) ~= "function" then return end
    if wrapped[geterrorhandler()] then return end -- our handler already sees every error
    bugGrabberHooked = true
    bg.RegisterCallback(T, "BugGrabber_BugGrabbed", function(_, err)
        if type(err) == "table" then record("Lua error", err.message, trimStack(err.stack)) end
    end)
end

Q:On("ADDON_ACTION_BLOCKED", function(event, addon, func)
    if isOurs(addon) then record("Blocked action", tostring(addon) .. " tried to call " .. tostring(func)) end
end)
Q:On("ADDON_ACTION_FORBIDDEN", function(event, addon, func)
    if isOurs(addon) then record("Forbidden action", tostring(addon) .. " tried to call " .. tostring(func)) end
end)
Q:On("LUA_WARNING", function(event, _, text)
    if isOurs(text) then record("Lua warning", text) end
end)

---------------------------------------------------------------------------
-- Checks. Each returns a list of problems (strings) and one line saying what passed.
---------------------------------------------------------------------------
local function checkAddons()
    local problems, loaded, versions = {}, {}, {}
    for _, name in ipairs(ADDONS) do
        local _, _, _, loadable, reason = C_AddOns.GetAddOnInfo(name)
        local present = reason ~= "MISSING" and (C_AddOns.DoesAddOnExist == nil or C_AddOns.DoesAddOnExist(name))
        if C_AddOns.IsAddOnLoaded(name) then
            loaded[#loaded + 1] = name
            local v = C_AddOns.GetAddOnMetadata(name, "Version")
            if v and not v:find("@", 1, true) then versions[v] = (versions[v] and versions[v] .. ", " or "") .. name end
        elseif present and not C_AddOns.IsAddOnLoadOnDemand(name) then
            local enabled = true
            local ok, state = pcall(C_AddOns.GetAddOnEnableState, name, UnitName("player"))
            if ok and state == 0 then enabled = false end
            if enabled then
                problems[#problems + 1] = ("%s is installed and turned on but didn't load (%s)."):format(name,
                    tostring(reason or (loadable and "no reason given" or "not loadable")))
            end
        end
    end
    local count = 0
    for _ in pairs(versions) do count = count + 1 end
    if count > 1 then
        local parts = {}
        for v, names in pairs(versions) do parts[#parts + 1] = v .. " (" .. names .. ")" end
        table.sort(parts)
        problems[#problems + 1] = "Encore addons are on different versions: " .. table.concat(parts, "; ")
            .. ". An old folder is probably left in Interface\\AddOns."
    end
    return problems, "Addons loaded: " .. table.concat(loaded, ", ")
end

local function checkFeatures()
    local problems, ids, tabs = {}, {}, {}
    for _, t in ipairs(Q.TABS) do tabs[t.id] = true end
    local options = 0
    for _, f in ipairs(Q.order) do
        local id = tostring(f.id)
        if ids[id] then problems[#problems + 1] = "Feature id " .. id .. " is registered twice." end
        ids[id] = true
        if not tabs[f.tab] then problems[#problems + 1] = id .. ": unknown tab " .. tostring(f.tab) .. "." end
        if f.Enable ~= nil and type(f.Enable) ~= "function" then problems[#problems + 1] = id .. ": Enable is not a function." end
        if f.status == "error" then
            problems[#problems + 1] = id .. " (" .. tostring(f.name) .. ") failed to start: " .. tostring(f.error)
        end
        for i, o in ipairs(f.options or {}) do
            options = options + 1
            local where = ("%s option %d (%s)"):format(id, i, tostring(o.name or o.key or (type(o.text) == "string" and o.text) or o.kind))
            if not OPTION_KINDS[o.kind] then
                problems[#problems + 1] = where .. ": unknown kind " .. tostring(o.kind) .. "."
            elseif NEEDS_KEY[o.kind] and type(o.key) ~= "string" then
                problems[#problems + 1] = where .. ": has no key."
            elseif o.kind == "slider" and not (tonumber(o.min) and tonumber(o.max) and o.min < o.max) then
                problems[#problems + 1] = where .. ": slider needs min below max."
            elseif o.kind == "button" and type(o.onClick) ~= "function" then
                problems[#problems + 1] = where .. ": button has no onClick."
            end
            for _, field in ipairs({ "when", "text", "choices" }) do
                if type(o[field]) == "function" then
                    local ok, err = pcall(o[field], f)
                    if not ok then problems[#problems + 1] = where .. ": " .. field .. "() failed: " .. tostring(err) end
                end
            end
        end
    end
    return problems, ("Features: %d registered, %d options checked"):format(#Q.order, options)
end

local function checkWindow()
    if not Q.SelfTestWindow then return { "The Encore-QoL window file didn't load." }, nil end
    local problems = {}
    local errors, built = Q:SelfTestWindow()
    for id, err in pairs(errors) do problems[#problems + 1] = "Settings for " .. tostring(id) .. " can't be built: " .. tostring(err) end
    table.sort(problems)
    return problems, ("Window: built, %d feature settings blocks"):format(built or 0)
end

local function checkSaved()
    local problems = {}
    local db = Q.db
    if type(db) ~= "table" then return { "EncoreQoLDB is missing." }, nil end
    for _, root in ipairs({ { "EncoreQoLDB", db }, { "EncoreQoLProfDB", Q.profDB } }) do
        local t = root[2]
        if type(t) ~= "table" or type(t.features) ~= "table" then
            problems[#problems + 1] = root[1] .. ".features is missing."
        else
            for id, v in pairs(t.features) do
                if type(v) ~= "table" then problems[#problems + 1] = root[1] .. ".features." .. tostring(id) .. " is not a table." end
            end
        end
    end
    if type(db.cvarTemp) == "table" and next(db.cvarTemp) and not (Q.features.fishing and Q.features.fishing.active) then
        local names = {}
        for name in pairs(db.cvarTemp) do names[#names + 1] = name end
        problems[#problems + 1] = "Game options changed for a moment were not put back: " .. table.concat(names, ", ")
    end
    return problems, "Saved data: looks right"
end

local function checkErrors()
    local problems = {}
    for _, e in ipairs(T.order) do
        local line = ("[%s%s] %s"):format(e.kind, e.count > 1 and (" x" .. e.count) or "", e.msg)
        if e.stack then line = line .. "\n" .. e.stack end
        problems[#problems + 1] = line
    end
    return problems, "No Lua errors or blocked actions from Encore addons"
end

local CHECKS = {
    { "Errors", checkErrors },
    { "Addons", checkAddons },
    { "Features", checkFeatures },
    { "Window", checkWindow },
    { "Saved data", checkSaved },
}

function T.Run()
    hookBugGrabber()
    wrapHandler()
    local problems, passed = {}, {}
    for _, c in ipairs(CHECKS) do
        local ok, list, okLine = pcall(c[2])
        if not ok then
            problems[#problems + 1] = c[1] .. " check itself failed: " .. tostring(list)
        else
            for _, p in ipairs(list) do problems[#problems + 1] = p end
            if #list == 0 and okLine then passed[#passed + 1] = okLine end
        end
    end
    T.last = { problems = problems, passed = passed, total = #CHECKS }
    return T.last
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function reportText(r)
    local lines = {
        ("Encore-QoL self-test, version %s, %s"):format(tostring(Q.version), date("%Y-%m-%d %H:%M")),
        #r.problems == 0 and "Everything passed." or ("%d problem(s) found."):format(#r.problems),
        "",
    }
    if #r.problems > 0 then
        lines[#lines + 1] = "PROBLEMS"
        for _, p in ipairs(r.problems) do lines[#lines + 1] = "- " .. p end
        lines[#lines + 1] = ""
    end
    if #r.passed > 0 then
        lines[#lines + 1] = "PASSED"
        for _, p in ipairs(r.passed) do lines[#lines + 1] = "- " .. p end
    end
    return table.concat(lines, "\n")
end

local win
local function window()
    if win then return win end
    local UI = _G.EncoreEssentials.UI
    win = UI.Window({ name = "EncoreQoLSelfTest", title = "Encore-QoL self-test", width = 600, height = 400 })
    win.summary = UI.Text(win.content, "GameFontNormal", "")
    win.summary:SetPoint("TOPLEFT", 0, 0)
    win.summary:SetPoint("RIGHT", 0, 0)
    local box = CreateFrame("Frame", nil, win.content)
    box:SetPoint("TOPLEFT", 0, -22)
    box:SetPoint("BOTTOMRIGHT", 0, 32)
    UI.Border(box, UI.COPPER, 0.35)
    win.scroll = UI.ScrollText(box)
    win.scroll:SetPoint("TOPLEFT", 6, -6)
    win.scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local again = UI.Button(win.content, "Run again", function() T.Show(T.Run()) end, 110)
    again:SetPoint("BOTTOMLEFT", 0, 0)
    local copy = UI.Button(win.content, "Select all", function()
        win.scroll.box:SetFocus()
        win.scroll.box:HighlightText()
    end, 110)
    copy:SetPoint("LEFT", again, "RIGHT", 8, 0)
    local hint = UI.Text(win.content, "GameFontDisableSmall", "Ctrl+C copies the selected text.")
    hint:SetPoint("LEFT", copy, "RIGHT", 10, 0)
    return win
end

function T.Show(r)
    r = r or T.last or T.Run()
    local w = window()
    local UI = _G.EncoreEssentials.UI
    if #r.problems == 0 then
        w.summary:SetText(("All %d checks passed."):format(r.total))
        UI.Color(w.summary, UI.GREEN)
    else
        w.summary:SetText(("%d problem(s) found. Copy the text below to report them."):format(#r.problems))
        UI.Color(w.summary, UI.RED)
    end
    w.scroll:SetText(reportText(r))
    w:Show()
end

-- Errors that come after the test: show them too, out of combat, at most every 30 seconds.
local lastPopup = 0
local function popup()
    if not T.auto then return end
    if InCombatLockdown() then T.pending = true return end
    if GetTime() - lastPopup < 30 then
        if not T.pending then T.pending = true; C_Timer.After(30, function() T.pending = false; popup() end) end
        return
    end
    lastPopup = GetTime()
    T.Show(T.Run())
end
Q:On("PLAYER_REGEN_ENABLED", function()
    if T.pending then T.pending = false; popup() end
end)

Q:On("PLAYER_LOGIN", function()
    if not T.IsTestBuild() then return end
    T.auto = true
    C_Timer.After(6, function()
        local r = T.Run()
        if #r.problems > 0 then
            lastPopup = GetTime()
            T.Show(r)
        else
            Q:Print("Self-test (%s): all %d checks passed. /eqol selftest shows the details.", tostring(Q.version), r.total)
        end
        T.OnNewError = function() C_Timer.After(1, popup) end
    end)
end)
