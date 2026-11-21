-- Encore-Stonks browser: laid out like the auction house's Browse tab, but over Stonks' price history only.
-- Category tree on the left (the auction house's own categories), search on top, results on the right
-- (only items Stonks or Auctionator has prices for). Clicking a result shows it in the graph panel (Panel.lua),
-- which docks to the right of this window.
local _, ns = ...
local Stonks = ns.Stonks
local U = ns.UI
local Browse = ns.Browse
-- WoW Forever has no global GetItemInfo; the C_Item one is the same call.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

local TEAL_SOFT, COPPER, GOLD, INK, DIM = U.TEAL_SOFT, U.COPPER, U.GOLD, U.INK, U.DIM
local setColor, gradient, coinShort = U.setColor, U.gradient, U.coinShort
local itemName, itemIcon, itemQualityColor, linkFor, itemIDOf = U.itemName, U.itemIcon, U.itemQualityColor, U.linkFor, U.itemIDOf

local TREE_W = 176
local TREE_ROW_H, RESULT_ROW_H = 20, 26
local PAGE_SIZE = 100 -- items per page (Det, 2026-11-21: 500 at once lagged when sorting by iLvl/Req)

local frame, tree, results, searchBox, countText, pager
local renderTree, renderResults, settingsSort

-- Item level and required level columns (Det, 2026-11-21). Shown only while the list holds items where they mean
-- something: consumables, containers, weapons, gems, armor, ammo, quivers and quest items. Trade goods, reagents,
-- recipes and the like have an item level too, but it says nothing about them.
local LEVEL_CLASSES = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [6] = true, [11] = true, [12] = true }
local LEVEL_SORTS = { ilvl = true, req = true }
local NAME_RIGHT, NAME_RIGHT_LEVELS = -250, -334
local showLevels = false
local levelButtons, refreshHeader = {}, nil

local state = {
    node = "all",     -- selected tree entry id
    match = nil,      -- function(key, name) for the selected category or list
    expanded = {},    -- [id] = true for open categories
    search = "",
    page = 1,         -- current results page
    base = nil,       -- last price/name sort { id, desc }: decides which items are on which page
}

---------------------------------------------------------------------------
-- Data helpers
---------------------------------------------------------------------------
local function sampleCount(key)
    local r = Stonks.realmData
    local str = r and r.items[key]
    local n = str and select(2, str:gsub(";", ";")) or 0
    if Stonks:Pending(key) then n = n + 1 end
    return n
end

local function auctionatorDays(key)
    if not Stonks:Settings().useAuctionator then return 0 end
    local a = _G.Auctionator
    local entry = a and a.Database and type(a.Database.db) == "table" and a.Database.db[key]
    if type(entry) ~= "table" or type(entry.h) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(entry.h) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- Category tree (looks like the auction house's filter list)
---------------------------------------------------------------------------
local function initTreeRow(row)
    if row.built then return end
    row.built = true
    row:SetHeight(TREE_ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetPoint("TOPLEFT", 0, -1)
    row.bg:SetPoint("BOTTOMRIGHT", 0, 1)
    gradient(row.bg, "VERTICAL", 0.16, 0.11, 0.07, 1, 0.30, 0.22, 0.14, 1)
    row.edge = U.addBorder(row, 0.45, 0.33, 0.2, 0.9)
    row.edge[1]:SetPoint("TOPLEFT", 0, -1); row.edge[1]:SetPoint("TOPRIGHT", 0, -1)
    row.edge[2]:SetPoint("BOTTOMLEFT", 0, 1); row.edge[2]:SetPoint("BOTTOMRIGHT", 0, 1)
    row.sel = row:CreateTexture(nil, "ARTWORK")
    row.sel:SetPoint("TOPLEFT", 1, -2)
    row.sel:SetPoint("BOTTOMRIGHT", -1, 2)
    gradient(row.sel, "HORIZONTAL", 0.55, 0.75, 1, 0.55, 0.35, 0.55, 1, 0.15)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -2)
    hl:SetPoint("BOTTOMRIGHT", -1, 2)
    hl:SetColorTexture(1, 0.9, 0.6, 0.12)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        local d = self.data
        if not d or d.heading then return end
        if d.children and #d.children > 0 then
            -- Like the auction house: clicking an open, selected category closes it
            if state.node == d.id and state.expanded[d.id] then
                state.expanded[d.id] = nil
            else
                state.expanded[d.id] = true
            end
        end
        state.node, state.match, state.page = d.id, d.match, 1
        if d.onSelect then d.onSelect() end
        renderTree()
        renderResults()
    end)
end

local function fillTreeRow(row, d)
    initTreeRow(row)
    row.data = d
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", 8 + (d.depth or 0) * 12, 0)
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetText(d.text)
    local selected = d.id == state.node
    row.sel:SetShown(selected)
    if d.heading then
        row.bg:Hide()
        for _, t in ipairs(row.edge) do t:Hide() end
        row.text:SetFontObject("GameFontDisableSmall")
        row.text:SetTextColor(0.5, 0.5, 0.5)
        row:EnableMouse(false)
        return
    end
    row:EnableMouse(true)
    row.bg:Show()
    for _, t in ipairs(row.edge) do t:Show() end
    row.bg:SetAlpha((d.depth or 0) > 0 and 0.7 or 1)
    -- Auction house colours: gold categories, white subcategories, white for the selected entry.
    -- Set every time: rows are recycled, and a font object doesn't undo an earlier SetTextColor.
    if (d.depth or 0) > 0 then
        row.text:SetFontObject("GameFontHighlightSmall")
        row.text:SetTextColor(1, 1, 1)
    else
        row.text:SetFontObject("GameFontNormalSmall")
        if selected then row.text:SetTextColor(1, 1, 1) else row.text:SetTextColor(1, 0.82, 0) end
    end
end

local categoryCache
local function categories()
    -- The game's own list appears once the auction house has been opened; rebuild then.
    local fromGame = type(_G.AuctionCategories) == "table" and #_G.AuctionCategories > 0
    if not categoryCache or categoryCache.fromGame ~= fromGame then
        categoryCache = { fromGame = fromGame, tree = Browse.Categories(Stonks:AllKeys(), itemIDOf) }
    end
    return categoryCache.tree
end

function renderTree()
    if not tree then return end
    local rows = {}
    rows[#rows + 1] = { id = "all", text = "All items", depth = 0, onSelect = function() Stonks:ShowMarket() end }
    local function add(node, depth, path)
        local id = "cat:" .. path .. node.name
        local match = function(key)
            local c = Browse.ItemClass(itemIDOf(key))
            return c ~= nil and node.match(c)
        end
        rows[#rows + 1] = { id = id, text = node.name, depth = depth, match = match, children = node.children }
        if state.expanded[id] then
            for _, child in ipairs(node.children or {}) do add(child, depth + 1, path .. node.name .. "/") end
        end
    end
    for _, node in ipairs(categories()) do add(node, 0, "") end

    local lists = Browse.ShoppingLists()
    if #lists > 0 then
        rows[#rows + 1] = { id = "h:lists", text = "Auctionator shopping lists", heading = true }
        for _, name in ipairs(lists) do
            rows[#rows + 1] = {
                id = "list:" .. name, text = name, depth = 0,
                match = (function()
                    local m
                    return function(_, itemNameText)
                        m = m or Browse.ShoppingListMatcher(name) or function() return false end
                        return m(itemNameText)
                    end
                end)(),
                onSelect = function() Stonks:ShowList(name) end,
            }
        end
    end
    tree:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------
-- Item level and required level, from the game's item cache (nil until the item has loaded).
local function itemLevels(key)
    local id = itemIDOf(key)
    if not id then return nil end
    local _, _, _, ilvl, req = GetItemInfo(id)
    return ilvl, req
end

local function hasLevels(key)
    local c = Browse.ItemClass(itemIDOf(key))
    return c ~= nil and LEVEL_CLASSES[c[1]] == true
end

local statsCache = {}
-- Stats per item, kept until new prices arrive (sorting by a price column needs them for every listed item).
local function statsFor(key)
    local st = statsCache[key]
    if st == nil then
        st = Stonks:ItemStats(key) or false
        statsCache[key] = st
    end
    return st or nil
end

-- Column sort, saved with the window settings. Default: most days of data first.
function settingsSort()
    local w = Stonks:Settings().window
    if type(w) ~= "table" then return { id = "days", desc = true } end
    if type(w.sort) ~= "table" or not w.sort.id then w.sort = { id = "days", desc = true } end
    return w.sort
end

local function initResultRow(row)
    if row.built then return end
    row.built = true
    row:SetHeight(RESULT_ROW_H)
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetColorTexture(1, 1, 1, 0.03)
    row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.sel:SetAllPoints()
    gradient(row.sel, "HORIZONTAL", 0.76, 0.08, 0.05, 0.55, 0.23, 0.01, 0, 0.15)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.9, 0.6, 0.08)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 4, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", NAME_RIGHT, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.last = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.last:SetPoint("RIGHT", -180, 0)
    row.avg = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.avg:SetPoint("RIGHT", -100, 0)
    row.trend = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.trend:SetPoint("RIGHT", -46, 0)
    row.days = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.days:SetPoint("RIGHT", -6, 0)
    setColor(row.days, DIM)
    row.ilvl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.ilvl:SetPoint("RIGHT", -296, 0)
    row.req = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.req:SetPoint("RIGHT", -256, 0)
    row:SetScript("OnClick", function(self)
        if not self.key then return end
        if IsModifiedClick("CHATLINK") then
            local link = linkFor(self.key)
            if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
            return
        end
        Stonks:ShowItem(self.key)
    end)
    U.tooltip(row, function(tt, self)
        local link = self.key and linkFor(self.key)
        if link then tt:SetHyperlink(link) else tt:SetText(itemName(self.key)) end
        tt:AddLine(" ")
        tt:AddLine(("%d Stonks samples, %d Auctionator days"):format(self.samples or 0, self.adays or 0), TEAL_SOFT[1], TEAL_SOFT[2], TEAL_SOFT[3])
        tt:AddLine("Click to show its price history.", DIM[1], DIM[2], DIM[3])
    end)
end

local function fillResultRow(row, d)
    initResultRow(row)
    row.key, row.samples, row.adays = d.key, d.samples, d.days
    row.stripe:SetShown(d.index % 2 == 0)
    row.sel:SetShown(d.key == Stonks:PanelKey())
    row.icon:SetTexture(itemIcon(d.key))
    row.name:SetText(itemName(d.key))
    row.name:SetTextColor(itemQualityColor(d.key))
    local st = statsFor(d.key)
    row.last:SetText(coinShort(st and st.last))
    row.avg:SetText(coinShort(st and st.avg7))
    local pct = st and st.last and st.avg14 and (st.last / st.avg14 - 1) * 100 or nil
    row.trend:SetText(U.pctColored(pct))
    row.days:SetText(tostring((st and st.days) or 0))

    -- Level columns: blank for items they don't apply to (an All items list mixes gear with trade goods)
    row.name:SetPoint("RIGHT", showLevels and NAME_RIGHT_LEVELS or NAME_RIGHT, 0)
    row.ilvl:SetShown(showLevels)
    row.req:SetShown(showLevels)
    if showLevels then
        local ilvl, req
        if hasLevels(d.key) then ilvl, req = itemLevels(d.key) end
        row.ilvl:SetText(ilvl and ilvl > 0 and tostring(ilvl) or "")
        if req and req > 1 then
            row.req:SetText(tostring(req))
            if req > (UnitLevel("player") or 0) then row.req:SetTextColor(1, 0.25, 0.25) else row.req:SetTextColor(1, 1, 1) end
        else
            row.req:SetText("")
        end
    end
end

-- Shows or hides the two level columns in the header.
local function setLevelColumns(on)
    showLevels = on
    for _, b in ipairs(levelButtons) do b:SetShown(on) end
    local sort = settingsSort()
    if not on and LEVEL_SORTS[sort.id] then
        -- Sorted by a column that went away: back to the default until it comes back
        sort.id, sort.desc = "days", true
        if refreshHeader then refreshHeader() end
    end
end

-- Pages of PAGE_SIZE. The pages follow the price, name or days sort over the whole list (those values are cached).
-- iLvl and Req only reorder the page on screen: they need the game's item info, and asking for it for thousands of
-- items at once is what lagged the game.
local function rowValue(d, id)
    if id == "name" then return d.name end
    if id == "ilvl" or id == "req" then
        if not hasLevels(d.key) then return nil end
        local ilvl, req = itemLevels(d.key)
        if id == "ilvl" then return ilvl end
        return req or nil
    end
    local st = statsFor(d.key)
    if not st then return nil end
    if id == "trend" then return st.last and st.avg14 and (st.last / st.avg14 - 1) or nil end
    return st[id]
end

function renderResults(keepScroll)
    if not results then return end
    local search = state.search:lower()
    local match = state.match
    local found = {}
    local levels = false
    for _, key in ipairs(Stonks:AllKeys()) do
        local name = itemName(key)
        if (search == "" or name:lower():find(search, 1, true) or tostring(key) == search)
            and (not match or match(key, name)) then
            found[#found + 1] = { key = key, name = name, samples = sampleCount(key), days = auctionatorDays(key) }
            levels = levels or hasLevels(key)
        end
    end
    setLevelColumns(levels)

    local sort = settingsSort()
    if not LEVEL_SORTS[sort.id] then state.base = { id = sort.id, desc = sort.desc } end
    U.SortRows(found, state.base or { id = "days", desc = true }, rowValue)

    local pages = math.max(1, math.ceil(#found / PAGE_SIZE))
    state.page = math.min(math.max(1, state.page or 1), pages)
    local first = (state.page - 1) * PAGE_SIZE
    local rows = {}
    for i = first + 1, math.min(first + PAGE_SIZE, #found) do
        rows[#rows + 1] = found[i]
    end
    if LEVEL_SORTS[sort.id] then U.SortRows(rows, sort, rowValue) end
    for i, d in ipairs(rows) do d.index = i end
    results:SetDataProvider(CreateDataProvider(rows), keepScroll and ScrollBoxConstants.RetainScrollPosition or nil)

    countText:SetText(("%d items with prices"):format(#found))
    if pager then pager:Update(state.page, pages, #found, first + 1, first + #rows) end
end

local function createList(parent, template, extent, init)
    local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", 3, -3)
    box:SetPoint("BOTTOMRIGHT", -14, 3)
    local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 2, -2)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 2, 2)
    bar:SetHideIfUnscrollable(true)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(extent)
    view:SetElementInitializer(template, init)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    return box
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function openOptions(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Keep hourly detail for")
        for _, d in ipairs(Stonks.KEEP_DAYS_OPTIONS) do
            root:CreateRadio(d .. " days", function(v) return Stonks:KeepDays() == v end, function(v)
                Stonks:SetKeepDays(v)
                Stonks:InvalidateMarket()
            end, d)
        end
        root:CreateDivider()
        root:CreateCheckbox("Also use Auctionator's daily history", function() return Stonks:Settings().useAuctionator == true end, function()
            Stonks:Settings().useAuctionator = not Stonks:Settings().useAuctionator
            Stonks:InvalidateMarket()
            renderResults()
        end)
        root:CreateCheckbox("Open the graph beside the auction house", function() return Stonks:Settings().dockAH ~= false end, function()
            Stonks:Settings().dockAH = Stonks:Settings().dockAH == false
        end)
        root:CreateCheckbox("Show averages in item tooltips", function() return Stonks:Settings().tooltip ~= false end, function()
            Stonks:Settings().tooltip = Stonks:Settings().tooltip == false
        end)
        root:CreateDivider()
        root:CreateButton("Reset window size and position", function() frame:ResetSize(); Stonks:DockPanel() end)
    end)
end

local function createWindow()
    frame = U.CreateWindow({
        name = "EncoreStonksFrame", title = "Encore-Stonks", width = 780, height = 470, minW = 700, minH = 380,
        settingsKey = "window", onOptions = openOptions, defaultX = -280,
        onMoved = function() Stonks:DockPanel() end,
    })

    -- Search, like the auction house's Name box
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 70, -34)
    label:SetText("Name")
    searchBox = CreateFrame("EditBox", "EncoreStonksSearchBox", frame, "SearchBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("LEFT", label, "RIGHT", 10, 0)
    searchBox:SetAutoFocus(false)
    if searchBox.Instructions then searchBox.Instructions:SetText("Search, or shift-click an item") end
    searchBox:HookScript("OnTextChanged", function(self)
        local value = strtrim(self:GetText() or "")
        if value ~= state.search then
            state.search, state.page = value, 1
            renderResults()
        end
    end)
    countText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("LEFT", searchBox, "RIGHT", 14, 0)
    countText:SetPoint("RIGHT", -40, 0)
    countText:SetJustifyH("LEFT")
    countText:SetWordWrap(false)
    setColor(countText, DIM)

    -- Category tree
    local treePane = U.well(frame)
    treePane:SetPoint("TOPLEFT", 12, -62)
    treePane:SetPoint("BOTTOMLEFT", 12, 28)
    treePane:SetWidth(TREE_W)
    tree = createList(treePane, "EncoreStonksTreeRowTemplate", TREE_ROW_H, fillTreeRow)

    -- Results with a column header
    local resultPane = U.well(frame)
    resultPane:SetPoint("TOPLEFT", 12 + TREE_W + 6, -62)
    resultPane:SetPoint("BOTTOMRIGHT", -12, 28)
    local head = CreateFrame("Frame", nil, resultPane)
    head:SetPoint("TOPLEFT", 3, -3)
    head:SetPoint("TOPRIGHT", -17, -3)
    head:SetHeight(18)
    local headBg = head:CreateTexture(nil, "BACKGROUND")
    headBg:SetAllPoints()
    gradient(headBg, "VERTICAL", 0.09, 0.06, 0.04, 1, 0.17, 0.13, 0.09, 1)
    local sort = settingsSort()
    local headButtons
    refreshHeader, headButtons = U.SortHeader(head, {
        { id = "name", label = "Item", point = "LEFT", x = 30, width = 160, tip = "Item name." },
        { id = "ilvl", label = "iLvl", point = "RIGHT", x = -296, width = 36, desc = true, tip = "Item level." },
        { id = "req", label = "Req", point = "RIGHT", x = -256, width = 34, desc = true, tip = "Required level to use the item. Red when it is above your level." },
        { id = "last", label = "Last", point = "RIGHT", x = -180, width = 70, desc = true, tip = "Lowest buyout on the last day seen." },
        { id = "avg7", label = "7-day avg", point = "RIGHT", x = -100, width = 76, desc = true, tip = "Moving average of the daily lows over 7 days." },
        { id = "trend", label = "Trend", point = "RIGHT", x = -46, width = 50, desc = true, tip = "Last price against the 14-day average." },
        { id = "days", label = "Days", point = "RIGHT", x = -6, width = 38, desc = true, tip = "Days with a price." },
    }, sort, function()
        -- A new price/name order reshuffles the pages: start at page 1. iLvl/Req only sort the page you're on.
        if not LEVEL_SORTS[sort.id] then state.page = 1 end
        renderResults()
    end)
    local listHolder = CreateFrame("Frame", nil, resultPane)
    listHolder:SetPoint("TOPLEFT", 0, -21)
    listHolder:SetPoint("BOTTOMRIGHT")
    results = createList(listHolder, "EncoreStonksResultRowTemplate", RESULT_ROW_H, fillResultRow)
    levelButtons = { headButtons[2], headButtons[3] } -- iLvl, Req
    Stonks:Settings().filters = nil -- left over from the Filter dropdown (0.1.3-beta to 0.1.5)

    local credit = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    credit:SetPoint("BOTTOMLEFT", 16, 9)
    credit:SetText("Only items with recorded prices are listed. Prices from your Auctionator scans.")
    setColor(credit, DIM)

    -- Page arrows, bottom right: < Page 2 of 14 >
    pager = CreateFrame("Frame", nil, frame)
    pager:SetSize(170, 24)
    pager:SetPoint("BOTTOMRIGHT", -14, 3)
    local function arrow(dir)
        local b = CreateFrame("Button", nil, pager)
        b:SetSize(24, 24)
        local tex = "Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-"
        b:SetNormalTexture(tex .. "Up")
        b:SetPushedTexture(tex .. "Down")
        b:SetDisabledTexture(tex .. "Disabled")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        return b
    end
    pager.prev, pager.next = arrow("Prev"), arrow("Next")
    pager.next:SetPoint("RIGHT")
    pager.text = pager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pager.text:SetPoint("RIGHT", pager.next, "LEFT", -4, 0)
    pager.prev:SetPoint("RIGHT", pager.text, "LEFT", -4, 0)
    local function turn(delta)
        state.page = (state.page or 1) + delta
        renderResults()
    end
    pager.prev:SetScript("OnClick", function() turn(-1) end)
    pager.next:SetScript("OnClick", function() turn(1) end)
    U.tooltip(pager.prev, function(tt) tt:SetText("Previous page") end)
    U.tooltip(pager.next, function(tt) tt:SetText("Next page") end)
    function pager:Update(page, pages, total, from, to)
        self.text:SetText(("Page %d of %d"):format(page, pages))
        self.prev:SetEnabled(page > 1)
        self.next:SetEnabled(page < pages)
        self.range = total > 0 and ("Items %d to %d of %d"):format(from, to, total) or nil
    end
    U.tooltip(pager, function(tt, self)
        tt:SetText(self.text:GetText() or "")
        if self.range then tt:AddLine(self.range, 1, 1, 1) end
        tt:AddLine("iLvl and Req sort the items on this page.", 0.6, 0.55, 0.45, true)
    end)
    pager:EnableMouse(true)
    credit:SetPoint("RIGHT", pager, "LEFT", -8, 0)
    credit:SetJustifyH("LEFT")
    credit:SetWordWrap(false)

    local namesPending = false
    local watcher = CreateFrame("Frame", nil, frame)
    watcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    watcher:SetScript("OnEvent", function()
        if namesPending or not frame:IsShown() then return end
        namesPending = true
        C_Timer.After(0.5, function()
            namesPending = false
            if frame:IsShown() then renderResults(true) end
        end)
    end)

    frame:HookScript("OnShow", function()
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
        renderTree()
        renderResults()
        Stonks:ShowPanel() -- the graph panel docks to the right of this window
    end)
    frame:HookScript("OnHide", function()
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
        GameTooltip:Hide()
        -- The panel goes with the browser unless the auction house is open
        local ah = _G.AuctionFrame or _G.AuctionHouseFrame
        if ah and ah:IsShown() then Stonks:DockPanel() else Stonks:HidePanel() end
    end)
end

-- Selected item changed in the panel: refresh the highlight.
function Stonks:OnPanelItem()
    if frame and frame:IsShown() and results then
        results:ForEachFrame(function(row)
            if row.sel then row.sel:SetShown(row.key ~= nil and row.key == Stonks:PanelKey()) end
        end)
    end
end

-- New prices while the browser is open
local refreshTimer
function Stonks:OnBrowserData()
    wipe(statsCache)
    if not frame or not frame:IsShown() or refreshTimer then return end
    refreshTimer = C_Timer.NewTimer(3, function()
        refreshTimer = nil
        renderResults(true)
    end)
end

-- Shift-click an item (bags, chat, Auctionator) while the search box has focus: show that item.
local function onInsertLink(link)
    if not (searchBox and searchBox:HasFocus() and type(link) == "string") then return end
    local key = link:match("|Hitem:(%d+)")
    if not key then return end
    searchBox:SetText(itemName(key))
    searchBox:ClearFocus()
    Stonks:ShowItem(key)
end
if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", onInsertLink) end
if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", onInsertLink) end

function Stonks:ToggleWindow()
    if not frame then createWindow() end
    frame:SetShown(not frame:IsShown())
end
