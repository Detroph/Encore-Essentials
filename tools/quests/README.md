# Encore-DB quest data

`EncoreEssentials_DB/Data/Quests-<source>.lua` hold each instance's quests and the quest chains they belong to,
one file per source. They are built here and read in the game only through the quest data layer
(`EncoreEssentials_DB/QuestData.lua`), so the quest window never depends on where the data came from.

## Refreshing (project rule, 2026-11-19: QuestieDB first, Wowhead Forever fills the blanks)

```
git clone --depth 1 https://github.com/Questie/QuestieDB tools/cache/questiedb   # or: git -C tools/cache/questiedb pull
node tools/quests/build-quests.mjs          # QuestieDB -> Data/Quests-questie.lua, and tools/out/quest-ids.json
#   then collect the Wowhead Forever quest pages for those IDs (the Wowhead step of tools/refresh.mjs,
#   a browser script) into tools/out/wowhead-drops.json, and run build-quests again:
node tools/quests/build-quests.mjs          # -> Data/Quests-questie.lua and Data/Quests-fillin.lua
```

`node tools/refresh.mjs quests` runs the same steps. Commit the changed `Data/Quests-*.lua`; nothing else changes.

The QuestieDB step runs `tools/quests/sources/questie-extract.lua` with Lua 5.1: `lua` on PATH, or set
`QUESTIE_LUA` (QuestieDB ships a Lua in `tools/lua-binary/`). `QUESTIE_JSON=<file>` uses an extract made earlier.

## Sources

A source is `tools/quests/sources/<id>.mjs`, exporting `id`, `priority` and `load(ctx)`, which returns the model
below. `build-quests.mjs --source a,b` runs them in order (default `questie,fillin`); each writes its own
`Data/Quests-<id>.lua`, which must be listed in `EncoreEssentials_DB.toc`. In the game, the higher `priority`
wins field by field, so a lower one only fills blanks. `ctx.questIds` holds the quest IDs earlier sources found.

- `questie.mjs` (priority 10): QuestieDB's WoW Forever database. That is Questie's Classic data (built from
  CMaNGOS) converted to Forever's maps, plus Forever layers from Wowhead Forever, QuestieTrace recordings made in
  Forever and hand-written Forever fixes. Quests go to an instance by their QuestieDB category (the instance's
  area); quests new in Forever with no category go by the instance name in their title or objective (listed in the
  report). `QUESTIE_SCOPE=forever` keeps only quests new in Forever, from the Forever layers. Rewards: the items
  that list the quest in `questRewards` (one unsplit `rewardItems` list, since QuestieDB does not say which are a
  choice) and `reputationReward`. QuestieDB has no XP or money; those come from the Wowhead Forever fill-in.
- `fillin.mjs` (priority 0, writes `Quests-fillin.lua`): Wowhead Forever's quest pages, collected in a browser into
  `tools/out/wowhead-drops.json` (`quests[<id>]`): descriptions, rewards, money, XP and anything QuestieDB lacks.
- `foreverdb.mjs`: ForeverDB.net's files (only the fields it labels as Forever data). Not in the default order
  any more; `--source foreverdb` still builds it.

Every source returns its credit line and a header line for its file; add each source to
`EncoreEssentials_DB/NOTICE.txt`.

## Model

```js
{
  source: { id, name, url, credit, version, priority, header },
  instances: [ { key, name, quests: [questID, ...] } ],   // key: instance name in lower case with dashes, as in Loot.lua
  quests: {
    [questID]: {
      title, level, minLevel, side,            // side "A" / "H", left out for both factions or unknown
      objective, text, isNew,                  // text: the quest's description
      start, finish,                           // { kind: "npc" | "object" | "item", id, name, map (uiMap), x, y }
      prev: [questID], next: [questID],        // quests before and after it in its chain
      xp, money,                               // money in copper
      rewards: [[itemID, count]], choice: [[itemID, count]],
      rewardItems: [itemID],                   // reward items not split into given and choice (QuestieDB)
      rep: [[factionID, amount]],              // reputation rewards
    },
  },
  items: { [itemID]: [name, quality] },        // reward names until the game has the item
  left: [ "notes for the report" ],
}
```

Every field except `quests[id]` itself is optional. A quest without a title gets its name from the game.

## In the game

Each `Data/Quests-*.lua` adds one table to `ns.QuestSources`. `QuestData.lua` merges every source it finds and
answers the window's questions: `DB.Quests:ForInstance(inst)`, `DB.Quests:Get(id)`, `DB.Quests:Title(id)`.
Above every source, Encore-DB lays the rewards your own game showed you: `EncoreEssentials/QuestRewards.lua` (in
the core addon, which is always loaded) notes the exact XP, money, reward items and choices at quest givers and for
quests in your log, in `EncoreEssentialsDB.questRewards`. XP seen more than five levels above the quest only counts
when no source has XP.

Another addon can add or override quests without a new Encore-DB release by filling the global
`EncoreEssentials_QuestSources` with tables in the same format before Encore-DB loads.
