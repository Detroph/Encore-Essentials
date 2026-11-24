-- Encore-QoL: Professions tab, trainers.
local _, ns = ...
local Q = ns.QoL
local W = Q.W

local function available()
    local list, cost = {}, 0
    for i = 1, GetNumTrainerServices and GetNumTrainerServices() or 0 do
        local _, _, kind = GetTrainerServiceInfo(i)
        if kind == "available" then
            list[#list + 1] = i
            cost = cost + (GetTrainerServiceCost(i) or 0)
        end
    end
    return list, cost
end

Q:Feature{
    id = "trainAll", tab = "professions", section = "Trainers", name = "Train all",
    desc = "A Train all button on trainers, with the total cost in gold, silver and copper.",
    idea = "Leatrix Plus",
    detect = { { eqol = "showTrainAllButton" }, { leatrix = "ShowTrainAllButton" } },
    Enable = function(f)
        local function update()
            local frame = _G.ClassTrainerFrame
            if not frame then return end
            if not f.button then
                f.button = W.Button(frame, "Train all", function()
                    local list, cost = available()
                    if cost > GetMoney() then Q:Print("Not enough money: training everything costs %s.", Q.Coins(cost)) return end
                    for n = #list, 1, -1 do BuyTrainerService(list[n]) end
                    Q:Print("Trained %d for %s.", #list, Q.Coins(cost))
                end, 110)
                local anchor = _G.ClassTrainerTrainButton or frame.TrainButton
                if anchor then f.button:SetPoint("RIGHT", anchor, "LEFT", -4, 0) else f.button:SetPoint("BOTTOMLEFT", 10, 6) end
                W.Tooltip(f.button, "Train all", function()
                    local list, cost = available()
                    return #list .. " to learn, " .. Q.Coins(cost)
                end)
            end
            local list = available()
            f.button:SetShown(f.active)
            f.button:SetEnabled(#list > 0)
        end
        f:On("TRAINER_SHOW", function() C_Timer.After(0, update) end)
        f:On("TRAINER_UPDATE", update)
    end,
    Disable = function(f) if f.button then f.button:Hide() end end,
}
