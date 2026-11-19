// Downloads the ForeverDB addon's data files (GPL-3.0 with an attribution term: credit "Data from ForeverDB.net").
// The list, sizes and SHA-256 hashes come from https://foreverdb.net/downloads/addon-manifest.json.
// Files go to tools/cache/foreverdb-files/<data version>/ (not in the repository). They are only read as text, never run.
// Usage: node tools/loot/foreverdb-files.mjs [File.lua ...]   (no names = every data file)
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { CACHE } from './net.mjs';
import { readLuaTables } from './lua-table.mjs';

const SITE = 'https://foreverdb.net/';
const UA = 'addon-data-tool/0.1 (WoW addon data builder)';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Folder of the newest downloaded data version, or null.
export function filesDir() {
  const root = path.join(CACHE, 'foreverdb-files');
  if (!fs.existsSync(root)) return null;
  const v = fs.readdirSync(root).filter((d) => fs.existsSync(path.join(root, d, 'manifest.json'))).sort().pop();
  return v ? path.join(root, v) : null;
}

// Reads one downloaded data file: { header (its first line, the credit to keep), tables ({ 'ns.x': value }), version }.
const parsed = new Map();
export function readFdb(name) {
  if (parsed.has(name)) return parsed.get(name);
  const dir = filesDir();
  if (!dir) throw new Error('No ForeverDB files yet: run node tools/loot/foreverdb-files.mjs first');
  const src = fs.readFileSync(path.join(dir, 'Data', name), 'utf8');
  const out = { header: src.split('\n', 1)[0].trimEnd(), tables: readLuaTables(src), version: path.basename(dir) };
  parsed.set(name, out);
  return out;
}

async function main() {
  const want = new Set(process.argv.slice(2).map((s) => s.replace(/^Data\//, '')));
  const res = await fetch(SITE + 'downloads/addon-manifest.json', { headers: { 'User-Agent': UA } });
  if (res.status !== 200) throw new Error(`manifest: HTTP ${res.status}`);
  const manifest = await res.json();
  const dir = path.join(CACHE, 'foreverdb-files', manifest.data.version.replace(/[^\w.-]/g, '_'));
  fs.mkdirSync(path.join(dir, 'Data'), { recursive: true });
  let got = 0, kept = 0;
  for (const f of manifest.data.files) {
    if (want.size && !want.has(path.basename(f.path))) continue;
    const file = path.join(dir, f.path);
    const hash = (b) => crypto.createHash('sha256').update(b).digest('hex');
    if (fs.existsSync(file) && hash(fs.readFileSync(file)) === f.sha256) { kept++; continue; }
    await sleep(1200);
    const r = await fetch(SITE + f.url, { headers: { 'User-Agent': UA } });
    if (r.status !== 200) throw new Error(`${f.path}: HTTP ${r.status}`);
    const buf = Buffer.from(await r.arrayBuffer());
    if (hash(buf) !== f.sha256) throw new Error(`${f.path}: SHA-256 does not match the manifest`);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, buf);
    got++;
    console.log(`${f.path} ${Math.round(buf.length / 1024)} KB`);
  }
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify(manifest, null, 1));
  console.log(`data ${manifest.data.version}: ${got} downloaded, ${kept} already up to date -> ${dir}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
