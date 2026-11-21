# Encore Essentials

## 0.1.6

- Encore-Stonks: the item list has iLvl and Req columns (item level and required level) for weapons, armor, consumables, containers, gems, ammo, quivers and quest items. They hide in categories where they mean nothing, like Trade Goods or Recipes. Both sort on click; Req shows red above your level.
- Encore-Stonks: the Filter dropdown beside the Name search is gone. It threw Lua errors; sort by the new level columns instead.

## 0.1.5

- Encore-Stonks: guild sharing works with WoW Forever's two-part names ("Berya Ebonlocke"). The space in the name made every guildmate throw out the login summary offers and accepts as malformed, so nobody ever got a login summary and the sync history stayed empty. Share links from players with such names work again too.
- Encore-Stonks: the first login with this version switches guild sharing on for everyone, once. Turning it off or to receive only afterwards sticks.
- Encore-Stonks: `/stonksync who` asks the guild who runs Encore-Stonks, with their version, sharing setting and last scan. `/stonksync status` lists the guildmates heard from this session, and `/stonksync perf` says which messages were rejected and why.
- Encore Essentials is in the game's Options > AddOns tab, with an Encore-DB and an Encore-Stonks page. General: login message, Open Encore Essentials. Minimap button: show, detach, lock, square. Encore-DB: item icon size, highlighted items, random drops open, split Blackrock Spire, reset window. Encore-Stonks: days of hourly detail, Auctionator history, open beside the auction house, tooltip averages, guild sharing (share, receive only, off), low-end mode, guild sync history. Same settings as the right-click and cogwheel menus.
- `/encore options` opens it, and the minimap button's right-click menu has Options....

## 0.1.4

- Encore-Stonks: Share scan and Share item now really go to the chat you have open, like shift-clicking an item: into the open whisper, party, raid, guild, officer or channel box at the cursor, or the chat you last had open. In 0.1.3 they opened an empty guild box instead, because the game fills a newly opened chat box one frame later and wiped the link. Guild only when your last chat was say, yell or emote, or you have not opened a chat yet this session.

## 0.1.3-beta

- Encore-DB: quests show their rewards: items, reward choices, reputation, XP and money. Exact values come from what the game shows you at quest givers and in your quest log, with QuestieDB and Wowhead Forever filling the rest.
- Encore-Stonks: a Filter button beside the Name search, like the auction house: level range, Uncollected Only, Usable Only and rarity checkboxes. The red cross clears them. The category list uses the auction house colours.
- Encore-DB: items always show at least two side by side, three or four as the window is stretched. Columns that don't fit (level, type, slot) are left out; the item tooltip still has them.
- Encore-Stonks: the graph window has two tabs in its title bar, Graphs and History. History lists every guild sync you received: hourly guild scans, your login summary, and items or scans shared by chat link, with when, from whom, how many prices came in and how many were kept. Columns sort on click; click a shared item to see its graph. Also `/stonksync history`.
- Encore-Stonks: Share scan and Share item put the link into the chat you have open (whisper, party, raid, guild, officer or a channel) instead of always guild chat. With no chat open they use the chat Enter would open, and guild chat when that is say, yell or emote.

## 0.1.2-beta

- Module window: modules show as tiles from left to right, starting a new row after four.
- Encore-DB: data refresh (ForeverDB 2026-11-20, QuestieDB, foreverchanges.pro, Wowhead Forever): 28 instances, 2,926 items, 913 quests, 2,458 recipes.
- Encore-DB: bosses list only their own loot. Random and level-range drops come off the bosses; the rare and epic ones are under World Epics and World Rares.
- Encore-DB: white and grey items are left off boss and trash tables, except quest items and recipes.
- Credits: Wowhead Forever is now credited in NOTICE, README and the in-game credit tooltip.

## 0.1.1

- Minimap button: right-click to unlock and drag it anywhere on screen, lock it, or reattach it to the minimap.
- Minimap button: optional large square style with a resize knob (24 to 72 px).

## 0.1.0

First public release.

- Encore-DB: dungeon loot with drop rates and boss portraits, dungeon quests and quest chains, World Epics and World Rares by level, recipes for every profession, PvP and reputation vendors, Forever-change highlighting.
- Encore-Stonks: hourly auction price history from Auctionator scans with trend, weekday, hour and whole-market charts, docked beside the auction house, with guild price sharing.
