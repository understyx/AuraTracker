local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local PlaySoundFile = PlaySoundFile
local LSM = LibStub("LibSharedMedia-3.0")
local GetTime = GetTime
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitAffectingCombat = UnitAffectingCombat
local UnitIsDead = UnitIsDead
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local IsMounted = IsMounted
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitInVehicle = UnitInVehicle
local GetNumRaidMembers = GetNumRaidMembers
local GetNumPartyMembers = GetNumPartyMembers
local UnitExists = UnitExists
local GetTalentInfo, GetNumTalentTabs, GetNumTalents = GetTalentInfo, GetNumTalentTabs, GetNumTalents
local GetTalentTabInfo = GetTalentTabInfo
local GetGlyphSocketInfo = GetGlyphSocketInfo
local GetNumGlyphSockets = GetNumGlyphSockets
local GetSpellInfo = GetSpellInfo
local GetSpellLink = GetSpellLink
local UnitAura = UnitAura
local SendChatMessage = SendChatMessage
local UnitName = UnitName
local math_floor = math.floor
local string_format = string.format
local string_gsub = string.gsub

-- ==========================================================
-- MODULE
-- ==========================================================

local Conditionals = {}
ns.AuraTracker.Conditionals = Conditionals

-- ==========================================================
-- SOUND OPTIONS  (LibSharedMedia integration)
-- ==========================================================

-- Register built-in sounds with LibSharedMedia so they appear
-- alongside any sounds other addons register.
LSM:Register("sound", "Raid Warning", [[Sound\Interface\RaidWarning.wav]])
LSM:Register("sound", "Alarm Clock",  [[Sound\Interface\AlarmClockWarning3.wav]])
LSM:Register("sound", "Map Ping",     [[Sound\Interface\MapPing.wav]])
LSM:Register("sound", "Level Up",     [[Sound\Interface\LevelUp.wav]])
LSM:Register("sound", "PvP Queue",    [[Sound\Spells\PVPEnterQueue.wav]])
LSM:Register("sound", "Bell",         [[Sound\Spells\ShaysBell.wav]])

-- Migration map: old DB keys -> LSM names (for backward compat)
local OLD_SOUND_KEYS = {
    RAID_WARNING = "Raid Warning",
    ALARM        = "Alarm Clock",
    MAP_PING     = "Map Ping",
    LEVEL_UP     = "Level Up",
    PVP_QUEUE    = "PvP Queue",
    BELL         = "Bell",
}
Conditionals.OLD_SOUND_KEYS = OLD_SOUND_KEYS

--- Return unit tokens for the "smart group" check.
--- Priority: Raid > Party > Solo, matching WeakAuras behaviour.
--- In a raid   → raid1 .. raidN  (includes the player)
--- In a party  → "player" + party1 .. partyN
--- Solo        → { "player" }
local function GetSmartGroupUnits()
    local numRaid = GetNumRaidMembers and GetNumRaidMembers() or 0
    if numRaid > 0 then
        local units = {}
        for i = 1, numRaid do
            units[#units + 1] = "raid" .. i
        end
        return units
    end
    local numParty = GetNumPartyMembers and GetNumPartyMembers() or 0
    if numParty > 0 then
        local units = { "player" }
        for i = 1, numParty do
            units[#units + 1] = "party" .. i
        end
        return units
    end
    return { "player" }
end

--- Returns true if ANY smart-group member's stat % satisfies op/value.
--- getFunc / maxFunc are the raw API locals (e.g. UnitHealth/UnitHealthMax).
local function SmartGroupPctCheck(getFunc, maxFunc, op, value)
    for _, u in ipairs(GetSmartGroupUnits()) do
        if UnitExists(u) then
            local maxVal = maxFunc(u)
            if maxVal and maxVal > 0 then
                local pct = (getFunc(u) / maxVal) * 100
                if Conditionals:CompareValue(pct, op, value) then
                    return true
                end
            end
        end
    end
    return false
end

--- Public accessor so other modules (e.g. TrackedItem) can iterate group units.
function Conditionals:GetSmartGroupUnits()
    return GetSmartGroupUnits()
end

-- ==========================================================
-- COMPARISON HELPERS
-- ==========================================================

--- Evaluates a percentage-based condition for a unit.
--- When unit == "smart_group" the check passes if ANY group member satisfies it.
local function CheckUnitPct(unit, getFunc, maxFunc, op, value)
    if unit == "smart_group" then
        return SmartGroupPctCheck(getFunc, maxFunc, op, value)
    end
    local maxVal = maxFunc(unit)
    if not maxVal or maxVal == 0 then return false end
    local pct = (getFunc(unit) / maxVal) * 100
    return Conditionals:CompareValue(pct, op, value)
end

Conditionals.ConditionOp = {
    LT  = "<",
    LTE = "<=",
    GT  = ">",
    GTE = ">=",
    EQ  = "==",
}

function Conditionals:CompareValue(actual, op, expected)
    if not actual or not expected then return false end
    if     op == "<"  then return actual < expected
    elseif op == "<=" then return actual <= expected
    elseif op == ">"  then return actual > expected
    elseif op == ">=" then return actual >= expected
    elseif op == "==" then return actual == expected
    end
    return false
end

function Conditionals:PlaySoundForKey(key)
    if not key or key == "NONE" or key == "None" then return end
    -- Migrate old DB key format (e.g. "RAID_WARNING") to LSM name
    local lsmKey = OLD_SOUND_KEYS[key] or key
    local path = LSM:Fetch("sound", lsmKey)
    if path then
        PlaySoundFile(path)
    end
end

-- ==========================================================
-- LOAD CONDITIONS  (shared: bars + icons)
-- ==========================================================
-- These determine VISIBILITY (show/hide).
-- All must be met (AND logic) for the bar/icon to be visible.

Conditionals.LoadCheckType = {
    IN_COMBAT      = "in_combat",       -- Yes / No
    ALIVE          = "alive",           -- Alive / Dead
    HAS_VEHICLE_UI = "has_vehicle_ui",  -- Yes / No
    MOUNTED        = "mounted",         -- Yes / No
    TALENT         = "talent",          -- has a specific talent
    GLYPH          = "glyph",           -- has a specific glyph
    UNIT_HP        = "unit_hp",         -- [Unit] health % (icon-only)
    IN_GROUP       = "in_group",        -- Solo / Party / Raid / Party or Raid
    AURA           = "aura",            -- [Unit] has/missing a specific aura (by spell ID)
}

Conditionals.MAX_LOAD_CONDITIONS = 5

-- Simple yes/no values for boolean load conditions
Conditionals.YesNo = {
    ["yes"] = "Yes",
    ["no"]  = "No",
}

Conditionals.AliveValues = {
    ["alive"] = "Alive",
    ["dead"]  = "Dead",
}

Conditionals.GroupValues = {
    ["solo"]     = "Solo",
    ["party"]    = "In Party",
    ["raid"]     = "In Raid",
    ["group"]    = "In Party or Raid",
}

Conditionals.HPUnits = {
    player      = "Player",
    target      = "Target",
    focus       = "Focus",
    smart_group = "Smart Group",
}

Conditionals.AuraUnits = {
    player      = "Player",
    target      = "Target",
    smart_group = "Smart Group",
}

Conditionals.AuraValues = {
    have_aura    = "Have Aura",
    missing_aura = "Don't Have Aura",
}

