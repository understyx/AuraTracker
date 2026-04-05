local _, ns = ...

local Config = ns.AuraTracker.Config
local AuraTracker = ns.AuraTracker.Controller

local math_floor = math.floor
local string_char, string_byte = string.char, string.byte
local table = table
local type, pairs = type, pairs

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local B64_DECODE = {}
for i = 1, #B64_CHARS do
    B64_DECODE[B64_CHARS:sub(i, i)] = i - 1
end

local function B64Encode(data)
    local result = {}
    local len = #data
    local i = 1
    while i <= len do
        local b0 = string_byte(data, i)
        local b1 = string_byte(data, i + 1) or 0
        local b2 = string_byte(data, i + 2) or 0
        local n  = b0 * 65536 + b1 * 256 + b2
        result[#result + 1] = B64_CHARS:sub(math_floor(n / 262144) + 1, math_floor(n / 262144) + 1)
        result[#result + 1] = B64_CHARS:sub(math_floor((n % 262144) / 4096) + 1, math_floor((n % 262144) / 4096) + 1)
        result[#result + 1] = (i + 1 <= len) and B64_CHARS:sub(math_floor((n % 4096) / 64) + 1, math_floor((n % 4096) / 64) + 1) or "="
        result[#result + 1] = (i + 2 <= len) and B64_CHARS:sub((n % 64) + 1, (n % 64) + 1) or "="
        i = i + 3
    end
    return table.concat(result)
end

local function B64Decode(data)
    data = data:gsub("[^A-Za-z0-9+/=]", "")
    local result = {}
    local len = #data
    local i = 1
    while i + 3 <= len do
        local c0 = B64_DECODE[data:sub(i,     i    )] or 0
        local c1 = B64_DECODE[data:sub(i + 1, i + 1)] or 0
        local c2 = B64_DECODE[data:sub(i + 2, i + 2)] or 0
        local c3 = B64_DECODE[data:sub(i + 3, i + 3)] or 0
        local n  = c0 * 262144 + c1 * 4096 + c2 * 64 + c3
        result[#result + 1] = string_char(math_floor(n / 65536))
        if data:sub(i + 2, i + 2) ~= "=" then
            result[#result + 1] = string_char(math_floor((n % 65536) / 256))
        end
        if data:sub(i + 3, i + 3) ~= "=" then
            result[#result + 1] = string_char(n % 256)
        end
        i = i + 4
    end
    return table.concat(result)
end

local EXPORT_PREFIX = "ATv1:"

local function FindUniqueBarKey(dbBars, baseKey)
    local candidate = baseKey
    local counter   = 1
    while dbBars[candidate] do
        candidate = baseKey .. counter
        counter   = counter + 1
    end
    return candidate
end

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = DeepCopy(v) end
    return copy
end

function AuraTracker:ExportBar(barKey)
    local db = self:GetBarDB(barKey)
    if not db then return nil, "Bar not found" end

    local exportData = {
        name             = db.name,
        direction        = db.direction,
        iconSize         = db.iconSize,
        spacing          = db.spacing,
        scale            = db.scale,
        textSize         = db.textSize,
        showCooldownText = db.showCooldownText,
        ignoreGCD        = db.ignoreGCD,
        trackedItems     = db.trackedItems,
        loadConditions   = db.loadConditions,
    }

    local AceSerializer = LibStub("AceSerializer-3.0")
    local serialized = AceSerializer:Serialize(exportData)
    return EXPORT_PREFIX .. B64Encode(serialized)
end

function AuraTracker:ImportBar(str, newBarKey)
    if not str or str == "" then
        return false, "Empty import string"
    end
    if str:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return false, "Invalid format – string must start with " .. EXPORT_PREFIX
    end

    local encoded = str:sub(#EXPORT_PREFIX + 1)
    local decoded = B64Decode(encoded)
    if not decoded or decoded == "" then
        return false, "Failed to decode import string"
    end

    local AceSerializer = LibStub("AceSerializer-3.0")
    local ok, exportData = AceSerializer:Deserialize(decoded)
    if not ok or type(exportData) ~= "table" then
        return false, "Failed to parse import data"
    end

    local db = self:GetDB()
    local baseKey = (newBarKey and newBarKey ~= "") and newBarKey
                    or (exportData.name and exportData.name:gsub("[^%w]", ""))
                    or "ImportedBar"
    newBarKey = FindUniqueBarKey(db.bars, baseKey)

    db.bars[newBarKey] = {
        enabled          = true,
        name             = exportData.name or newBarKey,
        direction        = exportData.direction or "HORIZONTAL",
        iconSize         = exportData.iconSize or 40,
        spacing          = exportData.spacing or 2,
        scale            = exportData.scale or 1.0,
        textSize         = exportData.textSize or 12,
        showCooldownText = exportData.showCooldownText ~= false,
        ignoreGCD        = exportData.ignoreGCD ~= false,
        trackedItems     = exportData.trackedItems or {},
        loadConditions   = exportData.loadConditions or {},
        point            = "CENTER",
        x                = 0,
        y                = -300,
        textColor        = { r = 1, g = 1, b = 1, a = 1 },
    }

    self:RebuildBar(newBarKey)
    return true, newBarKey
end

function AuraTracker:ImportExampleBar(exampleIndex, newBarKey)
    local example = Config.ExampleBars and Config.ExampleBars[exampleIndex]
    if not example then return false, "Example not found" end

    local db = self:GetDB()

    local baseKey = (newBarKey and newBarKey ~= "") and newBarKey
                    or (example.name and example.name:gsub("[^%w]", ""))
                    or "ExampleBar"
    newBarKey = FindUniqueBarKey(db.bars, baseKey)

    local d = DeepCopy(example.data or {})

    d.enabled          = true
    d.name             = example.name or newBarKey
    d.direction        = d.direction        or "HORIZONTAL"
    d.iconSize         = d.iconSize         or 40
    d.spacing          = d.spacing          or 2
    d.scale            = d.scale            or 1.0
    d.textSize         = d.textSize         or 12
    d.showCooldownText = d.showCooldownText ~= false
    d.ignoreGCD        = d.ignoreGCD        ~= false
    d.trackedItems     = d.trackedItems     or {}
    d.loadConditions   = d.loadConditions   or {}
    d.textColor        = d.textColor        or { r = 1, g = 1, b = 1, a = 1 }
    d.point = "CENTER"
    d.x     = 0
    d.y     = -300

    db.bars[newBarKey] = d

    self:RebuildBar(newBarKey)
    return true, newBarKey
end
