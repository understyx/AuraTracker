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
        local inCombat = UnitAffectingCombat("player") and true or false
        return (cond.value == "yes") == inCombat

    elseif check == "alive" then
        local isDead = UnitIsDeadOrGhost("player") and true or false
        if cond.value == "alive" then return not isDead end
        return isDead

    elseif check == "has_vehicle_ui" then
        local hasUI = (UnitHasVehicleUI and UnitHasVehicleUI("player"))
                   or (UnitInVehicle and UnitInVehicle("player"))
                   or false
        return (cond.value == "yes") == (hasUI and true or false)

    elseif check == "mounted" then
        local mounted = IsMounted and IsMounted() or false
        return (cond.value == "yes") == (mounted and true or false)

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
        return hasRank and true or false

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

-- ==========================================================
-- UI: LOAD CONDITION BUILDER
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
            args[prefix .. "glyphSelect"] = {
                type = "select",
                name = "Glyph",
                desc = "Select one of your currently inscribed glyphs.",
                values = function() return self:_BuildGlyphList() end,
                order = condBase + 0.02,
                width = "double",
                get = function() return cond.glyphSpellId end,
                set = function(_, val)
                    cond.glyphSpellId = val
                    notifyFn(barKey)
                end,
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

local actionCheckLabels = {
    ["unit_hp"]    = "Unit HP %",
    ["unit_power"] = "Unit Power %",
    ["remaining"]  = "Remaining Duration",
    ["stacks"]     = "Stack Count",
}

--- Build AceConfig args for action conditionals (icon-only: glow + sound).
function Conditionals:BuildActionConditionUI(args, owner, orderBase, barKey, notifyFn)
    local soundValues = { ["NONE"] = "None" }
    for key, snd in pairs(self.SoundOptions) do
        soundValues[key] = snd.label
    end

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
            args[prefix .. "unit"] = {
                type = "select",
                name = "Unit",
                values = self.HPUnits,
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
            values = soundValues,
            order = condBase + 0.05,
            get = function() return cond.sound or "NONE" end,
            set = function(_, val)
                cond.sound = (val ~= "NONE") and val or nil
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
