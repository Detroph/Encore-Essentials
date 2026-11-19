// ForeverDB's Loot.lua, keeping only what players saw in WoW Forever.
//   Loot entry "item:pct:src[:h[:kills[:seen]]]": src f = seen in Forever (kept), c = Classic data from CMaNGOS (dropped).
//   pct is a drop rate only when `kills` (looted kills it was measured over) is given; otherwise it is 0 or Classic's.
//   clue lists (client clues, unconfirmed) are dropped.
//   Vendor lists are kept only when ForeverDB players saw the vendor in Forever (fv = true).
import { readFdb } from './foreverdb-files.mjs';

export function fdbLoot() {
  const file = readFdb('Loot.lua');
  const db = file.tables['ns.lootDB'];
  const dropped = { classic: 0, clues: 0, vendors: [] };
  const parse = (s) => (s || '').split(';').filter(Boolean).flatMap((e) => {
    const [id, pct, src, h, kills, seen] = e.split(':');
    if (src !== 'f') { dropped.classic++; return []; }
    const k = kills ? +kills : null;
    return [{ id: +id, chance: k && +pct > 0 ? +pct : null, kills: k, seen: seen ? +seen : null, hidden: h ? +h : null }];
  });
  const instances = db.inst.map((d) => {
    if (d.clue) dropped.clues += d.clue.split(';').filter(Boolean).length;
    const lv = String(d.lv ?? '').split('-').filter(Boolean).map(Number);
    const bosses = d.bosses.map((b) => {
      const items = parse(b.loot);
      return { npc: b.npc, name: b.name, items, kills: Math.max(0, ...items.map((e) => e.kills || 0)) };
    });
    return { id: d.id, name: d.name, kind: d.kind, levels: lv.length ? lv : null, zone: d.zone ?? null, open: !!d.open, new: !!d.forever, bosses, trash: parse(d.trash) };
  });
  const vendors = [];
  for (const v of db.vend) {
    if (!v.fv) { dropped.vendors.push(v.name); continue; }
    const items = v.items.split(';').filter(Boolean).map((e) => {
      const [id, standing, copper] = e.split(':');
      return { id: +id, standing: /^\d+$/.test(standing) ? +standing : standing, copper: +copper || null };
    });
    vendors.push({ kind: v.kind, name: v.name, npc: v.npc ?? null, faction: v.faction ?? null, side: v.side ?? null, items });
  }
  return { header: file.header, version: file.version, built: db.built, standing: db.standing, instances, vendors, dropped };
}

// Every item ID in the kept data (for fetching item details).
export function fdbLootIds() {
  const { instances, vendors } = fdbLoot();
  const ids = new Set();
  for (const d of instances) for (const e of [...d.bosses.flatMap((b) => b.items), ...d.trash]) ids.add(e.id);
  for (const v of vendors) for (const e of v.items) ids.add(e.id);
  return ids;
}
