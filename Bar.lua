local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local math_max = math.max
local table_insert, table_remove, table_sort = table.insert, table.remove, table.sort
local ipairs, wipe = ipairs, wipe
local CreateFrame = CreateFrame

local Bar = {}
Bar.__index = Bar
ns.AuraTracker.Bar = Bar

-- ==========================================================
-- CONSTRUCTOR
-- ==========================================================

function Bar:New(name, parent, options)
    options = options or {}
    
    local self = setmetatable({}, Bar)
    
    self.name = name
    self.icons = {}
    self.direction = options.direction or "HORIZONTAL"
    self.spacing = options.spacing or 0
    self.iconSize = options.iconSize or 40
    self.scale = options.scale or 1.0

    self.frame = CreateFrame("Frame", "AuraTracker_Bar_" .. name, parent or UIParent)
    self.frame:SetSize(self.iconSize, self.iconSize)
    self.frame:SetScale(self.scale)
    self.frame:SetFrameStrata("LOW")
    
    local point = options.point or "CENTER"
    local x = options.x or 0
    local y = options.y or 0
    local anchor = (options.anchorFrame and _G[options.anchorFrame]) or (parent or UIParent)
    local anchorPoint = options.anchorPoint or point
    self.frame:SetPoint(point, anchor, anchorPoint, x / self.scale, y / self.scale)
    
    self.minWidth = self.iconSize
    self.minHeight = self.iconSize
    self._layoutPending = false
    
    return self
end

-- ==========================================================
-- LIFECYCLE
-- ==========================================================

function Bar:Destroy()
    self:ClearIcons()
    self.frame:Hide()
    self.frame:SetParent(nil)
end

function Bar:Show()
    self.frame:Show()
end

function Bar:Hide()
    self.frame:Hide()
end

function Bar:IsShown()
    return self.frame:IsShown()
end

function Bar:GetFrame()
    return self.frame
end

function Bar:GetName()
    return self.name
end

-- ==========================================================
-- ICON MANAGEMENT
-- ==========================================================

function Bar:AddIcon(icon)
    table_insert(self.icons, icon)
    icon:GetFrame():SetParent(self.frame)
end

function Bar:RemoveIcon(icon)
    for i, existing in ipairs(self.icons) do
        if existing == icon then
            table_remove(self.icons, i)
            return true
        end
    end
    return false
end

function Bar:RemoveIconById(id)
    for i, icon in ipairs(self.icons) do
        if icon:GetId() == id then
            table_remove(self.icons, i)
            return icon
        end
    end
    return nil
end

function Bar:GetIcons()
    return self.icons
end

function Bar:GetIconById(id)
    for _, icon in ipairs(self.icons) do
        if icon:GetId() == id then
            return icon
        end
    end
    return nil
end

function Bar:ClearIcons()
    wipe(self.icons)
end

function Bar:GetIconCount()
    return #self.icons
end

function Bar:GetVisibleIconCount()
    local count = 0
    for _, icon in ipairs(self.icons) do
        if icon:GetFrame():IsShown() then
            count = count + 1
        end
    end
    return count
end

-- ==========================================================
-- LAYOUT
-- ==========================================================

function Bar:UpdateLayout()
    if self._layoutPending then return end
    self._layoutPending = true

    -- Defer layout to the next frame so multiple visibility changes
    -- within the same tick are coalesced into a single layout pass.
    -- Uses a one-shot OnUpdate frame (3.3.5-compatible; C_Timer is unavailable).
    if not self._layoutFrame then
        self._layoutFrame = CreateFrame("Frame")
        local bar = self
        self._layoutFrame:SetScript("OnUpdate", function(f)
            f:Hide()
            bar._layoutPending = false
            bar:DoLayout()
        end)
    end
    self._layoutFrame:Show()
end

function Bar:DoLayout()
    local prev, w, h = nil, 0, 0
    local horiz = self.direction == "HORIZONTAL"
    
    for _, icon in ipairs(self.icons) do
        local frame = icon:GetFrame()
        frame:ClearAllPoints()
        
        if frame:IsShown() then
            if horiz then
                frame:SetPoint(
                    "LEFT",
                    prev or self.frame,
                    prev and "RIGHT" or "LEFT",
                    prev and self.spacing or 0,
                    0
                )
                w = w + frame:GetWidth() + (prev and self.spacing or 0)
                h = math_max(h, frame:GetHeight())
            else
                frame:SetPoint(
                    "TOP",
                    prev or self.frame,
                    prev and "BOTTOM" or "TOP",
                    0,
                    prev and -self.spacing or 0
                )
                h = h + frame:GetHeight() + (prev and self.spacing or 0)
                w = math_max(w, frame:GetWidth())
            end
            prev = frame
        end
    end
    
    self.frame:SetSize(
        math_max(w, self.minWidth),
        math_max(h, self.minHeight)
    )
end

function Bar:SetDirection(direction)
    self.direction = direction
    self:DoLayout()
end

function Bar:SetSpacing(spacing)
    self.spacing = spacing
    self:DoLayout()
end

function Bar:SetIconSize(size)
    self.iconSize = size
    self.minWidth = size
    self.minHeight = size
    self.frame:SetSize(size, size)
end

function Bar:SetScale(scale)
    self.scale = scale or 1.0
    self.frame:SetScale(self.scale)
end

-- ==========================================================
-- POSITIONING
-- ==========================================================

function Bar:SetPosition(point, x, y, anchorFrame, anchorPoint)
    local anchor = (anchorFrame and _G[anchorFrame]) or UIParent
    local relPoint = anchorPoint or point
    self.frame:ClearAllPoints()
    self.frame:SetPoint(point, anchor, relPoint, x / self.scale, y / self.scale)
end

function Bar:SetMinSize(width, height)
    self.minWidth = width
    self.minHeight = height
end