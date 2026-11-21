// AtlasLoot Continued (WoW Forever port): its boss and loot lists, used as a cross-check only.
// AtlasLoot Continued is GPL v2 only, and Encore Essentials is GPL-3.0 (it bundles ForeverDB and QuestieDB data, both
// GPL-3.0). The two licences cannot be combined, so nothing from AtlasLoot is copied into the addon: build-loot.mjs
// uses these lists as leads, and an entry is only kept when Wowhead Forever confirms it (its item tooltip names the boss,
// or the boss's Wowhead page lists the drop). The rest goes to tools/out/atlasloot-check.json for a person to look at.
//
// Reads AtlasLootContinued_DungeonsAndRaids/data-forever.lua from the installed addon as text; it is never run and never
// bundled. The folder comes from tools/refresh.config.json ("atlasLoot": the AddOns folder, or the
// AtlasLootContinued_DungeonsAndRaids folder itself), or the ATLASLOOT environment variable.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { refreshConfig } from '../refresh-config.mjs';

const FILE = 'data-forever.lua';
const SUB = 'AtlasLootContinued_DungeonsAndRaids';

export function atlasLootFile() {
  const dir = process.env.ATLASLOOT || refreshConfig().atlasLoot;
  if (!dir) return null;
  for (const f of [path.join(dir, FILE), path.join(dir, SUB, FILE)]) if (fs.existsSync(f)) return f;
  return null;
}

// "TheTempleOfAtal'HakkarForever" -> "The Temple Of Atal'Hakkar"
const fromKey = (k) => k.replace(/Forever$/, '').replace(/([a-z])([A-Z])/g, '$1 $2');

export function atlasLoot(file = atlasLootFile()) {
  if (!file) return null;
  const src = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
  const dungeons = [];
  const names = {}; // item ID -> name, from AtlasLoot's line comments (only to label the check report)
  for (const block of src.split(/\ndata\["/).slice(1)) {
    const key = block.slice(0, block.indexOf('"'));
    const head = block.slice(0, block.indexOf('\titems = {') >= 0 ? block.indexOf('\titems = {') : block.length);
    const nm = head.match(/^\tname = AL\["([^"]+)"\]/m);
    const inst = head.match(/^\tInstanceID = (\d+)/m);
    const lr = head.match(/LevelRange = (?:GetForVersion\()?\{\s*(\d+),\s*(\d+),\s*(\d+)/);
    const bosses = [];
    // A boss: { name = AL["..."], npcID = n, ..., [NORMAL_DIFF] = { { slot, itemID }, ... }, }
    for (const m of block.matchAll(/\n\t\t\{[^\n]*\n\t\t\tname = (?:AL\["([^"]+)"\]|"([^"]+)")[^]*?\[NORMAL_DIFF\] = \{([^]*?)\n\t\t\t\},/g)) {
      const name = m[1] || m[2];
      const before = m[0].slice(0, m[0].indexOf('[NORMAL_DIFF]'));
      const npc = before.match(/npcID = \{?\s*(\d+)/);
      const items = [];
      for (const r of m[3].matchAll(/\{\s*\d+,\s*(\d{2,7})\s*\}\s*,?\s*(?:--\s*(.+))?/g)) {
        const id = +r[1];
        if (!items.includes(id)) items.push(id);
        if (r[2] && !names[id]) names[id] = r[2].trim();
      }
      if (/^Coming Soon$/i.test(name) || !items.length) continue;
      bosses.push({ name, npc: npc ? +npc[1] : null, trash: /^trash( mobs)?$/i.test(name), items });
    }
    if (bosses.length) dungeons.push({ key, name: nm ? nm[1] : fromKey(key), instance: inst ? +inst[1] : null, levels: lr ? [+lr[2], +lr[3]] : null, bosses });
  }
  const ver = src.match(/-- *Version:? *([\w.-]+)/i);
  return { file, version: ver ? ver[1] : fs.statSync(file).mtime.toISOString().slice(0, 10), dungeons, names };
}

// node tools/loot/atlasloot-loot.mjs: print what was read.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const a = atlasLoot();
  if (!a) { console.log('No AtlasLoot folder: set "atlasLoot" in tools/refresh.config.json or ATLASLOOT'); process.exit(1); }
  const n = a.dungeons.reduce((s, d) => s + d.bosses.reduce((t, b) => t + b.items.length, 0), 0);
  console.log(`AtlasLoot ${a.version}: ${a.dungeons.length} instances, ${a.dungeons.reduce((s, d) => s + d.bosses.length, 0)} bosses, ${n} entries`);
}
