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

--- Build AceConfig args for load conditions.
--- @param args      table   Args table to inject into
--- @param owner     table   DB table that has .loadConditions
--- @param orderBase number  Order base
--- @param barKey    string  Bar key
--- @param notifyFn  function  Called after changes
--- @param mode      string  "bar" or "icon"
function Conditionals:BuildLoadConditionUI(args, owner, orderBase, barKey, notifyFn, mode)
    mode = mode or "bar"

    owner.loadConditions = owner.loadConditions or {}

    if mode == "bar" then
        -- -------------------------------------------------------
        -- BAR MODE: fixed set of tristate toggles, one per type.
        -- No sub-header is added here; the Load tab itself acts as
        -- the "Load Conditions" container together with the top-level
        -- loadTabDesc description in BarSettingsUI.lua.
        -- -------------------------------------------------------
        local condList = owner.loadConditions
        local o = orderBase + 0.5

        local simpleTypes = {
            { check = "in_combat",      label = "In Combat",
              hint  = "Yes = bar shows only in combat.  No = bar shows only out of combat." },
            { check = "alive",          label = "Alive",
              hint  = "Yes = bar shows only while alive.  No = bar shows only while dead." },
            { check = "mounted",        label = "Mounted",
              hint  = "Yes = bar shows only while mounted.  No = bar shows only while not mounted." },
            { check = "has_vehicle_ui", label = "Has Vehicle UI",
              hint  = "Yes = bar shows only while in a vehicle.  No = bar shows only outside a vehicle." },
            { check = "in_group",       label = "In Group",
              hint  = "Yes = bar shows only in a party or raid.  No = bar shows only while solo." },
        }

        for _, ct in ipairs(simpleTypes) do
            local check = ct.check
            local label = ct.label
            args["barCond_" .. check] = {
                type     = "toggle",
                tristate = true,
                name     = function()
                    local v = GetTristateCondValue(condList, check)
                    if v == true  then return TRISTATE_YES_COLOR .. label .. TRISTATE_COLOR_END end
                    if v == false then return TRISTATE_NO_COLOR  .. label .. TRISTATE_COLOR_END end
                    return label
                end,
                desc     = ct.hint,
                order    = o,
                width    = "double",
                get = function()
                    return GetTristateCondValue(condList, check)
                end,
                set = function(_, val)
                    SetTristateCondValue(condList, check, val)
                    notifyFn(barKey)
                end,
            }
            o = o + 0.05
        end

        -- Glyph: tristate toggle + spell-ID input (shown when not nil)
        local glyphState = GetGlyphTristate(condList)
        args.barCond_glyph_toggle = {
            type     = "toggle",
            tristate = true,
            name     = function()
                local v = GetGlyphTristate(condList)
                if v == true  then return TRISTATE_YES_COLOR .. "Glyph" .. TRISTATE_COLOR_END end
                if v == false then return TRISTATE_NO_COLOR  .. "Glyph" .. TRISTATE_COLOR_END end
                return "Glyph"
            end,
            desc     = "Yes = bar shows only when glyph is equipped.  "
                    .. "No = bar shows only when glyph is NOT equipped.",
            order    = o,
            width    = "double",
            get = function()
                return GetGlyphTristate(condList)
            end,
            set = function(_, val)
                local sid = GetGlyphSpellId(condList)
                SetGlyphTristate(condList, val, sid)
                notifyFn(barKey)
            end,
        }
        o = o + 0.05

        if glyphState ~= nil then
            args.barCond_glyph_spellId = {
                type  = "input",
                name  = "Glyph Spell ID",
                desc  = "Enter the spell ID of the glyph to check.\n"
                     .. "Find glyph IDs on Wowhead or with /script print(GetSpellInfo(id)) in-game.",
                order = o,
                width = "normal",
                get   = function()
                    return tostring(GetGlyphSpellId(condList) or "")
                end,
                set   = function(_, val)
                    local n = tonumber(val)
                    local sid = (n and n > 0) and n or nil
                    local state = GetGlyphTristate(condList)
                    SetGlyphTristate(condList, state, sid)
                    notifyFn(barKey)
                end,
            }
            o = o + 0.05

            local spellId = GetGlyphSpellId(condList)
            args.barCond_glyph_name = {
                type  = "description",
                name  = function()
                    if spellId then
                        local name = GetSpellInfo(spellId)
                        if name then return "|cFF00FF00" .. name .. "|r" end
                        return "|cFFFF4400Unknown spell ID|r"
                    end
                    return "|cFFAAAAFFEnter a spell ID above.|r"
                end,
                order = o,
                width = "normal",
            }
        end

        -- Aura: tristate toggle + unit selector + spell-ID input (shown when not nil)
        local auraState = GetBarAuraState(condList)
        args.barCond_aura_toggle = {
            type     = "toggle",
            tristate = true,
            name     = function()
                local v = GetBarAuraState(condList)
                if v == true  then return TRISTATE_YES_COLOR .. "Aura" .. TRISTATE_COLOR_END end
                if v == false then return TRISTATE_NO_COLOR  .. "Aura" .. TRISTATE_COLOR_END end
                return "Aura"
            end,
            desc     = "Yes = bar shows only when the aura is present.  "
                    .. "No = bar shows only when the aura is absent.",
            order    = o,
            width    = "double",
            get = function()
                return GetBarAuraState(condList)
            end,
            set = function(_, val)
                local sid  = GetBarAuraSpellId(condList)
                local unit = GetBarAuraUnit(condList)
                SetBarAuraState(condList, val, sid, unit)
                notifyFn(barKey)
            end,
        }
        o = o + 0.05

        if auraState ~= nil then
            args.barCond_aura_unit = {
                type   = "select",
                name   = "Unit",
                values = self.AuraUnits,
                order  = o,
                width  = "normal",
                get    = function() return GetBarAuraUnit(condList) end,
                set    = function(_, val)
                    local sid   = GetBarAuraSpellId(condList)
                    local state = GetBarAuraState(condList)
                    SetBarAuraState(condList, state, sid, val)
                    notifyFn(barKey)
                end,
            }
            o = o + 0.05

            args.barCond_aura_spellId = {
                type  = "input",
                name  = "Aura Spell ID",
                desc  = "Enter the spell ID of the aura to check.\n"
                     .. "Find spell IDs on Wowhead or with /script print(GetSpellInfo(id)) in-game.",
                order = o,
                width = "normal",
                get   = function()
                    return tostring(GetBarAuraSpellId(condList) or "")
                end,
                set   = function(_, val)
                    local n     = tonumber(val)
                    local sid   = (n and n > 0) and n or nil
                    local state = GetBarAuraState(condList)
                    local unit  = GetBarAuraUnit(condList)
                    SetBarAuraState(condList, state, sid, unit)
                    notifyFn(barKey)
                end,
            }
            o = o + 0.05

            local auraSpellId = GetBarAuraSpellId(condList)
            args.barCond_aura_name = {
                type  = "description",
                name  = function()
                    if auraSpellId then
                        local name = GetSpellInfo(auraSpellId)
                        if name then return "|cFF00FF00" .. name .. "|r" end
                        return "|cFFFF4400Unknown spell ID|r"
                    end
                    return "|cFFAAAAFFEnter a spell ID above.|r"
                end,
                order = o,
                width = "normal",
            }
        end

        return
    end

    -- -------------------------------------------------------
    -- ICON MODE: WeakAuras-style tristate toggles.
    -- Singleton conditions (in_combat, alive, mounted, etc.) each
    -- get one tristate toggle: nil = any, true = required (green),
    -- false = excluded (red).  Aura is the only type where multiple
    -- entries make sense and keeps an add/remove list.
    -- -------------------------------------------------------
    local condList = owner.loadConditions
    local o = orderBase

    args.iconLoadDesc = {
        type  = "description",
        name  = "|cFFAAAAFFDefine when this icon should be visible.\n"
             .. "|cFF00CC00Green|r = required   "
             .. "|cFFCC0000Red|r = excluded   "
             .. "Unchecked = any|r",
        order = o,
        width = "full",
    }
    o = o + 0.1

    -- --- Simple boolean tristates ---
    local iconSimpleTypes = {
        { check = "in_combat",
          label = "In Combat",
          hint  = "Yes = icon shows only in combat.  No = icon shows only out of combat." },
        { check = "alive",
          label = "Alive",
          hint  = "Yes = icon shows only while alive.  No = icon shows only while dead." },
        { check = "mounted",
          label = "Mounted",
          hint  = "Yes = icon shows only while mounted.  No = icon shows only while not mounted." },
        { check = "has_vehicle_ui",
          label = "Has Vehicle UI",
          hint  = "Yes = icon shows only while in a vehicle.  No = icon shows only outside a vehicle." },
        { check = "in_group",
          label = "In Group",
          hint  = "Yes = icon shows only in a party or raid.  No = icon shows only while solo." },
    }

    for _, ct in ipairs(iconSimpleTypes) do
        local check = ct.check
        local label = ct.label
        args["iconCond_" .. check] = {
            type     = "toggle",
            tristate = true,
            name     = function()
                local v = GetTristateCondValue(condList, check)
                if v == true  then return TRISTATE_YES_COLOR .. label .. TRISTATE_COLOR_END end
                if v == false then return TRISTATE_NO_COLOR  .. label .. TRISTATE_COLOR_END end
                return label
            end,
            desc     = ct.hint,
            order    = o,
            width    = "double",
            get = function()
                return GetTristateCondValue(condList, check)
            end,
            set = function(_, val)
                SetTristateCondValue(condList, check, val)
                notifyFn(barKey)
            end,
        }
        o = o + 0.05
    end

    -- --- Talent: tristate + talent selector ---
    local talentState = GetIconTalentTristate(condList)
    args.iconCond_talent_toggle = {
        type     = "toggle",
        tristate = true,
        name     = function()
            local v = GetIconTalentTristate(condList)
            if v == true  then return TRISTATE_YES_COLOR .. "Talent" .. TRISTATE_COLOR_END end
            if v == false then return TRISTATE_NO_COLOR  .. "Talent" .. TRISTATE_COLOR_END end
            return "Talent"
        end,
        desc     = "Yes = icon shows only when the selected talent is learned.  "
                .. "No = icon shows only when it is NOT learned.",
        order    = o,
        width    = "double",
        get = function()
            return GetIconTalentTristate(condList)
        end,
        set = function(_, val)
            local tKey = GetIconTalentKey(condList)
            SetIconTalentTristate(condList, val, tKey)
            notifyFn(barKey)
        end,
    }
    o = o + 0.05

    if talentState ~= nil then
        args.iconCond_talent_select = {
            type          = "multiselect",
            dialogControl = "AuraTrackerMiniTalent",
            name          = "Talent",
            order         = o,
            width         = "full",
            values        = function()
                return self:_BuildTalentList()
            end,
            get = function(_, key)
                local tc = GetIconTalentCond(condList)
                if not tc or not tc.talentKey then return nil end
                if key == tc.talentKey then
                    return tc.talentState
                end
                return nil
            end,
            set = function(_, key, value)
                local tc = GetIconTalentCond(condList)
                if tc then
                    if value == nil and key == tc.talentKey then
                        tc.talentKey   = nil
                        tc.talentState = nil
                    else
                        tc.talentKey   = key
                        tc.talentState = value
                    end
                end
                notifyFn(barKey)
            end,
        }
        o = o + 0.1
    end

    -- --- Glyph: tristate + spell ID input ---
    local glyphState = GetGlyphTristate(condList)
    args.iconCond_glyph_toggle = {
        type     = "toggle",
        tristate = true,
        name     = function()
            local v = GetGlyphTristate(condList)
            if v == true  then return TRISTATE_YES_COLOR .. "Glyph" .. TRISTATE_COLOR_END end
            if v == false then return TRISTATE_NO_COLOR  .. "Glyph" .. TRISTATE_COLOR_END end
            return "Glyph"
        end,
        desc     = "Yes = icon shows only when the glyph is equipped.  "
                .. "No = icon shows only when the glyph is NOT equipped.",
        order    = o,
        width    = "double",
        get = function()
            return GetGlyphTristate(condList)
        end,
        set = function(_, val)
            local sid = GetGlyphSpellId(condList)
            SetGlyphTristate(condList, val, sid)
            notifyFn(barKey)
        end,
    }
    o = o + 0.05

    if glyphState ~= nil then
        args.iconCond_glyph_spellId = {
            type  = "input",
            name  = "Glyph Spell ID",
            desc  = "Enter the spell ID of the glyph to check.\n"
                 .. "Find glyph IDs on Wowhead or with /script print(GetSpellInfo(id)) in-game.",
            order = o,
            width = "normal",
            get   = function()
                return tostring(GetGlyphSpellId(condList) or "")
            end,
            set   = function(_, val)
                local n     = tonumber(val)
                local sid   = (n and n > 0) and n or nil
                local state = GetGlyphTristate(condList)
                SetGlyphTristate(condList, state, sid)
                notifyFn(barKey)
            end,
        }
        o = o + 0.05

        local glyphSpellId = GetGlyphSpellId(condList)
        args.iconCond_glyph_name = {
            type  = "description",
            name  = function()
                if glyphSpellId then
                    local name = GetSpellInfo(glyphSpellId)
                    if name then return "|cFF00FF00" .. name .. "|r" end
                    return "|cFFFF4400Unknown spell ID|r"
                end
                return "|cFFAAAAFFEnter a spell ID above.|r"
            end,
            order = o,
            width = "normal",
        }
        o = o + 0.05
    end

    -- --- Unit HP: enable toggle + sub-controls ---
    local unitHpEnabled = GetIconUnitHPEnabled(condList)
    args.iconCond_unitHp_enable = {
        type  = "toggle",
        name  = function()
            if GetIconUnitHPEnabled(condList) then
                return TRISTATE_YES_COLOR .. "Unit HP %" .. TRISTATE_COLOR_END
            end
            return "Unit HP %"
        end,
        desc  = "Enable a unit health percent threshold condition for this icon.",
        order = o,
        width = "double",
        get   = function() return GetIconUnitHPEnabled(condList) end,
        set   = function(_, val)
            SetIconUnitHPEnabled(condList, val)
            notifyFn(barKey)
        end,
    }
    o = o + 0.05

    if unitHpEnabled then
        args.iconCond_unitHp_unit = {
            type   = "select",
            name   = "Unit",
            values = self.HPUnits,
            order  = o,
            width  = "half",
            get    = function()
                local c = GetIconUnitHPCond(condList)
                return c and c.unit or "target"
            end,
            set    = function(_, val)
                local c = GetIconUnitHPCond(condList)
                if c then c.unit = val end
                notifyFn(barKey)
            end,
        }
        o = o + 0.05

        args.iconCond_unitHp_op = {
            type   = "select",
            name   = "Operator",
            values = condOpLabels,
            order  = o,
            width  = "half",
            get    = function()
                local c = GetIconUnitHPCond(condList)
                return c and c.op or "<="
            end,
            set    = function(_, val)
                local c = GetIconUnitHPCond(condList)
                if c then c.op = val end
                notifyFn(barKey)
            end,
        }
        o = o + 0.05

        args.iconCond_unitHp_value = {
            type  = "input",
            name  = "HP %",
            desc  = "Health percent threshold (0-100).",
            order = o,
            width = "half",
            get   = function()
                local c = GetIconUnitHPCond(condList)
                return tostring(c and c.value or 35)
            end,
            set   = function(_, val)
                local c = GetIconUnitHPCond(condList)
                if c then c.value = tonumber(val) or 35 end
                notifyFn(barKey)
            end,
        }
        o = o + 0.05
    end

    -- --- Aura conditions: multiple entries allowed ---
    args.iconCond_aura_header = {
        type  = "header",
        name  = "Aura Conditions",
        order = o,
    }
    o = o + 0.05

    args.iconCond_aura_desc = {
        type  = "description",
        name  = "|cFFAAAAFFMultiple aura conditions can be added; all must be met.|r",
        order = o,
        width = "full",
    }
    o = o + 0.05

    local numAuras = 0
    for _, cond in ipairs(condList) do
        if cond.check == "aura" then numAuras = numAuras + 1 end
    end

    if numAuras < 5 then
        args.iconCond_aura_add = {
            type  = "execute",
            name  = "+ Add Aura",
            order = o,
            width = "normal",
            func  = function()
                table.insert(condList, {
                    check   = "aura",
                    unit    = "player",
                    value   = "have_aura",
                    spellId = nil,
                })
                notifyFn(barKey)
            end,
        }
        o = o + 0.05
    end

    local auraSeq = 0
    for ci, cond in ipairs(condList) do
        if cond.check == "aura" then
            auraSeq = auraSeq + 1
            local prefix   = "iconCond_aura_" .. auraSeq .. "_"
            local auraBase = o + (auraSeq - 1) * 0.25

            args[prefix .. "unit"] = {
                type   = "select",
                name   = "Unit",
                values = self.AuraUnits,
                order  = auraBase,
                width  = "half",
                get    = function() return cond.unit or "player" end,
                set    = function(_, val)
                    cond.unit = val
                    notifyFn(barKey)
                end,
            }
            args[prefix .. "state"] = {
                type   = "select",
                name   = "State",
                values = self.AuraValues,
                order  = auraBase + 0.02,
                width  = "half",
                get    = function() return cond.value or "have_aura" end,
                set    = function(_, val)
                    cond.value = val
                    notifyFn(barKey)
                end,
            }
            args[prefix .. "spellId"] = {
                type  = "input",
                name  = "Spell ID",
                desc  = "Enter the spell ID of the aura to check.\n"
                     .. "Find spell IDs on Wowhead or with /script print(GetSpellInfo(id)) in-game.",
                order = auraBase + 0.04,
                width = "half",
                get   = function() return tostring(cond.spellId or "") end,
                set   = function(_, val)
                    local n = tonumber(val)
                    cond.spellId = (n and n > 0) and n or nil
                    notifyFn(barKey)
                end,
            }
            args[prefix .. "auraName"] = {
                type  = "description",
                name  = function()
                    if cond.spellId then
                        local name = GetSpellInfo(cond.spellId)
                        if name then return "|cFF00FF00" .. name .. "|r" end
                        return "|cFFFF4400Unknown spell ID|r"
                    end
                    return "|cFFAAAAFFEnter a spell ID to the left.|r"
                end,
                order = auraBase + 0.06,
                width = "half",
            }
            args[prefix .. "remove"] = {
                type  = "execute",
                name  = "Remove",
                order = auraBase + 0.08,
                width = "half",
                func  = function()
                    table.remove(condList, ci)
                    notifyFn(barKey)
                end,
            }
        end
    end
end

-- ==========================================================
-- UI: ACTION CONDITIONAL BUILDER  (icon-only)
-- ==========================================================

--- Build AceConfig args for action conditionals (icon-only: glow + sound).
function Conditionals:BuildActionConditionUI(args, owner, orderBase, barKey, notifyFn)
    owner.conditionals = owner.conditionals or {}
    local maxCond = self.MAX_ACTION_CONDITIONS

    args.actionCondHeader = {
        type = "header",
        name = "Action Conditionals",
        order = orderBase,
    }
    args.actionCondDesc = {
        type = "description",
        name = "|cFFAAAAFFTrigger glow, desaturate, or sound on this icon when conditions are met.\n"
            .. "Sounds play only on transition (false→true).|r",
        order = orderBase + 0.1,
        width = "full",
    }

    if #owner.conditionals < maxCond then
        args.actionCondAdd = {
            type = "execute",
            name = "+ Add Action Condition",
            order = orderBase + 0.2,
            width = "normal",
            func = function()
                table.insert(owner.conditionals, {
                    check = "remaining",
                    op = "<=",
                    value = 5,
                    unit = "target",
                    glow = false,
                    desaturate = false,
                    sound = nil,
                    glowColor = nil,
                })
                notifyFn(barKey)
            end,
        }
    end

    for ci, cond in ipairs(owner.conditionals) do
        local condBase = orderBase + 0.5 + (ci - 1) * 0.15
        local prefix = "actionCond" .. ci .. "_"
        local check = cond.check
        local isHP = (check == "unit_hp" or check == "unit_power")

        args[prefix .. "header"] = {
            type = "header",
            name = "Action " .. ci,
            order = condBase,
        }
        args[prefix .. "check"] = {
            type = "select",
            name = "Condition",
            values = actionCheckLabels,
            order = condBase + 0.01,
            get = function() return cond.check or "remaining" end,
            set = function(_, val)
                cond.check = val
                if val == "unit_hp" or val == "unit_power" then
                    cond.unit = cond.unit or "target"
                    cond.op = cond.op or "<="
                    cond.value = cond.value or 35
                elseif val == "remaining" then
                    cond.op = cond.op or "<="
                    cond.value = cond.value or 5
                elseif val == "stacks" then
                    cond.op = cond.op or ">="
                    cond.value = cond.value or 5
                end
                notifyFn(barKey)
            end,
        }
        if isHP then
            local unitValues = (check == "unit_power") and self.PowerUnits or self.HPUnits
            args[prefix .. "unit"] = {
                type = "select",
                name = "Unit",
                values = unitValues,
                order = condBase + 0.015,
                width = "half",
                get = function() return cond.unit or "target" end,
                set = function(_, val)
                    cond.unit = val
                    notifyFn(barKey)
                end,
            }
        end
        args[prefix .. "op"] = {
            type = "select",
            name = "Operator",
            values = condOpLabels,
            order = condBase + 0.02,
            width = "half",
            get = function() return cond.op or "<=" end,
            set = function(_, val)
                cond.op = val
                notifyFn(barKey)
            end,
        }
        local valDesc
        if check == "remaining" then valDesc = "Seconds"
        elseif check == "unit_hp" or check == "unit_power" then valDesc = "Percent (0-100)"
        else valDesc = "Stack count" end
        args[prefix .. "value"] = {
            type = "input",
            name = "Value",
            desc = valDesc,
            order = condBase + 0.03,
            width = "half",
            get = function() return tostring(cond.value or 5) end,
            set = function(_, val)
                cond.value = tonumber(val) or 5
                notifyFn(barKey)
            end,
        }
        args[prefix .. "glow"] = {
            type = "toggle",
            name = "Glow",
            desc = "Show a pulsing glow border when this condition is met.",
            order = condBase + 0.04,
            width = "half",
            get = function() return cond.glow or false end,
            set = function(_, val)
                cond.glow = val
                notifyFn(barKey)
            end,
        }
        args[prefix .. "desaturate"] = {
            type = "toggle",
            name = "Desaturate",
            desc = "Desaturate (grey out) the icon when this condition is met.",
            order = condBase + 0.045,
            width = "half",
            get = function() return cond.desaturate or false end,
            set = function(_, val)
                cond.desaturate = val
                notifyFn(barKey)
            end,
        }
        args[prefix .. "sound"] = {
            type = "select",
            name = "Sound",
            desc = "Play a sound when entering this condition.",
            values = function()
                local vals = {}
                local sounds = LSM:List("sound")
                if sounds then
                    for _, name in ipairs(sounds) do
                        vals[name] = name
                    end
                end
                return vals
            end,
            order = condBase + 0.05,
            get = function()
                local key = cond.sound
                if not key then return "None" end
                -- Migrate old DB key format to LSM name
                local old = self.OLD_SOUND_KEYS
                if old and old[key] then return old[key] end
                return key
            end,
            set = function(_, val)
                cond.sound = (val ~= "None") and val or nil
                -- Preview the selected sound
                if val and val ~= "None" then
                    local path = LSM:Fetch("sound", val)
                    if path then
                        PlaySoundFile(path)
                    end
                end
                notifyFn(barKey)
            end,
        }
        if cond.glow then
            args[prefix .. "glowColor"] = {
                type = "color",
                name = "Glow Color",
                desc = "Color of the glow border.",
                order = condBase + 0.06,
                hasAlpha = false,
                get = function()
                    local c = cond.glowColor or { r = 1, g = 1, b = 0 }
                    return c.r, c.g, c.b
                end,
                set = function(_, r, g, b)
                    cond.glowColor = { r = r, g = g, b = b }
                    notifyFn(barKey)
                end,
            }
        end
        args[prefix .. "remove"] = {
            type = "execute",
            name = "Remove",
            order = condBase + 0.07,
            width = "half",
            func = function()
                table.remove(owner.conditionals, ci)
                notifyFn(barKey)
            end,
        }
    end
end

-- ==========================================================
-- UI: ICON ACTIONS BUILDER  (On Click / On Show / On Hide)
-- ==========================================================

local iconActionTypeLabels = {
    ["chat"]  = "Send Chat Message",
    ["sound"] = "Play Sound",
    ["glow"]  = "Glow",
}

-- On Hide: glow has no meaningful effect (the icon is already hidden),
-- so we expose only chat and sound for that trigger.
local iconActionTypeLabelsNoGlow = {
    ["chat"]  = "Send Chat Message",
    ["sound"] = "Play Sound",
}

local chatChannelLabels = {
    ["SAY"]   = "Say",
    ["YELL"]  = "Yell",
    ["PARTY"] = "Party",
    ["RAID"]  = "Raid",
    ["EMOTE"] = "Emote",
    ["SMART"] = "Raid > Party > Say",
}

local iconActionTriggerInfo = {
    { key = "onClickActions", label = "On Click",  desc = "Actions fired when the icon is clicked." },
    { key = "onShowActions",  label = "On Show",   desc = "Actions fired when the icon becomes visible." },
    { key = "onHideActions",  label = "On Hide",   desc = "Actions fired when the icon becomes hidden.", noGlow = true },
}

--- Build AceConfig args for icon event actions (On Click / On Show / On Hide).
function Conditionals:BuildIconActionsUI(args, owner, orderBase, barKey, notifyFn)
    args.iconActionsHeader = {
        type  = "header",
        name  = "Icon Actions",
        order = orderBase,
    }
    args.iconActionsDesc = {
        type  = "description",
        name  = "|cFFAAAAFFFire actions when the icon is clicked, shown, or hidden.\n"
            .. "Chat message tokens: %name, %stack, %remaining, %target, %player, %spelllink|r",
        order = orderBase + 0.1,
        width = "full",
    }

    for ti, triggerInfo in ipairs(iconActionTriggerInfo) do
        local triggerKey  = triggerInfo.key
        local triggerBase = orderBase + ti * 2

        -- Ensure the list table exists
        owner[triggerKey] = owner[triggerKey] or {}
        local actions = owner[triggerKey]

        -- Trigger sub-header
        local hdrKey = "iconAction_" .. triggerKey .. "_hdr"
        args[hdrKey] = {
            type  = "header",
            name  = triggerInfo.label,
            order = triggerBase,
        }

        -- Add-action button
        if #actions < self.MAX_ICON_ACTIONS then
            local addKey = "iconAction_" .. triggerKey .. "_add"
            args[addKey] = {
                type  = "execute",
                name  = "+ Add Action",
                order = triggerBase + 0.1,
                width = "normal",
                func  = function()
                    table.insert(owner[triggerKey], {
                        type    = "sound",
                        sound   = nil,
                        message = "",
                        channel = "SAY",
                        glow    = false,
                        glowColor = nil,
                    })
                    notifyFn(barKey)
                end,
            }
        end

        for ai, action in ipairs(actions) do
            local aBase  = triggerBase + 0.5 + (ai - 1) * 0.2
            local prefix = "iconAction_" .. triggerKey .. "_" .. ai .. "_"

            args[prefix .. "type"] = {
                type   = "select",
                name   = triggerInfo.label .. " " .. ai,
                values = triggerInfo.noGlow and iconActionTypeLabelsNoGlow or iconActionTypeLabels,
                order  = aBase,
                get    = function() return action.type or "sound" end,
                set    = function(_, val)
                    action.type = val
                    notifyFn(barKey)
                end,
            }

            if action.type == "chat" then
                args[prefix .. "channel"] = {
                    type   = "select",
                    name   = "Channel",
                    values = chatChannelLabels,
                    order  = aBase + 0.01,
                    width  = "half",
                    get    = function() return action.channel or "SAY" end,
                    set    = function(_, val)
                        action.channel = val
                        notifyFn(barKey)
                    end,
                }
                args[prefix .. "message"] = {
                    type  = "input",
                    name  = "Message",
                    desc  = "Message to send. Tokens: %name, %stack, %remaining, %target, %player, %spelllink",
                    order = aBase + 0.02,
                    width = "double",
                    get   = function() return action.message or "" end,
                    set   = function(_, val)
                        action.message = val
                        notifyFn(barKey)
                    end,
                }

            elseif action.type == "sound" then
                args[prefix .. "sound"] = {
                    type   = "select",
                    name   = "Sound",
                    desc   = "Sound to play when triggered.",
                    values = function()
                        local vals = { ["None"] = "None" }
                        local sounds = LSM:List("sound")
                        if sounds then
                            for _, name in ipairs(sounds) do
                                vals[name] = name
                            end
                        end
                        return vals
                    end,
                    order  = aBase + 0.01,
                    width  = "double",
                    get    = function()
                        local key = action.sound
                        if not key then return "None" end
                        local old = self.OLD_SOUND_KEYS
                        if old and old[key] then return old[key] end
                        return key
                    end,
                    set    = function(_, val)
                        action.sound = (val ~= "None") and val or nil
                        -- Preview the selected sound
                        if val and val ~= "None" then
                            local path = LSM:Fetch("sound", val)
                            if path then PlaySoundFile(path) end
                        end
                        notifyFn(barKey)
                    end,
                }

            elseif action.type == "glow" then
                args[prefix .. "glow"] = {
                    type  = "toggle",
                    name  = "Enable Glow",
                    desc  = "Turn the icon glow on (true) or off (false) when triggered.",
                    order = aBase + 0.01,
                    width = "half",
                    get   = function() return action.glow or false end,
                    set   = function(_, val)
                        action.glow = val
                        notifyFn(barKey)
                    end,
                }
                if action.glow then
                    args[prefix .. "glowColor"] = {
                        type     = "color",
                        name     = "Color",
                        order    = aBase + 0.02,
                        hasAlpha = false,
                        get      = function()
                            local c = action.glowColor or { r = 1, g = 0.8, b = 0 }
                            return c.r, c.g, c.b
                        end,
                        set      = function(_, r, g, b)
                            action.glowColor = { r = r, g = g, b = b }
                            notifyFn(barKey)
                        end,
                    }
                end
            end

            args[prefix .. "remove"] = {
                type  = "execute",
                name  = "Remove",
                order = aBase + 0.09,
                width = "half",
                func  = function()
                    table.remove(owner[triggerKey], ai)
                    notifyFn(barKey)
                end,
            }
        end
    end
end

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
