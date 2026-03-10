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

-- Library references
local LibFramePool = LibStub("LibFramePool-1.0")
local LibEditmode  = LibStub("LibEditmode-1.0")

-- The addon object (created in AuraTracker.lua)
local AuraTracker = ns.AuraTracker.Controller

-- ==========================================================
-- CONSTANTS
-- ==========================================================

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
            if item:GetTrackType() == Config.TrackType.INTERNAL_CD then
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
            end
            if icon then
                icon.conditionals   = data.conditionals
                icon.loadConditions = data.loadConditions
                icon.onClickActions = data.onClickActions
                icon.onShowActions  = data.onShowActions
                icon.onHideActions  = data.onHideActions
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

    -- Bar-level load conditions
    if db.loadConditions and #db.loadConditions > 0 then
        local Conditionals = ns.AuraTracker.Conditionals
        if Conditionals and not Conditionals:CheckAllLoadConditions(db.loadConditions) then
            return false
        end
    end

    -- Legacy: bar-level conditionals (old format, backward compat)
    if db.conditionals and #db.conditionals > 0 then
        local Conditionals = ns.AuraTracker.Conditionals
        if Conditionals and not Conditionals:CheckAll(db.conditionals, nil) then
            return false
        end
    end

    return true
end
