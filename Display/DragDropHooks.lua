local _, ns = ...
local DragDrop = ns.AuraTracker.DragDrop
local Config = ns.AuraTracker.Config
local GetSpellLink = GetSpellLink
local GetSpellInfo = GetSpellInfo
local GetPetActionInfo = GetPetActionInfo
local GetMouseFocus = GetMouseFocus
local UnitAura = UnitAura
local IsShiftKeyDown = IsShiftKeyDown
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame
local pairs = pairs
local _G = _G

-- ==========================================================
-- PET ACTION BAR HOOKS (drag from pet action bar)
-- ==========================================================

-- Called when a pet action spell is dropped on a drop zone.
-- Uses self.draggedPetSpell captured at drag-start rather than querying
-- GetPetActionInfo() at drop time (which would return nil because
-- PickupPetAction already cleared the slot).
function DragDrop:HandlePetSpellDrop(barKey)
    if not self.draggedPetSpell then return end
    local spellId = self.draggedPetSpell.id
    local name    = self.draggedPetSpell.name
    self.draggedPetSpell = nil  -- clear early to prevent duplicate handling if OnDragStop fires after OnReceiveDrag

    local controller = self.controller
    local success, result = controller:AddCooldown(barKey, spellId)
    if success then
        controller:Print("Now tracking |cff00ff00" .. result .. "|r cooldown")
    elseif result then
        controller:Print("Failed: " .. result)
    end
end

-- Hooks a single PetActionButton to mirror the buff-button drag pattern:
-- spell info is captured in OnMouseDown (before PickupPetAction clears the
-- slot), a floating icon follows the cursor, drop zones are shown, and the
-- tracked spell is delivered via the OnDragStop + GetMouseFocus() path.
-- HookScript is used so the button's secure PickupPetAction handler is
-- preserved without taint.
function DragDrop:HookPetActionButton(button, index)
    if not button or button._auraTrackerPetHooked then return end
    button._auraTrackerPetHooked = true

    -- Pre-capture spell info before PickupPetAction clears the slot.
    button:HookScript("OnMouseDown", function(_, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        local name, _, texture, isToken = GetPetActionInfo(index)
        if name and not isToken then
            self._pendingPetSpell = { name = name, texture = texture }
        else
            self._pendingPetSpell = nil
        end
    end)

    -- Drag confirmed: resolve spell link and store for drop handling.
    button:HookScript("OnDragStart", function()
        local pending = self._pendingPetSpell
        self._pendingPetSpell = nil
        if not pending then return end

        local spellLink = GetSpellLink(pending.name)
        local spellId = spellLink and tonumber(spellLink:match("spell:(%d+)"))
        if not spellId then return end

        self.draggedPetSpell = { name = pending.name, id = spellId }
        self:ShowDropZones()

        if pending.texture then
            local dragFrame = self:GetDragFrame()
            dragFrame.texture:SetTexture(pending.texture)
            dragFrame:Show()
        end
    end)

    button:HookScript("OnDragStop", function()
        if self.draggedPetSpell then
            local focus = GetMouseFocus()
            if self.dropZones then
                for bk, dropZone in pairs(self.dropZones) do
                    if focus == dropZone then
                        self:HandlePetSpellDrop(bk)
                        break
                    end
                end
            end
        end
        -- Always clean up floating icon and drop zones on drag end.
        self:ClearDragState()
    end)
end

function DragDrop:HookPetActionButtons()
    for i = 1, 10 do
        local button = _G["PetActionButton" .. i]
        if button then
            self:HookPetActionButton(button, i)
        end
    end
end

-- ==========================================================
-- BUFF BUTTON HOOKS (aura drag from buff frame)
-- ==========================================================

local FILTER_KEY_MAP = {
    HELPFUL = "PLAYER_BUFF",
    HARMFUL = "PLAYER_DEBUFF",
}

-- Reverse lookup from Config.AuraFilter: "unit|filter" → filterKey
-- Supports all units (player, target, focus) so addon frames for any
-- unit type can be hooked automatically.
local UNIT_FILTER_TO_KEY = {}
for key, data in pairs(Config.AuraFilter) do
    UNIT_FILTER_TO_KEY[data.unit .. "|" .. data.filter] = key
end

function DragDrop:HookAuraButtonByName(buttonName, index, filter)
    local button = _G[buttonName .. index]
    if not button or button._auraTrackerHooked then return end

    local filterKey = FILTER_KEY_MAP[filter]
    if not filterKey then return end

    self:HookAuraButton(button, "player", filter, filterKey)
    button._auraTrackerHooked = true
end

function DragDrop:HookBuffButtons()
    for i = 1, 32 do
        self:HookAuraButtonByName("BuffButton", i, "HELPFUL")
    end
    for i = 1, 16 do
        self:HookAuraButtonByName("DebuffButton", i, "HARMFUL")
    end
end

-- Hook GameTooltip:SetUnitAura, SetUnitBuff, and SetUnitDebuff to detect
-- aura frames created by any addon (oUF, ElvUI, TukUI, etc.).
-- SetUnitBuff/SetUnitDebuff are used by oUF and many unit-frame addons for
-- target/focus aura tooltips, while SetUnitAura is the generic variant.
-- When a user hovers over an aura button that shows a UnitAura tooltip, we
-- apply our drag handlers so it can be dragged onto AuraTracker bars.
function DragDrop:HookTooltipAuraDetection()
    if self._tooltipHookRegistered then return end
    self._tooltipHookRegistered = true

    local function hookAuraFrame(unit, filter)
        local frame = GameTooltip:GetOwner()
        if not frame or frame._auraTrackerHooked then return end

        local filterKey = UNIT_FILTER_TO_KEY[unit .. "|" .. filter]
        if not filterKey then return end

        self:HookAuraButton(frame, unit, filter, filterKey)
        frame._auraTrackerHooked = true
    end

    hooksecurefunc(GameTooltip, "SetUnitAura", function(_, unit, index, filter)
        hookAuraFrame(unit, filter)
    end)

    hooksecurefunc(GameTooltip, "SetUnitBuff", function(_, unit)
        hookAuraFrame(unit, "HELPFUL")
    end)

    hooksecurefunc(GameTooltip, "SetUnitDebuff", function(_, unit)
        hookAuraFrame(unit, "HARMFUL")
    end)
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

-- ==========================================================
-- TEMP ENCHANT BUTTON HOOKS (drag from weapon enchant frames)
-- ==========================================================

-- Maps TempEnchant button index to weapon slot name.
-- TempEnchant1 corresponds to the main-hand slot (inventory slot 16).
-- TempEnchant2 corresponds to the off-hand slot (inventory slot 17).
local TEMP_ENCHANT_SLOTS = { "mainhand", "offhand" }

function DragDrop:HookTempEnchantButton(button, slot)
    if not button or button._auraTrackerTempEnchantHooked then return end
    button._auraTrackerTempEnchantHooked = true

    button:RegisterForDrag("LeftButton")

    local oldDragStart = button:GetScript("OnDragStart")
    local oldDragStop  = button:GetScript("OnDragStop")

    button:SetScript("OnDragStart", function(b)
        self.draggedEnchantSlot = slot
        self:ShowDropZones()

        -- Show a floating icon following the cursor
        local icon
        local t = b:GetNormalTexture()
        if t then icon = t:GetTexture() end
        if not icon then
            -- Fallback: try the named icon child (e.g. "TempEnchant1Icon")
            local bName = b:GetName()
            local child = bName and _G[bName .. "Icon"]
            if child then icon = child:GetTexture() end
        end
        if icon then
            local dragFrame = self:GetDragFrame()
            dragFrame.texture:SetTexture(icon)
            dragFrame:Show()
        end

        if oldDragStart then oldDragStart(b) end
    end)

    button:SetScript("OnDragStop", function(b)
        if self.draggedEnchantSlot then
            local focus = GetMouseFocus()
            if self.dropZones then
                for bk, dropZone in pairs(self.dropZones) do
                    if focus == dropZone then
                        self:HandleEnchantSlotDrop(bk)
                        break
                    end
                end
            end
            self:ClearDragState()
        end

        if oldDragStop then oldDragStop(b) end
    end)
end

function DragDrop:HandleEnchantSlotDrop(barKey)
    if not self.draggedEnchantSlot then return end
    local controller = self.controller
    local slot = self.draggedEnchantSlot
    local success, msg = controller:AddWeaponEnchantBySlot(barKey, slot)
    if success then
        local label = (slot == "offhand") and "Offhand" or "Mainhand"
        controller:Print("Now tracking |cff00ff00" .. label .. " Enchant|r (weapon enchant)")
    elseif msg then
        controller:Print("Failed: " .. msg)
    end
end

function DragDrop:HookTempEnchantButtons()
    -- Default Blizzard UI: TempEnchant1 (main-hand), TempEnchant2 (off-hand)
    for i = 1, 2 do
        local button = _G["TempEnchant" .. i]
        if button then
            self:HookTempEnchantButton(button, TEMP_ENCHANT_SLOTS[i])
        end
    end

    -- ElvUI: ElvuiPlayerBuffsTempEnchant1 (main-hand), ElvuiPlayerBuffsTempEnchant2 (off-hand)
    for i = 1, 2 do
        local button = _G["ElvuiPlayerBuffsTempEnchant" .. i]
        if button then
            self:HookTempEnchantButton(button, TEMP_ENCHANT_SLOTS[i])
        end
    end

    -- Tooltip hook to catch any other addon's temp enchant buttons lazily.
    -- When a button showing a weapon-slot inventory tooltip (slot 16/17) is
    -- hovered and its frame name contains "TempEnchant", we hook it then.
    self:HookTempEnchantByTooltip()
end

function DragDrop:HookTempEnchantByTooltip()
    if self._tempEnchantTooltipHookRegistered then return end
    self._tempEnchantTooltipHookRegistered = true

    local WEAPON_INVENTORY_SLOTS = { [16] = "mainhand", [17] = "offhand" }

    hooksecurefunc(GameTooltip, "SetInventoryItem", function(_, unit, invSlot)
        if unit ~= "player" then return end
        local weaponSlot = WEAPON_INVENTORY_SLOTS[invSlot]
        if not weaponSlot then return end

        local frame = GameTooltip:GetOwner()
        if not frame or frame._auraTrackerTempEnchantHooked then return end

        -- Only hook frames whose name identifies them as temp enchant buttons.
        local frameName = frame:GetName()
        if frameName and frameName:find("TempEnchant") then
            self:HookTempEnchantButton(frame, weaponSlot)
        end
    end)
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
