# Encore Essentials

Encore's addon toolkit for **World of Warcraft: Forever**.

| Folder | In-game name | What it does |
|---|---|---|
| `EncoreEssentials/` | Encore Essentials | Core: saved settings, the `/encore` command, the minimap button, the Encore Essentials window, shared art. Always loaded. |
| `EncoreEssentials_DB/` | Encore-DB | Loot and recipe database. Loads only when opened with `/encore db`. *Window not built yet.* |
| `EncoreEssentials_Stonks/` | Encore-Stonks | Auction price graphs (over time, by weekday, by hour of day) from Auctionator scans. Loads with the game so it can record every scan; open it with `/encore stonks` or from the Encore Essentials window; at the auction house its graph docks beside the auction house. |

Status: **0.1.0, skeleton.** The core loads and answers `/encore`; Encore-DB loads on demand and prints a placeholder message. The planned Encore-DB window is the clickable mock-up in [`docs/mockup/encore-db-mockup.html`](docs/mockup/encore-db-mockup.html).

## Install for development (Windows)

Link the repository folders into the game instead of copying them, so every `git pull` updates the addon.

### Quick setup (PowerShell)

With [Git for Windows](https://git-scm.com/download/win) installed, run these two commands in PowerShell:

```powershell
git clone https://github.com/Detroph/Encore-Essentials.git C:\dev\Encore-Essentials
powershell -ExecutionPolicy Bypass -File C:\dev\Encore-Essentials\tools\setup-dev.ps1
```

The script finds your `_forever_` folder (or asks for it), creates `Interface\AddOns` if needed and links both addon folders. It never replaces an existing addon folder. Run it again any time; it also pulls the latest version.

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
   ```
   If `Interface\AddOns` does not exist yet, create it first. Junctions (`/J`) need no administrator rights.
4. Start the game. On the character screen, open **AddOns** and check that *Encore Essentials* and *Encore-DB* are listed and enabled.

### Check that it works

In game:

- `/encore` lists the commands.
- `/encore info` shows the addon version and the game's Interface number. If it reports a mismatch, change `## Interface:` in both `.toc` files to the number shown, then **fully restart the game** (`/reload` does not re-read `.toc` files).
- `/encore db` loads Encore-DB and prints its placeholder message.
- The Encore crest button sits on the minimap ring just below the day/night indicator, at the same size, and keeps that size at any resolution or UI scale. Left-click it to open the **Encore Essentials window** in the middle of the screen, which lists the modules (for now Encore-DB). Right-click it for options: addon info, the login-message setting and *Hide minimap button*. `/encore minimap` shows or hides it. The game's addon list button on the minimap (Addon Compartment) also opens the window.
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
docs/mockup/             interactive HTML mock-up of the Encore-DB window
assets/                  Encore crest and icons (SVG sources and PNG exports)
tools/                   data-extraction scripts for the Encore-DB database
```

## Data sources for Encore-DB

**Data from ForeverDB.net (https://foreverdb.net).** ForeverDB.net is the main source. Encore-DB is built from the data files of its addon, which are GPL-3.0 with an attribution term. The generated files keep ForeverDB's credit line, and [`EncoreEssentials_DB/NOTICE.txt`](EncoreEssentials_DB/NOTICE.txt) gives the terms.

- **Bosses, loot and drop rates:** ForeverDB's loot data. It covers instances and bosses in the game client's order, with NPC IDs. Encore-DB keeps only the drops that players' ForeverDB addons saw in WoW Forever, with drop rates per looted kill. ForeverDB's Classic data and its unconfirmed client clues are left out. Random world drops seen from a boss go in a separate list.
- **Reputation and PvP vendors:** ForeverDB's vendor lists, only for vendors that players saw in Forever.
- **Recipes:** ForeverDB's recipe data, taken from the Forever client. Each recipe has its reagents, crafted item and skill colours, and how it is learned: trainer, recipe item or automatic. Trainer costs are included where they were seen at Forever trainers, and so are Merchant's Favor costs. Recipes ForeverDB marks as speculation (Season of Discovery leftovers) are left out.
- **Recipe item sources:** the vendors, drops and quests that ForeverDB players saw in Forever, plus the reputation the item needs. Sources ForeverDB labels as Classic are left out. Vendor positions come only from vendors seen in Forever.
- **Filling the gaps:**
  - The dungeon pages of [foreverchanges.pro](https://foreverchanges.pro/dungeons) add bosses, items and instances that ForeverDB has no Forever drops for yet.
  - The item pages of foreverchanges.pro add recipe sources that ForeverDB lacks.
  - Its Classic drop chances and "in Classic" entries are not used.
- **Boss levels:** [QuestieDB](https://github.com/Questie/QuestieDB) (GPL-3.0), its WoW Forever NPC data, for the level on each boss portrait. Bosses without a known level show none.
- **Recipe data from the client:** the WoW Forever client's own data tables (product `wowf` on [wago.tools](https://wago.tools/)), compared with the Classic Era client, for the profession tools in `tools/`.
- **Boss portraits:** pictures from Dungeon Journal (ForeverDungeonJournal) by Exehn, photographed from the game's own portraits. They are renamed to each boss's NPC ID by `tools/import-dj-portraits.mjs`. Bosses without a picture get the game's live portrait.
- **Dungeon quests:** [QuestieDB](https://github.com/Questie/QuestieDB) by the Questie team (GPL-3.0), its WoW Forever database. That is Questie's Classic quest data, originally built from CMaNGOS/VMaNGOS data, converted to Forever's maps and corrected with Forever layers: QuestieTrace recordings made in Forever and hand-written Forever fixes.
- WoW Forever is its own game. No Vanilla server or emulator databases (CMaNGOS, VMaNGOS, AzerothCore, TrinityCore) are used, and that includes the CMaNGOS-derived parts of ForeverDB's files. The one exception is QuestieDB: its Forever data starts from Questie's Classic data, which is built from CMaNGOS, with Forever corrections on top, and Encore-DB takes quests and boss levels from it.

See [`tools/README.md`](tools/README.md) for how the data is extracted.

## License

Copyright (C) 2026 the Encore Essentials authors. Licensed under GPL-3.0: see [`LICENSE`](LICENSE). Encore-DB's quest data is QuestieDB's (GPL-3.0), and its other data files carry ForeverDB.net's attribution term (GPL-3.0 section 7(b)): see [`EncoreEssentials_DB/NOTICE.txt`](EncoreEssentials_DB/NOTICE.txt). World of Warcraft and its content are trademarks and copyrights of Blizzard Entertainment.
