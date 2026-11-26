-- Encore-DB window: tabs across the top, a filter strip and three panes (browse tree | sections | items),
-- following docs/mockup/encore-db-mockup.html. Built on first open from the game's own templates.
-- Item details (name, quality, icon, item level, required level) come from the game when it has the item
-- cached; the stored data stands in until then. Drops, prices and Forever flags only exist in the stored data.
-- Data from ForeverDB.net (https://foreverdb.net); see NOTICE.txt.
local _, ns = ...
local Encore = _G.EncoreEssentials
local DB = ns.DB

local Loot = ns.Loot or { items = {}, instances = {}, vendors = {}, standing = {} }
local ITEMS = Loot.items or {}
-- Dungeons with wings become one entry per wing (Data\Wings.lua); Blackrock Spire only if the player chose it.
if ns.ApplyWings then ns.ApplyWings(Loot, ((Encore.db and Encore.db.settings or {}).dbWindow or {}).splitBRS == true) end
local Recipes = ns.Recipes or {}

-- Open World: rare and epic world drops, World Epics first, each by the level needed to use them.
-- One table, as the file is near Lua's limit of 200 file-level locals.
local World = {
    bands = {
        { text = "Any level", min = 0, max = 0 },
        { text = "Levels 1-10", min = 1, max = 10 }, { text = "Levels 11-20", min = 11, max = 20 },
        { text = "Levels 21-30", min = 21, max = 30 }, { text = "Levels 31-40", min = 31, max = 40 },
        { text = "Levels 41-50", min = 41, max = 50 }, { text = "Levels 51-60", min = 51, max = 60 },
    },
    -- cat: the quality a category starts at; World Epics also hold legendaries.
    cats = { { cat = 4, text = "World Epics" }, { cat = 3, text = "World Rares" } },
}
function World.catOf(id)
    local q = ITEMS[id] and ITEMS[id][2] or 0
    return q >= 4 and 4 or q == 3 and 3 or nil
end
function World.catText(cat)
    for _, c in ipairs(World.cats) do if c.cat == cat then return c.text end end
    return "World drops"
end
function World.bandOf(id)
    local it = ITEMS[id]
    local req = it and it[7] or 0
    for b, band in ipairs(World.bands) do
        if req >= band.min and req <= band.max then return b end
    end
    return #World.bands
end
function World.items(cat, b)
    if not World.byBand then
        World.byBand = { [3] = {}, [4] = {} }
        for _, id in ipairs(Loot.world or {}) do
            local c = World.catOf(id)
            if c then
                local k = World.bandOf(id)
                World.byBand[c][k] = World.byBand[c][k] or {}
                table.insert(World.byBand[c][k], id)
            end
        end
    end
    return World.byBand[cat] and World.byBand[cat][b] or {}
end
local RecipeSources = ns.RecipeSources or {}
local RecipeNames = ns.RecipeNames or {}

local DEFAULT_W, DEFAULT_H = 1100, 660
local MIN_W, MIN_H = 1000, 560
local TREE_W, SEC_W = 210, 300
local PANE_TOP, PANE_BOTTOM = -98, 34
local TILE_GAP, COL_GAP, NAME_MIN = 12, 6, 110
-- Item icon sizes in the item grid (pixels); "normal" is twice "small", "large" three times.
local ICON_SIZES = { small = 18, normal = 36, large = 54 }
local ICON_SIZE_OPTIONS = { { "small", "Small" }, { "normal", "Normal" }, { "large", "Large" } }
local POPUP_W = 340
local ICONS = "Interface\\Icons\\"
-- Texture paths, in one table: this file is near Lua's limit of 200 file-level locals.
local TEX = {
    crest = "Interface\\AddOns\\EncoreEssentials\\Media\\encore-crest",
    skull = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    portraitMask = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
    portraitPath = "Interface\\AddOns\\EncoreEssentials_DB\\Media\\Portraits\\",
    -- The target frame's silver rare dragon, cut to the part around its portrait (64 px portrait at 126, 12 in the
    -- frame's 232 x 100 area, which starts 24 px into the 256 x 128 file). Drawn around our boss portrait (portraitSize).
    rare = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare",
    rareCoords = { 148 / 256, 1, 0, 100 / 128 }, -- from 2 px left of the portrait to the frame's right edge
    portraitSize = 60, -- boss portraits in the boss list, in pixels
    questionMark = 134400, -- Interface\Icons\INV_Misc_QuestionMark
    -- The target frame's level circle (centre at 203, 66 in the 256 x 128 file, about 26 px across). The rare
    -- dragon has the same circle in the same place, so rare rows only get the number.
    level = "Interface\\TargetingFrame\\UI-TargetingFrame",
    levelCoords = { 190 / 256, 216 / 256, 53 / 128, 79 / 128 },
}

-- The level badge on a boss portrait: the number in the level circle, coloured like the target frame's by how it
-- compares with the player's level, or the skull for a boss-level mob (level -1). Nothing when the level is unknown.
function ns.SetLevelBadge(row, level, rare)
    local known = level ~= nil
    row.levelRing:SetShown(known and not rare)
    row.levelSkull:SetShown(known and level < 0)
    row.levelText:SetShown(known and level >= 0)
    if known and level >= 0 then
        row.levelText:SetText(level)
        local color = (GetCreatureDifficultyColor or GetQuestDifficultyColor)
        local c = color and color(level)
        if c then row.levelText:SetTextColor(c.r, c.g, c.b) else row.levelText:SetTextColor(1, 0.82, 0) end
    end
end

-- Item flags in Loot.lua
local F_NEW, F_RECIPE, F_QUEST, F_CHANGED = 1, 2, 4, 8

-- Colours from the mock-up
local TEAL = { 0.07, 0.78, 0.78 }
local TEAL_SOFT = { 0.48, 0.82, 0.80 }
local COPPER = { 0.92, 0.58, 0.22 }
local GOLD = { 1, 0.82, 0 }
local INK = { 0.95, 0.90, 0.81 }
local DIM = { 0.64, 0.57, 0.47 }
local TAB_INK = { 0.84, 0.73, 0.54 }
local TEAL_HEX = "|cff7ad1cc"

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
local GetItemIconByID = (C_Item and C_Item.GetItemIconByID) or _G.GetItemIcon
local GetSpellTexture = (C_Spell and C_Spell.GetSpellTexture) or _G.GetSpellTexture

local frame, treeList, secList, lootList, statusText, searchBox, legend, legendGem, popup
local qualityDropdown, slotDropdown
local tabButtons = {}
local renderAll, renderLoot, renderSections, hidePopup, queuePortrait, openOptions

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local state = {
    tab = "dungeons",
    sort = { key = nil, desc = false }, -- item lists: column clicked to sort by (nil = the list's own order)
    quality = 0, -- lowest quality shown
    slot = "", -- "", "armor", "weapon", "jewel", "other"
    highlight = 1, -- 1 default, 2 highlight Forever changes and additions, 3 Forever only
    search = "",
    collapsed = {}, -- tree headers closed by the player
    inst = nil, boss = 1, -- Dungeons & Raids
    prof = nil, bracket = 1, -- Professions: a skill bracket (1 = all recipes), a category key (ProfessionView.lua) or "sets"
    repOpen = {}, -- Reputations: [item group] = false once the player closes it
    vendor = {}, standing = nil, -- PvP and Reputations: vendor index per tab, standing shown
    iconSize = "normal", -- item icon size: "small", "normal" or "large"
    randomOpen = {}, -- [instance/boss] = true or false once the player opens or closes its random drops
    recipesOpen = {}, -- [instance] = true or false once the player opens or closes its shared recipe drops
    band = 1, worldQuality = 4, -- Open World: level range and category shown (4 = World Epics, 3 = World Rares)
}

local function settings()
    local s = Encore.db and Encore.db.settings
    if not s then return {} end
    if type(s.dbWindow) ~= "table" then s.dbWindow = {} end
    return s.dbWindow
end

local function highlightOn() return state.highlight >= 2 end
local function foreverOnly() return state.highlight == 3 end

local function iconPx() return ICON_SIZES[state.iconSize] or ICON_SIZES.normal end
-- Width from a cell's left edge to its name: the icon, its 1 px quality edge and some space.
local function iconW() return iconPx() + 10 end

---------------------------------------------------------------------------
-- Item details
---------------------------------------------------------------------------
local function hasFlag(flags, f)
    return flags ~= nil and bit.band(flags, f) ~= 0
end

local function isForever(flags)
    return hasFlag(flags, F_NEW) or hasFlag(flags, F_CHANGED)
end

local function qualityColor(q)
    q = q or 1
    if C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(q)
        if r then return r, g, b end
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- The game's weapon and armour types are long ("One-Handed Swords"); show them like the stored data ("Sword").
local SHORT_KIND = { Staves = "Staff", ["Fist Weapons"] = "Fist Weapon", Miscellaneous = false, Thrown = "Thrown" }
local function shortKind(classID, sub)
    if not sub or sub == "" or (classID ~= 2 and classID ~= 4) then return nil end
    local s = sub:gsub("^One%-Handed ", ""):gsub("^Two%-Handed ", "")
    local short = SHORT_KIND[s]
    if short == false then return nil end
    return short or (s:gsub("s$", ""))
end

-- Enchants, armor kits, oils, sharpening stones, weightstones, scopes and the like.
local ENHANCEMENT_NAMES = { "Armor Kit$", "Sharpening Stone$", "Weightstone$", " Scope$", "Shield Spike$", " Spurs$", "Counterweight$" }
local function isEnhancement(name, classID, sub)
    if classID == 8 or sub == "Item Enhancement" then return true end
    if not name then return false end
    for _, p in ipairs(ENHANCEMENT_NAMES) do
        if name:find(p) then return true end
    end
    return name:find(" Oil$") ~= nil and not name:find(" of Oil$")
end

-- Ask the server once for items the game has not cached; GET_ITEM_INFO_RECEIVED redraws when they arrive.
local requested = {}
local function requestItem(id)
    if requested[id] then return end
    requested[id] = true
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end

-- name, quality, icon, slot, kind (armour or weapon type), ilvl, req, flags, type (Type column)
local function itemInfo(id)
    local it = ITEMS[id]
    local gName, _, gQuality, gLevel, gReq, _, _, _, _, gIcon = GetItemInfo(id)
    if not gName then requestItem(id) end
    local _, iType, iSub, equipLoc, iIcon, classID
    if GetItemInfoInstant then _, iType, iSub, equipLoc, iIcon, classID = GetItemInfoInstant(id) end
    local info = {}
    info.name = gName or (it and it[1]) or RecipeNames[id] or ("Item " .. id)
    info.quality = gQuality or (it and it[2]) or 1
    info.icon = gIcon or iIcon or (it and it[3] and (ICONS .. it[3])) or GetItemIconByID(id) or TEX.questionMark
    info.ilvl = gLevel or (it and it[6])
    if gName then
        info.req = (gReq and gReq > 1) and gReq or nil
    else
        info.req = it and it[7]
    end
    local slot = it and it[4]
    if not slot and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
        local text = _G[equipLoc]
        if type(text) == "string" and text ~= "" then slot = text end
    end
    info.slot = slot
    info.kind = (it and it[5]) or shortKind(classID, iSub)
    info.flags = (it and it[8]) or 0
    if info.kind then
        info.type = info.kind
    elseif isEnhancement(info.name, classID, iSub) then
        info.type = "Enhancement"
    elseif hasFlag(info.flags, F_RECIPE) or classID == 9 then
        info.type = "Recipe"
    elseif hasFlag(info.flags, F_QUEST) or classID == 12 then
        info.type = "Quest item"
    elseif not slot and iSub and iSub ~= "" and iSub ~= "Other" and iSub ~= "Junk" then
        info.type = iSub
    elseif not slot then
        info.type = iType
    end
    return info
end

local function itemName(id)
    return (GetItemInfo(id)) or (ITEMS[id] and ITEMS[id][1]) or RecipeNames[id] or ("Item " .. id)
end

local function itemExists(id)
    return id and not (C_Item and C_Item.DoesItemExistByID and not C_Item.DoesItemExistByID(id))
end

-- A loot list entry is an item ID or { itemID, chance }.
local function entryOf(e)
    if type(e) == "table" then return e[1], e[2] end
    return e, nil
end

local JEWEL = { Neck = true, Finger = true, Trinket = true }
local WEAPON = { ["One-Hand"] = true, ["Two-Hand"] = true, ["Main Hand"] = true, Ranged = true, Thrown = true, Relic = true }
local OTHER = { Tabard = true, Shirt = true, Bag = true }
local function slotGroup(slot, kind)
    if not slot or OTHER[slot] then return "other" end
    if JEWEL[slot] then return "jewel" end
    if WEAPON[slot] or (slot == "Off Hand" and kind ~= "Shield") then return "weapon" end
    return "armor"
end

local function passesInfo(info)
    if foreverOnly() and not isForever(info.flags) then return false end
    if info.quality < state.quality then return false end
    if state.slot ~= "" and slotGroup(info.slot, info.kind) ~= state.slot then return false end
    return true
end

local function coin(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return copper .. "c"
end

local function standingLabel(n)
    return _G["FACTION_STANDING_LABEL" .. n] or (Loot.standing and Loot.standing[n]) or tostring(n)
end

-- Vendor standings are 4..8 or "r<PvP rank>".
local function standingText(s)
    if type(s) == "number" then return standingLabel(s) end
    if s == "q" then return "Quest reward" end
    if type(s) == "string" then return "PvP rank " .. (s:match("%d+") or s) end
    return ""
end

local function factionName(id)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local data = C_Reputation.GetFactionDataByID(id)
        if data and data.name then return data.name end
    end
    if GetFactionInfoByID then
        local name = GetFactionInfoByID(id)
        if name then return name end
    end
    return "faction " .. id
end

local function mapName(map)
    local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    return info and info.name
end

local function fmtChance(c)
    if not c then return nil end
    if c < 1 then return ("%.2f%%"):format(c) end
    return ("%.1f%%"):format(c)
end

-- One entry in an item grid.
local function cellFromInfo(id, info, extra)
    local c = {
        id = id, name = info.name, quality = info.quality, icon = info.icon,
        ilvl = info.ilvl and tostring(info.ilvl), req = info.req and tostring(info.req),
        slot = info.slot, type = info.type,
        isNew = hasFlag(info.flags, F_NEW), changed = hasFlag(info.flags, F_CHANGED),
    }
    if extra then
        for k, v in pairs(extra) do c[k] = v end
    end
    return c
end

local function heading(text) return { kind = "heading", text = text } end
local function textLine(text) return { kind = "text", text = text } end
local function emptyLine(text) return { kind = "empty", text = text } end

---------------------------------------------------------------------------
-- Precomputed counts (the teal counters: items new or changed in Forever)
---------------------------------------------------------------------------
local function storedForever(id)
    local it = ITEMS[id]
    return it ~= nil and isForever(it[8])
end

-- [instance] = { items, forever, bosses = { [boss] = { items, forever } } }, counted on first use
-- (the instance list changes when dungeons are split into wings).
local stats = setmetatable({}, { __index = function(stats, inst)
    local s = { items = 0, forever = 0, bosses = {} }
    for b, boss in ipairs(inst.bosses or {}) do
        local bs = { items = 0, forever = 0 }
        for _, e in ipairs(boss.items or {}) do
            local id = entryOf(e)
            bs.items = bs.items + 1
            if storedForever(id) then bs.forever = bs.forever + 1 end
        end
        s.items, s.forever = s.items + bs.items, s.forever + bs.forever
        s.bosses[b] = bs
    end
    rawset(stats, inst, s)
    return s
end })

local function vendorForever(v)
    local n = 0
    for _, e in ipairs(v.items or {}) do
        if storedForever(e[1]) then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------
local function recipeLevel(r) return r[3] or r[4] or r.level or 0 end
local sortedRecipes = {}
local function recipesOf(prof)
    if sortedRecipes[prof] then return sortedRecipes[prof] end
    local list = {}
    for _, r in ipairs(Recipes[prof] or {}) do list[#list + 1] = r end
    table.sort(list, function(a, b)
        local la, lb = recipeLevel(a), recipeLevel(b)
        if la ~= lb then return la < lb end
        local na, nb = a[2] or "", b[2] or ""
        if na ~= nb then return na < nb end
        return (a[1] or 0) < (b[1] or 0)
    end)
    sortedRecipes[prof] = list
    return list
end

local PROF_GROUPS = {
    { key = "crafting", text = "Professions", list = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring" } },
    { key = "secondary", text = "Gathering and secondary", list = { "Cooking", "First Aid", "Fishing", "Herbalism", "Mining", "Skinning" } },
}

local PROF_ICONS = {
    Alchemy = "Trade_Alchemy", Blacksmithing = "Trade_BlackSmithing", Enchanting = "Trade_Engraving",
    Engineering = "Trade_Engineering", Leatherworking = "INV_Misc_ArmorKit_17", Tailoring = "Trade_Tailoring",
    Herbalism = "Spell_Nature_NatureTouchGrow", Mining = "Trade_Mining", Skinning = "INV_Misc_Pelt_Wolf_01",
    Cooking = "INV_Misc_Food_15", ["First Aid"] = "Spell_Holy_SealOfSacrifice", Fishing = "Trade_Fishing",
}

local SKILL_BRACKETS = {
    { text = "All recipes", min = -1, max = 100000 },
    { text = "Apprentice", sub = "Skill 1-74", min = -1, max = 74 },
    { text = "Journeyman", sub = "Skill 75-149", min = 75, max = 149 },
    { text = "Expert", sub = "Skill 150-224", min = 150, max = 224 },
    { text = "Artisan", sub = "Skill 225-299", min = 225, max = 299 },
    { text = "Beyond Artisan", sub = "Skill 300 and up", min = 300, max = 100000 },
}

local function inBracket(r, b)
    local lv = recipeLevel(r)
    return lv >= b.min and lv <= b.max
end

-- The skill a recipe is learned at; the data stores 0 for recipes you can learn at skill 1.
local function learnSkill(r)
    if not r[3] then return "?" end
    return tostring(math.max(1, r[3]))
end

local function skillText(r)
    if r.level and not r[3] then return ("|cffff8040Level %d|r"):format(r.level) end
    return ("|cffff8040%s|r |cffffff00%d|r |cff40bf40%d|r |cff9d9d9d%d|r"):format(learnSkill(r), r[4] or 0, r[5] or 0, r[6] or 0)
end

-- "Enchant Bracer - Agility" -> "Bracer"
local function enchantSlot(r)
    return r[2] and r[2]:match("^Enchant (.-) %- ")
end
local ENCHANT_WEAPON = { Weapon = true, ["2H Weapon"] = true }

local function recipeCell(r, prof)
    local makes = r[7]
    local c
    if makes then
        local info = itemInfo(makes)
        c = cellFromInfo(makes, info)
        c.info = info
        if c.icon == TEX.questionMark and GetSpellTexture then c.icon = GetSpellTexture(r[1]) or c.icon end
    else
        c = { spell = r[1], quality = 1, slot = enchantSlot(r), type = "Enhancement",
            icon = (GetSpellTexture and GetSpellTexture(r[1])) or TEX.questionMark }
    end
    c.name = r[2] or c.name or ("Spell " .. r[1])
    if r[8] and r[8] > 1 then c.name = c.name .. " |cffc8b898x" .. r[8] .. "|r" end
    c.skill = skillText(r)
    c.sortv = { skill = r[3] or r.level or 9999 }
    if type(r[10]) == "number" then c.recipeItem = r[10] end -- learned from this recipe item
    c.isNew, c.changed = r.new == true, r.changed == true
    c.recipe = r
    if prof then c.from = prof end
    return c
end

local function passesRecipe(r, c)
    if foreverOnly() and not (r.new or r.changed) then return false end
    if c.info then
        if c.info.quality < state.quality then return false end
        if state.slot ~= "" and slotGroup(c.info.slot, c.info.kind) ~= state.slot then return false end
    elseif state.slot ~= "" then
        local s = c.slot
        local group = (not s and "other") or (ENCHANT_WEAPON[s] and "weapon") or "armor"
        if group ~= state.slot then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- Where an item comes from (search results)
---------------------------------------------------------------------------
local whereIndex, lowerNames
local function buildIndexes()
    whereIndex, lowerNames = {}, {}
    for id, it in pairs(ITEMS) do lowerNames[id] = (it[1] or ""):lower() end
    for pass = 1, 2 do
        for i, inst in ipairs(Loot.instances or {}) do
            for b, boss in ipairs(inst.bosses or {}) do
                local list
                if pass == 1 then list = boss.items else list = boss.also end
                for _, e in ipairs(list or {}) do
                    local id = entryOf(e)
                    if not whereIndex[id] then
                        whereIndex[id] = { text = boss.name .. ", " .. inst.name, tab = "dungeons", inst = i, boss = b }
                    end
                end
            end
        end
    end
    for i, inst in ipairs(Loot.instances or {}) do
        for _, id in ipairs(inst.recipes or {}) do
            if not whereIndex[id] then
                whereIndex[id] = { text = "Any boss, " .. inst.name, tab = "dungeons", inst = i, boss = 1 }
            end
        end
    end
    for _, id in ipairs(Loot.world or {}) do
        if not whereIndex[id] then whereIndex[id] = { text = "World drop", tab = "world", world = id } end
    end
    for v, vendor in ipairs(Loot.vendors or {}) do
        for _, e in ipairs(vendor.items or {}) do
            if not whereIndex[e[1]] then
                whereIndex[e[1]] = { text = vendor.name, tab = vendor.kind == "pvp" and "pvp" or "reputations", vendor = v }
            end
        end
    end
    if ns.CollectionsView then ns.CollectionsView.index(whereIndex) end
end

local function clearSearch()
    state.search = ""
    if searchBox and searchBox:GetText() ~= "" then searchBox:SetText("") end
end

local function selectTab(key)
    state.tab = key
    state.standing = nil
    settings().tab = key
    clearSearch()
    renderAll()
end

local function goTo(w)
    if w.tab == "dungeons" then
        state.inst, state.boss = w.inst, w.boss
    elseif w.tab == "world" then
        state.band, state.worldQuality = World.bandOf(w.world), World.catOf(w.world) or 4
    elseif w.tab == "collections" then
        if ns.CollectionsView then ns.CollectionsView.goTo(w) end
    else
        state.vendor[w.tab] = w.vendor
    end
    selectTab(w.tab)
end

---------------------------------------------------------------------------
-- Recipe popup contents
---------------------------------------------------------------------------
local function setPin(map, x, y, label)
    local zone = mapName(map) or "?"
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(map) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        Encore:Print("Map pin set: %s, %s (%.1f, %.1f).", label, zone, x, y)
    else
        Encore:Print("%s: %s (%.1f, %.1f).", label, zone, x, y)
    end
    -- Open the world map on that zone so the pin is in view.
    if WorldMapFrame and not (InCombatLockdown and InCombatLockdown()) then
        if OpenWorldMap then
            pcall(OpenWorldMap, map)
        else
            if not WorldMapFrame:IsShown() then
                if ToggleWorldMap then pcall(ToggleWorldMap) else pcall(ShowUIPanel, WorldMapFrame) end
            end
            if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, map) end
        end
    end
end

-- Text for one recipe source, and a click action when it has map coordinates.
local function sourceText(s)
    local t = s.type
    local text, onClick
    if t == "vendor" then
        text = "Sold by |cffffffff" .. (s.name or "a vendor") .. "|r"
        local zone = mapName(s.map) or s.where
        if zone then text = text .. " in " .. zone end
        if s.x and s.y then
            text = text .. (" (%.1f, %.1f)"):format(s.x, s.y)
            if s.map then
                local name, map, x, y = s.name or "Vendor", s.map, s.x, s.y
                onClick = function() setPin(map, x, y, name) end
            end
        end
        if s.side == "A" then text = text .. ", Alliance" elseif s.side == "H" then text = text .. ", Horde" end
        if s.price then text = text .. "  ·  " .. coin(s.price) end
        if s.limited then text = text .. "  ·  limited supply" end
    elseif t == "drop" then
        if s.name then
            text = "Drops from |cffffffff" .. s.name .. "|r"
            if s.sources and s.sources > 1 then text = text .. (" and %d other creatures"):format(s.sources - 1) end
        else
            text = "Drops from creatures"
        end
        if s.where then text = text .. " in " .. s.where end
        if s.rate then text = text .. "  ·  " .. s.rate end
    elseif t == "quest" then
        text = "Quest reward" .. (s.name and (": |cffffffff" .. s.name .. "|r") or "")
    elseif t == "reputation" then
        text = "Reputation: |cffffffff" .. (s.name or "?") .. "|r, " .. (s.standing and standingLabel(s.standing) or "?")
    elseif t == "seen" then
        text = ("Players saw it drop %d times (%d players)"):format(s.drops or 0, s.players or 0)
    elseif t == "container" then
        text = "Found in |cffffffff" .. (s.name or "a container") .. "|r"
        if s.rate then text = text .. "  ·  " .. s.rate end
    else
        text = tostring(t or "Source") .. (s.name and (": " .. s.name) or "")
    end
    if s.from then text = text .. "  |cff9d9d9d(" .. s.from .. ")|r" end
    if onClick then text = text .. "  " .. TEAL_HEX .. "[map pin]|r" end
    return text, onClick
end

local function recipePopupEntries(r)
    local e = {}
    local cell = recipeCell(r)
    local qr, qg, qb = qualityColor(cell.quality)
    e[#e + 1] = { icon = cell.icon, iconSize = 24, text = r[2] or "?", font = "GameFontNormalLarge", color = { qr, qg, qb },
        itemID = r[7], after = 6 }
    if highlightOn() and r.new then
        e[#e + 1] = { text = "New in WoW Forever", color = TEAL_SOFT }
    elseif highlightOn() and r.changed then
        e[#e + 1] = { text = "Changed in WoW Forever", color = TEAL_SOFT }
    end
    if r.level and not r[3] then
        e[#e + 1] = { text = ("Learned at level |cffff8040%d|r."):format(r.level), color = DIM }
    else
        e[#e + 1] = { text = ("Learned at |cffff8040%s|r.  Turns |cffffff00yellow|r at %d, |cff40bf40green|r at %d, |cff9d9d9dgrey|r at %d.")
            :format(learnSkill(r), r[4] or 0, r[5] or 0, r[6] or 0), color = DIM }
    end
    if r[8] and r[8] > 1 then e[#e + 1] = { text = ("Makes %d."):format(r[8]), color = DIM } end

    e[#e + 1] = { text = "Reagents", font = "GameFontNormal", color = GOLD, gap = 6 }
    local reagents = r[9]
    if type(reagents) == "table" and #reagents > 0 then
        for i = 1, #reagents, 2 do
            local id, n = reagents[i], reagents[i + 1]
            if id then
                local info = itemInfo(id)
                local rr, rg, rb = qualityColor(info.quality)
                e[#e + 1] = { icon = info.icon, text = info.name .. "  |cffffffffx" .. (n or 1) .. "|r", color = { rr, rg, rb }, itemID = id }
            end
        end
    else
        e[#e + 1] = { text = "No reagents.", color = DIM }
    end

    e[#e + 1] = { text = "How to learn it", font = "GameFontNormal", color = GOLD, gap = 6 }
    local l = r[10]
    if l == "t" then
        e[#e + 1] = { text = (r.level and not r[3] and "From the rogue trainer" or "From a profession trainer") .. (r.trainerCost and (" for " .. coin(r.trainerCost)) or "") .. "." }
    elseif l == "a" then
        e[#e + 1] = { text = "Learned automatically with the profession." }
    elseif type(l) == "number" then
        local info = itemInfo(l)
        local rr, rg, rb = qualityColor(info.quality)
        e[#e + 1] = { icon = info.icon, text = info.name, color = { rr, rg, rb }, itemID = l }
        if r.notInClient then e[#e + 1] = { text = "This recipe item is not in the game client yet.", color = DIM } end
        local sources = RecipeSources[l]
        if sources and #sources > 0 then
            for _, s in ipairs(sources) do
                local text, onClick = sourceText(s)
                e[#e + 1] = { text = text, onClick = onClick }
            end
        else
            e[#e + 1] = { text = "No source has been seen in WoW Forever yet.", color = DIM }
        end
    else
        e[#e + 1] = { text = "How it is learned is not known yet.", color = DIM }
    end
    if r.favor then e[#e + 1] = { text = ("Costs %d Merchant's Favor."):format(r.favor) } end
    if r.faction then e[#e + 1] = { text = "Needs reputation with |cffffffff" .. factionName(r.faction) .. "|r." } end
    return e
end

---------------------------------------------------------------------------
-- Tabs and what fills them
---------------------------------------------------------------------------
local TABS = {
    { key = "dungeons", text = "Dungeons & Raids" },
    { key = "world", text = "Open World" },
    { key = "professions", text = "Professions" },
    { key = "pvp", text = "PvP", vendorKind = "pvp" },
    { key = "reputations", text = "Reputations", vendorKind = "faction" },
    -- World Events comes back when WoW Forever runs its first events (no event loot is shown until then).
    { key = "collections", text = "Collections" },
}
local TAB_BY_KEY = {}
for _, t in ipairs(TABS) do TAB_BY_KEY[t.key] = t end

local DUNGEON_GROUPS = {
    { key = "low", text = "Dungeons, levels 13-24", test = function(i) return i.kind ~= "raid" and i.levels and i.levels[1] and i.levels[1] < 25 end },
    { key = "mid", text = "Dungeons, levels 25-39", test = function(i) return i.kind ~= "raid" and i.levels and i.levels[1] and i.levels[1] >= 25 and i.levels[1] < 40 end },
    { key = "high", text = "Dungeons, levels 40-60", test = function(i) return i.kind ~= "raid" and i.levels and i.levels[1] and i.levels[1] >= 40 end },
    { key = "other", text = "Other dungeons", test = function(i) return i.kind ~= "raid" and not (i.levels and i.levels[1]) end },
    { key = "raids", text = "Raids", test = function(i) return i.kind == "raid" end },
}

local SIDES = {
    { key = "A", text = "Alliance" },
    { key = "H", text = "Horde" },
    { key = false, text = "Both factions" },
}

local function levelText(inst)
    if inst.kind == "raid" then return (inst.size or "?") .. "-player" end
    local lv = inst.levels
    if not (lv and lv[1]) then return "" end
    return lv[2] and (lv[1] .. "-" .. lv[2]) or tostring(lv[1])
end

local function firstInstance()
    for _, g in ipairs(DUNGEON_GROUPS) do
        for i, inst in ipairs(Loot.instances or {}) do
            if g.test(inst) then return i end
        end
    end
end

local function vendorsIn(kind, side)
    local list = {}
    for v, vendor in ipairs(Loot.vendors or {}) do
        if vendor.kind == kind and (vendor.side or false) == side then list[#list + 1] = v end
    end
    return list
end

local function firstVendor(kind)
    for _, s in ipairs(SIDES) do
        local list = vendorsIn(kind, s.key)
        if list[1] then return list[1] end
    end
end

local function firstProfession()
    for _, g in ipairs(PROF_GROUPS) do
        for _, p in ipairs(g.list) do
            if Recipes[p] then return p end
        end
    end
end

-- Tree: a header row per group, then its entries.
local function treeRows()
    local rows = {}
    local tab = TAB_BY_KEY[state.tab]
    local function group(key, text, entries)
        if #entries == 0 then return end
        local open = not state.collapsed[key]
        rows[#rows + 1] = { kind = "cat", text = text, open = open, onClick = function()
            state.collapsed[key] = open or nil
            renderAll()
        end }
        if open then
            for _, e in ipairs(entries) do rows[#rows + 1] = e end
        end
    end
    local function pick()
        state.standing = nil
        clearSearch()
        renderAll()
    end

    if state.tab == "dungeons" then
        for _, g in ipairs(DUNGEON_GROUPS) do
            local entries = {}
            for i, inst in ipairs(Loot.instances or {}) do
                if g.test(inst) then
                    entries[#entries + 1] = {
                        kind = "leaf", text = inst.name, right = levelText(inst), pip = stats[inst].forever,
                        isNew = inst.new, selected = state.inst == i,
                        onClick = function() state.inst, state.boss = i, 1; pick() end,
                    }
                end
            end
            group(g.key, g.text, entries)
        end
    elseif state.tab == "world" then
        for _, c in ipairs(World.cats) do
            local entries = {}
            for b, band in ipairs(World.bands) do
                local list = World.items(c.cat, b)
                if #list > 0 then
                    local n = 0
                    for _, id in ipairs(list) do if storedForever(id) then n = n + 1 end end
                    entries[#entries + 1] = {
                        kind = "leaf", text = band.text, right = tostring(#list), pip = n,
                        selected = state.band == b and state.worldQuality == c.cat,
                        onClick = function() state.band, state.worldQuality = b, c.cat; pick() end,
                    }
                end
            end
            group("world" .. c.cat, c.text, entries)
        end
    elseif state.tab == "professions" then
        for _, g in ipairs(PROF_GROUPS) do
            local entries = {}
            for _, p in ipairs(g.list) do
                if Recipes[p] then
                    local n = 0
                    for _, r in ipairs(Recipes[p]) do if r.new or r.changed then n = n + 1 end end
                    entries[#entries + 1] = {
                        kind = "leaf", text = p, right = tostring(#Recipes[p]), pip = n, selected = state.prof == p,
                        icon = ICONS .. (PROF_ICONS[p] or "INV_Misc_QuestionMark"),
                        onClick = function() state.prof, state.bracket = p, 1; pick() end,
                    }
                end
            end
            group(g.key, g.text, entries)
        end
    elseif tab and tab.vendorKind then
        for _, s in ipairs(SIDES) do
            local entries = {}
            for _, v in ipairs(vendorsIn(tab.vendorKind, s.key)) do
                local vendor = Loot.vendors[v]
                entries[#entries + 1] = {
                    kind = "leaf", text = vendor.name, right = tostring(#(vendor.items or {})), pip = vendorForever(vendor),
                    selected = state.vendor[state.tab] == v,
                    onClick = function() state.vendor[state.tab] = v; pick() end,
                }
            end
            group(tab.vendorKind .. tostring(s.key), s.text, entries)
        end
    elseif state.tab == "collections" and ns.CollectionsView then
        for _, g in ipairs(ns.CollectionsView.tree(pick)) do group(g.key, g.text, g.entries) end
    end
    return rows
end

local function vendorStandings(vendor)
    local keys, seen = {}, {}
    for _, e in ipairs(vendor.items or {}) do
        local s = e[2]
        if s ~= nil and not seen[s] then
            seen[s] = true
            keys[#keys + 1] = s
        end
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta == "number" end
        if ta == "number" then return a < b end
        return (tonumber(a:match("%d+")) or 0) < (tonumber(b:match("%d+")) or 0)
    end)
    return keys
end

-- Middle column: bosses, skill brackets or standings.
local function sectionRows()
    local rows = {}
    local tab = TAB_BY_KEY[state.tab]
    if state.tab == "dungeons" then
        local inst = state.inst and Loot.instances[state.inst]
        if not inst then return rows end
        local meta = {}
        meta[#meta + 1] = inst.kind == "raid" and "Raid" or "Dungeon"
        if inst.size then meta[#meta + 1] = inst.size .. " players" end
        if inst.levels and inst.levels[1] then meta[#meta + 1] = "levels " .. levelText(inst) end
        if inst.new and highlightOn() then meta[#meta + 1] = TEAL_HEX .. "New in WoW Forever|r" end
        rows[#rows + 1] = { kind = "head", title = inst.name, meta = table.concat(meta, "  ·  ") }
        -- The instance's quests and quest chains (QuestView.lua), above the bosses.
        local quests = DB.Quests and DB.Quests:ForInstance(inst)
        if quests and quests.count > 0 then
            rows[#rows + 1] = {
                kind = "sec", text = "Quests",
                sub = quests.count .. (quests.count == 1 and " quest" or " quests")
                    .. (quests.chains > 0 and ("  ·  %d %s"):format(quests.chains, quests.chains == 1 and "chain" or "chains") or ""),
                npc = false, badge = "Interface\\GossipFrame\\AvailableQuestIcon", selected = state.boss == "quests",
                onClick = function() state.boss = "quests"; clearSearch(); renderAll() end,
            }
        end
        local bossRows = {}
        for b, boss in ipairs(inst.bosses or {}) do
            local bs = stats[inst].bosses[b]
            local sub = bs.items .. (bs.items == 1 and " item" or " items")
            if boss.kills then sub = sub .. ("  ·  %d kills seen"):format(boss.kills) end
            bossRows[b] = (ns.BossAttach and ns.BossAttach[boss.name]) and false or {
                kind = "sec", text = boss.name, sub = sub, pip = bs.forever, selected = state.boss == b, npc = boss.npc or false, boss = boss, rare = boss.rare, level = boss.level,
                onClick = function() state.boss = b; clearSearch(); renderAll() end,
            }
        end
        -- Instances with wings (Data\Wings.lua) get a heading per wing; bosses no wing names
        -- (trash, rare spawns we have not placed) follow under "Other".
        local wings = ns.Wings and ns.Wings[inst.key]
        if wings then
            local wingOf = {}
            for w, wing in ipairs(wings) do
                for _, name in ipairs(wing.bosses) do wingOf[name] = w end
            end
            local function addGroup(title, pick)
                local first = true
                for b, boss in ipairs(inst.bosses or {}) do
                    if bossRows[b] and pick(boss) then
                        if first then rows[#rows + 1] = { kind = "heading", text = title }; first = false end
                        rows[#rows + 1] = bossRows[b]
                    end
                end
            end
            for w, wing in ipairs(wings) do
                addGroup(wing.name, function(boss) return not boss.trash and wingOf[boss.name] == w end)
            end
            addGroup("Other", function(boss) return not boss.trash and not wingOf[boss.name] end)
            for b, boss in ipairs(inst.bosses or {}) do
                if boss.trash and bossRows[b] then rows[#rows + 1] = bossRows[b] end
            end
        else
            for _, r in ipairs(bossRows) do if r then rows[#rows + 1] = r end end
        end
    elseif state.tab == "world" then
        local band = World.bands[state.band]
        if not band then return rows end
        rows[#rows + 1] = { kind = "head", title = World.catText(state.worldQuality), meta = band.text .. "  ·  dropped by creatures in the open world" }
        for _, c in ipairs(World.cats) do
            local n = #World.items(c.cat, state.band)
            if n > 0 then
                rows[#rows + 1] = {
                    kind = "sec", text = c.text, sub = n .. (n == 1 and " item" or " items"), selected = state.worldQuality == c.cat,
                    onClick = function() state.worldQuality = c.cat; clearSearch(); renderAll() end,
                }
            end
        end
    elseif state.tab == "professions" then
        ns.ProfessionView.sections(rows)
    elseif tab and tab.vendorKind then
        local v = state.vendor[state.tab]
        local vendor = v and Loot.vendors[v]
        if not vendor then return rows end
        local side = vendor.side == "A" and "Alliance" or vendor.side == "H" and "Horde" or "Both factions"
        rows[#rows + 1] = { kind = "head", title = vendor.name,
            meta = side .. "  ·  " .. (vendor.kind == "pvp" and "PvP rewards" or "Reputation rewards") }
        rows[#rows + 1] = {
            kind = "sec", text = "All standings", sub = #(vendor.items or {}) .. " items", pip = vendorForever(vendor),
            selected = state.standing == nil,
            onClick = function() state.standing = nil; clearSearch(); renderAll() end,
        }
        for _, s in ipairs(vendorStandings(vendor)) do
            local n = 0
            for _, e in ipairs(vendor.items) do if e[2] == s then n = n + 1 end end
            rows[#rows + 1] = {
                kind = "sec", text = standingText(s), sub = n .. (n == 1 and " item" or " items"), selected = state.standing == s,
                onClick = function() state.standing = s; clearSearch(); renderAll() end,
            }
        end
    elseif state.tab == "collections" and ns.CollectionsView then
        ns.CollectionsView.sections(rows)
    end
    return rows
end

---------------------------------------------------------------------------
-- Right pane contents: blocks of headings, text and item grids
---------------------------------------------------------------------------
local function grid(cells, heads) return { kind = "grid", cells = cells, heads = heads } end

local function searchBlocks()
    if not whereIndex then buildIndexes() end
    local blocks = {}
    local q = state.search:lower()
    if #q < 2 then
        blocks[1] = emptyLine("Type at least two letters to search.")
        return blocks, "Search"
    end
    local hits = {}
    for id, name in pairs(lowerNames) do
        if name:find(q, 1, true) then hits[#hits + 1] = id end
    end
    table.sort(hits, function(a, b)
        local qa, qb = ITEMS[a][2] or 1, ITEMS[b][2] or 1
        if qa ~= qb then return qa > qb end
        if lowerNames[a] ~= lowerNames[b] then return lowerNames[a] < lowerNames[b] end
        return a < b
    end)
    local MAX = 200
    local cells = {}
    for _, id in ipairs(hits) do
        local info = itemInfo(id)
        if passesInfo(info) then
            local w = whereIndex[id]
            cells[#cells + 1] = cellFromInfo(id, info, { from = w and w.text, where = w })
            if #cells >= MAX then break end
        end
    end
    local recipeCells = {}
    for _, g in ipairs(PROF_GROUPS) do
        for _, p in ipairs(g.list) do
            for _, r in ipairs(recipesOf(p)) do
                if r[2] and r[2]:lower():find(q, 1, true) then
                    local c = recipeCell(r, p)
                    if passesRecipe(r, c) and #recipeCells < MAX then recipeCells[#recipeCells + 1] = c end
                end
            end
        end
    end
    blocks[#blocks + 1] = heading(("Items (%d)"):format(#cells) .. (#cells >= MAX and ", first " .. MAX .. " shown" or ""))
    if #cells > 0 then
        blocks[#blocks + 1] = grid(cells, { from = "Found in" })
    else
        blocks[#blocks + 1] = textLine("|cff9d9d9dNo items match.|r")
    end
    blocks[#blocks + 1] = heading(("Recipes (%d)"):format(#recipeCells) .. (#recipeCells >= MAX and ", first " .. MAX .. " shown" or ""))
    if #recipeCells > 0 then
        blocks[#blocks + 1] = grid(recipeCells, { from = "Profession" })
    else
        blocks[#blocks + 1] = textLine("|cff9d9d9dNo recipes match.|r")
    end
    return blocks, ("Search: %d items, %d recipes"):format(#cells, #recipeCells)
end

local FILTERED = "Nothing here matches the filters. Press Reset to show everything."

local function lootBlocks()
    local blocks = {}
    if state.search ~= "" then return searchBlocks() end
    local tab = TAB_BY_KEY[state.tab]
    if state.tab == "collections" and ns.CollectionsView then return ns.CollectionsView.blocks() end
    if tab.soon then
        blocks[1] = emptyLine("Nothing here yet. " .. tab.text .. " comes in a later version of Encore-DB.")
        return blocks, tab.text
    end

    if state.tab == "dungeons" then
        local inst = state.inst and Loot.instances[state.inst]
        if inst and state.boss == "quests" and ns.QuestView then return ns.QuestView.blocks(inst) end
        local boss = inst and inst.bosses and inst.bosses[state.boss]
        if not boss then
            blocks[1] = emptyLine(inst and "No bosses recorded for this instance yet." or "Pick an instance on the left.")
            return blocks, inst and inst.name or ""
        end
        local function addList(list)
            local cells, total = {}, 0
            for _, e in ipairs(list or {}) do
                local id, chance = entryOf(e)
                total = total + 1
                local info = itemInfo(id)
                if passesInfo(info) then cells[#cells + 1] = cellFromInfo(id, info, { chance = fmtChance(chance) }) end
            end
            if #cells > 0 then blocks[#blocks + 1] = grid(cells) end
            return #cells, total
        end
        blocks[#blocks + 1] = heading(boss.name)
        if ns.BossNotes and ns.BossNotes[boss.name] then blocks[#blocks + 1] = textLine(ns.BossNotes[boss.name]) end
        local shown, total = addList(boss.items)
        if total == 0 then
            blocks[#blocks + 1] = emptyLine("No loot recorded for this boss in WoW Forever yet.")
        elseif shown == 0 then
            blocks[#blocks + 1] = emptyLine(FILTERED)
        end
        -- Loot of attached bosses (Data\Wings.lua), each under its own heading
        for _, other in ipairs(ns.AttachedBosses and ns.AttachedBosses(inst, boss) or {}) do
            blocks[#blocks + 1] = heading(other.name)
            local n, t = addList(other.items)
            if t > 0 and n == 0 then blocks[#blocks + 1] = textLine("|cff9d9d9dNone match the filters.|r") end
            shown = shown + n
        end
        if boss.also and #boss.also > 0 then
            -- Random drops: closed until the player opens them (or sets them to open in the options).
            local key = state.inst .. "/" .. state.boss
            local open = state.randomOpen[key]
            if open == nil then open = settings().randomOpen == true end
            blocks[#blocks + 1] = {
                kind = "toggle", open = open,
                text = ("Random drops, also seen dropping (%d)"):format(#boss.also),
                onClick = function()
                    state.randomOpen[key] = not open
                    renderLoot(true)
                end,
            }
            if open then
                local alsoShown = addList(boss.also)
                if alsoShown == 0 then blocks[#blocks + 1] = textLine("|cff9d9d9dNone match the filters.|r") end
                shown = shown + alsoShown
            end
        end
        if inst.recipes and #inst.recipes > 0 and not boss.trash then
            -- Profession recipes every boss of this level range can drop: one list per instance, closed by default.
            local key = inst.key or tostring(state.inst)
            local open = state.recipesOpen[key]
            if open == nil then open = settings().randomOpen == true end
            blocks[#blocks + 1] = {
                kind = "toggle", open = open,
                text = ("Recipes any boss here can drop (%d)"):format(#inst.recipes),
                onClick = function()
                    state.recipesOpen[key] = not open
                    renderLoot(true)
                end,
            }
            if open then
                local n = addList(inst.recipes)
                if n == 0 then blocks[#blocks + 1] = textLine("|cff9d9d9dNone match the filters.|r") end
                shown = shown + n
            end
        end
        -- All grids on a boss page share one layout (same columns, same items per row)
        local all = {}
        for _, bl in ipairs(blocks) do
            if bl.kind == "grid" then
                for _, c in ipairs(bl.cells) do all[#all + 1] = c end
                bl.layoutCells = all
            end
        end
        return blocks, ("%s, %s: %d items shown"):format(boss.name, inst.name, shown)
    elseif state.tab == "world" then
        local band = World.bands[state.band]
        local list = band and World.items(state.worldQuality, state.band) or {}
        if #list == 0 then -- nothing in this level range: show the first one with items
            for b in ipairs(World.bands) do
                if #World.items(state.worldQuality, b) > 0 then state.band, band, list = b, World.bands[b], World.items(state.worldQuality, b); break end
            end
        end
        if #list == 0 then return { emptyLine("No world drops recorded in WoW Forever yet.") }, tab.text end
        local title = World.catText(state.worldQuality)
        blocks[#blocks + 1] = heading(title .. ", " .. band.text:lower())
        local cells, total = {}, 0
        for _, id in ipairs(list) do
            total = total + 1
            local info = itemInfo(id)
            if passesInfo(info) then cells[#cells + 1] = cellFromInfo(id, info) end
        end
        if #cells > 0 then
            blocks[#blocks + 1] = grid(cells)
        else
            blocks[#blocks + 1] = emptyLine(total > 0 and FILTERED or "No items.")
        end
        return blocks, ("%s, %s: %d items shown"):format(title, band.text:lower(), #cells)
    elseif state.tab == "professions" then
        return ns.ProfessionView.blocks()
    elseif tab.vendorKind then
        local v = state.vendor[state.tab]
        local vendor = v and Loot.vendors[v]
        if not vendor then return { emptyLine("No vendors players have seen in WoW Forever yet.") }, "" end
        blocks[#blocks + 1] = heading(vendor.name .. (state.standing ~= nil and (": " .. standingText(state.standing)) or ""))
        local cells, total = {}, 0
        for _, e in ipairs(vendor.items or {}) do
            if state.standing == nil or e[2] == state.standing then
                total = total + 1
                local info = itemInfo(e[1])
                if passesInfo(info) then
                    cells[#cells + 1] = cellFromInfo(e[1], info, {
                        cost = e[3] and coin(e[3]),
                        standing = (state.standing == nil and e[2] ~= nil) and standingText(e[2]) or nil,
                        from = e[4],
                        sortv = { cost = e[3], standing = type(e[2]) == "number" and e[2] or e[2] == "q" and 9 or tonumber(tostring(e[2]):match("%d+") or "") },
                    })
                end
            end
        end
        if #cells > 0 and tab.vendorKind == "faction" and ns.VendorGroups then
            -- Reputation rewards in groups (armour, weapons, recipes ...) the player can close and open again.
            for _, g in ipairs(ns.VendorGroups(cells)) do
                local open = state.repOpen[g.key] ~= false
                blocks[#blocks + 1] = {
                    kind = "toggle", open = open, text = ("%s (%d)"):format(g.text, #g.cells),
                    onClick = function()
                        state.repOpen[g.key] = not open
                        renderLoot(true)
                    end,
                }
                if open then
                    blocks[#blocks + 1] = grid(g.cells)
                    blocks[#blocks].layoutCells = cells -- all groups share one layout
                end
            end
        elseif #cells > 0 then
            blocks[#blocks + 1] = grid(cells)
        else
            blocks[#blocks + 1] = emptyLine(total > 0 and FILTERED or "No items.")
        end
        return blocks, ("%s: %d items shown"):format(vendor.name, #cells)
    end
    return blocks, ""
end

---------------------------------------------------------------------------
-- Grid layout: columns that have values, 2-4 items side by side (never fewer than two)
---------------------------------------------------------------------------
local COLUMNS = {
    { key = "skill", w = 82, head = "Skill" },
    { key = "ilvl", w = 30, head = "iLvl", right = true },
    { key = "req", w = 28, head = "Req", right = true },
    { key = "slot", w = 72, head = "Slot" },
    { key = "type", w = 82, head = "Type" },
    { key = "standing", w = 76, head = "Needs" },
    { key = "cost", w = 92, head = "Price", right = true },
    { key = "chance", w = 46, head = "Chance", right = true },
    { key = "from", w = 140, head = "From" },
}
-- Columns dropped in this order when the items side by side are too narrow for them (the item tooltip still
-- shows them). Chance and price always stay.
local DROP_FIRST = { "req", "ilvl", "from", "type", "standing", "slot", "skill" }

local function listWidth()
    local w = lootList and lootList:GetWidth()
    if w and w > 50 then return w end
    local fw = (frame and frame:GetWidth()) or DEFAULT_W
    return fw - (12 + TREE_W + 6 + SEC_W + 6) - 12 - 6 - 14
end

local function makeLayout(cells, width, heads, forceN)
    local present = {}
    for _, col in ipairs(COLUMNS) do
        for _, c in ipairs(cells) do
            local v = c[col.key]
            if v ~= nil and v ~= "" then
                present[col.key] = true
                break
            end
        end
    end
    local function fixedWidth()
        local f = 0
        for _, col in ipairs(COLUMNS) do
            if present[col.key] then f = f + col.w + COL_GAP end
        end
        return f
    end
    local ICON_W = iconW()
    local px = iconPx()
    -- First column: the recipe a profession item is learned from (blank when a trainer teaches it)
    local lead = 0
    for _, c in ipairs(cells) do if c.recipe then lead = px + 6; break end end
    -- Items side by side: always at least two, three or four as the pane gets wider. Counted from a
    -- small item (icon, name, slot, skill, and chance or price), then columns that don't fit are dropped.
    local keep = 0
    for _, key in ipairs({ "slot", "skill", "chance", "cost" }) do
        for _, col in ipairs(COLUMNS) do
            if col.key == key and present[key] then keep = keep + col.w + COL_GAP end
        end
    end
    local smallest = lead + ICON_W + NAME_MIN + 12 + keep + 4
    local n = forceN or math.max(2, math.min(4, math.floor((width + TILE_GAP) / (smallest + TILE_GAP))))
    local tileW = math.floor((width - (n - 1) * TILE_GAP) / n)
    for _, key in ipairs(DROP_FIRST) do
        if lead + ICON_W + NAME_MIN + 12 + fixedWidth() + 4 <= tileW then break end
        present[key] = nil
    end
    local cols, x = {}, tileW - 4
    for i = #COLUMNS, 1, -1 do
        local col = COLUMNS[i]
        if present[col.key] then
            x = x - col.w
            table.insert(cols, 1, { key = col.key, x = x, w = col.w, right = col.right, head = (heads and heads[col.key]) or col.head })
            x = x - COL_GAP
        end
    end
    return { n = n, tileW = tileW, nameW = math.max(40, x - ICON_W - lead), cols = cols, lead = lead,
        iconW = ICON_W, icon = px, cellH = px + 4, rowH = px + 8 }
end

-- Sorting by a column: a cell's sortv value, else the number in its text, else its text. Empty values go last.
function ns.SortValue(c, key)
    if c.sortv and c.sortv[key] ~= nil then return c.sortv[key] end
    local v = c[key]
    if v == nil or v == "" then return nil end
    v = tostring(v):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if key ~= "name" then
        local n = tonumber((v:gsub(",", "")):match("%-?%d+%.?%d*") or "")
        if n then return n end
    end
    return v:lower()
end
function ns.SortCells(cells, key, desc)
    local out, pos = {}, {}
    for i, c in ipairs(cells) do out[i] = c; pos[c] = i end
    table.sort(out, function(a, b)
        local x, y = ns.SortValue(a, key), ns.SortValue(b, key)
        if x == nil or y == nil then
            if x == nil and y == nil then return pos[a] < pos[b] end
            return y == nil
        end
        if type(x) ~= type(y) then x, y = tostring(x), tostring(y) end
        if x == y then return pos[a] < pos[b] end
        if desc then return x > y end
        return x < y
    end)
    return out
end

local function packRows(blocks)
    local rows = {}
    local width = listWidth()
    for _, b in ipairs(blocks) do
        if b.kind == "grid" then
            local layout = makeLayout(b.layoutCells or b.cells, width, b.heads, b.split and #b.split)
            local key, desc = state.sort.key, state.sort.desc
            if not key then key, desc = b.defaultSort, false end
            local known = key == "name"
            for _, col in ipairs(layout.cols) do if col.key == key then known = true end end
            -- The list's own order (profession recipes by skill) still applies when its column is hidden
            local doSort = key and (known or key == b.defaultSort)
            if doSort then b.cells = ns.SortCells(b.cells, key, desc) end
            layout.sortKey, layout.sortDesc = known and key or nil, desc
            rows[#rows + 1] = { kind = "cols", layout = layout }
            if b.split then
                -- Lists side by side (one- and two-handed weapons, armour types): each fills its own column, titled
                -- in the Name heading.
                local lists, height = {}, 0
                layout.titles = {}
                for i, part in ipairs(b.split) do
                    lists[i] = doSort and ns.SortCells(part.cells, key, desc) or part.cells
                    layout.titles[i] = part.title
                    height = math.max(height, #lists[i])
                end
                for r = 1, height do
                    local slice = {}
                    for col = 1, #lists do slice[col] = lists[col][r] end
                    rows[#rows + 1] = { kind = "cells", cells = slice, layout = layout }
                end
            else
                -- Fill down each column first, then the next column, so the sorted order reads top to bottom.
                local total = #b.cells
                local height = math.ceil(total / layout.n)
                for r = 1, height do
                    local slice = {}
                    for col = 1, layout.n do slice[col] = b.cells[(col - 1) * height + r] end
                    rows[#rows + 1] = { kind = "cells", cells = slice, layout = layout }
                end
            end
        else
            rows[#rows + 1] = b
        end
    end
    return rows
end

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------
local function setColor(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end

local function addBorder(f, r, g, b, a, layer)
    -- The shared Encore edge: each side stays at least one real screen pixel at small UI scales.
    return Encore.UI.Edges(f, r, g, b, a, layer)
end

-- Textures given a gradient keep it, so each gets its gradient once and is only shown, hidden or faded after.
local function gradient(tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    tex:SetColorTexture(1, 1, 1, 1)
    tex:SetGradient(orientation, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
end

-- Soft counter of things new or changed in Forever; only shown while highlighting is on.
local function makePip(row)
    row.pipBg = row:CreateTexture(nil, "ARTWORK")
    row.pipBg:SetHeight(13)
    row.pipBg:SetColorTexture(TEAL[1], TEAL[2], TEAL[3], 0.16)
    row.pipEdge = addBorder(row, TEAL[1], TEAL[2], TEAL[3], 0.45, "ARTWORK")
    for _, t in ipairs(row.pipEdge) do t:ClearAllPoints() end
    local e = row.pipEdge
    e[1]:SetPoint("TOPLEFT", row.pipBg); e[1]:SetPoint("TOPRIGHT", row.pipBg)
    e[2]:SetPoint("BOTTOMLEFT", row.pipBg); e[2]:SetPoint("BOTTOMRIGHT", row.pipBg)
    e[3]:SetPoint("TOPLEFT", row.pipBg); e[3]:SetPoint("BOTTOMLEFT", row.pipBg)
    e[4]:SetPoint("TOPRIGHT", row.pipBg); e[4]:SetPoint("BOTTOMRIGHT", row.pipBg)
    row.pipText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.pipText:SetPoint("CENTER", row.pipBg, "CENTER", 0, 0)
    setColor(row.pipText, TEAL_SOFT)
end

local function setPip(row, n)
    local show = highlightOn() and n ~= nil and n > 0
    row.pipBg:SetShown(show); row.pipText:SetShown(show)
    for _, t in ipairs(row.pipEdge) do t:SetShown(show) end
    if show then
        row.pipText:SetText(n)
        row.pipBg:SetWidth(math.max(18, row.pipText:GetStringWidth() + 8))
    end
    return show
end

-- A diamond gem, as on the mock-up's frame corners.
local function gem(parent, point, x, y)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(18, 18)
    f:SetPoint("CENTER", parent, point, x, y)
    f:SetFrameLevel(parent:GetFrameLevel() + 30)
    local sizes = { { 15, 0, 0, 0 }, { 13, COPPER[1], COPPER[2], COPPER[3] }, { 9, TEAL[1], TEAL[2], TEAL[3] } }
    for i, s in ipairs(sizes) do
        local t = f:CreateTexture(nil, "OVERLAY", nil, i)
        t:SetColorTexture(s[2], s[3], s[4], 1)
        t:SetSize(s[1], s[1])
        t:SetPoint("CENTER")
        t:SetRotation(math.rad(45))
    end
    local shine = f:CreateTexture(nil, "OVERLAY", nil, 5)
    shine:SetColorTexture(0.75, 1, 1, 0.9)
    shine:SetSize(3, 3)
    shine:SetPoint("CENTER", -1.5, 1.5)
    shine:SetRotation(math.rad(45))
end

local function linkItem(id)
    if not itemExists(id) then return end
    local item = Item:CreateFromItemID(id)
    item:ContinueOnItemLoad(function()
        local link = item:GetItemLink()
        if link then HandleModifiedItemClick(link) end
    end)
end

local function linkSpell(spell)
    local link = (C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(spell)) or (GetSpellLink and GetSpellLink(spell))
    if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
end

---------------------------------------------------------------------------
-- Boss portraits: the game's own portrait of each boss, found by loading the creature into a hidden model
-- to read its display ID. Display IDs are kept in the saved settings so this happens once per boss.
---------------------------------------------------------------------------
local portraitQueue, portraitQueued, portraitFailed = {}, {}, {}
local resolver, resolverModel, resolving

-- Bundled boss portrait pictures (Media\Portraits\<npc>.tga, from ForeverDungeonJournal; see NOTICE.txt).
-- They show at once and are not render targets; bosses without one get the game's live portrait.
local Portraits = ns.Portraits or {}
local PortraitNames = ns.PortraitNames or {}
local function bossPicture(boss)
    local npc = boss.npc or PortraitNames[boss.name]
    if npc and Portraits[npc] then return TEX.portraitPath .. npc end
end

local function displayCache()
    local s = settings()
    local build = GetBuildInfo and select(2, GetBuildInfo()) or "?"
    if type(s.displays) ~= "table" or s.displaysBuild ~= build then
        s.displays, s.displaysBuild = {}, build
    end
    return s.displays
end

local portraitRefreshPending = false
local function portraitsChanged()
    if portraitRefreshPending then return end
    portraitRefreshPending = true
    C_Timer.After(0.2, function()
        portraitRefreshPending = false
        if frame and frame:IsShown() then renderSections() end
    end)
end

local function modelDisplay()
    local ok, id = pcall(resolverModel.GetDisplayInfo, resolverModel)
    if ok and type(id) == "number" then return id end
    return 0
end

local function createResolver()
    if not (SetPortraitTextureFromCreatureDisplayID and frame) then return end
    resolverModel = CreateFrame("PlayerModel", nil, frame)
    resolverModel:SetSize(1, 1)
    resolverModel:SetPoint("BOTTOMLEFT", 4, 4)
    resolverModel:SetScript("OnModelLoaded", function()
        if resolving then resolving.loaded = true end
    end)
    resolver = CreateFrame("Frame", nil, frame)
    resolver:Hide()
    resolver:SetScript("OnUpdate", function(self, elapsed)
        if not resolving then
            local npc = table.remove(portraitQueue, 1)
            if not npc then
                self:Hide()
                return
            end
            resolving = { npc = npc, t = 0 }
            if resolverModel.ClearModel then pcall(resolverModel.ClearModel, resolverModel) end
            resolving.before = modelDisplay()
            if not pcall(resolverModel.SetCreature, resolverModel, npc) then resolving.failed = true end
            return
        end
        local r = resolving
        r.t = r.t + elapsed
        local id = (not r.failed) and modelDisplay() or 0
        if id > 0 and (r.loaded or id ~= r.before) then
            displayCache()[r.npc] = id
            resolving = nil
            portraitsChanged()
        elseif r.failed or r.t > 3 then
            portraitFailed[r.npc] = true
            resolving = nil
        end
    end)
end

function queuePortrait(npc)
    if not (npc and resolver) or portraitQueued[npc] or portraitFailed[npc] then return end
    portraitQueued[npc] = true
    portraitQueue[#portraitQueue + 1] = npc
    resolver:Show()
end

---------------------------------------------------------------------------
-- Row builders (each pooled frame is built once, then filled per element)
---------------------------------------------------------------------------
local function onRowClick(self, button)
    local d = self.data
    if d and d.onClick then d.onClick(button) end
end

local function initTreeRow(row, d)
    if not row.built then
        row.built = true
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        gradient(row.sel, "HORIZONTAL", 1, 0.82, 0, 0.30, 1, 0.82, 0, 0)
        row.selBar = row:CreateTexture(nil, "ARTWORK")
        row.selBar:SetPoint("TOPLEFT"); row.selBar:SetPoint("BOTTOMLEFT"); row.selBar:SetWidth(2)
        row.selBar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        gradient(hl, "HORIZONTAL", 1, 0.82, 0, 0.16, 1, 0.82, 0, 0)
        row.pmEdge = row:CreateTexture(nil, "ARTWORK", nil, 1)
        row.pmEdge:SetSize(14, 14)
        row.pmEdge:SetPoint("LEFT", 4, 0)
        row.pmEdge:SetColorTexture(0.79, 0.47, 0.18, 1)
        row.pmFill = row:CreateTexture(nil, "ARTWORK", nil, 2)
        row.pmFill:SetSize(12, 12)
        row.pmFill:SetPoint("CENTER", row.pmEdge)
        gradient(row.pmFill, "VERTICAL", 0.14, 0.08, 0.04, 1, 0.36, 0.23, 0.11, 1)
        row.pmText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.pmText:SetPoint("CENTER", row.pmEdge, "CENTER", 0, 1)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", 20, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.right = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.right:SetJustifyH("RIGHT")
        makePip(row)
        row:SetScript("OnClick", onRowClick)
    end
    row.data = d
    local cat = d.kind == "cat"
    row.pmEdge:SetShown(cat); row.pmFill:SetShown(cat); row.pmText:SetShown(cat)
    row.pmText:SetText(d.open and "-" or "+")
    row.sel:SetShown(d.selected == true); row.selBar:SetShown(d.selected == true)
    row.icon:SetShown(d.icon ~= nil)
    if d.icon then
        row.icon:SetTexture(d.icon)
        -- iconCoords: a part of an icon sheet (class icons); otherwise the usual crop of an icon's border
        if d.iconCoords then row.icon:SetTexCoord(unpack(d.iconCoords)) else row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    end

    row.label:SetFontObject(cat and "GameFontNormal" or "GameFontHighlight")
    if cat then
        setColor(row.label, GOLD)
    elseif d.selected then
        row.label:SetTextColor(1, 1, 1)
    elseif d.isNew and highlightOn() then
        setColor(row.label, TEAL_SOFT)
    else
        setColor(row.label, INK)
    end
    row.label:SetText(d.text)
    row.right:SetText(d.right or "")
    setColor(row.right, DIM)

    row.pipBg:ClearAllPoints()
    row.pipBg:SetPoint("RIGHT", -4, 0)
    local hasPip = setPip(row, (not cat) and d.pip or nil)
    row.right:ClearAllPoints()
    if hasPip then
        row.right:SetPoint("RIGHT", row.pipBg, "LEFT", -5, 0)
    else
        row.right:SetPoint("RIGHT", -6, 0)
    end
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", cat and 24 or (d.icon and 50 or 22), 0)
    row.label:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
end

local function initSectionRow(row, d)
    if not row.built then
        row.built = true
        row.bg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.bg:SetPoint("TOPLEFT", 0, -1); row.bg:SetPoint("BOTTOMRIGHT", 0, 1)
        gradient(row.bg, "VERTICAL", 0, 0, 0, 0.25, 1, 1, 1, 0.04)
        row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 2)
        row.sel:SetPoint("TOPLEFT", 0, -1); row.sel:SetPoint("BOTTOMRIGHT", 0, 1)
        gradient(row.sel, "VERTICAL", 0.30, 0.004, 0, 0.75, 0.70, 0.04, 0.03, 0.75)
        row.edge = addBorder(row, COPPER[1], COPPER[2], COPPER[3], 0.9, "ARTWORK")
        row.edge[1]:SetPoint("TOPLEFT", 0, -1); row.edge[1]:SetPoint("TOPRIGHT", 0, -1)
        row.edge[2]:SetPoint("BOTTOMLEFT", 0, 1); row.edge[2]:SetPoint("BOTTOMRIGHT", 0, 1)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", 0, -1); hl:SetPoint("BOTTOMRIGHT", 0, 1)
        hl:SetColorTexture(1, 0.82, 0, 0.10)
        -- Round boss portrait on a dark disc
        row.portraitBg = row:CreateTexture(nil, "ARTWORK", nil, 1)
        local P = TEX.portraitSize
        row.portraitBg:SetSize(P, P)
        row.portraitBg:SetPoint("LEFT", 6, 0)
        row.portraitBg:SetColorTexture(0, 0, 0, 0.7)
        row.portrait = row:CreateTexture(nil, "ARTWORK", nil, 2)
        row.portrait:SetAllPoints(row.portraitBg)
        local mask = row:CreateMaskTexture()
        mask:SetTexture(TEX.portraitMask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(row.portraitBg)
        row.portrait:AddMaskTexture(mask)
        row.portraitBg:AddMaskTexture(mask)
        -- Silver dragon around a rare spawn's portrait (scale P/64 of the target frame's)
        row.rare = row:CreateTexture(nil, "OVERLAY", nil, 1)
        row.rare:SetTexture(TEX.rare)
        row.rare:SetTexCoord(unpack(TEX.rareCoords))
        row.rare:SetSize(108 * P / 64, 100 * P / 64)
        row.rare:SetPoint("TOPLEFT", row.portraitBg, "TOPLEFT", -2 * P / 64, 12 * P / 64)
        row.rare:Hide()
        -- Level in the target frame's little circle at the portrait's lower right (P/64 of its size), or the
        -- skull for a boss-level mob
        local lv = 26 * P / 64
        row.levelRing = row:CreateTexture(nil, "OVERLAY", nil, 2)
        row.levelRing:SetTexture(TEX.level)
        row.levelRing:SetTexCoord(unpack(TEX.levelCoords))
        row.levelRing:SetSize(lv, lv)
        row.levelRing:SetPoint("CENTER", row.portraitBg, "TOPLEFT", 53 * P / 64, -54 * P / 64)
        local ringMask = row:CreateMaskTexture()
        ringMask:SetTexture(TEX.portraitMask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        ringMask:SetAllPoints(row.levelRing)
        row.levelRing:AddMaskTexture(ringMask)
        row.levelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        do local font = row.levelText:GetFont(); if font then row.levelText:SetFont(font, 13, "OUTLINE") end end
        row.levelText:SetPoint("CENTER", row.levelRing, "CENTER", 0, 0)
        row.levelSkull = row:CreateTexture(nil, "OVERLAY", nil, 3)
        row.levelSkull:SetTexture(TEX.skull)
        row.levelSkull:SetSize(16, 16)
        row.levelSkull:SetPoint("CENTER", row.levelRing, "CENTER", 0, 0)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)
        makePip(row)
        row.pipBg:SetPoint("RIGHT", -8, 0)
        row:SetScript("OnClick", onRowClick)
    end
    row.data = d
    row.sel:SetShown(d.selected == true)
    for _, t in ipairs(row.edge) do t:SetShown(d.selected == true) end
    local hasPortrait = d.npc ~= nil
    row.portraitBg:SetShown(hasPortrait); row.portrait:SetShown(hasPortrait)
    -- An icon on the disc instead of a portrait (the Quests row)
    if d.badge and not row.badge then
        row.badge = row:CreateTexture(nil, "ARTWORK", nil, 3)
        row.badge:SetPoint("CENTER", row.portraitBg)
    end
    if row.badge then
        row.badge:SetShown(d.badge ~= nil)
        if d.badge then
            row.badge:SetTexture(d.badge)
            if d.badgeCoords then row.badge:SetTexCoord(unpack(d.badgeCoords)) else row.badge:SetTexCoord(0, 1, 0, 1) end
            row.badge:SetSize(d.badgeSize or 30, d.badgeSize or 30)
        end
    end
    if hasPortrait then
        local picture = d.boss and bossPicture(d.boss)
        local display = (not picture) and d.npc and displayCache()[d.npc]
        if d.badge then
            row.portrait:SetColorTexture(0.30, 0.20, 0.05, 1)
        elseif picture then
            row.portrait:SetTexture(picture)
            row.portrait:SetTexCoord(0, 1, 0, 1)
        elseif display and SetPortraitTextureFromCreatureDisplayID then
            SetPortraitTextureFromCreatureDisplayID(row.portrait, display)
            row.portrait:SetTexCoord(0, 1, 0, 1)
        else
            row.portrait:SetTexture(TEX.skull)
            row.portrait:SetTexCoord(-0.15, 1.15, -0.15, 1.15)
            if d.npc then queuePortrait(d.npc) end
        end
    end
    row.rare:SetShown(hasPortrait and d.rare == true)
    ns.SetLevelBadge(row, hasPortrait and d.level or nil, d.rare == true)
    local left = hasPortrait and (d.rare and 108 or 76) or 12
    local hasPip = setPip(row, d.pip)
    local rightEdge = hasPip and -32 or -8
    -- Name and subtitle centred together on the row
    local hasSub = d.sub ~= nil and d.sub ~= ""
    row.label:ClearAllPoints()
    if hasSub then
        row.label:SetPoint("BOTTOMLEFT", row, "LEFT", left, 1)
        row.label:SetPoint("BOTTOMRIGHT", row, "RIGHT", rightEdge, 1)
    else
        row.label:SetPoint("LEFT", left, 0)
        row.label:SetPoint("RIGHT", rightEdge, 0)
    end
    row.sub:ClearAllPoints()
    row.sub:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
    row.sub:SetPoint("TOPRIGHT", row.label, "BOTTOMRIGHT", 0, -3)
    row.label:SetText(d.text)
    if d.selected then setColor(row.label, GOLD) else setColor(row.label, INK) end
    row.sub:SetText(d.sub or "")
    setColor(row.sub, DIM)
end

local function initHeadRow(row, d)
    if not row.built then
        row.built = true
        row:EnableMouse(false)
        row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        row.title:SetPoint("TOPLEFT", 8, -8)
        row.title:SetPoint("TOPRIGHT", -8, -8)
        row.title:SetJustifyH("LEFT")
        row.title:SetWordWrap(false)
        row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.meta:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
        row.meta:SetPoint("TOPRIGHT", row.title, "BOTTOMRIGHT", 0, -4)
        row.meta:SetJustifyH("LEFT")
        row.meta:SetJustifyV("TOP")
        local line = row:CreateTexture(nil, "ARTWORK")
        line:SetPoint("BOTTOMLEFT", 6, 3); line:SetPoint("BOTTOMRIGHT", -6, 3); line:SetHeight(1)
        line:SetColorTexture(COPPER[1], COPPER[2], COPPER[3], 0.3)
    end
    row.data = d
    row.title:SetText(d.title or "")
    setColor(row.title, GOLD)
    row.meta:SetText(d.meta or "")
    setColor(row.meta, DIM)
end

-- Column headings above an item grid, repeated for each item column.
local function initColsRow(row, d)
    if not row.built then
        row.built = true
        row:EnableMouse(false)
        row.heads = {}
        local line = row:CreateTexture(nil, "ARTWORK")
        line:SetPoint("BOTTOMLEFT", 0, 1); line:SetPoint("BOTTOMRIGHT", 0, 1); line:SetHeight(1)
        line:SetColorTexture(COPPER[1], COPPER[2], COPPER[3], 0.25)
    end
    local L = d.layout
    for i = 1, 4 do
        local h = row.heads[i]
        if i <= L.n then
            if not h then
                h = { cols = {} }
                h.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                h.name:SetJustifyH("LEFT")
                row.heads[i] = h
            end
            local x0 = (i - 1) * (L.tileW + TILE_GAP)
            -- A heading button: click to sort by it, click again to reverse.
            local function head(key, fs, x, w, text, right)
                fs:ClearAllPoints()
                fs:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 4)
                fs:SetWidth(w)
                fs:SetJustifyH(right and "RIGHT" or "LEFT")
                local arrow = L.sortKey == key and (L.sortDesc and " |TInterface\\Buttons\\Arrow-Down-Up:10:10|t" or " |TInterface\\Buttons\\Arrow-Up-Up:10:10|t") or ""
                fs:SetText(text .. arrow)
                setColor(fs, GOLD, L.sortKey == key and 1 or 0.8)
                fs:Show()
                h.btn = h.btn or {}
                local b = h.btn[key]
                if not b then
                    b = CreateFrame("Button", nil, row)
                    b:SetScript("OnClick", function(self)
                        if state.sort.key == self.key or (state.sort.key == nil and self.isDefault) then
                            state.sort.key, state.sort.desc = self.key, not state.sort.desc
                        else
                            state.sort.key, state.sort.desc = self.key, false
                        end
                        renderAll()
                    end)
                    h.btn[key] = b
                end
                b.key, b.isDefault = key, L.sortKey == key and state.sort.key == nil
                b:ClearAllPoints()
                b:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 0)
                b:SetSize(w, 18)
                b:Show()
            end
            for _, b in pairs(h.btn or {}) do b:Hide() end
            if L.lead > 0 then
                h.lead = h.lead or row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                h.lead:ClearAllPoints()
                h.lead:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x0, 4)
                h.lead:SetText("Rec.")
                setColor(h.lead, GOLD, 0.8)
                h.lead:Show()
            elseif h.lead then
                h.lead:Hide()
            end
            head("name", h.name, x0 + L.lead + L.iconW, math.max(40, L.nameW), L.titles and L.titles[i] or "Name")
            for _, fs in pairs(h.cols) do fs:Hide() end
            for _, col in ipairs(L.cols) do
                local fs = h.cols[col.key]
                if not fs then
                    fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    fs:SetWordWrap(false)
                    h.cols[col.key] = fs
                end
                head(col.key, fs, x0 + col.x, col.w, col.head, col.right)
            end
        elseif h then
            h.name:Hide()
            if h.lead then h.lead:Hide() end
            for _, fs in pairs(h.cols) do fs:Hide() end
            for _, b in pairs(h.btn or {}) do b:Hide() end
        end
    end
end

local function cellEnter(self)
    local d = self.data
    if not d then return end
    if popup and popup:IsShown() and popup.owner == self then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    local isItem = d.id and itemExists(d.id)
    if isItem then
        GameTooltip:SetItemByID(d.id)
    elseif d.spell and GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(d.spell)
    else
        GameTooltip:SetText(d.name or "", qualityColor(d.quality))
    end
    if highlightOn() then
        if d.isNew then
            GameTooltip:AddLine("New in WoW Forever", TEAL_SOFT[1], TEAL_SOFT[2], TEAL_SOFT[3])
        elseif d.changed then
            GameTooltip:AddLine("Changed in WoW Forever", TEAL_SOFT[1], TEAL_SOFT[2], TEAL_SOFT[3])
        end
    end
    if d.recipe then
        GameTooltip:AddLine("Click to see the reagents and how to learn it.", GOLD[1], GOLD[2], GOLD[3], true)
    elseif d.where then
        GameTooltip:AddLine("Click to open " .. d.where.text .. ".", GOLD[1], GOLD[2], GOLD[3], true)
    end
    if isItem or d.spell then GameTooltip:AddLine("Shift-click to link it in chat.", DIM[1], DIM[2], DIM[3]) end
    GameTooltip:Show()
end

local togglePopup -- defined with the popup below

local function cellClick(self)
    local d = self.data
    if not d then return end
    if IsModifiedClick() then
        if d.id then linkItem(d.id) elseif d.spell then linkSpell(d.spell) end
        return
    end
    if d.recipe then
        togglePopup(self, d.recipe)
    elseif d.where then
        goTo(d.where)
    end
end

local function newCell(row)
    local c = CreateFrame("Button", nil, row)
    c:SetHeight(22)
    c.bg = c:CreateTexture(nil, "BACKGROUND", nil, 1)
    c.bg:SetAllPoints()
    c.bg:SetColorTexture(0, 0, 0, 0.32)
    c.tint = c:CreateTexture(nil, "BACKGROUND", nil, 2)
    c.tint:SetAllPoints()
    gradient(c.tint, "HORIZONTAL", TEAL[1], TEAL[2], TEAL[3], 0.16, TEAL[1], TEAL[2], TEAL[3], 0.01)
    c.stripe = c:CreateTexture(nil, "BACKGROUND", nil, 3)
    c.stripe:SetPoint("TOPLEFT"); c.stripe:SetPoint("BOTTOMLEFT"); c.stripe:SetWidth(2)
    c.stripe:SetColorTexture(TEAL[1], TEAL[2], TEAL[3], 0.7)
    local hl = c:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    gradient(hl, "HORIZONTAL", 1, 0.82, 0, 0.16, 1, 0.82, 0, 0.03)
    c.iconEdge = c:CreateTexture(nil, "BORDER")
    c.iconEdge:SetPoint("LEFT", 3, 0)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("CENTER", c.iconEdge)
    c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.gem = c:CreateTexture(nil, "OVERLAY")
    c.gem:SetPoint("CENTER", c.iconEdge, "TOPLEFT", 1, -1)
    c.gem:SetRotation(math.rad(45))
    c.name = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.name:SetJustifyH("LEFT")
    -- First column: the recipe item this is learned from, with its tooltip
    c.lead = CreateFrame("Button", nil, c)
    c.lead.icon = c.lead:CreateTexture(nil, "ARTWORK")
    c.lead.icon:SetAllPoints()
    c.lead.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.lead:SetScript("OnEnter", function(self)
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetItemByID(self.item)
        GameTooltip:AddLine("Shift-click to link it in chat.", DIM[1], DIM[2], DIM[3])
        GameTooltip:Show()
    end)
    c.lead:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.lead:SetScript("OnClick", function(self)
        if self.item and IsModifiedClick() then linkItem(self.item) else cellClick(c) end
    end)
    c.colText = {}
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    c:SetScript("OnClick", cellClick)
    c:SetScript("OnEnter", cellEnter)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return c
end

local function fillCell(c, d, L)
    if popup and popup:IsShown() and popup.owner == c and d.recipe ~= popup.recipe then hidePopup() end
    c.data = d
    c:SetSize(L.tileW, L.cellH)
    if c.iconPx ~= L.icon or c.leadW ~= L.lead then
        -- Bigger icons get a bigger name that may wrap onto a second line.
        local px = L.icon
        c.iconPx, c.leadW = px, L.lead
        c.iconEdge:ClearAllPoints()
        c.iconEdge:SetPoint("LEFT", 3 + L.lead, 0)
        c.lead:ClearAllPoints()
        c.lead:SetPoint("LEFT", 4, 0)
        c.lead:SetSize(px, px)
        c.iconEdge:SetSize(px + 2, px + 2)
        c.icon:SetSize(px, px)
        c.gem:SetSize(px >= ICON_SIZES.normal and 10 or 6, px >= ICON_SIZES.normal and 10 or 6)
        c.name:SetFontObject(px >= ICON_SIZES.normal and "GameFontHighlightLarge" or "GameFontHighlight")
        c.name:SetWordWrap(px >= ICON_SIZES.normal)
        if c.name.SetMaxLines then c.name:SetMaxLines(px >= ICON_SIZES.normal and 2 or 1) end
        c.name:ClearAllPoints()
        c.name:SetPoint("LEFT", L.iconW + L.lead, 0)
    end
    local ri = L.lead > 0 and d.recipeItem
    c.lead.item = ri or nil
    c.lead:SetShown(ri and true or false)
    if ri then
        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(ri)
        c.lead.icon:SetTexture(tex or (GetItemIcon and GetItemIcon(ri)) or TEX.questionMark)
    end
    local r, g, b = qualityColor(d.quality)
    c.iconEdge:SetColorTexture(r, g, b, 0.85)
    c.icon:SetTexture(d.icon or TEX.questionMark)
    c.name:SetWidth(L.nameW)
    c.name:SetText(d.name or "")
    c.name:SetTextColor(r, g, b)
    for _, fs in pairs(c.colText) do fs:Hide() end
    for _, col in ipairs(L.cols) do
        local fs = c.colText[col.key]
        if not fs then
            fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetWordWrap(false)
            c.colText[col.key] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", c, "LEFT", col.x, 0)
        fs:SetWidth(col.w)
        fs:SetJustifyH(col.right and "RIGHT" or "LEFT")
        fs:SetText(d[col.key] or "")
        if col.key == "chance" or col.key == "cost" then setColor(fs, INK) else setColor(fs, DIM) end
        fs:Show()
    end
    local mark = highlightOn() and (d.isNew or d.changed)
    c.tint:SetShown(mark); c.stripe:SetShown(mark); c.gem:SetShown(mark)
    if mark then
        c.tint:SetAlpha(d.isNew and 1 or 0.5)
        c.stripe:SetAlpha(d.isNew and 1 or 0.55)
        c.gem:SetColorTexture(TEAL_SOFT[1], TEAL_SOFT[2], TEAL_SOFT[3], d.isNew and 1 or 0.55)
    end
end

local function initCellsRow(row, d)
    if not row.built then
        row.built = true
        row:EnableMouse(false)
        row.cells = {}
    end
    local L = d.layout
    for i = 1, 4 do
        local cd = d.cells[i]
        local c = row.cells[i]
        if cd then
            if not c then
                c = newCell(row)
                row.cells[i] = c
            end
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (L.tileW + TILE_GAP), -1)
            fillCell(c, cd, L)
            c:Show()
        elseif c then
            c:Hide()
            c.data = nil
        end
    end
end

local LINE_FONTS = { heading = "GameFontNormal", text = "GameFontHighlightSmall", empty = "GameFontDisable" }

local function initLineRow(row, d)
    if not row.built then
        row.built = true
        row:EnableMouse(false)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.line = row:CreateTexture(nil, "ARTWORK")
        row.line:SetPoint("BOTTOMLEFT", 6, 2); row.line:SetPoint("BOTTOMRIGHT", -6, 2); row.line:SetHeight(1)
        row.line:SetColorTexture(COPPER[1], COPPER[2], COPPER[3], 0.35)
    end
    row.data = d
    row.text:SetFontObject(LINE_FONTS[d.kind] or "GameFontHighlightSmall")
    row.text:ClearAllPoints()
    row.line:SetShown(d.kind == "heading")
    if d.kind == "empty" then
        row.text:SetPoint("LEFT", 16, 0)
        row.text:SetPoint("RIGHT", -16, 0)
        row.text:SetJustifyH("CENTER")
        row.text:SetWordWrap(true)
        setColor(row.text, DIM)
    elseif d.kind == "text" then
        row.text:SetPoint("LEFT", 12, 0)
        row.text:SetPoint("RIGHT", -10, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(true)
        setColor(row.text, INK)
    else -- heading
        row.text:SetPoint("BOTTOMLEFT", 8, 6)
        row.text:SetPoint("BOTTOMRIGHT", -8, 6)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        setColor(row.text, GOLD)
    end
    row.text:SetText(d.text or "")
end

-- A heading that opens and closes the list under it (random drops).
local function initToggleRow(row, d)
    if not row.built then
        row.built = true
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", 2, -3); hl:SetPoint("BOTTOMRIGHT", -2, 2)
        gradient(hl, "HORIZONTAL", 1, 0.82, 0, 0.14, 1, 0.82, 0, 0)
        row.pmEdge = row:CreateTexture(nil, "ARTWORK", nil, 1)
        row.pmEdge:SetSize(14, 14)
        row.pmEdge:SetPoint("BOTTOMLEFT", 8, 6)
        row.pmEdge:SetColorTexture(0.79, 0.47, 0.18, 1)
        row.pmFill = row:CreateTexture(nil, "ARTWORK", nil, 2)
        row.pmFill:SetSize(12, 12)
        row.pmFill:SetPoint("CENTER", row.pmEdge)
        gradient(row.pmFill, "VERTICAL", 0.14, 0.08, 0.04, 1, 0.36, 0.23, 0.11, 1)
        row.pmText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.pmText:SetPoint("CENTER", row.pmEdge, "CENTER", 0, 1)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", row.pmEdge, "RIGHT", 7, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        setColor(row.text, GOLD)
        local line = row:CreateTexture(nil, "ARTWORK")
        line:SetPoint("BOTTOMLEFT", 6, 2); line:SetPoint("BOTTOMRIGHT", -6, 2); line:SetHeight(1)
        line:SetColorTexture(COPPER[1], COPPER[2], COPPER[3], 0.35)
        row:SetScript("OnClick", onRowClick)
    end
    row.data = d
    row.pmText:SetText(d.open and "-" or "+")
    row.text:SetText(d.text or "")
end

-- (Few file-level locals left: this file is near Lua's limit of 200, so sizes live in the table.)
local ROW_KINDS = {
    toggle = { "EncoreDBToggleRowTemplate", initToggleRow, 30 },
    cat = { "EncoreDBTreeRowTemplate", initTreeRow, 22 },
    leaf = { "EncoreDBTreeRowTemplate", initTreeRow, 20 },
    leafIcon = { "EncoreDBTreeRowTemplate", initTreeRow, 32 }, -- extent of a leaf with an icon (professions)
    sec = { "EncoreDBSectionRowTemplate", initSectionRow, 70 },
    -- As tall as the heading + column titles over the item grid (28 + 20), so the first
    -- boss row lines up with the first item row.
    head = { "EncoreDBHeadRowTemplate", initHeadRow, 48 },
    cols = { "EncoreDBColsRowTemplate", initColsRow, 20 },
    cells = { "EncoreDBItemRowTemplate", initCellsRow, 24 },
    heading = { "EncoreDBLineRowTemplate", initLineRow, 28 },
    text = { "EncoreDBLineRowTemplate", initLineRow },
    empty = { "EncoreDBLineRowTemplate", initLineRow },
}

---------------------------------------------------------------------------
-- Recipe popup: opens beside a clicked recipe instead of a separate page
---------------------------------------------------------------------------
local POPUP_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function popupLine(i)
    local l = popup.lines[i]
    if l then return l end
    l = CreateFrame("Button", nil, popup)
    l.icon = l:CreateTexture(nil, "ARTWORK")
    l.icon:SetPoint("TOPLEFT", 0, 0)
    l.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    l.text = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.text:SetJustifyH("LEFT")
    l.text:SetWordWrap(true)
    local hl = l:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", -3, 1); hl:SetPoint("BOTTOMRIGHT", 3, -1)
    hl:SetColorTexture(1, 0.82, 0, 0.10)
    l:RegisterForClicks("LeftButtonUp")
    l:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        if e.itemID and IsModifiedClick() then
            linkItem(e.itemID)
        elseif e.onClick then
            e.onClick()
        end
    end)
    l:SetScript("OnEnter", function(self)
        local e = self.entry
        if not (e and e.itemID and itemExists(e.itemID)) then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetItemByID(e.itemID)
        GameTooltip:AddLine("Shift-click to link it in chat.", DIM[1], DIM[2], DIM[3])
        GameTooltip:Show()
    end)
    l:SetScript("OnLeave", function() GameTooltip:Hide() end)
    popup.lines[i] = l
    return l
end

local function layoutPopup(entries)
    local inner = POPUP_W - 24
    local y = -12
    for i, e in ipairs(entries) do
        local l = popupLine(i)
        l.entry = e
        if e.gap then y = y - e.gap end
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, y)
        l.text:SetFontObject(e.font or "GameFontHighlightSmall")
        local x, iconSize = 0, e.iconSize or 14
        if e.icon then
            l.icon:SetTexture(e.icon)
            l.icon:SetSize(iconSize, iconSize)
            l.icon:Show()
            x = iconSize + 5
        else
            l.icon:Hide()
        end
        local textW = inner - x - (i == 1 and 18 or 0) -- room for the close button
        l.text:ClearAllPoints()
        l.text:SetWidth(textW)
        l.text:SetText(e.text or "")
        local th = l.text:GetStringHeight()
        local h = math.max(th, e.icon and iconSize or 0)
        l.text:SetPoint("LEFT", l, "LEFT", x, 0)
        if e.color then setColor(l.text, e.color) else setColor(l.text, INK) end
        l:SetSize(inner, h)
        l:EnableMouse(e.onClick ~= nil or e.itemID ~= nil)
        l:Show()
        y = y - h - (e.after or 3)
    end
    for i = #entries + 1, #popup.lines do
        popup.lines[i]:Hide()
        popup.lines[i].entry = nil
    end
    popup:SetHeight(-y + 10)
end

local function createPopup()
    popup = CreateFrame("Frame", "EncoreDBRecipePopup", frame, "BackdropTemplate")
    popup:SetWidth(POPUP_W)
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetBackdrop(POPUP_BACKDROP)
    popup:SetBackdropColor(0.07, 0.05, 0.03, 0.97)
    popup:SetBackdropBorderColor(COPPER[1], COPPER[2], COPPER[3], 1)
    popup.lines = {}
    popup:Hide()
    local close = CreateFrame("Button", nil, popup, "UIPanelCloseButtonNoScripts")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() popup:Hide() end)
    popup:SetScript("OnHide", function(self)
        self.recipe, self.owner = nil, nil
    end)
    -- Close on a click anywhere else, and when its recipe scrolls out of the list.
    pcall(popup.RegisterEvent, popup, "GLOBAL_MOUSE_DOWN")
    popup:SetScript("OnEvent", function(self)
        if not self:IsShown() then return end
        if self:IsMouseOver() or (self.owner and self.owner:IsMouseOver()) then return end
        self:Hide()
    end)
    popup:SetScript("OnUpdate", function(self)
        local o = self.owner
        if not (o and o:IsVisible()) then
            self:Hide()
            return
        end
        local top, bottom = lootList:GetTop(), lootList:GetBottom()
        local oTop, oBottom = o:GetTop(), o:GetBottom()
        if top and oTop and (oBottom > top or oTop < bottom) then self:Hide() end
    end)
end

function togglePopup(owner, r)
    if not popup then return end
    if popup:IsShown() and popup.recipe == r then
        popup:Hide()
        return
    end
    GameTooltip:Hide()
    popup.recipe, popup.owner = r, owner
    layoutPopup(recipePopupEntries(r))
    popup:ClearAllPoints()
    local right = owner:GetRight() or 0
    if right + POPUP_W + 8 > (UIParent:GetRight() or 0) then
        popup:SetPoint("TOPRIGHT", owner, "TOPLEFT", -4, 0)
    else
        popup:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, 0)
    end
    popup:Show()
end

function hidePopup()
    if popup then popup:Hide() end
end

---------------------------------------------------------------------------
-- Scroll lists
---------------------------------------------------------------------------
local measure

local function createList(pane, textWidth)
    local box = CreateFrame("Frame", nil, pane, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", 3, -3)
    box:SetPoint("BOTTOMRIGHT", -14, 3)
    local bar = CreateFrame("EventFrame", nil, pane, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 2, -2)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 2, 2)
    bar:SetHideIfUnscrollable(true)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtentCalculator(function(_, d)
        if d.kind == "cells" then return d.layout.rowH end
        if d.kind == "leaf" and d.icon then return ROW_KINDS.leafIcon[3] end
        if d.kind == "sec" and d.npc == nil then return 56 end -- no boss portrait: the shorter row
        local kind = ROW_KINDS[d.kind] or ROW_KINDS.text
        if kind[3] then return kind[3] end
        measure:SetFontObject(LINE_FONTS[d.kind] or "GameFontHighlightSmall")
        measure:SetWidth(textWidth(box) - (d.indent or 0))
        measure:SetText(d.text or "")
        local h = measure:GetStringHeight() + 8
        if d.kind == "empty" then return math.max(70, h + 30) end
        return math.max(20, h)
    end)
    view:SetElementFactory(function(factory, d)
        local kind = ROW_KINDS[d.kind] or ROW_KINDS.text
        factory(kind[1], kind[2])
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    return box
end

local function setRows(box, rows, keepScroll)
    box:SetDataProvider(CreateDataProvider(rows), keepScroll and ScrollBoxConstants.RetainScrollPosition or nil)
end

local function well(left, width)
    local f = CreateFrame("Frame", nil, frame)
    f:SetPoint("TOPLEFT", left, PANE_TOP)
    if width then
        f:SetPoint("BOTTOMLEFT", left, PANE_BOTTOM)
        f:SetWidth(width)
    else
        f:SetPoint("BOTTOMRIGHT", -12, PANE_BOTTOM)
    end
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.016, 0.012, 0.008, 0.72)
    addBorder(f, 0, 0, 0, 1)
    local inner = addBorder(f, COPPER[1], COPPER[2], COPPER[3], 0.22)
    inner[1]:SetPoint("TOPLEFT", 1, -1); inner[1]:SetPoint("TOPRIGHT", -1, -1)
    inner[2]:SetPoint("BOTTOMLEFT", 1, 1); inner[2]:SetPoint("BOTTOMRIGHT", -1, 1)
    inner[3]:SetPoint("TOPLEFT", 1, -1); inner[3]:SetPoint("BOTTOMLEFT", 1, 1)
    inner[4]:SetPoint("TOPRIGHT", -1, -1); inner[4]:SetPoint("BOTTOMRIGHT", -1, 1)
    return f
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------
local function updateTabs()
    for _, b in ipairs(tabButtons) do
        local on = b.key == state.tab
        b:SetHeight(on and 27 or 24)
        b.bgOn:SetShown(on); b.bgOff:SetShown(not on)
        if on then
            setColor(b.text, GOLD)
        elseif b.soon then
            b.text:SetTextColor(0.5, 0.46, 0.4)
        else
            setColor(b.text, TAB_INK)
        end
        for _, t in ipairs(b.edge) do
            t:SetColorTexture(on and COPPER[1] or 0.54, on and COPPER[2] or 0.33, on and COPPER[3] or 0.13, 1)
        end
    end
end

local function updateLegend()
    if legend then
        legend:SetShown(highlightOn())
        legendGem:SetShown(highlightOn())
    end
end

function renderLoot(keepScroll)
    if not frame then return end
    if not keepScroll then hidePopup() end
    local blocks, status = lootBlocks()
    setRows(lootList, packRows(blocks), keepScroll)
    statusText:SetText(status or "")
    if popup and popup:IsShown() and popup.recipe then layoutPopup(recipePopupEntries(popup.recipe)) end
end

function renderSections()
    if not frame then return end
    setRows(secList, sectionRows(), true)
end

function renderAll()
    if not frame then return end
    if state.tab == "dungeons" and not (state.inst and Loot.instances[state.inst]) then state.inst, state.boss = firstInstance(), 1 end
    -- Remembered for the next session: the dungeon (by key, as wings can change the list) and the boss page.
    if state.inst and Loot.instances[state.inst] then
        local s = settings()
        s.inst, s.boss = Loot.instances[state.inst].key, state.boss
    end
    if state.tab == "professions" and not (state.prof and Recipes[state.prof]) then state.prof, state.bracket = firstProfession(), 1 end
    local tab = TAB_BY_KEY[state.tab]
    if tab and tab.vendorKind and not (state.vendor[state.tab] and Loot.vendors[state.vendor[state.tab]]) then
        state.vendor[state.tab] = firstVendor(tab.vendorKind)
    end
    updateTabs()
    updateLegend()
    setRows(treeList, treeRows(), true)
    renderSections()
    renderLoot()
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local QUALITY_OPTIONS = {
    { 0, "Any quality" }, { 2, "Uncommon and better" }, { 3, "Rare and better" }, { 4, "Epic and better" },
}
local SLOT_OPTIONS = {
    { "", "Any slot" }, { "armor", "Armor" }, { "weapon", "Weapons" }, { "jewel", "Neck, rings, trinkets" },
    { "other", "Recipes and other" },
}
local HIGHLIGHT_OPTIONS = {
    { 1, "Default" }, { 2, "Highlight Forever changes" }, { 3, "Forever only" },
}

local function savePosition()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if point then settings().point = { point, relPoint, x, y } end
end

local function radioMenu(dropdown, options, get, set)
    dropdown:SetupMenu(function(_, root)
        for _, o in ipairs(options) do
            root:CreateRadio(o[2], function(v) return get() == v end, function(v) set(v) end, o[1])
        end
    end)
end

local function setHighlight(v)
    state.highlight = v
    settings().highlight = v
    renderAll()
end

local function setIconSize(v)
    state.iconSize = v
    settings().iconSize = v
    renderLoot(true)
end

local function resetWindow()
    local s = settings()
    s.size, s.point = nil, nil
    frame:SetSize(DEFAULT_W, DEFAULT_H)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
end

-- The options menu under the cogwheel. More options go here as Encore-DB grows.
function openOptions(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    hidePopup()
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Item icons")
        for _, o in ipairs(ICON_SIZE_OPTIONS) do
            root:CreateRadio(o[2], function(v) return state.iconSize == v end, setIconSize, o[1])
        end
        root:CreateDivider()
        root:CreateTitle("Highlighted items")
        for _, o in ipairs(HIGHLIGHT_OPTIONS) do
            root:CreateRadio(o[2], function(v) return state.highlight == v end, setHighlight, o[1])
        end
        root:CreateDivider()
        root:CreateCheckbox("Split Blackrock Spire into Lower and Upper", function() return settings().splitBRS == true end, function()
            settings().splitBRS = not settings().splitBRS or nil
            DB:ApplyOption("splitBRS")
        end)
        root:CreateCheckbox("Open random drops by default", function() return settings().randomOpen == true end, function()
            settings().randomOpen = not settings().randomOpen or nil
            DB:ApplyOption("randomOpen")
        end)
        root:CreateDivider()
        root:CreateButton("Reset window size and position", resetWindow)
    end)
end

-- A saved setting changed, from the cogwheel menu or from Options > AddOns > Encore-DB (EncoreEssentials
-- Options.lua writes the saved value first, then calls this). Brings the open window in line with it.
function DB:ApplyOption(key)
    local s = settings()
    if key == "splitBRS" then
        local current = state.inst and Loot.instances[state.inst]
        if ns.ApplyWings then ns.ApplyWings(Loot, s.splitBRS == true) end
        -- Stay on the same dungeon, or on its first wing / the whole dungeon it was a wing of
        state.inst = nil
        for i, inst in ipairs(Loot.instances) do
            if current and (inst == current or inst.parent == current.key or inst.key == current.parent) then
                state.inst = i
                break
            end
        end
        state.boss, state.randomOpen, whereIndex = 1, {}, nil
        renderAll()
    elseif key == "randomOpen" then
        state.randomOpen = {}
        renderLoot(true)
    elseif key == "highlight" then
        local h = tonumber(s.highlight)
        if h and h >= 1 and h <= 3 then setHighlight(h) end
    elseif key == "iconSize" then
        if ICON_SIZES[s.iconSize] then setIconSize(s.iconSize) end
    elseif key == "resetWindow" then
        if frame then resetWindow() end
    end
end

local function createWindow()
    frame = CreateFrame("Frame", "EncoreDBFrame", UIParent, "PortraitFrameTemplate")
    frame:Hide()
    tinsert(UISpecialFrames, "EncoreDBFrame")
    local saved = settings()
    local size = type(saved.size) == "table" and saved.size or {}
    frame:SetSize(math.max(MIN_W, tonumber(size[1]) or DEFAULT_W), math.max(MIN_H, tonumber(size[2]) or DEFAULT_H))
    local p = saved.point
    if type(p) == "table" and p[1] then
        frame:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else
        frame:SetPoint("CENTER")
    end
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_W, MIN_H)
    elseif frame.SetMinResize then
        frame:SetMinResize(MIN_W, MIN_H)
    end
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    frame:SetTitle("Encore-DB")
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)
    end

    -- Keep our title-bar and corner buttons above the window border. When the window
    -- is raised the client resets child frame levels, which let the border art
    -- (NineSlice) draw over them: they still took the mouse but looked invisible.
    local onTop = {}
    local function keepOnTop()
        local level = frame:GetFrameLevel() + 40
        if frame.NineSlice then level = math.max(level, frame.NineSlice:GetFrameLevel() + 5) end
        if frame.CloseButton then level = math.max(level, frame.CloseButton:GetFrameLevel()) end
        for _, b in ipairs(onTop) do b:SetFrameLevel(level) end
    end
    frame:HookScript("OnShow", keepOnTop)
    frame:HookScript("OnMouseDown", keepOnTop) -- a click raises the window
    hooksecurefunc(frame, "Raise", keepOnTop)
    hooksecurefunc(frame, "SetFrameLevel", keepOnTop)

    -- Options: a cogwheel left of the close button
    local cog = CreateFrame("Button", nil, frame)
    onTop[#onTop + 1] = cog
    cog:SetSize(18, 18)
    if frame.CloseButton then
        cog:SetPoint("RIGHT", frame.CloseButton, "LEFT", -2, 0)
    else
        cog:SetPoint("TOPRIGHT", -30, -4)
    end
    local function cogTexture(layer)
        local t = cog:CreateTexture(nil, layer, nil, 7)
        t:SetAllPoints()
        -- Bundled texture: the client's own gear atlases/files don't render on every client version
        if t:SetTexture("Interface\\AddOns\\EncoreEssentials_DB\\Media\\cogwheel") == false then
            t:SetTexture(ICONS .. "Trade_Engineering") -- file not found: the game's own gear icon
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        return t
    end
    cogTexture("OVERLAY")
    local cogLit = cogTexture("HIGHLIGHT")
    cogLit:SetBlendMode("ADD")
    cogLit:SetAlpha(0.5)
    cog:SetScript("OnClick", function(self) openOptions(self) end)
    cog:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText("Encore-DB options")
        GameTooltip:Show()
    end)
    cog:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local portrait = frame.GetPortrait and frame:GetPortrait() or frame.portrait
    if portrait then
        portrait:SetTexture(TEX.crest)
        portrait:SetTexCoord(0, 1, 0, 1)
    end
    -- Copper frame, as in the mock-up
    if frame.NineSlice then
        for _, region in ipairs({ frame.NineSlice:GetRegions() }) do
            if region.SetVertexColor then region:SetVertexColor(1, 0.74, 0.5) end
        end
    end
    gem(frame, "BOTTOMLEFT", 3, 3)

    -- Resize grip in the bottom-right corner
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -5, 5)
    onTop[#onTop + 1] = grip
    keepOnTop()
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    -- Sized by hand from the cursor: the client's StartSizing() snaps this frame
    -- straight to its maximum size on some client versions.
    local sizing
    local function stopSizing()
        if not sizing then return end
        sizing = nil
        grip:SetScript("OnUpdate", nil)
        settings().size = { math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5) }
        savePosition()
    end
    local function cursor()
        local x, y = GetCursorPosition()
        local s = frame:GetEffectiveScale()
        return x / s, y / s
    end
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        hidePopup()
        -- Pin the top-left corner so only the bottom-right edge follows the cursor
        local left, top = frame:GetLeft(), frame:GetTop()
        if not left or not top then return end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        local ratio = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
        local cx, cy = cursor()
        sizing = {
            x = cx, y = cy, w = frame:GetWidth(), h = frame:GetHeight(),
            maxW = math.max(MIN_W, UIParent:GetWidth() * ratio - left),
            maxH = math.max(MIN_H, top),
        }
        grip:SetScript("OnUpdate", function()
            if not IsMouseButtonDown("LeftButton") then return stopSizing() end
            local x, y = cursor()
            local w = math.min(sizing.maxW, math.max(MIN_W, sizing.w + (x - sizing.x)))
            local h = math.min(sizing.maxH, math.max(MIN_H, sizing.h + (sizing.y - y)))
            frame:SetSize(w, h)
        end)
    end)
    grip:SetScript("OnMouseUp", stopSizing)
    grip:SetScript("OnHide", stopSizing)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText("Drag to resize")
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Tabs
    local x = 66
    for _, t in ipairs(TABS) do
        local b = CreateFrame("Button", nil, frame)
        b.key, b.soon = t.key, t.soon
        b.bgOn = b:CreateTexture(nil, "BACKGROUND")
        b.bgOn:SetPoint("TOPLEFT", 1, -1); b.bgOn:SetPoint("BOTTOMRIGHT", -1, 0)
        gradient(b.bgOn, "VERTICAL", 0.23, 0.01, 0, 1, 0.76, 0.08, 0.05, 1)
        b.bgOff = b:CreateTexture(nil, "BACKGROUND")
        b.bgOff:SetPoint("TOPLEFT", 1, -1); b.bgOff:SetPoint("BOTTOMRIGHT", -1, 0)
        gradient(b.bgOff, "VERTICAL", 0.09, 0.06, 0.04, 1, 0.17, 0.13, 0.09, 1)
        b.edge = addBorder(b, COPPER[1], COPPER[2], COPPER[3], 1)
        b.edge[2]:Hide()
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 0)
        hl:SetColorTexture(1, 0.9, 0.6, 0.08)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("CENTER", 0, 0)
        b.text:SetText(t.text)
        b:SetSize(math.floor(b.text:GetStringWidth() + 28), 24)
        b:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", x, -58)
        x = x + b:GetWidth() + 3
        b:SetScript("OnClick", function() selectTab(t.key) end)
        tabButtons[#tabButtons + 1] = b
    end
    local tabLine = frame:CreateTexture(nil, "ARTWORK")
    tabLine:SetPoint("TOPLEFT", 8, -58); tabLine:SetPoint("TOPRIGHT", -8, -58); tabLine:SetHeight(1)
    tabLine:SetColorTexture(COPPER[1], COPPER[2], COPPER[3], 0.6)

    -- Filter strip
    local qLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    qLabel:SetPoint("TOPLEFT", 16, -72)
    qLabel:SetText("Quality")
    qualityDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    qualityDropdown:SetWidth(150)
    qualityDropdown:SetPoint("LEFT", qLabel, "RIGHT", 8, 0)
    radioMenu(qualityDropdown, QUALITY_OPTIONS, function() return state.quality end, function(v)
        state.quality = v
        renderLoot()
    end)

    local sLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sLabel:SetPoint("LEFT", qualityDropdown, "RIGHT", 14, 0)
    sLabel:SetText("Slot")
    slotDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    slotDropdown:SetWidth(130)
    slotDropdown:SetPoint("LEFT", sLabel, "RIGHT", 8, 0)
    radioMenu(slotDropdown, SLOT_OPTIONS, function() return state.slot end, function(v)
        state.slot = v
        renderLoot()
    end)

    -- "Highlighted items" lives in the cogwheel options menu only
    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetSize(64, 22)
    reset:SetPoint("LEFT", slotDropdown, "RIGHT", 12, 0)
    reset:SetText("Reset")
    reset:SetScript("OnClick", function()
        state.quality, state.slot = 0, ""
        for _, d in ipairs({ qualityDropdown, slotDropdown }) do
            if d.GenerateMenu then d:GenerateMenu() end
        end
        clearSearch()
        renderAll()
    end)

    searchBox = CreateFrame("EditBox", "EncoreDBSearchBox", frame, "SearchBoxTemplate")
    searchBox:SetSize(180, 20)
    searchBox:SetPoint("TOPRIGHT", -18, -73)
    searchBox:SetAutoFocus(false)
    if searchBox.Instructions then searchBox.Instructions:SetText("Search loot and recipes") end
    -- Searches a moment after typing stops, so each letter doesn't ask the game for every matching item.
    searchBox:HookScript("OnTextChanged", function(self)
        local text = strtrim(self:GetText() or "")
        self.typed = (self.typed or 0) + 1
        if text == state.search then return end
        local apply = function()
            if strtrim(self:GetText() or "") ~= text then return end
            state.search = text
            renderLoot()
        end
        if text == "" then apply() return end
        local token = self.typed
        C_Timer.After(0.3, function() if token == self.typed then apply() end end)
    end)

    -- Panes
    local treePane = well(12, TREE_W)
    local secPane = well(12 + TREE_W + 6, SEC_W)
    local lootPane = well(12 + TREE_W + 6 + SEC_W + 6, nil)
    measure = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    measure:SetWordWrap(true)
    measure:SetAlpha(0) -- never anchored, so never drawn; only measures wrapped text
    treeList = createList(treePane, function() return TREE_W - 40 end)
    secList = createList(secPane, function() return SEC_W - 40 end)
    lootList = createList(lootPane, function(box) return math.max(100, box:GetWidth() - 22) end)

    -- Re-lay the item grid when the window is resized (more or fewer items side by side).
    local relayoutPending = false
    lootList:HookScript("OnSizeChanged", function()
        if relayoutPending or not frame:IsShown() then return end
        relayoutPending = true
        C_Timer.After(0.1, function()
            relayoutPending = false
            if frame:IsShown() then renderLoot(true) end
        end)
    end)

    -- Status bar
    local credit = CreateFrame("Button", nil, frame)
    credit:SetPoint("BOTTOMRIGHT", -26, 8)
    credit:SetHeight(18)
    credit.text = credit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    credit.text:SetPoint("RIGHT")
    credit.text:SetText(DB.Credit)
    setColor(credit.text, DIM)
    credit:SetWidth(credit.text:GetStringWidth() + 4)
    credit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText("Encore-DB data")
        GameTooltip:AddLine(DB.Credit, 1, 1, 1, true)
        GameTooltip:AddLine("Filled in from foreverchanges.pro, Wowhead Forever and the game itself.", 1, 1, 1, true)
        GameTooltip:AddLine("Boss portraits from Dungeon Journal by Exehn.", 1, 1, 1, true)
        GameTooltip:AddLine("Only what players saw in WoW Forever. No Classic or emulator data.", DIM[1], DIM[2], DIM[3], true)
        GameTooltip:Show()
    end)
    credit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    legend = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    legend:SetPoint("RIGHT", credit, "LEFT", -18, 0)
    legend:SetText("New or changed in WoW Forever")
    setColor(legend, TEAL_SOFT)
    legendGem = frame:CreateTexture(nil, "OVERLAY")
    legendGem:SetSize(7, 7)
    legendGem:SetPoint("RIGHT", legend, "LEFT", -6, 0)
    legendGem:SetColorTexture(TEAL_SOFT[1], TEAL_SOFT[2], TEAL_SOFT[3], 1)
    legendGem:SetRotation(math.rad(45))

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("LEFT", frame, "BOTTOMLEFT", 16, 17)
    statusText:SetPoint("RIGHT", legendGem, "LEFT", -20, 0)
    statusText:SetJustifyH("LEFT")
    statusText:SetWordWrap(false)
    setColor(statusText, DIM)

    createPopup()
    createResolver()

    -- Items missing from the game's cache arrive a moment after they are asked for.
    -- Redraw the item pane (at most every 0.3 s) as they arrive.
    local refreshPending = false
    local watcher = CreateFrame("Frame", nil, frame)
    watcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    watcher:SetScript("OnEvent", function(_, _, _, success)
        if success == false then return end -- an item the server does not know
        if refreshPending or not frame:IsShown() then return end
        refreshPending = true
        C_Timer.After(0.3, function()
            refreshPending = false
            if frame:IsShown() then
                renderLoot(true)
                -- Profession categories and item sets count items the game has just loaded.
                if state.tab == "professions" then renderSections() end
            end
        end)
    end)

    frame:HookScript("OnShow", function()
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
        renderAll()
    end)
    frame:HookScript("OnHide", function()
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
        GameTooltip:Hide()
        hidePopup()
        -- Each portrait the game draws is a render target; let them go while the window is closed
        -- (the rows draw them again on the next open).
        if secList and secList.ForEachFrame then
            secList:ForEachFrame(function(row)
                if row.portrait then row.portrait:SetTexture(nil) end
            end)
        end
    end)
end

-- What QuestView.lua (and later views in their own files) build on. Window.lua is close to Lua's limit of
-- 200 file-level locals, so new views live in their own files and get the shared pieces from here.
ns.UI = {
    state = state, settings = settings, rowKinds = ROW_KINDS, lineFonts = LINE_FONTS,
    heading = heading, textLine = textLine, emptyLine = emptyLine, grid = grid,
    recipesOf = recipesOf, skillBrackets = SKILL_BRACKETS, inBracket = inBracket,
    itemInfo = itemInfo, cellFromInfo = cellFromInfo, recipeCell = recipeCell, passesRecipe = passesRecipe, passesInfo = passesInfo, coin = coin,
    mapName = mapName, setPin = setPin, highlightOn = highlightOn,
    setColor = setColor, gradient = gradient, addBorder = addBorder, onRowClick = onRowClick,
    colors = { TEAL = TEAL, TEAL_SOFT = TEAL_SOFT, COPPER = COPPER, GOLD = GOLD, INK = INK, DIM = DIM, TEAL_HEX = TEAL_HEX },
    renderLoot = function(keepScroll) renderLoot(keepScroll) end,
    renderAll = function() renderAll() end,
    clearSearch = function() clearSearch() end,
    isShown = function() return frame ~= nil and frame:IsShown() end,
}

-- Inside a dungeon or raid Encore-DB knows, opening the window shows it (once per visit, so browsing other
-- dungeons from inside still works). Wings sharing one map are told apart by the subzone name.
function DB:ShowCurrentInstance()
    if not (IsInInstance and GetInstanceInfo) then return false end
    local inside, kind = IsInInstance()
    if not inside or (kind ~= "party" and kind ~= "raid") then state.autoInstance = nil return false end
    local name, _, _, _, _, _, _, id = GetInstanceInfo()
    if not id or id == state.autoInstance then return false end
    name = (name or ""):lower()
    local sub = (GetSubZoneText and GetSubZoneText() or ""):lower()
    local found, wing
    for i, inst in ipairs(Loot.instances or {}) do
        if inst.foreverdb == id or (not inst.foreverdb and inst.name:lower() == name) then
            found = found or i
            if sub ~= "" and inst.parent and inst.name:lower():find(sub, 1, true) then wing = i end
        end
    end
    found = wing or found
    if not found then return false end
    state.autoInstance = id
    if state.inst ~= found then state.inst, state.boss = found, 1 end
    state.tab = "dungeons"
    settings().tab = "dungeons"
    return true
end

function DB:ToggleWindow()
    if not frame then
        local saved = settings()
        if saved.tab and TAB_BY_KEY[saved.tab] then state.tab = saved.tab end
        if type(saved.inst) == "string" then
            for i, inst in ipairs(Loot.instances or {}) do
                if inst.key == saved.inst then
                    state.inst = i
                    local b = saved.boss
                    if b == "quests" or (type(b) == "number" and inst.bosses and inst.bosses[b]) then state.boss = b end
                    break
                end
            end
        end
        local h = tonumber(saved.highlight)
        if h and h >= 1 and h <= 3 then state.highlight = h end
        if ICON_SIZES[saved.iconSize] then state.iconSize = saved.iconSize end
        createWindow()
    end
    if not frame:IsShown() then
        if DB:ShowCurrentInstance() then clearSearch() end
    end
    frame:SetShown(not frame:IsShown())
end
