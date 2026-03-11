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
    INTERNAL_CD   = "internal_cd",    -- Trinket / enchant internal cooldown tracking via combat log
    WEAPON_ENCHANT = "weapon_enchant", -- Temporary weapon enchant (sharpening stones, imbues, etc.)
    TOTEM         = "totem",          -- Shaman totem element slot (fire/earth/water/air)
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
    PLAYER_BUFF    = Config.DisplayMode.ACTIVE_ONLY,
    PLAYER_DEBUFF  = Config.DisplayMode.ACTIVE_ONLY,
    TARGET_BUFF    = Config.DisplayMode.ALWAYS,
    TARGET_DEBUFF  = Config.DisplayMode.ALWAYS,
    FOCUS_BUFF     = Config.DisplayMode.ALWAYS,
    FOCUS_DEBUFF   = Config.DisplayMode.ALWAYS,
    COOLDOWN       = Config.DisplayMode.ALWAYS,
    ITEM           = Config.DisplayMode.ALWAYS,
    COOLDOWN_AURA  = Config.DisplayMode.ALWAYS,
    INTERNAL_CD    = Config.DisplayMode.ALWAYS,
    WEAPON_ENCHANT = Config.DisplayMode.ALWAYS,
    TOTEM          = Config.DisplayMode.ALWAYS,
}

Config.GCD_SPELL_ID = 61304
Config.GCD_THRESHOLD = 1.6

-- Sentinel IDs used when a temporary weapon enchant is tracked by slot only
-- (i.e. dragged from the TempEnchant buff-frame button rather than from an
-- item in the player's bags).  Negative values are safe because real item
-- and spell IDs are always positive in WoW.
Config.MAINHAND_ENCHANT_SLOT_ID = -1
Config.OFFHAND_ENCHANT_SLOT_ID  = -2

-- Sentinel IDs for shaman totem element trackers.  One icon per element slot
-- tracks whichever totem of that element is currently placed.
Config.FIRE_TOTEM_ID  = -10
Config.EARTH_TOTEM_ID = -11
Config.WATER_TOTEM_ID = -12
Config.AIR_TOTEM_ID   = -13

-- Maps each totem sentinel ID to the GetTotemInfo slot index.
-- Slot 1 = Fire, 2 = Earth, 3 = Water, 4 = Air (WotLK 3.3.5 convention).
Config.TotemSlot = {
    [-10] = 1,  -- Fire
    [-11] = 2,  -- Earth
    [-12] = 3,  -- Water
    [-13] = 4,  -- Air
}

-- Human-readable element names used as fallback display text.
Config.TotemElementName = {
    [-10] = "Fire Totem",
    [-11] = "Earth Totem",
    [-12] = "Water Totem",
    [-13] = "Air Totem",
}

-- Maps shaman totem spell IDs to the sentinel totem ID for that element.
-- When a totem spell is dragged onto a bar, the corresponding element tracker
-- is added so that any totem of that element is monitored via GetTotemInfo.
-- Values correspond to: FIRE_TOTEM_ID=-10, EARTH_TOTEM_ID=-11,
--                       WATER_TOTEM_ID=-12, AIR_TOTEM_ID=-13 (defined above).
Config.TotemSpells = {
    -- ==============================
    -- Fire Totems (slot 1)
    -- ==============================
    -- Searing Totem (all ranks)
    [3599]  = -10, [6363]  = -10, [6364]  = -10, [6365]  = -10, [6366]  = -10,
    [25533] = -10, [58700] = -10, [58704] = -10, [58705] = -10,
    [58707] = -10, [58708] = -10,
    -- Magma Totem ranks 1-6
    [8190]  = -10, [10585] = -10, [10586] = -10, [10587] = -10,
    [58731] = -10, [58736] = -10,
    -- Fire Elemental Totem
    [2894]  = -10,
    -- Flametongue Totem ranks 1-5
    [8227]  = -10, [8249]  = -10, [10526] = -10, [16387] = -10, [25557] = -10,
    -- ==============================
    -- Earth Totems (slot 2)
    -- ==============================
    -- Stoneskin Totem ranks 1-8
    [8071]  = -11, [8154]  = -11, [10406] = -11, [10407] = -11, [10408] = -11,
    [25506] = -11, [58753] = -11, [58759] = -11,
    -- Strength of Earth Totem ranks 1-7
    [8075]  = -11, [8160]  = -11, [10442] = -11, [25362] = -11, [25527] = -11,
    [57622] = -11, [58643] = -11,
    -- Earth Elemental Totem
    [2062]  = -11,
    -- Earthbind Totem
    [2484]  = -11,
    -- Tremor Totem
    [8143]  = -11,
    -- ==============================
    -- Water Totems (slot 3)
    -- ==============================
    -- Mana Spring Totem ranks 1-6
    [5675]  = -12, [10495] = -12, [10496] = -12, [10497] = -12,
    [25570] = -12, [58774] = -12,
    -- Healing Stream Totem ranks 1-6
    [5394]  = -12, [6375]  = -12, [6377]  = -12, [10462] = -12,
    [10463] = -12, [25567] = -12,
    -- Cleansing Totem
    [8170]  = -12,
    -- Mana Tide Totem ranks 1-4
    [16190] = -12, [17359] = -12, [17360] = -12, [17361] = -12,
    -- ==============================
    -- Air Totems (slot 4)
    -- ==============================
    -- Windfury Totem ranks 1-5
    [8512]  = -13, [10613] = -13, [10614] = -13, [25585] = -13, [60112] = -13,
    -- Wrath of Air Totem
    [3738]  = -13,
    -- Grace of Air Totem ranks 1-4
    [8835]  = -13, [10626] = -13, [10627] = -13, [25359] = -13,
    -- Grounding Totem
    [8177]  = -13,
    -- Tranquil Air Totem
    [25908] = -13,
    -- Nature's Resistance Totem ranks 1-4
    [10595] = -13, [10600] = -13, [10601] = -13, [25574] = -13,
}

-- ==========================================================
-- WEAPON ENCHANT SPELLS
-- ==========================================================
-- Shaman weapon imbue spells that should be tracked as PLAYER_BUFF auras
-- rather than cooldowns when dragged onto a bar.  Covers all WotLK ranks.
Config.WeaponEnchantSpells = {
    -- Windfury Weapon (ranks 1-6)
    [8232]  = true, [8235]  = true, [10486] = true,
    [16362] = true, [16363] = true, [25505] = true,
    -- Flametongue Weapon (ranks 1-9)
    [8024]  = true, [8027]  = true, [8030]  = true,
    [16339] = true, [16341] = true, [25488] = true,
    [58789] = true, [58790] = true, [58791] = true,
    -- Frostbrand Weapon (ranks 1-7)
    [8033]  = true, [8038]  = true, [10456] = true,
    [16355] = true, [16356] = true, [58796] = true, [58797] = true,
    -- Earthliving Weapon (ranks 1-5)
    [51990] = true, [51991] = true, [51992] = true,
    [51993] = true, [51994] = true,
}

-- ==========================================================
-- WEAPON ENCHANT ITEMS
-- ==========================================================
-- Consumable items that apply a temporary weapon enchant.
-- Value is the weapon slot ("mainhand" or "offhand").
Config.WeaponEnchantItems = {
    -- Sharpening Stones
    [3498]  = "mainhand",  -- Rough Sharpening Stone
    [3502]  = "mainhand",  -- Coarse Sharpening Stone
    [3504]  = "mainhand",  -- Heavy Sharpening Stone
    [3521]  = "mainhand",  -- Solid Sharpening Stone
    [12404] = "mainhand",  -- Dense Sharpening Stone
    [18262] = "mainhand",  -- Elemental Sharpening Stone
    [28421] = "mainhand",  -- Adamantite Sharpening Stone
    [44452] = "mainhand",  -- Eternal Sharpening Stone
    -- Weightstones
    [3239]  = "mainhand",  -- Rough Weightstone
    [3240]  = "mainhand",  -- Coarse Weightstone
    [3241]  = "mainhand",  -- Heavy Weightstone
    [7964]  = "mainhand",  -- Solid Weightstone
    [12643] = "mainhand",  -- Dense Weightstone
    [28422] = "mainhand",  -- Adamantite Weightstone
    -- Warlock Spellstones / Firestones
    [5522]  = "mainhand",  -- Minor Spellstone
    [13601] = "mainhand",  -- Spellstone
    [13602] = "mainhand",  -- Greater Spellstone
    [1254]  = "mainhand",  -- Minor Firestone
    [13699] = "mainhand",  -- Firestone
    [13700] = "mainhand",  -- Greater Firestone
    [13701] = "mainhand",  -- Major Firestone
    -- Rogue Poisons
    -- Instant Poison I-IX
    [6947]  = "mainhand", [6949]  = "mainhand", [6950]  = "mainhand",
    [8926]  = "mainhand", [8927]  = "mainhand", [8928]  = "mainhand",
    [21923] = "mainhand", [43230] = "mainhand", [43231] = "mainhand",
    -- Deadly Poison I-VII
    [2892]  = "mainhand", [2893]  = "mainhand", [8984]  = "mainhand",
    [8985]  = "mainhand", [20844] = "mainhand", [22053] = "mainhand",
    [43232] = "mainhand",
    -- Wound Poison I-VI
    [10918] = "mainhand", [10919] = "mainhand", [10920] = "mainhand",
    [10921] = "mainhand", [22055] = "mainhand", [43235] = "mainhand",
    -- Mind-Numbing Poison I-III
    [5237]  = "mainhand", [6067]  = "mainhand", [6068]  = "mainhand",
    -- Crippling Poison I-II
    [3775]  = "mainhand", [3776]  = "mainhand",
    -- Anesthetic Poison I-II
    [21835] = "mainhand", [43237] = "mainhand",
}

-- ==========================================================
-- EXAMPLE BARS
-- ==========================================================
-- Pre-built bar configurations that users can import from the
-- Example Bars section in the settings panel.  Each entry has:
--   class  – "NONE" for all classes, or a class key (e.g. "DEATHKNIGHT")
--   name   – display name for the bar
--   desc   – short description shown in the UI
--   data   – bar data table (direction + trackedItems)
Config.ExampleBars = {
    {
        class = "DEATHKNIGHT",
        name  = "DK: Disease Tracker",
        desc  = "Tracks Frost Fever and Blood Plague on the target.",
        data  = {
            direction = "HORIZONTAL",
            trackedItems = {
                [45477] = { order = 1, trackType = "aura", auraId = 55095,
                    type = "target_debuff", unit = "target", filter = "HARMFUL",
                    displayMode = "always", onlyMine = false },
                [45462] = { order = 2, trackType = "aura", auraId = 55078,
                    type = "target_debuff", unit = "target", filter = "HARMFUL",
                    displayMode = "always", onlyMine = false },
            },
        },
    },
    {
        class = "WARLOCK",
        name  = "Warlock: DoT Tracker",
        desc  = "Tracks Corruption, Curse of Agony, and Haunt on the target.",
        data  = {
            direction = "HORIZONTAL",
            trackedItems = {
                [47813] = { order = 1, trackType = "aura", auraId = 47813,
                    type = "target_debuff", unit = "target", filter = "HARMFUL",
                    displayMode = "always", onlyMine = true },
                [47865] = { order = 2, trackType = "aura", auraId = 47865,
                    type = "target_debuff", unit = "target", filter = "HARMFUL",
                    displayMode = "always", onlyMine = true },
                [59164] = { order = 3, trackType = "aura", auraId = 59164,
                    type = "target_debuff", unit = "target", filter = "HARMFUL",
                    displayMode = "always", onlyMine = true },
            },
        },
    },
    {
        class = "WARRIOR",
        name  = "Warrior: Debuff Tracker",
        desc  = "Tracks Sunder Armor and Demoralizing Shout on the target.",
        data  = {
            direction = "HORIZONTAL",
            trackedItems = {
                [47467] = { order = 1, trackType = "aura", auraId = 47467,
                    type = "target_debuff", unit = "target", filter = "HARMFUL",
                    displayMode = "always", onlyMine = false },
                [47437] = { order = 2, trackType = "aura", auraId = 47437,
                    type = "target_debuff", unit = "target", filter = "HARMFUL",
                    displayMode = "always", onlyMine = false },
            },
        },
    },
    {
        class = "NONE",
        name  = "Buff Monitor",
        desc  = "Shows when Kings, Fort, MotW, Wisdom, or Might is missing from you.",
        data  = {
            direction = "HORIZONTAL",
            trackedItems = {
                [20217] = { order = 1, trackType = "aura", auraId = 20217,
                    type = "player_buff", unit = "player", filter = "HELPFUL",
                    displayMode = "missing_only", onlyMine = false },
                [48162] = { order = 2, trackType = "aura", auraId = 48162,
                    type = "player_buff", unit = "player", filter = "HELPFUL",
                    displayMode = "missing_only", onlyMine = false },
                [48470] = { order = 3, trackType = "aura", auraId = 48470,
                    type = "player_buff", unit = "player", filter = "HELPFUL",
                    displayMode = "missing_only", onlyMine = false },
                [48938] = { order = 4, trackType = "aura", auraId = 48938,
                    type = "player_buff", unit = "player", filter = "HELPFUL",
                    displayMode = "missing_only", onlyMine = false },
                [47436] = { order = 5, trackType = "aura", auraId = 47436,
                    type = "player_buff", unit = "player", filter = "HELPFUL",
                    displayMode = "missing_only", onlyMine = false },
            },
        },
    },
}


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
        label  = "Buff - Agility and Strength",
        spells = {
            [57623] = true,  -- Horn of Winter
            [58643] = true,  -- Strength of Earth Totem
        },
    },
    BUFF_ATTACK_POWER = {
        label  = "Buff - Attack Power",
        spells = {
            [47436] = true,  -- Battle Shout
            [48934] = true,  -- Blessing of Might
            [20045] = true,  -- Improved Blessing of Might (talent)
        },
    },
    BUFF_ATTACK_POWER_PCT = {
        label  = "Buff - 10% APIncrease",
        spells = {
            [19506] = true,  -- Trueshot Aura
            [30811] = true,  -- Unleashed Rage
            [53138] = true,  -- Abomination's Might
        },
    },
    BUFF_DAMAGE_INCREASE = {
        label  = "Buff - Damage 3% Increase",
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
        label  = "Buff -  3% Haste",
        spells = {
            [48396] = true,  -- Improved Moonkin Form
            [53648] = true,  -- Swift Retribution
        },
    },
    BUFF_HEALING_RECEIVED = {
        label  = "Buff - Healing Received Increase",
        spells = {
            [20140] = true,  -- Improved Devotion Aura
            [34123] = true,  -- Tree of Life
        },
    },
    BUFF_HEALTH = {
        label  = "Buff - Health",
        spells = {
            [47440] = true,  -- Commanding Shout
            [47982] = true,  -- Blood Pact (Improved Imp)
        },
    },
    BUFF_INTELLECT = {
        label  = "Buff -  Intellect",
        spells = {
            [42995] = true,  -- Arcane Intellect / Arcane Brilliance
            [47893] = true,  -- Fel Intelligence
        },
    },
    BUFF_MANA_PER_5 = {
        label  = "Buff - MP5",
        spells = {
            [48938] = true,  -- Blessing of Wisdom
            [20245] = true,  -- Improved Blessing of Wisdom (talent)
            [58774] = true,  -- Mana Spring Totem
            [16190] = true,  -- Restorative Totems (Mana Tide Totem)
        },
    },
    BUFF_MELEE_HASTE = {
        label  = "Buff - Melee Haste",
        spells = {
            [55610] = true,  -- Improved Icy Talons
            [8512]  = true,  -- Windfury Totem
            [29193] = true,  -- Improved Windfury Totem (talent)
        },
    },
    BUFF_PHYSICAL_CRIT = {
        label  = "Buff - 5% Physical Crit",
        spells = {
            [17007] = true,  -- Leader of the Pack
            [29801] = true,  -- Rampage
        },
    },
    BUFF_PHYSICAL_DAMAGE_REDUCTION = {
        label  = "Buff - Physical Damage Reduction",
        spells = {
            [16237] = true,  -- Ancestral Healing
            [15363] = true,  -- Inspiration
        },
    },
    BUFF_REPLENISHMENT = {
        label  = "Buff - Replenishment",
        spells = {
            [44561] = true,  -- Enduring Winter (Replenishment proc)
            [53292] = true,  -- Hunting Party (Replenishment proc)
            [54118] = true,  -- Improved Soul Leech (Replenishment proc)
            [31878] = true,  -- Judgements of the Wise (Replenishment proc)
            [48160] = true,  -- Vampiric Touch
        },
    },
    BUFF_SPELL_CRIT = {
        label  = "Buff - 5% Spell Crit",
        spells = {
            [51470] = true,  -- Elemental Oath
            [24907] = true,  -- Moonkin Aura
        },
    },
    BUFF_SPIRIT = {
        label  = "Buff - Spirit",
        spells = {
            [48074] = true,  -- Divine Spirit / Prayer of Spirit
            [47893] = true,  -- Fel Intelligence
        },
    },
    BUFF_STAMINA = {
        label  = "Buff - Stamina",
        spells = {
            [48162] = true,  -- Power Word: Fortitude / Prayer of Fortitude
            [14767] = true,  -- Improved Power Word: Fortitude (talent)
        },
    },
    BUFF_STATS = {
        label  = "Buff - Mark of the Wild",
        spells = {
            [48470] = true,  -- Mark of the Wild / Gift of the Wild
            [17055] = true,  -- Improved Mark of the Wild (talent)
        },
    },
    BUFF_STATS_PCT = {
        label  = "Stats % (Kings/Sanctuary)",
        spells = {
            [20217] = true,  -- Blessing of Kings
        },
    },

    -- ========================================
    --  DEBUFFS
    -- ========================================
    DEBUFF_ARMOR_MAJOR = {
        label  = "Debuff - Sunder Armor",
        spells = {
            [55749] = true,  -- Acid Spit (Worm pet)
            [8647]  = true,  -- Expose Armor
            [47467] = true,  -- Sunder Armor
        },
    },
    DEBUFF_ARMOR_MINOR = {
        label  = "Debuff - 5% armor reduction",
        spells = {
            [50511] = true,  -- Curse of Weakness
            [770]   = true,  -- Faerie Fire
            [50498] = true,  -- Sting (Wasp pet)
        },
    },
    DEBUFF_ATTACK_POWER_REDUCTION = {
        label  = "Debuff - AP Reduction",
        spells = {
            [50511] = true,  -- Curse of Weakness
            [30909] = true,  -- Improved Curse of Weakness (talent)
            [48560] = true,  -- Demoralizing Roar
            [16862] = true,  -- Feral Aggression (talent)
            [47437] = true,  -- Demoralizing Shout
            [12879] = true,  -- Improved Demoralizing Shout (talent)
            [26017] = true,  -- Vindication
        },
    },
    DEBUFF_ATTACK_SPEED_REDUCTION = {
        label  = "Debuff - AS Reduction",
        spells = {
            [45477] = true,  -- Icy Touch
            [55610] = true,  -- Improved Icy Talons (also reduces attack speed via debuff)
            [48484] = true,  -- Infected Wounds
            [53696] = true,  -- Judgements of the Just
            [47502] = true,  -- Thunder Clap
            [12666] = true,  -- Improved Thunder Clap (talent)
        },
    },
    DEBUFF_BLEED_DAMAGE = {
        label  = "Debuff - Bleed Damage Increase",
        spells = {
            [48564] = true,  -- Mangle (Bear)
            [48566] = true,  -- Mangle (Cat)
            [57386] = true,  -- Stampede (Rhino pet)
            [46855] = true,  -- Trauma
        },
    },
    DEBUFF_CAST_SPEED_REDUCTION = {
        label  = "Debuff - Cast Speed Reduction",
        spells = {
            [11719] = true,  -- Curse of Tongues
            [58604] = true,  -- Lava Breath (Core Hound pet)
            [5761]  = true,  -- Mind-numbing Poison
            [31589] = true,  -- Slow
        },
    },
    DEBUFF_CRIT_CHANCE = {
        label  = "Debuff - Crit Chance (Debuff)",
        spells = {
            [20337] = true,  -- Heart of the Crusader
            [58410] = true,  -- Master Poisoner
            [57722] = true,  -- Totem of Wrath
        },
    },
    DEBUFF_HEALING_REDUCTION = {
        label  = "Debuff - Mortal Strike",
        spells = {
            [49050] = true,  -- Aimed Shot
            [56112] = true,  -- Furious Attacks
            [47486] = true,  -- Mortal Strike
            [57975] = true,  -- Wound Poison
        },
    },
    DEBUFF_MELEE_HIT_REDUCTION = {
        label  = "Debuff - Melee Hit Reduction",
        spells = {
            [49868] = true,  -- Insect Swarm
            [3043]  = true,  -- Scorpid Sting
        },
    },
    DEBUFF_PHYSICAL_DAMAGE_INCREASE = {
        label  = "Debuff - Physical Damage Increase",
        spells = {
            [29859] = true,  -- Blood Frenzy
            [58413] = true,  -- Savage Combat
        },
    },
    DEBUFF_SPELL_CRIT = {
        label  = "Debuff - 5% Spell Crit",
        spells = {
            [22959] = true,  -- Improved Scorch
            [17800] = true,  -- Improved Shadow Bolt
            [28593] = true,  -- Winter's Chill
        },
    },
    DEBUFF_SPELL_DAMAGE_INCREASE = {
        label  = "Debuff - Spell Damage Increase",
        spells = {
            [47864] = true,  -- Curse of the Elements
            [60433] = true,  -- Earth and Moon
            [51161] = true,  -- Ebon Plaguebringer
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
    if trackType == self.TrackType.INTERNAL_CD then
        return self.DefaultDisplayMode.INTERNAL_CD
    end
    if trackType == self.TrackType.WEAPON_ENCHANT then
        return self.DefaultDisplayMode.WEAPON_ENCHANT
    end
    return self.DefaultDisplayMode[filterKey] or self.DisplayMode.ALWAYS
end

function Config:IsWeaponEnchantSpell(spellId)
    return self.WeaponEnchantSpells[spellId] == true
end

function Config:IsWeaponEnchantItem(itemId)
    return self.WeaponEnchantItems[itemId] ~= nil
end

function Config:GetWeaponEnchantSlot(itemId)
    return self.WeaponEnchantItems[itemId]
end

-- ==========================================================
-- EXPECTED WEAPON ENCHANT CHOICES
-- ==========================================================
-- Ordered list of named weapon enchant types for the settings dropdown.
-- key    = internal string stored in DB; "any" = wildcard
-- label  = human-readable display name
-- auraId = spell ID kept for reference / icon display; NOT used for in-game
--          buff detection (WotLK weapon imbues do not appear as UnitAura buffs).
Config.WeaponEnchantChoices = {
    { key = "any",         label = "Any Enchant",          auraId = nil   },
    -- Shaman weapon imbues
    { key = "windfury",    label = "Windfury Weapon",       auraId = 25505 },
    { key = "flametongue", label = "Flametongue Weapon",    auraId = 58790 },
    { key = "frostbrand",  label = "Frostbrand Weapon",     auraId = 58797 },
    { key = "earthliving", label = "Earthliving Weapon",    auraId = 51994 },
    -- Warlock stones
    { key = "firestone",   label = "Firestone",             auraId = nil   },
    { key = "spellstone",  label = "Spellstone",            auraId = nil   },
    -- Consumable stones
    { key = "sharpening",  label = "Sharpening Stone",      auraId = nil   },
    { key = "weightstone", label = "Weightstone",           auraId = nil   },
}

-- Fast key → {label, auraId} lookup built from the ordered list above.
Config.WeaponEnchantChoiceByKey = {}
for _, choice in ipairs(Config.WeaponEnchantChoices) do
    Config.WeaponEnchantChoiceByKey[choice.key] = choice
end

-- Maps consumable weapon enchant item IDs → expected enchant key.
-- Used to auto-set the expected enchant when one of these items is dragged.
Config.WeaponEnchantItemChoice = {
    -- Sharpening Stones
    [3498]  = "sharpening", [3502]  = "sharpening", [3504] = "sharpening",
    [3521]  = "sharpening", [12404] = "sharpening", [18262] = "sharpening",
    [28421] = "sharpening", [44452] = "sharpening",
    -- Weightstones
    [3239]  = "weightstone", [3240]  = "weightstone", [3241]  = "weightstone",
    [7964]  = "weightstone", [12643] = "weightstone", [28422] = "weightstone",
    -- Warlock Spellstones
    [5522]  = "spellstone", [13601] = "spellstone", [13602] = "spellstone",
    -- Warlock Firestones
    [1254]  = "firestone", [13699] = "firestone", [13700] = "firestone", [13701] = "firestone",
}

-- Returns the enchant choice key for a weapon enchant item, or nil.
function Config:GetWeaponEnchantChoiceForItem(itemId)
    return self.WeaponEnchantItemChoice[itemId]
end

-- Returns the auraId (kept for reference/icon display) for a given choice key, or nil.
function Config:GetWeaponEnchantAuraId(choiceKey)
    local choice = choiceKey and self.WeaponEnchantChoiceByKey[choiceKey]
    return choice and choice.auraId
end

-- ==========================================================
-- WEAPON ENCHANT TOOLTIP NAME MATCHING
-- ==========================================================
-- Maps tooltip-extracted enchant names to choice keys so UpdateWeaponEnchant
-- can identify which specific enchant is on a weapon slot via tooltip parsing.

-- Module-level caches (built lazily on first call to GetWeaponEnchantKeyFromName).
local _enchantExactMap    = nil  -- exact name  → key
local _enchantSubstrList  = nil  -- {name, key, len} sorted longest-first for substr match

-- Returns the enchant choice key matching the given parsed tooltip name, or nil.
-- Matching uses:
--   1. Exact match against GetSpellInfo names (localized, for Shaman imbues).
--   2. Exact match against choice labels (English fallback for consumables).
--   3. Substring match against the above, longest-first, to handle rank
--      prefixes such as "Dense Sharpening Stone" → key "sharpening".
function Config:GetWeaponEnchantKeyFromName(enchantName)
    if not _enchantExactMap then
        _enchantExactMap   = {}
        _enchantSubstrList = {}
        local seen = {}  -- deduplicate names
        for _, choice in ipairs(self.WeaponEnchantChoices) do
            if choice.key ~= "any" then
                local names = {}
                -- Localized spell name (for Shaman imbues with a known auraId)
                if choice.auraId then
                    local spellName = GetSpellInfo(choice.auraId)
                    if spellName then names[spellName] = true end
                end
                -- English label as a fallback
                if choice.label and choice.label ~= "" then
                    names[choice.label] = true
                end
                for name in pairs(names) do
                    if not seen[name] then
                        seen[name] = true
                        _enchantExactMap[name] = choice.key
                        _enchantSubstrList[#_enchantSubstrList + 1] = { name = name, key = choice.key, len = #name }
                    end
                end
            end
        end
        -- Sort longest-first so more specific substrings match before shorter ones.
        table.sort(_enchantSubstrList, function(a, b) return a.len > b.len end)
    end

    -- 1. Exact match
    local key = _enchantExactMap[enchantName]
    if key then return key end

    -- 2. Substring match (handles rank variants like "Dense Sharpening Stone" or "Grand Firestone")
    for _, entry in ipairs(_enchantSubstrList) do
        if enchantName:find(entry.name, 1, true) then
            return entry.key
        end
    end

    return nil
end

-- ==========================================================
-- TOTEM HELPERS
-- ==========================================================

-- Returns true if spellId is a known shaman totem spell.
function Config:IsTotemSpell(spellId)
    return self.TotemSpells[spellId] ~= nil
end

-- Returns the sentinel totem element ID (e.g. FIRE_TOTEM_ID) for a given
-- totem spell ID, or nil if the spell is not a known totem.
function Config:GetTotemIdForSpell(spellId)
    return self.TotemSpells[spellId]
end

-- Returns the GetTotemInfo slot index (1-4) for a sentinel totem ID, or nil.
function Config:GetTotemSlot(totemId)
    return self.TotemSlot[totemId]
end

-- Returns the default element name string for a sentinel totem ID.
function Config:GetTotemElementName(totemId)
    return self.TotemElementName[totemId] or "Totem"
end

-- Representative spell IDs per element used as a generic icon when no specific
-- totem spell is stored for an element tracker (e.g. in the settings panel).
Config.TotemElementSpell = {
    [-10] = 3599,   -- Searing Totem I  (fire)
    [-11] = 2484,   -- Earthbind Totem  (earth)
    [-12] = 5394,   -- Healing Stream Totem I  (water)
    [-13] = 8512,   -- Windfury Totem I  (air)
}

-- Returns a generic icon texture for the given sentinel totem ID, or nil.
function Config:GetTotemElementIcon(totemId)
    local spellId = self.TotemElementSpell[totemId]
    if spellId then
        local _, _, texture = GetSpellInfo(spellId)
        return texture
    end
    return nil
end