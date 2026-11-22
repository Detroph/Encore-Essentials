-- Encore-DB Collections tab: mounts, companions, tabards and legendaries (ns.Collections), item sets
-- (ns.ItemSets) and class skills such as rogue poisons (ns.ClassSkills), all from Data/Extras.lua. Left: the
-- collections, the item set groups and the class skills. Middle: where the items come from, the sets in a group, or
-- the levels a skill is learned at. Right: the items or recipes. Window.lua calls in here (it is near Lua's local limit).
local _, ns = ...

local View = {}
ns.CollectionsView = View

local SIDE_TEXT = { A = "Alliance", H = "Horde" }
local function ui() return ns.UI end
local function cols() return ns.Collections or {} end
local function setGroups() return ns.ItemSets or {} end
local function classSkills() return ns.ClassSkills or {} end

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

-- state.colCat: a collection key, "set<i>" for item set group i, or "skill<i>" for class skill i.
-- state.colPart: a group, set or level index, nil = all.
local function current()
    local st = ui().state
    local k = st.colCat
    if type(k) == "string" then
        local si = tonumber(k:match("^set(%d+)$"))
        if si and setGroups()[si] then return nil, setGroups()[si] end
        local ki = tonumber(k:match("^skill(%d+)$"))
        if ki and classSkills()[ki] then return nil, nil, classSkills()[ki] end
        for _, c in ipairs(cols()) do if c.key == k then return c end end
    end
    if cols()[1] then st.colCat = cols()[1].key; return cols()[1] end
    if setGroups()[1] then st.colCat = "set1"; return nil, setGroups()[1] end
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
    for i, g in ipairs(setGroups()) do
        entries[#entries + 1] = {
            kind = "leaf", text = g.text, right = tostring(#g.sets), selected = st.colCat == "set" .. i,
            onClick = function() st.colCat, st.colPart = "set" .. i, nil; pick() end,
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

local function setSub(s)
    local t = {}
    if s.class then t[#t + 1] = s.class end
    if s.side then t[#t + 1] = SIDE_TEXT[s.side] end
    t[#t + 1] = #s.pieces .. " pieces"
    return table.concat(t, "  ·  ")
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
        rows[#rows + 1] = { kind = "head", title = sg.text, meta = #sg.sets .. " item sets" }
        rows[#rows + 1] = { kind = "sec", text = "All sets", sub = #sg.sets .. " sets", selected = st.colPart == nil, onClick = choose(nil) }
        for i, s in ipairs(sg.sets) do
            rows[#rows + 1] = { kind = "sec", text = s.name, sub = setSub(s), selected = st.colPart == i, onClick = choose(i) }
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
        for i, s in ipairs(sg.sets) do
            if st.colPart == nil or st.colPart == i then
                blocks[#blocks + 1] = U.heading(s.name .. (s.class and ("  |cff9d9d9d" .. s.class .. (s.side and (", " .. SIDE_TEXT[s.side]) or "") .. "|r") or ""))
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
    for i, g in ipairs(setGroups()) do
        for p, s in ipairs(g.sets) do
            for _, id in ipairs(s.pieces) do
                if not where[id] then where[id] = { text = s.name, tab = "collections", cat = "set" .. i, part = p } end
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
