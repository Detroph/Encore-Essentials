-- Encore-Stonks: the Deals tab in the auction house (Det, 2026-11-26).
--
-- A tab after Auctionator's tabs lists the listings of the last Auctionator full scan that are
--   * cheaper than a vendor pays for them ("Under vendor price"), or
--   * a chosen percentage (slider, 5-90%) under the Stonks 3, 7 or 14-day average ("Under market price").
-- Only a scan under 15 minutes old counts (that is also the full scan cooldown). After that the rows empty and
-- "Requires a fresh Auctionator scan" fills the middle of the tab, with a button that starts one.
-- Clicking a row, or Buy all, opens the buy prompt on the same tab (DealsBuy.lua).
--
-- The tab is made with LibAHTab-1-0, the library Auctionator uses for its own tabs; it comes with Auctionator, so
-- the tab exists only when Auctionator is loaded. The listings come from Auctionator's full scan: its ScanComplete
-- event passes every listing of the scan (Auctionator itself keeps only the lowest price per item). They are kept
-- in memory only, never saved. Averages are worked out from the days before today, so the scan's own low prices
-- don't pull them down; launch week is left out as everywhere in Stonks (Stats.lua).
local _, ns = ...
local Stonks = ns.Stonks
local U = ns.UI
local Deals = {}
Stonks.Deals = Deals

local FRESH_SECONDS = 15 * 60
local SCAN_COOLDOWN = 15 * 60
local PCT_MIN, PCT_MAX, PCT_STEP = 5, 90, 5
local MIN_DAYS = 3
local BUDGET_MS = 4
local ROW_H = 22
local TAB_ID = "EncoreStonksDeals"
Deals.FRESH_SECONDS, Deals.MIN_DAYS = FRESH_SECONDS, MIN_DAYS

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local floor, max, min = math.floor, math.max, math.min
local coin, coinShort = U.coin, U.coinShort
local TEAL_SOFT, DIM, INK = U.TEAL_SOFT, U.DIM, U.INK

-- Errors are reported once each in chat (many players have Lua errors hidden).
local reported = {}
local function safe(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok and not reported[err] then
            reported[err] = true
            print("|cffd9a066Encore-Stonks|r Deals error: " .. tostring(err))
        end
    end
end
Deals.safe = safe

---------------------------------------------------------------------------
-- Settings (saved in EncoreStonksDB.settings.deals)
---------------------------------------------------------------------------
local function S()
    local s = Stonks:Settings()
    if type(s.deals) ~= "table" then s.deals = {} end
    local d = s.deals
    if d.mode ~= "market" then d.mode = "vendor" end
    local p = tonumber(d.pct) or 30
    d.pct = max(PCT_MIN, min(PCT_MAX, floor(p / PCT_STEP + 0.5) * PCT_STEP))
    if d.avg ~= 3 and d.avg ~= 14 then d.avg = 7 end
    if d.minDays == nil then d.minDays = true end
    if d.greys == nil then d.greys = true end
    if d.gear == nil then d.gear = true end
    if type(d.sortvendor) ~= "table" or not d.sortvendor.id then d.sortvendor = { id = "total", desc = true } end
    if type(d.sortmarket) ~= "table" or not d.sortmarket.id then d.sortmarket = { id = "under", desc = true } end
    return d
end
Deals.Settings = S
function Deals.Enabled() return Stonks:Settings().dealsTab ~= false end

---------------------------------------------------------------------------
-- The last full scan
---------------------------------------------------------------------------
-- rows: one per item and unit price: { key, itemID, link, name, quality, icon, classID, unit, qty, auctions,
-- vendor, avg = { [3] =, [7] =, [14] = }, days }. Only rows that are a deal in some mode at some setting are kept.
local scan = { at = nil, rows = {}, busy = false, progress = 0, scanning = false, scanProgress = 0 }
Deals.scan = scan

function Deals.Fresh() return scan.at ~= nil and not scan.busy and time() - scan.at < FRESH_SECONDS end

local function auctionator() return _G.Auctionator end

local function fullScanFrame()
    local A = auctionator()
    return A and A.State and A.State.FullScanFrameRef
end

-- Seconds until Auctionator allows the next full scan (0 when it can start now), or nil without Auctionator.
function Deals.ScanWait()
    local A = auctionator()
    if not (A and A.SavedState) then return nil end
    local last = A.SavedState.TimeOfLastReplicateScan
    if not last then return 0 end
    return max(0, SCAN_COOLDOWN - (time() - last))
end

function Deals.CanScan()
    local f = fullScanFrame()
    if not (f and f.InitiateScan) then return false end
    if f.CanInitiate then
        local ok, can = pcall(f.CanInitiate, f)
        return ok and can and true or false
    end
    return (Deals.ScanWait() or 0) == 0
end

-- As Auctionator's own scan button does: Auctionator starts the full scan, or says in chat when the next one is
-- allowed. The click always reaches Auctionator, so it never looks like nothing happened.
function Deals.StartScan()
    local f = fullScanFrame()
    if f and f.InitiateScan then
        f:InitiateScan()
    else
        print("|cffd9a066Encore-Stonks|r Auctionator's full scan isn't ready: turn Auctionator on, then close and open the auction house.")
    end
end

-- The player's own listings are left out. On WoW Forever UnitName returns first name and surname apart.
local function myNames()
    local name, second = UnitName("player")
    local full = name
    if second and second ~= "" then
        local c = Constants and Constants.CharacterNameSeparatorConsts
        full = name .. (c and c.CHARACTERNAME_SURNAME_SEPARATOR or " ") .. second
    end
    return name, full
end

local GEAR = { [2] = true, [4] = true }

-- Stonks keys are Auctionator's database keys: the item ID, or "gr:<id>:<n>" for random-suffix gear.
local function keyFor(itemID, link, classID)
    if GEAR[classID] and link then
        local A = auctionator()
        local fn = A and A.Utilities and A.Utilities.DBKeyFromLink
        if fn then
            local got
            pcall(fn, link, function(keys) got = type(keys) == "table" and keys[1] or nil end)
            if got then return tostring(got) end
        end
    end
    return tostring(itemID)
end

local function averagesFor(key, today)
    local ok, st = pcall(Stonks.ItemStats, Stonks, key, nil, today)
    if not ok or not st then return nil end
    return { [3] = st.avg3, [7] = st.avg7, [14] = st.avg14 }, st.days or 0
end

-- Works through the scan a few milliseconds per frame: listings grouped by item and price, then the averages of
-- each item, then only the possible deals are kept.
local worker
local function process(data)
    if worker then worker:Cancel(); worker = nil end
    scan.busy, scan.progress = true, 0
    scan.rows = {}
    if Deals.Refresh then Deals.Refresh() end

    local first, full = myNames()
    local groups, list, keys, seenKey, missing = {}, {}, {}, {}, {}
    local n, i, k = #data, 1, 1
    local stats = {}
    local today = Stonks.DayNumber(time())

    local function addListing(e)
        local info = e and e.replicateInfo
        if type(info) ~= "table" then return end
        local count, buyout, itemID = info[3], info[10], info[17]
        if not (count and count > 0 and buyout and buyout > 0 and itemID) then return end
        local owner = info[14]
        if owner and (owner == first or owner == full) then return end
        local _, _, _, _, _, _, _, _, _, _, sell, classID = GetItemInfo(itemID)
        if sell == nil then missing[itemID] = true end
        local link = e.itemLink
        local key = keyFor(itemID, link, classID)
        local unit = buyout / count
        local gk = key .. "@" .. floor(unit * 100 + 0.5)
        local g = groups[gk]
        if g then
            g.qty, g.auctions = g.qty + count, g.auctions + 1
            return
        end
        g = {
            key = key, itemID = itemID, link = link, name = info[1], icon = info[2], quality = info[4],
            classID = classID, unit = unit, qty = count, auctions = 1, vendor = sell,
        }
        groups[gk] = g
        list[#list + 1] = g
        if not seenKey[key] then seenKey[key] = true; keys[#keys + 1] = key end
    end

    local function finish()
        if worker then worker:Cancel(); worker = nil end
        local rows = {}
        local lowest = 1 - PCT_MIN / 100
        for _, g in ipairs(list) do
            if g.vendor == nil and missing[g.itemID] then
                local _, _, _, _, _, _, _, _, _, _, sell, classID = GetItemInfo(g.itemID)
                g.vendor, g.classID = sell, g.classID or classID
            end
            local st = stats[g.key]
            if st then g.avg, g.days = st.avg, st.days end
            local vendorDeal = g.vendor and g.vendor > 0 and g.unit < g.vendor
            local marketDeal = false
            if g.avg then
                for _, a in pairs(g.avg) do
                    if a and a > 0 and g.unit <= a * lowest then marketDeal = true end
                end
            end
            if vendorDeal or marketDeal then
                g.name = g.name or (U.itemName(g.key))
                rows[#rows + 1] = g
            end
        end
        scan.rows, scan.listings = rows, n
        scan.at = time()
        scan.busy, scan.progress = false, 1
        if Deals.Refresh then Deals.Refresh() end
    end

    worker = C_Timer.NewTicker(0, safe(function()
        local t0 = debugprofilestop()
        while i <= n do
            addListing(data[i])
            i = i + 1
            if debugprofilestop() - t0 > BUDGET_MS then
                scan.progress = 0.5 * i / max(1, n)
                if Deals.Progress then Deals.Progress() end
                return
            end
        end
        if next(missing) and k == 1 then
            for id in pairs(missing) do
                if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
            end
        end
        while k <= #keys do
            local key = keys[k]
            k = k + 1
            local avg, days = averagesFor(key, today)
            if avg then stats[key] = { avg = avg, days = days } end
            if debugprofilestop() - t0 > BUDGET_MS then
                scan.progress = 0.5 + 0.5 * k / max(1, #keys)
                if Deals.Progress then Deals.Progress() end
                return
            end
        end
        finish()
    end))
end

---------------------------------------------------------------------------
-- Auctionator's full scan events
---------------------------------------------------------------------------
local listening
local function listen()
    if listening then return end
    local A = auctionator()
    local ev = A and A.FullScan and A.FullScan.Events
    if not (ev and A.EventBus and A.EventBus.Register and ev.ScanComplete) then return end
    local names = {}
    for _, e in ipairs({ ev.ScanStart, ev.ScanProgress, ev.ScanComplete, ev.ScanFailed }) do
        if e then names[#names + 1] = e end
    end
    local listener = {}
    listener.ReceiveEvent = safe(function(_, name, arg)
        if name == ev.ScanStart then
            scan.scanning, scan.scanProgress = true, 0
        elseif name == ev.ScanProgress then
            scan.scanning, scan.scanProgress = true, tonumber(arg) or scan.scanProgress
            if Deals.Progress then Deals.Progress() end
            return
        elseif name == ev.ScanFailed then
            scan.scanning = false
        elseif name == ev.ScanComplete then
            scan.scanning = false
            if type(arg) == "table" then process(arg) end
        end
        if Deals.Refresh then Deals.Refresh() end
    end)
    listening = pcall(A.EventBus.Register, A.EventBus, listener, names)
end

---------------------------------------------------------------------------
-- Rows in the current mode
---------------------------------------------------------------------------
local function under(row, avgDays)
    local a = row.avg and row.avg[avgDays]
    if not a or a <= 0 then return nil end
    return (a - row.unit) / a * 100
end
Deals.Under = under

-- The highest price per item the buy prompt may pay for this row's item in this mode.
function Deals.Limit(row, mode)
    local s = S()
    if mode == "vendor" then return row.vendor, true end -- strictly below
    local a = row.avg and row.avg[s.avg]
    if not a then return nil end
    return floor(a * (1 - s.pct / 100)), false -- at or below
end

function Deals.Matches(row, mode, search)
    local s = S()
    if search and search ~= "" and not (row.name or ""):lower():find(search, 1, true) then return false end
    if mode == "vendor" then
        if not (row.vendor and row.vendor > 0 and row.unit < row.vendor) then return false end
        if not s.greys and row.quality == 0 then return false end
        if not s.gear and GEAR[row.classID] then return false end
        return true
    end
    local u = under(row, s.avg)
    if not u or u < s.pct then return false end
    if s.minDays and (row.days or 0) < MIN_DAYS then return false end
    return true
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
local tab, results, overlay, heads, modeButtons, avgButtons = nil, nil, nil, {}, {}, {}
local ctrl, searchBoxes = {}, {}
local statusText, sumText, scanText, cdText, scanButton, buyAllButton, slider, pctText
local shownRows = {}

local COLS = {
    vendor = {
        { id = "qty", label = "Qty", width = 50, desc = true, tip = "How many are listed at this price." },
        { id = "unit", label = "Buyout each", width = 92, tip = "Buyout price per item." },
        { id = "vendor", label = "Vendor each", width = 92, desc = true, tip = "What a vendor pays for one." },
        { id = "profit", label = "Profit each", width = 88, desc = true, tip = "Vendor price minus buyout, per item." },
        { id = "total", label = "Total profit", width = 96, desc = true, tip = "Profit if you buy all listed at this price and sell them to a vendor." },
    },
    market = {
        { id = "qty", label = "Qty", width = 46, desc = true, tip = "How many are listed at this price." },
        { id = "unit", label = "Buyout each", width = 92, tip = "Buyout price per item." },
        { id = "avg", label = "Market", width = 92, desc = true, tip = "Stonks average over the chosen days, from the days before today. Launch week (4-11 Nov) is left out." },
        { id = "under", label = "Under", width = 56, desc = true, tip = "How far the buyout is below the market average." },
        { id = "save", label = "Saving each", width = 88, desc = true, tip = "Market average minus buyout, per item." },
        { id = "days", label = "Days", width = 40, desc = true, tip = "Days Stonks has prices for this item." },
    },
}
-- x offsets from the right edge, right-aligned columns
for _, cols in pairs(COLS) do
    local x = -6
    for i = #cols, 1, -1 do
        cols[i].point, cols[i].x = "RIGHT", x
        x = x - cols[i].width - 8
    end
    table.insert(cols, 1, { id = "name", label = "Item", point = "LEFT", x = 30, width = 200, tip = "Item name, coloured by quality." })
end

local function value(row, id)
    local s = S()
    if id == "name" then return row.name end
    if id == "qty" then return row.qty end
    if id == "unit" then return row.unit end
    if id == "vendor" then return row.vendor end
    if id == "profit" then return row.vendor and (row.vendor - row.unit) end
    if id == "total" then return row.vendor and (row.vendor - row.unit) * row.qty end
    if id == "avg" then return row.avg and row.avg[s.avg] end
    if id == "under" then return under(row, s.avg) end
    if id == "save" then local a = row.avg and row.avg[s.avg]; return a and (a - row.unit) end
    if id == "days" then return row.days end
end
Deals.Value = value

local function cellText(row, id)
    local s = S()
    if id == "qty" then return tostring(row.qty) end
    if id == "unit" then return coinShort(row.unit) end
    if id == "vendor" then return coinShort(row.vendor) end
    if id == "profit" then return "|cff7ad1cc" .. coinShort(row.vendor - row.unit) .. "|r" end
    if id == "total" then return "|cff7ad1cc" .. coinShort((row.vendor - row.unit) * row.qty) .. "|r" end
    if id == "avg" then return coinShort(row.avg and row.avg[s.avg]) end
    if id == "under" then local u = under(row, s.avg); return u and ("|cff7ad1cc-%d%%|r"):format(floor(u + 0.5)) or "-" end
    if id == "save" then local a = row.avg and row.avg[s.avg]; return a and coinShort(a - row.unit) or "-" end
    if id == "days" then
        local d = row.days or 0
        return d < MIN_DAYS and ("|cffeb9339" .. d .. "|r") or tostring(d)
    end
    return ""
end

local function rowTooltip(tt, self)
    local row = self.row
    if not row then return end
    if row.link then tt:SetHyperlink(row.link) else tt:SetText(row.name or "?") end
    local mode = S().mode
    tt:AddLine(" ")
    tt:AddDoubleLine(("%d listed (%d auction%s)"):format(row.qty, row.auctions, row.auctions == 1 and "" or "s"), coin(row.unit) .. " each", 1, 1, 1, 1, 1, 1)
    if mode == "vendor" then
        tt:AddDoubleLine("Profit each", coin(row.vendor - row.unit), TEAL_SOFT[1], TEAL_SOFT[2], TEAL_SOFT[3], 1, 1, 1)
        tt:AddDoubleLine("Profit for all " .. row.qty, coin((row.vendor - row.unit) * row.qty), TEAL_SOFT[1], TEAL_SOFT[2], TEAL_SOFT[3], 1, 1, 1)
        tt:AddLine("Click to buy the ones under vendor price.", DIM[1], DIM[2], DIM[3])
    else
        local s = S()
        local a = row.avg and row.avg[s.avg]
        tt:AddDoubleLine("Stonks " .. s.avg .. "-day average", coin(a), 1, 0.82, 0, 1, 1, 1)
        local u = under(row, s.avg)
        if u then tt:AddLine(("%d%% under the market average"):format(floor(u + 0.5)), TEAL_SOFT[1], TEAL_SOFT[2], TEAL_SOFT[3]) end
        tt:AddLine(("3-day %s   7-day %s   14-day %s"):format(coinShort(row.avg and row.avg[3]), coinShort(row.avg and row.avg[7]), coinShort(row.avg and row.avg[14])), DIM[1], DIM[2], DIM[3])
        local d = row.days or 0
        if d < MIN_DAYS then tt:AddLine(("Prices on %d day%s only"):format(d, d == 1 and "" or "s"), 0.92, 0.58, 0.22)
        else tt:AddLine(("Prices on %d days"):format(d), DIM[1], DIM[2], DIM[3]) end
        tt:AddLine(("Click to buy the ones %d%% or more under."):format(s.pct), DIM[1], DIM[2], DIM[3])
    end
    tt:AddLine("Shift-click to link it in chat.", DIM[1], DIM[2], DIM[3])
end

local function initRow(btn)
    if btn.built then return end
    btn.built = true
    btn:SetHeight(ROW_H)
    btn.stripe = btn:CreateTexture(nil, "BACKGROUND")
    btn.stripe:SetAllPoints()
    btn.stripe:SetColorTexture(1, 1, 1, 0.03)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.9, 0.6, 0.08)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(18, 18)
    btn.icon:SetPoint("LEFT", 6, 0)
    btn.name = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.name:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
    btn.name:SetJustifyH("LEFT")
    btn.name:SetWordWrap(false)
    btn.cells = {}
    for i = 1, 6 do
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("RIGHT")
        fs:SetWordWrap(false)
        btn.cells[i] = fs
    end
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", safe(function(self)
        local row = self.row
        if not row then return end
        if IsModifiedClick("CHATLINK") and row.link then
            if ChatEdit_InsertLink then ChatEdit_InsertLink(row.link) end
            return
        end
        if Stonks.ShowItem and (Stonks:Settings().dockAH ~= false or (Stonks.PanelShown and Stonks:PanelShown())) then
            Stonks:ShowItem(row.key, { follow = true })
        end
        if Deals.OpenBuy then Deals.OpenBuy({ row }, S().mode) end
    end))
    U.tooltip(btn, rowTooltip)
end

local function fillRow(btn, row)
    initRow(btn)
    btn.row = row
    local mode = S().mode
    local cols = COLS[mode]
    btn.stripe:SetShown(row.index % 2 == 0)
    btn.icon:SetTexture(row.icon or U.itemIcon(row.key))
    btn.name:SetText(row.name or "")
    local r, g, b = 1, 1, 1
    local q = row.quality
    if q and C_Item and C_Item.GetItemQualityColor then
        local qr, qg, qb = C_Item.GetItemQualityColor(q)
        if qr then r, g, b = qr, qg, qb end
    end
    btn.name:SetTextColor(r, g, b)
    btn.name:SetPoint("RIGHT", btn, "RIGHT", cols[2].x - cols[2].width - 8, 0)
    for i = 1, 6 do
        local c = cols[i + 1]
        local fs = btn.cells[i]
        if c then
            fs:ClearAllPoints()
            fs:SetPoint("RIGHT", btn, "RIGHT", c.x, 0)
            fs:SetWidth(c.width)
            fs:SetText(cellText(row, c.id))
            fs:Show()
        else
            fs:Hide()
        end
    end
end

local function hm(t) return date("%H:%M", t) end
local function ago(sec)
    local m = floor(sec / 60)
    if m < 1 then return "just now" end
    if m < 60 then return m .. " min ago" end
    return ("%d h %d min ago"):format(floor(m / 60), m % 60)
end
local function clock(sec) return ("%d:%02d"):format(floor(sec / 60), sec % 60) end

-- The big message over the empty list: no Auctionator, scanning, working out, or the scan is too old.
local function updateOverlay()
    if not overlay then return end
    local fresh = Deals.Fresh()
    overlay:SetShown(not fresh)
    if fresh then return end
    local big, sub, showButton = "Requires a fresh Auctionator scan", nil, true
    if not fullScanFrame() then
        big, sub, showButton = "Requires Auctionator", "The deals come from Auctionator's full scan of the auction house. Turn Auctionator on and open the auction house again.", false
    elseif scan.scanning then
        big, showButton = "Scanning the auction house", false
        sub = ("Auctionator is scanning: %d%%. The deals show when it finishes."):format(floor((scan.scanProgress or 0) * 100))
    elseif scan.busy then
        big, showButton = "Working out the deals", false
        sub = ("%d%% done."):format(floor((scan.progress or 0) * 100))
    elseif scan.at then
        sub = ("Last full scan %s, |cffeb9339%s|r. Deals only show from a full scan in the last %d minutes, because older listings are often bought already."):format(hm(scan.at), ago(time() - scan.at), FRESH_SECONDS / 60)
    else
        sub = ("No full scan since you logged in. Deals only show from a full scan in the last %d minutes."):format(FRESH_SECONDS / 60)
    end
    overlay.big:SetText(big)
    overlay.sub:SetText(sub)
    overlay.button:SetShown(showButton)
    if showButton then
        local wait = Deals.ScanWait() or 0
        overlay.button:Enable()
        overlay.button:SetText(wait > 0 and not Deals.CanScan() and ("Next full scan in " .. clock(wait)) or "Start full scan")
    end
end

local function updateScanLine()
    if not tab then return end
    if scan.at then
        local left = FRESH_SECONDS - (time() - scan.at)
        local txt = ("Full scan at %s (%s), %s listings."):format(hm(scan.at), ago(time() - scan.at), BreakUpLargeNumbers and BreakUpLargeNumbers(scan.listings or 0) or tostring(scan.listings or 0))
        if left > 0 and not scan.busy then txt = txt .. (" Shown for %d more min."):format(math.ceil(left / 60)) end
        scanText:SetText(txt)
    else
        scanText:SetText("No full scan since you logged in.")
    end
    local wait = Deals.ScanWait()
    if scan.scanning then
        cdText:SetText(("Scanning %d%%"):format(floor((scan.scanProgress or 0) * 100)))
        scanButton:Disable()
    elseif wait and wait > 0 then
        cdText:SetText("Next full scan in " .. clock(wait))
        scanButton:Enable() -- Auctionator says in chat when the next one is allowed
    else
        cdText:SetText(fullScanFrame() and "Full scan ready" or "")
        scanButton:SetEnabled(fullScanFrame() ~= nil)
    end
end

function Deals.Progress()
    if tab and tab:IsShown() then updateOverlay(); updateScanLine() end
end

local function render()
    if not tab or not tab:IsShown() then return end
    local s = S()
    local mode = s.mode
    for m, b in pairs(modeButtons) do b:SetOn(m == mode) end
    for m, f in pairs(ctrl) do f:SetShown(m == mode) end
    for m, h in pairs(heads) do h:SetShown(m == mode) end
    for d, b in pairs(avgButtons) do b:SetOn(d == s.avg) end
    pctText:SetText(s.pct .. "%")
    heads.market.refresh()
    heads.vendor.refresh()
    -- the Market column names the chosen average
    for _, b in ipairs(heads.market.buttons) do
        if b.col.id == "avg" then b.label:SetText(s.avg .. "-day avg") end
    end

    local fresh = Deals.Fresh()
    local counts = { vendor = 0, market = 0 }
    wipe(shownRows)
    if fresh then
        local search = {}
        for m, box in pairs(searchBoxes) do search[m] = (box:GetText() or ""):lower() end
        for _, row in ipairs(scan.rows) do
            for m in pairs(counts) do
                if Deals.Matches(row, m, search[m]) then
                    counts[m] = counts[m] + 1
                    if m == mode then shownRows[#shownRows + 1] = row end
                end
            end
        end
        U.SortRows(shownRows, s["sort" .. mode], value)
        for i, row in ipairs(shownRows) do row.index = i end
    end
    modeButtons.vendor.text:SetText(("Under vendor price  |cffffe7b0%s|r"):format(fresh and counts.vendor or "-"))
    modeButtons.market.text:SetText(("Under market price  |cffffe7b0%s|r"):format(fresh and counts.market or "-"))
    results:SetDataProvider(CreateDataProvider(shownRows), ScrollBoxConstants.RetainScrollPosition)

    tab.empty:SetShown(fresh and #shownRows == 0)
    if mode == "vendor" then
        tab.empty:SetText("No listings below vendor price in the last full scan.")
        local cost, profit = 0, 0
        for _, r in ipairs(shownRows) do cost = cost + r.unit * r.qty; profit = profit + (r.vendor - r.unit) * r.qty end
        sumText:SetText(#shownRows > 0 and ("Buy all: %s   Profit: |cff7ad1cc%s|r"):format(coin(cost), coin(profit)) or "")
    else
        tab.empty:SetText(("Nothing listed %d%% or more under the %d-day average. Move the slider left to see more."):format(s.pct, s.avg))
        sumText:SetText(#shownRows > 0 and ("%d listings %d%%+ under the %d-day average"):format(#shownRows, s.pct, s.avg) or "")
    end
    buyAllButton:SetEnabled(fresh and mode == "vendor" and #shownRows > 0)
    updateOverlay()
    updateScanLine()
end
Deals.Refresh = safe(render)

local function checkbox(parent, label, get, set, tip)
    local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    b:SetSize(22, 22)
    local text = b.text or b.Text
    if type(text) ~= "table" then
        text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", b, "RIGHT", 1, 0)
    end
    text:SetFontObject("GameFontHighlightSmall")
    text:SetText(label)
    b.label = text
    b:SetChecked(get())
    b:SetScript("OnClick", safe(function(self) set(self:GetChecked() and true or false); render() end))
    if tip then U.tooltip(b, function(tt) tt:SetText(label); tt:AddLine(tip, 1, 1, 1, true) end) end
    b.width = 26 + (text:GetStringWidth() or 60)
    return b
end

local function searchBox(parent, mode)
    local box = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
    box:SetSize(150, 20)
    box:SetAutoFocus(false)
    if box.Instructions then box.Instructions:SetText("Filter by name") end
    box:HookScript("OnTextChanged", safe(function() render() end))
    searchBoxes[mode] = box
    return box
end

local function buildSlider(parent)
    local sl = CreateFrame("Slider", nil, parent)
    sl:SetOrientation("HORIZONTAL")
    sl:SetSize(140, 16)
    sl:SetMinMaxValues(PCT_MIN, PCT_MAX)
    sl:SetValueStep(PCT_STEP)
    if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
    sl:EnableMouseWheel(true)
    local track = sl:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(6)
    track:SetColorTexture(0.04, 0.035, 0.03, 1)
    local edge = CreateFrame("Frame", nil, sl)
    edge:SetPoint("TOPLEFT", track, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 1, -1)
    U.addBorder(edge, U.COPPER[1], U.COPPER[2], U.COPPER[3], 0.6)
    local fill = sl:CreateTexture(nil, "ARTWORK")
    fill:SetHeight(4)
    fill:SetColorTexture(U.TEAL[1], U.TEAL[2], U.TEAL[3], 0.9)
    sl:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = sl:GetThumbTexture()
    if thumb then thumb:SetSize(28, 28) end
    -- The fill runs from the track's start to the thumb's centre, so it always meets the thumb (the thumb travels
    -- inside the track, not across its full width).
    fill:SetPoint("LEFT", track, "LEFT")
    if thumb then fill:SetPoint("RIGHT", thumb, "CENTER") end
    local function update(v)
        if thumb then return end
        fill:SetWidth(max(1, (v - PCT_MIN) / (PCT_MAX - PCT_MIN) * (sl:GetWidth() or 140)))
    end
    sl:SetScript("OnValueChanged", safe(function(self, v, byUser)
        v = floor(v / PCT_STEP + 0.5) * PCT_STEP
        update(v)
        local s = S()
        if s.pct ~= v then s.pct = v; render() end
    end))
    sl:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(max(PCT_MIN, min(PCT_MAX, (self:GetValue() or 30) + delta * PCT_STEP)))
    end)
    sl:SetValue(S().pct)
    update(S().pct)
    U.tooltip(sl, function(tt)
        tt:SetText("Under market by at least")
        tt:AddLine(("Shows listings at least this far below the Stonks average. %d%% to %d%%; the mouse wheel moves it too."):format(PCT_MIN, PCT_MAX), 1, 1, 1, true)
    end)
    return sl
end

local function buildHead(parent, mode)
    local head = CreateFrame("Frame", nil, parent)
    head:SetPoint("TOPLEFT", 3, -3)
    head:SetPoint("TOPRIGHT", -17, -3)
    head:SetHeight(20)
    local bg = head:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    U.gradient(bg, "VERTICAL", 0.09, 0.06, 0.04, 1, 0.17, 0.13, 0.09, 1)
    local refresh, buttons = U.SortHeader(head, COLS[mode], S()["sort" .. mode], function() render() end)
    head.refresh, head.buttons = refresh, buttons
    -- SortHeader keeps the table it was given; settings can be replaced (an import), so point it at the saved one
    return head
end

local function build()
    local ah = _G.AuctionHouseFrame
    tab = CreateFrame("Frame", "EncoreStonksDealsFrame", ah)
    tab:SetPoint("TOPLEFT", ah, "TOPLEFT", 8, -26)
    tab:SetPoint("BOTTOMRIGHT", ah, "BOTTOMRIGHT", -6, 28)
    tab:Hide()

    U.gem(tab, "TOPLEFT", 66, -16)
    local title = tab:CreateFontString(nil, "OVERLAY")
    local UI = _G.EncoreEssentials and _G.EncoreEssentials.UI
    if UI and UI.TitleFont then UI.TitleFont(title, 17) else title:SetFontObject("GameFontNormalLarge") end
    title:SetPoint("TOPLEFT", 82, -4)
    title:SetText("Stonks Deals")
    scanText = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scanText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    U.setColor(scanText, DIM)

    scanButton = _G.EncoreEssentials.UI.Button(tab)
    scanButton:SetSize(100, 22)
    scanButton:SetPoint("TOPRIGHT", -4, -6)
    scanButton:SetText("Full scan")
    scanButton:SetScript("OnClick", safe(function() Deals.StartScan(); render() end))
    U.tooltip(scanButton, function(tt)
        tt:SetText("Full scan")
        tt:AddLine("Starts Auctionator's full scan of every listing. The auction house allows one every 15 minutes.", 1, 1, 1, true)
    end)
    cdText = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cdText:SetPoint("RIGHT", scanButton, "LEFT", -8, 0)
    U.setColor(cdText, DIM)

    -- Mode tabs
    local labels = { vendor = "Under vendor price", market = "Under market price" }
    local x = 4
    for _, m in ipairs({ "vendor", "market" }) do
        local b = U.ToggleButton(tab, labels[m], 178)
        b:SetHeight(24)
        b:SetPoint("TOPLEFT", x, -44)
        x = x + 182
        b:SetScript("OnClick", safe(function()
            S().mode = m
            if Deals.CloseBuy then Deals.CloseBuy() end
            render()
        end))
        modeButtons[m] = b
    end
    local rule = tab:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(U.COPPER[1], U.COPPER[2], U.COPPER[3], 0.5)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 4, -68)
    rule:SetPoint("TOPRIGHT", -4, -68)

    -- Controls: one row per mode
    for _, m in ipairs({ "vendor", "market" }) do
        local f = CreateFrame("Frame", nil, tab)
        f:SetPoint("TOPLEFT", 6, -72)
        f:SetPoint("TOPRIGHT", -6, -72)
        f:SetHeight(26)
        ctrl[m] = f
        local box = searchBox(f, m)
        box:SetPoint("LEFT", 6, 0)
    end
    do
        local f = ctrl.vendor
        local greys = checkbox(f, "Grey items", function() return S().greys end, function(v) S().greys = v end)
        greys:SetPoint("LEFT", searchBoxes.vendor, "RIGHT", 14, 0)
        local gear = checkbox(f, "Weapons and armour", function() return S().gear end, function(v) S().gear = v end)
        gear:SetPoint("LEFT", greys, "LEFT", greys.width + 12, 0)
        buyAllButton = _G.EncoreEssentials.UI.Button(f)
        buyAllButton:SetSize(190, 22)
        buyAllButton:SetPoint("RIGHT", 0, 0)
        buyAllButton:SetText("Buy all under vendor price")
        buyAllButton:SetScript("OnClick", safe(function()
            if Deals.Fresh() and #shownRows > 0 and Deals.OpenBuy then Deals.OpenBuy(shownRows, "vendor") end
        end))
        U.tooltip(buyAllButton, function(tt)
            tt:SetText("Buy all under vendor price")
            tt:AddLine("Searches every item in this list again and lets you buy each listing that is still below its vendor price, one per click.", 1, 1, 1, true)
        end)
    end
    do
        local f = ctrl.market
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", searchBoxes.market, "RIGHT", 14, 0)
        lbl:SetText("At least")
        U.setColor(lbl, DIM)
        slider = buildSlider(f)
        slider:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
        pctText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        pctText:SetPoint("LEFT", slider, "RIGHT", 10, 0)
        pctText:SetWidth(34)
        pctText:SetJustifyH("LEFT")
        local lbl2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl2:SetPoint("LEFT", pctText, "RIGHT", 2, 0)
        lbl2:SetText("under")
        U.setColor(lbl2, DIM)
        local prev = lbl2
        for _, d in ipairs({ 3, 7, 14 }) do
            local b = U.ToggleButton(f, d .. " days", 52)
            b:SetPoint("LEFT", prev, "RIGHT", prev == lbl2 and 12 or 3, 0)
            b:SetScript("OnClick", safe(function() S().avg = d; render() end))
            U.tooltip(b, function(tt)
                tt:SetText(d .. "-day average")
                tt:AddLine("Compare with the Stonks " .. d .. "-day moving average, like the graph panel's buttons.", 1, 1, 1, true)
            end)
            avgButtons[d] = b
            prev = b
        end
        local days = checkbox(f, MIN_DAYS .. "+ days of prices", function() return S().minDays end, function(v) S().minDays = v end,
            "Hides items Stonks has seen on fewer than " .. MIN_DAYS .. " days: a thin average can make anything look cheap.")
        days:SetPoint("LEFT", prev, "RIGHT", 10, 0)
    end

    -- The list
    local well = U.well(tab)
    well:SetPoint("TOPLEFT", 4, -102)
    well:SetPoint("BOTTOMRIGHT", -4, 22)
    heads.vendor = buildHead(well, "vendor")
    heads.market = buildHead(well, "market")
    local box = CreateFrame("Frame", nil, well, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", 3, -25)
    box:SetPoint("BOTTOMRIGHT", -17, 3)
    local bar = CreateFrame("EventFrame", nil, well, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, -2)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 2)
    bar:SetHideIfUnscrollable(true)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("EncoreStonksDealRowTemplate", fillRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    results = box

    tab.empty = well:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    tab.empty:SetPoint("CENTER", 0, -10)
    tab.empty:SetWidth(460)

    -- The big message over the list when the scan is not fresh
    overlay = CreateFrame("Frame", nil, well)
    overlay:SetPoint("TOPLEFT", 3, -25)
    overlay:SetPoint("BOTTOMRIGHT", -3, 3)
    overlay:SetFrameLevel(box:GetFrameLevel() + 20)
    overlay:EnableMouse(true)
    local shade = overlay:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0.03, 0.02, 0.01, 0.55)
    U.gem(overlay, "CENTER", 0, 64)
    overlay.big = overlay:CreateFontString(nil, "OVERLAY")
    if UI and UI.TitleFont then UI.TitleFont(overlay.big, 26) else overlay.big:SetFontObject("GameFontNormalHuge") end
    overlay.big:SetPoint("CENTER", 0, 30)
    overlay.big:SetShadowOffset(2, -2)
    overlay.sub = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    overlay.sub:SetPoint("TOP", overlay.big, "BOTTOM", 0, -12)
    overlay.sub:SetWidth(440)
    overlay.sub:SetSpacing(2)
    overlay.button = _G.EncoreEssentials.UI.Button(overlay)
    overlay.button:SetSize(190, 26)
    overlay.button:SetPoint("TOP", overlay.sub, "BOTTOM", 0, -14)
    overlay.button:SetScript("OnClick", safe(function() Deals.StartScan(); render() end))

    statusText = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", 8, 5)
    statusText:SetText("Prices from your Auctionator scans. Averages leave out today and launch week (4-11 Nov).")
    U.setColor(statusText, DIM)
    sumText = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sumText:SetPoint("BOTTOMRIGHT", -8, 5)
    U.setColor(sumText, INK)

    local ticker
    tab:SetScript("OnShow", safe(function()
        render()
        if ticker then ticker:Cancel() end
        local wasFresh = Deals.Fresh()
        ticker = C_Timer.NewTicker(1, safe(function()
            local fresh = Deals.Fresh()
            if fresh ~= wasFresh then
                wasFresh = fresh
                if not fresh and Deals.CloseBuy then Deals.CloseBuy() end
                render()
            else
                updateScanLine()
                updateOverlay()
            end
        end))
    end))
    tab:SetScript("OnHide", function()
        if ticker then ticker:Cancel(); ticker = nil end
    end)
    Deals.tab = tab
end

-- Adds the tab once per session, after Auctionator's tabs.
local added
local function addTab()
    if added or not Deals.Enabled() then return end
    local ah = _G.AuctionHouseFrame
    local lib = LibStub and LibStub("LibAHTab-1-0", true)
    if not (ah and lib and lib.CreateTab) then return end
    if lib.DoesIDExist and lib:DoesIDExist(TAB_ID) then added = true; return end
    listen()
    build()
    lib:CreateTab(TAB_ID, tab, "Stonks", "Stonks Deals")
    added = true
    local button = lib.GetButton and lib:GetButton(TAB_ID)
    if button then
        U.tooltip(button, function(tt)
            tt:SetText("Stonks Deals")
            tt:AddLine("Listings under vendor price or under the Stonks market average, from your last Auctionator full scan.", 1, 1, 1, true)
        end)
    end
end

-- Turning the option off hides the tab button; turning it on adds it the next time the auction house opens.
function Deals.SetEnabled(on)
    Stonks:Settings().dealsTab = on and true or false
    local lib = LibStub and LibStub("LibAHTab-1-0", true)
    local button = added and lib and lib.GetButton and lib:GetButton(TAB_ID)
    if button then
        button:SetShown(on)
        if not on and tab and tab:IsShown() then tab:Hide() end
    end
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "ADDON_LOADED", "PLAYER_LOGIN" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", safe(function(_, event, arg1)
    if event == "AUCTION_HOUSE_SHOW" then
        listen()
        -- Auctionator adds its tabs when the auction house opens; ours goes after them
        C_Timer.After(0.2, safe(addTab))
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if Deals.CloseBuy then Deals.CloseBuy() end
    elseif (event == "ADDON_LOADED" and arg1 == "Auctionator") or event == "PLAYER_LOGIN" then
        listen()
    end
end))
