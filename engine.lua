--[[
    Daseeki Raid Mechanics — detection engine (all Classic Era 1.14.x safe)

    Sources:
      • COMBAT_LOG_EVENT_UNFILTERED -> CombatLogGetCurrentEventInfo()
          - boss detection via npcID from GUID
          - trigger types: cast / aura / death
      • CHAT_MSG_MONSTER_YELL / _EMOTE  -> trigger type: yell / emote
      • UNIT_HEALTH (target/focus/boss tokens) -> trigger type: health
      • C_Timer schedule on engage -> trigger type: timer

    Matched triggers are dispatched to alerts.lua via Addon:FireAlert(key, mechDef).
    Per-key throttle prevents duplicate fires; fired-flags reset each engage.

    /drm debug prints every boss cast spellID/name and monster yell/emote so the
    vanilla 40-man spell IDs/timers can be verified in-game.
--]]

local _, Addon = ...

local THROTTLE = 1.5   -- min seconds between repeat fires of the same mechanic key

-- Encounters shorter than this don't count toward kill stats — filters out
-- tag-and-reset blips (a stray body-pull that instantly resets, a hunter Feign
-- Death wipe-skip, etc.) that aren't real attempts.
local MIN_STATS_DURATION = 10   -- seconds

Addon.active    = nil  -- { raidId, bossId, boss, startTime }
Addon.curMapID  = nil
local fired     = {}   -- mechKey -> last fire GetTime()
local healthFired = {} -- mechKey -> true (once per pull)
local timers    = {}   -- active C_Timer handles for the current encounter

Addon._combatHooks = {}   -- fn(subevent, sourceGUID, sourceID, destGUID, destID, spellID, spellName)
Addon._mechCount   = {}   -- mechKey -> running cast count (showCount mechanics); wiped on engage

-- ── Debug log buffer (persisted to SavedVariables, see core.lua Init) ───────────
-- `Addon.db.debugLive` is the IN-PROGRESS current raid sitting — lives in
-- SavedVariables (not a transient local), so its DATA is preserved across a /reload
-- and auto-written to disk by the client on the normal logout/reload save points.
-- Reload semantics: PLAYER_LOGOUT fires for BOTH a true logout AND a /reload, and
-- there is no reliable Classic-Era API to distinguish them from inside that event, so
-- on /reload the current sitting is snapshotted (finalized) into `debugSessions` just
-- as it is on a real logout. The data is therefore never lost across a reload — it
-- simply moves from the "live" bucket into a saved (logout-tagged) session, which the
-- log viewer still shows in full. It accumulates across pulls within a sitting;
-- `FinalizeDebugSession` (below) snapshots it into `Addon.db.debugSessions` (tagged
-- with raidId) on logout/reload or on leaving the raid, then clears it for the next
-- sitting. Each line is timestamped relative to Addon._dbgStartTime — started
-- lazily at the first line logged this UI session and reset on each boss Engage,
-- so encounter lines stay pull-relative (the "==== ENGAGED" marker delimits them).
--
-- SavedVariables size is HARD-capped so a long 40-man sitting can't bloat the DB into
-- multi-MB territory (which slows logout/reload): debugLive is trimmed to
-- DEBUG_LOG_MAX_LINES (oldest dropped, marker inserted) and at most DEBUG_MAX_SESSIONS
-- finalized sessions are retained (oldest dropped). DEBUG_LOG_WARN_LINES stays a soft
-- one-time chat heads-up well below the hard cap.
local DEBUG_LOG_WARN_LINES = 5000    -- soft one-time heads-up past this size
local DEBUG_LOG_MAX_LINES  = 25000   -- HARD cap on the live log; oldest lines dropped past this
local DEBUG_MAX_SESSIONS   = 15      -- HARD cap on stored finalized sessions; oldest dropped past this

local function DebugLiveLog()
    return Addon.db and Addon.db.debugLive
end

-- Snapshots the in-progress sitting (Addon.db.debugLive) into Addon.db.debugSessions
-- — tagged with whichever raid we most recently fought or were inside
-- (Addon._debugRaidId/Name, set on Engage and on entering a registered raid zone) —
-- then clears debugLive for the next sitting. No-op if nothing was logged. Called on
-- PLAYER_LOGOUT and on leaving the raid zone we were logging for; multiple sessions
-- can share the same raidId (e.g. raiding the same instance across separate weeks),
-- by design, so they can be consolidated when reviewed later.
local function FinalizeDebugSession(reason)
    local live = Addon.db and Addon.db.debugLive
    if not live or #live == 0 then return end
    Addon.db.debugSessions = Addon.db.debugSessions or {}
    table.insert(Addon.db.debugSessions, {
        raidId   = Addon._debugRaidId or "unknown",
        raidName = Addon._debugRaidName or Addon._debugRaidId or "Unknown",
        savedAt  = date and date("%Y-%m-%d %H:%M") or "",
        reason   = reason or "saved",
        lines    = live,
    })
    Addon.db.debugLive = {}
    -- Hard cap the number of retained sessions (ring-buffer: drop oldest first).
    while #Addon.db.debugSessions > DEBUG_MAX_SESSIONS do
        table.remove(Addon.db.debugSessions, 1)
    end
    if Addon.debug then
        print(Addon:Tag("[DRM]") .. string.format(" Debug session saved (%s, %d lines, %s).",
            Addon._debugRaidName or "unknown raid", #live, reason or "saved"))
    end
end
Addon.FinalizeDebugSession = FinalizeDebugSession

-- Combines every finalized session (tagged raid/timestamp/reason) plus the current
-- in-progress sitting into one reviewable text blob, in chronological order.
function Addon:BuildFullDebugLogText()
    local out = {}
    local sessions = Addon.db and Addon.db.debugSessions or {}
    for i, s in ipairs(sessions) do
        out[#out + 1] = string.format("======== SESSION %d -- %s -- %s -- %s ========",
            i, s.raidName or s.raidId or "?", s.savedAt or "", s.reason or "")
        for _, line in ipairs(s.lines or {}) do out[#out + 1] = line end
        out[#out + 1] = ""
    end
    local live = Addon.db and Addon.db.debugLive
    if live and #live > 0 then
        out[#out + 1] = string.format("======== LIVE (current sitting, not yet finalized) -- %s ========",
            Addon._debugRaidName or Addon._debugRaidId or "?")
        for _, line in ipairs(live) do out[#out + 1] = line end
    end
    return table.concat(out, "\n")
end

function Addon:DebugLogLineCount()
    local n = 0
    for _, s in ipairs((Addon.db and Addon.db.debugSessions) or {}) do n = n + #(s.lines or {}) end
    n = n + #((Addon.db and Addon.db.debugLive) or {})
    return n
end

-- Hard cap on the live log: once it exceeds DEBUG_LOG_MAX_LINES, drop the oldest
-- lines (plus a ~10% margin so we don't re-trim on every subsequent append — keeps
-- this amortized O(1) per line) and leave a marker. Reuses the SAME table reference
-- so the SavedVariables-backed db.debugLive stays valid.
local function TrimDebugLiveLog(log)
    if #log <= DEBUG_LOG_MAX_LINES then return end
    local drop = (#log - DEBUG_LOG_MAX_LINES) + math.floor(DEBUG_LOG_MAX_LINES * 0.1)
    if drop >= #log then drop = #log - 1 end
    local kept = { "......[older debug lines trimmed to cap SavedVariables size]......" }
    for i = drop + 1, #log do kept[#kept + 1] = log[i] end
    wipe(log)
    for i = 1, #kept do log[i] = kept[i] end
end

local function AppendDebugLog(line)
    local log = DebugLiveLog()
    if not log then return end
    -- Lazy t=0 reference: before the first Engage of this UI session nothing has
    -- set the clock, so start it at the first logged line — trash lines then get
    -- real, increasing timestamps instead of all reading [0.0]. Engage still
    -- resets it, keeping encounter lines pull-relative.
    if not Addon._dbgStartTime then Addon._dbgStartTime = GetTime() end
    local t = GetTime() - Addon._dbgStartTime
    log[#log + 1] = string.format("[%7.1f] %s", t, line)
    if #log == DEBUG_LOG_WARN_LINES then
        print(Addon:Tag("[DRM]") .. " Debug log has grown past " .. DEBUG_LOG_WARN_LINES
            .. " lines this sitting — consider reviewing/clearing it soon (large SavedVariables can slow logout).")
    end
    if #log > DEBUG_LOG_MAX_LINES then TrimDebugLiveLog(log) end
end

-- Loud: prints to chat immediately AND buffers — for low-frequency "headline"
-- events (engage/disengage/death/casts) worth seeing live.
local function DLog(fmt, ...)
    if not Addon.debug then return end
    local line = string.format(fmt, ...)
    print(Addon:Tag("[DRM]") .. " " .. line)
    AppendDebugLog(line)
end

-- Quiet: buffers only, no chat spam — for high-frequency events (auras/damage)
-- that would flood a busy raid's chat window but are still worth capturing.
local function BLog(fmt, ...)
    if not Addon.debug then return end
    AppendDebugLog(string.format(fmt, ...))
end

-- Exposed so other files (e.g. the optional dbm_bridge.lua) can write into the same
-- timestamped debug log without duplicating the buffering/formatting logic.
Addon.DLog = DLog
Addon.BLog = BLog

-- Widgets/modules register a combat-log hook here instead of their own frame, so
-- they catch the engaging event too (their handler runs after Engage, same event).
function Addon:RegisterCombatHook(fn)
    if type(fn) == "function" then Addon._combatHooks[#Addon._combatHooks + 1] = fn end
end

-- ── Helpers ──────────────────────────────────────────────────────────────────--
local function NpcIDFromGUID(guid)
    if not guid then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
    return nil
end

local function InstanceMatches(raidDef)
    if not raidDef or not raidDef.mapID then return true end  -- nil mapID = no gating
    return Addon.curMapID == raidDef.mapID
end

local function Throttled(key)
    local now = GetTime()
    if fired[key] and (now - fired[key]) < THROTTLE then return true end
    fired[key] = now
    return false
end

-- ── Engage / disengage ─────────────────────────────────────────────────────────
local function CancelTimers()
    for _, h in ipairs(timers) do
        if h and h.Cancel then h:Cancel() end
    end
    wipe(timers)
end

local function ScheduleTimerMechanics()
    if not Addon.active then return end
    local boss = Addon.active.boss
    for _, mech in ipairs(boss.mechanics or {}) do
        local t = mech.trigger
        if t and t.type == "timer" and t.delay then
            local key = Addon:MechKey(Addon.active.raidId, Addon.active.bossId, mech.id)
            -- Initial fire after `delay`; if `interval`, keep firing on that cadence.
            timers[#timers + 1] = C_Timer.NewTimer(t.delay, function()
                if Addon.active and not Addon:IsDebugOnly() and Addon:GetMechanicConfig(key, mech).masterEnabled then
                    Addon:FireAlert(key, mech)
                end
            end)
            if t.interval then
                timers[#timers + 1] = C_Timer.NewTicker(t.interval, function()
                    if Addon.active and not Addon:IsDebugOnly() and Addon:GetMechanicConfig(key, mech).masterEnabled then
                        Addon:FireAlert(key, mech)
                    end
                end)
            end
        end
    end
end

-- ── Pull timer ────────────────────────────────────────────────────────────────--
-- One-shot standalone countdown bar, fed by /drm pull, the DBM pull mirror
-- (dbm_bridge.lua) and the options "Test" button. Voice count at 5s remaining
-- (media.lua sequencer), "PULL!" special warning at zero. Anchored via the
-- "#pulltimer" pseudo-key through the same GetAnchorPos/SetMechanicPos plumbing
-- the widgets use — drag the bar itself to place it, position persists.
local PULL_ANCHOR       = "#pulltimer"
local DEFAULT_PULL_POS  = { point = "TOP", relPoint = "TOP", x = 0, y = -180 }
local pullFrame   -- lazily created bar frame
local pullState   -- { total, endTime, source, voiceFired } while counting, else nil

local function EnsurePullFrame()
    if pullFrame then return pullFrame end
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(220, 30); f:SetFrameStrata("HIGH")
    if Addon.ApplyDarkBackdrop then Addon:ApplyDarkBackdrop(f) end
    f:SetMovable(true); f:EnableMouse(true)

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar)
    if Addon.StyleBar then Addon:StyleBar(bar) end
    bar:SetStatusBarColor(0.9, 0.35, 0.2)
    f.bar = bar

    f.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.label:SetPoint("CENTER")
    if Addon.TrySetFont then Addon:TrySetFont(f.label, "body") end
    if Addon.StyleFont then Addon:StyleFont(f.label) end

    -- Drag-to-place, same convention as the widget modules (mod_gothik_waves etc).
    f:SetScript("OnMouseDown", function(self, b) if b == "LeftButton" then self:StartMoving() end end)
    f:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        Addon:SetMechanicPos(PULL_ANCHOR, p, rp, x, y)
    end)

    f:SetScript("OnUpdate", function(self)
        if not pullState then self:Hide(); return end
        local rem = pullState.endTime - GetTime()
        if rem <= 0 then
            pullState = nil
            self:Hide()
            Addon:ShowSpecialWarning("#pull", "PULL!", { 1, 0.2, 0.2 }, "raidwarning")
            return
        end
        self.bar:SetValue(rem)
        self.label:SetText(string.format("Pull in %.0fs", rem))
        -- One-shot voice count once <=5s remain (from the start for short timers).
        -- The sequencer speaks floor(rem)..1 aligned so "1" lands ~1s before zero.
        if not pullState.voiceFired and rem <= 5.05 then
            pullState.voiceFired = true
            if not (Addon.db and Addon.db.settings.countdownVoice == false) then
                Addon:PlayVoiceCountdown(math.floor(rem + 0.5))
            end
        end
    end)

    f:Hide()
    pullFrame = f
    return f
end

-- Restart-safe: calling while a countdown runs cleanly restarts it.
function Addon:StartPullTimer(seconds, source)
    seconds = tonumber(seconds) or 10
    if seconds < 3 then seconds = 3 elseif seconds > 60 then seconds = 60 end
    Addon:CancelPullTimer()
    local f = EnsurePullFrame()
    pullState = { total = seconds, endTime = GetTime() + seconds, source = source }
    f.bar:SetMinMaxValues(0, seconds)
    f.bar:SetValue(seconds)
    f.label:SetText(string.format("Pull in %.0fs", seconds))
    local pos = Addon.GetAnchorPos and Addon:GetAnchorPos(PULL_ANCHOR, DEFAULT_PULL_POS) or DEFAULT_PULL_POS
    f:ClearAllPoints()
    f:SetPoint(pos.point or "TOP", UIParent, pos.relPoint or "TOP", pos.x or 0, pos.y or 0)
    f:Show()
    DLog("Pull timer started: %.0fs (%s)", seconds, tostring(source or "manual"))
end

function Addon:CancelPullTimer()
    if pullFrame then pullFrame:Hide() end
    if pullState and Addon.StopVoiceCountdown then Addon:StopVoiceCountdown() end
    pullState = nil
end

-- Cooldown-mode trackers start on the FIRST detected cast (see Dispatch), NOT at
-- engage, so phase-gated abilities (e.g. Kel'Thuzad P2) don't count down / glow
-- before they can actually happen, and the CD is measured from a real cast.

local function Engage(raidId, bossId, boss)
    if Addon.active and Addon.active.bossId == bossId then return end
    Addon.active = { raidId = raidId, bossId = bossId, boss = boss, startTime = GetTime() }
    Addon._bossKilled = false
    -- Which raid the CURRENT debug-log sitting belongs to (for the session snapshot
    -- tag on finalize — see FinalizeDebugSession). Set every Engage, not just once,
    -- so it always reflects the most recently fought raid this sitting.
    Addon._debugRaidId = raidId
    local raidDef = Addon:GetRaid(raidId)
    Addon._debugRaidName = raidDef and raidDef.name or raidId
    wipe(fired)
    wipe(healthFired)
    wipe(Addon._mechCount)
    Addon._dbgLast = {}   -- fresh per-fight cast intervals for debug
    Addon._dbgStartTime = GetTime()   -- t=0 reference for this pull's log timestamps
    CancelTimers()
    Addon:CancelPullTimer()   -- boss engaged — a still-running pull countdown is moot
    -- Debug Only: skip ALL mechanic/module startup — Engage still runs (so debug
    -- logging stays scoped to the right boss + Disengage still works), just nothing
    -- visual/audible fires.
    if not Addon:IsDebugOnly() then
        ScheduleTimerMechanics()
        -- Cooldown mechanics with a known opening time (firstCast) predict from engage
        -- (DBM-style); all other cooldown mechanics start on their first detected cast.
        for _, mech in ipairs(boss.mechanics or {}) do
            if mech.mode == "cooldown" and mech.firstCast then
                local key = Addon:MechKey(raidId, bossId, mech.id)
                if Addon:GetMechanicConfig(key, mech).masterEnabled then
                    Addon:StartCooldown(key, mech, mech.firstCast)
                end
            end
        end
        if Addon.StartBossModules then Addon:StartBossModules(raidId, bossId) end
    end
    DLog("==== ENGAGED: %s (%s) ====", boss.name or bossId, raidId)
end

local function Disengage()
    if not Addon.active then return end
    local dur = GetTime() - Addon.active.startTime
    DLog("==== ENCOUNTER END: %s -- %s -- duration %.1fs ====",
        Addon.active.boss.name or Addon.active.bossId,
        Addon._bossKilled and "KILLED" or "WIPE/LEFT COMBAT", dur)
    -- Persistent kill/wipe stats (db.stats — see core.lua GetBossStats). Only record
    -- encounters that lasted >= MIN_STATS_DURATION so tag-and-reset blips don't
    -- pollute the wipe count. Leaving the zone mid-fight also lands here (via
    -- PLAYER_ENTERING_WORLD -> Disengage) with _bossKilled false, so it counts as a
    -- wipe — by design: the boss wasn't killed, whatever the reason.
    if dur >= MIN_STATS_DURATION then
        local s = Addon:GetBossStats(Addon.active.raidId, Addon.active.bossId)
        s.lastTime = dur
        if Addon._bossKilled then
            s.kills      = (s.kills or 0) + 1
            s.lastResult = "kill"
            if not s.bestTime or dur < s.bestTime then s.bestTime = dur end
            if not s.firstKillAt then s.firstKillAt = date("%Y-%m-%d") end
        else
            s.wipes      = (s.wipes or 0) + 1
            s.lastResult = "wipe"
        end
    end
    Addon.active = nil
    Addon._bossKilled = false
    CancelTimers()
    if Addon.StopAllCooldowns then Addon:StopAllCooldowns() end
    if Addon.StopAllModules then Addon:StopAllModules() end
    wipe(fired)
    wipe(healthFired)
end

-- ── Kill statistics text ───────────────────────────────────────────────────────
-- mm:ss for stats display. alerts.lua has a similar FmtTime but it's file-local
-- there, so a tiny copy lives here; exposed on Addon so options.lua's per-boss
-- stats line can reuse it (engine.lua loads before options.lua — see the .toc).
local function FmtStatsTime(secs)
    secs = math.floor((secs or 0) + 0.5)
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end
Addon.FmtStatsTime = FmtStatsTime

-- One readable multi-line summary of recorded kill stats — all raids, or just
-- `raidId` when given. Per raid: a header, then one line per boss in the raid's
-- own boss order, skipping bosses with nothing recorded. (A later wave wires this
-- to /drm stats + a Daseeki-Core text dialog — this only builds the string.)
function Addon:BuildStatsText(raidId)
    local raids
    if raidId then
        local r = Addon:GetRaid(raidId)
        raids = r and { r } or {}
    else
        raids = Addon:GetRaids()
    end
    local stats = (Addon.db and Addon.db.stats) or {}
    local out = {}
    for _, raid in ipairs(raids) do
        local rs = stats[raid.id]
        if rs then
            local lines = {}
            for _, boss in ipairs(raid.bosses or {}) do
                local s = rs[boss.id]
                if s and ((s.kills or 0) > 0 or (s.wipes or 0) > 0) then
                    local line = string.format("%s \226\128\148 %d kill%s / %d wipe%s",
                        boss.name or boss.id,
                        s.kills or 0, (s.kills or 0) == 1 and "" or "s",
                        s.wipes or 0, (s.wipes or 0) == 1 and "" or "s")
                    if s.bestTime then line = line .. " \226\128\148 best " .. FmtStatsTime(s.bestTime) end
                    if s.lastTime then
                        line = line .. string.format(" \226\128\148 last %s (%s)",
                            FmtStatsTime(s.lastTime), s.lastResult or "?")
                    end
                    if s.firstKillAt then line = line .. " \226\128\148 first kill " .. s.firstKillAt end
                    lines[#lines + 1] = line
                end
            end
            if #lines > 0 then
                out[#out + 1] = "==== " .. (raid.name or raid.id) .. " ===="
                for _, l in ipairs(lines) do out[#out + 1] = l end
                out[#out + 1] = ""
            end
        end
    end
    if out[#out] == "" then out[#out] = nil end   -- no trailing blank line
    if #out == 0 then return "No boss kill statistics recorded yet." end
    return table.concat(out, "\n")
end

-- A matched trigger either fires a one-shot alert (alert mode) or resets the
-- recurring cooldown cycle (cooldown mode — the cast is the cycle's reset event).
-- Single gating point for the masterEnabled (mechanics-list) checkbox: when off,
-- NOTHING for this key fires — Ability Tracker, On Cast Notification, count, all of it.
-- Debug Only overrides masterEnabled too (a blanket kill-switch, see Addon:IsDebugOnly).
local function Dispatch(key, mech)
    if Addon:IsDebugOnly() then return end
    if not Addon:GetMechanicConfig(key, mech).masterEnabled then return end
    if mech.showCount then Addon._mechCount[key] = (Addon._mechCount[key] or 0) + 1 end
    if mech.mode == "cooldown" then
        -- First cast creates + starts the tracker; later casts reset the cycle.
        if Addon._cooldownDisplays[key] then Addon:ResetCooldown(key) else Addon:StartCooldown(key, mech) end
    else
        Addon:FireAlert(key, mech)
    end
    -- On-cast text popup (opt-in, fired the moment the ability happens).
    if Addon.FireOnCast then Addon:FireOnCast(key, mech) end
end

-- Spell match supporting a single spellID, a spellName, OR a spellIDs list.
local function SpellMatch(t, spellID, spellName)
    if t.spellID and spellID == t.spellID then return true end
    if t.spellName and spellName == t.spellName then return true end
    if t.spellIDs then
        for _, id in ipairs(t.spellIDs) do if spellID == id then return true end end
    end
    return false
end

-- ── Trigger matching on combat-log ─────────────────────────────────────────────
local function MatchCombatLog(subevent, sourceID, destID, spellID, spellName, destGUID)
    if not Addon.active then return end
    local boss = Addon.active.boss
    for _, mech in ipairs(boss.mechanics or {}) do
        local t = mech.trigger
        if t then
            local match = false
            if t.type == "cast" and (subevent == "SPELL_CAST_START" or subevent == "SPELL_CAST_SUCCESS") then
                -- onStart: match the begin-cast only (e.g. a long cast shown as a cast bar),
                -- so START + SUCCESS of the same long cast don't both fire.
                local seOK = (not t.onStart) or (subevent == "SPELL_CAST_START")
                local fromBoss = (t.npcID and sourceID == t.npcID) or (not t.npcID)
                if seOK and fromBoss and SpellMatch(t, spellID, spellName) then
                    match = true
                end
            elseif t.type == "aura" and (subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH"
                    or (t.onRemove and subevent == "SPELL_AURA_REMOVED")) then
                if SpellMatch(t, spellID, spellName) then
                    if (not t.onPlayer) or destGUID == UnitGUID("player") then match = true end
                end
            elseif t.type == "death" and subevent == "UNIT_DIED" then
                if t.npcID and destID == t.npcID then match = true end
            end

            if match then
                local key = Addon:MechKey(Addon.active.raidId, Addon.active.bossId, mech.id)
                if not Throttled(key) then Dispatch(key, mech) end
            end
        end
    end
end

-- ── Personal Damage Warning ───────────────────────────────────────────────────--
-- Independent of the mechanic's own trigger.type (cast/aura/etc — used for the
-- Ability Tracker + On Cast Notification): fires separately whenever the SAME
-- spellID actually deals damage to the PLAYER, e.g. you're standing in a ground
-- effect like Rain of Fire / Blizzard. Throttled with its own key suffix so it
-- doesn't interact with the mechanic's main dispatch throttle.
local DAMAGE_SUBEVENTS = { SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true, RANGE_DAMAGE = true }
local function MatchDamage(subevent, spellID, spellName, destGUID)
    if not Addon.active or Addon:IsDebugOnly() then return end
    if not DAMAGE_SUBEVENTS[subevent] then return end
    if destGUID ~= UnitGUID("player") then return end
    local boss = Addon.active.boss
    for _, mech in ipairs(boss.mechanics or {}) do
        local t = mech.trigger
        if t and SpellMatch(t, spellID, spellName) then
            local key = Addon:MechKey(Addon.active.raidId, Addon.active.bossId, mech.id)
            if Addon:GetMechanicConfig(key, mech).masterEnabled
               and not Throttled(key .. "#dmgthrottle") and Addon.FireDamageWarning then
                Addon:FireDamageWarning(key, mech)
            end
        end
    end
end

local function MatchChat(isEmote, text)
    if not Addon.active then return end
    local boss = Addon.active.boss
    for _, mech in ipairs(boss.mechanics or {}) do
        local t = mech.trigger
        if t and ((t.type == "yell" and not isEmote) or (t.type == "emote" and isEmote)) and t.text then
            if text:find(t.text, 1, true) then
                local key = Addon:MechKey(Addon.active.raidId, Addon.active.bossId, mech.id)
                if not Throttled(key) then Dispatch(key, mech) end
            end
        end
    end
end

local function MatchHealth(unit)
    if not Addon.active then return end
    local guid = UnitGUID(unit)
    local id   = NpcIDFromGUID(guid)
    if not id then return end
    local boss = Addon.active.boss
    -- only react to the engaged boss's units
    local isBossUnit = false
    for _, n in ipairs(boss.npcIDs or {}) do if n == id then isBossUnit = true break end end
    if not isBossUnit then return end

    local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
    if not hpMax or hpMax == 0 then return end
    local pct = hp / hpMax * 100

    for _, mech in ipairs(boss.mechanics or {}) do
        local tr = mech.trigger
        if tr and tr.type == "health" and tr.pct and pct <= tr.pct then
            local key = Addon:MechKey(Addon.active.raidId, Addon.active.bossId, mech.id)
            if not healthFired[key] then
                healthFired[key] = true
                Dispatch(key, mech)
            end
        end
    end
end

-- ── Event dispatch ───────────────────────────────────────────────────────────--
function Addon:OnEngineEvent(event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local _, _, _, _, _, _, _, mapID = GetInstanceInfo()
        -- Finalize the debug sitting if we're LEAVING the raid zone it was logged
        -- for (regardless of whether debug capture is currently on — the data may
        -- have been gathered earlier this sitting). No-op if nothing was logged.
        if Addon._debugRaidId and Addon.curMapID then
            local raidDef = Addon:GetRaid(Addon._debugRaidId)
            if raidDef and raidDef.mapID and Addon.curMapID == raidDef.mapID and mapID ~= raidDef.mapID then
                FinalizeDebugSession("left " .. (Addon._debugRaidName or Addon._debugRaidId))
            end
        end
        Addon.curMapID = mapID
        -- Fallback session tag: entering a registered raid's zone tags the sitting
        -- right away, so trash-only segments (no Engage before a /reload or logout
        -- finalizes them) don't save as "unknown". Engage still overwrites this
        -- with the raid actually fought.
        for _, raidDef in ipairs(Addon:GetRaids()) do
            if raidDef.mapID and raidDef.mapID == mapID then
                Addon._debugRaidId   = raidDef.id
                Addon._debugRaidName = raidDef.name or raidDef.id
                break
            end
        end
        Addon:UpdateAutoDebug()   -- fires on login + every zone-in
        Disengage()

    elseif event == "PLAYER_LOGOUT" then
        FinalizeDebugSession("logout")

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellID, spellName = CombatLogGetCurrentEventInfo()
        local sourceID = NpcIDFromGUID(sourceGUID)
        local destID   = NpcIDFromGUID(destGUID)

        -- Debug capture (only while Addon.debug is on — see /drm debug, debugonly,
        -- or General -> Debug Only). Comprehensive: casts (start+success, with the
        -- interval since that spell last fired -- the MIN gap across a fight ~= the
        -- real cooldown), auras, damage taken from NPCs, and any unit death, scoped
        -- to NPC-sourced or player-targeted events so it doesn't capture unrelated
        -- raid chatter. Loud (chat+buffer) for casts/deaths; quiet (buffer only) for
        -- auras/damage since those can be very high-frequency in a busy fight.
        if Addon.debug then
            local isPlayerDest = destGUID == UnitGUID("player")
            if (subevent == "SPELL_CAST_START" or subevent == "SPELL_CAST_SUCCESS") and sourceID then
                Addon._dbgLast = Addon._dbgLast or {}
                local last = Addon._dbgLast[spellID]
                local gap = last and string.format(" (+%.1fs)", GetTime() - last) or ""
                if subevent == "SPELL_CAST_SUCCESS" then Addon._dbgLast[spellID] = GetTime() end
                DLog("%s %s (id %s)%s -- %s (npc %s)",
                    subevent == "SPELL_CAST_START" and "CAST-START" or "CAST",
                    tostring(spellName), tostring(spellID), gap, tostring(sourceName), tostring(sourceID))
            elseif (subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REMOVED"
                    or subevent == "SPELL_AURA_APPLIED_DOSE" or subevent == "SPELL_AURA_REFRESH")
                    and (sourceID or isPlayerDest) then
                BLog("%s %s (id %s) -- %s -> %s", subevent, tostring(spellName), tostring(spellID),
                    tostring(sourceName), isPlayerDest and "YOU" or tostring(destName))
            elseif (subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "RANGE_DAMAGE")
                    and sourceID and isPlayerDest then
                local amount = select(15, CombatLogGetCurrentEventInfo())
                BLog("%s %s (id %s) -- %s -> YOU%s", subevent, tostring(spellName), tostring(spellID),
                    tostring(sourceName), amount and (" for " .. tostring(amount)) or "")
            elseif subevent == "UNIT_DIED" and destID and Addon.active then
                DLog("UNIT_DIED: %s (npc %s)", tostring(destName), tostring(destID))
            end
        end

        -- Engage when a known boss npc is seen in its instance.
        if sourceID or destID then
            local id = sourceID
            local raidId, bossId, boss = nil, nil, nil
            if id then raidId, bossId, boss = Addon:GetBossByNpcID(id) end
            if not boss and destID then raidId, bossId, boss = Addon:GetBossByNpcID(destID) end
            if boss and InstanceMatches(Addon:GetRaid(raidId)) then
                Engage(raidId, bossId, boss)
            end
        end

        -- Note: disengage is handled by PLAYER_REGEN_ENABLED (combat end), which
        -- correctly covers both kills and wipes and multi-NPC fights (Four Horsemen)
        -- without prematurely stopping alerts when one unit of the group dies.
        MatchCombatLog(subevent, sourceID, destID, spellID, spellName, destGUID)
        MatchDamage(subevent, spellID, spellName, destGUID)

        -- Track a KILL (vs wipe/left-combat) for the Disengage debug summary —
        -- unconditional, independent of the boss-death sound setting below.
        if subevent == "UNIT_DIED" and destID and Addon.active then
            local npcs = Addon.active.boss.npcIDs
            if npcs and npcs[1] == destID then Addon._bossKilled = true end
        end

        -- Boss-death sound (configurable in General). Only the PRIMARY boss npc
        -- (npcIDs[1]) so add deaths (e.g. Thaddius's Stalagg/Feugen) don't trigger it.
        -- Suppressed in Debug Only mode along with everything else.
        if subevent == "UNIT_DIED" and destID and Addon.active and Addon.db
           and Addon.db.settings and Addon.db.settings.deathSound and not Addon:IsDebugOnly() then
            local npcs = Addon.active.boss.npcIDs
            if npcs and npcs[1] == destID and Addon.PlaySoundByKey then
                Addon:PlaySoundByKey(Addon.db.settings.deathSoundKey)
            end
        end

        -- Widget/module combat hooks run AFTER Engage in the same event, so a
        -- handler registered during Engage still catches the engaging cast. Modules
        -- never start in Debug Only mode, so skip calling their hooks entirely.
        if not Addon:IsDebugOnly() then
            for _, fn in ipairs(Addon._combatHooks) do
                fn(subevent, sourceGUID, sourceID, destGUID, destID, spellID, spellName)
            end
        end

    elseif event == "CHAT_MSG_MONSTER_YELL" then
        local text = ...
        DLog("YELL: %s", tostring(text))
        MatchChat(false, text or "")

    elseif event == "CHAT_MSG_MONSTER_EMOTE" then
        local text = ...
        DLog("EMOTE: %s", tostring(text))
        MatchChat(true, text or "")

    elseif event == "UNIT_HEALTH" then
        local unit = ...
        MatchHealth(unit)

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Left combat: if the boss is dead or we wiped, drop the encounter.
        if Addon.active then Disengage() end
    end
end

-- Auto-enable debug logging in 20/40-man RAIDS ONLY (never dungeons/world), when
-- either the Auto-log setting or Debug Only mode is on. Debug Only still silences
-- all mechanic output everywhere (its kill-switch checks are independent of this) —
-- this only controls whether combat events get LOGGED, and that's raid-scoped.
-- Called on login + every zone change + whenever either setting is toggled. Only
-- auto-disables what it auto-enabled (a manual /drm debug toggle is left alone).
function Addon:UpdateAutoDebug()
    local s = Addon.db and Addon.db.settings
    if not s then return end
    local _, instanceType, _, _, maxPlayers = GetInstanceInfo()
    local inRaid = instanceType == "raid" and (maxPlayers == 20 or maxPlayers == 40)
    local want = inRaid and (s.autoDebug or s.debugOnly)
    if want then
        if not Addon.debug then
            Addon.debug = true; Addon._autoDebug = true
            print(Addon:Tag("[DRM]") .. " Auto-debug " .. Addon:Wrap("ok", "ON") .. " — logging casts (with intervals), yells & emotes.")
        end
    elseif Addon._autoDebug then
        Addon.debug = false; Addon._autoDebug = false
        print(Addon:Tag("[DRM]") .. " Auto-debug " .. Addon:Wrap("danger", "OFF") .. ".")
    end
    Addon:UpdateDebugOnlyIndicator()
end

-- Lightweight on-screen cue that Debug Only is ON (every mechanic alert silenced) so a
-- user is reminded that the addon is muted. The banner flashes briefly: it appears at
-- full alpha, holds for ~4 seconds, then fades out over ~1 second and hides itself.
-- Created lazily and only shown while Debug Only is active. Refreshed on login, on every
-- zone change, and whenever the Debug Only toggle flips (both go through UpdateAutoDebug);
-- each refresh cleanly restarts the show/hold/fade cycle so timers/fades never stack.
-- Pairs with the login chat reminder in core.lua OnLogin.
function Addon:UpdateDebugOnlyIndicator()
    local on = Addon:IsDebugOnly()
    if not on and not Addon._dbgIndicator then return end
    if not Addon._dbgIndicator then
        local fr = CreateFrame("Frame", nil, UIParent)
        fr:SetSize(300, 22)
        fr:SetPoint("TOP", UIParent, "TOP", 0, -140)
        fr:SetFrameStrata("HIGH")
        local fs = fr:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        if Addon.ReFaceKeepingSize then Addon:ReFaceKeepingSize(fs) end  -- keep the Large size, take the suite face
        fs:SetAllPoints()
        fs:SetText("|cffff8800Daseeki Raid Mechanics: DEBUG ONLY — alerts silenced|r")
        Addon._dbgIndicator = fr
        -- Hold-then-fade animation: full alpha for 4s, then fade to 0 over 1s.
        local ag = fr:CreateAnimationGroup()
        local anim = ag:CreateAnimation("Alpha")
        anim:SetFromAlpha(1)
        anim:SetToAlpha(0)
        anim:SetStartDelay(4)
        anim:SetDuration(1)
        ag:SetScript("OnFinished", function() fr:Hide() end)
        Addon._dbgIndicatorAnim = ag
    end
    if on then
        -- Cleanly restart the show/hold/fade cycle: stop any in-flight animation,
        -- reset to full alpha, then play again so timers/fades never stack.
        Addon._dbgIndicatorAnim:Stop()
        Addon._dbgIndicator:SetAlpha(1)
        Addon._dbgIndicator:Show()
        Addon._dbgIndicatorAnim:Play()
    else
        Addon._dbgIndicatorAnim:Stop()
        Addon._dbgIndicator:Hide()
    end
end

function Addon:InitEngine()
    if Addon.engineFrame then return end
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")
    ef:RegisterEvent("PLAYER_LOGOUT")
    ef:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    ef:RegisterEvent("CHAT_MSG_MONSTER_YELL")
    ef:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:RegisterEvent("UNIT_HEALTH")  -- filtered to the engaged boss's units in the handler
    ef:SetScript("OnEvent", function(_, event, ...) Addon:OnEngineEvent(event, ...) end)
    Addon.engineFrame = ef

    -- prime the current instance map id
    local _, _, _, _, _, _, _, mapID = GetInstanceInfo()
    Addon.curMapID = mapID
end
