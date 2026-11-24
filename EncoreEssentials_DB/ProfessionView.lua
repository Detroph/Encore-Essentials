-- Encore-DB Professions tab, middle and right panes. Middle: all recipes, then the recipes sorted by what they make
-- (Weapons - Maces, Armor - Chest, Enhancements, Potions, item sets ...), then by skill bracket. Right: the recipes of the
-- choice, with columns side by side where a category splits in two (one-handed and two-handed weapons; cloth, leather,
-- mail and plate armour). The grouping follows the game's own item classes (GetItemInfoInstant) and the recipe and item
-- names; it is our own, written for Encore-DB. Window.lua calls in here (it is near Lua's local limit).
local _, ns = ...

local View = {}
ns.ProfessionView = View

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
local function ui() return ns.UI end

-- Categories, in the order the middle pane lists them. Keys starting "ench:" are made per enchanted slot.
local CATS = {
    { key = "w:dagger", text = "Weapons - Daggers", plural = "Daggers" },
    { key = "w:axe", text = "Weapons - Axes", plural = "Axes" },
    { key = "w:mace", text = "Weapons - Maces", plural = "Maces" },
    { key = "w:sword", text = "Weapons - Swords", plural = "Swords" },
    { key = "w:polearm", text = "Weapons - Polearms", plural = "Polearms" },
    { key = "w:staff", text = "Weapons - Staves", plural = "Staves" },
    { key = "w:fist", text = "Weapons - Fist Weapons", plural = "Fist Weapons" },
    { key = "w:gun", text = "Weapons - Guns", plural = "Guns" },
    { key = "w:bow", text = "Weapons - Bows", plural = "Bows" },
    { key = "w:crossbow", text = "Weapons - Crossbows", plural = "Crossbows" },
    { key = "w:wand", text = "Weapons - Wands", plural = "Wands" },
    { key = "w:thrown", text = "Weapons - Thrown", plural = "Thrown" },
    { key = "w:other", text = "Weapons - Other", plural = "Weapons" },
    { key = "a:head", text = "Armor - Head" },
    { key = "a:shoulder", text = "Armor - Shoulder" },
    { key = "a:back", text = "Armor - Back" },
    { key = "a:chest", text = "Armor - Chest" },
    { key = "a:wrist", text = "Armor - Wrist" },
    { key = "a:hands", text = "Armor - Hands" },
    { key = "a:waist", text = "Armor - Waist" },
    { key = "a:legs", text = "Armor - Legs" },
    { key = "a:feet", text = "Armor - Feet" },
    { key = "a:neck", text = "Armor - Neck" },
    { key = "a:finger", text = "Armor - Rings" },
    { key = "a:trinket", text = "Armor - Trinkets" },
    { key = "a:shirt", text = "Armor - Shirts" },
    { key = "a:tabard", text = "Armor - Tabards" },
    { key = "a:offhand", text = "Armor - Off-hand" },
    { key = "a:other", text = "Armor - Other" },
    { key = "shield", text = "Shields" },
    { key = "ench:Boots", text = "Enchants - Boots" },
    { key = "ench:Bracer", text = "Enchants - Bracer" },
    { key = "ench:Chest", text = "Enchants - Chest" },
    { key = "ench:Cloak", text = "Enchants - Cloak" },
    { key = "ench:Gloves", text = "Enchants - Gloves" },
    { key = "ench:Shield", text = "Enchants - Shield" },
    { key = "ench:Weapon", text = "Enchants - Weapon" },
    { key = "ench:2H Weapon", text = "Enchants - 2H Weapon" },
    { key = "flask", text = "Flasks" },
    { key = "elixir", text = "Elixirs" },
    { key = "potion", text = "Potions" },
    { key = "protection", text = "Protection potions" },
    { key = "transmute", text = "Transmutes" },
    { key = "oil", text = "Oils" },
    { key = "rod", text = "Rods" },
    { key = "enhancement", text = "Enhancements" },
    { key = "explosive", text = "Explosives" },
    { key = "firework", text = "Fireworks" },
    { key = "device", text = "Devices" },
    { key = "parts", text = "Parts" },
    { key = "pet", text = "Pets" },
    { key = "ammo", text = "Ammo" },
    { key = "bag", text = "Bags" },
    { key = "quiver", text = "Quivers and ammo pouches" },
    { key = "bandage", text = "Bandages" },
    { key = "food", text = "Food and drink" },
    { key = "material", text = "Materials" },
    { key = "misc", text = "Misc" },
}
local CAT_BY_KEY = {}
for i, c in ipairs(CATS) do c.order = i; CAT_BY_KEY[c.key] = c end
local function catOf(key)
    if not CAT_BY_KEY[key] then -- an enchanted slot not in the list above
        local c = { key = key, text = "Enchants - " .. key:sub(6), order = CAT_BY_KEY["ench:2H Weapon"].order + 0.5 }
        CATS[#CATS + 1] = c
        CAT_BY_KEY[key] = c
    end
    return CAT_BY_KEY[key]
end

-- Game item classes (Enum.ItemClass) and their subclasses.
local C_CONSUMABLE, C_CONTAINER, C_WEAPON, C_ARMOR, C_PROJECTILE, C_TRADE, C_ENHANCEMENT, C_QUIVER, C_MISC = 0, 1, 2, 4, 6, 7, 8, 11, 15
-- Weapon subclass -> category, and whether it is two-handed.
local WEAPON = {
    [0] = "w:axe", [1] = "w:axe", [2] = "w:bow", [3] = "w:gun", [4] = "w:mace", [5] = "w:mace", [6] = "w:polearm",
    [7] = "w:sword", [8] = "w:sword", [10] = "w:staff", [13] = "w:fist", [15] = "w:dagger", [16] = "w:thrown",
    [17] = "w:polearm", [18] = "w:crossbow", [19] = "w:wand",
}
local TWO_HANDED = { [1] = true, [5] = true, [8] = true }
local ARMOR_SLOT = {
    INVTYPE_HEAD = "a:head", INVTYPE_SHOULDER = "a:shoulder", INVTYPE_CLOAK = "a:back", INVTYPE_CHEST = "a:chest",
    INVTYPE_ROBE = "a:chest", INVTYPE_WRIST = "a:wrist", INVTYPE_HAND = "a:hands", INVTYPE_WAIST = "a:waist",
    INVTYPE_LEGS = "a:legs", INVTYPE_FEET = "a:feet", INVTYPE_NECK = "a:neck", INVTYPE_FINGER = "a:finger",
    INVTYPE_TRINKET = "a:trinket", INVTYPE_BODY = "a:shirt", INVTYPE_TABARD = "a:tabard", INVTYPE_HOLDABLE = "a:offhand",
    INVTYPE_SHIELD = "shield",
}
-- Armour columns, left to right. Cloaks are cloth to the game, but every cloak goes in one list.
local ARMOR_TYPE = { [1] = { 1, "Cloth" }, [2] = { 2, "Leather" }, [3] = { 3, "Mail" }, [4] = { 4, "Plate" } }

local function has(name, ...)
    for i = 1, select("#", ...) do
        if name:find((select(i, ...))) then return true end
    end
    return false
end

-- The category of one recipe, and its column inside the category: col = { order, title } or nil for one list.
local function classify(r, prof)
    local spellName, makes = r[2] or "", r[7]
    if not makes then
        local slot = spellName:match("^Enchant (.-) %- ")
        if slot then return "ench:" .. slot end
        return "misc"
    end
    local _, _, _, equipLoc, _, classID, subID
    if GetItemInfoInstant then _, _, _, equipLoc, _, classID, subID = GetItemInfoInstant(makes) end
    local name = (GetItemInfo and GetItemInfo(makes)) or spellName
    if prof == "Alchemy" and has(spellName, "^Transmute") then return "transmute" end
    if classID == C_WEAPON then
        local key = WEAPON[subID] or "w:other"
        local cat = CAT_BY_KEY[key]
        if key == "w:axe" or key == "w:mace" or key == "w:sword" then
            if TWO_HANDED[subID] then return key, { 2, "Two-Handed " .. cat.plural } end
            return key, { 1, "One-Handed " .. cat.plural }
        end
        return key
    end
    if classID == C_ARMOR then
        local key = (subID == 6 and "shield") or ARMOR_SLOT[equipLoc]
        if not key then return "misc" end
        if key == "a:back" or key == "shield" then return key end
        return key, ARMOR_TYPE[subID]
    end
    if classID == C_CONTAINER then return "bag" end
    if classID == C_QUIVER then return "quiver" end
    if classID == C_PROJECTILE then
        return "ammo", (subID == 2 and { 1, "Arrows" }) or (subID == 3 and { 2, "Bullets" }) or nil
    end
    if classID == C_MISC and subID == 2 then return "pet" end
    if prof == "Alchemy" then
        if has(name, "^Flask ") then return "flask" end
        if has(name, "Protection Potion") then return "protection" end
        if has(name, "Elixir") then return "elixir" end
        if has(name, "Potion", "Draught", "Philter") then
            if has(name, "Healing", "Mana", "Rejuvenation", "Restorative") then return "potion", { 1, "Healing and mana" } end
            return "potion", { 2, "Other potions" }
        end
        if has(name, " Oil$", "^Oil of ") then return "oil" end
    end
    if prof == "Enchanting" then
        if has(name, " Rod$") then return "rod" end
        if has(name, " Oil$") then return "oil" end
    end
    if classID == C_CONSUMABLE and has(name, "Potion$") then -- healing potions some other professions make
        if has(name, "Healing", "Mana") then return "potion", { 1, "Healing and mana" } end
        return "potion", { 2, "Other potions" }
    end
    if prof == "Alchemy" and classID == C_CONSUMABLE then
        if subID == 3 then return "flask" end
        if subID == 2 then return "elixir" end
        if subID == 1 then return "potion", { 2, "Other potions" } end
    end
    if (prof == "First Aid" and has(name, "Bandage")) or (classID == C_CONSUMABLE and subID == 7) then return "bandage" end
    if classID == C_ENHANCEMENT or (classID == C_CONSUMABLE and subID == 6) or has(name, "Armor Kit$", "Sharpening Stone$", "Weightstone$", " Scope$", "Shield Spike$",
        " Spurs$", "Counterweight$", " Oil$") then
        return "enhancement"
    end
    if prof == "Engineering" then
        if (classID == C_TRADE and subID == 2) or has(name, "Bomb", "Dynamite", "Grenade", "Explosive Charge", "Sapper", "Land Mine") then
            return "explosive"
        end
        if has(name, "Firework", "Rocket", "Flare", "Launcher") then return "firework" end
        if classID == C_TRADE and subID == 1 then return "parts" end
        if classID == C_TRADE and subID == 3 then return "device" end
    end
    if classID == C_CONSUMABLE and subID == 5 then return "food" end
    if prof == "Cooking" and classID == C_CONSUMABLE then return "food" end
    if classID == C_TRADE then
        if subID == 1 then return "parts" end
        if subID == 2 then return "explosive" end
        if subID == 3 then return "device" end
        return "material"
    end
    return "misc"
end

-- [prof] = { [recipe] = { key = category, col = column } }. Built once a profession is first shown; recipes whose
-- item the game does not know yet are looked at again later.
local cache = {}
local function catInfo(r, prof)
    cache[prof] = cache[prof] or {}
    local c = cache[prof][r]
    if not c then
        local key, col = classify(r, prof)
        c = { key = key, col = col }
        -- Item details may still be loading: keep the answer only when the game knew the item.
        if not r[7] or (GetItemInfoInstant and GetItemInfoInstant(r[7])) then cache[prof][r] = c end
    end
    return c
end

-- Item sets a profession makes: the game's set ID (once the item is loaded), else the sets in Data/Extras.lua.
local dataSets
local function dataSetOf(item)
    if not dataSets then
        dataSets = {}
        for _, g in ipairs(ns.ItemSets or {}) do
            for _, s in ipairs(g.sets or {}) do
                for _, p in ipairs(s.pieces or {}) do dataSets[p] = s end
            end
        end
    end
    return dataSets[item]
end
local function setIDOf(item)
    local s = dataSetOf(item)
    if s and s.id then return s.id end
    if GetItemInfo then
        local id = select(16, GetItemInfo(item))
        if type(id) == "number" and id > 0 then return id end
    end
end

-- A set's name: Data/Extras.lua's, the game's, or the words all its pieces' names start with ("Acolyte's set").
local function setName(id, pieces)
    for _, p in ipairs(pieces) do
        local s = dataSetOf(p)
        if s and s.id == id then return s.name end
    end
    local fn = (C_Item and C_Item.GetItemSetInfo) or _G.GetItemSetInfo
    if fn then
        local ok, name = pcall(fn, id)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    local common
    for _, p in ipairs(pieces) do
        local words = {}
        for w in (((GetItemInfo and GetItemInfo(p)) or "")):gmatch("%S+") do words[#words + 1] = w end
        if not common then
            common = words
        else
            local n = 0
            while n < #common and n < #words and common[n + 1] == words[n + 1] do n = n + 1 end
            for i = #common, n + 1, -1 do common[i] = nil end
        end
    end
    if common and #common > 0 then
        -- "Azure Skyforged Chain" and "Azure Skyforged Helm" share "Azure Skyforged"; one piece alone keeps its full name.
        if #pieces > 1 then return table.concat(common, " ") .. " set" end
        return table.concat(common, " ")
    end
    return "Item set " .. id
end

-- { { id, name, recipes = { ... } }, ... }, sorted by the lowest skill a piece is learned at.
local function setsOf(prof, list)
    local byID, out = {}, {}
    for _, r in ipairs(list) do
        local id = r[7] and setIDOf(r[7])
        if id then
            if not byID[id] then
                byID[id] = { id = id, recipes = {}, pieces = {}, skill = 100000 }
                out[#out + 1] = byID[id]
            end
            local s = byID[id]
            s.recipes[#s.recipes + 1] = r
            s.pieces[#s.pieces + 1] = r[7]
            s.skill = math.min(s.skill, r[3] or r[4] or 100000)
        end
    end
    for _, s in ipairs(out) do s.name = setName(s.id, s.pieces) end
    table.sort(out, function(a, b)
        if a.skill ~= b.skill then return a.skill < b.skill end
        return a.name < b.name
    end)
    return out
end

-- Ask the game once for every item a profession makes, so item classes and set IDs are there when the lists are drawn.
local requested = {}
local function requestAll(prof, list)
    if requested[prof] then return end
    requested[prof] = true
    if not (C_Item and C_Item.RequestLoadItemDataByID) then return end
    for _, r in ipairs(list) do
        if r[7] and not (GetItemInfo and GetItemInfo(r[7])) then pcall(C_Item.RequestLoadItemDataByID, r[7]) end
    end
end

-- { { cat, recipes = { ... }, forever = n }, ... } in category order.
local function categories(prof, list)
    local byKey, out = {}, {}
    for _, r in ipairs(list) do
        local key = catInfo(r, prof).key
        local g = byKey[key]
        if not g then
            g = { cat = catOf(key), recipes = {}, forever = 0 }
            byKey[key] = g
            out[#out + 1] = g
        end
        g.recipes[#g.recipes + 1] = r
        if r.new or r.changed then g.forever = g.forever + 1 end
    end
    table.sort(out, function(a, b) return a.cat.order < b.cat.order end)
    return out
end

local function foreverCount(list)
    local n = 0
    for _, r in ipairs(list) do if r.new or r.changed then n = n + 1 end end
    return n
end

local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

-- Middle pane.
function View.sections(rows)
    local U = ui()
    local state = U.state
    local prof = state.prof
    if not prof then return end
    local list = U.recipesOf(prof)
    requestAll(prof, list)
    local function pick(value)
        return function() state.bracket = value; U.clearSearch(); U.renderAll() end
    end
    local n = foreverCount(list)
    rows[#rows + 1] = { kind = "head", title = prof, meta = plural(#list, "recipe", "recipes")
        .. ((U.highlightOn() and n > 0) and ("  ·  %s%d new or changed in WoW Forever|r"):format(U.colors.TEAL_HEX, n) or "") }
    rows[#rows + 1] = {
        kind = "sec", text = "All recipes", sub = plural(#list, "recipe", "recipes"), pip = n,
        selected = state.bracket == 1, onClick = pick(1),
    }
    local cats = categories(prof, list)
    local sets = setsOf(prof, list)
    if #cats > 1 or #sets > 0 then
        rows[#rows + 1] = { kind = "heading", text = "By type" }
        for _, g in ipairs(cats) do
            rows[#rows + 1] = {
                kind = "sec", text = g.cat.text, sub = plural(#g.recipes, "recipe", "recipes"), pip = g.forever,
                selected = state.bracket == g.cat.key, onClick = pick(g.cat.key),
            }
        end
        if #sets > 0 then
            local pieces = 0
            for _, s in ipairs(sets) do pieces = pieces + #s.recipes end
            rows[#rows + 1] = {
                kind = "sec", text = "Item sets", sub = plural(#sets, "set", "sets") .. "  ·  " .. plural(pieces, "recipe", "recipes"),
                selected = state.bracket == "sets", onClick = pick("sets"),
            }
        end
    end
    local first = true
    for i, b in ipairs(U.skillBrackets) do
        if i > 1 then
            local count, nForever = 0, 0
            for _, r in ipairs(list) do
                if U.inBracket(r, b) then
                    count = count + 1
                    if r.new or r.changed then nForever = nForever + 1 end
                end
            end
            if count > 0 then
                if first then rows[#rows + 1] = { kind = "heading", text = "By skill" }; first = false end
                rows[#rows + 1] = {
                    kind = "sec", text = b.text, sub = (b.sub and (b.sub .. "  ·  ") or "") .. plural(count, "recipe", "recipes"),
                    pip = nForever, selected = state.bracket == i, onClick = pick(i),
                }
            end
        end
    end
end

-- Recipe cells of a list that pass the filters; total counts them all.
local function cellsOf(recipes)
    local U = ui()
    local cells = {}
    for _, r in ipairs(recipes) do
        local c = U.recipeCell(r)
        if U.passesRecipe(r, c) then cells[#cells + 1] = c end
    end
    return cells
end

-- Right pane.
function View.blocks()
    local U = ui()
    local state = U.state
    local prof = state.prof
    if not prof then return { U.emptyLine("Pick a profession on the left.") }, "" end
    local list = U.recipesOf(prof)
    local blocks, shown = {}, 0
    local FILTERED = "Nothing here matches the filters. Press Reset to show everything."
    local status = "Click a recipe for reagents and how to learn it."
    local sel = state.bracket

    if sel == "sets" then
        blocks[#blocks + 1] = U.heading(prof .. ": item sets")
        local all = {}
        for _, s in ipairs(setsOf(prof, list)) do
            local cells = cellsOf(s.recipes)
            if #cells > 0 then
                blocks[#blocks + 1] = U.heading(("%s (%d)"):format(s.name, #s.recipes))
                local g = U.grid(cells)
                g.defaultSort, g.layoutCells = "skill", all
                for _, c in ipairs(cells) do all[#all + 1] = c end
                blocks[#blocks + 1] = g
                shown = shown + #cells
            end
        end
        if shown == 0 then blocks[#blocks + 1] = U.emptyLine(#blocks > 1 and FILTERED or "No item sets here.") end
        return blocks, ("%s, item sets: %d recipes shown. %s"):format(prof, shown, status)
    end

    if type(sel) == "string" then
        local group
        for _, g in ipairs(categories(prof, list)) do if g.cat.key == sel then group = g end end
        if not group then sel, state.bracket = 1, 1 end
        if group then
            blocks[#blocks + 1] = U.heading(prof .. ": " .. group.cat.text)
            -- Columns inside the category (one- and two-handed, armour types), left to right.
            local cols, byOrder = {}, {}
            for _, r in ipairs(group.recipes) do
                local col = catInfo(r, prof).col or { 0, "" }
                local c = byOrder[col[1]]
                if not c then
                    c = { order = col[1], title = col[2], recipes = {} }
                    byOrder[col[1]] = c
                    cols[#cols + 1] = c
                end
                c.recipes[#c.recipes + 1] = r
            end
            table.sort(cols, function(a, b) return a.order < b.order end)
            local all, split = {}, {}
            for _, c in ipairs(cols) do
                c.cells = cellsOf(c.recipes)
                for _, cell in ipairs(c.cells) do all[#all + 1] = cell end
                if #c.cells > 0 then split[#split + 1] = { title = c.title ~= "" and c.title or nil, cells = c.cells } end
            end
            shown = #all
            if shown == 0 then
                blocks[#blocks + 1] = U.emptyLine(FILTERED)
            elseif #split == 1 or (#split > 1 and #split <= 3) then
                -- One list, or up to three lists side by side, each with its own column of the grid.
                local g = U.grid(all)
                g.defaultSort = "skill"
                if #split > 1 then g.split = split end
                blocks[#blocks + 1] = g
            else
                -- Four armour types: one list under the other.
                for _, s in ipairs(split) do
                    blocks[#blocks + 1] = U.heading(s.title or "Other")
                    local g = U.grid(s.cells)
                    g.defaultSort, g.layoutCells = "skill", all
                    blocks[#blocks + 1] = g
                end
            end
            return blocks, ("%s, %s: %d recipes shown. %s"):format(prof, group.cat.text, shown, status)
        end
    end

    local b = U.skillBrackets[sel] or U.skillBrackets[1]
    blocks[#blocks + 1] = U.heading(prof .. ": " .. b.text)
    local inB, total = {}, 0
    for _, r in ipairs(list) do
        if U.inBracket(r, b) then total = total + 1; inB[#inB + 1] = r end
    end
    local cells = cellsOf(inB)
    if #cells > 0 then
        local g = U.grid(cells)
        g.defaultSort = "skill" -- lowest skill to learn first, from a recipe or a trainer
        blocks[#blocks + 1] = g
    else
        blocks[#blocks + 1] = U.emptyLine(total > 0 and FILTERED or "No recipes here.")
    end
    return blocks, ("%s: %d recipes shown. %s"):format(prof, #cells, status)
end

-- For the test harness.
View.classify = classify
