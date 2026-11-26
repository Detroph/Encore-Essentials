-- Encore Essentials: "What's new" window, shown once on the first login after an update.
-- Keep each version to a few short lines a player can read in ten seconds; CHANGELOG.md has the details.
local _, ns = ...
local Encore = ns.Encore
local L = ns.L

-- Newest first. A version here is the tag without the leading v ("0.2.6.1-beta" is written "0.2.6.1").
-- A full release (three numbers) sums up its betas: players updating to it see only that entry.
local NOTES = {
    { version = "0.2.6.1", lines = {
        "New modules: Encore-PvP (battleground timers and history) and Encore-Alts (your characters at a glance).",
        "New module Encore-Professions: a levelling guide beside the profession window (the Encore button by the skill bar).",
        "Wishlist: Alt-click an item in Encore-DB; Encore tells you when it drops, is rolled for or is at the AH.",
        "Encore-DB: AH price and crafting profit columns; tooltips can show where items drop (option).",
        "Encore-QoL: open all mail, restock at vendors, ready check buffs.",
        "Encore-Stonks: a Stonks tab in the auction house lists items under vendor price or under the market average.",
        "Share your settings with /encore export and /encore import. Key bindings for every window.",
        "/encore setup: choose which Encore modules load.",
        "Beta versions test themselves at login and show any error in a window (/eqol selftest).",
    } },
}
Encore.WHATS_NEW = NOTES

local FIRST_VERSION = "0.2.5" -- the last version before this window existed; players coming from it see what's new

-- "0.2.6.1-beta" -> { 0, 2, 6, 1 }; a full "0.2.6" -> { 0, 2, 6, huge } so it sorts after its betas.
local function parse(v)
    local t = {}
    for n in tostring(v or ""):gsub("^v", ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
    if #t == 3 then t[4] = math.huge end
    for i = #t + 1, 4 do t[i] = 0 end
    return t
end

local function compare(a, b)
    local x, y = parse(a), parse(b)
    for i = 1, 4 do
        if x[i] ~= y[i] then return x[i] < y[i] and -1 or 1 end
    end
    return 0
end

local function isFull(v) return parse(v)[4] == math.huge end

-- Entries newer than `seen`, up to `current`. Updating to a full release shows only full-release entries.
local function entriesBetween(seen, current)
    local list = {}
    for _, e in ipairs(NOTES) do
        if compare(e.version, current) <= 0 and (not seen or compare(e.version, seen) > 0)
            and (not isFull(current) or isFull(e.version)) then
            list[#list + 1] = e
            if #list == 3 then break end
        end
    end
    return list
end

local window
local function build()
    local UI = Encore.UI
    window = UI.Window({ name = "EncoreEssentialsWhatsNew", width = 420, height = 200 })
    window.lines = {}
    window.ok = UI.Button(window, L.WHATSNEW_OK, function() window:Hide() end, 100)
    window.ok:SetPoint("BOTTOMRIGHT", -14, 12)
    window.hint = UI.Text(window, "GameFontDisableSmall", L.WHATSNEW_AGAIN)
    window.hint:SetPoint("BOTTOMLEFT", 14, 17)
end

local function line(i)
    local fs = window.lines[i]
    if not fs then
        fs = Encore.UI.Text(window.content, "GameFontHighlight")
        fs:SetWidth(392)
        fs:SetSpacing(2)
        window.lines[i] = fs
    end
    fs:Show()
    return fs
end

function Encore:ShowWhatsNew(entries)
    entries = entries or entriesBetween(nil, self.version == "dev" and NOTES[1] and NOTES[1].version or self.version)
    if not window then build() end
    for _, fs in ipairs(window.lines) do fs:Hide() end
    window.title:SetText(L.WHATSNEW_TITLE:format(self.version))
    local UI, n, y = Encore.UI, 0, 0
    if #entries == 0 then
        n = n + 1
        local fs = line(n)
        fs:SetText(L.WHATSNEW_NONE)
        UI.Color(fs, UI.DIM)
        fs:SetPoint("TOPLEFT", 0, 0)
        y = fs:GetStringHeight()
    end
    for _, e in ipairs(entries) do
        if #entries > 1 then
            n = n + 1
            local head = line(n)
            head:SetText(e.version)
            UI.Color(head, UI.COPPER)
            head:SetPoint("TOPLEFT", 0, -y)
            y = y + head:GetStringHeight() + 4
        end
        for _, text in ipairs(e.lines) do
            n = n + 1
            local fs = line(n)
            fs:SetText("|cffeb9339•|r " .. text)
            UI.Color(fs, UI.INK)
            fs:SetPoint("TOPLEFT", 0, -y)
            y = y + fs:GetStringHeight() + 6
        end
        y = y + 6
    end
    window:SetHeight(math.min(560, y + 44 + 46))
    window:Show()
end

-- First login after an update: show what changed since the version seen last, once.
-- The setup window (Setup.lua) takes this window's place twice: on a new install, and once on the first full
-- release from SETUP_FROM for players who already had Encore. It then shows these notes itself.
function Encore:CheckWhatsNew()
    local db = self.db
    local current = self.version
    if current == "dev" then return end
    local seen = db.seenVersion
    if not seen then
        if (db.stats.logins or 0) <= 1 then -- new install: no notes, but the setup window
            db.seenVersion = current
            if self.ShowSetup and not db.setupShown then
                db.setupShown = current
                self:ShowSetup()
            end
            return
        end
        seen = FIRST_VERSION
    end
    if compare(current, seen) <= 0 then return end
    db.seenVersion = current
    local entries = entriesBetween(seen, current)
    if self.ShowSetup and not db.setupShown and isFull(current) and compare(current, self.SETUP_FROM or current) >= 0 then
        db.setupShown = current
        self:ShowSetup(entries, true)
        return
    end
    if #entries > 0 then self:ShowWhatsNew(entries) end
end
