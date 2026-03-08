local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local Config = ns.AuraTracker.Config
local CreateFrame = CreateFrame
local GetTime = GetTime
local math_floor, math_max = math.floor, math.max
local string_format = string.format

local SnapshotTracker = nil  -- resolved lazily

local Icon = {}
Icon.__index = Icon
ns.AuraTracker.Icon = Icon

Icon.POOL_KEY = "AuraTrackerIcons"

-- ==========================================================
-- FRAME FACTORY (for pool)
-- ==========================================================

function Icon.CreateFrame(parent)
    local f = CreateFrame("Frame", nil, parent or UIParent)
    f:SetSize(40, 40)
    
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    
    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints()
    f.cooldown:SetAlpha(0)
    
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont([[Fonts\FRIZQT__.ttf]], 12, "OUTLINE")
    f.text:SetPoint("CENTER")
    
    f.stackText = f:CreateFontString(nil, "OVERLAY")
    f.stackText:SetFont([[Fonts\FRIZQT__.ttf]], 10, "OUTLINE")
    f.stackText:SetPoint("BOTTOMRIGHT", -2, 2)

    f.snapshotText = f:CreateFontString(nil, "OVERLAY")
    f.snapshotText:SetFont([[Fonts\FRIZQT__.ttf]], 9, "OUTLINE")
    f.snapshotText:SetPoint("TOP", 0, -2)

    return f
end

-- ==========================================================
-- CONSTRUCTOR
-- ==========================================================

function Icon:New(frame, trackedItem, displayMode)
    local self = setmetatable({}, Icon)
    
    self.frame = frame
    self.trackedItem = trackedItem
    self.displayMode = displayMode or Config.DisplayMode.ALWAYS
    self.showCooldownText = true
    
    if trackedItem then
        self.frame.icon:SetTexture(trackedItem:GetTexture())
    end
    
    self.frame.icon:SetDesaturated(false)
    self.frame:SetAlpha(1)
    self.frame.cooldown:Hide()
    self.frame.text:SetText("")
    self.frame.stackText:Hide()
    self.frame.snapshotText:SetText("")
    self.frame.snapshotText:Hide()
    
    return self
end

-- ==========================================================
-- LIFECYCLE
-- ==========================================================

function Icon:Destroy()
    self.frame:Hide()
    self.frame:ClearAllPoints()
    self.trackedItem = nil
end

function Icon:GetFrame()
    return self.frame
end

-- ==========================================================
-- TRACKED ITEM
-- ==========================================================

function Icon:SetTrackedItem(trackedItem)
    self.trackedItem = trackedItem
    if trackedItem then
        self.frame.icon:SetTexture(trackedItem:GetTexture())
    end
end

function Icon:GetTrackedItem()
    return self.trackedItem
end

function Icon:GetId()
    return self.trackedItem and self.trackedItem:GetId()
end

-- ==========================================================
-- DISPLAY MODE
-- ==========================================================

function Icon:SetDisplayMode(mode)
    self.displayMode = mode
end

function Icon:GetDisplayMode()
    return self.displayMode
end

-- ==========================================================
-- VISIBILITY LOGIC
-- ==========================================================

function Icon:ShouldShow()
    if not self.trackedItem then
        return false
    end
    
    local isActive = self.trackedItem:IsActive()
    
    if self.displayMode == Config.DisplayMode.ALWAYS then
        return true
    elseif self.displayMode == Config.DisplayMode.ACTIVE_ONLY then
        return isActive
    elseif self.displayMode == Config.DisplayMode.MISSING_ONLY then
        return not isActive
    end
    
    return true
end

-- ==========================================================
-- REFRESH / RENDER
-- ==========================================================

function Icon:Refresh()
    if not self.trackedItem then
        self.frame:Hide()
        return false
    end
    
    -- Update texture in case it changed (e.g., exclusive group)
    self.frame.icon:SetTexture(self.trackedItem:GetTexture())
    
    local shouldShow = self:ShouldShow()
    local wasShown = self.frame:IsShown()
    
    if shouldShow then
        self.frame:Show()
        if self.trackedItem:GetTrackType() == Config.TrackType.COOLDOWN_AURA then
            self:RenderDualTrack()
        elseif self.trackedItem:IsActive() then
            self:RenderActive()
        else
            self:RenderInactive()
        end
    else
        self.frame:Hide()
    end
    
    return wasShown ~= shouldShow
end

function Icon:RenderActive()
    local item = self.trackedItem
    
    self.frame:SetAlpha(1)
    self.frame.icon:SetDesaturated(false)
    
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
    self.frame.cooldown:Hide()
    self.frame.stackText:Hide()
    self.frame.snapshotText:Hide()
    self.frame.text:SetText("")
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
        self.frame.cooldown:Hide()
        self.frame.stackText:Hide()
        self.frame.text:SetText("")
    end
end

function Icon:UpdateCooldownText()
    if not self.showCooldownText or not self.trackedItem then
        self.frame.text:SetText("")
        return
    end
    
    local item = self.trackedItem
    
    if item:GetTrackType() == Config.TrackType.COOLDOWN_AURA then
        if item:IsOnCooldown() then
            local remaining = item:GetRemaining()
            if remaining > 0 then
                self.frame.text:SetText(self:FormatTime(remaining))
            else
                self.frame.text:SetText("")
            end
        elseif item:IsAuraActive() then
            local remaining = item:GetAuraExpiration() - GetTime()
            if remaining > 0 then
                self.frame.text:SetText(self:FormatTime(remaining))
            else
                self.frame.text:SetText("")
            end
        else
            self.frame.text:SetText("")
        end
        return
    end
    
    local remaining = self.trackedItem:GetRemaining()
    if remaining > 0 then
        self.frame.text:SetText(self:FormatTime(remaining))
    else
        self.frame.text:SetText("")
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

-- ==========================================================
-- SNAPSHOT DIFF TEXT
-- ==========================================================

function Icon:UpdateSnapshotText()
    if not self.showSnapshotText or not self.trackedItem then
        self.frame.snapshotText:Hide()
        return
    end

    local item = self.trackedItem
    local tt = item:GetTrackType()

    -- Only show for active aura-type items
    local isAuraActive = false
    if tt == Config.TrackType.AURA then
        isAuraActive = item:IsActive()
    elseif tt == Config.TrackType.COOLDOWN_AURA then
        isAuraActive = item:IsAuraActive()
    end

    if not isAuraActive then
        self.frame.snapshotText:Hide()
        return
    end

    -- Lazily resolve SnapshotTracker reference
    if not SnapshotTracker then
        SnapshotTracker = ns.AuraTracker.SnapshotTracker
    end
    if not SnapshotTracker then
        self.frame.snapshotText:Hide()
        return
    end

    local unit = item.unit
    local spellName = item:GetName()
    local diffText = SnapshotTracker:GetSnapshotDiff(unit, spellName)

    if diffText then
        self.frame.snapshotText:SetText(diffText)
        self.frame.snapshotText:Show()
    else
        self.frame.snapshotText:Hide()
    end
end

-- ==========================================================
-- STYLING
-- ==========================================================

function Icon:ApplyStyle(styleOptions)
    styleOptions = styleOptions or {}

    local size = styleOptions.size or 40
    self.frame:SetSize(size, size)

    local fontSize = styleOptions.fontSize or 12
    self.frame.text:SetFont([[Fonts\FRIZQT__.ttf]], fontSize, "OUTLINE")
    self.frame.stackText:SetFont(
        [[Fonts\FRIZQT__.ttf]],
        fontSize * 0.9,
        "OUTLINE"
    )

    if not self.frame.border then
        local border = CreateFrame("Frame", nil, self.frame)
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 2,
        })
        self.frame.border = border
    end
    self.frame.border:SetFrameLevel(self.frame:GetFrameLevel() + 1)
    self.frame.border:SetBackdropBorderColor(0, 0, 0, 1)

    local c = styleOptions.textColor or { r = 1, g = 1, b = 1, a = 1 }
    self.frame.text:SetTextColor(c.r, c.g, c.b, c.a)

    self.showCooldownText = styleOptions.showCooldownText ~= false
    if self.showCooldownText then
        self.frame.text:Show()
    else
        self.frame.text:Hide()
    end

    self.showSnapshotText = styleOptions.showSnapshotText or false
    if not self.showSnapshotText then
        self.frame.snapshotText:Hide()
    end
end