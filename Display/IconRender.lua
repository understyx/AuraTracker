local _, ns = ...
local Icon = ns.AuraTracker.Icon
local Config = ns.AuraTracker.Config
local Conditionals = nil  -- resolved lazily

local RegisterGlow   = Icon._RegisterGlow
local UnregisterGlow = Icon._UnregisterGlow

local GetTime = GetTime
local CreateFrame = CreateFrame
local LSM = LibStub("LibSharedMedia-3.0")
local PlaySoundFile = PlaySoundFile
local math_floor = math.floor
local string_format = string.format

function Icon:RenderActive()
    local item = self.trackedItem
    
    self.frame:SetAlpha(1)
    self.frame.icon:SetDesaturated(false)
    self._renderDesaturated = false
    
    local duration = item:GetDuration()
    local expiration = item:GetExpiration()
    
    if duration and duration > 0 and expiration and expiration > 0 then
        self.frame.cooldown:SetCooldown(expiration - duration, duration)
        self.frame.cooldown:Show()
    else
        self.frame.cooldown:Hide()
    end
    
    local stacks = item:GetStacks()
    self:UpdateStackDisplay(stacks)
end

function Icon:RenderInactive()
    self.frame:SetAlpha(1)
    self.frame.icon:SetDesaturated(true)
    self._renderDesaturated = true
    self.frame.cooldown:Hide()
    self.frame.stackText:Hide()
    self.frame.snapshotFrame:Hide()
    -- Do NOT clear frame.text here. UpdateCooldownText() owns frame.text and
    -- runs immediately after Refresh() in the same update pass. Clearing text
    -- here would beat the _prevCooldownText cache, causing the cooldown
    -- countdown to vanish for all but one 100ms tick per second.
end

function Icon:RenderInternalCD()
    local item = self.trackedItem
    local duration = item:GetDuration()
    local expiration = item:GetExpiration()

    if not item:IsActive() and duration and duration > 0 and expiration and expiration > 0 then
        -- ICD is running: show cooldown sweep on desaturated icon
        self.frame:SetAlpha(1)
        self.frame.icon:SetDesaturated(true)
        self._renderDesaturated = true
        self.frame.cooldown:SetCooldown(expiration - duration, duration)
        self.frame.cooldown:Show()
    else
        -- Trinket is ready: full color, no sweep
        self.frame:SetAlpha(1)
        self.frame.icon:SetDesaturated(false)
        self._renderDesaturated = false
        self.frame.cooldown:Hide()
    end

    self.frame.stackText:Hide()
end

function Icon:UpdateStackDisplay(stacks)
    if stacks and stacks > 1 then
        self.frame.stackText:SetText(stacks)
        self.frame.stackText:Show()
    else
        self.frame.stackText:Hide()
    end
end

function Icon:RenderDualTrack()
    local item = self.trackedItem

    if item:IsOnCooldown() then
        -- On cooldown: desaturated icon, show CD sweep
        self.frame:SetAlpha(1)
        self.frame.icon:SetDesaturated(true)
        self._renderDesaturated = true
        local duration = item:GetDuration()
        local expiration = item:GetExpiration()
        if duration and duration > 0 and expiration and expiration > 0 then
            self.frame.cooldown:SetCooldown(expiration - duration, duration)
            self.frame.cooldown:Show()
        else
            self.frame.cooldown:Hide()
        end
        self:UpdateStackDisplay(item:GetAuraStacks())
    elseif item:IsAuraActive() then
        -- Ready + aura active: full color, show aura sweep + stacks
        self.frame:SetAlpha(1)
        self.frame.icon:SetDesaturated(false)
        self._renderDesaturated = false
        local auraDur = item:GetAuraDuration()
        local auraExp = item:GetAuraExpiration()
        if auraDur and auraDur > 0 and auraExp and auraExp > 0 then
            self.frame.cooldown:SetCooldown(auraExp - auraDur, auraDur)
            self.frame.cooldown:Show()
        else
            self.frame.cooldown:Hide()
        end
        self:UpdateStackDisplay(item:GetAuraStacks())
    else
        -- Ready + no aura: full color, no sweep
        self.frame:SetAlpha(1)
        self.frame.icon:SetDesaturated(false)
        self._renderDesaturated = false
        self.frame.cooldown:Hide()
        self.frame.stackText:Hide()
        -- Do NOT clear frame.text here; UpdateCooldownText() owns it.
    end
end

-- ==========================================================
-- CONDITIONAL SYSTEM  (delegates to Conditionals module)
-- ==========================================================

function Icon:SetGlow(show, color)
    if show then
        if not self.frame.glowBorder then
            local glow = CreateFrame("Frame", nil, self.frame)
            glow:SetPoint("TOPLEFT", -3, 3)
            glow:SetPoint("BOTTOMRIGHT", 3, -3)
            glow:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 3,
            })
            glow:SetFrameLevel(self.frame:GetFrameLevel() + 2)
            glow._dir = 1
            glow._alpha = 1
            self.frame.glowBorder = glow
        end
        local c = color or { r = 1, g = 1, b = 0 }  -- default yellow
        self.frame.glowBorder:SetBackdropBorderColor(c.r, c.g, c.b, 1)
        self.frame.glowBorder:Show()
        RegisterGlow(self.frame.glowBorder)
    else
        if self.frame.glowBorder then
            self.frame.glowBorder:Hide()
            UnregisterGlow(self.frame.glowBorder)
        end
    end
end

function Icon:EvaluateConditionals()
    -- Lazily resolve Conditionals reference
    if not Conditionals then
        Conditionals = ns.AuraTracker.Conditionals
    end

    local glowActive = false
    local glowColor  = nil
    local shouldDesaturate = false
    local hasDesaturateConds = false

    if self.conditionals and self.trackedItem and Conditionals then
        glowActive, glowColor, shouldDesaturate, hasDesaturateConds = Conditionals:Evaluate(
            self.conditionals, self._condState, self.trackedItem
        )
    end

    -- Merge in event glow (from onClick/onShow/onHide actions)
    if self._eventGlowActive then
        glowActive = true
        if not glowColor and self._eventGlowColor then
            glowColor = self._eventGlowColor
        end
    end

    self:SetGlow(glowActive, glowColor)

    -- Apply conditional desaturation.  Only touch saturation when at least
    -- one conditional has desaturate=true; otherwise leave the icon exactly
    -- as the preceding render method (RenderActive / RenderInactive / etc.)
    -- set it.  When conditions clear we restore the render's baseline by
    -- reading _renderDesaturated, which every render method keeps up to date.
    -- This prevents a false "saturate" from overriding cooldown greying.
    if hasDesaturateConds then
        if shouldDesaturate then
            self.frame.icon:SetDesaturated(true)
        else
            self.frame.icon:SetDesaturated(self._renderDesaturated)
        end
    end
end

--- Fire all actions registered for `triggerKey` ("onClick"/"onShow"/"onHide").
function Icon:FireEventActions(triggerKey)
    local actions
    if triggerKey == "onClick" then
        actions = self.onClickActions
    elseif triggerKey == "onShow" then
        actions = self.onShowActions
    elseif triggerKey == "onHide" then
        actions = self.onHideActions
    end
    if not actions or #actions == 0 then return end

    if not Conditionals then
        Conditionals = ns.AuraTracker.Conditionals
    end
    if not Conditionals then return end

    local glowReq, glowColorReq = Conditionals:ExecuteIconActions(actions, self.trackedItem)
    if glowReq ~= nil then
        self._eventGlowActive = glowReq
        self._eventGlowColor  = glowColorReq
        -- Immediately update glow so onClick feedback is instant
        self:EvaluateConditionals()
    end
end

function Icon:UpdateCooldownText()
    if not self.showCooldownText or not self.trackedItem then
        if self._prevCooldownText ~= "" then
            self.frame.text:SetText("")
            self._prevCooldownText = ""
        end
        return
    end

    local item = self.trackedItem
    local newText

    if item:GetTrackType() == Config.TrackType.COOLDOWN_AURA then
        if item:IsOnCooldown() then
            local remaining = item:GetRemaining()
            if remaining > 0 then
                newText = self:FormatTime(remaining)
            end
        elseif item:IsAuraActive() then
            local remaining = item:GetAuraExpiration() - GetTime()
            if remaining > 0 then
                newText = self:FormatTime(remaining)
            end
        end
    else
        local remaining = self.trackedItem:GetRemaining()
        if remaining > 0 then
            newText = self:FormatTime(remaining)
        end
    end

    newText = newText or ""
    if self._prevCooldownText ~= newText then
        self.frame.text:SetText(newText)
        self._prevCooldownText = newText
    end
end

function Icon:FormatTime(seconds)
    if seconds >= 60 then
        return string_format("%dm", math_floor(seconds / 60))
    end
    if seconds >= 10 then
        return tostring(math_floor(seconds))
    end
    return string_format("%.1f", seconds)
end

