// Boss-by-boss loot lists from foreverchanges.pro dungeon pages (robots.txt allows /dungeons).
// Only item IDs, boss names and the "New in Forever" mark are taken. The page's drop chances
// are Classic values ("Drop chance in Classic"), so they are ignored: Forever chances come from Wowhead.
// Usage: node tools/loot/fc-dungeons.mjs  ->  tools/out/fc-dungeons.json
import { get, writeJson, decode } from './net.mjs';

const BASE = 'https://foreverchanges.pro';
const SKIP = new Set(['loot', 'sets', 'before', 'quests', 'map', 'comments']);

function parse(slug, html) {
  const title = decode((html.match(/<h1[^>]*>(.*?)<\/h1>/s) || [])[1] || slug).replace(/<[^>]+>/g, '').trim();
  const lv = html.replace(/<[^>]+>/g, ' ').match(/Level\s+(\d+)\s*[–-]\s*(\d+)/);
  const re = /<section[^>]*id="([^"]+)"|<h[2-4][^>]*>(.*?)<\/h[2-4]>|<a [^>]*href="\/item\/(\d+)[^"]*"[^>]*>(.*?)<\/a>/gs;
  // The loot part runs from section "loot" to "sets"; quest sections ("quest-<id>") follow later.
  const sections = [];
  let cur = null, mode = 'pre', m;
  while ((m = re.exec(html))) {
    if (m[1]) {
      const id = m[1];
      if (id === 'loot') { mode = 'loot'; cur = null; continue; }
      if (id === 'sets' || id === 'before') mode = 'post';
      const q = id.match(/^quest-(\d+)$/);
      if (mode === 'loot' && !SKIP.has(id)) cur = { kind: id === 'observed-recipes' ? 'recipes' : 'enc', key: id, name: null, items: [] };
      else if (q) cur = { kind: 'quest', key: id, quest: +q[1], name: null, items: [] };
      else cur = null;
      if (cur) sections.push(cur);
    } else if (m[2] !== undefined) {
      if (cur && cur.name === null) cur.name = decode(m[2].replace(/<[^>]+>/g, '')).replace(/\d+$/, '').trim();
    } else if (m[3] && cur) {
      const id = +m[3];
      if (!cur.items.some((i) => i.id === id)) cur.items.push({ id, new: /lb-mark-new/.test(m[4]) });
    }
  }
  return {
    key: slug, name: title.replace(/\s+WoW Forever.*$/, '').replace(/\s+Location, story.*$/, ''),
    levels: lv ? [+lv[1], +lv[2]] : null,
    encounters: sections.filter((s) => s.kind === 'enc').map((s) => ({
      key: s.key, name: s.name, trash: s.key === 'trash-mobs', items: s.items,
    })),
    recipes: sections.filter((s) => s.kind === 'recipes').flatMap((s) => s.items.map((i) => i.id)),
    quests: sections.filter((s) => s.kind === 'quest').map((s) => ({ id: s.quest, name: s.name, items: s.items.map((i) => i.id) })),
    source: `${BASE}/dungeons/${slug}`,
  };
}

const map = await get(`${BASE}/sitemap.xml`);
const slugs = [...map.body.matchAll(/<loc>https:\/\/foreverchanges\.pro\/dungeons\/([a-z0-9-]+)<\/loc>/g)].map((m) => m[1]);
const out = [];
for (const slug of slugs) {
  const r = await get(`${BASE}/dungeons/${slug}`);
  if (r.status !== 200) { console.warn('skip', slug, r.status); continue; }
  const d = parse(slug, r.body);
  out.push(d);
  console.log(`${d.name}: ${d.encounters.length} encounters, ${d.encounters.reduce((n, e) => n + e.items.length, 0)} items, ${d.recipes.length} recipes`);
}
console.log('wrote', writeJson('out/fc-dungeons.json', out));
