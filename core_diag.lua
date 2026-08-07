--[[
    Daseeki Raid Mechanics 2.0 — engine diagnostics (wave 5)

    THE OWNER'S MEASURING INSTRUMENTS. Three surfaces that are neither engine logic
    nor presentation, and that Drew actively uses on raid nights:

    1. THE COMBAT-LOG DEBUG CAPTURE (`/drm debuglog`). A SavedVariables-backed line
       log with per-sitting SESSIONS, finalized and tagged with the raid on exit.
       This is how a timer value gets MEASURED rather than guessed — it predates the
       2.0 rebuild and survives it unchanged.
    2. AUTO-DEBUG + THE DEBUG-ONLY INDICATOR. The policy that turns capture on by
       itself inside a 20/40-man raid, and the on-screen banner that makes "all your
       alerts are deliberately silenced" impossible to leave on by accident.
    3. KILL-STATISTICS TEXT. The readable projection of `db.stats`, which the options
       boss panels and `/drm stats` both render.

    WHERE THIS CAME FROM (W5 scaffold retirement). All three were tenants of the
    scrapped engine.lua, were re-seated in core_boot.lua during the wave-1
    demolition, and sat there through W4 because core_boot.lua was the file where
    homeless things lived. It is not scaffolding any more — the design doc's rule is
    that core_boot.lua is GONE as a scaffold by W5 — so the diagnostics were given
    an honest home of their own rather than being left as the majority tenant of a
    file named "boot".

    RELATIONSHIP TO core_telemetry.lua: different instrument, different consumer.
    The telemetry ring is the ENGINE's self-audit (bounded, build-stamped, one
    additive SavedVariables key, read by the arbitration viewer). This file is the
    OWNER's raw capture (unbounded-until-trimmed, session-tagged, read by a human
    pasting it into a report). Neither replaces the other.
--]]

local _, Addon = ...

-- Resolved at load: core_diag.lua loads AFTER core_sched.lua and core_lifecycle.lua
-- (see the .toc chain), so both are real by the time this line runs.
local Life  = Addon.Lifecycle
local Sched = Addon.Sched

-- ══════════════════════════════════════════════════════════════════════════════
--  DEBUG LOG (SavedVariables-backed; sessions finalized on raid exit / logout)
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
--  AUTO-DEBUG + DEBUG-ONLY INDICATOR
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
--  KILL-STATISTICS TEXT (reads db.stats; never creates entries)
-- ══════════════════════════════════════════════════════════════════════════════
local function FmtStatsTime(secs)
    secs = math.floor((secs or 0) + 0.5)
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end
Addon.FmtStatsTime = FmtStatsTime

-- W5 (lesson Class 8): the walk is SORTED. This text is pasted into reports and
-- compared between sittings; a raid list that reshuffles itself between two runs of
-- the same command is unreadable as a diff. Zones come out in the options tree's
-- progression order when the tree is available, alphabetically otherwise.
local function zoneRank(rid)
    for i, z in ipairs(Addon.zones or {}) do
        if z.id == rid then return z.order or (900 + i) end
    end
    return 999
end

function Addon:BuildStatsText(raidId)
    local stats = (Addon.db and Addon.db.stats) or {}
    local rids = {}
    for rid in pairs(stats) do
        if not raidId or rid == raidId then rids[#rids + 1] = rid end
    end
    table.sort(rids, function(a, b)
        local ra, rb = zoneRank(a), zoneRank(b)
        if ra ~= rb then return ra < rb end
        return tostring(a) < tostring(b)
    end)

    local out = {}
    for _, rid in ipairs(rids) do
        out[#out + 1] = "== " .. tostring(rid) .. " =="
        local bids = {}
        for bid in pairs(stats[rid]) do bids[#bids + 1] = bid end
        table.sort(bids, function(a, b) return tostring(a) < tostring(b) end)
        for _, bid in ipairs(bids) do
            local s = stats[rid][bid]
            if (s.kills or 0) > 0 or (s.wipes or 0) > 0 then
                out[#out + 1] = string.format("  %-24s %d kill(s), %d wipe(s)%s",
                    tostring(bid), s.kills or 0, s.wipes or 0,
                    s.bestTime and ("  best " .. FmtStatsTime(s.bestTime)) or "")
            end
        end
    end
    if #out == 0 then return "No recorded kills yet." end
    return table.concat(out, "\n")
end

return true
