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

---------------------------------------------------------------------------
-- Auction House look (Det, 2026-11-20): parchment window with the red border and title bar, and inside it
-- panes, rows and category buttons drawn with the game's own Auction House art (atlases the client ships
-- for its auction house). Where an atlas is missing, a plain colour stands in.
---------------------------------------------------------------------------
function Theme.HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- tex shows the atlas, or the colour { r, g, b, a } when the client lacks it. Returns true for the atlas.
function Theme.Atlas(tex, name, fallback)
    if Theme.HasAtlas(name) then
        tex:SetAtlas(name)
        return true
    end
    local c = fallback or { 0, 0, 0, 0 }
    tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return false
end

-- Dark pane colours, used for text inside the Auction House panes (the game's light colours).
Theme.AH = {
    GOLD = { 1, 0.82, 0 }, INK = { 0.95, 0.90, 0.81 }, DIM = { 0.64, 0.57, 0.47 },
    TEAL = { 0.07, 0.78, 0.78 }, TEAL_SOFT = { 0.48, 0.82, 0.80 }, COPPER = { 0.92, 0.58, 0.22 },
}

-- An Auction House pane: the AH's background art inside the thin gold inset border its panes use.
-- atlas: "auctionhouse-background-index" (item lists), "-categories" (category list), "-summarylist".
function Theme.AHPane(f, atlas)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    bg:SetPoint("TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    Theme.Atlas(bg, atlas or "auctionhouse-background-index", { 0.07, 0.05, 0.035, 0.94 })
    local ok = false
    if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
        local edge = CreateFrame("Frame", nil, f, "NineSlicePanelTemplate")
        edge:SetAllPoints()
        edge:SetFrameLevel(f:GetFrameLevel())
        ok = pcall(NineSliceUtil.ApplyLayoutByName, edge, "InsetFrameTemplate")
        if not ok then edge:Hide() end
    end
    if not ok then
        Theme.Border(f, { 0, 0, 0 }, 1)
        Theme.Border(f, { 0.72, 0.56, 0.30 }, 0.6, "BORDER", 1)
    end
    return bg
end

-- An Auction House list row: alternating stripe, hover glow and selection glow from the AH's own item list.
-- Returns the stripe and the selection textures; show the stripe on every other row.
function Theme.AHRow(row, inset)
    inset = inset or 0
    local stripe = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    stripe:SetPoint("TOPLEFT", 0, -inset); stripe:SetPoint("BOTTOMRIGHT", 0, inset)
    Theme.Atlas(stripe, "auctionhouse-rowstripe-1", { 1, 1, 1, 0.05 })
    local sel = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    sel:SetPoint("TOPLEFT", 0, -inset); sel:SetPoint("BOTTOMRIGHT", 0, inset)
    Theme.Atlas(sel, "auctionhouse-ui-row-select", { 1, 0.82, 0, 0.18 })
    sel:SetBlendMode("ADD")
    sel:Hide()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 0, -inset); hl:SetPoint("BOTTOMRIGHT", 0, inset)
    Theme.Atlas(hl, "auctionhouse-ui-row-highlight", { 1, 0.82, 0, 0.10 })
    hl:SetBlendMode("ADD")
    return stripe, sel
end

-- An Auction House category button (the gold-edged bars of the AH's category list).
-- Returns the button art and the selection glow (hidden; show it on the selected entry).
function Theme.AHNavButton(row, inset)
    inset = inset or 1
    local bg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("TOPLEFT", 0, -inset); bg:SetPoint("BOTTOMRIGHT", 0, inset)
    if not Theme.Atlas(bg, "auctionhouse-nav-button") then
        bg:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg")
        bg:SetTexCoord(0, 0.53125, 0, 0.625)
    end
    local sel = row:CreateTexture(nil, "ARTWORK", nil, -1)
    sel:SetAllPoints(bg)
    Theme.Atlas(sel, "auctionhouse-nav-button-select", { 1, 0.82, 0, 0.25 })
    sel:SetBlendMode("ADD")
    sel:Hide()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(bg)
    if not Theme.Atlas(hl, "auctionhouse-nav-button-highlight") then
        hl:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
    end
    hl:SetBlendMode("ADD")
    return bg, sel
end
