local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local SnapshotTracker = {}
ns.AuraTracker.SnapshotTracker = SnapshotTracker

-- Localize frequently-used globals
local pairs, ipairs, select, type = pairs, ipairs, select, type
local math_floor = math.floor
local string_match = string.match
local GetTime = GetTime
local UnitAura = UnitAura
local UnitGUID = UnitGUID
local UnitLevel = UnitLevel
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitDamage = UnitDamage
local UnitClass = UnitClass
local UnitCreatureType = UnitCreatureType
local GetSpellCritChance = GetSpellCritChance
local GetTalentInfo = GetTalentInfo
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local GetInventoryItemLink = GetInventoryItemLink
local GetLocale = GetLocale
local INVSLOT_HEAD = INVSLOT_HEAD

-- Minimap tracking API (C_Minimap in Classic, global in original WotLK)
local GetNumTrackingTypes = C_Minimap and C_Minimap.GetNumTrackingTypes or GetNumTrackingTypes
local GetTrackingInfo = C_Minimap and C_Minimap.GetTrackingInfo or GetTrackingInfo

-- Module-private state
local playerClass = nil
local playerGUID = nil
local snapshots = {}        -- [destGUID][spellName] = { damageMod, critChance }
local masterPoisoners = {}  -- [rogueGUID] = expirationTime
local MASTER_POISONER_WINDOW = 3
local recentDirectDotCasts = {} -- [destGUID][dotSpellId] = expiryTime
local DIRECT_CAST_WINDOW = 2

-- Per-frame cache for expensive calculations
local cachedDamageMod, cachedCritChance, cachedCritDamage
local cacheTime = 0
local CACHE_TTL = 0.25
local cacheIsDirty = true

-- ==========================================================
-- HELPERS
-- ==========================================================

local function Round(num, nearest)
    nearest = nearest or 1
    local lower = math_floor(num / nearest) * nearest
    local upper = lower + nearest
    return (upper - num < num - lower) and upper or lower
end

local function GetNumSetItemsEquipped(setId)
    if WeakAuras and WeakAuras.GetNumSetItemsEquipped then
        return WeakAuras.GetNumSetItemsEquipped(setId)
    end
    return 0
end

-- ==========================================================
-- CLASS-SPECIFIC DATA TABLES
-- ==========================================================

-- The unit used for target-dependent calculations (level, debuffs, health)
local TARGET_UNIT = "target"

local masterPoisonerWhitelist = {
    [1329]  = true, -- Mutilate (Rank 1)
    [34411] = true, -- Mutilate (Rank 2)
    [34412] = true, -- Mutilate (Rank 3)
    [34413] = true, -- Mutilate (Rank 4)
    [48663] = true, -- Mutilate (Rank 5)
    [48666] = true, -- Mutilate (Rank 6)
}

-- DoTs refreshed through talents/glyphs keep their original snapshot.
-- Only a fresh SPELL_AURA_APPLIED recalculates damage/crit modifiers.
-- A manual recast (detected via SPELL_CAST_SUCCESS) also recalculates.
local noRecalcOnRefresh = {
    -- Warlock: Corruption — refreshed by Everlasting Affliction
    [172]   = true, [6222]  = true, [6223]  = true, [7648]  = true,
    [11671] = true, [11672] = true, [25311] = true, [27216] = true,
    [47812] = true, [47813] = true,
    -- Hunter: Serpent Sting — refreshed by Chimera Shot
    [1978]  = true, [13549] = true, [13550] = true, [13551] = true,
    [13552] = true, [13553] = true, [13554] = true, [13555] = true,
    [25295] = true, [27016] = true, [49000] = true, [49001] = true,
    -- DK: Blood Plague — refreshed by Pestilence (Glyph of Disease)
    [55078] = true,
    -- DK: Frost Fever — refreshed by Pestilence (Glyph of Disease)
    [55095] = true,
}

-- Abilities that directly (re)apply a noRecalcOnRefresh DoT via a different
-- spell (e.g. Plague Strike applies Blood Plague). Value = the DoT spell ID.
-- For Corruption/Serpent Sting the cast ID already matches the aura ID,
-- so they don't need entries here.
local indirectApplicators = {
    -- Plague Strike → Blood Plague (55078)
    [45462] = 55078, [49917] = 55078, [49918] = 55078,
    [49919] = 55078, [49920] = 55078, [49921] = 55078,
    -- Icy Touch → Frost Fever (55095)
    [45477] = 55095, [49896] = 55095, [49903] = 55095,
    [49904] = 55095, [49909] = 55095,
}

-- Spell crit school per class (shadow=6, nature=4, etc.)
local critSchools = {
    WARLOCK = 6,
    PRIEST  = 6,
    HUNTER  = 4,
}

-- Talent-based crit chance bonuses. Key = tab*100 + talentIndex, value = % per rank.
local critChanceTalents = {
    WARLOCK = {
        [116] = 3, -- Malediction
    },
    PRIEST = {
        [319] = 3, -- Mind Melt
    },
}

-- Set-bonus crit chance
local critChanceSetBonuses = {
    WARLOCK = {
        function() return GetNumSetItemsEquipped(884) >= 2 and 5 or nil end, -- T10 2set
    },
    PRIEST = {
        function() return GetNumSetItemsEquipped(886) >= 2 and 5 or nil end, -- T10 2set
    },
}

-- Talents that enable periodic crit damage bonus. Key = tab*100+index, value = bonus per rank.
local critModDamageBonusTalents = {
    WARLOCK = {
        [128] = 2, -- Pandemic
    },
}

-- Buffs that enable periodic crit damage bonus
local critModDamageBonusBuffs = {
    PRIEST = {
        [15473] = 2, -- Shadowform
    },
}

-- Set bonuses that enable periodic crit damage bonus
local critModDamageBonusSetBonuses = {
    HUNTER = {
        function() return GetNumSetItemsEquipped(859) >= 2 and 2 or nil end, -- T9 2set
    },
}

-- Buffs that multiply the crit damage value itself
local critModBuffs = {
    [65134] = 1.35, -- Storm Power (Hodir)
}

-- Meta gems that multiply crit damage
local critModMetaGems = {
    ["32409"] = 0.03,
    ["34220"] = 0.03,
    ["41285"] = 0.03,
    ["41398"] = 0.03,
}

-- Enemy debuffs that increase crit chance against the target
local critChanceEnemyDebuffs = {
    [17800] = 5, -- Shadow Mastery
    [22959] = 5, -- Improved Scorch
    [12579] = 1, -- Winter's Chill
    [21183] = 1, -- Heart of the Crusader (Rank 1)
    [54498] = 2, -- Heart of the Crusader (Rank 2)
    [54499] = 3, -- Heart of the Crusader (Rank 3)
    [30708] = 3, -- Totem of Wrath
}

-- Master Poisoner crit bonus helper
local function GetMasterPoisonerCritBonus(casterUnit, now)
    if casterUnit then
        local guid = UnitGUID(casterUnit)
        if guid then
            local expiry = masterPoisoners[guid]
            if expiry then
                if expiry > now then
                    return 3
                else
                    masterPoisoners[guid] = nil
                end
            end
        end
    end
    return nil
end

-- Poison spell IDs for Master Poisoner detection
local critChanceEnemyMasterPoisonerDebuffs = {
    [2818]  = true, -- Deadly Poison I
    [2819]  = true, -- Deadly Poison II
    [11353] = true, -- Deadly Poison III
    [11354] = true, -- Deadly Poison IV
    [25349] = true, -- Deadly Poison V
    [26968] = true, -- Deadly Poison VI
    [27187] = true, -- Deadly Poison VII
    [57969] = true, -- Deadly Poison VIII
    [57970] = true, -- Deadly Poison IX
    [13218] = true, -- Wound Poison I
    [13222] = true, -- Wound Poison II
    [13223] = true, -- Wound Poison III
    [13224] = true, -- Wound Poison IV
    [27189] = true, -- Wound Poison V
    [57974] = true, -- Wound Poison VI
    [57975] = true, -- Wound Poison VII
    [3409]  = true, -- Crippling Poison
    [5760]  = true, -- Mind-numbing Poison
}

-- Player buff damage modifiers (class-specific)
local damageModBuffs = {
    PRIEST = {
        [15473] = 0.15, -- Shadowform
        [15258] = 0.02, -- Shadow Weaving
    },
}

-- Player debuff damage modifiers (generic + class-specific)
local damageModDebuffs = {
    [63277] = 1, -- Shadow Crash (General Vezax)
    WARLOCK = {
        [40880] = -0.25, -- Prismatic Aura: Shadow (Mother Shahraz)
        [40897] = 0.25,  -- Prismatic Aura: Holy (Mother Shahraz)
    },
    PRIEST = {
        [40880] = -0.25, -- Prismatic Aura: Shadow
        [40897] = 0.25,  -- Prismatic Aura: Holy
    },
    HUNTER = {
        [40883] = -0.25, -- Prismatic Aura: Nature
        [40891] = 0.25,  -- Prismatic Aura: Arcane
    },
}

-- Talent damage modifiers
local damageModTalents = {
    HUNTER = {
        [208] = 0.1, -- Improved Stings
    },
}

-- Set-bonus damage modifiers
local damageModSetBonuses = {
    WARLOCK = {
        function() return GetNumSetItemsEquipped(529) >= 4 and 0.12 or nil end, -- T3 4set
        function() return GetNumSetItemsEquipped(646) >= 4 and 0.05 or nil end, -- T5 4set
        function() return GetNumSetItemsEquipped(846) >= 4 and 0.1 or nil end,  -- T9 4set
    },
    HUNTER = {
        function() return GetNumSetItemsEquipped(838) >= 2 and 0.1 or nil end, -- T8 2set
    },
}

-- Weapon enchant damage modifiers (class-specific)
local damageModWeaponEnchants = {
    WARLOCK = {
        [3615] = 0.01, -- Spellstone (Rank 1)
        [3616] = 0.01, -- Spellstone (Rank 2)
        [3617] = 0.01, -- Spellstone (Rank 3)
        [3618] = 0.01, -- Spellstone (Rank 4)
        [3619] = 0.01, -- Spellstone (Rank 5)
        [3620] = 0.01, -- Spellstone (Rank 6)
    },
}

-- Execute-range talent damage modifiers
local damageModExecuteTalents = {
    WARLOCK = {
        [123] = 0.04, -- Death's Embrace
    },
}

-- Tracking talent damage modifiers (Hunter)
local damageModTrackingTalents = {
    HUNTER = {
        [314] = 0.01, -- Improved Tracking
    },
}

-- ==========================================================
-- TRACKING LOCALIZATION (for Hunter Improved Tracking)
-- ==========================================================

local GAME_LOCALE = GetLocale()

local localizations = {
    enUS = {
        ["Beast"]     = "Beast",  ["Demon"]       = "Demon",
        ["Dragonkin"] = "Dragonkin", ["Elemental"] = "Elemental",
        ["Giant"]     = "Giant",  ["Humanoid"]    = "Humanoid",
        ["Undead"]    = "Undead",
    },
    deDE = {
        ["Wildtier"]  = "Beast",  ["D\195\164mon"]    = "Demon",
        ["Drachkin"]  = "Dragonkin", ["Elementar"]  = "Elemental",
        ["Riese"]     = "Giant",  ["Humanoid"]    = "Humanoid",
        ["Untoter"]   = "Undead",
    },
    frFR = {
        ["B\195\170te"]       = "Beast",  ["D\195\169mon"]      = "Demon",
        ["Draconien"]  = "Dragonkin", ["El\195\169mentaire"] = "Elemental",
        ["G\195\169ant"]      = "Giant",  ["Humano\195\175de"]  = "Humanoid",
        ["Mort-vivant"]= "Undead",
    },
    koKR = {
        ["\236\149\188\236\136\152"]     = "Beast",
        ["\236\149\133\235\167\136"]     = "Demon",
        ["\236\154\169\236\161\177"]     = "Dragonkin",
        ["\236\160\149\235\160\185"]     = "Elemental",
        ["\234\177\176\236\157\184"]     = "Giant",
        ["\236\157\184\234\176\132\237\152\149"] = "Humanoid",
        ["\236\150\184\235\141\176\235\147\156"] = "Undead",
    },
    esES = {
        ["Bestia"]    = "Beast",  ["Demonio"]     = "Demon",
        ["Drag\195\179n"]     = "Dragonkin", ["Elemental"]  = "Elemental",
        ["Gigante"]   = "Giant",  ["Humanoide"]   = "Humanoid",
        ["No-muerto"] = "Undead",
    },
    esMX = {
        ["Bestia"]    = "Beast",  ["Demonio"]     = "Demon",
        ["Dragon"]    = "Dragonkin", ["Elemental"]  = "Elemental",
        ["Gigante"]   = "Giant",  ["Humanoide"]   = "Humanoid",
        ["No-muerto"] = "Undead",
    },
    ptBR = {
        ["Fera"]          = "Beast",  ["Dem\195\180nio"]    = "Demon",
        ["Drac\195\180nico"]  = "Dragonkin", ["Elemental"]  = "Elemental",
        ["Gigante"]       = "Giant",  ["Humanoide"]   = "Humanoid",
        ["Morto-vivo"]    = "Undead",
    },
    itIT = {
        ["Bestia"]    = "Beast",  ["Demone"]      = "Demon",
        ["Dragoide"]  = "Dragonkin", ["Elementale"] = "Elemental",
        ["Gigante"]   = "Giant",  ["Umanoide"]    = "Humanoid",
        ["Non Morto"] = "Undead",
    },
    ruRU = {
        ["\208\150\208\184\208\178\208\190\209\130\208\189\208\190\208\181"] = "Beast",
        ["\208\148\208\181\208\188\208\190\208\189"]     = "Demon",
        ["\208\148\209\128\208\176\208\186\208\190\208\189"]     = "Dragonkin",
        ["\208\173\208\187\208\181\208\188\208\181\208\189\209\130\208\176\208\187\209\140"] = "Elemental",
        ["\208\146\208\181\208\187\208\184\208\186\208\176\208\189"]   = "Giant",
        ["\208\147\209\131\208\188\208\176\208\189\208\190\208\184\208\180"] = "Humanoid",
        ["\208\157\208\181\208\182\208\184\209\130\209\140"]     = "Undead",
    },
    zhCN = {
        ["\233\135\142\229\133\189"] = "Beast",
        ["\230\129\182\233\173\148"] = "Demon",
        ["\233\190\153\231\177\187"] = "Dragonkin",
        ["\229\133\131\231\180\160\231\148\159\231\137\169"] = "Elemental",
        ["\229\183\168\228\186\186"] = "Giant",
        ["\228\186\186\229\158\139\231\148\159\231\137\169"] = "Humanoid",
        ["\228\186\161\231\129\181"] = "Undead",
    },
    zhTW = {
        ["\233\135\142\231\184\189"] = "Beast",
        ["\230\131\161\233\173\148"] = "Demon",
        ["\233\190\141\233\161\158"] = "Dragonkin",
        ["\229\133\131\231\180\160\231\148\159\231\137\169"] = "Elemental",
        ["\229\183\168\228\186\186"] = "Giant",
        ["\228\186\186\229\158\139\231\148\159\231\137\169"] = "Humanoid",
        ["\228\184\141\230\173\187\230\151\143"] = "Undead",
    },
}

local trackingSpells = {
    [1494]  = "Beast",
    [19878] = "Demon",
    [19879] = "Dragonkin",
    [19880] = "Elemental",
    [19882] = "Giant",
    [19883] = "Humanoid",
    [19884] = "Undead",
}

local function DelocalizeTracking(localized)
    if not localized or not localizations[GAME_LOCALE] then return nil end
    return localizations[GAME_LOCALE][localized]
end

-- ==========================================================
-- INITIALIZATION
-- ==========================================================

function SnapshotTracker:Init(controller)
    self.controller = controller
    playerGUID = UnitGUID("player")
    playerClass = select(2, UnitClass("player"))
end

function SnapshotTracker:ResetPlayerInfo()
    playerGUID = UnitGUID("player")
    playerClass = select(2, UnitClass("player"))
end

-- ==========================================================
-- CALCULATION: CRIT CHANCE
-- ==========================================================

function SnapshotTracker:GetCritChance()
    local baseCrit = GetSpellCritChance(critSchools[playerClass] or 1)
    local now = GetTime()

    -- Talent-based crit (only one class-specific talent applies)
    local talentCrit = 0
    for indices, val in pairs(critChanceTalents[playerClass] or {}) do
        local talentIndex = indices % 100
        local tab = (indices - talentIndex) / 100
        local _, _, _, _, rank = GetTalentInfo(tab, talentIndex)
        if rank and rank > 0 then
            talentCrit = val * rank
            break -- only one talent applies per class
        end
    end

    -- Crit suppression based on target level
    local targetLevel = UnitLevel(TARGET_UNIT)
    local playerLevel = UnitLevel("player")
    if targetLevel == -1 then
        targetLevel = playerLevel + 3
    elseif targetLevel < playerLevel then
        targetLevel = playerLevel
    end
    local critSuppression = playerLevel - targetLevel

    -- Enemy debuffs that increase crit chance
    local critDebuff = 0
    local mpCounted = false
    for i = 1, 40 do
        local name, _, _, count, _, _, _, source, _, _, spellId =
            UnitAura(TARGET_UNIT, i, "HARMFUL")
        if not name then break end

        local debuffVal = critChanceEnemyDebuffs[spellId]
        if debuffVal then
            local stacks = count or 0
            if stacks == 0 then stacks = 1 end
            critDebuff = critDebuff + debuffVal * stacks
        end

        if not mpCounted and critChanceEnemyMasterPoisonerDebuffs[spellId] then
            local mpBonus = GetMasterPoisonerCritBonus(source, now)
            if mpBonus then
                critDebuff = critDebuff + mpBonus
                mpCounted = true
            end
        end
    end

    -- Set-bonus crit
    local critSet = 0
    for _, func in ipairs(critChanceSetBonuses[playerClass] or {}) do
        local val = func()
        if val then critSet = critSet + val end
    end

    return baseCrit + talentCrit + critDebuff + critSuppression + critSet
end

-- ==========================================================
-- CALCULATION: CRIT DAMAGE MULTIPLIER
-- ==========================================================

function SnapshotTracker:GetCritDamage()
    local critDamageBonus = 0
    local critDamage = 1.5

    -- Talent-based periodic crit damage bonus
    -- Talent-based periodic crit damage bonus (only one per class)
    for indices, val in pairs(critModDamageBonusTalents[playerClass] or {}) do
        local talentIndex = indices % 100
        local tab = (indices - talentIndex) / 100
        local _, _, _, _, rank = GetTalentInfo(tab, talentIndex)
        if rank and rank > 0 then
            critDamageBonus = val * rank
            break -- only one talent applies per class
        end
    end

    -- Buff-based periodic crit damage bonus (only used if no talent provides one)
    if critDamageBonus == 0 then
        local classBuffs = critModDamageBonusBuffs[playerClass]
        if classBuffs then
            for i = 1, 40 do
                local name, _, _, _, _, _, _, _, _, _, spellId =
                    UnitAura("player", i, "HELPFUL")
                if not name then break end
                local val = classBuffs[spellId]
                if val then
                    critDamageBonus = val
                    break -- only one buff source applies
                end
            end
        end
    end

    -- Set-bonus periodic crit damage bonus (fallback)
    if critDamageBonus == 0 then
        for _, func in ipairs(critModDamageBonusSetBonuses[playerClass] or {}) do
            local val = func()
            if val then critDamageBonus = val end
        end
    end

    if critDamageBonus == 0 then
        return 0
    end

    -- Buffs that multiply the crit damage value
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, _, spellId =
            UnitAura("player", i, "HELPFUL")
        if not name then break end
        local val = critModBuffs[spellId]
        if not val and critModBuffs[playerClass] then
            val = critModBuffs[playerClass][spellId]
        end
        if val then
            critDamage = critDamage * (1 + val)
            break
        end
    end

    -- Meta gem crit damage multiplier
    if INVSLOT_HEAD then
        local link = GetInventoryItemLink("player", INVSLOT_HEAD)
        if link then
            local g1, g2, g3, g4 = string_match(link,
                "item:%d+:[^:]*:([^:]*):([^:]*):([^:]*):([^:]*)")
            local gems = { g1, g2, g3, g4 }
            for _, gem in ipairs(gems) do
                if gem then
                    local val = critModMetaGems[gem]
                    if val then
                        critDamage = critDamage * (1 + val)
                        break
                    end
                end
            end
        end
    end

    return (critDamage - 1) * critDamageBonus
end

-- ==========================================================
-- CALCULATION: DAMAGE MODIFIER
-- ==========================================================

function SnapshotTracker:IsTrackingTarget()
    if not GetNumTrackingTypes or not GetTrackingInfo then
        return false
    end
    for i = 1, GetNumTrackingTypes() do
        local _, _, active, _, _, spellID = GetTrackingInfo(i)
        -- Tracking types without spell IDs (e.g. herbs, minerals) come after
        -- creature-tracking spells; stop once we reach them.
        if not spellID then break end
        if active then
            local creatureType = trackingSpells[spellID]
            -- Active tracking is not a creature-type spell (e.g. Find Fish)
            if not creatureType then break end
            return DelocalizeTracking(UnitCreatureType(TARGET_UNIT)) == creatureType
        end
    end
    return false
end

function SnapshotTracker:GetDamageMod()
    local damageMod = select(7, UnitDamage("player")) or 1

    -- Player buff modifiers (class-specific)
    local classBuffs = damageModBuffs[playerClass]
    if classBuffs then
        for i = 1, 40 do
            local name, _, _, count, _, _, _, _, _, _, spellId =
                UnitAura("player", i, "HELPFUL")
            if not name then break end
            local val = classBuffs[spellId]
            if val then
                local stacks = count or 0
                if stacks == 0 then stacks = 1 end
                damageMod = damageMod * (1 + val * stacks)
            end
        end
    end

    -- Player debuff modifiers (generic + class-specific)
    local classDebuffs = type(damageModDebuffs[playerClass]) == "table"
        and damageModDebuffs[playerClass] or nil
    for i = 1, 40 do
        local name, _, _, count, _, _, _, _, _, _, spellId =
            UnitAura("player", i, "HARMFUL")
        if not name then break end
        local val = damageModDebuffs[spellId]
        if not val and classDebuffs then
            val = classDebuffs[spellId]
        end
        if val then
            local stacks = count or 0
            if stacks == 0 then stacks = 1 end
            damageMod = damageMod * (1 + val * stacks)
        end
    end

    -- Talent modifiers
    for indices, val in pairs(damageModTalents[playerClass] or {}) do
        local talentIndex = indices % 100
        local tab = (indices - talentIndex) / 100
        local _, _, _, _, rank = GetTalentInfo(tab, talentIndex)
        if rank and rank > 0 then
            damageMod = damageMod * (1 + val * rank)
            break
        end
    end

    -- Set-bonus modifiers
    for _, func in ipairs(damageModSetBonuses[playerClass] or {}) do
        local val = func()
        if val then damageMod = damageMod * (1 + val) end
    end

    -- Weapon enchant modifiers
    local hasEnchant, _, _, enchantID = GetWeaponEnchantInfo()
    if hasEnchant and enchantID then
        local classEnchants = damageModWeaponEnchants[playerClass]
        local val = classEnchants and classEnchants[enchantID]
        if val then damageMod = damageMod * (1 + val) end
    end

    -- Execute-range talent modifiers
    for indices, val in pairs(damageModExecuteTalents[playerClass] or {}) do
        local talentIndex = indices % 100
        local tab = (indices - talentIndex) / 100
        local _, _, _, _, rank = GetTalentInfo(tab, talentIndex)
        if rank and rank > 0 then
            local maxHP = UnitHealthMax(TARGET_UNIT)
            if maxHP and maxHP > 0 and UnitHealth(TARGET_UNIT) / maxHP <= 0.35 then
                damageMod = damageMod * (1 + val * rank)
            end
            break
        end
    end

    -- Tracking talent modifiers (Hunter)
    for indices, val in pairs(damageModTrackingTalents[playerClass] or {}) do
        local talentIndex = indices % 100
        local tab = (indices - talentIndex) / 100
        local _, _, _, _, rank = GetTalentInfo(tab, talentIndex)
        if rank and rank > 0 then
            if self:IsTrackingTarget() then
                damageMod = damageMod * (1 + val * rank)
            end
            break
        end
    end

    return damageMod
end

-- ==========================================================
-- CACHED CALCULATION ACCESS
-- ==========================================================

local function GetCachedValues(self)
    local now = GetTime()
    if cacheIsDirty or (now - cacheTime > CACHE_TTL) then
        cachedDamageMod = self:GetDamageMod()
        cachedCritChance = self:GetCritChance()
        cachedCritDamage = self:GetCritDamage()
        cacheTime = now
        cacheIsDirty = false
    end
    return cachedDamageMod, cachedCritChance, cachedCritDamage
end

function SnapshotTracker:InvalidateCache()
    cacheIsDirty = true
end

-- ==========================================================
-- CLEU EVENT HANDLING
-- ==========================================================

function SnapshotTracker:ProcessEvent(subEvent, sourceGUID, destGUID, spellId, spellName)
    -- UNIT_DIED has no source; clean up regardless
    if subEvent == "UNIT_DIED" then
        if destGUID then
            snapshots[destGUID] = nil
            recentDirectDotCasts[destGUID] = nil
        end
        return
    end

    -- Master Poisoner: track Mutilate casts from any player
    if subEvent == "SPELL_CAST_SUCCESS" then
        if masterPoisonerWhitelist[spellId] then
            masterPoisoners[sourceGUID] = GetTime() + MASTER_POISONER_WINDOW
        end
        -- Track direct casts of noRecalcOnRefresh DoTs so we can
        -- distinguish manual recasts from talent/glyph refreshes.
        if sourceGUID == playerGUID and destGUID then
            local dotId = noRecalcOnRefresh[spellId] and spellId
                          or indirectApplicators[spellId]
            if dotId then
                if not recentDirectDotCasts[destGUID] then
                    recentDirectDotCasts[destGUID] = {}
                end
                recentDirectDotCasts[destGUID][dotId] = GetTime() + DIRECT_CAST_WINDOW
            end
        end
        return
    end

    -- For aura events, only track player-applied auras (no whitelist)
    if sourceGUID ~= playerGUID then return end

    if subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH" then
        if not spellName then return end
        -- Talent/glyph refreshes only extend the timer; they do not
        -- reapply the aura, so damage and crit snapshots stay unchanged.
        -- A manual recast (recent SPELL_CAST_SUCCESS for the same DoT)
        -- is allowed through so the snapshot is recalculated.
        if subEvent == "SPELL_AURA_REFRESH" and noRecalcOnRefresh[spellId]
           and snapshots[destGUID] and snapshots[destGUID][spellName] then
            local casts = recentDirectDotCasts[destGUID]
            local isDirectCast = casts and casts[spellId]
                                 and casts[spellId] > GetTime()
            if isDirectCast then
                casts[spellId] = nil  -- consume the flag
            else
                return  -- talent/glyph refresh: keep existing snapshot
            end
        end
        if not snapshots[destGUID] then
            snapshots[destGUID] = {}
        end
        self:InvalidateCache()
        local damageMod, critChance = GetCachedValues(self)
        snapshots[destGUID][spellName] = {
            damageMod  = damageMod,
            critChance = critChance,
        }
    elseif subEvent == "SPELL_AURA_REMOVED" then
        if spellName and snapshots[destGUID] then
            snapshots[destGUID][spellName] = nil
        end
    end
end

function SnapshotTracker:HandleCLEU(...)
    local subEvent, sourceGUID, destGUID, spellId, spellName

    if CombatLogGetCurrentEventInfo then
        -- WotLK Classic format (CombatLogGetCurrentEventInfo available)
        local _, se, _, sg, _, _, _, dg, _, _, _, si, sn = CombatLogGetCurrentEventInfo()
        subEvent, sourceGUID, destGUID, spellId, spellName = se, sg, dg, si, sn
    else
        -- Original WotLK format: args passed via event
        -- timestamp(1), subEvent(2), sourceGUID(3), sourceName(4), sourceFlags(5),
        -- destGUID(6), destName(7), destFlags(8), spellId(9), spellName(10), ...
        subEvent   = select(2, ...)
        sourceGUID = select(3, ...)
        destGUID   = select(6, ...)
        spellId    = select(9, ...)
        spellName  = select(10, ...)
    end

    if subEvent then
        self:ProcessEvent(subEvent, sourceGUID, destGUID, spellId, spellName)
    end
end

-- ==========================================================
-- QUERY API
-- ==========================================================

function SnapshotTracker:GetSnapshotDiff(unit, spellName)
    if not unit or not spellName then return nil end

    local guid = UnitGUID(unit)
    if not guid then return nil end

    local unitSnaps = snapshots[guid]
    if not unitSnaps then return nil end

    local snap = unitSnaps[spellName]
    if not snap then return nil end

    local damageMod, critChance, critDamage = GetCachedValues(self)

    -- critDamage (from talents/set bonuses) is intentionally shared between
    -- expected and current calculations: these modifiers are semi-permanent
    -- and don't change between DoT application and now. Only damageMod and
    -- critChance (which change with temporary buffs/debuffs) are snapshotted.
    local expectedTick = (100 + critChance * critDamage) * damageMod
    local currentTick  = (100 + snap.critChance * critDamage) * snap.damageMod

    if currentTick == 0 then return nil end

    local diff = Round((expectedTick / currentTick - 1) * 100, 0.1)

    if diff > 0 then
        return "|cff00ff00+" .. diff .. "%|r"
    elseif diff < 0 then
        return "|cffff0000" .. diff .. "%|r"
    end
    return nil  -- no diff worth showing at exactly 0
end

function SnapshotTracker:HasSnapshot(unit, spellName)
    if not unit or not spellName then return false end
    local guid = UnitGUID(unit)
    if not guid then return false end
    return snapshots[guid] and snapshots[guid][spellName] ~= nil
end
