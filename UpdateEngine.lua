local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local Config = ns.AuraTracker.Config

-- Localize frequently-used globals
local pairs, ipairs = pairs, ipairs
local GetSpellCooldown = GetSpellCooldown
local CreateFrame = CreateFrame
local math_abs = math.abs

local UpdateEngine = {}
ns.AuraTracker.UpdateEngine = UpdateEngine

-- GCD state (module-private)
local gcdStart, gcdDuration = nil, nil

-- ==========================================================
-- PRIVATE HELPERS
-- ==========================================================

-- Iterates all active (enabled) bars, calling fn(bar, db) for each.
-- Avoids repeating the pairs/GetBarDB/enabled boilerplate across update functions.
local function ForEnabledBars(controller, fn)
    for barKey, bar in pairs(controller.bars) do
        local db = controller:GetBarDB(barKey)
        if db and db.enabled then
            fn(bar, db)
        end
    end
end

-- ==========================================================
-- INITIALIZATION
-- ==========================================================

function UpdateEngine:Init(controller)
    self.controller = controller
    self.updateFrame = nil
end

-- ==========================================================
-- UPDATE FRAME (100ms tick)
-- ==========================================================

function UpdateEngine:CreateUpdateFrame()
    if self.updateFrame then return end

    local engine = self
    self.updateFrame = CreateFrame("Frame")
    self.updateFrame.elapsed = 0
    self.updateFrame:SetScript("OnUpdate", function(frame, elapsed)
        frame.elapsed = frame.elapsed + elapsed
        if frame.elapsed >= 0.1 then
            frame.elapsed = 0
            engine.controller:RecheckBarConditions()
            engine:UpdateAllCooldowns()
        end
    end)
    self.updateFrame:Show()
end

function UpdateEngine:StopUpdateFrame()
    if self.updateFrame then
        self.updateFrame:Hide()
    end
end

-- ==========================================================
-- GCD HANDLING
-- ==========================================================

function UpdateEngine:UpdateGCDState()
    local start, duration = GetSpellCooldown(Config.GCD_SPELL_ID)
    if duration and duration > 0 and duration <= Config.GCD_THRESHOLD then
        gcdStart, gcdDuration = start, duration
    else
        gcdStart, gcdDuration = nil, nil
    end
end

function UpdateEngine:GetGCDState()
    return gcdStart, gcdDuration
end

function UpdateEngine:IsGCD(start, duration)
    if not gcdStart or not gcdDuration then return false end
    if not start or start == 0 or not duration or duration <= 0 then return false end
    return math_abs(start - gcdStart) < 0.05 and math_abs(duration - gcdDuration) < 0.05
end

-- ==========================================================
-- UPDATE LOOPS
-- ==========================================================

function UpdateEngine:UpdateAllCooldowns()
    -- Refresh GCD state once per tick so every cooldown check
    -- uses the latest values instead of stale event-driven data.
    self:UpdateGCDState()

    local controller = self.controller
    ForEnabledBars(controller, function(bar, db)
        local needsLayout = false

        for _, icon in ipairs(bar:GetIcons()) do
            local item = icon:GetTrackedItem()
            if item then
                local tt = item:GetTrackType()
                if tt == Config.TrackType.COOLDOWN
                or tt == Config.TrackType.ITEM
                or tt == Config.TrackType.COOLDOWN_AURA
                or tt == Config.TrackType.INTERNAL_CD
                or tt == Config.TrackType.WEAPON_ENCHANT then
                    item:Update(gcdStart, gcdDuration, db.ignoreGCD)
                    local visChanged = icon:Refresh()
                    needsLayout = needsLayout or visChanged
                end
                -- Update cooldown text for all shown icons in the same pass,
                -- avoiding a separate bars×icons traversal each tick.
                if icon:GetFrame():IsShown() then
                    icon:UpdateCooldownText()
                end
            end
        end

        if needsLayout then
            bar:UpdateLayout()
        end
    end)
end

function UpdateEngine:UpdateAllAuras()
    local controller = self.controller
    ForEnabledBars(controller, function(bar, db)
        local needsLayout = false

        for _, icon in ipairs(bar:GetIcons()) do
            local item = icon:GetTrackedItem()
            if item then
                local tt = item:GetTrackType()
                if tt == Config.TrackType.AURA
                or tt == Config.TrackType.COOLDOWN_AURA then
                    item:Update()
                    local visChanged = icon:Refresh()
                    needsLayout = needsLayout or visChanged
                end
            end
        end

        if needsLayout then
            bar:UpdateLayout()
        end
    end)
end

function UpdateEngine:UpdateAurasForUnit(unit)
    local controller = self.controller
    ForEnabledBars(controller, function(bar, db)
        local needsLayout = false

        for _, icon in ipairs(bar:GetIcons()) do
            local item = icon:GetTrackedItem()
            if item then
                local tt = item:GetTrackType()
                if (tt == Config.TrackType.AURA or tt == Config.TrackType.COOLDOWN_AURA)
                and item.unit == unit then
                    item:Update()
                    local visChanged = icon:Refresh()
                    needsLayout = needsLayout or visChanged
                end
            end
        end

        if needsLayout then
            bar:UpdateLayout()
        end
    end)
end

function UpdateEngine:UpdateCooldownText()
    local controller = self.controller
    ForEnabledBars(controller, function(bar, db)
        for _, icon in ipairs(bar:GetIcons()) do
            if icon:GetFrame():IsShown() then
                icon:UpdateCooldownText()
            end
        end
    end)
end

function UpdateEngine:UpdateSnapshotText()
    local controller = self.controller
    ForEnabledBars(controller, function(bar, db)
        for _, icon in ipairs(bar:GetIcons()) do
            if icon:GetFrame():IsShown() then
                icon:UpdateSnapshotText()
            end
        end
    end)
end

-- ==========================================================
-- BAR REFRESH (visual/style update)
-- ==========================================================

function UpdateEngine:RefreshBar(barKey)
    local controller = self.controller
    local bar = controller.bars[barKey]
    local db = controller:GetBarDB(barKey)
    if not bar or not db then return end

    local styleOptions = ns.AuraTracker.BuildStyleOptions(db)
    local needsLayout = false

    for _, icon in ipairs(bar:GetIcons()) do
        icon:ApplyStyle(styleOptions)
        local item = icon:GetTrackedItem()
        if item then
            local tt = item:GetTrackType()
            if tt == Config.TrackType.COOLDOWN
            or tt == Config.TrackType.ITEM
            or tt == Config.TrackType.COOLDOWN_AURA
            or tt == Config.TrackType.INTERNAL_CD
            or tt == Config.TrackType.WEAPON_ENCHANT then
                item:Update(gcdStart, gcdDuration, db.ignoreGCD)
            else
                item:Update()
            end
            local visChanged = icon:Refresh()
            needsLayout = needsLayout or visChanged
        end
    end

    if needsLayout then
        bar:UpdateLayout()
    end
end
