local _, ns = ...
local Config = ns.AuraTracker.Config

-- Internal cooldown durations in seconds for each proc spell ID.
-- Default ICD when a proc is not listed here is 45 seconds.
Config.TrinketProcCooldowns = {
    [60486] = 0,
    [60525] = 0,
    [60314] = 0,
    [60196] = 0,
    [71575] = 0,
    [71577] = 0,
    [71570] = 0,
    [71572] = 0,
    [71432] = 0,
    [71396] = 0,
    [65006] = 0,
    [71600] = 0,
    [71643] = 0,
    [67696] = 0,
    [67750] = 0,
    [67713] = 0,
    [67759] = 0,
    [72416] = 60,
    [72412] = 60,
    [72418] = 60,
    [72414] = 60,
    [51348] = 10,
    [51353] = 10,
    [54808] = 60,
    [55018] = 60,
    [71485] = 105,
    [71492] = 105,
    [71486] = 105,
    [71484] = 105,
    [71491] = 105,
    [71487] = 105,
    [71556] = 105,
    [71560] = 105,
    [71558] = 105,
    [71561] = 105,
    [71559] = 105,
    [71557] = 105,
    [71605] = 90,
    [71636] = 90,
    [55637] = 60,    -- Lightweave Embroidery
    [55775] = 60,    -- Swordguard Embroidery
    [55767] = 60,    -- Darkglow Embroidery
    [59626] = 35,    -- Black Magic
    [59620] = 0,     -- Berserking
    [28093] = 0,     -- Mongoose
    [64440] = 0,     -- Blade Ward
    [64568] = 10,    -- Blood Draining
    [42976] = 0,     -- Executioner
    [20007] = 0,     -- Crusader
    [53365] = 0,     -- Rune of the Fallen Crusader
    [34260] = 0,
    [43747] = 0,
    [43751] = 0,
    [43749] = 0,
    [43738] = 0,
    [43740] = 0,
    [43742] = 0,
    [41038] = 0,
    [41043] = 0,
    [57909] = 0,
    [60819] = 0,
    [60795] = 0,
    [60771] = 0,
    [62146] = 0,
    [60828] = 0,
    [60566] = 0,
    [60547] = 0,
    [60544] = 0,
    [60565] = 0,
    [60766] = 0,
    [60567] = 0,
    [60549] = 0,
    [64963] = 0,
    [65182] = 0,
    [64951] = 0,
    [60568] = 0,
    [60551] = 0,
    [67371] = 0,
    [67364] = 0,
    [67378] = 0,
    [67388] = 8,
    [67385] = 0,
    [67391] = 0,
    [67354] = 0,
    [67355] = 0,
    [67360] = 0,
    [67358] = 0,
    [67380] = 0,
    [67383] = 0,
    [60569] = 0,
    [60553] = 0,
    [71184] = 0,
    [71187] = 0,
    [71175] = 0,
    [71177] = 0,
    [71199] = 0,
    [71227] = 0,
    [71192] = 0,
    [71197] = 0,
    [71229] = 0,
    [71216] = 0,
    [71220] = 0,
    [60555] = 0,
    [60570] = 0,
}

Config.DEFAULT_ICD = 45

-- ==========================================================
-- REVERSE LOOKUP: proc spell ID -> list of item IDs
-- ==========================================================
Config.TrinketProcToItems = {}
for itemId, procData in pairs(Config.TrinketItemToProc) do
    if type(procData) == "number" then
        Config.TrinketProcToItems[procData] = Config.TrinketProcToItems[procData] or {}
        Config.TrinketProcToItems[procData][itemId] = true
    elseif type(procData) == "table" then
        for _, procId in ipairs(procData) do
            Config.TrinketProcToItems[procId] = Config.TrinketProcToItems[procId] or {}
            Config.TrinketProcToItems[procId][itemId] = true
        end
    end
end

-- ==========================================================
-- LOOKUP FUNCTIONS
-- ==========================================================

--- Returns the proc spell ID(s) for a given trinket item ID, or nil.
function Config:GetTrinketProcSpells(itemId)
    return self.TrinketItemToProc[itemId]
end

--- Returns the internal cooldown duration for a proc spell ID.
--- Falls back to DEFAULT_ICD (45s) if not explicitly listed.
function Config:GetTrinketProcCooldown(procSpellId)
    local cd = self.TrinketProcCooldowns[procSpellId]
    if cd then return cd end
    return self.DEFAULT_ICD
end

--- Returns true if the given item ID is a known trinket with ICD data.
function Config:IsTrinketWithICD(itemId)
    return self.TrinketItemToProc[itemId] ~= nil
end
