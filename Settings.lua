local addonName, ns = ...

-- ==========================================================
-- CONSTANTS & HELPERS (WOTLK 3.3.5 Compatible)
-- ==========================================================

local L = {
    CLASSES = {
        ["NONE"] = "Any Class",
        ["WARRIOR"] = "Warrior", ["PALADIN"] = "Paladin", ["HUNTER"] = "Hunter",
        ["ROGUE"] = "Rogue", ["PRIEST"] = "Priest", ["DEATHKNIGHT"] = "Death Knight",
        ["SHAMAN"] = "Shaman", ["MAGE"] = "Mage", ["WARLOCK"] = "Warlock",
        ["DRUID"] = "Druid",
    },
    FILTERS = {
        ["HELPFUL"] = "Buffs",
        ["HARMFUL"] = "Debuffs",
        ["NONE"] = "Both",
    },
    UNITS = {
        ["target"] = "Target",
        ["player"] = "Player",
        ["pet"] = "Pet",
        ["focus"] = "Focus",
    },
    DISPLAY_MODES = {
        ["always"] = "Always Show",
        ["active_only"] = "Show When Active",
        ["missing_only"] = "Show When Missing",
    }
}

-- Session state for editing specific auras (UI State only)
local editState = {
    selectedBar = nil,
    selectedAura = nil,
}

local function GetSpellNameByID(spellId)
    -- WOTLK API: GetSpellInfo returns name, rank, icon
    local name, _, icon = GetSpellInfo(spellId)
    return name or "Unknown Spell", icon
end

-- ==========================================================
-- LOGIC: AURA MANAGEMENT
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

    -- Swap orders
    local temp = itemA.order
    barData.trackedItems[itemA.spellId].order = itemB.order
    barData.trackedItems[itemB.spellId].order = temp

    -- Refresh UI
    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
    if ns.AuraTracker and ns.AuraTracker.Controller then
        ns.AuraTracker.Controller:RebuildBar(barKey)
    end
end

-- ==========================================================
-- OPTIONS: AURA EDITOR (SUB-GROUP)
-- ==========================================================

local function CreateAuraEditorOptions(barKey, barData, spellId)
    local data = barData.trackedItems[spellId]
    if not data then return nil end

    local name, icon = GetSpellNameByID(spellId)

    return {
        type = "group",
        name = "Edit: " .. name,
        childGroups = "tab",
        args = {
            back = {
                type = "execute",
                name = "< Back to List",
                order = 0,
                func = function() editState.selectedAura = nil end,
            },
            info = {
                type = "description",
                name = string.format("Configuring: |cFFFFFFFF%s|r (ID: %d)", name, spellId),
                fontSize = "medium",
                order = 1,
            },
            iconPreview = {
                type = "description",
                name = "",
                image = icon,
                imageWidth = 32,
                imageHeight = 32,
                order = 1,
                width = "full",
            },
            displayMode = {
                type = "select",
                name = "Visibility",
                desc = "When should this icon appear?",
                values = L.DISPLAY_MODES,
                order = 10,
                get = function() return data.displayMode end,
                set = function(_, val) 
                    data.displayMode = val 
                    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
                end,
            },
            unit = {
                type = "select",
                name = "Unit",
                desc = "Which unit to track this aura on.",
                values = L.UNITS,
                order = 11,
                get = function() return data.unit end,
                set = function(_, val) 
                    data.unit = val 
                    if ns.AuraTracker and ns.AuraTracker.Controller then
                        ns.AuraTracker.Controller:RebuildBar(barKey)
                    end
                end,
            },
            filter = {
                type = "select",
                name = "Aura Type",
                desc = "Buff, Debuff, or Both.",
                values = L.FILTERS,
                order = 12,
                get = function() return data.filter end,
                set = function(_, val) 
                    data.filter = val 
                    if ns.AuraTracker and ns.AuraTracker.Controller then
                        ns.AuraTracker.Controller:RebuildBar(barKey)
                    end
                end,
            },
            delete = {
                type = "execute",
                name = "Remove Aura",
                desc = "Stop tracking this spell on this bar.",
                order = 100,
                confirm = true,
                confirmText = "Are you sure you want to remove " .. name .. "?",
                func = function()
                    barData.trackedItems[spellId] = nil
                    editState.selectedAura = nil
                    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
                    if ns.AuraTracker and ns.AuraTracker.Controller then
                        ns.AuraTracker.Controller:RebuildBar(barKey)
                    end
                end,
            }
        }
    }
end

-- ==========================================================
-- OPTIONS: AURA LIST (MANAGEMENT)
-- ==========================================================

local function CreateAuraListOptions(barKey, barData)
    -- Ensure orders are normalized before drawing
    NormalizeAuraOrders(barData)

    local sortedItems = {}
    for spellId, data in pairs(barData.trackedItems) do
        table.insert(sortedItems, { spellId = spellId, data = data, order = data.order or 999 })
    end
    table.sort(sortedItems, function(a, b) return a.order < b.order end)

    local args = {
        addHeader = { type = "header", name = "Add New Aura", order = 1 },
        addAura = {
            type = "input",
            name = "Spell ID",
            desc = "Enter the Spell ID to track.",
            order = 2,
            width = "half",
            set = function(_, val)
                local spellId = tonumber(val)
                if spellId then
                    if barData.trackedItems[spellId] then
                        print("|cFFFF0000Aura Tracker:|r This spell is already on this bar.")
                        return
                    end
                    local name = GetSpellInfo(spellId)
                    if not name then
                        print("|cFFFF0000Aura Tracker:|r Invalid Spell ID.")
                        return
                    end

                    barData.trackedItems[spellId] = {
                        auraId = spellId,
                        order = #sortedItems + 1,
                        displayMode = "active_only",
                        unit = "target",
                        filter = "HARMFUL",
                    }
                    editState.selectedAura = spellId -- Auto-select new item for editing
                    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
                    if ns.AuraTracker and ns.AuraTracker.Controller then
                        ns.AuraTracker.Controller:RebuildBar(barKey)
                    end
                end
            end,
        },
        listHeader = { type = "header", name = "Tracked Auras", order = 10 },
    }

    if #sortedItems == 0 then
        args.emptyMsg = {
            type = "description",
            name = "No auras tracked yet. Add one above.",
            order = 11,
            width = "full",
        }
    else
        for i, item in ipairs(sortedItems) do
            local spellId = item.spellId
            local name, icon = GetSpellNameByID(spellId)
            local isEditing = (editState.selectedAura == spellId)

            -- If we are editing this specific aura, return the Editor Options instead of the list row
            if isEditing then
                return CreateAuraEditorOptions(barKey, barData, spellId)
            end

            -- Otherwise, render a compact row
            args["row_" .. spellId] = {
                type = "group",
                name = "",
                inline = true,
                order = 20 + i,
                args = {
                    up = {
                        type = "execute",
                        name = "▲",
                        width = 0.1,
                        order = 1,
                        disabled = (i == 1),
                        func = function() SwapAuraOrder(barKey, barData, i, -1) end,
                    },
                    down = {
                        type = "execute",
                        name = "▼",
                        width = 0.1,
                        order = 2,
                        disabled = (i == #sortedItems),
                        func = function() SwapAuraOrder(barKey, barData, i, 1) end,
                    },
                    edit = {
                        type = "execute",
                        name = name,
                        desc = "Click to configure settings.",
                        image = icon,
                        imageWidth = 24,
                        imageHeight = 24,
                        width = "normal",
                        order = 3,
                        func = function() editState.selectedAura = spellId end,
                    },
                }
            }
        end
    end

    return {
        type = "group",
        name = "Auras",
        childGroups = "tree", 
        args = args,
    }
end

-- ==========================================================
-- OPTIONS: BAR SETTINGS
-- ==========================================================

local function CreateBarSettings(barKey, barData)
    return {
        name = {
            type = "input",
            name = "Bar Name",
            desc = "Internal ID and Display Name.",
            order = 1,
            width = "full",
            get = function() return barData.name end,
            set = function(_, val) 
                barData.name = val 
                LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
            end,
        },
        dimensions = {
            type = "group",
            name = "Dimensions",
            inline = true,
            order = 2,
            args = {
                iconSize = {
                    type = "range",
                    name = "Icon Size",
                    min = 10, max = 100, step = 1,
                    width = "half",
                    get = function() return barData.iconSize end,
                    set = function(_, val) 
                        barData.iconSize = val
                        if ns.AuraTracker and ns.AuraTracker.Controller then
                            ns.AuraTracker.Controller:RebuildBar(barKey)
                        end
                    end,
                },
                spacing = {
                    type = "range",
                    name = "Spacing",
                    min = 0, max = 50, step = 1,
                    width = "half",
                    get = function() return barData.spacing end,
                    set = function(_, val) 
                        barData.spacing = val
                        if ns.AuraTracker and ns.AuraTracker.Controller then
                            ns.AuraTracker.Controller:RebuildBar(barKey)
                        end
                    end,
                },
            }
        },
        text = {
            type = "group",
            name = "Text",
            inline = true,
            order = 3,
            args = {
                textSize = {
                    type = "range",
                    name = "Size",
                    min = 8, max = 32, step = 1,
                    width = "half",
                    get = function() return barData.textSize end,
                    set = function(_, val) 
                        barData.textSize = val
                        if ns.AuraTracker and ns.AuraTracker.Controller then
                            ns.AuraTracker.Controller:RebuildBar(barKey)
                        end
                    end,
                },
                textColor = {
                    type = "color",
                    name = "Color",
                    hasAlpha = true,
                    width = "half",
                    get = function()
                        local c = barData.textColor
                        return c.r, c.g, c.b, c.a
                    end,
                    set = function(_, r, g, b, a)
                        barData.textColor.r = r
                        barData.textColor.g = g
                        barData.textColor.b = b
                        barData.textColor.a = a
                        if ns.AuraTracker and ns.AuraTracker.Controller then
                            ns.AuraTracker.Controller:RebuildBar(barKey)
                        end
                    end,
                },
            }
        },
        restrictions = {
            type = "group",
            name = "Restrictions",
            inline = true,
            order = 4,
            args = {
                talent = {
                    type = "input",
                    name = "Talent Req",
                    desc = "Talent name required to show bar (Optional).",
                    width = "full",
                    get = function() return tostring(barData.talentRestriction or "") end,
                    set = function(_, val) barData.talentRestriction = val end,
                },
                class = {
                    type = "select",
                    name = "Class Req",
                    values = L.CLASSES,
                    width = "full",
                    get = function() return barData.classRestriction or "NONE" end,
                    set = function(_, val) barData.classRestriction = val end,
                }
            }
        },
        -- The Aura List is injected here as a sub-group
        auraManagement = CreateAuraListOptions(barKey, barData),
        
        deleteBar = {
            type = "execute",
            name = "Delete Entire Bar",
            desc = "Removes this bar and all tracked auras.",
            order = 100,
            confirm = true,
            confirmText = "Delete this bar permanently?",
            func = function()
                if ns.AuraTracker and ns.AuraTracker.Controller then
                    ns.AuraTracker.Controller:DeleteBar(barKey)
                    -- Reset edit state if we deleted the selected bar
                    if editState.selectedBar == barKey then
                        editState.selectedBar = nil
                        editState.selectedAura = nil
                    end
                    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
                end
            end,
        }
    }
end

-- ==========================================================
-- MAIN OPTIONS STRUCTURE & UPDATE FUNCTION
-- ==========================================================

function ns.GetAuraTrackerOptions()
    local options = {
        type = "group",
        name = "Aura Tracker",
        childGroups = "tree", 
        args = {
            general = {
                type = "group",
                name = "General",
                order = 0,
                args = {
                    intro = {
                        type = "description",
                        name = "Welcome to Aura Tracker.\nSelect a bar from the left to configure it, or create a new one below.",
                        fontSize = "medium",
                        order = 1,
                    },
                    createBar = {
                        type = "input",
                        name = "New Bar ID",
                        desc = "Enter a unique ID (e.g., 'MyBuffs') and press Enter.",
                        order = 2,
                        width = "full",
                        set = function(_, val)
                            if val and val ~= "" then
                                -- Safety check for initialization
                                if not ns.AuraTracker or not ns.AuraTracker.Controller then
                                    print("|cFFFF0000Aura Tracker:|r System not initialized yet.")
                                    return
                                end

                                local bars = ns.AuraTracker.Controller:GetBars()
                                if bars[val] then
                                    print("|cFFFF0000Aura Tracker:|r Bar '" .. val .. "' already exists.")
                                else
                                    ns.AuraTracker.Controller:CreateBar(val)
                                    -- Force refresh of options table
                                    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
                                    print("|cFF00FF00Aura Tracker:|r Bar '" .. val .. "' created.")
                                end
                            end
                        end,
                    },
                }
            }
            -- Bars will be injected here by UpdateBarOptions
        }
    }
    return options
end

-- This is the function you requested. It populates the options table dynamically.
-- Call this after your DB/Controller is initialized, or whenever bars change.
function ns.UpdateBarOptions(options)
    if not options then return end
    if not options.args then options.args = {} end

    -- Safety Check: If Controller isn't ready, clear bars and return
    if not ns.AuraTracker or not ns.AuraTracker.Controller then
        -- Clean up existing bar args to avoid showing stale data
        for key in pairs(options.args) do
            if key ~= "general" then
                options.args[key] = nil
            end
        end
        return options
    end

    local bars = ns.AuraTracker.Controller:GetBars()
    
    -- 1. Clear old bar entries (except 'general') to prevent duplicates
    for key in pairs(options.args) do
        if key ~= "general" then
            options.args[key] = nil
        end
    end

    -- 2. Populate new bar entries
    local order = 10
    for key, barData in pairs(bars) do
        -- Reset edit state if the selected bar no longer exists
        if editState.selectedBar == key and not barData then
            editState.selectedBar = nil
            editState.selectedAura = nil
        end

        options.args[key] = {
            type = "group",
            name = barData.name or key,
            order = order,
            childGroups = "tab", -- Inside a bar, use tabs (Settings vs Auras)
            args = CreateBarSettings(key, barData),
        }
        order = order + 1
    end

    return options
end

-- Helper function to refresh options easily from elsewhere in your code
function ns.RefreshOptions()
    local options = ns.GetAuraTrackerOptions()
    ns.UpdateBarOptions(options)
    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
end