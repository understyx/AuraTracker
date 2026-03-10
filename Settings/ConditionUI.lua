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
-- UI: LOAD CONDITION BUILDER
-- ==========================================================

--- Build AceConfig args for load conditions.
--- @param args      table   Args table to inject into
--- @param owner     table   DB table that has .loadConditions
--- @param orderBase number  Order base
--- @param barKey    string  Bar key
--- @param notifyFn  function  Called after changes
--- @param mode      string  "bar" or "icon"
function Conditionals:BuildLoadConditionUI(args, owner, orderBase, barKey, notifyFn, mode)
    mode = mode or "bar"

    local checkLabels = (mode == "icon") and loadCheckLabelsIcon or loadCheckLabelsShared

    owner.loadConditions = owner.loadConditions or {}
    local maxCond = self.MAX_LOAD_CONDITIONS

    args.loadCondHeader = {
        type = "header",
        name = "Load Conditions",
        order = orderBase,
    }
    args.loadCondDesc = {
        type = "description",
        name = "|cFFAAAAFFAll conditions must be met for this "
            .. (mode == "bar" and "bar" or "icon")
            .. " to be visible.|r",
        order = orderBase + 0.1,
        width = "full",
    }

    if #owner.loadConditions < maxCond then
        args.loadCondAdd = {
            type = "execute",
            name = "+ Add Load Condition",
            order = orderBase + 0.2,
            width = "normal",
            func = function()
                table.insert(owner.loadConditions, {
                    check = "in_combat",
                    value = "yes",
                })
                notifyFn(barKey)
            end,
        }
    end

    for ci, cond in ipairs(owner.loadConditions) do
        local condBase = orderBase + 0.5 + (ci - 1) * 0.15
        local prefix = "loadCond" .. ci .. "_"
        local check = cond.check

        args[prefix .. "header"] = {
            type = "header",
            name = "Load " .. ci,
            order = condBase,
        }
        args[prefix .. "check"] = {
            type = "select",
            name = "Condition",
            values = checkLabels,
            order = condBase + 0.01,
            get = function() return cond.check or "in_combat" end,
            set = function(_, val)
                cond.check = val
                -- Reset value on type change
                if val == "in_combat" or val == "has_vehicle_ui" or val == "mounted" then
                    cond.value = "yes"
                elseif val == "alive" then
                    cond.value = "alive"
                elseif val == "in_group" then
                    cond.value = "group"
                elseif val == "unit_hp" then
                    cond.value = 35
                    cond.op = "<="
                    cond.unit = "target"
                elseif val == "talent" then
                    cond.talentKey = nil
                    cond.talentState = true
                elseif val == "glyph" then
                    cond.glyphSpellId = nil
                end
                notifyFn(barKey)
            end,
        }

        -- Yes/No toggles
        if check == "in_combat" or check == "has_vehicle_ui" or check == "mounted" then
            args[prefix .. "value"] = {
                type = "select",
                name = "Value",
                values = self.YesNo,
                order = condBase + 0.02,
                width = "half",
                get = function() return cond.value or "yes" end,
                set = function(_, val)
                    cond.value = val
                    notifyFn(barKey)
                end,
            }
        elseif check == "alive" then
            args[prefix .. "value"] = {
                type = "select",
                name = "Value",
                values = self.AliveValues,
                order = condBase + 0.02,
                width = "half",
                get = function() return cond.value or "alive" end,
                set = function(_, val)
                    cond.value = val
                    notifyFn(barKey)
                end,
            }
        elseif check == "in_group" then
            args[prefix .. "value"] = {
                type = "select",
                name = "Value",
                values = self.GroupValues,
                order = condBase + 0.02,
                get = function() return cond.value or "group" end,
                set = function(_, val)
                    cond.value = val
                    notifyFn(barKey)
                end,
            }
        elseif check == "unit_hp" then
            args[prefix .. "unit"] = {
                type = "select",
                name = "Unit",
                values = self.HPUnits,
                order = condBase + 0.02,
                width = "half",
                get = function() return cond.unit or "target" end,
                set = function(_, val)
                    cond.unit = val
                    notifyFn(barKey)
                end,
            }
            args[prefix .. "op"] = {
                type = "select",
                name = "Operator",
                values = condOpLabels,
                order = condBase + 0.03,
                width = "half",
                get = function() return cond.op or "<=" end,
                set = function(_, val)
                    cond.op = val
                    notifyFn(barKey)
                end,
            }
            args[prefix .. "val"] = {
                type = "input",
                name = "HP %",
                desc = "Health percent (0-100)",
                order = condBase + 0.04,
                width = "half",
                get = function() return tostring(cond.value or 35) end,
                set = function(_, val)
                    cond.value = tonumber(val) or 35
                    notifyFn(barKey)
                end,
            }
        elseif check == "talent" then
            args[prefix .. "talentSelect"] = {
                type          = "multiselect",
                dialogControl = "AuraTrackerMiniTalent",
                name          = "Talent",
                order         = condBase + 0.02,
                width         = "full",
                values        = function()
                    return self:_BuildTalentList()
                end,
                get = function(_, key)
                    if not cond.talentKey then return nil end
                    if key == cond.talentKey then
                        return cond.talentState
                    end
                    return nil
                end,
                set = function(_, key, value)
                    if value == nil and key == cond.talentKey then
                        cond.talentKey = nil
                        cond.talentState = nil
                    else
                        cond.talentKey = key
                        cond.talentState = value
                    end
                    notifyFn(barKey)
                end,
            }
        elseif check == "glyph" then
            args[prefix .. "glyphSpellId"] = {
                type  = "input",
                name  = "Glyph Spell ID",
                desc  = "Enter the spell ID of the glyph to check.\n"
                    .. "You can find glyph spell IDs on wowhead or by using\n"
                    .. "/script print(GetSpellInfo(id)) in-game.",
                order = condBase + 0.02,
                width = "half",
                get   = function() return tostring(cond.glyphSpellId or "") end,
                set   = function(_, val)
                    local n = tonumber(val)
                    cond.glyphSpellId = (n and n > 0) and n or nil
                    notifyFn(barKey)
                end,
            }
            args[prefix .. "glyphName"] = {
                type  = "description",
                name  = function()
                    if cond.glyphSpellId then
                        local name = GetSpellInfo(cond.glyphSpellId)
                        if name then
                            return "|cFF00FF00" .. name .. "|r"
                        end
                        return "|cFFFF4400Unknown spell ID|r"
                    end
                    return "|cFFAAAAFFEnter a spell ID to the left.|r"
                end,
                order = condBase + 0.03,
                width = "half",
            }
        end

        args[prefix .. "remove"] = {
            type = "execute",
            name = "Remove",
            order = condBase + 0.09,
            width = "half",
            func = function()
                table.remove(owner.loadConditions, ci)
                notifyFn(barKey)
            end,
        }
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
        name = "|cFFAAAAFFTrigger glow or sound on this icon when conditions are met.\n"
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

local chatChannelLabels = {
    ["SAY"]   = "Say",
    ["YELL"]  = "Yell",
    ["PARTY"] = "Party",
    ["RAID"]  = "Raid",
    ["EMOTE"] = "Emote",
}

local iconActionTriggerInfo = {
    { key = "onClickActions", label = "On Click",  desc = "Actions fired when the icon is clicked." },
    { key = "onShowActions",  label = "On Show",   desc = "Actions fired when the icon becomes visible." },
    { key = "onHideActions",  label = "On Hide",   desc = "Actions fired when the icon becomes hidden." },
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
            .. "Chat message tokens: %name, %stack, %remaining, %target, %player|r",
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
                values = iconActionTypeLabels,
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
                    desc  = "Message to send. Tokens: %name, %stack, %remaining, %target, %player",
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
