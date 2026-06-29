--[[
    Daseeki Raid Mechanics — encounter registry

    Data files (data_<raid>.lua) call Addon:RegisterRaid(def). This module keeps
    the ordered raid list, an npcID -> boss index (for combat-log detection), and
    lookup helpers used by the engine and the options UI.

    Raid def shape:
      {
        id      = "naxxramas",
        name    = "Naxxramas",
        order   = 70,
        mapID   = 533,                 -- instanceMapID for instance gating (nil = any)
        icon    = "Interface\\Icons\\...",
        bosses  = {
            { id="patchwerk", name="Patchwerk", npcIDs={16028}, mechanics={ ... } },
            ...
        },
      }

    A pseudo-boss with id "other" (Trash) is auto-appended to every raid so trash
    mechanics have a home in the UI.
--]]

local _, Addon = ...

Addon.raids     = {}    -- ordered array of raid defs
Addon.raidsById = {}    -- id -> def
Addon.npcIndex  = {}    -- npcID -> { raidId, bossId, boss }

local function ReSort()
    table.sort(Addon.raids, function(a, b)
        if (a.order or 100) == (b.order or 100) then return (a.name or "") < (b.name or "") end
        return (a.order or 100) < (b.order or 100)
    end)
end

function Addon:RegisterRaid(def)
    assert(type(def) == "table" and def.id, "RegisterRaid requires a table with an id")
    def.bosses = def.bosses or {}

    -- Ensure an "Other (Trash)" pseudo-boss exists at the end.
    local hasOther = false
    for _, b in ipairs(def.bosses) do if b.id == "other" then hasOther = true break end end
    if not hasOther then
        def.bosses[#def.bosses + 1] = { id = "other", name = "Other (Trash)", npcIDs = {}, mechanics = {} }
    end

    -- (Re)register: replace any prior def with the same id.
    if not Addon.raidsById[def.id] then
        Addon.raids[#Addon.raids + 1] = def
    else
        for i, r in ipairs(Addon.raids) do
            if r.id == def.id then Addon.raids[i] = def break end
        end
    end
    Addon.raidsById[def.id] = def
    ReSort()

    -- Build the npcID -> boss index.
    for _, boss in ipairs(def.bosses) do
        for _, npcID in ipairs(boss.npcIDs or {}) do
            Addon.npcIndex[npcID] = { raidId = def.id, bossId = boss.id, boss = boss }
        end
    end
    return def
end

function Addon:GetRaids() return Addon.raids end
function Addon:GetRaid(id) return Addon.raidsById[id] end

function Addon:GetBoss(raidId, bossId)
    local r = Addon.raidsById[raidId]
    if not r then return nil end
    for _, b in ipairs(r.bosses) do
        if b.id == bossId then return b end
    end
    return nil
end

-- Look up which boss an npcID belongs to (combat-log detection).
function Addon:GetBossByNpcID(npcID)
    local hit = Addon.npcIndex[npcID]
    if hit then return hit.raidId, hit.bossId, hit.boss end
    return nil
end

-- ── Stub raids ─────────────────────────────────────────────────────────────────
-- Every Classic Era raid is registered so the UI shows the full list. Naxxramas is
-- populated by data_naxxramas.lua; the rest start empty and are filled later against
-- the same format. instanceMapIDs are the live Classic Era values.
-- `size` (20/40) marks a real raid instance; the options UI shows one section tab per
-- sized raid. World Bosses has no size (not a 20/40 raid) so it's excluded from the tabs.
local STUBS = {
    { id = "moltencore", name = "Molten Core",        order = 10, mapID = 409, size = 40, icon = "Interface\\Icons\\Spell_Fire_LavaSpawn" },
    { id = "onyxia",     name = "Onyxia's Lair",      order = 20, mapID = 249, size = 40, icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Black" },
    { id = "bwl",        name = "Blackwing Lair",     order = 30, mapID = 469, size = 40, icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
    { id = "zg",         name = "Zul'Gurub",          order = 40, mapID = 309, size = 20, icon = "Interface\\Icons\\INV_Misc_IdolOfHakkar" },
    { id = "aq20",       name = "Ruins of Ahn'Qiraj", order = 50, mapID = 509, size = 20, icon = "Interface\\Icons\\INV_Misc_AhnQirajTrinket_04" },
    { id = "aq40",       name = "Temple of Ahn'Qiraj",order = 60, mapID = 531, size = 40, icon = "Interface\\Icons\\INV_Misc_QirajiCrystal_05" },
    { id = "worldbosses",name = "World Bosses",        order = 80, mapID = nil, icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Green" },
}
for _, s in ipairs(STUBS) do
    Addon:RegisterRaid({ id = s.id, name = s.name, order = s.order, mapID = s.mapID, size = s.size, icon = s.icon, bosses = {} })
end
