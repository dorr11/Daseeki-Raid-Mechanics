--[[
    Daseeki Raid Mechanics 2.0 — THE PLACEMENT MODEL (routing + anchors)

    Owner design, 2026-08-07. Two things live here, and they are deliberately in one
    file because neither is useful without the other:

      Addon.Route    WHICH bucket a row's output goes to.  Every timer and warning
                     row answers exactly one question — Major / Minor / Hidden /
                     Custom — and the answer is DATA (db.mechanics[key].route),
                     read at TIMER_START / WARN dispatch. When the user has not
                     answered, the answer is DERIVED from the row's own severity
                     (DBM-flavoured: adds and interrupts are Major, the rest Minor),
                     so a fresh profile is already sorted sensibly.

      Addon.Anchors  WHERE a placed thing sits. One resolver for EVERY anchor in the
                     addon — the four bucket anchors, the Specials anchor, every
                     Custom row's own anchor, and every special module's frame.
                     An anchor is one of three modes:

                       dock    docked to another anchor (the specials' default)
                       attach  SetPoint against a NAMED GAME FRAME with an offset
                               (target frame / player frame / minimap / any frame
                               the user names)
                       screen  free placement at the stored screen position

    THE FALLBACK RULE IS THE WHOLE POINT OF THE ATTACH MODE. A frame anchored to
    TargetFrame must not vanish, freeze off-screen, or error when the target dies and
    the frame hides. `Anchors.Resolve` re-asks "is the host actually there and
    visible?" on EVERY apply, and the answer "no" falls straight back to the stored
    screen position. Nothing is cached, because a cached answer is exactly the defect
    (CLIENT_ASYNC_LESSONS class 5, sticky calibration).

    LATE-CREATED FRAMES (CLIENT_ASYNC_LESSONS class 2, the Raid Prep Brief B lesson).
    A user can name a frame belonging to an addon that has not loaded yet, and the
    default UI's own frames are not all present at our load. So the watcher WATCHES
    THE OBJECT, not just the event: every host we successfully resolve gets its
    OnShow/OnHide hooked ONCE, and a host we could NOT resolve is re-evaluated on the
    ordinary settle events (ADDON_LOADED, PLAYER_ENTERING_WORLD, PLAYER_TARGET_CHANGED,
    GROUP_ROSTER_UPDATE). Re-evaluation is idempotent — it is just Resolve + SetPoint
    again — so firing it too often costs a SetPoint and firing it late still heals.

    DREW_UI_STYLE compliance:
      * Every anchor carries a LABELLED drag handle while unlocked (principle 6) —
        that is `Addon:HudAnchor`, and this file is what positions it.
      * Docked specials stack on ONE pad with no dead band (principle 4).
      * Nothing here hardcodes a colour or a font; it only computes points.
      * Layout errors surface: no pcall wraps a SetPoint below.

    SAVEDVARIABLES. Purely additive. `db.anchors[key]` is created lazily and only
    when something is actually stored; every read goes through `Anchors.Peek`, which
    NEVER creates a row. `db.mechanics[key].pos` (the screen position) and
    `db.mechanics[key].route` (the bucket) ride the tables that already exist, so
    DB_VERSION does not move and core.lua's migration chain stays a no-op.
--]]

local _, Addon = ...

-- ══════════════════════════════════════════════════════════════════════════════
--  ROUTE — which bucket a row's output goes to
-- ══════════════════════════════════════════════════════════════════════════════
local Route = {}
Addon.Route = Route

Route.ORDER  = { "major", "minor", "hidden", "custom" }
Route.VALID  = { major = true, minor = true, hidden = true, custom = true }
Route.LABEL  = {
    major  = "Major",
    minor  = "Minor",
    hidden = "Hidden",
    custom = "Custom",
}
-- One sentence per bucket, shown under the control. Principle 6: a four-way choice
-- that changes where a thing appears is not self-explanatory from its four words.
Route.HINT = {
    major  = "Big list / big centred warning. Starts large; never demoted.",
    minor  = "Normal list / ordinary announcement. Promotes to Major on the clock.",
    hidden = "Not drawn. Sounds and voice still play.",
    custom = "Its own place on screen, outside both lists.",
}

-- SEVERITY -> DEFAULT BUCKET (the owner's DBM flavour).
--
-- Colour classes are ENGINE SPEC §4.5's: 1 add, 2 AoE, 3 targeted, 4 interrupt,
-- 5 role, 6 stage, 7 user. "Boss-adds and interrupt-class rows are Major" is
-- classes 1 and 4 verbatim.
--
-- Class 7 and the three special categories are ALSO Major, and that is not an
-- extension of the rule — it is the rule the engine ALREADY enforced: §4.7 says
-- "colour-type 7 bars and explicitly-flagged bars start large and never shrink", and
-- the bar surface has always put pull / break / berserk with them. That rule used to
-- live in ui_bars.lua; this IS that rule, moved, not a second copy of it. Routing
-- them anywhere else would silently demote a pull countdown.
Route.MAJOR_COLOR    = { [1] = true, [4] = true, [7] = true }
Route.MAJOR_CATEGORY = { pull = true, ["break"] = true, berserk = true }

-- `desc` = { kind = "timer"|"warning", color =, category =, tier =, large = }
-- PURE. This is the function the harness asserts the default table against.
function Route.Severity(desc)
    if type(desc) ~= "table" then return "minor" end
    if desc.kind == "warning" then
        return (desc.tier == "special") and "major" or "minor"
    end
    if desc.large then return "major" end
    if desc.category ~= nil and Route.MAJOR_CATEGORY[desc.category] then return "major" end
    if desc.color ~= nil and Route.MAJOR_COLOR[desc.color] then return "major" end
    return "minor"
end

-- The shipped default, INCLUDING the ship-off rule: a row the encounter data ships
-- with `default = false` is Hidden by default, because "off" and "drawn somewhere"
-- are not both true. PURE.
function Route.Default(desc, shipsOff)
    if shipsOff then return "hidden" end
    return Route.Severity(desc)
end

local function mechRow(key)
    local db = Addon.db
    if type(db) ~= "table" or type(db.mechanics) ~= "table" then return nil end
    return db.mechanics[key]
end

-- TRANSIENT OVERRIDES — IN MEMORY, NEVER SAVEDVARIABLES.
--
-- Layout mode (ui_testing.lua) has to put a bar of every colour class in BOTH buckets
-- at once so a placement pass can see what a full screen looks like. Severity alone
-- cannot express that — a class-1 bar is Major by definition — and writing the
-- override to `db.mechanics[key].route` would leave a synthetic key sitting in a
-- player's profile the moment they alt-F4 out of a layout pass.
--
-- So the answer lives here, above the saved answer, in a table that does not survive a
-- reload. It is deliberately the FIRST thing `Route.Of` consults: a layout pass wants
-- its sample bars where it put them even for a key the user has an opinion about.
-- Nothing in the live path ever writes it.
Route.transient = {}

function Route.SetTransient(key, bucket)
    if not key then return nil end
    Route.transient[key] = Route.VALID[bucket] and bucket or nil
    return Route.transient[key]
end

function Route.ClearTransient()
    local n = 0
    for k in pairs(Route.transient) do Route.transient[k] = nil; n = n + 1 end
    return n
end

-- The live answer for one option key.
--
-- THE SHIP-OFF TRAP, AND WHY IT IS NOT ONE. `Route.Default` says a ship-off row is
-- Hidden. If that stood after the user ticked the row ON, the user would enable a
-- mechanic and see nothing, with a control that reads "Hidden" and no explanation.
-- So an EXPLICIT masterEnabled = true retires the ship-off part of the default and
-- the row falls back to its severity — the user turned it on, they meant to see it.
-- An explicit route always wins over both.
function Route.Of(key, desc, shipsOff)
    local tr = Route.transient[key]
    if tr and Route.VALID[tr] then return tr end
    local o = mechRow(key)
    if o and Route.VALID[o.route] then return o.route end
    if shipsOff and o and o.masterEnabled == true then shipsOff = false end
    return Route.Default(desc, shipsOff)
end

function Route.Set(key, bucket)
    if not key then return nil end
    Addon:SetMechanicOption(key, "route", Route.VALID[bucket] and bucket or nil)
    return bucket
end

-- "Back to whatever the encounter data implies" — the control's reset.
function Route.Clear(key)
    if not key then return nil end
    Addon:SetMechanicOption(key, "route", nil)
    return true
end

-- Describe a live engine bar. `class` is the RESOLVED colour (ui_bars' ClassOf
-- already folds the category fallback in), because that is the number the user sees
-- as the bar's colour and therefore the number the severity rule must read.
function Route.DescribeBar(bar, resolvedClass)
    return {
        kind     = "timer",
        color    = resolvedClass,
        category = bar and bar.category,
        large    = bar and bar.large and true or false,
    }
end

function Route.DescribeWarning(row)
    return { kind = "warning", tier = row and row.tier }
end

-- Describe a PROJECTED options row (core_api projectRow stamps this on the mech).
function Route.DescribeRow(row, kind)
    return {
        kind     = (kind == "warning") and "warning" or "timer",
        color    = row and row.color,
        category = row and (row.category or row.kind),
        tier     = row and row.tier,
        large    = row and row.large and true or false,
    }
end

-- ══════════════════════════════════════════════════════════════════════════════
--  ANCHORS — where a placed thing sits
-- ══════════════════════════════════════════════════════════════════════════════
local Anchors = {}
Addon.Anchors = Anchors

Anchors.ANCHOR_SPECIALS = "#specials"
Anchors.SPECIALS_LABEL  = "Boss specials"
Anchors.SPECIALS_POS    = { point = "CENTER", relPoint = "CENTER", x = 320, y = 40 }

-- One pad between docked specials — DREW_UI_STYLE principle 4, the same rule the
-- bar stack follows. There is no second gap anywhere in the dock.
Anchors.DOCK_PAD = 4

-- ATTACH TARGETS. `global` is the _G name we look up; `frame` means "the user names
-- it themselves". Order is the dropdown order, and it is fixed, not sorted, because
-- Screen is the answer nine times out of ten and belongs first (principle 7).
Anchors.ATTACH_ORDER = { "screen", "target", "player", "minimap", "frame" }
Anchors.ATTACH = {
    screen  = { label = "Screen (free placement)" },
    target  = { label = "Target frame",  global = "TargetFrame" },
    player  = { label = "Player frame",  global = "PlayerFrame" },
    minimap = { label = "Minimap",       global = "Minimap" },
    frame   = { label = "Custom frame\226\128\166" },
}
Anchors.ATTACH_LABEL_TO_KEY = {}
for k, v in pairs(Anchors.ATTACH) do Anchors.ATTACH_LABEL_TO_KEY[v.label] = k end

Anchors.installed = {}    -- key -> { key, frame, label, dock, defaultPos, mode }
Anchors.order     = {}    -- registration order (deterministic dock stacking)
Anchors.hooked    = {}    -- global frame name -> true (OnShow/OnHide hooked once)
Anchors.pending   = {}    -- global frame name -> true (named but not resolvable yet)

local EMPTY = {}

-- ── Storage ───────────────────────────────────────────────────────────────────
-- Peek NEVER creates. Browsing the options tree must not litter SavedVariables with
-- empty records — the same discipline Addon:GetBossStats already follows.
function Anchors.Peek(key)
    local db = Addon.db
    if type(db) ~= "table" or type(db.anchors) ~= "table" then return nil end
    local r = db.anchors[key]
    return (type(r) == "table") and r or nil
end

function Anchors.Record(key)
    local db = Addon.db
    if type(db) ~= "table" then return {} end        -- pre-Init: honest, non-persisting
    if type(db.anchors) ~= "table" then db.anchors = {} end
    local r = db.anchors[key]
    if type(r) ~= "table" then r = {}; db.anchors[key] = r end
    return r
end

-- The stored SCREEN position, read exactly the way alerts.lua has always read it.
-- This is the fallback every other mode falls back TO, so it must stay independent
-- of the anchor machinery.
function Anchors.StoredPos(key, defaultPos)
    local db = Addon.db
    local m = (type(db) == "table" and type(db.mechanics) == "table") and db.mechanics[key] or nil
    if m and type(m.pos) == "table" then return m.pos end
    return defaultPos or { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
end

-- ── Host resolution ───────────────────────────────────────────────────────────
-- A usable host is a TABLE that can be pointed at and is actually visible. Every
-- clause is a real failure mode: a garbage frame name resolves to a string or a
-- function, an addon frame may exist but be hidden, and a hidden frame's screen
-- position is not a place to put a raid warning.
function Anchors.IsUsableFrame(f)
    if type(f) ~= "table" then return false end
    if type(f.SetPoint) ~= "function" or type(f.GetPoint) ~= "function" then return false end
    if type(f.IsVisible) == "function" then return f:IsVisible() and true or false end
    if type(f.IsShown) == "function" then return f:IsShown() and true or false end
    return true
end

-- The _G name this key wants to attach to, or nil for "no attachment configured".
-- PURE over the record.
function Anchors.AttachName(rec)
    rec = rec or EMPTY
    local mode = rec.attach
    if not mode or mode == "screen" then return nil end
    local spec = Anchors.ATTACH[mode]
    if not spec then return nil end
    local name = spec.global
    if mode == "frame" then name = rec.frameName end
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return nil end
    return name
end

-- Resolve the attach host, recording a MISS so the watcher can heal it later.
function Anchors.AttachHost(key)
    local name = Anchors.AttachName(Anchors.Peek(key))
    if not name then return nil, nil end
    local f = _G[name]
    if Anchors.IsUsableFrame(f) then
        Anchors.HookHost(name, f)
        Anchors.pending[name] = nil
        return f, name
    end
    Anchors.pending[name] = true
    return nil, name
end

function Anchors.AnchorFrame(anchorKey)
    local t = Addon._hudAnchors
    return t and t[anchorKey] or nil
end

-- ── Mode ──────────────────────────────────────────────────────────────────────
-- PURE, and the reason the whole fallback rule is assertable headless: it takes the
-- three facts and returns the verdict, touching no frame.
function Anchors.ModeFor(rec, dockKey, hostPresent, attachPresent)
    rec = rec or EMPTY
    if dockKey and rec.detached ~= true and hostPresent then return "dock" end
    if attachPresent then return "attach" end
    return "screen"
end

function Anchors.ModeOf(key)
    local e = Anchors.installed[key] or EMPTY
    local dockKey = e.dock
    local dockHost = dockKey and Anchors.AnchorFrame(dockKey) or nil
    local host = Anchors.AttachHost(key)
    return Anchors.ModeFor(Anchors.Peek(key), dockKey,
                           Anchors.IsUsableFrame(dockHost), host ~= nil), dockHost, host
end

-- Vertical offset of one docked entry: the accumulated heights of the docked
-- entries registered before it, one pad apart. Deterministic (registration order,
-- never pairs()) — CLIENT_ASYNC_LESSONS class 8.
function Anchors.DockOffset(key)
    local e = Anchors.installed[key]
    if not e or not e.dock then return 0, 0 end
    local dy = 0
    for _, k in ipairs(Anchors.order) do
        if k == key then break end
        local o = Anchors.installed[k]
        if o and o.dock == e.dock and o.frame and (Anchors.Peek(k) or EMPTY).detached ~= true then
            local shown = (type(o.frame.IsShown) == "function") and o.frame:IsShown() or false
            if shown then
                local h = (type(o.frame.GetHeight) == "function") and (o.frame:GetHeight() or 0) or 0
                dy = dy - (h + Anchors.DOCK_PAD)
            end
        end
    end
    return 0, dy
end

-- THE RESOLVER. Returns mode, relativeFrame, point, relPoint, x, y.
function Anchors.Resolve(key, defaultPos)
    local mode, dockHost, host = Anchors.ModeOf(key)
    local rec = Anchors.Peek(key) or EMPTY
    if mode == "dock" then
        local ox, oy = rec.ox, rec.oy
        if ox == nil or oy == nil then ox, oy = Anchors.DockOffset(key) end
        return "dock", dockHost, rec.point or "TOP", rec.relPoint or "BOTTOM", ox, oy
    end
    if mode == "attach" then
        return "attach", host, rec.point or "CENTER", rec.relPoint or "CENTER",
               rec.ox or 0, rec.oy or 0
    end
    local e = Anchors.installed[key]
    local pos = Anchors.StoredPos(key, defaultPos or (e and e.defaultPos))
    return "screen", nil, pos.point or "CENTER", pos.relPoint or "CENTER", pos.x or 0, pos.y or 0
end

-- ── Applying ──────────────────────────────────────────────────────────────────
-- Stateless place: resolve and point, register nothing. This is what the per-frame
-- surfaces (a Custom bar, a Custom warning line) call on every refresh, which is
-- also why they re-anchor live for free.
function Anchors.Place(key, frame, defaultPos)
    if type(frame) ~= "table" or type(frame.SetPoint) ~= "function" then return nil end
    local mode, rel, p, rp, x, y = Anchors.Resolve(key, defaultPos)
    -- A user who names the frame we are about to place would create a circular
    -- anchor. Refuse it and fall back rather than let the client error every frame.
    if rel == frame then
        local pos = Anchors.StoredPos(key, defaultPos)
        mode, rel, p, rp, x, y = "screen", nil, pos.point or "CENTER", pos.relPoint or "CENTER",
                                 pos.x or 0, pos.y or 0
    end
    frame:ClearAllPoints()
    frame:SetPoint(p, rel or _G.UIParent, rp, x, y)
    return mode
end

-- Registered place: the anchor system OWNS this frame's position from now on and
-- re-applies it whenever the world changes underneath it.
function Anchors.Install(key, frame, opts)
    opts = opts or EMPTY
    local e = Anchors.installed[key]
    if not e then
        e = { key = key }
        Anchors.installed[key] = e
        Anchors.order[#Anchors.order + 1] = key
    end
    if frame then e.frame = frame end
    if opts.label      then e.label = opts.label end
    if opts.dock       then e.dock = opts.dock end
    if opts.defaultPos then e.defaultPos = opts.defaultPos end
    e.mode = Anchors.Place(key, e.frame, e.defaultPos)
    Anchors.HookDrag(key, e.frame)
    Anchors.Watch()
    return e
end

function Anchors.Forget(key)
    local e = Anchors.installed[key]
    if not e then return false end
    Anchors.installed[key] = nil
    for i, k in ipairs(Anchors.order) do
        if k == key then table.remove(Anchors.order, i) break end
    end
    return true
end

function Anchors.Reapply(key)
    local e = Anchors.installed[key]
    if not e or not e.frame then return nil end
    e.mode = Anchors.Place(key, e.frame, e.defaultPos)
    return e.mode
end

-- Idempotent by construction: it is Resolve + SetPoint again. Firing it too often
-- costs a SetPoint; firing it late still heals. That is what makes the late-frame
-- watcher safe to hang off every settle event we can name.
function Anchors.ReapplyAll()
    local n = 0
    for _, key in ipairs(Anchors.order) do
        if Anchors.Reapply(key) then n = n + 1 end
    end
    return n
end

-- ── Dragging ──────────────────────────────────────────────────────────────────
-- Class 3 (mixed coordinate spaces): GetCenter answers in the frame's OWN scale
-- space, and a SetPoint offset is applied in the ANCHORED frame's space. Converting
-- both to UI pixels and back into the anchored frame's space is the only version of
-- this that survives a user with a scale chain.
local function centerUI(f)
    if type(f) ~= "table" or type(f.GetCenter) ~= "function" then return nil end
    local cx, cy = f:GetCenter()
    if not cx then return nil end
    local s = (type(f.GetEffectiveScale) == "function" and f:GetEffectiveScale()) or 1
    return cx * s, cy * s, s
end

function Anchors.OffsetBetween(frame, host)
    local fx, fy, fs = centerUI(frame)
    local hx, hy = centerUI(host)
    if not (fx and hx) then return nil end
    if not fs or fs == 0 then fs = 1 end
    return (fx - hx) / fs, (fy - hy) / fs
end

-- Where a drag lands depends on the mode the anchor was in: a free anchor stores a
-- screen position (the fallback everything else falls back to, so it is always kept
-- current), an attached or docked one stores an OFFSET from its host.
function Anchors.SaveDrag(key, frame)
    if type(frame) ~= "table" then return nil end
    local mode, dockHost, host = Anchors.ModeOf(key)
    local target = (mode == "dock") and dockHost or ((mode == "attach") and host or nil)
    if target then
        local ox, oy = Anchors.OffsetBetween(frame, target)
        if ox then
            local rec = Anchors.Record(key)
            rec.point, rec.relPoint, rec.ox, rec.oy = "CENTER", "CENTER", ox, oy
            Anchors.Reapply(key)
            return mode
        end
    end
    if type(frame.GetPoint) == "function" then
        local p, _, rp, x, y = frame:GetPoint()
        if p then Addon:SetMechanicPos(key, p, rp, x, y) end
    end
    Anchors.Reapply(key)
    return "screen"
end

function Anchors.HookDrag(key, frame)
    if type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
    if frame._drmAnchorDragHooked then return false end
    frame._drmAnchorDragHooked = true
    frame:HookScript("OnMouseUp", function(s) Anchors.SaveDrag(key, s) end)
    return true
end

-- ── The watcher (CLIENT_ASYNC_LESSONS class 2) ────────────────────────────────
-- WATCH THE OBJECT: every host we successfully resolve gets its own OnShow/OnHide
-- hooked ONCE, so a target frame that hides re-anchors its dependants immediately
-- rather than on the next unrelated event.
function Anchors.HookHost(name, f)
    if Anchors.hooked[name] then return false end
    if type(f) ~= "table" or type(f.HookScript) ~= "function" then return false end
    Anchors.hooked[name] = true
    f:HookScript("OnShow", function() Anchors.ReapplyAll() end)
    f:HookScript("OnHide", function() Anchors.ReapplyAll() end)
    return true
end

-- …and the settle events, for the hosts that do not exist yet (an addon frame whose
-- addon loads after us, a unit frame the client creates on demand).
Anchors.WATCH_EVENTS = {
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED",
    "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED",
}

function Anchors.Watch()
    if Anchors._watcher then return false end
    if type(_G.CreateFrame) ~= "function" then return false end
    local w = _G.CreateFrame("Frame")
    Anchors._watcher = w
    w:SetScript("OnEvent", function() Anchors.ReapplyAll() end)
    for _, ev in ipairs(Anchors.WATCH_EVENTS) do w:RegisterEvent(ev) end
    return true
end

-- ── The Specials anchor ───────────────────────────────────────────────────────
-- The fifth HUD anchor. Created on demand exactly like the other four, so a user
-- with no special modules enabled never sees it and never pays for it.
function Anchors.EnsureSpecialsAnchor()
    if type(_G.CreateFrame) ~= "function" then return nil end
    return Addon:HudAnchor(Anchors.ANCHOR_SPECIALS, Anchors.SPECIALS_LABEL,
                           Anchors.SPECIALS_POS, 220, 22)
end

-- ── Attach configuration (what the options dropdowns call) ────────────────────
function Anchors.GetAttach(key)
    local rec = Anchors.Peek(key)
    return (rec and rec.attach) or "screen", rec and rec.frameName or ""
end

function Anchors.SetAttach(key, mode, frameName)
    local rec = Anchors.Record(key)
    rec.attach = (mode and mode ~= "screen") and mode or nil
    if mode == "frame" then
        rec.frameName = (type(frameName) == "string" and frameName ~= "") and frameName or nil
    end
    -- Switching modes invalidates the stored offset: an offset measured against the
    -- minimap means nothing against the target frame.
    rec.ox, rec.oy, rec.point, rec.relPoint = nil, nil, nil, nil
    Anchors.Reapply(key)
    return rec.attach or "screen"
end

function Anchors.SetFrameName(key, name)
    local rec = Anchors.Record(key)
    rec.frameName = (type(name) == "string" and name:match("^%s*(.-)%s*$") ~= "") and name or nil
    Anchors.Reapply(key)
    return rec.frameName
end

function Anchors.IsDetached(key)
    return (Anchors.Peek(key) or EMPTY).detached and true or false
end

function Anchors.SetDetached(key, on)
    local rec = Anchors.Record(key)
    rec.detached = on and true or nil
    rec.ox, rec.oy = nil, nil
    Anchors.Reapply(key)
    return rec.detached and true or false
end

-- Per-row size multiplier for a Custom row (item 3: "position, optional frame
-- attachment, size multiplier"). Bounded so a slider cannot produce an invisible or
-- screen-filling bar.
Anchors.SIZE_MIN, Anchors.SIZE_MAX = 0.5, 2.5

function Anchors.GetSize(key)
    local rec = Anchors.Peek(key)
    local v = rec and tonumber(rec.size) or 1
    if v < Anchors.SIZE_MIN then v = Anchors.SIZE_MIN end
    if v > Anchors.SIZE_MAX then v = Anchors.SIZE_MAX end
    return v
end

function Anchors.SetSize(key, v)
    v = tonumber(v) or 1
    if v < Anchors.SIZE_MIN then v = Anchors.SIZE_MIN end
    if v > Anchors.SIZE_MAX then v = Anchors.SIZE_MAX end
    local rec = Anchors.Record(key)
    rec.size = (v ~= 1) and v or nil
    return v
end

-- Reset one anchor to "wherever the addon would have put it".
function Anchors.Reset(key)
    local db = Addon.db
    if type(db) == "table" and type(db.anchors) == "table" then db.anchors[key] = nil end
    if type(db) == "table" and type(db.mechanics) == "table" and db.mechanics[key] then
        db.mechanics[key].pos = nil
    end
    Anchors.Reapply(key)
    return true
end

return Anchors
