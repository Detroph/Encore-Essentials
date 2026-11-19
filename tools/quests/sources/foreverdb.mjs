// Quest source: ForeverDB.net's addon data files (GPL-3.0 with an attribution term: credit "Data from ForeverDB.net").
// Reads the files tools/loot/foreverdb-files.mjs downloaded and returns the source-neutral quest model that
// tools/quests/build-quests.mjs writes out (see the model in tools/quests/README.md).
//
// Only what ForeverDB labels as WoW Forever data is used:
//   - Dungeons.lua: each instance's quest list, "dungeon quests confirmed in Forever".
//   - QuestForever.lua: titles, levels, objective text, quest givers, map points and the confirmed previous quest,
//     from the Forever client, its game cache and what players recorded in Forever.
//   - QuestGuide.lua: only the fields it labels f (Forever): description, money, rewards, and chain links marked f.
// QuestClassic.lua (from CMaNGOS classic-db) and every field QuestGuide labels c (Classic) are never read.
import { readFdb } from '../../loot/foreverdb-files.mjs';

export const id = 'foreverdb';

const slug = (s) => s.toLowerCase().normalize('NFD').replace(/['’]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const ids = (s) => (s || '').split(/\s+/).filter(Boolean);
const num = (s) => { const n = Number(s); return Number.isFinite(n) ? n : 0; };

// "niak1q" -> { map, x, y }: base-36 of map * 1e6 + x * 10 * 1e3 + y * 10.
function spot(code) {
  if (!code) return null;
  const v = parseInt(code.split(/\s+/)[0], 36);
  if (!Number.isFinite(v) || v <= 0) return null;
  const map = Math.floor(v / 1e6), r = v % 1e6;
  return { map, x: Math.floor(r / 1000) / 10, y: (r % 1000) / 10 };
}

// "6414 3324:2" -> [[6414, 1], [3324, 2]]
const itemList = (s) => ids(s).map((t) => { const [i, c] = t.split(':'); return [num(i), num(c) || 1]; }).filter(([i]) => i > 0);

export function load() {
  const dungeons = readFdb('Dungeons.lua');
  const qfFile = readFdb('QuestForever.lua');
  const qgFile = readFdb('QuestGuide.lua');
  const meta = readFdb('Meta.lua').tables['ns.meta'] || {};
  const D = dungeons.tables['ns.dungeons'] || {};
  const qf = qfFile.tables['ns.qfQuests'] || {};
  const poi = qfFile.tables['ns.qfPoi'] || {};
  const seen = qfFile.tables['ns.qfSeen'] || {};
  const npcNames = qfFile.tables['ns.qfNpcNames'] || {};
  const npcSpots = qfFile.tables['ns.qfNpcSpots'] || {};
  const qfItems = qfFile.tables['ns.qfItems'] || {};
  const qg = qgFile.tables['ns.qgQuests'] || {};
  const S = qgFile.tables['ns.qgS'] || [];
  const qgItems = qgFile.tables['ns.qgItems'] || {};
  const str = (i) => (i ? S[num(i) - 1] : undefined);

  // Chain links ForeverDB confirmed in Forever: QuestForever's previous quest, and QuestGuide's links marked f.
  // A link from a quest to one more than 5 levels below it is dropped: those come from players who took a
  // low quest late (e.g. Arugal Must Die, level 27, "before" Prove Your Worth, level 10) and are not a chain.
  const prev = new Map(), next = new Map();
  const levelOf = (q) => num((qf[q] || '').split('|')[1]);
  const dropped = [];
  const link = (a, b) => {
    if (!a || !b || a === b) return;
    if (levelOf(a) && levelOf(b) && levelOf(a) - levelOf(b) > 5) {
      if (!next.get(a)?.has(b) && !dropped.includes(`${a}>${b}`)) dropped.push(`${a}>${b}`);
      return;
    }
    (next.get(a) || next.set(a, new Set()).get(a)).add(b);
    (prev.get(b) || prev.set(b, new Set()).get(b)).add(a);
  };
  for (const [q, v] of Object.entries(qf)) link(num(v.split('|')[8]), num(q));
  for (const [q, v] of Object.entries(qg)) {
    const g = v.split('|');
    for (const t of ids(g[11])) if (t.endsWith('f')) link(num(t.slice(0, -1)), num(q));
    for (const t of ids(g[12])) if (t.endsWith('f')) link(num(q), num(t.slice(0, -1)));
  }

  const left = [];
  function who(code, q, which) {
    if (!code) return null;
    const kind = { n: 'npc', o: 'object', i: 'item' }[code[0]];
    const id = num(code.slice(1));
    if (!kind || !id) return null;
    const out = { kind, id };
    if (kind === 'npc' && npcNames[id]) out.name = npcNames[id];
    if (kind === 'item' && qfItems[id]) out.name = qfItems[id];
    // Where: the Forever client's quest map point, else where players saw it, else where players saw the NPC.
    const p = spot(poi[q]?.[which]) || spot(seen[q]?.[which]) || (kind === 'npc' && spot(npcSpots[id]));
    if (p) Object.assign(out, p);
    return out;
  }

  const items = {};
  function quest(q) {
    const f = qf[q] ? qf[q].split('|') : null;
    const g = qg[q] ? qg[q].split('|') : null;
    const Q = { id: q };
    if (f) {
      if (f[0]) Q.title = f[0];
      if (num(f[1]) > 0) Q.level = num(f[1]);
      if (num(f[2]) > 0) Q.minLevel = num(f[2]);
      if (f[3]) Q.objective = f[3];
      Q.start = who(f[4], q, 's');
      Q.finish = who(f[5], q, 'e');
      if (num(f[6]) > 0) Q.players = num(f[6]);
      if (f[7] === '1') Q.isNew = true;
      if (f[10] === 'a') Q.side = 'A'; else if (f[10] === 'h') Q.side = 'H';
    }
    if (g) {
      const src = g[3] || '';
      if (src[0] === 'f' && str(g[1])) Q.text = str(g[1]);
      if (!Q.objective && src[1] === 'f' && str(g[2])) Q.objective = str(g[2]);
      if (g[5] === 'f' && num(g[4]) !== 0) Q.money = num(g[4]);
      const xp = (g[6] || '').split(':');
      if (num(xp[0]) > 0) Q.xp = num(xp[0]);
      if (g[9] === 'f') {
        Q.rewards = itemList(g[7]);
        Q.choice = itemList(g[8]);
        for (const [i] of [...Q.rewards, ...Q.choice]) {
          if (qgItems[i]) { const [n, ql] = qgItems[i].split('|'); items[i] = [n, num(ql)]; }
        }
      }
    }
    if (!f && !g) left.push(`${q}: no Forever data`);
    Q.prev = [...(prev.get(q) || [])].sort((a, b) => a - b);
    Q.next = [...(next.get(q) || [])].sort((a, b) => a - b);
    return Q;
  }

  const instances = [];
  const quests = {};
  for (const [did, d] of Object.entries(D)) {
    const list = ids(d.q).map(num).filter(Boolean);
    if (!list.length) continue;
    instances.push({ key: slug(d.n), name: d.n, sourceId: num(did), quests: list });
    // The dungeon's quests and the quests chained to them, both ways.
    const todo = [...list];
    while (todo.length) {
      const q = todo.pop();
      if (quests[q]) continue;
      quests[q] = quest(q);
      for (const n of [...quests[q].prev, ...quests[q].next]) if (!quests[n]) todo.push(n);
    }
  }

  return {
    source: {
      id,
      name: 'ForeverDB.net',
      url: 'https://foreverdb.net',
      credit: 'Data from ForeverDB.net (https://foreverdb.net)',
      version: meta.version || dungeons.version,
      build: meta.build,
      header: dungeons.header, // ForeverDB's credit line: the first line of every file built from its data
    },
    instances,
    quests,
    items,
    left: [...left, ...dropped.map((d) => `link ${d} dropped: the quest before is more than 5 levels higher`)],
  };
}
