-- Encore-QoL: battleground data for the PvP frames. Where each piece comes from:
--   Node owner and capture timers  battleground chat lines (CHAT_MSG_BG_SYSTEM_*), plus the map's POI icons
--                                  (C_AreaPoiInfo). Encore learns which POI icon means which owner from the
--                                  chat lines, so on a late join the icons alone tell it the owners.
--   Capture time                   counted down from the moment a node is assaulted: AB 60 s, AV 240 s.
--   Scores and bases               the score widgets at the top of the screen (C_UIWidgetManager).
--   Boss and officer health        read every second from target, focus, mouseover, nameplates and the raid's
--                                  targets, then shared with the group.
--   Sharing                        addon messages in instance chat on Encore's own prefix. Capping's messages are
--                                  read too, and Encore answers in Capping's format for players who have it.
-- Forever keeps the combat log away from addons, so deaths come from health hitting 0 or a tower falling.
local _, ns = ...
local Q = _G.EncoreQoL -- Encore-PvP plugs its features into Encore-QoL (same window, same saved settings)

local BG = {}
Q.BG = BG

local PREFIX = "EncoreQoL"
local CAPPING = "Capping"

BG.CAP_TIME = { AB = 60, AV = 240 }

-- instanceID -> battleground
local INSTANCES = { [529] = "AB", [30] = "AV", [489] = "WSG", [2107] = "AB", [2245] = "AV" }

local AB_NODES = { "Stables", "Farm", "Blacksmith", "Lumber Mill", "Gold Mine" }
BG.AB_NODES = AB_NODES

-- AV nodes with their kind and starting owner.
local AV_NODES = {
    { name = "Dun Baldar North Bunker", kind = "tower", owner = "A" },
    { name = "Dun Baldar South Bunker", kind = "tower", owner = "A" },
    { name = "Icewing Bunker", kind = "tower", owner = "A" },
    { name = "Stonehearth Bunker", kind = "tower", owner = "A" },
    { name = "Iceblood Tower", kind = "tower", owner = "H" },
    { name = "Tower Point", kind = "tower", owner = "H" },
    { name = "East Frostwolf Tower", kind = "tower", owner = "H" },
    { name = "West Frostwolf Tower", kind = "tower", owner = "H" },
    { name = "Stormpike Aid Station", kind = "gy", owner = "A" },
    { name = "Stormpike Graveyard", kind = "gy", owner = "A" },
    { name = "Stonehearth Graveyard", kind = "gy", owner = "A" },
    { name = "Snowfall Graveyard", kind = "gy", owner = nil },
    { name = "Iceblood Graveyard", kind = "gy", owner = "H" },
    { name = "Frostwolf Graveyard", kind = "gy", owner = "H" },
    { name = "Frostwolf Relief Hut", kind = "gy", owner = "H" },
    { name = "Irondeep Mine", kind = "mine", owner = nil },
    { name = "Coldtooth Mine", kind = "mine", owner = nil },
}
BG.AV_NODES = AV_NODES

-- Generals, captains and the officer in each tower. NPC IDs of marshals and warmasters to check on Forever.
BG.GENERALS = { A = { id = 11948, name = "Vanndar" }, H = { id = 11946, name = "Drek'Thar" } }
BG.OFFICERS = {
    { id = 11949, name = "Balinda", side = "A", captain = true },
    { id = 14762, name = "Dun Baldar North Marshal", side = "A", tower = "Dun Baldar North Bunker" },
    { id = 14763, name = "Dun Baldar South Marshal", side = "A", tower = "Dun Baldar South Bunker" },
    { id = 14764, name = "Icewing Marshal", side = "A", tower = "Icewing Bunker" },
    { id = 14765, name = "Stonehearth Marshal", side = "A", tower = "Stonehearth Bunker" },
    { id = 11947, name = "Galvangar", side = "H", captain = true },
    { id = 14773, name = "Iceblood Warmaster", side = "H", tower = "Iceblood Tower" },
    { id = 14776, name = "Tower Point Warmaster", side = "H", tower = "Tower Point" },
    { id = 14772, name = "East Frostwolf Warmaster", side = "H", tower = "East Frostwolf Tower" },
    { id = 14777, name = "West Frostwolf Warmaster", side = "H", tower = "West Frostwolf Tower" },
}
local WATCHED = {}
for _, g in pairs(BG.GENERALS) do WATCHED[g.id] = true end
for _, o in ipairs(BG.OFFICERS) do WATCHED[o.id] = true end

-- AB points per second by bases held (classic rates).
BG.AB_RATE = { [0] = 0, 10 / 12, 10 / 9, 10 / 6, 10 / 3, 30 }
BG.AB_WIN = 2000

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
BG.users = 0           -- frame features using the data
BG.kind = nil          -- "AB", "AV", "WSG" or nil
BG.nodes = {}          -- name -> { name, kind, owner, contestedBy, ends, firstHand, poi }
BG.health = {}         -- npcId -> { pct, at, firstHand }
BG.score = { A = 0, H = 0, basesA = 0, basesH = 0, reinfA = nil, reinfH = nil }
BG.preview = false

function BG:MySide() return UnitFactionGroup("player") == "Horde" and "H" or "A" end
function BG:EnemySide() return self:MySide() == "H" and "A" or "H" end

local function resetNodes(kind)
    wipe(BG.nodes)
    if kind == "AB" then
        for _, n in ipairs(AB_NODES) do BG.nodes[n] = { name = n, kind = "base" } end
    elseif kind == "AV" then
        for _, n in ipairs(AV_NODES) do BG.nodes[n.name] = { name = n.name, kind = n.kind, owner = n.owner } end
    end
    wipe(BG.health)
    BG.score = { A = 0, H = 0, basesA = 0, basesH = 0 }
end

-- Timers that are still running, soonest first.
function BG:Timers()
    local list, now = {}, GetTime()
    for _, n in pairs(self.nodes) do
        if n.ends and n.ends > now then list[#list + 1] = n end
    end
    table.sort(list, function(a, b) return a.ends < b.ends end)
    return list
end

function BG:HealthOf(id)
    local h = self.health[id]
    if not h then return nil end
    return h.pct, GetTime() - h.at
end

-- Officer status: "alive", "attacked" (lost health in the last 15 s), "dead".
function BG:OfficerState(o)
    if o.tower then
        local n = self.nodes[o.tower]
        if n and n.destroyed then return "dead" end
    end
    local pct, age = self:HealthOf(o.id)
    if pct == 0 then return "dead" end
    if pct and pct < 100 and age < 15 then return "attacked" end
    return "alive"
end

-- AB: who wins, when, and with what score.
function BG:Prediction()
    local s = self.score
    local ra, rh = BG.AB_RATE[s.basesA or 0] or 0, BG.AB_RATE[s.basesH or 0] or 0
    local ta = ra > 0 and (BG.AB_WIN - s.A) / ra or math.huge
    local th = rh > 0 and (BG.AB_WIN - s.H) / rh or math.huge
    if ta == math.huge and th == math.huge then return nil end
    if ta <= th then
        return "A", ta, BG.AB_WIN, math.min(BG.AB_WIN, math.floor(s.H + rh * ta))
    end
    return "H", th, math.min(BG.AB_WIN, math.floor(s.A + ra * th)), BG.AB_WIN
end

-- AB: bases your side needs from now on to still win (nil when no number of bases does it).
function BG:BasesNeeded()
    local s, me = self.score, self:MySide()
    local mine, theirs = me == "A" and s.A or s.H, me == "A" and s.H or s.A
    for need = 1, 5 do
        local myRate, theirRate = BG.AB_RATE[need], BG.AB_RATE[5 - need]
        local myTime = (BG.AB_WIN - mine) / myRate
        local theirTime = theirRate > 0 and (BG.AB_WIN - theirs) / theirRate or math.huge
        if myTime < theirTime then return need end
    end
    return nil
end

---------------------------------------------------------------------------
-- Chat lines
---------------------------------------------------------------------------
-- Node names in other client languages. Battleground chat and map labels use the client's language, while
-- Encore keys its nodes by the English names. Arathi Basin's five bases are listed here; any client also learns
-- each node's map label (and its POI ID) the first time it is matched, saved in EncoreQoLDB.frames.poiIDs.
local ALIASES = {
    AB = {
        Stables = { "Ställe", "écuries", "establos" },
        Farm = { "Hof", "ferme", "granja" },
        Blacksmith = { "Schmiede", "forge", "herrería" },
        ["Lumber Mill"] = { "Sägewerk", "scierie", "aserradero" },
        ["Gold Mine"] = { "Goldmine", "mine d'or", "mina de oro" },
    },
}
BG.localNames = {} -- [name as the client writes it] = node key, for this battleground

local function addLocalName(text, key)
    if type(text) == "string" and text ~= "" and text ~= key then BG.localNames[text] = key end
end

local function resetLocalNames(kind)
    wipe(BG.localNames)
    for key, list in pairs(ALIASES[kind] or {}) do
        for _, alias in ipairs(list) do addLocalName(alias, key) end
    end
end

local function nodeIn(text)
    local best, bestLen
    for name in pairs(BG.nodes) do
        if text:find(name, 1, true) and (not bestLen or #name > bestLen) then best, bestLen = name, #name end
    end
    for alias, key in pairs(BG.localNames) do
        if BG.nodes[key] and text:find(alias, 1, true) and (not bestLen or #alias > bestLen) then best, bestLen = key, #alias end
    end
    return best
end

-- The game's own words for the two factions, so this works in any client language.
local function factionWords(side)
    if side == "H" then return { FACTION_HORDE, "Horde" } end
    return { FACTION_ALLIANCE, "Alliance" }
end

local function teamIn(text, event)
    if event == "CHAT_MSG_BG_SYSTEM_HORDE" then return "H" end
    if event == "CHAT_MSG_BG_SYSTEM_ALLIANCE" then return "A" end
    for _, side in ipairs({ "H", "A" }) do
        for _, word in ipairs(factionWords(side)) do
            if type(word) == "string" and word ~= "" and text:find(word, 1, true) then return side end
        end
    end
end

local function learnTexture(node)
    local poi = node.poi
    if not (poi and poi.textureIndex and BG.kind) then return end
    local key = node.contestedBy and ("c" .. node.contestedBy) or (node.owner or "N")
    local learned = Q.db.frames.poiTextures
    if type(learned) ~= "table" then learned = {}; Q.db.frames.poiTextures = learned end
    learned[BG.kind] = learned[BG.kind] or {}
    learned[BG.kind][poi.textureIndex] = key
end

function BG:Contest(name, by, secondsLeft, firstHand)
    local n = self.nodes[name]
    if not n then return end
    n.contestedBy = by
    n.ends = GetTime() + (secondsLeft or BG.CAP_TIME[self.kind] or 60)
    n.firstHand = firstHand
    self:Changed()
end

function BG:Settle(name, owner, destroyed)
    local n = self.nodes[name]
    if not n then return end
    n.owner, n.contestedBy, n.ends = owner, nil, nil
    if destroyed then n.destroyed = true end
    self:Changed()
end

-- What a line says happened. English lines are read by their words; in other languages the battleground's own
-- order of events is used: a node that isn't being taken is now assaulted, one being taken is now captured (or
-- destroyed, for a tower) by the side that assaulted it or defended by the other side. Mines change hands at once.
local function englishVerb(lower)
    if lower:find("under attack") or lower:find("assault") or lower:find("claims") then return "contest" end
    if lower:find("destroyed") then return "destroy" end
    if lower:find("taken") or lower:find("captured") or lower:find("defended") or lower:find("controls") then return "settle" end
end

local lastLine = {} -- [node] = GetTime() of the last line read without English words (the herald repeats them)

local function onSystem(event, text)
    if _G.issecretvalue and _G.issecretvalue(text) then return end -- secret chat values can't be read
    if not BG.kind or not text then return end
    local name = nodeIn(text)
    if not name then return end
    local team = teamIn(text, event)
    local verb = englishVerb(text:lower())
    local n = BG.nodes[name]
    if not verb then
        local now = GetTime()
        if lastLine[name] and now - lastLine[name] < 3 then return end
        lastLine[name] = now
        if n.kind == "mine" then
            verb = "settle"
        elseif n.contestedBy then
            verb = (n.kind == "tower" and team == n.contestedBy) and "destroy" or "settle"
        else
            verb = "contest"
        end
    end
    if verb == "contest" then
        BG:Contest(name, team, nil, true)
    elseif verb == "destroy" then
        BG:Settle(name, team, true)
    else
        BG:Settle(name, team)
    end
    C_Timer.After(1, function()
        BG:ScanPOIs()
        learnTexture(BG.nodes[name])
    end)
end

---------------------------------------------------------------------------
-- Map POIs and score widgets
---------------------------------------------------------------------------
function BG:ScanPOIs()
    if not (C_AreaPoiInfo and C_Map) then return end
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return end
    local learned = type(Q.db.frames.poiTextures) == "table" and Q.db.frames.poiTextures[self.kind] or {}
    if type(Q.db.frames.poiIDs) ~= "table" then Q.db.frames.poiIDs = {} end
    local ids = Q.db.frames.poiIDs[self.kind] or {}
    Q.db.frames.poiIDs[self.kind] = ids
    for _, poiID in ipairs(C_AreaPoiInfo.GetAreaPOIForMap(map) or {}) do
        local info = C_AreaPoiInfo.GetAreaPOIInfo(map, poiID)
        local name = info and info.name and nodeIn(info.name)
        if not name and self.nodes[ids[poiID] or ""] then name = ids[poiID] end
        local n = name and self.nodes[name]
        if n then
            -- Remember which POI this node is and what this client calls it, for chat in any language.
            ids[poiID] = name
            addLocalName(info.name, name)
            local old = n.poi and n.poi.textureIndex
            n.poi = { id = poiID, textureIndex = info.textureIndex }
            if type(info.position) == "table" and info.position.GetXY then
                local x, y = info.position:GetXY()
                if x and y then n.pos = { x, y } end
            end
            local known = learned[info.textureIndex]
            if known and old ~= info.textureIndex then
                if known:sub(1, 1) == "c" then
                    if not n.contestedBy then n.contestedBy = known:sub(2) end
                else
                    n.owner = known ~= "N" and known or nil
                    n.contestedBy, n.ends = nil, nil
                end
            end
        end
    end
end

-- /eqol bgpoi: lists the map labels on this map with their POI IDs and the node each one is matched to, so
-- node names in other client languages can be added to ALIASES.
function BG:DumpPOIs()
    local map = C_Map and C_Map.GetBestMapForUnit("player")
    if not (map and C_AreaPoiInfo) then Q:Print("No map here.") return end
    Q:Print(("Map %d, battleground %s:"):format(map, tostring(self.kind)))
    local ids = type(Q.db.frames.poiIDs) == "table" and Q.db.frames.poiIDs[self.kind or ""] or {}
    for _, poiID in ipairs(C_AreaPoiInfo.GetAreaPOIForMap(map) or {}) do
        local info = C_AreaPoiInfo.GetAreaPOIInfo(map, poiID)
        if info then
            local node = (info.name and nodeIn(info.name)) or ids[poiID] or "-"
            Q:Print(("  %d  %s  (texture %s) = %s"):format(poiID, tostring(info.name), tostring(info.textureIndex), node))
        end
    end
end

local function numbers(text)
    local list = {}
    for d in tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gmatch("%d+") do list[#list + 1] = tonumber(d) end
    return list
end

-- Reads the two team score widgets at the top of the screen: first Alliance, then Horde.
function BG:ScanWidgets()
    if not (C_UIWidgetManager and C_UIWidgetManager.GetTopCenterWidgetSetID) then return end
    local set = C_UIWidgetManager.GetTopCenterWidgetSetID()
    local widgets = set and C_UIWidgetManager.GetAllWidgetsBySetID(set) or {}
    local found = {}
    for _, w in ipairs(widgets) do
        local info = C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo and C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo(w.widgetID)
        if info and info.text and info.text ~= "" then found[#found + 1] = { id = w.widgetID, text = info.text } end
    end
    table.sort(found, function(a, b) return a.id < b.id end)
    if #found < 2 then return end
    local a, h = numbers(found[1].text), numbers(found[2].text)
    local s = self.score
    if self.kind == "AB" then
        -- "Bases: 3  Resources: 1240/2000"
        if #a >= 2 then s.basesA, s.A = a[1], a[#a - 1] or a[1] end
        if #h >= 2 then s.basesH, s.H = h[1], h[#h - 1] or h[1] end
    elseif self.kind == "AV" then
        -- "Reinforcements: 412"
        s.reinfA, s.reinfH = a[#a], h[#h]
    end
end

---------------------------------------------------------------------------
-- Boss and officer health
---------------------------------------------------------------------------
local function npcID(guid)
    local kind, _, _, _, _, id = strsplit("-", guid or "")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local units = { "target", "focus", "mouseover" }
for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
for i = 1, 40 do units[#units + 1] = "raid" .. i .. "target" end

function BG:ScanHealth()
    local now, seen = GetTime(), {}
    for _, unit in ipairs(units) do
        local id = UnitExists(unit) and npcID(UnitGUID(unit))
        if id and WATCHED[id] and not seen[id] then
            seen[id] = true
            local ok, pct = pcall(function()
                if UnitIsDead(unit) then return 0 end
                return math.floor(UnitHealth(unit) / math.max(1, UnitHealthMax(unit)) * 100 + 0.5)
            end)
            if ok and pct then
                local h = self.health[id]
                if not h or h.pct ~= pct or now - h.at > 5 then
                    self.health[id] = { pct = pct, at = now, firstHand = true }
                    self:SendHealth(id, pct)
                    self:Changed()
                end
            end
        end
    end
    -- Drop bars nobody has seen for a while.
    for id, h in pairs(self.health) do
        if now - h.at > 60 and h.pct ~= 0 then self.health[id] = nil end
    end
end

---------------------------------------------------------------------------
-- Sharing. On whenever a BG frame is on (no separate switch, Det's choice).
---------------------------------------------------------------------------
local cappingBad = false
local lastHealthSent = {}

local function cappingHere() return C_AddOns.IsAddOnLoaded("Capping") end

local function send(prefix, msg)
    if not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return end
    C_ChatInfo.SendAddonMessage(prefix, msg, "INSTANCE_CHAT")
end

-- Other PvP features send their own short messages ("kind:rest") through Encore's prefix and get them back
-- through BG.onMessage[kind](rest, sender).
BG.onMessage = {}
function BG:Send(msg) send(PREFIX, msg) end

function BG:SendHealth(id, pct)
    local now = GetTime()
    if lastHealthSent[id] and now - lastHealthSent[id] < 1 then return end
    lastHealthSent[id] = now
    send(PREFIX, "h:" .. id .. ":" .. pct)
    if not cappingHere() and not cappingBad then send(CAPPING, id .. ":" .. pct) end
end

-- Our first-hand timers, e.g. for a player who just joined.
function BG:SendTimers()
    local mine, capping = {}, {}
    local now = GetTime()
    for _, n in pairs(self.nodes) do
        if n.ends and n.ends > now and n.firstHand then
            local left = math.floor(n.ends - now)
            mine[#mine + 1] = ("%s|%s|%d"):format(n.name, n.contestedBy or "?", left)
            if n.poi and n.poi.id then capping[#capping + 1] = n.poi.id .. "-" .. left end
        end
    end
    if #mine > 0 then send(PREFIX, "t:" .. table.concat(mine, ";")) end
    if #capping > 0 and not cappingHere() and not cappingBad then send(CAPPING, table.concat(capping, "~") .. "~") end
end

local function nodeByPoi(poiID)
    for _, n in pairs(BG.nodes) do
        if n.poi and n.poi.id == poiID then return n end
    end
end

local function onAddonMessage(_, prefix, msg, _, sender)
    if not msg then return end
    if not BG.kind and select(2, IsInInstance()) ~= "pvp" then return end
    if sender and Ambiguate(sender, "none") == Q.FullName("player") then return end
    if prefix == PREFIX then
        local kind, rest = msg:match("^(%a+):?(.*)$")
        if kind == "h" then
            local id, pct = rest:match("^(%d+):(%d+)$")
            id, pct = tonumber(id), tonumber(pct)
            if id and WATCHED[id] and pct then
                local h = BG.health[id]
                if not h or not h.firstHand or GetTime() - h.at > 2 then BG.health[id] = { pct = pct, at = GetTime() } BG:Changed() end
            end
        elseif kind == "t" then
            for name, by, left in rest:gmatch("([^|;]+)|([^|;]+)|(%d+)") do
                local n = BG.nodes[name]
                if n and not n.ends then BG:Contest(name, by ~= "?" and by or nil, tonumber(left), false) end
            end
        elseif kind == "tr" then
            BG:SendTimers()
        elseif kind and BG.onMessage[kind] then
            local ok, err = pcall(BG.onMessage[kind], rest, sender)
            if not ok then geterrorhandler()(err) end
        end
    elseif prefix == CAPPING then
        if msg == "tr" then BG:SendTimers() return end
        local id, pct = msg:match("^(%d+):(%d+)$")
        if id then
            id, pct = tonumber(id), tonumber(pct)
            if WATCHED[id] and pct and pct <= 100 then
                local h = BG.health[id]
                if not h or not h.firstHand or GetTime() - h.at > 2 then BG.health[id] = { pct = pct, at = GetTime() } BG:Changed() end
            end
            return
        end
        local any = false
        for poi, left in msg:gmatch("(%d+)%-(%d+)~") do
            any = true
            local n = nodeByPoi(tonumber(poi))
            if n and not n.ends then BG:Contest(n.name, nil, tonumber(left), false) end
        end
        if not any then cappingBad = true end -- a format we don't know: stop speaking Capping's
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
BG.listeners = {}
function BG:Changed()
    for _, fn in ipairs(self.listeners) do pcall(fn) end
end

local handles = {}
local ticker

local function zoneCheck()
    local _, kind, _, _, _, _, _, instanceID = GetInstanceInfo()
    local bg = kind == "pvp" and INSTANCES[instanceID] or nil
    if bg ~= BG.kind then
        BG.kind = bg
        resetNodes(bg)
        resetLocalNames(bg)
        wipe(lastLine)
        cappingBad = false
        if bg then
            C_Timer.After(3, function()
                BG:ScanPOIs()
                send(PREFIX, "tr")
                if not cappingHere() then send(CAPPING, "tr") end
            end)
        end
        BG:Changed()
    end
end

function BG:Use()
    self.users = self.users + 1
    if self.users > 1 then return end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        C_ChatInfo.RegisterAddonMessagePrefix(CAPPING)
    end
    handles = {
        Q:On("PLAYER_ENTERING_WORLD", zoneCheck),
        Q:On("ZONE_CHANGED_NEW_AREA", zoneCheck),
        Q:On("CHAT_MSG_BG_SYSTEM_ALLIANCE", onSystem),
        Q:On("CHAT_MSG_BG_SYSTEM_HORDE", onSystem),
        Q:On("CHAT_MSG_BG_SYSTEM_NEUTRAL", onSystem),
        Q:On("CHAT_MSG_MONSTER_YELL", onSystem),
        Q:On("CHAT_MSG_ADDON", onAddonMessage),
        Q:On("AREA_POIS_UPDATED", function() if BG.kind then BG:ScanPOIs() BG:Changed() end end),
        Q:On("UPDATE_UI_WIDGET", function() if BG.kind then BG:ScanWidgets() BG:Changed() end end),
    }
    ticker = C_Timer.NewTicker(1, function()
        if not BG.kind then return end
        BG:ScanHealth()
        BG:ScanWidgets()
        BG:Changed()
    end)
    zoneCheck()
end

function BG:Release()
    self.users = math.max(0, self.users - 1)
    if self.users > 0 then return end
    for _, h in ipairs(handles) do Q:Off(h) end
    handles = {}
    if ticker then ticker:Cancel() ticker = nil end
end

---------------------------------------------------------------------------
-- Sample data for the Preview button (outside a battleground).
---------------------------------------------------------------------------
function BG:Sample(kind)
    local now = GetTime()
    local s = { kind = kind, nodes = {}, health = {}, score = {} }
    if kind == "AB" then
        local owners = { Stables = "H", Farm = "H", ["Lumber Mill"] = "H", ["Gold Mine"] = "A", Blacksmith = "A" }
        for _, n in ipairs(AB_NODES) do s.nodes[n] = { name = n, kind = "base", owner = owners[n] } end
        s.nodes.Blacksmith.contestedBy = "H"
        s.nodes.Blacksmith.ends = now + 42
        s.score = { A = 980, H = 1240, basesA = 1, basesH = 3 }
    else
        for _, n in ipairs(AV_NODES) do s.nodes[n.name] = { name = n.name, kind = n.kind, owner = n.owner } end
        s.nodes["Stormpike Graveyard"].contestedBy, s.nodes["Stormpike Graveyard"].ends = "H", now + 107
        s.nodes["Iceblood Tower"].contestedBy, s.nodes["Iceblood Tower"].ends = "A", now + 125
        s.nodes["Dun Baldar South Bunker"].contestedBy, s.nodes["Dun Baldar South Bunker"].ends = "H", now + 192
        s.nodes["Stonehearth Bunker"].destroyed, s.nodes["Stonehearth Bunker"].owner = true, "H"
        s.nodes["Icewing Bunker"].destroyed, s.nodes["Icewing Bunker"].owner = true, "H"
        s.health[11948] = { pct = 64, at = now - 8 }
        s.health[11946] = { pct = 92, at = now - 3 }
        s.health[11949] = { pct = 0, at = now - 60 }
        s.health[14773] = { pct = 71, at = now - 2 }
        s.score = { reinfA = 287, reinfH = 412 }
    end
    return s
end
