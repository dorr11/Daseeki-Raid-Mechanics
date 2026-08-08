--[[
    Daseeki Raid Mechanics 2.0 — the composition root (engine core)

    ONE JOB. `Addon:InitEngine()`, called once from core.lua's OnLogin, is the single
    place where the finished subsystems are wired to each other and to the client:

      * boot the lifecycle's arming timeline (§1.2);
      * stand up the services and presentation in dependency order;
      * project the encounter registry into the options tree;
      * create the ONE engine event frame and register the lifecycle's event set,
        including the Era unit-event token expansion (§10.1/§8.6) — the single most
        silently-fatal Era gate, because registering a bare UNIT_* event with the
        retail token set registers NOTHING useful on Classic;
      * attach the addon channel and the receive-only DBM bridge.

    W5 — THE SCAFFOLDING IS GONE. Through waves 1-4 this file was also the place
    homeless things lived: the wave-1 demolition removed engine.lua and encounters.lua,
    and every surviving caller of theirs was answered here by a documented stand-in,
    each labelled with the wave that would replace it. The design doc's rule was that
    the file "should shrink every wave and be gone by W5", and this is that wave.
    Nothing below is transitional, and nothing below is labelled as such:

      * the pull/break timers left in W3 — core_sync.lua owns them (ENGINE SPEC
        §11.4/§9.2), under the same public names;
      * the raid/boss/npc READERS and the 1.x `RegisterRaid` refusal left in W5 —
        they now sit in core_api.lua §E, next to `PublishOptionsTree`, which is the
        thing that fills them;
      * the combat-log debug capture, auto-debug policy, Debug-Only indicator and
        kill-statistics text left in W5 — core_diag.lua, an honest home for the
        owner's measuring instruments rather than a majority tenancy in a file
        named "boot".

    What remains is boot. The GATE RETIRE assertions hold it to that.
--]]

local _, Addon = ...

local Life = Addon.Lifecycle

Addon._mechCount = Addon._mechCount or {}    -- per-key mechanic counters (alerts.lua)
Addon.active     = nil                       -- the widget contract (see core_api.lua)

-- ══════════════════════════════════════════════════════════════════════════════
--  BOOT
-- ══════════════════════════════════════════════════════════════════════════════
function Addon:InitEngine()
    if Addon.engineFrame then return Addon.engineFrame end

    Life:Boot()

    -- SERVICES + PRESENTATION. Each one registers against the dispatch seam and owns
    -- nothing the engine already decided. Era goes FIRST because it installs the
    -- role/class resolvers core_api's ship-off defaults call, and a row evaluated
    -- before they exist would default differently.
    if Addon.Era      then Addon.Era.Init()      end   -- svc_era.lua
    if Addon.Scan     then Addon.Scan.Init()     end   -- svc_scan.lua
    if Addon.Bars     then Addon.Bars.Init()     end   -- ui_bars.lua
    if Addon.Warnings then Addon.Warnings.Init() end   -- ui_warnings.lua
    if Addon.Callbacks and Addon.Callbacks.Init then Addon.Callbacks.Init() end  -- public_api.lua
    -- The testing suite goes LAST of the presentation group: it drives the two surfaces
    -- above through their real paths and must not be able to register a callback ahead
    -- of the surface it is testing.
    if Addon.Testing then Addon.Testing.Init() end     -- ui_testing.lua

    -- Project the encounter registry into the raid/boss/mechanic tree options.lua
    -- consumes. Runs AFTER svc_era installed the role/class resolvers, because a
    -- projected row publishes its RESOLVED default, and BEFORE core.lua's OnLogin
    -- calls Addon:RegisterOptions().
    if Addon.API and Addon.API.PublishOptionsTree then
        Addon.API.PublishOptionsTree()
        -- AUDIT RM-1: and keep it resolved. A promotion to Main Tank or a respec
        -- changes the answer those defaults froze; ROLE_CHANGED re-projects.
        if Addon.API.WatchRoleChanges then Addon.API.WatchRoleChanges() end
    end

    if type(_G.CreateFrame) ~= "function" then
        Addon.engineFrame = false            -- headless: the harness drives Life directly
        return false
    end

    local ef = _G.CreateFrame("Frame")
    for _, e in ipairs(Life.EVENTS) do
        if e == "UNIT_HEALTH_FREQUENT" then
            -- ENGINE SPEC §10.1 + §8.6: on Classic a bare UNIT_* registration expands
            -- to the WRONG token set, and there is no `focus` token at all. Register
            -- the Era tokens explicitly: mouseover, target, player, targettarget.
            if ef.RegisterUnitEvent then
                ef:RegisterUnitEvent(e, "mouseover", "target")
                -- a second frame carries the remaining tokens (RegisterUnitEvent
                -- accepts at most two per registration)
                local ef2 = _G.CreateFrame("Frame")
                ef2:RegisterUnitEvent(e, "player", "targettarget")
                ef2:SetScript("OnEvent", function(_, event, ...) Life:OnEvent(event, ...) end)
                Addon.engineFrame2 = ef2
            else
                ef:RegisterEvent(e)
            end
        else
            local okr = pcall(ef.RegisterEvent, ef, e)
            if not okr and Addon.Telemetry then
                Addon.Telemetry.Write("api.validate", { reason = "event not available on this client", key = e })
            end
        end
    end
    ef:SetScript("OnEvent", function(_, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" and _G.CombatLogGetCurrentEventInfo then
            local _, sub, _, sGUID, sName, sFlags, sRaid, dGUID, dName, dFlags, dRaid,
                  a1, a2, a3, a4 = _G.CombatLogGetCurrentEventInfo()
            return Life:Deliver(Life:NormalizeCLEU(sub, sGUID, sName, sFlags, sRaid,
                                                   dGUID, dName, dFlags, dRaid, a1, a2, a3, a4))
        end
        return Life:OnEvent(event, ...)
    end)
    Addon.engineFrame = ef

    -- The owner's engage/end debug lines (core_diag.lua owns the log itself).
    Addon:RegisterEngineCallback("ENGINE_ENGAGE", function(_, encId, rt, delay, trigger)
        Addon._dbgStartTime = Addon.Sched:Now()
        Addon.DLog("ENGAGE %s (delay %.2f, via %s)", tostring(encId), delay or 0, tostring(trigger))
    end)
    Addon:RegisterEngineCallback("ENGINE_END", function(_, encId, rt, wiped, duration)
        Addon.DLog("END %s after %.1fs (%s)", tostring(encId), duration or 0, wiped and "WIPE" or "KILL")
    end)

    -- The addon channel attaches here, after the engine frame exists, so the sync
    -- layer is booted by the same one call core.lua already makes and there is no
    -- second login handler racing this one. Sync is loaded AFTER this file, so the
    -- reference is resolved at CALL time, never at load time.
    if Addon.Sync then Addon.Sync:Boot() end
    if Addon.DBMBridge then Addon.DBMBridge:Boot() end

    Addon:UpdateAutoDebug()
    return ef
end

return true
