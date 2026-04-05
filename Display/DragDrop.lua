local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local Config = ns.AuraTracker.Config

-- Localize frequently-used globals
local pairs = pairs
local GetSpellLink, GetCursorInfo, ClearCursor = GetSpellLink, GetCursorInfo, ClearCursor
local GetSpellInfo = GetSpellInfo
local GetPetActionInfo = GetPetActionInfo
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
    self.draggedPetSpell = nil
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
    self.draggedEnchantSlot = nil
    self.draggedPetSpell = nil
    self._pendingPetSpell = nil
    self:HideDropZones()
    if self.dragIconFrame then
        self.dragIconFrame:Hide()
    end
end

-- ==========================================================
-- DROP ZONES
-- ==========================================================

local function CreateDropZoneFrame(bar, handler, clickCallback, auraHandler)
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
        if cursorType then
            local isShift = IsShiftKeyDown()
            ClearCursor()
            handler(cursorType, id, subType, isShift)
        elseif auraHandler then
            auraHandler()
        end
    end)

    dropZone:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            local cursorType, id, subType = GetCursorInfo()
            if cursorType == "spell" or cursorType == "item" then
                local isShift = IsShiftKeyDown()
                ClearCursor()
                handler(cursorType, id, subType, isShift)
            elseif auraHandler and auraHandler() then
                -- Aura drop from buff frame handled
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

    if cursorType == "petaction" then
        self:HandlePetSpellDrop(barKey)
        return
    end

    if cursorType ~= "spell" then return end

    local controller = self.controller

    local spellLink = GetSpellLink(id, subType)
    -- Fallback for edge cases where GetSpellLink returns nil with a subType.
    -- On some WotLK builds GetCursorInfo() returns the real spell ID as 'id'
    -- rather than a book-slot index, so retry without the subType first.
    -- If that also fails, GetSpellInfo(id, "pet") can retrieve the spell name
    -- which is then resolved via GetSpellLink.
    if not spellLink and subType == "pet" then
        spellLink = GetSpellLink(id)
        if not spellLink then
            local petSpellName = GetSpellInfo(id, "pet")
            if petSpellName then
                spellLink = GetSpellLink(petSpellName)
            end
        end
    end
    if not spellLink then return end

    local spellId = tonumber(spellLink:match("spell:(%d+)"))
    if not spellId then return end

    local success, result

    -- Totem spells: add an element-slot totem tracker instead of a spell CD.
    if Config:IsTotemSpell(spellId) then
        success, result = controller:AddTotem(barKey, spellId)
        if success then
            controller:Print("Now tracking |cff00ff00" .. result .. "|r (totem)")
        elseif result then
            controller:Print("Failed: " .. result)
        end
        return
    end

    -- Apply global/custom mappings; fall back to shift-key heuristic.
    -- isShift is forwarded so that SpellToAuraMap entries (e.g. Icy Touch →
    -- Frost Fever, Plague Strike → Blood Plague) only activate on shift-drag.
    local mapping = controller:GetDropAction(spellId, isShift)
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
    elseif Config:IsWeaponEnchantSpell(spellId) then
        success, result = controller:AddAura(barKey, spellId, "PLAYER_BUFF")
        if success then
            controller:Print("Now tracking |cff00ff00" .. result .. "|r weapon enchant buff")
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
    -- If the item applies a temporary weapon enchant, track the enchant duration
    if Config:IsWeaponEnchantItem(itemId) then
        local slot = Config:GetWeaponEnchantSlot(itemId)
        local success, result = controller:AddWeaponEnchant(barKey, itemId, slot)
        if success then
            controller:Print("Now tracking |cff00ff00" .. result .. "|r weapon enchant")
        elseif result then
            controller:Print("Failed: " .. result)
        end
        return
    end
    -- If the item has known trinket ICD data, track as Internal CD
    if Config:IsTrinketWithICD(itemId) then
        local success, result = controller:AddInternalCD(barKey, itemId)
        if success then
            controller:Print("Now tracking |cff00ff00" .. result .. "|r trinket ICD")
        elseif result then
            controller:Print("Failed: " .. result)
        end
        return
    end
    local success, result = controller:AddItem(barKey, itemId)
    if success then
        controller:Print("Now tracking |cff00ff00" .. result .. "|r item cooldown")
    elseif result then
        controller:Print("Failed: " .. result)
    end
end

