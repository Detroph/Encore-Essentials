-- Encore-Professions: the guide panel beside the profession window, and the round Encore button by the skill bar
-- that turns it on or off (remembered for the account). While it is on, the panel opens with the profession window:
-- "Select a profession" until one is shown, then that profession's route or where to farm.
local _, ns = ...
local P = ns.P
local Encore = _G.EncoreEssentials

local WIDTH, PAD = 372, 12
local GAP = 66 -- space between the profession window and the guide, for its side tabs
local INNER = WIDTH - 2 * PAD
local TOP = -60 -- the views start under the portrait
local ICON = "Interface\\AddOns\\EncoreEssentials\\Media\\encore-professions-icon"
local COLOUR = { o = { 1, 0.5, 0.25 }, y = { 1, 1, 0 }, g = { 0.25, 0.75, 0.25 }, x = { 0.5, 0.5, 0.5 } }
local COLOUR_NAME = { o = "Orange", y = "Yellow", g = "Green", x = "Grey" }
local MODE_NAME = { cheap = "Cheapest", fast = "Fewest crafts" }

local panel, button
local view = {}

local function hex(c) return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end
local function UI() return Encore.UI end

local function itemName(id)
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not n and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return n or ("item " .. id)
end

local function itemIcon(id)
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function tip(frame, fn)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        if fn(self, GameTooltip) ~= false then GameTooltip:Show() end
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function smallButton(parent, text, width, onClick, style)
    local b = UI().Button(parent, text, onClick, width, style)
    b:SetHeight(20)
    return b
end

---------------------------------------------------------------------------
-- What to learn next, and where
---------------------------------------------------------------------------
local function rankCapFor(prof, skill)
    for _, r in ipairs(ns.Ranks[prof] or {}) do
        if skill < r.skill then return r.cap - 75 end
    end
    return 300
end

-- { text, place = { map, x, y, name } } for a rank step or a recipe still to learn.
local function trip(prof, st)
    if st.kind == "rank" then
        local r = st.rank
        if r.how == "trainer" then
            local t = P:Trainer(prof, r.cap)
            return {
                text = ("At |cffffffff%d|r: train |cffffffff%s|r%s"):format(st.at, r.name, r.level > 0 and (" (level " .. r.level .. ")") or ""),
                sub = t and (t.name .. ", " .. P.PlaceText(t) .. " · " .. P.Coins(r.cost or 0)) or ("Any " .. prof .. " trainer · " .. P.Coins(r.cost or 0)),
                place = t,
            }
        elseif r.how == "book" then
            local v = P.Nearest(r.vendors)
            return {
                text = ("At |cffffffff%d|r: buy and read |cffffffff%s|r"):format(st.at, itemName(r.item)),
                sub = v and (v.name .. ", " .. P.PlaceText(v)) or "From a vendor",
                place = v,
            }
        elseif r.how == "quest" then
            local q = P.Nearest(r.quests)
            return {
                text = ("At |cffffffff%d|r: quest |cffffffff%s|r (level %d) for %s"):format(st.at, q and q.name or "?", q and q.level or r.level, r.name),
                sub = q and q.by and (q.by .. ", " .. P.PlaceText(q)) or "",
                place = q,
            }
        end
    elseif st.kind == "craft" and (st.learn or 0) > 0 and not P.Knows(st.spell) then
        if type(st.how) == "number" then
            local v = P.Nearest(ns.RecipeVendors[st.how])
            return {
                text = ("At |cffffffff%d|r: buy |cffffffff%s|r"):format(st.learnAt or st.from, itemName(st.how)),
                sub = v and (v.name .. ", " .. P.PlaceText(v) .. " · " .. P.Coins(v.price or st.learn)) or P.Coins(st.learn),
                place = v,
            }
        end
        local t = P:Trainer(prof, rankCapFor(prof, st.learnAt or st.from))
        return {
            text = ("At |cffffffff%d|r: learn |cffffffff%s|r"):format(st.learnAt or st.from, st.name),
            sub = t and (t.name .. ", " .. P.PlaceText(t) .. " · " .. P.Coins(st.learn)) or ("Any " .. prof .. " trainer · " .. P.Coins(st.learn)),
            place = t,
        }
    end
end

---------------------------------------------------------------------------
-- Building the panel
---------------------------------------------------------------------------
local function card(parent)
    return UI().Well(parent)
end

local function skillBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(INNER, 14)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.07, 0.6, 0.6)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    UI().Border(bar, UI().COPPER, 0.5)
    bar.text = UI().Text(bar, "GameFontHighlightSmall", "")
    bar.text:SetPoint("CENTER")
    return bar
end

local function buildCraft(p)
    local v = CreateFrame("Frame", nil, p)
    v:SetPoint("TOPLEFT", PAD, TOP)
    v:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    view.craft = v

    v.status = UI().Text(v, "GameFontHighlightSmall", "")
    v.status:SetPoint("TOPLEFT", 0, 0)
    v.status:SetWidth(INNER - 92)
    v.recalc = smallButton(v, "Recalculate", 88, function() P:Recalculate() end, "dark")
    v.recalc:SetPoint("TOPRIGHT", 0, 2)
    tip(v.recalc, function(_, tt)
        tt:SetText("Recalculate route", 1, 0.82, 0)
        tt:AddLine("Plans the route again from your skill, the recipes you know and today's prices. The route never changes by itself.", 1, 1, 1, true)
    end)

    v.wo = CreateFrame("CheckButton", nil, v, "UICheckButtonTemplate")
    v.wo:SetSize(22, 22)
    v.wo:SetPoint("TOPLEFT", -3, -22)
    v.woText = UI().Text(v, "GameFontHighlightSmall", "Working Overtime")
    v.woText:SetPoint("LEFT", v.wo, "RIGHT", 0, 0)
    v.woMinus = smallButton(v, "-", 22, function() local _, n = P:WorkingOvertime(); P:SetWorkingOvertime(nil, n - 1); P:Recalculate() end, "dark")
    v.woPlus = smallButton(v, "+", 22, function() local _, n = P:WorkingOvertime(); P:SetWorkingOvertime(nil, n + 1); P:Recalculate() end, "dark")
    v.woPoints = UI().Text(v, "GameFontHighlightSmall", "0/5")
    v.woMinus:SetPoint("LEFT", v.woText, "RIGHT", 8, 0)
    v.woPoints:SetPoint("LEFT", v.woMinus, "RIGHT", 4, 0)
    v.woPlus:SetPoint("LEFT", v.woPoints, "RIGHT", 4, 0)
    v.wo:SetScript("OnClick", function(self) P:SetWorkingOvertime(self:GetChecked()); P:Recalculate() end)
    local woTip = function(_, tt)
        local _, _, talent = P:WorkingOvertime()
        tt:SetText("Working Overtime", 1, 0.82, 0)
        tt:AddLine("Legacy talent: +4% skill-up chance per point on yellow and green recipes, +20% at 5/5.", 1, 1, 1, true)
        tt:AddLine(("Your Legacy tree has %d/5. Change the number to plan for points you haven't spent yet. Changing it recalculates the route."):format(talent), 1, 1, 1, true)
        tt:AddLine("How the server adds the bonus is not confirmed; Encore adds it to the chance, as SkillUp Forever's estimate does.", 0.64, 0.57, 0.47, true)
    end
    tip(v.wo, woTip)
    tip(v.woMinus, woTip)
    tip(v.woPlus, woTip)

    v.bar = skillBar(v)
    v.bar:SetPoint("TOPLEFT", 0, -50)

    -- The step to do now
    local now = card(v)
    now:SetPoint("TOPLEFT", 0, -72)
    now:SetSize(INNER, 140)
    v.now = now
    now.head = UI().Text(now, "GameFontNormalSmall", "", UI().DIM)
    now.head:SetPoint("TOPLEFT", 8, -6)
    now.icon = now:CreateTexture(nil, "ARTWORK")
    now.icon:SetSize(30, 30)
    now.icon:SetPoint("TOPLEFT", 8, -20)
    now.title = UI().Text(now, "GameFontNormal", "")
    now.title:SetPoint("TOPLEFT", now.icon, "TOPRIGHT", 8, 0)
    now.title:SetWidth(INNER - 56)
    now.title:SetWordWrap(false)
    now.sub = UI().Text(now, "GameFontHighlightSmall", "", UI().DIM)
    now.sub:SetPoint("TOPLEFT", now.title, "BOTTOMLEFT", 0, -2)
    now.sub:SetWidth(INNER - 56)
    now.hit = CreateFrame("Frame", nil, now)
    now.hit:SetPoint("TOPLEFT", now.icon)
    now.hit:SetPoint("BOTTOMRIGHT", now.sub, "BOTTOMRIGHT")
    tip(now.hit, function(_, tt) return v.nowStep and P.StepTooltip(tt, v.nowStep) end)
    now.reag = {}
    for i = 1, 6 do
        local r = CreateFrame("Frame", nil, now)
        r:SetSize(INNER - 16, 14)
        r:SetPoint("TOPLEFT", 8, -56 - (i - 1) * 14)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(12, 12)
        r.icon:SetPoint("LEFT")
        r.left = UI().Text(r, "GameFontHighlightSmall", "")
        r.left:SetPoint("LEFT", 16, 0)
        r.left:SetWidth(150)
        r.left:SetWordWrap(false)
        r.right = UI().Text(r, "GameFontHighlightSmall", "")
        r.right:SetPoint("RIGHT")
        r.right:SetJustifyH("RIGHT")
        tip(r, function(self, tt) return self.item and P.ReagentTooltip(tt, self.item) end)
        now.reag[i] = r
    end
    now.select = smallButton(now, "Select recipe", 110, function()
        local st = v.nowStep
        local box = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RecipeList
            and ProfessionsFrame.CraftingPage.RecipeList.SearchBox
        if st and box then box:SetText(st.name) end
    end)
    now.select:SetPoint("BOTTOMLEFT", 8, 6)
    tip(now.select, function(_, tt)
        tt:SetText("Select recipe", 1, 0.82, 0)
        tt:AddLine("Finds the recipe in the list on the left. Click it there to craft.", 1, 1, 1, true)
    end)

    -- The next trainer, vendor or quest
    local t = card(v)
    t:SetSize(INNER, 40)
    v.trip = t
    t.text = UI().Text(t, "GameFontHighlightSmall", "")
    t.text:SetPoint("TOPLEFT", 8, -6)
    t.text:SetWidth(INNER - 100)
    t.sub = UI().Text(t, "GameFontHighlightSmall", "", UI().DIM)
    t.sub:SetPoint("TOPLEFT", t.text, "BOTTOMLEFT", 0, -2)
    t.sub:SetWidth(INNER - 100)
    t.go = smallButton(t, "Waypoint", 80, function()
        local pl = t.place
        if pl then P.Waypoint(pl.map, pl.x, pl.y, pl.name or pl.by) end
    end)
    t.go:SetPoint("RIGHT", -6, 0)

    -- Every step, sortable
    v.table = UI().Table(v, {
        { key = "skill", head = "Skill", w = 52 },
        { key = "name", head = "Recipe", w = 126 },
        { key = "crafts", head = "Crafts", w = 38, right = true },
        { key = "cost", head = "Cost", w = 88, right = true },
    }, {
        sort = { key = "skill", desc = false },
        tooltip = function(st, tt) return P.StepTooltip(tt, st) end,
    })

    v.shop = CreateFrame("CheckButton", nil, v, "UICheckButtonTemplate")
    v.shop:SetSize(22, 22)
    v.shopText = UI().Text(v, "GameFontHighlightSmall", "")
    v.shopText:SetPoint("LEFT", v.shop, "RIGHT", 0, 0)
    v.shopText:SetWidth(INNER - 26)
    v.shop:SetScript("OnClick", function(self) P:DB().shopping = self:GetChecked() and true or false; P:Refresh() end)
    local shopTip = function(_, tt)
        local o = P:Open()
        tt:SetText("Auctionator shopping list", 1, 0.82, 0)
        tt:AddLine(("Encore keeps the list \"%s\" in Auctionator's Shopping tab: the auction house reagents still missing for the next 3 steps."):format(P.ListName(o and o.name or "<profession>")), 1, 1, 1, true)
        tt:AddLine("It updates when a step is done, when your bags change and when you recalculate. Vendor reagents stay off it.", 1, 1, 1, true)
        if not P.HasShoppingAPI() then tt:AddLine("Requires Auctionator.", 1, 0.3, 0.3) end
    end
    tip(v.shop, shopTip)

    v.foot = UI().Text(v, "GameFontNormalSmall", "")
    v.foot:SetPoint("BOTTOMLEFT", 0, 0)
    v.footRight = UI().Text(v, "GameFontNormalSmall", "")
    v.footRight:SetPoint("BOTTOMRIGHT", 0, 0)
    v.shop:SetPoint("BOTTOMLEFT", -3, 14)
    v.table:SetPoint("BOTTOMRIGHT", 0, 38)
end

local function buildGather(p)
    local v = CreateFrame("Frame", nil, p)
    v:SetPoint("TOPLEFT", PAD, TOP)
    v:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    view.gather = v
    v.bar = skillBar(v)
    v.bar:SetPoint("TOPLEFT", 0, 0)
    v.what = UI().Text(v, "GameFontHighlightSmall", "")
    v.what:SetPoint("TOPLEFT", 0, -22)
    v.what:SetWidth(INNER)
    v.picks = {}
    for i = 1, 3 do
        local c = card(v)
        c:SetSize(INNER, 44)
        c.rank = UI().Text(c, "GameFontNormalSmall", i == 1 and "Best" or i == 2 and "2nd" or "3rd", UI().COPPER)
        c.rank:SetPoint("TOPLEFT", 8, -6)
        c.zone = UI().Text(c, "GameFontHighlight", "")
        c.zone:SetPoint("TOPLEFT", 44, -6)
        c.zone:SetWidth(INNER - 44 - 150)
        c.zone:SetWordWrap(false)
        c.sub = UI().Text(c, "GameFontHighlightSmall", "", UI().DIM)
        c.sub:SetPoint("TOPLEFT", c.zone, "BOTTOMLEFT", 0, -2)
        c.sub:SetWidth(INNER - 44 - 8)
        c.sub:SetWordWrap(false)
        c.map = smallButton(c, "Map", 46, function() P.ShowMap(c.mapID) end, "dark")
        c.map:SetPoint("TOPRIGHT", -6, -4)
        c.nodes = smallButton(c, "Show nodes", 92, function() if c.kind then P.ShowNodes(c.kind) end end)
        c.nodes:SetPoint("RIGHT", c.map, "LEFT", -4, 0)
        c.nodes:SetMotionScriptsWhileDisabled(true)
        tip(c.nodes, function(self, tt)
            tt:SetText("Show nodes", 1, 0.82, 0)
            if P.HasGatherLite() then
                tt:AddLine("Turns on GatherLite's minimap and world map markers for these nodes.", 1, 1, 1, true)
            else
                tt:AddLine("Requires GatherLite", 1, 0.3, 0.3)
            end
        end)
        tip(c, function(self, tt) return self.tipFn and self.tipFn(tt) end)
        v.picks[i] = c
    end
    v.next = UI().Text(v, "GameFontHighlightSmall", "", UI().DIM)
    v.next:SetWidth(INNER)
    local t = card(v)
    t:SetSize(INNER, 40)
    v.trip = t
    t.text = UI().Text(t, "GameFontHighlightSmall", "")
    t.text:SetPoint("TOPLEFT", 8, -6)
    t.text:SetWidth(INNER - 100)
    t.sub = UI().Text(t, "GameFontHighlightSmall", "", UI().DIM)
    t.sub:SetPoint("TOPLEFT", t.text, "BOTTOMLEFT", 0, -2)
    t.sub:SetWidth(INNER - 100)
    t.go = smallButton(t, "Waypoint", 80, function()
        local pl = t.place
        if pl then P.Waypoint(pl.map, pl.x, pl.y, pl.name or pl.by) end
    end)
    t.go:SetPoint("RIGHT", -6, 0)
    v.note = UI().Text(v, "GameFontHighlightSmall", "", UI().DIM)
    v.note:SetWidth(INNER)
    v.qol = smallButton(v, "Open Encore-QoL Fishing", 200, function() P.OpenQoLFishing() end)
    v.qol:SetMotionScriptsWhileDisabled(true)
    v.qol:SetPoint("BOTTOM", 0, 18)
    v.qolNote = UI().Text(v, "GameFontHighlightSmall", "One-button fishing, keybind and lure settings", UI().DIM)
    v.qolNote:SetPoint("TOP", v.qol, "BOTTOM", 0, -3)
    tip(v.qol, function(_, tt)
        tt:SetText("Encore-QoL Fishing", 1, 0.82, 0)
        if P.HasQoL() then
            tt:AddLine("Opens the Encore-QoL window on its Professions tab, Fishing section.", 1, 1, 1, true)
        else
            tt:AddLine("Requires Encore-QoL", 1, 0.3, 0.3)
        end
    end)
end

local function buildEmpty(p)
    local v = CreateFrame("Frame", nil, p)
    v:SetAllPoints()
    view.empty = v
    local icon = v:CreateTexture(nil, "ARTWORK")
    icon:SetSize(48, 48)
    icon:SetPoint("CENTER", 0, 40)
    icon:SetTexture(ICON)
    icon:SetAlpha(0.6)
    v.title = UI().Text(v, "GameFontNormalLarge", "Select a profession")
    v.title:SetPoint("TOP", icon, "BOTTOM", 0, -10)
    v.text = UI().Text(v, "GameFontHighlightSmall", "Click a profession tab to see its route.", UI().DIM)
    v.text:SetPoint("TOP", v.title, "BOTTOM", 0, -6)
end

local function build()
    panel = CreateFrame("Frame", "EncoreProfessionsPanel", ProfessionsFrame, "PortraitFrameTemplate")
    panel:SetWidth(WIDTH)
    -- Far enough right to clear the profession tabs down the window's right edge.
    panel:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", GAP, 0)
    panel:SetPoint("BOTTOMLEFT", ProfessionsFrame, "BOTTOMRIGHT", GAP, 0)
    panel:EnableMouse(true)
    UI().Skin(panel, ICON)
    -- Closing the guide turns it off, as the Encore button by the skill bar does.
    if panel.CloseButton then panel.CloseButton:SetScript("OnClick", function() P:SetOn(false) end) end
    panel.modes = {}
    local prev
    for _, m in ipairs({ "fast", "cheap" }) do
        local b = smallButton(panel, MODE_NAME[m], m == "fast" and 92 or 70, function()
            P:DB().mode = m
            P:Recalculate()
        end)
        if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", -PAD, -32) end
        tip(b, function(_, tt)
            tt:SetText(MODE_NAME[m], 1, 0.82, 0)
            tt:AddLine(m == "cheap" and "The route with the lowest cost: reagents, recipes and training."
                or "The route with the fewest crafts: orange recipes first, then the cheapest of those.", 1, 1, 1, true)
            tt:AddLine("Changing it recalculates the route.", 0.64, 0.57, 0.47, true)
        end)
        panel.modes[m] = b
        prev = b
    end
    buildCraft(panel)
    buildGather(panel)
    buildEmpty(panel)
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
function P.ReagentTooltip(tt, item)
    tt:SetItemByID(item)
    local p, source, info = P.Price(item)
    if not p then
        tt:AddLine("No price: not sold by vendors and not seen at the auction house. Farm it or scan the auction house.", 1, 0.5, 0.25, true)
    elseif source == "vendor" then
        tt:AddDoubleLine("Vendor", P.Coins(p), 0.64, 0.57, 0.47, 1, 1, 1)
    else
        if info and info.last then tt:AddDoubleLine("Last Auctionator scan", P.Coins(info.last), 0.64, 0.57, 0.47, 1, 1, 1) end
        if info and info.avg7 then tt:AddDoubleLine("7-day average (Encore-Stonks)", P.Coins(info.avg7), 0.64, 0.57, 0.47, 1, 1, 1) end
        if info and info.spike then tt:AddLine("The scan is far from the average, so the route uses the average.", 1, 0.5, 0.25, true) end
    end
end

function P.StepTooltip(tt, st)
    if st.kind == "craft" then
        if tt.SetSpellByID then tt:SetSpellByID(st.spell) else tt:SetText(st.name) end
        tt:AddLine(" ")
        tt:AddDoubleLine("Skill", st.from .. " to " .. st.to, 0.64, 0.57, 0.47, 1, 1, 1)
        tt:AddDoubleLine("Colour at the start", COLOUR_NAME[st.colour] or "?", 0.64, 0.57, 0.47, unpack(COLOUR[st.colour] or COLOUR.x))
        tt:AddDoubleLine("About", st.crafts .. " crafts", 0.64, 0.57, 0.47, 1, 1, 1)
        tt:AddDoubleLine("Reagents", P.Coins(st.total), 0.64, 0.57, 0.47, 1, 1, 1)
        if (st.learn or 0) > 0 then
            tt:AddDoubleLine(type(st.how) == "number" and "Recipe from a vendor" or "Learn at a trainer", P.Coins(st.learn), 0.64, 0.57, 0.47, 1, 1, 1)
        end
        if st.unknown then tt:AddLine("A reagent has no price yet: scan the auction house and recalculate.", 1, 0.5, 0.25, true) end
    elseif st.kind == "rank" then
        local o = P:Open()
        local t = trip(o and o.name or "", st)
        tt:SetText(st.name, 1, 0.82, 0)
        if t then
            tt:AddLine((t.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), 1, 1, 1, true)
            if t.sub ~= "" then tt:AddLine(t.sub, 0.64, 0.57, 0.47, true) end
        end
    elseif st.kind == "gap" then
        tt:SetText("No trainer or vendor recipe", 1, 0.82, 0)
        tt:AddLine("No recipe from a trainer or a vendor gives skill-ups here. Recipes from drops, quests and reputation could.", 1, 1, 1, true)
    end
end

---------------------------------------------------------------------------
-- Showing a crafting route
---------------------------------------------------------------------------
local function stepText(st, key)
    local U = UI()
    if key == "skill" then
        if st.kind == "rank" then return tostring(st.at) end
        return st.from .. "-" .. st.to
    elseif key == "name" then
        if st.kind == "rank" then return "Train " .. st.name, U.COPPER end
        if st.kind == "gap" then return "No trainer or vendor recipe", U.DIM end
        return st.name, COLOUR[st.colour]
    elseif key == "crafts" then
        return st.kind == "craft" and tostring(st.crafts) or ""
    elseif key == "cost" then
        if st.kind == "gap" then return "" end
        if st.kind == "rank" then return P.Coins(st.cost or 0) end
        return P.Coins(st.total + (st.learn or 0)), st.unknown and { 1, 0.5, 0.25 } or nil
    end
end

local function stepValue(st, key)
    if key == "skill" then return st.at or st.from end
    if key == "name" then return st.name or "" end
    if key == "crafts" then return st.crafts or 0 end
    if key == "cost" then return st.kind == "rank" and (st.cost or 0) or ((st.total or 0) + (st.learn or 0)) end
end

local function showCraft(o)
    local v = view.craft
    local route = P:Route(o)
    local idx = P.Progress(route, o.base, o.max)
    local stale = P.Stale(route, idx)
    if stale then
        v.status:SetText("|cffff8040" .. stale .. "|r")
    else
        v.status:SetText(("%s route, made %s"):format(MODE_NAME[route.mode], P.Ago(route.made)))
    end
    local use, points = P:WorkingOvertime()
    v.wo:SetChecked(use)
    v.woPoints:SetText(points .. "/5")
    v.woMinus:SetEnabled(points > 0)
    v.woPlus:SetEnabled(points < P.WO_MAX)

    v.bar:SetMinMaxValues(0, route.top)
    v.bar:SetValue(o.base)
    v.bar.text:SetText(("%s %d / %d"):format(o.shown, o.base, o.max))

    -- Now
    local now, st = v.now, route.steps[idx]
    local y = -72 - 140 - 6
    if st and st.kind == "craft" then
        v.nowStep = st
        now:Show()
        local left = P.CraftsLeft(st, o.base)
        now.head:SetText(("NOW · %d TO %d"):format(st.from, st.to))
        now.icon:SetTexture(st.makes and itemIcon(st.makes) or "Interface\\Icons\\INV_Misc_QuestionMark")
        now.title:SetText(hex(COLOUR[st.colour]) .. ("Make %d × %s|r"):format(left, st.name))
        now.sub:SetText(("%s · about %d crafts for %d points · %s"):format(COLOUR_NAME[st.colour], st.crafts, st.to - st.from, P.Coins(st.total)))
        local n = 0
        for k = 1, #st.reag, 2 do
            n = n + 1
            local r = now.reag[n]
            if not r then break end
            local item, need = st.reag[k], st.reag[k + 1] * left
            local have = math.min(P.Have(item), need)
            local p, source = P.Price(item)
            r.item = item
            r.icon:SetTexture(itemIcon(item))
            r.left:SetText(itemName(item))
            local col = have >= need and "|cff12c7c7" or "|cffa39178"
            r.right:SetText(("%s%d/%d|r · %s"):format(col, have, need, p and (P.Coins((need - have) * p) .. (source == "vendor" and " vendor" or "")) or "|cffff8040no price|r"))
            r:Show()
        end
        for k = n + 1, #now.reag do now.reag[k]:Hide(); now.reag[k].item = nil end
    else
        v.nowStep = nil
        now:Hide()
        y = -72
    end

    -- Next trip: the first rank or recipe to learn from here on
    local t
    for i = idx, #route.steps do
        t = trip(o.name, route.steps[i])
        if t then break end
        if route.steps[i].kind == "gap" then break end
    end
    if t then
        v.trip.text:SetText(t.text)
        v.trip.sub:SetText(t.sub or "")
        v.trip.place = t.place
        v.trip.go:SetEnabled(t.place ~= nil)
        v.trip:ClearAllPoints()
        v.trip:SetPoint("TOPLEFT", 0, y)
        v.trip:Show()
        y = y - 46
    else
        v.trip:Hide()
    end
    v.table:ClearAllPoints()
    v.table:SetPoint("TOPLEFT", 0, y)
    v.table:SetPoint("BOTTOMRIGHT", 0, 38)
    local rows = {}
    for i = idx + 1, #route.steps do rows[#rows + 1] = route.steps[i] end
    v.table:SetRows(rows, stepText, stepValue)

    -- Shopping list
    local hasAPI = P.HasShoppingAPI()
    v.shop:SetEnabled(hasAPI)
    v.shop:SetChecked(hasAPI and P:DB().shopping)
    if not hasAPI then
        v.shopText:SetText("|cff808080Auctionator shopping list (requires Auctionator)|r")
    elseif P:DB().shopping then
        local missing = P.Missing(route, idx, o.base)
        v.shopText:SetText(("Auctionator list \"%s\": %d to buy"):format(P.ListName(o.name), #missing))
        P:UpdateShopping(o.name, route, idx, o.base)
    else
        v.shopText:SetText("Auctionator shopping list")
    end

    local cost, crafts = 0, 0
    for i = idx, #route.steps do
        local s = route.steps[i]
        if s.kind == "craft" then
            local left = P.CraftsLeft(s, o.base)
            crafts = crafts + left
            cost = cost + s.mat * left + ((s.learn or 0) > 0 and not P.Knows(s.spell) and s.learn or 0)
        elseif s.kind == "rank" then
            cost = cost + (s.cost or 0)
        end
    end
    local last = route.steps[#route.steps]
    local goal = last and (last.kind == "gap" and last.from or last.to or last.at) or route.top
    v.foot:SetText(("To %d: %d crafts"):format(goal, crafts))
    v.footRight:SetText(P.Coins(cost))
end

---------------------------------------------------------------------------
-- Showing where to farm
---------------------------------------------------------------------------
local function setTrip(t, prof, cap, at)
    local r = P.NextRank(prof, cap)
    if not r then t:Hide() return false end
    local info = trip(prof, { kind = "rank", at = r.skill, rank = r, name = r.name, cost = r.cost })
    if not info then t:Hide() return false end
    t.text:SetText(info.text)
    t.sub:SetText(info.sub or "")
    t.place = info.place
    t.go:SetEnabled(info.place ~= nil)
    t:Show()
    return true
end

local function showGather(o)
    local v = view.gather
    v.bar:SetMinMaxValues(0, 300)
    v.bar:SetValue(o.base)
    v.bar.text:SetText(("%s %d / %d"):format(o.shown, o.base, o.max))
    local res = P.FarmPicks(o.name, o.base) or { picks = {} }
    local kind = P.GATHERING[o.name]
    local showNodes = (kind == "mining" or kind == "herbalism")
    if o.name == "Mining" or o.name == "Herbalism" then
        local parts = {}
        for i, n in ipairs(res.nodes or {}) do
            if i > 4 then break end
            parts[#parts + 1] = hex(COLOUR[n.colour]) .. n.node.name .. "|r"
        end
        v.what:SetText(#parts > 0 and ("Skill-ups from " .. table.concat(parts, ", ")) or "No node gives skill-ups at your skill.")
    elseif o.name == "Skinning" then
        v.what:SetText(("You can skin beasts up to level %d. Zones with the most beasts that still give skill-ups:"):format(res.maxLevel or 0))
    else
        v.what:SetText("Fish where the zone level is close to your skill ÷ 5; a catch can still get away below it.")
    end
    local y = -22 - (v.what:GetStringHeight() or 12) - 8
    for i, c in ipairs(v.picks) do
        local pk = res.picks[i]
        if pk then
            c.mapID = pk.map
            c.zone:SetText(pk.name or P.ZoneName(pk.map))
            local info, z = pk.info, ns.Zones[pk.map]
            if o.name == "Skinning" then
                c.sub:SetText(("Beasts level %d-%d · about %d spawns"):format(info.lo, info.hi, info.spawns))
            elseif o.name == "Fishing" then
                local names = {}
                for k, id in ipairs(info.fish) do if k <= 2 then names[#names + 1] = itemName(id) end end
                if info.city then
                    c.sub:SetText(("City water · %s"):format(table.concat(names, ", ")))
                else
                    c.sub:SetText(("Zone level %d-%d · %s"):format(info.lo, info.hi, table.concat(names, ", ")))
                end
            else
                c.sub:SetText(("About %d nodes · %s%s"):format(info.nodes, table.concat(info.names, ", "),
                    z and (" · level " .. z.lo .. "-" .. z.hi) or ""))
            end
            c.kind = showNodes and kind or nil
            c.nodes:SetShown(showNodes)
            c.nodes:SetEnabled(showNodes and P.HasGatherLite())
            c.tipFn = function(tt)
                tt:SetText(pk.name or P.ZoneName(pk.map), 1, 0.82, 0)
                if pk.maps then
                    local zones = {}
                    for _, m in ipairs(pk.maps) do zones[#zones + 1] = P.ZoneName(m) end
                    tt:AddLine(table.concat(zones, ", "), 0.95, 0.9, 0.81, true)
                end
                tt:AddLine(c.sub:GetText(), 1, 1, 1, true)
                if o.name == "Fishing" then
                    for _, id in ipairs(info.fish) do tt:AddLine(itemName(id), 0.64, 0.57, 0.47) end
                end
            end
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 0, y)
            c:Show()
            y = y - 48
        else
            c:Hide()
        end
    end
    if #res.picks == 0 then
        v.next:SetText("No zone found for your skill.")
    elseif res.nextNode then
        v.next:SetText(("At %d: %s"):format(res.nextNode.levels[1], res.nextNode.name))
    else
        v.next:SetText("")
    end
    v.next:ClearAllPoints()
    v.next:SetPoint("TOPLEFT", 0, y - 2)
    y = y - 20
    v.trip:ClearAllPoints()
    v.trip:SetPoint("TOPLEFT", 0, y)
    if setTrip(v.trip, o.name, o.max, o.base) then y = y - 46 end
    v.note:ClearAllPoints()
    v.note:SetPoint("TOPLEFT", 0, y)
    if o.name == "Mining" then
        v.note:SetText("Smelting also gives skill-ups.")
    elseif o.name == "Fishing" then
        v.note:SetText("Fishing skill goes up with every catch, faster at low skill. Where you fish doesn't change that, as long as fish don't get away.")
    else
        v.note:SetText("")
    end
    local fishing = o.name == "Fishing"
    v.qol:SetShown(fishing)
    v.qolNote:SetShown(fishing)
    v.qol:SetEnabled(fishing and P.HasQoL())
end

---------------------------------------------------------------------------
-- Route storage
---------------------------------------------------------------------------
function P:Route(o)
    local routes = self:Char().routes
    local r = routes[o.name]
    if not r or r.version ~= 1 then
        r = self:MakeRoute(o)
    end
    return r
end

function P:MakeRoute(o)
    local r = P.Plan(o.name, o.base, { mode = self:DB().mode, bonus = self:Bonus(), cap = o.max })
    r.version = 1
    self:Char().routes[o.name] = r
    return r
end

function P:Recalculate()
    local o = self:Open()
    if not o or P.GATHERING[o.name] or o.name == "Fishing" or not ns.Recipes[o.name] then return false end
    self:MakeRoute(o)
    self:Refresh()
    return true
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local lastKey
function P:Refresh()
    if not (panel and ProfessionsFrame) then return end
    if button then
        local on = self:IsOn()
        button.icon:SetDesaturated(not on)
        button.icon:SetAlpha(on and 1 or 0.6)
        button.glow:SetShown(on)
    end
    if not (self:IsOn() and ProfessionsFrame:IsShown()) then panel:Hide() return end
    panel:Show()
    local o = self:Open()
    view.empty:Hide(); view.craft:Hide(); view.gather:Hide()
    for _, b in pairs(panel.modes) do b:Hide() end
    if not o then
        panel.title:SetText("Levelling guide")
        view.empty:Show()
        lastKey = nil
        return
    end
    lastKey = o.name .. ":" .. o.base .. ":" .. o.max
    if P.GATHERING[o.name] or o.name == "Fishing" then
        panel.title:SetText(o.name == "Fishing" and "Where to fish" or "Where to farm")
        view.gather:Show()
        showGather(o)
    elseif ns.Recipes[o.name] then
        panel.title:SetText("Levelling guide")
        for m, b in pairs(panel.modes) do
            b:Show()
            b:SetOn(self:DB().mode == m)
        end
        view.craft:Show()
        showCraft(o)
    else
        panel.title:SetText("Levelling guide")
        view.empty:Show()
    end
end

local function protectedRefresh()
    local ok, err = pcall(P.Refresh, P)
    if not ok then geterrorhandler()(err) end
end

---------------------------------------------------------------------------
-- The Encore button by the skill bar
---------------------------------------------------------------------------
local function buildButton()
    button = CreateFrame("Button", "EncoreProfessionsButton", ProfessionsFrame)
    button:SetSize(28, 28)
    local page = ProfessionsFrame.CraftingPage
    local bar = page and page.RankBar
    if bar then
        button:SetPoint("LEFT", bar, "RIGHT", 8, 0)
    else
        button:SetPoint("TOPRIGHT", ProfessionsFrame, "TOPRIGHT", -40, -28)
    end
    button:SetFrameLevel((ProfessionsFrame:GetFrameLevel() or 1) + 20)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture(ICON)
    local mask = button:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(button.icon)
    button.icon:AddMaskTexture(mask)
    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(48, 48)
    ring:SetPoint("TOPLEFT", -4, 4)
    button.glow = button:CreateTexture(nil, "BACKGROUND")
    button.glow:SetPoint("CENTER")
    button.glow:SetSize(40, 40)
    button.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    button.glow:SetBlendMode("ADD")
    button.glow:SetVertexColor(0.07, 0.78, 0.78)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    button:SetScript("OnClick", function()
        P:SetOn(not P:IsOn())
    end)
    tip(button, function(_, tt)
        tt:SetText("Encore-Professions", 1, 0.82, 0)
        tt:AddLine("Turns the levelling guide on or off. Encore remembers the setting.", 1, 1, 1, true)
        tt:AddLine("While it is on, the guide opens by itself whenever you open your professions.", 1, 1, 1, true)
        tt:AddLine(P:IsOn() and "On" or "Off", 0.07, 0.78, 0.78)
    end)
end

---------------------------------------------------------------------------
-- Hooking the profession window (Blizzard_Professions loads when it is first opened)
---------------------------------------------------------------------------
local attached
local function attach()
    if attached or not ProfessionsFrame then return end
    attached = true
    build()
    buildButton()
    panel:Hide()
    ProfessionsFrame:HookScript("OnShow", function() C_Timer.After(0, protectedRefresh) end)
    ProfessionsFrame:HookScript("OnHide", function() panel:Hide() end)
    -- The window changes profession through its own tabs; check a few times a second while it shows.
    local elapsed, rowKey = 0, nil
    panel.watch = CreateFrame("Frame", nil, ProfessionsFrame)
    panel.watch:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.5 then return end
        elapsed = 0
        local o = P:Open()
        local key = o and (o.name .. ":" .. o.base .. ":" .. o.max) or nil
        -- The chance and profit beside each recipe follow the skill, guide on or off.
        if key ~= rowKey then rowKey = key; P.RefreshRecipeRows() end
        if not P:IsOn() then return end
        if key ~= lastKey or not panel:IsShown() then protectedRefresh() end
    end)
    P.AttachRecipeList()
    if ProfessionsFrame:IsShown() then protectedRefresh() end
end

P.Attach = attach

local bagsPending
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("BAG_UPDATE_DELAYED")
pcall(events.RegisterEvent, events, "TRADE_SKILL_LIST_UPDATE")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == "Blizzard_Professions" then attach() end
    elseif event == "PLAYER_LOGIN" then
        P:DB()
        attach()
    elseif event == "BAG_UPDATE_DELAYED" or event == "TRADE_SKILL_LIST_UPDATE" then
        if panel and ProfessionsFrame:IsShown() and not bagsPending then
            bagsPending = true
            C_Timer.After(1, function()
                bagsPending = false
                if panel:IsShown() then protectedRefresh() end
                if event == "TRADE_SKILL_LIST_UPDATE" then P.RefreshRecipeRows() end
            end)
        end
    end
end)
