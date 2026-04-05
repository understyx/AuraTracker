local _, ns = ...

local Config = ns.AuraTracker.Config
local TrackedItem = ns.AuraTracker.TrackedItem
local AuraTracker = ns.AuraTracker.Controller
local LibFramePool = LibStub("LibFramePool-1.0")

local GetSpellInfo, GetItemInfo = GetSpellInfo, GetItemInfo

local _IFH = ns.AuraTracker._ItemFactoryHelpers
local GetNextOrder = function(...) return _IFH.GetNextOrder(...) end
local CreateAndRegisterIcon = function(...) return _IFH.CreateAndRegisterIcon(...) end

-- ==========================================================
-- WEAPON ENCHANT
-- ==========================================================

function AuraTracker:CreateWeaponEnchantIcon(barKey, itemId, slot, order, styleOptions, displayMode, expectedEnchant)
    local bar = self.bars[barKey]
    local db = self:GetBarDB(barKey)
    if not bar or not db then return nil end

    local item = TrackedItem:New(itemId, Config.TrackType.WEAPON_ENCHANT, {
        slot           = slot,
        expectedEnchant = expectedEnchant,
    })
    if not item:GetName() then return nil end

    local resolvedMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.WEAPON_ENCHANT)
    local icon = CreateAndRegisterIcon(bar, item, order, styleOptions, resolvedMode)
    self.items[barKey]["wenchant_" .. itemId] = item
    return icon
end

function AuraTracker:AddWeaponEnchant(barKey, itemId, slot)
    local db = self:GetBarDB(barKey)
    if not db then return false, "Bar not found" end

    local name = GetItemInfo(itemId)
    if not name then return false, "Item not found" end

    db.trackedItems = db.trackedItems or {}
    if db.trackedItems[itemId] then return false, "Already tracked" end

    db.trackedItems[itemId] = {
        order           = GetNextOrder(db.trackedItems),
        trackType       = Config.TrackType.WEAPON_ENCHANT,
        slot            = slot or "mainhand",
        displayMode     = Config.DisplayMode.ALWAYS,
        expectedEnchant = Config:GetWeaponEnchantChoiceForItem(itemId),
    }
    self:RebuildBar(barKey)

    return true, name
end

function AuraTracker:AddWeaponEnchantBySlot(barKey, slot)
    local db = self:GetBarDB(barKey)
    if not db then return false, "Bar not found" end

    slot = slot or "mainhand"
    local id = (slot == "offhand") and Config.OFFHAND_ENCHANT_SLOT_ID or Config.MAINHAND_ENCHANT_SLOT_ID

    local label = (slot == "offhand") and "Offhand Enchant" or "Mainhand Enchant"

    db.trackedItems = db.trackedItems or {}
    if db.trackedItems[id] then return false, label .. " already tracked" end

    db.trackedItems[id] = {
        order = GetNextOrder(db.trackedItems),
        trackType = Config.TrackType.WEAPON_ENCHANT,
        slot = slot,
        displayMode = Config.DisplayMode.ALWAYS,
    }
    self:RebuildBar(barKey)

    return true, label
end

-- ==========================================================
-- TOTEM
-- ==========================================================

function AuraTracker:CreateTotemIcon(barKey, totemId, spellId, order, styleOptions, displayMode)
    local bar = self.bars[barKey]
    local db = self:GetBarDB(barKey)
    if not bar or not db then return nil end

    local totemSlot = Config:GetTotemSlot(totemId)
    if not totemSlot then return nil end

    local item = TrackedItem:New(totemId, Config.TrackType.TOTEM, {
        totemSlot = totemSlot,
        spellId   = spellId,
    })
    if not item:GetName() then return nil end

    local resolvedMode = displayMode or Config:GetDefaultDisplayMode(Config.TrackType.TOTEM)
    local icon = CreateAndRegisterIcon(bar, item, order, styleOptions, resolvedMode)
    self.items[barKey]["totem_" .. totemId] = item
    return icon
end

function AuraTracker:AddTotem(barKey, spellId)
    local db = self:GetBarDB(barKey)
    if not db then return false, "Bar not found" end

    local totemId = Config:GetTotemIdForSpell(spellId)
    if not totemId then return false, "Not a known totem spell" end

    local elementName = Config:GetTotemElementName(totemId)

    db.trackedItems = db.trackedItems or {}
    if db.trackedItems[totemId] then return false, elementName .. " already tracked" end

    local spellName = GetSpellInfo(spellId)

    db.trackedItems[totemId] = {
        order       = GetNextOrder(db.trackedItems),
        trackType   = Config.TrackType.TOTEM,
        totemSlot   = Config:GetTotemSlot(totemId),
        spellId     = spellId,
        displayMode = Config.DisplayMode.ALWAYS,
    }
    self:RebuildBar(barKey)

    return true, spellName or elementName
end
