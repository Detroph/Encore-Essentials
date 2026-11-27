-- Encore-DB quest view: an instance's quests and quest chains, opened from the Quests row above the bosses.
-- Quest data comes from the quest data layer (QuestData.lua), never from a data file directly.
-- Chains read top to bottom: quests out in the world before and after the dungeon, and the dungeon's own quests
-- marked gold. Click a quest for its objective, where it starts and ends (with a map pin) and its rewards.
local _, ns = ...
local DB = ns.DB

local View = {}
ns.QuestView = View

local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local ACTIVE_ICON = "Interface\\GossipFrame\\ActiveQuestIcon"
local DONE_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
local INDENT = 44 -- details lines start under the quest title
local KEEP = 2 -- chain steps out in the world shown next to the dungeon's own before the rest fold away
local SIDES = { A = { "Alliance", "|cff4a9bff" }, H = { "Horde", "|cffff4d4d" } }

local function ui() return ns.UI end

---------------------------------------------------------------------------
-- Quest facts from the game: done, in the quest log, difficulty colour
---------------------------------------------------------------------------
local function isDone(id)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(id) end
    if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(id) end
    return false
end

local function inLog(id)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local i = C_QuestLog.GetLogIndexForQuestID(id)
        return i ~= nil and i > 0
    end
    if GetQuestLogIndexByID then return (GetQuestLogIndexByID(id) or 0) > 0 end
    return false
end

local function levelColor(level)
    if level and GetQuestDifficultyColor then
        local c = GetQuestDifficultyColor(level)
        if c then return c.r, c.g, c.b end
    end
    return 1, 0.82, 0
end

local function hex(r, g, b) return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255) end

local function playerSide()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return f == "Alliance" and "A" or f == "Horde" and "H" or nil
end

local function sideFilter()
    local s = ui().state.questSide
    if s == nil then return playerSide() end
    return s or nil -- false = both factions
end

local function title(id)
    return DB.Quests:Title(id) or ("Quest #" .. id)
end

-- "Dalar Dawnweaver, Silverpine Forest"
local function whoText(w)
    if not w then return nil end
    local name = w.name or w[3]
    local kind = w.kind or w[1]
    if not name then
        name = kind == "object" and "an object" or kind == "item" and "an item" or "someone"
    end
    local zone = ui().mapName(w.map or w[4])
    return zone and (name .. ", " .. zone) or name
end

local function whoPlace(w)
    if not w then return nil end
    return w.map or w[4], w.x or w[5], w.y or w[6]
end

local function money(copper)
    if not copper or copper <= 0 then return nil end
    return ui().coin(copper)
end

local function number(n)
    local s = tostring(math.floor(n))
    while true do
        local t, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        s = t
        if k == 0 then return s end
    end
end

---------------------------------------------------------------------------
-- Building the list
---------------------------------------------------------------------------
local function rewardCells(q)
    local cells = {}
    local U = ui()
    local function add(list, label)
        for _, e in ipairs(list or {}) do
            local id, count = e, 1
            if type(e) == "table" then id, count = e[1], e[2] or 1 end
            local info = U.itemInfo(id)
            local fallback = DB.Quests:ItemFallback(id)
            if fallback and info.name == ("Item " .. id) then
                info.name, info.quality = fallback[1], fallback[2] or info.quality
            end
            if count > 1 then info.name = info.name .. " x" .. count end
            cells[#cells + 1] = U.cellFromInfo(id, info, { from = label })
        end
    end
    if q.rewards or q.choice or q.seen then
        add(q.rewards, "You get")
        add(q.choice, "Choose one")
    else
        -- QuestieDB's reward items, not split into given and pick-one yet
        add(q.rewardItems, "Quest reward")
    end
    return cells
end

-- Reward items as shown: the split lists, or the unsplit list while nothing has split it.
local function rewardCount(q)
    if q.rewards or q.choice or q.seen then return #(q.rewards or {}) + #(q.choice or {}) end
    return #(q.rewardItems or {})
end

local function factionName(id)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local d = C_Reputation.GetFactionDataByID(id)
        if d and d.name then return d.name end
    end
    if GetFactionInfoByID then
        local name = GetFactionInfoByID(id)
        if name then return name end
    end
    return "Faction #" .. id
end

-- "+250 Thunder Bluff", reputation rewards in one line
local function repText(q)
    local parts = {}
    for _, r in ipairs(q.rep or {}) do
        local amount = r[2] or 0
        parts[#parts + 1] = (amount >= 0 and "+" or "") .. number(amount) .. " " .. factionName(r[1])
    end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

local function details(rows, q, id)
    local U = ui()
    local C = U.colors
    if q.objective then
        rows[#rows + 1] = { kind = "qtext", indent = INDENT, text = "|cffffd100Objective:|r " .. q.objective }
    end
    if q.text then
        rows[#rows + 1] = { kind = "qtext", indent = INDENT, text = q.text, dim = true }
    end
    local function place(label, w)
        local text = whoText(w)
        if not text then return end
        local map, x, y = whoPlace(w)
        local line = { kind = "qtext", indent = INDENT, text = "|cffffd100" .. label .. "|r " .. text }
        if map and x and y and x > 0 then
            line.text = line.text .. (" (%.1f, %.1f)  %s[map pin]|r"):format(x, y, C.TEAL_HEX)
            local name = w.name or w[3] or title(id)
            line.onClick = function() U.setPin(map, x, y, name) end
        end
        rows[#rows + 1] = line
    end
    place("Starts:", q.start)
    local s, f = q.start, q.finish
    if f and not (s and (s.id or s[2]) == (f.id or f[2]) and (s.kind or s[1]) == (f.kind or f[1])) then
        place("Ends:", f)
    elseif f then
        rows[#rows + 1] = { kind = "qtext", indent = INDENT, text = "|cffffd100Ends:|r back at the same place" }
    end
    if q.minLevel then
        rows[#rows + 1] = { kind = "qtext", indent = INDENT, text = "|cffffd100Needs level|r " .. q.minLevel }
    end
    local facts = {}
    if q.xp then facts[#facts + 1] = number(q.xp) .. " XP" end
    if money(q.money) then facts[#facts + 1] = money(q.money) end
    local rep = repText(q)
    if rep then facts[#facts + 1] = rep end
    local cells = rewardCells(q)
    if #facts > 0 then
        rows[#rows + 1] = { kind = "qtext", indent = INDENT, text = "|cffffd100Rewards:|r " .. table.concat(facts, "  ·  ") }
    elseif #cells > 0 then
        rows[#rows + 1] = { kind = "qtext", indent = INDENT, text = "|cffffd100Rewards:|r" }
    end
    if #cells > 0 then
        if not (q.rewards or q.choice or q.seen) and #cells > 1 then
            rows[#rows + 1] = { kind = "qtext", indent = INDENT, dim = true,
                text = "Some of these may be a choice: take the quest to see which." }
        end
        rows[#rows + 1] = U.grid(cells, { from = "Reward" })
    end
    rows[#rows + 1] = { kind = "qtext", indent = INDENT, text = " ", gap = true }
end

-- Where a chain step outside this dungeon is done: another instance that lists it, or out in the world.
local function elsewhere(id)
    for _, key in ipairs(DB.Quests:Instances(id) or {}) do
        for _, inst in ipairs((ns.Loot and (ns.Loot.allInstances or ns.Loot.instances)) or {}) do
            if inst.key == key then return "In " .. inst.name end
        end
    end
    return "Out in the world"
end

local function questRow(id, opts)
    local q = DB.Quests:Get(id) or { id = id }
    local U = ui()
    local done, active = isDone(id), inLog(id)
    local sub = {}
    if not opts.inside then sub[#sub + 1] = "|cff9d9d9d" .. elsewhere(id) .. "|r" end
    local giver = whoText(q.start)
    if giver then sub[#sub + 1] = giver end
    if q.xp then sub[#sub + 1] = number(q.xp) .. " XP" end
    if money(q.money) then sub[#sub + 1] = money(q.money) end
    local nRewards = rewardCount(q)
    if nRewards > 0 then sub[#sub + 1] = nRewards .. (nRewards == 1 and " reward" or " rewards") end
    local tags = {}
    if q.new and U.highlightOn() then tags[#tags + 1] = U.colors.TEAL_HEX .. "New in Forever|r" end
    if SIDES[q.side] then tags[#tags + 1] = SIDES[q.side][2] .. SIDES[q.side][1] .. "|r" end
    if done then
        tags[#tags + 1] = "|cff20ff20Done|r"
    elseif active then
        tags[#tags + 1] = "|cffffd100In your log|r"
    end
    -- Dungeon prep: group members with Encore who have it in their log (EncoreEssentials GroupQuests.lua)
    local Encore = _G.EncoreEssentials
    local holders = Encore and Encore.GroupQuestHolders and Encore:GroupQuestHolders(id)
    if holders and #holders > 0 then tags[#tags + 1] = "|cff73d966Group: " .. table.concat(holders, ", ") .. "|r" end
    local open = U.state.questOpen and U.state.questOpen[id]
    return {
        kind = "quest", id = id, level = q.level, title = title(id), sub = table.concat(sub, "  ·  "),
        tags = table.concat(tags, "  "), inside = opts.inside, step = opts.step, chain = opts.chain,
        first = opts.first, last = opts.last, done = done, active = active, open = open,
        onClick = function()
            U.state.questOpen = U.state.questOpen or {}
            U.state.questOpen[id] = not open or nil
            U.renderLoot(true)
        end,
    }
end

function View.blocks(inst)
    local U = ui()
    local rows = {}
    local data = DB.Quests:ForInstance(inst)
    local side = sideFilter()
    local hideDone = U.state.questHideDone
    local function sideOk(id)
        local q = DB.Quests:Get(id)
        return not side or not q or not q.side or q.side == side
    end

    rows[#rows + 1] = { kind = "qfilter" }
    local nChains, nSingles, shown, nDone = 0, 0, 0, 0
    local chains, singles = {}, {}
    for _, g in ipairs(data.groups) do
        local steps = {}
        local anyInside, allDone = false, true
        for _, id in ipairs(g.steps) do
            if sideOk(id) then
                steps[#steps + 1] = id
                if data.inside[id] then
                    anyInside = true
                    if not isDone(id) then allDone = false end
                end
            end
        end
        if anyInside and not (hideDone and allDone) then
            if #steps > 1 then chains[#chains + 1] = steps else singles[#singles + 1] = steps[1] end
        end
    end
    for id in pairs(data.inside) do
        if isDone(id) then nDone = nDone + 1 end
    end

    if #chains > 0 then
        rows[#rows + 1] = U.heading(("Quest chains (%d)"):format(#chains))
        for _, steps in ipairs(chains) do
            nChains = nChains + 1
            local nInside = 0
            for _, id in ipairs(steps) do if data.inside[id] then nInside = nInside + 1 end end
            rows[#rows + 1] = {
                kind = "qchain", text = title(steps[#steps]),
                meta = ("%d steps, %d in the dungeon"):format(#steps, nInside),
            }
            -- Long lead-ins and follow-ups out in the world fold away, keeping the KEEP steps next to the dungeon.
            local firstIn, lastIn = #steps, 1
            for i, id in ipairs(steps) do
                if data.inside[id] then
                    firstIn = math.min(firstIn, i)
                    lastIn = math.max(lastIn, i)
                end
            end
            local chainKey = tostring(steps[1]) .. ">" .. tostring(steps[#steps])
            U.state.questChainOpen = U.state.questChainOpen or {}
            local unfolded = U.state.questChainOpen[chainKey]
            local foldBefore = (not unfolded and firstIn - 1 > KEEP + 1) and (firstIn - 1 - KEEP) or 0
            local foldAfter = (not unfolded and #steps - lastIn > KEEP + 1) and (#steps - lastIn - KEEP) or 0
            local function foldRow(n, text)
                rows[#rows + 1] = {
                    kind = "qtext", indent = INDENT, text = U.colors.TEAL_HEX .. ("+ %d %s"):format(n, text) .. "|r",
                    onClick = function() U.state.questChainOpen[chainKey] = true; U.renderLoot(true) end,
                }
            end
            if foldBefore > 0 then foldRow(foldBefore, foldBefore == 1 and "earlier quest in this chain" or "earlier quests in this chain") end
            for i, id in ipairs(steps) do
                if i > foldBefore and i <= #steps - foldAfter then
                    local inside = data.inside[id] == true
                    if inside then shown = shown + 1 end
                    rows[#rows + 1] = questRow(id, {
                        inside = inside, step = i, chain = true,
                        first = i == foldBefore + 1 and foldBefore == 0, last = i == #steps - foldAfter and foldAfter == 0,
                    })
                    if U.state.questOpen and U.state.questOpen[id] then details(rows, DB.Quests:Get(id) or {}, id) end
                end
            end
            if foldAfter > 0 then foldRow(foldAfter, foldAfter == 1 and "later quest in this chain" or "later quests in this chain") end
        end
    end
    if #singles > 0 then
        rows[#rows + 1] = U.heading(("Quests (%d)"):format(#singles))
        table.sort(singles, function(a, b)
            local qa, qb = DB.Quests:Get(a) or {}, DB.Quests:Get(b) or {}
            if (qa.level or 0) ~= (qb.level or 0) then return (qa.level or 0) < (qb.level or 0) end
            return a < b
        end)
        for _, id in ipairs(singles) do
            nSingles = nSingles + 1
            shown = shown + 1
            rows[#rows + 1] = questRow(id, { inside = true })
            if U.state.questOpen and U.state.questOpen[id] then details(rows, DB.Quests:Get(id) or {}, id) end
        end
    end
    if nChains + nSingles == 0 then
        local live = DB.QuestieLive
        local notice = data.count == 0 and live and live:Notice()
        rows[#rows + 1] = U.emptyLine(notice or (data.count > 0 and "No quests here match the filter above.")
            or "No quests for this instance have been confirmed in WoW Forever yet.")
    end

    local status = ("%s: %d of %d quests shown, %d done. Click a quest for its objective, where it starts and its rewards.")
        :format(inst.name, shown, data.count, nDone)
    return rows, status
end

---------------------------------------------------------------------------
-- Row kinds
---------------------------------------------------------------------------
local function setColor(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end

-- Filter strip: which faction's quests, and whether to hide finished ones.
local FILTERS = {
    { key = "auto", text = "My faction" },
    { key = false, text = "Both factions" },
    { key = "A", text = "Alliance" },
    { key = "H", text = "Horde" },
}

local function initFilterRow(row)
    local U = ui()
    local C = U.colors
    if not row.built then
        row.built = true
        row:EnableMouse(false)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", 10, 0)
        row.label:SetText("Show")
        setColor(row.label, C.DIM)
        row.buttons = {}
        local prev = row.label
        for i, f in ipairs(FILTERS) do
            local b = CreateFrame("Button", nil, row)
            b:SetHeight(20)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("CENTER", 0, 1)
            b.text:SetText(f.text)
            b:SetWidth(b.text:GetStringWidth() + 16)
            b:SetPoint("LEFT", prev, "RIGHT", i == 1 and 8 or 4, 0)
            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetAllPoints()
            b.line = b:CreateTexture(nil, "ARTWORK")
            b.line:SetPoint("BOTTOMLEFT"); b.line:SetPoint("BOTTOMRIGHT"); b.line:SetHeight(1)
            b.line:SetColorTexture(C.COPPER[1], C.COPPER[2], C.COPPER[3], 1)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.82, 0, 0.10)
            b:SetScript("OnClick", function()
                U.state.questSide = (f.key == "auto") and nil or f.key
                U.renderLoot(true)
            end)
            b.key = f.key
            row.buttons[i] = b
            prev = b
        end
        local done = CreateFrame("Button", nil, row)
        done:SetHeight(20)
        done:SetPoint("RIGHT", -8, 0)
        done.box = done:CreateTexture(nil, "ARTWORK")
        done.box:SetSize(12, 12)
        done.box:SetPoint("LEFT", 0, 0)
        done.check = done:CreateTexture(nil, "OVERLAY")
        done.check:SetSize(16, 16)
        done.check:SetPoint("CENTER", done.box, "CENTER", 1, 1)
        done.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        done.text = done:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        done.text:SetPoint("LEFT", done.box, "RIGHT", 5, 0)
        done.text:SetText("Hide finished")
        done:SetWidth(done.text:GetStringWidth() + 20)
        done:SetScript("OnClick", function()
            U.state.questHideDone = not U.state.questHideDone or nil
            U.renderLoot(true)
        end)
        row.done = done
        local line = row:CreateTexture(nil, "ARTWORK")
        line:SetPoint("BOTTOMLEFT", 6, 1); line:SetPoint("BOTTOMRIGHT", -6, 1); line:SetHeight(1)
        line:SetColorTexture(C.COPPER[1], C.COPPER[2], C.COPPER[3], 0.25)
    end
    local current = U.state.questSide
    for _, b in ipairs(row.buttons) do
        local on = (b.key == "auto" and current == nil) or (b.key ~= "auto" and b.key == current)
        b.bg:SetColorTexture(on and 0.45 or 0, on and 0.25 or 0, on and 0.08 or 0, on and 0.6 or 0.3)
        b.line:SetShown(on)
        if on then setColor(b.text, C.GOLD) else setColor(b.text, C.INK, 0.85) end
    end
    row.done.box:SetColorTexture(0.79, 0.47, 0.18, 1)
    row.done.check:SetShown(U.state.questHideDone == true)
    setColor(row.done.text, C.INK, 0.85)
end

-- Chain heading: the chain's last quest names it.
local function initChainRow(row, d)
    local C = ui().colors
    if not row.built then
        row.built = true
        row:EnableMouse(false)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetPoint("TOPLEFT", 4, -6); row.bg:SetPoint("BOTTOMRIGHT", -4, 0)
        ui().gradient(row.bg, "HORIZONTAL", 0.45, 0.26, 0.08, 0.45, 0.45, 0.26, 0.08, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 12, -3)
        row.icon:SetTexture("Interface\\QuestFrame\\UI-QuestLog-BookIcon")
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.meta:SetPoint("RIGHT", -10, -3)
        row.meta:SetJustifyH("RIGHT")
        row.text:SetPoint("RIGHT", row.meta, "LEFT", -8, 0)
    end
    row.text:SetText(d.text or "")
    setColor(row.text, C.GOLD)
    row.meta:SetText(d.meta or "")
    setColor(row.meta, C.DIM)
end

-- One quest: a step on the chain's rail (or a quest marker), level and title, giver and rewards, tags.
local function initQuestRow(row, d)
    local U = ui()
    local C = U.colors
    if not row.built then
        row.built = true
        row.tint = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.tint:SetPoint("TOPLEFT", 4, -1); row.tint:SetPoint("BOTTOMRIGHT", -4, 1)
        U.gradient(row.tint, "HORIZONTAL", 1, 0.82, 0, 0.10, 1, 0.82, 0, 0.0)
        row.open = row:CreateTexture(nil, "BACKGROUND", nil, 2)
        row.open:SetPoint("TOPLEFT", 4, -1); row.open:SetPoint("BOTTOMRIGHT", -4, 1)
        row.open:SetColorTexture(0, 0, 0, 0.35)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", 4, -1); hl:SetPoint("BOTTOMRIGHT", -4, 1)
        U.gradient(hl, "HORIZONTAL", 1, 0.82, 0, 0.16, 1, 0.82, 0, 0.02)
        -- Rail: line above and below the step marker
        row.railTop = row:CreateTexture(nil, "ARTWORK", nil, 1)
        row.railTop:SetWidth(2)
        row.railTop:SetPoint("TOP", row, "TOPLEFT", 24, 0)
        row.railTop:SetPoint("BOTTOM", row, "LEFT", 24, 0)
        row.railBottom = row:CreateTexture(nil, "ARTWORK", nil, 1)
        row.railBottom:SetWidth(2)
        row.railBottom:SetPoint("TOP", row, "LEFT", 24, 0)
        row.railBottom:SetPoint("BOTTOM", row, "BOTTOMLEFT", 24, 0)
        row.nodeEdge = row:CreateTexture(nil, "ARTWORK", nil, 2)
        row.nodeEdge:SetSize(22, 22)
        row.nodeEdge:SetPoint("CENTER", row, "LEFT", 24, 0)
        row.nodeFill = row:CreateTexture(nil, "ARTWORK", nil, 3)
        row.nodeFill:SetSize(20, 20)
        row.nodeFill:SetPoint("CENTER", row.nodeEdge)
        U.gradient(row.nodeFill, "VERTICAL", 0.14, 0.08, 0.04, 1, 0.36, 0.23, 0.11, 1)
        row.nodeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.nodeText:SetPoint("CENTER", row.nodeEdge, "CENTER", 0, 0)
        row.marker = row:CreateTexture(nil, "OVERLAY")
        row.marker:SetSize(20, 20)
        row.marker:SetPoint("CENTER", row, "LEFT", 24, 0)
        row.check = row:CreateTexture(nil, "OVERLAY", nil, 2)
        row.check:SetSize(16, 16)
        row.check:SetPoint("CENTER", row.nodeEdge, "BOTTOMRIGHT", -2, 2)
        row.check:SetTexture(DONE_ICON)
        row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.title:SetPoint("BOTTOMLEFT", row, "LEFT", INDENT, 2)
        row.title:SetJustifyH("LEFT")
        row.title:SetWordWrap(false)
        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.sub:SetPoint("TOPLEFT", row, "LEFT", INDENT, -3)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)
        row.tags = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.tags:SetPoint("RIGHT", -30, 0)
        row.tags:SetJustifyH("RIGHT")
        row.pmEdge = row:CreateTexture(nil, "ARTWORK", nil, 1)
        row.pmEdge:SetSize(14, 14)
        row.pmEdge:SetPoint("RIGHT", -10, 0)
        row.pmEdge:SetColorTexture(0.79, 0.47, 0.18, 1)
        row.pmFill = row:CreateTexture(nil, "ARTWORK", nil, 2)
        row.pmFill:SetSize(12, 12)
        row.pmFill:SetPoint("CENTER", row.pmEdge)
        U.gradient(row.pmFill, "VERTICAL", 0.14, 0.08, 0.04, 1, 0.36, 0.23, 0.11, 1)
        row.pmText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.pmText:SetPoint("CENTER", row.pmEdge, "CENTER", 0, 1)
        row.title:SetPoint("RIGHT", row.tags, "LEFT", -10, 0)
        row.sub:SetPoint("RIGHT", row.tags, "LEFT", -10, 0)
        row:SetScript("OnClick", U.onRowClick)
    end
    row.data = d
    local chain = d.chain == true
    local railR, railG, railB = C.COPPER[1], C.COPPER[2], C.COPPER[3]
    row.railTop:SetColorTexture(railR, railG, railB, 0.55)
    row.railBottom:SetColorTexture(railR, railG, railB, 0.55)
    row.railTop:SetShown(chain and not d.first)
    row.railBottom:SetShown(chain and not d.last)
    row.nodeEdge:SetShown(chain); row.nodeFill:SetShown(chain); row.nodeText:SetShown(chain)
    if chain then
        if d.inside then
            row.nodeEdge:SetColorTexture(C.GOLD[1], C.GOLD[2], C.GOLD[3], 1)
        else
            row.nodeEdge:SetColorTexture(0.45, 0.40, 0.33, 1)
        end
        row.nodeText:SetText(d.step or "")
        if d.inside then setColor(row.nodeText, C.GOLD) else setColor(row.nodeText, C.DIM) end
    end
    row.marker:SetShown(not chain)
    if not chain then row.marker:SetTexture(d.active and ACTIVE_ICON or QUEST_ICON) end
    row.check:SetShown(d.done == true)
    if not chain then
        row.check:ClearAllPoints()
        row.check:SetPoint("CENTER", row.marker, "BOTTOMRIGHT", -2, 2)
    else
        row.check:ClearAllPoints()
        row.check:SetPoint("CENTER", row.nodeEdge, "BOTTOMRIGHT", -2, 2)
    end
    row.tint:SetShown(d.inside == true)
    row.open:SetShown(d.open == true)

    local lv = ""
    if d.level then lv = hex(levelColor(d.level)) .. "[" .. d.level .. "]|r " end
    row.title:SetText(lv .. d.title)
    if d.done then
        row.title:SetTextColor(0.62, 0.62, 0.62)
    elseif d.inside then
        setColor(row.title, C.INK)
    else
        setColor(row.title, C.INK, 0.75)
    end
    row.sub:SetText(d.sub or "")
    setColor(row.sub, C.DIM)
    row.tags:SetText(d.tags or "")
    row.pmText:SetText(d.open and "-" or "+")
end

-- A details line under an open quest; a click sets the map pin when it has one.
local function initTextRow(row, d)
    local C = ui().colors
    if not row.built then
        row.built = true
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(true)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(1, 0.82, 0, 0.08)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetPoint("TOPLEFT", 4, 0); row.bg:SetPoint("BOTTOMRIGHT", -4, 0)
        row.bg:SetColorTexture(0, 0, 0, 0.35)
        row:SetScript("OnClick", ui().onRowClick)
    end
    row.data = d
    row:EnableMouse(d.onClick ~= nil)
    row.hl:SetShown(d.onClick ~= nil)
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", 12 + (d.indent or 0), 0)
    row.text:SetPoint("RIGHT", -10, 0)
    row.text:SetText(d.text or "")
    if d.dim then setColor(row.text, C.DIM) else setColor(row.text, C.INK) end
end

local registered = false
function View.register()
    if registered or not ns.UI then return end
    registered = true
    local kinds = ns.UI.rowKinds
    kinds.qfilter = { "EncoreDBQuestFilterRowTemplate", initFilterRow, 30 }
    kinds.qchain = { "EncoreDBQuestChainRowTemplate", initChainRow, 32 }
    kinds.quest = { "EncoreDBQuestRowTemplate", initQuestRow, 44 }
    kinds.qtext = { "EncoreDBQuestTextRowTemplate", initTextRow }
end
View.register()

-- Redraw when the game learns a quest's name, or a quest is taken, handed in or abandoned.
local events = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_DATA_LOAD_RESULT", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE" }) do
    pcall(events.RegisterEvent, events, e)
end
local pending = false
events:SetScript("OnEvent", function()
    local U = ns.UI
    if pending or not (U and U.isShown() and U.state.tab == "dungeons" and U.state.boss == "quests") then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        if U.isShown() and U.state.boss == "quests" then U.renderLoot(true) end
    end)
end)

-- Redraw the quest list when a group member's quest log arrives.
do
    local Encore = _G.EncoreEssentials
    local previous = Encore and Encore.OnGroupQuests
    if Encore then
        function Encore:OnGroupQuests(who)
            if previous then previous(self, who) end
            local U = ui()
            if U and U.isShown() and U.state.tab == "dungeons" and U.state.boss == "quests" then U.renderLoot(true) end
        end
    end
end
