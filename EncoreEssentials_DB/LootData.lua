-- Encore-DB: one place to ask the loot data questions other files need, without reaching into Window.lua.
-- ns.LootData.Where(itemID)  -> list of { text, chance, tab, inst, boss / vendor / world }, every place it comes from
-- ns.LootData.Price(itemID)  -> 7-day auction average in copper from Encore-Stonks, or nil
local _, ns = ...
local Encore = _G.EncoreEssentials
local Loot = ns.Loot
local D = {}
ns.LootData = D

local function entryOf(e)
    if type(e) == "table" then return e[1], e[2] end
    return e, nil
end

local where -- [itemID] = list, built on first use and again when the dungeon list changes (wings)
local builtFor

local function add(id, s)
    if not id then return end
    local list = where[id]
    if not list then list = {}; where[id] = list end
    list[#list + 1] = s
end

local function build()
    where, builtFor = {}, Loot.instances
    for i, inst in ipairs(Loot.instances or {}) do
        for b, boss in ipairs(inst.bosses or {}) do
            for _, e in ipairs(boss.items or {}) do
                local id, chance = entryOf(e)
                add(id, { text = boss.trash and inst.name or (boss.name .. ", " .. inst.name), chance = chance,
                    tab = "dungeons", inst = i, boss = b })
            end
        end
        for _, id in ipairs(inst.recipes or {}) do
            add(id, { text = "Any boss, " .. inst.name, tab = "dungeons", inst = i, boss = 1 })
        end
    end
    for v, vendor in ipairs(Loot.vendors or {}) do
        for _, e in ipairs(vendor.items or {}) do
            add(e[1], { text = "Sold by " .. vendor.name, tab = vendor.kind == "pvp" and "pvp" or "reputations", vendor = v })
        end
    end
    for _, id in ipairs(Loot.world or {}) do
        add(type(id) == "table" and id[1] or id, { text = "World drop", tab = "world", world = id })
    end
end

function D.Where(id)
    id = tonumber(id)
    if not id then return nil end
    if not where or builtFor ~= Loot.instances then build() end
    return where[id]
end

---------------------------------------------------------------------------
-- Auction prices (Encore-Stonks), cached until Stonks records new prices
---------------------------------------------------------------------------
local prices = {}

function D.PricesOn()
    local s = Encore.db and Encore.db.settings and Encore.db.settings.dbWindow
    return not (type(s) == "table" and s.ahPrices == false)
end

function D.Price(id)
    if not id or not D.PricesOn() then return nil end
    local p = prices[id]
    if p == nil then
        p = false
        local stonks = Encore.modules and Encore.modules.Stonks
        if stonks and stonks.ItemStats then
            local ok, st = pcall(stonks.ItemStats, stonks, tostring(id))
            if ok and type(st) == "table" then p = st.avg7 or st.avg3 or st.avg14 or false end
        end
        prices[id] = p
    end
    return p or nil
end

function D.ResetPrices() wipe(prices) end

local stonks = Encore.modules and Encore.modules.Stonks
if stonks and type(stonks.OnData) == "function" then hooksecurefunc(stonks, "OnData", D.ResetPrices) end

-- Short coin text for a price column: whole silver above one gold, with the coin icons.
function D.CoinShort(copper)
    return _G.EncoreEssentials.UI.Coins(copper, true)
end

-- Reagents { item, n, item, n, ... } at AH prices: total copper and how many reagents have no price.
function D.CraftCost(reagents)
    if type(reagents) ~= "table" or not D.PricesOn() then return nil, 0 end
    local total, missing = 0, 0
    for i = 1, #reagents, 2 do
        local p = D.Price(reagents[i])
        if p then total = total + p * (reagents[i + 1] or 1) else missing = missing + 1 end
    end
    return total, missing
end

-- Profit in green, loss in red with a minus sign, as coins.
function D.ProfitText(copper)
    local text = D.CoinShort(math.abs(copper))
    if copper < 0 then return "|cffff5a4c-|r" .. text end
    return "|cff73d966+|r" .. text
end
