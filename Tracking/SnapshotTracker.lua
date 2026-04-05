local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local SnapshotTracker = ns.AuraTracker.SnapshotTracker

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
-- Start dirty so the first query triggers a full calculation.
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

-- Aliases for data tables defined in SnapshotData.lua
local TARGET_UNIT = SnapshotTracker._TARGET_UNIT
local masterPoisonerWhitelist = SnapshotTracker._masterPoisonerWhitelist
local noRecalcOnRefresh = SnapshotTracker._noRecalcOnRefresh
local indirectApplicators = SnapshotTracker._indirectApplicators
local critSchools = SnapshotTracker._critSchools
local critChanceTalents = SnapshotTracker._critChanceTalents
local critChanceSetBonuses = SnapshotTracker._critChanceSetBonuses
local critModDamageBonusTalents = SnapshotTracker._critModDamageBonusTalents
local critModDamageBonusBuffs = SnapshotTracker._critModDamageBonusBuffs
local critModDamageBonusSetBonuses = SnapshotTracker._critModDamageBonusSetBonuses
local critModBuffs = SnapshotTracker._critModBuffs
local critModMetaGems = SnapshotTracker._critModMetaGems
local critChanceEnemyDebuffs = SnapshotTracker._critChanceEnemyDebuffs
local critCategoryExclusiveWithMP = SnapshotTracker._critCategoryExclusiveWithMP
local critChanceEnemyMasterPoisonerDebuffs = SnapshotTracker._critChanceEnemyMasterPoisonerDebuffs
local damageModBuffs = SnapshotTracker._damageModBuffs
local damageModDebuffs = SnapshotTracker._damageModDebuffs
local damageModTalents = SnapshotTracker._damageModTalents
local damageModSetBonuses = SnapshotTracker._damageModSetBonuses
local damageModWeaponEnchants = SnapshotTracker._damageModWeaponEnchants
local damageModExecuteTalents = SnapshotTracker._damageModExecuteTalents
local damageModTrackingTalents = SnapshotTracker._damageModTrackingTalents
local GAME_LOCALE = SnapshotTracker._GAME_LOCALE
local localizations = SnapshotTracker._localizations
local trackingSpells = SnapshotTracker._trackingSpells
local DelocalizeTracking = SnapshotTracker._DelocalizeTracking

-- Master Poisoner crit bonus helper
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
    local exclusiveCritSeen = false  -- true if HotC or ToW is present
    local mpBonusValue = nil         -- MP bonus deferred until after the loop
    for i = 1, 40 do
        local name, _, _, count, _, _, _, source, _, _, spellId =
            UnitAura(TARGET_UNIT, i, "HARMFUL")
        if not name then break end

        local debuffVal = critChanceEnemyDebuffs[spellId]
        if debuffVal then
            local stacks = count or 0
            if stacks == 0 then stacks = 1 end
            critDebuff = critDebuff + debuffVal * stacks
            if critCategoryExclusiveWithMP[spellId] then
                exclusiveCritSeen = true
            end
        end

        if not mpBonusValue and critChanceEnemyMasterPoisonerDebuffs[spellId] then
            mpBonusValue = GetMasterPoisonerCritBonus(source, now)
        end
    end
    -- Master Poisoner shares the exclusive "spell-crit taken" category with
    -- Heart of the Crusader and Totem of Wrath; only add it when neither of
    -- those is already present, to avoid double-counting.
    if mpBonusValue and not exclusiveCritSeen then
        critDebuff = critDebuff + mpBonusValue
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
    -- WotLK 3.3.5 CLEU format: timestamp(1), subEvent(2), sourceGUID(3),
    -- sourceName(4), sourceFlags(5), destGUID(6), destName(7), destFlags(8),
    -- spellId(9), spellName(10), spellSchool(11), ...
    local _, subEvent, sourceGUID, _, _, destGUID, _, _, spellId, spellName = ...

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
