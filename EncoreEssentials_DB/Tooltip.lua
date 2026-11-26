-- Encore-DB: item tooltips say where the item drops or who sells it (up to three places).
-- Works once Encore-DB is loaded: after the window was opened, or at login with "Load at login" on.
local _, ns = ...
local Encore = _G.EncoreEssentials
local D = ns.LootData
local MAX = 3

local function on()
    local s = Encore.db and Encore.db.settings and Encore.db.settings.dbWindow
    return not (type(s) == "table" and s.tooltipSources == false)
end

local function addLines(tooltip, id)
    if not (id and on()) or tooltip.encoreDBID == id then return end
    local list = D.Where(id)
    if not list or #list == 0 then return end
    tooltip.encoreDBID = id
    for i = 1, math.min(MAX, #list) do
        local s = list[i]
        local chance = s.chance and (s.chance >= 10 and ("%d%%"):format(s.chance + 0.5) or ("%.1f%%"):format(s.chance)) or ""
        tooltip:AddDoubleLine((i == 1 and "|cffeb9339Encore-DB|r " or "   ") .. s.text, chance, 0.85, 0.75, 0.6, 1, 1, 1)
    end
    if #list > MAX then tooltip:AddLine(("   and %d more"):format(#list - MAX), 0.64, 0.57, 0.47) end
    if tooltip:IsShown() then tooltip:Show() end
end

local function clearMark(tooltip) tooltip.encoreDBID = nil end

local function idOf(tooltip, data)
    local id = data and data.id
    if not id and tooltip.GetItem then
        local _, link = tooltip:GetItem()
        id = link and tonumber(link:match("item:(%d+)"))
    end
    return id
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        local ok, err = pcall(addLines, tooltip, idOf(tooltip, data))
        if not ok then geterrorhandler()(err) end
    end)
else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt and tt.HookScript then
            tt:HookScript("OnTooltipSetItem", function(self)
                local ok, err = pcall(addLines, self, idOf(self))
                if not ok then geterrorhandler()(err) end
            end)
        end
    end
end
for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tt and tt.HookScript then tt:HookScript("OnTooltipCleared", clearMark); tt:HookScript("OnHide", clearMark) end
end
