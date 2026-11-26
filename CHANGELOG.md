# Encore Essentials

## Next (not released yet)

- New module Encore-Professions: a levelling guide beside the profession window. The round Encore button by the skill bar turns it on or off (remembered for the account); while it is on, the guide opens with the profession window, says "Select a profession" until one is shown, then shows that profession's route. Crafting professions (First Aid and Cooking too) get a route of trainer recipes and vendor patterns bought for gold only (no drops, quests, reputation or Merchant's Favor, like What's Training?), Cheapest or Fewest crafts, with what to make now and its reagents (in your bags and bank, price each), the next trainer, pattern vendor, Expert book or Artisan quest with a waypoint, and every step in a sortable list. Prices: the last Auctionator scan, the Encore-Stonks 7-day average when a scan is more than half off it, vendor reagents at the vendor's price (learned at every merchant). Working Overtime (Legacy talent) is read from your tree and can be set by hand; it adds 4% per point to yellow and green chances. The route is planned once and changes only with Recalculate (or a new mode or Working Overtime setting); it warns when it is over 3 days old or reagent prices moved more than 15%. The Auctionator shopping list "Encore: <profession>" holds the auction reagents still missing for the next 3 steps. Mining and Herbalism show the best, 2nd and 3rd zone for the nodes that still give skill-ups, with Show nodes (turns on GatherLite's minimap and world map markers; greyed out with "Requires GatherLite" without it); Skinning the zones with skinnable beasts and their levels; Fishing zones by level with their catches, the Expert book and Artisan quest, and an Open Encore-QoL Fishing button. /eprof turns it on or off, /eprof recalc plans again. Data built by tools/professions/build.py from Encore-DB (ForeverDB), What's Training? (MIT), QuestieDB, GatherLite (MIT) and SkillUp Forever (GPL-3.0-or-later).
- Encore: setup window. It lists the Encore modules as tiles with a few lines on what each one does, and clicking a tile turns that module off or back on (for all characters, or only the one you play). Done closes it when nothing changed; Reload UI applies the change with one reload. It opens on the first login after installing Encore, and once on the first login after 0.2.6 for players who already have it, in place of What's new (the release notes show inside it). /encore setup and Options > AddOns > Encore Essentials > Choose modules open it again.
- Encore-PvP, Encore-Alts and Encore-Professions get their own Encore icons (shield, character cards, anvil) in the Encore window and the game's addon list.
- Encore-QoL: settings that change a game option for a moment (the fishing sound boost, auto loot while fishing) now remember the original value in saved variables and put it back at logout and on the next login. Before, a crash or /reload while fishing could leave music and ambience at 0.
- Encore-QoL: every game option Encore-QoL changes keeps its original value across sessions, so turning a feature off later still restores your own setting.
- Encore-QoL: battleground timers (Alterac Valley, Arathi Basin) now work on clients in other languages. The herald's lines are read by faction and by the order of events instead of English words; Arathi Basin's bases have German, French and Spanish names built in, and every client learns its own map labels. New command /eqol bgpoi lists the map labels and how they are matched.
- Encore: /encore reset restores default settings only. Noted quest rewards are kept; /encore forgetquests clears them.
- Encore: a short "What's new" window opens once on the first login after an update. /encore whatsnew shows it again.
- Encore-QoL: self-test. In beta versions it runs a few seconds after login and opens a window listing any Lua error, blocked action, addon that didn't load, mixed Encore versions, broken feature or setting; errors later in the session open it again. /eqol selftest runs it in any version. It only reads, never changes a setting.
- Encore-DB: opens on the dungeon you are in, and remembers the last dungeon and boss you looked at. Search waits until you stop typing. The empty World Events tab is gone until WoW Forever runs events.
- All Encore windows share one look: borders in Encore-DB and Encore-Stonks keep every edge visible at small UI scales, like Encore-QoL's. The Encore title font now lives in EncoreEssentials (saved font choices move with it).
- Tooltips on the minimap button and Encore-DB recipe icons follow the mouse; the "click to sort" tooltip on column headers is gone.
- The "Encore Essentials loaded" chat line is off for new installs. /encore help lists every module's commands.
- Encore-DB: item tooltips say where an item drops (boss and dungeon with the drop chance), who sells it, or that it is a world drop, up to three places. Off by default: turn on Show where items drop in Options > AddOns > Encore Essentials. Works once Encore-DB is loaded; Load Encore-DB at login (off) makes it work from the start.
- Encore-DB: new AH column in item lists with Encore-Stonks' 7-day average price, sortable like every column (Options > AddOns > Encore-DB to turn it off).
- Encore: the main window shows what each module is doing (Encore-Stonks recording or missing Auctionator, how many Encore-QoL features are on or have errors, whether Encore-DB is loaded). When a guild member has a newer full release, you get one chat line and the main window says so.
- Wishlist: Alt-click any item in Encore-DB to wish for it (a gold star marks it; new Wishlist tab lists them by where they drop, click one to go there). Encore tells you when a wished item comes up for a roll or is in loot (raid warning and sound), is linked in chat, or Encore-Stonks sees it at the auction house, and its tooltip says it is on your list. Options > AddOns > Encore Essentials > Wishlist alerts.
- Encore-DB: profession lists get a Profit column: the product's AH price (times how many one craft makes) minus its reagents at AH prices, from Encore-Stonks, when every price is known. Sortable.
- New module Encore-PvP: the battleground timers, Alterac Valley and Arathi Basin frames, enemy bars, resurrection timer and battleground helpers move out of Encore-QoL into their own addon folder (settings are kept, still on the PvP page of the Encore-QoL window; /epvp opens it). Turn the folder off if you don't play battlegrounds. New feature Battleground history: every finished battleground with result, time, killing blows, honorable kills, deaths and honor, win rate per battleground, all columns sortable (/epvp history). Games kept is a setting (25 to 1000, 300 by default), and Delete history clears it after asking.
- Encore-QoL: new Errands section. Open all mail (a button on the mailbox; skips cash on delivery, stops when bags are full, Shift-click for money only). Restock at vendors (item IDs and amounts you always carry, with a gold limit per visit). Ready check: my buffs (tells only you about a missing food buff, flask or battle elixir, or weapon enhancement).
- Encore: key bindings (Options > Keybindings > AddOns > Encore Essentials) for the main window, Encore-DB, Encore-Stonks, Encore-QoL, Encore-PvP, battleground history and the wishlist. /encore wishlist opens the wishlist.
- Encore: settings sharing. /encore export (or the button in Options) gives one text with your settings for every module; a guildmate pastes it in /encore import. Window places, price history, wishlists and learned data stay yours. The text is read, never run, so it is safe to paste.
- New module Encore-Alts (/ealts): a window with every character you log in on: level, gold (and the total), rested experience (growing while you are logged out), professions, profession cooldowns (transmute, Mooncloth, Salt Shaker), raid lockouts and when you last played them, every column sortable; hover a row for details, right-click to forget a character. Item tooltips show how many your other characters have in their bags and bank.
- Encore-DB: dungeon prep. In a group, players with Encore share which quests are in their quest log (quest IDs only), and a dungeon's quest list tags each quest with who in the group has it.
- The download no longer contains a 2.3 MB test file by mistake (it was 42% of the zip).
- Encore-Stonks: new Stonks tab in the auction house, after Auctionator's tabs. Two modes: listings under vendor price (profit each and for the lot, Buy all button), and listings under the market price with a slider from 5% to 90% under the 3, 7 or 14-day Stonks average (averages from the days before today, launch week left out; items with fewer than 3 days of prices hidden unless you untick that box). Uses only a full Auctionator scan under 15 minutes old; otherwise the list is empty and asks for a fresh scan, with a button that starts one. Clicking a row opens a buy prompt on the same tab: a fresh search of the item, then one purchase per click, only listings still under the limit (commodity prices are checked with the server before you confirm; listings that sold meanwhile are skipped). Every column sorts. Option: Deals tab in the auction house (Options > AddOns > Encore-Stonks).

## 0.2.5

Full release of everything in the 0.2.5.1 to 0.2.5.7 betas below. In short, for Encore-QoL:

- Who rolled what reads the game's loot history and the newer loot chat. It shows only while you hover a roll's Need or Greed button, with pick counts under those buttons, and closes 5 seconds after the roll ends.
- Sell junk is ported from Dejunk (MIT) and only ever sells grey items, with Safe sell (12 items per visit, all buy-back-able) on.
- Button drawer: LibDBIcon addon buttons only, on top of the drawer, opens on mouseover, movable and resizable, with the muted Encore star as its icon.
- Login UI scaling with Auto, Custom and pixel-perfect presets.
- Move more frames can move the group loot roll window.
- Warsong Gulch round timer matches the mock-up; borders keep every edge at small UI scales.

## 0.2.5.7

- Encore-QoL: Who rolled what puts a small number under the Need and Greed buttons of each loot roll: how many players picked it so far. Hover the button for who picked what.
- Encore-QoL: Who rolled what shows only while the mouse is on a roll's Need or Greed button, right beside that roll (new option "Only while hovering Need or Greed", on). Turn it off to get a window for every roll as before.
- Encore-QoL: Who rolled what closes 5 seconds after a roll is won or everyone passed (was 20). The "Stays after the roll ends" slider now goes from 1 to 60 seconds in steps of 1.

## 0.2.5.6

- Encore-QoL: Sell junk could sell a non-grey item (an uncommon bow was sold). It is now ported from Dejunk (MIT), a long-standing sell-junk addon, cut down to grey items only: it starts a moment after the vendor opens, sells one item at a time at your network latency, checks right before every sale that the slot still holds the same grey item (also by the item's own info) and that it isn't locked or refundable, scans the bags again in batches, and stops when the vendor closes or doesn't buy. New option Safe sell (on): at most 12 items per visit, so all of them can be bought back from the Buyback tab. The chat line counts what was really sold.

## 0.2.5.5

- Encore-QoL: Button drawer: the addon buttons are now the top layer, above the drawer's background and border, so they no longer look dark. The layer lock LibDBIcon puts on its buttons is now always lifted before moving them (on WoW Forever the check for it could miss, which kept them under the background). Buttons also stay fully visible in the drawer when an addon fades minimap buttons.

## 0.2.5.4

- Encore-QoL: the button drawer's icon is now the Encore star with a teal gem, in softer muted tones, on the Encore frame (gold rim, teal ring, red field). Same file name, so a /reload is not enough: restart the game after updating.

## 0.2.5.3

- Encore-QoL: Button drawer: the addon buttons really sit on top of the drawer now. LibDBIcon locks its buttons' drawing layer, which silently undid the earlier fix; the drawer unlocks it, moves the buttons above its background and locks it again (and puts them back as they were when the drawer is turned off).

## 0.2.5.2

- Encore-QoL: the button drawer has its own icon: a shaded leather drawstring bag with a teal gem clasp on a red disc with a gold rim, bold enough to read at small sizes. A new file, so the game needs a full restart (not /reload) after updating.
- Encore-QoL: Button drawer is no longer see-through when the minimap is faded, so its buttons show at full strength on top of the background.
- Encore-QoL: window and frame borders keep every edge at small UI scales (like 0.53 for 1440p), where some 1-pixel edges used to vanish.

## 0.2.5.1

- Encore-QoL: Who rolled what reads the roll lines of the newer loot chat, which start with a clickable loot-history link. Before, those lines were not recognised, so the window never opened. If a roll window was missed it is now started from the chat line itself.
- Encore-QoL: the Warsong Gulch round timer now looks like the mock-up: a thin gold ring inside the copper border. In game the gold filled the whole circle and hid the border.
- Encore-QoL: new Login UI scaling (Interface > UI scaling): sets the UI scale at every login, with Auto (768 / screen height), Custom, and pixel-perfect presets for 4K, 1440p and 1080p at 100% and 125%. Goes below the game's 0.64 slider floor.
- Encore-QoL: Button drawer: the addon buttons sit on top of the drawer again instead of under its background, and the drawer button on the minimap is bigger. It can now be resized (16 to 64) and dragged anywhere, with a lock option (right-click it to lock or unlock) and a reset. The drawer opens on mouseover and closes 0.3 seconds after the mouse leaves (can be turned off to open by click).
- Encore-QoL: Button drawer picks up addon buttons as soon as they're made at login, instead of up to 5 seconds later, and no longer re-checks the minimap on a timer: only when an addon loads and after each loading screen.
- Encore-QoL: Button drawer only takes standard addon minimap buttons (LibDBIcon, used by almost every addon). Map pins (innkeepers, mailboxes, Questie and HandyNotes pins) stay on the minimap.
- Encore-QoL: Move more frames can now move the group loot roll window (Need/Greed/Pass).
- Encore-QoL: Who rolled what reads the game's own loot history where the client has it: everyone's Need, Greed, Transmog or Pass, their roll, the winner, and who is still choosing come straight from the game instead of chat. Chat lines are still read as a fallback, and now also match when extra text surrounds them.
- Encore-QoL: Who rolled what windows sit in one tidy column beside the game's loot roll frames, each right above the last, instead of fixed spots that could cover the minimap. Dragged windows stay where you put them.
- Encore-QoL: `/eqol rolls` prints what Who rolled what last saw in loot chat, to help track down rolls it misses.

## 0.2.4

Full release of everything in the 0.2.4.1 to 0.2.4.7 betas below, plus:

- Encore-QoL: the Resurrection timer follows each graveyard's own clock. Every spirit healer brings the dead back every 30 seconds on its own beat, so one shared clock was wrong. The timer is now a list of your side's graveyards, each counting down to its next wave, with the one you'd come back at (the nearest your side holds) on top in gold and "Die now" in its last 3 seconds. Clocks are learned when you or a groupmate waits at a spirit healer and shared with the group by graveyard; a graveyard nobody has waited at yet shows "?". Assaulted bases drop off the list until they're held again.
- Encore-QoL: in Warsong Gulch you can keep a single round timer instead of the list (on by default), with a round or square background. The small bar and time box looks are gone.

## 0.2.4.7

- Encore-QoL: Enemy bars have a Health text setting: percent (76%, as before), the real value (4.2k), both (4.2k · 76%) or none. It can be set per battleground.

## 0.2.4.6

- Encore-QoL: Enemy bars show a power bar under each health bar: mana in blue, rage in red, energy in yellow. On by default, with a height setting (2 to 12 px), and both can be set per battleground. Like health, it fills in once the enemy has been your target, focus or mouseover or had a nameplate on screen; until then it shows faint in the class's usual colour, and in Alterac Valley it stays faint.

## 0.2.4.5

- Encore-QoL: Resurrection timer looks, after the first test in game. Both rings have a thicker copper border (3 px, round or square) and a thinner progress ring. The Time box is now a square: the seconds large in the middle, "Time to resurrect" on two rows underneath. No box or border changes size when the numbers change.

## 0.2.4.4

- Encore-QoL: new in PvP > Battleground timers: **Resurrection timer**. Counts down to the next spirit healer wave (every 30 seconds) in every battleground, while you're dead and while you're alive. In the last 3 seconds it turns red and a "Die now" box shows underneath, so you can die just in time to come straight back. Four looks: ring with a round background, ring with a square background, small bar, or a "Time to resurrect" box, plus a size slider. The timer is shared with your battleground group, so it runs before you've died once. Drag it while unlocked; right-click it to lock or unlock.
- Encore-QoL: new in PvP > Enemies: **Enemy bars**. Every enemy player as a class-coloured bar, best kill first (healers, the flag carrier and low health go up). Left-click targets, right-click focuses, also in combat; in combat the order holds and the new best target glows. Enemies out of nameplate range fade, and health shows everywhere except Alterac Valley. Class bars (optionally in columns of 10) or columns of five (1 to 8 columns per row), with bar height, bar width, font size, how many to show and a class icon in front of the bar.
- Encore-QoL: both have **Customize for each battleground** (separate looks for Warsong Gulch, Arathi Basin and Alterac Valley), a Preview button, Lock position and Reset position.

## 0.2.4.3

- Encore-QoL: the window is laid out like the game's Options window. On the left a tree: Overview, then each tab, which opens to show its sections. On the right the section's page: each feature has a bar with its switch, name and status, a line on what it does, then its settings as rows with the name on the left and the setting on the right, in groups (for an action bar: Shows, Custom rules, Hide anyway when, See-through and fade). Custom rules only show when Shows is set to Custom rules. Search lists every matching feature across all tabs.
- Encore-QoL: drag the bottom right corner to resize the window (720 x 440 up to 1600 x 1100). The size and position are kept.
- Encore-QoL: new in Quality of life > Loot and bags: Who rolled what. A small window next to each group loot roll lists who picked Need, Greed or Pass, what each one rolled, who won, and who is still choosing (class coloured, winner on top). It stays 20 seconds after the roll ends (5 to 120), can be dragged or closed, and shows the item's tooltip on hover. It reads the game's own loot chat lines, so it works in any client language.
- Encore-QoL: the Alterac Valley and Arathi Basin frames have tooltips. Hover a general, captain, marshal or warmaster for its side, health and when it was last seen, and a tower, bunker, graveyard, mine or base (icon or bar) for who holds it, who is assaulting it and the time left.
- Encore-QoL: fixes the Lua error "Widgets.lua:56: bad argument #1 to 'SetText'" when hovering a feature's On · Encore or Off badge.
- Encore-QoL: the window no longer says which addon a feature's idea came from. Credits stay in NOTICE and the README.
- Encore-QoL: battleground messages you send yourself are no longer read back as a groupmate's (WoW Forever's first name and surname are now joined when comparing).

## 0.2.4.2

- New module: **Encore-QoL** (folder `EncoreEssentials_QoL`). Open it from the Encore window, `/encore qol` or `/eqol`. Every feature starts off.
- Each feature checks whether another addon already does it (Enhance QoL, Leatrix Plus, BetterFishing, KelaGraphics, ErrorMonster, MinimapButtonBag, Bartender4, Dominos, ElvUI, SexyMap, Capping and more). If one does, its switch is locked and names that addon. Encore never changes another addon's settings. The Overview tab lists who runs what; `/eqol check` checks again.
- Quality of life: auto repair (guild bank first), sell junk with a keep list, auto quests, auto gossip, auto dismount, faster auto loot, easy delete, free bag slots, vendor price and IDs in tooltips, summons and resurrections, invites with a whisper keyword, blocks (duels, charters, strangers), bigger reading text, flight times. Shift skips any automation for one click.
- Interface: Action bar 1 to 6, pet and stance bars each with their own show rule (always, never, in or out of combat, mouseover or custom: target, dragging, group, casting, resting, low health; hide when a fishing pole is equipped, mounted, on a flight or in a vehicle), alpha in and out of combat, fade and linger time. Action bar text: keybind, macro name, count and cooldown numbers each with show, font (Marcellus SC included), size, outline, colour and position, keybinds hideable per bar; range tint; hide borders. Square minimap, button drawer, wheel zoom and tidy, movers for the durability doll, quest tracker, error text, zone text, capture bar, ghost button and buffs while Edit Mode is open, quest log levels, class coloured names, player and target frame hidden until mouseover, chat buttons and fade time, tooltip size and guild rank, hide error text, boss banners and raid group labels.
- Visual & audio: graphics sliders past the menu caps (ground clutter density and distance, view distance, foliage, detail fade, particles, weather) with a reset to game defaults, cursor ring with trail, mute sounds by file ID, whisper sound, max camera distance, no screen glow or low-health flash, keep audio synced, screenshot on level up.
- Combat: durability warning on ready checks and entering dungeons, interrupt and crowd control announce in party or raid (never in /say), hide chat, minimap or bags in combat.
- PvP: Alterac Valley frame (Compact list, Slim strip, Two sides, Timer bars) and Arathi Basin frame (Compact card, Score bar, Base list, Floating). AV shows the generals' health on top (enemy first), enemy captain and officers as icons, your own officers only when attacked, and tower, bunker and graveyard timers while something is being capped. AB shows the score, who wins and when, the five bases and their timers. Preview button to see them outside a battleground; right-click a frame to lock it or change its size, drag to move. Timers and health are shared with your battleground group, and Encore reads and answers Capping's messages. Release in battlegrounds, queue popup with time left, hide clutter in battlegrounds.
- Professions: one-button fishing (set the key in Options > Keybindings > Encore-QoL; none by default), optional double right-click, louder splash and auto loot while fishing, best pole and lure, lure warning, fishing bar, sortable catch log per zone. Train all at trainers with the total cost. Professions keeps its own saved table so it can become its own addon later.
- Encore-QoL is new and needs testing in game: battleground widgets, POI icons and officer NPC IDs on Forever, and bobber interaction for one-button fishing (uses the game's soft target Interact).

## 0.2.4.1

- Encore-Stonks: much lighter on memory. Opening the All items market view, the daily refresh of the item list's prices and item tooltips no longer build a table for every price of every item: market view about 640 MB of short-lived memory down to about 60 MB, the first login of each day about 390 MB down to about 10 MB (only items with new prices are worked out again). The item list's prices are no longer all kept in memory as tables (about 15 MB), and the browser's item list is let go when the window closes. Every average, chart and price is the same as before.
- Encore-Stonks: an hour seen twice for the same item (after a logout or /reload within that hour) is saved once, with the lowest price and most units, as within one session. Once, on the first login with this version, Stonks merges the doubled hours already saved (about a quarter of all saved samples) and saves its price summaries again in a smaller form. No hour of prices is dropped, launch week included.
- Encore-Stonks: an hourly guild scan and a login summary no longer arrive at the same time. A guildmate who just finished a scan waits to share it while someone's login summary is being sent (up to 5 minutes before the end of the hour, then it shares anyway), and a login summary request waits while an hourly scan is still coming in. Works best when everyone has this version; older versions behave as before.
- Encore-DB: Professions are sorted by what each recipe makes. Under All recipes, the middle list now has the recipe types (Weapons - Daggers, Axes, Maces, Swords ...; Armor - Head, Shoulder, Chest ...; Shields, Enhancements, Enchants by slot, Flasks, Elixirs, Potions, Transmutes, Explosives, Parts, Bags, Materials, Misc and more), then the item sets the profession makes, then the skill brackets as before. Weapons show one-handed and two-handed side by side, armour shows cloth, leather, mail and plate side by side, and potions show healing and mana apart from the rest. Each recipe still shows its skill-up levels in orange, yellow, green and grey.
- Encore-DB: Reputations: a faction's rewards are split into groups (Armor, Weapons, Recipes, Consumables ...) under headings you can close and open again, for every standing. A group you close stays closed when you look at another faction.
- Encore-DB: 45 more dungeon drops that AtlasLoot Continued lists and Wowhead Forever confirms. Trash loot in The Drowned City (10), Krol'dok Stronghold (9), Alcaz Prison (9), Shaper's Terrace (3), City of Dalaran (2) and Ruins of Lordaeron (2). Tor'Rel's three drops under Izha'Rel and Tor'Rel. Sothos and Jarien's Heirlooms under Jarien and Sothos. The Arena Spoils (Lefty's Brass Knuckle, Malgen's Long Bow, Shroud of Arcane Mastery) under the Ring of Law. Each drop is listed where Wowhead Forever shows it.
- Encore-DB: Guardians of Hyjal also shows the six blue rewards of its reputation quests as "Quest reward", with the quest's name: Work Well Done (Horn of Ve'han, Hermit's Pauldron, Wild Wristguards, Ring of Nature's Cycles, Ketharas' Linked Belt) and Return to Jereman (Jereman's Bauble).

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
