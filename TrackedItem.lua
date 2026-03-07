local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local Config = ns.AuraTracker.Config
local GetSpellInfo, GetSpellCooldown = GetSpellInfo, GetSpellCooldown
local GetItemInfo, GetItemCooldown = GetItemInfo, GetItemCooldown
local GetTime, UnitAura = GetTime, UnitAura
local math_abs = math.abs

local TrackedItem = {}
TrackedItem.__index = TrackedItem
ns.AuraTracker.TrackedItem = TrackedItem

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
    if trackType == Config.TrackType.ITEM then
        local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(id)
        self.name = itemName
        self.texture = itemTexture
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

        -- Match by spell ID first, then fall back to name for lower-rank spells
        if group.spells[spellId] or (groupNames and groupNames[name]) then
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