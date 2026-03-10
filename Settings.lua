local addonName, ns = ...

local pairs, ipairs, next = pairs, ipairs, next
local tonumber, tostring = tonumber, tostring
local table_insert, table_sort, table_remove = table.insert, table.sort, table.remove
local math_max, math_min, math_floor = math.max, math.min, math.floor
local string_format, string_upper = string.format, string.upper
local GetSpellInfo, GetItemInfo = GetSpellInfo, GetItemInfo

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
        ["cooldown"]      = "Cooldown",
        ["aura"]          = "Aura",
        ["item"]          = "Item",
        ["cooldown_aura"] = "Cooldown + Aura",
        ["internal_cd"]   = "Trinket ICD",
    },
    DUAL_DISPLAY_MODES = {
        ["always"]       = "Always Show",
        ["active_only"]  = "Show When Ready",
        ["missing_only"] = "Show When Unavailable",
    },
}

-- ==========================================================
-- SESSION STATE  (UI-only; not persisted)
-- ==========================================================

local editState = {
    selectedBar  = nil,
    selectedAura = nil,
}

-- ==========================================================
-- HELPERS
-- ==========================================================

local function GetSpellNameByID(spellId)
    local name, _, icon = GetSpellInfo(spellId)
    return name or "Unknown Spell", icon
end

local function GetItemNameByID(itemId)
    local name, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemId)
    return name or "Unknown Item", texture
end

local function GetTrackedNameAndIcon(id, trackType)
    if trackType == "item" or trackType == "internal_cd" then
        return GetItemNameByID(id)
    end
    return GetSpellNameByID(id)
end

local function GetTrackTypeLabel(trackType, filterKey)
    if trackType == "aura" then
        local src = filterKey and L.AURA_SOURCES[filterKey] or "aura"
        return "|cFFAAFFAA" .. src .. "|r"
    end
    if trackType == "item" then
        return "|cFFFFD700item|r"
    end
    if trackType == "internal_cd" then
        return "|cFFFF8800trinket ICD|r"
    end
    if trackType == "cooldown_aura" then
        local src = filterKey and L.AURA_SOURCES[filterKey] or "aura"
        return "|cFFAAD4FFcooldown|r + |cFFAAFFAA" .. src .. "|r"
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
-- TALENT LIST BUILDER  (delegates to Conditionals module)
-- ==========================================================

local function BuildTalentList()
    local Conditionals = ns.AuraTracker and ns.AuraTracker.Conditionals
    if Conditionals then
        return Conditionals:_BuildTalentList()
    end
    return {}
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
-- EXPORT SHARED UTILITIES
-- ==========================================================
-- These are used by IconEditorUI.lua and BarSettingsUI.lua
-- which load after this file.

ns.AuraTracker = ns.AuraTracker or {}
ns.AuraTracker.SettingsUtils = {
    L = L,
    editState = editState,
    NotifyChange = NotifyChange,
    NotifyAndRebuild = NotifyAndRebuild,
    RebuildBar = RebuildBar,
    GetSpellNameByID = GetSpellNameByID,
    GetItemNameByID = GetItemNameByID,
    GetTrackedNameAndIcon = GetTrackedNameAndIcon,
    GetTrackTypeLabel = GetTrackTypeLabel,
    GetFilterData = GetFilterData,
    NormalizeAuraOrders = NormalizeAuraOrders,
    MoveIconToPosition = MoveIconToPosition,
    GetBarDisplayName = GetBarDisplayName,
    BuildTalentList = BuildTalentList,
}

-- ==========================================================
-- MAIN OPTIONS  &  BAR INJECTION
-- ==========================================================

function ns.GetAuraTrackerOptions()
    return {
        type        = "group",
        name        = "Aura Tracker",
        childGroups = "tree",
        args        = {
            -- Introduction / How-to page
            introduction = {
                type  = "group",
                name  = "Introduction",
                order = 1,
                args  = {
                    welcome = {
                        type     = "description",
                        name     = "|cFF00CCFFAura Tracker|r lets you create moveable icon bars that track cooldowns, "
                            .. "auras (buffs/debuffs), and item cooldowns for any class.",
                        fontSize = "medium",
                        order    = 1,
                        width    = "full",
                    },

                    -- Getting Started
                    gettingStartedHeader = { type = "header", name = "Getting Started", order = 10 },
                    gettingStartedDesc = {
                        type  = "description",
                        order = 11,
                        width = "full",
                        name  = "1.  Open |cFFFFFF00Bars|r in the tree on the left and enter a name in "
                            .. "|cFFFFFF00New Bar ID|r to create a bar.\n"
                            .. "2.  Click |cFFFFFF00Toggle Movers|r to enter edit mode and drag bars "
                            .. "to the desired screen position.\n"
                            .. "3.  Drag spells or items from your spellbook / bags onto a bar to start "
                            .. "tracking them.\n"
                            .. "4.  Open a bar in the settings tree to fine-tune its appearance and icons.",
                    },

                    -- Drag & Drop
                    dragDropHeader = { type = "header", name = "Drag & Drop", order = 20 },
                    dragDropDesc = {
                        type  = "description",
                        order = 21,
                        width = "full",
                        name  = "|cFFAAD4FFNormal drag|r from the spellbook onto a bar "
                            .. "tracks the spell as a |cFFAAD4FFcooldown|r.\n\n"
                            .. "|cFFAAAAFFShift + drag|r from the spellbook onto a bar "
                            .. "tracks the spell as a |cFFAAFFAAtarget debuff aura|r instead.\n\n"
                            .. "|cFFFFD700Items|r can be dragged from your bags to track item cooldowns.\n\n"
                            .. "You can also drag aura buttons from the |cFFFFFFFFbuff/debuff frame|r "
                            .. "(or addon frames like ElvUI) directly onto a bar. "
                            .. "Hold |cFFAAAAFFShift|r while dragging an aura button to set its display "
                            .. "mode to |cFFAAAAFF\"Show When Missing\"|r.",
                    },

                    -- Icon Settings
                    iconSettingsHeader = { type = "header", name = "Per-Icon Settings", order = 40 },
                    iconSettingsDesc = {
                        type  = "description",
                        order = 41,
                        width = "full",
                        name  = "Click any icon in a bar's |cFFFFFF00Icons|r tab to open its inline editor. "
                            .. "From there you can:\n\n"
                            .. "• Change |cFFFFFF00Visibility|r (Always, Active Only, Missing Only).\n"
                            .. "• Set the |cFFFFFF00Aura Source|r (player/target/focus, buff/debuff).\n"
                            .. "• Toggle |cFFFFFF00Only Mine|r to track only your own auras.\n"
                            .. "• Enable |cFFFFFF00Show Snapshot Diff|r to see whether refreshing a DoT "
                            .. "now would increase or decrease its damage.\n"
                            .. "• Add |cFFFFFF00Also Track (Alternatives)|r spell IDs so one icon "
                            .. "covers an entire spell family (e.g. all Warlock curses).\n"
                            .. "• Reorder icons with the Move Left / Move Right buttons.",
                    },

                    -- Bar Settings
                    barSettingsHeader = { type = "header", name = "Bar Settings", order = 50 },
                    barSettingsDesc = {
                        type  = "description",
                        order = 51,
                        width = "full",
                        name  = "Each bar has two tabs:\n\n"
                            .. "|cFFFFFF00Bar Configuration|r – Bar name, layout direction, Ignore GCD toggle, "
                            .. "Show Only Known Spells, class restriction, icon size, spacing, scale, "
                            .. "font size, outline, and text color.\n\n"
                            .. "|cFFFFFF00Icons|r – Add or remove tracked spells/items and configure each icon.",
                    },

                    -- Tips
                    tipsHeader = { type = "header", name = "Tips", order = 60 },
                    tipsDesc = {
                        type  = "description",
                        order = 61,
                        width = "full",
                        name  = "• Use |cFFFFFF00/auratracker|r or |cFFFFFF00/at|r to open this settings panel.\n"
                            .. "• Bars are saved per-character. Each character can have different bars.\n"
                            .. "• The |cFFFFFF00Class Restriction|r option lets you share a profile between "
                            .. "characters while hiding class-specific bars on the wrong class.\n"
                            .. "• Enable |cFFFFFF00Show Only Known Spells|r to automatically hide icons "
                            .. "for spells your character hasn't learned yet.",
                    },
                },
            },

            -- Toggle edit mode (movers) at the top level for easy access
            toggleMovers = {
                type  = "execute",
                name  = "Toggle Movers",
                desc  = "Toggle edit mode to drag bars to new positions on screen.",
                order = 5,
                width = "normal",
                func  = function()
                    if LibEditmode then
                        LibEditmode:ToggleEditMode("AuraTracker")
                    end
                end,
            },

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

    -- CreateBarSettings is defined in BarSettingsUI.lua and exported at load time.
    local CreateBarSettings = ns.AuraTracker.CreateBarSettings

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
        else
            -- Expand the Bars group by default so users see their bars immediately
            AceConfigDialog:SelectGroup(addonName, "bars")
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
