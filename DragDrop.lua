local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local Config = ns.AuraTracker.Config

-- Localize frequently-used globals
local pairs = pairs
local GetSpellLink, GetCursorInfo, ClearCursor = GetSpellLink, GetCursorInfo, ClearCursor
local GetCursorPosition, GetMouseFocus = GetCursorPosition, GetMouseFocus
local IsShiftKeyDown = IsShiftKeyDown
local UnitAura = UnitAura
local CreateFrame = CreateFrame
local tonumber = tonumber

local DragDrop = {}
ns.AuraTracker.DragDrop = DragDrop

-- ==========================================================
-- INITIALIZATION
-- ==========================================================

function DragDrop:Init(controller, onBarClick)
    self.controller = controller
    self.onBarClick = onBarClick
    self.dropZones = {}
    self.isDragging = false
    self.draggedAura = nil
    self.dragIconFrame = nil
end

-- ==========================================================
-- DRAG STATE
-- ==========================================================

function DragDrop:OnDragStart()
    self.isDragging = true
    self:ShowDropZones()
end

function DragDrop:OnDragEnd()
    self.isDragging = false
    self:HideDropZones()
end

function DragDrop:ClearDragState()
    self.draggedAura = nil
    self:HideDropZones()
    if self.dragIconFrame then
        self.dragIconFrame:Hide()
    end
end

-- ==========================================================
-- DROP ZONES
-- ==========================================================

local function CreateDropZoneFrame(bar, handler, clickCallback, auraDropHandler)
    local dropZone = CreateFrame("Frame", nil, bar:GetFrame())
    dropZone:SetAllPoints(bar:GetFrame())
    dropZone:SetFrameLevel(bar:GetFrame():GetFrameLevel() + 10)
    dropZone:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    dropZone:SetBackdropColor(0, 0.5, 1, 0.3)
    dropZone:SetBackdropBorderColor(0, 0.8, 1, 0.8)

    local label = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText("Drop Here")
    dropZone.label = label

    dropZone:EnableMouse(true)

    dropZone:SetScript("OnReceiveDrag", function()
        local cursorType, id, subType = GetCursorInfo()
        local isShift = IsShiftKeyDown()
        ClearCursor()
        handler(cursorType, id, subType, isShift)
    end)

    dropZone:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            local cursorType, id, subType = GetCursorInfo()
            if cursorType == "spell" or cursorType == "item" then
                local isShift = IsShiftKeyDown()
                ClearCursor()
                handler(cursorType, id, subType, isShift)
            elseif auraDropHandler and auraDropHandler() then
                -- Aura drag from buff frame (no cursor item); handled before clickCallback
            else
                clickCallback()
            end
        end
    end)

    return dropZone
end

function DragDrop:ShowDropZones()
    local controller = self.controller
    for barKey, bar in pairs(controller.bars) do
        if not self.dropZones[barKey] then
            local dropZone = CreateDropZoneFrame(
                bar,
                function(cursorType, id, subType, isShift)
                    self:HandleDrop(barKey, cursorType, id, subType, isShift)
                end,
                function()
                    if self.onBarClick then self.onBarClick(barKey) end
                end,
                function()
                    if self.draggedAura then
                        self:HandleAuraDrop(barKey)
                        self:ClearDragState()
                        return true
                    end
                    return false
                end
            )
            self.dropZones[barKey] = dropZone
        end

        self.dropZones[barKey]:Show()
    end
end

function DragDrop:HideDropZones()
    if not self.dropZones then return end

    for barKey, dropZone in pairs(self.dropZones) do
        dropZone:Hide()
        dropZone:SetParent(nil)
        self.dropZones[barKey] = nil
    end
end

-- ==========================================================
-- SPELL DROP HANDLING
-- ==========================================================

function DragDrop:HandleDrop(barKey, cursorType, id, subType, isShift)
    if cursorType == "item" then
        return self:HandleItemDrop(barKey, id)
    end

    if cursorType ~= "spell" then return end

    local controller = self.controller

    local spellLink = GetSpellLink(id, subType)
    if not spellLink then return end

    local spellId = tonumber(spellLink:match("spell:(%d+)"))
    if not spellId then return end

    local success, result

    -- Apply global/custom mappings; fall back to shift-key heuristic
    local mapping = controller:GetDropAction(spellId)
    if mapping then
        if mapping.trackType == Config.TrackType.AURA then
            local fk = mapping.filterKey or "TARGET_DEBUFF"
            success, result = controller:AddAura(barKey, spellId, fk, mapping.auraId)
            if success then
                local fkLabel = fk:lower():gsub("_", " ")
                controller:Print("Now tracking |cff00ff00" .. result .. "|r (" .. fkLabel .. ", mapped)")
            end
        elseif mapping.trackType == Config.TrackType.COOLDOWN_AURA then
            local fk = mapping.filterKey or "TARGET_DEBUFF"
            success, result = controller:AddCooldownAura(barKey, spellId, fk, mapping.auraId)
            if success then
                controller:Print("Now tracking |cff00ff00" .. result .. "|r cooldown + aura (mapped)")
            end
        else
            success, result = controller:AddCooldown(barKey, spellId)
            if success then
                controller:Print("Now tracking |cff00ff00" .. result .. "|r cooldown (mapped)")
            end
        end
    elseif Config.DualTrackSpells[spellId] then
        local dualConfig = Config.DualTrackSpells[spellId]
        local fk = dualConfig.filterKey or "TARGET_DEBUFF"
        success, result = controller:AddCooldownAura(barKey, spellId, fk, dualConfig.auraId)
        if success then
            controller:Print("Now tracking |cff00ff00" .. result .. "|r cooldown + aura")
        end
    elseif isShift then
        success, result = controller:AddAura(barKey, spellId, "TARGET_DEBUFF")
        if success then
            controller:Print("Now tracking |cff00ff00" .. result .. "|r as target debuff (only mine)")
        end
    else
        success, result = controller:AddCooldown(barKey, spellId)
        if success then
            controller:Print("Now tracking |cff00ff00" .. result .. "|r cooldown")
        end
    end

    if not success and result then
        controller:Print("Failed: " .. result)
    end
end

-- ==========================================================
-- ITEM DROP HANDLING
-- ==========================================================

function DragDrop:HandleItemDrop(barKey, itemId)
    local controller = self.controller
    local success, result = controller:AddItem(barKey, itemId)
    if success then
        controller:Print("Now tracking |cff00ff00" .. result .. "|r item cooldown")
    elseif result then
        controller:Print("Failed: " .. result)
    end
end

-- ==========================================================
-- BUFF BUTTON HOOKS (aura drag from buff frame)
-- ==========================================================

function DragDrop:HookBuffButtons()
    for i = 1, 32 do
        local button = _G["BuffButton" .. i]
        if button and not button._auraTrackerHooked then
            self:HookAuraButton(button, "player", "HELPFUL", "PLAYER_BUFF")
            button._auraTrackerHooked = true
        end
    end

    for i = 1, 16 do
        local button = _G["DebuffButton" .. i]
        if button and not button._auraTrackerHooked then
            self:HookAuraButton(button, "player", "HARMFUL", "PLAYER_DEBUFF")
            button._auraTrackerHooked = true
        end
    end
end

function DragDrop:GetDragFrame()
    if not self.dragIconFrame then
        self.dragIconFrame = CreateFrame("Frame", nil, UIParent)
        self.dragIconFrame:SetFrameStrata("TOOLTIP")
        self.dragIconFrame:SetSize(30, 30)

        self.dragIconFrame.texture = self.dragIconFrame:CreateTexture(nil, "ARTWORK")
        self.dragIconFrame.texture:SetAllPoints()

        self.dragIconFrame:SetScript("OnUpdate", function(f)
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (x / scale) + 15, (y / scale) - 15)
        end)
        self.dragIconFrame:Hide()
    end
    return self.dragIconFrame
end

function DragDrop:HandleAuraDrop(barKey)
    if not self.draggedAura then return end

    local controller = self.controller
    local filterKey = self.draggedAura.filterKey or "TARGET_DEBUFF"
    local success, msg = controller:AddAura(barKey, self.draggedAura.id, filterKey, nil, self.draggedAura.displayMode)

    if success then
        local modeText = ""
        if self.draggedAura.displayMode == Config.DisplayMode.MISSING_ONLY then
            modeText = " (show when missing)"
        end
        controller:Print("Added |cff00ff00" .. self.draggedAura.name .. "|r as " .. filterKey:lower() .. modeText)
    else
        controller:Print("Failed: " .. (msg or "Unknown error"))
    end
end

function DragDrop:HookAuraButton(button, unit, filter, filterKey)
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

            self:ShowDropZones()

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
                for bk, dropZone in pairs(self.dropZones) do
                    if focus == dropZone then
                        self:HandleAuraDrop(bk)
                        break
                    end
                end
            end

            self:ClearDragState()
        end

        if oldDragStop then oldDragStop(b) end
    end)
end
