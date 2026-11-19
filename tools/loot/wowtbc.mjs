// Boss loot lists from wowtbc.gg's WoW Forever loot tables (Gatsby page-data JSON).
// Covers the dungeons and the raids, including the new Forever dungeons foreverchanges.pro has no loot for.
// Usage: node tools/loot/wowtbc.mjs  ->  tools/out/wowtbc.json
import { get, writeJson } from './net.mjs';

const BASE = 'https://wowtbc.gg';
const out = [];
for (const section of ['dungeons', 'raids']) {
  const list = await get(`${BASE}/warcraftforever/loot-tables/${section}/`);
  const slugs = [...new Set([...list.body.matchAll(new RegExp(`href="/warcraftforever/loot-tables/${section}/([a-z0-9-]+)/"`, 'g'))].map((m) => m[1]))];
  for (const slug of slugs) {
    const r = await get(`${BASE}/page-data/warcraftforever/loot-tables/${section}/${slug}/page-data.json`);
    if (r.status !== 200) { console.warn('skip', slug, r.status); continue; }
    const pc = JSON.parse(r.body).result.pageContext;
    for (const l of pc.loot || []) {
      const items = {};
      for (const g of pc.gearData || []) items[g.id] = { name: g.name, discovered: g.discovered, source: g.source };
      out.push({
        key: slug, section, name: l.dungeon || l.raid, levels: l.levels, size: l.type, new: !!l.new,
        bosses: (l.bosses || []).map((b) => ({ name: b.name, items: b.items || [] })),
        quests: (l.quests || []).map((q) => ({ name: q.name, items: q.items || [], level: q.level, faction: q.faction })),
        items, source: `${BASE}/warcraftforever/loot-tables/${section}/${slug}/`,
      });
      console.log(`${section}/${l.dungeon || l.raid}: ${l.bosses.length} bosses, ${l.bosses.reduce((n, b) => n + (b.items || []).length, 0)} items`);
    }
  }
}
console.log('wrote', writeJson('out/wowtbc.json', out));
