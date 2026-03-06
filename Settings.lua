local addonName, ns = ...

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

-- Per-bar editing state: which icon is selected for editing
local editState = {
    selectedBar  = nil,
    selectedAura = nil,
}

-- Per-bar add-form state: what the user has chosen before submitting
local addState = {}

-- Mapping-page state
local mappingEditState = {
    selectedSpell = nil,
}

-- ==========================================================
-- HELPERS
-- ==========================================================

local function GetSpellNameByID(spellId)
    local name, _, icon = GetSpellInfo(spellId)
    return name or "Unknown Spell", icon
end

-- Returns a colored short label for displaying an icon's track type in a list row.
-- For auras, includes the filter key in human-readable form.
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

-- Module-level constant to avoid creating a new table on every getter call
local DEFAULT_TEXT_COLOR = { r = 1, g = 1, b = 1, a = 1 }

-- Looks up a filter-data table {unit, filter} from Config given a lowercase filterKey
-- (e.g. "target_debuff"). Returns nil if not found.
local function GetFilterData(filterKey)
    local Config = ns.AuraTracker and ns.AuraTracker.Config
    if not Config or not filterKey then return nil end
    return Config:GetAuraFilter(string.upper(filterKey))
end

-- ==========================================================
-- ICON ORDER HELPERS
-- ==========================================================

local function NormalizeAuraOrders(barData)
    if not barData.trackedItems then return end
    local sorted = {}
    for spellId, data in pairs(barData.trackedItems) do
        table.insert(sorted, { id = spellId, order = data.order or 999 })
    end
    table.sort(sorted, function(a, b) return a.order < b.order end)
    for i, item in ipairs(sorted) do
        barData.trackedItems[item.id].order = i
    end
end

local function SwapAuraOrder(barKey, barData, currentIndex, direction)
    if not barData then return end
    NormalizeAuraOrders(barData)
    local sorted = {}
    for spellId, data in pairs(barData.trackedItems) do
        table.insert(sorted, { spellId = spellId, order = data.order })
    end
    table.sort(sorted, function(a, b) return a.order < b.order end)
    if currentIndex < 1 or currentIndex > #sorted then return end
    local targetIndex = currentIndex + direction
    if targetIndex < 1 or targetIndex > #sorted then return end
    local itemA = sorted[currentIndex]
    local itemB = sorted[targetIndex]
    local temp = itemA.order
    barData.trackedItems[itemA.spellId].order = itemB.order
    barData.trackedItems[itemB.spellId].order = temp
    NotifyAndRebuild(barKey)
end

-- ==========================================================
-- ICON EDITOR (single-icon settings)
-- ==========================================================

local function CreateIconEditorOptions(barKey, barData, spellId)
    local data = barData.trackedItems[spellId]
    if not data then return nil end

    local name, icon = GetSpellNameByID(spellId)
    local isCooldown = (data.trackType == "cooldown")

    local args = {
        back = {
            type = "execute",
            name = "< Back to List",
            order = 0,
            func = function()
                editState.selectedAura = nil
                NotifyChange()
            end,
        },
        info = {
            type = "description",
            name = string.format("Configuring: |cFFFFFFFF%s|r  (ID: %d)", name, spellId),
            fontSize = "medium",
            order = 1,
        },
        iconPreview = {
            type = "description",
            name = "",
            image = icon,
            imageWidth = 32,
            imageHeight = 32,
            order = 2,
            width = "full",
        },
        displayMode = {
            type = "select",
            name = "Visibility",
            desc = "When should this icon be visible?",
            -- Use context-appropriate labels depending on track type
            values = isCooldown and L.COOLDOWN_DISPLAY_MODES or L.AURA_DISPLAY_MODES,
            order = 10,
            get = function() return data.displayMode or "always" end,
            set = function(_, val)
                data.displayMode = val
                NotifyAndRebuild(barKey)
            end,
        },
    }

    -- Aura-only: source (unit + buff/debuff) and optional aura-ID override
    if not isCooldown then
        args.auraSource = {
            type = "select",
            name = "Track From",
            desc = "Which unit and buff/debuff type to monitor.",
            values = L.AURA_SOURCES,
            order = 11,
            get = function() return data.type or "target_debuff" end,
            set = function(_, val)
                data.type = val
                -- Keep unit/filter in sync for runtime use
                local fd = GetFilterData(val)
                if fd then
                    data.unit   = fd.unit
                    data.filter = fd.filter
                end
                NotifyAndRebuild(barKey)
            end,
        }
        args.auraIdOverride = {
            type = "input",
            name = "Aura ID Override",
            desc = "Override which spell ID is scanned as the aura. Leave blank to use the same ID as the spell.",
            order = 12,
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

    args.delete = {
        type = "execute",
        name = "Remove from Bar",
        desc = "Stop tracking this spell on this bar.",
        order = 100,
        confirm = true,
        confirmText = "Remove " .. name .. " from this bar?",
        func = function()
            barData.trackedItems[spellId] = nil
            editState.selectedAura = nil
            NotifyAndRebuild(barKey)
        end,
    }

    return {
        type = "group",
        name = "Edit: " .. name,
        childGroups = "tab",
        args = args,
    }
end

-- ==========================================================
-- ICON LIST  (add + reorder + click-to-edit)
-- ==========================================================

local function CreateIconListOptions(barKey, barData)
    barData.trackedItems = barData.trackedItems or {}
    NormalizeAuraOrders(barData)

    -- If user clicked "Edit" on an icon, show the editor instead of the list
    if editState.selectedAura and barData.trackedItems[editState.selectedAura] then
        return CreateIconEditorOptions(barKey, barData, editState.selectedAura)
    end

    -- Build sorted list
    local sortedItems = {}
    for spellId, data in pairs(barData.trackedItems) do
        table.insert(sortedItems, { spellId = spellId, data = data, order = data.order or 999 })
    end
    table.sort(sortedItems, function(a, b) return a.order < b.order end)

    -- Per-bar add-form state. The `or` ensures the table is created once and then
    -- reused on every subsequent rebuild, preserving the user's last selection.
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

                local maxOrder = 0
                for _, d in pairs(barData.trackedItems) do
                    maxOrder = math.max(maxOrder, d.order or 0)
                end

                if st.trackType == "cooldown" then
                    barData.trackedItems[spellId] = {
                        order       = maxOrder + 1,
                        trackType   = "cooldown",
                        displayMode = "always",
                    }
                else
                    local fk = st.filterKey or "target_debuff"
                    local fd = GetFilterData(fk)
                    barData.trackedItems[spellId] = {
                        order       = maxOrder + 1,
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
        for i, item in ipairs(sortedItems) do
            local spellId     = item.spellId
            local isCooldown  = (item.data.trackType == "cooldown")
            local spellName, spellIcon = GetSpellNameByID(spellId)
            local typeLabel   = GetTrackTypeLabel(item.data.trackType, item.data.type)

            args["row_" .. spellId] = {
                type   = "group",
                name   = "",
                inline = true,
                order  = 20 + i,
                args   = {
                    up = {
                        type     = "execute",
                        name     = "▲",
                        width    = 0.1,
                        order    = 1,
                        disabled = (i == 1),
                        func     = function() SwapAuraOrder(barKey, barData, i, -1) end,
                    },
                    down = {
                        type     = "execute",
                        name     = "▼",
                        width    = 0.1,
                        order    = 2,
                        disabled = (i == #sortedItems),
                        func     = function() SwapAuraOrder(barKey, barData, i, 1) end,
                    },
                    edit = {
                        type        = "execute",
                        name        = spellName .. "  " .. typeLabel,
                        desc        = "Click to edit settings for this icon.",
                        image       = spellIcon,
                        imageWidth  = 24,
                        imageHeight = 24,
                        width       = "normal",
                        order       = 3,
                        func        = function()
                            editState.selectedAura = spellId
                            NotifyChange()
                        end,
                    },
                },
            }
        end
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
                talent = {
                    type  = "input",
                    name  = "Show with Talent",
                    desc  = "Only show this bar when the player has at least one rank in the named talent (exact name, case-sensitive). Leave blank for no restriction.",
                    order = 12,
                    width = "full",
                    get   = function() return tostring(barData.talentRestriction or "") end,
                    set   = function(_, val)
                        barData.talentRestriction = (val ~= "") and val or nil
                        NotifyAndRebuild(barKey)
                    end,
                },
                dangerHeader = { type = "header", name = "", order = 100 },
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
                        NotifyAndRebuild(barKey)
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
                        NotifyAndRebuild(barKey)
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
                        NotifyAndRebuild(barKey)
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
                        NotifyAndRebuild(barKey)
                    end,
                },
                textSize = {
                    type     = "range",
                    name     = "Font Size",
                    min      = 8, max = 32, step = 1,
                    order    = 12,
                    width    = "double",
                    get      = function() return barData.textSize end,
                    set      = function(_, val)
                        barData.textSize = val
                        NotifyAndRebuild(barKey)
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
                        NotifyAndRebuild(barKey)
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
-- GLOBAL MAPPINGS PAGE
-- ==========================================================

local function CreateMappingsOptions()
    local ctrl = ns.AuraTracker and ns.AuraTracker.Controller
    local db   = ctrl and ctrl:GetDB()
    if not db then return { type = "group", name = "Mappings", args = {} } end

    db.customMappings = db.customMappings or {}

    -- If user clicked to edit a mapping, show its editor inline
    if mappingEditState.selectedSpell then
        local spellId = mappingEditState.selectedSpell
        local m       = db.customMappings[spellId]
        if m then
            local spellName, spellIcon = GetSpellNameByID(spellId)
            return {
                type = "group",
                name = "Mappings",
                args = {
                    back = {
                        type  = "execute",
                        name  = "< Back to Mappings",
                        order = 0,
                        func  = function()
                            mappingEditState.selectedSpell = nil
                            NotifyChange()
                        end,
                    },
                    info = {
                        type     = "description",
                        name     = string.format("Mapping for |cFFFFFFFF%s|r  (Spell ID: %d)", spellName, spellId),
                        fontSize = "medium",
                        order    = 1,
                    },
                    iconPreview = {
                        type        = "description",
                        name        = "",
                        image       = spellIcon,
                        imageWidth  = 32,
                        imageHeight = 32,
                        order       = 2,
                        width       = "full",
                    },
                    trackType = {
                        type   = "select",
                        name   = "Default Action",
                        desc   = "What to do when this spell is dragged onto a bar.",
                        values = L.TRACK_TYPES,
                        order  = 10,
                        get    = function() return m.trackType or "cooldown" end,
                        set    = function(_, val)
                            m.trackType = val
                            NotifyChange()
                        end,
                    },
                    filterKey = {
                        type   = "select",
                        name   = "Aura Source",
                        desc   = "Which unit and buff/debuff type to monitor when tracking as aura.",
                        values = L.AURA_SOURCES,
                        order  = 11,
                        hidden = function() return m.trackType ~= "aura" end,
                        get    = function() return m.filterKey or "target_debuff" end,
                        set    = function(_, val)
                            m.filterKey = val
                            NotifyChange()
                        end,
                    },
                    auraId = {
                        type  = "input",
                        name  = "Aura ID Override",
                        desc  = "Override which spell ID is scanned as the aura. Leave blank to use the same ID.",
                        order = 12,
                        hidden = function() return m.trackType ~= "aura" end,
                        get   = function() return tostring(m.auraId or spellId) end,
                        set   = function(_, val)
                            local n = tonumber(val)
                            m.auraId = (n and n ~= spellId) and n or nil
                            NotifyChange()
                        end,
                    },
                    delete = {
                        type        = "execute",
                        name        = "Remove Mapping",
                        order       = 100,
                        confirm     = true,
                        confirmText = "Remove mapping for " .. spellName .. "?",
                        func        = function()
                            db.customMappings[spellId] = nil
                            mappingEditState.selectedSpell = nil
                            NotifyChange()
                        end,
                    },
                },
            }
        end
        -- mapping was deleted; fall through to list
        mappingEditState.selectedSpell = nil
    end

    -- Build the mapping list
    local args = {
        desc = {
            type     = "description",
            name     = "Spell mappings control what happens when a spell is dragged onto a bar.\n" ..
                       "Custom mappings override the built-in defaults.\n" ..
                       "Without a mapping: normal drag tracks the |cFFAAD4FFcooldown|r, " ..
                       "|cFFAAAAFFshift-drag|r tracks the aura.",
            order    = 1,
            width    = "full",
        },

        addHeader  = { type = "header", name = "Add Custom Mapping", order = 5 },
        addSpellId = {
            type  = "input",
            name  = "Spell ID  (press Enter to add)",
            desc  = "Adds a custom mapping for the given spell. You can then configure it.",
            order = 6,
            width = "full",
            get   = function() return "" end,
            set   = function(_, val)
                local spellId = tonumber(val)
                if not spellId then return end
                if db.customMappings[spellId] then
                    mappingEditState.selectedSpell = spellId
                    NotifyChange()
                    return
                end
                local spellName = GetSpellInfo(spellId)
                if not spellName then
                    print("|cFFFF0000Aura Tracker:|r Spell ID " .. spellId .. " not found.")
                    return
                end
                db.customMappings[spellId] = {
                    trackType = "cooldown",
                    filterKey = "target_debuff",
                }
                mappingEditState.selectedSpell = spellId
                NotifyChange()
            end,
        },

        customHeader = { type = "header", name = "Custom Mappings", order = 20 },
    }

    -- Custom mapping rows
    local hasMappings = false
    for spellId, m in pairs(db.customMappings) do
        hasMappings = true
        local spellName, spellIcon = GetSpellNameByID(spellId)
        local typeLabel = GetTrackTypeLabel(m.trackType, m.filterKey)

        args["mapping_" .. spellId] = {
            type   = "group",
            name   = "",
            inline = true,
            order  = 30 + spellId,
            args   = {
                icon = {
                    type        = "description",
                    name        = "",
                    image       = spellIcon,
                    imageWidth  = 20,
                    imageHeight = 20,
                    order       = 1,
                    width       = 0.18,
                },
                edit = {
                    type        = "execute",
                    name        = spellName .. "  →  " .. typeLabel,
                    desc        = "Click to edit this mapping.",
                    order       = 2,
                    width       = "normal",
                    func        = function()
                        mappingEditState.selectedSpell = spellId
                        NotifyChange()
                    end,
                },
                remove = {
                    type        = "execute",
                    name        = "✕",
                    desc        = "Remove this mapping.",
                    order       = 3,
                    width       = 0.18,
                    confirm     = true,
                    confirmText = "Remove mapping for " .. spellName .. "?",
                    func        = function()
                        db.customMappings[spellId] = nil
                        NotifyChange()
                    end,
                },
            },
        }
    end

    if not hasMappings then
        args.noMappings = {
            type  = "description",
            name  = "No custom mappings yet.",
            order = 21,
            width = "full",
        }
    end

    -- Built-in mappings (read-only display)
    local Config = ns.AuraTracker and ns.AuraTracker.Config
    if Config and next(Config.SpellToAuraMap) then
        args.builtinHeader = { type = "header", name = "Built-in Mappings (read only)", order = 50 }
        local i = 0
        for spellId, auraId in pairs(Config.SpellToAuraMap) do
            if auraId ~= spellId then
                i = i + 1
                local sName, sIcon = GetSpellNameByID(spellId)
                local aName        = GetSpellNameByID(auraId)
                args["builtin_" .. spellId] = {
                    type     = "description",
                    name     = string.format("|T%s:16:16|t |cFFFFFFFF%s|r  →  %s (aura)", sIcon or "", sName, aName),
                    order    = 51 + i,
                    width    = "full",
                }
            end
        end
    end

    return {
        type        = "group",
        name        = "Mappings",
        order       = 5,
        childGroups = "tree",
        args        = args,
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
            general = {
                type  = "group",
                name  = "General",
                order = 0,
                args  = {
                    intro = {
                        type     = "description",
                        name     = "Welcome to |cFF00BFFFAura Tracker|r.\n" ..
                                   "Select a bar on the left to configure it, or create a new one below.\n" ..
                                   "|cFFAAAAFF/auratracker|r or |cFFAAAAFF/at|r opens this panel.\n" ..
                                   "In Edit Mode, |cFFFFFF00right-click|r a bar to open its settings directly.",
                        fontSize = "medium",
                        order    = 1,
                    },
                    createBar = {
                        type  = "input",
                        name  = "New Bar ID  (press Enter)",
                        desc  = "Enter a unique identifier (e.g. \"MyDebuffs\") and press Enter to create a new bar.",
                        order = 2,
                        width = "full",
                        get   = function() return "" end,
                        set   = function(_, val)
                            if not (val and val ~= "") then return end
                            if not (ns.AuraTracker and ns.AuraTracker.Controller) then
                                print("|cFFFF0000Aura Tracker:|r Not initialized yet.")
                                return
                            end
                            local bars = ns.AuraTracker.Controller:GetBars()
                            if bars[val] then
                                print("|cFFFF0000Aura Tracker:|r Bar '" .. val .. "' already exists.")
                            else
                                ns.AuraTracker.Controller:CreateBar(val)
                                NotifyChange()
                                print("|cFF00FF00Aura Tracker:|r Bar '" .. val .. "' created.")
                            end
                        end,
                    },
                },
            },

            -- Mappings page (always shown, even before any bars exist)
            mappings = CreateMappingsOptions(),

            -- Parent group that holds all individual bar groups
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
-- Called each time the options are requested (via the AceConfig callback).
function ns.UpdateBarOptions(options)
    if not options then return end
    options.args = options.args or {}

    -- Ensure the Bars parent group and its args table always exist
    options.args.bars = options.args.bars or {}
    options.args.bars.args = options.args.bars.args or {}

    if not (ns.AuraTracker and ns.AuraTracker.Controller) then
        options.args.bars.args = {}
        return options
    end

    local bars = ns.AuraTracker.Controller:GetBars()

    -- Clear stale bar entries from the Bars sub-group
    for key in pairs(options.args.bars.args) do
        options.args.bars.args[key] = nil
    end

    -- Refresh mappings page (db may have changed)
    options.args.mappings = CreateMappingsOptions()

    -- Re-populate bar entries under the Bars parent group
    local order = 1
    for key, barData in pairs(bars) do
        if editState.selectedBar == key and not barData then
            editState.selectedBar  = nil
            editState.selectedAura = nil
        end
        options.args.bars.args[key] = {
            type        = "group",
            name        = barData.name or key,
            order       = order,
            childGroups = "tab",
            args        = CreateBarSettings(key, barData),
        }
        order = order + 1
    end

    return options
end

-- Convenience: trigger a full options refresh from anywhere
function ns.RefreshOptions()
    NotifyChange()
end

-- ==========================================================
-- SETTINGS PANEL SHIM
-- A lightweight object for other parts of the addon to use.
-- ==========================================================

local AceConfigDialog = LibStub("AceConfigDialog-3.0")

ns.AuraTracker = ns.AuraTracker or {}
ns.AuraTracker.SettingsPanel = {
    Show = function(self, barKey)
        AceConfigDialog:SetDefaultSize(addonName, 900, 650)
        AceConfigDialog:Open(addonName)
        -- Raise the minimum resize so child elements never overspill the frame
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
        for tab = 1, GetNumTalentTabs() do
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
