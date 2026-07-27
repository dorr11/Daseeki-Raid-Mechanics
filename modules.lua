--[[
    Daseeki Raid Mechanics — custom-module framework

    Some mechanics are too bespoke for the declarative trigger/style model (ported
    WeakAuras: multi-unit trackers, nameplate icons, raid-roster rotations). Those
    are implemented as "modules": a self-contained chunk of runtime attached to a
    boss, shown in that boss's options with an Enable toggle (+ optional config),
    and Start()/Stop()'d automatically on engage/disengage.

    Register (in a mod_*.lua file, loaded after modules.lua):
        Addon:RegisterModule({
            id="loatheb_healers", raidId="naxxramas", bossId="loatheb",
            name="Healer Tracker (WA)", desc="...",
            defaults = { enabled = false },
            placeKey = "naxxramas:loatheb:healers_mod",   -- optional: a placeable anchor
            placeDef = { name=, icon=, style="icon" },     -- mechDef for the Place preview
            Start = function(self) ... end,                -- begin runtime
            Stop  = function(self) ... end,                -- tear down
            Test  = function(self) ... end,                -- optional preview from options
            BuildConfig = function(self, parent) ... end,  -- optional extra option widgets
        })

    Enabled state + per-module config live in DaseekiRaidMechanicsDB.modules[id].
--]]

local _, Addon = ...

Addon.modules        = {}   -- ordered array of module defs
Addon.modulesByBoss  = {}   -- "raidId:bossId" -> { defs }
Addon._activeModules = {}   -- id -> def (currently Start()'d)

function Addon:RegisterModule(def)
    assert(type(def) == "table" and def.id, "RegisterModule requires an id")
    Addon.modules[#Addon.modules + 1] = def
    local k = (def.raidId or "?") .. ":" .. (def.bossId or "?")
    Addon.modulesByBoss[k] = Addon.modulesByBoss[k] or {}
    table.insert(Addon.modulesByBoss[k], def)
    return def
end

function Addon:GetBossModules(raidId, bossId)
    return Addon.modulesByBoss[(raidId or "?") .. ":" .. (bossId or "?")] or {}
end

-- ── Config (DaseekiRaidMechanicsDB.modules[id]) ─────────────────────────────────
function Addon:GetModuleConfig(id)
    Addon.db.modules = Addon.db.modules or {}
    local c = Addon.db.modules[id]
    if not c then c = {}; Addon.db.modules[id] = c end
    return c
end

function Addon:IsModuleEnabled(id, def)
    local c = Addon:GetModuleConfig(id)
    if c.enabled ~= nil then return c.enabled end
    return (def and def.defaults and def.defaults.enabled) and true or false
end

function Addon:SetModuleEnabled(id, on)
    Addon:GetModuleConfig(id).enabled = on and true or false
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────────
function Addon:StartModule(def)
    if Addon._activeModules[def.id] then return end
    Addon._activeModules[def.id] = def
    if def.Start then def:Start() end
end

function Addon:StopModule(def)
    if not Addon._activeModules[def.id] then return end
    Addon._activeModules[def.id] = nil
    if def.Stop then def:Stop() end
end

function Addon:IsModuleActive(id)
    return Addon._activeModules[id] ~= nil
end

-- Called by the engine on engage: start every enabled module for that boss.
function Addon:StartBossModules(raidId, bossId)
    if not Addon.db.settings.enabled then return end
    for _, def in ipairs(Addon:GetBossModules(raidId, bossId)) do
        if Addon:IsModuleEnabled(def.id, def) then Addon:StartModule(def) end
    end
end

function Addon:StopAllModules()
    for _, def in pairs(Addon._activeModules) do
        if def.Stop then def:Stop() end
    end
    wipe(Addon._activeModules)
end
