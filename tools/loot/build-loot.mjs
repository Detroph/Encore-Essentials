// Merges the loot sources into EncoreEssentials_DB/Data/Loot.lua. Source order: the Dungeon Journal first,
// then ForeverDB, then Wowhead Forever for blanks. Which sources run: "lootSources" in tools/refresh.config.json.
//   Dungeon Journal (ForeverDungeonJournal by Exehn, tools/loot/dj-loot.mjs), when its folder is set: its hand-kept boss
//     loot is each boss's own loot; its probable and shared drops are random drops. Bosses are matched to ForeverDB's by
//     NPC ID, then by name; ForeverDB's instance and boss names are kept.
//   ForeverDB.net's addon data files (tools/loot/foreverdb-files.mjs), the main source: Loot.lua's instances, bosses in the
//     client's order with their NPC IDs, the drops players' ForeverDB addons saw in WoW Forever with drop rates per looted kill,
//     and the reputation and PvP vendors players saw. Its Classic data (CMaNGOS) and unconfirmed client clues are not used.
//     Item names and qualities where Wowhead has none: Dungeons.lua (the Forever client), then SearchNames.lua.
//     New and changed items: Items.lua.
//   foreverchanges.pro (out/fc-dungeons.json) and wowtbc.gg (out/wowtbc.json): fill in bosses and items ForeverDB has not seen yet,
//     and instances it does not list.
//   Wowhead Forever tooltips (out/wowhead-items.json): item name, quality, icon, slot and levels, and a drop chance
//     where ForeverDB has none and Wowhead names that same boss as the dropper.
//   Wowhead Forever pages (out/wowhead-drops.json, tools/loot/wowhead-drops.mjs), when present:
//     - each boss's Drops tab: drops ForeverDB has not seen, and drop chances where Wowhead counted far more kills;
//       a fill-in boss tie Wowhead contradicts (no drop in 1,000+ kills) is dropped, and trash loot that one boss
//       clearly drops moves to that boss;
//     - profession recipes that drop from bosses in two or more instances are the level range's shared recipe drops:
//       listed once per instance (recipes), not under every boss;
//     - reputation rewards (faction pages) for factions ForeverDB players have not seen yet, and the world drops.
// Each boss gets two lists: items (its own loot) and also (random world drops players saw from it).
// Usage: node tools/loot/build-loot.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readJson, writeJson } from './net.mjs';
import { readFdb } from './foreverdb-files.mjs';
import { fdbLoot } from './fdb-loot.mjs';
import { djLoot, djFolder } from './dj-loot.mjs';
import { refreshConfig } from '../refresh-config.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const FL = fdbLoot();
const fdb = FL.instances;
const sizes = readFdb('Dungeons.lua').tables['ns.dungeons'];
const dgItems = readFdb('Dungeons.lua').tables['ns.dgItems'] || {};
const searchNames = readFdb('SearchNames.lua').tables['ns.searchItemNames'] || {};
const itemFacts = readFdb('Items.lua').tables['ns.items'] || {};
// Sources to use ("lootSources"): dungeon-journal (a source) or dungeon-journal-check (only compared, in
// out/dj-check.json), foreverdb, foreverchanges, wowtbc, wowhead.
const SOURCES = new Set(refreshConfig().lootSources || ['dungeon-journal-check', 'foreverdb', 'foreverchanges', 'wowhead']);
const djAll = SOURCES.has('dungeon-journal') || SOURCES.has('dungeon-journal-check') ? djLoot(djFolder()) : null;
const dj = SOURCES.has('dungeon-journal') ? djAll : null;
const optJson = (f) => { try { return readJson(f); } catch { return []; } };
const fc = SOURCES.has('foreverchanges') ? optJson('out/fc-dungeons.json') : [];
const tbc = SOURCES.has('wowtbc') ? optJson('out/wowtbc.json') : [];
let wh = {}; // item tooltips (tools/out/wowhead-items.json, made by the separate encore-data-tools project)
try { wh = readJson('out/wowhead-items.json'); } catch { /* not collected: build without them */ }
let whd = null; // Wowhead Forever pages (optional)
try { whd = readJson('out/wowhead-drops.json'); } catch { /* not collected yet: build without it */ }
let npcLevels = null; // QuestieDB's NPC levels (tools/loot/questie-levels.mjs, optional)
try { npcLevels = readJson('out/npc-levels.json'); } catch { /* not extracted yet: no levels */ }
const WH_MIN_KILLS = 50; // fewer looted kills on Wowhead: not used
const WH_NONE_KILLS = 1000; // no drop in this many kills contradicts a fill-in site's boss tie
const WH_ALSO_PCT = 1; // Wowhead drops added to a boss from this rate (random drops below WH_OWN_PCT)
const WH_OWN_PCT = 2; // own loot from this rate when rare or better, or from WH_OWN_ANY_PCT for any item
const WH_OWN_ANY_PCT = 10;
const WH_MOVE_PCT = 2; // trash loot a boss drops at this rate or more moves to the boss
const RECIPE_RE = /^(Plans|Pattern|Formula|Design|Schematic|Recipe|Manual|Technique):/;

const norm = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[^a-z0-9]/g, '');
// One Encore instance per ForeverDB instance: the wings on the other sites are joined into it.
function group(name) {
  const n = norm(name).replace(/^the/, '');
  if (n.startsWith('scarletmonastery')) return 'scarletmonastery';
  if (n.startsWith('diremaul')) return 'diremaul';
  if (n.includes('blackrockspire')) return 'blackrockspire';
  if (n.startsWith('stratholme')) return 'stratholme';
  if (n === 'stockade') return 'stormwindstockade';
  if (n === 'templeofatalhakkar') return 'sunkentemple';
  if (n.startsWith('excavationsite')) return 'excavationsitewetlands';
  return n;
}
const slug = (s) => s.toLowerCase().normalize('NFD').replace(/['’]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

const instances = new Map();
const skipped = [];
function inst(key, init) {
  if (!instances.has(key)) instances.set(key, { key, bosses: [], sources: new Set(), ...init });
  return instances.get(key);
}
const TRASH = new Set(['trash', 'trashmobs', 'trashloot']);
// Fill-in names that belong to one ForeverDB encounter (the client's grouping).
const ALIAS = {
  goroshthedervish: 'ringoflaw', eviscerator: 'ringoflaw', okthorthebreaker: 'ringoflaw', hedrumthecreeper: 'ringoflaw', grizzle: 'ringoflaw', anubshiah: 'ringoflaw', theldren: 'ringoflaw',
  doomrel: 'theseven', angerrel: 'theseven', dopeel: 'theseven', gloomrel: 'theseven', haterel: 'theseven', seethrel: 'theseven', vilerel: 'theseven', chestoftheseven: 'theseven',
  darkcoffer: 'thevault', watchmandoomgrip: 'thevault',
};
function lev(a, b) {
  const d = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    let prev = d[0]; d[0] = i;
    for (let j = 1; j <= b.length; j++) { const t = d[j]; d[j] = Math.min(d[j] + 1, d[j - 1] + 1, prev + (a[i - 1] === b[j - 1] ? 0 : 1)); prev = t; }
  }
  return d[b.length];
}
// A fill-in boss in an instance ForeverDB has bosses for: find ForeverDB's boss of the same encounter.
function fdbBoss(I, name) {
  const list = I.bosses.filter((x) => x.fdb);
  if (!list.length) return null;
  const pre = name.match(/^(.+?):\s*(.+)$/);
  const cands = [name, ...(pre ? [pre[1], pre[2]] : [])].map(norm);
  for (const c of cands) {
    const a = ALIAS[c] || c;
    const hit = list.find((x) => norm(x.name) === a) ||
      list.find((x) => { const n = norm(x.name); return (a.length >= 5 && n.length >= 5 && (n.includes(a) || a.includes(n))) || (a.length >= 6 && lev(a, n) <= 2); });
    if (hit) return hit;
  }
  return null;
}
function boss(I, name, trash) {
  const n = norm(name);
  if (TRASH.has(n)) trash = true;
  let b = I.bosses.find((x) => (trash ? x.trash : norm(x.name) === n)) || (!trash && fdbBoss(I, name));
  if (!b) { b = { name: trash ? 'Trash mobs' : name, trash: !!trash, kills: 0, items: new Map(), aliases: new Set() }; I.bosses.push(b); }
  b.aliases.add(n);
  return b;
}
function addItem(b, id, src, extra) {
  const e = b.items.get(id) || { id, src: new Set() };
  e.src.add(src);
  Object.assign(e, extra);
  b.items.set(id, e);
  return e;
}

// 1. ForeverDB.net. Instances it marks as speculation (not live in Forever) are skipped.
//    So are instances with no drop seen in Forever, unless a fill-in source lists them (step 2 adds those).
const fillKeys = new Set([...fc, ...tbc, ...(dj?.dungeons || [])].map((d) => group(d.name)));
const seenIn = new Map(); // item ID -> set of ForeverDB instances it was seen in (two or more = a random world drop)
for (const d of fdb) {
  for (const e of [...d.bosses.flatMap((b) => b.items), ...d.trash]) {
    (seenIn.get(e.id) || seenIn.set(e.id, new Set()).get(e.id)).add(d.id);
  }
}
for (const d of fdb) {
  const key = group(d.name);
  const seen = d.bosses.some((b) => b.items.length) || d.trash.length;
  if (!seen && !fillKeys.has(key)) { skipped.push(`${d.name} (Classic data only)`); continue; }
  const I = inst(key, { name: d.name, kind: d.kind || 'dungeon', levels: d.levels, size: sizes[d.id]?.size, new: d.new, open: d.open, fdb: d.id });
  I.sources.add(`ForeverDB Loot.lua ${FL.version}`);
  for (const b of d.bosses) {
    const B = boss(I, b.name);
    B.kills = b.kills;
    B.npc = b.npc;
    B.fdb = true;
    for (const e of b.items) addItem(B, e.id, 'fdb', e.chance != null ? { chance: e.chance } : {});
  }
  if (d.trash.length) {
    const B = boss(I, '', true);
    for (const e of d.trash) addItem(B, e.id, 'fdb', e.chance != null ? { chance: e.chance } : {});
  }
}

// 1b. Dungeon Journal (Exehn): the first loot source. Its own boss loot is confirmed own loot; probable and shared drops
//     are random drops. A Journal boss is ForeverDB's boss of the same NPC, else of the same name or alias.
const djStats = { bosses: 0, matched: 0, own: 0, random: 0 };
for (const d of dj?.dungeons || []) {
  const key = group(d.name);
  const I = inst(key, { name: d.name.replace(/^The /, ''), kind: 'dungeon', levels: d.levels });
  if (!I.levels && d.levels) I.levels = d.levels;
  I.sources.add(`Dungeon Journal ${dj.version || ''} by Exehn`.replace('  ', ' '));
  for (const b of d.bosses) {
    let B = !b.trash && b.npc ? I.bosses.find((x) => x.npc === b.npc) : null;
    if (!B && !b.trash) for (const a of b.aliases) { const n = norm(a); B = I.bosses.find((x) => norm(x.name) === n || x.aliases.has(n)); if (B) break; }
    if (B) { B.aliases.add(norm(b.name)); djStats.matched++; } else B = boss(I, b.name, b.trash);
    if (!B.npc && b.npc) B.npc = b.npc;
    B.dj = true;
    djStats.bosses++;
    for (const id of b.items) { addItem(B, id, 'dj', { djOwn: true }); djStats.own++; }
    for (const id of [...b.probable, ...b.shared]) { const e = addItem(B, id, 'dj', {}); if (!e.djOwn) { e.djRandom = true; djStats.random++; } }
  }
}

// 2. foreverchanges.pro and wowtbc.gg fill in (only when listed in lootSources).
for (const d of fc) {
  const key = group(d.name);
  const I = inst(key, { name: d.name.replace(/^The /, ''), kind: 'dungeon', levels: d.levels });
  I.sources.add(d.source);
  for (const e of d.encounters) {
    const B = boss(I, e.name, e.trash);
    e.items.forEach((i) => addItem(B, i.id, 'fc', i.new ? { new: true } : {}));
  }
}
for (const d of tbc) {
  const key = group(d.name);
  const I = inst(key, { name: d.name, kind: d.section === 'raids' ? 'raid' : 'dungeon', levels: d.levels });
  if (d.section === 'raids') { I.kind = 'raid'; if (!I.size) I.size = parseInt(d.size) || d.size; }
  if (d.new) I.new = true;
  if (!I.levels && d.levels) I.levels = d.levels;
  I.sources.add(d.source);
  for (const b of d.bosses) {
    const B = boss(I, b.name);
    b.items.forEach((id) => addItem(B, +id, 'tbc', {}));
  }
}

// 2a. Boss roster checked against the Dungeon Journal (names and NPC IDs only, never its loot): a boss it lists that
//     no source here has is added, with no loot until Wowhead has its drops. Its order is the kill order (step 4).
const bossStats = { added: [], merged: [] };
const djBossOf = (I, jb) => {
  const names = [jb.name, ...jb.aliases].map(norm).flatMap((n) => (ALIAS[n] ? [n, ALIAS[n]] : [n]));
  // Same NPC, or same name; an alias only counts when the NPC IDs do not disagree.
  return I.bosses.find((x) => !x.trash && ((jb.npc && x.npc === jb.npc) || norm(x.name) === norm(jb.name) ||
    (!(jb.npc && x.npc && x.npc !== jb.npc) && (names.includes(norm(x.name)) || names.some((n) => x.aliases.has(n))))));
};
if (!dj) for (const d of djAll?.dungeons || []) {
  const I = instances.get(group(d.name));
  if (!I) continue;
  for (const jb of d.bosses) {
    if (jb.trash || / bosses$/i.test(jb.name) || djBossOf(I, jb)) continue;
    // A boss of its own (no name guessing: Sneed's Shredder is not Sneed).
    const B = { name: jb.name, trash: false, kills: 0, items: new Map(), aliases: new Set([norm(jb.name)]), npc: jb.npc || undefined, listed: true };
    I.bosses.push(B);
    bossStats.added.push(`${I.name}: ${jb.name}`);
  }
}
// Two entries for one NPC (a fill-in site's name and ForeverDB's, or a group's members): one boss, ForeverDB's name first.
function mergeSameNpc() {
  for (const I of instances.values()) {
    const keep = new Map();
    I.bosses = I.bosses.filter((B) => {
      if (B.trash || !B.npc) return true;
      const K = keep.get(B.npc);
      if (!K) { keep.set(B.npc, B); return true; }
      const [into, from] = !K.fdb && B.fdb ? [B, K] : [K, B];
      for (const [id, e] of from.items) { const t = into.items.get(id); if (t) for (const x of e.src) t.src.add(x); else into.items.set(id, e); }
      for (const a of from.aliases) into.aliases.add(a);
      into.aliases.add(norm(from.name));
      into.kills = Math.max(into.kills || 0, from.kills || 0);
      into.fdb = into.fdb || from.fdb; into.listed = into.listed || from.listed;
      bossStats.merged.push(`${I.name}: ${from.name} -> ${into.name}`);
      if (into === B) { keep.set(B.npc, B); I.bosses[I.bosses.indexOf(K)] = null; return true; }
      return false;
    }).filter(Boolean);
  }
}
if (!whd) mergeSameNpc();

// 2b. Wowhead Forever boss pages.
const whName = {}; // item ID -> [name, quality] from Wowhead lists, for items with no tooltip fetched
const whStats = { npcs: 0, added: 0, chances: 0, dropped: 0, moved: 0 };
const whBoss = (B) => {
  const W = B.npc && whd?.npcs?.[B.npc];
  return W && !W.missing && W.kills >= WH_MIN_KILLS ? W : null;
};
if (whd) {
  for (const W of Object.values(whd.npcs || {})) for (const [id, v] of Object.entries(W.items || {})) whName[id] = whName[id] || v;
  for (const f of Object.values(whd.factions || {})) for (const x of f.items || []) whName[x.id] = whName[x.id] || [x.name, x.quality];
  for (const l of Object.values(whd.world || {})) for (const x of l.items || []) whName[x.id] = whName[x.id] || [x.name, x.quality];
  // NPC IDs for bosses only a fill-in site lists: by name, from Wowhead's instance NPCs and boss pages.
  const npcByName = new Map();
  for (const z of Object.values(whd.zones || {})) for (const n of z.npcs || []) if (!npcByName.has(norm(n.name))) npcByName.set(norm(n.name), n.id);
  for (const [id, W] of Object.entries(whd.npcs || {})) if (W.name && !npcByName.has(norm(W.name))) npcByName.set(norm(W.name), +id);
  // The Dungeon Journal's NPC IDs, only to find a boss's Wowhead page (its loot is not used here).
  for (const d of djAll?.dungeons || []) for (const jb of d.bosses) if (jb.npc && whd.npcs?.[jb.npc]) {
    for (const n of [jb.name, ...jb.aliases]) if (!npcByName.has(norm(n))) npcByName.set(norm(n), jb.npc);
  }
  for (const I of instances.values()) for (const B of I.bosses) {
    if (!B.npc && !B.trash) B.npc = npcByName.get(norm(B.name)) || [...B.aliases].map((a) => npcByName.get(a)).find(Boolean);
  }
  mergeSameNpc();
  for (const I of instances.values()) {
    for (const B of I.bosses) {
      const W = whBoss(B);
      if (!W) continue;
      whStats.npcs++;
      B.whKills = W.kills;
      const pct = (id) => (100 * (W.drops[id] || 0)) / W.kills;
      for (const [id, e] of B.items) {
        const c = W.drops[id] || 0;
        if (c && W.kills >= 3 * (B.kills || 0)) { e.chance = Math.round(pct(id) * 100) / 100; e.whChance = true; whStats.chances++; }
        if (!c && W.kills >= WH_NONE_KILLS) {
          if (!e.src.has('fdb') && !e.src.has('dj')) { B.items.delete(id); whStats.dropped++; } else e.whNone = true;
        }
      }
      for (const [sid, c] of Object.entries(W.drops)) {
        const id = +sid, p = pct(id), q = W.items?.[sid]?.[1] ?? 1;
        if (B.items.has(id) || q < 1) continue;
        const recipe = RECIPE_RE.test(W.items?.[sid]?.[0] || '');
        if (p < WH_ALSO_PCT && !(recipe && c >= 2)) continue;
        const e = addItem(B, id, 'whn', { chance: Math.round(p * 100) / 100, whChance: true });
        e.whOwn = p >= WH_OWN_ANY_PCT || (p >= WH_OWN_PCT && q >= 3);
        whStats.added++;
      }
    }
    // Trash loot one boss here clearly drops goes to that boss.
    const T = I.bosses.find((b) => b.trash);
    if (T) for (const [id, e] of [...T.items]) {
      const to = I.bosses.filter((b) => !b.trash && whBoss(b)).map((b) => [b, (100 * (whBoss(b).drops[id] || 0)) / b.whKills])
        .filter(([, p]) => p >= WH_MOVE_PCT).sort((a, b) => b[1] - a[1])[0];
      if (!to) continue;
      const [B, p] = to;
      const be = addItem(B, id, 'whn', { chance: Math.round(p * 100) / 100, whChance: true });
      be.whOwn = true;
      for (const s of e.src) be.src.add(s);
      T.items.delete(id);
      whStats.moved++;
    }
  }
}

// 3. Item details from Wowhead Forever, own loot vs random drops, drop chances.
const items = {};
// Wowhead details first; name and quality from the Forever client (Dungeons.lua) or SearchNames.lua where it has none.
function itemOf(id) {
  const w = wh[id];
  const it = w && !w.unknown ? { ...w } : { id, name: null };
  const [dn, dq] = String(dgItems[id] ?? '').split('|');
  const jn = dj?.names?.[id];
  if (!it.name) it.name = (jn && jn[0]) || dn || searchNames[id] || whName[id]?.[0] || null;
  if (it.quality == null && dq !== undefined && dq !== '') it.quality = +dq;
  if (it.quality == null && whName[id]) it.quality = whName[id][1];
  if (it.quality == null && jn && typeof jn[1] === 'number') it.quality = jn[1];
  if (!it.recipe && RECIPE_RE.test(it.name || '')) it.recipe = true;
  const facts = String(itemFacts[id] ?? '').split('|');
  if (facts.includes('n')) it.newItem = true;
  if (facts.includes('c')) it.changed = true;
  return it;
}
let leftOut = 0, whChances = 0;
const notFetched = new Set();
const confirmedIn = new Map(); // item ID -> instances where a fill-in source or Wowhead ties it to a boss
for (const I of instances.values()) for (const B of I.bosses) for (const e of B.items.values()) {
  const w = wh[e.id];
  if (w && !w.unknown && w.droppedBy && (norm(w.droppedBy) === norm(B.name) || B.aliases.has(norm(w.droppedBy)))) e.src.add('wh');
  if (e.src.has('fc') || e.src.has('tbc') || e.src.has('wh') || e.whOwn || e.djOwn) (confirmedIn.get(e.id) || confirmedIn.set(e.id, new Set()).get(e.id)).add(I.key);
}
for (const I of instances.values()) {
  for (const B of I.bosses) {
    for (const [id, e] of B.items) {
      const w = wh[id];
      const fromFdb = e.src.has('fdb') || e.src.has('whn') || e.src.has('dj'); // seen in Forever (Journal, ForeverDB or Wowhead)
      // An item only the fill-in sites list, and Wowhead Forever does not know, is not confirmed in Forever: left out.
      // One not fetched from Wowhead yet is left out too, but counted apart: run wowhead-items.mjs again.
      if (!fromFdb && !w) { B.items.delete(id); notFetched.add(id); continue; }
      if (!fromFdb && w.unknown) { B.items.delete(id); leftOut++; continue; }
      if (e.chance == null && e.src.has('wh') && w.dropChance) { e.chance = w.dropChance; whChances++; }
      const it = items[id] || (items[id] = itemOf(id));
      if (e.new) it.newDrop = true;
      // Own loot test on the merged record: Wowhead details, else the Forever client's quality from ForeverDB.
      const own = confirmedIn.get(id)?.has(I.key) ||
        ((seenIn.get(id)?.size || 0) < 2 && (it.bind === 'Binds when picked up' || it.bind === 'Quest Item' || (it.quality ?? 0) >= 3 || it.recipe));
      // The Journal's own loot stays own loot; its probable and shared drops are random unless another source ties them here.
      e.random = e.djOwn ? false : e.djRandom && !e.whOwn && !e.src.has('fc') && !e.src.has('tbc') && !e.src.has('wh') ? true : !own || (!!e.whNone && !e.whOwn);
    }
  }
  // A fill-in "boss" named after its only item (e.g. Defias Gunpowder) is trash loot.
  for (const B of I.bosses) {
    if (B.items.size === 1 && !B.kills) {
      const [e] = B.items.values();
      const n = items[e.id]?.name;
      if (n && norm(n) === norm(B.name)) { const T = boss(I, '', true); T.items.set(e.id, { ...e, src: new Set([...e.src, ...(T.items.get(e.id)?.src || [])]) }); B.items.clear(); }
    }
  }
  // Empty entries are dropped: trash, and bosses only a fill-in site lists in an instance ForeverDB has bosses for.
  I.bosses = I.bosses.filter((b) => b.items.size || (!b.trash && (!I.fdb || b.fdb || b.dj || b.listed)));
}
// Shared recipe drops: recipes seen from bosses in two or more instances. Listed once per instance, not per boss.
const recipeInsts = new Map();
for (const I of instances.values()) for (const B of I.bosses) if (!B.trash) for (const id of B.items.keys()) {
  if (items[id]?.recipe) (recipeInsts.get(id) || recipeInsts.set(id, new Set()).get(id)).add(I.key);
}
let sharedRecipes = 0;
for (const I of instances.values()) {
  I.recipes = new Set();
  for (const B of I.bosses) for (const id of [...B.items.keys()]) {
    if ((recipeInsts.get(id)?.size || 0) >= 2) { I.recipes.add(id); B.items.delete(id); }
  }
  sharedRecipes += I.recipes.size;
  I.bosses = I.bosses.filter((b) => b.items.size || (!b.trash && (!I.fdb || b.fdb || b.listed)));
}
// Items the ForeverDB vendors sell.
const vendors = FL.vendors.map((v) => ({ ...v, items: [...v.items] }));
// Reputation rewards from Wowhead Forever's faction pages: added to ForeverDB's vendor of that faction,
// or a new vendor for factions ForeverDB players have not seen (standing and seller only; no price).
const NOT_A_FACTION = /^(Alliance|Horde|Alliance Forces|Horde Forces|Battleground Neutral|PvP Rank Points|Legacy Track|Neutral Both.*|DNT .*|.* - .*)$/;
let whRewards = 0, whFactions = 0;
for (const [fid, f] of Object.entries(whd?.factions || {})) {
  const its = (f.items || []).filter((x) => x.standing != null);
  if (!its.length || NOT_A_FACTION.test(f.name || '')) continue;
  let v = vendors.find((x) => x.kind === 'faction' && x.faction === +fid);
  if (!v) {
    v = { kind: 'faction', name: f.name, npc: its[0].vendors?.[0]?.npc ?? null, faction: +fid, side: f.side === 1 ? 'A' : f.side === 2 ? 'H' : null, items: [], wh: true };
    vendors.push(v);
    whFactions++;
  }
  const have = new Set(v.items.map((e) => e.id));
  for (const x of its) if (!have.has(x.id)) { v.items.push({ id: x.id, standing: x.standing, copper: null }); whRewards++; }
  v.items.sort((a, b) => (typeof a.standing === 'number' ? a.standing : 99) - (typeof b.standing === 'number' ? b.standing : 99));
}
vendors.sort((a, b) => (a.kind === b.kind ? 0 : a.kind === 'pvp' ? 1 : -1) || a.name.localeCompare(b.name));
for (const v of vendors) for (const e of v.items) if (!items[e.id]) items[e.id] = itemOf(e.id);
// World drops from Wowhead Forever: dropped items no boss, NPC or instance is named for, rare or better only, no quest items
// (project rule: uncommon and common world drops are not in the addon). Items an instance or a vendor lists are left out here.
const listed = new Set(Object.keys(items).map(Number));
const world = new Map();
// Quest items and quest starters are left out too (project rule): the Quest item lists, Quest Item binding, quest-starter tooltips.
const questIds = new Set(Object.entries(whd?.world || {}).filter(([k]) => k.startsWith('quest/')).flatMap(([, l]) => (l.items || []).map((x) => x.id)));
for (const l of Object.values(whd?.world || {})) for (const x of l.items || []) {
  if (listed.has(x.id) || world.has(x.id) || (x.quality ?? 0) < 3 || questIds.has(x.id)) continue;
  const t = wh[x.id];
  if (t && (t.bind === 'Quest Item' || t.startsQuest || t.type === 'Quest')) continue;
  world.set(x.id, x);
  if (!items[x.id]) items[x.id] = itemOf(x.id);
  const it = items[x.id];
  if (it.ilvl == null && x.ilvl) it.ilvl = x.ilvl;
  if (it.req == null && x.req) it.req = x.req;
}

// 4. Lua output.
const q = (s) => JSON.stringify(s ?? '').replace(/\\u([0-9a-f]{4})/gi, (_, h) => String.fromCharCode(parseInt(h, 16)));
const order = [...instances.values()].sort((a, b) =>
  (a.kind === b.kind ? 0 : a.kind === 'raid' ? 1 : -1) || ((a.levels || [99])[0] - (b.levels || [99])[0]) || a.name.localeCompare(b.name));
// Kill order: the Dungeon Journal's order (its wings one after the other), matched by NPC ID, then name. A boss it does
// not list stays right after the boss it followed here. Trash last. Wings.lua orders the bosses within each wing.
const djOrder = new Map();
for (const d of djAll?.dungeons || []) (djOrder.get(group(d.name)) || djOrder.set(group(d.name), []).get(group(d.name))).push(...d.bosses.filter((b) => !b.trash));
for (const I of order) {
  const list = djOrder.get(I.key);
  if (list) {
    const rankOf = (B) => {
      const k = list.findIndex((jb) => jb.npc && jb.npc === B.npc);
      if (k >= 0) return k;
      const names = [norm(B.name), ...B.aliases];
      return list.findIndex((jb) => [jb.name, ...jb.aliases].some((n) => names.includes(norm(n)) || names.includes(ALIAS[norm(n)])));
    };
    let last = -1;
    const keyed = I.bosses.map((B, i) => { const r = rankOf(B); if (r >= 0) last = r; return { B, r: r >= 0 ? r : last + 0.5, i }; });
    keyed.sort((a, b) => (a.B.trash - b.B.trash) || (a.r - b.r) || (a.i - b.i));
    I.bosses = keyed.map((x) => x.B);
  } else I.bosses.sort((a, b) => a.trash - b.trash);
}
// Rare spawns: Wowhead's NPC classification (rare or rare elite) where collected, else the Dungeon Journal's rare mark.
for (const I of order) for (const B of I.bosses) {
  if (B.trash) continue;
  const c = B.npc && whd?.npcs?.[B.npc]?.classification;
  if (c != null) { B.rare = c === 2 || c === 4; continue; }
  const jb = (djOrder.get(I.key) || []).find((j) => (j.npc && j.npc === B.npc) || norm(j.name) === norm(B.name));
  if (jb?.rare) B.rare = true;
}
// Levels for the boss portraits: QuestieDB's Forever database first, Wowhead Forever's NPC page
// where QuestieDB has none. A boss-rank NPC (QuestieDB rank 3, or "??" on Wowhead) shows a skull instead.
let levelsFound = 0;
for (const I of order) for (const B of I.bosses) {
  if (B.trash || !B.npc) continue;
  const qd = npcLevels?.npcs?.[B.npc];
  const wl = whd?.npcs?.[B.npc]?.level;
  if (qd) { B.level = qd[2] === 3 ? -1 : qd[1]; B.levelMin = qd[0]; }
  else if (wl === -1) B.level = -1;
  else if (Array.isArray(wl)) { B.level = wl[wl.length - 1]; B.levelMin = wl[0]; }
  if (B.level != null) levelsFound++;
}
const rank = (e) => -(e.chance ?? -1);
const entry = (e) => (e.chance != null ? `{ ${e.id}, ${e.chance} }` : `${e.id}`);
const L = [];
L.push(FL.header);
L.push('-- Encore-DB loot tables. Generated by tools/loot/build-loot.mjs: do not edit by hand.');
L.push(`-- Data from ForeverDB.net (https://foreverdb.net), data version ${FL.version}: bosses, the drops players saw in WoW Forever`);
L.push('-- with drop rates per looted kill, and the reputation and PvP vendors players saw. Its Classic data and clues are left out.');
if (dj) L.push(`-- Boss loot first from Dungeon Journal (ForeverDungeonJournal) ${dj.version || ''} by Exehn: its hand-kept boss and loot lists.`);
const fills = [fc.length && 'foreverchanges.pro', tbc.length && 'wowtbc.gg'].filter(Boolean);
L.push(`-- ${fills.length ? `Filled in from ${fills.join(' and ')}. ` : ''}${Object.keys(wh).length ? 'Item details from Wowhead Forever (https://www.wowhead.com/forever) and the game client.' : 'Item details from the game client.'}`);
if (whd) L.push('-- Boss drops, drop chances, reputation rewards and world drops filled in from Wowhead Forever (https://www.wowhead.com/forever).');
if (npcLevels) L.push(`-- Boss levels from QuestieDB (https://github.com/Questie/QuestieDB, GPL-3.0), ${npcLevels.source}: its WoW Forever NPC data, which is Questie's Classic data with Forever corrections. No other Classic or emulator data.`);
else L.push('-- No Classic or emulator data.');
L.push("-- Licence: GPL-3.0 with ForeverDB.net's attribution term; see NOTICE.txt in this addon.");
L.push(`-- Built ${new Date().toISOString().slice(0, 10)}.`);
L.push('local _, ns = ...');
L.push('ns.Loot = {}');
L.push('-- Item: { name, quality, icon, slot, type, itemLevel, requiredLevel, flags }');
L.push('--   flags: 1 = new in Forever, 2 = recipe, 4 = quest item, 8 = changed in Forever.');
L.push('-- Missing details (nil) come from the game client at run time.');
L.push('ns.Loot.items = {');
const nil = (v, f = (x) => x) => (v == null || v === '' ? 'nil' : f(v));
for (const id of Object.keys(items).map(Number).sort((a, b) => a - b)) {
  const w = items[id];
  const flags = (w.newDrop || w.newItem ? 1 : 0) | (w.recipe ? 2 : 0) | (w.bind === 'Quest Item' ? 4 : 0) | (w.changed ? 8 : 0);
  L.push(`  [${id}] = { ${q(w.name)}, ${nil(w.quality)}, ${nil(w.icon, q)}, ${nil(w.slot, q)}, ${nil(w.type, q)}, ${nil(w.ilvl)}, ${nil(w.req)}, ${flags} },`);
}
L.push('}');
L.push('-- Instance: key, name, kind, size, levels, new (added in Forever), open (ForeverDB lists it as open), foreverdb (its ID), bosses.');
L.push('-- Instance recipes: profession recipes any boss here can drop (shared by the bosses of this level range).');
L.push('-- Boss: name, rare (a rare spawn), level (-1: boss level, shown as a skull), npc, kills (most looted kills recorded), items (its own loot), also (random drops seen from it).');
L.push('-- A list entry is an item ID, or { itemID, drop chance in % } (per looted kill in Forever).');
L.push('ns.Loot.instances = {');
for (const I of order) {
  L.push(`  { key = ${q(slug(I.name))}, name = ${q(I.name)}, kind = ${q(I.kind)}${I.size ? `, size = ${I.size}` : ''}${I.levels ? `, levels = { ${I.levels.join(', ')} }` : ''}${I.new ? ', new = true' : ''}${I.open ? ', open = true' : ''}${I.fdb ? `, foreverdb = ${I.fdb}` : ''}, bosses = {`);
  for (const B of I.bosses) {
    const all = [...B.items.values()].sort((a, b) => rank(a) - rank(b));
    const own = all.filter((e) => !e.random).map(entry), also = all.filter((e) => e.random).map(entry);
    const kills = Math.max(B.kills || 0, B.whKills || 0);
    L.push(`    { name = ${q(B.name)}${B.trash ? ', trash = true' : ''}${B.rare ? ', rare = true' : ''}${B.level != null ? `, level = ${B.level}` : ''}${B.npc ? `, npc = ${B.npc}` : ''}${kills ? `, kills = ${kills}` : ''}, items = { ${own.join(', ')} }${also.length ? `, also = { ${also.join(', ')} }` : ''} },`);
  }
  L.push(`  }${I.recipes?.size ? `, recipes = { ${[...I.recipes].sort((a, b) => a - b).join(', ')} }` : ''} },`);
}
L.push('}');
L.push('-- Vendor: kind (pvp or faction), name, npc, faction (faction ID), side (A or H), items.');
L.push('-- Vendor item: { itemID, standing (4 Neutral .. 8 Exalted, or "r<PvP rank>"), price in copper or nil }.');
L.push('ns.Loot.vendors = {');
for (const v of vendors) {
  const its = v.items.map((e) => `{ ${e.id}, ${typeof e.standing === 'number' ? e.standing : q(e.standing)}${e.copper ? `, ${e.copper}` : ''} }`);
  L.push(`  { kind = ${q(v.kind)}, name = ${q(v.name)}${v.npc ? `, npc = ${v.npc}` : ''}${v.faction ? `, faction = ${v.faction}` : ''}${v.side ? `, side = ${q(v.side)}` : ''}, items = { ${its.join(', ')} } },`);
}
L.push('}');
L.push('ns.Loot.standing = { [3] = "Unfriendly", [4] = "Neutral", [5] = "Friendly", [6] = "Honored", [7] = "Revered", [8] = "Exalted" }');
L.push('-- World drops: rare and epic item IDs dropped in the open world, by required level then name.');
const worldIds = [...world.keys()].sort((a, b) => ((items[a].req || 0) - (items[b].req || 0)) || String(items[a].name).localeCompare(String(items[b].name)));
L.push('ns.Loot.world = {');
for (let k = 0; k < worldIds.length; k += 20) L.push(`  ${worldIds.slice(k, k + 20).join(', ')},`);
L.push('}');
const file = path.join(REPO, 'EncoreEssentials_DB', 'Data', 'Loot.lua');
fs.mkdirSync(path.dirname(file), { recursive: true });
fs.writeFileSync(file, L.join('\n') + '\n');

// The Dungeon Journal as a cross-check: its boss loot that this build does not list in that instance, and the reverse.
if (djAll) {
  const have = new Map(order.map((I) => [I.key, new Set([...I.bosses.flatMap((b) => [...b.items.keys()]), ...(I.recipes || [])])]));
  const check = { version: djAll.version, missingHere: [], notInJournal: [] };
  const inJournal = new Map();
  for (const d of djAll.dungeons) {
    const key = group(d.name), mine = have.get(key) || new Set();
    const js = inJournal.get(key) || inJournal.set(key, new Set()).get(key);
    for (const b of d.bosses) for (const id of [...b.items, ...b.probable, ...b.shared]) {
      js.add(id);
      if (!mine.has(id)) check.missingHere.push({ instance: d.name, boss: b.name, npc: b.npc, item: id, name: djAll.names[id]?.[0] || null, probable: !b.items.includes(id) });
    }
  }
  for (const I of order) {
    const js = inJournal.get(I.key);
    if (js) for (const B of I.bosses) for (const id of B.items.keys()) if (!js.has(id)) check.notInJournal.push({ instance: I.name, boss: B.name, item: id, name: items[id]?.name || null });
  }
  writeJson('out/dj-check.json', check);
  console.log(`Dungeon Journal check: ${check.missingHere.length} of its entries not listed here, ${check.notInJournal.length} entries here not in it (tools/out/dj-check.json)`);
}

const report = {
  foreverdb: { version: FL.version, built: FL.built, classicEntriesLeftOut: FL.dropped.classic, cluesLeftOut: FL.dropped.clues, vendorsLeftOut: FL.dropped.vendors },
  dungeonJournal: dj ? { version: dj.version, ...djStats } : null,
  levelsFound,
  bossesAdded: bossStats.added, bossesMerged: bossStats.merged,
  skipped,
  notFetchedFromWowhead: [...notFetched].sort((a, b) => a - b),
  vendors: vendors.map((v) => ({ name: v.name, items: v.items.length, fromWowhead: !!v.wh })),
  wowhead: whd ? { ...whStats, sharedRecipes, rewardsAdded: whRewards, factionsAdded: whFactions, worldDrops: world.size } : null,
  instances: order.map((I) => {
    const all = I.bosses.flatMap((b) => [...b.items.values()]);
    return {
      name: I.name, kind: I.kind, open: !!I.open, bosses: I.bosses.length, own: all.filter((e) => !e.random).length, also: all.filter((e) => e.random).length,
      fromDungeonJournal: all.filter((e) => e.src.has('dj')).length, fromForeverDB: all.filter((e) => e.src.has('fdb')).length, fillIn: all.filter((e) => !e.src.has('fdb')).length,
      withChance: all.filter((e) => e.chance != null).length, sources: [...I.sources],
    };
  }),
};
writeJson('out/loot-report.json', report);
const noDetails = Object.values(items).filter((w) => w.quality == null).length;
console.log(`${order.length} instances, ${Object.keys(items).length} items (${noDetails} without Wowhead details yet), ${whChances} chances from Wowhead, ${leftOut} fill-in entries left out (not on Wowhead Forever)`);
if (notFetched.size) console.log(`WARNING: ${notFetched.size} fill-in items not fetched from Wowhead yet, left out: run node tools/loot/wowhead-items.mjs, then build again`);
if (dj) console.log(`Dungeon Journal ${dj.version}: ${djStats.bosses} bosses (${djStats.matched} matched to ForeverDB by NPC/alias), ${djStats.own} own and ${djStats.random} random entries`);
else if (!djAll && (SOURCES.has('dungeon-journal') || SOURCES.has('dungeon-journal-check'))) console.log('No Dungeon Journal folder: set "dungeonJournal" in tools/refresh.config.json or DUNGEON_JOURNAL');
if (whd) console.log(`Wowhead: ${whStats.npcs} bosses, ${whStats.added} drops added, ${whStats.chances} chances, ${whStats.dropped} contradicted ties dropped, ${whStats.moved} moved from trash; ${sharedRecipes} shared recipe entries; ${whRewards} reputation rewards (${whFactions} new factions); ${world.size} world drops`);
else console.log('No out/wowhead-drops.json: built without Wowhead Forever pages (run node tools/loot/wowhead-drops.mjs)');
console.log('skipped:', skipped.join('; '));
console.log('wrote', file, `(${Math.round(fs.statSync(file).size / 1024)} KB)`);
