local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local Config = {}
ns.AuraTracker.Config = Config

-- ==========================================================
-- ENUMS / CONSTANTS
-- ==========================================================

Config.TrackType = {
    COOLDOWN    = "cooldown",
    AURA        = "aura",
    ITEM        = "item",          -- Future: track item cooldowns (e.g. potions, trinkets)
    INTERNAL_CD = "internal_cd",   -- Future: custom internal cooldown trackers (e.g. Lock and Load ICD)
}

Config.DisplayMode = {
    ALWAYS = "always",
    ACTIVE_ONLY = "active_only",
    MISSING_ONLY = "missing_only",
}

Config.AuraFilter = {
    PLAYER_BUFF   = { unit = "player", filter = "HELPFUL" },
    PLAYER_DEBUFF = { unit = "player", filter = "HARMFUL" },
    TARGET_BUFF   = { unit = "target", filter = "HELPFUL" },
    TARGET_DEBUFF = { unit = "target", filter = "HARMFUL" },
    FOCUS_BUFF    = { unit = "focus",  filter = "HELPFUL" },
    FOCUS_DEBUFF  = { unit = "focus",  filter = "HARMFUL" },
}

Config.SpellToAuraMap = {
    -- Death Knight
    [45477] = 55095,  -- Icy Touch -> Frost Fever
    [45462] = 55078,  -- Plague Strike -> Blood Plague
    -- Hunter
    [49001] = 49001,  -- Serpent Sting
    -- Warlock
    [47843] = 47843,  -- Unstable Affliction
    [47867] = 47867,  -- Curse of Doom
}

Config.DefaultDisplayMode = {
    PLAYER_BUFF   = Config.DisplayMode.ACTIVE_ONLY,
    PLAYER_DEBUFF = Config.DisplayMode.ACTIVE_ONLY,
    TARGET_BUFF   = Config.DisplayMode.ALWAYS,
    TARGET_DEBUFF = Config.DisplayMode.ALWAYS,
    FOCUS_BUFF    = Config.DisplayMode.ALWAYS,
    FOCUS_DEBUFF  = Config.DisplayMode.ALWAYS,
    COOLDOWN      = Config.DisplayMode.ALWAYS,
}

Config.GCD_SPELL_ID = 61304
Config.GCD_THRESHOLD = 1.6

-- Spells that should be tracked as both a cooldown and an aura simultaneously.
-- The UI can show both states (e.g., cooldown sweep + debuff duration).
-- Future: Implement dual-display mode in Icon.lua for these spells.
Config.DualTrackSpells = {
    -- [spellId] = { auraId = auraId, filterKey = "TARGET_DEBUFF" },
}

-- ==========================================================
-- FUNCTIONS
-- ==========================================================

function Config:GetAuraFilter(filterKey)
    return self.AuraFilter[filterKey]
end

function Config:GetMappedAuraId(spellId)
    return self.SpellToAuraMap[spellId] or spellId
end

function Config:GetDefaultDisplayMode(trackType, filterKey)
    if trackType == self.TrackType.COOLDOWN then
        return self.DefaultDisplayMode.COOLDOWN
    end
    return self.DefaultDisplayMode[filterKey] or self.DisplayMode.ALWAYS
end