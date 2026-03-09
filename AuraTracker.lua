local addonName, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local Config = ns.AuraTracker.Config
local TrackedItem = ns.AuraTracker.TrackedItem
local Icon = ns.AuraTracker.Icon
local Bar = ns.AuraTracker.Bar
local DragDrop = ns.AuraTracker.DragDrop
local UpdateEngine = ns.AuraTracker.UpdateEngine
local SnapshotTracker = ns.AuraTracker.SnapshotTracker

-- Localize frequently-used globals
local pairs, ipairs, wipe = pairs, ipairs, wipe
local GetSpellInfo, GetItemInfo = GetSpellInfo, GetItemInfo
local UnitGUID, UnitClass = UnitGUID, UnitClass
local IsSpellKnown = IsSpellKnown
local GetTime = GetTime
local GetInventoryItemID = GetInventoryItemID
local math_max = math.max
local string_upper, string_lower = string.upper, string.lower
local table_sort = table.sort
local strtrim = strtrim

-- Library references
local LibFramePool = LibStub("LibFramePool-1.0")
local LibEditmode  = LibStub("LibEditmode-1.0")

-- Create module via Ace3
local AuraTracker = LibStub("AceAddon-3.0"):NewAddon("AuraTracker", "AceEvent-3.0", "AceConsole-3.0")
ns.AuraTracker.Controller = AuraTracker

local playerGUID = nil

local BAR_DEFAULTS = {
    enabled = true,
    direction = "HORIZONTAL",
    spacing = 2,
    iconSize = 40,
    scale = 1.0,
    point = "CENTER",
    x = 0,
    y = -200,
    textSize = 12,
    showCooldownText = true,
    ignoreGCD = true,
    textColor = { r = 1, g = 1, b = 1, a = 1 },
}

-- Returns the next order value for a trackedItems table
local function GetNextOrder(trackedItems)
    local maxOrder = 0
    for _, data in pairs(trackedItems) do
        local order = type(data) == "table" and data.order or 0
        maxOrder = math_max(maxOrder, order)
    end
    return maxOrder + 1
end

-- Builds the common style options table from a bar's DB entry
local function BuildStyleOptions(db)
    return {
        size = db.iconSize,
        fontSize = db.textSize,
        fontOutline = db.fontOutline,
        textColor = db.textColor,
        showCooldownText = db.showCooldownText,
    }
end

-- ==========================================================
-- LIFECYCLE
-- ==========================================================

function AuraTracker:OnInitialize()
    local defaults = {
        profile = {
            enabled = true,
            bars = {},
            customMappings = {},
        }
    }
    self.db = LibStub("AceDB-3.0"):New("SimpleAuraTrackerDB", defaults, true)

    self.bars = {}
    self.items = {}
    
    playerGUID = UnitGUID("player")
    
    LibFramePool:CreatePool(Icon.POOL_KEY, Icon.CreateFrame)

    -- Register configuration options with AceConfig
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, function()
        local options = ns.GetAuraTrackerOptions()
        ns.UpdateBarOptions(options)
        return options
    end)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, "Aura Tracker")

    -- Register slash commands
    self:RegisterChatCommand("auratracker", "OnSlashCommand")
    self:RegisterChatCommand("at", "OnSlashCommand")
end

function AuraTracker:OnEnable()
    local db = self:GetDB()
    if not db or not db.enabled then
        self:Disable()
        return
    end

    if not next(db.bars) then
        self:CreateBar("auratracker")
    end

    -- Initialize extracted modules
    DragDrop:Init(self, function(barKey)
        local SP = ns.AuraTracker.SettingsPanel
        if SP then SP:Show(barKey) end
    end)
    UpdateEngine:Init(self)
    SnapshotTracker:Init(self)

    self:RebuildAllBars()
    UpdateEngine:CreateUpdateFrame()
    self:RegisterEvent("CHARACTER_POINTS_CHANGED", "OnTalentsChanged")
    self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnTalentsChanged")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnSpellUpdateCooldown")
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("SPELLS_CHANGED", "OnSpellsChanged")
    self:RegisterEvent("ACTIONBAR_SHOWGRID", "OnDragStart")
    self:RegisterEvent("ACTIONBAR_HIDEGRID", "OnDragEnd")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCLEU")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnEquipmentChanged")

    DragDrop:HookBuffButtons()
    hooksecurefunc("AuraButton_Update", function(buttonName, index, filter)
        DragDrop:HookAuraButtonByName(buttonName, index, filter)
    end)
    DragDrop:HookTooltipAuraDetection()

end

function AuraTracker:OnDisable()
    DragDrop:HideDropZones()
    self:DestroyAllBars()
    UpdateEngine:StopUpdateFrame()
    self:UnregisterAllEvents()
end

function AuraTracker:GetAllBars()
    return self.bars
end

function AuraTracker:GetDB()
    return self.db.profile
end

function AuraTracker:GetBarDB(barKey)
    local db = self:GetDB()
    return db and db.bars and db.bars[barKey]
end

function AuraTracker:GetBars()
    local db = self:GetDB()
    return db and db.bars
end


function AuraTracker:OnTalentsChanged()
    self:RebuildAllBars()
end

-- ==========================================================
-- BAR MANAGEMENT
-- ==========================================================

function AuraTracker:CreateBar(barKey)
    if self.bars[barKey] then
        return self.bars[barKey]
    end

    local profileDB = self:GetDB()
    if not profileDB then return nil end

    if not profileDB.bars[barKey] then
        local entry = {}
        for k, v in pairs(BAR_DEFAULTS) do
            if k == "textColor" then
                entry[k] = { r = v.r, g = v.g, b = v.b, a = v.a }
            else
                entry[k] = v
            end
        end
        entry.name = barKey
        entry.trackedItems = {}
        profileDB.bars[barKey] = entry
    end

    local db = profileDB.bars[barKey]
    if not db.enabled then
        return nil
    end

    local bar = Bar:New(barKey, UIParent, {
        direction = db.direction,
        spacing = db.spacing,
        iconSize = db.iconSize,
        scale = db.scale,
        point = db.point,
        x = db.x,
        y = db.y,
    })

    self.bars[barKey] = bar
    self.items[barKey] = {}

    local mover = LibEditmode:Register(bar:GetFrame(), {
        label = "AT: " .. (db.name or barKey),
        syncSize = true,
        addonName = "AuraTracker",
        subKey = barKey,
        initialPoint = {
            db.point or "CENTER",
            UIParent,
            db.point or "CENTER",
            db.x or 0,
            db.y or 0,
        },
        onMove = function(point, relTo, relPoint, x, y)
            db.point = point
            db.x = x
            db.y = y
        end,
        onRightClick = function()
            local SP = ns.AuraTracker.SettingsPanel
            if SP then SP:Show(barKey) end
        end,
    })
    bar.mover = mover

    return bar
end

function AuraTracker:DeleteBar(barKey)
    local bar = self.bars[barKey]
    if bar then
        for _, icon in ipairs(bar:GetIcons()) do
            icon:Destroy()
            LibFramePool:Release(icon:GetFrame())
        end

        LibEditmode:Unregister(bar:GetFrame())

        bar:Destroy()
        self.bars[barKey] = nil
        self.items[barKey] = nil
    end

    -- Always remove from database even if the bar widget was not
    -- active (e.g. hidden by class restriction or disabled).
    local profileDB = self:GetDB()
    if profileDB and profileDB.bars then
        profileDB.bars[barKey] = nil
    end

    return true
end

function AuraTracker:GetBar(barKey)
    return self.bars[barKey]
end

function AuraTracker:ReleaseBarIcons(barKey)
    local bar = self.bars[barKey]
    if not bar then return end
    for _, icon in ipairs(bar:GetIcons()) do
        icon:Destroy()
        LibFramePool:Release(icon:GetFrame())
    end
    bar:ClearIcons()
    if self.items[barKey] then
        wipe(self.items[barKey])
    end
    -- Clear proc→item reverse lookup; it gets rebuilt in CreateInternalCDIcon
    if self._procToItems then
        wipe(self._procToItems)
    end
end

function AuraTracker:RebuildBar(barKey)
    local db = self:GetBarDB(barKey)
    if not db then return end

    if not self:ShouldShowBar(barKey) then
        local bar = self.bars[barKey]
        if bar then
            self:ReleaseBarIcons(barKey)
            LibEditmode:Unregister(bar:GetFrame())
            bar:Destroy()
            self.bars[barKey] = nil
            self.items[barKey] = nil
        end
        return
    end

    if not self.bars[barKey] then
        self:CreateBar(barKey)
    end

    local bar = self.bars[barKey]
    if not bar then return end

    self:ReleaseBarIcons(barKey)

    bar:SetDirection(db.direction)
    bar:SetSpacing(db.spacing)
    bar:SetIconSize(db.iconSize)
    bar:SetScale(db.scale or 1.0)
    bar:SetPosition(db.point, db.x, db.y)
    
    local styleOptions = BuildStyleOptions(db)
    
    if db.trackedItems then
        for spellId, data in pairs(db.trackedItems) do
            local order = type(data) == "table" and data.order or 999
            if data.trackType == Config.TrackType.COOLDOWN then
                self:CreateCooldownIcon(barKey, spellId, order, styleOptions, data.displayMode)
            elseif data.trackType == Config.TrackType.AURA then
                local filterKey = data.type and string_upper(data.type) or "TARGET_DEBUFF"
                local icon = self:CreateAuraIcon(barKey, spellId, filterKey, data.auraId, order, styleOptions, data.displayMode, data.onlyMine, data.exclusiveSpells)
                if icon then icon.showSnapshotText = data.showSnapshotText or false end
            elseif data.trackType == Config.TrackType.ITEM then
                self:CreateItemIcon(barKey, spellId, order, styleOptions, data.displayMode)
            elseif data.trackType == Config.TrackType.COOLDOWN_AURA then
                local filterKey = data.type and string_upper(data.type) or "TARGET_DEBUFF"
                local icon = self:CreateCooldownAuraIcon(barKey, spellId, filterKey, data.auraId, order, styleOptions, data.displayMode, data.onlyMine, data.exclusiveSpells)
                if icon then icon.showSnapshotText = data.showSnapshotText or false end
            elseif data.trackType == Config.TrackType.INTERNAL_CD then
                self:CreateInternalCDIcon(barKey, spellId, order, styleOptions, data.displayMode)
            end
        end
    end
    
    self:SortBarIcons(barKey)
    self:SyncTrinketEquipState()

    -- Initial update so icons reflect correct state before syncing mover size
    UpdateEngine:UpdateAllCooldowns()
    UpdateEngine:UpdateAllAuras()
    bar:DoLayout()

    if bar.mover then
        local frame = bar:GetFrame()
        local scale = frame:GetScale()
        bar.mover:SetSize(frame:GetWidth() * scale, frame:GetHeight() * scale)
        bar.mover:ClearAllPoints()
        bar.mover:SetPoint(
            db.point or "CENTER",
            UIParent,
            db.point or "CENTER",
            db.x or 0,
            db.y or 0
        )
    end
end

function AuraTracker:RebuildAllBars()
    self:DestroyAllBars()
    
    local db = self:GetDB()
    if not db or not db.enabled then return end
    
    for barKey in pairs(db.bars) do
        if self:ShouldShowBar(barKey) then
            self:CreateBar(barKey)
            self:RebuildBar(barKey)
        end
    end
end

function AuraTracker:DestroyAllBars()
    for barKey, bar in pairs(self.bars) do
        for _, icon in ipairs(bar:GetIcons()) do
            icon:Destroy()
            LibFramePool:Release(icon:GetFrame())
        end
        LibEditmode:Unregister(bar:GetFrame())
        bar:Destroy()
    end
    wipe(self.bars)
    wipe(self.items)
end

function AuraTracker:SortBarIcons(barKey)
    local bar = self.bars[barKey]
    if not bar then return end
    
    table_sort(bar:GetIcons(), function(a, b)
        local orderA = a.order or 999
        local orderB = b.order or 999
        return orderA < orderB
    end)
end

-- ==========================================================
-- ADDING / REMOVING TRACKED ITEMS
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
    
    local frame = LibFramePool:Acquire(Icon.POOL_KEY, bar:GetFrame())
    
    local finalDisplayMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.COOLDOWN)
    local icon = Icon:New(frame, item, finalDisplayMode)
    icon.order = order

    icon:ApplyStyle(styleOptions)
    
    self.items[barKey][spellId] = item
    bar:AddIcon(icon)
    
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
    
    local frame = LibFramePool:Acquire(Icon.POOL_KEY, bar:GetFrame())
    
    local finalDisplayMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.AURA, filterKey)
    local icon = Icon:New(frame, item, finalDisplayMode)
    icon.order = order
    icon:ApplyStyle(styleOptions)
    
    self.items[barKey]["aura_" .. spellId] = item
    bar:AddIcon(icon)
    
    return icon
end

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

    -- Auto-link exclusive groups: if the spell belongs to a preset, add the whole group
    local presetKey = Config:GetPresetForSpell(spellId)
    if presetKey then
        local preset = Config.ExclusivePresets[presetKey]
        if preset then
            local entry = db.trackedItems[spellId]
            entry.exclusiveSpells = entry.exclusiveSpells or {}
            for groupSpellId in pairs(preset.spells) do
                if groupSpellId ~= spellId then
                    entry.exclusiveSpells[groupSpellId] = true
                end
            end
        end
    end

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

function AuraTracker:CreateItemIcon(barKey, itemId, order, styleOptions, displayMode)
    local bar = self.bars[barKey]
    local db = self:GetBarDB(barKey)
    if not bar or not db then return nil end
    
    local item = TrackedItem:New(itemId, Config.TrackType.ITEM)
    if not item:GetName() then return nil end
    
    local frame = LibFramePool:Acquire(Icon.POOL_KEY, bar:GetFrame())
    
    local finalDisplayMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.ITEM)
    local icon = Icon:New(frame, item, finalDisplayMode)
    icon.order = order
    icon:ApplyStyle(styleOptions)
    
    self.items[barKey]["item_" .. itemId] = item
    bar:AddIcon(icon)
    
    return icon
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

function AuraTracker:CreateInternalCDIcon(barKey, itemId, order, styleOptions, displayMode)
    local bar = self.bars[barKey]
    local db = self:GetBarDB(barKey)
    if not bar or not db then return nil end

    local item = TrackedItem:New(itemId, Config.TrackType.INTERNAL_CD)
    if not item:GetName() then return nil end

    local frame = LibFramePool:Acquire(Icon.POOL_KEY, bar:GetFrame())

    local finalDisplayMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.INTERNAL_CD)
    local icon = Icon:New(frame, item, finalDisplayMode)
    icon.order = order
    icon:ApplyStyle(styleOptions)

    self.items[barKey]["icd_" .. itemId] = item
    bar:AddIcon(icon)

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
    
    local frame = LibFramePool:Acquire(Icon.POOL_KEY, bar:GetFrame())
    
    local finalDisplayMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.COOLDOWN_AURA)
    local icon = Icon:New(frame, item, finalDisplayMode)
    icon.order = order
    icon:ApplyStyle(styleOptions)
    
    self.items[barKey]["cda_" .. spellId] = item
    bar:AddIcon(icon)
    
    return icon
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

    -- Auto-link exclusive groups: if the spell belongs to a preset, add the whole group
    local presetKey = Config:GetPresetForSpell(spellId)
    if presetKey then
        local preset = Config.ExclusivePresets[presetKey]
        if preset then
            local entry = db.trackedItems[spellId]
            entry.exclusiveSpells = entry.exclusiveSpells or {}
            for groupSpellId in pairs(preset.spells) do
                if groupSpellId ~= spellId then
                    entry.exclusiveSpells[groupSpellId] = true
                end
            end
        end
    end

    self:RebuildBar(barKey)
    
    return true, name
end

-- ==========================================================
-- GLOBAL MAPPINGS
-- ==========================================================

-- Returns a mapping action table for a spellId, or nil if no mapping is defined.
-- Custom (user) mappings take precedence over built-in Config.SpellToAuraMap.
function AuraTracker:GetDropAction(spellId)
    local db = self:GetDB()
    -- User-defined custom mappings take precedence
    if db and db.customMappings then
        local m = db.customMappings[spellId]
        if m then return m end
    end
    -- Built-in static mapping: spell applies a different aura ID
    local mappedAuraId = Config.SpellToAuraMap[spellId]
    if mappedAuraId and mappedAuraId ~= spellId then
        return {
            trackType = Config.TrackType.AURA,
            auraId = mappedAuraId,
            filterKey = "TARGET_DEBUFF",
        }
    end
    return nil
end

function AuraTracker:OnSpellUpdateCooldown()
    UpdateEngine:UpdateGCDState()
end

function AuraTracker:OnCLEU(event, ...)
    SnapshotTracker:HandleCLEU(...)

    -- Trinket ICD tracking via proc buff detection
    -- WotLK 3.3.5 CLEU format: timestamp(1), subEvent(2), sourceGUID(3),
    -- sourceName(4), sourceFlags(5), destGUID(6), destName(7), destFlags(8),
    -- spellId(9), spellName(10), spellSchool(11), ...
    if self._procToItems and next(self._procToItems) then
        local _, subEvent, _, _, _, destGUID, _, _, spellId = ...
        if destGUID == playerGUID
        and (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH") then
            local trackedItems = self._procToItems[spellId]
            if trackedItems then
                local now = GetTime()
                for trackedItem in pairs(trackedItems) do
                    trackedItem:OnProcDetected(spellId, now)
                end
            end
        end
    end
end

function AuraTracker:OnUnitAura(event, unit)
    if unit == "player" or unit == "target" or unit == "focus" then
        UpdateEngine:UpdateAurasForUnit(unit)
    end
    -- Player buffs and target debuffs affect snapshot calculations;
    -- skip invalidation for unrelated units (e.g. party members).
    if unit == "player" or unit == "target" then
        SnapshotTracker:InvalidateCache()
    end
    UpdateEngine:UpdateSnapshotText()
end

function AuraTracker:OnTargetChanged()
    UpdateEngine:UpdateAurasForUnit("target")
    SnapshotTracker:InvalidateCache()
    UpdateEngine:UpdateSnapshotText()
end

function AuraTracker:OnPlayerEnteringWorld()
    playerGUID = UnitGUID("player")
    SnapshotTracker:ResetPlayerInfo()
    self:RebuildAllBars()
end

function AuraTracker:OnSpellsChanged()
    self:RebuildAllBars()
end

-- ==========================================================
-- TRINKET EQUIP STATE
-- ==========================================================

local TRINKET_SLOT1 = 13
local TRINKET_SLOT2 = 14

--- Returns a set of trinket item IDs currently equipped in slots 13 and 14.
local function GetEquippedTrinketIds()
    local ids = {}
    local id1 = GetInventoryItemID("player", TRINKET_SLOT1)
    local id2 = GetInventoryItemID("player", TRINKET_SLOT2)
    if id1 then ids[id1] = true end
    if id2 then ids[id2] = true end
    return ids
end

--- Syncs the equipped flag on all INTERNAL_CD tracked items across all bars.
--- Returns a table of item IDs that were newly equipped (previously unequipped).
function AuraTracker:SyncTrinketEquipState()
    local equippedIds = GetEquippedTrinketIds()
    local newlyEquipped = {}

    for barKey, itemTable in pairs(self.items) do
        for key, item in pairs(itemTable) do
            if item:GetTrackType() == Config.TrackType.INTERNAL_CD then
                local wasEquipped = item:IsEquipped()
                local isNowEquipped = equippedIds[item:GetId()]
                item:SetEquipped(isNowEquipped)
                if isNowEquipped and not wasEquipped then
                    newlyEquipped[item:GetId()] = item
                end
            end
        end
    end

    return newlyEquipped
end

function AuraTracker:OnEquipmentChanged(event, slot)
    if slot ~= TRINKET_SLOT1 and slot ~= TRINKET_SLOT2 then return end

    local newlyEquipped = self:SyncTrinketEquipState()

    -- Start 30s swap cooldown on newly equipped trinkets
    local now = GetTime()
    for _, item in pairs(newlyEquipped) do
        item:OnEquipSwap(now)
    end
end

-- ==========================================================
-- EVENT DELEGATES
-- ==========================================================

function AuraTracker:OnDragStart()
    DragDrop:OnDragStart()
end

function AuraTracker:OnDragEnd()
    DragDrop:OnDragEnd()
end

-- ==========================================================
-- UTILITY
-- ==========================================================

function AuraTracker:Print(message)
    print("|cff00bfffAuraTracker:|r " .. message)
end

-- ==========================================================
-- EDIT MODE INTEGRATION
-- ==========================================================

function AuraTracker:OnSlashCommand(input)
    local cmd = strtrim(string_lower(input or ""))

    if cmd == "editmode" or cmd == "move" then
        LibEditmode:ToggleEditMode("AuraTracker")
        if LibEditmode:IsEditModeActive("AuraTracker") then
            self:Print("Edit mode |cFF00FF00enabled|r. Drag bars to reposition them. Type /at editmode again to exit.")
        else
            self:Print("Edit mode |cFFFF4444disabled|r.")
        end
        return
    end

    local SP = ns.AuraTracker.SettingsPanel
    if SP then SP:Show() end
end

-- ==========================================================
-- CLASS/TALENT RESTRICTION CHECK
-- ==========================================================

function AuraTracker:ShouldShowBar(barKey)
    local db = self:GetBarDB(barKey)
    if not db or not db.enabled then
        return false
    end

    if db.classRestriction and db.classRestriction ~= "NONE" then
        local _, playerClass = UnitClass("player")
        if playerClass ~= db.classRestriction then
            return false
        end
    end

    -- Legacy single-talent-name check (backward compatibility)
    if db.talentRestriction and db.talentRestriction ~= "NONE" then
        local SP = ns.AuraTracker.SettingsPanel
        if SP and not SP:CheckTalentRestriction(db.talentRestriction) then
            return false
        end
    end

    -- New multi-talent requirement check
    if db.talentRequirements and next(db.talentRequirements) then
        local numTabs = GetNumTalentTabs and GetNumTalentTabs() or 0
        local maxTalents = MAX_NUM_TALENTS or 30
        if numTabs > 0 then
            for combinedIndex, requiredState in pairs(db.talentRequirements) do
                local tab = math.ceil(combinedIndex / maxTalents)
                local talentIndex = combinedIndex - (tab - 1) * maxTalents
                if tab >= 1 and tab <= numTabs then
                    local name, iconTex, tier, col, rank = GetTalentInfo(tab, talentIndex)
                    local hasRank = rank and rank > 0
                    if requiredState == true and not hasRank then
                        return false
                    elseif requiredState == false and hasRank then
                        return false
                    end
                end
            end
        end
    end

    return true
end