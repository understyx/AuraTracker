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

-- Exclusive spell groups are user-configurable per icon via the "Also Track" UI.
-- Each tracked icon can define a set of alternative spell IDs
-- stored as exclusiveSpells = { [spellId] = true, ... } in the DB entry.
--
-- The presets below provide WotLK-era defaults that can be loaded via the UI.
-- These use max-rank (level 80) spell IDs; name-based matching in
-- UpdateAuraExclusive handles lower-level ranks automatically.

Config.ExclusivePresets = {
    -- ========================================
    --  WARLOCK-SPECIFIC
    -- ========================================
    WARLOCK_CURSES = {
        label  = "Warlock Curses",
        spells = {
            [47864] = true,  -- Curse of the Elements
            [47867] = true,  -- Curse of Doom
            [47865] = true,  -- Curse of Agony
            [11719] = true,  -- Curse of Tongues
            [50511] = true,  -- Curse of Weakness
        },
    },
    WARLOCK_CORRUPTION = {
        label  = "Corruption / Seed of Corruption",
        spells = {
            [47813] = true,  -- Corruption
            [47836] = true,  -- Seed of Corruption
        },
    },

    -- ========================================
    --  BUFFS
    -- ========================================
    BUFF_AGILITY_STRENGTH = {
        label  = "Agility and Strength",
        spells = {
            [57623] = true,  -- Horn of Winter
            [58643] = true,  -- Strength of Earth Totem
        },
    },
    BUFF_ATTACK_POWER = {
        label  = "Attack Power",
        spells = {
            [47436] = true,  -- Battle Shout
            [48934] = true,  -- Blessing of Might
        },
    },
    BUFF_ATTACK_POWER_PCT = {
        label  = "Attack Power % Increase",
        spells = {
            [19506] = true,  -- Trueshot Aura
            [30811] = true,  -- Unleashed Rage
            [53138] = true,  -- Abomination's Might
        },
    },
    BUFF_DAMAGE_INCREASE = {
        label  = "Damage % Increase",
        spells = {
            [31583] = true,  -- Arcane Empowerment
            [34460] = true,  -- Ferocious Inspiration
            [31869] = true,  -- Sanctified Retribution
        },
    },
    BUFF_DAMAGE_REDUCTION = {
        label  = "Damage Reduction",
        spells = {
            [25899] = true,  -- Blessing of Sanctuary
            [63944] = true,  -- Renewed Hope
        },
    },
    BUFF_HASTE_3PCT = {
        label  = "3% Haste",
        spells = {
            [48396] = true,  -- Improved Moonkin Form
            [54153] = true,  -- Swift Retribution (aura)
        },
    },
    BUFF_HEALING_RECEIVED = {
        label  = "Healing Received Increase",
        spells = {
            [63514] = true,  -- Improved Devotion Aura (healing increase effect)
            [34123] = true,  -- Tree of Life
        },
    },
    BUFF_HEALTH = {
        label  = "Health (Stamina via Shout/Imp)",
        spells = {
            [47440] = true,  -- Commanding Shout
            [47982] = true,  -- Blood Pact (Improved Imp)
        },
    },
    BUFF_INTELLECT = {
        label  = "Intellect",
        spells = {
            [42995] = true,  -- Arcane Intellect / Arcane Brilliance
            [47893] = true,  -- Fel Intelligence
        },
    },
    BUFF_MANA_PER_5 = {
        label  = "Mana per 5",
        spells = {
            [48938] = true,  -- Blessing of Wisdom
            [58774] = true,  -- Mana Spring Totem
            [16190] = true,  -- Mana Tide Totem
        },
    },
    BUFF_MELEE_HASTE = {
        label  = "Melee Haste",
        spells = {
            [55610] = true,  -- Improved Icy Talons
            [8512]  = true,  -- Windfury Totem
        },
    },
    BUFF_PHYSICAL_CRIT = {
        label  = "Physical Crit",
        spells = {
            [17007] = true,  -- Leader of the Pack
            [29801] = true,  -- Rampage
        },
    },
    BUFF_PHYSICAL_DAMAGE_REDUCTION = {
        label  = "Physical Damage Reduction (Armor)",
        spells = {
            [16236] = true,  -- Ancestral Healing (buff)
            [15363] = true,  -- Inspiration
        },
    },
    BUFF_REPLENISHMENT = {
        label  = "Replenishment",
        spells = {
            [57669] = true,  -- Replenishment (all sources apply this same buff)
        },
    },
    BUFF_SPELL_CRIT = {
        label  = "Spell Crit",
        spells = {
            [51470] = true,  -- Elemental Oath
            [24907] = true,  -- Moonkin Aura
        },
    },
    BUFF_SPELL_HASTE = {
        label  = "Spell Haste (Wrath of Air)",
        spells = {
            [3738]  = true,  -- Wrath of Air Totem
        },
    },
    BUFF_SPELL_POWER = {
        label  = "Spell Power",
        spells = {
            [47240] = true,  -- Demonic Pact
            [58656] = true,  -- Flametongue Totem
            [57722] = true,  -- Totem of Wrath
        },
    },
    BUFF_SPIRIT = {
        label  = "Spirit",
        spells = {
            [48074] = true,  -- Divine Spirit / Prayer of Spirit
            [47893] = true,  -- Fel Intelligence
        },
    },
    BUFF_STAMINA = {
        label  = "Stamina",
        spells = {
            [48162] = true,  -- Power Word: Fortitude / Prayer of Fortitude
        },
    },
    BUFF_STATS = {
        label  = "Stats (Mark of the Wild)",
        spells = {
            [48470] = true,  -- Mark of the Wild / Gift of the Wild
        },
    },
    BUFF_STATS_PCT = {
        label  = "Stats % (Kings/Sanctuary)",
        spells = {
            [20217] = true,  -- Blessing of Kings
            [25899] = true,  -- Blessing of Sanctuary
        },
    },

    -- ========================================
    --  DEBUFFS
    -- ========================================
    DEBUFF_ARMOR_MAJOR = {
        label  = "Armor Reduction (Major, 20%)",
        spells = {
            [55749] = true,  -- Acid Spit (Worm pet)
            [8647]  = true,  -- Expose Armor
            [47467] = true,  -- Sunder Armor
        },
    },
    DEBUFF_ARMOR_MINOR = {
        label  = "Armor Reduction (Minor, 5%)",
        spells = {
            [50511] = true,  -- Curse of Weakness
            [770]   = true,  -- Faerie Fire
            [50498] = true,  -- Sting (Wasp pet)
        },
    },
    DEBUFF_ATTACK_POWER_REDUCTION = {
        label  = "Attack Power Reduction",
        spells = {
            [50511] = true,  -- Curse of Weakness
            [48560] = true,  -- Demoralizing Roar
            [47437] = true,  -- Demoralizing Shout
            [26016] = true,  -- Vindication (debuff)
        },
    },
    DEBUFF_ATTACK_SPEED_REDUCTION = {
        label  = "Attack Speed Reduction",
        spells = {
            [55095] = true,  -- Frost Fever (from Icy Touch)
            [48484] = true,  -- Infected Wounds
            [53696] = true,  -- Judgements of the Just
            [47502] = true,  -- Thunder Clap
        },
    },
    DEBUFF_BLEED_DAMAGE = {
        label  = "Bleed Damage Increase",
        spells = {
            [48564] = true,  -- Mangle (Bear)
            [48566] = true,  -- Mangle (Cat)
            [57386] = true,  -- Stampede (Rhino pet)
            [46857] = true,  -- Trauma (debuff)
        },
    },
    DEBUFF_CAST_SPEED_REDUCTION = {
        label  = "Cast Speed Reduction",
        spells = {
            [11719] = true,  -- Curse of Tongues
            [58604] = true,  -- Lava Breath (Core Hound pet)
            [5761]  = true,  -- Mind-numbing Poison
            [31589] = true,  -- Slow
        },
    },
    DEBUFF_CRIT_CHANCE = {
        label  = "Crit Chance (Debuff)",
        spells = {
            [20337] = true,  -- Heart of the Crusader
            [57722] = true,  -- Totem of Wrath
        },
    },
    DEBUFF_HEALING_REDUCTION = {
        label  = "Healing Reduction (Mortal Strike)",
        spells = {
            [49050] = true,  -- Aimed Shot
            [56112] = true,  -- Furious Attacks
            [47486] = true,  -- Mortal Strike
            [57975] = true,  -- Wound Poison
        },
    },
    DEBUFF_HEALTH_RESTORE = {
        label  = "Health Restoration (JoL)",
        spells = {
            [20271] = true,  -- Judgement of Light
        },
    },
    DEBUFF_MANA_RESTORE = {
        label  = "Mana Restoration (JoW)",
        spells = {
            [53408] = true,  -- Judgement of Wisdom
        },
    },
    DEBUFF_MELEE_HIT_REDUCTION = {
        label  = "Melee Hit Reduction",
        spells = {
            [49868] = true,  -- Insect Swarm
            [3043]  = true,  -- Scorpid Sting
        },
    },
    DEBUFF_PHYSICAL_DAMAGE_INCREASE = {
        label  = "Physical Damage Increase",
        spells = {
            [30070] = true,  -- Blood Frenzy (debuff)
            [58683] = true,  -- Savage Combat (debuff)
        },
    },
    DEBUFF_SPELL_CRIT = {
        label  = "Spell Crit (Debuff)",
        spells = {
            [22959] = true,  -- Improved Scorch (debuff)
            [17800] = true,  -- Shadow Mastery (debuff applied by Improved Shadow Bolt talent)
            [28593] = true,  -- Winter's Chill
        },
    },
    DEBUFF_SPELL_DAMAGE_INCREASE = {
        label  = "Spell Damage Increase",
        spells = {
            [47864] = true,  -- Curse of the Elements
            [60433] = true,  -- Earth and Moon (debuff)
            [51735] = true,  -- Ebon Plague (debuff)
        },
    },
    DEBUFF_SPELL_HIT = {
        label  = "Spell Hit Chance (Debuff)",
        spells = {
            [770]   = true,  -- Faerie Fire (spell hit component added by Improved Faerie Fire talent, same aura ID)
            [33198] = true,  -- Misery
        },
    },
}

-- Build a reverse lookup: spell ID → preset key.
-- Used for auto-linking exclusive groups when a user adds a spell.
-- Some spells appear in multiple presets (e.g. Fel Intelligence provides
-- both Intellect and Spirit).  We keep only the first mapping found;
-- users can still load other presets manually via the UI dropdown.
Config.SpellToPreset = {}
for presetKey, preset in pairs(Config.ExclusivePresets) do
    for spellId in pairs(preset.spells) do
        if not Config.SpellToPreset[spellId] then
            Config.SpellToPreset[spellId] = presetKey
        end
    end
end

-- Returns the preset key a spell belongs to, or nil.
function Config:GetPresetForSpell(spellId)
    return self.SpellToPreset[spellId]
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