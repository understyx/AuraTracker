local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local Config = ns.AuraTracker.Config
local PlaySoundFile = PlaySoundFile
local GetTime = GetTime
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitInVehicle = UnitInVehicle
local GetNumRaidMembers = GetNumRaidMembers
local GetNumPartyMembers = GetNumPartyMembers
local GetTalentInfo, GetNumTalentTabs, GetNumTalents = GetTalentInfo, GetNumTalentTabs, GetNumTalents
local GetTalentTabInfo = GetTalentTabInfo

-- ==========================================================
-- ENUMS / CONSTANTS
-- ==========================================================

local Conditionals = {}
ns.AuraTracker.Conditionals = Conditionals

-- Sound files available for conditional triggers.
-- Keys are stored in saved variables; file paths are WotLK-safe.
Conditionals.SoundOptions = {
    NONE         = { label = "None",         file = nil },
    RAID_WARNING = { label = "Raid Warning", file = [[Sound\Interface\RaidWarning.wav]] },
    ALARM        = { label = "Alarm Clock",  file = [[Sound\Interface\AlarmClockWarning3.wav]] },
    MAP_PING     = { label = "Map Ping",     file = [[Sound\Interface\MapPing.wav]] },
    LEVEL_UP     = { label = "Level Up",     file = [[Sound\Interface\LevelUp.wav]] },
    PVP_QUEUE    = { label = "PvP Queue",    file = [[Sound\Spells\PVPEnterQueue.wav]] },
    BELL         = { label = "Bell",         file = [[Sound\Spells\ShaysBell.wav]] },
}

-- What to check (for icon conditionals these use the icon's tracked item):
Conditionals.ConditionCheck = {
    ACTIVE     = "active",      -- item is active (aura present / off cooldown)
    INACTIVE   = "inactive",    -- item is inactive (aura missing / on cooldown)
    REMAINING  = "remaining",   -- seconds remaining on the active timer (> 0 only)
    STACKS     = "stacks",      -- buff/debuff stack count
    UNIT_HP    = "unit_hp",     -- unit health percent (0-100)
    TALENT     = "talent",      -- talent selected (has at least 1 point)
    IN_VEHICLE = "in_vehicle",  -- player is in a vehicle
    IN_RAID    = "in_raid",     -- player is in a raid group
    IN_GROUP   = "in_group",    -- player is in a party or raid
}

-- Comparison operators for numeric checks (remaining, stacks, unit_hp):
Conditionals.ConditionOp = {
    LT  = "<",
    LTE = "<=",
    GT  = ">",
    GTE = ">=",
    EQ  = "==",
}

-- Maximum number of conditionals allowed per icon or bar
Conditionals.MAX_CONDITIONALS = 3

-- Units available for the unit_hp check
Conditionals.HPUnits = {
    player = "Player",
    target = "Target",
    focus  = "Focus",
}

-- ==========================================================
-- EVALUATION HELPERS
-- ==========================================================

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

--- Check a single condition. For icon-level conditionals, `item` is the TrackedItem.
--- For bar-level conditionals, `item` may be nil (only non-item checks apply).
function Conditionals:CheckCondition(cond, item)
    local check = cond.check

    if check == "active" then
        return item and item:IsActive() or false
    elseif check == "inactive" then
        return item and (not item:IsActive()) or false
    elseif check == "remaining" then
        if not item then return false end
        local remaining = item:GetRemaining()
        if remaining <= 0 then return false end
        return self:CompareValue(remaining, cond.op, cond.value)
    elseif check == "stacks" then
        if not item then return false end
        local stacks = item:GetStacks() or 0
        return self:CompareValue(stacks, cond.op, cond.value)
    elseif check == "unit_hp" then
        local unit = cond.unit or "target"
        local maxHP = UnitHealthMax(unit)
        if not maxHP or maxHP == 0 then return false end
        local pct = (UnitHealth(unit) / maxHP) * 100
        return self:CompareValue(pct, cond.op, cond.value)
    elseif check == "talent" then
        local talentKey = cond.talentKey  -- combinedIndex (tab-1)*maxTalents+i
        if not talentKey then return false end
        local maxTalents = MAX_NUM_TALENTS or 30
        local numTabs = GetNumTalentTabs and GetNumTalentTabs() or 0
        if numTabs == 0 then return false end
        local tab = math.ceil(talentKey / maxTalents)
        local talentIndex = talentKey - (tab - 1) * maxTalents
        if tab < 1 or tab > numTabs then return false end
        local name, iconTex, tier, col, rank = GetTalentInfo(tab, talentIndex)
        local hasRank = rank and rank > 0
        if cond.talentState == false then
            -- "excluded" means condition met when talent NOT learned
            return not hasRank
        else
            -- default: condition met when talent IS learned
            return hasRank
        end
    elseif check == "in_vehicle" then
        return UnitInVehicle and UnitInVehicle("player") or false
    elseif check == "in_raid" then
        return GetNumRaidMembers and (GetNumRaidMembers() > 0) or false
    elseif check == "in_group" then
        local inRaid = GetNumRaidMembers and (GetNumRaidMembers() > 0) or false
        local inParty = GetNumPartyMembers and (GetNumPartyMembers() > 0) or false
        return inRaid or inParty
    end

    return false
end

--- Evaluate an array of conditionals. Returns glow state + triggers sounds on transitions.
--- `condList` is the array of condition definitions.
--- `condState` is a table tracking previous evaluation per conditional (for sound transitions).
--- `item` is the TrackedItem (nil for bar-level conditionals).
--- Returns: glowActive (bool), glowColor (table or nil)
function Conditionals:Evaluate(condList, condState, item)
    if not condList then
        return false, nil
    end

    local glowActive = false
    local glowColor = nil

    for i, cond in ipairs(condList) do
        local met = self:CheckCondition(cond, item)
        local wasMet = condState[i]

        if met then
            if cond.glow then
                glowActive = true
                if cond.glowColor then
                    glowColor = cond.glowColor
                end
            end

            -- Sound: play only on transition from false→true.
            -- wasMet==false (not `not wasMet`) skips the first evaluation (nil)
            -- to prevent spurious sounds on load/rebuild.
            if wasMet == false and cond.sound and cond.sound ~= "NONE" then
                self:PlaySoundForKey(cond.sound)
            end
        end

        condState[i] = met
    end

    return glowActive, glowColor
end

--- Check all conditions as load-conditions (AND logic). Returns true if all are met.
--- Used for bar-level visibility. `condList` is the array of condition definitions.
--- `item` is nil for bar-level conditionals (only non-item checks apply).
function Conditionals:CheckAll(condList, item)
    if not condList or #condList == 0 then
        return true  -- no conditions = always visible
    end
    for _, cond in ipairs(condList) do
        if not self:CheckCondition(cond, item) then
            return false
        end
    end
    return true
end

-- ==========================================================
-- SHARED UI BUILDER  (AceConfig args for Settings.lua)
-- ==========================================================

--- Build AceConfig args for a conditionals section.
--- @param args      table   The args table to inject into
--- @param condOwner table   The DB table that has .conditionals (e.g. data or barData)
--- @param orderBase number  Order base for the UI entries
--- @param barKey    string  Bar key for NotifyAndRebuild
--- @param notifyFn  function Called after changes: notifyFn(barKey)
--- @param mode      string  "icon" or "bar" — controls which check types are available
function Conditionals:BuildConditionUI(args, condOwner, orderBase, barKey, notifyFn, mode)
    mode = mode or "icon"

    local condCheckLabels
    if mode == "icon" then
        condCheckLabels = {
            ["active"]     = "Active",
            ["inactive"]   = "Inactive",
            ["remaining"]  = "Remaining Time",
            ["stacks"]     = "Stacks",
            ["unit_hp"]    = "Unit HP %",
            ["talent"]     = "Talent Selected",
            ["in_vehicle"] = "In Vehicle",
            ["in_raid"]    = "In Raid",
            ["in_group"]   = "In Group (Raid or Party)",
        }
    else
        -- Bar-level conditionals: no item-dependent checks
        condCheckLabels = {
            ["unit_hp"]    = "Unit HP %",
            ["talent"]     = "Talent Selected",
            ["in_vehicle"] = "In Vehicle",
            ["in_raid"]    = "In Raid",
            ["in_group"]   = "In Group (Raid or Party)",
        }
    end

    local condOpLabels = {
        ["<"]  = "< (Less Than)",
        ["<="] = "<= (At Most)",
        [">"]  = "> (Greater Than)",
        [">="] = ">= (At Least)",
        ["=="] = "== (Equal To)",
    }

    local soundValues = { ["NONE"] = "None" }
    for key, snd in pairs(self.SoundOptions) do
        soundValues[key] = snd.label
    end

    local hpUnitValues = {}
    for k, v in pairs(self.HPUnits) do
        hpUnitValues[k] = v
    end

    condOwner.conditionals = condOwner.conditionals or {}
    local maxCond = self.MAX_CONDITIONALS

    args.editorCondHeader = {
        type = "header",
        name = mode == "bar" and "Load Conditions" or "Conditional Actions",
        order = orderBase,
    }
    args.editorCondDesc = {
        type = "description",
        name = mode == "bar"
            and "|cFFAAAAFFDefine load conditions for this bar.\nAll conditions must be met for the bar to be visible.|r"
            or  "|cFFAAAAFFDefine conditions that trigger glow, sound, or color changes on this icon.\nConditions are evaluated each update; sounds play only on transition.|r",
        order = orderBase + 0.1,
        width = "full",
    }

    if #condOwner.conditionals < maxCond then
        args.editorCondAdd = {
            type = "execute",
            name = "+ Add Condition",
            order = orderBase + 0.2,
            width = "normal",
            func = function()
                local defaultCheck = (mode == "icon") and "active" or "unit_hp"
                table.insert(condOwner.conditionals, {
                    check = defaultCheck,
                    op = "<=",
                    value = (defaultCheck == "unit_hp") and 35 or 5,
                    glow = false,
                    sound = nil,
                    glowColor = nil,
                    unit = "target",
                    talentKey = nil,
                    talentState = true,
                })
                notifyFn(barKey)
            end,
        }
    end

    for ci, cond in ipairs(condOwner.conditionals) do
        local condBase = orderBase + 0.5 + (ci - 1) * 0.1
        local prefix = "editorCond" .. ci .. "_"
        local isNumeric = (cond.check == "remaining" or cond.check == "stacks" or cond.check == "unit_hp")
        local isHP = (cond.check == "unit_hp")
        local isTalent = (cond.check == "talent")

        args[prefix .. "header"] = {
            type = "header",
            name = "Condition " .. ci,
            order = condBase,
        }
        args[prefix .. "check"] = {
            type = "select",
            name = "When",
            desc = "What state to check.",
            values = condCheckLabels,
            order = condBase + 0.01,
            get = function() return cond.check or "active" end,
            set = function(_, val)
                cond.check = val
                notifyFn(barKey)
            end,
        }
        if isHP then
            args[prefix .. "unit"] = {
                type = "select",
                name = "Unit",
                desc = "Which unit's health to check.",
                values = hpUnitValues,
                order = condBase + 0.015,
                width = "half",
                get = function() return cond.unit or "target" end,
                set = function(_, val)
                    cond.unit = val
                    notifyFn(barKey)
                end,
            }
        end
        if isNumeric then
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
            if cond.check == "remaining" then valDesc = "Seconds"
            elseif cond.check == "unit_hp" then valDesc = "Health percent (0-100)"
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
        end
        if isTalent then
            args[prefix .. "talentSelect"] = {
                type          = "multiselect",
                dialogControl = "AuraTrackerMiniTalent",
                name          = "Talent",
                order         = condBase + 0.025,
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
                        -- clear selection
                        cond.talentKey = nil
                        cond.talentState = nil
                    else
                        -- only allow one talent per condition
                        cond.talentKey = key
                        cond.talentState = value
                    end
                    notifyFn(barKey)
                end,
            }
        end
        if mode == "icon" then
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
        end
        args[prefix .. "remove"] = {
            type = "execute",
            name = "Remove",
            order = condBase + 0.07,
            width = "half",
            func = function()
                table.remove(condOwner.conditionals, ci)
                notifyFn(barKey)
            end,
        }
    end
end

--- Build talent list for the MiniTalent widget (shared helper).
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

    -- Background textures for each talent tab
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
