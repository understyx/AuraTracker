local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local Config = ns.AuraTracker.Config
local GetSpellInfo, GetSpellCooldown = GetSpellInfo, GetSpellCooldown
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
    
    local filterData = Config:GetAuraFilter(self.filterKey)
    if filterData then
        self.unit = filterData.unit
        self.filter = filterData.filter
    end
    
    local name, _, texture = GetSpellInfo(self.auraId or id)
    self.name = name
    self.texture = texture

    self.active = false
    self.duration = 0
    self.expiration = 0
    self.stacks = 0
    self.actualCooldownEnd = nil
    
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
-- UPDATE
-- ==========================================================

function TrackedItem:Update(gcdStart, gcdDuration, ignoreGCD)
    if self.trackType == Config.TrackType.COOLDOWN then
        return self:UpdateCooldown(gcdStart, gcdDuration, ignoreGCD)
    elseif self.trackType == Config.TrackType.AURA then
        return self:UpdateAura()
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

    local name, _, _, count, _, duration, expiration =
        UnitAura(self.unit, self.name, nil, self.filter)

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