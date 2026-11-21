// AtlasLoot Continued (WoW Forever port): which items its PvP, Collections and Factions modules list, and its rogue
// poisons, used only as leads for build-extras.mjs. AtlasLoot is GPL v2 only and Encore Essentials is GPL-3.0, so
// nothing from AtlasLoot is copied into the addon: only the item, item set and spell IDs are read, to know which
// Wowhead Forever pages to look at. An item ships only when Wowhead Forever shows a source for it in WoW Forever,
// and everything the addon shows about it (name, vendor, price, standing, group) comes from Wowhead Forever.
//
// Reads, as text (never run, never bundled), from the AddOns folder in tools/refresh.config.json ("atlasLoot") or the
// ATLASLOOT environment variable:
//   AtlasLootContinued_PvP/data-forever.lua          battlegrounds and honor rewards
//   AtlasLootContinued_Collections/data-forever.lua  mounts, companions, tabards, legendaries, item sets
//   AtlasLootContinued_Factions/data.lua             reputation rewards (its data-forever.lua is still empty)
//   AtlasLootContinued_Crafting/data-forever.lua     rogue poisons
// World events are left out on purpose: none have run in WoW Forever yet (Det, 2026-11-21).
// Writes tools/out/extras-leads.json. Usage: node tools/loot/atlasloot-extras.mjs
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { refreshConfig } from '../refresh-config.mjs';
import { writeJson } from './net.mjs';

const FILES = {
  pvp: 'AtlasLootContinued_PvP/data-forever.lua',
  collections: 'AtlasLootContinued_Collections/data-forever.lua',
  factions: 'AtlasLootContinued_Factions/data.lua',
  crafting: 'AtlasLootContinued_Crafting/data-forever.lua',
};

// The AtlasLoot blocks used, and what Encore-DB calls them. Section names are only used to tell sections apart
// (e.g. which standing a PvP section is); the addon labels everything from Wowhead Forever data.
const PVP = ['WarsongGulchForever', 'AlteracValleyForever', 'ArathiBasinForever', 'ArmorForever', 'WeaponsForever', 'PvPMountsForever', 'InsigniaForever'];
const PVP_SETS = ['ClassSetsForever'];
const COLLECTIONS = ['MountsForever', 'CompanionsForever', 'TabardsForever', 'LegendarysForever'];
const SETS = ['ZGSetsForever', 'AQSetsForever', 'MiscSetsForever'];
// Sections never used: not obtainable, or world events (not run in Forever yet).
const SKIP_SECTION = /Unobtainable|World Events|Seasonal/i;

export function atlasLootDir() {
  const dir = process.env.ATLASLOOT || refreshConfig().atlasLoot;
  if (!dir) return null;
  return fs.existsSync(path.join(dir, FILES.pvp)) ? dir : null;
}

// A section's label: the first quoted string in its name expression (AL["Faction Mounts"] -> "Faction Mounts"),
// or the standing for _G["FACTION_STANDING_LABEL8"].
const STANDING_LABEL = { 3: 'Unfriendly', 4: 'Neutral', 5: 'Friendly', 6: 'Honored', 7: 'Revered', 8: 'Exalted' };
function label(expr) {
  const st = expr.match(/FACTION_STANDING_LABEL(\d)/);
  if (st) return STANDING_LABEL[st[1]] || 'Standing ' + st[1];
  const q = expr.match(/\["([^"]+)"\]/) || expr.match(/"([^"]+)"/);
  return q ? q[1] : expr.trim();
}

// data["Key"] = { ... items = { { name = ..., [X_DIFF] = { { slot, id }, ... } }, ... } }
export function blocks(file) {
  const src = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n').replace(/--\[\[[^]*?\]\]/g, '');
  const out = {};
  for (const part of src.split(/\ndata\["/).slice(1)) {
    const key = part.slice(0, part.indexOf('"'));
    const isSet = /TableType = SET_ITTYPE/.test(part.slice(0, part.indexOf('items = {') + 1 || part.length));
    const faction = part.match(/^\tFactionID = (\d+)/m);
    const sections = [];
    let cur = null;
    for (const line of part.split('\n')) {
      if (/^\t\t\{/.test(line)) { cur = { name: '', ids: [] }; sections.push(cur); continue; }
      const nm = line.match(/^\t\t\tname = (.+?),?\s*$/);
      if (nm && cur && !cur.name) { cur.name = label(nm[1]); continue; }
      const row = line.match(/^\s*\{\s*\d+,\s*(\d+)\s*[,}]/);
      if (row && cur && !cur.ids.includes(+row[1])) cur.ids.push(+row[1]);
    }
    out[key] = { set: isSet, faction: faction ? +faction[1] : null, sections: sections.filter((s) => s.ids.length) };
  }
  return out;
}

export function atlasLootExtras(dir = atlasLootDir()) {
  if (!dir) return null;
  const read = (k) => blocks(path.join(dir, FILES[k]));
  const pvp = read('pvp'), col = read('collections'), fac = read('factions'), craft = read('crafting');
  const pick = (all, keys) => keys.filter((k) => all[k]).map((k) => ({
    key: k.replace(/Forever$/, ''),
    sections: all[k].sections.filter((s) => !SKIP_SECTION.test(s.name)),
  }));
  const leads = {
    source: dir,
    read: new Date().toISOString().slice(0, 10),
    pvp: pick(pvp, PVP),
    collections: pick(col, COLLECTIONS),
    sets: [...pick(pvp, PVP_SETS).map((b) => ({ ...b, pvp: true })), ...pick(col, SETS)],
    factions: Object.entries(fac).map(([k, b]) => ({ key: k, faction: b.faction, sections: b.sections })),
    poisons: (craft.RoguePoisonsForever?.sections || []).flatMap((s) => s.ids),
  };
  const ids = new Set();
  for (const g of [...leads.pvp, ...leads.collections, ...leads.factions]) for (const s of g.sections) for (const id of s.ids) ids.add(id);
  leads.itemIds = [...ids].sort((a, b) => a - b);
  leads.setIds = [...new Set(leads.sets.flatMap((b) => b.sections.flatMap((s) => s.ids)))].sort((a, b) => a - b);
  return leads;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const l = atlasLootExtras();
  if (!l) { console.log('No AtlasLoot folder: set "atlasLoot" in tools/refresh.config.json or ATLASLOOT'); process.exit(1); }
  writeJson('out/extras-leads.json', l);
  console.log(`AtlasLoot leads: ${l.itemIds.length} items, ${l.setIds.length} item sets, ${l.poisons.length} poisons -> tools/out/extras-leads.json`);
}
