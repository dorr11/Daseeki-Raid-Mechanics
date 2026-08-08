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
            placeKey   = "naxxramas:loatheb:healers_mod",  -- optional: a placeable anchor
            placeLabel = "Loatheb healers",                -- optional: the anchor's label
            placeFrame = function() return container end,  -- optional: the LIVE widget frame
            placeDef = { name=, icon=, style="icon" },     -- mechDef for the Place preview
            Start = function(self) ... end,                -- begin runtime
            Stop  = function(self) ... end,                -- tear down
            Test  = function(self) ... end,                -- optional preview from options
            BuildConfig = function(self, parent) ... end,  -- optional extra option widgets
        })

    Enabled state + per-module config live in DaseekiRaidMechanicsDB.modules[id].

    ── THE PLACEMENT SEAM (2.0 anchor rework) ──────────────────────────────────
    `placeKey` was declared here from the beginning and never used by a module. It
    is now the seam through which the ANCHOR SYSTEM takes over a special's placement,
    and it is deliberately the ONLY thing the mod files had to learn:

        placeKey    the anchor key (the module's existing "raid:boss:thing_mod" key,
                    so a player's saved position carries over untouched)
        placeLabel  what the labelled drag handle says
        placeFrame  a function returning the module's LIVE container frame

    `placeFrame` is the one genuinely new field, and it is the one that makes the
    fallback rule possible. Without a handle on the frame, the anchor system can
    compute a position but cannot RE-apply it — and "re-apply when the attached frame
    hides" is the entire point of the attach mode. It is a metadata declaration: it
    returns an upvalue the module already had. NOTHING in a module's logic moved.

    A module that declares the seam is DOCKED to the Specials anchor by default and
    can be detached to its own placement from the options surface, exactly like a
    Custom timer row. `Addon:InstallModuleAnchor` is called on Start and on preview;
    it is idempotent, so calling it twice costs one SetPoint.

    A module with no placeable frame (Razuvious's understudy icons live on enemy
    NAMEPLATES by construction) declares no seam and is not in the anchor system.
    That is the honest answer for it, not an omission.
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

-- ── Placement seam (2.0 anchor rework) ─────────────────────────────────────────
-- Hand the module's live frame to the anchor system, docked to the Specials anchor.
-- Called AFTER Start / preview, because that is when the frame exists — a module
-- creates its container lazily and there is nothing to place before then.
--
-- Idempotent: Anchors.Install on an already-installed key just re-resolves and
-- re-points, which is what we want anyway when a module restarts on a new pull.
function Addon:InstallModuleAnchor(def)
    if type(def) ~= "table" or not def.placeKey then return nil end
    local A = Addon.Anchors
    if not A then return nil end
    if type(def.placeFrame) ~= "function" then return nil end
    local f = def.placeFrame(def)
    if type(f) ~= "table" or type(f.SetPoint) ~= "function" then return nil end
    A.EnsureSpecialsAnchor()
    A.Install(def.placeKey, f, {
        label      = def.placeLabel or def.name or def.id,
        dock       = A.ANCHOR_SPECIALS,
        defaultPos = def.placeDefaultPos,
    })
    return def.placeKey
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────────
function Addon:StartModule(def)
    if Addon._activeModules[def.id] then return end
    Addon._activeModules[def.id] = def
    if def.Start then def:Start() end
    Addon:InstallModuleAnchor(def)
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
