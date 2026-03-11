local addonName, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local DragDrop = ns.AuraTracker.DragDrop
local UpdateEngine = ns.AuraTracker.UpdateEngine
local SnapshotTracker = ns.AuraTracker.SnapshotTracker
local Icon = ns.AuraTracker.Icon

-- Localize frequently-used globals
local pairs = pairs
local UnitGUID = UnitGUID
local GetTime = GetTime
local string_lower = string.lower
local strtrim = strtrim

-- Library references
local LibFramePool = LibStub("LibFramePool-1.0")
local LibEditmode  = LibStub("LibEditmode-1.0")

-- Create module via Ace3
local AuraTracker = LibStub("AceAddon-3.0"):NewAddon("AuraTracker", "AceEvent-3.0", "AceConsole-3.0")
ns.AuraTracker.Controller = AuraTracker

local playerGUID = nil

-- ==========================================================
-- LIFECYCLE
-- ==========================================================

function AuraTracker:OnInitialize()
    local defaults = {
        profile = {
            enabled = true,
            bars = {},
            customMappings = {},
        }
    }
    self.db = LibStub("AceDB-3.0"):New("SimpleAuraTrackerDB", defaults, true)

    self.bars = {}
    self.items = {}
    
    playerGUID = UnitGUID("player")
    
    LibFramePool:CreatePool(Icon.POOL_KEY, Icon.CreateFrame)

    -- Register configuration options with AceConfig
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, function()
        local options = ns.GetAuraTrackerOptions()
        ns.UpdateBarOptions(options)
        return options
    end)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, "Aura Tracker")

    -- Register slash commands
    self:RegisterChatCommand("auratracker", "OnSlashCommand")
    self:RegisterChatCommand("at", "OnSlashCommand")
end

function AuraTracker:OnEnable()
    local db = self:GetDB()
    if not db or not db.enabled then
        self:Disable()
        return
    end

    if not next(db.bars) then
        self:CreateBar("auratracker")
    end

    -- Initialize extracted modules
    DragDrop:Init(self, function(barKey)
        local SP = ns.AuraTracker.SettingsPanel
        if SP then SP:Show(barKey) end
    end)
    UpdateEngine:Init(self)
    SnapshotTracker:Init(self)

    self:RebuildAllBars()
    UpdateEngine:CreateUpdateFrame()
    self:RegisterEvent("CHARACTER_POINTS_CHANGED", "OnTalentsChanged")
    self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnTalentsChanged")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnSpellUpdateCooldown")
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("SPELLS_CHANGED", "OnSpellsChanged")
    self:RegisterEvent("ACTIONBAR_SHOWGRID", "OnDragStart")
    self:RegisterEvent("ACTIONBAR_HIDEGRID", "OnDragEnd")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCLEU")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnEquipmentChanged")
    self:RegisterEvent("PLAYER_TOTEM_UPDATE", "OnTotemUpdate")

    DragDrop:HookBuffButtons()
    hooksecurefunc("AuraButton_Update", function(buttonName, index, filter)
        DragDrop:HookAuraButtonByName(buttonName, index, filter)
    end)
    DragDrop:HookTooltipAuraDetection()
    DragDrop:HookTempEnchantButtons()

end

function AuraTracker:OnDisable()
    DragDrop:HideDropZones()
    self:DestroyAllBars()
    UpdateEngine:StopUpdateFrame()
    self:UnregisterAllEvents()
end

-- ==========================================================
-- DATABASE ACCESS
-- ==========================================================

function AuraTracker:GetAllBars()
    return self.bars
end

function AuraTracker:GetDB()
    return self.db.profile
end

function AuraTracker:GetBarDB(barKey)
    local db = self:GetDB()
    return db and db.bars and db.bars[barKey]
end

function AuraTracker:GetBars()
    local db = self:GetDB()
    return db and db.bars
end

-- ==========================================================
-- EVENT HANDLERS
-- ==========================================================

function AuraTracker:OnTalentsChanged()
    self:InvalidateBarStaticCache()
    self:RebuildAllBars()
end

function AuraTracker:OnSpellUpdateCooldown()
    UpdateEngine:UpdateGCDState()
end

function AuraTracker:OnCLEU(event, ...)
    SnapshotTracker:HandleCLEU(...)

    if self._procToItems and next(self._procToItems) then
        local _, subEvent, _, _, _, destGUID, _, _, spellId = ...
        if destGUID == playerGUID
        and (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH") then
            local trackedItems = self._procToItems[spellId]
            if trackedItems then
                local now = GetTime()
                for trackedItem in pairs(trackedItems) do
                    trackedItem:OnProcDetected(spellId, now)
                end
            end
        end
    end
end

function AuraTracker:OnUnitAura(event, unit)
    if unit == "player" or unit == "target" or unit == "focus" then
        UpdateEngine:UpdateAurasForUnit(unit)
    end
    -- Snapshots are only affected by player buffs and target debuffs;
    -- skip the full bar traversal for unrelated units (e.g. focus, party).
    if unit == "player" or unit == "target" then
        SnapshotTracker:InvalidateCache()
        UpdateEngine:UpdateSnapshotText()
    end
end

function AuraTracker:OnTargetChanged()
    UpdateEngine:UpdateAurasForUnit("target")
    SnapshotTracker:InvalidateCache()
    UpdateEngine:UpdateSnapshotText()
end

function AuraTracker:OnPlayerEnteringWorld()
    playerGUID = UnitGUID("player")
    SnapshotTracker:ResetPlayerInfo()
    self:InvalidateBarStaticCache()
    self:RebuildAllBars()
end

function AuraTracker:OnSpellsChanged()
    self:RebuildAllBars()
end

function AuraTracker:OnDragStart()
    DragDrop:OnDragStart()
end

function AuraTracker:OnDragEnd()
    DragDrop:OnDragEnd()
end

function AuraTracker:OnTotemUpdate()
    UpdateEngine:UpdateAllCooldowns()
end

-- ==========================================================
-- UTILITY
-- ==========================================================

function AuraTracker:Print(message)
    print("|cff00bfffAuraTracker:|r " .. message)
end

-- ==========================================================
-- EDIT MODE INTEGRATION
-- ==========================================================

function AuraTracker:OnSlashCommand(input)
    local cmd = strtrim(string_lower(input or ""))

    if cmd == "editmode" or cmd == "move" then
        LibEditmode:ToggleEditMode("AuraTracker")
        if LibEditmode:IsEditModeActive("AuraTracker") then
            self:Print("Edit mode |cFF00FF00enabled|r. Drag bars to reposition them. Type /at editmode again to exit.")
        else
            self:Print("Edit mode |cFFFF4444disabled|r.")
        end
        return
    end

    local SP = ns.AuraTracker.SettingsPanel
    if SP then SP:Show() end
end