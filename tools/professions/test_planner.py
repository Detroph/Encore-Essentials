#!/usr/bin/env python3
"""Runs Encore-Professions' planner and farm picks outside the game (Lua 5.1 through lupa) and prints the routes.

    pip install lupa
    python3 tools/professions/test_planner.py [profession ...]

Auction prices are made up (one fixed price per item, from its ID), vendor prices are the addon's own. Fails with
exit code 1 when a route is empty, a step goes backwards, or the planner raises.
"""
import os
import sys

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ADDON = os.path.join(ROOT, "EncoreEssentials_Professions")

STUBS = r"""
time = os.time
C_AddOns = { GetAddOnMetadata = function() return "dev" end }
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print(m) end }
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
SlashCmdList = {}
function UnitName() return "Test" end
function GetRealmName() return "Realm" end
function UnitFactionGroup() return "Alliance" end
C_Map = { GetBestMapForUnit = function() return 1453 end, GetMapInfo = function(m) return { name = "Map " .. m, mapType = 3, parentMapID = 0 } end }
Enum = { UIMapType = { Continent = 2 } }
function GetCoinTextureString(c) return c .. "c" end
function IsPlayerSpell() return false end
C_Item = { GetItemCount = function() return 0 end, GetItemNameByID = function(id) return "Item " .. id end }
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
function geterrorhandler() return function(e) error(e) end end
-- made-up auction prices: 20c to 20s, stable per item
Auctionator = { API = { v1 = {
  GetAuctionPriceByItemID = function(_, id) return 20 + (id * 7919) % 2000 end,
  GetAuctionAgeByItemID = function() return 0 end } } }
"""


def run(profs):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    ns = lua.eval("{}")
    for f in ("Data/Recipes.lua", "Data/World.lua", "Core.lua", "Prices.lua", "Planner.lua", "Gather.lua"):
        chunk = lua.eval("function(src, name) return assert(loadstring(src, name)) end")(
            open(os.path.join(ADDON, f), encoding="utf-8").read(), f)
        chunk("EncoreEssentials_Professions", ns)
    P = ns.P
    bad = 0
    for prof in profs:
        if prof not in ("Mining", "Herbalism", "Skinning", "Fishing"):
            for mode in ("cheap", "fast"):
                for bonus in (0, 0.2):
                    r = lua.eval("""function(P, prof, mode, bonus)
                        return P.Plan(prof, 1, { mode = mode, bonus = bonus, cap = 75, known = function() return false end }) end""")(P, prof, mode, bonus)
                    steps = [r.steps[i] for i in range(1, len(r.steps) + 1)]
                    crafts = [s for s in steps if s.kind == "craft"]
                    print("%-14s %-5s WO %2d%%: %3d steps, %4d crafts, %8.2fg, ends %s" % (
                        prof, mode, bonus * 100, len(steps), r.crafts, r.total / 10000,
                        steps[-1].kind + " " + str(steps[-1]["from"] or steps[-1].at)))
                    if not crafts:
                        bad += 1
                        print("  no crafts")
                    last = 0
                    for s in crafts:
                        if s["from"] < last:
                            bad += 1
                            print("  step goes backwards", s.name)
                        last = s.to
                    if mode == "cheap" and bonus == 0:
                        for s in steps:
                            if s.kind == "craft":
                                print("    %3d-%-3d %3dx %-34s %s %8.2fg%s" % (s["from"], s.to, s.crafts, s.name, s.colour,
                                      (s.total + (s.learn or 0)) / 10000, "  (no price)" if s.unknown else ""))
                            elif s.kind == "rank":
                                print("    %3d     train %s (%s)" % (s.at, s.name, s.rank.how))
                            else:
                                print("    %3d     no trainer or vendor recipe" % s["from"])
        else:
            for skill in (1, 80, 160, 240):
                res = lua.eval("function(P, p, s) return P.FarmPicks(p, s) end")(P, prof, skill)
                picks = [res.picks[i] for i in range(1, len(res.picks) + 1)] if res else []
                print("%-10s at %3d: %s" % (prof, skill, ", ".join("%d (%.0f)" % (p.map, p.score) for p in picks) or "none"))
    return bad


UI_STUBS = r"""
local function mock(name)
  local o = { _name = name, _shown = false, _text = "" }
  return setmetatable(o, { __index = function(t, k)
    if k == "IsShown" or k == "IsVisible" then return function(self) return self._shown end end
    if k == "Show" then return function(self) self._shown = true end end
    if k == "Hide" then return function(self) self._shown = false end end
    if k == "SetShown" then return function(self, v) self._shown = v and true or false end end
    if k == "SetText" then return function(self, v) self._text = v end end
    if k == "GetText" then return function(self) return self._text end end
    if k == "GetStringHeight" or k == "GetFrameLevel" or k == "GetWidth" or k == "GetHeight" then return function() return 12 end end
    if k == "GetChecked" then return function() return true end end
    if k == "SetScript" then return function(self, ev, fn) rawset(self, "_" .. ev, fn) end end
    if k == "HookScript" then return function(self, ev, fn) rawset(self, "_" .. ev, fn) end end
    if k:match("^Create") then return function() return mock(k) end end
    return function() end
  end })
end
UIMOCK = mock
function CreateFrame(kind, name) local f = mock(kind); if name then _G[name] = f end; return f end
UIParent = mock("UIParent"); GameTooltip = mock("GameTooltip"); UISpecialFrames = {}
C_Timer = { After = function(_, fn) fn() end }
function tinsert(t, v) table.insert(t, v) end
GameFontNormalLarge = {}
ProfessionsFrame = mock("ProfessionsFrame"); ProfessionsFrame._shown = true
ProfessionsFrame.CraftingPage = mock("CraftingPage"); ProfessionsFrame.CraftingPage.RankBar = mock("RankBar")
PROF = nil
Professions = { GetProfessionInfo = function() return PROF end }
-- Encore core's UI kit, loaded for real
EncoreEssentials = { modules = {}, RegisterModule = function(self, n, m) self.modules[n] = m end }
"""


def ui_check():
    """Loads the panel with stand-in frames and shows every profession once; any Lua error fails."""
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    lua.execute(UI_STUBS)
    load = lua.eval("function(src, name, ...) return assert(loadstring(src, name))(...) end")
    kit = open(os.path.join(ROOT, "EncoreEssentials", "UI", "Kit.lua"), encoding="utf-8").read()
    load(kit, "Kit.lua", "EncoreEssentials", lua.eval("{ Encore = EncoreEssentials }"))
    ns = lua.eval("{}")
    for f in ("Data/Recipes.lua", "Data/World.lua", "Core.lua", "Prices.lua", "Planner.lua", "Shopping.lua",
              "Gather.lua", "Panel.lua"):
        load(open(os.path.join(ADDON, f), encoding="utf-8").read(), f, "EncoreEssentials_Professions", ns)
    P = ns.P
    lua.eval("function(P) P:DB(); P.Attach() end")(P)
    errors = 0
    for prof, skill, mx in (("Tailoring", 112, 150), ("First Aid", 150, 225), ("Cooking", 75, 150), ("Mining", 112, 150),
                            ("Herbalism", 40, 75), ("Skinning", 200, 225), ("Fishing", 112, 150), (None, 0, 0)):
        lua.eval("""function(name, skill, max)
            if name then PROF = { professionName = name, skillLevel = skill, maxSkillLevel = max, skillModifier = 0 }
            else PROF = nil end
        end""")(prof, skill, mx)
        try:
            lua.eval("function(P) return P:Refresh() end")(P)
        except Exception as e:  # noqa: BLE001
            errors += 1
            print("UI error for", prof, e)
    return errors


if __name__ == "__main__":
    profs = sys.argv[1:] or ["Tailoring", "First Aid", "Cooking", "Alchemy", "Blacksmithing", "Engineering",
                             "Leatherworking", "Enchanting", "Mining", "Herbalism", "Skinning", "Fishing"]
    bad = run(profs)
    bad += ui_check()
    print("UI check:", "ok" if not bad else "failed")
    sys.exit(1 if bad else 0)

