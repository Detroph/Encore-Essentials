-- Encore-DB: loot and recipe database module (load on demand).
-- /encore db opens the window built in Window.lua (design: docs/mockup/encore-db-mockup.html).
-- Data from ForeverDB.net (https://foreverdb.net); see NOTICE.txt.
local _, ns = ...
local Encore = _G.EncoreEssentials
local DB = Encore:RegisterModule("DB", {})
ns.DB = DB
DB.Loot = ns.Loot
DB.Recipes = ns.Recipes
DB.RecipeSources = ns.RecipeSources
DB.Credit = "Data from ForeverDB.net (https://foreverdb.net)"

function DB:Toggle()
    if self.ToggleWindow then
        self:ToggleWindow()
    else
        Encore:Print("Encore-DB: the window did not load. Check for Lua errors.")
    end
end
