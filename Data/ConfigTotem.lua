local _, ns = ...
local Config = ns.AuraTracker.Config

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