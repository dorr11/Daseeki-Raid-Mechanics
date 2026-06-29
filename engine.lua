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

Addon.active    = nil  -- { raidId, bossId, boss, startTime }
Addon.curMapID  = nil
local fired     = {}   -- mechKey -> last fire GetTime()
local healthFired = {} -- mechKey -> true (once per pull)
local timers    = {}   -- active C_Timer handles for the current encounter

Addon._combatHooks = {}   -- fn(subevent, sourceGUID, sourceID, destGUID, destID, spellID, spellName)
Addon._mechCount   = {}   -- mechKey -> running cast count (showCount mechanics); wiped on engage

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
                if Addon.active and Addon:GetMechanicConfig(key, mech).masterEnabled then
                    Addon:FireAlert(key, mech)
                end
            end)
            if t.interval then
                timers[#timers + 1] = C_Timer.NewTicker(t.interval, function()
                    if Addon.active and Addon:GetMechanicConfig(key, mech).masterEnabled then
                        Addon:FireAlert(key, mech)
                    end
                end)
            end
        end
    end
end

-- Cooldown-mode trackers start on the FIRST detected cast (see Dispatch), NOT at
-- engage, so phase-gated abilities (e.g. Kel'Thuzad P2) don't count down / glow
-- before they can actually happen, and the CD is measured from a real cast.

local function Engage(raidId, bossId, boss)
    if Addon.active and Addon.active.bossId == bossId then return end
    Addon.active = { raidId = raidId, bossId = bossId, boss = boss, startTime = GetTime() }
    wipe(fired)
    wipe(healthFired)
    wipe(Addon._mechCount)
    Addon._dbgLast = {}   -- fresh per-fight cast intervals for debug
    CancelTimers()
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
    if Addon.debug then
        print("|cff66ccff[DRM]|r engaged: |cffffffff" .. (boss.name or bossId) .. "|r")
    end
end

local function Disengage()
    if not Addon.active then return end
    if Addon.debug then print("|cff66ccff[DRM]|r encounter ended.") end
    Addon.active = nil
    CancelTimers()
    if Addon.StopAllCooldowns then Addon:StopAllCooldowns() end
    if Addon.StopAllModules then Addon:StopAllModules() end
    wipe(fired)
    wipe(healthFired)
end

-- A matched trigger either fires a one-shot alert (alert mode) or resets the
-- recurring cooldown cycle (cooldown mode — the cast is the cycle's reset event).
-- Single gating point for the masterEnabled (mechanics-list) checkbox: when off,
-- NOTHING for this key fires — Ability Tracker, On Cast Notification, count, all of it.
local function Dispatch(key, mech)
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
    if not Addon.active then return end
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
        Addon.curMapID = mapID
        Addon:UpdateAutoDebug()   -- fires on login + every zone-in
        Disengage()

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellID, spellName = CombatLogGetCurrentEventInfo()
        local sourceID = NpcIDFromGUID(sourceGUID)
        local destID   = NpcIDFromGUID(destGUID)

        -- Debug capture: log creature SPELL_CAST_SUCCESS with the time since that
        -- spell last fired (the MIN gap across a fight ~= the real cooldown).
        if Addon.debug and subevent == "SPELL_CAST_SUCCESS" and sourceID and Addon.curMapID then
            Addon._dbgLast = Addon._dbgLast or {}
            local last = Addon._dbgLast[spellID]
            local gap = last and string.format(" |cff88ff88+%.1fs|r", GetTime() - last) or ""
            Addon._dbgLast[spellID] = GetTime()
            print(string.format("|cff66ccff[DRM]|r |cffffff00%s|r (id %s)%s — %s (npc %s)",
                tostring(spellName), tostring(spellID), gap, tostring(sourceName), tostring(sourceID)))
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

        -- Boss-death sound (configurable in General). Only the PRIMARY boss npc
        -- (npcIDs[1]) so add deaths (e.g. Thaddius's Stalagg/Feugen) don't trigger it.
        if subevent == "UNIT_DIED" and destID and Addon.active and Addon.db
           and Addon.db.settings and Addon.db.settings.deathSound then
            local npcs = Addon.active.boss.npcIDs
            if npcs and npcs[1] == destID and Addon.PlaySoundByKey then
                Addon:PlaySoundByKey(Addon.db.settings.deathSoundKey)
            end
        end

        -- Widget/module combat hooks run AFTER Engage in the same event, so a
        -- handler registered during Engage still catches the engaging cast.
        for _, fn in ipairs(Addon._combatHooks) do
            fn(subevent, sourceGUID, sourceID, destGUID, destID, spellID, spellName)
        end

    elseif event == "CHAT_MSG_MONSTER_YELL" then
        local text = ...
        if Addon.debug then print("|cff66ccff[DRM yell]|r " .. tostring(text)) end
        MatchChat(false, text or "")

    elseif event == "CHAT_MSG_MONSTER_EMOTE" then
        local text = ...
        if Addon.debug then print("|cff66ccff[DRM emote]|r " .. tostring(text)) end
        MatchChat(true, text or "")

    elseif event == "UNIT_HEALTH" then
        local unit = ...
        MatchHealth(unit)

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Left combat: if the boss is dead or we wiped, drop the encounter.
        if Addon.active then Disengage() end
    end
end

-- Auto-enable debug logging in 20/40-man raids (toggled by the options setting).
-- Called on login + every zone change. Only auto-disables what it auto-enabled.
function Addon:UpdateAutoDebug()
    local s = Addon.db and Addon.db.settings
    if not s then return end
    local _, instanceType, _, _, maxPlayers = GetInstanceInfo()
    local inRaid = s.autoDebug and instanceType == "raid" and (maxPlayers == 20 or maxPlayers == 40)
    if inRaid then
        if not Addon.debug then
            Addon.debug = true; Addon._autoDebug = true
            print("|cff66ccff[DRM]|r Auto-debug |cff00ff00ON|r — logging casts (with intervals), yells & emotes for this raid.")
        end
    elseif Addon._autoDebug then
        Addon.debug = false; Addon._autoDebug = false
        print("|cff66ccff[DRM]|r Auto-debug |cffff0000OFF|r (left raid).")
    end
end

function Addon:InitEngine()
    if Addon.engineFrame then return end
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")
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
