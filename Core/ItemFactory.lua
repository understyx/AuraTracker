local _, ns = ...

local Config = ns.AuraTracker.Config
local TrackedItem = ns.AuraTracker.TrackedItem
local Icon = ns.AuraTracker.Icon

-- Localize frequently-used globals
local pairs, ipairs = pairs, ipairs
local GetSpellInfo, GetItemInfo = GetSpellInfo, GetItemInfo
local IsSpellKnown = IsSpellKnown
local math_max = math.max
local string_upper = string.upper

-- Library references
local LibFramePool = LibStub("LibFramePool-1.0")

-- The addon object (created in AuraTracker.lua)
local AuraTracker = ns.AuraTracker.Controller

-- ==========================================================
-- HELPERS
-- ==========================================================

-- Returns the next order value for a trackedItems table
local function GetNextOrder(trackedItems)
    local maxOrder = 0
    for _, data in pairs(trackedItems) do
        local order = type(data) == "table" and data.order or 0
        maxOrder = math_max(maxOrder, order)
    end
    return maxOrder + 1
end

-- Acquires a pooled frame, wraps it in an Icon, applies style settings, and
-- registers the icon with the bar.  All Create*Icon helpers share this logic.
local function CreateAndRegisterIcon(bar, item, order, styleOptions, displayMode)
    local frame = LibFramePool:Acquire(Icon.POOL_KEY, bar:GetFrame())
    local icon  = Icon:New(frame, item, displayMode)
    icon.order  = order
    icon:ApplyStyle(styleOptions)
    bar:AddIcon(icon)
    return icon
end

-- If spellId belongs to a preset exclusive group, adds all other group members
-- to entry.exclusiveSpells. Used by AddAura and AddCooldownAura.
local function ApplyExclusiveGroup(trackedItems, spellId)
    local presetKey = Config:GetPresetForSpell(spellId)
    if not presetKey then return end
    local preset = Config.ExclusivePresets[presetKey]
    if not preset then return end
    local entry = trackedItems[spellId]
    entry.exclusiveSpells = entry.exclusiveSpells or {}
    for groupSpellId in pairs(preset.spells) do
        if groupSpellId ~= spellId then
            entry.exclusiveSpells[groupSpellId] = true
        end
    end
end

-- ==========================================================
-- ICON CREATION
-- ==========================================================

function AuraTracker:CreateCooldownIcon(barKey, spellId, order, styleOptions, displayMode)
    local bar = self.bars[barKey]
    local db = self:GetBarDB(barKey)
    if not bar or not db then return nil end
    
    if db.showOnlyKnown and not (IsSpellKnown(spellId) or IsSpellKnown(spellId, true)) then
        return nil
    end
    
    local item = TrackedItem:New(spellId, Config.TrackType.COOLDOWN)
    if not item:GetName() then return nil end

    local resolvedMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.COOLDOWN)
    local icon = CreateAndRegisterIcon(bar, item, order, styleOptions, resolvedMode)
    self.items[barKey][spellId] = item
    return icon
end

function AuraTracker:CreateAuraIcon(barKey, spellId, filterKey, auraId, order, styleOptions, displayMode, onlyMine, exclusiveSpells)
    local bar = self.bars[barKey]
    if not bar then return nil end
    
    filterKey = filterKey and string_upper(filterKey:gsub(" ", "_")) or "TARGET_DEBUFF"
    
    local item = TrackedItem:New(spellId, Config.TrackType.AURA, {
        auraId = auraId,
        filterKey = filterKey,
        onlyMine = onlyMine,
        exclusiveSpells = exclusiveSpells,
    })
    if not item:GetName() then return nil end

    local resolvedMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.AURA, filterKey)
    local icon = CreateAndRegisterIcon(bar, item, order, styleOptions, resolvedMode)
    self.items[barKey]["aura_" .. spellId] = item
    return icon
end

function AuraTracker:CreateItemIcon(barKey, itemId, order, styleOptions, displayMode)
    local bar = self.bars[barKey]
    local db = self:GetBarDB(barKey)
    if not bar or not db then return nil end
    
    local item = TrackedItem:New(itemId, Config.TrackType.ITEM)
    if not item:GetName() then return nil end

    local resolvedMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.ITEM)
    local icon = CreateAndRegisterIcon(bar, item, order, styleOptions, resolvedMode)
    self.items[barKey]["item_" .. itemId] = item
    return icon
end

function AuraTracker:CreateInternalCDIcon(barKey, itemId, order, styleOptions, displayMode)
    local bar = self.bars[barKey]
    local db = self:GetBarDB(barKey)
    if not bar or not db then return nil end

    local item = TrackedItem:New(itemId, Config.TrackType.INTERNAL_CD)

    local resolvedMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.INTERNAL_CD)
    local icon = CreateAndRegisterIcon(bar, item, order, styleOptions, resolvedMode)
    self.items[barKey]["icd_" .. itemId] = item

    -- Register proc spell IDs for CLEU lookup
    local procSpells = item:GetProcSpellIds()
    if procSpells then
        self._procToItems = self._procToItems or {}
        for _, procId in ipairs(procSpells) do
            self._procToItems[procId] = self._procToItems[procId] or {}
            self._procToItems[procId][item] = true
        end
    end

    return icon
end

function AuraTracker:CreateCustomICDIcon(barKey, triggerSpellId, icdDuration, order, styleOptions, displayMode)
    local bar = self.bars[barKey]
    local db = self:GetBarDB(barKey)
    if not bar or not db then return nil end

    local item = TrackedItem:New(triggerSpellId, Config.TrackType.CUSTOM_ICD, {
        icdDuration = icdDuration or Config.DEFAULT_ICD,
    })
    if not item:GetName() then return nil end

    local resolvedMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.CUSTOM_ICD)
    local icon = CreateAndRegisterIcon(bar, item, order, styleOptions, resolvedMode)
    self.items[barKey]["cicd_" .. triggerSpellId] = item

    -- Register trigger spell ID for CLEU proc lookup
    self._procToItems = self._procToItems or {}
    self._procToItems[triggerSpellId] = self._procToItems[triggerSpellId] or {}
    self._procToItems[triggerSpellId][item] = true

    return icon
end

function AuraTracker:CreateCooldownAuraIcon(barKey, spellId, filterKey, auraId, order, styleOptions, displayMode, onlyMine, exclusiveSpells)
    local bar = self.bars[barKey]
    local db = self:GetBarDB(barKey)
    if not bar or not db then return nil end
    
    if db.showOnlyKnown and not (IsSpellKnown(spellId) or IsSpellKnown(spellId, true)) then
        return nil
    end
    
    filterKey = filterKey and string_upper(filterKey:gsub(" ", "_")) or "TARGET_DEBUFF"
    
    local item = TrackedItem:New(spellId, Config.TrackType.COOLDOWN_AURA, {
        auraId = auraId,
        filterKey = filterKey,
        onlyMine = onlyMine,
        exclusiveSpells = exclusiveSpells,
    })
    if not item:GetName() then return nil end

    local resolvedMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.COOLDOWN_AURA)
    local icon = CreateAndRegisterIcon(bar, item, order, styleOptions, resolvedMode)
    self.items[barKey]["cda_" .. spellId] = item
    return icon
end

-- ==========================================================
-- ADD / REMOVE TRACKED ITEMS
-- ==========================================================

function AuraTracker:AddCooldown(barKey, spellId)
    local db = self:GetBarDB(barKey)
    if not db then return false, "Bar not found" end
    
    local name = GetSpellInfo(spellId)
    if not name then return false, "Spell not found" end
    
    db.trackedItems = db.trackedItems or {}
    if db.trackedItems[spellId] then return false, "Already tracked" end
    
    db.trackedItems[spellId] = { 
        order = GetNextOrder(db.trackedItems),
        trackType = Config.TrackType.COOLDOWN,
        displayMode = Config.DisplayMode.ALWAYS,
    }
    self:RebuildBar(barKey)
    
    return true, name
end

function AuraTracker:RemoveCooldown(barKey, spellId)
    local db = self:GetBarDB(barKey)
    if not db or not db.trackedItems then return false end
    
    db.trackedItems[spellId] = nil
    self:RebuildBar(barKey)
    
    return true
end

function AuraTracker:AddAura(barKey, spellId, filterKey, specificAuraId, displayMode, onlyMine)
    local db = self:GetBarDB(barKey)
    if not db then return false, "Bar not found" end
    
    filterKey = filterKey or "TARGET_DEBUFF"
    local filterData = Config:GetAuraFilter(filterKey)
    if not filterData then return false, "Invalid filter type" end
    
    local name = GetSpellInfo(spellId)
    if not name then return false, "Spell not found" end
    
    local actualAuraId = specificAuraId or Config:GetMappedAuraId(spellId)
    
    db.trackedItems = db.trackedItems or {}
    if db.trackedItems[spellId] then return false, "Already tracked" end
    
    local finalDisplayMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.AURA, filterKey)
    
    -- Default to only tracking own auras (player usually wants their own debuffs)
    if onlyMine == nil then
        onlyMine = true
    end
    
    db.trackedItems[spellId] = {
        order = GetNextOrder(db.trackedItems),
        auraId = actualAuraId,
        type = filterKey:lower(),
        trackType = Config.TrackType.AURA,
        unit = filterData.unit,
        filter = filterData.filter,
        displayMode = finalDisplayMode,
        onlyMine = onlyMine,
    }

    -- Auto-link exclusive groups
    ApplyExclusiveGroup(db.trackedItems, spellId)

    self:RebuildBar(barKey)

    return true, name
end

function AuraTracker:RemoveAura(barKey, spellId)
    local db = self:GetBarDB(barKey)
    if not db or not db.trackedItems then return false end

    db.trackedItems[spellId] = nil
    self:RebuildBar(barKey)

    return true
end

function AuraTracker:AddItem(barKey, itemId)
    local db = self:GetBarDB(barKey)
    if not db then return false, "Bar not found" end
    
    local name = GetItemInfo(itemId)
    if not name then return false, "Item not found" end
    
    db.trackedItems = db.trackedItems or {}
    if db.trackedItems[itemId] then return false, "Already tracked" end
    
    db.trackedItems[itemId] = {
        order = GetNextOrder(db.trackedItems),
        trackType = Config.TrackType.ITEM,
        displayMode = Config.DisplayMode.ALWAYS,
    }
    self:RebuildBar(barKey)
    
    return true, name
end

function AuraTracker:AddInternalCD(barKey, itemId)
    local db = self:GetBarDB(barKey)
    if not db then return false, "Bar not found" end

    local name = GetItemInfo(itemId)
    if not name then return false, "Item not found" end

    if not Config:IsTrinketWithICD(itemId) then
        return false, "No ICD data for this item"
    end

    db.trackedItems = db.trackedItems or {}
    if db.trackedItems[itemId] then return false, "Already tracked" end

    db.trackedItems[itemId] = {
        order = GetNextOrder(db.trackedItems),
        trackType = Config.TrackType.INTERNAL_CD,
        displayMode = Config.DisplayMode.ALWAYS,
    }
    self:RebuildBar(barKey)

    return true, name
end

function AuraTracker:AddCustomICD(barKey, triggerSpellId, icdDuration)
    local db = self:GetBarDB(barKey)
    if not db then return false, "Bar not found" end

    local name = GetSpellInfo(triggerSpellId)
    if not name then return false, "Spell not found" end

    icdDuration = tonumber(icdDuration)
    if not icdDuration or icdDuration <= 0 then
        return false, "ICD duration must be greater than 0"
    end

    db.trackedItems = db.trackedItems or {}
    if db.trackedItems[triggerSpellId] then return false, "Already tracked" end

    db.trackedItems[triggerSpellId] = {
        order = GetNextOrder(db.trackedItems),
        trackType = Config.TrackType.CUSTOM_ICD,
        icdDuration = icdDuration,
        displayMode = Config.DisplayMode.ALWAYS,
    }
    self:RebuildBar(barKey)

    return true, name
end

function AuraTracker:AddCooldownAura(barKey, spellId, filterKey, specificAuraId, displayMode, onlyMine)
    local db = self:GetBarDB(barKey)
    if not db then return false, "Bar not found" end
    
    filterKey = filterKey or "TARGET_DEBUFF"
    local filterData = Config:GetAuraFilter(filterKey)
    if not filterData then return false, "Invalid filter type" end
    
    local name = GetSpellInfo(spellId)
    if not name then return false, "Spell not found" end
    
    local actualAuraId = specificAuraId or Config:GetMappedAuraId(spellId)
    
    db.trackedItems = db.trackedItems or {}
    if db.trackedItems[spellId] then return false, "Already tracked" end
    
    local finalDisplayMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.COOLDOWN_AURA)
    
    db.trackedItems[spellId] = {
        order = GetNextOrder(db.trackedItems),
        auraId = actualAuraId,
        type = filterKey:lower(),
        trackType = Config.TrackType.COOLDOWN_AURA,
        unit = filterData.unit,
        filter = filterData.filter,
        displayMode = finalDisplayMode,
        onlyMine = onlyMine or false,
    }

    -- Auto-link exclusive groups
    ApplyExclusiveGroup(db.trackedItems, spellId)

    self:RebuildBar(barKey)
    
    return true, name
end

-- ==========================================================
-- GLOBAL MAPPINGS
-- ==========================================================

-- Returns a mapping action table for a spellId, or nil if no mapping is defined.
-- Custom (user) mappings take precedence over built-in Config.SpellToAuraMap.
-- isShift controls whether the built-in SpellToAuraMap entries activate:
--   shift=true  → Icy Touch maps to Frost Fever aura, Plague Strike to Blood Plague
--   shift=false → falls through so the spell tracks as a cooldown
function AuraTracker:GetDropAction(spellId, isShift)
    local db = self:GetDB()
    -- User-defined custom mappings take precedence (always apply regardless of shift)
    if db and db.customMappings then
        local m = db.customMappings[spellId]
        if m then return m end
    end
    -- Built-in static mapping: spell applies a different aura ID.
    -- Only activate on shift-drag so a normal drag still tracks as a cooldown.
    if isShift then
        local mappedAuraId = Config.SpellToAuraMap[spellId]
        if mappedAuraId and mappedAuraId ~= spellId then
            return {
                trackType = Config.TrackType.AURA,
                auraId = mappedAuraId,
                filterKey = "TARGET_DEBUFF",
            }
        end
    end
    return nil
end


-- Export helpers for use by ItemFactoryEnchantTotem.lua
ns.AuraTracker._ItemFactoryHelpers = {
    GetNextOrder          = GetNextOrder,
    CreateAndRegisterIcon = CreateAndRegisterIcon,
}

