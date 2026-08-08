--[[
    Daseeki Raid Mechanics 2.0 — addon-channel sync, reload recovery,
    pull + break timers  (wave 3)

    ENGINE SPEC §7 (the addon-channel protocol), §9.1/§9.2 (reload recovery and
    break-timer persistence), §11.4 (pull and break timers), and the §12 numbers.
    Design doc, target-architecture item 7: "our own prefix; pull/break/kill with the
    spec's corroboration thresholds (Classic's 1-sender end concession noted); version
    nag WITHOUT the hard self-disable (owner product call: we never brick ourselves);
    reload recovery via the whisper cascade pattern; DBM pull-timer ingest receive-only."

    ───────────────────────────────────────────────────────────────────────────────
    OUR OWN WIRE. We ride OUR OWN PREFIX and nobody else's. The suite convention is
    Nexus's: `DSK` + one letter for the addon + a role index (Nexus uses DSKN0..DSKN3),
    so Raid Mechanics is `DSKR0`. One prefix carries everything: unlike Nexus's mesh
    (which splits prefixes so each role gets its own token bucket for bulk transfers)
    raid-mechanics traffic is a handful of short messages per pull, and the reference
    engine's own single-prefix design (§7.1) is the proven shape for exactly this load.

        payload := sender \t transportVersion \t subPrefix \t subProtocol \t arg1 \t …

    DELIBERATE DEVIATION FROM THE REFERENCE (an improvement, not an accident). The
    reference carries each message's own protocol number INSIDE its argument list at a
    per-message position (§7.2: "each guild/world message carries its own protocol
    number distinct from the transport version … receivers hard-drop mismatches").
    That works, but it means every handler re-implements the same gate at a different
    argument index. We hoist it to a FIXED FOURTH FIELD, so there is exactly ONE
    hard-drop rule, applied before dispatch, for every sub-protocol we will ever add.
    The evolution property the reference buys with it is preserved verbatim: bump one
    message's number and old clients silently ignore that message and nothing else.

    ───────────────────────────────────────────────────────────────────────────────
    THE TRANSMIT FIREWALL (SN-bridge precedent, Nexus mesh.lua). Third-party prefixes
    we RECEIVE on — today just the boss-mod prefix dbm_bridge.lua ingests — are
    RECEIVE-ONLY forever. Registering a prefix only enables receiving; it never permits
    sending. But "there is no send path" is a claim that rots, so it is enforced
    structurally the same way Nexus enforces it: EVERY message leaves through
    `rawSend`, EVERY queued frame enters through `Enqueue`, and BOTH are gated on the
    same pure predicate. Gating both is what makes "no send path can carry it"
    provable rather than asserted, and the guard keeps a counter so a fire is visible.

    ───────────────────────────────────────────────────────────────────────────────
    OWNER VETO, WRITTEN INTO THE CODE. ENGINE SPEC §7.4 hard-disables the addon after
    3 senders report a newer force-disable revision. Design doc R2 (owner-approved,
    2026-08-07): NAG ONLY, NEVER SELF-DISABLE. We never brick ourselves in the middle
    of somebody's raid night because a stranger's client said so. `SELF_DISABLE` below
    is a named constant pinned to false, the force-disable field is PARSED and COUNTED
    but never acted on, and GATE SYNC-VER asserts the absence two ways: behaviourally
    (five force-disable senders leave us enabled and call nothing) and structurally
    (this file contains no disable call at all), so a mutation that restores the
    reference behaviour reddens a gate instead of shipping.

    HEADLESS DISCIPLINE: every WoW API is reached through `Sync.env` (comms-specific)
    or `Lifecycle.env` (world facts the harness already injects), and every timed step
    runs on the engine scheduler. The harness drives the REAL cascade on a fake clock.
--]]

local _, Addon = ...

local Sync = {}
Addon.Sync = Sync

local function S()    return Addon.Sched end
local function Life() return Addon.Lifecycle end
local function Tim()  return Addon.Timers end

-- Telemetry kinds this wave adds. Registered from here rather than by editing the
-- wave-1 ring, so the "unknown kind" drift counter stays meaningful.
if Addon.Telemetry and Addon.Telemetry.KINDS then
    Addon.Telemetry.KINDS["sync.firewall"] = true   -- a forbidden-prefix transmit was blocked
    Addon.Telemetry.KINDS["sync.drop"]     = true   -- an inbound message was refused
    Addon.Telemetry.KINDS["sync.recovery"] = true   -- a reload-recovery cascade step
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.1 WIRE CONSTANTS
-- ══════════════════════════════════════════════════════════════════════════════
Sync.PREFIX      = "DSKR0"
Sync.PREFIX_LIST = { Sync.PREFIX }
Sync.TRANSPORT   = 1              -- transport protocol version

local FIELD_SEP = "\t"            -- §7.1 field separator
local ARG_SEP   = "\30"           -- our own sub-separator for packed argument lists
Sync.FIELD_SEP, Sync.ARG_SEP = FIELD_SEP, ARG_SEP

-- §7.2 sub-prefix catalogue, ours. `scope` drives receive-side channel validation
-- (§7.1), `prio` picks the send queue (§7.1: ALERT for combat-critical traffic,
-- NORMAL for hello/version/recovery payloads), `proto` is the per-message
-- sub-protocol number receivers hard-drop on mismatch (§7.2).
Sync.SUB = {
    C   = { scope = "group",   prio = "ALERT",  proto = 1 },  -- combat start
    EE  = { scope = "group",   prio = "ALERT",  proto = 1 },  -- encounter ended
    K   = { scope = "group",   prio = "ALERT",  proto = 1 },  -- mob killed
    M   = { scope = "group",   prio = "ALERT",  proto = 1 },  -- module sync
    PT  = { scope = "group",   prio = "ALERT",  proto = 1 },  -- pull timer
    BT  = { scope = "group",   prio = "ALERT",  proto = 1 },  -- break timer
    H   = { scope = "group",   prio = "NORMAL", proto = 1 },  -- hello (request versions)
    V   = { scope = "group",   prio = "NORMAL", proto = 1 },  -- version
    RT  = { scope = "whisper", prio = "ALERT",  proto = 1 },  -- request timers
    CI  = { scope = "whisper", prio = "NORMAL", proto = 1 },  -- combat info reply
    TR  = { scope = "whisper", prio = "NORMAL", proto = 1 },  -- timer info reply
    VI  = { scope = "whisper", prio = "NORMAL", proto = 1 },  -- variable info reply
    BTR = { scope = "whisper", prio = "NORMAL", proto = 1 },  -- break-timer recovery reply
}

-- §7.3 / §12 CORROBORATION. Combat start needs three distinct senders on every
-- client. Encounter end needs three on retail but ONLY ONE on Classic — the spec's
-- explicit concession ("classic breaks too badly otherwise"). Both rows are kept as
-- data rather than one hard-coded number, because the concession is the kind of fact
-- that gets quietly "tidied up" into 3 by someone who has not read §7.3.
Sync.CORROBORATION = {
    classic = { C = 3, EE = 1 },
    retail  = { C = 3, EE = 3 },
}
Sync.CLIENT = "classic"           -- Era. The only client this addon ships for.

function Sync.Threshold(sub, client)
    local row = Sync.CORROBORATION[client or Sync.CLIENT]
    if not row then return 1 end
    return row[sub] or 1
end

-- §12 numbers quick-reference.
Sync.MODULE_SEND_DEDUP    = 8     -- module sync de-duplication, send side
Sync.MODULE_RECV_DEDUP    = 0     -- receive side, per-module configurable (enc.combat.syncThreshold)
Sync.SPAM_PRUNE_AGE       = 8     -- sync-spam table pruning: entries older than 8 s…
                                  -- …on the 20 s housekeeping pass (Sched.HOUSEKEEP_INTERVAL)
Sync.BREAK_THROTTLE       = 1     -- break timers: one per sender per second
Sync.BREAK_MAX            = 3600  -- …and capped at 3600 s (= the §11.4 60-minute maximum)
Sync.RECOVERY_ASK_AT      = { 7, 10, 13 }   -- §9.1 whisper cascade
-- AUDIT RM-2 (Brief N, lesson Class 6). Ours, not the spec's: the ONE bounded
-- re-arm, 5 s past the last rung of the cascade. It exists for the case the spec
-- never contemplated — the group list still unanswered thirteen seconds after a
-- reload — and it is a single extra ask, not a second ladder, because the flag it
-- extends BLINDS combat-start detection while it is held (§9.1 step 3). Worst case
-- is therefore 18 s + the 5 s reply window, once, instead of 15 s.
Sync.RECOVERY_REARM_AT    = 18
Sync.RECOVERY_REPLY_VALID = 5               -- §9.1 "only within 5 s of asking"
Sync.RECOVERY_REPLY_THROTTLE = 1            -- §7.3 one reply per requester per second
Sync.VERSION_DEBOUNCE     = 3     -- §7.4 group version reply debounce
Sync.NAG_SENDERS          = 2     -- §7.4 update nag after 2 distinct newer senders
Sync.PULL_MIN             = 3     -- §11.4 refuses durations between 0 and 3 s exclusive
-- Ours: a sane ceiling, the spec states none. RAISED FROM 60 IN W4a, because the
-- ceiling was demonstrably too low for real content: Molten Core's Ragnaros RP is a
-- 73 s stand-still window (ENCOUNTERS SPEC §2.10) declared through
-- `detect.pullCountdown`, and clamping it to 60 would do exactly what this function's
-- own refusal comment objects to — turn a declared duration into a quiet lie.
Sync.PULL_MAX             = 180
Sync.PULL_COUNTDOWN_DEPTH = 5     -- §12 pull-timer countdown depth
Sync.BREAK_ANNOUNCE_AT    = { 600, 300, 120, 60 }   -- §11.4 10, 5, 2, 1 minutes…
                                                    -- …plus zero, which the bar's own expiry carries

-- OWNER VETO (design doc R2). Pinned false. See the file header.
Sync.SELF_DISABLE = false

-- Our version identity. `release` is a plain YYYYMMDD integer so "newer" is an
-- integer comparison with no date arithmetic and no per-month day table.
Sync.VERSION = { rev = 20000, release = 20260807, display = "2.0.0" }

-- ══════════════════════════════════════════════════════════════════════════════
--  THE TRANSMIT FIREWALL (§7.5 interop boundary, SN-bridge precedent)
-- ══════════════════════════════════════════════════════════════════════════════
-- Prefixes this client may RECEIVE on but must NEVER transmit on. dbm_bridge.lua
-- registers the boss-mod prefix for ingest; impersonating another addon's traffic is
-- out of the question, so the send path refuses it structurally.
Sync.FORBIDDEN_TX = {
    ["D5"] = true,     -- the boss-mod public prefix dbm_bridge.lua ingests (§7.1)
}
Sync.forbiddenTxBlocked = 0

-- PURE predicate — the single source of truth both gates call.
function Sync.IsForbiddenTxPrefix(prefix)
    return Sync.FORBIDDEN_TX[prefix] == true
end

local function blockTx(prefix, where)
    Sync.forbiddenTxBlocked = (Sync.forbiddenTxBlocked or 0) + 1
    if Addon.Telemetry then
        Addon.Telemetry.Write("sync.firewall", { key = prefix, reason = where })
    end
    return false
end

-- ══════════════════════════════════════════════════════════════════════════════
--  INJECTABLE ENVIRONMENT
-- ══════════════════════════════════════════════════════════════════════════════
-- Comms-specific only. World facts (in-instance, in-raid, difficulty, group
-- iteration) are read through `Lifecycle.env`, which the harness already injects —
-- one fake world, not two.
local function g(name)
    return function(...)
        local f = _G[name]
        if type(f) == "function" then return f(...) end
        return nil
    end
end

Sync.env = {
    SendAddonMessage = function(prefix, msg, chatType, target)
        local C = _G.C_ChatInfo
        if C and type(C.SendAddonMessage) == "function" then
            return C.SendAddonMessage(prefix, msg, chatType, target)
        end
        local f = _G.SendAddonMessage
        if type(f) == "function" then return f(prefix, msg, chatType, target) end
        return nil
    end,
    RegisterAddonMessagePrefix = function(prefix)
        local C = _G.C_ChatInfo
        if C and type(C.RegisterAddonMessagePrefix) == "function" then
            return C.RegisterAddonMessagePrefix(prefix)
        end
        local f = _G.RegisterAddonMessagePrefix
        if type(f) == "function" then return f(prefix) end
        return nil
    end,
    -- §7.1 says INSTANCE_CHAT is for "an INSTANCE-GROUP and inside an instance", which
    -- is NOT the same question as IsInGroup(). On Era an instance group essentially
    -- never exists, so answering the easy question instead would route every raid's
    -- traffic onto a channel the server rejects — i.e. silently break all sync inside
    -- raids, which is the only place it matters.
    IsInInstanceGroup = function()
        local f = _G.IsInGroup
        if type(f) ~= "function" then return false end
        local okv, v = pcall(f, _G.LE_PARTY_CATEGORY_INSTANCE or 2)
        if not okv then return false end
        return v and true or false
    end,
    GetNetStats        = g("GetNetStats"),
    GetRealmName       = g("GetRealmName"),
    UnitIsConnected    = g("UnitIsConnected"),
    UnitIsGroupLeader  = g("UnitIsGroupLeader"),
    UnitIsGroupAssistant = g("UnitIsGroupAssistant"),
    FlashClientIcon    = g("FlashClientIcon"),
    -- name, realm for a unit token; realm is nil/"" for same-realm players. Falls
    -- back to the lifecycle's injected world so the harness has ONE world to fake.
    UnitNameRealm = function(unit)
        local f = _G.UnitName
        if type(f) ~= "function" then
            local L = Addon.Lifecycle
            f = L and L.env and L.env.UnitName
        end
        if type(f) ~= "function" then return nil end
        return f(unit)
    end,
    Time = function()
        local f = _G.GetServerTime
        if type(f) == "function" then
            local okv, v = pcall(f)
            if okv and type(v) == "number" then return v end
        end
        if type(os) == "table" and type(os.time) == "function" then return os.time() end
        return 0
    end,
    DateAt = function(when)
        local f = _G.date
        if type(f) == "function" then
            local okv, v = pcall(f, "%H:%M", when)
            if okv and type(v) == "string" then return v end
        end
        return nil
    end,
}

function Sync:SetEnv(t)
    if type(t) ~= "table" then return end
    for k, v in pairs(t) do Sync.env[k] = v end
end

-- ── Identity ──────────────────────────────────────────────────────────────────
-- §7.1: `Name-RealmWithSpacesAndHyphensStripped`.
function Sync.StripRealm(realm)
    if type(realm) ~= "string" or realm == "" then return nil end
    return (realm:gsub("[%s%-]", ""))
end

function Sync.FullName(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    local r = Sync.StripRealm(realm)
    if not r then return name end
    return name .. "-" .. r
end

function Sync.MyRealm()
    return Sync.StripRealm(Sync.env.GetRealmName())
end

function Sync.Me()
    local name, realm = Sync.env.UnitNameRealm("player")
    return Sync.FullName(name or "player", realm or Sync.env.GetRealmName())
end

-- §7.1 "the sender name is taken from whichever of the two sender arguments carries a
-- realm suffix, then ambiguated to short form" — we carry one name and normalise it.
function Sync.ShortName(full)
    if type(full) ~= "string" then return nil end
    return (full:match("^([^%-]+)")) or full
end

function Sync.SameRealm(full)
    if type(full) ~= "string" then return false end
    local r = full:match("%-(.+)$")
    if not r then return true end                 -- no suffix = our own realm
    local mine = Sync.MyRealm()
    return mine == nil or r == mine
end

-- §7.3 "each accepted start adds the receiver's own latency (GetNetStats world
-- latency ÷ 1000)".
function Sync.Latency()
    local _, _, _, world = Sync.env.GetNetStats()
    local ms = tonumber(world)
    if not ms or ms < 0 then return 0 end
    return ms / 1000
end

-- ══════════════════════════════════════════════════════════════════════════════
--  ENCODING
-- ══════════════════════════════════════════════════════════════════════════════
-- One field, escaped. Separators can never survive into a field, so a hostile or
-- merely careless payload can never inject an extra field.
local function esc(v)
    if v == nil then return "" end
    if v == true then return "1" end
    if v == false then return "0" end
    return (tostring(v):gsub("[\t\n\r\30]", " "))
end

function Sync.Encode(sender, sub, ...)
    local meta = Sync.SUB[sub]
    local parts = { esc(sender), esc(Sync.TRANSPORT), esc(sub), esc(meta and meta.proto or 1) }
    for i = 1, select("#", ...) do parts[#parts + 1] = esc((select(i, ...))) end
    return table.concat(parts, FIELD_SEP)
end

-- Plain-text split that PRESERVES empty fields (an omitted optional argument is an
-- empty field, not a missing one, and every handler indexes positionally).
function Sync.Split(s, sep)
    local out = {}
    if type(s) ~= "string" then return out end
    sep = sep or FIELD_SEP
    local start = 1
    while true do
        local i = s:find(sep, start, true)
        if not i then out[#out + 1] = s:sub(start) break end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + #sep
    end
    return out
end

function Sync.PackArgs(list)
    if type(list) ~= "table" or #list == 0 then return "" end
    local out = {}
    for i = 1, #list do out[i] = esc(list[i]) end
    return table.concat(out, ARG_SEP)
end

function Sync.UnpackArgs(s)
    if type(s) ~= "string" or s == "" then return {} end
    return Sync.Split(s, ARG_SEP)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  SEND PATH — the two gates the firewall rests on
-- ══════════════════════════════════════════════════════════════════════════════
Sync.queue  = { ALERT = {}, NORMAL = {} }
Sync.DRAIN_INTERVAL = 0.1
Sync.BUCKET_CAP     = 10
Sync.BUCKET_REFILL  = 5           -- tokens per second
Sync.tokens = Sync.BUCKET_CAP
Sync.tokensAt = nil
Sync.sent   = 0
Sync.draining = false

-- GATE 1 of 2. The wire itself. Nothing reaches SendAddonMessage except through here.
local function rawSend(prefix, payload, chatType, target)
    if Sync.IsForbiddenTxPrefix(prefix) then return blockTx(prefix, "rawSend") end
    Sync.sent = Sync.sent + 1
    Sync.lastSent = { prefix = prefix, payload = payload, chatType = chatType, target = target }
    Sync.env.SendAddonMessage(prefix, payload, chatType, target)
    return true
end
Sync._rawSend = rawSend           -- exposed for the transmit-firewall gate

-- GATE 2 of 2. The scheduler. A forbidden prefix cannot even enter the queue, so it
-- can never be waiting to leave when someone later loosens gate 1.
function Sync.Enqueue(prefix, payload, meta)
    if Sync.IsForbiddenTxPrefix(prefix) then return blockTx(prefix, "Enqueue") end
    meta = meta or {}
    local q = Sync.queue[meta.priority == "ALERT" and "ALERT" or "NORMAL"]
    q[#q + 1] = { prefix = prefix, payload = payload,
                  chatType = meta.chatType, target = meta.target }
    Sync.WakeDrain()
    return true
end

local drainTask
function Sync.WakeDrain()
    if Sync.draining then return end
    Sync.draining = true
    S():Schedule(Sync.DRAIN_INTERVAL, drainTask, Sync)
end

function Sync.QueueDepth()
    return #Sync.queue.ALERT + #Sync.queue.NORMAL
end

function Sync.Drain()
    local now = S():Now()
    if Sync.tokensAt then
        Sync.tokens = Sync.tokens + (now - Sync.tokensAt) * Sync.BUCKET_REFILL
        if Sync.tokens > Sync.BUCKET_CAP then Sync.tokens = Sync.BUCKET_CAP end
    end
    Sync.tokensAt = now
    local n = 0
    while Sync.tokens >= 1 do
        -- ALERT drains ahead of NORMAL, always (§7.1 two priorities).
        local q = (#Sync.queue.ALERT > 0) and Sync.queue.ALERT or Sync.queue.NORMAL
        local msg = table.remove(q, 1)
        if not msg then break end
        Sync.tokens = Sync.tokens - 1
        rawSend(msg.prefix, msg.payload, msg.chatType, msg.target)
        n = n + 1
    end
    Sync.draining = false
    if Sync.QueueDepth() > 0 then Sync.WakeDrain() end
    return n
end

function drainTask() return Sync.Drain() end

-- §7.1 channel selection. Returns nil for SOLO, which means "loop it straight back
-- into the local handler rather than send".
function Sync.Channel()
    local e = Life().env
    if e.IsInInstance() and Sync.env.IsInInstanceGroup() then return "INSTANCE_CHAT" end
    if e.IsInRaid() then return "RAID" end
    if e.IsInGroup() then return "PARTY" end
    return nil
end

-- Broadcast one sub-prefix to the group. SOLO loops back so the sender behaves
-- identically to a receiver (§7.1, §7.3).
function Sync.Send(sub, ...)
    local meta = Sync.SUB[sub]
    if not meta then return false, "unknown_sub" end
    if meta.scope == "whisper" then return false, "whisper_scope" end
    local me = Sync.Me()
    local payload = Sync.Encode(me, sub, ...)
    local chan = Sync.Channel()
    if not chan then
        Sync.Receive(Sync.PREFIX, payload, "SOLO", me)
        return true, "loopback"
    end
    return Sync.Enqueue(Sync.PREFIX, payload, { priority = meta.prio, chatType = chan }), chan
end

function Sync.Whisper(sub, target, ...)
    local meta = Sync.SUB[sub]
    if not meta then return false, "unknown_sub" end
    if not target or target == "" then return false, "no_target" end
    -- §9.1: cross-realm WHISPER addon messages silently fail, so we never send one.
    if not Sync.SameRealm(target) then return false, "cross_realm" end
    local payload = Sync.Encode(Sync.Me(), sub, ...)
    return Sync.Enqueue(Sync.PREFIX, payload,
        { priority = meta.prio, chatType = "WHISPER", target = target })
end

-- ══════════════════════════════════════════════════════════════════════════════
--  RECEIVE PATH
-- ══════════════════════════════════════════════════════════════════════════════
Sync.spam         = {}    -- dedupe key -> timestamp
Sync.corroborate  = {}    -- "sub:key" -> { at =, senders = { [full] = true }, n = }
Sync.peers        = {}    -- full name -> { rev =, release =, display =, at = }
Sync.breakSeen    = {}    -- sender -> timestamp (break-timer throttle)
Sync.replySeen    = {}    -- requester -> timestamp (recovery reply throttle)
Sync.stats = { received = 0, dropped = 0, corroborated = 0, nagged = 0,
               forceDisableSeen = 0, recovered = 0 }

local function drop(reason, sub, sender)
    Sync.stats.dropped = Sync.stats.dropped + 1
    if Addon.Telemetry then
        Addon.Telemetry.Write("sync.drop", { reason = reason, key = sub, path = sender })
    end
    return nil, reason
end
Sync._drop = drop

-- §7.3 de-duplication helper. Returns true when the key was ALREADY seen inside the
-- window (i.e. the caller should drop).
function Sync.SeenRecently(key, window)
    local now = S():Now()
    local last = Sync.spam[key]
    Sync.spam[key] = now
    if last and (now - last) < (window or Sync.SPAM_PRUNE_AGE) then return true end
    return false
end

-- §7.3 corroboration counter. Returns the number of DISTINCT senders now on record.
function Sync.Corroborate(bucketKey, sender)
    local now = S():Now()
    local b = Sync.corroborate[bucketKey]
    if not b or (now - b.at) > Sync.SPAM_PRUNE_AGE then
        b = { at = now, senders = {}, n = 0 }
        Sync.corroborate[bucketKey] = b
    end
    if not b.senders[sender] then
        b.senders[sender] = true
        b.n = b.n + 1
        b.at = now
    end
    return b.n
end

function Sync.ClearCorroboration(bucketKey)
    Sync.corroborate[bucketKey] = nil
end

-- §7.3 / §12: sync-spam table pruning — every 20 s (the scheduler's housekeeping
-- interval), entries older than 8 s. Registered on the engine housekeeper so the
-- "idle cost outside encounters is zero" guarantee holds: no private heartbeat.
function Sync.Prune()
    local now = S():Now()
    local age = Sync.SPAM_PRUNE_AGE
    local n = 0
    for k, t in pairs(Sync.spam) do
        if (now - t) > age then Sync.spam[k] = nil; n = n + 1 end
    end
    for k, b in pairs(Sync.corroborate) do
        if (now - b.at) > age then Sync.corroborate[k] = nil; n = n + 1 end
    end
    for k, t in pairs(Sync.breakSeen) do
        if (now - t) > age then Sync.breakSeen[k] = nil; n = n + 1 end
    end
    for k, t in pairs(Sync.replySeen) do
        if (now - t) > age then Sync.replySeen[k] = nil; n = n + 1 end
    end
    return n
end

-- §7.1 receive-side channel validation.
local GROUP_CHANNELS = { RAID = true, PARTY = true, INSTANCE_CHAT = true, SOLO = true }
function Sync.ChannelAllowed(scope, channel)
    if scope == "whisper" then return channel == "WHISPER" or channel == "SOLO" end
    return GROUP_CHANNELS[channel] == true
end

-- Re-entrancy guard. Some inbound messages drive engine paths that themselves emit
-- SYNC_SEND (a corroborated kill re-enters Life:OnUnitDied, which broadcasts `K`).
-- Echoing a sync we just received back onto the wire would be an amplification loop,
-- so outbound sends are suppressed for the duration of inbound handling.
Sync.inbound = false
local function withoutEcho(fn, ...)
    local prev = Sync.inbound
    Sync.inbound = true
    local ok, a, b = pcall(fn, ...)
    Sync.inbound = prev
    if not ok then return nil, "handler_error" end
    return a, b
end
Sync._withoutEcho = withoutEcho

local HANDLERS = {}      -- filled in below

-- THE one entry point. `channel` is the CHAT_MSG_ADDON channel; `rawSender` is the
-- name the client reports (used only when the payload's own sender field is absent).
function Sync.Receive(prefix, payload, channel, rawSender)
    if prefix ~= Sync.PREFIX then return drop("not_our_prefix", prefix, rawSender) end
    local f = Sync.Split(payload)
    local sender    = (f[1] ~= "" and f[1]) or rawSender
    local transport = tonumber(f[2])
    local sub       = f[3]
    local proto     = tonumber(f[4])

    if not sub or not Sync.SUB[sub] then return drop("unknown_sub", sub, sender) end
    -- §7.1: "A message whose declared protocol version is lower than the receiver's
    -- is dropped."
    if not transport or transport < Sync.TRANSPORT then
        return drop("transport_version", sub, sender)
    end
    -- §7.2: per-message sub-protocol numbers are HARD-DROPPED on mismatch. This is
    -- the single hoisted gate (see the file header) — it fires before dispatch, for
    -- every sub-prefix, in both directions of drift (older AND newer).
    if proto ~= Sync.SUB[sub].proto then return drop("subprotocol", sub, sender) end
    if not Sync.ChannelAllowed(Sync.SUB[sub].scope, channel) then
        return drop("channel_scope", sub, sender)
    end

    Sync.stats.received = Sync.stats.received + 1
    Addon:FireEngineEvent("SYNC_RECV", sub, sender, unpack(f, 5, math.max(4, #f)))

    local h = HANDLERS[sub]
    if not h then return drop("no_handler", sub, sender) end
    return h(sender, channel, unpack(f, 5, math.max(4, #f)))
end

-- The live CHAT_MSG_ADDON shape.
function Sync.OnAddonMessage(prefix, payload, channel, rawSender)
    return Sync.Receive(prefix, payload, channel, rawSender)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.3 COMBAT START (`C`) — three distinct senders
-- ══════════════════════════════════════════════════════════════════════════════
-- Our `C` carries the sender's instance id as an extra field so the spec's "outdoors
-- with the sender in a different world-zone than the player" rejection is actually
-- implementable — the reference gets the zone from its own richer payload.
local function currentInstanceId()
    local _, _, _, _, _, _, _, instanceId = Life().env.GetInstanceInfo()
    return instanceId
end

local function currentInstanceType()
    local _, instanceType = Life().env.GetInstanceInfo()
    return instanceType
end

function Sync.OnCombatStart(sender, channel, delay, encId, pct, trigger, zone)
    if sender == Sync.Me() then return drop("self", "C", sender) end
    if currentInstanceType() == "pvp" then return drop("pvp", "C", sender) end

    local enc = Addon.encountersById[encId]
    if not enc then return drop("no_module", "C", sender) end

    local here = currentInstanceId()
    -- Outdoors, a sender in a different world-zone is not in our fight.
    if not Life().env.IsInInstance() then
        if zone and zone ~= "" and tonumber(zone) ~= here then
            return drop("different_zone", "C", sender)
        end
    end
    -- The module's own zone list must include where we are standing.
    if #(enc.zones or {}) > 0 then
        local hit = false
        for _, z in ipairs(enc.zones) do if z == here then hit = true break end end
        if not hit then return drop("zone_not_in_module", "C", sender) end
    end

    local n = Sync.Corroborate("C:" .. tostring(encId), sender)
    local need = Sync.Threshold("C")
    if n < need then return false, "corroborating", n end

    Sync.ClearCorroboration("C:" .. tostring(encId))
    Sync.stats.corroborated = Sync.stats.corroborated + 1
    local d = (tonumber(delay) or 0) + Sync.Latency()
    local rt = withoutEcho(function()
        return Life():StartCombat(enc, d, "sync")
    end)
    return rt, "started", n
end
HANDLERS.C = Sync.OnCombatStart

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.3 ENCOUNTER END (`EE`) — THREE senders on retail, ONE on Classic
-- ══════════════════════════════════════════════════════════════════════════════
function Sync.OnEncounterEnd(sender, channel, encounterId, success, encId)
    if sender == Sync.Me() then return drop("self", "EE", sender) end
    local rt = Life().byId[encId]
    if not rt then return drop("not_engaged", "EE", sender) end

    local n = Sync.Corroborate("EE:" .. tostring(encId), sender)
    if n < Sync.Threshold("EE") then return false, "corroborating", n end
    Sync.ClearCorroboration("EE:" .. tostring(encId))
    Sync.stats.corroborated = Sync.stats.corroborated + 1

    local won = (success == "1" or success == 1 or success == true)
    if not won then return false, "not_a_kill", n end
    withoutEcho(function() Life():EndCombat(rt, false, "sync_encounter_end") end)
    return true, "ended", n
end
HANDLERS.EE = Sync.OnEncounterEnd

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.3 MOB KILL (`K`)
-- ══════════════════════════════════════════════════════════════════════════════
function Sync.OnKill(sender, channel, creatureId, difficultyId)
    if sender == Sync.Me() then return drop("self", "K", sender) end
    local it = currentInstanceType()
    if it == "pvp" or it == "none" then return drop("instance_type", "K", sender) end
    -- Guards against a parallel raid of the same instance on another difficulty.
    local mine = Life():SnapshotDifficulty()
    if difficultyId and difficultyId ~= "" and tonumber(difficultyId) ~= mine.id then
        return drop("difficulty_mismatch", "K", sender)
    end
    local cid = tonumber(creatureId)
    if not cid then return drop("bad_creature", "K", sender) end
    return withoutEcho(function() return Life():OnUnitDied(cid) end)
end
HANDLERS.K = Sync.OnKill

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.3 MODULE SYNC (`M`)
-- ══════════════════════════════════════════════════════════════════════════════
-- Send side: de-duplicated by moduleId+event+args on an 8 s window, AND delivered to
-- the sender locally so behaviour is identical for sender and receivers.
function Sync.SendModuleSync(encId, key, ...)
    local args = { ... }
    local dedupKey = "M:send:" .. tostring(encId) .. ":" .. tostring(key)
                     .. ":" .. Sync.PackArgs(args)
    if Sync.SeenRecently(dedupKey, Sync.MODULE_SEND_DEDUP) then return false, "deduped" end
    Sync.DeliverModuleSync(Sync.Me(), encId, key, Sync.PackArgs(args))
    return Sync.Send("M", encId, key, Sync.PackArgs(args))
end

function Sync.DeliverModuleSync(sender, encId, key, packed)
    local rt = Life().byId[encId]
    if not rt then return 0 end
    -- The `sync` trigger vocabulary already exists in the W1 grammar; a sync row
    -- matches on its key through the standard `text` matcher.
    return rt:Route({ on = "sync", text = key, sourceName = Sync.ShortName(sender),
                      args = Sync.UnpackArgs(packed) })
end

function Sync.OnModuleSync(sender, channel, encId, key, packed)
    if sender == Sync.Me() then return drop("self", "M", sender) end
    local enc = Addon.encountersById[encId]
    local window = (enc and enc.combat and enc.combat.syncThreshold) or Sync.MODULE_RECV_DEDUP
    if window > 0 and Sync.SeenRecently("M:recv:" .. tostring(sender) .. ":" .. tostring(encId)
                                        .. ":" .. tostring(key) .. ":" .. tostring(packed), window) then
        return drop("module_dedup", "M", sender)
    end
    return withoutEcho(function()
        return Sync.DeliverModuleSync(sender, encId, key, packed)
    end)
end
HANDLERS.M = Sync.OnModuleSync

-- ══════════════════════════════════════════════════════════════════════════════
--  §11.4 PULL TIMER  (moved here from core_boot.lua's W1 shim)
-- ══════════════════════════════════════════════════════════════════════════════
local pullTimer
local function ensurePullTimer()
    if pullTimer then return pullTimer end
    pullTimer = Tim().New({
        id = "engine:pull", key = "pull", kind = "combat",
        text = "Pull", countdown = { depth = Sync.PULL_COUNTDOWN_DEPTH },
    })
    pullTimer.Category = function() return "pull" end
    return pullTimer
end
Sync._ensurePullTimer = ensurePullTimer

-- §11.4 "requires rank > 0 (or being the tank in an LFG group)". Era has no LFG
-- role, so rank is the whole rule; solo (no group) is trivially permitted so /drm
-- pull works while testing alone.
function Sync.CanBroadcastPull()
    if not Life().env.IsInGroup() then return true end
    if Sync.env.UnitIsGroupLeader("player") then return true end
    if Sync.env.UnitIsGroupAssistant("player") then return true end
    return false
end

-- Returns seconds on success; nil + reason on refusal.
--   `source`   "manual" (slash/user) | "sync" | "dbm" | "countdown" | "test"
-- Only a MANUAL pull broadcasts — a pull we received must never be re-broadcast, and
-- the test button must never reach the raid.
function Addon:StartPullTimer(seconds, source, target)
    seconds = tonumber(seconds)
    if seconds == nil then seconds = 10 end
    source = source or "manual"
    if seconds == 0 then return Addon:CancelPullTimer(source) end   -- §11.4 0 = cancel

    -- A refusal must SAY SO when a person typed the command. The reference engine's
    -- own refusals are silent, which is fine for a sync-driven pull and unhelpful for
    -- `/drm pull 1` — and slash.lua is not this wave's file to change, so the message
    -- belongs here, next to the rule it explains.
    local function refuse(reason, said)
        if source == "manual" and said and type(print) == "function" then
            print(Addon:Tag("[DRM]") .. " " .. Addon:Wrap("danger", "Pull timer refused:")
                  .. " " .. said)
        end
        return nil, reason
    end

    -- §11.4 REFUSES durations between 0 and 3 s exclusive. W1's shim silently clamped
    -- to 3; the spec refuses, and a silent clamp turns "pull in 1" into a lie.
    if seconds > 0 and seconds < Sync.PULL_MIN then
        return refuse("too_short", ("%d seconds is the minimum; use 0 to cancel."):format(Sync.PULL_MIN))
    end
    if seconds < 0 then return refuse("negative", "that is not a duration.") end
    if seconds > Sync.PULL_MAX then seconds = Sync.PULL_MAX end

    if source ~= "test" then
        if currentInstanceType() == "pvp" then
            return refuse("pvp", "not inside a battleground or arena.")
        end
        if Life():AnyEngaged() then
            return refuse("in_encounter", "a boss fight is already in progress.")
        end
    end

    local t = ensurePullTimer()
    t:Start(seconds)
    Addon.pullSource = source
    Addon.pullTarget = target
    -- §11.4: "If the sender is targeting something that is not a group member, the
    -- announcement names that target."
    local text = ("Pull in %d"):format(math.floor(seconds + 0.5))
    if target and target ~= "" then text = text .. " — " .. tostring(target) end
    if source ~= "manual" and source ~= "test" then text = text .. " (" .. tostring(source) .. ")" end
    Addon:EmitAnnounce(nil, nil, text)
    Addon:FireEngineEvent("ENGINE_PULL", seconds, source, target)
    Sync.env.FlashClientIcon()                    -- §11.4 flashes the taskbar icon
    if Addon.DLog then Addon.DLog("Pull timer started: %.0fs (%s)", seconds, tostring(source)) end

    if source == "manual" and not Sync.inbound and Sync.CanBroadcastPull() then
        Sync.Send("PT", seconds, currentInstanceId(), target)
    end
    return seconds
end

function Addon:CancelPullTimer(source)
    if pullTimer then pullTimer:Stop() end
    if Addon.StopVoiceCountdown then Addon:StopVoiceCountdown() end
    Addon.pullSource, Addon.pullTarget = nil, nil
    Addon:FireEngineEvent("ENGINE_PULL", 0, source or "cancel")
    if (source or "manual") == "manual" and not Sync.inbound and Sync.CanBroadcastPull() then
        Sync.Send("PT", 0, currentInstanceId(), nil)
    end
    return true
end

function Sync.OnPullTimer(sender, channel, seconds, zone, target)
    if sender == Sync.Me() then return drop("self", "PT", sender) end
    -- §11.4 reception filter (optional, off by default): drop pull timers whose
    -- sender is on a different map from the receiver.
    local s = Addon.db and Addon.db.settings
    if s and s.pullTimerZoneFilter and zone and zone ~= "" then
        if tonumber(zone) ~= currentInstanceId() then return drop("zone_filter", "PT", sender) end
    end
    local n = tonumber(seconds)
    if n == nil then return drop("bad_seconds", "PT", sender) end
    return withoutEcho(function()
        if n == 0 then return Addon:CancelPullTimer("sync") end
        return Addon:StartPullTimer(n, "sync", (target ~= "" and target) or nil)
    end)
end
HANDLERS.PT = Sync.OnPullTimer

-- ══════════════════════════════════════════════════════════════════════════════
--  §11.4 + §9.2 BREAK TIMER
-- ══════════════════════════════════════════════════════════════════════════════
local breakTimer
local function ensureBreakTimer()
    if breakTimer then return breakTimer end
    breakTimer = Tim().New({ id = "engine:break", key = "break", kind = "combat", text = "Break" })
    breakTimer.Category = function() return "break" end
    return breakTimer
end

local function breakAnnounce(remaining)
    local mins = math.floor((remaining or 0) / 60 + 0.5)
    Addon:EmitAnnounce(nil, nil, ("Break: %d minute%s left"):format(mins, mins == 1 and "" or "s"))
end

function Addon:StartBreakTimer(seconds, source, silent)
    seconds = tonumber(seconds)
    if seconds == nil then return nil, "bad_seconds" end
    if seconds == 0 then return Addon:CancelBreakTimer(source) end   -- §11.4 0 = cancel
    if seconds < 0 then return nil, "negative" end
    if seconds > Sync.BREAK_MAX then seconds = Sync.BREAK_MAX end    -- §11.4 60-minute maximum

    local t = ensureBreakTimer()
    t:Start(seconds)
    Sync.breakStartedAt = Sync.env.Time()
    Sync.breakDuration  = seconds

    -- §9.2: persisted to disk as duration / wallclock-at-start.
    if Addon.db then
        Addon.db.breakTimer = { duration = seconds, startedAt = Sync.breakStartedAt }
    end

    -- §11.4 announces at 10, 5, 2 and 1 minutes remaining. Zero is carried by the
    -- bar's own expiry, which the HUD already renders.
    S():Unschedule(breakAnnounce)
    for _, at in ipairs(Sync.BREAK_ANNOUNCE_AT) do
        if seconds > at then S():Schedule(seconds - at, breakAnnounce, nil, at) end
    end

    if not silent then
        -- §11.4: the "over at" wall-clock time is computed and shown.
        local overAt = Sync.env.DateAt(Sync.breakStartedAt + seconds)
        local text = ("Break: %d minute%s"):format(math.floor(seconds / 60 + 0.5),
                                                   seconds >= 120 and "s" or "")
        if overAt then text = text .. " (over at " .. overAt .. ")" end
        if source and source ~= "manual" then text = text .. " [" .. tostring(source) .. "]" end
        Addon:EmitAnnounce(nil, nil, text)
    end
    Addon:FireEngineEvent("ENGINE_BREAK", seconds, source or "manual")

    if (source or "manual") == "manual" and not Sync.inbound then
        Sync.Send("BT", seconds)
    end
    return seconds
end

function Addon:CancelBreakTimer(source)
    if breakTimer then breakTimer:Stop() end
    S():Unschedule(breakAnnounce)
    Sync.breakStartedAt, Sync.breakDuration = nil, nil
    if Addon.db then Addon.db.breakTimer = nil end
    Addon:FireEngineEvent("ENGINE_BREAK", 0, source or "cancel")
    if (source or "manual") == "manual" and not Sync.inbound then Sync.Send("BT", 0) end
    return true
end

function Addon:BreakTimeLeft()
    if not breakTimer then return nil end
    local bar = breakTimer:Get()
    if not bar then return nil end
    local left = Tim().Remaining(bar)
    if not left or left <= 0 then return nil end
    return left
end

function Sync.OnBreakTimer(sender, channel, seconds)
    if sender == Sync.Me() then return drop("self", "BT", sender) end
    -- §7.3 break timers are throttled to one per sender per second…
    local now = S():Now()
    local last = Sync.breakSeen[sender]
    if last and (now - last) < Sync.BREAK_THROTTLE then return drop("break_throttle", "BT", sender) end
    Sync.breakSeen[sender] = now
    local n = tonumber(seconds)
    if n == nil then return drop("bad_seconds", "BT", sender) end
    if n > Sync.BREAK_MAX then n = Sync.BREAK_MAX end   -- …and capped at 3600 s
    Addon.breakSource = Sync.ShortName(sender)          -- attribution for the HUD/announce
    return withoutEcho(function()
        if n == 0 then return Addon:CancelBreakTimer("sync") end
        return Addon:StartBreakTimer(n, "sync")
    end)
end
HANDLERS.BT = Sync.OnBreakTimer

-- §9.2: on the deferred startup pass the remaining time is recomputed against the
-- wall clock; if positive the timer restarts SILENTLY, otherwise the record is
-- discarded.
function Sync.RestorePersistedBreak()
    local rec = Addon.db and Addon.db.breakTimer
    if type(rec) ~= "table" then return nil, "none" end
    local left = (tonumber(rec.duration) or 0) - (Sync.env.Time() - (tonumber(rec.startedAt) or 0))
    if left and left > 0 then
        Addon:StartBreakTimer(left, "restored", true)
        return left
    end
    Addon.db.breakTimer = nil
    return nil, "expired"
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.4 VERSION CHECKING — NAG ONLY. NEVER SELF-DISABLE.
-- ══════════════════════════════════════════════════════════════════════════════
Sync.newestSeen   = nil     -- { rev, release, display, from }
Sync.newerSenders = {}      -- distinct senders reporting a newer release
Sync.newerCount   = 0
Sync.nagged       = false   -- once per session

local function sendVersionReply()
    local v = Sync.VERSION
    -- Field 6 is the reference's "force-disable revision". We ADVERTISE ours (so a
    -- reference-shaped peer's bookkeeping still works) and we PARSE the field on the
    -- way in, but acting on it is vetoed. See the header.
    Sync.Send("V", v.rev, v.release, v.display, v.rev)
end

function Sync.OnHello(sender, channel)
    if sender == Sync.Me() then return false, "self" end
    -- §7.4: every recipient schedules a V reply 3 s later, CANCELLING any previously
    -- scheduled reply, so a wave of invites produces one reply, not twenty.
    S():DelayedCall(Sync.VERSION_DEBOUNCE, sendVersionReply, Sync)
    return true, "scheduled"
end
HANDLERS.H = Sync.OnHello

function Sync.OnVersion(sender, channel, rev, release, display, forceDisableRev)
    if sender == Sync.Me() then return false, "self" end
    local r  = tonumber(release) or 0
    local rv = tonumber(rev) or 0
    Sync.peers[sender] = { rev = rv, release = r, display = display, at = S():Now() }

    -- The force-disable revision is READ so peer bookkeeping is complete, and
    -- COUNTED so the telemetry ring can show how often the reference engine would
    -- have bricked us. It is NEVER acted on. Design doc R2, owner-approved.
    local fdr = tonumber(forceDisableRev) or 0
    if fdr > Sync.VERSION.rev and r > Sync.VERSION.release then
        Sync.stats.forceDisableSeen = Sync.stats.forceDisableSeen + 1
    end

    if r <= Sync.VERSION.release then return false, "not_newer" end

    if not Sync.newestSeen or r > Sync.newestSeen.release then
        Sync.newestSeen = { rev = rv, release = r, display = display, from = sender }
    end
    if not Sync.newerSenders[sender] then
        Sync.newerSenders[sender] = true
        Sync.newerCount = Sync.newerCount + 1
    end

    -- §7.4: after 2 DISTINCT such senders the update nag is shown ONCE and a
    -- persistent reminder flag is set.
    if Sync.newerCount >= Sync.NAG_SENDERS and not Sync.nagged then
        Sync.nagged = true
        Sync.stats.nagged = Sync.stats.nagged + 1
        if Addon.db and Addon.db.settings then Addon.db.settings.updateReminder = true end
        if type(print) == "function" then
            print(Addon:Tag("[DRM]") .. " " .. Addon:Wrap("warn", "Update available:")
                .. " raiders around you are running "
                .. tostring((Sync.newestSeen and Sync.newestSeen.display) or "a newer build")
                .. " (you have " .. Sync.VERSION.display .. "). "
                .. "Raid Mechanics keeps working normally.")
        end
    end
    return true, "tracked", Sync.newerCount
end
HANDLERS.V = Sync.OnVersion

function Sync.SendHello()
    return Sync.Send("H")
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §9.1 RELOAD / LATE-JOIN TIMER RECOVERY — the whisper cascade
-- ══════════════════════════════════════════════════════════════════════════════
Sync.recovery = { active = false, asked = {}, order = {}, repliedBy = nil, startedAt = nil,
                  rearmed = false, rungs = #Sync.RECOVERY_ASK_AT }

-- Step 1: rank the group by version (highest first), then by name for determinism.
-- Candidates must be connected, a player, not a ghost, and ON THE SAME REALM —
-- cross-realm WHISPER addon messages silently fail, so they are skipped entirely.
--
-- AUDIT RM-3 (Brief N, lesson Class 4). This function's version key was PROVABLY
-- DEAD while it was called from `BeginRecovery`: `Sync.peers` is fresh-empty after
-- a /reload (new Lua state), `Sync.SendHello()` goes out on the SAME FRAME one line
-- before recovery begins, and peers answer `V` on a deliberate 3 s debounce. No
-- revision could possibly have landed, so every candidate carried `rev = -1`,
-- `a.rev ~= b.rev` was never true, and the sort collapsed permanently onto the
-- alphabetical tie-break — while the comment above went on asserting a version
-- contract. Ranking is now performed AT THE ASK (see `askTask`), by which time the
-- 7 s rung has given the hello replies four seconds to arrive, so the key means
-- what it says. RM-3 is fixed by RM-2's fix, exactly as the audit predicted.
function Sync.RankCandidates()
    local me = Sync.Me()
    local out = {}
    Life().env.ForEachGroupMember(function(u)
        local name, realm = Sync.env.UnitNameRealm(u)
        local full = Sync.FullName(name, realm)
        if not full or full == me then return false end
        if Sync.env.UnitIsConnected(u) == false then return false end
        if Life().env.UnitIsPlayer(u) == false then return false end
        if Life().env.UnitIsDeadOrGhost(u) then return false end
        if not Sync.SameRealm(full) then return false end
        local p = Sync.peers[full]
        out[#out + 1] = { name = full, rev = (p and p.rev) or -1 }
        return false
    end)
    table.sort(out, function(a, b)
        if a.rev ~= b.rev then return a.rev > b.rev end
        return a.name < b.name
    end)
    return out
end

-- Scheduled work is dispatched as `fn(arg1, …)` with no implicit self, and §3.2's
-- cancellation matches on FUNCTION IDENTITY — so both of these are plain named
-- locals, forward-declared because they refer to each other.
local askTask

-- The scheduled expiry of the "recovery in progress" flag. A named function rather
-- than the closure this used to be, so the re-arm below can Unschedule and re-issue
-- it (a fresh closure has no identity to cancel on).
local function expireTask()
    Sync.recovery.active = false
end

-- Give up early and hand the detection paths back. Reached only when the ladder has
-- run to its END with nobody asked — the original code's instinct here was right
-- ("drop the flag rather than blinding detection for 15 s"), it was just applied on
-- the wrong frame.
local function abortRecovery(why)
    Sync.recovery.active = false
    Life():SetRecovering(false)
    S():Unschedule(askTask, Sync)
    S():Unschedule(expireTask, Sync)
    if Addon.Telemetry then
        Addon.Telemetry.Write("sync.recovery", { reason = why })
    end
    return false, why
end

-- ── AUDIT RM-2 (Brief N, lesson Class 6) — THE ROSTER IS READ AT THE ASK ──────
-- `BeginRecovery` used to snapshot the candidate list synchronously, on the
-- PLAYER_ENTERING_WORLD frame, and then schedule one ask per candidate. The
-- whispers were correctly deferred to +7/10/13 s — the code already knew the login
-- seam is asynchronous — and then it read the one thing that is not ready yet.
-- Reload mid-raid: `IsInGroup()` is restored but `GetNumGroupMembers()` still
-- answers 0, the snapshot is empty, `asked == 0`, the flag is dropped and the
-- function returns "no_candidates". It has one caller and nothing retries, so the
-- player rejoins the pull with NO BARS AT ALL, silently — and this feature exists
-- for precisely that scenario.
--
-- Each rung now reads the LIVE roster when it fires. The 7/10/13 s ladder was
-- always the retry machine; it was just spending three attempts on one stale
-- answer. Three live reads, each picking the best candidate not already asked.
function askTask(ordinal)
    if not Sync.recovery.active then return false, "inactive" end
    if Sync.recovery.repliedBy then return false, "replied" end   -- step 4

    local last = (ordinal >= (Sync.recovery.rungs or #Sync.RECOVERY_ASK_AT))

    -- Class 6: an unanswered group list is not an empty group. Refuse to conclude
    -- anything from it, and re-arm instead of treating dark as "nobody is there".
    if not Life():RosterPopulated() then
        if Addon.Telemetry then
            Addon.Telemetry.Write("sync.recovery", { reason = "roster_dark", delay = ordinal })
        end
        if Sync.ReArmRecovery("roster_dark") then return false, "roster_dark" end
        if last and next(Sync.recovery.asked) == nil then return abortRecovery("no_candidates") end
        return false, "roster_dark"
    end

    local cands = Sync.RankCandidates()
    local pick
    for i = 1, #cands do
        if not Sync.recovery.asked[cands[i].name] then pick = cands[i] break end
    end
    if not pick then
        -- Nobody NEW to ask. If we have asked somebody already the raid is simply
        -- exhausted and the reply window is still running; if we have asked nobody
        -- the list read empty, which on a populated roster is a real answer — but
        -- still worth one bounded re-arm before giving the flag back.
        if next(Sync.recovery.asked) ~= nil then return false, "exhausted" end
        if Sync.ReArmRecovery("no_candidates") then return false, "no_candidates" end
        if last then return abortRecovery("no_candidates") end
        return false, "no_candidates"
    end

    Sync.recovery.asked[pick.name] = S():Now()
    Sync.recovery.order[#Sync.recovery.order + 1] = pick.name
    Sync.Whisper("RT", pick.name)
    if Addon.Telemetry then
        Addon.Telemetry.Write("sync.recovery", { reason = "request", path = pick.name, delay = ordinal })
    end
    return true, pick.name
end
Sync._askTask = askTask

-- ONE bounded re-arm (Class 6's "re-ASK on a bounded ladder", the shape Nexus
-- mesh-friends already uses). If the roster is still dark — or still reads empty —
-- when a rung fires, add exactly one more ask at RECOVERY_REARM_AT and extend the
-- suppression window far enough to cover it plus the reply-validity window. The
-- `rearmed` latch is what makes it bounded: a permanently dark roster costs one
-- extra ask and 8 s of suppression, not an unbounded ladder.
function Sync.ReArmRecovery(why)
    if not Sync.recovery.active then return false, "inactive" end
    if Sync.recovery.rearmed then return false, "already_rearmed" end
    Sync.recovery.rearmed = true

    local elapsed = S():Now() - (Sync.recovery.startedAt or S():Now())
    local delay = Sync.RECOVERY_REARM_AT - elapsed
    if delay < 0 then delay = 0 end
    Sync.recovery.rungs = (Sync.recovery.rungs or #Sync.RECOVERY_ASK_AT) + 1
    S():Schedule(delay, askTask, Sync, Sync.recovery.rungs)

    -- The absolute-deadline recovery flag EXTENDS rather than races (core_lifecycle
    -- §9.1 step 3), so re-stamping it is the whole extension.
    local span = delay + Sync.RECOVERY_REPLY_VALID
    Life():SetRecovering(true, span)
    S():Unschedule(expireTask, Sync)
    S():Schedule(span, expireTask, Sync)
    if Addon.Telemetry then
        Addon.Telemetry.Write("sync.recovery", { reason = "rearm", path = why, delay = delay })
    end
    return true, delay
end

-- Triggered on login/reload: in a group, not in PvP, and no boss currently engaged.
function Sync.BeginRecovery(reason)
    if Sync.recovery.active then return false, "already_active" end
    if not Life().env.IsInGroup() then return false, "solo" end
    if currentInstanceType() == "pvp" then return false, "pvp" end
    if Life():AnyEngaged() then return false, "already_engaged" end

    Sync.recovery = { active = true, asked = {}, order = {}, repliedBy = nil,
                      startedAt = S():Now(), reason = reason,
                      rearmed = false, rungs = #Sync.RECOVERY_ASK_AT }
    -- Step 3: the "recovery in progress" flag, 15 s, held by the LIFECYCLE so the
    -- combat-start paths it gates are the real ones.
    Life():SetRecovering(true)
    S():Schedule(Life().RECOVERY_SUPPRESS, expireTask, Sync)

    -- AUDIT RM-2: rungs are armed, NOT candidates. Nothing about the group is read
    -- on this frame — see `askTask`.
    for i, at in ipairs(Sync.RECOVERY_ASK_AT) do
        S():Schedule(at, askTask, Sync, i)
    end
    return true, #Sync.RECOVERY_ASK_AT
end

function Sync.EndRecovery(by)
    Sync.recovery.repliedBy = by
    -- Step 4: any reply invalidates the remaining requests.
    S():Unschedule(askTask, Sync)
    return true
end

-- §9.1: replies are accepted ONLY from a player we actually asked, and only within
-- 5 s of asking.
function Sync.AcceptReply(sender)
    local at = Sync.recovery.asked[sender]
    if not at then return false, "not_asked" end
    if (S():Now() - at) > Sync.RECOVERY_REPLY_VALID then return false, "stale" end
    return true
end

-- ── Responder side (`RT` received) ────────────────────────────────────────────
function Sync.OnRequestTimers(sender, channel)
    if sender == Sync.Me() then return drop("self", "RT", sender) end
    -- §7.3 timer-recovery replies are limited to one per requester per second.
    local now = S():Now()
    local last = Sync.replySeen[sender]
    if last and (now - last) < Sync.RECOVERY_REPLY_THROTTLE then
        return drop("reply_throttle", "RT", sender)
    end
    Sync.replySeen[sender] = now

    local L = Life()
    if not L:AnyEngaged() then
        -- §9.1: break timers are sent instead when the responder is not in combat.
        local left = Addon:BreakTimeLeft()
        if left then Sync.Whisper("BTR", sender, left) return 1, "break" end
        return 0, "nothing_to_send"
    end

    local sent = 0
    for i = 1, #L.engaged do
        local rt = L.engaged[i]
        -- Order matters (§9.1): CI, then VI per state variable, then TR per live bar.
        Sync.Whisper("CI", sender, rt.id, now - rt.pullTime); sent = sent + 1
        Sync.Whisper("VI", sender, rt.id, "__stage", tostring(rt.stage)); sent = sent + 1
        -- AUDIT RMS-2 (Brief G, lesson Class 8). The comment two lines above already
        -- CLAIMS an order contract — "CI, then VI per state variable, then TR per
        -- live bar" — but only the inter-group order was enforced; the per-variable
        -- walk was pairs(). A state whose meaning depends on a prior state could be
        -- applied out of sequence on the joining client. Sorting the keys is what
        -- the comment was always asserting.
        local stateKeys = {}
        for k in pairs(rt.states) do stateKeys[#stateKeys + 1] = k end
        table.sort(stateKeys)
        for _, k in ipairs(stateKeys) do
            Sync.Whisper("VI", sender, rt.id, k, tostring(rt.states[k])); sent = sent + 1
        end
        -- AUDIT RMS-1 (Brief G, lesson Class 8). Every whisper below enters
        -- Sync.Enqueue behind a 10-deep bucket refilling at 5/s. On a bar-heavy pull
        -- that bucket TRUNCATES — so the pairs() walk did not merely reorder the
        -- restore, it decided WHICH TIMERS A JOINING RAIDER GETS AT ALL, differently
        -- every attempt. Sorted MOST-URGENT-FIRST: deterministic, and the right
        -- answer besides — a bar with 4 s left is worth more to someone who just
        -- reloaded mid-pull than one with 90 s left, and if anything is going to be
        -- dropped by the bucket it should be the far-off one. `barId` breaks ties so
        -- two bars expiring on the same frame still order identically on every client.
        local restore = {}
        for barId, bar in pairs(Tim().bars) do
            if bar.encId == rt.id then
                local t = Tim().objects[bar.timerId]
                -- AI/learning timers are excluded; zero-length and expired bars skipped.
                if t and t.kind ~= "learning" and (bar.total or 0) > 0 then
                    local left = Tim().Remaining(bar)
                    if left and left > 0 then
                        restore[#restore + 1] = { id = barId, bar = bar, left = left }
                    end
                end
            end
        end
        table.sort(restore, function(a, b)
            if a.left ~= b.left then return a.left < b.left end
            return a.id < b.id
        end)
        for _, r in ipairs(restore) do
            local parts = Sync.Split(r.id)
            local args = {}
            for j = 2, #parts do args[#args + 1] = parts[j] end
            Sync.Whisper("TR", sender, rt.id, r.bar.key, r.left, r.bar.total,
                         Sync.PackArgs(args), r.bar.paused and 1 or 0)
            sent = sent + 1
        end
    end
    return sent, "combat"
end
HANDLERS.RT = Sync.OnRequestTimers

-- ── Requester side ────────────────────────────────────────────────────────────
function Sync.OnCombatInfo(sender, channel, encId, elapsed)
    if not Sync.AcceptReply(sender) then return drop("reply_rejected", "CI", sender) end
    Sync.EndRecovery(sender)
    if Life():AnyEngaged() then return drop("already_in_combat", "CI", sender) end
    local enc = Addon.encountersById[encId]
    if not enc then return drop("no_module", "CI", sender) end
    local e = (tonumber(elapsed) or 0) + Sync.Latency()
    -- Trigger "recovery" is already understood by W1's StartCombat: it marks the pull
    -- NOT record-eligible, exactly as §9.1 requires.
    local rt = withoutEcho(function() return Life():StartCombat(enc, e, "recovery") end)
    if rt then
        Sync.stats.recovered = Sync.stats.recovered + 1
        if Addon.Telemetry then
            Addon.Telemetry.Write("sync.recovery", { reason = "combat_restored", enc = encId, delay = e })
        end
    end
    return rt
end
HANDLERS.CI = Sync.OnCombatInfo

function Sync.OnVariableInfo(sender, channel, encId, key, value)
    if not Sync.AcceptReply(sender) then return drop("reply_rejected", "VI", sender) end
    Sync.EndRecovery(sender)
    local rt = Life().byId[encId]
    if not rt then return drop("not_engaged", "VI", sender) end
    -- §9.1: restore verbatim, converting "true"/"false" back to booleans.
    local v = value
    if v == "true" then v = true elseif v == "false" then v = false end
    if key == "__stage" then
        -- …and RE-FIRE the stage-change broadcast when the recovered variable is the
        -- stage, so external consumers resync.
        rt:SetStage(tonumber(value) or 1)
        return true, "stage"
    end
    rt.states[key] = v
    return true, "state"
end
HANDLERS.VI = Sync.OnVariableInfo

function Sync.OnTimerInfo(sender, channel, encId, rowKey, timeLeft, total, packedArgs, paused)
    if not Sync.AcceptReply(sender) then return drop("reply_rejected", "TR", sender) end
    Sync.EndRecovery(sender)
    local rt = Life().byId[encId]
    if not rt then return drop("not_engaged", "TR", sender) end
    local t = rt:Timer(rowKey)
    if not t then return drop("no_timer", "TR", sender) end

    local left  = tonumber(timeLeft) or 0
    local tot   = tonumber(total) or 0
    local isPaused = (paused == "1" or paused == 1 or paused == true)
    if tot <= 0 or left <= 0 then return drop("zero_length", "TR", sender) end
    local args = Sync.UnpackArgs(packedArgs)

    -- VARIANCE SURVIVES RESTORATION. §9.1 says "start at full duration then
    -- immediately update elapsed" — and §4.2's window is exactly what "full duration"
    -- means for a variance timer. So when the responder's reported total agrees with
    -- OUR declared window's maximum, we start from the DECLARED duration (min/max/
    -- variance intact) and update elapsed with a nil total, which Timer:Update
    -- deliberately treats as "do not collapse the window". Only when the totals
    -- disagree (a peer on different encounter data) do we fall back to the reported
    -- plain number, because inventing a window we cannot corroborate would be worse.
    local d = t.dur
    local declared = d and d.hasVariance and math.abs((d.max or 0) - tot) <= 0.05
    local bar
    if declared then bar = t:Start(nil, unpack(args)) else bar = t:Start(tot, unpack(args)) end
    if not bar then return drop("start_failed", "TR", sender) end

    -- §9.1: elapsed = total − timeLeft + latency; latency omitted for paused bars,
    -- which are then re-paused.
    local elapsed = tot - left + (isPaused and 0 or Sync.Latency())
    t:Update(elapsed, nil, unpack(args))
    if isPaused then t:Pause(unpack(args)) end

    if type(rt.def.onTimerRecovery) == "function" then
        pcall(rt.def.onTimerRecovery, rt, rowKey, left, tot)   -- §9.1 module hook
    end
    return bar
end
HANDLERS.TR = Sync.OnTimerInfo

function Sync.OnBreakRecovery(sender, channel, seconds)
    if not Sync.AcceptReply(sender) then return drop("reply_rejected", "BTR", sender) end
    Sync.EndRecovery(sender)
    local n = tonumber(seconds)
    if not n or n <= 0 then return drop("bad_seconds", "BTR", sender) end
    return withoutEcho(function() return Addon:StartBreakTimer(n, "recovered", true) end)
end
HANDLERS.BTR = Sync.OnBreakRecovery

Sync.HANDLERS = HANDLERS

-- ══════════════════════════════════════════════════════════════════════════════
--  ENGINE SEAM — outbound dispatch
-- ══════════════════════════════════════════════════════════════════════════════
-- W1 publishes every outbound sync intent as SYNC_SEND(subPrefix, …). This is the
-- ONLY place the engine's decisions become wire traffic; the engine core itself has
-- no idea a network exists.
function Sync.OnSendRequest(_, sub, a1, a2, a3, a4)
    if Sync.inbound then return false, "echo_suppressed" end
    if sub == "C" then
        -- (delay, encId, bossPct, trigger) -> our C also carries the instance id
        return Sync.Send("C", a1, a2, a3, a4, currentInstanceId())
    elseif sub == "EE" then
        return Sync.Send("EE", a1, a2, a3)
    elseif sub == "K" then
        return Sync.Send("K", a1, a2)
    elseif sub == "M" then
        return Sync.SendModuleSync(a1, a2)
    end
    return false, "unmapped"
end

-- ══════════════════════════════════════════════════════════════════════════════
--  BOOT
-- ══════════════════════════════════════════════════════════════════════════════
Sync.booted = false

function Sync:Boot()
    if Sync.booted then return false end
    Sync.booted = true

    for _, p in ipairs(Sync.PREFIX_LIST) do Sync.env.RegisterAddonMessagePrefix(p) end

    Addon:RegisterEngineCallback("SYNC_SEND", Sync.OnSendRequest, Sync)

    -- §2.3: a start cancels any running pull timer.
    Addon:RegisterEngineCallback("ENGINE_ENGAGE", function()
        if pullTimer and pullTimer:Get() then Addon:CancelPullTimer("engage") end
    end, Sync)

    -- §9.1 trigger + §9.2 deferred break restore, both on the login seam.
    Addon:RegisterEngineCallback("ENGINE_LOGIN", function(_, isLogin, isReload)
        Sync.RestorePersistedBreak()
        Sync.SendHello()
        Sync.BeginRecovery(isReload and "reload" or "login")
    end, Sync)

    S():AddHousekeeper(Sync.Prune, Sync)

    if type(_G.CreateFrame) == "function" then
        local f = _G.CreateFrame("Frame")
        f:RegisterEvent("CHAT_MSG_ADDON")
        f:SetScript("OnEvent", function(_, _, prefix, payload, channel, sender)
            Sync.OnAddonMessage(prefix, payload, channel, sender)
        end)
        Sync.frame = f
    end
    return true
end

-- Full reset used by the harness between fixtures.
function Sync:Reset()
    Sync.spam, Sync.corroborate, Sync.peers = {}, {}, {}
    Sync.breakSeen, Sync.replySeen = {}, {}
    Sync.queue = { ALERT = {}, NORMAL = {} }
    Sync.tokens, Sync.tokensAt, Sync.draining = Sync.BUCKET_CAP, nil, false
    Sync.sent, Sync.lastSent = 0, nil
    Sync.newestSeen, Sync.newerSenders, Sync.newerCount, Sync.nagged = nil, {}, 0, false
    Sync.recovery = { active = false, asked = {}, order = {}, repliedBy = nil,
                      rearmed = false, rungs = #Sync.RECOVERY_ASK_AT }
    Sync.inbound = false
    Sync.forbiddenTxBlocked = 0
    Sync.stats = { received = 0, dropped = 0, corroborated = 0, nagged = 0,
                   forceDisableSeen = 0, recovered = 0 }
    return true
end

return Sync
