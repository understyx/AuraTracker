local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

-- Bar creation logic: frame construction, mover registration, and
-- positioning helpers.  Stateful CRUD methods live in BarManager.lua.

local Config = ns.AuraTracker.Config
local Bar    = ns.AuraTracker.Bar

local LibEditmode = LibStub("LibEditmode-1.0")

local AuraTracker = ns.AuraTracker.Controller

-- ==========================================================
-- POSITIONING HELPERS
-- ==========================================================

--- Resolves an anchor frame name string to an actual frame object.
--- Returns UIParent when the name is nil, empty, or refers to a non-existent frame.
local function ResolveAnchorFrame(anchorFrameName)
    return (anchorFrameName and _G[anchorFrameName]) or UIParent
end

--- Returns the screen-space (UI unit) X,Y coordinates for the given named
--- anchor point on a frame.  Used to convert UIParent-relative drag results
--- back into anchor-frame-relative offsets when an anchorFrame is configured.
local function GetPointScreenXY(frame, point)
    local l, b = frame:GetLeft(), frame:GetBottom()
    if not l or not b then return 0, 0 end
    local w, h = frame:GetWidth(), frame:GetHeight()
    local r, t = l + w, b + h
    local cx, cy = l + w * 0.5, b + h * 0.5
    if     point == "CENTER"      then return cx, cy
    elseif point == "TOP"         then return cx, t
    elseif point == "BOTTOM"      then return cx, b
    elseif point == "LEFT"        then return l,  cy
    elseif point == "RIGHT"       then return r,  cy
    elseif point == "TOPLEFT"     then return l,  t
    elseif point == "TOPRIGHT"    then return r,  t
    elseif point == "BOTTOMLEFT"  then return l,  b
    elseif point == "BOTTOMRIGHT" then return r,  b
    end
    return cx, cy
end

-- Export positioning helpers for use by BarManager (mover sync in RebuildBar)
ns.AuraTracker._ResolveAnchorFrame = ResolveAnchorFrame
ns.AuraTracker._GetPointScreenXY   = GetPointScreenXY

-- ==========================================================
-- CONSTANTS
-- ==========================================================

local BAR_DEFAULTS = {
    enabled = true,
    direction = "HORIZONTAL",
    spacing = 2,
    iconSize = 40,
    scale = 1.0,
    point = "CENTER",
    x = 0,
    y = -200,
    textSize = 12,
    showCooldownText = true,
    ignoreGCD = true,
    textColor = { r = 1, g = 1, b = 1, a = 1 },
}
ns.AuraTracker._BarDefaults = BAR_DEFAULTS

-- ==========================================================
-- BAR CREATION
-- ==========================================================

function AuraTracker:CreateBar(barKey)
    if self.bars[barKey] then
        return self.bars[barKey]
    end

    local profileDB = self:GetDB()
    if not profileDB then return nil end

    if not profileDB.bars[barKey] then
        local entry = {}
        for k, v in pairs(BAR_DEFAULTS) do
            if k == "textColor" then
                entry[k] = { r = v.r, g = v.g, b = v.b, a = v.a }
            else
                entry[k] = v
            end
        end
        entry.name = barKey
        entry.trackedItems = {}
        profileDB.bars[barKey] = entry
    end

    local db = profileDB.bars[barKey]
    if not db.enabled then
        return nil
    end

    local bar = Bar:New(barKey, UIParent, {
        direction = db.direction,
        spacing = db.spacing,
        iconSize = db.iconSize,
        scale = db.scale,
        point = db.point,
        x = db.x,
        y = db.y,
        anchorFrame = db.anchorFrame,
        anchorPoint = db.anchorPoint,
    })

    self.bars[barKey] = bar
    self.items[barKey] = {}

    local anchorFrameRef = ResolveAnchorFrame(db.anchorFrame)
    local anchorRelPoint = db.anchorPoint or db.point or "CENTER"

    local mover = LibEditmode:Register(bar:GetFrame(), {
        label = "AT: " .. (db.name or barKey),
        syncSize = true,
        addonName = "AuraTracker",
        subKey = barKey,
        snapSize = db.snapSize,
        initialPoint = {
            db.point or "CENTER",
            anchorFrameRef,
            anchorRelPoint,
            db.x or 0,
            db.y or 0,
        },
        onMove = function(point, relTo, relPoint, x, y)
            db.point = point
            local af = ResolveAnchorFrame(db.anchorFrame)
            if af and af ~= UIParent then
                -- Recalculate offset relative to the configured anchor frame so
                -- that the bar stays anchored to that frame after dragging.
                local anchorRelPt = db.anchorPoint or point
                local barPtX, barPtY = GetPointScreenXY(bar:GetFrame(), point)
                local afPtX, afPtY  = GetPointScreenXY(af, anchorRelPt)
                db.x = barPtX - afPtX
                db.y = barPtY - afPtY
            else
                db.x = x
                db.y = y
            end
        end,
        onRightClick = function()
            local SP = ns.AuraTracker.SettingsPanel
            if SP then SP:Show(barKey) end
        end,
    })
    bar.mover = mover

    return bar
end
