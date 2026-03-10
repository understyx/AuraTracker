local addonName, ns = ...

local pairs, next = pairs, next
local tonumber, tostring = tonumber, tostring
local string_format = string.format
local GetSpellInfo = GetSpellInfo

-- ==========================================================
-- LOCAL CONSTANTS & HELPERS
-- ==========================================================

local TRACK_TYPES = {
    ["cooldown"]      = "Cooldown",
    ["aura"]          = "Aura",
    ["item"]          = "Item",
    ["cooldown_aura"] = "Cooldown + Aura",
}

local AURA_SOURCES = {
    ["player_buff"]   = "Player – Buff",
    ["player_debuff"] = "Player – Debuff",
    ["target_buff"]   = "Target – Buff",
    ["target_debuff"] = "Target – Debuff",
    ["focus_buff"]    = "Focus – Buff",
    ["focus_debuff"]  = "Focus – Debuff",
}

local function GetSpellNameByID(spellId)
    local name, _, icon = GetSpellInfo(spellId)
    return name or "Unknown Spell", icon
end

local function GetTrackTypeLabel(trackType, filterKey)
    if trackType == "aura" then
        local src = filterKey and AURA_SOURCES[filterKey] or "aura"
        return "|cFFAAFFAA" .. src .. "|r"
    end
    if trackType == "item" then
        return "|cFFFFD700item|r"
    end
    if trackType == "cooldown_aura" then
        local src = filterKey and AURA_SOURCES[filterKey] or "aura"
        return "|cFFAAD4FFcooldown|r + |cFFAAFFAA" .. src .. "|r"
    end
    return "|cFFAAD4FFcooldown|r"
end

local function NotifyChange()
    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
end

-- ==========================================================
-- SESSION STATE (UI-only; not persisted)
-- ==========================================================

local mappingEditState = {
    selectedSpell = nil,
}

-- ==========================================================
-- MAPPINGS OPTIONS
-- ==========================================================

function ns.CreateMappingsOptions()
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
                        name     = string_format("Mapping for |cFFFFFFFF%s|r  (Spell ID: %d)", spellName, spellId),
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
                        values = TRACK_TYPES,
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
                        values = AURA_SOURCES,
                        order  = 11,
                        hidden = function() return m.trackType ~= "aura" and m.trackType ~= "cooldown_aura" end,
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
                        hidden = function() return m.trackType ~= "aura" and m.trackType ~= "cooldown_aura" end,
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
                    name        = "x",
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
                    name     = string_format("|T%s:16:16|t |cFFFFFFFF%s|r  →  %s (aura)", sIcon or "", sName, aName),
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
