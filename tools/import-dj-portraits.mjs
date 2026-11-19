// One-time import: boss portrait pictures from ForeverDungeonJournal (by Exehn), renamed to the boss's NPC ID.
// Usage: node tools/import-dj-portraits.mjs "<path to AddOns>\ForeverDungeonJournal"
// Writes EncoreEssentials_DB/Media/Portraits/<npc>.tga and EncoreEssentials_DB/Data/Portraits.lua.
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const dj = process.argv[2];
if (!dj) throw new Error('give the ForeverDungeonJournal folder');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const out = path.join(root, 'EncoreEssentials_DB', 'Media', 'Portraits');

// NPC ID -> display ID, and boss name -> NPC ID, from Dungeon Journal's data
const display = new Map();
const npcByName = new Map();
const bosses = fs.readFileSync(path.join(dj, 'Data', 'Bosses.lua'), 'utf8');
const stat = bosses.slice(bosses.indexOf('FDJ.STATIC_DISPLAY_IDS'), bosses.indexOf('FDJ.TRASH_MOB_DISPLAY_IDS'));
for (const m of stat.matchAll(/\[(\d+)\]\s*=\s*(\d+),?[ \t]*(?:--[ \t]*([^\r\n]+))?/g)) {
  display.set(+m[1], +m[2]);
  if (m[3] && !npcByName.has(m[3].trim())) npcByName.set(m[3].trim(), +m[1]);
}
const dungeons = fs.readFileSync(path.join(dj, 'Data', 'Dungeons.lua'), 'utf8');
for (const m of dungeons.matchAll(/npcID\s*=\s*(\d+)[^{}]{0,300}?displayID\s*=\s*(\d+)/g)) {
  if (!display.has(+m[1])) display.set(+m[1], +m[2]);
}
for (const m of dungeons.matchAll(/name\s*=\s*"([^"]+)",\s*npcID\s*=\s*(\d+)/g)) {
  if (!npcByName.has(m[1])) npcByName.set(m[1], +m[2]);
}

// Encore's bosses: their own NPC ID, else the one Dungeon Journal has for the same name
const loot = fs.readFileSync(path.join(root, 'EncoreEssentials_DB', 'Data', 'Loot.lua'), 'utf8');
const npcSet = new Set();
const byName = new Map();
for (const m of loot.slice(loot.indexOf('instances')).matchAll(/\{\s*name\s*=\s*"([^"]+)"(,\s*npc\s*=\s*(\d+))?/g)) {
  if (m[3]) {
    npcSet.add(+m[3]);
  } else if (npcByName.has(m[1])) {
    byName.set(m[1], npcByName.get(m[1]));
    npcSet.add(npcByName.get(m[1]));
  }
}

fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
const have = [];
let missing = 0;
for (const npc of npcSet) {
  const d = display.get(npc);
  const src = d && path.join(dj, 'Media', 'Portraits', d + '.tga');
  if (src && fs.existsSync(src)) {
    fs.copyFileSync(src, path.join(out, npc + '.tga'));
    have.push(npc);
  } else {
    missing++;
  }
}
have.sort((a, b) => a - b);
const haveSet = new Set(have);
const lines = [];
for (let i = 0; i < have.length; i += 10) lines.push('    ' + have.slice(i, i + 10).map((n) => `[${n}]=true,`).join(' '));
const nameLines = [...byName].filter(([, n]) => haveSet.has(n)).sort(([a], [b]) => (a < b ? -1 : 1))
  .map(([name, n]) => `    [${JSON.stringify(name)}] = ${n},`);
fs.writeFileSync(path.join(root, 'EncoreEssentials_DB', 'Data', 'Portraits.lua'),
  '-- Boss portrait pictures in Media/Portraits, named by NPC ID.\n' +
  "-- Pictures from ForeverDungeonJournal by Exehn (photographs of the game's own portraits). See NOTICE.txt.\n" +
  'local _, ns = ...\n' +
  `ns.Portraits = {\n${lines.join('\n')}\n}\n` +
  '-- Bosses Encore has no NPC ID for: boss name -> NPC ID of its picture\n' +
  `ns.PortraitNames = {\n${nameLines.join('\n')}\n}\n`);
console.log(`bosses with an NPC ID ${npcSet.size - byName.size}, matched by name ${byName.size}, pictures ${have.length}, without ${missing}`);
