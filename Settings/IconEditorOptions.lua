local _, ns = ...

local SU = ns.AuraTracker.SettingsUtils

local pairs, ipairs = pairs, ipairs
local table_insert, table_sort = table.insert, table.sort
local string_format = string.format
local GetSpellInfo = GetSpellInfo

local L = SU.L
local editState = SU.editState

local function NotifyAndRebuild(barKey)
    SU.NotifyAndRebuild(barKey)
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

    -- Track type choices available for the add-icon form
    local ADD_TRACK_TYPE_VALUES = {
        ["cooldown"]      = "Cooldown",
        ["aura"]          = "Aura (Target Debuff)",
        ["player_buff"]   = "Aura (Player Buff)",
        ["target_buff"]   = "Aura (Target Buff)",
        ["cooldown_aura"] = "Cooldown + Aura (Target Debuff)",
        ["item"]          = "Item (use cooldown)",
    }

    local args = {
        -- ----------------------------------------------------------
        -- Add Icon section  (orders 1-9)
        -- ----------------------------------------------------------
        addHeader = {
            type  = "header",
            name  = "Add Icon",
            order = 1,
        },
        addDesc = {
            type  = "description",
            name  = "|cFFAAAAFFEnter a spell or item ID, choose a tracking type, then click Add.\n"
                .. "You can also drag spells or items from your spellbook / bags directly onto the bar.|r",
            order = 2,
            width = "full",
        },
        addTrackType = {
            type   = "select",
            name   = "Track Type",
            desc   = "How to track this spell or item.",
            values = ADD_TRACK_TYPE_VALUES,
            order  = 3,
            width  = "double",
            get    = function() return editState.addTrackType or "cooldown" end,
            set    = function(_, val)
                editState.addTrackType = val
                NotifyChange()
            end,
        },
        addIconId = {
            type  = "input",
            name  = "Spell / Item ID",
            desc  = "Enter the numeric spell ID (for cooldowns and auras) or item ID (for items).",
            order = 4,
            width = "double",
            get   = function() return editState.addIconId or "" end,
            set   = function(_, val) editState.addIconId = val end,
        },
        addIconBtn = {
            type  = "execute",
            name  = "Add",
            desc  = "Add this spell or item to the bar.",
            order = 5,
            width = "half",
            func  = function()
                local idStr = editState.addIconId or ""
                local id = tonumber(idStr)
                if not id or id <= 0 then
                    print("|cFFFF0000Aura Tracker:|r Please enter a valid spell or item ID.")
                    return
                end
                local ctrl = ns.AuraTracker and ns.AuraTracker.Controller
                if not ctrl then return end
                local trackType = editState.addTrackType or "cooldown"
                local ok, result
                if trackType == "cooldown" then
                    ok, result = ctrl:AddCooldown(barKey, id)
                elseif trackType == "item" then
                    ok, result = ctrl:AddItem(barKey, id)
                elseif trackType == "cooldown_aura" then
                    ok, result = ctrl:AddCooldownAura(barKey, id, "TARGET_DEBUFF")
                elseif trackType == "player_buff" then
                    ok, result = ctrl:AddAura(barKey, id, "PLAYER_BUFF")
                elseif trackType == "target_buff" then
                    ok, result = ctrl:AddAura(barKey, id, "TARGET_BUFF")
                else  -- "aura" → target debuff
                    ok, result = ctrl:AddAura(barKey, id, "TARGET_DEBUFF")
                end
                if ok then
                    editState.addIconId = ""
                    NotifyAndRebuild(barKey)
                else
                    print("|cFFFF0000Aura Tracker:|r " .. (result or "Failed to add icon."))
                end
            end,
        },

        -- ----------------------------------------------------------
        -- Tracked Icons list  (orders 10+)
        -- ----------------------------------------------------------
        listHeader = { type = "header", name = "Tracked Icons", order = 10 },
    }

    if #sortedItems == 0 then
        args.emptyMsg = {
            type  = "description",
            name  = "No icons tracked yet. Use the |cFFFFFF00Add Icon|r form above, or drag spells from your spellbook onto the bar.",
            order = 11,
            width = "full",
        }
    else
        args.listHint = {
            type  = "description",
            name  = "|cFFAAAAFFClick an icon to configure, reorder, or remove it.|r",
            order = 11,
            width = "full",
        }
        for i, item in ipairs(sortedItems) do
            local spellId          = item.spellId
            local spellName, spellIcon = GetTrackedNameAndIcon(spellId, item.data.trackType)
            local typeLabel        = GetTrackTypeLabel(item.data.trackType, item.data.type)

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

    -- If an icon is selected, inject the tabbed editor inline below the icon strip
    if editState.selectedAura and barData.trackedItems[editState.selectedAura] then
        InjectIconEditorArgs(args, barKey, barData, editState.selectedAura, 100)
    end

    -- childGroups="tab": non-group children (icon list, editor header)
    -- render above the tab control; group children (injected by
    -- InjectIconEditorArgs) become the General/Load/Action/Also Track tabs.
    return {
        type        = "group",
        name        = "Icons",
        childGroups = "tab",
        args        = args,
    }
end

-- Export for use by BarSettingsUI.lua
ns.AuraTracker.CreateIconListOptions = CreateIconListOptions
