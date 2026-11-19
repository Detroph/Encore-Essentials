-- Encore-DB: dungeons with wings.
-- Hand-kept and separate from the generated loot data (Loot.lua), so it survives a data refresh
-- or a switch to another data source. Keyed by instance key; bosses by name as in Loot.lua.
--
-- Each wing becomes its own dungeon in the list. A dungeon marked optional is only split when the
-- player turns that on in the options menu, and one marked headingsOnly never is; while a dungeon
-- is not split, its boss list shows a heading per wing.
-- Bosses no wing names (rare spawns or summons we have not placed) and trash are listed in every wing.
-- Within a wing, bosses follow the order listed here: the usual kill order.
local _, ns = ...

ns.Wings = {
    ["blackrock-spire"] = {
        optional = true,
        { key = "lower", name = "Lower Blackrock Spire", bosses = {
            "Spirestone Butcher", "Spirestone Battle Lord", "Spirestone Lord Magus", "Highlord Omokk",
            "Shadow Hunter Vosh'gajin", "War Master Voone", "Mor Grayhoof", "Mother Smolderweb", "Crystal Fang",
            "Urok Doomhowl", "Bannok Grimaxe", "Burning Felguard", "Quartermaster Zigris", "Halycon",
            "Gizrul the Slavener", "Ghok Bashguud", "Overlord Wyrmthalak",
        } },
        { key = "upper", name = "Upper Blackrock Spire", bosses = {
            "Pyroguard Emberseer", "Solakar Flamewreath", "Jed Runewatcher", "Goraluk Anvilcrack", "Gyth",
            "Warchief Rend Blackhand", "The Beast", "Lord Valthalak", "General Drakkisath",
        } },
    },
    ["stratholme"] = {
        headingsOnly = true, -- stays one dungeon, with a heading per side in its boss list
        { key = "living", name = "Living side", bosses = {
            "Skul", "Stratholme Courier", "Hearthsinger Forresten", "The Unforgiven", "Timmy the Cruel",
            "Malor the Zealous", "Crimson Hammersmith", "Postmaster Malown", "Ezra Grimm", "Cannon Master Willey",
            "Archivist Galford", "Balnazzar", "Jarien and Sothos",
        } },
        { key = "undead", name = "Undead side", bosses = {
            "Stonespine", "Nerub'enkan", "Baroness Anastari", "Maleki the Pallid", "Magistrate Barthilas",
            "Ramstein the Gorger", "Black Guard Swordsmith", "Baron Rivendare",
        } },
    },
    ["scarlet-monastery"] = {
        { key = "graveyard", name = "Scarlet Monastery - Graveyard", bosses = {
            "Interrogator Vishas", "Azshir the Sleepless", "Fallen Champion", "Ironspine", "Scorn", "Bloodmage Thalnos",
        } },
        { key = "library", name = "Scarlet Monastery - Library", bosses = {
            "Houndmaster Loksey", "Arcanist Doan", "Doan's Strongbox",
        } },
        { key = "armory", name = "Scarlet Monastery - Armory", bosses = {
            "Herod",
        } },
        { key = "cathedral", name = "Scarlet Monastery - Cathedral", bosses = {
            "High Inquisitor Fairbanks", "Scarlet Commander Mograine", "High Inquisitor Whitemane",
        } },
    },
    ["dire-maul"] = {
        { key = "east", name = "Dire Maul - East", bosses = {
            "Pusillin", "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", "Alzzin the Wildshaper", "Isalien",
        } },
        { key = "west", name = "Dire Maul - West", bosses = {
            "Tendris Warpwood", "Tsu'zee", "Magister Kalendris", "Illyanna Ravenoak", "Immol'thar",
            -- Lord Hel'nurath is summoned in Immol'thar's prison during the warlock epic mount quest
            -- (Dreadsteed of Xoroth), with J'eevee's Jar, Black Lodestone and Xorothian Glyphs.
            "Lord Hel'nurath",
            "Prince Tortheldrin", "Shen'dralar Provisioner",
        } },
        { key = "north", name = "Dire Maul - North", bosses = {
            "Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik", "Captain Kromcrush",
            "Cho'Rush the Observer", "King Gordok", "Knot Thimblejack's Cache", "Tribute", "Mizzle the Crafty",
        } },
    },
}

-- Bosses whose loot is shown on another boss's page, under its own heading, instead of in the list.
ns.BossAttach = {
    ["Pimgib"] = "Lethtendris", -- Lethtendris's imp, Dire Maul East
}

-- A line shown above a boss's loot.
ns.BossNotes = {
    ["Lord Hel'nurath"] = "Summoned during the warlock epic mount quest (Dreadsteed of Xoroth). "
        .. "The summoning needs J'eevee's Jar, Black Lodestone and Xorothian Glyphs.",
}

-- Bosses attached to this one (see BossAttach).
function ns.AttachedBosses(inst, boss)
    local list
    for _, other in ipairs(inst.bosses or {}) do
        if ns.BossAttach[other.name] == boss.name then
            list = list or {}
            list[#list + 1] = other
        end
    end
    return list
end

-- One instance table per wing, made once so selections and counts stay stable when the option changes.
local wingCache = {}
local function wingInstances(inst, spec)
    if wingCache[inst] then return wingCache[inst] end
    local placed = {}
    for _, wing in ipairs(spec) do
        for _, name in ipairs(wing.bosses) do placed[name] = true end
    end
    local list = {}
    for _, wing in ipairs(spec) do
        local w = {}
        for k, v in pairs(inst) do w[k] = v end
        w.key, w.name, w.parent, w.bosses = inst.key .. "/" .. wing.key, wing.name, inst.key, {}
        -- In the order the wing lists them
        for _, name in ipairs(wing.bosses) do
            for _, boss in ipairs(inst.bosses or {}) do
                if boss.name == name then w.bosses[#w.bosses + 1] = boss; break end
            end
        end
        for _, boss in ipairs(inst.bosses or {}) do
            if not boss.trash and not placed[boss.name] and not ns.BossAttach[boss.name] then
                w.bosses[#w.bosses + 1] = boss
            end
        end
        -- Attached bosses ride along with their host so its page can show them
        for _, boss in ipairs(inst.bosses or {}) do
            local host = ns.BossAttach[boss.name]
            if host then
                for _, b in ipairs(w.bosses) do
                    if b.name == host then w.bosses[#w.bosses + 1] = boss; break end
                end
            end
        end
        for _, boss in ipairs(inst.bosses or {}) do
            if boss.trash then w.bosses[#w.bosses + 1] = boss end
        end
        list[#list + 1] = w
    end
    wingCache[inst] = list
    return list
end

-- Rebuild loot.instances from the stored list, splitting dungeons into wings.
-- splitOptional: also split the optional ones (Blackrock Spire).
function ns.ApplyWings(loot, splitOptional)
    loot.allInstances = loot.allInstances or loot.instances or {}
    local out = {}
    for _, inst in ipairs(loot.allInstances) do
        local spec = ns.Wings[inst.key]
        if spec and not spec.headingsOnly and (splitOptional or not spec.optional) then
            for _, w in ipairs(wingInstances(inst, spec)) do out[#out + 1] = w end
        else
            out[#out + 1] = inst
        end
    end
    loot.instances = out
end
