#!/usr/bin/env python3
"""Builds Encore-Professions' data: EncoreEssentials_Professions/Data/Recipes.lua and Data/World.lua.

    python3 tools/professions/build.py --wt <WhatsTraining> --questie <QuestieDB> --gatherlite <GatherLite> --skillup <SkillUpForever>

Inputs (every one is read as text, never run):
- EncoreEssentials_DB/Data/Recipes.lua (ForeverDB.net, checked against Wowhead Forever): recipes, skill colours,
  reagents, how each is learned, trainer fees, vendors with places and prices, reputation and Merchant's Favor flags.
- What's Training? (Fusionpit, MIT) Crafting/Recipes/Camelot: the rank of each profession (skill, level, fee, the
  book or quest that teaches it), and the learn skill where ForeverDB has none.
- QuestieDB (GPL-3.0) data/Forever and support/Forever/Zones: profession trainers and their places, the NPCs and
  quests behind the rank books and quests, zone maps, and the beasts and mob levels of each zone.
- GatherLite (Wuild, MIT) scripts/nodes.lua and plugins: herb and ore skill levels, node places, fish caught per zone.
- SkillUp Forever (cjber, GPL-3.0-or-later) Data/Vendor.lua: reagents vendors sell and their client buy prices.

Only recipes a trainer teaches or a vendor sells for gold make it in: no drops, quests, reputation, Merchant's Favor,
World Events or recipes not in the client yet (Det's rule, the way What's Training? lists them).
"""
import argparse
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from luatext import as_list, find_table, parse  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "EncoreEssentials_Professions", "Data")

SKILL_LINES = {"Alchemy": 171, "Blacksmithing": 164, "Cooking": 185, "Enchanting": 333, "Engineering": 202,
               "First Aid": 129, "Fishing": 356, "Herbalism": 182, "Leatherworking": 165, "Mining": 186,
               "Skinning": 393, "Tailoring": 197}
WT_FILES = {"Alchemy": "Alchemy", "Blacksmithing": "Blacksmithing", "Cooking": "Cooking", "Enchanting": "Enchanting",
            "Engineering": "Engineering", "First Aid": "FirstAid", "Fishing": "Fishing", "Herbalism": "Herbalism",
            "Leatherworking": "Leatherworking", "Mining": "Mining", "Skinning": "Skinning", "Tailoring": "Tailoring"}
RANK_CAP = {"Journeyman": 150, "Expert": 225, "Artisan": 300}

# Profession trainers by their title in QuestieDB. Specialisation trainers (Mooncloth, Dragonscale, Gnomish ...)
# teach no ranks and are left out.
TRAINER_TITLE = {
    "Alchemy": r"\bAlchemist\b|^Alchemy Trainer$",
    "Blacksmithing": r"^(Journeyman|Expert|Artisan|Master) Blacksmith$|^Blacksmithing Trainer$",
    "Enchanting": r"\bEnchanter\b|^Enchanting Trainer$",
    "Engineering": r"^(Journeyman|Expert|Artisan|Master) Engineer$|^Engineering Trainer$",
    "Leatherworking": r"^(Journeyman|Expert|Artisan|Master) Leatherworker$|^Leatherworking Trainer$",
    "Tailoring": r"^(Journeyman|Expert|Artisan|Master) Tailor$|^Tailoring Trainer$",
    "Cooking": r"^Cooking Trainer$|^Cook$|^Chef$",
    "First Aid": r"^First Aid Trainer$|^Physician$|^Surgeon$",
    "Fishing": r"^Fishing Trainer$|^Fisherman$|^Superior Fisherman$",
    "Herbalism": r"^Herbalism Trainer$|^Herbalist$|^Superior Herbalist$",
    "Mining": r"^Mining Trainer$|^Miner$",
    "Skinning": r"^Skinning Trainer$|^Skinner$",
}
NOT_TRAINER = re.compile(r"Supplies|Supplier|Shadoweave|Mooncloth|Spellfire|Dragonscale|Elemental|Tribal|Gnom|Goblin|World")
TRAINER_FLAG = 16
COOLDOWN = {18560}  # Mooncloth (a cooldown at a moonwell); transmutes are left out by name

# Skinnable beasts, by their names (QuestieDB has no creature type). Names only pick the mobs to count.
BEAST = re.compile(r"\b(Wolf|Worg|Boar|Bear|Grizzly|Cat|Lion|Lioness|Panther|Tiger|Leopard|Lynx|Sabercat|Saber|Stalker|"
                   r"Prowler|Raptor|Crocolisk|Basilisk|Hyena|Gorilla|Ape|Silverback|Scorpid|Spider|Widow|Lurker|Tarantula|"
                   r"Recluse|Crab|Turtle|Tortoise|Snapjaw|Kodo|Thunder Lizard|Thunderhead|Lizard|Strider|Plainstrider|"
                   r"Tallstrider|Hawk|Owl|Vulture|Buzzard|Carrion Bird|Bat|Wind Serpent|Serpent|Yeti|Stag|Deer|Ram|Goat|"
                   r"Coyote|Jackal|Hippogryph|Chimaera|Devilsaur|Stegodon|Pterrordax|Diemetradon|Shardtooth|Frostsaber|"
                   r"Nightsaber|Mountain Lion|Felstalker|Bloodfang|Mastiff|Hound|Gnoll Hound|Swoop|Wildkin|Thistlefur Bear|"
                   r"Ashenvale Bear|Thrasher|Ravager|Ridge|Ironjaw|Mosshoof|Moonkin|Bristleback Boar|Elk)\b")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua(v):
    if v is None:
        return "nil"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, (int,)):
        return str(v)
    if isinstance(v, float):
        return ("%.1f" % v).rstrip("0").rstrip(".")
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua(x) for x in v) + " }" if v else "{}"
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            if x is None:
                continue
            key = k if isinstance(k, str) and re.match(r"^[A-Za-z_]\w*$", k) else "[" + lua(k) + "]"
            parts.append("%s = %s" % (key, lua(x)))
        return "{ " + ", ".join(parts) + " }" if parts else "{}"
    raise TypeError(type(v))


# QuestieDB ----------------------------------------------------------------------------------------------------
def questie_block(path):
    src = read(path)
    m = re.search(r"\[\[return\s*", src)
    return parse(src, m.end())[0]


def zone_maps(qdb):
    src = read(os.path.join(qdb, "support", "Forever", "Zones", "areaIdToUiMapId.lua"))
    blocks = re.findall(r"=\s*\[\[return\s*(\{.*?\})\s*\]\]", src, re.S)
    maps = {}
    for b in reversed(blocks):  # the main table first, then the overrides on top
        t, _ = parse(b, 0)
        for k, v in (t.items() if isinstance(t, dict) else []):
            if isinstance(v, int) and v > 0:
                maps[k] = v
    return maps


def outdoor(map_id):
    return 1411 <= map_id <= 1458 or map_id >= 2000


def npc_place(npc, maps):
    spawns = npc.get(7) if isinstance(npc, dict) else (npc[6] if len(npc) > 6 else None)
    if not isinstance(spawns, dict):
        return None
    for zone, coords in spawns.items():
        coords = as_list(coords)
        m = maps.get(zone)
        if m and coords and isinstance(coords[0], list) and len(coords[0]) >= 2 and coords[0][0] >= 0:
            return m, round(coords[0][0], 1), round(coords[0][1], 1)
    return None


def field(npc, n):
    if isinstance(npc, dict):
        return npc.get(n)
    return npc[n - 1] if len(npc) >= n else None


# Recipes ------------------------------------------------------------------------------------------------------
def wt_entries(wt, prof):
    path = os.path.join(wt, "Crafting", "Recipes", "Camelot", WT_FILES[prof] + ".lua")
    if not os.path.exists(path):
        return []
    src = read(path)
    t = find_table(src, "ns.Recipes[%d]" % SKILL_LINES[prof])
    return as_list(t)


def build_recipes(args, maps, npcs, quests):
    src = read(os.path.join(ROOT, "EncoreEssentials_DB", "Data", "Recipes.lua"))
    recipes = find_table(src, "ns.Recipes")
    sources = find_table(src, "ns.RecipeSources")
    out, vendors, ranks, report = {}, {}, {}, collections.Counter()
    for prof in sorted(SKILL_LINES):
        wt = wt_entries(args.wt, prof)
        wt_by_spell = {e.get("spell"): e for e in wt if isinstance(e, dict)}
        # Ranks: Journeyman, Expert, Artisan with what teaches them.
        rl = []
        for e in wt:
            if not isinstance(e, dict) or e.get("rank") not in RANK_CAP:
                continue
            r = {"name": e["rank"], "skill": e.get("skill"), "cap": RANK_CAP[e["rank"]], "spell": e.get("spell"),
                 "level": e.get("level") or 0}
            srcs = as_list(e.get("source"))
            if "trainer" in srcs:
                r["how"], r["cost"] = "trainer", e.get("cost")
            elif "vendor" in srcs and e.get("teach"):
                r["how"], r["item"] = "book", e["teach"]
                vl = []
                for v in as_list(e.get("vendors")):
                    n = npcs.get(v.get("npc"))
                    place = n and npc_place(n, maps)
                    if place:
                        vl.append({"npc": v["npc"], "name": field(n, 1), "map": place[0], "x": place[1], "y": place[2],
                                   "side": {"Alliance": "A", "Horde": "H"}.get(v.get("faction"))})
                r["vendors"] = vl
            elif "quest" in srcs:
                r["how"] = "quest"
                ql = []
                for q in as_list(e.get("quests")):
                    qd = quests.get(q.get("id"))
                    if not qd:
                        continue
                    starter = as_list(as_list(field(qd, 2))[0]) if as_list(field(qd, 2)) else []
                    n = npcs.get(starter[0]) if starter else None
                    place = n and npc_place(n, maps)
                    entry = {"id": q["id"], "name": field(qd, 1), "level": q.get("level") or field(qd, 4),
                             "side": {"Alliance": "A", "Horde": "H"}.get(q.get("faction"))}
                    if place:
                        entry.update({"npc": starter[0], "by": field(n, 1), "map": place[0], "x": place[1], "y": place[2]})
                    ql.append(entry)
                r["quests"] = ql
            rl.append(r)
        ranks[prof] = sorted(rl, key=lambda r: r["skill"] or 0)

        rows = []
        for e in as_list(recipes.get(prof)):
            if isinstance(e, list):
                e = {i + 1: v for i, v in enumerate(e)}
            spell, name, skill, yellow, green, grey, makes, count, reag, learned = [e.get(i) for i in range(1, 11)]
            if e.get("notInClient") or e.get("favor") or e.get("faction"):
                report["reputation, favor or not in client"] += 1
                continue
            w = wt_by_spell.get(spell, {})
            if w.get("reputation") or w.get("merchantFavor"):
                report["reputation or favor (What's Training?)"] += 1
                continue
            if ("Winter" in name and "Clothes" in name) or name.startswith("Transmute") or spell in COOLDOWN:
                report["world event or cooldown"] += 1
                continue
            if learned is None and "trainer" in as_list(w.get("source")):
                learned = "t"  # What's Training? fills in a trainer recipe ForeverDB has no source for
            if learned in ("t", "a"):
                how, cost = learned, e.get("trainerCost") or w.get("cost") or 0
            elif isinstance(learned, int):
                vl = [s for s in as_list(sources.get(learned)) if isinstance(s, dict) and s.get("type") == "vendor"
                      and not s.get("limited")]
                if not vl:
                    report["drop, quest or limited vendor"] += 1
                    continue
                how = learned
                cost = min(s.get("price") or 0 for s in vl)
                vendors[learned] = [{"npc": s.get("npc"), "name": s.get("name"), "map": s.get("map"), "x": s.get("x"),
                                     "y": s.get("y"), "side": s.get("side"), "price": s.get("price")} for s in vl]
            else:
                report["unknown source"] += 1
                continue
            learn = skill if isinstance(skill, int) and skill > 0 else w.get("skill")
            if not isinstance(learn, int):
                learn = max(1, (yellow or 1) - 25) if isinstance(yellow, int) else 1
            if not (isinstance(yellow, int) and isinstance(grey, int)) or grey <= 0 or not reag:
                report["no colours or reagents"] += 1
                continue
            rows.append([spell, name, max(1, learn), yellow, green, grey, makes, count or 1, as_list(reag), how, cost])
            report["kept"] += 1
        rows.sort(key=lambda r: (r[2], r[3], r[1]))
        if rows:
            out[prof] = rows
    return out, vendors, ranks, report


def build_trainers(npcs, maps):
    out = collections.defaultdict(list)
    for nid, n in npcs.items():
        title = field(n, 14)
        flags = field(n, 15) or 0
        if not isinstance(title, str) or not (flags & TRAINER_FLAG) or NOT_TRAINER.search(title):
            continue
        for prof, pat in TRAINER_TITLE.items():
            if re.search(pat, title):
                place = npc_place(n, maps)
                if not place:
                    break
                cap = 300
                if title.startswith("Journeyman"):
                    cap = 150
                elif title.startswith("Expert"):
                    cap = 225
                side = field(n, 13)
                out[prof].append({"npc": nid, "name": field(n, 1), "title": title, "map": place[0], "x": place[1],
                                  "y": place[2], "side": side if side in ("A", "H") else None, "cap": cap})
                break
    for prof in out:
        out[prof].sort(key=lambda t: (t["map"], t["npc"]))
    return dict(out)


def build_zones(npcs, maps):
    """Per outdoor map: hostile mob levels (for fishing tiers) and skinnable beasts' levels."""
    mobs, beasts = collections.defaultdict(list), collections.defaultdict(collections.Counter)
    for nid, n in npcs.items():
        if field(n, 13) or field(n, 14):  # friendly to a side, or has a title: not a wild mob
            continue
        if (field(n, 6) or 0) not in (0, 1):
            continue
        lo, hi = field(n, 4), field(n, 5)
        spawns = field(n, 7)
        if not (isinstance(lo, int) and isinstance(hi, int) and isinstance(spawns, dict)) or hi > 63:
            continue
        name = field(n, 1) or ""
        for zone, coords in spawns.items():
            m = maps.get(zone)
            if not m or not outdoor(m):
                continue
            k = len(as_list(coords))
            mobs[m].extend([(lo + hi) // 2] * max(1, k))
            if BEAST.search(name):
                beasts[m][(lo + hi) // 2] += max(1, k)
    zones = {}
    for m, levels in mobs.items():
        if len(levels) < 20:
            continue
        levels.sort()
        lo = levels[int(len(levels) * 0.15)]
        hi = levels[int(len(levels) * 0.85)]
        b = beasts.get(m)
        bl = []
        if b:
            for lvl, cnt in sorted(b.items()):
                bl += [lvl, cnt]
        zones[m] = {"lo": lo, "hi": hi, "beasts": bl or None}
    return zones


# GatherLite ---------------------------------------------------------------------------------------------------
def build_nodes(gl):
    src = read(os.path.join(gl, "scripts", "nodes.lua"))
    nodes = []
    for m in re.finditer(r'InsertObject\("(ore|herb)",\s*(\{[^}]*\}),\s*"(\w+)",\s*"[^"]*",\s*(\{[^}]*\})', src):
        kind, ids, name, levels = m.group(1), parse(m.group(2))[0], m.group(3), parse(m.group(4))[0]
        nodes.append({"kind": kind, "ids": ids, "name": name, "levels": levels})
    pre = find_table(read(os.path.join(gl, "plugins", "database", "data", "forever.lua")), "addon.predefined")
    merged = collections.OrderedDict()
    for n in nodes:
        counts = collections.Counter()
        for oid in n["ids"]:
            for m, pts in (pre.get(oid) or {}).items():
                if outdoor(m):
                    counts[m] += len(as_list(pts)) // 2
        if not counts:
            continue
        key = (n["kind"], n["name"])
        if key in merged:
            merged[key]["counts"].update(counts)
        else:
            merged[key] = {"kind": n["kind"], "name": n["name"], "levels": n["levels"], "counts": counts}
    out = {"Mining": [], "Herbalism": []}
    for n in merged.values():
        top = [[m, c] for m, c in n["counts"].most_common(8) if c >= 3]
        if not top:
            continue
        label = re.sub(r"\b(Of|The)\b", lambda w: w.group(0).lower(), n["name"].replace("_", " ").title()).replace("'S", "'s")
        out["Mining" if n["kind"] == "ore" else "Herbalism"].append({"name": label, "levels": n["levels"],
                                                                      "zones": [x for z in top for x in z]})
    for k in out:
        out[k].sort(key=lambda n: (n["levels"][0], n["name"]))
    fish = find_table(read(os.path.join(gl, "plugins", "fishing", "data.lua")), "addon.fishDB")
    catches = collections.defaultdict(list)
    for f in as_list(fish):
        if f.get("type") != "fish":
            continue
        for m in (f.get("maps") or {}):
            if outdoor(m):
                catches[m].append(f["itemID"])
    return out, catches


def vendor_prices(skillup):
    t = find_table(read(os.path.join(skillup, "Data", "Vendor.lua")), "ns.VendorPrices")
    return {k: v for k, v in sorted(t.items()) if isinstance(k, int)}


HEADER = """-- Encore-Professions data. Generated by tools/professions/build.py: do not edit by hand.
-- Recipes, skill colours, reagents, trainer fees and recipe vendors: Encore-DB (Data from ForeverDB.net,
-- https://foreverdb.net, checked against Wowhead Forever). Ranks: What's Training? by Fusionpit (MIT).
-- Trainers, quests and zones: QuestieDB (GPL-3.0). Gathering nodes and fish: GatherLite by Wuild (MIT).
-- Vendor reagent prices: SkillUp Forever by cjber (GPL-3.0-or-later; client buy prices, LibPeriodicTable item list).
-- Licence: GPL-3.0; see NOTICE.txt in this addon.
local _, ns = ...
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wt", required=True, help="What's Training? addon folder")
    ap.add_argument("--questie", required=True, help="QuestieDB checkout")
    ap.add_argument("--gatherlite", required=True, help="GatherLite addon folder")
    ap.add_argument("--skillup", required=True, help="SkillUp Forever addon folder")
    args = ap.parse_args()

    maps = zone_maps(args.questie)
    npcs = questie_block(os.path.join(args.questie, "data", "Forever", "foreverNpcDB.lua"))
    quests = questie_block(os.path.join(args.questie, "data", "Forever", "foreverQuestDB.lua"))
    recipes, vendors, ranks, report = build_recipes(args, maps, npcs, quests)
    trainers = build_trainers(npcs, maps)
    zones = build_zones(npcs, maps)
    nodes, catches = build_nodes(args.gatherlite)
    prices = vendor_prices(args.skillup)

    os.makedirs(OUT, exist_ok=True)
    lines = [HEADER,
             "-- [profession] = { { spell, name, learn (skill), yellow, green, grey, makes, count, { item, n, ... },",
             "--   how (\"t\" trainer, \"a\" automatic, or the recipe item a vendor sells), cost (copper) } }",
             "ns.Recipes = {"]
    for prof, rows in recipes.items():
        lines.append("  [%s] = {" % lua_str(prof))
        lines += ["    " + lua(r) + "," for r in rows]
        lines.append("  },")
    lines += ["}", "-- [recipe item] = { { npc, name, map (uiMap), x, y, side, price } }", "ns.RecipeVendors = {"]
    lines += ["  [%d] = %s," % (k, lua(v)) for k, v in sorted(vendors.items())]
    lines += ["}", "-- [profession] = { { name, skill (learn at), cap, spell, level, how = trainer|book|quest, cost, item, vendors, quests } }",
              "ns.Ranks = {"]
    lines += ["  [%s] = %s," % (lua_str(p), lua(r)) for p, r in ranks.items() if r]
    lines += ["}", "-- [item] = copper a vendor asks for one", "ns.VendorPrices = {"]
    lines += ["  [%d] = %d," % (k, v) for k, v in prices.items()]
    lines += ["}", ""]
    with open(os.path.join(OUT, "Recipes.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))

    lines = [HEADER, "-- [profession] = { { npc, name, title, map (uiMap), x, y, side, cap (highest skill it trains to) } }",
             "ns.Trainers = {"]
    for prof, tl in sorted(trainers.items()):
        lines.append("  [%s] = {" % lua_str(prof))
        lines += ["    " + lua(t) + "," for t in tl]
        lines.append("  },")
    lines += ["}", "-- Gathering nodes: { name, levels { orange, yellow, green, grey } (or just the first), zones { map, nodes, ... } }",
              "ns.Nodes = {"]
    for prof, nl in nodes.items():
        lines.append("  [%s] = {" % lua_str(prof))
        lines += ["    " + lua(n) + "," for n in nl]
        lines.append("  },")
    lines += ["}", "-- [map] = { lo, hi (most wild mobs' levels), beasts { level, spawns, ... }, fish { item, ... } }", "ns.Zones = {"]
    for m in sorted(set(zones) | set(catches)):
        z = dict(zones.get(m) or {})
        if catches.get(m):
            z["fish"] = sorted(set(catches[m]))
        if z:
            lines.append("  [%d] = %s," % (m, lua(z)))
    lines += ["}", ""]
    with open(os.path.join(OUT, "World.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))

    for k, v in sorted(report.items()):
        print("%-40s %d" % (k, v))
    print("professions", len(recipes), "vendor recipes", len(vendors), "trainers",
          sum(len(v) for v in trainers.values()), "zones", len(zones), "nodes", sum(len(v) for v in nodes.values()))


if __name__ == "__main__":
    main()
