local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local Config = ns.AuraTracker.Config
local LSM = LibStub("LibSharedMedia-3.0")
local CreateFrame = CreateFrame
local GetTime = GetTime
local PlaySoundFile = PlaySoundFile
local math_floor, math_max = math.floor, math.max
local string_format = string.format

local SnapshotTracker = nil   -- resolved lazily
local Conditionals = nil      -- resolved lazily

-- Glow animation constants
local GLOW_TICK       = 0.03   -- seconds between alpha steps
local GLOW_FADE_STEP  = 0.05   -- alpha change per step
local GLOW_MIN_ALPHA  = 0.3    -- lowest alpha during pulse

-- ==========================================================
-- SHARED GLOW ANIMATION
-- A single master OnUpdate handler drives all active glow
-- frames instead of creating one handler per glowing icon.
-- ==========================================================

local activeGlows    = {}
local glowMasterFrame = nil

local function RegisterGlow(glow)
    if not glowMasterFrame then
        glowMasterFrame = CreateFrame("Frame")
        glowMasterFrame._elapsed = 0
        glowMasterFrame:SetScript("OnUpdate", function(f, elapsed)
            f._elapsed = f._elapsed + elapsed
            if f._elapsed < GLOW_TICK then return end
            f._elapsed = 0
            for g in pairs(activeGlows) do
                g._alpha = g._alpha + g._dir * GLOW_FADE_STEP
                if g._alpha >= 1 then
                    g._alpha = 1
                    g._dir  = -1
                elseif g._alpha <= GLOW_MIN_ALPHA then
                    g._alpha = GLOW_MIN_ALPHA
                    g._dir  = 1
                end
                g:SetAlpha(g._alpha)
            end
        end)
    end
    activeGlows[glow] = true
    glowMasterFrame:Show()
end

local function UnregisterGlow(glow)
    activeGlows[glow] = nil
    if glowMasterFrame and not next(activeGlows) then
        glowMasterFrame:Hide()
    end
end

local Icon = {}
Icon.__index = Icon
ns.AuraTracker.Icon = Icon

-- Expose glow helpers for IconRender.lua (which loads after this file)
Icon._RegisterGlow   = RegisterGlow
Icon._UnregisterGlow = UnregisterGlow

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
    f.text:SetFont([[Fonts\FRIZQT__.ttf]], 12, "THICKOUTLINE")
    f.text:SetPoint("CENTER")
    
    f.stackText = f:CreateFontString(nil, "OVERLAY")
    f.stackText:SetFont([[Fonts\FRIZQT__.ttf]], 10, "THICKOUTLINE")
    f.stackText:SetPoint("BOTTOMRIGHT", -2, 2)

    -- Snapshot diff: own child frame so it layers above the glow border
    f.snapshotFrame = CreateFrame("Frame", nil, f)
    f.snapshotFrame:SetPoint("TOP", f, "TOP", 0, 8)
    f.snapshotFrame:SetSize(1, 1)

    f.snapshotBG = f.snapshotFrame:CreateTexture(nil, "BACKGROUND")
    f.snapshotBG:SetAllPoints()
    f.snapshotBG:SetTexture(0, 0, 0, 1)

    f.snapshotText = f.snapshotFrame:CreateFontString(nil, "OVERLAY")
    f.snapshotText:SetFont([[Fonts\FRIZQT__.ttf]], 9, "THICKOUTLINE")
    f.snapshotText:SetPoint("CENTER")

    f.snapshotFrame:Hide()

    -- Array of extra FontStrings created on-demand for custom text overlays.
    -- Entries are created lazily in ApplyCustomTexts and persist with the frame.
    f.customTextStrings = {}

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

    -- Load conditions (visibility): shared with bars
    self.loadConditions = nil  -- array of load condition defs (from DB)

    -- Action conditionals (glow/sound): icon-only
    self.conditionals = nil  -- array of action conditional defs (from DB)
    self._condState = {}     -- tracks previous evaluation result per conditional (for sound transitions)

    -- Custom text overlays (array of {enabled,format,point,xOffset,yOffset,color})
    self.customTexts = nil

    -- Icon event actions: triggered on click / show / hide
    self.onClickActions = nil
    self.onShowActions  = nil
    self.onHideActions  = nil

    -- Event-glow state (set by onShow/onHide/onClick action defs)
    self._eventGlowActive = false
    self._eventGlowColor  = nil

    -- Previous shown state (nil = first run, used to suppress spurious onShow/onHide on rebuild)
    self._prevShown = nil

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

    -- Wire up click handler (mouse must be enabled on the frame)
    self.frame:EnableMouse(true)
    -- Keep a reference so the closure can reach the Icon instance
    local iconRef = self
    self.frame:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            iconRef:FireEventActions("onClick")
        end
    end)

    if trackedItem then
        self.frame.icon:SetTexture(trackedItem:GetTexture())
    end
    
    self.frame.icon:SetDesaturated(false)
    self._renderDesaturated = false
    self.frame:SetAlpha(1)
    self.frame.cooldown:Hide()
    self.frame.text:SetText("")
    self.frame.stackText:Hide()
    self.frame.snapshotText:SetText("")
    self.frame.snapshotFrame:Hide()
    
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

-- ==========================================================
-- REFRESH / RENDER
-- ==========================================================

function Icon:Refresh()
    if not self.trackedItem then
        self.frame:Hide()
        return false
    end
    
    -- Update texture in case it changed (e.g. exclusive group rank swap)
    local newTexture = self.trackedItem:GetTexture()
    if newTexture ~= self._lastTexture then
        self.frame.icon:SetTexture(newTexture)
        self._lastTexture = newTexture
    end

    local shouldShow = self:ShouldShow()
    local wasShown = self.frame:IsShown()

    -- Detect first-run (nil) vs genuine show/hide transitions
    local prevShown = self._prevShown
    self._prevShown = shouldShow

    if shouldShow then
        self.frame:Show()
        local tt = self.trackedItem:GetTrackType()
        if tt == Config.TrackType.COOLDOWN_AURA then
            self:RenderDualTrack()
        elseif tt == Config.TrackType.INTERNAL_CD
        or tt == Config.TrackType.CUSTOM_ICD then
            self:RenderInternalCD()
        elseif self.trackedItem:IsActive() then
            self:RenderActive()
        else
            self:RenderInactive()
        end
        if prevShown == false then
            self:FireEventActions("onShow")
        end
        self:EvaluateConditionals()
    else
        if prevShown == true then
            self:FireEventActions("onHide")
            -- Clear any event glow when icon is hidden
            self._eventGlowActive = false
            self._eventGlowColor  = nil
        end
        self.frame:Hide()
        self:SetGlow(false)
    end
    
    return wasShown ~= shouldShow
end

