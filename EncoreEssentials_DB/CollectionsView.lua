-- Encore-DB Collections tab: mounts, companions, tabards and legendaries (ns.Collections), item sets
-- (ns.ItemSets, shown by class) and class skills such as rogue poisons (ns.ClassSkills), all from Data/Extras.lua. Left: the
-- collections, the item set groups and the class skills. Middle: where the items come from, the sets in a group, or
-- the levels a skill is learned at. Right: the items or recipes. Window.lua calls in here (it is near Lua's local limit).
local _, ns = ...

local View = {}
ns.CollectionsView = View

local SIDE_TEXT = { A = "Alliance", H = "Horde" }
local function ui() return ns.UI end
local function cols() return ns.Collections or {} end
local function classSkills() return ns.ClassSkills or {} end

-- Item sets are shown by class: ns.ItemSets is grouped by source (PvP, Zul'Gurub, Ahn'Qiraj, later dungeon and tier
-- sets), and here every set with a class goes under that class, whatever its source. Sets without a class stay in
-- their source group (e.g. "Other sets"). Any new source group in Data/Extras.lua is picked up the same way.
local CLASS_ORDER = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
-- Class icon coordinates in the game's class icon sheets (same as CLASS_ICON_TCOORDS, for clients without it)
local CLASS_COORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
    DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 },
}
local CLASS_SQUARES = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local function classCoords(class)
    local tok = class and class:upper()
    if not tok then return nil end
    return (CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[tok]) or CLASS_COORDS[tok]
end

local byClassCache, byClassSource
-- { { key, text, class, sets = { { set = s, source = groupText }, ... } }, ... }: classes first, then classless groups.
local function setGroups()
    local src = ns.ItemSets or {}
    if byClassCache and byClassSource == src then return byClassCache end
    local list, byKey = {}, {}
    local function group(key, text, class)
        if not byKey[key] then
            byKey[key] = { key = key, text = text, class = class, sets = {} }
            list[#list + 1] = byKey[key]
        end
        return byKey[key]
    end
    for _, c in ipairs(CLASS_ORDER) do group("class:" .. c, c, c) end
    for _, g in ipairs(src) do
        for _, s in ipairs(g.sets) do
            local t = s.class and group("class:" .. s.class, s.class, s.class) or group("src:" .. g.text, g.text)
            t.sets[#t.sets + 1] = { set = s, source = g.text }
        end
    end
    local out = {}
    for _, t in ipairs(list) do if #t.sets > 0 then out[#out + 1] = t end end
    byClassCache, byClassSource = out, src
    return out
end
local function setGroupByKey(key)
    for _, g in ipairs(setGroups()) do if g.key == key then return g end end
end
-- The levels a class skill's recipes are learned at, lowest first: { { level, recipes = { ... } } }.
local function skillLevels(k)
    local by, list = {}, {}
    for _, r in ipairs(k.recipes) do
        local lv = r.level or 0
        if not by[lv] then by[lv] = { level = lv, recipes = {} }; list[#list + 1] = by[lv] end
        local t = by[lv].recipes
        t[#t + 1] = r
    end
    table.sort(list, function(a, b) return a.level < b.level end)
    return list
end

local function count(c)
    local n = 0
    for _, g in ipairs(c.groups) do n = n + #g.items end
    return n
end

-- state.colCat: a collection key, "set:<group key>" for an item set group (a class), or "skill<i>" for class skill i.
-- state.colPart: a group, set or level index, nil = all.
local function current()
    local st = ui().state
    local k = st.colCat
    if type(k) == "string" then
        local sk = k:match("^set:(.+)$")
        local sg = sk and setGroupByKey(sk)
        if sg then return nil, sg end
        local ki = tonumber(k:match("^skill(%d+)$"))
        if ki and classSkills()[ki] then return nil, nil, classSkills()[ki] end
        for _, c in ipairs(cols()) do if c.key == k then return c end end
    end
    if cols()[1] then st.colCat = cols()[1].key; return cols()[1] end
    if setGroups()[1] then st.colCat = "set:" .. setGroups()[1].key; return nil, setGroups()[1] end
end

function View.tree(pick)
    local st = ui().state
    local groups = {}
    local entries = {}
    for _, c in ipairs(cols()) do
        entries[#entries + 1] = {
            kind = "leaf", text = c.text, right = tostring(count(c)), selected = st.colCat == c.key,
            onClick = function() st.colCat, st.colPart = c.key, nil; pick() end,
        }
    end
    groups[#groups + 1] = { key = "colItems", text = "Collections", entries = entries }
    entries = {}
    for _, g in ipairs(setGroups()) do
        local cat = "set:" .. g.key
        local coords = classCoords(g.class)
        entries[#entries + 1] = {
            kind = "leaf", text = g.text, right = tostring(#g.sets), selected = st.colCat == cat,
            icon = coords and CLASS_SQUARES, iconCoords = coords,
            onClick = function() st.colCat, st.colPart = cat, nil; pick() end,
        }
    end
    groups[#groups + 1] = { key = "colSets", text = "Item sets", entries = entries }
    if classSkills()[1] then
        entries = {}
        for i, k in ipairs(classSkills()) do
            entries[#entries + 1] = {
                kind = "leaf", text = k.text, right = tostring(#k.recipes), selected = st.colCat == "skill" .. i,
                onClick = function() st.colCat, st.colPart = "skill" .. i, nil; pick() end,
            }
        end
        groups[#groups + 1] = { key = "colSkills", text = "Class skills", entries = entries }
    end
    return groups
end

-- e = { set, source }: the source group, the side and the piece count, e.g. "Zul'Gurub  ·  Horde  ·  4 pieces".
local function setSub(e, classless)
    local s, t = e.set, {}
    if not classless then t[#t + 1] = e.source end
    if s.side then t[#t + 1] = SIDE_TEXT[s.side] end
    t[#t + 1] = #s.pieces .. " pieces"
    return table.concat(t, "  ·  ")
end

-- The round icon on a set's row: its class icon, or for a set without a class the icon of its first piece.
local function setBadge(sg, s)
    local coords = classCoords(sg.class)
    if coords then return CLASS_CIRCLES, coords, 56 end
    local id = s.pieces[1]
    local tex = id and ((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id)))
    if tex then return tex, nil, 36 end
end

function View.sections(rows)
    local st = ui().state
    local function choose(i) return function() st.colPart = i; ui().clearSearch(); ui().renderAll() end end
    local c, sg, k = current()
    if c then
        rows[#rows + 1] = { kind = "head", title = c.text, meta = count(c) .. " items  ·  sources from Wowhead Forever" }
        rows[#rows + 1] = { kind = "sec", text = "All sources", sub = count(c) .. " items", selected = st.colPart == nil, onClick = choose(nil) }
        for i, g in ipairs(c.groups) do
            rows[#rows + 1] = { kind = "sec", text = g.text, sub = #g.items .. (#g.items == 1 and " item" or " items"), selected = st.colPart == i, onClick = choose(i) }
        end
    elseif sg then
        rows[#rows + 1] = { kind = "head", title = sg.class and (sg.text .. " sets") or sg.text, meta = #sg.sets .. " item sets" }
        rows[#rows + 1] = { kind = "sec", text = "All sets", sub = #sg.sets .. " sets", selected = st.colPart == nil, onClick = choose(nil) }
        for i, e in ipairs(sg.sets) do
            local badge, coords, size = setBadge(sg, e.set)
            local row = {
                kind = "sec", text = e.set.name, sub = setSub(e, not sg.class), selected = st.colPart == i, onClick = choose(i),
                badge = badge, badgeCoords = coords, badgeSize = size,
            }
            if badge then row.npc = false end -- npc = false: the round disc without a boss portrait, holding the badge
            rows[#rows + 1] = row
        end
    elseif k then
        rows[#rows + 1] = { kind = "head", title = k.text, meta = #k.recipes .. " recipes  ·  from the " .. k.class:lower() .. " trainer" }
        rows[#rows + 1] = { kind = "sec", text = "All levels", sub = #k.recipes .. " recipes", selected = st.colPart == nil, onClick = choose(nil) }
        for i, l in ipairs(skillLevels(k)) do
            rows[#rows + 1] = { kind = "sec", text = "Level " .. l.level, sub = #l.recipes .. (#l.recipes == 1 and " recipe" or " recipes"), selected = st.colPart == i, onClick = choose(i) }
        end
    end
end

function View.blocks()
    local U = ui()
    local st = U.state
    local blocks, shown, total = {}, 0, 0
    local function addGrid(list, fromOf)
        local cells = {}
        for _, e in ipairs(list) do
            total = total + 1
            local id = type(e) == "table" and e[1] or e
            local info = U.itemInfo(id)
            if U.passesInfo(info) then cells[#cells + 1] = U.cellFromInfo(id, info, { from = fromOf and fromOf(e) }) end
        end
        shown = shown + #cells
        if #cells > 0 then blocks[#blocks + 1] = U.grid(cells, { from = "Source" }) end
        return #cells
    end
    local c, sg, k = current()
    if c then
        for i, g in ipairs(c.groups) do
            if st.colPart == nil or st.colPart == i then
                blocks[#blocks + 1] = U.heading(c.text .. ": " .. g.text:lower())
                if addGrid(g.items, function(e) return e[2] end) == 0 then blocks[#blocks] = nil end
            end
        end
    elseif sg then
        for i, e in ipairs(sg.sets) do
            local s = e.set
            if st.colPart == nil or st.colPart == i then
                local note = sg.class and e.source or s.class
                if note and s.side then note = note .. ", " .. SIDE_TEXT[s.side] end
                blocks[#blocks + 1] = U.heading(s.name .. (note and ("  |cff9d9d9d" .. note .. "|r") or ""))
                if addGrid(s.pieces) == 0 then blocks[#blocks] = nil end
            end
        end
    elseif k then
        for i, l in ipairs(skillLevels(k)) do
            if st.colPart == nil or st.colPart == i then
                local cells = {}
                for _, r in ipairs(l.recipes) do
                    total = total + 1
                    local cell = U.recipeCell(r, k.class .. " trainer")
                    if U.passesRecipe(r, cell) then cells[#cells + 1] = cell end
                end
                shown = shown + #cells
                if #cells > 0 then
                    blocks[#blocks + 1] = U.heading(k.text .. ": level " .. l.level)
                    blocks[#blocks + 1] = U.grid(cells)
                end
            end
        end
    else
        return { U.emptyLine("No collections recorded in WoW Forever yet.") }, "Collections"
    end
    if shown == 0 then
        blocks = { U.emptyLine(total > 0 and "Nothing here matches the filters. Press Reset to show everything." or "No items.") }
    end
    return blocks, ("%s: %d %s shown"):format((c or sg or k).text, shown, k and "recipes" or "items")
end

-- Search: where each item is, for items nothing else lists.
function View.index(where)
    for _, c in ipairs(cols()) do
        for _, g in ipairs(c.groups) do
            for _, e in ipairs(g.items) do
                if not where[e[1]] then where[e[1]] = { text = c.text .. ": " .. e[2], tab = "collections", cat = c.key } end
            end
        end
    end
    for _, g in ipairs(setGroups()) do
        for p, e in ipairs(g.sets) do
            for _, id in ipairs(e.set.pieces) do
                if not where[id] then where[id] = { text = e.set.name, tab = "collections", cat = "set:" .. g.key, part = p } end
            end
        end
    end
    for i, k in ipairs(classSkills()) do
        for p, l in ipairs(skillLevels(k)) do
            for _, r in ipairs(l.recipes) do
                local id = r[7]
                if id and not where[id] then where[id] = { text = k.text .. ": level " .. l.level, tab = "collections", cat = "skill" .. i, part = p } end
            end
        end
    end
end

function View.goTo(w)
    local st = ui().state
    st.colCat, st.colPart = w.cat, w.part
end
