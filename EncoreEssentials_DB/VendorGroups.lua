-- Encore-DB Reputations tab: a faction's rewards in groups (armour, weapons, recipes ...) that the right pane shows
-- under headings the player can close and open again. Window.lua calls ns.VendorGroups (it is near Lua's local limit).
local _, ns = ...

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant

-- In the order they are shown.
local GROUPS = {
    { key = "armor", text = "Armor" },
    { key = "weapon", text = "Weapons" },
    { key = "shield", text = "Shields and off-hands" },
    { key = "jewel", text = "Necks, rings and trinkets" },
    { key = "back", text = "Cloaks" },
    { key = "tabard", text = "Tabards" },
    { key = "recipe", text = "Recipes" },
    { key = "consumable", text = "Consumables" },
    { key = "enhancement", text = "Enhancements" },
    { key = "mount", text = "Mounts and pets" },
    { key = "bag", text = "Bags" },
    { key = "quest", text = "Quest items" },
    { key = "other", text = "Other" },
}

local JEWEL = { INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true }
local SLOT_JEWEL = { Neck = true, Finger = true, Trinket = true }

local function groupOf(c)
    local _, _, _, equipLoc, _, classID, subID
    if c.id and GetItemInfoInstant then _, _, _, equipLoc, _, classID, subID = GetItemInfoInstant(c.id) end
    local slot = c.slot
    local name = type(c.name) == "string" and c.name or ""
    if c.type == "Recipe" or classID == 9 or name:find("^Pattern: ") or name:find("^Plans: ") or name:find("^Formula: ")
        or name:find("^Recipe: ") or name:find("^Schematic: ") or name:find("^Manual: ") then
        return "recipe"
    end
    if c.type == "Quest item" or classID == 12 then return "quest" end
    if c.type == "Enhancement" or classID == 8 then return "enhancement" end
    if classID == 15 and (subID == 2 or subID == 5) then return "mount" end
    if equipLoc == "INVTYPE_TABARD" or slot == "Tabard" then return "tabard" end
    if equipLoc == "INVTYPE_CLOAK" or slot == "Back" then return "back" end
    if JEWEL[equipLoc or ""] or SLOT_JEWEL[slot or ""] then return "jewel" end
    if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" or slot == "Off Hand" or slot == "Held In Off-hand" then
        return "shield"
    end
    if classID == 2 or slot == "One-Hand" or slot == "Two-Hand" or slot == "Main Hand" or slot == "Ranged" or slot == "Thrown" then
        return "weapon"
    end
    if classID == 4 or (slot and slot ~= "" and slot ~= "Shirt" and slot ~= "Bag") then return "armor" end
    if classID == 0 then return "consumable" end
    if classID == 1 or classID == 11 or slot == "Bag" then return "bag" end
    return "other"
end

-- cells -> { { key, text, cells }, ... }, empty groups left out.
function ns.VendorGroups(cells)
    local byKey = {}
    for _, c in ipairs(cells) do
        local k = groupOf(c)
        byKey[k] = byKey[k] or {}
        table.insert(byKey[k], c)
    end
    local out = {}
    for _, g in ipairs(GROUPS) do
        if byKey[g.key] then out[#out + 1] = { key = g.key, text = g.text, cells = byKey[g.key] } end
    end
    return out
end
