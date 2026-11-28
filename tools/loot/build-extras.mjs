// Builds EncoreEssentials_DB/Data/Extras.lua: PvP rewards (Warsong Gulch, Alterac Valley, honor rewards), reputation
// rewards Data/Loot.lua lacks, the Collections tab (mounts, companions, tabards, legendaries, item sets) and rogue poisons
// (ns.ClassSkills, shown in the Collections tab under Class skills, not under Professions).
//
// Sources:
//   tools/out/wowhead-extras.json  Wowhead Forever (https://www.wowhead.com/forever): item names, qualities, levels,
//                                  sides, prices, sources and vendors; the reputation each item needs (its tooltip);
//                                  item sets and their pieces; the poison spells. Collected in the browser with the
//                                  script from encore-data-tools (wowhead-extras-script.mjs), because of Wowhead's check.
//   tools/out/extras-leads.json    atlasloot-extras.mjs: the item, item set and spell IDs AtlasLoot Continued lists.
//                                  Only used to know which Wowhead pages to read. Nothing of AtlasLoot's is copied:
//                                  AtlasLoot is GPL v2 only. Groups, names, vendors and standings all come from Wowhead.
//   EncoreEssentials_DB/Data/Loot.lua  what Encore-DB already lists, so it is not added twice.
// An item is kept only when Wowhead Forever shows a source for it in WoW Forever (sold by, dropped by, quest reward,
// crafted, fished, contained in), or its Wowhead page has one of those tabs. Promotion-only items (source 14) and
// world events (none have run in WoW Forever yet) are left out. Report: tools/out/extras-check.json.
// Usage: node tools/loot/build-extras.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readJson, writeJson } from './net.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const OUT = path.join(REPO, 'EncoreEssentials_DB', 'Data', 'Extras.lua');
const leads = readJson('out/extras-leads.json');
const W = readJson('out/wowhead-extras.json');
const lootLua = fs.readFileSync(path.join(REPO, 'EncoreEssentials_DB', 'Data', 'Loot.lua'), 'utf8');

// What Loot.lua has: its items, and each vendor's items by kind and faction.
const haveItems = new Set([...lootLua.matchAll(/^\s*\[(\d+)\] = \{/gm)].map((m) => +m[1]));
const haveVendors = [];
for (const m of lootLua.matchAll(/^\s*\{ kind = "(\w+)", name = "([^"]+)"(?:, npc = (\d+))?(?:, faction = (\d+))?(?:, side = "(\w)")?, items = \{(.*)\} \},$/gm))
  haveVendors.push({ kind: m[1], name: m[2], faction: m[4] ? +m[4] : null, side: m[5] || null, items: new Set([...m[6].matchAll(/\{ (\d+),/g)].map((x) => +x[1])) });

const STANDING = { Hated: 1, Hostile: 2, Unfriendly: 3, Neutral: 4, Friendly: 5, Honored: 6, Revered: 7, Exalted: 8 };
// Faction names as Wowhead's tooltips write them -> faction IDs. Loot.lua's factions are added below.
const FACTION = { 'Warsong Outriders': 889, 'Silverwing Sentinels': 890, 'Frostwolf Clan': 729, 'Stormpike Guard': 730,
  'The League of Arathor': 509, 'League of Arathor': 509, 'The Defilers': 510, 'Wintersaber Trainers': 589, 'Bloodsail Buccaneers': 87 };
for (const v of haveVendors) if (v.faction) FACTION[v.name] = v.faction;
const FACTION_NAME = { 889: 'Warsong Outriders', 890: 'Silverwing Sentinels', 729: 'Frostwolf Clan', 730: 'Stormpike Guard', 589: 'Wintersaber Trainers', 87: 'Bloodsail Buccaneers' };
for (const v of haveVendors) if (v.faction && !FACTION_NAME[v.faction]) FACTION_NAME[v.faction] = v.name;
const SIDE = { 1: 'A', 2: 'H' };

// Wowhead source types: 1 crafted, 2 drop, 4 quest, 5 vendor, 16 fishing. 14 is a promotion (not in the game).
const CONFIRM_TABS = /^(sold-by|dropped-by|reward-from|created-by|contained-in.*|fished-in|pick-pocketed-from|skinned-from|mined-from|gathered-from)$/;
const check = { kept: 0, notOnWowhead: [], noSource: [], promotionOnly: [], alreadyListed: 0 };
function confirmed(id) {
  const it = W.items[id];
  if (!it) { check.notOnWowhead.push(id); return false; }
  const src = it.source.filter((s) => s !== 14);
  if (src.length) return true;
  if ((W.pages[id] || []).some((t) => CONFIRM_TABS.test(t))) return true;
  (it.source.includes(14) ? check.promotionOnly : check.noSource).push({ id, name: it.name });
  return false;
}
const firstVendor = (id) => (W.items[id].sourcemore || []).find((s) => s.t === 1 && s.n) || null;
// Wowhead's sourcemore entries: t 1 = NPC (vendor or creature), t 2 = object, t 3 = item, t 5 = quest, t 6 = spell.
function fromText(id) {
  const it = W.items[id], sm = it.sourcemore || [];
  const s = it.source.filter((x) => x !== 14);
  const of = (t) => sm.find((e) => e.t === t && e.n);
  if (s.includes(5)) return of(1) ? 'Sold by ' + of(1).n : 'Vendor';
  if (s.includes(4)) return of(5) ? 'Quest: ' + of(5).n : 'Quest reward';
  if (s.includes(2)) { const d = of(1) || of(2) || of(3); return d ? 'Dropped by ' + d.n : 'Drop'; }
  if (s.includes(1)) return 'Crafted';
  if (s.includes(16)) return 'Fishing';
  const p = W.pages[id] || [];
  if (p.includes('sold-by')) return 'Vendor';
  if (p.includes('reward-from')) return 'Quest reward';
  if (p.includes('dropped-by')) return 'Drop';
  if (p.some((t) => t.startsWith('contained-in'))) return 'Container';
  if (p.includes('created-by')) return 'Crafted';
  return 'See Wowhead';
}
const groupOf = (id) => {
  const s = W.items[id].source, p = W.pages[id] || [];
  if (s.includes(5) || p.includes('sold-by')) return 'Vendors';
  if (s.includes(4) || p.includes('reward-from')) return 'Quests';
  if (s.includes(2) || p.includes('dropped-by') || p.some((t) => t.startsWith('contained-in'))) return 'Drops';
  if (s.includes(1) || p.includes('created-by')) return 'Crafted';
  return 'Other';
};

const items = new Map(); // id -> Lua item row
const useItem = (id) => {
  if (haveItems.has(id) || items.has(id)) return;
  const it = W.items[id];
  items.set(id, [it.name, it.quality, it.level || null, it.reqlevel > 1 ? it.reqlevel : null]);
};

// ---- PvP: battleground reputation vendors and honor rewards -------------------------------------------------
const vendors = []; // new vendors, and items to add to existing ones
const vendorFor = (kind, name, faction, side, npc) => {
  let v = vendors.find((x) => x.kind === kind && x.name === name && x.side === side);
  if (!v) vendors.push((v = { kind, name, faction, side, npc, items: [] }));
  return v;
};
const HONOR = { Armor: 'Honor rewards: armor', Weapons: 'Honor rewards: weapons', PvPMounts: 'Honor rewards: mounts', Insignia: 'Honor rewards: insignia' };
// Each battleground's two factions, and which side each is on. An item that needs no reputation (bandages, rations)
// is listed under the faction of its side in the battleground it is filed under.
const BATTLEGROUND = { WarsongGulch: [890, 889], AlteracValley: [730, 729], ArathiBasin: [509, 510] };
const FACTION_SIDE = { 890: 'A', 889: 'H', 730: 'A', 729: 'H', 509: 'A', 510: 'H' };
const listedIn = (kind, faction, id) => haveVendors.some((v) => v.kind === kind && v.faction === faction && v.items.has(id));
for (const g of leads.pvp) for (const s of g.sections) for (const id of s.ids) {
  if (!confirmed(id)) continue;
  const it = W.items[id], tt = W.tooltips[id] || {}, v = firstVendor(id);
  const side = SIDE[it.side] || null;
  // An item both sides can use has one ID; its tooltip names one side's faction, so it goes to both of that
  // battleground's factions at the same standing.
  const repFaction = tt.rep && FACTION[tt.rep[0]];
  const bgOf = (f) => Object.values(BATTLEGROUND).find((b) => b.includes(f));
  let factions = repFaction ? (side ? [repFaction] : bgOf(repFaction) || [repFaction])
    : (BATTLEGROUND[g.key] || []).filter((f) => !side || FACTION_SIDE[f] === side);
  if (factions.length) {
    let added = false;
    for (const faction of factions) {
      if (listedIn('pvp', faction, id)) continue;
      const vend = vendorFor('pvp', FACTION_NAME[faction] || tt.rep[0], faction, FACTION_SIDE[faction] || side, v?.ti);
      if (!vend.items.some((e) => e[0] === id)) { vend.items.push([id, tt.rep ? STANDING[tt.rep[1]] : null, it.buyprice || null]); added = true; }
    }
    if (!added) { check.alreadyListed++; continue; }
  } else if (HONOR[g.key]) {
    const sides = side ? [side] : ['A', 'H'];
    for (const sd of sides) {
      const vend = vendorFor('pvp', HONOR[g.key], null, sd, v?.ti);
      if (!vend.items.some((e) => e[0] === id)) vend.items.push([id, null, it.buyprice || null]); // WoW Forever's honor rewards need no PvP rank
    }
  } else continue;
  useItem(id);
}

// ---- Reputations: rewards Loot.lua's faction vendors lack ---------------------------------------------------
for (const g of leads.factions) for (const s of g.sections) for (const id of s.ids) {
  if (!confirmed(id)) continue;
  const tt = W.tooltips[id] || {};
  const faction = (tt.rep && FACTION[tt.rep[0]]) || g.faction;
  if (!faction) continue;
  if (listedIn('faction', faction, id)) { check.alreadyListed++; continue; }
  const it = W.items[id], v = firstVendor(id);
  const have = haveVendors.find((x) => x.kind === 'faction' && x.faction === faction);
  const vend = vendorFor('faction', have?.name || FACTION_NAME[faction] || (tt.rep && tt.rep[0]) || 'Faction ' + faction, faction, have ? have.side : (SIDE[it.side] || null), v?.ti);
  if (have) vend.merge = true;
  if (!vend.items.some((e) => e[0] === id)) vend.items.push([id, tt.rep ? STANDING[tt.rep[1]] : null, (W.items[id].source.includes(5) && it.buyprice) || null]);
  useItem(id);
}
for (const v of vendors) v.items.sort((a, b) => ((a[1] ?? 0) - (b[1] ?? 0)) || ((a[2] ?? 0) - (b[2] ?? 0)) || a[0] - b[0]);

// ---- Collections ----------------------------------------------------------------------------------------------
const COL = { Mounts: ['mounts', 'Mounts'], Companions: ['companions', 'Companions'], Tabards: ['tabards', 'Tabards'], Legendarys: ['legendaries', 'Legendaries'] };
const GROUP_ORDER = ['Vendors', 'Quests', 'Drops', 'Crafted', 'Other'];
const collections = [];
for (const g of leads.collections) {
  const [key, text] = COL[g.key] || [g.key.toLowerCase(), g.key];
  const seen = new Set(), groups = {};
  for (const s of g.sections) for (const id of s.ids) {
    if (seen.has(id) || !confirmed(id)) continue;
    seen.add(id);
    useItem(id);
    (groups[groupOf(id)] ||= []).push([id, fromText(id)]);
  }
  const list = GROUP_ORDER.filter((k) => groups[k]).map((k) => ({ text: k, items: groups[k].sort((a, b) => (W.items[a[0]].reqlevel || 0) - (W.items[b[0]].reqlevel || 0) || W.items[a[0]].name.localeCompare(W.items[b[0]].name)) }));
  if (list.length) collections.push({ key, text, groups: list });
}

// ---- Item sets: grouped by where Wowhead says their pieces come from -----------------------------------------
const CLASS = { 1: 'Warrior', 2: 'Paladin', 4: 'Hunter', 8: 'Rogue', 16: 'Priest', 64: 'Shaman', 128: 'Mage', 256: 'Warlock', 1024: 'Druid' };
// Wowhead's item set tags: 9 Ruins of Ahn'Qiraj, 10 Temple of Ahn'Qiraj, 11 Zul'Gurub, 6-8 PvP.
const NOTE = { 9: "Ruins of Ahn'Qiraj", 10: "Temple of Ahn'Qiraj", 11: "Zul'Gurub" };
const PVP_NOTE = new Set([6, 7, 8]);
const pvpSetIds = new Set(leads.sets.filter((b) => b.pvp).flatMap((b) => b.sections.flatMap((s) => s.ids)));
const setGroups = {};
for (const sid of leads.setIds) {
  const set = W.sets[sid];
  if (!set) continue;
  const pieces = (set.pieces || []).filter((p) => confirmed(p));
  if (pieces.length < 2) continue;
  pieces.forEach(useItem);
  const pvp = PVP_NOTE.has(set.note) || pvpSetIds.has(sid);
  const group = pvp ? (set.quality >= 4 ? 'PvP sets (epic)' : 'PvP sets (rare)') : NOTE[set.note] || 'Other sets';
  const side = SIDE[set.side] || SIDE[W.items[pieces[0]].side] || null;
  (setGroups[group] ||= []).push({ id: sid, name: set.name, cls: CLASS[set.reqclass] || null, side, quality: set.quality, level: set.maxlevel || set.minlevel || null, pieces });
}
const SET_ORDER = ['PvP sets (epic)', 'PvP sets (rare)', "Zul'Gurub", "Ruins of Ahn'Qiraj", "Temple of Ahn'Qiraj", 'Other sets'];
const sets = SET_ORDER.filter((k) => setGroups[k]).map((k) => ({ text: k, sets: setGroups[k].sort((a, b) => (a.cls || '').localeCompare(b.cls || '') || (a.side || '').localeCompare(b.side || '') || a.name.localeCompare(b.name)) }));

// ---- Rogue poisons: learned from the rogue trainer by level ----------------------------------------------------
const poisons = [];
for (const sp of leads.poisons) {
  const s = W.spells[sp];
  if (!s || !s.creates) continue;
  poisons.push({ spell: sp, name: s.name, level: s.level || null, makes: s.creates[0], count: s.creates[1] || 1, reagents: (s.reagents || []).flat() });
}
poisons.sort((a, b) => (a.level || 0) - (b.level || 0) || a.name.localeCompare(b.name));

// ---- Write -------------------------------------------------------------------------------------------------------
const q = (s) => JSON.stringify(String(s));
const n = (x) => (x == null ? 'nil' : String(x));
const L = [];
L.push('-- Encore-DB extras: PvP rewards, reputation rewards, collections, item sets and rogue poisons.');
L.push('-- Generated by tools/loot/build-extras.mjs: do not edit by hand.');
L.push(`-- Data from Wowhead Forever (https://www.wowhead.com/forever), read ${String(W.read).slice(0, 10)}: names, levels, prices, vendors, sources,`);
L.push('-- the reputation each item needs, item sets and poison recipes. Only items Wowhead Forever shows a source for are listed.');
L.push('-- AtlasLoot Continued (GPL v2 only) was read as the list of items to look up; none of its data is included.');
L.push('-- World events are left out until they run in WoW Forever. Licence: GPL-3.0; see NOTICE.txt in this addon.');
L.push(`-- Built ${new Date().toISOString().slice(0, 10)}.`);
L.push('local _, ns = ...');
L.push('local Loot = ns.Loot');
L.push('if not Loot then return end');
L.push('local items, vendors = Loot.items, Loot.vendors');
L.push('-- Items Loot.lua does not have: { name, quality, icon, slot, type, itemLevel, requiredLevel, flags }; the rest comes from the client.');
L.push('local add = {');
for (const [id, r] of [...items].sort((a, b) => a[0] - b[0])) L.push(`  [${id}] = { ${q(r[0])}, ${r[1]}, nil, nil, nil, ${n(r[2])}, ${n(r[3])}, 0 },`);
L.push('}');
L.push('for id, it in pairs(add) do if not items[id] then items[id] = it end end');
L.push('-- Vendors: as in Loot.lua. merge = true adds the items to Loot.lua\'s vendor for that faction.');
L.push('local more = {');
for (const v of vendors) {
  const its = v.items.map((e) => `{ ${e[0]}, ${typeof e[1] === 'string' ? q(e[1]) : n(e[1])}${e[2] ? `, ${e[2]}` : ''} }`);
  L.push(`  { kind = ${q(v.kind)}, name = ${q(v.name)}${v.npc ? `, npc = ${v.npc}` : ''}${v.faction ? `, faction = ${v.faction}` : ''}${v.side ? `, side = ${q(v.side)}` : ''}${v.merge ? ', merge = true' : ''}, items = { ${its.join(', ')} } },`);
}
L.push('}');
L.push('for _, v in ipairs(more) do');
L.push('    local into');
L.push('    if v.merge then');
L.push('        for _, o in ipairs(vendors) do if o.kind == v.kind and o.faction == v.faction then into = o; break end end');
L.push('    end');
L.push('    if into then');
L.push('        for _, e in ipairs(v.items) do into.items[#into.items + 1] = e end');
L.push('    else');
L.push('        v.merge = nil');
L.push('        vendors[#vendors + 1] = v');
L.push('    end');
L.push('end');
L.push('-- Collections tab: { key, text, groups = { { text, items = { { itemID, where from } } } } }.');
L.push('ns.Collections = {');
for (const c of collections) {
  L.push(`  { key = ${q(c.key)}, text = ${q(c.text)}, groups = {`);
  for (const g of c.groups) L.push(`    { text = ${q(g.text)}, items = { ${g.items.map((e) => `{ ${e[0]}, ${q(e[1])} }`).join(', ')} } },`);
  L.push('  } },');
}
L.push('}');
L.push('-- Item sets: { text, tab ("pvp": shown in the PvP tab, else Collections), sets = { { id, name, class, side, quality, level, pieces = { itemID, ... } } } }.');
L.push('ns.ItemSets = {');
for (const g of sets) {
  L.push(`  { text = ${q(g.text)}${g.text.startsWith('PvP') ? ', tab = "pvp"' : ''}, sets = {`);
  for (const s of g.sets) L.push(`    { id = ${s.id}, name = ${q(s.name)}${s.cls ? `, class = ${q(s.cls)}` : ''}${s.side ? `, side = ${q(s.side)}` : ''}, quality = ${n(s.quality)}, level = ${n(s.level)}, pieces = { ${s.pieces.join(', ')} } },`);
  L.push('  } },');
}
L.push('}');
L.push('-- Class skills (Collections tab, not Professions): rogue poisons, recipes as in Recipes.lua but learned by level');
L.push('-- from the rogue trainer: level = the level needed.');
L.push('ns.ClassSkills = {');
if (poisons.length) {
  L.push('  { key = "poisons", text = "Rogue poisons", class = "Rogue", recipes = {');
  for (const p of poisons) L.push(`    { ${p.spell}, ${q(p.name)}, nil, nil, nil, nil, ${p.makes}, ${p.count}, { ${p.reagents.join(', ')} }, "t", level = ${n(p.level)} },`);
  L.push('  } },');
}
L.push('}');
fs.writeFileSync(OUT, L.join('\n') + '\n');

check.kept = items.size;
check.vendors = vendors.map((v) => ({ kind: v.kind, name: v.name, side: v.side, merge: !!v.merge, items: v.items.length }));
check.collections = collections.map((c) => ({ key: c.key, items: c.groups.reduce((s, g) => s + g.items.length, 0) }));
check.sets = sets.map((g) => ({ group: g.text, sets: g.sets.length }));
check.poisons = poisons.length;
writeJson('out/extras-check.json', check);
console.log(`Extras.lua: ${items.size} new items, ${vendors.length} vendor lists, ${collections.length} collections, ${sets.reduce((s, g) => s + g.sets.length, 0)} item sets, ${poisons.length} poisons`);
console.log(`Left out: ${check.notOnWowhead.length} not on Wowhead Forever, ${check.noSource.length} with no source, ${check.promotionOnly.length} promotion only (tools/out/extras-check.json)`);
