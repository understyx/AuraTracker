local addonName, ns = ...

local SU = ns.AuraTracker.SettingsUtils
local L = SU.L
local editState = SU.editState
local pairs, ipairs, next = pairs, ipairs, next
local tonumber, tostring = tonumber, tostring
local table_insert, table_sort, table_remove = table.insert, table.sort, table.remove
local math_max, math_min, math_floor = math.max, math.min, math.floor
local string_format, string_upper = string.format, string.upper
local GetSpellInfo, GetItemInfo = GetSpellInfo, GetItemInfo

local LibEditmode = LibStub("LibEditmode-1.0", true)

local function NotifyChange() SU.NotifyChange() end
local function NotifyAndRebuild(barKey) SU.NotifyAndRebuild(barKey) end
local function RebuildBar(barKey) SU.RebuildBar(barKey) end
local function GetClassGroupKey(cr) return SU.GetClassGroupKey(cr) end
local function GetClassGroupName(ck) return SU.GetClassGroupName(ck) end
local function GetBarDisplayName(barKey, barData) return SU.GetBarDisplayName(barKey, barData) end
local function GetSpellNameByID(spellId) return SU.GetSpellNameByID(spellId) end
local function GetItemNameByID(itemId) return SU.GetItemNameByID(itemId) end
local function GetTrackedNameAndIcon(id, trackType) return SU.GetTrackedNameAndIcon(id, trackType) end
local function GetTrackTypeLabel(trackType, filterKey) return SU.GetTrackTypeLabel(trackType, filterKey) end
local function GetFilterData(filterKey) return SU.GetFilterData(filterKey) end
local function BuildTalentList() return SU.BuildTalentList() end

-- ==========================================================
-- MAIN OPTIONS  &  BAR INJECTION
-- ==========================================================

function ns.RefreshOptions()
    NotifyChange()
end

-- ==========================================================
-- SETTINGS PANEL SHIM
-- ==========================================================
-- Delegates to the WeakAuras-style MainFrame when available,
-- with a fallback to the legacy AceConfigDialog window.

local AceConfigDialog = LibStub("AceConfigDialog-3.0")

ns.AuraTracker = ns.AuraTracker or {}
ns.AuraTracker.SettingsPanel = {
    Show = function(self, barKey)
        -- Prefer the new custom two-panel frame
        local mf = ns.AuraTracker.MainFrame
        if mf then
            mf:Open(barKey)
            return
        end
        -- Fallback: legacy AceConfigDialog standalone window
        AceConfigDialog:SetDefaultSize(addonName, 900, 650)
        do
            local rootStatus = AceConfigDialog:GetStatusTable(addonName)
            rootStatus.groups = rootStatus.groups or {}
            rootStatus.groups.groups = rootStatus.groups.groups or {}
            local tg = rootStatus.groups.groups
            tg["bars"] = true
            tg["bars\001class_NONE"] = true
            local _, playerClass = UnitClass("player")
            if playerClass then
                tg["bars\001class_" .. playerClass] = true
            end
        end
        AceConfigDialog:Open(addonName)
        local f = AceConfigDialog.OpenFrames and AceConfigDialog.OpenFrames[addonName]
        if f and f.frame then
            f.frame:SetMinResize(750, 550)
        end
        if barKey then
            local classGroupKey = "class_NONE"
            local found = false
            if ns.AuraTracker and ns.AuraTracker.Controller then
                local allBars = ns.AuraTracker.Controller:GetBars()
                local barData = allBars and allBars[barKey]
                if barData then
                    classGroupKey = "class_" .. GetClassGroupKey(barData.classRestriction)
                    found = true
                end
            end
            if found then
                AceConfigDialog:SelectGroup(addonName, "bars", classGroupKey, barKey)
            else
                AceConfigDialog:SelectGroup(addonName, "bars")
            end
        else
            AceConfigDialog:SelectGroup(addonName, "bars")
        end
    end,

    Hide = function(self)
        local mf = ns.AuraTracker.MainFrame
        if mf then
            mf:Close()
            return
        end
        local frame = AceConfigDialog.OpenFrames and AceConfigDialog.OpenFrames[addonName]
        if frame then frame:Hide() end
    end,

    CheckTalentRestriction = function(self, talentName)
        if not talentName or talentName == "" or talentName == "NONE" then
            return true
        end
        local numTabs = GetNumTalentTabs()
        if numTabs == 0 then
            return true
        end
        for tab = 1, numTabs do
            for i = 1, GetNumTalents(tab) do
                local name, _, _, _, rank = GetTalentInfo(tab, i)
                if name == talentName and rank and rank > 0 then
                    return true
                end
            end
        end
        return false
    end,
}
