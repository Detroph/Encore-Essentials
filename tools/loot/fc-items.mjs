// Where an item comes from, from foreverchanges.pro item pages ("Where it comes from": drops, containers,
// vendors and quests, with the rates their players recorded in Forever). Used for recipe sources.
// Usage: node tools/loot/fc-items.mjs [profession.json ...]  ->  tools/out/fc-items.json
// Each profession file is a prof.py output; the recipe item IDs are read from its recipeItems.
import { get, writeJson, readJson, decode } from './net.mjs';

const strip = (s) => decode((s || '').replace(/<[^>]+>/g, '')).trim();

export function parseSources(html) {
  const sec = html.match(/<section class="it-from" aria-labelledby="h-from">([\s\S]*?)<\/section>/);
  if (!sec) return [];
  const out = [];
  for (const g of sec[1].matchAll(/<div class="it-from-group"><h3>(.*?)<\/h3><ul>([\s\S]*?)<\/ul><\/div>/g)) {
    const type = strip(g[1]);
    for (const li of g[2].matchAll(/<li>([\s\S]*?)<\/li>/g)) {
      const b = li[1];
      const link = b.match(/<a href="\/(item|npc|quest|object)\/(\d+)[^"]*"[^>]*>(.*?)<\/a>/);
      const name = link ? strip(link[3]) : strip((b.match(/<b>(.*?)<\/b>/) || [])[1]);
      const spans = [...b.matchAll(/<span>(.*?)<\/span>/g)].map((m) => strip(m[1]));
      const rate = strip((b.match(/<em[^>]*>(.*?)<\/em>/) || [])[1]);
      const e = { type, name };
      if (link) e[link[1]] = +link[2];
      if (spans.length) e.where = spans.join(', ');
      if (rate) e.rate = rate;
      out.push(e);
    }
  }
  return out;
}

// Without arguments: the recipe items build-recipes.mjs found no ForeverDB Forever source for (out/recipes-report.json).
// Earlier results in out/fc-items.json are kept.
const ids = new Set();
for (const f of process.argv.slice(2)) {
  for (const r of readJson(f)) (r.recipeItems || []).forEach((i) => ids.add(i.id));
}
if (!process.argv[2]) readJson('out/recipes-report.json').noSource.forEach((id) => ids.add(id));
let out = {};
try { out = readJson('out/fc-items.json'); } catch { /* first run */ }
let n = 0;
for (const id of [...ids].sort((a, b) => a - b)) {
  const r = await get(`https://foreverchanges.pro/item/${id}`);
  out[id] = r.status === 200 ? parseSources(r.body) : null;
  if (++n % 25 === 0) console.log(`${n}/${ids.size}`);
}
const none = [...ids].filter((id) => !out[id] || !out[id].length).length;
console.log(`done: ${ids.size} items, ${none} with no known source`);
console.log('wrote', writeJson('out/fc-items.json', out));
