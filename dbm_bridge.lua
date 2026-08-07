--[[
    Daseeki Raid Mechanics 2.0 — boss-mod interop, RECEIVE-ONLY  (wave 3)

    Design doc verdict for this file: "REBUILD as receive-only interop — ingest DBM
    users' pull/break timers off their public prefix, RECEIVE-ONLY (the SN
    transmit-firewall precedent: never send on a third-party prefix). Our own sync
    rides our own prefix."

    CLEAN-ROOM. Everything below is implemented from DBM_ENGINE_BEHAVIOR_SPEC.md
    alone — no third-party source was read for this file, and the wave-1 version's
    source-file/line citations are gone with it. The spec's own framing (§0) is that
    message prefixes are "unprotectable facts and interoperability requirements",
    which is exactly and only what we use them as. The load-bearing spec rules:

      §7.1  Prefix `D5`, protocol version 1. Payload is
            `sender \t protocolVersion \t subPrefix \t arg1 \t arg2 \t …`.
            A message declaring a protocol version lower than the reader's is dropped.
      §7.2  `BT` (group) = break timer, seconds.  `U` = user timer (seconds, text).
      §10.19 THE FACT THAT DECIDES THIS FILE'S SHAPE: "Pull timers ride the Blizzard
            countdown API (C_PartyInfo.DoCountdown → START_PLAYER_COUNTDOWN /
            CANCEL_PLAYER_COUNTDOWN), so modless raiders see them. BREAK TIMERS DO
            NOT — they use the addon channel (BT) … Old-format pull-timer comms are
            explicitly ignored."
            So there are TWO ingest paths, not one, and listening for pull timers on
            the addon channel would hear nothing at all on a current client:
              * PULL  <- the Blizzard countdown events (works even with no boss mod
                         installed anywhere, which is strictly more coverage than the
                         wave-1 bridge's in-process callback hook had)
              * BREAK <- `D5` / `BT`
      §11.4 is what we render them THROUGH: our own pull and break timers in
            core_sync.lua, with the sender attributed on the bar and in the announce.

    ───────────────────────────────────────────────────────────────────────────────
    THE TRANSMIT FIREWALL. We NEVER send on `D5`, or on any prefix we register here.
    Registering a prefix enables RECEIVING; it does not permit sending, and there is
    deliberately no send call anywhere in this file. But absence-of-code is a claim
    that rots as a file gets edited, so the guarantee is STRUCTURAL, exactly as the
    Nexus mesh enforces the same boundary for its own interop prefixes:

      1. Every prefix in RECV_PREFIXES is pushed into `Sync.FORBIDDEN_TX` AT LOAD, so
         "we listen here" and "we may never speak here" are literally the same list
         and cannot drift apart.
      2. The sync transport gates that table in BOTH of its choke points — `Enqueue`
         (the scheduler) and `rawSend` (the wire) — so no send path, queued or
         immediate, can carry one of these prefixes.
      3. A blocked attempt increments `Sync.forbiddenTxBlocked` and writes a
         `sync.firewall` telemetry entry, so a fire is visible rather than silent.

    GATE SYNC-FW in the harness proves all three through the real functions.
--]]

local _, Addon = ...

local Bridge = {}
Addon.DBMBridge = Bridge

local Sync = Addon.Sync

-- §7.1: the boss-mod public prefix. RECEIVE ONLY.
Bridge.RECV_PREFIXES = { "D5" }
Bridge.PROTOCOL      = 1        -- §7.1 protocol version 1
Bridge.FIELD_SEP     = "\t"

-- STEP 1 OF THE FIREWALL (see the header): listening here forbids speaking here, by
-- construction, at load time — before any of this file's code can ever run.
if Sync then
    for _, p in ipairs(Bridge.RECV_PREFIXES) do Sync.FORBIDDEN_TX[p] = true end
end

Bridge.stats = {
    heard = 0, breakIngested = 0, pullIngested = 0,
    drop = { notOurs = 0, protocol = 0, unknownSub = 0, badArgs = 0, throttled = 0, disabled = 0 },
}

local function bump(key)
    Bridge.stats.drop[key] = (Bridge.stats.drop[key] or 0) + 1
    return nil, key
end

local function enabled()
    local s = Addon.db and Addon.db.settings
    if not s then return true end
    if s.dbmIngest ~= nil then return s.dbmIngest and true or false end
    -- The 1.x option was called "Mirror DBM pull timers" and still exists in the
    -- options tree (options.lua is W5's file, not this wave's). Honour it rather than
    -- leaving a switch on screen that no longer switches anything.
    return s.mirrorDBMPull ~= false      -- default ON
end
Bridge.IsEnabled = enabled

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.1 WIRE DECODE  (pure — the harness asserts it directly)
-- ══════════════════════════════════════════════════════════════════════════════
function Bridge.Decode(payload)
    if type(payload) ~= "string" then return nil, "not_a_string" end
    local f = Sync.Split(payload, Bridge.FIELD_SEP)
    local sender = f[1]
    local proto  = tonumber(f[2])
    local sub    = f[3]
    if not sub or sub == "" then return nil, "no_sub" end
    local args = {}
    for i = 4, #f do args[#args + 1] = f[i] end
    return { sender = sender, protocol = proto, sub = sub, args = args }
end

-- ══════════════════════════════════════════════════════════════════════════════
--  INGEST
-- ══════════════════════════════════════════════════════════════════════════════
local RECV = {}
for _, p in ipairs(Bridge.RECV_PREFIXES) do RECV[p] = true end

Bridge.THROTTLE = 1            -- one accepted message per sender per second

local lastFrom = {}

local function throttled(who)
    local now = Addon.Sched:Now()
    local last = lastFrom[who or "?"]
    lastFrom[who or "?"] = now
    if last and (now - last) < Bridge.THROTTLE then return true end
    return false
end

function Bridge.OnAddonMessage(prefix, payload, channel, rawSender)
    if not RECV[prefix] then return bump("notOurs") end
    Bridge.stats.heard = Bridge.stats.heard + 1
    if not enabled() then return bump("disabled") end

    local msg = Bridge.Decode(payload)
    if not msg then return bump("badArgs") end
    -- §7.1: a message declaring a protocol version lower than ours is dropped.
    if not msg.protocol or msg.protocol < Bridge.PROTOCOL then return bump("protocol") end

    local who = msg.sender
    if not who or who == "" then who = rawSender end
    if who and Sync.Me() and Sync.ShortName(who) == Sync.ShortName(Sync.Me()) then
        return bump("notOurs")      -- our own name on their wire: not possible, but cheap
    end

    if msg.sub == "BT" then
        local secs = tonumber(msg.args[1])
        if secs == nil then return bump("badArgs") end
        if throttled(who) then return bump("throttled") end
        Bridge.stats.breakIngested = Bridge.stats.breakIngested + 1
        Addon.breakSource = Sync.ShortName(who)
        return Bridge.RenderBreak(secs, who)
    end

    -- Everything else on their wire is theirs. We count it and walk away: no
    -- combat-start corroboration, no kill sync, no version handshake. Our engine is
    -- driven by OUR wire and our own detection, never by another addon's opinion.
    return bump("unknownSub")
end

-- Both renderers go through the SAME §11.4 surfaces our own wire uses, with the
-- source attributed, so an ingested timer is indistinguishable from ours on screen
-- except for the attribution — and impossible to confuse in the logs.
function Bridge.RenderBreak(seconds, who)
    local src = "dbm" .. ((who and who ~= "") and (":" .. tostring(Sync.ShortName(who))) or "")
    if seconds == 0 then return Addon:CancelBreakTimer(src) end
    return Addon:StartBreakTimer(seconds, src)
end

function Bridge.RenderPull(seconds, who)
    local src = "countdown" .. ((who and who ~= "") and (":" .. tostring(Sync.ShortName(who))) or "")
    if seconds == 0 then return Addon:CancelPullTimer(src) end
    return Addon:StartPullTimer(seconds, src)
end

-- ── §10.19 the Blizzard countdown path (this is where pull timers actually are) ──
Bridge.PULL_DEDUP = 3          -- a countdown re-broadcast inside this window is one pull

function Bridge.OnStartCountdown(a1, a2)
    if not enabled() then return bump("disabled") end
    -- Defensive argument read: the event carries an initiator and a duration, and we
    -- take whichever argument is the number rather than pinning an index.
    local secs = tonumber(a2)
    local who  = a1
    if secs == nil then secs, who = tonumber(a1), a2 end
    if secs == nil then return bump("badArgs") end

    local now = Addon.Sched:Now()
    if Bridge._lastPullAt and (now - Bridge._lastPullAt) < Bridge.PULL_DEDUP
       and Bridge._lastPullSecs == secs then
        return bump("throttled")
    end
    Bridge._lastPullAt, Bridge._lastPullSecs = now, secs

    Bridge.stats.pullIngested = Bridge.stats.pullIngested + 1
    return Bridge.RenderPull(secs, who)
end

function Bridge.OnCancelCountdown(who)
    if not enabled() then return bump("disabled") end
    Bridge._lastPullAt, Bridge._lastPullSecs = nil, nil
    return Bridge.RenderPull(0, who)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  BOOT
-- ══════════════════════════════════════════════════════════════════════════════
-- Called from Addon:InitEngine() (core_boot.lua) at login, so there is one boot
-- order for the whole engine and no second PLAYER_LOGIN handler racing it.
Bridge.booted = false

function Bridge:Boot()
    if Bridge.booted then return false end
    Bridge.booted = true

    -- RECEIVE registration. This grants no send capability of any kind, and the
    -- prefixes are already in the transmit firewall (see the header, step 1).
    for _, p in ipairs(Bridge.RECV_PREFIXES) do Sync.env.RegisterAddonMessagePrefix(p) end

    if type(_G.CreateFrame) ~= "function" then return true end   -- headless

    local f = _G.CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("START_PLAYER_COUNTDOWN")
    f:RegisterEvent("CANCEL_PLAYER_COUNTDOWN")
    f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
        if event == "CHAT_MSG_ADDON" then
            return Bridge.OnAddonMessage(a1, a2, a3, a4)
        elseif event == "START_PLAYER_COUNTDOWN" then
            return Bridge.OnStartCountdown(a1, a2)
        elseif event == "CANCEL_PLAYER_COUNTDOWN" then
            return Bridge.OnCancelCountdown(a1)
        end
    end)
    Bridge.frame = f
    return true
end

function Bridge:Reset()
    lastFrom = {}
    Bridge._lastPullAt, Bridge._lastPullSecs = nil, nil
    Bridge.stats = {
        heard = 0, breakIngested = 0, pullIngested = 0,
        drop = { notOurs = 0, protocol = 0, unknownSub = 0, badArgs = 0, throttled = 0, disabled = 0 },
    }
    return true
end

return Bridge
