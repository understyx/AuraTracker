local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

-- Lookup methods for Config.  The data tables (TrackType, DisplayMode, etc.)
-- are defined in Config.lua which loads before this file.

local Config = ns.AuraTracker.Config

-- Returns the preset key a spell belongs to, or nil.
function Config:GetPresetForSpell(spellId)
    return self.SpellToPreset[spellId]
end

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
    if trackType == self.TrackType.CUSTOM_ICD then
        return self.DefaultDisplayMode.CUSTOM_ICD
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
