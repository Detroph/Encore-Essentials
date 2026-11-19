// NPC levels from QuestieDB (https://github.com/Questie/QuestieDB, GPL-3.0), its WoW Forever database, for the
// level shown on each boss portrait. Project rule (2026-11-19): boss levels come from QuestieDB.
// Usage: node tools/loot/questie-levels.mjs        -> tools/out/npc-levels.json
//
// Needs a QuestieDB checkout (default tools/cache/questiedb; QUESTIEDB=<path> or "questieDB" in
// tools/refresh.config.json overrides it):
//   git clone --depth 1 https://github.com/Questie/QuestieDB tools/cache/questiedb
// and Lua 5.1: QUESTIE_LUA=<path>, else the one QuestieDB ships in tools/lua-binary, else `lua` on PATH.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { refreshConfig } from '../refresh-config.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const cfg = refreshConfig();
const checkout = path.resolve(process.env.QUESTIEDB || cfg.questieDB || path.join(ROOT, 'tools', 'cache', 'questiedb'));
if (!fs.existsSync(path.join(checkout, 'data', 'Forever', 'foreverNpcDB.lua'))) {
  console.error(`No QuestieDB checkout at ${checkout}: git clone --depth 1 https://github.com/Questie/QuestieDB tools/cache/questiedb`);
  process.exit(1);
}
function lua() {
  if (process.env.QUESTIE_LUA) return process.env.QUESTIE_LUA;
  const bin = path.join(checkout, 'tools', 'lua-binary');
  const own = process.platform === 'win32' ? path.join(bin, 'lua.exe') : path.join(bin, `${process.platform}-${process.arch}`, 'lua');
  return fs.existsSync(own) ? own : 'lua';
}
const out = execFileSync(lua(), [path.join(HERE, 'questie-levels.lua'), checkout], { maxBuffer: 1 << 27, encoding: 'utf8' });
const npcs = JSON.parse(out);
let version = new Date().toISOString().slice(0, 10);
try { version = 'QuestieDB@' + execFileSync('git', ['-C', checkout, 'log', '-1', '--format=%h %cs'], { encoding: 'utf8' }).trim(); } catch {}
const file = path.join(ROOT, 'tools', 'out', 'npc-levels.json');
fs.mkdirSync(path.dirname(file), { recursive: true });
fs.writeFileSync(file, JSON.stringify({ source: version, npcs }));
console.log(`npc-levels.json: ${Object.keys(npcs).length} NPCs from ${version}`);
