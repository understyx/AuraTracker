local _, ns = ...
local TrackedItem = ns.AuraTracker.TrackedItem
local Config = ns.AuraTracker.Config
local GetTime = GetTime
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local GetTotemInfo = GetTotemInfo
local math_floor = math.floor

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
    -- Fall back to the element's generic icon when originalTexture was not
    -- available at creation time (spell data not yet cached at login).
    self.texture    = self.originalTexture or Config:GetTotemElementIcon(self.id)

    return wasActive ~= self.active
end