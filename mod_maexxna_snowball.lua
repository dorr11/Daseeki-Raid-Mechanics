--[[
    Module — Maexxna "Snowball" timer (ported from WeakAura "[Maexxna] Snowball timer")

    The WA shows a 5s radial countdown + sound at ~11s and ~51s into the fight (it
    keys off ENCOUNTER_START). We start on engage and warn at ~11s, then on the
    Web Spray ~40s cadence (11, 51, 91, …) so it keeps warning for the whole fight.
    Reuses the addon's styled alert (icon style) so it inherits placement.
--]]

local _, Addon = ...

local KEY     = "naxxramas:maexxna:snowball_mod"
local MECHDEF = {
    name        = "Snowball",
    icon        = "Interface\\Icons\\Spell_Frost_FrostBolt02",
    style       = "icon",
    barDuration = 5,
    sound       = "ding",
    warningText = "Snowball!",
}

local timers = {}

local function fire(force) Addon:FireAlert(KEY, MECHDEF, force) end

local function cancel()
    for _, t in ipairs(timers) do if t and t.Cancel then t:Cancel() end end
    wipe(timers)
end

Addon:RegisterModule({
    id = "maexxna_snowball", raidId = "naxxramas", bossId = "maexxna",
    name = "Snowball Timer (WA)",
    desc = "On pull, a 5s radial countdown + sound before each Snowball (Web Spray): ~11s, then every ~40s.",
    defaults = { enabled = false },
    placeKey = KEY, placeDef = MECHDEF,

    Start = function()
        cancel()
        timers[1] = C_Timer.NewTimer(11, function() fire(false) end)
        timers[2] = C_Timer.NewTimer(51, function()
            fire(false)
            timers[3] = C_Timer.NewTicker(40, function() fire(false) end)
        end)
    end,

    Stop = function() cancel() end,

    Test = function() fire(true) end,
})
