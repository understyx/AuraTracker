local _, ns = ...
local Icon = ns.AuraTracker.Icon
local Config = ns.AuraTracker.Config
local LSM = LibStub("LibSharedMedia-3.0")
local string_format = string.format
local math_max = math.max
local math_floor = math.floor
local tostring = tostring

-- ==========================================================
-- CUSTOM TEXT OVERLAYS
-- ==========================================================

--- Substitute tokens in a format string with live values from the tracked item.
--- Available tokens:
---   %stacks / %count  – stack count
---   %remaining        – formatted time remaining (empty string when 0)
---   %progress         – "remaining/duration" in whole seconds (empty when no duration)
---   %name             – spell or item name
---   %srcName          – name of the aura caster (empty for non-aura types)
---   %destName         – name of the tracked unit (e.g. "Arthas")
function Icon:FormatCustomText(template)
    local item = self.trackedItem
    if not item then return template end

    local stacks    = item:GetStacks() or 0
    local remaining = item:GetRemaining() or 0
    local duration  = item:GetDuration() or 0
    local name      = item:GetName() or ""
    local srcName   = item:GetSrcName()
    local destName  = item:GetDestName()

    -- Use function-form replacements so that any '%' characters inside the
    -- substituted values are not interpreted as gsub escape sequences.
    local stackStr = tostring(stacks)
    local remainStr = remaining > 0 and self:FormatTime(remaining) or ""
    local progressStr = duration > 0
        and string_format("%.0f/%.0f", math_max(0, remaining), duration) or ""

    local result = template
    result = result:gsub("%%stacks",    function() return stackStr    end)
    result = result:gsub("%%count",     function() return stackStr    end)
    result = result:gsub("%%remaining", function() return remainStr   end)
    result = result:gsub("%%progress",  function() return progressStr end)
    result = result:gsub("%%name",      function() return name        end)
    result = result:gsub("%%srcName",   function() return srcName     end)
    result = result:gsub("%%destName",  function() return destName    end)
    return result
end

--- Create / configure extra FontStrings for each custom text entry.
--- Must be called after Icon:ApplyStyle() so the bar's font settings are available.
--- @param customTexts  array of { enabled, format, point, xOffset, yOffset, color }
--- @param styleOptions bar-level style options (font/fontSize/fontOutline)
function Icon:ApplyCustomTexts(customTexts, styleOptions)
    self.customTexts = customTexts  -- store for UpdateCustomTexts / RefreshBar

    local frame = self.frame
    frame.customTextStrings = frame.customTextStrings or {}

    local count = customTexts and #customTexts or 0

    -- Configure / create FontStrings for each custom text entry
    for i = 1, count do
        local ct = customTexts[i]
        local fs = frame.customTextStrings[i]
        if not fs then
            fs = frame:CreateFontString(nil, "OVERLAY")
            frame.customTextStrings[i] = fs
        end

        if ct.enabled ~= false then
            local fontSize    = ct.fontSize    or (styleOptions and styleOptions.fontSize) or 12
            local fontOutline = ct.fontOutline or (styleOptions and styleOptions.fontOutline) or "THICKOUTLINE"
            if fontOutline == "NONE" then fontOutline = "" end
            local fontPath = (styleOptions and styleOptions.font and LSM:Fetch("font", styleOptions.font))
                or [[Fonts\FRIZQT__.ttf]]
            fs:SetFont(fontPath, fontSize, fontOutline)

            local c = ct.color or { r = 1, g = 1, b = 1, a = 1 }
            fs:SetTextColor(c.r, c.g, c.b, c.a or 1)

            local point   = ct.point   or "BOTTOMRIGHT"
            local xOffset = ct.xOffset or 0
            local yOffset = ct.yOffset or 0
            fs:ClearAllPoints()
            fs:SetPoint(point, frame, point, xOffset, yOffset)

            fs:SetText("")  -- clear stale text from previous icon use
            fs:Show()
        else
            fs:Hide()
        end
    end

    -- Hide any FontStrings from a previous (larger) customTexts set.
    -- Do NOT call SetText here; the FontString is hidden so it won't display
    -- anything, and its text will be set fresh the next time it is reused.
    for i = count + 1, #frame.customTextStrings do
        local fs = frame.customTextStrings[i]
        if fs then
            fs:Hide()
        end
    end
end

--- Update the text content of all custom text FontStrings.
--- Called every 100 ms from UpdateEngine:UpdateAllCooldowns.
function Icon:UpdateCustomTexts()
    local ct = self.customTexts
    if not ct then return end
    local frame = self.frame
    if not frame.customTextStrings then return end

    for i, entry in ipairs(ct) do
        local fs = frame.customTextStrings[i]
        if fs and entry.enabled ~= false then
            local formatted = self:FormatCustomText(entry.format or "")
            fs:SetText(formatted)
        end
    end
end



-- ==========================================================
-- SNAPSHOT HELPERS
-- ==========================================================

-- Hides the snapshot diff overlay and resets the cooldown-text anchor back
-- to the icon centre.  Guards on _prevSnapshotActive so the WoW frame API
-- is only touched when a state transition actually occurs.
function Icon:HideSnapshotDisplay()
    self.frame.snapshotFrame:Hide()
    self.frame.text:ClearAllPoints()
    self.frame.text:SetPoint("CENTER")
    self._prevSnapshotActive = false
    self._prevSnapshotText   = nil
end

function Icon:UpdateSnapshotText()
    if not self.showSnapshotText or not self.trackedItem then
        if self._prevSnapshotActive ~= false then
            self:HideSnapshotDisplay()
        end
        return
    end

    local item = self.trackedItem
    local tt = item:GetTrackType()

    -- Only show for active aura-type items
    local isAuraActive = false
    if tt == Config.TrackType.AURA then
        isAuraActive = item:IsActive()
    elseif tt == Config.TrackType.COOLDOWN_AURA then
        isAuraActive = item:IsAuraActive()
    end

    if not isAuraActive then
        if self._prevSnapshotActive ~= false then
            self:HideSnapshotDisplay()
        end
        return
    end

    -- Lazily resolve SnapshotTracker reference
    if not SnapshotTracker then
        SnapshotTracker = ns.AuraTracker.SnapshotTracker
    end
    if not SnapshotTracker then
        if self._prevSnapshotActive ~= false then
            self:HideSnapshotDisplay()
        end
        return
    end

    local unit = item.unit
    local spellName = item:GetName()
    local diffText = SnapshotTracker:GetSnapshotDiff(unit, spellName)

    if diffText then
        -- Update text and resize frame only when text changes
        if self._prevSnapshotText ~= diffText then
            self.frame.snapshotText:SetText(diffText)
            self._prevSnapshotText = diffText
            local th = self.frame.snapshotText:GetStringHeight()
            self.frame.snapshotFrame:SetSize(math_max(1, self.frame:GetWidth()), math_max(1, th + 2))
        end
        -- Show on state transition
        if self._prevSnapshotActive ~= true then
            self.frame.snapshotFrame:Show()
            self._prevSnapshotActive = true
        end
    else
        if self._prevSnapshotActive ~= false then
            self.frame.snapshotFrame:Hide()
            self._prevSnapshotActive = false
            self._prevSnapshotText   = nil
        end
    end
end

-- ==========================================================
-- STYLING
-- ==========================================================

function Icon:ApplyStyle(styleOptions)
    styleOptions = styleOptions or {}

    local size = styleOptions.size or 40
    self.frame:SetSize(size, size)

    local fontSize = styleOptions.fontSize or 12
    local fontOutline = styleOptions.fontOutline or "THICKOUTLINE"
    if fontOutline == "NONE" then fontOutline = "" end

    local fontPath = (styleOptions.font and LSM:Fetch("font", styleOptions.font))
        or [[Fonts\FRIZQT__.ttf]]

    self.frame.text:SetFont(fontPath, fontSize, fontOutline)
    self.frame.stackText:SetFont(
        fontPath,
        fontSize * 0.9,
        fontOutline
    )
    self.frame.snapshotText:SetFont(
        fontPath,
        styleOptions.snapshotFontSize or (fontSize * 0.8),
        fontOutline
    )

    -- Snapshot frame sits above the glow border (border = level+1, snapshot = level+2)
    self.frame.snapshotFrame:SetFrameLevel(self.frame:GetFrameLevel() + 2)
    local snapshotBGAlpha = styleOptions.showSnapshotBG == false and 0 or (styleOptions.snapshotBGAlpha or 1.0)
    self.frame.snapshotBG:SetAlpha(snapshotBGAlpha)

    if self.frame.border then
        self.frame.border:SetFrameLevel(self.frame:GetFrameLevel() + 1)
        self.frame.border:SetBackdropBorderColor(0, 0, 0, 1)
    end

    local c = styleOptions.textColor or { r = 1, g = 1, b = 1, a = 1 }
    self.frame.text:SetTextColor(c.r, c.g, c.b, c.a)

    self.showCooldownText = styleOptions.showCooldownText ~= false
    if self.showCooldownText then
        self.frame.text:Show()
    else
        self.frame.text:Hide()
    end
end