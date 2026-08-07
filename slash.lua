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
        p("Open " .. W("text", "/drm") .. " options and use the " .. W("text", "Unlock frames") .. " checkbox (top) to drag a boss's frames into place.")

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
        p(("Demo: %d bars, %d warnings; the four HUD anchors are labelled and draggable. Use %s to clear.")
            :format(bars, warns, W("text", "/drm demo off")))

    elseif msg == "demo off" or msg == "demooff" then
        local n = Addon.Bars and Addon.Bars.StopDemo() or 0
        if Addon.Warnings then Addon.Warnings.Reset() end
        Addon:HideHudAnchors()
        p(("Demo cleared (%d bars stopped)."):format(n))

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

    elseif msg == "enable" then
        Addon.db.settings.enabled = true
        p("Alerts " .. W("ok", "enabled") .. ".")

    elseif msg == "disable" then
        Addon.db.settings.enabled = false
        p("Alerts " .. W("danger", "disabled") .. ".")

    else
        p("usage: " .. W("text", "/drm") .. " [options | pull <sec> | pull cancel | demo | demo off | anchors | stats | test | lock | debug | debugonly | log | savelog | clearlog | clearsessions | enable | disable]")
    end
end
