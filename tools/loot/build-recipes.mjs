// Writes EncoreEssentials_DB/Data/Recipes.lua: every profession's recipes and where their recipe items come from.
//   ForeverDB.net's addon data files, the main source (tools/loot/foreverdb-files.mjs):
//     Recipes.lua: recipes per profession (from the Forever client), how each is learned, trainer costs seen at Forever
//       trainers, Merchant's Favor costs, reputation. Recipes ForeverDB marks as speculation (Season of Discovery) are left out,
//       and so are its Classic drop lists (dr) and skill levels that are Classic trainer data.
//     Items.lua and NPCs.lua: vendors seen selling the recipe item in Forever, drops and quests seen in Forever,
//       required reputation. Entries marked Classic are left out.
//   foreverchanges.pro item pages (out/fc-items.json) fill in recipe items ForeverDB has no Forever source for
//     ("in Classic" groups left out).
// Usage: node tools/loot/build-recipes.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readJson, writeJson } from './net.mjs';
import { readFdb } from './foreverdb-files.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const RF = readFdb('Recipes.lua');
const recipes = RF.tables['ns.recipes'];
const info = RF.tables['ns.recipeInfo'] || {};
const names = RF.tables['ns.names'] || {};
const facts = readFdb('Items.lua').tables['ns.items'] || {};
const npcFile = readFdb('NPCs.lua').tables;
const npcs = npcFile['ns.npcs'] || {};
const sold = npcFile['ns.sold'] || {};
let fc = {};
try { fc = readJson('out/fc-items.json'); } catch { /* not built: no fill-in */ }

const q = (s) => JSON.stringify(s ?? '').replace(/\\u([0-9a-f]{4})/gi, (_, h) => String.fromCharCode(parseInt(h, 16)));
const num = (v) => (v == null || Number.isNaN(+v) ? null : +v);

// Where a recipe item comes from in Forever.
function sourcesOf(item) {
  const out = [];
  for (const p of String(facts[item] ?? '').split('|').filter(Boolean)) {
    const a = p.slice(1).split('~');
    if (p[0] === 'v' && a[3] === '1') {
      // Vendors: ns.sold lists {npc, price, stack, limited supply, ...}; only vendors players saw in Forever are kept.
      const s = sold[item] || [];
      for (let i = 0; i + 3 < s.length; i += 4) {
        const n = npcs[s[i]];
        if (!n || !n[6]) continue;
        out.push({ type: 'vendor', name: n[0], npc: s[i], map: n[2], x: n[3], y: n[4], side: n[5] || null, price: s[i + 1] || null, limited: !!s[i + 3] });
      }
      if (!out.some((e) => e.type === 'vendor') && a[1]) out.push({ type: 'vendor', name: a[1], where: a[2] || null });
    } else if (p[0] === 'd' && a[2] === '0') {
      out.push({ type: 'drop', name: a[0], sources: num(a[3]) });
    } else if (p[0] === 'q' && a[1] === '0') {
      out.push({ type: 'quest', name: a[0] });
    } else if (p[0] === 'r') {
      out.push({ type: 'reputation', name: a[0], standing: num(a[1]) });
    } else if (p[0] === 's') {
      out.push({ type: 'seen', drops: num(a[0]), players: num(a[1]) });
    }
  }
  return out;
}

const FC_TYPE = { 'Creature drop': 'drop', 'Dungeon drop': 'drop', 'Sold by a vendor': 'vendor', 'Found in a container': 'container', 'Quest reward': 'quest' };
const report = { professions: {}, speculationLeftOut: [], recipeItems: 0, fromForeverDB: 0, fromFillIn: 0, noSource: [] };
const R = [], S = [];
const sourceItems = new Set();
const usedNames = new Set();
for (const prof of Object.keys(recipes)) {
  let kept = 0;
  R.push(`  [${q(prof)}] = {`);
  for (const r of recipes[prof]) {
    const [spell, name, skill, yellow, green, grey, makes, count, reagents, learned, , isNew, classicSkill] = r;
    const ri = info[spell] || {};
    if (ri.sp) { report.speculationLeftOut.push(`${prof}: ${name} (${ri.sp})`); continue; }
    kept++;
    const learn = String(learned ?? '');
    const recipeItem = learn[0] === 'i' ? +learn.slice(1) : null;
    if (recipeItem && !ri.mi) sourceItems.add(recipeItem);
    const reag = String(reagents || '').split(',').filter(Boolean).map((x) => x.split(':').map(Number));
    for (const [id] of reag) usedNames.add(id);
    if (makes) usedNames.add(makes);
    if (recipeItem) usedNames.add(recipeItem);
    const f = [
      `${spell}`, q(name), classicSkill ? 'nil' : `${skill ?? 'nil'}`, `${yellow ?? 'nil'}`, `${green ?? 'nil'}`, `${grey ?? 'nil'}`,
      `${makes || 'nil'}`, `${count ?? 'nil'}`, `{ ${reag.map(([id, n]) => `${id}, ${n}`).join(', ')} }`,
      recipeItem ? `${recipeItem}` : learn === 'a' || learn === 't' ? q(learn) : 'nil',
    ];
    const extra = [];
    if (isNew) extra.push('new = true');
    if (ri.c) extra.push('changed = true');
    if (ri.tf && ri.tc) extra.push(`trainerCost = ${ri.tc}`);
    if (ri.fav) extra.push(`favor = ${ri.fav}`);
    if (ri.rp) extra.push(`faction = ${ri.rp}`);
    if (ri.mi) extra.push('notInClient = true');
    R.push(`    { ${f.join(', ')}${extra.length ? `, ${extra.join(', ')}` : ''} },`);
  }
  R.push('  },');
  report.professions[prof] = kept;
}

const fields = (e) => Object.entries(e).filter(([, v]) => v != null && v !== false && v !== '')
  .map(([k, v]) => `${k} = ${typeof v === 'string' ? q(v) : v === true ? 'true' : v}`).join(', ');
for (const item of [...sourceItems].sort((a, b) => a - b)) {
  report.recipeItems++;
  let list = sourcesOf(item);
  const real = list.filter((e) => e.type !== 'seen');
  if (real.length) report.fromForeverDB++;
  else {
    const fill = (fc[item] || []).filter((e) => FC_TYPE[e.type]).map((e) => ({ type: FC_TYPE[e.type], name: e.name === e.type ? '' : e.name, where: e.where, rate: e.rate, from: 'foreverchanges.pro' }));
    if (fill.length) { report.fromFillIn++; list = [...list, ...fill]; }
    else { report.noSource.push(item); if (!list.length) continue; }
  }
  S.push(`  [${item}] = { ${list.map((e) => `{ ${fields(e)} }`).join(', ')} },`);
}

const N = [...usedNames].filter((id) => names[id]).sort((a, b) => a - b).map((id) => `[${id}]=${q(names[id])}`);
const L = [
  RF.header,
  '-- Encore-DB recipes. Generated by tools/loot/build-recipes.mjs: do not edit by hand.',
  `-- Data from ForeverDB.net (https://foreverdb.net), data version ${RF.version}: recipes from the Forever client, how they are`,
  '-- learned, and the vendors, drops and quests players saw in WoW Forever. Its Classic data and speculation are left out.',
  '-- Filled in from foreverchanges.pro item pages, and checked against Wowhead Forever (https://www.wowhead.com/forever). No Classic or emulator data.',
  "-- Licence: GPL-3.0 with ForeverDB.net's attribution term; see NOTICE.txt in this addon.",
  `-- Built ${new Date().toISOString().slice(0, 10)}.`,
  'local _, ns = ...',
  '-- [profession] = { { spell, name, skill, yellow, green, grey, makes (item), count, reagents { item, n, item, n, ... },',
  '--   learned (recipe item ID, "t" trainer, "a" automatic, nil unknown), new, changed (in Forever), trainerCost (copper,',
  '--   seen at a Forever trainer), favor (Merchant\'s Favor), faction (reputation ID), notInClient (recipe item not in the client yet) } }',
  '-- skill is nil where ForeverDB only has Classic trainer data for it.',
  'ns.Recipes = {',
  ...R,
  '}',
  '-- [recipe item] = { sources }. type: vendor (name, npc, map = uiMap ID, x, y, side, price in copper, limited),',
  '--   drop (name of the first source, sources = how many), quest (name), reputation (faction name, standing 1 Hated .. 8 Exalted),',
  '--   seen (drops players saw, players), container. Fill-in entries have where, rate and from = "foreverchanges.pro".',
  'ns.RecipeSources = {',
  ...S,
  '}',
  '-- Item names for the recipe lists (the Forever client).',
  `ns.RecipeNames = { ${N.join(', ')} }`,
];
const file = path.join(REPO, 'EncoreEssentials_DB', 'Data', 'Recipes.lua');
fs.mkdirSync(path.dirname(file), { recursive: true });
fs.writeFileSync(file, L.join('\n') + '\n');
writeJson('out/recipes-report.json', report);
console.log(Object.entries(report.professions).map(([p, n]) => `${p} ${n}`).join(', '));
console.log(`${report.recipeItems} recipe items: ${report.fromForeverDB} with a ForeverDB Forever source, ${report.fromFillIn} filled in, ${report.noSource.length} without a source; ${report.speculationLeftOut.length} speculation recipes left out`);
console.log('wrote', file, `(${Math.round(fs.statSync(file).size / 1024)} KB)`);
