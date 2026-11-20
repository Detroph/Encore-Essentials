-- Encore Essentials: the shared parchment look used by every Encore window (the main window, Encore-DB and
-- Encore-Stonks). Light parchment from the game's own quest frame art, brown ink text, brown and gold edges,
-- like Blizzard's quest and book windows. Built-in textures only.
local _, ns = ...
local Encore = ns.Encore

local Theme = {}
Encore.Theme = Theme

-- The quest frame's parchment. The art fills the top-left 300 x 336 of the 512 x 512 file.
Theme.PARCHMENT = "Interface\\QuestFrame\\QuestBG"
Theme.PARCHMENT_COORDS = { 0, 300 / 512, 0, 336 / 512 }

-- Colours for things drawn on parchment, as { r, g, b }.
Theme.INK = { 0.20, 0.12, 0.05 }       -- body text
Theme.TITLE = { 0.40, 0.18, 0.02 }     -- headings, selected rows, column headings
Theme.DIM = { 0.40, 0.31, 0.20 }       -- secondary text
Theme.FAINT = { 0.52, 0.44, 0.34 }     -- disabled text, "nothing here" lines
Theme.EDGE = { 0.45, 0.28, 0.10 }      -- lines and frames on the parchment
Theme.TEAL = { 0.00, 0.44, 0.44 }      -- "new or changed in WoW Forever"
Theme.TEAL_SOFT = { 0.00, 0.40, 0.40 }
Theme.HOVER = { 0.55, 0.34, 0.06 }     -- hover and selection washes (used with a low alpha)
Theme.WELL = { 0.42, 0.26, 0.08 }      -- inset panes (used with a low alpha)

-- The same colours as chat colour codes, for text built with |c...|r.
local function hex(c) return ("|cff%02x%02x%02x"):format(c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5) end
Theme.hex = hex
Theme.INK_HEX = hex(Theme.INK)
Theme.TITLE_HEX = hex(Theme.TITLE)
Theme.DIM_HEX = hex(Theme.DIM)
Theme.FAINT_HEX = hex(Theme.FAINT)
Theme.TEAL_HEX = hex(Theme.TEAL)

-- Item quality colours that read on parchment: the game's own are made for dark backgrounds (white common
-- items, light green and blue). Tooltips stay dark, so they keep the game's colours.
local QUALITY_INK = {
    [0] = { 0.38, 0.38, 0.38 }, -- poor
    [1] = Theme.INK,            -- common
    [2] = { 0.06, 0.45, 0.00 }, -- uncommon
    [3] = { 0.00, 0.30, 0.72 }, -- rare
    [4] = { 0.46, 0.12, 0.74 }, -- epic
    [5] = { 0.78, 0.36, 0.00 }, -- legendary
    [6] = { 0.62, 0.50, 0.20 }, -- artifact
}
function Theme.QualityInk(q)
    local c = QUALITY_INK[q or 1] or Theme.INK
    return c[1], c[2], c[3]
end
function Theme.QualityHex(q)
    return hex(QUALITY_INK[q or 1] or Theme.INK)
end

-- Font objects for text on parchment: the game's fonts in brown ink, without the drop shadow that only
-- suits light text on dark backgrounds. Names: EncoreInk*, EncoreTitle*, EncoreFaint*.
local function makeFont(name, base, c)
    if _G[name] then return end
    local f = CreateFont(name)
    if _G[base] then f:CopyFontObject(_G[base]) end
    f:SetTextColor(c[1], c[2], c[3])
    f:SetShadowColor(0, 0, 0, 0)
    f:SetShadowOffset(0, 0)
end
makeFont("EncoreInkSmall", "GameFontHighlightSmall", Theme.INK)
makeFont("EncoreInk", "GameFontHighlight", Theme.INK)
makeFont("EncoreInkLarge", "GameFontHighlightLarge", Theme.INK)
makeFont("EncoreTitleSmall", "GameFontNormalSmall", Theme.TITLE)
makeFont("EncoreTitle", "GameFontNormal", Theme.TITLE)
makeFont("EncoreTitleLarge", "GameFontNormalLarge", Theme.TITLE)
makeFont("EncoreFaintSmall", "GameFontDisableSmall", Theme.FAINT)
makeFont("EncoreFaint", "GameFontDisable", Theme.FAINT)

-- Parchment on a texture (stretched, not tiled: the art has no repeating edge).
function Theme.SetParchment(tex)
    tex:SetTexture(Theme.PARCHMENT)
    tex:SetTexCoord(unpack(Theme.PARCHMENT_COORDS))
    tex:SetVertexColor(1, 1, 1, 1)
end

-- Give a PortraitFrameTemplate window the parchment look: parchment where the grey rock background was,
-- and the frame's border warmed towards brown and gold.
function Theme.ApplyWindow(frame)
    if frame.encoreParchment then return frame.encoreParchment end
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
    if frame.Bg then
        bg:SetAllPoints(frame.Bg)
        frame.Bg:Hide()
    else
        bg:SetPoint("TOPLEFT", 2, -21)
        bg:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    Theme.SetParchment(bg)
    if frame.TopTileStreaks then frame.TopTileStreaks:Hide() end
    -- Border: the newer client draws it as a NineSlice, the older as separate textures. Warm gold-brown.
    local regions = {}
    if frame.NineSlice then
        for _, r in ipairs({ frame.NineSlice:GetRegions() }) do regions[#regions + 1] = r end
    end
    for _, key in ipairs({ "PortraitFrame", "TopRightCorner", "TopLeftCorner", "TopBorder", "BotLeftCorner",
        "BotRightCorner", "BottomBorder", "LeftBorder", "RightBorder", "TitleBg" }) do
        if frame[key] then regions[#regions + 1] = frame[key] end
    end
    for _, r in ipairs(regions) do
        if r.SetVertexColor then r:SetVertexColor(1, 0.86, 0.62) end
    end
    frame.encoreParchment = bg
    return bg
end

-- A thin frame of four lines round f.
function Theme.Border(f, c, a, layer, inset)
    local t = {}
    inset = inset or 0
    for i = 1, 4 do
        t[i] = f:CreateTexture(nil, layer or "BORDER")
        t[i]:SetColorTexture(c[1], c[2], c[3], a or 1)
    end
    t[1]:SetPoint("TOPLEFT", inset, -inset); t[1]:SetPoint("TOPRIGHT", -inset, -inset); t[1]:SetHeight(1)
    t[2]:SetPoint("BOTTOMLEFT", inset, inset); t[2]:SetPoint("BOTTOMRIGHT", -inset, inset); t[2]:SetHeight(1)
    t[3]:SetPoint("TOPLEFT", inset, -inset); t[3]:SetPoint("BOTTOMLEFT", inset, inset); t[3]:SetWidth(1)
    t[4]:SetPoint("TOPRIGHT", -inset, -inset); t[4]:SetPoint("BOTTOMRIGHT", -inset, inset); t[4]:SetWidth(1)
    return t
end

-- An inset pane on the parchment: a faint brown wash, a brown edge and a light inner edge, like the
-- recessed boxes in Blizzard's quest log.
function Theme.Well(f)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(Theme.WELL[1], Theme.WELL[2], Theme.WELL[3], 0.10)
    Theme.Border(f, Theme.EDGE, 0.75)
    Theme.Border(f, { 1, 0.96, 0.85 }, 0.35, "BORDER", 1)
    return bg
end

-- Parchment behind a BackdropTemplate popup with a tooltip edge.
function Theme.ApplyPopup(f)
    if f.SetBackdropColor then f:SetBackdropColor(1, 1, 1, 0) end
    if f.SetBackdropBorderColor then f:SetBackdropBorderColor(0.78, 0.58, 0.32, 1) end
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -5)
    bg:SetPoint("TOPLEFT", 4, -4)
    bg:SetPoint("BOTTOMRIGHT", -4, 4)
    Theme.SetParchment(bg)
    return bg
end
