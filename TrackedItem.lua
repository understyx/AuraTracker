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
-- CONSTRUCTOR
-- ==========================================================

function TrackedItem:New(id, trackType, options)
    options = options or {}
    
    local self = setmetatable({}, TrackedItem)
    
    self.id = id
    self.trackType = trackType
    
    self.auraId = options.auraId or Config:GetMappedAuraId(id)
    self.filterKey = options.filterKey
    self.onlyMine = options.onlyMine or false
    
    local filterData = Config:GetAuraFilter(self.filterKey)
    if filterData then
        self.unit = filterData.unit
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
                if sname then
                    names[sname] = true
                end
            end
            self.exclusiveGroup = { spells = excl, names = names }
        end
    end
    
    -- Get name/texture based on track type
    if trackType == Config.TrackType.ITEM
    or trackType == Config.TrackType.INTERNAL_CD then
        local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(id)
        self.name = itemName
        self.texture = itemTexture
    elseif trackType == Config.TrackType.WEAPON_ENCHANT then
        -- For positive item IDs, prefer the item's own name and icon.
        if type(id) == "number" and id > 0 then
            local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(id)
            self.name = itemName
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
                        self.name = auraName
                        self.texture = auraTexture
                    end
                end
            end
        end
        -- Final generic fallback.
        if not self.name then
            local slot = options.slot or "mainhand"
            self.name = (slot == "offhand") and "Offhand Enchant" or "Mainhand Enchant"
            local weaponInvSlot = (slot == "offhand") and 17 or 16
            self.texture = GetInventoryItemTexture("player", weaponInvSlot)
        end
    elseif trackType == Config.TrackType.TOTEM then
        -- Use the dragged spell's name/icon for display; fall back to element name.
        if options.spellId then
            local spellName, _, spellTexture = GetSpellInfo(options.spellId)
            self.name = spellName
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
        self.name = name
        self.texture = texture
    end
    self.originalTexture = self.texture

    self.active = false
    self.duration = 0
    self.expiration = 0
    self.stacks = 0
    self.actualCooldownEnd = nil
    
    -- Dual-track state
    if trackType == Config.TrackType.COOLDOWN_AURA then
        self.onCooldown = false
        self.auraActive = false
        self.auraDuration = 0
        self.auraExpiration = 0
        self.auraStacks = 0
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
            self.icdDuration = Config.DEFAULT_ICD
        end
        self.nativeICD = self.icdDuration
        self.icdExpiration = 0
        self.equipped = false
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

-- ==========================================================
-- UPDATE
-- ==========================================================

function TrackedItem:Update(gcdStart, gcdDuration, ignoreGCD)
    if self.trackType == Config.TrackType.COOLDOWN then
        return self:UpdateCooldown(gcdStart, gcdDuration, ignoreGCD)
    elseif self.trackType == Config.TrackType.AURA then
        return self:UpdateAura()
    elseif self.trackType == Config.TrackType.ITEM then
        return self:UpdateItem()
    elseif self.trackType == Config.TrackType.COOLDOWN_AURA then
        return self:UpdateCooldownAura(gcdStart, gcdDuration, ignoreGCD)
    elseif self.trackType == Config.TrackType.INTERNAL_CD then
        return self:UpdateInternalCD()
    elseif self.trackType == Config.TrackType.WEAPON_ENCHANT then
        return self:UpdateWeaponEnchant()
    elseif self.trackType == Config.TrackType.TOTEM then
        return self:UpdateTotem()
    end
    return false
end

function TrackedItem:UpdateCooldown(gcdStart, gcdDuration, ignoreGCD)
    local wasActive = self.active
    local start, duration, enabled = GetSpellCooldown(self.id)
    local now = GetTime()
    
    if not start or enabled ~= 1 then
        self.active = false
        self.duration = 0
        self.expiration = 0
        self.actualCooldownEnd = nil
        return wasActive ~= self.active
    end
    
    if duration == 0 then
        self.active = true
        self.duration = 0
        self.expiration = 0
        self.actualCooldownEnd = nil
        return wasActive ~= self.active
    end
    
    local cooldownEnd = start + duration
    
    local isGCD = false
    if gcdStart and gcdDuration then
        isGCD = math_abs(start - gcdStart) < 0.05 and math_abs(duration - gcdDuration) < 0.05
    end
    
    if self.actualCooldownEnd and self.actualCooldownEnd > now then
        self.active = false
        self.expiration = self.actualCooldownEnd
        return wasActive ~= self.active
    end
    
    if ignoreGCD and isGCD then
        self.active = true
        self.duration = 0
        self.expiration = 0
        self.actualCooldownEnd = nil
        return wasActive ~= self.active
    end
    
    self.active = false
    self.duration = duration
    self.expiration = cooldownEnd
    self.actualCooldownEnd = cooldownEnd
    
    return wasActive ~= self.active
end

function TrackedItem:UpdateAura()
    local wasActive = self.active
    local prevStacks = self.stacks

    local filter = self:GetEffectiveFilter()

    if self.exclusiveGroup then
        return self:UpdateAuraExclusive(filter, wasActive, prevStacks)
    end

    local name, _, _, count, _, duration, expiration =
        UnitAura(self.unit, self.name, nil, filter)

    if name then
        self.active = true
        self.duration = duration or 0
        self.expiration = expiration or 0
        self.stacks = count or 0
    else
        self.active = false
        self.duration = 0
        self.expiration = 0
        self.stacks = 0
    end

    return wasActive ~= self.active or prevStacks ~= self.stacks
end

function TrackedItem:UpdateAuraExclusive(filter, wasActive, prevStacks)
    local group = self.exclusiveGroup
    local unit = self.unit
    local groupNames = group.names

    self.active = false
    self.duration = 0
    self.expiration = 0
    self.stacks = 0

    for i = 1, 40 do
        local name, _, _, count, _, duration, expiration, _, _, _, spellId =
            UnitAura(unit, i, filter)
        if not name then break end

        -- Match original spell, exclusive group spells, or fall back to name
        if spellId == self.auraId or group.spells[spellId] or name == self.name or (groupNames and groupNames[name]) then
            self.active = true
            self.duration = duration or 0
            self.expiration = expiration or 0
            self.stacks = count or 0
            local _, _, tex = GetSpellInfo(spellId)
            if tex then self.texture = tex end
            break
        end
    end

    if not self.active then
        self.texture = self.originalTexture
    end

    return wasActive ~= self.active or prevStacks ~= self.stacks
end

function TrackedItem:UpdateItem()
    local wasActive = self.active
    local start, duration, enabled = GetItemCooldown(self.id)

    if not start or enabled ~= 1 then
        self.active = false
        self.duration = 0
        self.expiration = 0
        return wasActive ~= self.active
    end

    if duration == 0 then
        self.active = true
        self.duration = 0
        self.expiration = 0
        return wasActive ~= self.active
    end

    self.active = false
    self.duration = duration
    self.expiration = start + duration

    return wasActive ~= self.active
end

function TrackedItem:UpdateCooldownAura(gcdStart, gcdDuration, ignoreGCD)
    local changed = false
    local wasActive = self.active
    local wasOnCD = self.onCooldown
    local wasAuraActive = self.auraActive
    local prevStacks = self.auraStacks

    -- Cooldown part
    local start, duration, enabled = GetSpellCooldown(self.id)
    local now = GetTime()

    if start and enabled == 1 and duration > 0 then
        local isGCD = false
        if gcdStart and gcdDuration then
            isGCD = math_abs(start - gcdStart) < 0.05 and math_abs(duration - gcdDuration) < 0.05
        end
        if ignoreGCD and isGCD then
            self.onCooldown = false
        else
            self.onCooldown = true
            self.duration = duration
            self.expiration = start + duration
        end
    else
        self.onCooldown = false
    end

    -- Aura part
    local filter = self:GetEffectiveFilter()

    local aName, _, _, count, _, auraDuration, auraExpiration =
        UnitAura(self.unit, self.name, nil, filter)

    if aName then
        self.auraActive = true
        self.auraDuration = auraDuration or 0
        self.auraExpiration = auraExpiration or 0
        self.auraStacks = count or 0
    else
        self.auraActive = false
        self.auraDuration = 0
        self.auraExpiration = 0
        self.auraStacks = 0
    end

    -- Combined state: "active" = ready to use (not on CD)
    self.active = not self.onCooldown

    -- Set display values based on priority
    if not self.onCooldown and self.auraActive then
        self.duration = self.auraDuration
        self.expiration = self.auraExpiration
        self.stacks = self.auraStacks
    elseif not self.onCooldown then
        self.duration = 0
        self.expiration = 0
        self.stacks = 0
    else
        self.stacks = self.auraStacks
    end

    changed = wasActive ~= self.active or wasOnCD ~= self.onCooldown
        or wasAuraActive ~= self.auraActive or prevStacks ~= self.auraStacks

    return changed
end

-- ==========================================================
-- WEAPON ENCHANT
-- ==========================================================

--- Polls GetWeaponEnchantInfo() to track a temporary weapon enchant.
--- Sets active=true with the remaining duration when the expected enchant (or
--- any enchant, if no specific type is configured) is present on the slot.
--- Sets active=false when no qualifying enchant is detected.
---
--- Detection strategy:
---   WotLK 3.3.5 has no API to determine *which* temporary enchant is on a
---   weapon slot — GetWeaponEnchantInfo() only reports presence + time.
---   Instead, when a specific enchant is expected, we read the name directly
---   from the weapon slot's tooltip (SetInventoryItem + FontString scan),
---   matching the extracted name against Config.WeaponEnchantChoices.
---   This works immediately, including enchants already present at login.
---   The result is cached per-slot until the enchant expires.
function TrackedItem:UpdateWeaponEnchant()
    local wasActive = self.active
    local hasMainEnchant, mainEndTimeMs, _, hasOffEnchant, offEndTimeMs = GetWeaponEnchantInfo()

    local hasEnchant, endTimeMs
    if self.weaponSlot == "offhand" then
        hasEnchant, endTimeMs = hasOffEnchant, offEndTimeMs
    else
        hasEnchant, endTimeMs = hasMainEnchant, mainEndTimeMs
    end

    if hasEnchant then
        -- Detect the enchant type via tooltip if not yet cached.
        -- Once detected the result is reused until the enchant disappears.
        if weaponEnchantCache[self.weaponSlot] == nil then
            local invSlot = WEAPON_INV_SLOT[self.weaponSlot]
            -- Store detected key, or the sentinel "?" if parse succeeds but
            -- no known type matched (avoids re-scanning every tick).
            weaponEnchantCache[self.weaponSlot] = DetectEnchantFromTooltip(invSlot) or "?"
        end
    else
        -- No enchant: clear cache so the next application is freshly detected.
        weaponEnchantCache[self.weaponSlot] = nil
    end

    -- When a specific enchant type is expected, compare against the cache.
    -- "?" means the slot has an enchant of unknown type — we cannot confirm
    -- the expected type is absent, so we fall back to treating it as present
    -- (same behaviour as "Any Enchant").
    if hasEnchant and self.expectedEnchantKey then
        local cachedKey = weaponEnchantCache[self.weaponSlot]
        if cachedKey and cachedKey ~= "?" and cachedKey ~= self.expectedEnchantKey then
            -- A different, identified enchant type is on the slot.
            hasEnchant = false
            endTimeMs  = nil
        end
    end

    if hasEnchant and endTimeMs and endTimeMs > 0 then
        local now = GetTime()
        self.active     = true
        self.duration   = 0  -- suppress cooldown spiral; text timer handles countdown
        self.expiration = now + (endTimeMs / 1000)
    else
        self.active     = false
        self.duration   = 0
        self.expiration = 0
    end

    return wasActive ~= self.active
end

function TrackedItem:GetWeaponSlot()
    return self.weaponSlot
end

function TrackedItem:UpdateInternalCD()
    local wasActive = self.active
    local now = GetTime()

    if self.icdExpiration > 0 and now < self.icdExpiration then
        -- ICD is still running
        self.active = false
        self.duration = self.icdDuration
        self.expiration = self.icdExpiration
    else
        -- ICD has expired or never started; trinket is ready
        self.active = true
        self.duration = 0
        self.expiration = 0
    end

    return wasActive ~= self.active
end

--- Called from CLEU handler when a matching proc spell is detected on the player.
--- Sets the ICD timer based on when the proc buff was applied.
function TrackedItem:OnProcDetected(procSpellId, buffAppliedTime)
    local icd = Config:GetTrinketProcCooldown(procSpellId)
    if icd > 0 then
        self.icdDuration = icd
        self.icdExpiration = buffAppliedTime + icd
        self.active = false
        self.duration = icd
        self.expiration = self.icdExpiration
    end
end

--- Returns the list of proc spell IDs this item watches for.
function TrackedItem:GetProcSpellIds()
    return self.procSpellIds
end

function TrackedItem:IsEquipped()
    return self.equipped
end

function TrackedItem:SetEquipped(val)
    self.equipped = val
end

local SWAP_CD = 30

--- Called when a trinket is placed into a trinket slot.
--- If native ICD > 30s, triggers the full ICD; otherwise triggers 30s.
--- Skips passive/stacking trinkets (nativeICD == 0).
function TrackedItem:OnEquipSwap(now)
    now = now or GetTime()
    -- Skip passive / stacking trinkets that have no ICD
    if not self.nativeICD or self.nativeICD <= 0 then return end
    local cd = (self.nativeICD > SWAP_CD) and self.nativeICD or SWAP_CD
    self.icdDuration = cd
    self.icdExpiration = now + cd
    self.active = false
    self.duration = cd
    self.expiration = self.icdExpiration
end

-- ==========================================================
-- DUAL-TRACK GETTERS
-- ==========================================================

function TrackedItem:IsOnCooldown()
    return self.onCooldown or false
end

function TrackedItem:IsAuraActive()
    return self.auraActive or false
end

function TrackedItem:GetAuraDuration()
    return self.auraDuration or 0
end

function TrackedItem:GetAuraExpiration()
    return self.auraExpiration or 0
end

function TrackedItem:GetAuraStacks()
    return self.auraStacks or 0
end

-- ==========================================================
-- TOTEM
-- ==========================================================

--- Polls GetTotemInfo() for the element slot this tracker monitors.
--- Sets active=true with remaining duration when a totem is placed and alive.
--- Updates the displayed icon texture to match the currently active totem so
--- the icon changes dynamically when a different totem of the same element is
--- dropped (e.g. switching from Searing Totem to Fire Elemental Totem).
function TrackedItem:UpdateTotem()
    local wasActive = self.active
    local now = GetTime()

    local haveTotem, _, startTime, duration, totemIcon = GetTotemInfo(self.totemSlot)

    if haveTotem and duration and duration > 0 then
        local expiration = startTime + duration
        if expiration > now then
            self.active     = true
            self.duration   = duration
            self.expiration = expiration
            -- Reflect the icon of whichever specific totem is placed.
            if totemIcon and totemIcon ~= "" then
                self.texture = totemIcon
            end
            return wasActive ~= self.active
        end
    end

    self.active     = false
    self.duration   = 0
    self.expiration = 0
    -- Restore the icon of the originally dragged spell when no totem is up.
    self.texture    = self.originalTexture

    return wasActive ~= self.active
end