local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local Config = ns.AuraTracker.Config
local GetSpellInfo, GetSpellCooldown = GetSpellInfo, GetSpellCooldown
local GetItemInfo, GetItemCooldown = GetItemInfo, GetItemCooldown
local GetTime = GetTime
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local GetTotemInfo = GetTotemInfo
local GetInventoryItemTexture = GetInventoryItemTexture
local CreateFrame = CreateFrame
local UnitAura = UnitAura
local UnitExists = UnitExists
local UnitName = UnitName
local ipairs, pairs = ipairs, pairs
local math_abs = math.abs

local TrackedItem = {}
TrackedItem.__index = TrackedItem
ns.AuraTracker.TrackedItem = TrackedItem

-- ==========================================================
-- WEAPON ENCHANT TYPE DETECTION (module-level, shared state)
-- ==========================================================
-- Per-slot cache: which enchant type is currently detected on each slot.
-- nil  = unknown (no enchant, or not yet parsed).
-- Set by DetectEnchantFromTooltip() in UpdateWeaponEnchant().
local weaponEnchantCache = { mainhand = nil, offhand = nil }

-- Inventory slot IDs for the two weapon slots.
local WEAPON_INV_SLOT = { mainhand = 16, offhand = 17 }

-- Pattern for matching the temporary enchant line in a weapon slot tooltip.
-- The format in WotLK is "Enchant Name (+X stat bonus)" on a single line.
-- Captures the enchant name (everything before the space+(digits) part).
-- Examples:
--   "Windfury Weapon (+321 Attack Power)"  → "Windfury Weapon"
--   "Grand Firestone (+80 fire damage)"    → "Grand Firestone"
--   "Dense Sharpening Stone (+12 damage)"  → "Dense Sharpening Stone"
local TENCH_PATTERN = "^(.-)%s+%([+-]?%d+%s+.+%)$"

-- Lazy-created hidden tooltip used exclusively for enchant detection.
local weaponEnchantTip = nil

-- Reads the weapon slot tooltip (via SetInventoryItem) and parses the
-- enchant-name line to determine which type of temp enchant is active.
-- Returns the matching Config key (e.g. "windfury"), or nil if unknown.
local function DetectEnchantFromTooltip(invSlotId)
    if not weaponEnchantTip then
        weaponEnchantTip = CreateFrame("GameTooltip", "AuraTracker_WeaponEnchantTip", UIParent, "GameTooltipTemplate")
        weaponEnchantTip:SetOwner(UIParent, "ANCHOR_NONE")
    end

    weaponEnchantTip:ClearLines()
    weaponEnchantTip:SetInventoryItem("player", invSlotId)

    local regions = { weaponEnchantTip:GetRegions() }
    for _, region in ipairs(regions) do
        if region:GetObjectType() == "FontString" then
            local text = region:GetText()
            if text then
                local name = text:match(TENCH_PATTERN)
                if name and name ~= "" then
                    local key = Config:GetWeaponEnchantKeyFromName(name)
                    if key then return key end
                end
            end
        end
    end

    return nil
end

-- ==========================================================
-- CONSTRUCTOR HELPERS  (local – not part of the public API)
-- ==========================================================

--- Resolves the display name and icon texture for a TrackedItem based on its
--- track type.  Must be called after self.auraId is set (used for the spell
--- fallback path in the `else` branch).
local function ResolveNameAndTexture(self, id, trackType, options)
    if trackType == Config.TrackType.ITEM
    or trackType == Config.TrackType.INTERNAL_CD then
        local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(id)
        self.name    = itemName
        self.texture = itemTexture

    elseif trackType == Config.TrackType.WEAPON_ENCHANT then
        -- For positive item IDs, prefer the item's own name and icon.
        if type(id) == "number" and id > 0 then
            local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(id)
            self.name    = itemName
            self.texture = itemTexture
        end
        -- For slot-based sentinel IDs or when item data is not yet cached,
        -- try to show the expected enchant's name and icon (if one is set).
        if not self.name then
            local enchKey = options.expectedEnchant
            if enchKey and enchKey ~= "any" then
                local auraId = Config:GetWeaponEnchantAuraId(enchKey)
                if auraId then
                    local auraName, _, auraTexture = GetSpellInfo(auraId)
                    if auraName then
                        self.name    = auraName
                        self.texture = auraTexture
                    end
                end
            end
        end
        -- Final generic fallback.
        if not self.name then
            local slot = options.slot or "mainhand"
            self.name    = (slot == "offhand") and "Offhand Enchant" or "Mainhand Enchant"
            local invSlot = (slot == "offhand") and 17 or 16
            self.texture = GetInventoryItemTexture("player", invSlot)
        end

    elseif trackType == Config.TrackType.TOTEM then
        -- Use the dragged spell's name/icon for display; fall back to element name.
        if options.spellId then
            local spellName, _, spellTexture = GetSpellInfo(options.spellId)
            self.name    = spellName
            self.texture = spellTexture
        end
        if not self.name then
            self.name = Config:GetTotemElementName(id)
        end
        -- If spell icon is unavailable (e.g. not cached yet), try the active
        -- totem icon; the texture will be refreshed on the next UpdateTotem call.
        if not self.texture then
            local totemSlot = options.totemSlot or Config:GetTotemSlot(id) or 1
            local _, _, _, _, activeIcon = GetTotemInfo(totemSlot)
            if activeIcon and activeIcon ~= "" then
                self.texture = activeIcon
            end
        end

    else
        local name, _, texture = GetSpellInfo(self.auraId or id)
        self.name    = name
        self.texture = texture
    end

    self.originalTexture = self.texture
end

--- Initialises the extra state fields that are specific to each track type.
--- `id` is passed directly so this helper does not depend on any prior call.
local function InitTypeState(self, id, trackType, options)
    -- Dual-track state
    if trackType == Config.TrackType.COOLDOWN_AURA then
        self.onCooldown    = false
        self.auraActive    = false
        self.auraDuration  = 0
        self.auraExpiration = 0
        self.auraStacks    = 0
    end

    -- Internal cooldown state
    if trackType == Config.TrackType.INTERNAL_CD then
        local procSpells = Config:GetTrinketProcSpells(id)
        if procSpells then
            if type(procSpells) == "number" then
                self.procSpellIds = { procSpells }
            else
                self.procSpellIds = procSpells
            end
            -- Use the ICD of the first proc spell as the default
            self.icdDuration = Config:GetTrinketProcCooldown(self.procSpellIds[1])
        else
            self.procSpellIds = {}
            self.icdDuration  = Config.DEFAULT_ICD
        end
        self.nativeICD     = self.icdDuration
        self.icdExpiration = 0
        self.equipped      = false
    end

    -- Temporary weapon enchant state
    if trackType == Config.TrackType.WEAPON_ENCHANT then
        self.weaponSlot = options.slot or "mainhand"
        -- Store the raw expected-enchant key so UpdateWeaponEnchant can compare
        -- against the per-slot cache populated by CLEU tracking.
        local enchKey = options.expectedEnchant
        if enchKey and enchKey ~= "any" then
            self.expectedEnchantKey = enchKey
        end
    end

    -- Totem state
    if trackType == Config.TrackType.TOTEM then
        self.totemSlot = options.totemSlot or Config:GetTotemSlot(id) or 1
    end
end

-- ==========================================================
-- CONSTRUCTOR
-- ==========================================================

function TrackedItem:New(id, trackType, options)
    options = options or {}

    local self = setmetatable({}, TrackedItem)

    self.id        = id
    self.trackType = trackType

    self.auraId    = options.auraId or Config:GetMappedAuraId(id)
    self.filterKey = options.filterKey
    self.onlyMine  = options.onlyMine or false

    local filterData = Config:GetAuraFilter(self.filterKey)
    if filterData then
        self.unit   = filterData.unit
        self.filter = filterData.filter
    end

    -- User-defined exclusive spell set for aura-tracking types.
    -- When set, UpdateAuraExclusive scans for any of these spells on the unit.
    -- We also build a name-based lookup so lower-level ranks match automatically.
    if trackType == Config.TrackType.AURA or trackType == Config.TrackType.COOLDOWN_AURA then
        local excl = options.exclusiveSpells
        if excl and next(excl) then
            local names = {}
            for sid in pairs(excl) do
                local sname = GetSpellInfo(sid)
                if sname then names[sname] = true end
            end
            self.exclusiveGroup = { spells = excl, names = names }
        end
    end

    ResolveNameAndTexture(self, id, trackType, options)

    -- Shared tracking state
    self.active            = false
    self.duration          = 0
    self.expiration        = 0
    self.stacks            = 0
    self.actualCooldownEnd = nil
    -- Source / destination names for custom text tokens (%srcName, %destName)
    self.srcName  = ""
    self.destName = ""

    InitTypeState(self, id, trackType, options)

    return self
end

-- ==========================================================
-- GETTERS
-- ==========================================================

function TrackedItem:GetId()
    return self.id
end

function TrackedItem:GetTrackType()
    return self.trackType
end

function TrackedItem:IsActive()
    return self.active
end

function TrackedItem:GetDuration()
    return self.duration
end

function TrackedItem:GetExpiration()
    return self.expiration
end

function TrackedItem:GetStacks()
    return self.stacks
end

function TrackedItem:GetTexture()
    return self.texture
end

function TrackedItem:GetName()
    return self.name
end

function TrackedItem:GetRemaining()
    return self.expiration - GetTime()
end

function TrackedItem:GetSrcName()
    return self.srcName or ""
end

function TrackedItem:GetDestName()
    return self.destName or ""
end

-- ==========================================================
-- INTERNAL HELPERS
-- ==========================================================

function TrackedItem:GetEffectiveFilter()
    local filter = self.filter
    if self.onlyMine and filter then
        filter = filter .. "|PLAYER"
    end
    return filter
end

--- Resets the shared aura tracking fields to "not active".
--- Called at the start of aura-scan paths to establish a clean baseline.
function TrackedItem:ClearAuraState()
    self.active     = false
    self.duration   = 0
    self.expiration = 0
    self.stacks     = 0
end

