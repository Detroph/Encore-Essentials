-- Encore-QoL: Combat tab. Trimmed by Det to three things the game and common addons don't already cover:
-- durability warning, interrupt and CC announce, and hiding frames in combat.
-- Forever keeps the combat log away from addons, so announcements come from your own casts and auras.
local _, ns = ...
local Q = ns.QoL

---------------------------------------------------------------------------
-- Durability warning
---------------------------------------------------------------------------
local function lowestDurability()
    local lowest
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = cur / max * 100
            if not lowest or pct < lowest then lowest = pct end
        end
    end
    return lowest
end

Q:Feature{
    id = "durability", tab = "combat", section = "Before the pull", name = "Durability warning",
    desc = "A warning on screen when your gear is below a set percent: on a ready check and when you enter a dungeon or raid.",
    defaults = { threshold = 30, readyCheck = true, instance = true },
    options = {
        { kind = "slider", key = "threshold", name = "Warn below", min = 5, max = 80, step = 5, fmt = function(v) return v .. "%" end },
        { kind = "check", key = "readyCheck", name = "On a ready check" },
        { kind = "check", key = "instance", name = "On entering a dungeon or raid" },
        { kind = "button", name = "Test it", onClick = function(f) f:Warn(true) end, always = true },
    },
    detect = { { eqol = "durabilityWarningEnabled" }, { leatrix = "DurabilityStatus" } },
    Warn = function(f, test)
        local pct = lowestDurability()
        if not test and (not pct or pct >= f:Get("threshold")) then return end
        local text = ("Durability low: %d%%. Repair before the pull."):format(math.floor(pct or 0))
        if RaidNotice_AddMessage and RaidWarningFrame then
            RaidNotice_AddMessage(RaidWarningFrame, text, { r = 1, g = 0.3, b = 0.2 })
        end
        Q:Print(text)
        PlaySound(SOUNDKIT.RAID_WARNING or 8959, "Master")
    end,
    Enable = function(f)
        f:On("READY_CHECK", function() if f:Get("readyCheck") then f:Warn() end end)
        f:On("PLAYER_ENTERING_WORLD", function()
            local _, kind = IsInInstance()
            if f:Get("instance") and (kind == "party" or kind == "raid") then C_Timer.After(3, function() f:Warn() end) end
        end)
    end,
}

---------------------------------------------------------------------------
-- Interrupt and CC announce
---------------------------------------------------------------------------
-- First rank of each spell; names are looked up in the game's language, so every rank matches.
local INTERRUPTS = { 1766, 6552, 72, 2139, 8042, 19244, 15487, 16979, 22570, 57994, 47528, 96231, 116705, 183752, 187707, 106839, 147362, 351338 }
local CC = { 118, 6770, 2637, 5782, 6358, 710, 9484, 1776, 2094, 20066, 853, 1513, 5484, 5246, 408, 339, 3355, 1090, 2484, 51514, 115078, 217832 }

local function nameSet(ids)
    local set = {}
    for _, id in ipairs(ids) do
        local n = Q.SpellName(id)
        if n then set[n] = true end
    end
    return set
end

local function findMyAura(unit, name)
    if AuraUtil and AuraUtil.FindAuraByName then
        local _, _, _, _, duration, expires = AuraUtil.FindAuraByName(name, unit, "HARMFUL|PLAYER")
        if duration then return true, expires end
        return false
    end
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local a = C_UnitAuras.GetAuraDataBySpellName(unit, name, "HARMFUL|PLAYER")
        if a then return true, a.expirationTime end
    end
    return false
end

Q:Feature{
    id = "announce", tab = "combat", section = "Announce", name = "Interrupt and CC announce",
    desc = "Says in party or raid chat when you interrupt a cast, and when your crowd control breaks early. Never in /say.",
    defaults = { interrupts = true, cc = true, solo = true },
    options = {
        { kind = "check", key = "interrupts", name = "Announce interrupts" },
        { kind = "check", key = "cc", name = "Announce crowd control breaking early" },
        { kind = "check", key = "solo", name = "When not in a group, show it to you only" },
    },
    Say = function(f, text)
        local channel = Q.GroupChannel()
        if channel then SendChatMessage(text, channel)
        elseif f:Get("solo") then Q:Print(text) end
    end,
    Enable = function(f)
        local interrupts, cc = nameSet(INTERRUPTS), nameSet(CC)
        local targetCast -- the cast your target had going: { name, guid }
        local function noteCast(unit)
            if unit ~= "target" then return end
            local name = UnitCastingInfo("target") or UnitChannelInfo("target")
            targetCast = name and { name = name, guid = UnitGUID("target"), who = UnitName("target") } or nil
        end
        f:On("UNIT_SPELLCAST_START", function(_, unit) noteCast(unit) end)
        f:On("UNIT_SPELLCAST_CHANNEL_START", function(_, unit) noteCast(unit) end)
        f:On("PLAYER_TARGET_CHANGED", function() noteCast("target") end)
        local pendingKick
        f:On("UNIT_SPELLCAST_INTERRUPTED", function(_, unit)
            if unit == "target" and pendingKick and GetTime() - pendingKick.at < 0.6 and targetCast then
                f:Say(("Interrupted %s's %s with %s."):format(targetCast.who or "?", targetCast.name, pendingKick.spell))
                pendingKick = nil
            end
        end)
        f:On("UNIT_SPELLCAST_CHANNEL_STOP", function(_, unit)
            if unit == "target" and pendingKick and GetTime() - pendingKick.at < 0.3 and targetCast then
                f:Say(("Interrupted %s's %s with %s."):format(targetCast.who or "?", targetCast.name, pendingKick.spell))
                pendingKick = nil
            end
        end)

        local watching -- your CC on the target: { spell, who, guid, expires }
        f:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
            if unit ~= "player" then return end
            local name = Q.SpellName(spellID)
            if not name then return end
            if f:Get("interrupts") and interrupts[name] then pendingKick = { spell = name, at = GetTime() } end
            if f:Get("cc") and cc[name] and UnitExists("target") then
                C_Timer.After(0.3, function()
                    local on, expires = findMyAura("target", name)
                    if on then watching = { spell = name, who = UnitName("target"), guid = UnitGUID("target"), expires = expires } end
                end)
            end
        end)
        f:Ticker(0.2, function()
            if not watching then return end
            if UnitGUID("target") ~= watching.guid then watching = nil return end
            local on = findMyAura("target", watching.spell)
            if on then return end
            local left = (watching.expires or 0) - GetTime()
            if left > 1 and not UnitIsDead("target") then
                f:Say(("%s on %s broke early (%d s left)."):format(watching.spell, watching.who or "?", math.floor(left)))
            end
            watching = nil
        end)
    end,
}

---------------------------------------------------------------------------
-- Hide in combat
---------------------------------------------------------------------------
local function chatFrames()
    local list = { GeneralDockManager }
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        list[#list + 1] = _G["ChatFrame" .. i]
        list[#list + 1] = _G["ChatFrame" .. i .. "Tab"]
    end
    return list
end

Q:Feature{
    id = "hideInCombat", tab = "combat", section = "In combat", name = "Hide in combat",
    desc = "Hides the chat, the minimap or your bags while you fight, and brings them back after.",
    defaults = { chat = false, minimap = false, bags = true },
    options = {
        { kind = "check", key = "chat", name = "Chat" },
        { kind = "check", key = "minimap", name = "Minimap" },
        { kind = "check", key = "bags", name = "Bags and the bag bar" },
    },
    detect = { { eqol = "chatIMHideInCombat" } },
    Groups = function(f)
        return {
            chat = chatFrames(),
            minimap = { MinimapCluster },
            bags = { _G.BagsBar, _G.MicroButtonAndBagsBar, _G.MainMenuBarBackpackButton },
        }
    end,
    Show = function(f, inCombat)
        for key, frames in pairs(f:Groups()) do
            local hide = inCombat and f:Get(key)
            for _, frame in pairs(frames) do
                if frame and frame.SetAlpha then frame:SetAlpha(hide and 0 or 1) end
            end
            if hide and key == "bags" and CloseAllBags then CloseAllBags() end
        end
    end,
    Enable = function(f)
        f:On("PLAYER_REGEN_DISABLED", function() f:Show(true) end)
        f:On("PLAYER_REGEN_ENABLED", function() f:Show(false) end)
    end,
    Disable = function(f) f:Show(false) end,
}
