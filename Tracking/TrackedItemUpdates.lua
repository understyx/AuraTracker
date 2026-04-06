local _, ns = ...
local TrackedItem = ns.AuraTracker.TrackedItem
local Config = ns.AuraTracker.Config
local GetTime = GetTime
local GetSpellCooldown = GetSpellCooldown
local UnitAura = UnitAura
local math_abs = math.abs
local math_floor = math.floor

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
    elseif self.trackType == Config.TrackType.CUSTOM_ICD then
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

    if self.unit == "smart_group" then
        return self:UpdateAuraSmartGroup(filter, wasActive, prevStacks)
    end

    if self.exclusiveGroup then
        return self:UpdateAuraExclusive(filter, wasActive, prevStacks)
    end

    local name, _, _, count, _, duration, expiration, casterUnit =
        UnitAura(self.unit, self.name, nil, filter)

    if name then
        self.active = true
        self.duration = duration or 0
        self.expiration = expiration or 0
        self.stacks = count or 0
        self.srcName  = casterUnit and (UnitName(casterUnit) or "") or ""
        self.destName = UnitName(self.unit) or ""
    else
        self.active = false
        self.duration = 0
        self.expiration = 0
        self.stacks = 0
        self.srcName  = ""
        self.destName = UnitName(self.unit) or ""
    end

    return wasActive ~= self.active or prevStacks ~= self.stacks
end

--- Aura update for the "smart_group" virtual unit.
--- Returns active = true if ANY group member has the aura.
function TrackedItem:UpdateAuraSmartGroup(filter, wasActive, prevStacks)
    local Conditionals = ns.AuraTracker.Conditionals
    local units = Conditionals and Conditionals:GetSmartGroupUnits() or { "player" }

    self:ClearAuraState()

    if self.exclusiveGroup then
        -- Exclusive-group variant: scan each group member for any of the exclusive spells.
        local group = self.exclusiveGroup
        local groupNames = group.names
        for _, u in ipairs(units) do
            if UnitExists(u) then
                for i = 1, 40 do
                    local name, _, _, count, _, duration, expiration, casterUnit, _, _, spellId =
                        UnitAura(u, i, filter)
                    if not name then break end
                    if spellId == self.auraId or group.spells[spellId]
                    or name == self.name or (groupNames and groupNames[name]) then
                        self.active     = true
                        self.duration   = duration or 0
                        self.expiration = expiration or 0
                        self.stacks     = count or 0
                        self.srcName    = casterUnit and (UnitName(casterUnit) or "") or ""
                        self.destName   = UnitName(u) or ""
                        local _, _, tex = GetSpellInfo(spellId)
                        if spellId and tex then self.texture = tex end
                        break
                    end
                end
            end
            if self.active then break end
        end
        if not self.active then
            self.texture  = self.originalTexture
            self.srcName  = ""
            self.destName = ""
        end
    else
        for _, u in ipairs(units) do
            if UnitExists(u) then
                local name, _, _, count, _, duration, expiration, casterUnit =
                    UnitAura(u, self.name, nil, filter)
                if name then
                    self.active     = true
                    self.duration   = duration or 0
                    self.expiration = expiration or 0
                    self.stacks     = count or 0
                    self.srcName    = casterUnit and (UnitName(casterUnit) or "") or ""
                    self.destName   = UnitName(u) or ""
                    break
                end
            end
        end
        if not self.active then
            self.srcName  = ""
            self.destName = ""
        end
    end

    return wasActive ~= self.active or prevStacks ~= self.stacks
end

function TrackedItem:UpdateAuraExclusive(filter, wasActive, prevStacks)
    local group      = self.exclusiveGroup
    local unit       = self.unit
    local groupNames = group.names

    self:ClearAuraState()

    for i = 1, 40 do
        local name, _, _, count, _, duration, expiration, casterUnit, _, _, spellId =
            UnitAura(unit, i, filter)
        if not name then break end

        -- Match original spell, exclusive group spells, or fall back to name
        if spellId == self.auraId or group.spells[spellId]
        or name == self.name or (groupNames and groupNames[name]) then
            self.active     = true
            self.duration   = duration or 0
            self.expiration = expiration or 0
            self.stacks     = count or 0
            self.srcName    = casterUnit and (UnitName(casterUnit) or "") or ""
            self.destName   = UnitName(unit) or ""
            local _, _, tex = GetSpellInfo(spellId)
            if tex then self.texture = tex end
            break
        end
    end

    if not self.active then
        self.texture  = self.originalTexture
        self.srcName  = ""
        self.destName = UnitName(unit) or ""
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

    local aName, _, _, count, _, auraDuration, auraExpiration, casterUnit =
        UnitAura(self.unit, self.name, nil, filter)

    if aName then
        self.auraActive = true
        self.auraDuration = auraDuration or 0
        self.auraExpiration = auraExpiration or 0
        self.auraStacks = count or 0
        self.srcName  = casterUnit and (UnitName(casterUnit) or "") or ""
        self.destName = UnitName(self.unit) or ""
    else
        self.auraActive = false
        self.auraDuration = 0
        self.auraExpiration = 0
        self.auraStacks = 0
        self.srcName  = ""
        self.destName = UnitName(self.unit) or ""
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

