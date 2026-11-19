// Settings for the data refresh (tools/refresh.mjs): tools/refresh.config.json, which is not in the repository.
// Copy tools/refresh.config.example.json to tools/refresh.config.json and set your paths.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
let cached;
export function refreshConfig() {
  if (cached) return cached;
  for (const f of ['refresh.config.json', 'refresh.config.example.json']) {
    const p = path.join(DIR, f);
    if (fs.existsSync(p)) { cached = { file: p, ...JSON.parse(fs.readFileSync(p, 'utf8')) }; return cached; }
  }
  return (cached = {});
}
