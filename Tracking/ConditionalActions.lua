local _, ns = ...

local Conditionals = ns.AuraTracker.Conditionals

-- Localize globals needed by action evaluation
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitExists = UnitExists
local GetNumRaidMembers = GetNumRaidMembers
local GetNumPartyMembers = GetNumPartyMembers
local GetTime = GetTime
local GetTalentInfo = GetTalentInfo
local GetTalentTabInfo = GetTalentTabInfo
local GetNumTalentTabs = GetNumTalentTabs
local GetNumTalents = GetNumTalents
local GetGlyphSocketInfo = GetGlyphSocketInfo
local GetNumGlyphSockets = GetNumGlyphSockets
local GetSpellInfo = GetSpellInfo
local SendChatMessage = SendChatMessage
local UnitName = UnitName
local PlaySoundFile = PlaySoundFile
local LSM = LibStub("LibSharedMedia-3.0")
local math_floor = math.floor
local string_format = string.format
local string_gsub = string.gsub

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
    player      = "Player",
    target      = "Target",
    focus       = "Focus",
    smart_group = "Smart Group",
}

--- Check one action condition.
--- `item` is the TrackedItem for remaining/stacks checks.
function Conditionals:CheckActionCondition(cond, item)
    local check = cond.check

    if check == "unit_hp" then
        return CheckUnitPct(cond.unit or "target", UnitHealth, UnitHealthMax, cond.op, cond.value)

    elseif check == "unit_power" then
        return CheckUnitPct(cond.unit or "player", UnitPower, UnitPowerMax, cond.op, cond.value)

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
--- Also returns:
---   shouldDesaturate  (bool) – true when at least one met conditional has desaturate=true.
---   hasDesaturateConds (bool) – true when at least one conditional has desaturate=true at all.
--- The caller should only touch icon saturation when hasDesaturateConds is true.
function Conditionals:EvaluateActions(condList, condState, item)
    if not condList then
        return false, nil, false, false
    end

    local glowActive = false
    local glowColor = nil
    local shouldDesaturate = false
    local hasDesaturateConds = false

    for i, cond in ipairs(condList) do
        local met = self:CheckActionCondition(cond, item)
        local wasMet = condState[i]

        if cond.desaturate then
            hasDesaturateConds = true
        end

        if met then
            if cond.glow then
                glowActive = true
                if cond.glowColor then
                    glowColor = cond.glowColor
                end
            end
            if cond.desaturate then
                shouldDesaturate = true
            end
            if wasMet == false and cond.sound and cond.sound ~= "NONE" and cond.sound ~= "None" then
                self:PlaySoundForKey(cond.sound)
            end
        end

        condState[i] = met
    end

    return glowActive, glowColor, shouldDesaturate, hasDesaturateConds
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
-- GLYPH HELPERS
-- ==========================================================

--- Return the effective spell ID for a glyph socket.
--- In WotLK 3.3.5 the API returns (enabled, glyphType, tooltipIndex, spellId).
--- Some private-server builds only fill one of the two ID positions, so we
--- prefer position 4 (spellId) and fall back to position 3 (tooltipIndex).
function Conditionals:_GetGlyphSocketSpellId(tooltipIndex, spellId)
    return spellId or tooltipIndex
end

-- ==========================================================
-- GLYPH LIST BUILDER
-- ==========================================================

function Conditionals:_BuildGlyphList()
    local list = {}
    local numSockets = (GetNumGlyphSockets and GetNumGlyphSockets()) or 6
    for i = 1, numSockets do
        local enabled, _, glyphTooltipIndex, glyphSpellId = GetGlyphSocketInfo(i)
        local id = self:_GetGlyphSocketSpellId(glyphTooltipIndex, glyphSpellId)
        if enabled and id then
            local name = GetSpellInfo(id)
            if name and not list[id] then
                list[id] = name
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

-- UI builder methods (BuildLoadConditionUI, BuildActionConditionUI,
-- BuildConditionUI, BuildIconActionsUI) are defined in ConditionUI.lua
-- to keep this file focused on evaluation logic.

-- ==========================================================
-- ICON ACTIONS  (On Click / On Show / On Hide)
-- ==========================================================
-- Each trigger (onClick, onShow, onHide) holds an ordered array of
-- action definitions.  An action has a `type` field:
--   "chat"  – send a chat message (with text replacements)
--   "sound" – play a sound via LibSharedMedia
--   "glow"  – enable or disable the icon glow

Conditionals.IconActionType = {
    CHAT  = "chat",
    SOUND = "sound",
    GLOW  = "glow",
}

Conditionals.ChatChannels = {
    SAY   = "SAY",
    YELL  = "YELL",
    PARTY = "PARTY",
    RAID  = "RAID",
    EMOTE = "EMOTE",
    SMART = "SMART",  -- Raid > Party > Say
}

Conditionals.MAX_ICON_ACTIONS = 5  -- per trigger

-- Text replacement tokens (applied to chat messages before sending).
-- Resolved at fire-time, so the item reference is always fresh.
function Conditionals:ApplyTextReplacements(msg, item)
    if not msg or not item then return msg end
    -- %name → spell / item name
    msg = string_gsub(msg, "%%name", item:GetName() or "")
    -- %stack → current stack count (or 0)
    local stacks = (item.GetStacks and item:GetStacks()) or 0
    msg = string_gsub(msg, "%%stack", tostring(stacks))
    -- %remaining → remaining time in seconds (integer)
    local remaining = (item.GetRemaining and item:GetRemaining()) or 0
    msg = string_gsub(msg, "%%remaining", tostring(math_floor(remaining)))
    -- %target → current target name
    local targetName = UnitName("target") or ""
    msg = string_gsub(msg, "%%target", targetName)
    -- %player → player name
    local playerName = UnitName("player") or ""
    msg = string_gsub(msg, "%%player", playerName)
    -- %spelllink → spell hyperlink (falls back to spell name if unavailable)
    local spellId = item:GetId()
    local link = (type(spellId) == "number" and spellId > 0)
        and (GetSpellLink and GetSpellLink(spellId))
        or nil
    msg = string_gsub(msg, "%%spelllink", link or (item:GetName() or ""))
    return msg
end

--- Execute a single icon action.
--- `item` is the TrackedItem (may be nil for pure event actions).
--- Returns the glow request: true = request glow on, false = request off, nil = no change.
function Conditionals:ExecuteSingleIconAction(action, item)
    local t = action.type
    if t == "chat" then
        local msg = action.message or ""
        if item then
            msg = self:ApplyTextReplacements(msg, item)
        end
        if msg ~= "" then
            local channel = action.channel or "SAY"
            if channel == "SMART" then
                if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                    channel = "RAID"
                elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
                    channel = "PARTY"
                else
                    channel = "SAY"
                end
            end
            if SendChatMessage then
                SendChatMessage(msg, channel)
            end
        end

    elseif t == "sound" then
        self:PlaySoundForKey(action.sound)

    elseif t == "glow" then
        return action.glow  -- true = on, false = off
    end

    return nil
end

--- Execute a list of icon actions.
--- Returns: glowActive (bool|nil), glowColor (table|nil)
--- glowActive is nil when no glow action was present in the list.
function Conditionals:ExecuteIconActions(actions, item)
    if not actions or #actions == 0 then
        return nil, nil
    end

    local glowActive = nil
    local glowColor  = nil

    for _, action in ipairs(actions) do
        local g = self:ExecuteSingleIconAction(action, item)
        if g ~= nil then
            glowActive = g
            if g and action.glowColor then
                glowColor = action.glowColor
            end
        end
    end

    return glowActive, glowColor
end
