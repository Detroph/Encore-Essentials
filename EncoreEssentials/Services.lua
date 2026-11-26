-- Encore Essentials: small services every module can use.
--   Encore.CompareVersions(a, b) -> -1, 0 or 1 ("0.2.6.1-beta" < "0.2.6" < "0.2.7.1-beta")
--   Encore.IsFullVersion(v)      -> true for a full release (three numbers)
--   Encore.newerVersion           -> a newer Encore version a guild member has, once one is seen
-- Guild version check: at login each player tells the guild which version they have (one short addon message);
-- a player with a newer version answers once. Only full releases are announced, unless you run a beta yourself.
local _, ns = ...
local Encore = ns.Encore
local L = ns.L

local PREFIX = "EncoreVer"

local function parse(v)
    local t = {}
    for n in tostring(v or ""):gsub("^v", ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
    if #t == 3 then t[4] = math.huge end
    for i = #t + 1, 4 do t[i] = 0 end
    return t
end

function Encore.CompareVersions(a, b)
    local x, y = parse(a), parse(b)
    for i = 1, 4 do
        if x[i] ~= y[i] then return x[i] < y[i] and -1 or 1 end
    end
    return 0
end

function Encore.IsFullVersion(v) return parse(v)[4] == math.huge end

local function valid(v) return type(v) == "string" and v:match("^%d+%.%d+%.%d+[%.%d]*%-?%a*%d*$") ~= nil end

local lastAnswer = 0
local told = false
local function onMessage(_, prefix, msg, channel, sender)
    if prefix ~= PREFIX or channel ~= "GUILD" then return end
    local mine = Encore.version
    if mine == "dev" or type(msg) ~= "string" then return end
    local kind, v = msg:match("^(%a+):(.+)$")
    if not (kind and valid(v)) then return end
    local cmp = Encore.CompareVersions(v, mine)
    if cmp > 0 then
        -- Someone has a newer one. Betas only count for players who run betas themselves.
        if not Encore.IsFullVersion(v) and Encore.IsFullVersion(mine) then return end
        if Encore.newerVersion and Encore.CompareVersions(v, Encore.newerVersion) <= 0 then return end
        Encore.newerVersion = v
        if not told then
            told = true
            Encore:Print(L.NEWER_VERSION, v)
        end
    elseif cmp < 0 and kind == "hello" and GetTime() - lastAnswer > 60 then
        -- Tell an older player once a minute at most, after a moment so not everyone answers at once.
        lastAnswer = GetTime()
        C_Timer.After(2 + math.random() * 6, function()
            C_ChatInfo.SendAddonMessage(PREFIX, "have:" .. mine, "GUILD")
        end)
    end
end

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local ok, err = pcall(onMessage, event, ...)
        if not ok then geterrorhandler()(err) end
    elseif event == "PLAYER_LOGIN" then
        if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        self:RegisterEvent("CHAT_MSG_ADDON")
        C_Timer.After(15, function()
            if IsInGuild() and Encore.version ~= "dev" then
                C_ChatInfo.SendAddonMessage(PREFIX, "hello:" .. Encore.version, "GUILD")
            end
        end)
    end
end)
f:RegisterEvent("PLAYER_LOGIN")
