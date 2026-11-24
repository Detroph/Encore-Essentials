// Quest rewards on a faction's reputation page: the gear its reputation quests give, shown with the faction's vendor
// rewards in Encore-DB (standing "q", "Quest reward", with the quest's name). Only the factions in FACTIONS get them
// (Det, 2026-11-24: Guardians of Hyjal). The data is Wowhead Forever's faction page, read in your browser:
//   node tools/loot/faction-quest-rewards.mjs script   -> tools/out/wowhead-faction-quests-sweep.js; paste it into the
//                                                         Console on www.wowhead.com/forever; it downloads
//                                                         wowhead-faction-quests.json
//   put that in tools/out/ and run the loot step (node tools/refresh.mjs loot), which runs this after build-loot.mjs.
// Uncommon or better items only. Run on its own: node tools/loot/faction-quest-rewards.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readJson } from './net.mjs';

const FACTIONS = [2765]; // Guardians of Hyjal
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const LOOT = path.join(REPO, 'EncoreEssentials_DB', 'Data', 'Loot.lua');
const OUT = path.join(REPO, 'tools', 'out');

if (process.argv[2] === 'script') {
  const js = `// Encore-DB: quest rewards on Wowhead Forever faction pages. Paste into the Console on www.wowhead.com/forever.
(async () => {
  const out = {};
  for (const f of ${JSON.stringify(FACTIONS)}) {
    const t = await (await fetch('/forever/faction=' + f)).text();
    const lv = t.match(/new Listview\\(\\{\\s*template: 'quest'[^]*?data: ?(\\[[^]*?\\])\\}\\);/);
    const quests = lv ? new Function('return ' + lv[1])() : [];
    const items = {};
    for (const m of t.matchAll(/WH\\.Gatherer\\.addData\\(3, \\d+, (\\{[^\\n]*?\\})\\);/g)) {
      try { for (const [k, v] of Object.entries(JSON.parse(m[1]))) items[k] = { n: v.name_enus, q: v.quality, icon: v.icon }; } catch (e) {}
    }
    out[f] = { quests: quests.map((q) => ({ id: q.id, name: q.name, rewards: [...(q.itemrewards || []), ...(q.itemchoices || [])].map((r) => r[0]) })), items };
    await new Promise((r) => setTimeout(r, 4000));
  }
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([JSON.stringify({ fetched: new Date().toISOString(), factions: out })], { type: 'application/json' }));
  a.download = 'wowhead-faction-quests.json'; a.click();
})();
`;
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, 'wowhead-faction-quests-sweep.js'), js);
  console.log('wrote tools/out/wowhead-faction-quests-sweep.js');
  process.exit(0);
}

let W;
try { W = readJson('out/wowhead-faction-quests.json'); } catch { console.log('faction-quest-rewards: no tools/out/wowhead-faction-quests.json yet ("node tools/loot/faction-quest-rewards.mjs script"); skipped'); process.exit(0); }
const lines = fs.readFileSync(LOOT, 'utf8').split('\n');
const itemsStart = lines.findIndex((l) => l.startsWith('ns.Loot.items = {'));
const itemsEnd = lines.indexOf('}', itemsStart);
const itemLines = new Map();
for (let n = itemsStart + 1; n < itemsEnd; n++) { const m = lines[n].match(/^  \[(\d+)\]/); if (m) itemLines.set(+m[1], lines[n]); }
let added = 0;
for (const [f, data] of Object.entries(W.factions || {})) {
  const n = lines.findIndex((l) => l.startsWith('  { kind = "faction"') && l.includes(`faction = ${f},`));
  if (n < 0) { console.log(`faction-quest-rewards: faction ${f} has no reputation list in Loot.lua; skipped`); continue; }
  if (lines[n].includes('"q"')) continue; // already added
  const extra = [];
  for (const q of data.quests) for (const id of q.rewards) {
    const it = data.items[id];
    if (!it || (it.q ?? 0) < 2 || lines[n].includes(`{ ${id},`)) continue;
    extra.push(`{ ${id}, "q", nil, ${JSON.stringify(q.name)} }`);
    if (!itemLines.has(id)) itemLines.set(id, `  [${id}] = { ${JSON.stringify(it.n)}, ${it.q}, ${it.icon ? JSON.stringify(it.icon) : 'nil'}, nil, nil, nil, nil, ${id >= 250000 ? 1 : 0} },`);
  }
  if (!extra.length) continue;
  lines[n] = lines[n].replace(/ \} \}(,?)$/, (m, c) => `, ${extra.join(', ')} } }${c}`);
  added += extra.length;
}
lines.splice(itemsStart + 1, itemsEnd - itemsStart - 1, ...[...itemLines.keys()].sort((a, b) => a - b).map((id) => itemLines.get(id)));
if (added && !lines.some((l) => l.includes('faction-quest-rewards.mjs')))
  lines.splice(lines.findIndex((l) => l.startsWith('-- Vendor item:')) + 1, 0,
    '--   standing "q": a reward of the faction\'s reputation quests (4th value: the quest), from Wowhead Forever (tools/loot/faction-quest-rewards.mjs).');
fs.writeFileSync(LOOT, lines.join('\n'));
console.log(`Faction quest rewards: ${added} added`);
