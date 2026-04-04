local _, ns = ...

local Conditionals = ns.AuraTracker.Conditionals
local _H = ns.AuraTracker._ConditionUIHelpers

local LSM = LibStub("LibSharedMedia-3.0")
local PlaySoundFile = PlaySoundFile
local GetSpellInfo = GetSpellInfo
local tonumber, tostring = tonumber, tostring

-- Import helpers
local GetTristateCondValue = _H.GetTristateCondValue
local SetTristateCondValue = _H.SetTristateCondValue
local GetGlyphTristate = _H.GetGlyphTristate
local SetGlyphTristate = _H.SetGlyphTristate
local GetGlyphSpellId = _H.GetGlyphSpellId
local GetBarAuraState = _H.GetBarAuraState
local SetBarAuraState = _H.SetBarAuraState
local GetBarAuraSpellId = _H.GetBarAuraSpellId
local GetBarAuraUnit = _H.GetBarAuraUnit
local GetIconTalentCond = _H.GetIconTalentCond
local GetIconTalentTristate = _H.GetIconTalentTristate
local SetIconTalentTristate = _H.SetIconTalentTristate
local GetIconTalentKey = _H.GetIconTalentKey
local GetIconUnitHPCond = _H.GetIconUnitHPCond
local GetIconUnitHPEnabled = _H.GetIconUnitHPEnabled
local SetIconUnitHPEnabled = _H.SetIconUnitHPEnabled

-- ==========================================================
-- UI: ICON ACTIONS BUILDER  (On Click / On Show / On Hide)
-- ==========================================================

local iconActionTypeLabels = {
    ["chat"]  = "Send Chat Message",
    ["sound"] = "Play Sound",
    ["glow"]  = "Glow",
}

-- On Hide: glow has no meaningful effect (the icon is already hidden),
-- so we expose only chat and sound for that trigger.
local iconActionTypeLabelsNoGlow = {
    ["chat"]  = "Send Chat Message",
    ["sound"] = "Play Sound",
}

local chatChannelLabels = {
    ["SAY"]   = "Say",
    ["YELL"]  = "Yell",
    ["PARTY"] = "Party",
    ["RAID"]  = "Raid",
    ["EMOTE"] = "Emote",
    ["SMART"] = "Raid > Party > Say",
}

local iconActionTriggerInfo = {
    { key = "onClickActions", label = "On Click",  desc = "Actions fired when the icon is clicked." },
    { key = "onShowActions",  label = "On Show",   desc = "Actions fired when the icon becomes visible." },
    { key = "onHideActions",  label = "On Hide",   desc = "Actions fired when the icon becomes hidden.", noGlow = true },
}

--- Build AceConfig args for icon event actions (On Click / On Show / On Hide).
function Conditionals:BuildIconActionsUI(args, owner, orderBase, barKey, notifyFn)
    args.iconActionsHeader = {
        type  = "header",
        name  = "Icon Actions",
        order = orderBase,
    }
    args.iconActionsDesc = {
        type  = "description",
        name  = "|cFFAAAAFFFire actions when the icon is clicked, shown, or hidden.\n"
            .. "Chat message tokens: %name, %stack, %remaining, %target, %player, %spelllink|r",
        order = orderBase + 0.1,
        width = "full",
    }

    for ti, triggerInfo in ipairs(iconActionTriggerInfo) do
        local triggerKey  = triggerInfo.key
        local triggerBase = orderBase + ti * 2

        -- Ensure the list table exists
        owner[triggerKey] = owner[triggerKey] or {}
        local actions = owner[triggerKey]

        -- Trigger sub-header
        local hdrKey = "iconAction_" .. triggerKey .. "_hdr"
        args[hdrKey] = {
            type  = "header",
            name  = triggerInfo.label,
            order = triggerBase,
        }

        -- Add-action button
        if #actions < self.MAX_ICON_ACTIONS then
            local addKey = "iconAction_" .. triggerKey .. "_add"
            args[addKey] = {
                type  = "execute",
                name  = "+ Add Action",
                order = triggerBase + 0.1,
                width = "normal",
                func  = function()
                    table.insert(owner[triggerKey], {
                        type    = "sound",
                        sound   = nil,
                        message = "",
                        channel = "SAY",
                        glow    = false,
                        glowColor = nil,
                    })
                    notifyFn(barKey)
                end,
            }
        end

        for ai, action in ipairs(actions) do
            local aBase  = triggerBase + 0.5 + (ai - 1) * 0.2
            local prefix = "iconAction_" .. triggerKey .. "_" .. ai .. "_"

            args[prefix .. "type"] = {
                type   = "select",
                name   = triggerInfo.label .. " " .. ai,
                values = triggerInfo.noGlow and iconActionTypeLabelsNoGlow or iconActionTypeLabels,
                order  = aBase,
                get    = function() return action.type or "sound" end,
                set    = function(_, val)
                    action.type = val
                    notifyFn(barKey)
                end,
            }

            if action.type == "chat" then
                args[prefix .. "channel"] = {
                    type   = "select",
                    name   = "Channel",
                    values = chatChannelLabels,
                    order  = aBase + 0.01,
                    width  = "half",
                    get    = function() return action.channel or "SAY" end,
                    set    = function(_, val)
                        action.channel = val
                        notifyFn(barKey)
                    end,
                }
                args[prefix .. "message"] = {
                    type  = "input",
                    name  = "Message",
                    desc  = "Message to send. Tokens: %name, %stack, %remaining, %target, %player, %spelllink",
                    order = aBase + 0.02,
                    width = "double",
                    get   = function() return action.message or "" end,
                    set   = function(_, val)
                        action.message = val
                        notifyFn(barKey)
                    end,
                }

            elseif action.type == "sound" then
                args[prefix .. "sound"] = {
                    type   = "select",
                    name   = "Sound",
                    desc   = "Sound to play when triggered.",
                    values = function()
                        local vals = { ["None"] = "None" }
                        local sounds = LSM:List("sound")
                        if sounds then
                            for _, name in ipairs(sounds) do
                                vals[name] = name
                            end
                        end
                        return vals
                    end,
                    order  = aBase + 0.01,
                    width  = "double",
                    get    = function()
                        local key = action.sound
                        if not key then return "None" end
                        local old = self.OLD_SOUND_KEYS
                        if old and old[key] then return old[key] end
                        return key
                    end,
                    set    = function(_, val)
                        action.sound = (val ~= "None") and val or nil
                        -- Preview the selected sound
                        if val and val ~= "None" then
                            local path = LSM:Fetch("sound", val)
                            if path then PlaySoundFile(path) end
                        end
                        notifyFn(barKey)
                    end,
                }

            elseif action.type == "glow" then
                args[prefix .. "glow"] = {
                    type  = "toggle",
                    name  = "Enable Glow",
                    desc  = "Turn the icon glow on (true) or off (false) when triggered.",
                    order = aBase + 0.01,
                    width = "half",
                    get   = function() return action.glow or false end,
                    set   = function(_, val)
                        action.glow = val
                        notifyFn(barKey)
                    end,
                }
                if action.glow then
                    args[prefix .. "glowColor"] = {
                        type     = "color",
                        name     = "Color",
                        order    = aBase + 0.02,
                        hasAlpha = false,
                        get      = function()
                            local c = action.glowColor or { r = 1, g = 0.8, b = 0 }
                            return c.r, c.g, c.b
                        end,
                        set      = function(_, r, g, b)
                            action.glowColor = { r = r, g = g, b = b }
                            notifyFn(barKey)
                        end,
                    }
                end
            end

            args[prefix .. "remove"] = {
                type  = "execute",
                name  = "Remove",
                order = aBase + 0.09,
                width = "half",
                func  = function()
                    table.remove(owner[triggerKey], ai)
                    notifyFn(barKey)
                end,
            }
        end
    end
end
