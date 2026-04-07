local _, ns = ...

local Config = ns.AuraTracker.Config
local Icon = ns.AuraTracker.Icon
local Bar = ns.AuraTracker.Bar
local UpdateEngine = ns.AuraTracker.UpdateEngine

-- Localize frequently-used globals
local pairs, ipairs, wipe = pairs, ipairs, wipe
local math_max = math.max
local string_upper = string.upper
local table_sort = table.sort
local UnitClass = UnitClass
local type, next, tostring = type, next, tostring

-- Library references
local LibFramePool = LibStub("LibFramePool-1.0")
local LibEditmode  = LibStub("LibEditmode-1.0")

-- The addon object (created in AuraTracker.lua)
local AuraTracker = ns.AuraTracker.Controller

-- Helpers exported by BarFactory.lua (loads before this file)
local ResolveAnchorFrame = ns.AuraTracker._ResolveAnchorFrame
local BuildStyleOptions  = ns.AuraTracker.BuildStyleOptions

-- ==========================================================
-- PRIVATE HELPERS
-- ==========================================================

--- Recursively deep-copies a value so mutating the result does not affect
--- the original table.  Used when instantiating bars from example templates.
local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = DeepCopy(v) end
    return copy
end

--- Returns a key that is not already present in dbBars.
--- Tries baseKey first, then appends an incrementing counter until a free
--- slot is found.
local function FindUniqueBarKey(dbBars, baseKey)
    local candidate = baseKey
    local counter   = 1
    while dbBars[candidate] do
        candidate = baseKey .. counter
        counter   = counter + 1
    end
    return candidate
end

-- ==========================================================
-- BAR MANAGEMENT
-- ==========================================================

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
    -- Rebuild proc→item reverse lookup from all remaining bars so that
    -- releasing one bar's icons does not break proc detection for other bars.
    self:RebuildProcLookup()
end

--- Rebuilds the _procToItems reverse lookup table
--- (procSpellId → { TrackedItem → true }) from all bars' tracked items.
function AuraTracker:RebuildProcLookup()
    self._procToItems = {}
    for bk, itemTable in pairs(self.items) do
        for key, item in pairs(itemTable) do
            local tt = item:GetTrackType()
            if tt == Config.TrackType.INTERNAL_CD
            or tt == Config.TrackType.CUSTOM_ICD then
                local procSpells = item:GetProcSpellIds()
                if procSpells then
                    for _, procId in ipairs(procSpells) do
                        self._procToItems[procId] = self._procToItems[procId] or {}
                        self._procToItems[procId][item] = true
                    end
                end
            end
        end
    end
end

function AuraTracker:RebuildBar(barKey)
    local db = self:GetBarDB(barKey)
    if not db then return end

    -- Class/talent restrictions may have changed via settings; clear this bar's cache.
    self:InvalidateBarStaticCache(barKey)

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
    bar:SetPosition(db.point, db.x, db.y, db.anchorFrame, db.anchorPoint)
    
    local styleOptions = BuildStyleOptions(db)
    
    if db.trackedItems then
        for spellId, data in pairs(db.trackedItems) do
            local order = type(data) == "table" and data.order or 999
            local icon
            if data.trackType == Config.TrackType.COOLDOWN then
                icon = self:CreateCooldownIcon(barKey, spellId, order, styleOptions, data.displayMode)
            elseif data.trackType == Config.TrackType.AURA then
                local filterKey = data.type and string_upper(data.type) or "TARGET_DEBUFF"
                icon = self:CreateAuraIcon(barKey, spellId, filterKey, data.auraId, order, styleOptions, data.displayMode, data.onlyMine, data.exclusiveSpells)
                if icon then icon.showSnapshotText = data.showSnapshotText or false end
            elseif data.trackType == Config.TrackType.ITEM then
                icon = self:CreateItemIcon(barKey, spellId, order, styleOptions, data.displayMode)
            elseif data.trackType == Config.TrackType.COOLDOWN_AURA then
                local filterKey = data.type and string_upper(data.type) or "TARGET_DEBUFF"
                icon = self:CreateCooldownAuraIcon(barKey, spellId, filterKey, data.auraId, order, styleOptions, data.displayMode, data.onlyMine, data.exclusiveSpells)
                if icon then icon.showSnapshotText = data.showSnapshotText or false end
            elseif data.trackType == Config.TrackType.INTERNAL_CD then
                icon = self:CreateInternalCDIcon(barKey, spellId, order, styleOptions, data.displayMode)
            elseif data.trackType == Config.TrackType.CUSTOM_ICD then
                icon = self:CreateCustomICDIcon(barKey, spellId, data.icdDuration, order, styleOptions, data.displayMode)
            elseif data.trackType == Config.TrackType.WEAPON_ENCHANT then
                icon = self:CreateWeaponEnchantIcon(barKey, spellId, data.slot, order, styleOptions, data.displayMode, data.expectedEnchant)
            elseif data.trackType == Config.TrackType.TOTEM then
                icon = self:CreateTotemIcon(barKey, spellId, data.spellId, order, styleOptions, data.displayMode)
            end
            if icon then
                icon.conditionals   = data.conditionals
                icon.loadConditions = data.loadConditions
                icon.onClickActions = data.onClickActions
                icon.onShowActions  = data.onShowActions
                icon.onHideActions  = data.onHideActions
                icon:ApplyCustomTexts(data.customTexts, styleOptions)
            end
        end
    end
    
    self:SortBarIcons(barKey)
    self:SyncEquipState()
    self._prevTrinketSlots = self:GetTrinketSlotMap()

    -- Initial update so icons reflect correct state before syncing mover size
    UpdateEngine:UpdateAllCooldowns()
    UpdateEngine:UpdateAllAuras()
    bar:DoLayout()

    if bar.mover then
        local frame = bar:GetFrame()
        local scale = frame:GetScale()
        bar.mover:SetSize(frame:GetWidth() * scale, frame:GetHeight() * scale)
        bar.mover:ClearAllPoints()
        local anchorFrameRef = ResolveAnchorFrame(db.anchorFrame)
        local anchorRelPoint = db.anchorPoint or db.point or "CENTER"
        bar.mover:SetPoint(
            db.point or "CENTER",
            anchorFrameRef,
            anchorRelPoint,
            db.x or 0,
            db.y or 0
        )
        bar.mover.snapSize = db.snapSize
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

--- Re-evaluate bar load conditions and show/hide bars whose visibility
--- state has changed.  This is intentionally lightweight: it only calls
--- RebuildBar for bars that actually need to toggle, keeping the per-tick
--- cost close to zero when nothing changes.
function AuraTracker:RecheckBarConditions()
    local db = self:GetDB()
    if not db or not db.enabled then return end

    for barKey in pairs(db.bars) do
        local shouldShow = self:ShouldShowBar(barKey)
        local isShown    = self.bars[barKey] ~= nil

        if shouldShow ~= isShown then
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

