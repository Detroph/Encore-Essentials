// Dungeon Journal (ForeverDungeonJournal by Exehn): its hand-kept boss and loot lists, the first loot source.
// Reads Data/Dungeons.lua and Data/SharedLoot.lua from a Dungeon Journal folder (the addon in AddOns, or a clone of
// its repository) as text; they are never run. The folder comes from tools/refresh.config.json ("dungeonJournal"),
// or the DUNGEON_JOURNAL environment variable.
//   Boss loot ("loot") is own loot; "probableLoot" (not seen yet) and the shared BoE helms (SharedLoot.lua) are
//   random drops. Bosses marked trash are the instance's trash loot.
import fs from 'node:fs';
import path from 'node:path';
import { readLuaTables } from './lua-table.mjs';
import { refreshConfig } from '../refresh-config.mjs';

export function djFolder() {
  const dir = process.env.DUNGEON_JOURNAL || refreshConfig().dungeonJournal;
  if (!dir) return null;
  return fs.existsSync(path.join(dir, 'Data', 'Dungeons.lua')) ? dir : null;
}

const ids = (list) => (Array.isArray(list) ? list : Object.values(list || {}))
  .map((e) => (Array.isArray(e) ? e : e && typeof e === 'object' ? Object.keys(e).filter((k) => /^\d+$/.test(k)).map((k) => e[k]) : null))
  .filter((a) => a && typeof a[0] === 'number');

export function djLoot(dir = djFolder()) {
  if (!dir) return null;
  const src = fs.readFileSync(path.join(dir, 'Data', 'Dungeons.lua'), 'utf8');
  const t = readLuaTables(src);
  const dungeons = {};
  for (const [k, v] of Object.entries(t)) {
    if (k === 'FDJ.DB') { for (const [n, d] of Object.entries(v)) if (d && typeof d === 'object' && d.bosses) dungeons[n] = d; }
    else { const m = k.match(/^(?:FDJ\.)?DB\["(.+)"\]$/); if (m && v && v.bosses) dungeons[m[1]] = v; }
  }
  const names = {}; // item ID -> [name, quality]
  const out = [];
  for (const [name, d] of Object.entries(dungeons)) {
    const lv = String(d.level || '').split('-').map(Number).filter(Boolean);
    const bosses = (Array.isArray(d.bosses) ? d.bosses : Object.values(d.bosses)).filter((b) => b && b.name).map((b) => {
      const read = (list) => ids(list).map((a) => { if (!names[a[0]]) names[a[0]] = [a[1], a[3]]; return a[0]; });
      return {
        name: b.name, npc: typeof b.npcID === 'number' ? b.npcID : null, trash: !!b.trash,
        // A rare spawn; rare with a rareLabel marks a summoned quest boss instead (e.g. "0.5 Quest Event").
        rare: b.rare === true && !b.rareLabel,
        aliases: (Array.isArray(b.aliases) ? b.aliases : []).filter((x) => typeof x === 'string'),
        items: read(b.loot), probable: read(b.probableLoot), shared: [],
      };
    });
    out.push({ name, levels: lv.length ? lv : null, bosses });
  }
  // Shared BoE helms: { itemID, name, { [dungeon variable] = { boss names } } }
  const shPath = path.join(dir, 'Data', 'SharedLoot.lua');
  if (fs.existsSync(shPath)) {
    const sh = fs.readFileSync(shPath, 'utf8');
    const vars = {};
    for (const m of sh.matchAll(/^local\s+([\w, ]+?)\s*=\s*(".*)$/gm)) {
      const ns = m[1].split(',').map((s) => s.trim()), vs = [...m[2].matchAll(/"([^"]+)"/g)].map((x) => x[1]);
      ns.forEach((n, i) => { if (vs[i]) vars[n] = vs[i]; });
    }
    const shared = readLuaTables(sh).SHARED || [];
    for (const e of shared) {
      const [id, iname, where] = Array.isArray(e) ? e : [e[1], e[2], e[3]];
      if (typeof id !== 'number') continue;
      if (!names[id]) names[id] = [iname, 3];
      for (const [k, list] of Object.entries(where || {})) {
        const inst = k.startsWith('$') ? vars[k.slice(1)] : k;
        const d = out.find((x) => x.name === inst);
        if (!d) continue;
        for (const bn of Array.isArray(list) ? list : []) {
          const b = d.bosses.find((x) => x.name === bn || x.aliases.includes(bn));
          if (b) b.shared.push(id);
        }
      }
    }
  }
  const toc = path.join(dir, 'ForeverDungeonJournal.toc');
  const version = fs.existsSync(toc) ? (fs.readFileSync(toc, 'utf8').match(/^## Version:\s*(.+)$/m) || [])[1]?.trim() : null;
  return { version, dungeons: out, names };
}
