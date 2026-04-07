local _, ns = ...

local state = ns.AuraTracker._MFState
local SU    = ns.AuraTracker.SettingsUtils

local table_insert, table_remove = table.insert, table.remove
local math_max = math.max
local GetCursorPosition = GetCursorPosition
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local StaticPopup_Show  = StaticPopup_Show
local CreateFrame       = CreateFrame

-- ======================================================
-- ROW POOL HELPERS
-- ======================================================

local function AcquireBarRow()
    local row = table_remove(state.barRowPool)
    if row then
        row:ClearAllPoints()
        row:Show()
        return row
    end
    local f = CreateFrame("Button", nil, state.scrollContent)
    f:SetHeight(state.ROW_H_BAR)
    f._type = "bar"

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    state.SetTexColor(bg, state.C_ROW_NORMAL)
    f._bg = bg

    local arrow = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    arrow:SetPoint("LEFT", f, "LEFT", 4, 0)
    f._arrow = arrow

    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", f, "LEFT", 24, 0)
    name:SetPoint("RIGHT", f, "RIGHT", -52, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    f._name = name

    -- Class badge (small colored rectangle)
    local badge = f:CreateTexture(nil, "OVERLAY")
    badge:SetSize(4, 18)
    badge:SetPoint("RIGHT", f, "RIGHT", -48, 0)
    badge:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    f._badge = badge

    -- Delete button
    local del = CreateFrame("Button", nil, f)
    del:SetSize(20, 20)
    del:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    del:SetNormalFontObject("GameFontNormalSmall")
    del:SetText("|cFFFF4444X|r")
    del:SetScript("OnEnter", function() del:SetText("|cFFFF0000X|r") end)
    del:SetScript("OnLeave", function() del:SetText("|cFFFF4444X|r") end)
    f._del = del

    f:SetScript("OnEnter", function(self)
        if self._selected then return end
        local cc = self._classColor
        if cc then
            state.SetTexColor(self._bg, state.ClassColor(cc, 0.45, 0.90))
        else
            state.SetTexColor(self._bg, state.C_ROW_HOVER)
        end
    end)
    f:SetScript("OnLeave", function(self)
        if self._selected then return end
        local cc = self._classColor
        if cc then
            state.SetTexColor(self._bg, state.ClassColor(cc, 0.30, 0.85))
        else
            state.SetTexColor(self._bg, state.C_ROW_NORMAL)
        end
    end)

    return f
end

local function ReleaseBarRow(row)
    row:Hide()
    row._classColor = nil
    table_insert(state.barRowPool, row)
end

local function AcquireIcoRow()
    local row = table_remove(state.icoRowPool)
    if row then
        row:ClearAllPoints()
        row:Show()
        return row
    end
    local f = CreateFrame("Button", nil, state.scrollContent)
    f:SetHeight(state.ROW_H_ICO)
    f._type = "icon"

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    state.SetTexColor(bg, state.C_ROW_NORMAL)
    f._bg = bg

    local ico = f:CreateTexture(nil, "ARTWORK")
    ico:SetSize(state.ICON_SIZE, state.ICON_SIZE)
    ico:SetPoint("LEFT", f, "LEFT", 30, 0)
    ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f._ico = ico

    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("LEFT", ico, "RIGHT", 5, 0)
    name:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    f._name = name

    f:SetScript("OnEnter", function(self)
        if self._selected then return end
        state.SetTexColor(self._bg, state.C_ROW_HOVER)
    end)
    f:SetScript("OnLeave", function(self)
        if self._selected then return end
        state.SetTexColor(self._bg, state.C_ROW_NORMAL)
    end)

    return f
end

local function ReleaseIcoRow(row)
    row:Hide()
    table_insert(state.icoRowPool, row)
end

-- ======================================================
-- LEFT PANEL  –  list rebuild
-- ======================================================

local function ClearActiveRows()
    for _, row in ipairs(state.activeRows) do
        if row._type == "bar" then
            ReleaseBarRow(row)
        else
            ReleaseIcoRow(row)
        end
    end
    state.activeRows = {}
end

local function SetRowSelected(row, sel)
    row._selected = sel
    if sel then
        local cc = row._classColor
        if cc then
            state.SetTexColor(row._bg, state.ClassColor(cc, 0.55, 1.0))
        else
            state.SetTexColor(row._bg, state.C_ROW_SEL)
        end
    else
        local cc = row._classColor
        if cc then
            state.SetTexColor(row._bg, state.ClassColor(cc, 0.30, 0.85))
        else
            state.SetTexColor(row._bg, state.C_ROW_NORMAL)
        end
    end
end

local function RebuildList()
    if not state.scrollContent then return end

    ClearActiveRows()

    local bars = state.GetSortedBars()
    local yOffset = 0

    for _, entry in ipairs(bars) do
        local barKey  = entry.key
        local barData = entry.data
        local expanded = state.expandedBars[barKey]
        local isSel    = (barKey == state.currentBar and state.currentIcon == nil)

        -- ── Bar row ──────────────────────────────────────────
        local row = AcquireBarRow()
        row._barKey = barKey

        -- Class badge color (must be set before SetRowSelected uses _classColor)
        local classKey = barData.classRestriction or "NONE"
        if classKey ~= "NONE" then
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classKey]
            if color then
                row._classColor = { color.r, color.g, color.b }
                row._badge:SetVertexColor(color.r, color.g, color.b, 1)
                row._badge:Hide() -- Note: We are hiding this, because this is just a class colored square currently!
            else
                row._classColor = nil
                row._badge:Hide()
            end
        else
            row._classColor = nil
            row._badge:Hide()
        end

        SetRowSelected(row, isSel)

        -- Arrow
        row._arrow:SetText(expanded and "|cFFAAAAAA-|r" or "|cFFAAAAAA+|r")

        -- Name
        local displayName = SU.GetBarDisplayName(barData, barKey)
        row._name:SetText(displayName)

        -- Delete handler (with confirmation popup)
        local capturedKey  = barKey
        local capturedName = barData.name or barKey
        row._del:SetScript("OnClick", function()
            StaticPopup_Show("AURATRACKER_CONFIRM_DELETE_BAR", capturedName, nil, {
                fn = function()
                    local ctrl = state.GetController()
                    if not ctrl then return end
                    ctrl:DeleteBar(capturedKey)
                    if state.currentBar == capturedKey then
                        state.currentBar  = nil
                        state.currentIcon = nil
                        SU.editState.selectedBar  = nil
                        SU.editState.selectedAura = nil
                    end
                    SU.NotifyChange()
                end
            })
        end)

        -- Click to select / expand
        row:SetScript("OnClick", function(self, btn)
            if btn == "LeftButton" then
                -- Toggle expand only if clicking the arrow area (x < 20)
                -- Otherwise select the bar
                local x = GetCursorPosition()
                local fx = self:GetLeft()
                local scale = self:GetEffectiveScale()
                local localX = (x / scale) - fx
                if localX <= 20 then
                    state.expandedBars[barKey] = not state.expandedBars[barKey]
                    RebuildList()
                else
                    state.currentBar  = barKey
                    state.currentIcon = nil
                    SU.editState.selectedBar  = barKey
                    SU.editState.selectedAura = nil
                    RebuildList()
                    state.RightPanelShowBar(barKey)
                end
            end
        end)

        row:SetPoint("TOPLEFT",  state.scrollContent, "TOPLEFT",  0, -yOffset)
        row:SetPoint("TOPRIGHT", state.scrollContent, "TOPRIGHT", 0, -yOffset)
        table_insert(state.activeRows, row)
        yOffset = yOffset + state.ROW_H_BAR

        -- ── Icon rows (when expanded) ─────────────────────────
        if expanded then
            local icons = state.GetSortedIcons(barData)
            for _, iconEntry in ipairs(icons) do
                local spellId  = iconEntry.spellId
                local iconData = iconEntry.data
                local isIconSel = (barKey == state.currentBar and state.currentIcon == spellId)

                local irow = AcquireIcoRow()
                irow._barKey  = barKey
                irow._spellId = spellId
                SetRowSelected(irow, isIconSel)

                -- Icon texture
                local tex = state.GetIconTexture(spellId, iconData.trackType)
                irow._ico:SetTexture(tex)

                -- Name + track type label
                local spellName = SU.GetTrackedNameAndIcon(spellId, iconData.trackType)
                local typeLabel = SU.GetTrackTypeLabel(iconData.trackType, iconData.type)
                irow._name:SetText(spellName .. "  " .. typeLabel)

                -- Click to select icon
                local cBarKey  = barKey
                local cSpellId = spellId
                irow:SetScript("OnClick", function()
                    state.currentBar  = cBarKey
                    state.currentIcon = cSpellId
                    SU.editState.selectedBar  = cBarKey
                    SU.editState.selectedAura = cSpellId
                    RebuildList()
                    state.RightPanelShowIcon(cBarKey, cSpellId)
                end)

                irow:SetPoint("TOPLEFT",  state.scrollContent, "TOPLEFT",  0, -yOffset)
                irow:SetPoint("TOPRIGHT", state.scrollContent, "TOPRIGHT", 0, -yOffset)
                table_insert(state.activeRows, irow)
                yOffset = yOffset + state.ROW_H_ICO
            end
        end

        -- Thin separator line after each bar block
        yOffset = yOffset + 2
    end

    if #bars == 0 then
        yOffset = 40
    end

    state.scrollContent:SetHeight(math_max(yOffset, 10))
end

-- Export to state so MainFrame.lua can call them
state.RebuildList    = RebuildList
state.ClearActiveRows = ClearActiveRows
