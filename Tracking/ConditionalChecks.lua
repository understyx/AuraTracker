local _, ns = ...

local Conditionals = ns.AuraTracker.Conditionals

-- Localize globals needed by this module
local UnitAura = UnitAura
local UnitExists = UnitExists
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitAffectingCombat = UnitAffectingCombat
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitInVehicle = UnitInVehicle
local IsMounted = IsMounted
local GetNumRaidMembers = GetNumRaidMembers
local GetNumPartyMembers = GetNumPartyMembers
local GetTalentInfo = GetTalentInfo
local GetTalentTabInfo = GetTalentTabInfo
local GetNumTalentTabs = GetNumTalentTabs
local GetNumTalents = GetNumTalents
local GetGlyphSocketInfo = GetGlyphSocketInfo
local GetNumGlyphSockets = GetNumGlyphSockets
local GetSpellInfo = GetSpellInfo
local GetSpellLink = GetSpellLink
local SendChatMessage = SendChatMessage
local UnitName = UnitName
local GetTime = GetTime
local PlaySoundFile = PlaySoundFile
local LSM = LibStub("LibSharedMedia-3.0")
local math_floor = math.floor
local string_format = string.format
local string_gsub = string.gsub

-- Local copies of group helpers (defined in Conditionals.lua)
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

local function CheckUnitPct(unit, getFunc, maxFunc, op, value)
    if unit == "smart_group" then
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
    local maxVal = maxFunc(unit)
    if not maxVal or maxVal == 0 then return false end
    local pct = (getFunc(unit) / maxVal) * 100
    return Conditionals:CompareValue(pct, op, value)
end

--- Return true if `unit` currently has an aura (buff or debuff) with the given spell ID.
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
        -- Talent data not yet loaded at login; pass optimistically so the icon
        -- isn't incorrectly hidden before the API is ready.  Unlike the bar-level
        -- check in ShouldShowBar(), this path is not cached and re-runs every tick,
        -- so it will self-correct as soon as talent data becomes available.
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

    elseif check == "glyph" then
        local glyphSpellId = cond.glyphSpellId
        if not glyphSpellId then return false end
        -- Scan all glyph sockets (use GetNumGlyphSockets if available, else 6)
        local numSockets = (GetNumGlyphSockets and GetNumGlyphSockets()) or 6
        local found = false
        for i = 1, numSockets do
            local enabled, _, glyphTooltipIndex, glyphSpell = GetGlyphSocketInfo(i)
            if enabled and self:_GetGlyphSocketSpellId(glyphTooltipIndex, glyphSpell) == glyphSpellId then
                found = true
                break
            end
        end
        -- glyphNegate = true means the condition passes when the glyph is NOT equipped
        if cond.glyphNegate then
            return not found
        end
        return found

    elseif check == "unit_hp" then
        return CheckUnitPct(cond.unit or "target", UnitHealth, UnitHealthMax, cond.op, cond.value)

    elseif check == "in_group" then
        local inRaid = GetNumRaidMembers and (GetNumRaidMembers() > 0) or false
        local inParty = GetNumPartyMembers and (GetNumPartyMembers() > 0) or false
        local expected = cond.value or "group"
        if expected == "solo" then return (not inRaid) and (not inParty) end
        if expected == "party" then return inParty and (not inRaid) end
        if expected == "raid" then return inRaid end
        if expected == "group" then return inRaid or inParty end
        return false

    elseif check == "aura" then
        local spellId = cond.spellId
        if not spellId then return false end
        local unit     = cond.unit  or "player"
        local wantAura = (cond.value ~= "missing_aura")
        if unit == "smart_group" then
            local units = GetSmartGroupUnits()
            if wantAura then
                -- passes when any group member has the aura
                for _, u in ipairs(units) do
                    if UnitHasAuraBySpellId(u, spellId) then return true end
                end
                return false
            else
                -- passes when any group member is missing the aura
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

