local addonName, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local Config = ns.AuraTracker.Config
local TrackedItem = ns.AuraTracker.TrackedItem
local Icon = ns.AuraTracker.Icon
local Bar = ns.AuraTracker.Bar
local SettingsPanel = ns.AuraTracker.SettingsPanel

-- Create module via Ace3
local AuraTracker = LibStub("AceAddon-3.0"):NewAddon("AuraTracker", "AceEvent-3.0")
ns.AuraTracker.Controller = AuraTracker

-- Local state
local gcdStart, gcdDuration = nil, nil
local playerGUID = nil

-- ==========================================================
-- LIFECYCLE
-- ==========================================================

function AuraTracker:OnInitialize()
    -- Define base defaults; AceDB will populate missing keys
    local defaults = {
        profile = {
            enabled = true,
            bars = {},
        }
    }
    -- Initialize the standalone DB
    self.db = LibStub("AceDB-3.0"):New("SimpleAuraTrackerDB", defaults, true)

    self.bars = {}
    self.items = {}
    self.dropZones = {}
    self.pendingAura = nil
    
    playerGUID = UnitGUID("player")
    
    ns:FramePool_RegisterFrameFactory(Icon.POOL_KEY, Icon.CreateFrame)
end

function AuraTracker:OnEnable()
    local db = self:GetDB()
    if not db or not db.enabled then
        self:Disable()
        return
    end
    
    self:RebuildAllBars()
    self:CreateUpdateFrame()
    self:RegisterEvent("CHARACTER_POINTS_CHANGED", "OnTalentsChanged")
    self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnTalentsChanged")
    -- Register events
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnSpellUpdateCooldown")
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("SPELLS_CHANGED", "OnSpellsChanged")
    
    -- Drag & drop events
    self:RegisterEvent("ACTIONBAR_SHOWGRID", "OnDragStart")
    self:RegisterEvent("ACTIONBAR_HIDEGRID", "OnDragEnd")
    
    -- Hook buff frame for click-to-add
    self:HookBuffButtons()
    hooksecurefunc("BuffFrame_Update", function()
        self:HookBuffButtons()
    end)
end

function AuraTracker:OnDisable()
    self:HideDropZones()
    self:DestroyAllBars()
    if self.updateFrame then
        self.updateFrame:Hide()
    end
    self:UnregisterAllEvents()
end

function AuraTracker:GetAllBars()
    return self.bars
end

function AuraTracker:GetDB()
    return self.db.profile.auraTracker
end

function AuraTracker:GetBarDB(barKey)
    local db = self:GetDB()
    return db and db.bars and db.bars[barKey]
end

function AuraTracker:GetBars()
    local db = self:GetDB()
    return db and db.bars
end


function AuraTracker:OnTalentsChanged()
    -- Rebuild bars to re-check talent restrictions
    self:RebuildAllBars()
end

-- ==========================================================
-- UPDATE FRAME
-- ==========================================================

function AuraTracker:CreateUpdateFrame()
    if self.updateFrame then return end
    
    self.updateFrame = CreateFrame("Frame")
    self.updateFrame.elapsed = 0
    self.updateFrame:SetScript("OnUpdate", function(frame, elapsed)
        frame.elapsed = frame.elapsed + elapsed
        if frame.elapsed >= 0.1 then
            frame.elapsed = 0
            
            AuraTracker:UpdateAllCooldowns()

            AuraTracker:UpdateCooldownText()
        end
    end)
    self.updateFrame:Show()
end

-- ==========================================================
-- BAR MANAGEMENT
-- ==========================================================

function AuraTracker:CreateBar(barKey)
    local db = self:GetBarDB(barKey)
    if not db or not db.enabled then
        return nil
    end
    if self.bars[barKey] then
        return self.bars[barKey]
    end
    
    local bar = Bar:New(barKey, UIParent, {
        direction = db.direction,
        spacing = db.spacing,
        iconSize = db.iconSize,
        point = db.point,
        x = db.x,
        y = db.y,
    })
    
    self.bars[barKey] = bar
    self.items[barKey] = {}
    
    -- Register mover with click callback for settings panel
    if ns.RegisterMovableFrame then
        local SettingsPanel = ns.AuraTracker.SettingsPanel
        local mover = ns:RegisterMovableFrame(
            bar:GetFrame(),
            db,
            "AT: " .. (db.name or barKey),
            nil,
            "AuraTracker",
            function()
                if SettingsPanel then
                    SettingsPanel:Show(barKey)
                end
            end
        )
        bar.mover = mover
    end
    
    return bar
end

function AuraTracker:DeleteBar(barKey)
    local bar = self.bars[barKey]
    if not bar then return false end
    
    -- Release all icons back to pool
    for _, icon in ipairs(bar:GetIcons()) do
        icon:Destroy()
        ns:ReleaseFrame(icon:GetFrame())
    end
    
    -- Unregister mover
    if ns.UnregisterMover then
        ns:UnregisterMover(bar:GetFrame())
    end
    
    bar:Destroy()
    self.bars[barKey] = nil
    self.items[barKey] = nil
    
    return true
end

function AuraTracker:GetBar(barKey)
    return self.bars[barKey]
end

function AuraTracker:RebuildBar(barKey)
    local bar = self.bars[barKey]
    local db = self:GetBarDB(barKey)
    if not bar or not db then return end
    
    -- Release existing icons
    for _, icon in ipairs(bar:GetIcons()) do
        icon:Destroy()
        ns:ReleaseFrame(icon:GetFrame())
    end
    bar:ClearIcons()
    wipe(self.items[barKey])
    
    -- Update bar settings
    bar:SetDirection(db.direction)
    bar:SetSpacing(db.spacing)
    bar:SetIconSize(db.iconSize)
    bar:SetPosition(db.point, db.x, db.y)
    
    local styleOptions = {
        size = db.iconSize,
        fontSize = db.textSize,
        textColor = db.textColor,
        showCooldownText = db.showCooldownText,
    }
    
    -- Rebuild cooldown icons
    if db.trackedItems then
        for spellId, data in pairs(db.trackedItems) do
            local order = type(data) == "table" and data.order or 999
            if data['trackType'] == Config.TrackType.COOLDOWN then
                self:CreateCooldownIcon(barKey, spellId, order, styleOptions)
            end
            if data['trackType'] == Config.TrackType.AURA then
                local filterKey = data.type and string.upper(data.type) or "TARGET_DEBUFF"
                local displayMode = data.displayMode
                self:CreateAuraIcon(barKey, spellId, filterKey, data.auraId, order, styleOptions, displayMode)
            end
        end
    end
    
    -- Sort icons by order
    self:SortBarIcons(barKey)
    
    bar:UpdateLayout()
    
    -- Initial update
    self:UpdateAllCooldowns()
    self:UpdateAllAuras()
end

function AuraTracker:RebuildAllBars()
    self:DestroyAllBars()
    
    local db = self:GetDB()
    if not db or not db.enabled then return end
    
    for barKey, barSettings in pairs(db.bars) do
        if barSettings.enabled then
            self:CreateBar(barKey)
            self:RebuildBar(barKey)
        end
    end
end

function AuraTracker:DestroyAllBars()
    for barKey in pairs(self.bars) do
        self:DeleteBar(barKey)
    end
end

function AuraTracker:SortBarIcons(barKey)
    local bar = self.bars[barKey]
    if not bar then return end
    
    table.sort(bar:GetIcons(), function(a, b)
        local orderA = a.order or 999
        local orderB = b.order or 999
        return orderA < orderB
    end)
end

-- ==========================================================
-- ADDING / REMOVING TRACKED ITEMS
-- ==========================================================

function AuraTracker:CreateCooldownIcon(barKey, spellId, order, styleOptions)
    local bar = self.bars[barKey]
    local db = self:GetBarDB(barKey)
    if not bar or not db then return nil end
    
    -- Check if spell is known (if configured)
    if db.showOnlyKnown and not (IsSpellKnown(spellId) or IsSpellKnown(spellId, true)) then -- IsSpellKnow(SpellId, [checkPet])
        return nil
    end
    
    -- Create TrackedItem
    local item = TrackedItem:New(spellId, Config.TrackType.COOLDOWN)
    if not item:GetName() then return nil end
    
    -- Acquire frame from pool
    local frame = ns:AcquireFrame(Icon.POOL_KEY, bar:GetFrame())
    
    -- Create Icon wrapper
    local displayMode = Config:GetDefaultDisplayMode(Config.TrackType.COOLDOWN)
    local icon = Icon:New(frame, item, displayMode)
    icon.order = order

    icon:ApplyStyle(styleOptions)
    
    -- Store references
    self.items[barKey][spellId] = item
    bar:AddIcon(icon)
    
    return icon
end

function AuraTracker:CreateAuraIcon(barKey, spellId, filterKey, auraId, order, styleOptions, displayMode)
    local bar = self.bars[barKey]
    if not bar then return nil end
    
    -- Normalize filterKey
    filterKey = filterKey and string.upper(filterKey:gsub(" ", "_")) or "TARGET_DEBUFF"
    
    -- Create TrackedItem
    local item = TrackedItem:New(spellId, Config.TrackType.AURA, {
        auraId = auraId,
        filterKey = filterKey,
    })
    if not item:GetName() then return nil end
    
    -- Acquire frame from pool
    local frame = ns:AcquireFrame(Icon.POOL_KEY, bar:GetFrame())
    
    -- Use provided displayMode or fall back to default
    local finalDisplayMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.AURA, filterKey)
    local icon = Icon:New(frame, item, finalDisplayMode)
    icon.order = order
    icon:ApplyStyle(styleOptions)
    
    -- Store references
    self.items[barKey]["aura_" .. spellId] = item
    bar:AddIcon(icon)
    
    return icon
end

function AuraTracker:AddCooldown(barKey, spellId)
    local db = self:GetBarDB(barKey)
    if not db then return false, "Bar not found" end
    
    local name = GetSpellInfo(spellId)
    if not name then return false, "Spell not found" end
    
    db.trackedItems = db.trackedItems or {}
    if db.trackedItems[spellId] then return false, "Already tracked" end
    
    local maxOrder = 0
    for _, data in pairs(db.trackedItems) do
        local order = type(data) == "table" and data.order or 0
        maxOrder = math.max(maxOrder, order)
    end
    
    db.trackedItems[spellId] = { 
        order = maxOrder + 1,
        trackType = Config.TrackType.COOLDOWN,
        displayMode = Config.DisplayMode.ALWAYS,
    }
    self:RebuildBar(barKey)
    
    return true, name
end

function AuraTracker:RemoveCooldown(barKey, spellId)
    local db = self:GetBarDB(barKey)
    if not db or not db.trackedItems then return false end
    
    db.trackedItems[spellId] = nil
    self:RebuildBar(barKey)
    
    return true
end

function AuraTracker:AddAura(barKey, spellId, filterKey, specificAuraId, displayMode)
    local db = self:GetBarDB(barKey)
    if not db then return false, "Bar not found" end
    
    filterKey = filterKey or "TARGET_DEBUFF"
    local filterData = Config:GetAuraFilter(filterKey)
    if not filterData then return false, "Invalid filter type" end
    
    local name = GetSpellInfo(spellId)
    if not name then return false, "Spell not found" end
    
    local actualAuraId = specificAuraId or Config:GetMappedAuraId(spellId)
    
    db.trackedItems = db.trackedItems or {}
    if db.trackedItems[spellId] then return false, "Already tracked" end
    
    local maxOrder = 0
    for _, data in pairs(db.trackedItems) do
        local order = type(data) == "table" and data.order or 0
        maxOrder = math.max(maxOrder, order)
    end
    
    -- Use provided displayMode or fall back to default
    local finalDisplayMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.AURA, filterKey)
    
    db.trackedItems[spellId] = {
        order = maxOrder + 1,
        auraId = actualAuraId,
        type = filterKey:lower(),
        trackType = Config.TrackType.AURA,
        unit = filterData.unit,
        filter = filterData.filter,
        displayMode = finalDisplayMode,
    }
    
    self:RebuildBar(barKey)
    
    return true, name
end

function AuraTracker:RemoveAura(barKey, spellId)
    local db = self:GetBarDB(barKey)
    if not db or not db.trackedItems then return false end
    
    db.trackedItems[spellId] = nil
    self:RebuildBar(barKey)
    
    return true
end

-- ==========================================================
-- EVENT HANDLERS
-- ==========================================================

function AuraTracker:OnSpellUpdateCooldown()
    self:UpdateGCDState()

end

function AuraTracker:OnUnitAura(event, unit)
    if unit == "player" or unit == "target" or unit == "focus" then
        self:UpdateAurasForUnit(unit)
    end
end

function AuraTracker:OnTargetChanged()
    self:UpdateAurasForUnit("target")
end

function AuraTracker:OnPlayerEnteringWorld()
    playerGUID = UnitGUID("player")
    self:RebuildAllBars()
end

function AuraTracker:OnSpellsChanged()
    self:RebuildAllBars()
end

-- ==========================================================
-- UPDATE LOOPS
-- ==========================================================

function AuraTracker:UpdateAllCooldowns()
    for barKey, bar in pairs(self.bars) do
        local db = self:GetBarDB(barKey)
        if db and db.enabled then
            local needsLayout = false
            
            for _, icon in ipairs(bar:GetIcons()) do
                local item = icon:GetTrackedItem()
                if item and item:GetTrackType() == Config.TrackType.COOLDOWN then
                    local changed = item:Update(gcdStart, gcdDuration, db.ignoreGCD)
                    local visChanged = icon:Refresh()
                    needsLayout = needsLayout or visChanged
                end
            end
            
            if needsLayout then
                bar:UpdateLayout()
            end
        end
    end
end

function AuraTracker:UpdateAllAuras()
    for barKey, bar in pairs(self.bars) do
        local db = self:GetBarDB(barKey)
        if db and db.enabled then
            local needsLayout = false
            
            for _, icon in ipairs(bar:GetIcons()) do
                local item = icon:GetTrackedItem()
                if item and item:GetTrackType() == Config.TrackType.AURA then
                    local changed = item:Update()
                    local visChanged = icon:Refresh()
                    needsLayout = needsLayout or visChanged
                end
            end
            
            if needsLayout then
                bar:UpdateLayout()
            end
        end
    end
end

function AuraTracker:UpdateAurasForUnit(unit)
    for barKey, bar in pairs(self.bars) do
        local db = self:GetBarDB(barKey)
        if db and db.enabled then
            local needsLayout = false
            
            for _, icon in ipairs(bar:GetIcons()) do
                local item = icon:GetTrackedItem()
                if item and item:GetTrackType() == Config.TrackType.AURA then
                    -- Only update if this item tracks the specified unit
                    if item.unit == unit then
                        local changed = item:Update()
                        local visChanged = icon:Refresh()
                        needsLayout = needsLayout or visChanged
                    end
                end
            end
            
            if needsLayout then
                bar:UpdateLayout()
            end
        end
    end
end

function AuraTracker:UpdateCooldownText()
    local now = GetTime()
    for _, bar in pairs(self.bars) do
        for _, icon in ipairs(bar:GetIcons()) do
            if icon:GetFrame():IsShown() then
                icon:UpdateCooldownText(now)
            end
        end
    end
end

function AuraTracker:RefreshBar(barKey)
    local bar = self.bars[barKey]
    local db = self:GetBarDB(barKey)
    if not bar or not db then return end
    
    local styleOptions = {
        size = db.iconSize,
        fontSize = db.textSize,
        textColor = db.textColor,
        showCooldownText = db.showCooldownText,
    }
    
    local needsLayout = false
    
    for _, icon in ipairs(bar:GetIcons()) do
        icon:ApplyStyle(styleOptions)
        local item = icon:GetTrackedItem()
        if item then
            item:Update(gcdStart, gcdDuration, db.ignoreGCD)
            local visChanged = icon:Refresh()
            needsLayout = needsLayout or visChanged
        end
    end
    
    if needsLayout then
        bar:UpdateLayout()
    end
end

-- ==========================================================
-- GCD HANDLING
-- ==========================================================

function AuraTracker:UpdateGCDState()
    local start, duration = GetSpellCooldown(Config.GCD_SPELL_ID)
    if duration and duration > 0 and duration <= Config.GCD_THRESHOLD then
        gcdStart, gcdDuration = start, duration
    else
        gcdStart, gcdDuration = nil, nil
    end
end

function AuraTracker:IsGCD(start, duration)
    if not gcdStart or not gcdDuration then return false end
    if not start or start == 0 or not duration or duration <= 0 then return false end
    return math.abs(start - gcdStart) < 0.05 and math.abs(duration - gcdDuration) < 0.05
end

-- ==========================================================
-- UTILITY
-- ==========================================================

function AuraTracker:IsSpellKnown(spellId)
    local name = GetSpellInfo(spellId)
    if not name then return false end
    
    local _, _, enabled = GetSpellCooldown(spellId)
    if enabled == 0 then return false end
    
    local usable, noMana = IsUsableSpell(name)
    return usable or noMana
end

function AuraTracker:FormatTime(seconds)
    if seconds >= 60 then
        return string.format("%dm", math.floor(seconds / 60))
    end
    if seconds >= 10 then
        return tostring(math.floor(seconds))
    end
    return string.format("%.1f", seconds)
end

function AuraTracker:Print(message)
    print("|cff00bfffAuraTracker:|r " .. message)
end


-- ==========================================================
-- DRAG & DROP / DROPZONES
-- ==========================================================

function AuraTracker:OnDragStart()
    self.isDragging = true
    self:ShowDropZones()
end

function AuraTracker:OnDragEnd()
    self.isDragging = false
    self:HideDropZones()
end

function AuraTracker:ShowDropZones()
    for barKey, bar in pairs(self.bars) do
        if not self.dropZones then
            self.dropZones = {}
        end
        
        if not self.dropZones[barKey] then
            local dropZone = ns.DropZone:Attach(
                bar:GetFrame(),
                function(cursorType, id, subType, isShift)
                    self:HandleDrop(barKey, cursorType, id, subType, isShift)
                end,
                {
                    text = "Track Spell or Buff",
                    shiftText = "Track as TARGET DEBUFF",
                }
            )
            dropZone:EnableMouse(true)
            dropZone:SetScript("OnMouseUp", function(_, button)
                if button == "LeftButton" then
                    self:OnBarClick(barKey)
                end
            end)
            self.dropZones[barKey] = dropZone
        end
        
        self.dropZones[barKey]:Show()
    end
end

function AuraTracker:HideDropZones()
    if not self.dropZones then return end
    
    for barKey, dropZone in pairs(self.dropZones) do
        ns.DropZone:Release(dropZone)
        self.dropZones[barKey] = nil
    end
end

function AuraTracker:HandleDrop(barKey, cursorType, id, subType, isShift)
    if cursorType ~= "spell" then return end
    
    local spellLink = GetSpellLink(id, subType)
    if not spellLink then return end
    
    local spellId = tonumber(spellLink:match("spell:(%d+)"))
    if not spellId then return end
    
    local success, result
    if isShift then
        success, result = self:AddAura(barKey, spellId, "TARGET_DEBUFF")
        if success then
            self:Print("Now tracking |cff00ff00" .. result .. "|r as target debuff")
        end
    else
        success, result = self:AddCooldown(barKey, spellId)
        if success then
            self:Print("Now tracking |cff00ff00" .. result .. "|r cooldown")
        end
    end
    
    if not success and result then
        self:Print("Failed: " .. result)
    end
end

-- ==========================================================
-- BUFF BUTTON DRAG & DROP
-- ==========================================================

function AuraTracker:HandleAuraDrop(barKey)
    if not self.draggedAura then return end
    
    local filterKey = self.draggedAura.filterKey or "TARGET_DEBUFF"
    local success, msg = self:AddAura(barKey, self.draggedAura.id, filterKey, nil, self.draggedAura.displayMode)
    
    if success then
        local modeText = ""
        if self.draggedAura.displayMode == Config.DisplayMode.MISSING_ONLY then
            modeText = " (show when missing)"
        end
        self:Print("Added |cff00ff00" .. self.draggedAura.name .. "|r as " .. filterKey:lower() .. modeText)
    else
        self:Print("Failed: " .. (msg or "Unknown error"))
    end
end

function AuraTracker:HookBuffButtons()
    -- Hook player buff buttons
    for i = 1, 32 do
        local button = _G["BuffButton" .. i]
        if button and not button._auraTrackerHooked then
            self:HookAuraButton(button, "player", "HELPFUL", "PLAYER_BUFF")
            button._auraTrackerHooked = true
        end
    end
    
    -- Hook player debuff buttons
    for i = 1, 16 do
        local button = _G["DebuffButton" .. i]
        if button and not button._auraTrackerHooked then
            self:HookAuraButton(button, "player", "HARMFUL", "PLAYER_DEBUFF")
            button._auraTrackerHooked = true
        end
    end
end

-- ==========================================================
-- BUFF BUTTON DRAG & DROP
-- ==========================================================

-- Helper function to create/get the visual drag icon frame
function AuraTracker:GetDragFrame()
    if not self.dragIconFrame then
        self.dragIconFrame = CreateFrame("Frame", nil, UIParent)
        self.dragIconFrame:SetFrameStrata("TOOLTIP") -- Keep it on top of everything
        self.dragIconFrame:SetSize(30, 30) -- Size of the dragged icon
        
        self.dragIconFrame.texture = self.dragIconFrame:CreateTexture(nil, "ARTWORK")
        self.dragIconFrame.texture:SetAllPoints()
        
        -- Make it follow the mouse cursor
        self.dragIconFrame:SetScript("OnUpdate", function(f)
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            -- Offset slightly bottom-right so the cursor pointer is still visible
            f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (x / scale) + 15, (y / scale) - 15)
        end)
        self.dragIconFrame:Hide()
    end
    return self.dragIconFrame
end

function AuraTracker:HandleAuraDrop(barKey)
    if not self.draggedAura then return end
    
    local filterKey = self.draggedAura.filterKey or "TARGET_DEBUFF"
    local success, msg = self:AddAura(barKey, self.draggedAura.id, filterKey, nil, self.draggedAura.displayMode)
    
    if success then
        local modeText = ""
        if self.draggedAura.displayMode == Config.DisplayMode.MISSING_ONLY then
            modeText = " (show when missing)"
        end
        self:Print("Added |cff00ff00" .. self.draggedAura.name .. "|r as " .. filterKey:lower() .. modeText)
    else
        self:Print("Failed: " .. (msg or "Unknown error"))
    end
end

function AuraTracker:HookAuraButton(button, unit, filter, filterKey)
    button:RegisterForDrag("LeftButton")
    
    local oldDragStart = button:GetScript("OnDragStart")
    local oldDragStop = button:GetScript("OnDragStop")
    
    button:SetScript("OnDragStart", function(b)
        local name, _, icon, _, _, _, _, _, _, _, spellId = UnitAura(unit, b:GetID(), filter)
        if name and spellId then
            local displayMode = IsShiftKeyDown() and Config.DisplayMode.MISSING_ONLY or nil
            
            self.draggedAura = {
                name = name,
                id = spellId,
                filterKey = filterKey,
                displayMode = displayMode,
            }
            
            -- Show drop zones
            self:ShowDropZones()
            
            -- Show the custom cursor icon
            if icon then
                local dragFrame = self:GetDragFrame()
                dragFrame.texture:SetTexture(icon)
                dragFrame:Show()
            end
        end
        
        if oldDragStart then oldDragStart(b) end
    end)

    button:SetScript("OnDragStop", function(b)
        if self.draggedAura then
            local focus = GetMouseFocus()
            
            if self.dropZones then
                for barKey, dropZone in pairs(self.dropZones) do
                    if focus == dropZone then
                        self:HandleAuraDrop(barKey)
                        break
                    end
                end
            end
            
            -- Clean up state
            self.draggedAura = nil
            self:HideDropZones()
            
            -- Hide the custom cursor icon
            if self.dragIconFrame then
                self.dragIconFrame:Hide()
            end
        end
        
        if oldDragStop then oldDragStop(b) end
    end)
end


-- ==========================================================
-- EDIT MODE INTEGRATION
-- ==========================================================

function AuraTracker:OnEditModeToggle(enabled)
    if not enabled then
        local SettingsPanel = ns.AuraTracker.SettingsPanel
        if SettingsPanel then
            SettingsPanel:Hide()
        end
    end
end




-- ==========================================================
-- CLASS/TALENT RESTRICTION CHECK
-- ==========================================================

function AuraTracker:ShouldShowBar(barKey)
    local db = self:GetBarDB(barKey)
    if not db or not db.enabled then
        return false
    end

    -- Check class restriction
    if db.classRestriction and db.classRestriction ~= "NONE" then
        local _, playerClass = UnitClass("player")
        if playerClass ~= db.classRestriction then
            return false
        end
    end

    -- Check talent restriction
    if db.talentRestriction and db.talentRestriction ~= "NONE" then
        if not SettingsPanel:CheckTalentRestriction(db.talentRestriction) then
            return false
        end
    end

    return true
end