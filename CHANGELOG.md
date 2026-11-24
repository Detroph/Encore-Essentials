# Encore Essentials

## Unreleased

- Encore-DB: Professions are sorted by what each recipe makes. Under All recipes, the middle list now has the recipe types (Weapons - Daggers, Axes, Maces, Swords ...; Armor - Head, Shoulder, Chest ...; Shields, Enhancements, Enchants by slot, Flasks, Elixirs, Potions, Transmutes, Explosives, Parts, Bags, Materials, Misc and more), then the item sets the profession makes, then the skill brackets as before. Weapons show one-handed and two-handed side by side, armour shows cloth, leather, mail and plate side by side, and potions show healing and mana apart from the rest. Each recipe still shows its skill-up levels in orange, yellow, green and grey.
- Encore-DB: Reputations: a faction's rewards are split into groups (Armor, Weapons, Recipes, Consumables ...) under headings you can close and open again, for every standing. A group you close stays closed when you look at another faction.

## 0.2.3

- Encore-DB: Collections > Item sets are listed by class (Warrior, Paladin, Hunter, Rogue, Priest, Shaman, Mage, Warlock, Druid), each with its class icon, and every class shows all its sets: PvP, Zul'Gurub, Ruins and Temple of Ahn'Qiraj. Each set says where it comes from. Sets for no single class stay under Other sets. Dungeon and tier sets will slot in the same way when they are added.
- Encore-Stonks: Auctionator's Auction price line in item tooltips shows when that price was scanned, in brackets: "Auction  12g 30s (22 Nov 14:05)". The time comes from Encore-Stonks' own record of each scan. Prices from before Stonks saw them show the day only, from Auctionator's history. On by default; turn it off in Options > AddOns > Encore Essentials > Encore-Stonks ("Show scan time on Auctionator's price"). Auctionator's own tooltip is otherwise unchanged, and nothing is changed if Auctionator's tooltip can't be found.

## 0.2.2

- Encore-Stonks: WoW Forever's launch week (4 to 11 November 2026) is left out of every average: the 3, 7 and 14-day averages, the median and mean, the normal price, the weekday and hour bars, the saved summaries and what you send to the guild. The prices stay saved and still show on the trend; hovering one says it is left out.
- Encore-Stonks: once, on the first login with this version, Stonks redoes its saved statistics and summaries without that week. Nothing is deleted.
- Encore-Stonks: hovering a point on the graph shows the year too ("Tuesday 10 Nov 2026").

## 0.2.1

- Encore-Stonks: login summaries work. On WoW Forever the game gives the addon your first name and surname apart ("Berya", "Ebonlocke") while guild messages carry the whole name ("Berya Ebonlocke"), and Stonks only used the first name. So every offer meant for you was ignored, guildmates never started sending when you picked them, and your own guild messages came back to you as if from a guildmate. Stonks now uses the whole name. Both sides need this version: the player logging in and the guildmate who sends.
- Encore-Stonks: an item with incomplete averages no longer stops a login summary you are sending halfway.

## 0.2.0

- Encore-DB: the PvP tab has Warsong Gulch (Warsong Outriders, Silverwing Sentinels) and Alterac Valley (Frostwolf Clan, Stormpike Guard) rewards by standing, and the honor rewards: armor, Grand Marshal's and High Warlord's weapons, insignia and war mounts, each with its price.
- Encore-DB: reputation rewards that were missing (Argent Dawn, Cenarion Circle, Zandalar Tribe and others) are added to their faction, with the standing they need where Wowhead Forever shows one.
- Encore-DB: the Collections tab is open. Mounts, companions, tabards and legendaries, grouped by vendors, quests, drops and crafted, each with where it comes from. Item sets: PvP sets, Zul'Gurub, Ruins and Temple of Ahn'Qiraj and other sets, with their pieces. Search finds these items too.
- Encore-DB: rogue poisons are in the Collections tab under Class skills, by the level you learn them at the rogue trainer (not under Professions).
- Everything new comes from Wowhead Forever, and only items Wowhead Forever shows a source for in WoW Forever are listed. AtlasLoot Continued's lists were only used to know which items to look up. World events stay out until they run in WoW Forever.
- Encore-Stonks: the sync history has two big tabs, Received and Sent. Sent lists what you sent to the guild: your hourly scans (to Guild), login summaries you sent to a guildmate, and items or scans you shared by chat link, with the same filters, sortable columns and tooltips as Received.
- Encore-Stonks: the sync history shows how much data went in or out: cards for today, the last 7 days and the last 30 days, and a bar per day for the last 30 days (hover a bar for that day). Both lists have a Size column. Sizes are the addon messages as they go over the wire, in B, KB or MB.
- Encore-Stonks: Clear (Shift-click) empties only the tab you're on.

## 0.1.9

- Encore-Stonks: fixes the Lua error "Browser.lua:143: attempt to call a nil value" when opening the Stonks browser in 0.1.8. The category list asked for the item list before the function that builds it was set up.
- Encore-Stonks: guild sync work (receiving a sync, the login summary) uses its few milliseconds per frame as meant. Before, it paused after every step, so big syncs took longer than needed.

## 0.1.8

- Encore-Stonks: prices seen at the neutral auction houses (Booty Bay, Gadgetzan, Everlook) are no longer recorded, so they don't pull your faction's averages up. Auctionator still keeps its own daily prices from there.
- Encore-Stonks: the browser opens without freezing. Each item's last price, 7- and 14-day averages and days are kept as a small saved summary, so opening the list no longer works out every item's price history. Summaries that are out of date (new prices, a guild sync, a new day) still show and are refreshed in the background a few milliseconds per frame, then the list redraws; the full history is untouched. About 20 seconds after login every item is brought up to date in the background.
- Encore-Stonks: the built list is reused when you reopen the browser, until new prices come in or you change the search, category or sort.
- Encore-Stonks: only the rows on screen ask the game for item names and info (all items only while searching, sorting by name or showing a shopping list). Sample and Auctionator day counts are worked out when you hover an item. When item info arrives, only the visible rows redraw.
- Encore-DB: World Rares and World Epics no longer list enchanting materials (Small and Large Glimmering, Glowing and Brilliant Shards, Nexus Crystal). They come from disenchanting, not from mobs. The data tool leaves them out on every refresh.
- Encore-Stonks: a Request sync button at the bottom left of the sync history (also `/stonksync request`) asks the guild for your login summary again, like logging in: one guildmate whispers you the prices that changed since your last summary. Once an hour; the button shows the time left, and says so when nobody has newer prices.
- Encore-Stonks: the sync history shows every login summary attempt, also one where the guildmate offered but nothing arrived. Guildmates still on 0.1.4 or older answer the login request but can't send to names with a space, so the login summary now prefers guildmates on this version, waits a little longer when only an old version answered, and doesn't ask a guildmate who never delivered again that session.

## 0.1.7

- Encore-Stonks: the item list shows 100 items per page (was the first 500), with arrows at the bottom right to page through. Sorting by price, name or days orders the whole list. iLvl and Req sort only the page you're on, so the game no longer lags looking up item info for every item.
- Encore-DB: item lists with two to four items side by side fill down each column first, then the next column, so a sorted list reads top to bottom in column 1, then column 2 and on.

## 0.1.6

- Encore-Stonks: fixes the Lua error "Browser.lua:188: attempt to call a nil value" when opening the Stonks browser in 0.1.5. The new iLvl and Req columns called GetItemInfo, which WoW Forever only has as C_Item.GetItemInfo. Share links had the same slip when naming the item.

## 0.1.5

- Encore-DB: boss loot follows AtlasLoot Continued: each boss shows the drops AtlasLoot lists for it that Wowhead Forever confirms, plus confirmed drops from summoned bosses (Valthalak, Isalien, Mor Grayhoof, Kormok), the Drowned City and the Ring of Law. About 470 drops that AtlasLoot doesn't list under a boss are gone from it. Drop chances, bosses AtlasLoot doesn't cover, recipes, world drops, reputations, vendors and quests come from the same sources as before.
- Encore-Stonks: the item list has iLvl and Req columns (item level and required level) for weapons, armor, consumables, containers, gems, ammo, quivers and quest items. They hide in categories where they mean nothing, like Trade Goods or Recipes. Both sort on click; Req shows red above your level.
- Encore-Stonks: the Filter dropdown beside the Name search is gone. It threw Lua errors; sort by the new level columns instead.
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
