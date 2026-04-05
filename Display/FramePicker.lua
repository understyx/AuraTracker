local _, ns = ...

-- ==========================================================
-- FRAME PICKER
-- Lets the user interactively click on any named WoW frame
-- to capture its global name for use as an anchor target.
--
-- Usage:
--   ns.AuraTracker.FramePicker:Start(function(frameName) ... end)
-- ==========================================================

local FramePicker = {}
ns.AuraTracker = ns.AuraTracker or {}
ns.AuraTracker.FramePicker = FramePicker

-- -------------------------------------------------------
-- Constants
-- -------------------------------------------------------

local SCAN_INTERVAL = 0.05   -- seconds between cursor-position scans
local HIGHLIGHT_BORDER_COLOR = { r = 0, g = 1, b = 0.2, a = 1 }
local LABEL_BG_COLOR         = { r = 0, g = 0, b = 0,   a = 0.75 }
local DIM_ALPHA              = 0.45

local STRATA_ORDER = {
    BACKGROUND        = 1,
    LOW               = 2,
    MEDIUM            = 3,
    HIGH              = 4,
    DIALOG            = 5,
    FULLSCREEN        = 6,
    FULLSCREEN_DIALOG = 7,
    TOOLTIP           = 8,
}

-- -------------------------------------------------------
-- Internals
-- -------------------------------------------------------

local _overlay  = nil   -- picker overlay frame (lazy-created)
local _callback = nil   -- function(frameName) called on selection

-- -------------------------------------------------------
-- Cursor-position hit-testing
-- -------------------------------------------------------

-- Recursively collect all named, visible child frames that contain (cx, cy).
-- cx/cy are in UIParent-coordinate space.
local function CollectHits(parent, cx, cy, skipFrame, out)
    if not parent then return end
    local children = { parent:GetChildren() }
    for i = 1, #children do
        local f = children[i]
        -- Skip the picker overlay itself and its subtree
        if f ~= skipFrame then
            if f:IsVisible() then
                local left   = f:GetLeft()
                local bottom = f:GetBottom()
                local right  = f:GetRight()
                local top    = f:GetTop()
                if left and right and bottom and top
                   and cx >= left  and cx <= right
                   and cy >= bottom and cy <= top
                then
                    if f:GetName() then
                        out[#out + 1] = f
                    end
                    -- Recurse into children even if this frame is unnamed
                    CollectHits(f, cx, cy, skipFrame, out)
                end
            end
        end
    end
end

-- Return the topmost named frame under the cursor, or nil.
local function GetFrameUnderCursor(skipFrame)
    local cx, cy = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    cx = cx / uiScale
    cy = cy / uiScale

    local hits = {}
    CollectHits(UIParent,   cx, cy, skipFrame, hits)
    CollectHits(WorldFrame, cx, cy, skipFrame, hits)

    -- Pick the highest (strata + level) frame
    local best, bestSO, bestFL = nil, -1, -1
    for _, f in ipairs(hits) do
        local so = STRATA_ORDER[f:GetFrameStrata() or "LOW"] or 2
        local fl = f:GetFrameLevel() or 0
        if so > bestSO or (so == bestSO and fl > bestFL) then
            best  = f
            bestSO = so
            bestFL = fl
        end
    end
    return best
end

-- -------------------------------------------------------
-- Overlay construction
-- -------------------------------------------------------

local function BuildOverlay()
    -- Full-screen capture frame
    local ov = CreateFrame("Frame", "AuraTracker_FramePickerOverlay", UIParent)
    ov:SetAllPoints(UIParent)
    ov:SetFrameStrata("TOOLTIP")
    ov:SetFrameLevel(200)
    ov:EnableMouse(true)
    ov:EnableKeyboard(true)
    ov:Hide()

    -- Dim background
    local dim = ov:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints(ov)
    dim:SetTexture("Interface\\Buttons\\WHITE8x8")
    dim:SetVertexColor(0, 0, 0, DIM_ALPHA)

    -- Instruction banner
    local banner = ov:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    banner:SetPoint("TOP", ov, "TOP", 0, -40)
    banner:SetText("|cffFFFF00[AuraTracker]|r  |cffFFFFFFHover over a frame and |cff00FF00LEFT-CLICK|r |cffFFFFFFto select it.|r  |cffFF8080Right-click or Escape to cancel.|r")
    banner:SetShadowOffset(1, -1)

    -- Green border highlight around the hovered frame
    local hi = CreateFrame("Frame", nil, ov)
    hi:SetFrameStrata("TOOLTIP")
    hi:SetFrameLevel(201)
    hi:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    hi:SetBackdropBorderColor(
        HIGHLIGHT_BORDER_COLOR.r,
        HIGHLIGHT_BORDER_COLOR.g,
        HIGHLIGHT_BORDER_COLOR.b,
        HIGHLIGHT_BORDER_COLOR.a
    )
    hi:Hide()
    ov.highlight = hi

    -- Label showing the hovered frame's name
    local labelBg = CreateFrame("Frame", nil, ov)
    labelBg:SetFrameStrata("TOOLTIP")
    labelBg:SetFrameLevel(202)
    labelBg:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 8, edgeSize = 8,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    labelBg:SetBackdropColor(LABEL_BG_COLOR.r, LABEL_BG_COLOR.g, LABEL_BG_COLOR.b, LABEL_BG_COLOR.a)
    labelBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    labelBg:Hide()
    ov.labelBg = labelBg

    local label = labelBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", labelBg, "TOPLEFT", 6, -6)
    label:SetPoint("BOTTOMRIGHT", labelBg, "BOTTOMRIGHT", -6, 6)
    ov.label = label

    -- -------------------------------------------------------
    -- OnUpdate: scan for the frame under the cursor
    -- -------------------------------------------------------
    ov._lastScan    = 0
    ov._hovered     = nil

    ov:SetScript("OnUpdate", function(self)
        local now = GetTime()
        if now - self._lastScan < SCAN_INTERVAL then return end
        self._lastScan = now

        local f = GetFrameUnderCursor(self)

        if f then
            hi:ClearAllPoints()
            hi:SetAllPoints(f)
            hi:Show()

            local name = f:GetName()
            local cx, cy = GetCursorPosition()
            local uiScale = UIParent:GetEffectiveScale()
            cx = cx / uiScale
            cy = cy / uiScale

            ov.label:SetText("|cff00FF00" .. name .. "|r")
            labelBg:SetWidth(ov.label:GetStringWidth() + 12)
            labelBg:SetHeight(ov.label:GetStringHeight() + 12)

            -- Position label near the cursor, nudged so it stays on screen
            labelBg:ClearAllPoints()
            local lbW = labelBg:GetWidth()
            local lbH = labelBg:GetHeight()
            local screenW = UIParent:GetRight() or GetScreenWidth()
            local anchorX = math.min(cx + 12, screenW - lbW)
            local anchorY = math.max(cy - 12, lbH)
            labelBg:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", anchorX, anchorY)
            labelBg:Show()

            self._hovered = f
        else
            hi:Hide()
            labelBg:Hide()
            self._hovered = nil
        end
    end)

    -- -------------------------------------------------------
    -- Mouse input
    -- -------------------------------------------------------
    ov:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            local picked = self._hovered
            FramePicker:Stop()
            if picked and _callback then
                _callback(picked:GetName())
            end
        elseif button == "RightButton" then
            FramePicker:Stop()
        end
    end)

    -- -------------------------------------------------------
    -- Keyboard input
    -- -------------------------------------------------------
    ov:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            FramePicker:Stop()
        end
    end)

    return ov
end

-- -------------------------------------------------------
-- Public API
-- -------------------------------------------------------

--- Open the frame picker.
--- @param callback function  Called with (frameName) when the user clicks a frame.
function FramePicker:Start(callback)
    _callback = callback
    if not _overlay then
        _overlay = BuildOverlay()
    end
    _overlay._hovered  = nil
    _overlay._lastScan = 0
    _overlay.highlight:Hide()
    _overlay.labelBg:Hide()
    _overlay:Show()
end

--- Close the frame picker without making a selection.
function FramePicker:Stop()
    _callback = nil
    if _overlay then
        _overlay:Hide()
        _overlay.highlight:Hide()
        _overlay.labelBg:Hide()
        _overlay._hovered = nil
    end
end

--- Returns true when the picker overlay is currently visible.
function FramePicker:IsActive()
    return _overlay ~= nil and _overlay:IsShown()
end
