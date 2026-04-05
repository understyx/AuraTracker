local _, ns = ...
local AuraTracker = ns.AuraTracker.Controller
local Conditionals = ns.AuraTracker.Conditionals

local UnitClass = UnitClass
local GetNumTalentTabs = GetNumTalentTabs
local GetTalentInfo = GetTalentInfo
local wipe = wipe

-- ==========================================================
-- CLASS/TALENT RESTRICTION CHECK
-- ==========================================================

-- Cache for static (class + talent) visibility checks.
-- Keyed by barKey; value is true/false.
-- Populated lazily in ShouldShowBar; cleared by RebuildBar (per-bar)
-- and by OnTalentsChanged (all bars) since those are the only events
-- that can change the static result.
local barStaticCache = {}

function AuraTracker:InvalidateBarStaticCache(barKey)
    if barKey then
        barStaticCache[barKey] = nil
    else
        wipe(barStaticCache)
    end
end

function AuraTracker:ShouldShowBar(barKey)
    local db = self:GetBarDB(barKey)
    if not db or not db.enabled then
        return false
    end

    -- Static checks: class restriction + talent requirements.
    -- These never change mid-session except on talent events,
    -- so cache the result to avoid repeated API calls every tick.
    local staticOk = barStaticCache[barKey]
    if staticOk == nil then
        staticOk = true

        if db.classRestriction and db.classRestriction ~= "NONE" then
            local _, playerClass = UnitClass("player")
            if playerClass ~= db.classRestriction then
                staticOk = false
            end
        end

        -- Legacy single-talent-name check (backward compatibility)
        if staticOk and db.talentRestriction and db.talentRestriction ~= "NONE" then
            local SP = ns.AuraTracker.SettingsPanel
            if SP and not SP:CheckTalentRestriction(db.talentRestriction) then
                staticOk = false
            end
        end

        -- New multi-talent requirement check
        if staticOk and db.talentRequirements and next(db.talentRequirements) then
            local numTabs = GetNumTalentTabs and GetNumTalentTabs() or 0
            local maxTalents = MAX_NUM_TALENTS or 30
            if numTabs == 0 then
                -- Talent data not yet loaded at login; skip caching so this
                -- check re-runs next tick once data is available.
                return true
            end
            -- numTabs > 0 is guaranteed here; iterate the talent requirements.
            for combinedIndex, requiredState in pairs(db.talentRequirements) do
                local tab = math.ceil(combinedIndex / maxTalents)
                local talentIndex = combinedIndex - (tab - 1) * maxTalents
                if tab >= 1 and tab <= numTabs then
                    local _, _, _, _, rank = GetTalentInfo(tab, talentIndex)
                    local hasRank = rank and rank > 0
                    if requiredState == true and not hasRank then
                        staticOk = false
                        break
                    elseif requiredState == false and hasRank then
                        staticOk = false
                        break
                    end
                end
            end
        end

        barStaticCache[barKey] = staticOk
    end

    if not staticOk then return false end

    -- Dynamic checks: load conditions change at runtime (combat, mount, group, etc.)
    if db.loadConditions and #db.loadConditions > 0 then
        local Conditionals = ns.AuraTracker.Conditionals
        if Conditionals and not Conditionals:CheckAllLoadConditions(db.loadConditions) then
            return false
        end
    end

    -- Legacy: bar-level conditionals (old format, backward compat)
    if db.conditionals and #db.conditionals > 0 then
        local Conditionals = ns.AuraTracker.Conditionals
        if Conditionals and not Conditionals:CheckAll(db.conditionals, nil) then
            return false
        end
    end

    return true
end

