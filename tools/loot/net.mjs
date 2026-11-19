// Polite cached HTTP GET for the data tools.
// Every response is saved under tools/cache/<host>/, so each page or tooltip is fetched once.
// Requests to a host are at least DELAY_MS apart; after MAX_FAILS failed requests in a row the tool stops.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const CACHE = path.join(ROOT, 'cache');
const UA = 'addon-data-tool/0.1 (WoW addon data builder)';
const DELAY_MS = 1200;
const MAX_FAILS = 3;

const last = new Map();
let fails = 0;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function cacheFile(url) {
  const u = new URL(url);
  const key = (u.pathname + u.search).replace(/[^a-zA-Z0-9._=-]+/g, '_').replace(/^_+/, '') || 'index';
  return path.join(CACHE, u.host, key);
}

// Returns { status, body } and caches 200 and 404 answers (404 = the thing does not exist).
export async function get(url) {
  const file = cacheFile(url);
  if (fs.existsSync(file)) return JSON.parse(fs.readFileSync(file, 'utf8'));
  const host = new URL(url).host;
  const wait = (last.get(host) || 0) + DELAY_MS - Date.now();
  if (wait > 0) await sleep(wait);
  last.set(host, Date.now());
  let res;
  try {
    res = await fetch(url, { headers: { 'User-Agent': UA } });
  } catch (e) {
    res = { status: 0, text: async () => String(e) };
  }
  const out = { status: res.status, body: await res.text() };
  if (out.status === 200 || out.status === 404) {
    fails = 0;
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(out));
  } else if (++fails >= MAX_FAILS) {
    throw new Error(`stopping: ${MAX_FAILS} failed requests in a row (last ${out.status} ${url})`);
  }
  return out;
}

export function writeJson(rel, data) {
  const file = path.join(ROOT, rel);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data, null, 1));
  return file;
}

export function readJson(rel) {
  return JSON.parse(fs.readFileSync(path.join(ROOT, rel), 'utf8'));
}

export const decode = (s) =>
  s.replace(/&#x27;|&#39;/g, "'").replace(/&quot;|&#34;/g, '"').replace(/&amp;/g, '&')
   .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&nbsp;/g, ' ').replace(/<!-- -->/g, '');
