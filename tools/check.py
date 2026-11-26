#!/usr/bin/env python3
"""Checks the addons before a pull request merges or a release is built.

    python3 tools/check.py

1. Every Lua file compiles as Lua 5.1 (luac5.1 -p, or lupa when luac5.1 is missing). This also catches the
   200 locals and 60 upvalues limits that only show in game as a file that silently doesn't load.
2. Every file a .toc lists exists (same letter case), and every Lua file is loaded by a .toc or an .xml.
3. Every Interface\\AddOns\\EncoreEssentials... texture or font path in the code exists.
4. What the packager would ship (everything but the .pkgmeta ignore list) holds only addon files.

Exit code 1 when anything fails, with one line per problem.
"""
import fnmatch
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDONS = sorted(d for d in os.listdir(ROOT) if d.startswith("EncoreEssentials") and os.path.isdir(os.path.join(ROOT, d)))
SHIP_TYPES = {".lua", ".toc", ".xml", ".tga", ".blp", ".ttf", ".otf", ".txt", ".md", ".png", ".jpg", ".ogg", ".mp3"}
MAX_FILE = 4 * 1024 * 1024
problems = []


def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def exists_exact(path):
    """True when the file exists with exactly this letter case (Windows ignores case, the packager doesn't)."""
    cur = ROOT
    for part in rel(path).split("/"):
        if not os.path.isdir(cur) or part not in os.listdir(cur):
            return False
        cur = os.path.join(cur, part)
    return True


def lua_files():
    for addon in ADDONS:
        for base, _, files in os.walk(os.path.join(ROOT, addon)):
            for f in files:
                if f.endswith(".lua"):
                    yield os.path.join(base, f)


# 1. syntax --------------------------------------------------------------------------------------------------
def check_syntax(files):
    luac = shutil.which("luac5.1")
    if luac:
        for f in files:
            r = subprocess.run([luac, "-p", f], capture_output=True, text=True)
            if r.returncode != 0:
                problems.append("syntax: " + (r.stderr.strip() or rel(f)))
        return
    try:
        from lupa import lua51
    except ImportError:
        problems.append("syntax: neither luac5.1 nor lupa (pip install lupa) is installed")
        return
    rt = lua51.LuaRuntime()
    load = rt.eval("function(s, n) local _, e = loadstring(s, n); return e end")
    for f in files:
        with open(f, encoding="utf-8", errors="replace") as fh:
            err = load(fh.read(), "@" + rel(f))
        if err:
            problems.append("syntax: " + err)


# 2. .toc and .xml -------------------------------------------------------------------------------------------
def check_toc():
    loaded = set()
    for addon in ADDONS:
        folder = os.path.join(ROOT, addon)
        toc = os.path.join(folder, addon + ".toc")
        if not os.path.isfile(toc):
            problems.append(f"toc: {addon} has no {addon}.toc")
            continue
        with open(toc, encoding="utf-8-sig") as fh:
            lines = [l.strip() for l in fh]
        interface = [l for l in lines if l.startswith("## Interface:")]
        if not interface:
            problems.append(f"toc: {rel(toc)} has no ## Interface line")
        for line in lines:
            if not line or line.startswith("#"):
                continue
            path = os.path.join(folder, *line.replace("\\", "/").split("/"))
            if not exists_exact(path):
                problems.append(f"toc: {rel(toc)} lists {line}, which doesn't exist (check the letter case)")
                continue
            loaded.add(os.path.normpath(path))
            if line.lower().endswith(".xml"):
                with open(path, encoding="utf-8") as fh:
                    xml = fh.read()
                for inc in re.findall(r'<(?:Script|Include)\s+file="([^"]+)"', xml):
                    p = os.path.join(os.path.dirname(path), *inc.replace("\\", "/").split("/"))
                    if not exists_exact(p):
                        problems.append(f"xml: {rel(path)} loads {inc}, which doesn't exist")
                    loaded.add(os.path.normpath(p))
    for f in lua_files():
        if os.path.normpath(f) not in loaded:
            problems.append(f"toc: {rel(f)} is not loaded by any .toc or .xml")


# 3. media paths ---------------------------------------------------------------------------------------------
MEDIA = re.compile(r'Interface[\\/]+AddOns[\\/]+(EncoreEssentials\w*)((?:[\\/]+[\w\-. ]+)+)', re.I)


def check_media(files):
    for f in list(files) + [os.path.join(ROOT, a, a + ".toc") for a in ADDONS]:
        if not os.path.isfile(f):
            continue
        with open(f, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        for addon, tail in set(MEDIA.findall(text)):
            parts = [p for p in re.split(r"[\\/]+", tail) if p]
            path = os.path.join(ROOT, addon, *parts)
            if os.path.splitext(path)[1]:
                ok = exists_exact(path)
            else:
                ok = any(exists_exact(path + ext) for ext in (".tga", ".blp", ".png", ".ttf"))
                ok = ok or os.path.isdir(path)  # a folder prefix built up in code
            if not ok:
                problems.append(f"media: {rel(f)} uses Interface\\AddOns\\{addon}{tail}, which doesn't exist")


# 4. what ships ----------------------------------------------------------------------------------------------
def pkgmeta_ignores():
    ignores, on = [], False
    with open(os.path.join(ROOT, ".pkgmeta"), encoding="utf-8") as fh:
        for line in fh:
            if re.match(r"^ignore:", line):
                on = True
                continue
            if on:
                m = re.match(r"^\s+-\s+(.+)$", line)
                if m:
                    ignores.append(m.group(1).strip().strip('"\''))
                elif line.strip() and not line.startswith(" "):
                    on = False
    return ignores


def check_package():
    ignores = pkgmeta_ignores()
    total, count = 0, 0
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for f in files:
            path = os.path.join(base, f)
            r = rel(path)
            if f.startswith(".") or any(r == i or r.startswith(i + "/") or fnmatch.fnmatch(f, i) for i in ignores):
                continue
            if os.path.exists(os.path.join(ROOT, ".git")) and subprocess.run(
                    ["git", "-C", ROOT, "check-ignore", "-q", r]).returncode == 0:
                continue  # gitignored: not in the repository, so the packager never sees it
            size = os.path.getsize(path)
            total, count = total + size, count + 1
            top = r.split("/")[0]
            ext = os.path.splitext(f)[1].lower()
            if top in ADDONS and ext not in SHIP_TYPES:
                problems.append(f"package: {r} would ship inside the addon ({ext or 'no extension'} files don't belong there)")
            elif top not in ADDONS and r not in ("CHANGELOG.md", "LICENSE", "NOTICE", "NOTICE.txt"):
                problems.append(f"package: {r} would ship in the zip; add it to the .pkgmeta ignore list")
            if size > MAX_FILE:
                problems.append(f"package: {r} is {size / 1048576:.1f} MB")
    print(f"package: {count} files, {total / 1048576:.1f} MB before compression")


def main():
    files = list(lua_files())
    check_syntax(files)
    check_toc()
    check_media(files)
    check_package()
    print(f"checked {len(files)} Lua files in {', '.join(ADDONS)}")
    for p in problems:
        print("FAIL " + p)
    if problems:
        print(f"{len(problems)} problem(s)")
        sys.exit(1)
    print("all checks passed")


if __name__ == "__main__":
    main()
