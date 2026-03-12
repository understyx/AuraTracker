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
local math_floor = math.floor
local string_char, string_byte = string.char, string.byte

-- Library references
local LibFramePool = LibStub("LibFramePool-1.0")
local LibEditmode  = LibStub("LibEditmode-1.0")

-- The addon object (created in AuraTracker.lua)
local AuraTracker = ns.AuraTracker.Controller

-- ==========================================================
-- BASE64 HELPERS  (used by import/export)
-- ==========================================================

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local B64_DECODE = {}
for i = 1, #B64_CHARS do
    B64_DECODE[B64_CHARS:sub(i, i)] = i - 1
end

local function B64Encode(data)
    local result = {}
    local len = #data
    local i = 1
    while i <= len do
        local b0 = string_byte(data, i)
        local b1 = string_byte(data, i + 1) or 0
        local b2 = string_byte(data, i + 2) or 0
        local n  = b0 * 65536 + b1 * 256 + b2
        result[#result + 1] = B64_CHARS:sub(math_floor(n / 262144) + 1, math_floor(n / 262144) + 1)
        result[#result + 1] = B64_CHARS:sub(math_floor((n % 262144) / 4096) + 1, math_floor((n % 262144) / 4096) + 1)
        result[#result + 1] = (i + 1 <= len) and B64_CHARS:sub(math_floor((n % 4096) / 64) + 1, math_floor((n % 4096) / 64) + 1) or "="
        result[#result + 1] = (i + 2 <= len) and B64_CHARS:sub((n % 64) + 1, (n % 64) + 1) or "="
        i = i + 3
    end
    return table.concat(result)
end

local function B64Decode(data)
    data = data:gsub("[^A-Za-z0-9+/=]", "")
    local result = {}
    local len = #data
    local i = 1
    while i + 3 <= len do
        local c0 = B64_DECODE[data:sub(i,     i    )] or 0
        local c1 = B64_DECODE[data:sub(i + 1, i + 1)] or 0
        local c2 = B64_DECODE[data:sub(i + 2, i + 2)] or 0
        local c3 = B64_DECODE[data:sub(i + 3, i + 3)] or 0
        local n  = c0 * 262144 + c1 * 4096 + c2 * 64 + c3
        result[#result + 1] = string_char(math_floor(n / 65536))
        if data:sub(i + 2, i + 2) ~= "=" then
            result[#result + 1] = string_char(math_floor((n % 65536) / 256))
        end
        if data:sub(i + 3, i + 3) ~= "=" then
            result[#result + 1] = string_char(n % 256)
        end
        i = i + 4
    end
    return table.concat(result)
end

-- Export string prefix (version tag for future format changes)
local EXPORT_PREFIX = "ATv1:"

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

-- Builds the style options table from a bar's DB entry.
-- Exposed on ns.AuraTracker so UpdateEngine.lua can reuse it without duplication.
local function BuildStyleOptions(db)
    return {
        size = db.iconSize,
        fontSize = db.textSize,
        fontOutline = db.fontOutline,
        font = db.font,
        snapshotFontSize = db.snapshotTextSize,
        showSnapshotBG = db.showSnapshotBG,
        snapshotBGAlpha = db.snapshotBGAlpha,
        textColor = db.textColor,
        showCooldownText = db.showCooldownText,
    }
end
ns.AuraTracker.BuildStyleOptions = BuildStyleOptions

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

-- Cache for static (class + talent) visibility checks.
-- Keyed by barKey; value is true/false.
-- Populated lazily in ShouldShowBar; cleared by RebuildBar (per-bar)
-- and by OnTalentsChanged (all bars) since those are the only events
-- that can change the static result.
local barStaticCache = {}

function AuraTracker:InvalidateBarStaticCache(barKey)
    if barKey then
        barStaticCache[barKey] = nil
    else
        wipe(barStaticCache)
    end
end

function AuraTracker:ShouldShowBar(barKey)
    local db = self:GetBarDB(barKey)
    if not db or not db.enabled then
        return false
    end

    -- Static checks: class restriction + talent requirements.
    -- These never change mid-session except on talent events,
    -- so cache the result to avoid repeated API calls every tick.
    local staticOk = barStaticCache[barKey]
    if staticOk == nil then
        staticOk = true

        if db.classRestriction and db.classRestriction ~= "NONE" then
            local _, playerClass = UnitClass("player")
            if playerClass ~= db.classRestriction then
                staticOk = false
            end
        end

        -- Legacy single-talent-name check (backward compatibility)
        if staticOk and db.talentRestriction and db.talentRestriction ~= "NONE" then
            local SP = ns.AuraTracker.SettingsPanel
            if SP and not SP:CheckTalentRestriction(db.talentRestriction) then
                staticOk = false
            end
        end

        -- New multi-talent requirement check
        if staticOk and db.talentRequirements and next(db.talentRequirements) then
            local numTabs = GetNumTalentTabs and GetNumTalentTabs() or 0
            local maxTalents = MAX_NUM_TALENTS or 30
            if numTabs == 0 then
                -- Talent data not yet loaded at login; skip caching so this
                -- check re-runs next tick once data is available.
                return true
            end
            -- numTabs > 0 is guaranteed here; iterate the talent requirements.
            for combinedIndex, requiredState in pairs(db.talentRequirements) do
                local tab = math.ceil(combinedIndex / maxTalents)
                local talentIndex = combinedIndex - (tab - 1) * maxTalents
                if tab >= 1 and tab <= numTabs then
                    local _, _, _, _, rank = GetTalentInfo(tab, talentIndex)
                    local hasRank = rank and rank > 0
                    if requiredState == true and not hasRank then
                        staticOk = false
                        break
                    elseif requiredState == false and hasRank then
                        staticOk = false
                        break
                    end
                end
            end
        end

        barStaticCache[barKey] = staticOk
    end

    if not staticOk then return false end

    -- Dynamic checks: load conditions change at runtime (combat, mount, group, etc.)
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

-- ==========================================================
-- IMPORT / EXPORT
-- ==========================================================

--- Serialises the bar's configuration (name, style, tracked icons, load
--- conditions) to a portable string that can be shared and re-imported.
--- Position and class/talent restrictions are intentionally excluded so an
--- imported bar starts at the screen centre and is visible for any character.
function AuraTracker:ExportBar(barKey)
    local db = self:GetBarDB(barKey)
    if not db then return nil, "Bar not found" end

    local exportData = {
        name             = db.name,
        direction        = db.direction,
        iconSize         = db.iconSize,
        spacing          = db.spacing,
        scale            = db.scale,
        textSize         = db.textSize,
        showCooldownText = db.showCooldownText,
        ignoreGCD        = db.ignoreGCD,
        trackedItems     = db.trackedItems,
        loadConditions   = db.loadConditions,
    }

    local AceSerializer = LibStub("AceSerializer-3.0")
    local serialized = AceSerializer:Serialize(exportData)
    return EXPORT_PREFIX .. B64Encode(serialized)
end

--- Creates a new bar from an export string produced by ExportBar().
--- @param str       The export string (must start with "ATv1:")
--- @param newBarKey Optional key for the new bar; auto-generated if nil/empty.
--- @return success (bool), newBarKey or errorMessage (string)
function AuraTracker:ImportBar(str, newBarKey)
    if not str or str == "" then
        return false, "Empty import string"
    end
    if str:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return false, "Invalid format – string must start with " .. EXPORT_PREFIX
    end

    local encoded = str:sub(#EXPORT_PREFIX + 1)
    local decoded = B64Decode(encoded)
    if not decoded or decoded == "" then
        return false, "Failed to decode import string"
    end

    local AceSerializer = LibStub("AceSerializer-3.0")
    local ok, exportData = AceSerializer:Deserialize(decoded)
    if not ok or type(exportData) ~= "table" then
        return false, "Failed to parse import data"
    end

    -- Determine a unique bar key
    local baseKey = (newBarKey and newBarKey ~= "") and newBarKey
                    or (exportData.name and exportData.name:gsub("[^%w]", ""))
                    or "ImportedBar"
    newBarKey = baseKey
    local db = self:GetDB()
    local counter = 1
    while db.bars[newBarKey] do
        newBarKey = baseKey .. counter
        counter   = counter + 1
    end

    db.bars[newBarKey] = {
        enabled          = true,
        name             = exportData.name or newBarKey,
        direction        = exportData.direction or "HORIZONTAL",
        iconSize         = exportData.iconSize or 40,
        spacing          = exportData.spacing or 2,
        scale            = exportData.scale or 1.0,
        textSize         = exportData.textSize or 12,
        showCooldownText = exportData.showCooldownText ~= false,
        ignoreGCD        = exportData.ignoreGCD ~= false,
        trackedItems     = exportData.trackedItems or {},
        loadConditions   = exportData.loadConditions or {},
        point            = "CENTER",
        x                = 0,
        y                = -300,
        textColor        = { r = 1, g = 1, b = 1, a = 1 },
    }

    self:RebuildBar(newBarKey)
    return true, newBarKey
end

--- Creates a new bar from one of the predefined Config.ExampleBars entries.
--- @param exampleIndex  1-based index into Config.ExampleBars
--- @param newBarKey     Optional key; auto-generated if nil/empty.
function AuraTracker:ImportExampleBar(exampleIndex, newBarKey)
    local example = Config.ExampleBars and Config.ExampleBars[exampleIndex]
    if not example then return false, "Example not found" end

    local db = self:GetDB()

    -- Unique key
    local baseKey = (newBarKey and newBarKey ~= "") and newBarKey
                    or (example.name and example.name:gsub("[^%w]", ""))
                    or "ExampleBar"
    newBarKey = baseKey
    local counter = 1
    while db.bars[newBarKey] do
        newBarKey = baseKey .. counter
        counter   = counter + 1
    end

    -- Deep-copy a value so edits don't mutate the template
    local function DeepCopy(t)
        if type(t) ~= "table" then return t end
        local copy = {}
        for k, v in pairs(t) do copy[k] = DeepCopy(v) end
        return copy
    end

    -- Start from a deep copy of example.data so all authored settings are
    -- preserved (scale, textColor, classRestriction, talentRequirements, etc.).
    local d = DeepCopy(example.data or {})

    -- Apply required fields and defaults for anything not set in the template.
    d.enabled          = true
    d.name             = example.name or newBarKey
    d.direction        = d.direction        or "HORIZONTAL"
    d.iconSize         = d.iconSize         or 40
    d.spacing          = d.spacing          or 2
    d.scale            = d.scale            or 1.0
    d.textSize         = d.textSize         or 12
    d.showCooldownText = d.showCooldownText ~= false
    d.ignoreGCD        = d.ignoreGCD        ~= false
    d.trackedItems     = d.trackedItems     or {}
    d.loadConditions   = d.loadConditions   or {}
    d.textColor        = d.textColor        or { r = 1, g = 1, b = 1, a = 1 }
    -- Position is always reset to a safe default on import.
    d.point = "CENTER"
    d.x     = 0
    d.y     = -300

    db.bars[newBarKey] = d

    self:RebuildBar(newBarKey)
    return true, newBarKey
end
