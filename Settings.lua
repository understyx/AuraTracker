local addonName, ns = ...

local pairs, ipairs, next = pairs, ipairs, next
local tonumber, tostring = tonumber, tostring
local table_insert, table_sort, table_remove = table.insert, table.sort, table.remove
local math_max, math_min, math_floor = math.max, math.min, math.floor
local string_format, string_upper = string.format, string.upper
local GetSpellInfo = GetSpellInfo

local LibEditmode = LibStub("LibEditmode-1.0", true)

-- ==========================================================
-- CONSTANTS & LABELS
-- ==========================================================

local L = {
    CLASSES = {
        ["NONE"] = "Any Class",
        ["WARRIOR"] = "Warrior", ["PALADIN"] = "Paladin", ["HUNTER"] = "Hunter",
        ["ROGUE"] = "Rogue", ["PRIEST"] = "Priest", ["DEATHKNIGHT"] = "Death Knight",
        ["SHAMAN"] = "Shaman", ["MAGE"] = "Mage", ["WARLOCK"] = "Warlock",
        ["DRUID"] = "Druid",
    },
    DIRECTIONS = {
        ["HORIZONTAL"] = "Horizontal",
        ["VERTICAL"]   = "Vertical",
    },
    AURA_SOURCES = {
        ["player_buff"]   = "Player – Buff",
        ["player_debuff"] = "Player – Debuff",
        ["target_buff"]   = "Target – Buff",
        ["target_debuff"] = "Target – Debuff",
        ["focus_buff"]    = "Focus – Buff",
        ["focus_debuff"]  = "Focus – Debuff",
    },
    -- Display-mode labels that make sense for cooldowns
    COOLDOWN_DISPLAY_MODES = {
        ["always"]       = "Always Show",
        ["active_only"]  = "Show When Ready",
        ["missing_only"] = "Show On Cooldown",
    },
    -- Display-mode labels that make sense for auras
    AURA_DISPLAY_MODES = {
        ["always"]       = "Always Show",
        ["active_only"]  = "Show When Active",
        ["missing_only"] = "Show When Missing",
    },
    TRACK_TYPES = {
        ["cooldown"] = "Cooldown",
        ["aura"]     = "Aura",
    },
}

-- ==========================================================
-- SESSION STATE  (UI-only; not persisted)
-- ==========================================================

local editState = {
    selectedBar  = nil,
    selectedAura = nil,
}

local addState = {}

-- ==========================================================
-- HELPERS
-- ==========================================================

local function GetSpellNameByID(spellId)
    local name, _, icon = GetSpellInfo(spellId)
    return name or "Unknown Spell", icon
end

local function GetTrackTypeLabel(trackType, filterKey)
    if trackType == "aura" then
        local src = filterKey and L.AURA_SOURCES[filterKey] or "aura"
        return "|cFFAAFFAA" .. src .. "|r"
    end
    return "|cFFAAD4FFcooldown|r"
end

local function RebuildBar(barKey)
    if ns.AuraTracker and ns.AuraTracker.Controller then
        ns.AuraTracker.Controller:RebuildBar(barKey)
    end
end

local function NotifyChange()
    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
end

local function NotifyAndRebuild(barKey)
    RebuildBar(barKey)
    NotifyChange()
end

local DEFAULT_TEXT_COLOR = { r = 1, g = 1, b = 1, a = 1 }

local function GetNextOrder(trackedItems)
    local maxOrder = 0
    for _, d in pairs(trackedItems) do
        maxOrder = math_max(maxOrder, d.order or 0)
    end
    return maxOrder + 1
end

local function GetBarDisplayName(barData, key)
    local classKey = barData.classRestriction or "NONE"
    local barName  = barData.name or key
    if classKey == "NONE" then
        return "All: " .. barName
    end
    local classLabel = L.CLASSES[classKey] or classKey
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classKey]
    if color then
        local hex = string_format("%02X%02X%02X",
            math_floor((color.r or 0) * 255),
            math_floor((color.g or 0) * 255),
            math_floor((color.b or 0) * 255))
        return "|cFF" .. hex .. classLabel .. ":|r " .. barName
    end
    return classLabel .. ": " .. barName
end

local function GetFilterData(filterKey)
    local Config = ns.AuraTracker and ns.AuraTracker.Config
    if not Config or not filterKey then return nil end
    return Config:GetAuraFilter(string_upper(filterKey))
end

-- ==========================================================
-- ICON ORDER HELPERS
-- ==========================================================

local function NormalizeAuraOrders(barData)
    if not barData.trackedItems then return end
    local sorted = {}
    for spellId, data in pairs(barData.trackedItems) do
        table_insert(sorted, { id = spellId, order = data.order or 999 })
    end
    table_sort(sorted, function(a, b) return a.order < b.order end)
    for i, item in ipairs(sorted) do
        barData.trackedItems[item.id].order = i
    end
end

local function MoveIconToPosition(barKey, barData, spellId, newPos)
    if not barData or not barData.trackedItems then return end
    NormalizeAuraOrders(barData)
    local sorted = {}
    for sid, d in pairs(barData.trackedItems) do
        table_insert(sorted, { spellId = sid, order = d.order or 999 })
    end
    table_sort(sorted, function(a, b) return a.order < b.order end)
    -- Find current position
    local currentPos
    for i, entry in ipairs(sorted) do
        if entry.spellId == spellId then
            currentPos = i
            break
        end
    end
    if not currentPos then return end
    newPos = math_max(1, math_min(newPos, #sorted))
    if currentPos == newPos then return end
    -- Remove from current and insert at new position
    local item = table_remove(sorted, currentPos)
    table_insert(sorted, newPos, item)
    -- Renumber all orders
    for i, entry in ipairs(sorted) do
        barData.trackedItems[entry.spellId].order = i
    end
    NotifyAndRebuild(barKey)
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

    local name, icon = GetSpellNameByID(spellId)
    local isCooldown = (data.trackType == "cooldown")
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
    args.editorDisplayMode = {
        type = "select",
        name = "Visibility",
        desc = "When should this icon be visible?",
        values = isCooldown and L.COOLDOWN_DISPLAY_MODES or L.AURA_DISPLAY_MODES,
        order = orderBase + 10,
        get = function() return data.displayMode or "always" end,
        set = function(_, val)
            data.displayMode = val
            NotifyAndRebuild(barKey)
        end,
    }

    -- Aura-only: source (unit + buff/debuff) and optional aura-ID override
    if not isCooldown then
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
    end

    -- Reorder controls
    if currentIndex and totalIcons > 1 then
        args.editorReorderHeader = { type = "header", name = "Order", order = orderBase + 50 }
        args.editorMoveLeft = {
            type     = "execute",
            name     = "◀ Move Left",
            order    = orderBase + 51,
            width    = "half",
            disabled = (currentIndex <= 1),
            func     = function() MoveIconToPosition(barKey, barData, spellId, currentIndex - 1) end,
        }
        args.editorMoveRight = {
            type     = "execute",
            name     = "Move Right ▶",
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

    addState[barKey] = addState[barKey] or { trackType = "cooldown", filterKey = "target_debuff" }
    local st = addState[barKey]

    local args = {
        addHeader = { type = "header", name = "Add Spell", order = 1 },

        addTrackType = {
            type = "select",
            name = "Track As",
            desc = "Whether to track this spell's cooldown or the aura it applies.",
            values = L.TRACK_TYPES,
            order = 2,
            width = "half",
            get = function() return st.trackType end,
            set = function(_, v)
                st.trackType = v
                NotifyChange()
            end,
        },

        addAuraSource = {
            type = "select",
            name = "Aura Source",
            desc = "Which unit and buff/debuff type to monitor.",
            values = L.AURA_SOURCES,
            order = 3,
            width = "half",
            hidden = function() return st.trackType ~= "aura" end,
            get = function() return st.filterKey end,
            set = function(_, v)
                st.filterKey = v
                NotifyChange()
            end,
        },

        addSpellId = {
            type = "input",
            name = "Spell ID  (press Enter to add)",
            desc = "Enter the numeric Spell ID and press Enter.",
            order = 4,
            width = "full",
            get = function() return "" end,
            set = function(_, val)
                local spellId = tonumber(val)
                if not spellId then return end

                if barData.trackedItems[spellId] then
                    print("|cFFFF0000Aura Tracker:|r This spell is already on this bar.")
                    return
                end
                local spellName = GetSpellInfo(spellId)
                if not spellName then
                    print("|cFFFF0000Aura Tracker:|r Spell ID " .. spellId .. " not found.")
                    return
                end

                local nextOrder = GetNextOrder(barData.trackedItems)

                if st.trackType == "cooldown" then
                    barData.trackedItems[spellId] = {
                        order       = nextOrder,
                        trackType   = "cooldown",
                        displayMode = "always",
                    }
                else
                    local fk = st.filterKey or "target_debuff"
                    local fd = GetFilterData(fk)
                    barData.trackedItems[spellId] = {
                        order       = nextOrder,
                        trackType   = "aura",
                        auraId      = spellId,
                        type        = fk,
                        unit        = fd and fd.unit   or "target",
                        filter      = fd and fd.filter or "HARMFUL",
                        displayMode = "active_only",
                    }
                end

                editState.selectedAura = spellId
                NotifyAndRebuild(barKey)
            end,
        },

        listHeader = { type = "header", name = "Tracked Icons", order = 10 },
    }

    if #sortedItems == 0 then
        args.emptyMsg = {
            type = "description",
            name = "No spells tracked yet. Add one above.",
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
            local spellName, spellIcon = GetSpellNameByID(spellId)
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

-- ==========================================================
-- BAR SETTINGS
-- ==========================================================

local function CreateBarSettings(barKey, barData)
    return {
        -- ==============================================
        -- TAB 1: General
        -- ==============================================
        general = {
            type        = "group",
            name        = "General",
            order       = 1,
            args        = {
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
                    width  = "normal",
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
                restrictionsHeader = { type = "header", name = "Restrictions", order = 10 },
                class = {
                    type   = "select",
                    name   = "Show for Class",
                    desc   = "Only show this bar when playing the selected class.",
                    values = L.CLASSES,
                    order  = 11,
                    width  = "normal",
                    get    = function() return barData.classRestriction or "NONE" end,
                    set    = function(_, val)
                        barData.classRestriction = val
                        NotifyAndRebuild(barKey)
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
                        if ns.AuraTracker and ns.AuraTracker.Controller then
                            ns.AuraTracker.Controller:DeleteBar(barKey)
                            if editState.selectedBar == barKey then
                                editState.selectedBar  = nil
                                editState.selectedAura = nil
                            end
                            NotifyChange()
                        end
                    end,
                },
            },
        },

        -- ==============================================
        -- TAB 2: Appearance
        -- ==============================================
        appearance = {
            type        = "group",
            name        = "Appearance",
            order       = 2,
            args        = {
                sizeHeader = { type = "header", name = "Size & Spacing", order = 1 },
                iconSize = {
                    type     = "range",
                    name     = "Icon Size",
                    min      = 10, max = 100, step = 1,
                    order    = 2,
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
                    order    = 3,
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
                    order    = 4,
                    width    = "double",
                    get      = function() return barData.scale or 1.0 end,
                    set      = function(_, val)
                        barData.scale = val
                        RebuildBar(barKey)
                    end,
                },
                textHeader = { type = "header", name = "Text", order = 10 },
                showCooldownText = {
                    type  = "toggle",
                    name  = "Show Cooldown Timer",
                    desc  = "Show remaining cooldown time as text on the icon.",
                    order = 11,
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
                    order    = 12,
                    width    = "double",
                    get      = function() return barData.textSize or 12 end,
                    set      = function(_, val)
                        barData.textSize = val
                        RebuildBar(barKey)
                    end,
                },
                textColor = {
                    type     = "color",
                    name     = "Text Color",
                    hasAlpha = true,
                    order    = 13,
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
            },
        },

        -- ==============================================
        -- TAB 3: Icons
        -- ==============================================
        icons = CreateIconListOptions(barKey, barData),
    }
end

-- ==========================================================
-- MAIN OPTIONS  &  BAR INJECTION
-- ==========================================================

function ns.GetAuraTrackerOptions()
    return {
        type        = "group",
        name        = "Aura Tracker",
        childGroups = "tree",
        args        = {
            -- Mappings page (always shown, even before any bars exist)
            mappings = ns.CreateMappingsOptions(),

            -- Parent group that holds all individual bar groups + new-bar creation
            bars = {
                type        = "group",
                name        = "Bars",
                order       = 10,
                childGroups = "tree",
                args        = {},
            },
        },
    }
end

-- Populates/refreshes bar groups in the options table.
function ns.UpdateBarOptions(options)
    if not options then return end
    options.args = options.args or {}

    options.args.bars = options.args.bars or {}
    options.args.bars.args = options.args.bars.args or {}

    if not (ns.AuraTracker and ns.AuraTracker.Controller) then
        options.args.bars.args = {}
        return options
    end

    local bars = ns.AuraTracker.Controller:GetBars()

    for key in pairs(options.args.bars.args) do
        options.args.bars.args[key] = nil
    end

    options.args.mappings = ns.CreateMappingsOptions()

    options.args.bars.args["__editMode"] = {
        type  = "execute",
        name  = "Toggle Move Bars",
        desc  = "Toggle edit mode to drag bars to new positions on screen.",
        order = -1,
        width = "normal",
        func  = function()
            if LibEditmode then
                LibEditmode:ToggleEditMode("AuraTracker")
            end
        end,
    }

    options.args.bars.args["__createBar"] = {
        type  = "input",
        name  = "New Bar ID  (press Enter)",
        desc  = "Enter a unique identifier (e.g. \"MyDebuffs\") and press Enter to create a new bar.",
        order = 0,
        width = "full",
        get   = function() return "" end,
        set   = function(_, val)
            if not (val and val ~= "") then return end
            if not (ns.AuraTracker and ns.AuraTracker.Controller) then
                print("|cFFFF0000Aura Tracker:|r Not initialized yet.")
                return
            end
            local existingBars = ns.AuraTracker.Controller:GetBars()
            if existingBars[val] then
                print("|cFFFF0000Aura Tracker:|r Bar '" .. val .. "' already exists.")
            else
                ns.AuraTracker.Controller:CreateBar(val)
                NotifyChange()
                print("|cFF00FF00Aura Tracker:|r Bar '" .. val .. "' created.")
            end
        end,
    }

    local order = 1
    for key, barData in pairs(bars) do
        if editState.selectedBar == key and not barData then
            editState.selectedBar  = nil
            editState.selectedAura = nil
        end
        options.args.bars.args[key] = {
            type        = "group",
            name        = GetBarDisplayName(barData, key),
            order       = order,
            childGroups = "tab",
            args        = CreateBarSettings(key, barData),
        }
        order = order + 1
    end

    return options
end

function ns.RefreshOptions()
    NotifyChange()
end

-- ==========================================================
-- SETTINGS PANEL SHIM
-- ==========================================================

local AceConfigDialog = LibStub("AceConfigDialog-3.0")

ns.AuraTracker = ns.AuraTracker or {}
ns.AuraTracker.SettingsPanel = {
    Show = function(self, barKey)
        AceConfigDialog:SetDefaultSize(addonName, 900, 650)
        AceConfigDialog:Open(addonName)
        local f = AceConfigDialog.OpenFrames and AceConfigDialog.OpenFrames[addonName]
        if f and f.frame then
            f.frame:SetMinResize(750, 550)
        end
        if barKey then
            AceConfigDialog:SelectGroup(addonName, "bars", barKey)
        end
    end,

    Hide = function(self)
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
