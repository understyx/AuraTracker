local _, ns = ...

-- ==========================================================
-- SHARED REFERENCES (from Settings.lua)
-- ==========================================================
-- Settings.lua exports shared utilities to ns.AuraTracker.SettingsUtils
-- which this file accesses at load time.

local SU = ns.AuraTracker.SettingsUtils

local pairs, ipairs, next = pairs, ipairs, next
local tonumber, tostring = tonumber, tostring
local table_insert, table_sort, table_remove = table.insert, table.sort, table.remove
local math_max = math.max
local string_format, string_upper = string.format, string.upper
local GetSpellInfo, GetItemInfo = GetSpellInfo, GetItemInfo

-- Import shared utilities
local L = SU.L
local editState = SU.editState

-- ==========================================================
-- HELPERS
-- ==========================================================

local function NotifyChange()
    SU.NotifyChange()
end

local function NotifyAndRebuild(barKey)
    SU.NotifyAndRebuild(barKey)
end

local function GetSpellNameByID(spellId)
    return SU.GetSpellNameByID(spellId)
end

local function GetTrackedNameAndIcon(id, trackType)
    return SU.GetTrackedNameAndIcon(id, trackType)
end

local function GetTrackTypeLabel(trackType, filterKey)
    return SU.GetTrackTypeLabel(trackType, filterKey)
end

local function GetFilterData(filterKey)
    return SU.GetFilterData(filterKey)
end

local function NormalizeAuraOrders(barData)
    SU.NormalizeAuraOrders(barData)
end

local function MoveIconToPosition(barKey, barData, spellId, newPos)
    SU.MoveIconToPosition(barKey, barData, spellId, newPos)
end

--- Build the combined data.type key from separate unit and filter values.
--- e.g. BuildAuraTypeKey("smart_group", "HELPFUL") → "smart_group_buff"
local function BuildAuraTypeKey(unit, filter)
    if not unit then return nil end
    local suffix = (filter == "HELPFUL") and "buff" or "debuff"
    return unit .. "_" .. suffix
end

-- ==========================================================
-- ICON EDITOR
-- ==========================================================

local function GetSortedIconIndex(barData, targetSpellId)
    NormalizeAuraOrders(barData)
    local sorted = {}
    for sid, d in pairs(barData.trackedItems) do
        table_insert(sorted, { spellId = sid, order = d.order or 999 })
    end
    table_sort(sorted, function(a, b) return a.order < b.order end)
    for i, entry in ipairs(sorted) do
        if entry.spellId == targetSpellId then
            return i, #sorted
        end
    end
    return nil, #sorted
end

-- Injects the icon editor into the outer args table as:
--   editorHeader / editorIconPreview / editorDeselect  (flat, above tabs)
--   iconEditorTabs  (childGroups="tab" group containing General/Load/Action/Also Track)
local function InjectIconEditorArgs(args, barKey, barData, spellId, orderBase)
    local data = barData.trackedItems[spellId]
    if not data then return end

    local name, icon = GetTrackedNameAndIcon(spellId, data.trackType)
    local isCooldown     = (data.trackType == "cooldown")
    local isItem         = (data.trackType == "item")
    local isAura         = (data.trackType == "aura")
    local isCooldownAura = (data.trackType == "cooldown_aura")
    local isInternalCD   = (data.trackType == "internal_cd")
    local isCustomICD    = (data.trackType == "custom_icd")
    local isWeaponEnchant = (data.trackType == "weapon_enchant")
    local isTotem        = (data.trackType == "totem")
    local hasAuraOptions = isAura or isCooldownAura
    local currentIndex, totalIcons = GetSortedIconIndex(barData, spellId)

    -- ----------------------------------------------------------
    -- Flat section: header / preview / deselect  (above the tabs)
    -- ----------------------------------------------------------
    args.editorHeader = {
        type  = "header",
        name  = string_format("Selected: %s  (ID: %s)", name, tostring(spellId)),
        order = orderBase,
    }
    args.editorIconPreview = {
        type        = "description",
        name        = "",
        image       = icon,
        imageWidth  = 32,
        imageHeight = 32,
        order       = orderBase + 1,
        width       = 0.25,
    }
    args.editorDeselect = {
        type  = "execute",
        name  = "Deselect",
        order = orderBase + 2,
        width = "half",
        func  = function()
            editState.selectedAura = nil
            NotifyChange()
        end,
    }

    -- ----------------------------------------------------------
    -- Build args tables for each sub-tab
    -- ----------------------------------------------------------

    local generalArgs = {}
    local loadArgs    = {}
    local actionArgs  = {}
    local altArgs     = {}

    -- ---- GENERAL TAB ----------------------------------------

    -- Display mode
    local displayValues
    if isCooldownAura then
        displayValues = L.DUAL_DISPLAY_MODES
    elseif isCooldown or isItem or isInternalCD or isCustomICD or isTotem then
        displayValues = L.COOLDOWN_DISPLAY_MODES
    else
        displayValues = L.AURA_DISPLAY_MODES
    end
    generalArgs.editorDisplayMode = {
        type   = "select",
        name   = "Visibility",
        desc   = "When should this icon be visible?",
        values = displayValues,
        order  = 1,
        get    = function() return data.displayMode or "always" end,
        set    = function(_, val)
            data.displayMode = val
            NotifyAndRebuild(barKey)
        end,
    }

    -- Custom ICD options
    if isCustomICD then
        generalArgs.editorCustomICDDuration = {
            type  = "input",
            name  = "ICD Duration (seconds)",
            desc  = "The internal cooldown duration in seconds that starts when the trigger buff is applied to the player.",
            order = 2,
            width = "double",
            get   = function()
                return tostring(data.icdDuration or "")
            end,
            set   = function(_, val)
                local n = tonumber(val)
                if n and n > 0 then
                    data.icdDuration = n
                    NotifyAndRebuild(barKey)
                end
            end,
        }
    end

    -- Aura-specific options
    if hasAuraOptions then
        generalArgs.editorAuraUnit = {
            type   = "select",
            name   = "Unit",
            desc   = "Which unit to monitor for this aura.",
            values = L.AURA_UNITS,
            order  = 2,
            width  = "half",
            get    = function() return data.unit or "target" end,
            set    = function(_, val)
                data.unit   = val
                data.type   = BuildAuraTypeKey(val, data.filter)
                NotifyAndRebuild(barKey)
            end,
        }
        generalArgs.editorAuraFilterType = {
            type   = "select",
            name   = "Aura Type",
            desc   = "Whether to track buffs or debuffs on the selected unit.",
            values = L.AURA_FILTER_TYPES,
            order  = 2.5,
            width  = "half",
            get    = function() return data.filter or "HARMFUL" end,
            set    = function(_, val)
                data.filter = val
                data.type   = BuildAuraTypeKey(data.unit, val)
                NotifyAndRebuild(barKey)
            end,
        }
        generalArgs.editorAuraIdOverride = {
            type  = "input",
            name  = "Aura ID Override",
            desc  = "Override which spell ID is scanned as the aura. Leave blank to use the same ID as the spell.",
            order = 3,
            get   = function()
                return tostring(data.auraId or spellId)
            end,
            set   = function(_, val)
                local n = tonumber(val)
                data.auraId = (n and n ~= spellId) and n or nil
                NotifyAndRebuild(barKey)
            end,
        }
        generalArgs.editorOnlyMine = {
            type  = "toggle",
            name  = "Only Mine",
            desc  = "Only track auras cast by you. Uncheck to track auras from any player (e.g. Improved Scorch from another mage).",
            order = 4,
            width = "full",
            get   = function() return data.onlyMine or false end,
            set   = function(_, val)
                data.onlyMine = val
                NotifyAndRebuild(barKey)
            end,
        }
        generalArgs.editorShowSnapshotText = {
            type  = "toggle",
            name  = "Show Snapshot Diff",
            desc  = "Show a percentage indicating whether refreshing this DoT now would increase (+) or decrease (-) its damage compared to when it was applied.",
            order = 5,
            width = "full",
            get   = function() return data.showSnapshotText or false end,
            set   = function(_, val)
                data.showSnapshotText = val
                NotifyAndRebuild(barKey)
            end,
        }
    end

    -- Weapon enchant slot + expected enchant options
    if isWeaponEnchant then
        generalArgs.editorWeaponSlot = {
            type   = "select",
            name   = "Weapon Slot",
            desc   = "Which weapon slot to check for a temporary enchant.",
            values = { ["mainhand"] = "Main Hand", ["offhand"] = "Off Hand" },
            order  = 2,
            get    = function() return data.slot or "mainhand" end,
            set    = function(_, val)
                data.slot = val
                NotifyAndRebuild(barKey)
            end,
        }

        -- Build the Expected Enchant dropdown from Config.WeaponEnchantChoices.
        local Config = ns.AuraTracker.Config
        local enchantValues = {}
        if Config and Config.WeaponEnchantChoices then
            for _, choice in ipairs(Config.WeaponEnchantChoices) do
                enchantValues[choice.key] = choice.label
            end
        end
        generalArgs.editorExpectedEnchant = {
            type   = "select",
            name   = "Expected Enchant",
            desc   = "Which temporary enchant is expected on this weapon slot.\n\n'Any Enchant' activates whenever any temporary enchant is present.\n\nFor a specific type, the enchant name is read directly from the weapon slot tooltip, so detection works immediately -- even for enchants already on the weapon at login.",
            values = enchantValues,
            order  = 3,
            get    = function() return data.expectedEnchant or "any" end,
            set    = function(_, val)
                data.expectedEnchant = (val == "any") and nil or val
                NotifyAndRebuild(barKey)
            end,
        }
    end

    -- Reorder controls
    if currentIndex and totalIcons > 1 then
        generalArgs.editorReorderHeader = { type = "header", name = "Order", order = 50 }
        generalArgs.editorMoveLeft = {
            type     = "execute",
            name     = "<  Move Left",
            order    = 51,
            width    = "0.75",
            disabled = (currentIndex <= 1),
            func     = function() MoveIconToPosition(barKey, barData, spellId, currentIndex - 1) end,
        }
        generalArgs.editorMoveRight = {
            type     = "execute",
            name     = "Move Right  >",
            order    = 52,
            width    = "0.75",
            disabled = (currentIndex >= totalIcons),
            func     = function() MoveIconToPosition(barKey, barData, spellId, currentIndex + 1) end,
        }
    end

    -- Danger zone in General tab
    generalArgs.editorDangerHeader = { type = "header", name = "", order = 99 }
    generalArgs.editorDelete = {
        type        = "execute",
        name        = "Remove from Bar",
        desc        = "Stop tracking this spell on this bar.",
        order       = 100,
        confirm     = true,
        confirmText = "Remove " .. name .. " from this bar?",
        func        = function()
            barData.trackedItems[spellId] = nil
            editState.selectedAura = nil
            NotifyAndRebuild(barKey)
        end,
    }

    -- ---- LOAD TAB -------------------------------------------

    local Conditionals = ns.AuraTracker and ns.AuraTracker.Conditionals
    if Conditionals then
        Conditionals:BuildLoadConditionUI(loadArgs, data, 1, barKey, NotifyAndRebuild, "icon")
    end

    -- ---- ACTION TAB -----------------------------------------

    if Conditionals then
        -- Icon event actions (On Click / On Show / On Hide) at the top
        Conditionals:BuildIconActionsUI(actionArgs, data, 1, barKey, NotifyAndRebuild)
        -- Action conditionals (glow/sound when a threshold is crossed) below
        Conditionals:BuildActionConditionUI(actionArgs, data, 20, barKey, NotifyAndRebuild)
    end

    -- ---- ALSO TRACK TAB (aura-only) -------------------------

    if hasAuraOptions then
        altArgs.editorAlsoTrackHeader = {
            type  = "header",
            name  = "Also Track (Alternatives)",
            order = 1,
        }
        altArgs.editorAlsoTrackDesc = {
            type  = "description",
            name  = "|cFFAAAAFFAdd alternative spell IDs that this icon should also scan for.\n"
                .. "The icon will show whichever spell is active (e.g. add all curse variants so one icon tracks any curse).\n"
                .. "Lower-level spell ranks are matched automatically by name.|r",
            order = 2,
            width = "full",
        }
        altArgs.editorAlsoTrackAdd = {
            type  = "input",
            name  = "Add Spell ID",
            desc  = "Enter a spell ID to add as an alternative for this icon.\n"
                .. "If the spell belongs to an exclusive group preset, all spells from that group will be added automatically.",
            order = 3,
            width = "full",
            get   = function() return "" end,
            set   = function(_, val)
                local sid = tonumber(val)
                if not sid then return end
                if sid == spellId then
                    print("|cFFFF0000Aura Tracker:|r This is the primary spell ID; no need to add it.")
                    return
                end
                local altName = GetSpellInfo(sid)
                if not altName then
                    print("|cFFFF0000Aura Tracker:|r Spell ID " .. sid .. " not found.")
                    return
                end
                data.exclusiveSpells = data.exclusiveSpells or {}
                if data.exclusiveSpells[sid] then
                    print("|cFFFF0000Aura Tracker:|r Spell " .. altName .. " is already in the list.")
                    return
                end
                data.exclusiveSpells[sid] = true

                -- Auto-link: if this spell belongs to an exclusive group, add the whole group
                local Cfg = ns.AuraTracker and ns.AuraTracker.Config
                if Cfg and Cfg.GetPresetForSpell then
                    local presetKey = Cfg:GetPresetForSpell(sid)
                    if presetKey then
                        local preset = Cfg.ExclusivePresets[presetKey]
                        if preset then
                            for groupSpellId in pairs(preset.spells) do
                                if groupSpellId ~= spellId then
                                    data.exclusiveSpells[groupSpellId] = true
                                end
                            end
                        end
                    end
                end

                NotifyAndRebuild(barKey)
            end,
        }

        -- WotLK preset loader
        local Config = ns.AuraTracker and ns.AuraTracker.Config
        if Config and Config.ExclusivePresets then
            local presetValues = { [""] = "Select a preset…" }
            for key, preset in pairs(Config.ExclusivePresets) do
                presetValues[key] = preset.label
            end
            altArgs.editorAlsoTrackPreset = {
                type  = "select",
                name  = "Load WotLK Preset",
                desc  = "Load a predefined set of alternative spell IDs.\n"
                    .. "These are WotLK-era (level 80) spell IDs. "
                    .. "Lower-level ranks are matched automatically by name.",
                values = presetValues,
                order  = 4,
                width  = "double",
                get    = function() return "" end,
                set    = function(_, key)
                    if key == "" then return end
                    local preset = Config.ExclusivePresets[key]
                    if not preset then return end
                    data.exclusiveSpells = data.exclusiveSpells or {}
                    local added = 0
                    for sid in pairs(preset.spells) do
                        if not data.exclusiveSpells[sid] then
                            data.exclusiveSpells[sid] = true
                            added = added + 1
                        end
                    end
                    if added > 0 then
                        NotifyAndRebuild(barKey)
                    else
                        print("|cFFFF9900Aura Tracker:|r All spells from this preset are already added.")
                    end
                end,
            }
        end

        -- Show current exclusive spell entries
        local excl = data.exclusiveSpells
        if excl and next(excl) then
            local exclOrder = 0
            for exclId in pairs(excl) do
                exclOrder = exclOrder + 1
                local exclName, exclIcon = GetSpellNameByID(exclId)
                altArgs["editorExcl_icon_" .. exclId] = {
                    type        = "description",
                    name        = "",
                    image       = exclIcon,
                    imageWidth  = 20,
                    imageHeight = 20,
                    order       = 5 + (exclOrder * 2),
                    width       = 0.15,
                }
                altArgs["editorExcl_remove_" .. exclId] = {
                    type  = "execute",
                    name  = exclName .. "  (ID: " .. exclId .. ")  x",
                    desc  = "Remove " .. exclName .. " from the alternatives list.",
                    order = 6 + (exclOrder * 2),
                    width = "normal",
                    func  = function()
                        if data.exclusiveSpells then
                            data.exclusiveSpells[exclId] = nil
                            if not next(data.exclusiveSpells) then
                                data.exclusiveSpells = nil
                            end
                        end
                        NotifyAndRebuild(barKey)
                    end,
                }
            end
        else
            altArgs.editorAlsoTrackEmpty = {
                type  = "description",
                name  = "No alternatives defined. This icon only tracks the primary spell.",
                order = 5,
                width = "full",
            }
        end
    end

    -- ---- CUSTOM TEXTS TAB -----------------------------------

    local ANCHOR_POINTS = {
        ["TOPLEFT"]     = "Top Left",
        ["TOP"]         = "Top Center",
        ["TOPRIGHT"]    = "Top Right",
        ["LEFT"]        = "Left",
        ["CENTER"]      = "Center",
        ["RIGHT"]       = "Right",
        ["BOTTOMLEFT"]  = "Bottom Left",
        ["BOTTOM"]      = "Bottom Center",
        ["BOTTOMRIGHT"] = "Bottom Right",
    }

    local customTextsArgs = {}

    customTextsArgs.ctDesc = {
        type  = "description",
        name  = "Add extra text overlays to this icon. Each overlay has its own format string, "
            .. "anchor point, and colour.\n\n"
            .. "|cFFFFFF00Tokens:|r  "
            .. "|cFFFFD700%stacks|r / |cFFFFD700%count|r – stack count  •  "
            .. "|cFFFFD700%remaining|r – time left (hidden when 0)  •  "
            .. "|cFFFFD700%progress|r – remaining/duration  •  "
            .. "|cFFFFD700%name|r – spell/item name  •  "
            .. "|cFFFFD700%srcName|r – caster name  •  "
            .. "|cFFFFD700%destName|r – target unit name",
        order = 1,
        width = "full",
    }

    customTextsArgs.ctAdd = {
        type  = "execute",
        name  = "Add Custom Text",
        desc  = "Append a new text overlay to this icon.",
        order = 2,
        width = "normal",
        func  = function()
            data.customTexts = data.customTexts or {}
            table_insert(data.customTexts, {
                enabled  = true,
                format   = "%stacks",
                point    = "BOTTOMRIGHT",
                xOffset  = -2,
                yOffset  = 2,
                color    = { r = 1, g = 1, b = 1, a = 1 },
            })
            NotifyAndRebuild(barKey)
        end,
    }

    -- Build an inline group for each existing custom text entry
    local cts = data.customTexts
    if cts and #cts > 0 then
        for ctIdx, ctEntry in ipairs(cts) do
            local ci = ctIdx  -- capture for closures
            customTextsArgs["ct_" .. ci] = {
                type   = "group",
                name   = "Text " .. ci,
                inline = true,
                order  = 10 + ci,
                args   = {
                    ctEnabled = {
                        type  = "toggle",
                        name  = "Enabled",
                        order = 1,
                        width = "half",
                        get   = function() return ctEntry.enabled ~= false end,
                        set   = function(_, val)
                            ctEntry.enabled = val
                            NotifyAndRebuild(barKey)
                        end,
                    },
                    ctDelete = {
                        type    = "execute",
                        name    = "Remove",
                        order   = 2,
                        width   = "half",
                        confirm = true,
                        confirmText = "Remove Text " .. ci .. "?",
                        func    = function()
                            -- ci is the index captured at UI-build time.
                            -- NotifyAndRebuild immediately regenerates the UI from the
                            -- updated array, so any stale closures from the old UI are
                            -- replaced before the user can interact with them again.
                            table_remove(data.customTexts, ci)
                            if #data.customTexts == 0 then
                                data.customTexts = nil
                            end
                            NotifyAndRebuild(barKey)
                        end,
                    },
                    ctFormat = {
                        type  = "input",
                        name  = "Format",
                        desc  = "Text to display. Use tokens: %stacks, %count, %remaining, %progress, %name, %srcName, %destName.",
                        order = 3,
                        width = "full",
                        get   = function() return ctEntry.format or "" end,
                        set   = function(_, val)
                            ctEntry.format = val or ""
                            NotifyAndRebuild(barKey)
                        end,
                    },
                    ctPoint = {
                        type   = "select",
                        name   = "Anchor",
                        desc   = "Where on the icon to place this text.",
                        values = ANCHOR_POINTS,
                        order  = 4,
                        width  = "double",
                        get    = function() return ctEntry.point or "BOTTOMRIGHT" end,
                        set    = function(_, val)
                            ctEntry.point = val
                            NotifyAndRebuild(barKey)
                        end,
                    },
                    ctXOffset = {
                        type    = "range",
                        name    = "X Offset",
                        min     = -64, max = 64, step = 1,
                        order   = 5,
                        width   = "double",
                        get     = function() return ctEntry.xOffset or 0 end,
                        set     = function(_, val)
                            ctEntry.xOffset = val
                            NotifyAndRebuild(barKey)
                        end,
                    },
                    ctYOffset = {
                        type    = "range",
                        name    = "Y Offset",
                        min     = -64, max = 64, step = 1,
                        order   = 6,
                        width   = "double",
                        get     = function() return ctEntry.yOffset or 0 end,
                        set     = function(_, val)
                            ctEntry.yOffset = val
                            NotifyAndRebuild(barKey)
                        end,
                    },
                    ctColor = {
                        type  = "color",
                        name  = "Color",
                        desc  = "Text colour.",
                        order = 7,
                        hasAlpha = true,
                        get   = function()
                            local c = ctEntry.color or {}
                            return c.r or 1, c.g or 1, c.b or 1, c.a or 1
                        end,
                        set   = function(_, r, g, b, a)
                            ctEntry.color = { r = r, g = g, b = b, a = a }
                            NotifyAndRebuild(barKey)
                        end,
                    },
                    ctFontSize = {
                        type  = "range",
                        name  = "Font Size",
                        desc  = "Font size for this text. Set to 0 to inherit the bar's default font size.",
                        min   = 0, max = 32, step = 1,
                        order = 8,
                        width = "double",
                        get   = function() return ctEntry.fontSize or 0 end,
                        set   = function(_, val)
                            -- 0 means "use bar default"; store nil so ApplyCustomTexts falls back
                            ctEntry.fontSize = (val > 0) and val or nil
                            NotifyAndRebuild(barKey)
                        end,
                    },
                },
            }
        end
    else
        customTextsArgs.ctEmpty = {
            type  = "description",
            name  = "|cFFAAAAAFNo custom texts defined. Click |cFFFFFF00Add Custom Text|r to add one.|r",
            order = 10,
            width = "full",
        }
    end

    -- ----------------------------------------------------------
    -- Inject tab groups directly into outer args.
    -- The icons group (childGroups="tab") renders these as tabs;
    -- non-group items (header, icon strip, preview) appear above.
    -- ----------------------------------------------------------

    args.iconEditorGeneral = {
        type  = "group",
        name  = "General",
        order = 1,
        args  = generalArgs,
    }
    args.iconEditorLoad = {
        type  = "group",
        name  = "Load",
        order = 2,
        args  = loadArgs,
    }
    args.iconEditorAction = {
        type  = "group",
        name  = "Action",
        order = 3,
        args  = actionArgs,
    }
    if hasAuraOptions then
        args.iconEditorAlternative = {
            type  = "group",
            name  = "Also Track",
            order = 4,
            args  = altArgs,
        }
    end
    args.iconEditorCustomTexts = {
        type  = "group",
        name  = "Custom Texts",
        order = 5,
        args  = customTextsArgs,
    }
end


-- Export for IconEditorOptions.lua
ns.AuraTracker._InjectIconEditorArgs = InjectIconEditorArgs
