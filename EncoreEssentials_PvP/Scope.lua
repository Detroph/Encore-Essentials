-- Encore-QoL: "Customize for each battleground" for PvP features.
-- Q.PvPScoped(def, keys) gives a feature two extra settings, perBG and editBG. With perBG on, the listed keys are
-- kept per battleground (WSG, AB, AV): the options window edits the battleground picked in editBG, and in a
-- battleground the feature reads that battleground's values. A value not set for a battleground falls back to the
-- general one, so a battleground nobody has set up looks like the general setup.
local _, ns = ...
local Q = _G.EncoreQoL -- Encore-PvP plugs its features into Encore-QoL (same window, same saved settings)
local BG = Q.BG

Q.PVP_SCOPES = { { "WSG", "Warsong Gulch" }, { "AB", "Arathi Basin" }, { "AV", "Alterac Valley" } }

function Q.PvPScoped(def, keys)
    local scoped = {}
    for _, k in ipairs(keys) do scoped[k] = true end
    def.defaults = def.defaults or {}
    def.defaults.perBG = false
    def.defaults.editBG = "WSG"

    local function bgTable(s, which, create)
        if type(s.bg) ~= "table" then
            if not create then return nil end
            s.bg = {}
        end
        local t = s.bg[which]
        if type(t) ~= "table" and create then t = {}; s.bg[which] = t end
        return type(t) == "table" and t or nil
    end

    -- f:Get(key [, bg]): bg defaults to the battleground being edited in the window.
    function def:Get(key, which)
        local s = self:Saved()
        if scoped[key] and s.perBG then
            local t = bgTable(s, which or s.editBG or "WSG")
            if t and t[key] ~= nil then return t[key] end
        end
        local v = s[key]
        if v == nil and self.defaults then v = self.defaults[key] end
        return v
    end

    -- The value in use right now: the current battleground's, or the edited one's outside (for Preview).
    function def:Live(key)
        local s = self:Saved()
        return self:Get(key, BG.kind or s.editBG or "WSG")
    end

    function def:Set(key, value)
        local s = self:Saved()
        if scoped[key] and s.perBG then
            bgTable(s, s.editBG or "WSG", true)[key] = value
        else
            s[key] = value
        end
        if self.active or self.previewing then
            if self.OnOption then
                local ok, err = pcall(self.OnOption, self, key, value)
                if not ok then geterrorhandler()(err) end
            end
        end
        Q:Changed(self)
    end

    local head = {
        { kind = "check", key = "perBG", name = "Customize for each battleground",
          tip = "Keep a different look for Warsong Gulch, Arathi Basin and Alterac Valley. A battleground you haven't set up uses the general setup." },
        { kind = "group", text = "Battleground", when = function(f) return f:Get("perBG") == true end },
        { kind = "choice", key = "editBG", name = "Settings below are for", choices = Q.PVP_SCOPES },
    }
    local options = {}
    for _, o in ipairs(head) do options[#options + 1] = o end
    for _, o in ipairs(def.options or {}) do options[#options + 1] = o end
    def.options = options
    return def
end
