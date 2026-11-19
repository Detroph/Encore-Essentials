// Reads the table assignments in a generated Lua data file (e.g. "ns.items = { ... }") without running any Lua.
// Supports what generated data files use: strings ("", '', [[ ]], [==[ ]==]), numbers, true/false/nil,
// tables with [key] = value, name = value and list entries, and -- comments. A bare name used as a value
// (a Lua variable, e.g. a shared constant) is read as { $ref: 'name' }, and as the key '$name' in [name] = value. Assignments may index a table: DB["x"] = { ... }.
export function readLuaTables(src) {
  let i = 0;
  const n = src.length;
  const err = (m) => { throw new Error(`${m} at offset ${i}: ${JSON.stringify(src.slice(i, i + 40))}`); };
  function ws() {
    for (;;) {
      while (i < n && /\s/.test(src[i])) i++;
      if (src.startsWith('--', i)) {
        const lm = /^--\[(=*)\[/.exec(src.slice(i, i + 20));
        if (lm) { const end = src.indexOf(`]${lm[1]}]`, i); i = end < 0 ? n : end + lm[1].length + 2; }
        else { const end = src.indexOf('\n', i); i = end < 0 ? n : end + 1; }
        continue;
      }
      return;
    }
  }
  function str() {
    const q = src[i];
    if (q === '[') {
      const m = /^\[(=*)\[/.exec(src.slice(i, i + 20));
      const close = `]${m[1]}]`;
      let start = i + m[0].length;
      if (src[start] === '\n') start++;
      const end = src.indexOf(close, start);
      i = end + close.length;
      return src.slice(start, end);
    }
    i++;
    let out = '';
    while (i < n && src[i] !== q) {
      if (src[i] === '\\') {
        const c = src[++i];
        const map = { n: '\n', t: '\t', r: '\r', '\\': '\\', '"': '"', "'": "'", '\n': '\n' };
        if (c in map) { out += map[c]; i++; }
        else if (/\d/.test(c)) { const m = /^\d{1,3}/.exec(src.slice(i)); out += String.fromCharCode(+m[0]); i += m[0].length; }
        else { out += c; i++; }
      } else out += src[i++];
    }
    i++;
    return out;
  }
  function value() {
    ws();
    const c = src[i];
    if (c === '{') return table();
    if (c === '"' || c === "'" || (c === '[' && /^\[=*\[/.test(src.slice(i, i + 10)))) return str();
    const m = /^-?(?:0x[0-9a-f]+|\d+\.?\d*(?:e[+-]?\d+)?|\.\d+)/i.exec(src.slice(i, i + 40));
    if (m) { i += m[0].length; return Number(m[0]); }
    if (src.startsWith('true', i)) { i += 4; return true; }
    if (src.startsWith('false', i)) { i += 5; return false; }
    if (src.startsWith('nil', i)) { i += 3; return null; }
    const id = /^[A-Za-z_][\w.]*/.exec(src.slice(i, i + 80));
    if (id) { i += id[0].length; return { $ref: id[0] }; }
    err('unexpected value');
  }
  // Tables become arrays when they only have list entries, objects otherwise (list entries keyed 1, 2, ...).
  function table() {
    i++;
    const obj = {};
    let pos = 0, keyed = false;
    for (;;) {
      ws();
      if (src[i] === '}') { i++; break; }
      let key;
      if (src[i] === '[' && !/^\[=*\[/.test(src.slice(i, i + 10))) {
        i++; key = value(); if (key && key.$ref) key = '$' + key.$ref; ws(); if (src[i] !== ']') err('expected ]'); i++; ws(); if (src[i] !== '=') err('expected ='); i++;
        keyed = true;
      } else {
        const m = /^([A-Za-z_]\w*)\s*=(?!=)/.exec(src.slice(i, i + 80));
        if (m) { key = m[1]; i += m[0].length; keyed = true; }
      }
      const v = value();
      if (key === undefined) obj[++pos] = v; else obj[key] = v;
      ws();
      if (src[i] === ',' || src[i] === ';') i++;
    }
    if (!keyed) return Object.keys(obj).map((k) => obj[k]);
    return obj;
  }
  const out = {};
  const re = /(?:^|\n)\s*(?:local\s+)?([\w.]+(?:\[\s*"[^"\n]+"\s*\])?)\s*=\s*(?=[{"'[\d-]|true|false)/g;
  let m;
  while ((m = re.exec(src))) {
    i = m.index + m[0].length;
    try { out[m[1]] = value(); } catch (e) { throw new Error(`${m[1]}: ${e.message}`); }
    re.lastIndex = i;
  }
  return out;
}
