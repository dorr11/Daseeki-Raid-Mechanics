--[[
    Daseeki Raid Mechanics — slash commands
        /drm, /raidmech [options|pull|stats|test|lock|debug]
--]]

local _, Addon = ...

local function p(msg) print("|cff66ccff[DRM]|r " .. msg) end

SLASH_DASEEKIRM1 = "/drm"
SLASH_DASEEKIRM2 = "/raidmech"
SlashCmdList["DASEEKIRM"] = function(msg)
    msg = strtrim(msg or ""):lower()

    if msg == "" or msg == "options" or msg == "config" then
        if _G.DaseekiSuite then
            DaseekiSuite:Open("raidmechanics")
        else
            p("Install |cffffffffDaseeki Core|r for the options window.")
        end

    elseif msg == "unlock" or msg == "test" then
        p("Open |cffffffff/drm|r options and use the |cffffffffUnlock frames|r checkbox (top) to drag a boss's frames into place.")

    elseif msg == "lock" then
        if Addon.LockAll then Addon:LockAll() end
        p("Frames |cffff0000locked|r.")

    elseif msg == "debug" then
        Addon.debug = not Addon.debug
        p("Debug capture " .. (Addon.debug and "|cff00ff00ON|r — boss casts and monster yells/emotes will print." or "|cffff0000OFF|r."))

    elseif msg == "debugonly" then
        local v = not Addon.db.settings.debugOnly
        Addon.db.settings.debugOnly = v
        if Addon.UpdateAutoDebug then Addon:UpdateAutoDebug() end
        p("Debug Only " .. (v and "|cff00ff00ON|r — all mechanic output silenced; combat events log while in 20/40-man raids." or "|cffff0000OFF|r — mechanics resumed."))

    elseif msg == "log" then
        local DS = _G.DaseekiSuite
        if not (DS and DS.ShowTextDialog) then p("Install |cffffffffDaseeki Core|r to view the log.") return end
        local n = Addon:DebugLogLineCount()
        if n == 0 then
            p("No debug log captured yet. Enable |cffffffffdebug|r or |cffffffffdebugonly|r and pull a boss first.")
        else
            DS.ShowTextDialog("DRM Debug Log (" .. n .. " lines, all sessions)", Addon:BuildFullDebugLogText(), true)
        end

    elseif msg == "savelog" then
        Addon.FinalizeDebugSession("manual save")
        p("Current sitting saved as a session (if it had any data).")

    elseif msg == "clearlog" then
        if Addon.db then Addon.db.debugLive = {} end
        p("Current (live) debug log cleared. Past saved sessions are untouched -- use |cffffffff/drm clearsessions|r to wipe those too.")

    elseif msg == "clearsessions" then
        if Addon.db then Addon.db.debugSessions = {} end
        p("All saved debug sessions cleared.")

    elseif msg == "pull" or msg:match("^pull%s") then
        -- "/drm pull [N]" starts an N-second countdown (default 10, clamped 3..60
        -- by StartPullTimer); "0" or "cancel" aborts a running one.
        local arg = msg:match("^pull%s+(%S+)")
        if arg == "cancel" or arg == "0" then
            Addon:CancelPullTimer()
            p("Pull timer |cffff0000cancelled|r.")
        else
            Addon:StartPullTimer(tonumber(arg) or 10, "manual")
        end

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
        p("Alerts |cff00ff00enabled|r.")

    elseif msg == "disable" then
        Addon.db.settings.enabled = false
        p("Alerts |cffff0000disabled|r.")

    else
        p("usage: |cffffffff/drm|r [options | pull <sec> | pull cancel | stats | test | lock | debug | debugonly | log | savelog | clearlog | clearsessions | enable | disable]")
    end
end
