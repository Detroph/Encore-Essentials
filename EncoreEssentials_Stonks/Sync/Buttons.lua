-- Encore-Stonks guild sharing: "Share item" and "Share scan" buttons along the bottom of the graph panel.
-- Each puts a chat link in the chat box (guild chat), the same as /stonksync link item or link scan.
-- The panel is built the first time it opens, so the buttons are added then.
local _, ns = ...
local Stonks = ns.Stonks
local U = ns.UI
local Sync = Stonks.Sync

local added = false

local function selectedID()
    local key = Stonks.PanelKey and Stonks:PanelKey()
    local id = tonumber(key)
    if id and math.floor(id) == id then return id end
    return nil
end

local function update(itemButton)
    local on = selectedID() ~= nil
    if on then itemButton:Enable() else itemButton:Disable() end
    itemButton:SetAlpha(on and 1 or 0.45)
end

local function addButtons()
    if added then return end
    local panel = _G.EncoreStonksPanel
    if not panel then return end
    added = true

    local scanButton = U.ToggleButton(panel, "Share scan", 84)
    scanButton:SetPoint("BOTTOMRIGHT", -26, 4) -- clear of the resize grip
    scanButton:SetScript("OnClick", function() Sync.Links.PostScan() end)
    U.tooltip(scanButton, function(tt)
        tt:SetText("Share your latest scan")
        tt:AddLine("Puts a link to your latest auction house scan in guild chat. Press Enter to send it. Guildmates with Encore-Stonks click it and confirm to import your prices.", 1, 1, 1, true)
    end)

    local itemButton = U.ToggleButton(panel, "Share item", 84)
    itemButton:SetPoint("RIGHT", scanButton, "LEFT", -4, 0)
    itemButton:SetScript("OnClick", function()
        local id = selectedID()
        if id then Sync.Links.PostItem("item:" .. id) end
    end)
    U.tooltip(itemButton, function(tt)
        tt:SetText("Share this item's prices")
        tt:AddLine("Puts a link to the selected item's price history in guild chat. Press Enter to send it. Guildmates with Encore-Stonks click it and confirm to import it.", 1, 1, 1, true)
    end)
    itemButton:HookScript("OnShow", function(self) update(self) end)
    update(itemButton)
    -- Follow the panel's selection.
    hooksecurefunc(Stonks, "ShowItem", function() update(itemButton) end)
    hooksecurefunc(Stonks, "ShowList", function() update(itemButton) end)
    hooksecurefunc(Stonks, "ShowMarket", function() update(itemButton) end)
end

if Stonks.ShowPanel then hooksecurefunc(Stonks, "ShowPanel", addButtons) end
if Stonks.ShowItem then hooksecurefunc(Stonks, "ShowItem", addButtons) end
