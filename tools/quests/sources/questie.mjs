// Quest source: QuestieDB (https://github.com/Questie/QuestieDB, GPL-3.0), its WoW Forever database.
// Usage: node tools/quests/build-quests.mjs --source questie        (QUESTIE_SCOPE=forever for its Forever layers only)
//
// Project data rule (2026-11-19): quests come from QuestieDB, with Wowhead Forever filling blanks. QuestieDB's Forever
// database is Questie's Classic data (built from CMaNGOS) converted to Forever's maps, plus Forever layers from
// Wowhead Forever, QuestieTrace recordings in Forever and hand-written Forever fixes. QUESTIE_SCOPE=forever keeps
// only quests new in Forever (ID 90000+) from the Forever layers, with no Classic data at all.
//
// Needs a QuestieDB checkout (default tools/cache/questiedb):
//   git clone --depth 1 https://github.com/Questie/QuestieDB tools/cache/questiedb
// and a Lua 5.1 to run questie-extract.lua: `lua` on PATH, or QUESTIE_LUA=<path to lua> (QuestieDB ships one in
// tools/lua-binary). Or run the extractor yourself and pass its output with QUESTIE_JSON=<file>.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const id = 'questie';
export const priority = 10; // first: the chosen quest source

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..', '..');
const FIRST_FOREVER_ID = 90000;
const SCOPE = process.env.QUESTIE_SCOPE === 'forever' ? 'forever' : 'full';

const slug = (s) => s.toLowerCase().normalize('NFD').replace(/['’]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const flat = (s) => slug(s).replace(/^the-/, '').replace(/-/g, '');

function extract() {
  if (process.env.QUESTIE_JSON) return JSON.parse(fs.readFileSync(process.env.QUESTIE_JSON, 'utf8'));
  const checkout = path.resolve(process.env.QUESTIEDB || path.join(ROOT, 'tools', 'cache', 'questiedb'));
  if (!fs.existsSync(path.join(checkout, 'src', 'corrections', 'Forever'))) {
    throw new Error(`No QuestieDB checkout at ${checkout}: git clone --depth 1 https://github.com/Questie/QuestieDB tools/cache/questiedb`);
  }
  const lua = process.env.QUESTIE_LUA || 'lua';
  const out = execFileSync(lua, [path.join(HERE, 'questie-extract.lua'), checkout, SCOPE], { maxBuffer: 1 << 28, encoding: 'utf8' });
  return JSON.parse(out);
}

// The QuestieDB commit the data came from (QUESTIE_VERSION overrides it).
function questieVersion() {
  if (process.env.QUESTIE_VERSION) return process.env.QUESTIE_VERSION;
  const checkout = path.resolve(process.env.QUESTIEDB || path.join(ROOT, 'tools', 'cache', 'questiedb'));
  try {
    return 'QuestieDB@' + execFileSync('git', ['-C', checkout, 'log', '-1', '--format=%h %cs'], { encoding: 'utf8' }).trim();
  } catch {
    return new Date().toISOString().slice(0, 10);
  }
}

// Instances the addon knows (Data/Loot.lua): key and name.
function knownInstances() {
  const src = fs.readFileSync(path.join(ROOT, 'EncoreEssentials_DB', 'Data', 'Loot.lua'), 'utf8');
  return [...src.matchAll(/\{ key = "([^"]+)", name = "([^"]+)"/g)].map((m) => ({ key: m[1], name: m[2] }));
}

// Forever race masks: Alliance races 1, 3, 4, 7 and 95 (Skyborne); Horde 2, 5, 6, 8 and 96.
const bit = (id) => 1n << BigInt(id - 1);
const ALLIANCE = [1, 3, 4, 7, 95].reduce((m, r) => m | bit(r), 0n);
const HORDE = [2, 5, 6, 8, 96].reduce((m, r) => m | bit(r), 0n);
function side(mask) {
  if (!mask) return undefined;
  const m = BigInt(Math.round(mask));
  const a = (m & ALLIANCE) !== 0n, h = (m & HORDE) !== 0n;
  return a && !h ? 'A' : h && !a ? 'H' : undefined;
}

const list = (v) => (Array.isArray(v) ? v.filter((x) => x != null) : v != null && v !== 0 ? [v] : []);
const num = (k) => Number(String(k).replace(/^#/, ''));

export function load() {
  const data = extract();
  const quests = new Map(Object.entries(data.quests).map(([k, v]) => [num(k), v]));
  const npcs = new Map(Object.entries(data.npcs).map(([k, v]) => [num(k), v]));
  const areaToMap = new Map(Object.entries(data.areaToMap).map(([k, v]) => [num(k), v]));
  const zoneNames = data.zoneNames || {};
  // [quest] = the item IDs it rewards (QuestieDB's items list the quests that reward them; it does not say which are
  // a choice, and has no XP or money: Wowhead Forever fills those).
  const rewardItems = new Map(Object.entries(data.questRewards || {}).map(([k, v]) => [num(k), list(v).map(Number)]));
  const itemNames = data.itemNames || {};
  const instances = knownInstances();
  const byFlat = new Map(instances.map((I) => [flat(I.name), I]));

  // Starters and finishers: { npcs, objects, items }, joined with the "_add" lists the Forever layers add.
  const actors = (q, base) => {
    const out = [[], [], []];
    for (const k of [base, `${base}_add`]) {
      const v = q[k];
      if (!Array.isArray(v)) continue;
      v.forEach((ids, i) => { if (i < 3) for (const x of list(ids)) if (!out[i].includes(x)) out[i].push(x); });
    }
    return out;
  };
  function who(q, base) {
    const [n, o, i] = actors(q, base);
    if (n.length) {
      const id = n[0];
      const npc = npcs.get(id) || {};
      const w = { kind: 'npc', id };
      if (npc.name) w.name = npc.name;
      for (const [area, spots] of Object.entries(npc.spawns || {})) {
        const map = areaToMap.get(Number(area));
        const s = Array.isArray(spots) && spots.find((p) => Array.isArray(p) && p[0] > 0);
        if (map && s) { Object.assign(w, { map, x: s[0], y: s[1] }); break; }
      }
      return w;
    }
    if (o.length) return { kind: 'object', id: o[0] };
    if (i.length) return { kind: 'item', id: i[0] };
    return null;
  }

  // Instance areas: QuestieDB's dungeon list (name and alternative area IDs) and its zone symbols.
  const areaInstance = new Map();
  const ALIAS = { stockade: 'stormwindstockade', templeofatalhakkar: 'sunkentemple' };
  const match = (name) => { const f = flat(name); return byFlat.get(ALIAS[f] || f); };
  for (const [k, d] of Object.entries(data.dungeons || {})) {
    const I = match(d[0]);
    if (!I) continue;
    areaInstance.set(num(k), I);
    for (const alt of list(d[1])) areaInstance.set(alt, I);
  }
  for (const [area, sym] of Object.entries(zoneNames)) {
    if (areaInstance.has(Number(area))) continue;
    const I = match(sym.replace(/_/g, ' '));
    if (I) areaInstance.set(Number(area), I);
  }

  // Which instance a quest belongs to: its category is the instance's area, or (quests new in Forever) its name
  // or objective names the instance.
  const how = new Map();
  function instanceOf(id, q) {
    const I = q.zoneOrSort > 0 && areaInstance.get(q.zoneOrSort);
    if (I) { how.set(id, 'area'); return I; }
    if (id < FIRST_FOREVER_ID) return null;
    const text = `${q.name || ''} ${list(q.objectivesText).join(' ')}`.toLowerCase();
    for (const I of instances) {
      const name = I.name.toLowerCase();
      if (name.length >= 6 && text.includes(name)) { how.set(id, 'text'); return I; }
    }
    return null;
  }

  // The quests used (all of them, or in the forever scope only those new in Forever), and links between them.
  const forever = new Map([...quests].filter(([qid, q]) => q.name && (SCOPE === 'full' || qid >= FIRST_FOREVER_ID)));
  const prev = new Map(), next = new Map();
  const link = (a, b) => {
    if (!a || !b || a === b || !forever.has(a) || !forever.has(b)) return;
    (next.get(a) || next.set(a, new Set()).get(a)).add(b);
    (prev.get(b) || prev.set(b, new Set()).get(b)).add(a);
  };
  for (const [qid, q] of forever) {
    for (const p of [...list(q.preQuestSingle), ...list(q.preQuestGroup), ...list(q.breadcrumbs)]) link(p, qid);
    for (const n of [...list(q.nextQuestInChain), ...list(q.childQuests), ...list(q.breadcrumbForQuestId)]) link(qid, n);
  }

  const byInstance = new Map();
  for (const [qid, q] of forever) {
    const I = instanceOf(qid, q);
    if (!I) continue;
    if (!byInstance.has(I.key)) byInstance.set(I.key, { key: I.key, name: I.name, quests: [] });
    byInstance.get(I.key).quests.push(qid);
  }

  const out = {};
  const todo = [...byInstance.values()].flatMap((I) => I.quests);
  while (todo.length) {
    const qid = todo.pop();
    if (out[qid]) continue;
    const q = forever.get(qid);
    const Q = { id: qid, title: q.name };
    if (qid >= FIRST_FOREVER_ID) Q.isNew = true;
    if (q.questLevel > 0) Q.level = q.questLevel;
    if (q.requiredLevel > 0) Q.minLevel = q.requiredLevel;
    const s = side(q.requiredRaces);
    if (s) Q.side = s;
    const obj = list(q.objectivesText).join(' ').trim();
    if (obj) Q.objective = obj;
    Q.start = who(q, 'startedBy');
    Q.finish = who(q, 'finishedBy');
    Q.prev = [...(prev.get(qid) || [])].sort((a, b) => a - b);
    Q.next = [...(next.get(qid) || [])].sort((a, b) => a - b);
    const ri = rewardItems.get(qid);
    if (ri?.length) Q.rewardItems = ri;
    const rep = (Array.isArray(q.reputationReward) ? q.reputationReward : [])
      .filter((r) => Array.isArray(r) && r[0] > 0 && r[1]).map((r) => [Number(r[0]), Number(r[1])]);
    if (rep.length) Q.rep = rep;
    out[qid] = Q;
    for (const n of [...Q.prev, ...Q.next]) if (!out[n]) todo.push(n);
  }

  for (const I of byInstance.values()) I.quests.sort((a, b) => (out[a].level || 0) - (out[b].level || 0) || a - b);
  return {
    source: {
      id,
      name: 'QuestieDB',
      url: 'https://github.com/Questie/QuestieDB',
      credit: 'Quest data from QuestieDB by the Questie team (https://github.com/Questie/QuestieDB)',
      version: questieVersion(),
      priority,
      header: `-- Data: QuestieDB (https://github.com/Questie/QuestieDB), GPL-3.0, ${SCOPE === 'full' ? 'its WoW Forever database' : 'its WoW Forever layers only (quests new in Forever)'}. See NOTICE.txt.`,
      scope: SCOPE,
    },
    instances: [...byInstance.values()],
    quests: out,
    items: Object.fromEntries([...new Set(Object.values(out).flatMap((Q) => Q.rewardItems || []))]
      .filter((i) => itemNames[`#${i}`]).map((i) => [i, [itemNames[`#${i}`], null]])),
    left: [...how].filter(([, h]) => h === 'text').map(([qid]) => `${qid} ${forever.get(qid).name}: placed by the instance name in its text`),
  };
}
