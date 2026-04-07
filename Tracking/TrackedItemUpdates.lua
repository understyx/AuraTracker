local _, ns = ...
local TrackedItem = ns.AuraTracker.TrackedItem
local Config = ns.AuraTracker.Config
local SQ = ns.AuraTracker.StateQuery
local GetTime = GetTime
local UnitAura = UnitAura
local UnitName = UnitName
local UnitExists = UnitExists
local GetSpellInfo = GetSpellInfo
local math_abs = math.abs

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
    elseif self.trackType == Config.TrackType.INTERNAL_CD
    or self.trackType == Config.TrackType.CUSTOM_ICD then
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
    local result = SQ.QueryCooldown(self.id, gcdStart, gcdDuration, ignoreGCD, self.actualCooldownEnd)
    self.active           = result.active
    self.duration         = result.duration
    self.expiration       = result.expiration
    self.actualCooldownEnd = result.actualCooldownEnd
    return wasActive ~= self.active
end

function TrackedItem:UpdateAura()
    local wasActive = self.active
    local prevStacks = self.stacks

    local filter = self:GetEffectiveFilter()

    if self.unit == "smart_group" then
        return self:UpdateAuraSmartGroup(filter, wasActive, prevStacks)
    end

    if self.exclusiveGroup then
        return self:UpdateAuraExclusive(filter, wasActive, prevStacks)
    end

    local result = SQ.QueryAura(self.unit, self.name, filter)
    self.active     = result.active
    self.duration   = result.duration
    self.expiration = result.expiration
    self.stacks     = result.stacks
    self.srcName    = result.srcName
    self.destName   = result.destName

    return wasActive ~= self.active or prevStacks ~= self.stacks
end

--- Aura update for the "smart_group" virtual unit.
--- Returns active = true if ANY group member has the aura.
function TrackedItem:UpdateAuraSmartGroup(filter, wasActive, prevStacks)
    local Conditionals = ns.AuraTracker.Conditionals
    local units = Conditionals and Conditionals:GetSmartGroupUnits() or { "player" }

    self:ClearAuraState()

    if self.exclusiveGroup then
        local group = self.exclusiveGroup
        local result = SQ.QueryAuraExclusiveSmartGroup(
            units, filter, self.auraId, group.spells, self.name, group.names)
        if result.active then
            self.active     = true
            self.duration   = result.duration
            self.expiration = result.expiration
            self.stacks     = result.stacks
            self.srcName    = result.srcName
            self.destName   = result.destName
            if result.texture then self.texture = result.texture end
        else
            self.texture  = self.originalTexture
            self.srcName  = ""
            self.destName = ""
        end
    else
        local result = SQ.QueryAuraSmartGroup(units, self.name, filter)
        if result.active then
            self.active     = true
            self.duration   = result.duration
            self.expiration = result.expiration
            self.stacks     = result.stacks
            self.srcName    = result.srcName
            self.destName   = result.destName
        else
            self.srcName  = ""
            self.destName = ""
        end
    end

    return wasActive ~= self.active or prevStacks ~= self.stacks
end

function TrackedItem:UpdateAuraExclusive(filter, wasActive, prevStacks)
    local group = self.exclusiveGroup
    self:ClearAuraState()

    local result = SQ.QueryAuraExclusive(
        self.unit, filter, self.auraId, group.spells, self.name, group.names)
    if result.active then
        self.active     = true
        self.duration   = result.duration
        self.expiration = result.expiration
        self.stacks     = result.stacks
        self.srcName    = result.srcName
        self.destName   = result.destName
        if result.texture then self.texture = result.texture end
    else
        self.texture  = self.originalTexture
        self.srcName  = ""
        self.destName = UnitName(self.unit) or ""
    end

    return wasActive ~= self.active or prevStacks ~= self.stacks
end

function TrackedItem:UpdateItem()
    local wasActive = self.active
    local result = SQ.QueryItemCooldown(self.id)
    self.active     = result.active
    self.duration   = result.duration
    self.expiration = result.expiration
    return wasActive ~= self.active
end

function TrackedItem:UpdateCooldownAura(gcdStart, gcdDuration, ignoreGCD)
    local wasActive     = self.active
    local wasOnCD       = self.onCooldown
    local wasAuraActive = self.auraActive
    local prevStacks    = self.auraStacks

    -- Cooldown part
    local cdResult = SQ.QueryCooldown(self.id, gcdStart, gcdDuration, ignoreGCD, self.actualCooldownEnd)
    if cdResult.active == false and cdResult.expiration > 0 then
        self.onCooldown        = true
        self.duration          = cdResult.duration
        self.expiration        = cdResult.expiration
        self.actualCooldownEnd = cdResult.actualCooldownEnd
    else
        self.onCooldown        = false
        self.actualCooldownEnd = nil
    end

    -- Aura part
    local filter = self:GetEffectiveFilter()
    local aResult = SQ.QueryAura(self.unit, self.name, filter)
    self.auraActive     = aResult.active
    self.auraDuration   = aResult.duration
    self.auraExpiration = aResult.expiration
    self.auraStacks     = aResult.stacks
    self.srcName        = aResult.srcName
    self.destName       = aResult.destName

    -- Combined state: "active" = ready to use (not on CD)
    self.active = not self.onCooldown

    -- Set display values based on priority
    if not self.onCooldown and self.auraActive then
        self.duration   = self.auraDuration
        self.expiration = self.auraExpiration
        self.stacks     = self.auraStacks
    elseif not self.onCooldown then
        self.duration   = 0
        self.expiration = 0
        self.stacks     = 0
    else
        self.stacks = self.auraStacks
    end

    return wasActive ~= self.active or wasOnCD ~= self.onCooldown
        or wasAuraActive ~= self.auraActive or prevStacks ~= self.auraStacks
end

