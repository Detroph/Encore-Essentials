-- Encore-Stonks: its page in the game's Options > AddOns > Encore Essentials (built by EncoreEssentials Options.lua).
-- Same saved settings as the cogwheel menus in the graph and browser windows, and as /stonksync.
local _, ns = ...
local Encore = _G.EncoreEssentials
local Stonks = ns.Stonks
if not (Encore and Encore.AddOptionsPage) then return end

local function s() return Stonks:Settings() end
local function sync() return Stonks.Sync and Stonks.Sync.Settings and Stonks.Sync.Settings() or {} end

-- Prices are worked out again with the new rule, and open windows and tooltips redraw.
local function refresh()
    if Stonks.InvalidateMarket then Stonks:InvalidateMarket() end
    if Stonks.OnData then Stonks:OnData() end
end

local keepOptions = {}
for _, d in ipairs(Stonks.KEEP_DAYS_OPTIONS) do keepOptions[#keepOptions + 1] = { d, d .. " days" } end

Stonks.optionsCategory = Encore:AddOptionsPage("Encore-Stonks", {
    { kind = "header", text = "Prices" },
    { kind = "dropdown", key = "StonksKeepDays", name = "Keep hourly detail for", default = 7, options = keepOptions,
        tooltip = "How many days of hourly prices are kept. Older prices are folded into the weekday and hour charts, so those keep learning. Longer means more saved data.",
        get = function() return Stonks:KeepDays() end,
        set = function(v) Stonks:SetKeepDays(v); refresh() end },
    { kind = "checkbox", key = "StonksAuctionator", name = "Also use Auctionator's daily history", default = true,
        tooltip = "Fill in days before Encore-Stonks was installed with Auctionator's one price per day (up to 21 days).",
        get = function() return s().useAuctionator == true end,
        set = function(v) s().useAuctionator = v; refresh() end },
    { kind = "header", text = "Auction house" },
    { kind = "checkbox", key = "StonksDockAH", name = "Open the graph beside the auction house", default = true,
        tooltip = "Show the Encore-Stonks graph next to the auction house window when it opens.",
        get = function() return s().dockAH ~= false end,
        set = function(v) s().dockAH = v end },
    { kind = "checkbox", key = "StonksTooltip", name = "Show averages in item tooltips", default = true,
        tooltip = "Add the moving averages and trend to item tooltips.",
        get = function() return s().tooltip ~= false end,
        set = function(v) s().tooltip = v end },
    { kind = "checkbox", key = "StonksAuctionatorTime", name = "Show scan time on Auctionator's price", default = true,
        tooltip = "Add the date and time of the scan to Auctionator's Auction line in item tooltips, e.g. (22 Nov 14:05). Only the date when the price is from before Encore-Stonks saw it.",
        get = function() return s().auctionatorTime ~= false end,
        set = function(v) s().auctionatorTime = v end },
    { kind = "header", text = "Guild sharing" },
    { kind = "dropdown", key = "StonksSyncMode", name = "Guild sharing", default = "share", varType = "string",
        options = { { "share", "Share and receive" }, { "receive", "Receive only" }, { "off", "Off" } },
        tooltip = "Share: your scans go to the guild and you answer login requests. Receive only: you get guild scans and your login summary. Off: nothing is sent or received automatically (chat links still work). Only item, price, quantity and hour are ever sent.",
        get = function() return sync().mode or "share" end,
        set = function(v)
            local old = sync().mode
            sync().mode = v
            if v ~= "off" and old == "off" and Stonks.Sync.StartAsk then Stonks.Sync.StartAsk() end
        end },
    { kind = "checkbox", key = "StonksLowEnd", name = "Low-end mode", default = false,
        tooltip = "Don't receive the hourly guild scans. You still get your login summary. For slow computers.",
        get = function() return sync().lowEnd == true end,
        set = function(v) sync().lowEnd = v or nil end },
    { kind = "button", text = "Guild sync history", tooltip = "Every guild sync you received: when, from whom and how many prices.",
        onClick = function()
            HideUIPanel(SettingsPanel)
            Stonks:ShowPage("history")
        end },
    { kind = "header", text = "Windows" },
    { kind = "button", text = "Open Encore-Stonks", onClick = function()
        HideUIPanel(SettingsPanel)
        Stonks:Toggle()
    end },
})
