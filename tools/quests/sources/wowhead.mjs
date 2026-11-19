// Quest source: Wowhead Forever (https://www.wowhead.com/forever), to fill what QuestieDB leaves blank:
// descriptions, rewards, money and XP, and anything else QuestieDB has no value for.
//
// Wowhead's pages sit behind a browser check, so they are not fetched here. tools/refresh.mjs makes a browser
// script (run in a desktop browser) that collects https://www.wowhead.com/forever/quest=<id> for every ID in
// tools/out/quest-ids.json (written by build-quests.mjs) into tools/out/wowhead-drops.json under `quests`:
//   quests[<id>] = { name, level, reqLevel, side ("A"/"H"/"B"), description, objectives,
//                    rewards: [[item, count]], choices: [[item, count]], money (copper), xp,
//                    start, end (NPC IDs), raw: { rewards, gains } }   or { missing: true }
// With no collected file yet, this source adds nothing and says so.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const id = 'wowhead';
export const priority = 0; // fills blanks below QuestieDB

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const FILE = process.env.WOWHEAD_JSON || path.join(ROOT, 'tools', 'out', 'wowhead-drops.json');

const n = (v) => { const x = Number(v); return Number.isFinite(x) ? x : 0; };
const items = (v) => (Array.isArray(v) ? v : [])
  .map((e) => (Array.isArray(e) ? [n(e[0]), n(e[1]) || 1] : typeof e === 'object' && e ? [n(e.id ?? e.item), n(e.count) || 1] : [n(e), 1]))
  .filter(([i]) => i > 0);
const text = (v) => (typeof v === 'string' ? v.replace(/\s+\n/g, '\n').trim() : Array.isArray(v) ? v.join(' ').trim() : '');
const npc = (v) => { const i = n(Array.isArray(v) ? v[0] : v?.id ?? v); return i > 0 ? { kind: 'npc', id: i, ...(v?.name ? { name: v.name } : {}) } : null; };

export function load(ctx = {}) {
  const source = {
    id, name: 'Quest fill-in', url: null,
    credit: null,
    version: new Date().toISOString().slice(0, 10), priority,
  };
  if (!fs.existsSync(FILE)) {
    return { source, instances: [], quests: {}, items: {}, left: [`no ${path.relative(ROOT, FILE)} yet: run the Wowhead step of tools/refresh.mjs`] };
  }
  const all = JSON.parse(fs.readFileSync(FILE, 'utf8')).quests || {};
  source.version = (fs.statSync(FILE).mtime.toISOString()).slice(0, 10);
  const quests = {};
  const left = [];
  const want = ctx.questIds && ctx.questIds.size ? ctx.questIds : new Set(Object.keys(all).map(Number));
  for (const qid of want) {
    const w = all[qid];
    if (!w) { left.push(`${qid}: not collected from Wowhead`); continue; }
    if (w.missing) { left.push(`${qid}: no Wowhead Forever page`); continue; }
    const Q = { id: qid };
    if (w.name) Q.title = w.name;
    if (n(w.level) > 0) Q.level = n(w.level);
    if (n(w.reqLevel) > 0) Q.minLevel = n(w.reqLevel);
    if (w.side === 'A' || w.side === 'H') Q.side = w.side;
    if (text(w.objectives)) Q.objective = text(w.objectives);
    if (text(w.description)) Q.text = text(w.description);
    if (n(w.money) > 0) Q.money = n(w.money);
    if (n(w.xp) > 0) Q.xp = n(w.xp);
    Q.rewards = items(w.rewards);
    Q.choice = items(w.choices);
    const s = npc(w.start), e = npc(w.end);
    if (s) Q.start = s;
    if (e) Q.finish = e;
    quests[qid] = Q;
  }
  return { source, instances: [], quests, items: {}, left };
}
