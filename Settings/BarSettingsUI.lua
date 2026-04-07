local _, ns = ...

-- ==========================================================
-- SHARED REFERENCES (from Settings.lua)
-- ==========================================================

local SU = ns.AuraTracker.SettingsUtils
local LSM = LibStub("LibSharedMedia-3.0")

local pairs = pairs
local string_format = string.format
local math_floor = math.floor
local next = next
local UnitClass = UnitClass

-- Import shared utilities
local L = SU.L

-- ==========================================================
-- LOCAL HELPERS
-- ==========================================================

local function RebuildBar(barKey)
    SU.RebuildBar(barKey)
end

local function NotifyChange()
    SU.NotifyChange()
end

local function NotifyAndRebuild(barKey)
    SU.NotifyAndRebuild(barKey)
end

local function BuildTalentList()
    return SU.BuildTalentList()
end

local DEFAULT_TEXT_COLOR = { r = 1, g = 1, b = 1, a = 1 }

-- ==========================================================
-- BAR SETTINGS
-- ==========================================================

local function CreateBarSettings(barKey, barData)
    local function HideTalentsForNonMatchingClass()
        local cr = barData.classRestriction
        if not cr or cr == "NONE" then return true end
        local _, playerClass = UnitClass("player")
        return cr ~= playerClass
    end

    -- Resolve CreateIconListOptions at runtime (it's defined in IconEditorUI.lua)
    local CreateIconListOptions = ns.AuraTracker.CreateIconListOptions
    local G = ns.AuraTracker._BarSettingsGroups

    local loadArgs = G.BuildBarLoadArgs(
        barKey, barData, HideTalentsForNonMatchingClass,
        NotifyAndRebuild, RebuildBar, BuildTalentList
    )

    -- ==========================================================
    -- RESULT: Bar Configuration (tabbed) + Icons
    -- ==========================================================

    return {
        -- ======================================================
        -- TAB 1: Bar Configuration  →  sub-tabs: General / Load
        -- ======================================================
        barConfig = {
            type        = "group",
            name        = "Bar Configuration",
            order       = 1,
            childGroups = "tab",
            args        = {
                -- ------ General sub-tab ------
                general = {
                    type  = "group",
                    name  = "General",
                    order = 1,
                    args  = G.BuildBarGeneralArgs(barKey, barData, NotifyChange, RebuildBar, NotifyAndRebuild),
                },

                -- ------ Load sub-tab ------
                load = {
                    type  = "group",
                    name  = "Load",
                    order = 2,
                    args  = loadArgs,
                },
            },
        },

        -- ======================================================
        -- TAB 2: Icons
        -- ======================================================
        icons = CreateIconListOptions(barKey, barData),
    }
end

-- Export for use by Settings.lua (UpdateBarOptions)
ns.AuraTracker.CreateBarSettings = CreateBarSettings
