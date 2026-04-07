local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

-- Pure per-condition checker functions extracted from ConditionalChecks.lua.
-- Each function receives only the condition table (and a Conditionals reference
-- for CompareValue) and returns a boolean.  No side effects.

local Conditionals = ns.AuraTracker.Conditionals

local UnitAura = UnitAura
local UnitExists = UnitExists
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitAffectingCombat = UnitAffectingCombat
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitInVehicle = UnitInVehicle
local IsMounted = IsMounted
local GetNumRaidMembers = GetNumRaidMembers
local GetNumPartyMembers = GetNumPartyMembers
local GetTalentInfo = GetTalentInfo
local GetNumTalentTabs = GetNumTalentTabs
local GetGlyphSocketInfo = GetGlyphSocketInfo
local GetNumGlyphSockets = GetNumGlyphSockets
local math = math

local ConditionFuncs = {}
ns.AuraTracker.ConditionFuncs = ConditionFuncs

-- ==========================================================
-- HELPERS (file-private)
-- ==========================================================

--- Return true if `unit` currently has an aura with the given spell ID.
local function UnitHasAuraBySpellId(unit, spellId)
    if not UnitExists(unit) then return false end
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, _, sid = UnitAura(unit, i, "HELPFUL")
        if not name then break end
        if sid == spellId then return true end
    end
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, _, sid = UnitAura(unit, i, "HARMFUL")
        if not name then break end
        if sid == spellId then return true end
    end
    return false
end
-- Expose for use by ConditionalChecks
ConditionFuncs.UnitHasAuraBySpellId = UnitHasAuraBySpellId

-- ==========================================================
-- INDIVIDUAL CONDITION CHECKERS
-- ==========================================================

function ConditionFuncs.CheckCombat(cond)
    local inCombat = not not UnitAffectingCombat("player")
    return (cond.value == "yes") == inCombat
end

function ConditionFuncs.CheckAlive(cond)
    local isDead = not not UnitIsDeadOrGhost("player")
    if cond.value == "alive" then return not isDead end
    return isDead
end

function ConditionFuncs.CheckVehicle(cond)
    local hasUI = (UnitHasVehicleUI and UnitHasVehicleUI("player"))
               or (UnitInVehicle and UnitInVehicle("player"))
               or false
    return (cond.value == "yes") == (not not hasUI)
end

function ConditionFuncs.CheckMounted(cond)
    local mounted = not not (IsMounted and IsMounted())
    return (cond.value == "yes") == mounted
end

function ConditionFuncs.CheckTalent(cond)
    local talentKey = cond.talentKey
    if not talentKey then return false end
    local maxTalents = MAX_NUM_TALENTS or 30
    local numTabs = GetNumTalentTabs and GetNumTalentTabs() or 0
    -- Talent data not yet loaded at login; pass optimistically.
    if numTabs == 0 then return true end
    local tab = math.ceil(talentKey / maxTalents)
    local talentIndex = talentKey - (tab - 1) * maxTalents
    if tab < 1 or tab > numTabs then return false end
    local _, _, _, _, rank = GetTalentInfo(tab, talentIndex)
    local hasRank = rank and rank > 0
    if cond.talentState == false then
        return not hasRank
    end
    return not not hasRank
end

function ConditionFuncs.CheckGlyph(cond, getGlyphSocketSpellId)
    local glyphSpellId = cond.glyphSpellId
    if not glyphSpellId then return false end
    local numSockets = (GetNumGlyphSockets and GetNumGlyphSockets()) or 6
    local found = false
    for i = 1, numSockets do
        local enabled, _, glyphTooltipIndex, glyphSpell = GetGlyphSocketInfo(i)
        if enabled and getGlyphSocketSpellId(glyphTooltipIndex, glyphSpell) == glyphSpellId then
            found = true
            break
        end
    end
    if cond.glyphNegate then
        return not found
    end
    return found
end

function ConditionFuncs.CheckUnitHP(cond)
    local unit = cond.unit or "target"
    if unit == "smart_group" then
        for _, u in ipairs(Conditionals:GetSmartGroupUnits()) do
            if UnitExists(u) then
                local maxVal = UnitHealthMax(u)
                if maxVal and maxVal > 0 then
                    local pct = (UnitHealth(u) / maxVal) * 100
                    if Conditionals:CompareValue(pct, cond.op, cond.value) then
                        return true
                    end
                end
            end
        end
        return false
    end
    local maxVal = UnitHealthMax(unit)
    if not maxVal or maxVal == 0 then return false end
    local pct = (UnitHealth(unit) / maxVal) * 100
    return Conditionals:CompareValue(pct, cond.op, cond.value)
end

function ConditionFuncs.CheckInGroup(cond)
    local inRaid  = GetNumRaidMembers  and (GetNumRaidMembers()  > 0) or false
    local inParty = GetNumPartyMembers and (GetNumPartyMembers() > 0) or false
    local expected = cond.value or "group"
    if expected == "solo"  then return (not inRaid) and (not inParty) end
    if expected == "party" then return inParty and (not inRaid) end
    if expected == "raid"  then return inRaid end
    if expected == "group" then return inRaid or inParty end
    return false
end

function ConditionFuncs.CheckAura(cond)
    local spellId = cond.spellId
    if not spellId then return false end
    local unit     = cond.unit  or "player"
    local wantAura = (cond.value ~= "missing_aura")
    if unit == "smart_group" then
        local units = Conditionals:GetSmartGroupUnits()
        if wantAura then
            for _, u in ipairs(units) do
                if UnitHasAuraBySpellId(u, spellId) then return true end
            end
            return false
        else
            for _, u in ipairs(units) do
                if UnitExists(u) and not UnitHasAuraBySpellId(u, spellId) then
                    return true
                end
            end
            return false
        end
    end
    local has = UnitHasAuraBySpellId(unit, spellId)
    return wantAura == has
end
