-- Encore-Professions: the skill-up chance and the profit or loss of one craft, at the right of each recipe in the
-- profession window's own list ("77% · -7c"), in the recipe's colour. The chance is the guide's own (with Working
-- Overtime as the guide plans it); the profit is what the item is worth (auction price, else what a vendor pays)
-- less its reagents. Idea from What's Training? (Fusionpit, MIT) and SkillUp Forever (cjber, GPL-3.0-or-later).
-- The text is kept in a table of our own, never written into the client's row, so the row's click stays the client's.
local _, ns = ...
local P = ns.P
local Encore = _G.EncoreEssentials

local COLOUR = { o = { 1, 0.5, 0.25 }, y = { 1, 1, 0 }, g = { 0.25, 0.75, 0.25 }, x = { 0.5, 0.5, 0.5 } }
-- The client's own colour for recipes Encore has no skill ranges for (Enum.TradeskillRelativeDifficulty).
local DIFFICULTY = { [0] = "o", [1] = "y", [2] = "g", [3] = "x" }

local texts = setmetatable({}, { __mode = "k" })
local bySpell = {}
local list

local function recipeFor(prof, spell)
    local map = bySpell[prof]
    if not map then
        map = {}
        for _, r in ipairs(ns.Recipes[prof] or {}) do map[r[1]] = r end
        bySpell[prof] = map
    end
    return map[spell]
end

function P:RowTextOn()
    return self:DB().rowText ~= false
end

-- SkillUp Forever writes its own text in the same place; leave the rows to it while it is loaded.
local function otherAddon()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("SkillUpForever")
end

-- Reagents and product from the client, for recipes outside Encore's list (drops, quests, reputation).
local function fromClient(recipeID)
    local s = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic and C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    if type(s) ~= "table" then return nil end
    local reagents = {}
    for _, slot in ipairs(s.reagentSlotSchematics or {}) do
        local first = slot.reagents and slot.reagents[1]
        if first and first.itemID then
            reagents[#reagents + 1] = first.itemID
            reagents[#reagents + 1] = slot.quantityRequired or 1
        end
    end
    return { recipeID, nil, nil, nil, nil, nil, s.outputItemID, s.quantityMin or 1, reagents }
end
P.RecipeFor = recipeFor
P.RecipeFromClient = fromClient

-- chance (0..1 or nil), colour key, profit (copper or nil) for one recipe at this skill.
function P.RowValues(prof, recipeInfo, skill, bonus, cache)
    local r = recipeFor(prof, recipeInfo.recipeID)
    local chance, colour
    if r then
        chance, colour = P.Chance(r, skill, bonus), P.Colour(r, skill)
    else
        colour = DIFFICULTY[recipeInfo.relativeDifficulty]
        if colour == "o" then chance = 1 elseif colour == "x" then chance = 0 end
        r = fromClient(recipeInfo.recipeID)
    end
    local profit
    if r then
        local cost, unknown = P.ReagentCost(prof, r, cache)
        if not unknown then
            local worth = 0
            if r[7] then
                local each = P.Worth(r[7])
                if each then worth = each * (r[8] or 1) else cost = nil end
            end
            if cost then profit = worth - cost end
        end
    end
    return chance, colour or "x", profit
end

function P.RowText(chance, profit)
    local parts = {}
    if chance then parts[#parts + 1] = math.floor(chance * 100 + 0.5) .. "%" end
    if profit then
        local coins = Encore.UI.Coins(profit, true)
        parts[#parts + 1] = profit > 0 and ("+" .. coins) or coins
    end
    return table.concat(parts, " · ")
end

local function context()
    local o = P:Open()
    if not o or not ns.Recipes[o.name] then return nil end
    return { prof = o.name, skill = o.base, bonus = P:Bonus(), cache = {} }
end

local function decorate(row, elementData, ctx)
    local text = texts[row]
    local data = elementData and elementData.GetData and elementData:GetData()
    local info = data and data.recipeInfo
    if not (info and ctx and P:RowTextOn() and not otherAddon()) then
        if text then text:Hide() end
        return
    end
    if Professions and Professions.GetHighestLearnedRecipe then info = Professions.GetHighestLearnedRecipe(info) or info end
    if not text then
        text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetJustifyH("RIGHT")
        text:SetWordWrap(false)
        texts[row] = text
    end
    local chance, colour, profit = P.RowValues(ctx.prof, info, ctx.skill, ctx.bonus, ctx.cache)
    local s = P.RowText(chance, profit)
    if s == "" then text:Hide() return end
    text:ClearAllPoints()
    if row.LockedIcon and row.LockedIcon:IsShown() then
        text:SetPoint("RIGHT", row.LockedIcon, "LEFT", -2, 0)
    else
        text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    end
    text:SetText(s)
    local c = COLOUR[colour] or COLOUR.x
    text:SetTextColor(c[1], c[2], c[3])
    text:Show()
    -- Shorten the recipe name so a long one stops before our text instead of running under it.
    local label = row.Label
    if label and row.GetWidth then
        local used = text:GetStringWidth() + 10
        if row.Count and row.Count:IsShown() then used = used + row.Count:GetStringWidth() end
        if row.SkillUps and row.SkillUps:IsShown() then used = used + row.SkillUps:GetWidth() end
        local room = row:GetWidth() - used - 8
        if label:GetWidth() > room then label:SetWidth(math.max(room, 40)) end
    end
end

-- Redraws the rows on screen (after a skill-up, a price change or a setting).
function P.RefreshRecipeRows()
    if not (list and list.ScrollBox and list.ScrollBox.ForEachFrame and list:IsVisible()) then return end
    local ctx = context()
    list.ScrollBox:ForEachFrame(function(row, elementData) decorate(row, elementData, ctx) end)
end

function P.AttachRecipeList()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    list = page and page.RecipeList
    if not (list and list.ScrollBox and ScrollUtil and ScrollUtil.AddInitializedFrameCallback) then return end
    ScrollUtil.AddInitializedFrameCallback(list.ScrollBox, function(_, row, elementData)
        local ok, err = pcall(decorate, row, elementData, context())
        if not ok then geterrorhandler()(err) end
    end, P)
end
