--[[
    Daseeki Raid Mechanics — optional DBM debug bridge

    SOFT integration only. If DBM-Core is loaded, this registers for DBM's public
    DBM_TimerBegin / DBM_TimerStop / DBM_Announce / DBM_SetStage / DBM_Pull
    callbacks via DBM:RegisterCallback — a stable, first-party pub/sub API DBM's OWN
    modules (e.g. DBM-Nameplate.lua) use the exact same way, not an internals hack.

    Callback names + argument order were VERIFIED against the DBM-Core installed on
    this machine (paths relative to DBM-Core\):
      DBM_TimerBegin : modules\objects\Timer.lua:548
                       (event, id, msg, timer, icon, barType, spellId, colorId, modId,
                        keep, fade, name, guid, timerCount, isPriority, type, ...)
      DBM_TimerStop  : modules\objects\Timer.lua:395/713/716   (event, id)
      DBM_Announce   : modules\objects\Announce.lua:592 &
                       modules\objects\SpecialWarning.lua:704
                       (event, text, icon, atype, spellId, modId, isSpecialWarning, count)
      DBM_SetStage   : modules\objects\BossMod.lua:275
                       (event, mod, modId, stage, encounterId, stageTotality)
      DBM_Pull       : DBM-Core.lua:5817                       (event, mod, delay, synced, startHp)
    (DBM's callback system passes the callback/event name as the FIRST handler arg —
     see DBM-Nameplate.lua:739 `if event ~= "DBM_TimerBegin" then return end`.)

    Purpose: purely to cross-log "what DBM thinks is happening" (its timer text/
    duration/spellID, announces, stage changes, pull detection) alongside our own
    raw combat-log capture in the SAME debug log, so the two can be compared line by
    line when rebuilding a boss's mechanic timings from real data.

    This creates NO functional dependency — Daseeki Raid Mechanics' own detection
    and alerting are completely unaffected if DBM is absent, disabled, or this file
    never successfully hooks (e.g. DBM not yet loaded, or a future DBM version
    renaming this API). Every callback here only WRITES to the debug log, with ONE
    deliberate exception: DBM_Pull also mirrors the pull into our own pull-timer
    bar (engine.lua StartPullTimer) when "Mirror DBM pull timers" is on — so any
    raid member's DBM pull drives our countdown too, no comms layer needed.
    (Sending our pulls TO DBM users would need addon comms — deferred, see E4.)
--]]

local _, Addon = ...

local function active() return Addon.debug end

local function onTimerBegin(_, id, msg, timer, icon, barType, spellId, colorId, modId, keep, fade, name)
    if not active() then return end
    Addon.DLog("[DBM] Timer start: %s (%.1fs) spell %s mod %s%s",
        tostring(msg), tonumber(timer) or 0, tostring(spellId), tostring(modId),
        name and (" target " .. tostring(name)) or "")
end

local function onTimerStop(_, id)
    if not active() then return end
    Addon.BLog("[DBM] Timer stop: id %s", tostring(id))
end

local function onAnnounce(_, text, icon, atype, spellId, modId, isSpecialWarning, count)
    if not active() then return end
    Addon.DLog("[DBM] %s: %s (spell %s, mod %s)",
        isSpecialWarning and "Special Warning" or "Announce", tostring(text), tostring(spellId), tostring(modId))
end

local function onSetStage(_, mod, modId, stage, encounterId)
    if not active() then return end
    Addon.DLog("[DBM] Stage change: mod %s -> stage %s (encounter %s)",
        tostring(modId), tostring(stage), tostring(encounterId))
end

-- DBM_Pull fires with the boss-mod object (a table), the pull delay, whether the pull
-- was network-synced, and the boss's starting HP. See DBM-Core.lua:5817.
-- Unlike the log-only handlers above, this one runs REGARDLESS of debug mode:
-- only the log line stays debug-gated; the pull-timer mirror below must work in
-- normal play too.
local function onPull(_, mod, delay, synced, startHp)
    if active() then
        local modId = (type(mod) == "table" and mod.id) and tostring(mod.id) or tostring(mod)
        Addon.DLog("[DBM] Pull: mod %s (delay %.1fs, startHP %s%s)",
            modId, tonumber(delay) or 0, tostring(startHp), synced and ", synced" or "")
    end
    -- Mirror DBM's pull into our countdown bar ("Mirror DBM pull timers", default
    -- ON). pcall-kept in the bridge's soft-dependency spirit: an error here would
    -- otherwise propagate up into DBM's callback dispatcher.
    delay = tonumber(delay)
    if delay and delay > 0 and Addon.StartPullTimer
       and Addon.db and Addon.db.settings and Addon.db.settings.mirrorDBMPull ~= false then
        pcall(function() Addon:StartPullTimer(delay, "dbm") end)
    end
end

-- Returns true ONLY if DBM is present AND every callback registered without error.
-- pcall-guarded so a future DBM renaming a callback can never error our addon and,
-- crucially, so the "active" confirmation below never lies about a hook that failed.
local function TryHook()
    if not (_G.DBM and type(DBM.RegisterCallback) == "function") then return false end
    local ok = pcall(function()
        DBM:RegisterCallback("DBM_TimerBegin", onTimerBegin)
        DBM:RegisterCallback("DBM_TimerStop",  onTimerStop)
        DBM:RegisterCallback("DBM_Announce",   onAnnounce)
        DBM:RegisterCallback("DBM_SetStage",   onSetStage)
        DBM:RegisterCallback("DBM_Pull",       onPull)
    end)
    return ok
end

-- DBM may finish loading after us regardless of .toc OptionalDeps ordering, so
-- retry once on PLAYER_LOGIN (by which point every addon is loaded). Stays silent
-- if DBM is absent or registration failed — the bridge is optional and degrades
-- cleanly, so we only announce it when it genuinely hooked.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if TryHook() then
        print("|cff66ccff[DRM]|r DBM debug bridge active — DBM's own timers/announces/stages/pulls will be cross-logged when debug capture is on.")
    end
end)
