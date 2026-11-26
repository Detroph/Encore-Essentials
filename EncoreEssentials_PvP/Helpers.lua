-- Encore-QoL: PvP tab, battleground helpers (moved here from Combat and QoL by Det).
local _, ns = ...
local Q = _G.EncoreQoL -- Encore-PvP plugs its features into Encore-QoL (same window, same saved settings)

local function inBattleground()
    local _, kind = IsInInstance()
    return kind == "pvp"
end

Q:Feature{
    id = "bgRelease", tab = "pvp", section = "Battleground helpers", name = "Release in battlegrounds",
    desc = "Releases your spirit straight away when you die in a battleground. Not when a soulstone or a res is waiting.",
    defaults = { skipAV = false },
    options = { { kind = "check", key = "skipAV", name = "Not in Alterac Valley" } },
    detect = { { eqol = "autoReleasePvP" }, { leatrix = "AutoReleasePvP" } },
    Enable = function(f)
        f:On("PLAYER_DEAD", function()
            if not inBattleground() or Q.Skip() then return end
            if f:Get("skipAV") and select(8, GetInstanceInfo()) == 30 then return end
            if HasSoulstone and HasSoulstone() then return end
            C_Timer.After(0.4, function()
                if UnitIsDead("player") and not UnitIsGhost("player") then RepopMe() end
            end)
        end)
    end,
}

Q:Feature{
    id = "bgQueue", tab = "pvp", section = "Battleground helpers", name = "Queue popup",
    desc = "When your battleground is ready: a sound, the game icon flashes in the taskbar, and the time left to enter shows on the popup.",
    Enable = function(f)
        f:On("UPDATE_BATTLEFIELD_STATUS", function()
            for i = 1, (GetMaxBattlefieldID and GetMaxBattlefieldID() or 3) do
                local status = GetBattlefieldStatus(i)
                if status == "confirm" and not f.ringing then
                    f.ringing = true
                    PlaySound(SOUNDKIT.PVP_THROUGH_QUEUE or 8459, "Master")
                    if FlashClientIcon then FlashClientIcon() end
                    f.index = i
                end
            end
            local any = false
            for i = 1, (GetMaxBattlefieldID and GetMaxBattlefieldID() or 3) do
                if GetBattlefieldStatus(i) == "confirm" then any = true end
            end
            if not any then f.ringing = false end
        end)
        f:Ticker(1, function()
            if not f.ringing or not f.index then return end
            local left = GetBattlefieldPortExpiration and GetBattlefieldPortExpiration(f.index)
            if not left or left <= 0 then return end
            local popup = StaticPopup_FindVisible and StaticPopup_FindVisible("CONFIRM_BATTLEFIELD_ENTRY")
            local text = popup and (popup.text or popup.Text)
            if text and text.GetText then
                local base = (text:GetText() or ""):gsub("\n|cffffd100%d+ s left|r$", "")
                text:SetText(base .. "\n|cffffd100" .. math.floor(left) .. " s left|r")
            end
            local pvp = _G.PVPReadyDialog
            if pvp and pvp:IsShown() and pvp.label then pvp.label:SetText(("%d s left"):format(left)) end
        end)
    end,
}

Q:Feature{
    id = "bgClutter", tab = "pvp", section = "Battleground helpers", name = "Hide clutter in battlegrounds",
    desc = "Hides the quest tracker and raid group labels while you're in a battleground.",
    trackers = function() return { _G.QuestWatchFrame, _G.WatchFrame, _G.ObjectiveTrackerFrame } end,
    Enable = function(f)
        local function update()
            local inside = inBattleground()
            for _, t in pairs(f.trackers()) do
                if inside then Q.KeepHidden(t) else Q.Unhide(t) end
            end
            for i = 1, 8 do
                local title = _G["CompactRaidGroup" .. i .. "Title"]
                if title then title:SetAlpha(inside and 0 or 1) end
            end
        end
        f:On("PLAYER_ENTERING_WORLD", update)
        f:On("ZONE_CHANGED_NEW_AREA", update)
        f:On("GROUP_ROSTER_UPDATE", update)
        update()
    end,
    Disable = function(f)
        for _, t in pairs(f.trackers()) do Q.Unhide(t) end
    end,
}
