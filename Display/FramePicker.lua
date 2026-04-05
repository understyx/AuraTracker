local _, ns = ...

-- ==========================================================
-- FRAME PICKER
-- Lets the user interactively click on any named WoW frame
-- to capture its global name for use as an anchor target.
--
-- Based on the WeakAuras FrameChooser approach: uses
-- GetMouseFocus() + IsMouseButtonDown() so that WoW's own
-- hit-testing determines the focused frame (no mouse-capturing
-- overlay that would intercept focus from all other frames).
--
-- Usage:
--   ns.AuraTracker.FramePicker:Start(function(frameName) ... end)
-- ==========================================================

local FramePicker = {}
ns.AuraTracker = ns.AuraTracker or {}
ns.AuraTracker.FramePicker = FramePicker

-- -------------------------------------------------------
-- Internals
-- -------------------------------------------------------

local _callback      = nil   -- function(frameName) called on selection
local _updateFrame   = nil   -- plain (non-mouse-capturing) OnUpdate host
local _highlightBox  = nil   -- green border around the focused frame
local _banner        = nil   -- instruction text shown while picker is active
local _lastFocus     = nil
local _lastFocusName = nil

-- -------------------------------------------------------
-- Frame construction (lazy, first Start() call)
-- -------------------------------------------------------

local function BuildFrames()
    -- Plain frame with no mouse capture – lets WoW report GetMouseFocus() normally.
    _updateFrame = CreateFrame("Frame")

    -- Green border highlight (parented to UIParent so it renders independently).
    _highlightBox = CreateFrame("Frame", nil, UIParent)
    _highlightBox:SetFrameStrata("TOOLTIP")
    _highlightBox:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    _highlightBox:SetBackdropBorderColor(0, 1, 0)
    _highlightBox:Hide()

    -- Instruction banner (no mouse capture).
    _banner = CreateFrame("Frame", nil, UIParent)
    _banner:SetFrameStrata("TOOLTIP")
    _banner:SetPoint("TOP", UIParent, "TOP", 0, -40)
    _banner:SetSize(700, 30)
    local fs = _banner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetAllPoints(_banner)
    fs:SetText("|cffFFFF00[AuraTracker]|r  |cffFFFFFFHover over a frame and |cff00FF00LEFT-CLICK|r |cffFFFFFFto select.|r  |cffFF8080Right-click to cancel.|r")
    fs:SetShadowOffset(1, -1)
    _banner:Hide()
end

-- -------------------------------------------------------
-- Public API
-- -------------------------------------------------------

--- Open the frame picker.
--- @param callback function  Called with (frameName) when the user clicks a frame.
function FramePicker:Start(callback)
    _callback      = callback
    _lastFocus     = nil
    _lastFocusName = nil

    if not _updateFrame then
        BuildFrames()
    end

    _highlightBox:Hide()
    _banner:Show()

    _updateFrame:SetScript("OnUpdate", function()
        -- Right-click cancels.
        if IsMouseButtonDown("RightButton") then
            FramePicker:Stop()
            return
        end

        -- Left-click selects the last highlighted frame.
        if IsMouseButtonDown("LeftButton") and _lastFocusName then
            local name = _lastFocusName
            FramePicker:Stop()
            if _callback then
                _callback(name)
            end
            return
        end

        SetCursor("CAST_CURSOR")

        local focus     = GetMouseFocus()
        local focusName = focus and focus:GetName()

        -- Ignore WorldFrame and unnamed frames.
        if focusName == "WorldFrame" or not focusName then
            focusName = nil
        end

        if focus ~= _lastFocus then
            if focusName then
                _highlightBox:ClearAllPoints()
                _highlightBox:SetPoint("BOTTOMLEFT", focus, "BOTTOMLEFT", -4, -4)
                _highlightBox:SetPoint("TOPRIGHT",   focus, "TOPRIGHT",    4,  4)
                _highlightBox:Show()
            end
            _lastFocusName = focusName
            _lastFocus     = focus
        end

        if not focusName then
            _highlightBox:Hide()
        end
    end)
end

--- Close the frame picker without making a selection.
function FramePicker:Stop()
    if _updateFrame then
        _updateFrame:SetScript("OnUpdate", nil)
    end
    if _highlightBox then _highlightBox:Hide() end
    if _banner       then _banner:Hide()       end
    ResetCursor()
    _callback      = nil
    _lastFocus     = nil
    _lastFocusName = nil
end

--- Returns true when the picker is currently active.
function FramePicker:IsActive()
    return _updateFrame ~= nil
        and _updateFrame:GetScript("OnUpdate") ~= nil
end
