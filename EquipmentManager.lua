local _, ns = ...

local Config = ns.AuraTracker.Config

-- Localize frequently-used globals
local pairs, ipairs = pairs, ipairs
local GetInventoryItemID = GetInventoryItemID
local GetTime = GetTime

-- The addon object (created in AuraTracker.lua)
local AuraTracker = ns.AuraTracker.Controller

-- ==========================================================
-- EQUIPMENT SLOT CONSTANTS
-- ==========================================================

local TRINKET_SLOT1 = 13
local TRINKET_SLOT2 = 14
local RING_SLOT1    = 11
local RING_SLOT2    = 12

local ICD_EQUIP_SLOTS = { TRINKET_SLOT1, TRINKET_SLOT2, RING_SLOT1, RING_SLOT2 }
local TRINKET_SLOTS   = { [TRINKET_SLOT1] = true, [TRINKET_SLOT2] = true }

-- ==========================================================
-- LOCAL HELPERS
-- ==========================================================

--- Returns a set of item IDs currently equipped in trinket and ring slots.
local function GetEquippedICDItemIds()
    local ids = {}
    for _, slot in ipairs(ICD_EQUIP_SLOTS) do
        local id = GetInventoryItemID("player", slot)
        if id then ids[id] = true end
    end
    return ids
end

-- ==========================================================
-- PUBLIC API
-- ==========================================================

--- Returns a map of { [slot] = itemId } for trinket slots only.
--- Used by BarManager to snapshot trinket state on rebuild.
function AuraTracker:GetTrinketSlotMap()
    return {
        [TRINKET_SLOT1] = GetInventoryItemID("player", TRINKET_SLOT1),
        [TRINKET_SLOT2] = GetInventoryItemID("player", TRINKET_SLOT2),
    }
end

--- Syncs the equipped flag on all INTERNAL_CD tracked items across all bars.
function AuraTracker:SyncEquipState()
    local equippedIds = GetEquippedICDItemIds()

    for barKey, itemTable in pairs(self.items) do
        for key, item in pairs(itemTable) do
            if item:GetTrackType() == Config.TrackType.INTERNAL_CD then
                item:SetEquipped(equippedIds[item:GetId()])
            end
        end
    end
end

--- Finds the TrackedItem for a given item ID across all bars.
function AuraTracker:FindICDItem(itemId)
    for barKey, itemTable in pairs(self.items) do
        local item = itemTable["icd_" .. itemId]
        if item then return item end
    end
    return nil
end

function AuraTracker:OnEquipmentChanged(event, slot)
    local isTrinketSlot = TRINKET_SLOTS[slot]
    -- Only care about trinket and ring slots
    if not isTrinketSlot and slot ~= RING_SLOT1 and slot ~= RING_SLOT2 then return end

    -- For trinket slots, detect which item was swapped in and apply swap CD.
    -- Read prev state BEFORE updating the snapshot for this slot so that a
    -- two-slot swap (t1↔t2) correctly detects changes on both events.
    if isTrinketSlot then
        local prev = self._prevTrinketSlots or {}
        local currentId = GetInventoryItemID("player", slot)
        local prevId = prev[slot]

        -- Update only this slot in the snapshot so the other slot's
        -- event still compares against the original state.
        -- (assignment needed when prev was created via the `or {}` fallback)
        prev[slot] = currentId
        self._prevTrinketSlots = prev

        -- Sync equipped flags
        self:SyncEquipState()

        -- Apply swap CD if a different item is now in this trinket slot
        if currentId and currentId ~= prevId then
            local item = self:FindICDItem(currentId)
            if item then
                item:OnEquipSwap(GetTime())
            end
        end
    else
        -- Ring slot changed – just sync visibility, no swap CD
        self:SyncEquipState()
    end
end
