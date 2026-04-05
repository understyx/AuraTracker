local _, ns = ...

local Config = ns.AuraTracker.Config
local Icon = ns.AuraTracker.Icon
local Bar = ns.AuraTracker.Bar
local UpdateEngine = ns.AuraTracker.UpdateEngine

-- Localize frequently-used globals
local pairs, ipairs, wipe = pairs, ipairs, wipe
local math_max = math.max
local string_upper = string.upper
local table_sort = table.sort
local UnitClass = UnitClass
local type, next, tostring = type, next, tostring
local math_floor = math.floor
local string_char, string_byte = string.char, string.byte

-- Library references
local LibFramePool = LibStub("LibFramePool-1.0")
local LibEditmode  = LibStub("LibEditmode-1.0")

-- The addon object (created in AuraTracker.lua)
local AuraTracker = ns.AuraTracker.Controller

-- ==========================================================
-- BASE64 HELPERS  (used by import/export)
-- ==========================================================

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local B64_DECODE = {}
for i = 1, #B64_CHARS do
    B64_DECODE[B64_CHARS:sub(i, i)] = i - 1
end

local function B64Encode(data)
    local result = {}
    local len = #data
    local i = 1
    while i <= len do
        local b0 = string_byte(data, i)
        local b1 = string_byte(data, i + 1) or 0
        local b2 = string_byte(data, i + 2) or 0
        local n  = b0 * 65536 + b1 * 256 + b2
        result[#result + 1] = B64_CHARS:sub(math_floor(n / 262144) + 1, math_floor(n / 262144) + 1)
        result[#result + 1] = B64_CHARS:sub(math_floor((n % 262144) / 4096) + 1, math_floor((n % 262144) / 4096) + 1)
        result[#result + 1] = (i + 1 <= len) and B64_CHARS:sub(math_floor((n % 4096) / 64) + 1, math_floor((n % 4096) / 64) + 1) or "="
        result[#result + 1] = (i + 2 <= len) and B64_CHARS:sub((n % 64) + 1, (n % 64) + 1) or "="
        i = i + 3
    end
    return table.concat(result)
end

local function B64Decode(data)
    data = data:gsub("[^A-Za-z0-9+/=]", "")
    local result = {}
    local len = #data
    local i = 1
    while i + 3 <= len do
        local c0 = B64_DECODE[data:sub(i,     i    )] or 0
        local c1 = B64_DECODE[data:sub(i + 1, i + 1)] or 0
        local c2 = B64_DECODE[data:sub(i + 2, i + 2)] or 0
        local c3 = B64_DECODE[data:sub(i + 3, i + 3)] or 0
        local n  = c0 * 262144 + c1 * 4096 + c2 * 64 + c3
        result[#result + 1] = string_char(math_floor(n / 65536))
        if data:sub(i + 2, i + 2) ~= "=" then
            result[#result + 1] = string_char(math_floor((n % 65536) / 256))
        end
        if data:sub(i + 3, i + 3) ~= "=" then
            result[#result + 1] = string_char(n % 256)
        end
        i = i + 4
    end
    return table.concat(result)
end

-- Export string prefix (version tag for future format changes)
local EXPORT_PREFIX = "ATv1:"

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

-- ==========================================================
-- PRIVATE HELPERS
-- ==========================================================

--- Recursively deep-copies a value so mutating the result does not affect
--- the original table.  Used when instantiating bars from example templates.
local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = DeepCopy(v) end
    return copy
end

--- Returns a key that is not already present in dbBars.
--- Tries baseKey first, then appends an incrementing counter until a free
--- slot is found.
local function FindUniqueBarKey(dbBars, baseKey)
    local candidate = baseKey
    local counter   = 1
    while dbBars[candidate] do
        candidate = baseKey .. counter
        counter   = counter + 1
    end
    return candidate
end

-- Builds the style options table from a bar's DB entry.
-- Exposed on ns.AuraTracker so UpdateEngine.lua can reuse it without duplication.
local function BuildStyleOptions(db)
    return {
        size = db.iconSize,
        fontSize = db.textSize,
        fontOutline = db.fontOutline,
        font = db.font,
        snapshotFontSize = db.snapshotTextSize,
        showSnapshotBG = db.showSnapshotBG,
        snapshotBGAlpha = db.snapshotBGAlpha,
        textColor = db.textColor,
        showCooldownText = db.showCooldownText,
    }
end
ns.AuraTracker.BuildStyleOptions = BuildStyleOptions

-- ==========================================================
-- BAR MANAGEMENT
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

function AuraTracker:DeleteBar(barKey)
    local bar = self.bars[barKey]
    if bar then
        for _, icon in ipairs(bar:GetIcons()) do
            icon:Destroy()
            LibFramePool:Release(icon:GetFrame())
        end

        LibEditmode:Unregister(bar:GetFrame())

        bar:Destroy()
        self.bars[barKey] = nil
        self.items[barKey] = nil
    end

    -- Always remove from database even if the bar widget was not
    -- active (e.g. hidden by class restriction or disabled).
    local profileDB = self:GetDB()
    if profileDB and profileDB.bars then
        profileDB.bars[barKey] = nil
    end

    return true
end

function AuraTracker:GetBar(barKey)
    return self.bars[barKey]
end

function AuraTracker:ReleaseBarIcons(barKey)
    local bar = self.bars[barKey]
    if not bar then return end
    for _, icon in ipairs(bar:GetIcons()) do
        icon:Destroy()
        LibFramePool:Release(icon:GetFrame())
    end
    bar:ClearIcons()
    if self.items[barKey] then
        wipe(self.items[barKey])
    end
    -- Rebuild proc→item reverse lookup from all remaining bars so that
    -- releasing one bar's icons does not break proc detection for other bars.
    self:RebuildProcLookup()
end

--- Rebuilds the _procToItems reverse lookup table
--- (procSpellId → { TrackedItem → true }) from all bars' tracked items.
function AuraTracker:RebuildProcLookup()
    self._procToItems = {}
    for bk, itemTable in pairs(self.items) do
        for key, item in pairs(itemTable) do
            if item:GetTrackType() == Config.TrackType.INTERNAL_CD then
                local procSpells = item:GetProcSpellIds()
                if procSpells then
                    for _, procId in ipairs(procSpells) do
                        self._procToItems[procId] = self._procToItems[procId] or {}
                        self._procToItems[procId][item] = true
                    end
                end
            end
        end
    end
end

function AuraTracker:RebuildBar(barKey)
    local db = self:GetBarDB(barKey)
    if not db then return end

    -- Class/talent restrictions may have changed via settings; clear this bar's cache.
    self:InvalidateBarStaticCache(barKey)

    if not self:ShouldShowBar(barKey) then
        local bar = self.bars[barKey]
        if bar then
            self:ReleaseBarIcons(barKey)
            LibEditmode:Unregister(bar:GetFrame())
            bar:Destroy()
            self.bars[barKey] = nil
            self.items[barKey] = nil
        end
        return
    end

    if not self.bars[barKey] then
        self:CreateBar(barKey)
    end

    local bar = self.bars[barKey]
    if not bar then return end

    self:ReleaseBarIcons(barKey)

    bar:SetDirection(db.direction)
    bar:SetSpacing(db.spacing)
    bar:SetIconSize(db.iconSize)
    bar:SetScale(db.scale or 1.0)
    bar:SetPosition(db.point, db.x, db.y, db.anchorFrame, db.anchorPoint)
    
    local styleOptions = BuildStyleOptions(db)
    
    if db.trackedItems then
        for spellId, data in pairs(db.trackedItems) do
            local order = type(data) == "table" and data.order or 999
            local icon
            if data.trackType == Config.TrackType.COOLDOWN then
                icon = self:CreateCooldownIcon(barKey, spellId, order, styleOptions, data.displayMode)
            elseif data.trackType == Config.TrackType.AURA then
                local filterKey = data.type and string_upper(data.type) or "TARGET_DEBUFF"
                icon = self:CreateAuraIcon(barKey, spellId, filterKey, data.auraId, order, styleOptions, data.displayMode, data.onlyMine, data.exclusiveSpells)
                if icon then icon.showSnapshotText = data.showSnapshotText or false end
            elseif data.trackType == Config.TrackType.ITEM then
                icon = self:CreateItemIcon(barKey, spellId, order, styleOptions, data.displayMode)
            elseif data.trackType == Config.TrackType.COOLDOWN_AURA then
                local filterKey = data.type and string_upper(data.type) or "TARGET_DEBUFF"
                icon = self:CreateCooldownAuraIcon(barKey, spellId, filterKey, data.auraId, order, styleOptions, data.displayMode, data.onlyMine, data.exclusiveSpells)
                if icon then icon.showSnapshotText = data.showSnapshotText or false end
            elseif data.trackType == Config.TrackType.INTERNAL_CD then
                icon = self:CreateInternalCDIcon(barKey, spellId, order, styleOptions, data.displayMode)
            elseif data.trackType == Config.TrackType.WEAPON_ENCHANT then
                icon = self:CreateWeaponEnchantIcon(barKey, spellId, data.slot, order, styleOptions, data.displayMode, data.expectedEnchant)
            elseif data.trackType == Config.TrackType.TOTEM then
                icon = self:CreateTotemIcon(barKey, spellId, data.spellId, order, styleOptions, data.displayMode)
            end
            if icon then
                icon.conditionals   = data.conditionals
                icon.loadConditions = data.loadConditions
                icon.onClickActions = data.onClickActions
                icon.onShowActions  = data.onShowActions
                icon.onHideActions  = data.onHideActions
                icon:ApplyCustomTexts(data.customTexts, styleOptions)
            end
        end
    end
    
    self:SortBarIcons(barKey)
    self:SyncEquipState()
    self._prevTrinketSlots = self:GetTrinketSlotMap()

    -- Initial update so icons reflect correct state before syncing mover size
    UpdateEngine:UpdateAllCooldowns()
    UpdateEngine:UpdateAllAuras()
    bar:DoLayout()

    if bar.mover then
        local frame = bar:GetFrame()
        local scale = frame:GetScale()
        bar.mover:SetSize(frame:GetWidth() * scale, frame:GetHeight() * scale)
        bar.mover:ClearAllPoints()
        local anchorFrameRef = ResolveAnchorFrame(db.anchorFrame)
        local anchorRelPoint = db.anchorPoint or db.point or "CENTER"
        bar.mover:SetPoint(
            db.point or "CENTER",
            anchorFrameRef,
            anchorRelPoint,
            db.x or 0,
            db.y or 0
        )
        bar.mover.snapSize = db.snapSize
    end
end

function AuraTracker:RebuildAllBars()
    self:DestroyAllBars()
    
    local db = self:GetDB()
    if not db or not db.enabled then return end
    
    for barKey in pairs(db.bars) do
        if self:ShouldShowBar(barKey) then
            self:CreateBar(barKey)
            self:RebuildBar(barKey)
        end
    end
end

--- Re-evaluate bar load conditions and show/hide bars whose visibility
--- state has changed.  This is intentionally lightweight: it only calls
--- RebuildBar for bars that actually need to toggle, keeping the per-tick
--- cost close to zero when nothing changes.
function AuraTracker:RecheckBarConditions()
    local db = self:GetDB()
    if not db or not db.enabled then return end

    for barKey in pairs(db.bars) do
        local shouldShow = self:ShouldShowBar(barKey)
        local isShown    = self.bars[barKey] ~= nil

        if shouldShow ~= isShown then
            self:RebuildBar(barKey)
        end
    end
end

function AuraTracker:DestroyAllBars()
    for barKey, bar in pairs(self.bars) do
        for _, icon in ipairs(bar:GetIcons()) do
            icon:Destroy()
            LibFramePool:Release(icon:GetFrame())
        end
        LibEditmode:Unregister(bar:GetFrame())
        bar:Destroy()
    end
    wipe(self.bars)
    wipe(self.items)
end

function AuraTracker:SortBarIcons(barKey)
    local bar = self.bars[barKey]
    if not bar then return end
    
    table_sort(bar:GetIcons(), function(a, b)
        local orderA = a.order or 999
        local orderB = b.order or 999
        return orderA < orderB
    end)
end

