local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local Config = ns.AuraTracker.Config
local LSM = LibStub("LibSharedMedia-3.0")
local CreateFrame = CreateFrame
local GetTime = GetTime
local PlaySoundFile = PlaySoundFile
local math_floor, math_max, math_min = math.floor, math.max, math.min
local string_format = string.format

local SnapshotTracker = nil   -- resolved lazily
local Conditionals = nil      -- resolved lazily

-- Glow animation constants
local GLOW_TICK       = 0.03   -- seconds between alpha steps
local GLOW_FADE_STEP  = 0.05   -- alpha change per step
local GLOW_MIN_ALPHA  = 0.3    -- lowest alpha during pulse

-- WoW's SetFont is hard-capped at ~20pt.  For larger sizes we apply SetScale
-- on a wrapper frame so the font renders at the desired visual size.
local MAX_FONT_SIZE = 20

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
    
    -- Wrapper frame for cooldown/timer text so SetScale can exceed the 20pt cap
    f.textFrame = CreateFrame("Frame", nil, f)
    f.textFrame:SetSize(1, 1)
    f.textFrame:SetPoint("CENTER", f, "CENTER")
    f.text = f.textFrame:CreateFontString(nil, "OVERLAY")
    f.text:SetFont([[Fonts\FRIZQT__.ttf]], 12, "THICKOUTLINE")
    f.text:SetPoint("CENTER")

    -- Wrapper frame for stack-count text (same scaling approach)
    f.stackTextFrame = CreateFrame("Frame", nil, f)
    f.stackTextFrame:SetSize(1, 1)
    f.stackTextFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    f.stackText = f.stackTextFrame:CreateFontString(nil, "OVERLAY")
    f.stackText:SetFont([[Fonts\FRIZQT__.ttf]], 10, "THICKOUTLINE")
    f.stackText:SetPoint("CENTER")

    -- Snapshot diff: own child frame so it layers above the glow border
    f.snapshotFrame = CreateFrame("Frame", nil, f)
    f.snapshotFrame:SetPoint("TOP", f, "TOP", 0, 8)
    f.snapshotFrame:SetSize(1, 1)

    f.snapshotBG = f.snapshotFrame:CreateTexture(nil, "BACKGROUND")
    f.snapshotBG:SetAllPoints()
    f.snapshotBG:SetTexture(0, 0, 0, 1)

    -- Inner wrapper so snapshotText can be scaled independently of snapshotBG
    f.snapshotTextFrame = CreateFrame("Frame", nil, f.snapshotFrame)
    f.snapshotTextFrame:SetSize(1, 1)
    f.snapshotTextFrame:SetPoint("CENTER")
    f.snapshotText = f.snapshotTextFrame:CreateFontString(nil, "OVERLAY")
    f.snapshotText:SetFont([[Fonts\FRIZQT__.ttf]], 9, "THICKOUTLINE")
    f.snapshotText:SetPoint("CENTER")

    f.snapshotFrame:Hide()

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
        if self.trackedItem:GetTrackType() == Config.TrackType.COOLDOWN_AURA then
            self:RenderDualTrack()
        elseif self.trackedItem:GetTrackType() == Config.TrackType.INTERNAL_CD then
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

-- ==========================================================
-- SNAPSHOT DIFF TEXT
-- ==========================================================

function Icon:UpdateSnapshotText()
    if not self.showSnapshotText or not self.trackedItem then
        if self._prevSnapshotActive ~= false then
            self.frame.snapshotFrame:Hide()
            self.frame.text:ClearAllPoints()
            self.frame.text:SetPoint("CENTER")
            self._prevSnapshotActive = false
            self._prevSnapshotText   = nil
        end
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
        if self._prevSnapshotActive ~= false then
            self.frame.snapshotFrame:Hide()
            self.frame.text:ClearAllPoints()
            self.frame.text:SetPoint("CENTER")
            self._prevSnapshotActive = false
            self._prevSnapshotText   = nil
        end
        return
    end

    -- Lazily resolve SnapshotTracker reference
    if not SnapshotTracker then
        SnapshotTracker = ns.AuraTracker.SnapshotTracker
    end
    if not SnapshotTracker then
        if self._prevSnapshotActive ~= false then
            self.frame.snapshotFrame:Hide()
            self.frame.text:ClearAllPoints()
            self.frame.text:SetPoint("CENTER")
            self._prevSnapshotActive = false
            self._prevSnapshotText   = nil
        end
        return
    end

    local unit = item.unit
    local spellName = item:GetName()
    local diffText = SnapshotTracker:GetSnapshotDiff(unit, spellName)

    if diffText then
        -- Update text and resize frame only when text changes
        if self._prevSnapshotText ~= diffText then
            self.frame.snapshotText:SetText(diffText)
            self._prevSnapshotText = diffText
            local th = self.frame.snapshotText:GetStringHeight()
            -- GetStringHeight returns height in snapshotTextFrame's coordinate space.
            -- Multiply by the font scale to convert to snapshotFrame units.
            local s = self._snapshotFontScale or 1
            self.frame.snapshotFrame:SetSize(math_max(1, self.frame:GetWidth()), math_max(1, th * s + 2))
        end
        -- Show on state transition
        if self._prevSnapshotActive ~= true then
            self.frame.snapshotFrame:Show()
            self._prevSnapshotActive = true
        end
    else
        if self._prevSnapshotActive ~= false then
            self.frame.snapshotFrame:Hide()
            self._prevSnapshotActive = false
            self._prevSnapshotText   = nil
        end
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
    local fontOutline = styleOptions.fontOutline or "THICKOUTLINE"
    if fontOutline == "NONE" then fontOutline = "" end

    local fontPath = (styleOptions.font and LSM:Fetch("font", styleOptions.font))
        or [[Fonts\FRIZQT__.ttf]]

    -- Helper: apply font with a scale workaround for sizes beyond MAX_FONT_SIZE.
    -- The wrapper frame is scaled so that (capped font size * scale) = desired size.
    local function applyScaledFont(fontString, wrapperFrame, size, path, outline)
        local capped = math_min(size, MAX_FONT_SIZE)
        fontString:SetFont(path, capped, outline)
        wrapperFrame:SetScale(size / capped)
    end

    applyScaledFont(self.frame.text,      self.frame.textFrame,      fontSize,
        fontPath, fontOutline)
    applyScaledFont(self.frame.stackText, self.frame.stackTextFrame, fontSize * 0.9,
        fontPath, fontOutline)

    local snapFontSize = styleOptions.snapshotFontSize or (fontSize * 0.8)
    applyScaledFont(self.frame.snapshotText, self.frame.snapshotTextFrame, snapFontSize,
        fontPath, fontOutline)
    self._snapshotFontScale = self.frame.snapshotTextFrame:GetScale()

    -- Snapshot frame sits above the glow border (border = level+1, snapshot = level+2)
    self.frame.snapshotFrame:SetFrameLevel(self.frame:GetFrameLevel() + 2)
    local snapshotBGAlpha = styleOptions.showSnapshotBG == false and 0 or (styleOptions.snapshotBGAlpha or 1.0)
    self.frame.snapshotBG:SetAlpha(snapshotBGAlpha)

    if self.frame.border then
        self.frame.border:SetFrameLevel(self.frame:GetFrameLevel() + 1)
        self.frame.border:SetBackdropBorderColor(0, 0, 0, 1)
    end

    local c = styleOptions.textColor or { r = 1, g = 1, b = 1, a = 1 }
    self.frame.text:SetTextColor(c.r, c.g, c.b, c.a)

    self.showCooldownText = styleOptions.showCooldownText ~= false
    if self.showCooldownText then
        self.frame.text:Show()
    else
        self.frame.text:Hide()
    end
end