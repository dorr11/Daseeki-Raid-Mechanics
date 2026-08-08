--[[
    Daseeki Raid Mechanics — slash commands
        /drm, /raidmech [options|pull|stats|test|lock|debug]
--]]

local _, Addon = ...

local function p(msg) print(Addon:Tag("[DRM]") .. " " .. msg) end
-- Local token-color shorthands (Field Ledger palette with Core; legacy literals without).
local function W(token, text) return Addon:Wrap(token, text) end

SLASH_DASEEKIRM1 = "/drm"
SLASH_DASEEKIRM2 = "/raidmech"
SlashCmdList["DASEEKIRM"] = function(msg)
    msg = strtrim(msg or ""):lower()

    if msg == "" or msg == "options" or msg == "config" then
        if _G.DaseekiSuite then
            DaseekiSuite:Open("raidmechanics")
        else
            p("Install " .. W("text", "Daseeki Core") .. " for the options window.")
        end

    elseif msg == "unlock" or msg == "test" then
        p("Placement: " .. W("text", "/drm layout") .. " fills every list and keeps it filled while you drag."
          .. " Per boss: open " .. W("text", "/drm") .. " options and press " .. W("text", "Test this boss")
          .. " at the top of its page; " .. W("text", "Play") .. " beside any row fires that row alone.")

    elseif msg == "lock" then
        if Addon.LockAll then Addon:LockAll() end
        Addon:HideHudAnchors()
        p("Frames " .. W("danger", "locked") .. ".")

    elseif msg == "debug" then
        Addon.debug = not Addon.debug
        p("Debug capture " .. (Addon.debug and (W("ok", "ON") .. " — boss casts and monster yells/emotes will print.") or (W("danger", "OFF") .. ".")))

    elseif msg == "debugonly" then
        local v = not Addon.db.settings.debugOnly
        Addon.db.settings.debugOnly = v
        if Addon.UpdateAutoDebug then Addon:UpdateAutoDebug() end
        p("Debug Only " .. (v and (W("ok", "ON") .. " — all mechanic output silenced; combat events log while in 20/40-man raids.") or (W("danger", "OFF") .. " — mechanics resumed.")))

    elseif msg == "log" then
        local DS = _G.DaseekiSuite
        if not (DS and DS.ShowTextDialog) then p("Install " .. W("text", "Daseeki Core") .. " to view the log.") return end
        local n = Addon:DebugLogLineCount()
        if n == 0 then
            p("No debug log captured yet. Enable " .. W("text", "debug") .. " or " .. W("text", "debugonly") .. " and pull a boss first.")
        else
            DS.ShowTextDialog("DRM Debug Log (" .. n .. " lines, all sessions)", Addon:BuildFullDebugLogText(), true)
        end

    elseif msg == "savelog" then
        Addon.FinalizeDebugSession("manual save")
        p("Current sitting saved as a session (if it had any data).")

    elseif msg == "clearlog" then
        if Addon.db then Addon.db.debugLive = {} end
        p("Current (live) debug log cleared. Past saved sessions are untouched -- use " .. W("text", "/drm clearsessions") .. " to wipe those too.")

    elseif msg == "clearsessions" then
        if Addon.db then Addon.db.debugSessions = {} end
        p("All saved debug sessions cleared.")

    elseif msg == "pull" or msg:match("^pull%s") then
        -- "/drm pull [N]" starts an N-second countdown (default 10, clamped 3..60
        -- by StartPullTimer); "0" or "cancel" aborts a running one.
        local arg = msg:match("^pull%s+(%S+)")
        if arg == "cancel" or arg == "0" then
            Addon:CancelPullTimer()
            p("Pull timer " .. W("danger", "cancelled") .. ".")
        else
            Addon:StartPullTimer(tonumber(arg) or 10, "manual")
        end

    -- ENGINE SPEC §11.7 demo mode, and the DREW_UI_STYLE rule that every visual
    -- system we build ships a debug affordance: "/drm demo" renders the whole
    -- wave-2 surface out of combat — one bar of every colour class, a variance bar,
    -- a count bar, a pull countdown, and one line of every warning tier — so a
    -- placement pass never needs a live boss.
    elseif msg == "demo" then
        if Addon.Bars then Addon.Bars.EnsureAnchors() end
        if Addon.Warnings then Addon.Warnings.EnsureAnchors() end
        Addon:ShowHudAnchors()
        local bars = Addon.Bars and Addon.Bars.Demo() or 0
        local warns = Addon.Warnings and Addon.Warnings.Demo() or 0
        p(("Demo: %d bars, %d warnings; every HUD anchor is labelled and draggable. Use %s to clear.")
            :format(bars, warns, W("text", "/drm demo off")))

    elseif msg == "demo off" or msg == "demooff" then
        local n = Addon.Bars and Addon.Bars.StopDemo() or 0
        if Addon.Warnings then Addon.Warnings.Reset() end
        Addon:HideHudAnchors()
        p(("Demo cleared (%d bars stopped)."):format(n))

    -- LAYOUT MODE (testing suite, feature 3). The persistent sibling of `demo`: `demo`
    -- is the one-shot quick version and stays exactly what it is; this one populates
    -- EVERYTHING — every colour class in BOTH buckets, both warning tiers, a docked
    -- special sample — and KEEPS it alive while the anchors are dragged, refreshing as
    -- placement changes. Typing it again turns it off and restores a clean screen.
    elseif msg == "layout" or msg == "layout on" or msg == "layout off" then
        local Tst = Addon.Testing
        if not Tst then p("The testing suite is not loaded.") return end
        local want
        if msg == "layout on" then want = true elseif msg == "layout off" then want = false end
        local on, why = Tst.Layout(want)
        if why == "engaged" then
            p("Layout mode " .. W("danger", "refused") .. " — a boss fight is in progress.")
        elseif on then
            p("Layout mode " .. W("ok", "ON") .. " — every bar list, both warning tiers and a"
              .. " docked special are populated and will stay that way. Drag the labelled"
              .. " handles; " .. W("text", "/drm layout") .. " again to exit.")
        else
            p("Layout mode " .. W("danger", "OFF") .. " — screen restored.")
        end

    -- COMPRESSED PLAYBACK (testing suite, feature 4). `/drm playback <boss> [speed]`.
    elseif msg == "playback" or msg:match("^playback%s") then
        local Tst = Addon.Testing
        if not Tst then p("The testing suite is not loaded.") return end
        local rest = msg:match("^playback%s+(.+)$")
        if not rest then
            p("usage: " .. W("text", "/drm playback <boss> [speed]")
              .. " — e.g. " .. W("text", "/drm playback heigan 5") .. ".")
            return
        end
        -- The trailing number is the speed when there is one; everything else is the
        -- boss reference, so "four horsemen 8" parses the way a person would read it.
        local ref, spd = rest:match("^(.-)%s+([%d%.]+)$")
        if not ref then ref, spd = rest, nil end
        local encId, used = Tst.Playback(ref, tonumber(spd))
        if not encId then
            if used == "engaged" then
                p("Playback " .. W("danger", "refused") .. " — a boss fight is in progress.")
            else
                p("No encounter matches " .. W("text", ref) .. ".")
            end
        else
            p(("Playing back %s at %s. %s to end it early."):format(
                W("text", encId), W("ok", used .. "x"), W("text", "/drm stop")))
        end

    -- One word that ends whatever the testing suite is doing.
    elseif msg == "stop" or msg == "test stop" then
        local Tst = Addon.Testing
        if Tst and Tst.Stop("slash") then
            p("Test " .. W("danger", "stopped") .. " — bars swept, warnings cleared.")
        else
            p("Nothing to stop.")
        end

    -- DATA VALIDATION (testing suite, feature 6). Patch-day insurance: every spell id
    -- in all 65 encounters through the live client, plus icons, sounds and voice cues.
    elseif msg == "validate" then
        local Tst = Addon.Testing
        if not Tst then p("The testing suite is not loaded.") return end
        local r = Tst.RunValidate()
        if r.suspects > 0 then
            p(("%s %d SUSPECT spell id(s) — those rows can never fire on this client."):format(
                W("danger", "Validation:"), r.suspects))
        end

    -- Just the anchors, no demo content: for nudging a placement mid-session.
    elseif msg == "anchors" then
        if Addon.Bars then Addon.Bars.EnsureAnchors() end
        if Addon.Warnings then Addon.Warnings.EnsureAnchors() end
        p(("HUD anchors %s (%d shown). %s to put them away."):format(
            W("ok", "unlocked"), Addon:ShowHudAnchors(), W("text", "/drm lock")))

    elseif msg == "stats" then
        local DS = _G.DaseekiSuite
        local text = Addon:BuildStatsText()
        if DS and DS.ShowTextDialog then
            DS.ShowTextDialog("DRM Boss Statistics", text, true)
        else
            -- No Daseeki Core: dump to chat line by line (the blob can be long).
            for line in (text .. "\n"):gmatch("([^\n]*)\n") do
                if line ~= "" then p(line) end
            end
        end

    -- W5: the early-refresh tripwire's ring, made readable in-game. This is the
    -- ARBITRATION INSTRUMENT — the thing that says which shipped timer value is
    -- wrong, with numbers from Drew's own raids — so it needs a one-word way in that
    -- does not depend on the hub being installed.
    elseif msg == "telemetry" or msg == "timers" then
        Addon:ShowTelemetryReport()

    elseif msg == "telemetry raw" then
        local DS = _G.DaseekiSuite
        local text = table.concat(Addon.Telemetry.Export(), "\n")
        if DS and DS.ShowTextDialog then
            DS.ShowTextDialog("DRM Engine Log (raw)", text, true)
        else
            for line in (text .. "\n"):gmatch("([^\n]*)\n") do
                if line ~= "" then p(line) end
            end
        end

    elseif msg == "telemetry clear" then
        local n = Addon.Telemetry.Clear()
        if Addon.RefreshTelemetryLine then Addon:RefreshTelemetryLine() end
        p(("Timer telemetry cleared (%d observation%s)."):format(n, n == 1 and "" or "s"))

    elseif msg == "enable" then
        Addon.db.settings.enabled = true
        p("Alerts " .. W("ok", "enabled") .. ".")

    elseif msg == "disable" then
        Addon.db.settings.enabled = false
        p("Alerts " .. W("danger", "disabled") .. ".")

    else
        p("usage: " .. W("text", "/drm") .. " [options | pull <sec> | pull cancel | demo | demo off | layout | playback <boss> [speed] | stop | validate | anchors | stats | telemetry | telemetry raw | telemetry clear | test | lock | debug | debugonly | log | savelog | clearlog | clearsessions | enable | disable]")
    end
end
