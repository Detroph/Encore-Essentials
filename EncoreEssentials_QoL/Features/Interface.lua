-- Encore-QoL: Interface tab, everything except action bars: minimap, Edit Mode extras, other frames, chat,
-- tooltip and clutter. Ideas from Leatrix Plus and Enhance QoL (All Rights Reserved): own code.
local _, ns = ...
local Q = ns.QoL
local W = Q.W

-- Hides a frame and keeps it hidden when the game shows it again, until restored.
local hidden = {}
local function keepHidden(frame)
    if not frame or hidden[frame] then return end
    hidden[frame] = true
    frame:Hide()
    if not frame.encoreQoLHook then
        frame.encoreQoLHook = true
        hooksecurefunc(frame, "Show", function(self) if hidden[self] then self:Hide() end end)
    end
end
local function unhide(frame, show)
    if not frame or not hidden[frame] then return end
    hidden[frame] = nil
    if show ~= false then frame:Show() end
end
Q.KeepHidden, Q.Unhide = keepHidden, unhide

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------
local ROUND_ART = { "MinimapBorder", "MinimapBorderTop", "MinimapCompassTexture", "MiniMapWorldMapButton", "MinimapNorthTag" }

local squareShape = function() return "SQUARE" end

Q:Feature{
    id = "squareMinimap", tab = "interface", section = "Minimap", name = "Square minimap",
    desc = "Square map with a thin copper border. Addon buttons follow the square edge. Built for the Camelot skin.",
    defaults = { border = 2, scale = 100 },
    options = {
        { kind = "slider", key = "border", name = "Border width", min = 0, max = 6, step = 1 },
        { kind = "slider", key = "scale", name = "Scale", min = 60, max = 160, step = 5, fmt = function(v) return v .. "%" end },
    },
    needsReload = true,
    detect = {
        { eqol = "enableSquareMinimap" }, { leatrix = "SquareMinimap" },
        { addon = "SexyMap" }, { addon = "BasicMinimap" },
        { fn = function() if _G.GetMinimapShape and _G.GetMinimapShape ~= squareShape then return Q.TaintOwner("GetMinimapShape") end end },
    },
    Enable = function(f)
        Minimap:SetMaskTexture("Interface\\ChatFrame\\ChatFrameBackground")
        _G.GetMinimapShape = squareShape
        for _, name in ipairs(ROUND_ART) do keepHidden(_G[name]) end
        -- The Camelot skin's round frame is a child texture of the cluster without a name.
        local cluster = MinimapCluster
        f.art = f.art or {}
        for _, region in ipairs({ (cluster.BorderTop or cluster):GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "Texture" and region ~= Minimap and region:IsShown()
                and region:GetWidth() > Minimap:GetWidth() * 0.9 then
                f.art[#f.art + 1] = region
                region:SetAlpha(0)
            end
        end
        if not f.border then
            f.border = CreateFrame("Frame", nil, Minimap)
            f.border:SetFrameLevel(Minimap:GetFrameLevel() + 2)
            f.lines = W.Border(f.border, W.COPPER, 1, "OVERLAY")
        end
        f:OnOption()
        f.border:Show()
        if _G.LibStub then
            local icon = LibStub("LibDBIcon-1.0", true)
            if icon and icon.IconCallback then pcall(icon.IconCallback, icon) end
        end
    end,
    OnOption = function(f)
        local b = f:Get("border")
        f.border:SetPoint("TOPLEFT", -b, b)
        f.border:SetPoint("BOTTOMRIGHT", b, -b)
        local w = math.max(1, b)
        f.lines[1]:SetHeight(w); f.lines[2]:SetHeight(w); f.lines[3]:SetWidth(w); f.lines[4]:SetWidth(w)
        f.border:SetShown(b > 0)
        Minimap:SetScale(f:Get("scale") / 100)
    end,
    Disable = function(f)
        Minimap:SetMaskTexture("Textures\\MinimapMask")
        if _G.GetMinimapShape == squareShape then _G.GetMinimapShape = nil end
        for _, name in ipairs(ROUND_ART) do unhide(_G[name]) end
        for _, region in ipairs(f.art or {}) do region:SetAlpha(1) end
        if f.border then f.border:Hide() end
        Minimap:SetScale(1)
    end,
}

-- Addon buttons (LibDBIcon and others parented to the minimap) gathered into one drawer.
local function isAddonButton(child)
    local name = child.GetName and child:GetName() or ""
    if name:find("^LibDBIcon10_") then return true end
    if child.encoreDrawer then return false end
    if child:GetObjectType() ~= "Button" or not child:IsShown() then return false end
    for _, skip in ipairs({ "MiniMap", "Minimap", "GameTime", "TimeManager", "Queue", "EncoreEssentials" }) do
        if name:find(skip, 1, true) then return false end
    end
    return name ~= ""
end

Q:Feature{
    id = "buttonDrawer", tab = "interface", section = "Minimap", name = "Button drawer",
    desc = "Collects addon minimap buttons into one Encore drawer that opens from a single button. The Encore button stays on the map.",
    defaults = { columns = 5 },
    options = { { kind = "slider", key = "columns", name = "Buttons per row", min = 2, max = 10, step = 1 } },
    needsReload = true,
    detect = { { eqol = "enableMinimapButtonBin" }, { addon = "MBB" }, { addon = "MinimapButtonBag" }, { addon = "MinimapButtonButton" } },
    Enable = function(f)
        if not f.toggle then
            local t = CreateFrame("Button", nil, Minimap)
            t.encoreDrawer = true
            t:SetSize(32, 32)
            t:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -4, -4)
            t:SetFrameLevel(Minimap:GetFrameLevel() + 8)
            local icon = t:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexture(Q.ICON)
            t:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
            local drawer = CreateFrame("Frame", nil, t)
            drawer.encoreDrawer = true
            drawer:SetPoint("TOPRIGHT", t, "BOTTOMLEFT", 0, 0)
            drawer:SetFrameStrata("DIALOG")
            W.Panel(drawer, 0.92)
            drawer:Hide()
            t:SetScript("OnClick", function() drawer:SetShown(not drawer:IsShown()) end)
            W.Tooltip(t, "Addon buttons", "Click to open or close the drawer.")
            f.toggle, f.drawer, f.buttons = t, drawer, {}
        end
        f.toggle:Show()
        f:Collect()
        f:Ticker(5, function() f:Collect() end)
    end,
    Collect = function(f)
        for _, child in ipairs({ Minimap:GetChildren() }) do
            if isAddonButton(child) and not f.buttons[child] then
                f.buttons[child] = true
                child:SetParent(f.drawer)
                if child.SetFrameStrata then child:SetFrameStrata("DIALOG") end
            end
        end
        local list = {}
        for b in pairs(f.buttons) do list[#list + 1] = b end
        table.sort(list, function(a, b) return (a:GetName() or "") < (b:GetName() or "") end)
        local cols = f:Get("columns")
        -- Buttons keep the minimap's low frame level when moved; lift them above the drawer's background.
        local level = f.drawer:GetFrameLevel() + 5
        for i, b in ipairs(list) do
            if b.SetFrameStrata then b:SetFrameStrata("DIALOG") end
            if b.SetFrameLevel and b:GetFrameLevel() < level then b:SetFrameLevel(level) end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f.drawer, "TOPLEFT", 4 + ((i - 1) % cols) * 34, -4 - math.floor((i - 1) / cols) * 34)
        end
        f.drawer:SetSize(8 + math.min(#list, cols) * 34, 8 + math.ceil(math.max(1, #list) / cols) * 34)
    end,
    OnOption = function(f) f:Collect() end,
    Disable = function(f)
        if f.toggle then f.toggle:Hide() end
        for b in pairs(f.buttons or {}) do b:SetParent(Minimap) end
        f.buttons = {}
    end,
}

Q:Feature{
    id = "minimapTidy", tab = "interface", section = "Minimap", name = "Wheel zoom and tidy",
    desc = "Zoom the minimap with the mouse wheel, and hide the buttons you don't use.",
    defaults = { zoomButtons = true, clock = false, tracking = false },
    options = {
        { kind = "check", key = "zoomButtons", name = "Hide zoom buttons" },
        { kind = "check", key = "clock", name = "Hide clock" },
        { kind = "check", key = "tracking", name = "Hide tracking button" },
    },
    detect = { { addon = "SexyMap" } },
    parts = function()
        return {
            zoomButtons = { _G.MinimapZoomIn or (Minimap.ZoomIn), _G.MinimapZoomOut or (Minimap.ZoomOut) },
            clock = { _G.TimeManagerClockButton },
            tracking = { _G.MiniMapTracking or _G.MiniMapTrackingFrame or (MinimapCluster.Tracking) },
        }
    end,
    Enable = function(f)
        Minimap:EnableMouseWheel(true)
        f:HookScript(Minimap, "OnMouseWheel", function(_, d)
            local z = Minimap:GetZoom() + (d > 0 and 1 or -1)
            Minimap:SetZoom(math.max(0, math.min(Minimap:GetZoomLevels() - 1, z)))
        end)
        f:OnOption()
    end,
    OnOption = function(f)
        for key, frames in pairs(f.parts()) do
            for _, frame in pairs(frames) do
                if f:Get(key) then keepHidden(frame) else unhide(frame) end
            end
        end
    end,
    Disable = function(f)
        for _, frames in pairs(f.parts()) do for _, frame in pairs(frames) do unhide(frame) end end
    end,
}

---------------------------------------------------------------------------
-- Edit Mode extras: frames the game keeps in place get a blue mover while Edit Mode is open (or while unlocked
-- from here). Drag to move, mouse wheel to scale. Frames that are already in Edit Mode are left out.
---------------------------------------------------------------------------
local MOVABLE = {
    { key = "durability", name = "Durability doll", frames = { "DurabilityFrame" } },
    { key = "questTracker", name = "Quest tracker", frames = { "QuestWatchFrame", "WatchFrame", "ObjectiveTrackerFrame" } },
    { key = "errors", name = "Error text", frames = { "UIErrorsFrame" } },
    { key = "zoneText", name = "Zone text", frames = { "ZoneTextFrame" } },
    { key = "capture", name = "Capture bar", frames = { "UIWidgetBelowMinimapContainerFrame" } },
    { key = "ghost", name = "Ghost button", frames = { "GhostFrame" } },
    { key = "buffs", name = "Buffs", frames = { "BuffFrame" } },
}

local function movableFrame(m)
    for _, n in ipairs(m.frames) do
        local frame = _G[n]
        if frame and not frame.system and not (frame.IsProtected and frame:IsProtected()) then return frame end
    end
end

Q:Feature{
    id = "editModeExtras", tab = "interface", section = "Edit Mode extras", name = "Move more frames",
    desc = "Adds blue movers to frames the game keeps fixed: durability doll, quest tracker, error text, zone text, capture bar, ghost button and buffs. They show while Edit Mode is open. Drag to move, mouse wheel to scale.",
    options = {
        { kind = "button", name = "Show movers now", onClick = function(f) f:ShowMovers(not f.moversShown) end },
        { kind = "button", name = "Reset all positions", onClick = function(f)
            f:Saved().pos = {}
            Q:Print("Positions reset. A /reload puts the frames back.")
        end },
    },
    detect = { { eqol = function() return C_AddOns.IsAddOnLoaded("EnhanceQoLMover") and type(_G.EnhanceQoLMoverDB) == "table" and next(_G.EnhanceQoLMoverDB) ~= nil end },
        { addon = "MoveAnything" }, { addon = "BlizzMove" } },
    -- Saved as screen position of the frame's centre plus its scale: { x, y, scale }.
    Place = function(f, m, frame)
        local pos = f:Saved().pos and f:Saved().pos[m.key]
        if type(pos) ~= "table" or not pos[1] then return end
        f.placing = true
        if pos[3] then frame:SetScale(pos[3]) end
        local s = frame:GetEffectiveScale()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos[1] / s, pos[2] / s)
        f.placing = false
    end,
    Remember = function(f, m, frame, sx, sy)
        local pos = f:Saved().pos[m.key] or {}
        if not sx then
            local cx, cy = frame:GetCenter()
            local s = frame:GetEffectiveScale()
            sx, sy = cx * s, cy * s
        end
        pos[1], pos[2], pos[3] = sx, sy, frame:GetScale()
        f:Saved().pos[m.key] = pos
    end,
    Enable = function(f)
        if type(f:Saved().pos) ~= "table" then f:Saved().pos = {} end
        f.movers = f.movers or {}
        for _, m in ipairs(MOVABLE) do
            local frame = movableFrame(m)
            if frame then
                if frame.SetMovable then frame:SetMovable(true) end
                if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, true) end
                f:Hook(frame, "SetPoint", function(self)
                    if not f.placing and f:Saved().pos[m.key] then f:Place(m, self) end
                end)
                f:Place(m, frame)
            end
        end
        if EditModeManagerFrame then
            f:HookScript(EditModeManagerFrame, "OnShow", function() f:ShowMovers(true) end)
            f:HookScript(EditModeManagerFrame, "OnHide", function() f:ShowMovers(false) end)
        end
    end,
    ShowMovers = function(f, show)
        f.moversShown = show and f.active
        for _, m in ipairs(MOVABLE) do
            local frame = movableFrame(m)
            local mover = f.movers[m.key]
            if frame and f.moversShown and not mover then
                mover = CreateFrame("Frame", nil, UIParent)
                mover:SetFrameStrata("DIALOG")
                mover:EnableMouse(true)
                mover:EnableMouseWheel(true)
                mover:SetMovable(true)
                mover:RegisterForDrag("LeftButton")
                local bg = mover:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0.24, 0.55, 1, 0.18)
                W.Border(mover, { 0.31, 0.64, 1 })
                mover.label = W.Text(mover, "GameFontHighlightSmall", m.name)
                mover.label:SetPoint("CENTER")
                mover:SetScript("OnDragStart", function(self) self:StartMoving() end)
                mover:SetScript("OnDragStop", function(self)
                    self:StopMovingOrSizing()
                    local cx, cy = self:GetCenter()
                    local s = self:GetEffectiveScale()
                    f:Remember(m, frame, cx * s, cy * s)
                    f:Place(m, frame)
                    self:ClearAllPoints()
                    self:SetAllPoints(frame)
                end)
                mover:SetScript("OnMouseWheel", function(self, d)
                    f:Remember(m, frame)
                    frame:SetScale(math.max(0.5, math.min(2, frame:GetScale() + d * 0.05)))
                    f:Saved().pos[m.key][3] = frame:GetScale()
                    f:Place(m, frame)
                    self:ClearAllPoints()
                    self:SetAllPoints(frame)
                end)
                f.movers[m.key] = mover
            end
            if mover then
                if f.moversShown and frame then
                    mover:ClearAllPoints()
                    mover:SetAllPoints(frame)
                    if (frame:GetWidth() or 0) < 30 then mover:SetSize(120, 30) end
                    mover:Show()
                else
                    mover:Hide()
                end
            end
        end
    end,
    Disable = function(f) f:ShowMovers(false) end,
    needsReload = true,
}

---------------------------------------------------------------------------
-- Other frames
---------------------------------------------------------------------------
Q:Feature{
    id = "questLevels", tab = "interface", section = "Other frames", name = "Quest log levels",
    desc = "Shows each quest's level in front of its name in the quest log.",
    detect = { { leatrix = "EnhanceQuestLevels" } },
    Enable = function(f)
        f:Hook("QuestLog_Update", function()
            local offset = FauxScrollFrame_GetOffset and QuestLogListScrollFrame and FauxScrollFrame_GetOffset(QuestLogListScrollFrame) or 0
            for i = 1, QUESTS_DISPLAYED or 0 do
                local button = _G["QuestLogTitle" .. i]
                local index = i + offset
                if button and button:IsShown() and GetQuestLogTitle then
                    local title, level, _, isHeader = GetQuestLogTitle(index)
                    if title and not isHeader and level and level > 0 then
                        button:SetText("  [" .. level .. "] " .. title)
                        if QuestLogTitleButton_Resize then QuestLogTitleButton_Resize(button) end
                    end
                end
            end
        end)
        if QuestLog_Update and QuestLogFrame and QuestLogFrame:IsShown() then QuestLog_Update() end
    end,
    needsReload = true,
}

local function classColor(unit)
    if not unit or not UnitIsPlayer(unit) then return nil end
    local _, class = UnitClass(unit)
    local c = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
    return c
end

Q:Feature{
    id = "classColorFrames", tab = "interface", section = "Other frames", name = "Class colored frames",
    desc = "Class colours on the names of the player, target, focus and party frames.",
    detect = { { leatrix = "ClassColFrames" }, { addon = "EnhanceQoLUnitFrames", replaced = true } },
    Enable = function(f)
        local function paint(frame)
            if not frame or not frame.unit then return end
            local c = classColor(frame.unit)
            local name = frame.name or frame.Name or (frame.GetName and _G[(frame:GetName() or "") .. "Name"])
            if c and name and name.SetTextColor then name:SetTextColor(c.r, c.g, c.b) end
            local bg = frame.nameBackground or (frame.GetName and _G[(frame:GetName() or "") .. "NameBackground"])
            if c and bg and bg.SetVertexColor then bg:SetVertexColor(c.r, c.g, c.b) end
        end
        f.paint = paint
        f:Hook("UnitFrame_Update", paint)
        f:Hook("TargetFrame_CheckFaction", paint)
        f:On("PLAYER_TARGET_CHANGED", function() paint(TargetFrame) end)
        f:On("GROUP_ROSTER_UPDATE", function() for i = 1, 4 do paint(_G["PartyMemberFrame" .. i]) end end)
        for _, fr in ipairs({ PlayerFrame, TargetFrame, FocusFrame }) do paint(fr) end
    end,
    needsReload = true,
}

Q:Feature{
    id = "hideUnitFrames", tab = "interface", section = "Other frames", name = "Hide until mouseover",
    desc = "Your player or target frame stays hidden until the mouse is over it, or you're in combat.",
    defaults = { player = true, target = false, combat = true },
    options = {
        { kind = "check", key = "player", name = "Player frame" },
        { kind = "check", key = "target", name = "Target frame" },
        { kind = "check", key = "combat", name = "Always show in combat" },
    },
    detect = { { addon = "EnhanceQoLUnitFrames", replaced = true } },
    Enable = function(f)
        f:Ticker(0.1, function()
            local combat = f:Get("combat") and (InCombatLockdown() or UnitAffectingCombat("player"))
            for key, frame in pairs({ player = PlayerFrame, target = TargetFrame }) do
                if frame then
                    if f:Get(key) then frame:SetAlpha((combat or frame:IsMouseOver()) and 1 or 0) else frame:SetAlpha(1) end
                end
            end
        end)
    end,
    Disable = function()
        if PlayerFrame then PlayerFrame:SetAlpha(1) end
        if TargetFrame then TargetFrame:SetAlpha(1) end
    end,
}

---------------------------------------------------------------------------
-- Chat and tooltip
---------------------------------------------------------------------------
Q:Feature{
    id = "chatButtons", tab = "interface", section = "Chat and tooltip", name = "Hide chat buttons",
    desc = "Hides the chat menu, channel, social and scroll buttons next to the chat window.",
    detect = { { addon = "Chattynator", replaced = true }, { addon = "Prat-3.0", replaced = true }, { leatrix = "NoChatButtons" } },
    list = function()
        local l = { _G.ChatFrameMenuButton, _G.ChatFrameChannelButton, _G.QuickJoinToastButton, _G.FriendsMicroButton, _G.ChatFrameToggleVoiceDeafenButton, _G.ChatFrameToggleVoiceMuteButton }
        for i = 1, NUM_CHAT_WINDOWS or 10 do l[#l + 1] = _G["ChatFrame" .. i .. "ButtonFrame"] end
        return l
    end,
    Enable = function(f) for _, b in pairs(f.list()) do keepHidden(b) end end,
    Disable = function(f) for _, b in pairs(f.list()) do unhide(b) end end,
}

Q:Feature{
    id = "chatFade", tab = "interface", section = "Chat and tooltip", name = "Chat fade time",
    desc = "How long chat lines stay before they fade out.",
    defaults = { seconds = 60 },
    options = { { kind = "slider", key = "seconds", name = "Lines stay for", min = 10, max = 600, step = 10, fmt = function(v) return v .. " s" end } },
    detect = { { eqol = "chatFrameFadeEnabled" }, { addon = "Chattynator", replaced = true } },
    Enable = function(f) f:OnOption() end,
    OnOption = function(f)
        for i = 1, NUM_CHAT_WINDOWS or 10 do
            local c = _G["ChatFrame" .. i]
            if c and c.SetTimeVisible then c:SetTimeVisible(f:Get("seconds")) end
        end
    end,
    Disable = function()
        for i = 1, NUM_CHAT_WINDOWS or 10 do
            local c = _G["ChatFrame" .. i]
            if c and c.SetTimeVisible then c:SetTimeVisible(120) end
        end
    end,
}

Q:Feature{
    id = "tooltip", tab = "interface", section = "Chat and tooltip", name = "Tooltip",
    desc = "Tooltip size, the guild rank on player tooltips, and no unit tooltips in combat. Encore tooltips already follow the cursor.",
    defaults = { scale = 100, rank = true, hideCombat = false },
    options = {
        { kind = "slider", key = "scale", name = "Size", min = 60, max = 160, step = 5, fmt = function(v) return v .. "%" end },
        { kind = "check", key = "rank", name = "Show guild rank" },
        { kind = "check", key = "hideCombat", name = "Hide unit tooltips in combat" },
    },
    detect = { { eqol = function(p) return p.TooltipUnitHideInCombat end }, { leatrix = "TipModEnable" }, { addon = "TipTac", replaced = true } },
    Enable = function(f)
        f:OnOption()
        if f.hooked then return end
        f.hooked = true
        Q.TooltipHook("unit", function(tt)
            if not f.active or tt ~= GameTooltip then return end
            local _, unit = tt:GetUnit()
            if not unit then return end
            if f:Get("hideCombat") and InCombatLockdown() then tt:Hide() return end
            if f:Get("rank") and UnitIsPlayer(unit) then
                local guild, rank = GetGuildInfo(unit)
                if guild and rank then
                    for i = 2, tt:NumLines() do
                        local line = _G["GameTooltipTextLeft" .. i]
                        local text = line and line:GetText()
                        if text and text:find(guild, 1, true) and not text:find(rank, 1, true) then
                            line:SetText(text .. " |cffa39278(" .. rank .. ")|r")
                            break
                        end
                    end
                end
            end
        end)
    end,
    OnOption = function(f) GameTooltip:SetScale(f:Get("scale") / 100) end,
    Disable = function() GameTooltip:SetScale(1) end,
}

---------------------------------------------------------------------------
-- Clutter
---------------------------------------------------------------------------
Q:Feature{
    id = "hideErrors", tab = "interface", section = "Hide clutter", name = "Hide error text",
    desc = "Stops the red error text (\"Not enough rage\", \"Out of range\") in the middle of the screen. Quest progress still shows.",
    detect = { { addon = "ErrorMonster" }, { eqol = "uiErrorFilterEnabled" }, { leatrix = "HideErrorMessages" } },
    Enable = function() UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE") end,
    Disable = function() UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE") end,
}

Q:Feature{
    id = "hideBossBanner", tab = "interface", section = "Hide clutter", name = "Hide boss banners",
    desc = "No big banner when a boss dies or loot drops.",
    detect = { { eqol = "autoHideBossBanner" } },
    Enable = function(f)
        if BossBanner then
            f:Hook(BossBanner, "PlayBanner", function(self) self:Hide() end)
        end
    end,
}

Q:Feature{
    id = "hideRaidLabels", tab = "interface", section = "Hide clutter", name = "Hide raid group labels",
    desc = "Hides the \"Group 1\" to \"Group 8\" labels on raid frames.",
    Enable = function(f)
        local function hideLabels()
            for i = 1, 8 do
                local t = _G["CompactRaidGroup" .. i .. "Title"]
                if t then t:SetAlpha(0) end
            end
        end
        f:On("GROUP_ROSTER_UPDATE", hideLabels)
        hideLabels()
    end,
    Disable = function()
        for i = 1, 8 do
            local t = _G["CompactRaidGroup" .. i .. "Title"]
            if t then t:SetAlpha(1) end
        end
    end,
}

---------------------------------------------------------------------------
-- UI scaling
---------------------------------------------------------------------------
-- Sets UIParent's scale directly, so values under the game's 0.64 slider floor work.
-- 768 / screen height gives a pixel-perfect UI; the presets are that for common screens.
local SCALE_CHOICES = {
    { "auto", "Auto (768 / screen height)" },
    { "custom", "Custom" },
    { "0.3556", "0.3556 (4K)" },
    { "0.5333", "0.5333 (1440p)" },
    { "0.6666", "0.6666 (1440p 125%)" },
    { "0.7111", "0.7111 (1080p)" },
    { "0.8888", "0.8888 (1080p 125%)" },
}

local function wantedScale(f)
    local mode = f:Get("mode")
    if mode == "auto" then
        local _, h = GetPhysicalScreenSize()
        if h and h > 0 then return 768 / h end
        return nil
    elseif mode == "custom" then
        return f:Get("custom")
    end
    return tonumber(mode)
end

Q:Feature{
    id = "uiScale", tab = "interface", section = "UI scaling", name = "Login UI scaling",
    desc = "Sets the UI scale each time you log in, including values smaller than the game's slider allows. Turn it off to go back to the game's own scaling.",
    defaults = { mode = "auto", custom = 0.64 },
    options = {
        { kind = "choice", key = "mode", name = "Scale", choices = SCALE_CHOICES },
        { kind = "group", text = "Custom scale", when = function(self) return self:Get("mode") == "custom" end },
        { kind = "slider", key = "custom", name = "Scale", min = 0.3, max = 1.2, step = 0.01, fmt = function(v) return ("%.2f"):format(v) end },
    },
    Enable = function(f)
        if not f.original then f.original = UIParent:GetScale() end
        local function apply()
            local s = wantedScale(f)
            if not s then return end
            s = math.max(0.3, math.min(1.2, s))
            if InCombatLockdown() then f.pending = true return end
            f.pending = nil
            if math.abs(UIParent:GetScale() - s) > 0.0001 then UIParent:SetScale(s) end
        end
        f.apply = apply
        -- The game resets the scale when the window or its own scale setting changes.
        f:On("UI_SCALE_CHANGED", function() C_Timer.After(0, apply) end)
        f:On("DISPLAY_SIZE_CHANGED", function() C_Timer.After(0, apply) end)
        f:On("PLAYER_ENTERING_WORLD", apply)
        f:On("PLAYER_REGEN_ENABLED", function() if f.pending then apply() end end)
        apply()
    end,
    OnOption = function(f) if f.apply then f.apply() end end,
    Disable = function(f)
        if InCombatLockdown() then return end
        local s = f.original
        if C_CVar.GetCVar("useUiScale") == "1" then s = tonumber(C_CVar.GetCVar("uiScale")) or s end
        if s then UIParent:SetScale(s) end
    end,
}
