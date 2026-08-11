--[[
    Daseeki Raid Mechanics 2.0 — telemetry ring (engine core, wave 1)

    THE THIRD-RING HOUSE PATTERN, modelled on Daseeki-Core's perf.lua ring:
      * ADDITIVE SavedVariables — exactly ONE new top-level key on the addon DB
        (`engineLog`), created lazily on the first write. No schema bump.
      * BOUNDED — a hard entry cap with a dropped-counter, so a bad night cannot
        grow the save file without limit.
      * BUILD-STAMPED — every entry carries the engine build token, so entries
        from an older build are never mistaken for current behaviour.
      * CLEARED IN PLACE — the table identity survives a clear, so nothing that
        captured a reference is left pointing at a corpse.

    WHY IT EXISTS (design doc, target architecture item 3): the reference engine
    raises a user-visible "please report this" chat line when a timer bar is
    restarted outside its declared window (ENGINE SPEC §4.3). We do not spam the
    raid — we WRITE THE OBSERVATION DOWN. This ring is the product's self-auditing
    timer dataset: after a few of Drew's raid nights it says, with numbers, which
    declared timer values are wrong.

    Entry shape for the tripwire (`timer.refresh`), which is the whole point:
        t        server time (wall clock)
        rt       GetTime() at the moment of the observation
        build    engine build token
        kind     "timer.refresh"
        enc      encounter id            \
        mod      owning module id         |  IDENTITY: what fired, in what fight
        timer    timer object id          |
        key      option/row key           |
        spell    spell id (when known)    |
        bar      bar id (identity args)   /
        stage    stage number at the time of the observation
        expMin   \
        expMax    |  EXPECTED WINDOW: what the data file promised
        expVar    |
        total    /
        obs      OBSERVED VALUE: seconds the replaced bar actually ran
        rem      remaining on the replaced bar at the instant of the restart
        delta    signed distance outside the declared window
        verdict  "early" | "early_minor" | "after_zero"
--]]

local _, Addon = ...

local T = {}
Addon.Telemetry = T

T.RING_KEY = "engineLog"
T.MAX      = 250          -- bounded ring; oldest entries are dropped
T.BUILD    = "2.1.0"      -- bumped per wave; every entry carries it

-- The enumerated kinds. A write with an unlisted kind still lands (we never drop
-- data because of a typo) but is counted, so the harness can catch drift.
T.KINDS = {
    ["timer.refresh"]     = true,  -- the early-refresh tripwire (§4.3)
    ["sched.overflow"]    = true,  -- a frame hit the drain ceiling (§3.1 + headless discipline)
    ["lifecycle.engage"]  = true,  -- which of the five paths started a fight (§2.1)
    ["lifecycle.verdict"] = true,  -- a wipe-poll verdict transition (§2.4)
    ["lifecycle.lockout"] = true,  -- a start refused by a re-engage lockout (§2.2)
    ["lifecycle.inert"]   = true,  -- an Era-inert path fired anyway (§10.22)
    ["api.validate"]      = true,  -- an encounter definition failed validation
}
T.unknownKinds = 0

-- ── AGGREGATE SUMMARIES ───────────────────────────────────────────────────────
-- The ring is bounded and every slot it spends on a repeating, uninformative event is
-- a slot a once-only observation cannot have. A subsystem that therefore COUNTS an
-- ambient event instead of writing one row per occurrence registers a provider here,
-- so the export still carries the number even though the ring does not carry the rows.
-- (Owner finding, live raid 2026-08-10: foreign-prefix addon traffic filled the ring
-- 250/250 and evicted the night's entire engine record. core_sync.lua is the first
-- provider.) Providers return an array of plain lines; a provider that throws is
-- skipped rather than taking the export down with it.
T.summaries = {}          -- ordered { name, fn }

function T.AddSummary(name, fn)
    if type(fn) ~= "function" then return false end
    for i = 1, #T.summaries do
        if T.summaries[i].name == name then T.summaries[i].fn = fn; return true end
    end
    T.summaries[#T.summaries + 1] = { name = name, fn = fn }
    return true
end

function T.SummaryLines()
    local out = {}
    for i = 1, #T.summaries do
        local ok, lines = pcall(T.summaries[i].fn)
        if ok and type(lines) == "table" then
            for j = 1, #lines do out[#out + 1] = tostring(lines[j]) end
        end
    end
    return out
end

local function nowServer()
    local f = _G.GetServerTime
    if type(f) == "function" then
        local okv, v = pcall(f)
        if okv and type(v) == "number" then return v end
    end
    if type(os) == "table" and type(os.time) == "function" then return os.time() end
    return 0
end

local function nowMono()
    local S = Addon.Sched
    if S then return S:Now() end
    local f = _G.GetTime
    if type(f) == "function" then
        local okv, v = pcall(f)
        if okv and type(v) == "number" then return v end
    end
    return 0
end

-- The saved ring. ADDITIVE: one new top-level key, created lazily on first write.
function T.Ring(create)
    local db = Addon.db or _G.DaseekiRaidMechanicsDB
    if type(db) ~= "table" then return nil end
    local r = db[T.RING_KEY]
    if type(r) ~= "table" then
        if not create then return nil end
        r = { dropped = 0 }
        db[T.RING_KEY] = r
    end
    return r
end

function T.Count()
    local r = T.Ring(false)
    return r and #r or 0
end

function T.Dropped()
    local r = T.Ring(false)
    return (r and r.dropped) or 0
end

-- IN PLACE: the SavedVariables table identity survives a clear.
function T.Clear()
    local r = T.Ring(false)
    if not r then return 0 end
    local n = #r
    for i = n, 1, -1 do r[i] = nil end
    r.dropped = 0
    return n
end

function T.IsEnabled()
    local db = Addon.db
    if type(db) ~= "table" then return true end
    local s = db.settings
    if type(s) ~= "table" then return true end
    return s.engineTelemetry ~= false     -- default ON
end

-- Append an entry. Returns the entry (so callers can assert on it) or nil when
-- telemetry is off / no DB is available yet.
function T.Write(kind, fields)
    if not T.IsEnabled() then return nil end
    if not T.KINDS[kind] then T.unknownKinds = T.unknownKinds + 1 end
    local r = T.Ring(true)
    if not r then return nil end

    local e = { t = nowServer(), rt = nowMono(), build = T.BUILD, kind = kind }
    if type(fields) == "table" then
        for k, v in pairs(fields) do
            if k ~= "t" and k ~= "rt" and k ~= "build" and k ~= "kind" then e[k] = v end
        end
    end

    local n = #r
    if n >= T.MAX then
        table.remove(r, 1)
        r.dropped = (r.dropped or 0) + 1
        n = n - 1
    end
    r[n + 1] = e

    if Addon.FireEngineEvent then Addon:FireEngineEvent("TELEMETRY", e) end
    return e
end

-- Human-readable export (the diagnostic-export house pattern). One line per
-- entry, newest last, so it can be pasted straight into a report.
local ORDER = { "enc", "mod", "timer", "key", "spell", "bar", "stage",
                "expMin", "expMax", "expVar", "total", "obs", "rem", "delta",
                "verdict", "path", "trigger", "delay", "reason", "queued", "ceiling", "n" }

function T.Export()
    local r = T.Ring(false)
    local out = {}
    out[#out + 1] = ("-- Daseeki Raid Mechanics engine log (build %s) --"):format(T.BUILD)
    -- The counted-not-recorded events, ahead of the rows, so the export is complete
    -- even when the ring holds one aggregate row for a million occurrences.
    local sums = T.SummaryLines()
    for i = 1, #sums do out[#out + 1] = "-- " .. sums[i] end
    if not r then
        out[#out + 1] = "(empty)"
        return out
    end
    if (r.dropped or 0) > 0 then
        out[#out + 1] = ("(%d older entries dropped: ring is capped at %d)"):format(r.dropped, T.MAX)
    end
    for i = 1, #r do
        local e = r[i]
        local parts = {}
        for _, k in ipairs(ORDER) do
            local v = e[k]
            if v ~= nil then
                if type(v) == "number" then
                    parts[#parts + 1] = ("%s=%s"):format(k, (("%.3f"):format(v):gsub("%.?0+$", "")))
                else
                    parts[#parts + 1] = ("%s=%s"):format(k, tostring(v))
                end
            end
        end
        out[#out + 1] = ("[%s] %-16s %s"):format(tostring(e.t), tostring(e.kind), table.concat(parts, " "))
    end
    return out
end

return T
