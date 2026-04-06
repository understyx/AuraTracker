local _, ns = ...

local Conditionals = ns.AuraTracker.Conditionals

local LSM = LibStub("LibSharedMedia-3.0")
local PlaySoundFile = PlaySoundFile
local GetSpellInfo = GetSpellInfo

local tonumber, tostring = tonumber, tostring

-- ==========================================================
-- LABEL TABLES
-- ==========================================================

local loadCheckLabelsShared = {
    ["in_combat"]      = "In Combat",
    ["alive"]          = "Alive / Dead",
    ["has_vehicle_ui"] = "Has Vehicle UI",
    ["mounted"]        = "Mounted",
    ["talent"]         = "Talent",
    ["glyph"]          = "Glyph",
    ["in_group"]       = "Group Type",
    ["aura"]           = "Aura",
}

local loadCheckLabelsIcon = {
    ["in_combat"]      = "In Combat",
    ["alive"]          = "Alive / Dead",
    ["has_vehicle_ui"] = "Has Vehicle UI",
    ["mounted"]        = "Mounted",
    ["talent"]         = "Talent",
    ["glyph"]          = "Glyph",
    ["in_group"]       = "Group Type",
    ["unit_hp"]        = "Unit HP %",
    ["aura"]           = "Aura",
}

local condOpLabels = {
    ["<"]  = "< (Less Than)",
    ["<="] = "<= (At Most)",
    [">"]  = "> (Greater Than)",
    [">="] = ">= (At Least)",
    ["=="] = "== (Equal To)",
}

local actionCheckLabels = {
    ["unit_hp"]    = "Unit HP %",
    ["unit_power"] = "Unit Power %",
    ["remaining"]  = "Remaining Duration",
    ["stacks"]     = "Stack Count",
}

-- ==========================================================
-- LOAD CONDITION TRISTATE HELPERS  (shared: bars + icons)
-- ==========================================================

-- Color codes for tristate toggle labels.
local TRISTATE_YES_COLOR = "|cFF00CC00"  -- green  (required / yes)
local TRISTATE_NO_COLOR  = "|cFFCC0000"  -- red    (excluded / no)
local TRISTATE_COLOR_END = "|r"

-- Mapping: check type → {trueVal, falseVal} used in the loadConditions array.
local tristateMap = {
    in_combat      = { trueVal = "yes",   falseVal = "no" },
    alive          = { trueVal = "alive", falseVal = "dead" },
    mounted        = { trueVal = "yes",   falseVal = "no" },
    has_vehicle_ui = { trueVal = "yes",   falseVal = "no" },
    in_group       = { trueVal = "group", falseVal = "solo" },
}

--- Read the tristate value for a simple boolean condition.
--- Returns nil (any/off), true (must be yes), or false (must be no).
local function GetTristateCondValue(condList, checkType)
    local map = tristateMap[checkType]
    if not map then return nil end
    for _, cond in ipairs(condList) do
        if cond.check == checkType then
            -- For in_group, the new tristate maps true → "group" and false → "solo".
            -- Older DB entries may have stored "party" or "raid" instead of "group";
            -- treat any non-solo value as true (in-group) for backward compatibility.
            if checkType == "in_group" then
                return cond.value ~= "solo"
            end
            return cond.value == map.trueVal
        end
    end
    return nil
end

--- Write a tristate value for a simple boolean condition.
--- val: nil = remove condition, true = set to trueVal, false = set to falseVal.
local function SetTristateCondValue(condList, checkType, val)
    local map = tristateMap[checkType]
    if not map then return end
    for i, cond in ipairs(condList) do
        if cond.check == checkType then
            if val == nil then
                table.remove(condList, i)
            else
                cond.value = val and map.trueVal or map.falseVal
            end
            return
        end
    end
    -- Not found; add a new entry only when not nil.
    if val ~= nil then
        table.insert(condList, {
            check = checkType,
            value = val and map.trueVal or map.falseVal,
        })
    end
end

--- Read the tristate value for the glyph condition.
--- Returns nil (any), true (has glyph), or false (doesn't have glyph).
local function GetGlyphTristate(condList)
    for _, cond in ipairs(condList) do
        if cond.check == "glyph" then
            return not cond.glyphNegate
        end
    end
    return nil
end

--- Set the tristate value for the glyph condition.
local function SetGlyphTristate(condList, val, spellId)
    for i, cond in ipairs(condList) do
        if cond.check == "glyph" then
            if val == nil then
                table.remove(condList, i)
            else
                cond.glyphNegate = (val == false) or nil
                if spellId then cond.glyphSpellId = spellId end
            end
            return
        end
    end
    if val ~= nil then
        table.insert(condList, {
            check       = "glyph",
            glyphSpellId = spellId,
            glyphNegate  = (val == false) or nil,
        })
    end
end

--- Return the spell ID stored in the glyph condition entry (if any).
local function GetGlyphSpellId(condList)
    for _, cond in ipairs(condList) do
        if cond.check == "glyph" then
            return cond.glyphSpellId
        end
    end
    return nil
end

-- ==========================================================
-- BAR AURA CONDITION HELPERS
-- ==========================================================

--- Read the tristate value for the aura condition.
--- Returns nil (off), true (have aura), or false (don't have aura).
local function GetBarAuraState(condList)
    for _, cond in ipairs(condList) do
        if cond.check == "aura" then
            return (cond.value ~= "missing_aura")
        end
    end
    return nil
end

--- Write the tristate value for the aura condition.
--- val: nil = remove, true = have_aura, false = missing_aura.
local function SetBarAuraState(condList, val, spellId, unit)
    for i, cond in ipairs(condList) do
        if cond.check == "aura" then
            if val == nil then
                table.remove(condList, i)
            else
                cond.value   = val and "have_aura" or "missing_aura"
                if spellId ~= nil then cond.spellId = spellId end
                if unit    ~= nil then cond.unit    = unit    end
            end
            return
        end
    end
    if val ~= nil then
        table.insert(condList, {
            check   = "aura",
            value   = val and "have_aura" or "missing_aura",
            spellId = spellId,
            unit    = unit or "player",
        })
    end
end

--- Return the spell ID stored in the aura condition entry (if any).
local function GetBarAuraSpellId(condList)
    for _, cond in ipairs(condList) do
        if cond.check == "aura" then return cond.spellId end
    end
    return nil
end

--- Return the unit stored in the aura condition entry (or "player").
local function GetBarAuraUnit(condList)
    for _, cond in ipairs(condList) do
        if cond.check == "aura" then return cond.unit or "player" end
    end
    return "player"
end

-- ==========================================================
-- ICON LOAD CONDITION HELPERS
-- ==========================================================

--- Return the talent condition entry, or nil if none.
local function GetIconTalentCond(condList)
    for _, cond in ipairs(condList) do
        if cond.check == "talent" then return cond end
    end
    return nil
end

--- Read the tristate value for the talent condition.
--- Returns nil (any), true (must have talent), false (must NOT have talent).
local function GetIconTalentTristate(condList)
    for _, cond in ipairs(condList) do
        if cond.check == "talent" then
            if cond.talentState == false then return false end
            return true
        end
    end
    return nil
end

--- Write the tristate value for the talent condition.
--- val: nil = remove, true = must have, false = must NOT have.
local function SetIconTalentTristate(condList, val, talentKey)
    for i, cond in ipairs(condList) do
        if cond.check == "talent" then
            if val == nil then
                table.remove(condList, i)
            else
                cond.talentState = val
                if talentKey ~= nil then cond.talentKey = talentKey end
            end
            return
        end
    end
    if val ~= nil then
        table.insert(condList, {
            check       = "talent",
            talentKey   = talentKey,
            talentState = val,
        })
    end
end

--- Return the talentKey stored in the talent condition entry (if any).
local function GetIconTalentKey(condList)
    for _, cond in ipairs(condList) do
        if cond.check == "talent" then return cond.talentKey end
    end
    return nil
end

--- Return the unit_hp condition entry, or nil if none.
local function GetIconUnitHPCond(condList)
    for _, cond in ipairs(condList) do
        if cond.check == "unit_hp" then return cond end
    end
    return nil
end

--- Return true if a unit_hp condition is currently active.
local function GetIconUnitHPEnabled(condList)
    return GetIconUnitHPCond(condList) ~= nil
end

--- Enable or disable the unit_hp condition.
--- When enabling, inserts a default entry if none exists.
--- When disabling, removes the entry.
local function SetIconUnitHPEnabled(condList, enabled)
    for i, cond in ipairs(condList) do
        if cond.check == "unit_hp" then
            if not enabled then
                table.remove(condList, i)
            end
            return
        end
    end
    if enabled then
        table.insert(condList, {
            check = "unit_hp",
            unit  = "target",
            op    = "<=",
            value = 35,
        })
    end
end


-- Export helpers for use by LoadConditionUI, ActionConditionUI, IconActionsUI
ns.AuraTracker._ConditionUIHelpers = {
    GetTristateCondValue = GetTristateCondValue,
    SetTristateCondValue = SetTristateCondValue,
    GetGlyphTristate = GetGlyphTristate,
    SetGlyphTristate = SetGlyphTristate,
    GetGlyphSpellId = GetGlyphSpellId,
    GetBarAuraState = GetBarAuraState,
    SetBarAuraState = SetBarAuraState,
    GetBarAuraSpellId = GetBarAuraSpellId,
    GetBarAuraUnit = GetBarAuraUnit,
    GetIconTalentCond = GetIconTalentCond,
    GetIconTalentTristate = GetIconTalentTristate,
    SetIconTalentTristate = SetIconTalentTristate,
    GetIconTalentKey = GetIconTalentKey,
    GetIconUnitHPCond = GetIconUnitHPCond,
    GetIconUnitHPEnabled = GetIconUnitHPEnabled,
    SetIconUnitHPEnabled = SetIconUnitHPEnabled,
    condOpLabels = condOpLabels,
    actionCheckLabels = actionCheckLabels,
}

-- ==========================================================
-- LEGACY COMPAT: BuildConditionUI (previous API)
-- ==========================================================
-- Maps the old single-call API to the new split system.

function Conditionals:BuildConditionUI(args, condOwner, orderBase, barKey, notifyFn, mode)
    if mode == "bar" then
        self:BuildLoadConditionUI(args, condOwner, orderBase, barKey, notifyFn, "bar")
    else
        self:BuildLoadConditionUI(args, condOwner, orderBase, barKey, notifyFn, "icon")
        self:BuildActionConditionUI(args, condOwner, orderBase + 5, barKey, notifyFn)
    end
end
