# Encore-DB data tools

Python 3 scripts that build Encore-DB's profession data. Downloaded data is not stored in the repository; fetch it into a working folder first.

## Refreshing the data (one command)

`tools/refresh.mjs` runs the whole refresh in the agreed source order, on your own computer, without a Claude session:

| Data | Sources, in order |
| --- | --- |
| Quests | QuestieDB, then Wowhead Forever for blanks |
| Loot and drops | ForeverDB, foreverchanges.pro, Wowhead Forever. The Dungeon Journal and AtlasLoot Continued addons are only compared, never copied: `tools/out/dj-check.json` and `tools/out/atlasloot-check.json` list their drops we don't have yet, and AtlasLoot's are kept only when Wowhead Forever confirms them |
| Boss levels | QuestieDB's Forever NPC data, then Wowhead Forever for blanks (`tools/loot/questie-levels.mjs`) |
| Professions | ForeverDB, then every recipe checked against Wowhead Forever (`tools/out/recipes-check.json`) |

Setup, once: copy `tools/refresh.config.example.json` to `tools/refresh.config.json` (not in the repository) and set `dungeonJournal` to your `AddOns\ForeverDungeonJournal` folder and `atlasLoot` to your `AddOns` folder. `lootSources` picks the loot sources: `dungeon-journal-check`, `atlasloot` (or `atlasloot-check`), `foreverdb`, `foreverchanges`, `wowhead`, and optionally `wowtbc`.

```
node tools/refresh.mjs all --download   # download the sources again, then quests, loot and professions
node tools/refresh.mjs loot             # one step, from the cached downloads
# The Wowhead collection scripts (wowhead-items.mjs, wowhead-drops.mjs, wowhead-browser-script.mjs) live in the
# separate encore-data-tools project. Copy them into tools/loot/ first; without them these steps are skipped.
node tools/refresh.mjs wowhead-script   # -> tools/out/wowhead-sweep.js, for the Wowhead pages (see below)
node tools/refresh.mjs import <files>   # read the files the Wowhead script downloaded
```

**AtlasLoot leads left out.** Wowhead's tooltips don't name a dropper for many new Forever trash drops, so the loot step can't confirm those AtlasLoot leads. `node tools/refresh.mjs leads-script` writes `tools/out/wowhead-leads-sweep.js`. Paste it into the Console on www.wowhead.com/forever: it reads Wowhead's item lists for those IDs (only the IDs come from AtlasLoot) and downloads `wowhead-leads.json`. Put that in `tools/out/`. The loot step then runs `tools/loot/atlasloot-additions.mjs` after `build-loot.mjs`. It adds a lead to Loot.lua only when Wowhead shows it dropping in that instance: under the boss (or chest) Wowhead names, or, for AtlasLoot's trash, under the instance's trash when Wowhead names no boss. Boss leads Wowhead doesn't tie to a boss, common items, recipes and crafted or vendor items stay out. Report: `tools/out/atlasloot-additions.json`. The same command also writes `tools/out/wowhead-faction-quests-sweep.js`. It reads the quest rewards of the factions listed in `tools/loot/faction-quest-rewards.mjs` (Guardians of Hyjal) from their Wowhead Forever pages and downloads `wowhead-faction-quests.json`. The loot step then lists those rewards with the faction's reputation rewards as "Quest reward".

**Extras (PvP and reputation rewards, collections, item sets, rogue poisons).** `node tools/refresh.mjs extras-script` reads AtlasLoot Continued's PvP, Collections, Factions and poison lists (`tools/loot/atlasloot-extras.mjs`, only the IDs, as leads: AtlasLoot is GPL v2 only and nothing of it is copied) and writes `tools/out/wowhead-extras-sweep.js`. Paste it into the Console on www.wowhead.com/forever; it reads the item set list, item lists by ID range, item tooltips and a few item pages, and downloads `wowhead-extras.json`. Put that in `tools/out/` and run `node tools/refresh.mjs extras`: `tools/loot/build-extras.mjs` writes `EncoreEssentials_DB/Data/Extras.lua` with only the items Wowhead Forever shows a source for, and `tools/out/extras-check.json` with what was left out. World events are left out until they run in Forever.

**Wowhead pages.** Wowhead shows a "Human Verification" check to scripts, so its boss, faction, world-drop and quest pages are read in your browser. Run `node tools/refresh.mjs wowhead-script`, open www.wowhead.com/forever, press F12, paste `tools/out/wowhead-sweep.js` into the Console and press Enter. A progress bar shows how far it is. It reads one page every 8 seconds and downloads `wowhead-drops-<n>.json` every 100 pages and at the end. When Wowhead shows its check, the script saves what it has and tries again every 5 minutes. It never answers the check; you can tick it yourself in another Wowhead tab. Then run `node tools/refresh.mjs import` with the downloaded files, and `node tools/refresh.mjs all`. A new script leaves out the pages already imported.

## 1. Client tables (wago.tools)

Find the latest WoW Forever build in `https://wago.tools/api/builds` (product `wowf`) and download these tables as CSV into one folder, e.g. `wago/`:

```
https://wago.tools/db2/<Table>/csv?build=<build>
```

Tables: `SkillLine`, `SkillLineAbility`, `SpellName`, `SpellReagents`, `SpellEffect`, `ItemEffect`, `ItemXItemEffect`, `ItemSparse`, `UiMap`, `UiMapAssignment`, `Map`, `FactionTemplate`.

For the new/changed comparison, download `SkillLineAbility`, `SpellReagents` and `ItemSparse` for the latest `wow_classic_era` build into `era/`. Note that the Classic Era client also contains Season of Discovery data, so content Forever shares with SoD is not flagged as new.

## 2. Build a profession

```
python3 prof.py wago 171 > alchemy.json             # 171 = Alchemy skill line
python3 diff.py wago era alchemy.json               # marks new / changed vs Classic Era
python3 mockdata.py alchemy.json wago recipes.json  # sample data for the mock-up
```

WoW Forever is its own game, so no Vanilla server databases are used.

## 3. Loot tables and recipe sources (Node 18+)

These tools fetch politely. They send one request per host every 1.2 s, cache every answer in `tools/cache/` (not in the repository), and stop after three failed requests in a row. A rerun fetches only what is not cached yet. Delete `tools/cache/<host>/` to refresh a source.

```
node tools/loot/foreverdb-files.mjs                   # ForeverDB.net addon data files (main source), checked against its manifest
node tools/loot/fc-dungeons.mjs                       # foreverchanges.pro: bosses and their loot per dungeon (fill-in)
node tools/loot/wowtbc.mjs                            # wowtbc.gg: Forever loot tables (optional fill-in, only with "wowtbc" in lootSources)
node tools/loot/wowhead-items.mjs --missing           # Wowhead Forever tooltips for the items in the lists above not fetched yet
node tools/loot/wowhead-drops.mjs                     # Wowhead Forever pages: boss drops, reputation rewards, world drops (slow, see below)
git clone --depth 1 https://github.com/Questie/QuestieDB tools/cache/questiedb   # once; refresh.mjs --download pulls it
node tools/loot/questie-levels.mjs                    # QuestieDB's Forever NPC levels -> tools/out/npc-levels.json
node tools/loot/build-loot.mjs                        # -> EncoreEssentials_DB/Data/Loot.lua
node tools/loot/build-recipes.mjs                     # -> EncoreEssentials_DB/Data/Recipes.lua (lists recipe items with no source)
node tools/loot/fc-items.mjs                          # foreverchanges.pro: sources for those recipe items (fill-in)
node tools/loot/build-recipes.mjs                     # again, with the fill-in
node tools/loot/check-recipes.mjs --fetch             # check every recipe against Wowhead Forever -> tools/out/recipes-check.json
```

`wowhead-drops.mjs` reads Wowhead Forever's pages as data: each boss's Drops tab (looted kills and how often each item dropped), each faction's reward list, and the item lists filtered on Source: Drop for world drops. Wowhead shows a "Human Verification" page after a few dozen pages; the tool then waits 15 minutes and tries again, and never tries to answer the check. Pages are cached, so a rerun goes on where it stopped. Data collected in a browser can be used instead: `node tools/loot/wowhead-drops.mjs --import <file.json>`. Without `tools/out/wowhead-drops.json`, `build-loot.mjs` builds from the other sources only.

`foreverdb-files.mjs` downloads the data files listed in `https://foreverdb.net/downloads/addon-manifest.json`. It checks each file's SHA-256 and saves it under `tools/cache/foreverdb-files/<data version>/`. The builders read the newest version with `lua-table.mjs`, which parses the Lua tables as text and never runs them. The ForeverDB website and its `/api/` are not used.

Rules the builders apply:

- **ForeverDB comes first.** These labels in its files decide what is kept:
  - Loot entries labelled `f` (seen in Forever) are kept.
  - Entries labelled `c` (Classic data from the CMaNGOS classic-db) are dropped, and so are the `clue` lists (unconfirmed client clues).
  - Vendor lists without `fv` (not seen in Forever) are dropped.
  - In `Items.lua`, recipe sources labelled Classic are dropped. There, `c` on an item means "changed in Forever".
  - Recipes with a speculation reason (`sp`) and skill levels that are Classic trainer data are dropped.
- **Dungeon Journal: compared only.** With `dungeon-journal-check`, `build-loot.mjs` reads the Journal's `Data/Dungeons.lua` and `Data/SharedLoot.lua` as text and writes `tools/out/dj-check.json`: its drops this build does not list, and the reverse. Nothing from it goes into Loot.lua. Its boss names, NPC IDs and item IDs are only used to find Wowhead pages: a boss our sources miss is added when Wowhead has a Drops tab for its NPC, with Wowhead's drops only.
- **AtlasLoot Continued: leads checked on Wowhead.** AtlasLoot Continued (by Okrah, Lag and many others, with a WoW Forever port) is GPL v2 only, and Encore Essentials is GPL-3.0 because it bundles ForeverDB and QuestieDB data. The two licences can't be combined, so nothing from AtlasLoot is copied. With `atlasloot-check`, `build-loot.mjs` reads `AtlasLootContinued_DungeonsAndRaids/data-forever.lua` as text (`tools/loot/atlasloot-loot.mjs`) and uses each boss's entries as leads. A lead goes into Loot.lua only when Wowhead Forever confirms it: the boss's Wowhead page lists the drop, or the item's Wowhead tooltip names the boss (or, for trash, a mob of that instance). A lead is dropped when Wowhead has 1,000 or more kills of the boss and never saw it. A boss only AtlasLoot lists is added only when Wowhead confirms some of its loot, and an AtlasLoot boss that already has most of its loot listed under another boss here (Olaf of The Lost Dwarves) counts as that boss. AtlasLoot's NPC IDs are never given to bosses here. `tools/out/atlasloot-check.json` lists the confirmed leads, the contradicted ones, the ones Wowhead could not confirm, the ones not fetched from Wowhead yet, and our drops AtlasLoot doesn't list.
  - `atlasloot` (the default, Det 2026-11-21: "AtlasLoot for everything it has, the other sources for the blanks") goes further: a boss AtlasLoot covers shows only AtlasLoot's drops, as confirmed on Wowhead, and they stay under that boss even when they also drop elsewhere. Drops only the other sources tie to that boss are left off it (listed under `notShown`). Shared recipe lists, drop chances, item details, levels, bosses and instances AtlasLoot doesn't cover, world drops, reputations and vendors still come from the other sources.
  - `atlasloot-check` only adds the confirmed leads and keeps everything else.
- **Instances.** An instance ForeverDB has only Classic data for (the Classic raids) is skipped unless a fill-in site lists it. `open = true` marks the instances ForeverDB lists as open.
- **Drop chances** are ForeverDB's drops per looted kill. A chance is written only when ForeverDB gives the number of kills it was measured over. Where ForeverDB has no chance, one is written only when Wowhead Forever names that same boss as the dropper. The Classic chances on foreverchanges.pro are ignored.
- **Own loot only.** A boss's table lists only its own loot: any item that a fill-in site or Wowhead ties to it, or that was seen only in that instance and is bind-on-pickup, a quest item, a recipe, or rare or better. Random and level-range drops (on Wowhead Forever's world-drop lists, or seen in two or more instances) are taken off the bosses; the rare and epic ones are listed as world drops, and the rest are left out. White and grey items (cloth, food, potions, vendor trash) are left off boss and trash tables too, except quest items and recipes (`BOSS_MIN_QUALITY` in build-loot.mjs).
- **Wowhead Forever boss drops** (when collected) add the drops ForeverDB has not seen from a boss (1% or more of looted kills), and replace a drop chance when Wowhead counted at least three times as many kills. A boss tie from a fill-in site is dropped when Wowhead has 1,000 or more kills of that boss and never saw the item. Trash loot that one boss drops in 2% or more of kills moves to that boss.
- **Shared recipe drops.** A profession recipe that drops from bosses in two or more instances is a drop of the whole level range. It is listed once per instance (`recipes`), not under every boss.
- **Reputations and world drops** (when collected): Wowhead Forever's faction rewards fill in factions ForeverDB players have not seen, with standing but no price. World drops are dropped items Wowhead ties to no NPC, boss or instance, rare or better only, no quest items or quest starters, and no enchanting materials (Trade Goods > Enchanting shards and crystals, `isEnchantingMat` in build-loot.mjs); in the window they are World Epics, then World Rares, each by level range.
- **Item details** come from Wowhead Forever. Where Wowhead has none, ForeverDB gives the item's name and quality, and the game fills in the rest at run time. A fill-in item that Wowhead does not know is left out.
- **Credit.** Every generated file starts with ForeverDB's credit line, and `EncoreEssentials_DB/NOTICE.txt` gives its terms: GPL-3.0 with the attribution "Data from ForeverDB.net (https://foreverdb.net)".
- **Reports.** `tools/out/loot-report.json` lists every instance with its boss and item counts, plus what was left out. `tools/out/recipes-report.json` lists the recipe counts and the recipe items that have no Forever source.

`alchemy-forever-70959.json` is the Alchemy output for Forever build 1.60.1.70959.

## 4. Dungeon quests (Node 18+)

```
node tools/quests/build-quests.mjs                    # QuestieDB, then Wowhead Forever -> EncoreEssentials_DB/Data/Quests-*.lua
```

Quests come from QuestieDB with Wowhead Forever filling blanks, through a swappable source layer. See `tools/quests/README.md` for the QuestieDB checkout and the Wowhead step.
