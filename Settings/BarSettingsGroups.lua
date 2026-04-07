local addonName, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

-- Per-section group builders for CreateBarSettings (BarSettingsUI.lua).
-- Sections requiring closures over barKey/barData receive them as parameters.

local SU  = ns.AuraTracker.SettingsUtils
local LSM = LibStub("LibSharedMedia-3.0")
local L   = SU.L
local math_floor = math.floor
local tostring, tonumber = tostring, tonumber
local next = next

local DEFAULT_TEXT_COLOR = { r = 1, g = 1, b = 1, a = 1 }

local G = {}
ns.AuraTracker._BarSettingsGroups = G

-- ============================================================
-- BuildBarLoadArgs
-- ============================================================
--- Build the args table used for the Load sub-tab.
--- @param barKey   string   Bar identifier key
--- @param barData  table    Bar DB entry
--- @param hideFn   function Returns true when talent rows should be hidden
--- @param notifyAndRebuildFn  function  Called after class/talent changes
--- @param rebuildFn           function  Called after talent-rank changes
--- @param buildTalentListFn   function  Returns the talent name→label map
function G.BuildBarLoadArgs(barKey, barData, hideFn, notifyAndRebuildFn, rebuildFn, buildTalentListFn)
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
                notifyAndRebuildFn(barKey)
            end,
        },
        talentRequirementsDesc = {
            type  = "description",
            name  = "|cFFFFFF00Click|r = Required (yellow)   |cFFFFFF00Click again|r = Excluded (red)   |cFFFFFF00Click again|r = Any (gray)",
            order = 3,
            width = "full",
            hidden = hideFn,
        },
        talentRequirements = {
            type          = "multiselect",
            dialogControl = "AuraTrackerMiniTalent",
            name          = "Required Talents",
            order         = 4,
            width         = "full",
            hidden        = hideFn,
            values        = function() return buildTalentListFn() end,
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
                if not next(barData.talentRequirements) then
                    barData.talentRequirements = nil
                end
                rebuildFn(barKey)
            end,
        },
    }

    local Conditionals = ns.AuraTracker and ns.AuraTracker.Conditionals
    if Conditionals then
        Conditionals:BuildLoadConditionUI(
            loadArgs, barData, 10, barKey, notifyAndRebuildFn, "bar"
        )
    end

    return loadArgs
end

-- ============================================================
-- BuildBarGeneralArgs
-- ============================================================
--- Build the args table for the General sub-tab (settings, position, danger zone).
--- @param barKey              string
--- @param barData             table
--- @param notifyFn            function  () → void
--- @param rebuildFn           function  (barKey) → void
--- @param notifyAndRebuildFn  function  (barKey) → void
function G.BuildBarGeneralArgs(barKey, barData, notifyFn, rebuildFn, notifyAndRebuildFn)
    return {
        name = {
            type  = "input",
            name  = "Bar Name",
            desc  = "Display name shown on the edit-mode mover.",
            order = 1,
            width = "full",
            get   = function() return barData.name end,
            set   = function(_, val)
                barData.name = val
                notifyFn()
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
                notifyAndRebuildFn(barKey)
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
                notifyAndRebuildFn(barKey)
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
                notifyAndRebuildFn(barKey)
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
                rebuildFn(barKey)
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
                rebuildFn(barKey)
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
                rebuildFn(barKey)
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
                rebuildFn(barKey)
            end,
        },
        textSize = {
            type     = "input",
            name     = "Font Size",
            desc     = "Font size for cooldown timer text (8-20).",
            order    = 32,
            width    = "double",
            get      = function() return tostring(barData.textSize or 12) end,
            set      = function(_, val)
                local n = tonumber(val)
                if n then
                    barData.textSize = math_floor(math.max(8, math.min(20, n)))
                    rebuildFn(barKey)
                end
            end,
            validate = function(_, val)
                if not tonumber(val) then return "Please enter a number (8-20)." end
                return true
            end,
        },
        snapshotTextSize = {
            type     = "input",
            name     = "Snapshot Font Size",
            desc     = "Font size for snapshot diff text (8-20). Defaults to 80% of Font Size when unset.",
            order    = 33,
            width    = "double",
            get      = function()
                return tostring(barData.snapshotTextSize or math_floor((barData.textSize or 12) * 0.8))
            end,
            set      = function(_, val)
                local n = tonumber(val)
                if n then
                    barData.snapshotTextSize = math_floor(math.max(8, math.min(20, n)))
                    rebuildFn(barKey)
                end
            end,
            validate = function(_, val)
                if not tonumber(val) then return "Please enter a number (8-20)." end
                return true
            end,
        },
        showSnapshotBG = {
            type  = "toggle",
            name  = "Show Snapshot Background",
            desc  = "Show a black background box behind snapshot diff text.",
            order = 34,
            width = "full",
            get   = function() return barData.showSnapshotBG ~= false end,
            set   = function(_, val)
                barData.showSnapshotBG = val
                rebuildFn(barKey)
            end,
        },
        snapshotBGAlpha = {
            type     = "range",
            name     = "Snapshot Background Opacity",
            desc     = "Opacity of the black background behind snapshot diff text.",
            min      = 0.0, max = 1.0, step = 0.05,
            order    = 35,
            width    = "double",
            disabled = function() return barData.showSnapshotBG == false end,
            get      = function() return barData.snapshotBGAlpha or 1.0 end,
            set      = function(_, val)
                barData.snapshotBGAlpha = val
                rebuildFn(barKey)
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
            order    = 36,
            width    = "double",
            get      = function() return barData.fontOutline or "THICKOUTLINE" end,
            set      = function(_, val)
                barData.fontOutline = val
                rebuildFn(barKey)
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
            order  = 37,
            width  = "double",
            get    = function()
                return barData.font or "Friz Quadrata TT"
            end,
            set    = function(_, val)
                barData.font = val
                rebuildFn(barKey)
            end,
        },
        textColor = {
            type     = "color",
            name     = "Text Color",
            hasAlpha = true,
            order    = 38,
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
                rebuildFn(barKey)
            end,
        },

        posHeader = { type = "header", name = "Position & Anchoring", order = 40 },
        anchorFrame = {
            type  = "input",
            name  = "Anchor Frame",
            desc  = "Name of the WoW frame to anchor this bar to (e.g. PlayerFrame, TargetFrame, AuraTracker_Bar_MyBar). Leave blank to anchor to the screen.",
            order = 41,
            width = "double",
            get   = function() return barData.anchorFrame or "" end,
            set   = function(_, val)
                val = val and val:match("^%s*(.-)%s*$") or ""
                if val == "" then
                    barData.anchorFrame = nil
                else
                    barData.anchorFrame = val
                end
                rebuildFn(barKey)
            end,
        },
        pickAnchorFrame = {
            type  = "execute",
            name  = "Pick Frame",
            desc  = "Click to enter frame-picking mode. Hover over any visible game frame and left-click to use it as the anchor. Right-click or press Escape to cancel.",
            order = 41.5,
            func  = function()
                local FP = ns.AuraTracker.FramePicker
                FP:Start(function(frameName)
                    barData.anchorFrame = frameName
                    rebuildFn(barKey)
                    notifyFn()
                end)
            end,
        },
        anchorPoint = {
            type   = "select",
            name   = "Anchor To Point",
            desc   = "Which point on the anchor frame this bar attaches to. Only used when Anchor Frame is set.",
            order  = 42,
            width  = "double",
            values = {
                CENTER      = "Center",
                TOP         = "Top",
                BOTTOM      = "Bottom",
                LEFT        = "Left",
                RIGHT       = "Right",
                TOPLEFT     = "Top Left",
                TOPRIGHT    = "Top Right",
                BOTTOMLEFT  = "Bottom Left",
                BOTTOMRIGHT = "Bottom Right",
            },
            disabled = function() return not barData.anchorFrame or barData.anchorFrame == "" end,
            get      = function() return barData.anchorPoint or "CENTER" end,
            set      = function(_, val)
                barData.anchorPoint = val
                rebuildFn(barKey)
            end,
        },
        snapSizeHeader = { type = "header", name = "Edit Mode Dragging", order = 45 },
        snapSize = {
            type  = "range",
            name  = "Snap Size",
            desc  = "Grid snap size when dragging bars in edit mode. Set to 0 to disable snapping.",
            min   = 0, max = 128, step = 1,
            order = 46,
            width = "double",
            get   = function() return barData.snapSize or 32 end,
            set   = function(_, val)
                barData.snapSize = (val == 32) and nil or val
                local ctrl = ns.AuraTracker and ns.AuraTracker.Controller
                if ctrl then
                    local bar = ctrl.bars and ctrl.bars[barKey]
                    if bar and bar.mover then
                        bar.mover.snapSize = barData.snapSize
                    end
                end
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
                notifyFn()
            end,
        },

        exportHeader = { type = "header", name = "Share / Export", order = 110 },
        exportDesc = {
            type  = "description",
            name  = "Copy the string below to share this bar with other players or "
                .. "import it on another character via the |cFFFFFF00Import Bar|r panel.",
            order = 111,
            width = "full",
        },
        exportString = {
            type  = "input",
            name  = "Export String",
            desc  = "Select all and copy (Ctrl+A, Ctrl+C) to share this bar.",
            order = 112,
            width = "full",
            get   = function()
                local ctrl = ns.AuraTracker and ns.AuraTracker.Controller
                if ctrl then
                    local str = ctrl:ExportBar(barKey)
                    return str or ""
                end
                return ""
            end,
            set   = function() end,  -- read-only; no-op on Enter
        },
    }
end
