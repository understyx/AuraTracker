local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local Config = {}
ns.AuraTracker.Config = Config

-- ==========================================================
-- ENUMS / CONSTANTS
-- ==========================================================

Config.TrackType = {
    COOLDOWN      = "cooldown",
    AURA          = "aura",
    ITEM          = "item",
    COOLDOWN_AURA = "cooldown_aura",
    INTERNAL_CD   = "internal_cd",   -- Future: custom internal cooldown trackers (e.g. Lock and Load ICD)
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
    ITEM          = Config.DisplayMode.ALWAYS,
    COOLDOWN_AURA = Config.DisplayMode.ALWAYS,
}

Config.GCD_SPELL_ID = 61304
Config.GCD_THRESHOLD = 1.6

-- Spells that should be tracked as both a cooldown and an aura simultaneously.
-- The UI shows both states: cooldown sweep when on CD, aura timer when active.
Config.DualTrackSpells = {
    -- [spellId] = { auraId = 12345, filterKey = "TARGET_DEBUFF" },
}

-- Spells that are mutually exclusive per target (only one can be active at a time).
-- When tracking any spell from a group, the icon scans for all spells in the group.
Config.ExclusiveGroups = {
    WARLOCK_CURSES = {
        label  = "Warlock Curses",
        spells = {
            [47864] = true,  -- Curse of Elements
            [47867] = true,  -- Curse of Doom
            [47865] = true,  -- Curse of Agony
            [11719] = true,  -- Curse of Tongues
            [50511] = true,  -- Curse of Weakness
        },
    },
}

-- Reverse lookup: spellId -> group data (built once at load time)
Config.ExclusiveGroupLookup = {}
for _, group in pairs(Config.ExclusiveGroups) do
    for spellId in pairs(group.spells) do
        Config.ExclusiveGroupLookup[spellId] = group
    end
end

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
    if trackType == self.TrackType.ITEM then
        return self.DefaultDisplayMode.ITEM
    end
    if trackType == self.TrackType.COOLDOWN_AURA then
        return self.DefaultDisplayMode.COOLDOWN_AURA
    end
    return self.DefaultDisplayMode[filterKey] or self.DisplayMode.ALWAYS
end

function Config:GetExclusiveGroup(spellId)
    return self.ExclusiveGroupLookup[spellId]
end