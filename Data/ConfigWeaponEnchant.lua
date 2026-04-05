local _, ns = ...
local Config = ns.AuraTracker.Config

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
