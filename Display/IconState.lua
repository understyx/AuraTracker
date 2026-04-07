local _, ns = ...

local Icon = ns.AuraTracker.Icon
local Config = ns.AuraTracker.Config

local Conditionals = nil  -- resolved lazily (matches Icon.lua pattern)

-- ==========================================================
-- VISIBILITY LOGIC  (extracted from Icon.lua)
-- ==========================================================

function Icon:ShouldShow()
    if not self.trackedItem then
        return false
    end

    -- Hide unequipped trinkets
    if self.trackedItem:GetTrackType() == Config.TrackType.INTERNAL_CD
    and not self.trackedItem:IsEquipped() then
        return false
    end

    -- Check icon-level load conditions (visibility)
    if self.loadConditions and #self.loadConditions > 0 then
        if not Conditionals then
            Conditionals = ns.AuraTracker.Conditionals
        end
        if Conditionals and not Conditionals:CheckAllLoadConditions(self.loadConditions) then
            return false
        end
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
