local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local PlaySoundFile = PlaySoundFile
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
local GetTalentInfo, GetNumTalentTabs, GetNumTalents = GetTalentInfo, GetNumTalentTabs, GetNumTalents
local GetTalentTabInfo = GetTalentTabInfo
local GetGlyphSocketInfo = GetGlyphSocketInfo
local GetSpellInfo = GetSpellInfo

-- ==========================================================
-- MODULE
-- ==========================================================

local Conditionals = {}
ns.AuraTracker.Conditionals = Conditionals

-- ==========================================================
-- SOUND OPTIONS
-- ==========================================================

Conditionals.SoundOptions = {
    NONE         = { label = "None",         file = nil },
    RAID_WARNING = { label = "Raid Warning", file = [[Sound\Interface\RaidWarning.wav]] },
    ALARM        = { label = "Alarm Clock",  file = [[Sound\Interface\AlarmClockWarning3.wav]] },
    MAP_PING     = { label = "Map Ping",     file = [[Sound\Interface\MapPing.wav]] },
    LEVEL_UP     = { label = "Level Up",     file = [[Sound\Interface\LevelUp.wav]] },
    PVP_QUEUE    = { label = "PvP Queue",    file = [[Sound\Spells\PVPEnterQueue.wav]] },
    BELL         = { label = "Bell",         file = [[Sound\Spells\ShaysBell.wav]] },
}

-- ==========================================================
-- COMPARISON HELPERS
-- ==========================================================

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
    if not key or key == "NONE" then return end
    local soundData = self.SoundOptions[key]
    if soundData and soundData.file then
        PlaySoundFile(soundData.file)
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
    player = "Player",
    target = "Target",
    focus  = "Focus",
}

--- Check one load condition.
function Conditionals:CheckLoadCondition(cond)
    local check = cond.check

    if check == "in_combat" then
        local inCombat = not not UnitAffectingCombat("player")
        return (cond.value == "yes") == inCombat

    elseif check == "alive" then
        local isDead = not not UnitIsDeadOrGhost("player")
        if cond.value == "alive" then return not isDead end
        return isDead

    elseif check == "has_vehicle_ui" then
        local hasUI = (UnitHasVehicleUI and UnitHasVehicleUI("player"))
                   or (UnitInVehicle and UnitInVehicle("player"))
                   or false
        return (cond.value == "yes") == (not not hasUI)

    elseif check == "mounted" then
        local mounted = not not (IsMounted and IsMounted())
        return (cond.value == "yes") == mounted

    elseif check == "talent" then
        local talentKey = cond.talentKey
        if not talentKey then return false end
        local maxTalents = MAX_NUM_TALENTS or 30
        local numTabs = GetNumTalentTabs and GetNumTalentTabs() or 0
        if numTabs == 0 then return false end
        local tab = math.ceil(talentKey / maxTalents)
        local talentIndex = talentKey - (tab - 1) * maxTalents
        if tab < 1 or tab > numTabs then return false end
        local _, _, _, _, rank = GetTalentInfo(tab, talentIndex)
        local hasRank = rank and rank > 0
        if cond.talentState == false then
            return not hasRank
        end
        return not not hasRank

    elseif check == "glyph" then
        local glyphSpellId = cond.glyphSpellId
        if not glyphSpellId then return false end
        -- Scan all glyph sockets
        for i = 1, 6 do
            local enabled, glyphType, glyphTooltipIndex, glyphSpell, icon = GetGlyphSocketInfo(i)
            if enabled and glyphSpell == glyphSpellId then
                return true
            end
        end
        return false

    elseif check == "unit_hp" then
        local unit = cond.unit or "target"
        local maxHP = UnitHealthMax(unit)
        if not maxHP or maxHP == 0 then return false end
        local pct = (UnitHealth(unit) / maxHP) * 100
        return self:CompareValue(pct, cond.op, cond.value)

    elseif check == "in_group" then
        local inRaid = GetNumRaidMembers and (GetNumRaidMembers() > 0) or false
        local inParty = GetNumPartyMembers and (GetNumPartyMembers() > 0) or false
        local expected = cond.value or "group"
        if expected == "solo" then return (not inRaid) and (not inParty) end
        if expected == "party" then return inParty and (not inRaid) end
        if expected == "raid" then return inRaid end
        if expected == "group" then return inRaid or inParty end
        return false
    end

    return true  -- unknown check type => pass
end

--- Check all load conditions (AND logic). All must pass for visibility.
function Conditionals:CheckAllLoadConditions(condList)
    if not condList or #condList == 0 then
        return true
    end
    for _, cond in ipairs(condList) do
        if not self:CheckLoadCondition(cond) then
            return false
        end
    end
    return true
end

-- ==========================================================
-- ACTION CONDITIONALS  (icon-only)
-- ==========================================================
-- These trigger ACTIONS (glow, sound) on an icon.
-- Each condition is evaluated independently; sounds on transition.

Conditionals.ActionCheckType = {
    UNIT_HP        = "unit_hp",      -- [Unit] HP %
    UNIT_POWER     = "unit_power",   -- [Unit] Power %  (mana/rage/energy/runic)
    REMAINING      = "remaining",    -- aura/cooldown remaining seconds
    STACKS         = "stacks",       -- stack count
}

Conditionals.MAX_ACTION_CONDITIONS = 3

Conditionals.PowerUnits = {
    player = "Player",
    target = "Target",
    focus  = "Focus",
}

--- Check one action condition.
--- `item` is the TrackedItem for remaining/stacks checks.
function Conditionals:CheckActionCondition(cond, item)
    local check = cond.check

    if check == "unit_hp" then
        local unit = cond.unit or "target"
        local maxHP = UnitHealthMax(unit)
        if not maxHP or maxHP == 0 then return false end
        local pct = (UnitHealth(unit) / maxHP) * 100
        return self:CompareValue(pct, cond.op, cond.value)

    elseif check == "unit_power" then
        local unit = cond.unit or "player"
        local maxPow = UnitPowerMax(unit)
        if not maxPow or maxPow == 0 then return false end
        local pct = (UnitPower(unit) / maxPow) * 100
        return self:CompareValue(pct, cond.op, cond.value)

    elseif check == "remaining" then
        if not item then return false end
        local remaining = item:GetRemaining()
        if remaining <= 0 then return false end
        return self:CompareValue(remaining, cond.op, cond.value)

    elseif check == "stacks" then
        if not item then return false end
        local stacks = item:GetStacks() or 0
        return self:CompareValue(stacks, cond.op, cond.value)
    end

    return false
end

--- Evaluate action conditionals. Returns glow state + triggers sounds on transitions.
function Conditionals:EvaluateActions(condList, condState, item)
    if not condList then
        return false, nil
    end

    local glowActive = false
    local glowColor = nil

    for i, cond in ipairs(condList) do
        local met = self:CheckActionCondition(cond, item)
        local wasMet = condState[i]

        if met then
            if cond.glow then
                glowActive = true
                if cond.glowColor then
                    glowColor = cond.glowColor
                end
            end
            if wasMet == false and cond.sound and cond.sound ~= "NONE" then
                self:PlaySoundForKey(cond.sound)
            end
        end

        condState[i] = met
    end

    return glowActive, glowColor
end

-- ==========================================================
-- BACKWARD COMPAT: Evaluate / CheckAll wrappers
-- ==========================================================
-- These maintain the previous API that Icon.lua/AuraTracker.lua may call.

function Conditionals:Evaluate(condList, condState, item)
    return self:EvaluateActions(condList, condState, item)
end

function Conditionals:CheckAll(condList, item)
    return self:CheckAllLoadConditions(condList)
end

-- ==========================================================
-- GLYPH LIST BUILDER
-- ==========================================================

function Conditionals:_BuildGlyphList()
    local list = {}
    for i = 1, 6 do
        local enabled, glyphType, glyphTooltipIndex, glyphSpellId, icon = GetGlyphSocketInfo(i)
        if enabled and glyphSpellId then
            local name = GetSpellInfo(glyphSpellId)
            if name and not list[glyphSpellId] then
                list[glyphSpellId] = name
            end
        end
    end
    return list
end

-- ==========================================================
-- TALENT LIST BUILDER
-- ==========================================================

function Conditionals:_BuildTalentList()
    local list = {}
    local numTabs = GetNumTalentTabs and GetNumTalentTabs() or 0
    local maxTalents = MAX_NUM_TALENTS or 30
    if numTabs == 0 then return list end

    for tab = 1, numTabs do
        local numTalents = GetNumTalents and GetNumTalents(tab) or 0
        for i = 1, numTalents do
            local talentName, iconTexture, tier, column = GetTalentInfo(tab, i)
            if talentName then
                local index = (tab - 1) * maxTalents + i
                list[index] = { iconTexture, tier, column, talentName }
            end
        end
    end

    local bgIndex = maxTalents * numTabs + 1
    local backgrounds = {}
    for tab = 1, numTabs do
        local _, _, _, texture = GetTalentTabInfo(tab)
        if texture then
            backgrounds[tab] = texture
        end
    end
    list[bgIndex] = backgrounds

    return list
end

-- UI builder methods (BuildLoadConditionUI, BuildActionConditionUI,
-- BuildConditionUI) are defined in ConditionUI.lua to keep this file
-- focused on evaluation logic.
