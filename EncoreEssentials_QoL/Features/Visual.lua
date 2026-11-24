-- Encore-QoL: Visual & audio tab. Sounds, camera, cursor, screen effects, and graphics settings past the
-- caps of the game's Graphics menu.
local _, ns = ...
local Q = ns.QoL
local W = Q.W
local MEDIA = "Interface\\AddOns\\EncoreEssentials_QoL\\Media\\"

---------------------------------------------------------------------------
-- Sound
---------------------------------------------------------------------------
local function idList(text)
    local ids = {}
    for id in tostring(text or ""):gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
    return ids
end

Q:Feature{
    id = "muteSounds", tab = "visual", section = "Sound", name = "Mute sounds",
    desc = "Mutes any game sound by its file ID (Wowhead's sound pages list them), for example a noisy mount or toy.",
    defaults = { ids = "" },
    options = { { kind = "edit", key = "ids", name = "Sound file IDs", tip = "File IDs separated by commas." } },
    detect = { { leatrix = "MuteGameSounds" }, { eqol = "soundEnabled" } },
    Enable = function(f)
        f.muted = {}
        for _, id in ipairs(idList(f:Get("ids"))) do
            MuteSoundFile(id)
            f.muted[#f.muted + 1] = id
        end
    end,
    OnOption = function(f) f:Disable() f:Enable() end,
    Disable = function(f)
        for _, id in ipairs(f.muted or {}) do UnmuteSoundFile(id) end
        f.muted = {}
    end,
}

local WHISPER_SOUNDS = {
    { "TELL_MESSAGE", "Game whisper sound" }, { "RAID_WARNING", "Raid warning" }, { "READY_CHECK", "Ready check" },
    { "UI_BNET_TOAST", "Battle.net toast" }, { "IG_PLAYER_INVITE", "Invite" }, { "AUCTION_WINDOW_OPEN", "Auction bell" },
}

Q:Feature{
    id = "whisperSound", tab = "visual", section = "Sound", name = "Whisper sound",
    desc = "Plays a sound of your choice when someone whispers you.",
    defaults = { sound = "RAID_WARNING" },
    options = {
        { kind = "choice", key = "sound", name = "Sound", choices = WHISPER_SOUNDS },
        { kind = "button", name = "Play it", onClick = function(f) f:Play() end },
    },
    detect = { { eqol = "chatIMUseCustomSound" } },
    Play = function(f)
        local kit = SOUNDKIT and SOUNDKIT[f:Get("sound")]
        if kit then PlaySound(kit, "Master") end
    end,
    Enable = function(f)
        local last = 0
        local function ping()
            if GetTime() - last < 2 then return end
            last = GetTime()
            f:Play()
        end
        f:On("CHAT_MSG_WHISPER", ping)
        f:On("CHAT_MSG_BN_WHISPER", ping)
    end,
}

Q:Feature{
    id = "audioSync", tab = "visual", section = "Sound", name = "Keep audio synced",
    desc = "Restarts the game's sound when you plug in or switch headsets, so sound follows your system's output device.",
    detect = { { leatrix = "AutoRestartSound" } },
    Enable = function(f)
        Q.SetCVar("Sound_OutputDriverIndex", "0")
        if not (Sound_GameSystem_GetNumOutputDrivers and Sound_GameSystem_RestartSoundSystem) then return end
        local function signature()
            local n = Sound_GameSystem_GetNumOutputDrivers() or 0
            local first = Sound_GameSystem_GetOutputDriverNameByIndex and Sound_GameSystem_GetOutputDriverNameByIndex(0) or ""
            return n .. ":" .. tostring(first)
        end
        local last = signature()
        f:Ticker(3, function()
            local now = signature()
            if now ~= last then
                last = now
                Sound_GameSystem_RestartSoundSystem()
            end
        end)
    end,
    Disable = function() Q.RestoreCVar("Sound_OutputDriverIndex") end,
}

---------------------------------------------------------------------------
-- Camera and screen
---------------------------------------------------------------------------
Q:Feature{
    id = "maxCamera", tab = "visual", section = "Camera and screen", name = "Max camera distance",
    desc = "Lets the camera zoom out further than the game's menu allows.",
    defaults = { factor = 4 },
    options = { { kind = "slider", key = "factor", name = "Zoom out up to", min = 1, max = 4, step = 0.1, fmt = function(v) return ("%.1fx"):format(v) end } },
    detect = { { leatrix = "MaxCameraZoom" } },
    Enable = function(f) Q.SetCVar("cameraDistanceMaxZoomFactor", f:Get("factor")) end,
    OnOption = function(f) C_CVar.SetCVar("cameraDistanceMaxZoomFactor", tostring(f:Get("factor"))) end,
    Disable = function() Q.RestoreCVar("cameraDistanceMaxZoomFactor") end,
}

Q:Feature{
    id = "screenEffects", tab = "visual", section = "Camera and screen", name = "Screen glow and flashes",
    desc = "Turns off the full-screen glow, the grey death screen and the red low-health flash.",
    defaults = { glow = true, death = true, lowHealth = true },
    options = {
        { kind = "check", key = "glow", name = "No full-screen glow" },
        { kind = "check", key = "death", name = "No grey screen when dead" },
        { kind = "check", key = "lowHealth", name = "No low-health flash" },
    },
    Enable = function(f) f:OnOption() end,
    OnOption = function(f)
        if f:Get("glow") then Q.SetCVar("ffxGlow", "0") else Q.RestoreCVar("ffxGlow") end
        if f:Get("death") then Q.SetCVar("ffxDeath", "0") else Q.RestoreCVar("ffxDeath") end
        if f:Get("lowHealth") then
            if C_CVar.GetCVar("doNotFlashLowHealthWarning") then Q.SetCVar("doNotFlashLowHealthWarning", "1") end
            Q.KeepHidden(_G.LowHealthFrame)
        else
            Q.RestoreCVar("doNotFlashLowHealthWarning")
            Q.Unhide(_G.LowHealthFrame, false)
        end
    end,
    Disable = function()
        for _, c in ipairs({ "ffxGlow", "ffxDeath", "doNotFlashLowHealthWarning" }) do Q.RestoreCVar(c) end
        Q.Unhide(_G.LowHealthFrame, false)
    end,
}

Q:Feature{
    id = "levelScreenshot", tab = "visual", section = "Camera and screen", name = "Screenshot on level up",
    desc = "Takes a screenshot each time you level up.",
    defaults = { onlyMax = false },
    options = { { kind = "check", key = "onlyMax", name = "Only at max level" } },
    Enable = function(f)
        f:On("PLAYER_LEVEL_UP", function(_, level)
            local max = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
            if f:Get("onlyMax") and tonumber(level) ~= max then return end
            C_Timer.After(1.2, Screenshot)
        end)
    end,
}

---------------------------------------------------------------------------
-- Cursor ring
---------------------------------------------------------------------------
local TRAIL = 10

Q:Feature{
    id = "cursorRing", tab = "visual", section = "Camera and screen", name = "Cursor ring",
    desc = "A ring around the mouse cursor so you find it in busy fights, with an optional trail.",
    defaults = { size = 48, color = { 0.92, 0.58, 0.22 }, combatOnly = false, trail = false },
    options = {
        { kind = "slider", key = "size", name = "Size", min = 20, max = 120, step = 4 },
        { kind = "color", key = "color", name = "Colour" },
        { kind = "check", key = "combatOnly", name = "Only in combat" },
        { kind = "check", key = "trail", name = "Trail" },
    },
    detect = { { eqol = "mouseRingEnabled" } },
    Enable = function(f)
        if not f.frame then
            local fr = CreateFrame("Frame", nil, UIParent)
            fr:SetFrameStrata("TOOLTIP")
            fr:SetAllPoints()
            fr:EnableMouse(false)
            f.ring = fr:CreateTexture(nil, "OVERLAY")
            f.ring:SetTexture(MEDIA .. "cursor-ring")
            f.dots = {}
            for i = 1, TRAIL do
                local d = fr:CreateTexture(nil, "ARTWORK")
                d:SetTexture(MEDIA .. "cursor-dot")
                f.dots[i] = d
            end
            f.history = {}
            fr:SetScript("OnUpdate", function()
                if not f.active then fr:Hide() return end
                local show = not f:Get("combatOnly") or InCombatLockdown()
                local scale = UIParent:GetEffectiveScale()
                local x, y = GetCursorPosition()
                x, y = x / scale, y / scale
                f.ring:SetShown(show)
                f.ring:ClearAllPoints()
                f.ring:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
                table.insert(f.history, 1, { x, y })
                f.history[TRAIL + 1] = nil
                for i, d in ipairs(f.dots) do
                    local p = f.history[i + 1]
                    if show and f:Get("trail") and p then
                        d:ClearAllPoints()
                        d:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p[1], p[2])
                        d:SetAlpha(0.6 * (1 - i / TRAIL))
                        d:Show()
                    else
                        d:Hide()
                    end
                end
            end)
            f.frame = fr
        end
        f:OnOption()
        f.frame:Show()
    end,
    OnOption = function(f)
        local s, c = f:Get("size"), f:Get("color")
        f.ring:SetSize(s, s)
        f.ring:SetVertexColor(c[1], c[2], c[3], 0.9)
        for _, d in ipairs(f.dots) do
            d:SetSize(s * 0.3, s * 0.3)
            d:SetVertexColor(c[1], c[2], c[3])
        end
    end,
    Disable = function(f) if f.frame then f.frame:Hide() end end,
}

---------------------------------------------------------------------------
-- Graphics past the menu caps. These only change game settings (CVars), so the check reads the game: an addon
-- that manages graphics on its own (KelaGraphics) locks the whole row.
---------------------------------------------------------------------------
local GRAPHICS = {
    { cvar = "groundEffectDensity", name = "Ground clutter density", min = 16, max = 256, step = 8 },
    { cvar = "groundEffectDist", name = "Ground clutter distance", min = 40, max = 500, step = 10 },
    { cvar = "farclip", name = "View distance", min = 500, max = 20000, step = 250 },
    { cvar = "horizonStart", name = "Foliage and terrain detail distance", min = 400, max = 10000, step = 100 },
    { cvar = "lodObjectFadeScale", name = "Detail fade distance", min = 50, max = 300, step = 10, fmt = function(v) return v .. "%" end },
    { cvar = "particleDensity", name = "Particle density", min = 10, max = 100, step = 5, fmt = function(v) return v .. "%" end },
    { cvar = "weatherDensity", name = "Weather (0 = off)", min = 0, max = 3, step = 1 },
}

local graphicsOptions = {
    { kind = "note", text = "Saved settings come from the game the first time you turn this on, so nothing jumps. Limits differ between clients; the game ignores values it doesn't allow." },
}
for _, g in ipairs(GRAPHICS) do
    graphicsOptions[#graphicsOptions + 1] = { kind = "slider", key = g.cvar, name = g.name .. " (" .. g.cvar .. ")", min = g.min, max = g.max, step = g.step, fmt = g.fmt }
end
graphicsOptions[#graphicsOptions + 1] = { kind = "button", name = "Reset to game defaults", onClick = function(f)
    for _, g in ipairs(GRAPHICS) do
        local default = C_CVar.GetCVarDefault and C_CVar.GetCVarDefault(g.cvar)
        if default then f:Set(g.cvar, tonumber(default)) end
    end
    Q:RefreshWindow()
end }

Q:Feature{
    id = "graphicsCaps", tab = "visual", section = "Graphics past the menu caps", name = "Graphics sliders",
    desc = "Sliders for graphics settings the game allows by /console but caps lower in its Graphics menu: ground clutter, view distance, foliage, detail fade, particles and weather.",
    options = graphicsOptions,
    detect = { { addon = "KelaGraphics" }, { addon = "AdvancedInterfaceOptions" } },
    Enable = function(f)
        for _, g in ipairs(GRAPHICS) do
            if f:Saved()[g.cvar] == nil then f:Saved()[g.cvar] = tonumber(C_CVar.GetCVar(g.cvar)) end
            local v = f:Saved()[g.cvar]
            if v then Q.SetCVar(g.cvar, v) end
        end
    end,
    OnOption = function(f, key, value)
        if value ~= nil and C_CVar.GetCVar(key) then
            Q.SetCVar(key, value)
        end
    end,
    Disable = function()
        for _, g in ipairs(GRAPHICS) do Q.RestoreCVar(g.cvar) end
    end,
}
