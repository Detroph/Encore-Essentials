-- Encore Essentials: settings sharing. /encore export shows one text with the settings of every Encore module
-- (core, Encore-DB window options, Encore-QoL and Encore-PvP features, Encore-Stonks options); /encore import takes
-- such a text and applies it after a /reload. Window positions, learned data, price history and wishlists are not
-- included. The text is read by a small parser, never run as code, so a text from someone else is safe to paste.
local _, ns = ...
local Encore = ns.Encore
local L = ns.L

local MAGIC = "ENC1"

---------------------------------------------------------------------------
-- Packing: T (table) ... E, S<len>:<bytes>, N<number>;, B1 / B0. Then base64, so chat and edit boxes keep it.
---------------------------------------------------------------------------
local function pack(v, out, depth)
    local t = type(v)
    if t == "table" then
        if depth > 12 then return end
        out[#out + 1] = "T"
        for k, x in pairs(v) do
            local kt, xt = type(k), type(x)
            if (kt == "string" or kt == "number") and (xt == "table" or xt == "string" or xt == "number" or xt == "boolean") then
                pack(k, out, depth + 1)
                pack(x, out, depth + 1)
            end
        end
        out[#out + 1] = "E"
    elseif t == "string" then
        out[#out + 1] = "S" .. #v .. ":" .. v
    elseif t == "number" then
        out[#out + 1] = "N" .. string.format("%.17g", v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "B1" or "B0"
    end
end

local function unpackAt(s, i, depth)
    if depth > 14 then error("too deep") end
    local c = s:sub(i, i)
    if c == "T" then
        local t = {}
        i = i + 1
        while s:sub(i, i) ~= "E" do
            if i > #s then error("cut off") end
            local k, x
            k, i = unpackAt(s, i, depth + 1)
            x, i = unpackAt(s, i, depth + 1)
            if type(k) == "table" then error("bad key") end
            t[k] = x
        end
        return t, i + 1
    elseif c == "S" then
        local len, at = s:match("^(%d+):()", i + 1)
        if not len then error("bad string") end
        len = tonumber(len)
        if at + len - 1 > #s then error("cut off") end
        return s:sub(at, at + len - 1), at + len
    elseif c == "N" then
        local num, at = s:match("^([%-%d%.eE%+infa]+);()", i + 1)
        local n = tonumber(num or "")
        if not n then error("bad number") end
        return n, at
    elseif c == "B" then
        return s:sub(i + 1, i + 1) == "1", i + 2
    end
    error("unknown piece")
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local chars = {}
        for j = 3, 0, -1 do
            local k = math.floor(n / 64 ^ j) % 64
            chars[#chars + 1] = B64:sub(k + 1, k + 1)
        end
        if not b then chars[3], chars[4] = "=", "=" elseif not c then chars[4] = "=" end
        out[#out + 1] = table.concat(chars)
    end
    return table.concat(out)
end

local function decode(text)
    text = text:gsub("[^%w%+/=]", "")
    local map = {}
    for i = 1, 64 do map[B64:sub(i, i)] = i - 1 end
    local out = {}
    for i = 1, #text, 4 do
        local q = text:sub(i, i + 3)
        local n, pad = 0, 0
        for j = 1, 4 do
            local ch = q:sub(j, j)
            if ch == "=" or ch == "" then pad = pad + 1; n = n * 64 else n = n * 64 + (map[ch] or 0) end
        end
        local a, b, c = math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
        out[#out + 1] = string.char(a)
        if pad < 2 then out[#out + 1] = string.char(b) end
        if pad < 1 then out[#out + 1] = string.char(c) end
    end
    return table.concat(out)
end

---------------------------------------------------------------------------
-- What is shared
---------------------------------------------------------------------------
local function copy(t, skip)
    if type(t) ~= "table" then return nil end
    local c = {}
    for k, v in pairs(t) do
        if not (skip and skip[k]) then c[k] = type(v) == "table" and copy(v) or v end
    end
    return c
end

-- Places, sizes and learned data stay with each player.
local SKIP_CORE = { dbWindow = true }
local SKIP_DBWINDOW = { displays = true, displaysBuild = true, size = true, point = true, inst = true, boss = true, tab = true }

local function collect()
    local s = {}
    local core = EncoreEssentialsDB and EncoreEssentialsDB.settings
    s.core = copy(core, SKIP_CORE)
    if s.core and s.core.minimap then s.core.minimap.point = nil end
    s.dbWindow = copy(core and core.dbWindow, SKIP_DBWINDOW)
    s.qol = EncoreQoLDB and copy(EncoreQoLDB.features)
    s.prof = EncoreQoLProfDB and copy(EncoreQoLProfDB.features)
    s.stonks = EncoreStonksDB and copy(EncoreStonksDB.settings)
    return s
end

function Encore:ExportSettings()
    local out = {}
    pack({ v = 1, from = Encore.version, settings = collect() }, out, 0)
    return MAGIC .. encode(table.concat(out))
end

-- Returns the settings table, or nil and why not.
function Encore:ReadSettingsText(text)
    text = strtrim(text or "")
    if text:sub(1, #MAGIC) ~= MAGIC then return nil, L.SHARE_BAD end
    local ok, t = pcall(function()
        local data = decode(text:sub(#MAGIC + 1))
        local v, i = unpackAt(data, 1, 0)
        if i <= #data then error("extra") end
        return v
    end)
    if not ok or type(t) ~= "table" or type(t.settings) ~= "table" then return nil, L.SHARE_BAD end
    return t.settings
end

local function merge(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            merge(target[k], v)
        else
            target[k] = v
        end
    end
end

function Encore:ImportSettings(text)
    local s, err = self:ReadSettingsText(text)
    if not s then return false, err end
    if type(s.core) == "table" then
        s.core.dbWindow = nil
        merge(EncoreEssentialsDB.settings, s.core) -- keeps your own minimap button position
    end
    if type(s.dbWindow) == "table" then
        if type(EncoreEssentialsDB.settings.dbWindow) ~= "table" then EncoreEssentialsDB.settings.dbWindow = {} end
        merge(EncoreEssentialsDB.settings.dbWindow, s.dbWindow)
    end
    if type(s.qol) == "table" and type(EncoreQoLDB) == "table" then EncoreQoLDB.features = copy(s.qol) end
    if type(s.prof) == "table" and type(EncoreQoLProfDB) == "table" then EncoreQoLProfDB.features = copy(s.prof) end
    if type(s.stonks) == "table" and type(EncoreStonksDB) == "table" then
        if type(EncoreStonksDB.settings) ~= "table" then EncoreStonksDB.settings = {} end
        merge(EncoreStonksDB.settings, s.stonks)
    end
    return true
end

---------------------------------------------------------------------------
-- Window: one text box; Export fills it, Import reads it
---------------------------------------------------------------------------
local win
local function window()
    if win then return win end
    local UI = Encore.UI
    win = UI.Window({ name = "EncoreEssentialsShare", title = L.SHARE_TITLE, width = 520, height = 320 })
    win.info = UI.Text(win.content, "GameFontHighlightSmall", "")
    win.info:SetPoint("TOPLEFT", 0, 0)
    win.info:SetPoint("RIGHT", 0, 0)
    win.info:SetWordWrap(true)
    local box = CreateFrame("Frame", nil, win.content)
    box:SetPoint("TOPLEFT", 0, -36)
    box:SetPoint("BOTTOMRIGHT", 0, 32)
    UI.Border(box, UI.COPPER, 0.35)
    win.scroll = UI.ScrollText(box, true)
    win.scroll:SetPoint("TOPLEFT", 6, -6)
    win.scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    win.apply = UI.Button(win.content, L.SHARE_APPLY, function()
        local ok, err = Encore:ImportSettings(win.scroll.box:GetText())
        if ok then
            win.info:SetText(L.SHARE_DONE)
            UI.Color(win.info, UI.GREEN)
            win.apply:Hide()
            win.reload:Show()
        else
            win.info:SetText(err)
            UI.Color(win.info, UI.RED)
        end
    end, 140)
    win.apply:SetPoint("BOTTOMLEFT", 0, 0)
    win.reload = UI.Button(win.content, L.SHARE_RELOAD, function() ReloadUI() end, 140)
    win.reload:SetPoint("BOTTOMLEFT", 0, 0)
    return win
end

function Encore:ShowExport()
    local w = window()
    w.title:SetText(L.SHARE_TITLE_EXPORT)
    w.info:SetText(L.SHARE_EXPORT_INFO)
    Encore.UI.Color(w.info, Encore.UI.INK)
    w.scroll:SetText(self:ExportSettings())
    w.apply:Hide()
    w.reload:Hide()
    w:Show()
    w.scroll.box:SetFocus()
    w.scroll.box:HighlightText()
end

function Encore:ShowImport()
    local w = window()
    w.title:SetText(L.SHARE_TITLE_IMPORT)
    w.info:SetText(L.SHARE_IMPORT_INFO)
    Encore.UI.Color(w.info, Encore.UI.INK)
    w.scroll:SetText("")
    w.apply:Show()
    w.reload:Hide()
    w:Show()
    w.scroll.box:SetFocus()
end
