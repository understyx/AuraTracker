local _, ns = ...

local Conditionals = ns.AuraTracker.Conditionals
local _H = ns.AuraTracker._ConditionUIHelpers

local LSM = LibStub("LibSharedMedia-3.0")
local PlaySoundFile = PlaySoundFile
local GetSpellInfo = GetSpellInfo
local tonumber, tostring = tonumber, tostring

-- Import helpers
local GetTristateCondValue = _H.GetTristateCondValue
local SetTristateCondValue = _H.SetTristateCondValue
local GetGlyphTristate = _H.GetGlyphTristate
local SetGlyphTristate = _H.SetGlyphTristate
local GetGlyphSpellId = _H.GetGlyphSpellId
local GetBarAuraState = _H.GetBarAuraState
local SetBarAuraState = _H.SetBarAuraState
local GetBarAuraSpellId = _H.GetBarAuraSpellId
local GetBarAuraUnit = _H.GetBarAuraUnit
local GetIconTalentCond = _H.GetIconTalentCond
local GetIconTalentTristate = _H.GetIconTalentTristate
local SetIconTalentTristate = _H.SetIconTalentTristate
local GetIconTalentKey = _H.GetIconTalentKey
local GetIconUnitHPCond = _H.GetIconUnitHPCond
local GetIconUnitHPEnabled = _H.GetIconUnitHPEnabled
local SetIconUnitHPEnabled = _H.SetIconUnitHPEnabled

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
