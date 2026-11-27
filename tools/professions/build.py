#!/usr/bin/env python3
"""Builds Encore-Professions' data: EncoreEssentials_Professions/Data/Recipes.lua and Data/World.lua.

    python3 tools/professions/build.py --wt <WhatsTraining> --gatherlite <GatherLite> --skillup <SkillUpForever>

Inputs (every one is read as text, never run):
- EncoreEssentials_DB/Data/Recipes.lua (ForeverDB.net, checked against Wowhead Forever): recipes, skill colours,
  reagents, how each is learned, trainer fees, vendors with places and prices, reputation and Merchant's Favor flags.
- What's Training? (Fusionpit, MIT) Crafting/Recipes/Camelot: the rank of each profession (skill, level, fee, the
  book or quest that teaches it), and the learn skill where ForeverDB has none.
- Not QuestieDB: trainers and their places, the rank books' vendors' and rank quests' names and places, and each
  zone's mob and beast levels are read in the game from the QuestieDB addon (EncoreEssentials_Professions/
  QuestieLive.lua), as QuestieDB's authors ask (2026-11-27). Only the NPC and quest IDs What's Training? gives ship.
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
COOLDOWN = {18560}  # Mooncloth (a cooldown at a moonwell); transmutes are left out by name


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


def outdoor(map_id):
    return 1411 <= map_id <= 1458 or map_id >= 2000


# Recipes ------------------------------------------------------------------------------------------------------
def wt_entries(wt, prof):
    path = os.path.join(wt, "Crafting", "Recipes", "Camelot", WT_FILES[prof] + ".lua")
    if not os.path.exists(path):
        return []
    src = read(path)
    t = find_table(src, "ns.Recipes[%d]" % SKILL_LINES[prof])
    return as_list(t)


def build_recipes(args):
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
                # Names and places come from the QuestieDB addon in the game (QuestieLive.lua).
                r["vendors"] = [{"npc": v["npc"], "side": {"Alliance": "A", "Horde": "H"}.get(v.get("faction"))}
                                for v in as_list(e.get("vendors")) if v.get("npc")]
            elif "quest" in srcs:
                r["how"] = "quest"
                # Quest names, givers and places come from the QuestieDB addon in the game (QuestieLive.lua).
                r["quests"] = [{"id": q["id"], "level": q.get("level"),
                                "side": {"Alliance": "A", "Horde": "H"}.get(q.get("faction"))}
                               for q in as_list(e.get("quests")) if q.get("id")]
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
-- Trainers, rank quests and zone levels: read in the game from the QuestieDB addon (QuestieLive.lua), not bundled.
-- Gathering nodes and fish: GatherLite by Wuild (MIT).
-- Vendor reagent prices: SkillUp Forever by cjber (GPL-3.0-or-later; client buy prices, LibPeriodicTable item list).
-- Licence: GPL-3.0; see NOTICE.txt in this addon.
local _, ns = ...
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wt", required=True, help="What's Training? addon folder")
    ap.add_argument("--gatherlite", required=True, help="GatherLite addon folder")
    ap.add_argument("--skillup", required=True, help="SkillUp Forever addon folder")
    args = ap.parse_args()

    recipes, vendors, ranks, report = build_recipes(args)
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

    # Trainers (ns.Trainers) and each zone's mob and beast levels come from the QuestieDB addon (QuestieLive.lua).
    lines = [HEADER, "-- Gathering nodes: { name, levels { orange, yellow, green, grey } (or just the first), zones { map, nodes, ... } }",
              "ns.Nodes = {"]
    for prof, nl in nodes.items():
        lines.append("  [%s] = {" % lua_str(prof))
        lines += ["    " + lua(n) + "," for n in nl]
        lines.append("  },")
    lines += ["}", "-- [map] = { fish { item, ... } } (QuestieLive.lua adds lo, hi and beasts from the QuestieDB addon)", "ns.Zones = {"]
    for m in sorted(catches):
        lines.append("  [%d] = %s," % (m, lua({"fish": sorted(set(catches[m]))})))
    lines += ["}", ""]
    with open(os.path.join(OUT, "World.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))

    for k, v in sorted(report.items()):
        print("%-40s %d" % (k, v))
    print("professions", len(recipes), "vendor recipes", len(vendors), "nodes", sum(len(v) for v in nodes.values()))


if __name__ == "__main__":
    main()
