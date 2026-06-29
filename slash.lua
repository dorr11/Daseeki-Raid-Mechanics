--[[
    Daseeki Raid Mechanics — slash commands
        /drm, /raidmech [options|test|lock|debug]
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

    elseif msg == "enable" then
        Addon.db.settings.enabled = true
        p("Alerts |cff00ff00enabled|r.")

    elseif msg == "disable" then
        Addon.db.settings.enabled = false
        p("Alerts |cffff0000disabled|r.")

    else
        p("usage: |cffffffff/drm|r [options | test | lock | debug | enable | disable]")
    end
end
