local addonName, ns = ...

local pairs, ipairs, next = pairs, ipairs, next
local tonumber, tostring = tonumber, tostring
local table_insert, table_sort, table_remove = table.insert, table.sort, table.remove
local math_max, math_min, math_floor = math.max, math.min, math.floor
local string_format, string_upper = string.format, string.upper
local GetSpellInfo, GetItemInfo = GetSpellInfo, GetItemInfo
local GetInventoryItemTexture = GetInventoryItemTexture

local LibEditmode = LibStub("LibEditmode-1.0", true)

-- ==========================================================
-- CONSTANTS & LABELS
-- ==========================================================

local L = {
    CLASSES = {
        ["NONE"] = "Any Class",
        ["WARRIOR"] = "Warrior", ["PALADIN"] = "Paladin", ["HUNTER"] = "Hunter",
        ["ROGUE"] = "Rogue", ["PRIEST"] = "Priest", ["DEATHKNIGHT"] = "Death Knight",
        ["SHAMAN"] = "Shaman", ["MAGE"] = "Mage", ["WARLOCK"] = "Warlock",
        ["DRUID"] = "Druid",
    },
    DIRECTIONS = {
        ["HORIZONTAL"] = "Horizontal",
        ["VERTICAL"]   = "Vertical",
    },
    AURA_SOURCES = {
        ["player_buff"]        = "Player – Buff",
        ["player_debuff"]      = "Player – Debuff",
        ["target_buff"]        = "Target – Buff",
        ["target_debuff"]      = "Target – Debuff",
        ["focus_buff"]         = "Focus – Buff",
        ["focus_debuff"]       = "Focus – Debuff",
        ["smart_group_buff"]   = "Smart Group – Buff",
        ["smart_group_debuff"] = "Smart Group – Debuff",
    },
    AURA_UNITS = {
        ["player"]      = "Player",
        ["target"]      = "Target",
        ["focus"]       = "Focus",
        ["smart_group"] = "Smart Group",
    },
    AURA_FILTER_TYPES = {
        ["HELPFUL"] = "Buff",
        ["HARMFUL"] = "Debuff",
    },
    -- Display-mode labels that make sense for cooldowns
    COOLDOWN_DISPLAY_MODES = {
        ["always"]       = "Always Show",
        ["active_only"]  = "Show When Ready",
        ["missing_only"] = "Show On Cooldown",
    },
    -- Display-mode labels that make sense for auras
    AURA_DISPLAY_MODES = {
        ["always"]       = "Always Show",
        ["active_only"]  = "Show When Active",
        ["missing_only"] = "Show When Missing",
    },
    TRACK_TYPES = {
        ["cooldown"]       = "Cooldown",
        ["aura"]           = "Aura",
        ["item"]           = "Item",
        ["cooldown_aura"]  = "Cooldown + Aura",
        ["internal_cd"]    = "Trinket ICD",
        ["weapon_enchant"] = "Weapon Enchant",
    },
    DUAL_DISPLAY_MODES = {
        ["always"]       = "Always Show",
        ["active_only"]  = "Show When Ready",
        ["missing_only"] = "Show When Unavailable",
    },
}

-- ==========================================================
-- SESSION STATE  (UI-only; not persisted)
-- ==========================================================

local editState = {
    selectedBar    = nil,
    selectedAura   = nil,
    -- Add-icon form state (persists across option rebuilds)
    addTrackType   = "cooldown",
    addIconId      = "",
}

-- ==========================================================
-- HELPERS
-- ==========================================================

local function GetSpellNameByID(spellId)
    local name, _, icon = GetSpellInfo(spellId)
    return name or "Unknown Spell", icon
end

local function GetItemNameByID(itemId)
    local name, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemId)
    return name or "Unknown Item", texture
end

local function GetTrackedNameAndIcon(id, trackType)
    if trackType == "item" or trackType == "internal_cd" then
        return GetItemNameByID(id)
    end
    if trackType == "weapon_enchant" then
        local Config = ns.AuraTracker.Config
        if Config and id == Config.MAINHAND_ENCHANT_SLOT_ID then
            return "Mainhand Enchant", GetInventoryItemTexture("player", 16)
        elseif Config and id == Config.OFFHAND_ENCHANT_SLOT_ID then
            return "Offhand Enchant", GetInventoryItemTexture("player", 17)
        end
        return GetItemNameByID(id)
    end
    if trackType == "totem" then
        local Config = ns.AuraTracker.Config
        if Config then
            return Config:GetTotemElementName(id), Config:GetTotemElementIcon(id)
        end
        return "Totem", nil
    end
    return GetSpellNameByID(id)
end

local function GetTrackTypeLabel(trackType, filterKey)
    if trackType == "aura" then
        local src = filterKey and L.AURA_SOURCES[filterKey] or "aura"
        return "|cFFAAFFAA" .. src .. "|r"
    end
    if trackType == "item" then
        return "|cFFFFD700item|r"
    end
    if trackType == "internal_cd" then
        return "|cFFFF8800trinket ICD|r"
    end
    if trackType == "weapon_enchant" then
        return "|cFFAAFF88weapon enchant|r"
    end
    if trackType == "totem" then
        return "|cFFFF9944totem|r"
    end
    if trackType == "cooldown_aura" then
        local src = filterKey and L.AURA_SOURCES[filterKey] or "aura"
        return "|cFFAAD4FFcooldown|r + |cFFAAFFAA" .. src .. "|r"
    end
    return "|cFFAAD4FFcooldown|r"
end

local function RebuildBar(barKey)
    if ns.AuraTracker and ns.AuraTracker.Controller then
        ns.AuraTracker.Controller:RebuildBar(barKey)
    end
end

local function NotifyChange()
    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
end

local function NotifyAndRebuild(barKey)
    RebuildBar(barKey)
    NotifyChange()
end

local function GetBarDisplayName(barData, key)
    local classKey = barData.classRestriction or "NONE"
    local barName  = barData.name or key
    if classKey == "NONE" then
        return "All: " .. barName
    end
    local classLabel = L.CLASSES[classKey] or classKey
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classKey]
    if color then
        local hex = string_format("%02X%02X%02X",
            math_floor((color.r or 0) * 255),
            math_floor((color.g or 0) * 255),
            math_floor((color.b or 0) * 255))
        return "|cFF" .. hex .. classLabel .. ":|r " .. barName
    end
    return classLabel .. ": " .. barName
end

local function GetFilterData(filterKey)
    local Config = ns.AuraTracker and ns.AuraTracker.Config
    if not Config or not filterKey then return nil end
    return Config:GetAuraFilter(string_upper(filterKey))
end

-- ==========================================================
-- TALENT LIST BUILDER  (delegates to Conditionals module)
-- ==========================================================

local function BuildTalentList()
    local Conditionals = ns.AuraTracker and ns.AuraTracker.Conditionals
    if Conditionals then
        return Conditionals:_BuildTalentList()
    end
    return {}
end

-- ==========================================================
-- CLASS GROUP HELPERS  (used by UpdateBarOptions + SettingsPanel)
-- ==========================================================

-- Returns the normalised bucket key ("NONE" or an uppercase class token)
-- for a given classRestriction value stored in bar DB data.
local function GetClassGroupKey(classRestriction)
    if classRestriction and classRestriction ~= "NONE" and classRestriction ~= "" then
        return classRestriction
    end
    return "NONE"
end

-- Returns the coloured display label used for a class-group heading in the
-- settings tree.  "NONE" maps to "Any Class"; other keys get RAID_CLASS_COLORS
-- colouring when available.
local function GetClassGroupName(classKey)
    if classKey == "NONE" then return "Any Class" end
    local classLabel = L.CLASSES[classKey] or classKey
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classKey]
    if color then
        local hex = string_format("%02X%02X%02X",
            math_floor((color.r or 0) * 255),
            math_floor((color.g or 0) * 255),
            math_floor((color.b or 0) * 255))
        return "|cFF" .. hex .. classLabel .. "|r"
    end
    return classLabel
end

-- ==========================================================
-- ICON ORDER HELPERS
-- ==========================================================

local function NormalizeAuraOrders(barData)
    if not barData.trackedItems then return end
    local sorted = {}
    for spellId, data in pairs(barData.trackedItems) do
        table_insert(sorted, { id = spellId, order = data.order or 999 })
    end
    table_sort(sorted, function(a, b) return a.order < b.order end)
    for i, item in ipairs(sorted) do
        barData.trackedItems[item.id].order = i
    end
end

local function MoveIconToPosition(barKey, barData, spellId, newPos)
    if not barData or not barData.trackedItems then return end
    NormalizeAuraOrders(barData)
    local sorted = {}
    for sid, d in pairs(barData.trackedItems) do
        table_insert(sorted, { spellId = sid, order = d.order or 999 })
    end
    table_sort(sorted, function(a, b) return a.order < b.order end)
    -- Find current position
    local currentPos
    for i, entry in ipairs(sorted) do
        if entry.spellId == spellId then
            currentPos = i
            break
        end
    end
    if not currentPos then return end
    newPos = math_max(1, math_min(newPos, #sorted))
    if currentPos == newPos then return end
    -- Remove from current and insert at new position
    local item = table_remove(sorted, currentPos)
    table_insert(sorted, newPos, item)
    -- Renumber all orders
    for i, entry in ipairs(sorted) do
        barData.trackedItems[entry.spellId].order = i
    end
    NotifyAndRebuild(barKey)
end

-- ==========================================================
-- EXPORT SHARED UTILITIES
-- ==========================================================
-- These are used by IconEditorUI.lua and BarSettingsUI.lua
-- which load after this file.

ns.AuraTracker = ns.AuraTracker or {}
ns.AuraTracker.SettingsUtils = {
    L = L,
    editState = editState,
    NotifyChange = NotifyChange,
    NotifyAndRebuild = NotifyAndRebuild,
    RebuildBar = RebuildBar,
    GetSpellNameByID = GetSpellNameByID,
    GetItemNameByID = GetItemNameByID,
    GetTrackedNameAndIcon = GetTrackedNameAndIcon,
    GetTrackTypeLabel = GetTrackTypeLabel,
    GetFilterData = GetFilterData,
    NormalizeAuraOrders = NormalizeAuraOrders,
    MoveIconToPosition = MoveIconToPosition,
    GetBarDisplayName = GetBarDisplayName,
    BuildTalentList = BuildTalentList,
    GetClassGroupKey = GetClassGroupKey,
    GetClassGroupName = GetClassGroupName,
}

