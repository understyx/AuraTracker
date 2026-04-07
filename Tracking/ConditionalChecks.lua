local _, ns = ...

local Conditionals = ns.AuraTracker.Conditionals
local CF = ns.AuraTracker.ConditionFuncs

--- Check one load condition.
function Conditionals:CheckLoadCondition(cond)
    local check = cond.check

    if check == "in_combat"      then return CF.CheckCombat(cond)
    elseif check == "alive"      then return CF.CheckAlive(cond)
    elseif check == "has_vehicle_ui" then return CF.CheckVehicle(cond)
    elseif check == "mounted"    then return CF.CheckMounted(cond)
    elseif check == "talent"     then return CF.CheckTalent(cond)
    elseif check == "glyph"      then
        return CF.CheckGlyph(cond, function(tip, sp)
            return self:_GetGlyphSocketSpellId(tip, sp)
        end)
    elseif check == "unit_hp"    then return CF.CheckUnitHP(cond)
    elseif check == "in_group"   then return CF.CheckInGroup(cond)
    elseif check == "aura"       then return CF.CheckAura(cond)
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

