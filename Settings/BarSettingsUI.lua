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

    -- ==========================================================
    -- LOAD TAB ARGS: restrictions merged with load conditions
    -- ==========================================================

    local loadArgs = {
        loadTabDesc = {
            type  = "description",
            name  = "Configure when this bar should be visible.\n"
                .. "Class and talent restrictions are checked at login. "
                .. "Dynamic conditions are re-evaluated during play.\n"
                .. "|cFF00CC00Green|r = required   "
                .. "|cFFCC0000Red|r = excluded   "
                .. "Unchecked = ignored",
            order = 1,
            width = "full",
        },
        class = {
            type   = "select",
            name   = "Show for Class",
            desc   = "Only show this bar when playing the selected class.",
            values = L.CLASSES,
            order  = 2,
            width  = "double",
            get    = function() return barData.classRestriction or "NONE" end,
            set    = function(_, val)
                barData.classRestriction = val
                NotifyAndRebuild(barKey)
            end,
        },
        talentRequirementsDesc = {
            type  = "description",
            name  = "|cFFFFFF00Click|r = Required (yellow)   |cFFFFFF00Click again|r = Excluded (red)   |cFFFFFF00Click again|r = Any (gray)",
            order = 3,
            width = "full",
            hidden = HideTalentsForNonMatchingClass,
        },
        talentRequirements = {
            type          = "multiselect",
            dialogControl = "AuraTrackerMiniTalent",
            name          = "Required Talents",
            order         = 4,
            width         = "full",
            hidden        = HideTalentsForNonMatchingClass,
            values        = function() return BuildTalentList() end,
            get           = function(_, key)
                local reqs = barData.talentRequirements
                return reqs and reqs[key]
            end,
            set           = function(_, key, value)
                barData.talentRequirements = barData.talentRequirements or {}
                if value == nil then
                    barData.talentRequirements[key] = nil
                else
                    barData.talentRequirements[key] = value
                end
                -- Clean up empty table
                if not next(barData.talentRequirements) then
                    barData.talentRequirements = nil
                end
                -- Only rebuild the bar; avoid NotifyChange() which would
                -- recreate the widget and collapse its expanded view.
                RebuildBar(barKey)
            end,
        },
    }

    -- Inject bar-level load conditions into the Load tab args
    local Conditionals = ns.AuraTracker and ns.AuraTracker.Conditionals
    if Conditionals then
        Conditionals:BuildLoadConditionUI(
            loadArgs, barData, 10, barKey, NotifyAndRebuild, "bar"
        )
    end

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
                    args  = {
                        name = {
                            type  = "input",
                            name  = "Bar Name",
                            desc  = "Display name shown on the edit-mode mover.",
                            order = 1,
                            width = "full",
                            get   = function() return barData.name end,
                            set   = function(_, val)
                                barData.name = val
                                NotifyChange()
                            end,
                        },
                        direction = {
                            type   = "select",
                            name   = "Direction",
                            desc   = "Icon layout direction.",
                            values = L.DIRECTIONS,
                            order  = 2,
                            width  = "double",
                            get    = function() return barData.direction or "HORIZONTAL" end,
                            set    = function(_, val)
                                barData.direction = val
                                NotifyAndRebuild(barKey)
                            end,
                        },
                        ignoreGCD = {
                            type  = "toggle",
                            name  = "Ignore GCD",
                            desc  = "Treat the global cooldown as \"ready\" so icons don't flicker on every cast.",
                            order = 3,
                            width = "full",
                            get   = function() return barData.ignoreGCD ~= false end,
                            set   = function(_, val)
                                barData.ignoreGCD = val
                                NotifyAndRebuild(barKey)
                            end,
                        },
                        showOnlyKnown = {
                            type  = "toggle",
                            name  = "Show Only Known Spells",
                            desc  = "Only show icons for spells your character currently knows. Unknown spells are hidden automatically.",
                            order = 4,
                            width = "full",
                            get   = function() return barData.showOnlyKnown or false end,
                            set   = function(_, val)
                                barData.showOnlyKnown = val
                                NotifyAndRebuild(barKey)
                            end,
                        },

                        sizeHeader = { type = "header", name = "Size & Spacing", order = 20 },
                        iconSize = {
                            type     = "range",
                            name     = "Icon Size",
                            min      = 10, max = 100, step = 1,
                            order    = 21,
                            width    = "double",
                            get      = function() return barData.iconSize end,
                            set      = function(_, val)
                                barData.iconSize = val
                                RebuildBar(barKey)
                            end,
                        },
                        spacing = {
                            type     = "range",
                            name     = "Spacing",
                            min      = 0, max = 50, step = 1,
                            order    = 22,
                            width    = "double",
                            get      = function() return barData.spacing end,
                            set      = function(_, val)
                                barData.spacing = val
                                RebuildBar(barKey)
                            end,
                        },
                        scale = {
                            type     = "range",
                            name     = "Scale",
                            desc     = "Overall scale of the bar frame (does not affect saved position).",
                            min      = 0.25, max = 3.0, step = 0.05,
                            order    = 23,
                            width    = "double",
                            get      = function() return barData.scale or 1.0 end,
                            set      = function(_, val)
                                barData.scale = val
                                RebuildBar(barKey)
                            end,
                        },

                        textHeader = { type = "header", name = "Text", order = 30 },
                        showCooldownText = {
                            type  = "toggle",
                            name  = "Show Cooldown Timer",
                            desc  = "Show remaining cooldown time as text on the icon.",
                            order = 31,
                            width = "full",
                            get   = function() return barData.showCooldownText ~= false end,
                            set   = function(_, val)
                                barData.showCooldownText = val
                                RebuildBar(barKey)
                            end,
                        },
                        textSize = {
                            type     = "range",
                            name     = "Font Size",
                            min      = 8, max = 32, step = 1,
                            order    = 32,
                            width    = "double",
                            get      = function() return barData.textSize or 12 end,
                            set      = function(_, val)
                                barData.textSize = val
                                RebuildBar(barKey)
                            end,
                        },
                        fontOutline = {
                            type     = "select",
                            name     = "Font Outline",
                            desc     = "Outline style for text on icons.",
                            values   = {
                                ["NONE"]          = "None",
                                ["OUTLINE"]       = "Thin",
                                ["THICKOUTLINE"]  = "Thick",
                            },
                            order    = 33,
                            width    = "double",
                            get      = function() return barData.fontOutline or "THICKOUTLINE" end,
                            set      = function(_, val)
                                barData.fontOutline = val
                                RebuildBar(barKey)
                            end,
                        },
                        font = {
                            type   = "select",
                            name   = "Font",
                            desc   = "Font used for cooldown and countdown texts on icons.",
                            values = function()
                                local fonts = LSM:List("font")
                                local t = {}
                                for _, name in ipairs(fonts) do
                                    t[name] = name
                                end
                                return t
                            end,
                            order  = 34,
                            width  = "double",
                            get    = function()
                                return barData.font or "Friz Quadrata TT"
                            end,
                            set    = function(_, val)
                                barData.font = val
                                RebuildBar(barKey)
                            end,
                        },
                        textColor = {
                            type     = "color",
                            name     = "Text Color",
                            hasAlpha = true,
                            order    = 35,
                            width    = "normal",
                            get      = function()
                                local c = barData.textColor or DEFAULT_TEXT_COLOR
                                return c.r, c.g, c.b, c.a
                            end,
                            set      = function(_, r, g, b, a)
                                barData.textColor = barData.textColor or {}
                                barData.textColor.r = r
                                barData.textColor.g = g
                                barData.textColor.b = b
                                barData.textColor.a = a
                                RebuildBar(barKey)
                            end,
                        },

                        dangerHeader = { type = "header", name = "Danger Zone", order = 100 },
                        deleteBar = {
                            type        = "execute",
                            name        = "Delete Bar",
                            desc        = "Permanently removes this bar and all its tracked icons.",
                            order       = 101,
                            confirm     = true,
                            confirmText = "Delete bar \"" .. (barData.name or barKey) .. "\" and all its icons?",
                            func        = function()
                                local ctrl = ns.AuraTracker and ns.AuraTracker.Controller
                                if ctrl then
                                    ctrl:DeleteBar(barKey)
                                end
                                local editSt = SU.editState
                                if editSt.selectedBar == barKey then
                                    editSt.selectedBar  = nil
                                    editSt.selectedAura = nil
                                end
                                NotifyChange()
                            end,
                        },
                    },
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
