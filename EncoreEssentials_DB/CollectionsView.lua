-- Encore-DB Collections tab: mounts, companions, tabards and legendaries (ns.Collections), item sets
-- (ns.ItemSets, by source, then class) and class skills such as rogue poisons (ns.ClassSkills), all from Data/Extras.lua. Left: the
-- collections, the item set groups and the class skills. Middle: where the items come from, the sets in a group, or
-- the levels a skill is learned at. Right: the items or recipes. Window.lua calls in here (it is near Lua's local limit).
local _, ns = ...

local View = {}
ns.CollectionsView = View

local SIDE_TEXT = { A = "Alliance", H = "Horde" }
local function ui() return ns.UI end
local function cols() return ns.Collections or {} end
local function classSkills() return ns.ClassSkills or {} end

-- Item sets: the left list keeps ns.ItemSets' source groups (PvP sets, Zul'Gurub, Ahn'Qiraj, Other sets, later dungeon
-- and tier sets). Inside a group the middle list has one row per class, with its class icon, holding that class's
-- sets; sets without a class follow one by one. Any new source group in Data/Extras.lua is split the same way.
local CLASS_ORDER = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
-- Class icon coordinates in the game's class icon sheets (same as CLASS_ICON_TCOORDS, for clients without it)
local CLASS_COORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
    DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 },
}
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local function classCoords(class)
    local tok = class and class:upper()
    if not tok then return nil end
    return (CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[tok]) or CLASS_COORDS[tok]
end

local partsCache = setmetatable({}, { __mode = "k" })
-- The middle-list rows of a source group: { { class = "Warrior", sets = { ... } }, ..., { set = s }, ... }, the
-- classes in CLASS_ORDER (any class not in it after them), then the sets without a class.
local function setParts(g)
    if partsCache[g] then return partsCache[g] end
    local byClass, extra, classless = {}, {}, {}
    for _, s in ipairs(g.sets) do
        if s.class then
            if not byClass[s.class] then
                byClass[s.class] = { class = s.class, sets = {} }
                extra[#extra + 1] = s.class
            end
            local t = byClass[s.class].sets
            t[#t + 1] = s
        else
            classless[#classless + 1] = { set = s }
        end
    end
    local parts, done = {}, {}
    for _, c in ipairs(CLASS_ORDER) do
        if byClass[c] then parts[#parts + 1] = byClass[c]; done[c] = true end
    end
    for _, c in ipairs(extra) do if not done[c] then parts[#parts + 1] = byClass[c] end end
    for _, e in ipairs(classless) do parts[#parts + 1] = e end
    partsCache[g] = parts
    return parts
end
local function partSets(part) return part.sets or { part.set } end
-- The item set groups a tab shows: a group's tab field says where it goes (tab = "pvp": the PvP tab), else Collections.
local function setGroups(tab)
    local out = {}
    for _, g in ipairs(ns.ItemSets or {}) do
        if (g.tab or "collections") == (tab or "collections") then out[#out + 1] = g end
    end
    return out
end
-- The group a "set:<group text>" key names in a tab.
local function setGroupByKey(key, tab)
    local text = type(key) == "string" and key:match("^set:(.+)$")
    if not text then return nil end
    for _, g in ipairs(setGroups(tab)) do if g.text == text then return g end end
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

-- state.colCat: a collection key, "set:<group text>" for an item set group, or "skill<i>" for class skill i.
-- state.colPart: a group, set part (class or classless set) or level index, nil = all.
local function current()
    local st = ui().state
    local k = st.colCat
    if type(k) == "string" then
        local sg = setGroupByKey(k)
        if sg then return nil, sg end
        local ki = tonumber(k:match("^skill(%d+)$"))
        if ki and classSkills()[ki] then return nil, nil, classSkills()[ki] end
        for _, c in ipairs(cols()) do if c.key == k then return c end end
    end
    if cols()[1] then st.colCat = cols()[1].key; return cols()[1] end
    if setGroups()[1] then st.colCat = "set:" .. setGroups()[1].text; return nil, setGroups()[1] end
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
        local cat = "set:" .. g.text
        entries[#entries + 1] = {
            kind = "leaf", text = g.text, right = tostring(#g.sets), selected = st.colCat == cat,
            onClick = function() st.colCat, st.colPart = cat, nil; pick() end,
        }
    end
    if entries[1] then groups[#groups + 1] = { key = "colSets", text = "Item sets", entries = entries } end
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

local function setSub(s)
    local t = {}
    if s.side then t[#t + 1] = SIDE_TEXT[s.side] end
    t[#t + 1] = #s.pieces .. " pieces"
    return table.concat(t, "  ·  ")
end

-- A class row's line under the name: how many sets, and for which faction when they all are for one.
local function classSub(part)
    local n, side = #part.sets, part.sets[1].side
    for _, s in ipairs(part.sets) do if s.side ~= side then side = nil end end
    return n .. (n == 1 and " set" or " sets") .. (side and ("  ·  " .. SIDE_TEXT[side]) or "")
end

-- The round icon on a row: the class icon, or for a set without a class the icon of its first piece.
local function partBadge(part)
    local coords = classCoords(part.class)
    if coords then return CLASS_CIRCLES, coords, 56 end
    local id = part.set and part.set.pieces[1]
    local tex = id and ((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id)))
    if tex then return tex, nil, 36 end
end

-- The middle list for an item set group: "All sets", a row per class, then the sets without a class.
local function setRows(rows, sg, sel, choose)
    rows[#rows + 1] = { kind = "head", title = sg.text, meta = #sg.sets .. " item sets" }
    rows[#rows + 1] = { kind = "sec", text = "All sets", sub = #sg.sets .. " sets", selected = sel == nil, onClick = choose(nil) }
    for i, part in ipairs(setParts(sg)) do
        local badge, coords, size = partBadge(part)
        local row = {
            kind = "sec", text = part.class or part.set.name, sub = part.class and classSub(part) or setSub(part.set),
            selected = sel == i, onClick = choose(i), badge = badge, badgeCoords = coords, badgeSize = size,
        }
        if badge then row.npc = false end -- npc = false: the round disc without a boss portrait, holding the badge
        rows[#rows + 1] = row
    end
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
        setRows(rows, sg, st.colPart, choose)
    elseif k then
        rows[#rows + 1] = { kind = "head", title = k.text, meta = #k.recipes .. " recipes  ·  from the " .. k.class:lower() .. " trainer" }
        rows[#rows + 1] = { kind = "sec", text = "All levels", sub = #k.recipes .. " recipes", selected = st.colPart == nil, onClick = choose(nil) }
        for i, l in ipairs(skillLevels(k)) do
            rows[#rows + 1] = { kind = "sec", text = "Level " .. l.level, sub = #l.recipes .. (#l.recipes == 1 and " recipe" or " recipes"), selected = st.colPart == i, onClick = choose(i) }
        end
    end
end

-- The headings and item grids of an item set group's sets (all, or one part).
local function addSets(sg, sel, addGrid, blocks)
    local U = ui()
    for i, part in ipairs(setParts(sg)) do
        if sel == nil or sel == i then
            for _, s in ipairs(partSets(part)) do
                local note = s.class
                if s.side then note = (note and (note .. ", ") or "") .. SIDE_TEXT[s.side] end
                blocks[#blocks + 1] = U.heading(s.name .. (note and ("  |cff9d9d9d" .. note .. "|r") or ""))
                if addGrid(s.pieces) == 0 then blocks[#blocks] = nil end
            end
        end
    end
end

-- Adds item grids to blocks and counts the items shown and listed.
local function gridAdder(blocks)
    local U = ui()
    local n = { shown = 0, total = 0 }
    return function(list, fromOf)
        local cells = {}
        for _, e in ipairs(list) do
            n.total = n.total + 1
            local id = type(e) == "table" and e[1] or e
            local info = U.itemInfo(id)
            if U.passesInfo(info) then cells[#cells + 1] = U.cellFromInfo(id, info, { from = fromOf and fromOf(e) }) end
        end
        n.shown = n.shown + #cells
        if #cells > 0 then blocks[#blocks + 1] = U.grid(cells, { from = "Source" }) end
        return #cells
    end, n
end

function View.blocks()
    local U = ui()
    local st = U.state
    local blocks = {}
    local addGrid, n = gridAdder(blocks)
    local c, sg, k = current()
    if c then
        for i, g in ipairs(c.groups) do
            if st.colPart == nil or st.colPart == i then
                blocks[#blocks + 1] = U.heading(c.text .. ": " .. g.text:lower())
                if addGrid(g.items, function(e) return e[2] end) == 0 then blocks[#blocks] = nil end
            end
        end
    elseif sg then
        addSets(sg, st.colPart, addGrid, blocks)
    elseif k then
        for i, l in ipairs(skillLevels(k)) do
            if st.colPart == nil or st.colPart == i then
                local cells = {}
                for _, r in ipairs(l.recipes) do
                    n.total = n.total + 1
                    local cell = U.recipeCell(r, k.class .. " trainer")
                    if U.passesRecipe(r, cell) then cells[#cells + 1] = cell end
                end
                n.shown = n.shown + #cells
                if #cells > 0 then
                    blocks[#blocks + 1] = U.heading(k.text .. ": level " .. l.level)
                    blocks[#blocks + 1] = U.grid(cells)
                end
            end
        end
    else
        return { U.emptyLine("No collections recorded in WoW Forever yet.") }, "Collections"
    end
    if n.shown == 0 then
        blocks = { U.emptyLine(n.total > 0 and "Nothing here matches the filters. Press Reset to show everything." or "No items.") }
    end
    return blocks, ("%s: %d %s shown"):format((c or sg or k).text, n.shown, k and "recipes" or "items")
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
    for _, g in ipairs(ns.ItemSets or {}) do
        local tab = g.tab or "collections"
        for p, part in ipairs(setParts(g)) do
            for _, s in ipairs(partSets(part)) do
                for _, id in ipairs(s.pieces) do
                    if not where[id] then
                        where[id] = tab == "collections" and { text = s.name, tab = tab, cat = "set:" .. g.text, part = p }
                            or { text = s.name, tab = tab, vendor = "set:" .. g.text, setPart = p, sets = true }
                    end
                end
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
    if w.tab == "collections" then
        st.colCat, st.colPart = w.cat, w.part
    else
        st.vendor[w.tab], st.setPart = w.vendor, w.setPart
    end
end

-- Item sets in another tab (the PvP tab's PvP sets): the tab's selection, state.vendor[tab], holds "set:<group text>"
-- instead of a vendor index, and state.setPart the class or set picked in the middle list.
function View.isSetKey(tab, v) return setGroupByKey(v, tab) ~= nil end

function View.setTree(tab, pick)
    local st = ui().state
    local entries = {}
    for _, g in ipairs(setGroups(tab)) do
        local key = "set:" .. g.text
        entries[#entries + 1] = {
            kind = "leaf", text = g.text, right = tostring(#g.sets), selected = st.vendor[tab] == key,
            onClick = function() st.vendor[tab], st.setPart = key, nil; pick() end,
        }
    end
    if entries[1] then return { key = tab .. "Sets", text = "Item sets", entries = entries } end
end

function View.setSections(rows, tab)
    local st = ui().state
    local sg = setGroupByKey(st.vendor[tab], tab)
    if not sg then return end
    setRows(rows, sg, st.setPart, function(i) return function() st.setPart = i; ui().clearSearch(); ui().renderAll() end end)
end

function View.setBlocks(tab)
    local U = ui()
    local sg = setGroupByKey(U.state.vendor[tab], tab)
    if not sg then return { U.emptyLine("No item sets here.") }, "" end
    local blocks = {}
    local addGrid, n = gridAdder(blocks)
    addSets(sg, U.state.setPart, addGrid, blocks)
    if n.shown == 0 then
        blocks = { U.emptyLine(n.total > 0 and "Nothing here matches the filters. Press Reset to show everything." or "No items.") }
    end
    return blocks, ("%s: %d items shown"):format(sg.text, n.shown)
end
