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
local condOpLabels = _H.condOpLabels

local TRISTATE_YES_COLOR = "|cFF00CC00"
local TRISTATE_NO_COLOR  = "|cFFCC0000"
local TRISTATE_COLOR_END = "|r"

--- Build AceConfig args for load conditions.
--- @param args      table   Args table to inject into
--- @param owner     table   DB table that has .loadConditions
--- @param orderBase number  Order base
--- @param barKey    string  Bar key
--- @param notifyFn  function  Called after changes
--- @param mode      string  "bar" or "icon"
function Conditionals:BuildLoadConditionUI(args, owner, orderBase, barKey, notifyFn, mode)
    mode = mode or "bar"

    owner.loadConditions = owner.loadConditions or {}

    local B = ns.AuraTracker._LoadCondBuilders
    if mode == "bar" then
        B.BuildBarConditions(args, owner, orderBase, barKey, notifyFn, Conditionals)
    else
        B.BuildIconConditions(args, owner, orderBase, barKey, notifyFn, Conditionals)
    end
end

