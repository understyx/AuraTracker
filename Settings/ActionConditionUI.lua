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
