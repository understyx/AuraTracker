local _, ns = ...

-- ==========================================================
-- SHARED REFERENCES (from Settings.lua)
-- ==========================================================
-- Settings.lua exports shared utilities to ns.AuraTracker.SettingsUtils
-- which this file accesses at load time.

local SU = ns.AuraTracker.SettingsUtils

local pairs, ipairs, next = pairs, ipairs, next
local tonumber, tostring = tonumber, tostring
local table_insert, table_sort = table.insert, table.sort
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

local function InjectIconEditorArgs(args, barKey, barData, spellId, orderBase)
    local data = barData.trackedItems[spellId]
    if not data then return end

    local name, icon = GetTrackedNameAndIcon(spellId, data.trackType)
    local isCooldown = (data.trackType == "cooldown")
    local isItem = (data.trackType == "item")
    local isAura = (data.trackType == "aura")
    local isCooldownAura = (data.trackType == "cooldown_aura")
    local isInternalCD = (data.trackType == "internal_cd")
    local hasAuraOptions = isAura or isCooldownAura
    local currentIndex, totalIcons = GetSortedIconIndex(barData, spellId)

    args.editorHeader = {
        type = "header",
        name = string_format("Selected: %s  (ID: %d)", name, spellId),
        order = orderBase,
    }
    args.editorIconPreview = {
        type = "description",
        name = "",
        image = icon,
        imageWidth = 32,
        imageHeight = 32,
        order = orderBase + 1,
        width = 0.25,
    }
    args.editorDeselect = {
        type = "execute",
        name = "Deselect",
        order = orderBase + 2,
        width = "half",
        func = function()
            editState.selectedAura = nil
            NotifyChange()
        end,
    }
    local displayValues
    if isCooldownAura then
        displayValues = L.DUAL_DISPLAY_MODES
    elseif isCooldown or isItem or isInternalCD then
        displayValues = L.COOLDOWN_DISPLAY_MODES
    else
        displayValues = L.AURA_DISPLAY_MODES
    end
    args.editorDisplayMode = {
        type = "select",
        name = "Visibility",
        desc = "When should this icon be visible?",
        values = displayValues,
        order = orderBase + 10,
        get = function() return data.displayMode or "always" end,
        set = function(_, val)
            data.displayMode = val
            NotifyAndRebuild(barKey)
        end,
    }

    -- ==========================================================
    -- LOAD CONDITIONS + ACTION CONDITIONALS  (shared module)
    -- ==========================================================

    local Conditionals = ns.AuraTracker and ns.AuraTracker.Conditionals
    if Conditionals then
        Conditionals:BuildLoadConditionUI(args, data, orderBase + 15, barKey, NotifyAndRebuild, "icon")
        Conditionals:BuildActionConditionUI(args, data, orderBase + 45, barKey, NotifyAndRebuild)
    end

    -- Aura options: source, aura-ID override, "only mine" toggle
    if hasAuraOptions then
        args.editorAuraSource = {
            type = "select",
            name = "Track From",
            desc = "Which unit and buff/debuff type to monitor.",
            values = L.AURA_SOURCES,
            order = orderBase + 11,
            get = function() return data.type or "target_debuff" end,
            set = function(_, val)
                data.type = val
                local fd = GetFilterData(val)
                if fd then
                    data.unit   = fd.unit
                    data.filter = fd.filter
                end
                NotifyAndRebuild(barKey)
            end,
        }
        args.editorAuraIdOverride = {
            type = "input",
            name = "Aura ID Override",
            desc = "Override which spell ID is scanned as the aura. Leave blank to use the same ID as the spell.",
            order = orderBase + 12,
            get = function()
                return tostring(data.auraId or spellId)
            end,
            set = function(_, val)
                local n = tonumber(val)
                data.auraId = (n and n ~= spellId) and n or nil
                NotifyAndRebuild(barKey)
            end,
        }
        args.editorOnlyMine = {
            type = "toggle",
            name = "Only Mine",
            desc = "Only track auras cast by you. Uncheck to track auras from any player (e.g. Improved Scorch from another mage).",
            order = orderBase + 13,
            width = "full",
            get = function() return data.onlyMine or false end,
            set = function(_, val)
                data.onlyMine = val
                NotifyAndRebuild(barKey)
            end,
        }
        args.editorShowSnapshotText = {
            type = "toggle",
            name = "Show Snapshot Diff",
            desc = "Show a percentage indicating whether refreshing this DoT now would increase (+) or decrease (-) its damage compared to when it was applied.",
            order = orderBase + 14,
            width = "full",
            get = function() return data.showSnapshotText or false end,
            set = function(_, val)
                data.showSnapshotText = val
                NotifyAndRebuild(barKey)
            end,
        }

        -- "Also Track" section: user-defined exclusive/alternative spell IDs
        args.editorAlsoTrackHeader = {
            type = "header",
            name = "Also Track (Alternatives)",
            order = orderBase + 20,
        }
        args.editorAlsoTrackDesc = {
            type = "description",
            name = "|cFFAAAAFFAdd alternative spell IDs that this icon should also scan for.\n"
                .. "The icon will show whichever spell is active (e.g. add all curse variants so one icon tracks any curse).\n"
                .. "Lower-level spell ranks are matched automatically by name.|r",
            order = orderBase + 21,
            width = "full",
        }
        args.editorAlsoTrackAdd = {
            type = "input",
            name = "Add Spell ID",
            desc = "Enter a spell ID to add as an alternative for this icon.\n"
                .. "If the spell belongs to an exclusive group preset, all spells from that group will be added automatically.",
            order = orderBase + 22,
            width = "full",
            get = function() return "" end,
            set = function(_, val)
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
            args.editorAlsoTrackPreset = {
                type = "select",
                name = "Load WotLK Preset",
                desc = "Load a predefined set of alternative spell IDs.\n"
                    .. "These are WotLK-era (level 80) spell IDs. "
                    .. "Lower-level ranks are matched automatically by name.",
                values = presetValues,
                order = orderBase + 22.5,
                width = "double",
                get = function() return "" end,
                set = function(_, key)
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
                args["editorExcl_icon_" .. exclId] = {
                    type        = "description",
                    name        = "",
                    image       = exclIcon,
                    imageWidth  = 20,
                    imageHeight = 20,
                    order       = orderBase + 23 + (exclOrder * 2),
                    width       = 0.15,
                }
                args["editorExcl_remove_" .. exclId] = {
                    type  = "execute",
                    name  = exclName .. "  (ID: " .. exclId .. ")  x",
                    desc  = "Remove " .. exclName .. " from the alternatives list.",
                    order = orderBase + 24 + (exclOrder * 2),
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
            args.editorAlsoTrackEmpty = {
                type = "description",
                name = "No alternatives defined. This icon only tracks the primary spell.",
                order = orderBase + 23,
                width = "full",
            }
        end
    end

    -- Reorder controls
    if currentIndex and totalIcons > 1 then
        args.editorReorderHeader = { type = "header", name = "Order", order = orderBase + 50 }
        args.editorMoveLeft = {
            type     = "execute",
            name     = "<  Move Left",
            order    = orderBase + 51,
            width    = "half",
            disabled = (currentIndex <= 1),
            func     = function() MoveIconToPosition(barKey, barData, spellId, currentIndex - 1) end,
        }
        args.editorMoveRight = {
            type     = "execute",
            name     = "Move Right  >",
            order    = orderBase + 52,
            width    = "half",
            disabled = (currentIndex >= totalIcons),
            func     = function() MoveIconToPosition(barKey, barData, spellId, currentIndex + 1) end,
        }
    end

    args.editorDangerHeader = { type = "header", name = "", order = orderBase + 99 }
    args.editorDelete = {
        type = "execute",
        name = "Remove from Bar",
        desc = "Stop tracking this spell on this bar.",
        order = orderBase + 100,
        confirm = true,
        confirmText = "Remove " .. name .. " from this bar?",
        func = function()
            barData.trackedItems[spellId] = nil
            editState.selectedAura = nil
            NotifyAndRebuild(barKey)
        end,
    }
end

-- ==========================================================
-- ICON LIST
-- ==========================================================

local function CreateIconListOptions(barKey, barData)
    barData.trackedItems = barData.trackedItems or {}
    NormalizeAuraOrders(barData)

    local sortedItems = {}
    for spellId, data in pairs(barData.trackedItems) do
        table_insert(sortedItems, { spellId = spellId, data = data, order = data.order or 999 })
    end
    table_sort(sortedItems, function(a, b) return a.order < b.order end)

    local args = {
        listHeader = { type = "header", name = "Tracked Icons", order = 10 },
    }

    if #sortedItems == 0 then
        args.emptyMsg = {
            type = "description",
            name = "No spells tracked yet. Drag spells from your spellbook onto the bar.",
            order = 11,
            width = "full",
        }
    else
        args.listHint = {
            type = "description",
            name = "|cFFAAAAFFClick an icon to configure, reorder, or remove it.|r",
            order = 11,
            width = "full",
        }
        for i, item in ipairs(sortedItems) do
            local spellId     = item.spellId
            local spellName, spellIcon = GetTrackedNameAndIcon(spellId, item.data.trackType)
            local typeLabel   = GetTrackTypeLabel(item.data.trackType, item.data.type)

            -- Compact icon button – click to configure
            args["icon_" .. spellId] = {
                type        = "execute",
                name        = "",
                desc        = spellName .. "  " .. typeLabel .. "\nClick to configure",
                image       = spellIcon,
                imageWidth  = 36,
                imageHeight = 36,
                width       = 0.20,
                order       = 20 + i,
                func        = function()
                    if editState.selectedAura == spellId then
                        editState.selectedAura = nil
                    else
                        editState.selectedAura = spellId
                    end
                    NotifyChange()
                end,
            }
        end
    end

    -- If an icon is selected, inject editor inline below the icon strip
    if editState.selectedAura and barData.trackedItems[editState.selectedAura] then
        InjectIconEditorArgs(args, barKey, barData, editState.selectedAura, 100)
    end

    return {
        type        = "group",
        name        = "Icons",
        childGroups = "tree",
        args        = args,
    }
end

-- Export for use by BarSettingsUI.lua
ns.AuraTracker.CreateIconListOptions = CreateIconListOptions
