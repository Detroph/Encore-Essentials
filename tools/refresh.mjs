// Refreshes Encore-DB's data from its sources, in the project's source order, so an update needs no Claude session:
//   quests       QuestieDB first, Wowhead Forever fills in blanks          (tools/quests/build-quests.mjs)
//   loot         ForeverDB, foreverchanges.pro, Wowhead Forever; the Dungeon Journal only as a cross-check
//                of gaps (tools/out/dj-check.json)                          (tools/loot/build-loot.mjs)
//                Boss levels: QuestieDB first, Wowhead Forever fills blanks (tools/loot/questie-levels.mjs)
//   professions  ForeverDB first, then everything checked against Wowhead Forever
//                                                                           (build-recipes.mjs, check-recipes.mjs)
// Settings: tools/refresh.config.json (copy refresh.config.example.json). See tools/README.md, "Refreshing the data".
//
// Usage: node tools/refresh.mjs <step> [--download]
//   all             quests, loot and professions
//   quests | loot | professions
//   wowhead-script  writes tools/out/wowhead-sweep.js, to paste into the browser console on wowhead.com/forever
//   import <files>  reads the wowhead-drops-*.json files the browser script downloaded
// --download first downloads the sources again: the ForeverDB files, foreverchanges.pro pages and missing Wowhead
// item tooltips (slow: one page every few seconds). Without it the cached downloads in tools/cache and tools/out are used.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { refreshConfig } from './refresh-config.mjs';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const cfg = refreshConfig();
const [step = 'help', ...rest] = process.argv.slice(2);
const download = rest.includes('--download');
const files = rest.filter((a) => !a.startsWith('--'));
const env = { ...process.env };
if (cfg.dungeonJournal && !env.DUNGEON_JOURNAL) env.DUNGEON_JOURNAL = cfg.dungeonJournal;
if (cfg.atlasLoot && !env.ATLASLOOT) env.ATLASLOOT = cfg.atlasLoot;

function run(script, ...args) {
  const file = path.join(DIR, script);
  if (!fs.existsSync(file)) { console.log(`skipped: ${script} is not in this checkout`); return false; }
  console.log(`\n> node tools/${script} ${args.join(' ')}`);
  const r = spawnSync(process.execPath, [file, ...args], { stdio: 'inherit', env });
  if (r.status) { console.error(`${script} failed (exit ${r.status})`); process.exit(r.status); }
  return true;
}

// QuestieDB checkout for boss levels: cloned or updated with --download, then read by questie-levels.mjs.
function levels() {
  const checkout = path.resolve(env.QUESTIEDB || cfg.questieDB || path.join(DIR, 'cache', 'questiedb'));
  if (download) {
    const git = fs.existsSync(path.join(checkout, '.git'))
      ? ['-C', checkout, 'pull', '--ff-only', '-q']
      : ['clone', '--depth', '1', '-q', 'https://github.com/Questie/QuestieDB', checkout];
    console.log(`\n> git ${git.join(' ')}`);
    spawnSync('git', git, { stdio: 'inherit' });
  }
  if (!fs.existsSync(path.join(checkout, 'data', 'Forever', 'foreverNpcDB.lua'))) {
    console.log(`\nNo QuestieDB checkout at ${checkout}: building without boss levels. Run with --download to fetch it.`);
    return;
  }
  env.QUESTIEDB = checkout;
  run('loot/questie-levels.mjs');
}

const steps = {
  quests() {
    run('quests/build-quests.mjs');
  },
  loot() {
    const src = new Set(cfg.lootSources || ['dungeon-journal-check', 'atlasloot', 'foreverdb', 'foreverchanges', 'wowhead']);
    if (download) {
      run('loot/foreverdb-files.mjs');
      if (src.has('foreverchanges')) run('loot/fc-dungeons.mjs');
      if (src.has('wowtbc')) run('loot/wowtbc.mjs');
      run('loot/wowhead-items.mjs', '--missing');
    }
    levels();
    if (!fs.existsSync(path.join(DIR, 'out', 'wowhead-drops.json')))
      console.log('\nNo tools/out/wowhead-drops.json yet: building without Wowhead boss pages. Run "node tools/refresh.mjs wowhead-script" for them.');
    run('loot/build-loot.mjs');
  },
  professions() {
    if (download) run('loot/foreverdb-files.mjs');
    run('loot/build-recipes.mjs');
    run('loot/check-recipes.mjs', ...(download ? ['--fetch'] : []));
  },
  all() { steps.quests(); steps.loot(); steps.professions(); },
  'wowhead-script'() {
    run('loot/wowhead-browser-script.mjs', '--pause', String(cfg.wowheadPauseSeconds || 8));
  },
  import() {
    if (!files.length) { console.error('Usage: node tools/refresh.mjs import <wowhead-drops-1.json> [...]'); process.exit(1); }
    run('loot/wowhead-drops.mjs', '--import', ...files.map((f) => path.resolve(f)));
    console.log('\nNow run: node tools/refresh.mjs all');
  },
  help() {
    console.log(fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
  },
};
if (!steps[step]) { console.error(`Unknown step "${step}".`); steps.help(); process.exit(1); }
if (!cfg.file) console.log('No tools/refresh.config.json: using the defaults (see refresh.config.example.json).');
else if (path.basename(cfg.file) !== 'refresh.config.json') console.log('Using refresh.config.example.json: copy it to refresh.config.json and set your paths.');
steps[step]();
