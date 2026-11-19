// Double-checks EncoreEssentials_DB/Data/Recipes.lua (ForeverDB) against Wowhead Forever's item tooltips, the project's rule for
// professions: ForeverDB first, then check everything with Wowhead Forever. Changes nothing; writes a report.
//   - recipe items Wowhead Forever does not know (not live in Forever, or a wrong ID);
//   - recipe items whose Wowhead profession or skill level differs from ForeverDB's;
//   - crafted items Wowhead Forever does not know.
// Usage: node tools/loot/check-recipes.mjs [--fetch]  ->  tools/out/recipes-check.json
//   --fetch first fetches the tooltips of the recipe and crafted items not in out/wowhead-items.json yet (8 s apart).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { readJson, writeJson } from './net.mjs';
import { readLuaTables } from './lua-table.mjs';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(DIR, '..', '..');
const R = readLuaTables(fs.readFileSync(path.join(REPO, 'EncoreEssentials_DB', 'Data', 'Recipes.lua'), 'utf8'))['ns.Recipes'] || {};
const list = [];
for (const [prof, rs] of Object.entries(R)) for (const r of rs) {
  list.push({ prof, spell: r[0], name: r[1], skill: typeof r[2] === 'number' ? r[2] : null, makes: typeof r[6] === 'number' ? r[6] : null, item: typeof r[9] === 'number' ? r[9] : null });
}
const ids = [...new Set(list.flatMap((r) => [r.item, r.makes]).filter(Boolean))].sort((a, b) => a - b);
if (process.argv.includes('--fetch') && !fs.existsSync(path.join(DIR, 'wowhead-items.mjs'))) {
  console.log('skipped --fetch: wowhead-items.mjs comes from the separate encore-data-tools project');
} else if (process.argv.includes('--fetch')) {
  const idFile = writeJson('out/recipe-item-ids.json', ids);
  const r = spawnSync(process.execPath, [path.join(DIR, 'wowhead-items.mjs'), idFile, '--missing'], { stdio: 'inherit' });
  if (r.status) process.exit(r.status);
}
let wh = {};
try { wh = readJson('out/wowhead-items.json'); } catch { /* none yet */ }
const report = { checked: 0, notFetched: [], recipeItemNotOnWowhead: [], craftedNotOnWowhead: [], professionDiffers: [], skillDiffers: [] };
for (const r of list) {
  report.checked++;
  if (r.item) {
    const w = wh[r.item];
    if (!w) report.notFetched.push(r.item);
    else if (w.unknown) report.recipeItemNotOnWowhead.push({ prof: r.prof, recipe: r.name, item: r.item });
    else if (w.skill) {
      if (w.skill[0] !== r.prof) report.professionDiffers.push({ recipe: r.name, item: r.item, foreverdb: r.prof, wowhead: w.skill[0] });
      else if (r.skill != null && w.skill[1] !== r.skill) report.skillDiffers.push({ prof: r.prof, recipe: r.name, item: r.item, foreverdb: r.skill, wowhead: w.skill[1] });
    }
  }
  if (r.makes) {
    const w = wh[r.makes];
    if (!w) report.notFetched.push(r.makes);
    else if (w.unknown) report.craftedNotOnWowhead.push({ prof: r.prof, recipe: r.name, makes: r.makes });
  }
}
report.notFetched = [...new Set(report.notFetched)].sort((a, b) => a - b);
writeJson('out/recipes-check.json', report);
console.log(`${report.checked} recipes checked against Wowhead Forever: ${report.recipeItemNotOnWowhead.length} recipe items and ${report.craftedNotOnWowhead.length} crafted items not on Wowhead, ${report.professionDiffers.length} profession and ${report.skillDiffers.length} skill level differences`);
if (report.notFetched.length) console.log(`${report.notFetched.length} items not fetched from Wowhead yet: run with --fetch`);
console.log('wrote tools/out/recipes-check.json');
