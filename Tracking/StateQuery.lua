local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

-- Pure WoW API query functions that return plain state tables.
-- No side effects; callers are responsible for applying results to TrackedItems.

local GetTime = GetTime
local GetSpellCooldown = GetSpellCooldown
local GetItemCooldown = GetItemCooldown
local UnitAura = UnitAura
local UnitName = UnitName
local UnitExists = UnitExists
local GetSpellInfo = GetSpellInfo
local math_abs = math.abs

local StateQuery = {}
ns.AuraTracker.StateQuery = StateQuery

-- ==========================================================
-- COOLDOWN QUERY
-- ==========================================================

--- Query a spell's cooldown state and return a plain state table.
--- @param spellId     number   Spell ID to query
--- @param gcdStart    number|nil  GCD start time (from UpdateEngine)
--- @param gcdDuration number|nil  GCD duration
--- @param ignoreGCD   boolean  If true, treat GCD as "ready"
--- @param prevEnd     number|nil  Previously stored actualCooldownEnd for this item
--- @return table { active, duration, expiration, actualCooldownEnd }
function StateQuery.QueryCooldown(spellId, gcdStart, gcdDuration, ignoreGCD, prevEnd)
    local start, duration, enabled = GetSpellCooldown(spellId)
    local now = GetTime()

    if not start or enabled ~= 1 then
        return { active = false, duration = 0, expiration = 0, actualCooldownEnd = nil }
    end

    if duration == 0 then
        return { active = true, duration = 0, expiration = 0, actualCooldownEnd = nil }
    end

    local cooldownEnd = start + duration

    local isGCD = false
    if gcdStart and gcdDuration then
        isGCD = math_abs(start - gcdStart) < 0.05 and math_abs(duration - gcdDuration) < 0.05
    end

    if prevEnd and prevEnd > now then
        return { active = false, duration = duration, expiration = prevEnd, actualCooldownEnd = prevEnd }
    end

    if ignoreGCD and isGCD then
        return { active = true, duration = 0, expiration = 0, actualCooldownEnd = nil }
    end

    return { active = false, duration = duration, expiration = cooldownEnd, actualCooldownEnd = cooldownEnd }
end

-- ==========================================================
-- ITEM COOLDOWN QUERY
-- ==========================================================

--- Query an item's cooldown state and return a plain state table.
--- @param itemId  number  Item ID
--- @return table { active, duration, expiration }
function StateQuery.QueryItemCooldown(itemId)
    local start, duration, enabled = GetItemCooldown(itemId)

    if not start or enabled ~= 1 then
        return { active = false, duration = 0, expiration = 0 }
    end

    if duration == 0 then
        return { active = true, duration = 0, expiration = 0 }
    end

    return { active = false, duration = duration, expiration = start + duration }
end

-- ==========================================================
-- AURA QUERY
-- ==========================================================

--- Query a single-unit aura and return a plain state table.
--- @param unit    string   Unit token (e.g. "player", "target")
--- @param name    string   Aura name to search for
--- @param filter  string   "HELPFUL" or "HARMFUL"
--- @return table { active, duration, expiration, stacks, srcName, destName }
function StateQuery.QueryAura(unit, name, filter)
    local auraName, _, _, count, _, duration, expiration, casterUnit =
        UnitAura(unit, name, nil, filter)

    if auraName then
        return {
            active     = true,
            duration   = duration or 0,
            expiration = expiration or 0,
            stacks     = count or 0,
            srcName    = casterUnit and (UnitName(casterUnit) or "") or "",
            destName   = UnitName(unit) or "",
        }
    end

    return {
        active     = false,
        duration   = 0,
        expiration = 0,
        stacks     = 0,
        srcName    = "",
        destName   = UnitName(unit) or "",
    }
end

--- Query an aura across an exclusive spell group (one icon tracks multiple spells).
--- Returns the first matching aura found, plus the texture of the active spell.
--- @param unit          string   Unit token
--- @param filter        string   "HELPFUL" or "HARMFUL"
--- @param primaryAuraId number   Primary aura spell ID
--- @param groupSpells   table    [spellId]=true set of exclusive group spells
--- @param primaryName   string   Primary aura name (fallback match)
--- @param groupNames    table|nil [name]=true set (optional)
--- @return table { active, duration, expiration, stacks, srcName, destName, texture }
function StateQuery.QueryAuraExclusive(unit, filter, primaryAuraId, groupSpells,
                                       primaryName, groupNames)
    for i = 1, 40 do
        local name, _, _, count, _, duration, expiration, casterUnit, _, _, spellId =
            UnitAura(unit, i, filter)
        if not name then break end
        if spellId == primaryAuraId or groupSpells[spellId]
        or name == primaryName or (groupNames and groupNames[name]) then
            local _, _, tex = GetSpellInfo(spellId)
            return {
                active     = true,
                duration   = duration or 0,
                expiration = expiration or 0,
                stacks     = count or 0,
                srcName    = casterUnit and (UnitName(casterUnit) or "") or "",
                destName   = UnitName(unit) or "",
                texture    = tex,
            }
        end
    end
    return { active = false, duration = 0, expiration = 0, stacks = 0,
             srcName = "", destName = UnitName(unit) or "", texture = nil }
end

--- Query an aura for any unit in a smart-group list.
--- Returns the first matching result (any group member has the aura).
--- @param units         table    List of unit tokens
--- @param name          string   Aura name
--- @param filter        string   "HELPFUL" or "HARMFUL"
--- @return table { active, duration, expiration, stacks, srcName, destName }
function StateQuery.QueryAuraSmartGroup(units, name, filter)
    for _, u in ipairs(units) do
        if UnitExists(u) then
            local result = StateQuery.QueryAura(u, name, filter)
            if result.active then
                return result
            end
        end
    end
    return { active = false, duration = 0, expiration = 0, stacks = 0,
             srcName = "", destName = "" }
end

--- Query an exclusive-group aura across all smart-group units.
--- @param units         table    List of unit tokens
--- @param filter        string   "HELPFUL" or "HARMFUL"
--- @param primaryAuraId number   Primary aura spell ID
--- @param groupSpells   table    [spellId]=true
--- @param primaryName   string   Primary aura name
--- @param groupNames    table|nil
--- @return table { active, duration, expiration, stacks, srcName, destName, texture }
function StateQuery.QueryAuraExclusiveSmartGroup(units, filter, primaryAuraId,
                                                  groupSpells, primaryName, groupNames)
    for _, u in ipairs(units) do
        if UnitExists(u) then
            local result = StateQuery.QueryAuraExclusive(
                u, filter, primaryAuraId, groupSpells, primaryName, groupNames)
            if result.active then
                return result
            end
        end
    end
    return { active = false, duration = 0, expiration = 0, stacks = 0,
             srcName = "", destName = "", texture = nil }
end
