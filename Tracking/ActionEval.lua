local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

-- Pure action-condition evaluation helpers.
-- These functions read WoW API or item state and return plain boolean/numeric
-- results.  All glow/sound side effects remain in ConditionalActions.lua.

local Conditionals = ns.AuraTracker.Conditionals

local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitPower, UnitPowerMax   = UnitPower, UnitPowerMax
local UnitExists = UnitExists

local ActionEval = {}
ns.AuraTracker.ActionEval = ActionEval

-- ==========================================================
-- HELPERS
-- ==========================================================

--- Evaluate a HP- or power-percentage condition against a single unit or
--- the smart group.  Uses the provided getter + max getter pair.
local function CheckUnitPct(unit, getFunc, maxFunc, op, value)
    if unit == "smart_group" then
        for _, u in ipairs(Conditionals:GetSmartGroupUnits()) do
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

-- Export for use in ConditionalActions.lua
ActionEval.CheckUnitPct = CheckUnitPct

-- ==========================================================
-- PER-CONDITION EVALUATOR
-- ==========================================================

--- Evaluate one action condition and return whether it is currently met.
--- @param cond  table    Single condition entry from icon.conditionals
--- @param item  table    TrackedItem instance (may be nil for non-item contexts)
--- @return boolean
function ActionEval.EvalCond(cond, item)
    local check = cond.check

    if check == "unit_hp" then
        return CheckUnitPct(cond.unit or "target", UnitHealth, UnitHealthMax, cond.op, cond.value)

    elseif check == "unit_power" then
        return CheckUnitPct(cond.unit or "player", UnitPower, UnitPowerMax, cond.op, cond.value)

    elseif check == "remaining" then
        if not item then return false end
        local remaining = item:GetRemaining()
        if remaining <= 0 then return false end
        return Conditionals:CompareValue(remaining, cond.op, cond.value)

    elseif check == "stacks" then
        if not item then return false end
        local stacks = item:GetStacks() or 0
        return Conditionals:CompareValue(stacks, cond.op, cond.value)
    end

    return false
end
