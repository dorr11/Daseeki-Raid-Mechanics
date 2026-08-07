--[[
    Daseeki Raid Mechanics 2.0 — engine boot + transitional surfaces
    (engine core, wave 1)

    THREE JOBS, all of them seams rather than logic:

    1. BOOT. `Addon:InitEngine()` (called from core.lua's OnLogin) creates the one
       engine event frame, registers the lifecycle's event set — including the Era
       unit-event token expansion from ENGINE SPEC §10.1/§8.6, which is the single
       most silently-fatal Era gate: registering a bare UNIT_* event with the retail
       token set registers NOTHING useful on Classic — and boots the lifecycle's
       arming timeline (§1.2).

    2. RETIREMENT SHIMS. The wave-1 demolition removed engine.lua and encounters.lua
       (see the design doc verdicts table). Files that SURVIVE this wave —
       alerts.lua, options.lua, slash.lua, dbm_bridge.lua — still call into those
       two. Every such call site is answered here by a documented, harmless stand-in
       so the addon LOADS AND RUNS on this branch. Each carries the wave that
       replaces it. This file is scaffolding: it should shrink every wave and be
       gone by W5.

    3. PORTED INFRASTRUCTURE. The combat-log debug capture (`/drm debuglog`) and the
       auto-debug/Debug-Only surfaces were engine.lua tenants but are not part of the
       scrapped trigger engine — they are diagnostics Drew actively uses to measure
       real timings. They move here intact, re-seated on the new combat-log path.
--]]

local _, Addon = ...

local Life  = Addon.Lifecycle
local Sched = Addon.Sched

Addon._mechCount = Addon._mechCount or {}    -- legacy alerts.lua contract
Addon.active     = nil                       -- legacy widget contract (see core_api.lua)

-- ══════════════════════════════════════════════════════════════════════════════
--  DEBUG LOG (ported from the retired engine.lua — SavedVariables-backed)
-- ══════════════════════════════════════════════════════════════════════════════
local DEBUG_LOG_MAX_LINES  = 20000
local DEBUG_LOG_WARN_LINES = 12000
local DEBUG_MAX_SESSIONS   = 15

local function DebugLiveLog() return Addon.db and Addon.db.debugLive end

local function FinalizeDebugSession(reason)
    local live = Addon.db and Addon.db.debugLive
    if not live or #live == 0 then return end
    Addon.db.debugSessions = Addon.db.debugSessions or {}
    table.insert(Addon.db.debugSessions, {
        raidId   = Addon._debugRaidId or "unknown",
        raidName = Addon._debugRaidName or Addon._debugRaidId or "Unknown",
        savedAt  = (type(date) == "function" and date("%Y-%m-%d %H:%M")) or "",
        reason   = reason or "saved",
        lines    = live,
    })
    Addon.db.debugLive = {}
    while #Addon.db.debugSessions > DEBUG_MAX_SESSIONS do
        table.remove(Addon.db.debugSessions, 1)
    end
end
Addon.FinalizeDebugSession = FinalizeDebugSession

function Addon:BuildFullDebugLogText()
    local out = {}
    for i, s in ipairs((Addon.db and Addon.db.debugSessions) or {}) do
        out[#out + 1] = string.format("======== SESSION %d -- %s -- %s -- %s ========",
            i, s.raidName or s.raidId or "?", s.savedAt or "", s.reason or "")
        for _, line in ipairs(s.lines or {}) do out[#out + 1] = line end
        out[#out + 1] = ""
    end
    local live = Addon.db and Addon.db.debugLive
    if live and #live > 0 then
        out[#out + 1] = string.format(
            "======== LIVE (current sitting, not yet finalized) -- %s ========",
            Addon._debugRaidName or Addon._debugRaidId or "?")
        for _, line in ipairs(live) do out[#out + 1] = line end
    end
    return table.concat(out, "\n")
end

function Addon:DebugLogLineCount()
    local n = 0
    for _, s in ipairs((Addon.db and Addon.db.debugSessions) or {}) do n = n + #(s.lines or {}) end
    return n + #((Addon.db and Addon.db.debugLive) or {})
end

local function TrimDebugLiveLog(log)
    if #log <= DEBUG_LOG_MAX_LINES then return end
    local drop = (#log - DEBUG_LOG_MAX_LINES) + math.floor(DEBUG_LOG_MAX_LINES * 0.1)
    if drop >= #log then drop = #log - 1 end
    local kept = { "......[older debug lines trimmed to cap SavedVariables size]......" }
    for i = drop + 1, #log do kept[#kept + 1] = log[i] end
    for i = #log, 1, -1 do log[i] = nil end
    for i = 1, #kept do log[i] = kept[i] end
end

local function AppendDebugLog(line)
    local log = DebugLiveLog()
    if not log then return end
    if not Addon._dbgStartTime then Addon._dbgStartTime = Sched:Now() end
    log[#log + 1] = string.format("[%7.1f] %s", Sched:Now() - Addon._dbgStartTime, line)
    if #log == DEBUG_LOG_WARN_LINES and type(print) == "function" then
        print(Addon:Tag("[DRM]") .. " Debug log has grown past " .. DEBUG_LOG_WARN_LINES
            .. " lines this sitting — consider reviewing/clearing it soon.")
    end
    if #log > DEBUG_LOG_MAX_LINES then TrimDebugLiveLog(log) end
end

local function DLog(fmt, ...)
    if not Addon.debug then return end
    local line = string.format(fmt, ...)
    if type(print) == "function" then print(Addon:Tag("[DRM]") .. " " .. line) end
    AppendDebugLog(line)
end

local function BLog(fmt, ...)
    if not Addon.debug then return end
    AppendDebugLog(string.format(fmt, ...))
end

Addon.DLog, Addon.BLog = DLog, BLog

-- ══════════════════════════════════════════════════════════════════════════════
--  AUTO-DEBUG + DEBUG-ONLY INDICATOR (ported)
-- ══════════════════════════════════════════════════════════════════════════════
function Addon:UpdateAutoDebug()
    local s = Addon.db and Addon.db.settings
    if not s then return end
    local _, instanceType, _, _, maxPlayers = Life.env.GetInstanceInfo()
    local inRaid = instanceType == "raid" and (maxPlayers == 20 or maxPlayers == 40)
    local want = inRaid and (s.autoDebug or s.debugOnly)
    if want then
        if not Addon.debug then
            Addon.debug, Addon._autoDebug = true, true
            if type(print) == "function" then
                print(Addon:Tag("[DRM]") .. " Auto-debug " .. Addon:Wrap("ok", "ON") .. ".")
            end
        end
    elseif Addon._autoDebug then
        Addon.debug, Addon._autoDebug = false, false
        if type(print) == "function" then
            print(Addon:Tag("[DRM]") .. " Auto-debug " .. Addon:Wrap("danger", "OFF") .. ".")
        end
    end
    Addon:UpdateDebugOnlyIndicator()
end

function Addon:UpdateDebugOnlyIndicator()
    local on = Addon:IsDebugOnly()
    if not on and not Addon._dbgIndicator then return end
    if type(_G.CreateFrame) ~= "function" then return end       -- headless: nothing to draw
    if not Addon._dbgIndicator then
        local fr = _G.CreateFrame("Frame", nil, _G.UIParent)
        fr:SetSize(300, 22)
        fr:SetPoint("TOP", _G.UIParent, "TOP", 0, -140)
        fr:SetFrameStrata("HIGH")
        local fs = fr:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        if Addon.ReFaceKeepingSize then Addon:ReFaceKeepingSize(fs) end
        fs:SetAllPoints()
        fs:SetText("|cffff8800Daseeki Raid Mechanics: DEBUG ONLY — alerts silenced|r")
        Addon._dbgIndicator = fr
        local ag = fr:CreateAnimationGroup()
        local anim = ag:CreateAnimation("Alpha")
        anim:SetFromAlpha(1); anim:SetToAlpha(0)
        anim:SetStartDelay(4); anim:SetDuration(1)
        ag:SetScript("OnFinished", function() fr:Hide() end)
        Addon._dbgIndicatorAnim = ag
    end
    if on then
        Addon._dbgIndicatorAnim:Stop()
        Addon._dbgIndicator:SetAlpha(1)
        Addon._dbgIndicator:Show()
        Addon._dbgIndicatorAnim:Play()
    else
        Addon._dbgIndicatorAnim:Stop()
        Addon._dbgIndicator:Hide()
    end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  PULL TIMER — RETIRED FROM THIS FILE IN W3 (do not re-add)
-- ══════════════════════════════════════════════════════════════════════════════
-- W1 parked a minimal `Addon:StartPullTimer` here so slash.lua and options.lua kept
-- working across the demolition. W3 owns pull timers for real: core_sync.lua carries
-- the full ENGINE SPEC §11.4 rule set (rank gate, PvP + in-encounter refusal, the
-- 0-to-3 s refusal instead of a silent clamp, 0 = cancel, target naming, the engage
-- cancel from §2.3) AND the wire that broadcasts one. The PUBLIC NAMES are unchanged
-- — `Addon:StartPullTimer(seconds, source)` / `Addon:CancelPullTimer()` — so nothing
-- outside this file moved. A re-added copy here would shadow-or-be-shadowed by the
-- real one depending on load order; the harness (GATE SYNC) asserts core_boot.lua no
-- longer defines either name. W2's ui_bars.lua RENDERS the pull bar (category
-- "pull", always-large class) — visibility landed in W2, ownership stays in W3.

-- ══════════════════════════════════════════════════════════════════════════════
--  STATS TEXT (ported; reads the same db.stats shape)
-- ══════════════════════════════════════════════════════════════════════════════
local function FmtStatsTime(secs)
    secs = math.floor((secs or 0) + 0.5)
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end
Addon.FmtStatsTime = FmtStatsTime

function Addon:BuildStatsText(raidId)
    local stats = (Addon.db and Addon.db.stats) or {}
    local out = {}
    for rid, bosses in pairs(stats) do
        if not raidId or rid == raidId then
            out[#out + 1] = "== " .. tostring(rid) .. " =="
            for bid, s in pairs(bosses) do
                if (s.kills or 0) > 0 or (s.wipes or 0) > 0 then
                    out[#out + 1] = string.format("  %-24s %d kill(s), %d wipe(s)%s",
                        tostring(bid), s.kills or 0, s.wipes or 0,
                        s.bestTime and ("  best " .. FmtStatsTime(s.bestTime)) or "")
                end
            end
        end
    end
    if #out == 0 then return "No recorded kills yet." end
    return table.concat(out, "\n")
end

-- ══════════════════════════════════════════════════════════════════════════════
--  RETIREMENT SHIMS for the removed encounter registry (encounters.lua)
-- ══════════════════════════════════════════════════════════════════════════════
-- W4 replaces every one of these with the real encounter registry read through
-- `Addon:GetEncounters()`. Until then options.lua and alerts.lua get empty,
-- well-shaped answers instead of nil-index errors.
Addon.raids     = Addon.raids     or {}
Addon.raidsById = Addon.raidsById or {}
Addon.npcIndex  = Addon.npcIndex  or {}

function Addon:GetRaids()  return Addon.raids end
function Addon:GetRaid(id) return Addon.raidsById[id] end
function Addon:GetBoss(raidId, bossId)
    local r = Addon.raidsById[raidId]
    if not r then return nil end
    for _, b in ipairs(r.bosses or {}) do if b.id == bossId then return b end end
    return nil
end
function Addon:GetBossByNpcID(npcID) return Addon.npcIndex[npcID] end

-- HARD STOP, not a silent no-op. The 1.x data files (data_naxxramas / data_bwl /
-- data_aq40) are PARKED ON DISK but OUT OF THE .toc: W4 regenerates them in the new
-- declarative grammar. If one of them is ever re-added to the load list by accident,
-- the old flat mechanic model would half-populate the options tree beside the new
-- encounter registry and be extremely confusing. So this refuses, loudly and
-- traceably, instead of accepting.
function Addon:RegisterRaid(def)
    if Addon.Telemetry then
        Addon.Telemetry.Write("api.validate", {
            reason = "legacy RegisterRaid refused (1.x data file is back in the load list)",
            enc = def and def.id,
        })
    end
    return nil, "the 1.x encounter-data format was retired in 2.0; W4 owns the new grammar"
end

-- ══════════════════════════════════════════════════════════════════════════════
--  BOOT
-- ══════════════════════════════════════════════════════════════════════════════
function Addon:InitEngine()
    if Addon.engineFrame then return Addon.engineFrame end

    Life:Boot()

    -- WAVE 2 SERVICES + PRESENTATION. Each one registers against the dispatch seam
    -- and owns nothing the engine already decided. Era goes first because it
    -- installs the role/class resolvers core_api's ship-off defaults call, and a
    -- row evaluated before they exist would default differently.
    if Addon.Era      then Addon.Era.Init()      end   -- svc_era.lua
    if Addon.Scan     then Addon.Scan.Init()     end   -- svc_scan.lua
    if Addon.Bars     then Addon.Bars.Init()     end   -- ui_bars.lua
    if Addon.Warnings then Addon.Warnings.Init() end   -- ui_warnings.lua
    if Addon.Callbacks and Addon.Callbacks.Init then Addon.Callbacks.Init() end  -- public_api.lua

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

    -- Diagnostics that used to live on engine.lua's own event handler.
    Addon:RegisterEngineCallback("ENGINE_ENGAGE", function(_, encId, rt, delay, trigger)
        Addon._dbgStartTime = Sched:Now()
        DLog("ENGAGE %s (delay %.2f, via %s)", tostring(encId), delay or 0, tostring(trigger))
    end)
    Addon:RegisterEngineCallback("ENGINE_END", function(_, encId, rt, wiped, duration)
        DLog("END %s after %.1fs (%s)", tostring(encId), duration or 0, wiped and "WIPE" or "KILL")
    end)

    -- W3: the addon channel attaches here, after the engine frame exists, so the
    -- sync layer is booted by the same one call core.lua already makes and there is
    -- no second login handler racing this one. Sync is loaded AFTER this file, so
    -- the reference is resolved at CALL time, never at load time.
    if Addon.Sync then Addon.Sync:Boot() end
    if Addon.DBMBridge then Addon.DBMBridge:Boot() end

    Addon:UpdateAutoDebug()
    return ef
end

return true
