// AtlasLoot Continued leads that the main build could not confirm, checked again on Wowhead Forever's item lists.
// AtlasLoot Continued is GPL v2 only and Encore Essentials is GPL-3.0, so nothing of AtlasLoot is copied: its boss lists
// (tools/loot/atlasloot-loot.mjs) only say which item IDs to look up. An item is added to Loot.lua only when Wowhead
// Forever shows it as a drop in that same instance, and it goes where Wowhead puts it:
//   - under a boss, when Wowhead names that boss (or its chest) as the dropper;
//   - under the instance's trash, when AtlasLoot lists it as trash and Wowhead shows it dropping in the instance from no
//     boss of it.
// A boss lead Wowhead only ties to the instance, not to a boss, is left out. So are common and poor items, recipes,
// crafted items and anything with no drop source on Wowhead. Report: tools/out/atlasloot-additions.json.
//
// The Wowhead data is read in your browser (Wowhead shows a Human Verification check to scripts):
//   node tools/loot/atlasloot-additions.mjs script   -> tools/out/wowhead-leads-sweep.js; paste it into the Console on
//                                                       www.wowhead.com/forever; it downloads wowhead-leads.json
//   put wowhead-leads.json in tools/out/, then run the loot step (node tools/refresh.mjs loot), which runs this after
//   build-loot.mjs. Run on its own: node tools/loot/atlasloot-additions.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readJson, writeJson } from './net.mjs';
import { atlasLoot, atlasLootFile } from './atlasloot-loot.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const LOOT = path.join(REPO, 'EncoreEssentials_DB', 'Data', 'Loot.lua');
const OUT = path.join(REPO, 'tools', 'out');
const MIN_QUALITY = 2; // uncommon or better, as build-loot.mjs keeps under bosses
const RECIPE_RE = /^(Plans|Pattern|Schematic|Formula|Recipe|Design|Manual|Blueprint|Book|Tome|Codex|Libram):/;
const norm = (s) => String(s || '').toLowerCase().replace(/^the /, '').replace(/['’]s\b/g, '').replace(/[^a-z0-9]/g, '');

// AtlasLoot instance names that differ from Encore-DB's (wings and halves that are one instance here).
const AL_INSTANCE = {
  thedrownedcity: 'drowned-city', lowerblackrockspire: 'blackrock-spire', upperblackrockspire: 'blackrock-spire',
  diremauleast: 'dire-maul', diremaulwest: 'dire-maul', diremaulnorth: 'dire-maul',
  scarletmonasterygraveyard: 'scarlet-monastery', scarletmonasterylibrary: 'scarlet-monastery',
  scarletmonasteryarmory: 'scarlet-monastery', scarletmonasterycathedral: 'scarlet-monastery',
  templeofatalhakkar: 'sunken-temple',
};
// Wowhead Forever zone names that differ from Encore-DB's instance names.
const WH_ZONE = { templeofatalhakkar: 'sunken-temple' };
// Chests Wowhead names as the dropper, and the entry they are listed under here.
const CHESTS = { sothosandjarienheirlooms: 'jarienandsothos', arenaspoils: 'ringoflaw' };

// Loot.lua's instances and bosses, read as text.
function readLoot(src) {
  const lines = src.split('\n');
  const insts = [];
  let I = null;
  lines.forEach((l, n) => {
    let m = l.match(/^  \{ key = "([^"]+)", name = "([^"]+)"/);
    if (m) { I = { key: m[1], name: m[2], line: n, bosses: [] }; insts.push(I); return; }
    m = l.match(/^    \{ name = "((?:[^"\\]|\\.)+)"(.*)items = \{(.*)\} \},?$/);
    if (m && I) {
      const ids = new Set([...m[3].matchAll(/(?:\{ )?(\d+)(?:, [\d.]+ \})?/g)].map((x) => +x[1]));
      I.bosses.push({ name: m[1], trash: /trash = true/.test(m[2]), line: n, ids });
    }
  });
  const items = new Set([...src.slice(src.indexOf('ns.Loot.items = {'), src.indexOf('ns.Loot.instances')).matchAll(/^  \[(\d+)\] = /gm)].map((m) => +m[1]));
  return { lines, insts, items };
}

const al = atlasLoot(atlasLootFile());
if (!al) { console.log('atlasloot-additions: no AtlasLoot folder ("atlasLoot" in tools/refresh.config.json); skipped'); process.exit(0); }
const src = fs.readFileSync(LOOT, 'utf8');
const L = readLoot(src);
const byKey = new Map(L.insts.map((I) => [I.key, I]));
const instOf = (name) => byKey.get(AL_INSTANCE[norm(name)]) || L.insts.find((I) => norm(I.name) === norm(name));

// Leads: AtlasLoot entries not listed under any boss of that instance here.
const leads = [];
for (const d of al.dungeons) {
  const I = instOf(d.name);
  if (!I) continue;
  const here = new Set(I.bosses.flatMap((b) => [...b.ids]));
  for (const b of d.bosses) for (const id of b.items) if (!here.has(id)) leads.push({ inst: I.key, alBoss: b.name, trash: b.trash, id });
}

if (process.argv[2] === 'script') {
  const ids = [...new Set(leads.map((x) => x.id))].sort((a, b) => a - b);
  const ranges = [];
  for (const id of ids) { const r = ranges[ranges.length - 1]; if (r && id - r[0] <= 400) r[1] = id; else ranges.push([id, id]); }
  const js = `// Encore-DB: Wowhead Forever item lists for ${ids.length} AtlasLoot leads (IDs only). Paste into the Console on www.wowhead.com/forever.
(async () => {
  const ranges = ${JSON.stringify(ranges)}, want = new Set(${JSON.stringify(ids)}), items = {}, zones = {};
  for (const [a, b] of ranges) {
    const t = await (await fetch('/forever/items?filter=151:151;2:4;' + a + ':' + b)).text();
    const m = t.match(/var listviewitems = (\\[[^]*?\\]);\\n/);
    if (!m) { console.log('No item list for ' + a + '-' + b + ' (Human Verification?): stopped'); break; }
    for (const d of new Function('return ' + m[1])()) if (want.has(d.id)) items[d.id] = { n: d.name, q: d.quality, ilvl: d.level, req: d.reqlevel, src: d.source, sm: d.sourcemore };
    await new Promise((r) => setTimeout(r, 4000));
  }
  for (const z of new Set(Object.values(items).flatMap((i) => (i.sm || []).map((s) => s.z)).filter(Boolean))) {
    const t = await (await fetch('/forever/zone=' + z)).text();
    zones[z] = ((t.match(/<title>([^<]*)/) || [])[1] || '').replace(/ - Zone - WoW Forever$/, '');
    await new Promise((r) => setTimeout(r, 4000));
  }
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([JSON.stringify({ fetched: new Date().toISOString(), zones, items })], { type: 'application/json' }));
  a.download = 'wowhead-leads.json'; a.click();
  console.log('Saved wowhead-leads.json: ' + Object.keys(items).length + ' items');
})();
`;
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, 'wowhead-leads-sweep.js'), js);
  console.log(`wrote tools/out/wowhead-leads-sweep.js (${ids.length} items in ${ranges.length} list pages)`);
  process.exit(0);
}

let W;
try { W = readJson('out/wowhead-leads.json'); } catch { console.log('atlasloot-additions: no tools/out/wowhead-leads.json yet ("node tools/loot/atlasloot-additions.mjs script"); skipped'); process.exit(0); }
const zoneInst = {};
for (const [z, name] of Object.entries(W.zones || {})) {
  const I = byKey.get(WH_ZONE[norm(name)]) || L.insts.find((x) => norm(x.name) === norm(name));
  if (I) zoneInst[z] = I.key;
}

const report = { atlasLoot: al.version, wowhead: W.fetched, added: [], leftOut: [] };
const add = new Map(); // "inst|boss name" -> [ids]
const newItems = new Map();
const seen = new Set();
for (const x of leads) {
  const k = `${x.inst}|${x.id}`;
  if (seen.has(k)) continue;
  const w = W.items?.[x.id];
  const row = { instance: x.inst, atlasLootBoss: x.alBoss, item: x.id, name: w?.n || al.names[x.id] || null };
  const skip = (why) => { if (!seen.has(k)) report.leftOut.push({ ...row, why }); };
  if (!w) { skip('not on Wowhead Forever'); continue; }
  if ((w.q ?? 0) < MIN_QUALITY) { skip('common or poor'); continue; }
  if (RECIPE_RE.test(w.n)) { skip('recipe'); continue; }
  if (!(w.src || []).includes(2)) { skip('no drop source on Wowhead (crafted, vendor or quest)'); continue; }
  const drops = (w.sm || []).filter((s) => s.dd != null && zoneInst[s.z] === x.inst);
  if (!drops.length) { skip('Wowhead shows no drop in this instance'); continue; }
  const I = byKey.get(x.inst);
  let B = null;
  for (const s of drops) {
    if (!s.n) continue;
    const n = CHESTS[norm(s.n)] || norm(s.n);
    B = I.bosses.find((b) => !b.trash && (norm(b.name) === n || norm(b.name).split('and').includes(n))) || B;
  }
  if (!B) {
    if (!x.trash) { skip('Wowhead names no boss for it'); continue; }
    B = I.bosses.find((b) => b.trash) || { name: 'Trash mobs', trash: true, ids: new Set(), create: true };
    if (B.create) I.bosses.push(B);
  }
  seen.add(k);
  if (B.ids.has(x.id)) continue;
  B.ids.add(x.id);
  const key = `${I.key}|${B.name}`;
  (add.get(key) || add.set(key, []).get(key)).push(x.id);
  if (!L.items.has(x.id)) newItems.set(x.id, w);
  report.added.push({ ...row, boss: B.name, wowhead: drops.map((s) => s.n || 'instance').join(', ') });
}

// Write: item details first, then the boss and trash entries.
const lines = L.lines.slice();
const itemsStart = lines.findIndex((l) => l.startsWith('ns.Loot.items = {'));
const itemsEnd = lines.indexOf('}', itemsStart);
const nil = (v, f = String) => (v == null ? 'nil' : f(v));
const q = (s) => JSON.stringify(s);
const itemLines = new Map();
for (let n = itemsStart + 1; n < itemsEnd; n++) { const m = lines[n].match(/^  \[(\d+)\]/); if (m) itemLines.set(+m[1], lines[n]); }
for (const [id, w] of newItems) itemLines.set(id, `  [${id}] = { ${q(w.n)}, ${nil(w.q)}, nil, nil, nil, ${nil(w.ilvl)}, ${nil(w.req)}, ${id >= 250000 ? 1 : 0} },`);
const sortedItems = [...itemLines.keys()].sort((a, b) => a - b).map((id) => itemLines.get(id));
const edits = []; // [line, replacement lines]
for (const I of L.insts) {
  let created = null;
  for (const B of I.bosses) {
    const ids = add.get(`${I.key}|${B.name}`);
    if (!ids) continue;
    if (B.create) { created = `    { name = "Trash mobs", trash = true, items = { ${ids.join(', ')} } },`; continue; }
    edits.push([B.line, [lines[B.line].replace(/items = \{ *\}/, 'items = {  }').replace(/(items = \{ )( ?)(.*?) \} \}(,?)$/, (m, a, sp, list, c) => `${a}${list ? `${list}, ` : ''}${ids.join(', ')} } }${c}`)]]);
  }
  if (created) {
    // after the instance's last boss line
    const last = Math.max(...I.bosses.filter((b) => b.line != null).map((b) => b.line));
    edits.push([last, [lines[last], created]]);
  }
}
for (const [n, rep] of edits.sort((a, b) => b[0] - a[0])) lines.splice(n, 1, ...rep);
lines.splice(itemsStart + 1, itemsEnd - itemsStart - 1, ...sortedItems);
if (report.added.length && !lines.some((l) => l.includes('atlasloot-additions.mjs')))
  lines.splice(lines.findIndex((l) => l.startsWith('-- Boss tables follow AtlasLoot')) + 1, 0,
    '-- AtlasLoot leads the main build left out are checked again on Wowhead Forever\'s item lists (tools/loot/atlasloot-additions.mjs).');
fs.writeFileSync(LOOT, lines.join('\n'));
writeJson('out/atlasloot-additions.json', report);
console.log(`AtlasLoot additions: ${report.added.length} drops added (${newItems.size} new items), ${report.leftOut.length} leads left out (tools/out/atlasloot-additions.json)`);
