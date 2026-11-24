# Encore Essentials

**A loot, quest and recipe database plus hourly auction price graphs with guild sharing, built for World of Warcraft: Forever.**

Encore Essentials is the addon suite of **Encore**, a Horde guild on the EU PvP realms. Four addons ship together:

| Folder | In-game name | What it does |
|---|---|---|
| `EncoreEssentials/` | Encore Essentials | Core: settings, the `/encore` command, the minimap crest button and the Encore Essentials window that opens the modules. Always loaded. |
| `EncoreEssentials_DB/` | Encore-DB | Dungeon loot, dungeon quests, world epics and rares, recipes, PvP and reputation vendors. Loads only when you open it. |
| `EncoreEssentials_Stonks/` | Encore-Stonks | Auction price history by date, weekday and hour from Auctionator scans, shared with your guild. |
| `EncoreEssentials_QoL/` | Encore-QoL | Quality of life, interface, visual and combat options, battleground timers for Alterac Valley and Arathi Basin, and one-button fishing. Every feature starts off. |

Open everything from the Encore crest on the minimap, the game's addon list button, or `/encore`.

## Highlights

### Encore-DB
- **Loot from WoW Forever itself.** Drops, drop rates, vendors and recipe sources are the ones players saw in Forever. Classic and emulator data is left out.
- **28 dungeons**, Forever's new ones included (The Hall of Thanes, Ruins of Lordaeron, City of Dalaran, Drowned City, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold, Shaper's Terrace and others), grouped by level range. Blackrock Spire can be split into Lower and Upper.
- **Boss portraits with level badges** coloured like the target frame against your level, a skull for boss-level mobs, and the **silver dragon frame for rare spawns**.
- **Drop rates per looted kill**, a fold-out list of each boss's random drops, and trash loot.
- **Dungeon quests and quest chains**, read top to bottom with the steps out in the world, marked *done* or *in your log*, with *Hide finished*, a faction filter and a map pin to where each quest starts and ends.
- **Open World:** World Epics and World Rares by required level (1-10 up to 51-60).
- **Professions:** every recipe by skill bracket with difficulty colours; click one for reagents, trainer cost, vendors (with a map pin), drops, quests and the reputation it needs.
- **PvP and reputation vendors** seen in Forever, with the standing or PvP rank and price of every item: Arathi Basin, Warsong Gulch, Alterac Valley, the honor rewards (armor, weapons, insignia, war mounts) and the reputation factions.
- **Collections:** mounts, companions, tabards and legendaries with where each comes from, and item sets (PvP, Zul'Gurub, Ahn'Qiraj and others) with their pieces.
- **Rogue poisons** in the Collections tab under Class skills, by the level you learn them.
- **Highlight Forever changes** marks what is new or changed in Forever, with teal counters per dungeon and boss; **Forever only** hides the rest.
- Search across all loot and recipes, quality and slot filters, three icon sizes, a resizable window, click-to-sort columns, coin-icon prices and tooltips that follow the cursor.

### Encore-Stonks
- **Hourly price history.** Auctionator keeps one price per item per day; Stonks records every scan by the hour.
- **Trend, By weekday, By hour and Whole market** charts, with 3, 7 and 14-day moving averages and bars labelled with their % above or below normal.
- **Docks beside the auction house** and follows your selection in the Browse, Bids and Auctions tabs, the sell slot and Auctionator's Shopping and Selling tabs.
- **Auction-house-style browser** with categories and your Auctionator shopping lists.
- **Item tooltips** with the 3, 7 and 14-day averages.
- **Guild price sharing:** one claimed scan per hour, a login summary of what changed while you were away (AFK players send first), and *Share item* / *Share scan* chat links that guildmates import only after clicking and confirming. At most 400 bytes a second, nothing in combat or instances, only item, price, quantity and hour leave your client. See [`docs/stonks-guild-sharing.md`](docs/stonks-guild-sharing.md).

### Encore-QoL
- **Everything starts off.** Turn on only what you want, in one resizable window laid out like the game's Options: a tree of tabs and sections on the left (Quality of life, Interface, Visual & audio, Combat, PvP, Professions), a search box and an Overview.
- **Knows your other addons.** When Enhance QoL, Leatrix Plus, BetterFishing, KelaGraphics, ErrorMonster, MinimapButtonBag, Bartender4 and others already do something, its switch is locked and names that addon. Encore never changes their settings; turn it off there and Encore's unlocks.
- **Who rolled what:** a small window beside each group loot roll lists who picked Need, Greed or Pass, their rolls, the winner and who is still choosing.
- **Action bars 1 to 6, pet and stance bars:** show always, never, in or out of combat, on mouseover or by your own rules (target, casting, group, fishing pole equipped, mounted...), with alpha and fade time. Button text: keybind, macro name, count and cooldown font, size, outline, colour and position.
- **Minimap and frames:** square minimap, button drawer, wheel zoom, movers for frames the game keeps fixed, class colours, chat and tooltip tidy-ups.
- **Visual & audio:** graphics sliders past the menu caps (ground clutter, view distance, particles, weather), cursor ring, mute sounds, max camera distance.
- **PvP:** Alterac Valley and Arathi Basin frames in four styles each, with win prediction, capture timers, generals' health and officers, and a tooltip on every icon and bar. Right-click to lock or scale, Preview outside a battleground, timers shared with your group and with Capping users.
- **One-button fishing:** one key casts and reels in, louder splash, auto loot, pole and lure, a fishing bar and a sortable catch log.

### Minimap button
The Encore crest sits under the day and night indicator at the same size at any resolution or UI scale, and minimap button collectors (EnhanceQoL's button sink, MinimapButtonBag) leave it alone.

## Install

From CurseForge: install **Encore Essentials** with the CurseForge app, or download the zip and unzip it into your WoW Forever folder's `Interface\AddOns`, so that `Interface\AddOns\EncoreEssentials`, `EncoreEssentials_DB`, `EncoreEssentials_Stonks` and `EncoreEssentials_QoL` exist. Encore-Stonks needs [Auctionator](https://www.curseforge.com/wow/addons/auctionator) for scanning.

## Commands

| Command | What it does |
|---|---|
| `/encore` | List the commands |
| `/encore db` | Open Encore-DB |
| `/encore stonks` | Open Encore-Stonks |
| `/encore qol` or `/eqol` | Open Encore-QoL (`/eqol check` checks your other addons again, `/eqol preview` shows the battleground frames) |
| `/encore minimap` | Show or hide the minimap button |
| `/encore info` | Addon version, game build and saved-data details |
| `/encore reset` | Restore default settings |
| `/stonksync` | Guild price sharing: `share`, `receive`, `off`, `status`, `perf`, `lowend`, `mute`, `link` |

## Install for development (Windows)

Link the repository folders into the game instead of copying them, so every `git pull` updates the addon.

### Quick setup (PowerShell)

With [Git for Windows](https://git-scm.com/download/win) installed, run these two commands in PowerShell:

```powershell
git clone https://github.com/Detroph/Encore-Essentials.git C:\dev\Encore-Essentials
powershell -ExecutionPolicy Bypass -File C:\dev\Encore-Essentials\tools\setup-dev.ps1
```

The script finds your `_forever_` folder (or asks for it), creates `Interface\AddOns` if needed and links all three addon folders. It never replaces an existing addon folder. Run it again any time; it also pulls the latest version.

### Manual setup

1. Clone the repository somewhere outside the game folder, for example `C:\dev`:
   ```bat
   cd C:\dev
   git clone https://github.com/Detroph/Encore-Essentials.git
   ```
2. Find your WoW Forever game folder: the one that contains both `Interface` and `WTF`. In the Battle.net app, select WoW Forever, open the gear menu next to Play and choose **Show in Explorer**.
3. Open **Command Prompt** (not PowerShell) and create one link per addon folder. Replace `<FOREVER>` with the folder from step 2:
   ```bat
   mklink /J "<FOREVER>\Interface\AddOns\EncoreEssentials" "C:\dev\Encore-Essentials\EncoreEssentials"
   mklink /J "<FOREVER>\Interface\AddOns\EncoreEssentials_DB" "C:\dev\Encore-Essentials\EncoreEssentials_DB"
   mklink /J "<FOREVER>\Interface\AddOns\EncoreEssentials_Stonks" "C:\dev\Encore-Essentials\EncoreEssentials_Stonks"
   mklink /J "<FOREVER>\Interface\AddOns\EncoreEssentials_QoL" "C:\dev\Encore-Essentials\EncoreEssentials_QoL"
   ```
   If `Interface\AddOns` does not exist yet, create it first. Junctions (`/J`) need no administrator rights.
4. Start the game. On the character screen, open **AddOns** and check that *Encore Essentials*, *Encore-DB* and *Encore-Stonks* are listed and enabled.

### Check that it works

In game:

- `/encore` lists the commands.
- `/encore info` shows the addon version and the game's Interface number. If it reports a mismatch, change `## Interface:` in all three `.toc` files to the number shown, then **fully restart the game** (`/reload` does not re-read `.toc` files).
- `/encore db` opens the Encore-DB window.
- `/encore stonks` opens the Encore-Stonks browser.
- The Encore crest button sits on the minimap ring just below the day/night indicator, at the same size, and keeps that size at any resolution or UI scale. Left-click it to open the **Encore Essentials window** in the middle of the screen, which lists the modules. Right-click it for options: addon info, the login-message setting and *Hide minimap button*. `/encore minimap` shows or hides it. The game's addon list button on the minimap (Addon Compartment) also opens the window.
- Right-click the button and choose *Unlock button* to drag it anywhere on screen, or *Use large square button* for a larger rounded-square version. While it's unlocked, the square button has a resize knob at its bottom-right corner (up to 72 px, the width of two standard icons). Right-click again to *Lock button position*, switch between round and square, or *Reattach to minimap*. These settings are saved account-wide.
- The button is not a LibDBIcon button and is not attached to the minimap frame, so minimap button collectors (EnhanceQoL's button sink, MinimapButtonBag) do not pick it up.

After changing Lua files, `/reload` is enough. After changing `.toc` files, restart the game.

## Saved data

`EncoreEssentialsDB` (account-wide) is written to `<FOREVER>\WTF\Account\<ACCOUNT>\SavedVariables\EncoreEssentials.lua` when you log out or `/reload`. Changes since the last logout or reload are lost if the game crashes.

`EncoreStonksDB` (account-wide, `SavedVariables\EncoreEssentials_Stonks.lua`) holds Encore-Stonks' price samples per realm. See below.

## Encore-Stonks and Auctionator

Auctionator keeps **one price per item per day** (the day's lowest buyout, the highest "lowest buyout" and the most units seen) for **21 days** (its `price_history_days` setting), with no time of day. That is enough for a rough weekday chart but not for hours.

Encore-Stonks therefore hooks `Auctionator.Database:SetPrice`, which every Auctionator full scan and search goes through, and keeps its own copy: per item per hour, the lowest unit buyout and the most units on sale. Auctionator's data is read live and never copied. Hourly samples are kept for 7 days (14 or 30 in the cogwheel menu); older ones are folded into 31 running totals per item (7 weekdays, 24 hours, each a count and a sum of log(price / normal)), so the weekday and hour charts keep learning for months while the saved data stays bounded. For 7,000 items: about 0.6 MB of totals plus about 0.55 MB of hourly detail per daily full scan (1.2 MB at one scan a day, 2.3 MB at three). Auctionator's own daily history fills in days Stonks has no sample for (switchable in the cogwheel menu).

- **Statistics** (like Auctioneer's Stat-Simple, Stat-StdDev and Stat-Histogram, kept as running numbers rather than raw scans, about 50 bytes per item): 3, 7 and 14-day moving averages, median and middle-50% range from a price histogram in 4% steps, mean and standard deviation weighted towards the last month. Each day counts once with its lowest buyout; prices more than 5x off the 14-day average are ignored.
- **Two windows.** `/encore stonks` opens a browser laid out like the auction house: a name search on top, the auction house categories on the left (Weapons, Armor with Plate/Mail/Leather/Cloth, Containers, Consumables, Trade Goods, Ammo, Recipes, Quest Items, Miscellaneous; the game's own list once the auction house has been opened, item classes before that) followed by your Auctionator shopping lists, and the items with price history on the right (last price, 7-day average, trend). The graph opens in its own panel to the right, which says "Select an item or a shopping list to display historic data." until something is picked.
- **Follows your selection.** At the auction house the graph panel docks to its right and shows whatever item you select: in the auction house's Browse, Bids and Auctions tabs (and the sell slot), in Auctionator's Shopping and Selling tabs, or in the Stonks browser. Searching an Auctionator shopping list shows the whole list with each item's trend; click an item to see its graph. The panel closes with the auction house (cogwheel menu to turn docking off).
- **Item tooltips:** every item tooltip with Stonks prices (bags, auction house, chat links) shows the 3, 7 and 14-day averages and the last price's % against each (cogwheel menu to turn off).
- **Trend:** price line (teal: Stonks samples with the hour, copper: Auctionator's daily lows) with a gold 3, 7 or 14-day moving average (buttons under the graph), the normal price (median) and the units on sale.
- **By weekday / By hour:** the typical price at each weekday or hour on a gold axis, each bar labelled with its % above or below the item's normal price, averaged on a log scale so one odd listing can't skew a bar. Thin data is drawn fainter, and the tooltip gives the sample count.
- **Whole market:** every item's weekday and hour profile averaged, each item counted once: when is the auction house as a whole cheap or expensive.

Weekdays and hours use the computer's time zone. Only hours you actually scan in get data, so scanning at different times of day fills the hour chart in.

## Repository layout

```
EncoreEssentials/        core addon (TOC, Lua, Media/*.tga textures)
EncoreEssentials_DB/     Encore-DB module (load on demand)
EncoreEssentials_Stonks/ Encore-Stonks module (auction price graphs, records Auctionator scans)
docs/                    guild sharing design notes and the Encore-DB window mock-up
assets/                  Encore crest and icons (SVG sources and PNG exports)
tools/                   data-extraction scripts for the Encore-DB database
```

## Data sources for Encore-DB

**Data from ForeverDB.net (https://foreverdb.net).** ForeverDB.net is the main source. Encore-DB is built from the data files of its addon, which are GPL-3.0 with an attribution term. The generated files keep ForeverDB's credit line, and [`EncoreEssentials_DB/NOTICE.txt`](EncoreEssentials_DB/NOTICE.txt) gives the terms.

- **Bosses, loot and drop rates:** ForeverDB's loot data. It covers instances and bosses in the game client's order, with NPC IDs. Encore-DB keeps only the drops that players' ForeverDB addons saw in WoW Forever, with drop rates per looted kill. ForeverDB's Classic data and its unconfirmed client clues are left out. Random world drops seen from a boss go in a separate list.
- **Reputation and PvP vendors:** ForeverDB's vendor lists, only for vendors that players saw in Forever. Warsong Gulch, Alterac Valley, honor rewards and reputation rewards ForeverDB has not seen come from Wowhead Forever.
- **Collections, item sets and rogue poisons:** Wowhead Forever. AtlasLoot Continued's lists are read only to know which items to look up; an item is listed only when Wowhead Forever shows a source for it, and none of AtlasLoot's data is included. World events are left out until they run in Forever.
- **Recipes:** ForeverDB's recipe data, taken from the Forever client. Each recipe has its reagents, crafted item and skill colours, and how it is learned: trainer, recipe item or automatic. Trainer costs are included where they were seen at Forever trainers, and so are Merchant's Favor costs. Recipes ForeverDB marks as speculation (Season of Discovery leftovers) are left out.
- **Recipe item sources:** the vendors, drops and quests that ForeverDB players saw in Forever, plus the reputation the item needs. Sources ForeverDB labels as Classic are left out. Vendor positions come only from vendors seen in Forever.
- **Filling the gaps:**
  - The dungeon pages of [foreverchanges.pro](https://foreverchanges.pro/dungeons) add bosses, items and instances that ForeverDB has no Forever drops for yet.
  - The item pages of foreverchanges.pro add recipe sources that ForeverDB lacks.
  - Its Classic drop chances and "in Classic" entries are not used.
  - [Wowhead Forever](https://www.wowhead.com/forever) gives item details (name, quality, icon, slot and levels), boss drops and drop chances ForeverDB has not seen, reputation rewards, world drops (rare and epic only) and quest details QuestieDB leaves blank. Every recipe is also checked against it.
  - AtlasLoot Continued (by Okrah, Lag and many others, with a WoW Forever port) decides which drops each boss it covers shows: the build looks up each of its drops on Wowhead Forever and lists the ones Wowhead confirms. Everything else (drop chances, recipes, other bosses and instances) comes from the sources above. None of AtlasLoot's data is included, since it is GPL v2 only and Encore-DB is GPL-3.0.
- **Boss levels:** [QuestieDB](https://github.com/Questie/QuestieDB) (GPL-3.0), its WoW Forever NPC data, for the level on each boss portrait. Bosses without a known level show none.
- **Recipe data from the client:** the WoW Forever client's own data tables (product `wowf` on [wago.tools](https://wago.tools/)), compared with the Classic Era client, for the profession tools in `tools/`.
- **Boss portraits:** pictures from Dungeon Journal (ForeverDungeonJournal) by Exehn, photographed from the game's own portraits. They are renamed to each boss's NPC ID by `tools/import-dj-portraits.mjs`. Bosses without a picture get the game's live portrait.
- **Dungeon quests:** [QuestieDB](https://github.com/Questie/QuestieDB) by the Questie team (GPL-3.0), its WoW Forever database. That is Questie's Classic quest data, originally built from CMaNGOS/VMaNGOS data, converted to Forever's maps and corrected with Forever layers: QuestieTrace recordings made in Forever and hand-written Forever fixes.
- WoW Forever is its own game. No Vanilla server or emulator databases (CMaNGOS, VMaNGOS, AzerothCore, TrinityCore) are used, and that includes the CMaNGOS-derived parts of ForeverDB's files. The one exception is QuestieDB: its Forever data starts from Questie's Classic data, which is built from CMaNGOS, with Forever corrections on top, and Encore-DB takes quests and boss levels from it.

See [`tools/README.md`](tools/README.md) for how the data is extracted.

## License

Copyright (C) 2026 the Encore Essentials authors. Licensed under GPL-3.0: see [`LICENSE`](LICENSE). Encore-DB's quest data is QuestieDB's (GPL-3.0), and its other data files carry ForeverDB.net's attribution term (GPL-3.0 section 7(b)): see [`EncoreEssentials_DB/NOTICE.txt`](EncoreEssentials_DB/NOTICE.txt). World of Warcraft and its content are trademarks and copyrights of Blizzard Entertainment.
