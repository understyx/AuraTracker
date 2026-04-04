local _, ns = ...

local SU = ns.AuraTracker.SettingsUtils
local L = SU.L
local editState = SU.editState
local pairs, ipairs, next = pairs, ipairs, next
local tonumber, tostring = tonumber, tostring
local table_insert, table_sort, table_remove = table.insert, table.sort, table.remove
local math_max, math_min, math_floor = math.max, math.min, math.floor
local string_format, string_upper = string.format, string.upper
local GetSpellInfo, GetItemInfo = GetSpellInfo, GetItemInfo
local GetInventoryItemTexture = GetInventoryItemTexture

local LibEditmode = LibStub("LibEditmode-1.0", true)

local function NotifyChange() SU.NotifyChange() end
local function NotifyAndRebuild(barKey) SU.NotifyAndRebuild(barKey) end
local function RebuildBar(barKey) SU.RebuildBar(barKey) end
local function GetClassGroupKey(cr) return SU.GetClassGroupKey(cr) end
local function GetClassGroupName(ck) return SU.GetClassGroupName(ck) end
local function GetBarDisplayName(barKey, barData) return SU.GetBarDisplayName(barKey, barData) end
local function GetSpellNameByID(spellId) return SU.GetSpellNameByID(spellId) end
local function GetItemNameByID(itemId) return SU.GetItemNameByID(itemId) end
local function GetTrackedNameAndIcon(id, trackType) return SU.GetTrackedNameAndIcon(id, trackType) end
local function GetTrackTypeLabel(trackType, filterKey) return SU.GetTrackTypeLabel(trackType, filterKey) end
local function GetFilterData(filterKey) return SU.GetFilterData(filterKey) end
local function BuildTalentList() return SU.BuildTalentList() end

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
                            .. "Special spells with a built-in mapping (e.g. |cFFAAFFAAIcy Touch|r → Frost Fever, "
                            .. "|cFFAAFFAAPlague Strike|r → Blood Plague) automatically track the disease aura "
                            .. "when |cFFAAAAFFshift-dragged|r.\n\n"
                            .. "|cFFAAFF88Shaman weapon imbue|r spells (Windfury Weapon, Flametongue Weapon, etc.) "
                            .. "are automatically tracked as player buffs when dragged.\n\n"
                            .. "|cFFFFD700Items|r can be dragged from your bags. "
                            .. "|cFFAAFF88Sharpening stones and other temp-enchant items|r track the weapon "
                            .. "enchant duration; other items track their use cooldown.\n\n"
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
                            .. "The editor is split into sub-tabs:\n\n"
                            .. "|cFFFFFF00General|r – Change |cFFFFFF00Visibility|r (Always, Active Only, Missing Only), "
                            .. "set the |cFFFFFF00Aura Source|r (player/target/focus, buff/debuff), "
                            .. "toggle |cFFFFFF00Only Mine|r to track only your own auras, "
                            .. "enable |cFFFFFF00Show Snapshot Diff|r to see whether refreshing a DoT "
                            .. "now would increase or decrease its damage, "
                            .. "and reorder icons with the Move Left / Move Right buttons.\n\n"
                            .. "|cFFFFFF00Load|r – Add conditions that control when this icon is shown "
                            .. "(e.g. only above a certain HP, only in combat).\n\n"
                            .. "|cFFFFFF00Action|r – Add conditional effects such as a pulsing glow or "
                            .. "sound alert when a threshold is crossed.\n\n"
                            .. "|cFFFFFF00Also Track|r – Add alternative spell IDs so one icon covers an "
                            .. "entire spell family (e.g. all Warlock curses). Available for aura icons only.",
                    },

                    -- Bar Settings
                    barSettingsHeader = { type = "header", name = "Bar Settings", order = 50 },
                    barSettingsDesc = {
                        type  = "description",
                        order = 51,
                        width = "full",
                        name  = "Each bar has two top-level tabs:\n\n"
                            .. "|cFFFFFF00Bar Configuration|r – Split into two sub-tabs:\n"
                            .. "  • |cFFFFFF00General|r – Bar name, layout direction, Ignore GCD, Show Only Known Spells, "
                            .. "icon size, spacing, scale, font size, outline, and text color.\n"
                            .. "  • |cFFFFFF00Load|r – Class restriction, talent requirements, and load conditions "
                            .. "that control when the bar is shown (e.g. only in combat, only in a group).\n\n"
                            .. "|cFFFFFF00Icons|r – Lists all tracked icons. Click an icon to open its inline editor, "
                            .. "which has up to four sub-tabs:\n"
                            .. "  • |cFFFFFF00General|r – Visibility mode, aura source, Only Mine, Snapshot Diff, and reorder controls.\n"
                            .. "  • |cFFFFFF00Load|r – Conditions controlling when this icon is shown.\n"
                            .. "  • |cFFFFFF00Action|r – Conditional effects (glow, sound) triggered during play.\n"
                            .. "  • |cFFFFFF00Also Track|r – Alternative spell IDs for aura icons (shown for aura/cooldown+aura only).",
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

            -- Import a bar from a previously exported string
            importBar = {
                type        = "group",
                name        = "Import Bar",
                order       = 7,
                childGroups = "tab",
                args        = {
                    desc = {
                        type  = "description",
                        name  = "Paste an export string below to create a new bar from it.\n"
                            .. "Export strings start with |cFFFFFF00ATv1:|r and are generated from "
                            .. "the |cFFFFFF00Export|r button on any bar's General settings tab.",
                        order = 1,
                        width = "full",
                    },
                    importString = {
                        type  = "input",
                        name  = "Import String  (paste here, then press Enter)",
                        desc  = "Paste the ATv1: export string here and press Enter to import the bar.",
                        order = 2,
                        width = "full",
                        multiline = false,
                        get   = function() return "" end,
                        set   = function(_, val)
                            if not val or val == "" then return end
                            local ctrl = ns.AuraTracker and ns.AuraTracker.Controller
                            if not ctrl then return end
                            local ok, result = ctrl:ImportBar(val, nil)
                            if ok then
                                NotifyChange()
                                print("|cFF00FF00Aura Tracker:|r Bar imported as '" .. result .. "'.")
                            else
                                print("|cFFFF0000Aura Tracker:|r Import failed: " .. (result or "unknown error"))
                            end
                        end,
                    },
                },
            },

            -- Example bars for common class configurations
            exampleBars = {
                type        = "group",
                name        = "Example Bars",
                order       = 8,
                childGroups = "tree",
                args        = (function()
                    local args = {
                        desc = {
                            type  = "description",
                            name  = "Click |cFFFFFF00Import|r next to any example to add it as a new bar. "
                                .. "You can then rename and customise it in the |cFFFFFF00Bars|r section.",
                            order = 1,
                            width = "full",
                        },
                    }
                    local Config = ns.AuraTracker and ns.AuraTracker.Config
                    if Config and Config.ExampleBars then
                        local L_CLASSES = {
                            ["NONE"] = "Any Class",
                            ["WARRIOR"] = "Warrior", ["PALADIN"] = "Paladin",
                            ["HUNTER"] = "Hunter",   ["ROGUE"] = "Rogue",
                            ["PRIEST"] = "Priest",   ["DEATHKNIGHT"] = "Death Knight",
                            ["SHAMAN"] = "Shaman",   ["MAGE"] = "Mage",
                            ["WARLOCK"] = "Warlock", ["DRUID"] = "Druid",
                        }
                        -- Desired display order for class groups
                        local CLASS_DISPLAY_ORDER = {
                            "NONE", "DEATHKNIGHT", "DRUID", "HUNTER", "MAGE",
                            "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
                        }
                        local CLASS_ORDER_INDEX = {}
                        for i, k in ipairs(CLASS_DISPLAY_ORDER) do
                            CLASS_ORDER_INDEX[k] = i
                        end

                        -- Group examples by class, preserving insertion order within each group
                        local byClass = {}
                        local classKeys = {}
                        for idx, example in ipairs(Config.ExampleBars) do
                            local classKey = example.class or "NONE"
                            if not byClass[classKey] then
                                byClass[classKey] = {}
                                table_insert(classKeys, classKey)
                            end
                            table_insert(byClass[classKey], { idx = idx, example = example })
                        end

                        -- Sort class keys by the canonical display order
                        table_sort(classKeys, function(a, b)
                            local ia = CLASS_ORDER_INDEX[a] or 99
                            local ib = CLASS_ORDER_INDEX[b] or 99
                            return ia < ib
                        end)

                        -- Build one collapsible tree group per class
                        for classGroupOrder, classKey in ipairs(classKeys) do
                            local examples  = byClass[classKey]
                            local classLabel = L_CLASSES[classKey] or classKey

                            -- Apply RAID_CLASS_COLORS when available
                            local classGroupName = classLabel
                            if classKey ~= "NONE" then
                                local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classKey]
                                if color then
                                    local hex = string_format("%02X%02X%02X",
                                        math_floor((color.r or 0) * 255),
                                        math_floor((color.g or 0) * 255),
                                        math_floor((color.b or 0) * 255))
                                    classGroupName = "|cFF" .. hex .. classLabel .. "|r"
                                end
                            end

                            local classArgs = {}
                            for exOrder, entry in ipairs(examples) do
                                local i       = entry.idx
                                local example = entry.example
                                classArgs["example_" .. i] = {
                                    type   = "group",
                                    name   = "",
                                    inline = true,
                                    order  = exOrder,
                                    args   = {
                                        info = {
                                            type  = "description",
                                            name  = string_format(
                                                "|cFFFFFFFF%s|r\n|cFFAAAAAA%s|r",
                                                example.name or "Example " .. i,
                                                example.desc or ""),
                                            order = 1,
                                            width = "double",
                                        },
                                        importBtn = {
                                            type  = "execute",
                                            name  = "Import",
                                            desc  = "Create a new bar based on this example.",
                                            order = 2,
                                            width = "half",
                                            func  = function()
                                                local ctrl = ns.AuraTracker and ns.AuraTracker.Controller
                                                if not ctrl then return end
                                                local ok, result = ctrl:ImportExampleBar(i, nil)
                                                if ok then
                                                    NotifyChange()
                                                    print("|cFF00FF00Aura Tracker:|r Example bar imported as '" .. result .. "'.")
                                                else
                                                    print("|cFFFF0000Aura Tracker:|r Import failed: " .. (result or ""))
                                                end
                                            end,
                                        },
                                    },
                                }
                            end

                            args["class_" .. classKey] = {
                                type  = "group",
                                name  = classGroupName,
                                order = 10 + classGroupOrder,
                                args  = classArgs,
                            }
                        end
                    end
                    return args
                end)(),
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

    -- CreateBarSettings is defined in BarSettingsUI.lua, which loads after this
    -- file. It's safe to access here because UpdateBarOptions runs at runtime
    -- (when the options panel opens), not at parse time.
    local CreateBarSettings = ns.AuraTracker.CreateBarSettings

    -- Group bars by class restriction into collapsible tree nodes.
    local classBuckets = {}  -- classKey -> list of { key, barData }
    local classOrder   = {}  -- ordered unique class keys

    for key, barData in pairs(bars) do
        if editState.selectedBar == key and not barData then
            editState.selectedBar  = nil
            editState.selectedAura = nil
        end
        local classKey = GetClassGroupKey(barData.classRestriction)
        if not classBuckets[classKey] then
            classBuckets[classKey] = {}
            table_insert(classOrder, classKey)
        end
        table_insert(classBuckets[classKey], { key = key, barData = barData })
    end

    -- Sort: "NONE" (Any Class) first, then other classes alphabetically.
    table_sort(classOrder, function(a, b)
        if a == "NONE" then return true end
        if b == "NONE" then return false end
        return a < b
    end)

    local groupOrder = 1
    for _, classKey in ipairs(classOrder) do
        local bucket = classBuckets[classKey]

        -- Sort bars within each group by display name.
        table_sort(bucket, function(a, b)
            return (a.barData.name or a.key) < (b.barData.name or b.key)
        end)

        -- Build the class group label.
        local groupName = GetClassGroupName(classKey)

        -- Build child bar entries for this class group.
        local groupArgs = {}
        for i, entry in ipairs(bucket) do
            groupArgs[entry.key] = {
                type        = "group",
                name        = entry.barData.name or entry.key,
                order       = i,
                childGroups = "tab",
                args        = CreateBarSettings(entry.key, entry.barData),
            }
        end

        options.args.bars.args["class_" .. classKey] = {
            type        = "group",
            name        = groupName,
            order       = groupOrder,
            childGroups = "tree",
            args        = groupArgs,
        }
        groupOrder = groupOrder + 1
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

        -- Pre-expand "Any Class" and the player's own class group so bars are
        -- immediately visible in the tree without any manual clicking.
        -- AceConfigDialog stores tree-node expansion in:
        --   GetStatusTable(app).groups.groups["<parentKey>\001<childKey>"] = true
        -- We seed this BEFORE Open() so the first render is already correct.
        do
            local rootStatus = AceConfigDialog:GetStatusTable(addonName)
            rootStatus.groups = rootStatus.groups or {}
            rootStatus.groups.groups = rootStatus.groups.groups or {}
            local tg = rootStatus.groups.groups
            tg["bars"] = true
            tg["bars\001class_NONE"] = true
            local _, playerClass = UnitClass("player")
            if playerClass then
                tg["bars\001class_" .. playerClass] = true
            end
        end

        AceConfigDialog:Open(addonName)
        local f = AceConfigDialog.OpenFrames and AceConfigDialog.OpenFrames[addonName]
        if f and f.frame then
            f.frame:SetMinResize(750, 550)
        end
        if barKey then
            -- Bars are now nested under class group nodes.  Resolve the
            -- correct class group key so SelectGroup navigates straight to
            -- the bar's settings page.
            local classGroupKey = "class_NONE"
            local found = false
            if ns.AuraTracker and ns.AuraTracker.Controller then
                local allBars = ns.AuraTracker.Controller:GetBars()
                local barData = allBars and allBars[barKey]
                if barData then
                    classGroupKey = "class_" .. GetClassGroupKey(barData.classRestriction)
                    found = true
                end
            end
            if found then
                AceConfigDialog:SelectGroup(addonName, "bars", classGroupKey, barKey)
            else
                AceConfigDialog:SelectGroup(addonName, "bars")
            end
        else
            -- Navigate to the bars section; the pre-expanded groups will be visible.
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
