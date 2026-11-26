"""Reads Lua table literals as text, without running them (the data files of other addons are data, never code).

    value, end = parse(src, start)   # one literal starting at src[start]
    find_table(src, "ns.Recipes")    # the literal after `ns.Recipes =`

Handles what data files use: tables with [key] = value, name = value and list items, strings in '...', "..." and
[[...]], numbers, true, false and nil. Comments are skipped.
"""
import re

_num = re.compile(r"-?(0x[0-9a-fA-F]+|\d+\.?\d*(e[-+]?\d+)?|\.\d+)")
_name = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_ref = re.compile(r"[A-Za-z_][A-Za-z0-9_.]*")


def _skip(src, i):
    n = len(src)
    while i < n:
        c = src[i]
        if c in " \t\r\n,;":
            i += 1
        elif src.startswith("--", i):
            if src.startswith("--[[", i):
                j = src.find("]]", i)
                i = n if j < 0 else j + 2
            else:
                j = src.find("\n", i)
                i = n if j < 0 else j + 1
        else:
            break
    return i


def _string(src, i):
    q = src[i]
    out = []
    i += 1
    while src[i] != q:
        if src[i] == "\\":
            nxt = src[i + 1]
            out.append({"n": "\n", "t": "\t"}.get(nxt, nxt))
            i += 2
        else:
            out.append(src[i])
            i += 1
    return "".join(out), i + 1


def parse(src, i=0):
    i = _skip(src, i)
    c = src[i]
    if c == "{":
        return _table(src, i + 1)
    if c in "'\"":
        return _string(src, i)
    if src.startswith("[[", i):
        j = src.index("]]", i)
        return src[i + 2:j], j + 2
    m = _num.match(src, i)
    if m:
        t = m.group(0)
        return (int(t, 16) if "x" in t.lower() else (float(t) if any(ch in t for ch in ".e") else int(t))), m.end()
    m = _ref.match(src, i)
    if m:
        word = m.group(0)  # true, false, nil, or a name like ns.L.X (kept as its text)
        return {"true": True, "false": False, "nil": None}.get(word, word), m.end()
    raise ValueError("unexpected %r at %d" % (src[i:i + 30], i))


def _table(src, i):
    arr, kv = [], {}
    while True:
        i = _skip(src, i)
        if src[i] == "}":
            i += 1
            break
        if src[i] == "[" and not src.startswith("[[", i):
            key, i = parse(src, i + 1)
            i = _skip(src, i)
            assert src[i] == "]", src[i:i + 20]
            i = _skip(src, i + 1)
            assert src[i] == "=", src[i:i + 20]
            kv[key], i = parse(src, i + 1)
            continue
        m = _name.match(src, i)
        if m:
            j = _skip(src, m.end())
            if j < len(src) and src[j] == "=" and src[j + 1] != "=":
                kv[m.group(0)], i = parse(src, j + 1)
                continue
        v, i = parse(src, i)
        arr.append(v)
    if kv:
        for n, v in enumerate(arr, 1):
            kv[n] = v
        return kv, i
    return arr, i


def find_table(src, name):
    """The literal assigned to `name` (e.g. ns.Recipes), or None."""
    m = re.search(re.escape(name) + r"\s*=\s*", src)
    if not m:
        return None
    return parse(src, m.end())[0]


def as_list(t):
    """A parsed table as a 1-based list (tables with holes come back as dicts)."""
    if isinstance(t, list):
        return t
    if isinstance(t, dict):
        n = 1
        out = []
        while n in t:
            out.append(t[n])
            n += 1
        return out
    return []
