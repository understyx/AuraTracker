local addonName, ns = ...

local SU           = ns.AuraTracker.SettingsUtils
local LibEditmode  = LibStub("LibEditmode-1.0", true)
local AceGUI       = LibStub("AceGUI-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local pairs, ipairs = pairs, ipairs
local table_insert, table_sort, table_remove = table.insert, table.sort, table.remove
local string_format = string.format
local math_floor, math_max = math.floor, math.max
local GetSpellInfo, GetItemInfo = GetSpellInfo, GetItemInfo

-- ======================================================
-- CONSTANTS
-- ======================================================

local FRAME_W        = 920
local FRAME_H        = 660
local LEFT_W         = 252   -- left panel pixel width
local TITLE_H        = 28    -- title bar height
local TOP_TOOLBAR_H  = 36    -- full-width toolbar below title bar
local INPUT_AREA_H   = 30    -- reserved space at top of left panel for new-bar input
local PAD            = 6     -- general padding
local ROW_H_BAR      = 28    -- bar row height in list
local ROW_H_ICO      = 23    -- icon row height in list
local ICON_SIZE      = 18    -- icon texture size in list

-- Right panel dimensions (filled by anchors, but AceGUI needs explicit size)
local RIGHT_W = FRAME_W - LEFT_W - 1 - PAD * 3  -- 1 = divider
local RIGHT_H = FRAME_H - TITLE_H - TOP_TOOLBAR_H - PAD * 4

-- Colours
local C_TITLE_BG    = { 0.10, 0.10, 0.10, 1.0 }
local C_LEFT_BG     = { 0.08, 0.08, 0.08, 1.0 }
local C_MAIN_BG     = { 0.05, 0.05, 0.05, 0.96 }
local C_DIVIDER     = { 0.20, 0.20, 0.20, 1.0 }
local C_ROW_SEL     = { 0.20, 0.35, 0.55, 0.80 }
local C_ROW_HOVER   = { 0.18, 0.18, 0.18, 0.90 }
local C_ROW_NORMAL  = { 0.00, 0.00, 0.00, 0.00 }

-- ======================================================
-- PRIVATE STATE
-- ======================================================

local mainFrame      = nil
local scrollFrame    = nil
local scrollContent  = nil
local rightGroup     = nil   -- AceGUI SimpleGroup used as right panel

local expandedBars   = {}    -- [barKey] = true/false
local currentBar     = nil   -- selected bar key (or nil)
local currentIcon    = nil   -- selected icon id  (or nil)

-- Row button pools (bar rows and icon rows are different heights)
local barRowPool  = {}
local icoRowPool  = {}
local activeRows  = {}  -- rows currently in use (in display order)

-- new-bar input state
local newBarInput = nil   -- EditBox widget (created once)

-- ======================================================
-- HELPERS
-- ======================================================

local function GetController()
    return ns.AuraTracker and ns.AuraTracker.Controller
end

local function GetSortedBars()
    local ctrl = GetController()
    if not ctrl then return {} end
    local bars = ctrl:GetBars()
    local list = {}
    for key, data in pairs(bars) do
        table_insert(list, { key = key, data = data })
    end
    table_sort(list, function(a, b)
        local classA = a.data.classRestriction or "NONE"
        local classB = b.data.classRestriction or "NONE"
        if classA ~= classB then
            if classA == "NONE" then return true end
            if classB == "NONE" then return false end
            return classA < classB
        end
        return (a.data.name or a.key) < (b.data.name or b.key)
    end)
    return list
end

local function GetSortedIcons(barData)
    if not barData or not barData.trackedItems then return {} end
    local list = {}
    for spellId, data in pairs(barData.trackedItems) do
        table_insert(list, { spellId = spellId, data = data, order = data.order or 999 })
    end
    table_sort(list, function(a, b) return a.order < b.order end)
    return list
end

local function GetIconTexture(spellId, trackType)
    local _, icon
    if trackType == "item" or trackType == "internal_cd" then
        _, _, _, _, _, _, _, _, _, icon = GetItemInfo(spellId)
    elseif trackType == "weapon_enchant" then
        local Config = ns.AuraTracker and ns.AuraTracker.Config
        if Config then
            if spellId == Config.MAINHAND_ENCHANT_SLOT_ID then
                icon = GetInventoryItemTexture("player", 16)
            elseif spellId == Config.OFFHAND_ENCHANT_SLOT_ID then
                icon = GetInventoryItemTexture("player", 17)
            end
        end
        if not icon then
            _, _, _, _, _, _, _, _, _, icon = GetItemInfo(spellId)
        end
    else
        _, _, icon = GetSpellInfo(spellId)
    end
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Set a texture's vertex color from an RGBA table
local function SetTexColor(tex, c)
    tex:SetVertexColor(c[1], c[2], c[3], c[4])
end

-- Apply a consistent dark custom style to a button (no Blizzard UIPanelButtonTemplate)
local function StyleAsCustomButton(btn, w, h)
    btn:SetSize(w, h)
    btn:SetNormalFontObject("GameFontNormalSmall")
    btn:SetHighlightFontObject("GameFontHighlightSmall")
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bg:SetVertexColor(0.16, 0.16, 0.16, 1.0)
    btn:SetHighlightTexture("Interface\\ChatFrame\\ChatFrameBackground")
    btn:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.12)
    btn:SetPushedTexture("Interface\\ChatFrame\\ChatFrameBackground")
    btn:GetPushedTexture():SetVertexColor(0.08, 0.08, 0.08, 1.0)
end

-- Build a dimmed RGBA color from a class color table {r,g,b} + brightness + alpha
local function ClassColor(cc, brightness, alpha)
    return { cc[1]*brightness, cc[2]*brightness, cc[3]*brightness, alpha }
end

-- ======================================================
-- ROW POOL HELPERS
-- ======================================================

local function AcquireBarRow()
    local row = table_remove(barRowPool)
    if row then
        row:ClearAllPoints()
        row:Show()
        return row
    end
    local f = CreateFrame("Button", nil, scrollContent)
    f:SetHeight(ROW_H_BAR)
    f._type = "bar"

    -- Background highlight texture
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    SetTexColor(bg, C_ROW_NORMAL)
    f._bg = bg

    -- Expand/collapse arrow (text glyph, no Blizzard texture)
    local arrow = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("LEFT", f, "LEFT", 4, 0)
    f._arrow = arrow

    -- Bar name
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

    -- Selection/hover highlight
    f:SetScript("OnEnter", function(self)
        if self._selected then return end
        local cc = self._classColor
        if cc then
            SetTexColor(self._bg, ClassColor(cc, 0.45, 0.90))
        else
            SetTexColor(self._bg, C_ROW_HOVER)
        end
    end)
    f:SetScript("OnLeave", function(self)
        if self._selected then return end
        local cc = self._classColor
        if cc then
            SetTexColor(self._bg, ClassColor(cc, 0.30, 0.85))
        else
            SetTexColor(self._bg, C_ROW_NORMAL)
        end
    end)

    return f
end

local function ReleaseBarRow(row)
    row:Hide()
    row._classColor = nil
    table_insert(barRowPool, row)
end

local function AcquireIcoRow()
    local row = table_remove(icoRowPool)
    if row then
        row:ClearAllPoints()
        row:Show()
        return row
    end
    local f = CreateFrame("Button", nil, scrollContent)
    f:SetHeight(ROW_H_ICO)
    f._type = "icon"

    -- Background
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    SetTexColor(bg, C_ROW_NORMAL)
    f._bg = bg

    -- Icon
    local ico = f:CreateTexture(nil, "ARTWORK")
    ico:SetSize(ICON_SIZE, ICON_SIZE)
    ico:SetPoint("LEFT", f, "LEFT", 30, 0)
    ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f._ico = ico

    -- Spell name
    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("LEFT", ico, "RIGHT", 5, 0)
    name:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    f._name = name

    -- Hover/select
    f:SetScript("OnEnter", function(self)
        if self._selected then return end
        SetTexColor(self._bg, C_ROW_HOVER)
    end)
    f:SetScript("OnLeave", function(self)
        if self._selected then return end
        SetTexColor(self._bg, C_ROW_NORMAL)
    end)

    return f
end

local function ReleaseIcoRow(row)
    row:Hide()
    table_insert(icoRowPool, row)
end

-- ======================================================
-- RIGHT PANEL NAVIGATION
-- ======================================================

local function GetBarClassKey(barKey)
    local ctrl = GetController()
    if not ctrl then return "NONE" end
    local bars = ctrl:GetBars()
    local barData = bars and bars[barKey]
    if not barData then return "NONE" end
    return SU.GetClassGroupKey(barData.classRestriction)
end

local function RightPanelShowBar(barKey)
    if not rightGroup or not barKey then return end
    local classKey = GetBarClassKey(barKey)
    local path = { "bars", "class_" .. classKey, barKey }
    rightGroup:SetUserData("basepath", path)
    rightGroup:SetUserData("appName", addonName)
    AceConfigDialog:Open(addonName, rightGroup, "bars", "class_" .. classKey, barKey)
end

local function RightPanelShowIcon(barKey, spellId)
    if not rightGroup or not barKey then return end
    local classKey = GetBarClassKey(barKey)
    local path = { "bars", "class_" .. classKey, barKey }
    -- Force the Icons tab active
    local barStatus = AceConfigDialog:GetStatusTable(addonName, path)
    barStatus.groups        = barStatus.groups or {}
    barStatus.groups.selected = "icons"
    rightGroup:SetUserData("basepath", path)
    rightGroup:SetUserData("appName", addonName)
    AceConfigDialog:Open(addonName, rightGroup, "bars", "class_" .. classKey, barKey)
end

local function RightPanelShowImport()
    if not rightGroup then return end
    rightGroup:SetUserData("basepath", nil)
    rightGroup:SetUserData("appName", addonName)
    AceConfigDialog:Open(addonName, rightGroup, "importBar")
end

local function RightPanelShowExamples()
    if not rightGroup then return end
    rightGroup:SetUserData("basepath", nil)
    rightGroup:SetUserData("appName", addonName)
    AceConfigDialog:Open(addonName, rightGroup, "exampleBars")
end

local function RightPanelShowPlaceholder()
    if not rightGroup then return end
    -- Clear basepath so auto-refresh doesn't navigate away
    rightGroup:SetUserData("basepath", nil)
    rightGroup:SetUserData("appName", addonName)
    rightGroup:ReleaseChildren()
    rightGroup:SetLayout("fill")
    local lbl = AceGUI:Create("Label")
    lbl:SetText("\n\n\n\n   |cFF888888← Select a bar from the list to configure it.\n\n"
             .. "   Use the |cFFFFFFFFNew Bar|r button to create your first bar, "
             .. "or use |cFFFFFFFFEdit Mode|r to drag bars on screen.|r")
    lbl:SetFullWidth(true)
    rightGroup:AddChild(lbl)
end

local function RefreshRightPanel()
    if not mainFrame or not mainFrame:IsShown() then return end
    if currentBar then
        if currentIcon then
            RightPanelShowIcon(currentBar, currentIcon)
        else
            RightPanelShowBar(currentBar)
        end
    else
        RightPanelShowPlaceholder()
    end
end

-- ======================================================
-- LEFT PANEL  –  list rebuild
-- ======================================================

local function ClearActiveRows()
    for _, row in ipairs(activeRows) do
        if row._type == "bar" then
            ReleaseBarRow(row)
        else
            ReleaseIcoRow(row)
        end
    end
    activeRows = {}
end

local function SetRowSelected(row, sel)
    row._selected = sel
    if sel then
        local cc = row._classColor
        if cc then
            SetTexColor(row._bg, ClassColor(cc, 0.55, 1.0))
        else
            SetTexColor(row._bg, C_ROW_SEL)
        end
    else
        local cc = row._classColor
        if cc then
            SetTexColor(row._bg, ClassColor(cc, 0.30, 0.85))
        else
            SetTexColor(row._bg, C_ROW_NORMAL)
        end
    end
end

local function RebuildList()
    if not scrollContent then return end

    ClearActiveRows()

    local bars = GetSortedBars()
    local yOffset = 0

    for _, entry in ipairs(bars) do
        local barKey  = entry.key
        local barData = entry.data
        local expanded = expandedBars[barKey]
        local isSel    = (barKey == currentBar and currentIcon == nil)

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
                row._badge:Show()
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
                    local ctrl = GetController()
                    if not ctrl then return end
                    ctrl:DeleteBar(capturedKey)
                    if currentBar == capturedKey then
                        currentBar  = nil
                        currentIcon = nil
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
                    expandedBars[barKey] = not expandedBars[barKey]
                    RebuildList()
                else
                    currentBar  = barKey
                    currentIcon = nil
                    SU.editState.selectedBar  = barKey
                    SU.editState.selectedAura = nil
                    RebuildList()
                    RightPanelShowBar(barKey)
                end
            end
        end)

        row:SetPoint("TOPLEFT",  scrollContent, "TOPLEFT",  0, -yOffset)
        row:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, -yOffset)
        table_insert(activeRows, row)
        yOffset = yOffset + ROW_H_BAR

        -- ── Icon rows (when expanded) ─────────────────────────
        if expanded then
            local icons = GetSortedIcons(barData)
            for _, iconEntry in ipairs(icons) do
                local spellId  = iconEntry.spellId
                local iconData = iconEntry.data
                local isIconSel = (barKey == currentBar and currentIcon == spellId)

                local irow = AcquireIcoRow()
                irow._barKey  = barKey
                irow._spellId = spellId
                SetRowSelected(irow, isIconSel)

                -- Icon texture
                local tex = GetIconTexture(spellId, iconData.trackType)
                irow._ico:SetTexture(tex)

                -- Name + track type label
                local spellName = SU.GetTrackedNameAndIcon(spellId, iconData.trackType)
                local typeLabel = SU.GetTrackTypeLabel(iconData.trackType, iconData.type)
                irow._name:SetText(spellName .. "  " .. typeLabel)

                -- Click to select icon
                local cBarKey  = barKey
                local cSpellId = spellId
                irow:SetScript("OnClick", function()
                    currentBar  = cBarKey
                    currentIcon = cSpellId
                    SU.editState.selectedBar  = cBarKey
                    SU.editState.selectedAura = cSpellId
                    RebuildList()
                    RightPanelShowIcon(cBarKey, cSpellId)
                end)

                irow:SetPoint("TOPLEFT",  scrollContent, "TOPLEFT",  0, -yOffset)
                irow:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, -yOffset)
                table_insert(activeRows, irow)
                yOffset = yOffset + ROW_H_ICO
            end
        end

        -- Thin separator line after each bar block
        yOffset = yOffset + 2
    end

    if #bars == 0 then
        yOffset = 40
    end

    scrollContent:SetHeight(math_max(yOffset, 10))
end

-- ======================================================
-- NEW-BAR INPUT
-- ======================================================

local function ShowNewBarInput()
    if not newBarInput then return end
    newBarInput:Show()
    newBarInput:SetFocus()
end

-- ======================================================
-- CONFIRM-DELETE POPUP
-- ======================================================

StaticPopupDialogs["AURATRACKER_CONFIRM_DELETE_BAR"] = {
    text          = "Delete bar \"%s\"?",
    button1       = "Delete",
    button2       = "Cancel",
    OnAccept      = function(self, data)
        if data and data.fn then data.fn() end
    end,
    timeout       = 0,
    whileDead     = true,
    hideOnEscape  = true,
    preferredIndex = 3,
}

-- ======================================================
-- MAIN FRAME BUILDER
-- ======================================================

local function BuildMainFrame()
    if mainFrame then return end

    -- ── Backdrop template safe for WotLK ────────────────────
    local backdrop = {
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    }

    mainFrame = CreateFrame("Frame", "AuraTrackerMainFrame", UIParent)
    mainFrame:SetSize(FRAME_W, FRAME_H)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetBackdrop(backdrop)
    mainFrame:SetBackdropColor(C_MAIN_BG[1], C_MAIN_BG[2], C_MAIN_BG[3], C_MAIN_BG[4])
    mainFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop",  mainFrame.StopMovingOrSizing)
    mainFrame:SetToplevel(true)
    mainFrame:Hide()

    -- Close with Escape
    table_insert(UISpecialFrames, "AuraTrackerMainFrame")

    -- ── Title bar ────────────────────────────────────────────
    local titleBar = CreateFrame("Frame", nil, mainFrame)
    titleBar:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",   3, -3)
    titleBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT",  -3, -3)
    titleBar:SetHeight(TITLE_H)
    titleBar:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    titleBar:SetBackdropColor(C_TITLE_BG[1], C_TITLE_BG[2], C_TITLE_BG[3], C_TITLE_BG[4])

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleText:SetText("|cFF00CCFFAuraTracker|r")

    local versionText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionText:SetPoint("LEFT", titleText, "RIGHT", 8, -1)
    versionText:SetText("|cFF888888Settings|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -2, 0)
    closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

    -- ── Full-width top toolbar (below title bar) ─────────────
    local topToolbar = CreateFrame("Frame", nil, mainFrame)
    topToolbar:SetPoint("TOPLEFT",  titleBar, "BOTTOMLEFT",  0, -2)
    topToolbar:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -2)
    topToolbar:SetHeight(TOP_TOOLBAR_H)
    topToolbar:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    topToolbar:SetBackdropColor(C_LEFT_BG[1], C_LEFT_BG[2], C_LEFT_BG[3], C_LEFT_BG[4])

    -- Separator below top toolbar
    local ttSep = mainFrame:CreateTexture(nil, "BACKGROUND")
    ttSep:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    ttSep:SetVertexColor(C_DIVIDER[1], C_DIVIDER[2], C_DIVIDER[3], C_DIVIDER[4])
    ttSep:SetPoint("TOPLEFT",  topToolbar, "BOTTOMLEFT",  0, 0)
    ttSep:SetPoint("TOPRIGHT", topToolbar, "BOTTOMRIGHT", 0, 0)
    ttSep:SetHeight(1)

    -- "New Bar" button
    local newBarBtn = CreateFrame("Button", nil, topToolbar)
    StyleAsCustomButton(newBarBtn, 80, 24)
    newBarBtn:SetPoint("LEFT", topToolbar, "LEFT", 8, 0)
    newBarBtn:SetText("New Bar")
    newBarBtn:SetScript("OnClick", function() ShowNewBarInput() end)

    -- "Edit Mode" button
    local editModeBtn = CreateFrame("Button", nil, topToolbar)
    StyleAsCustomButton(editModeBtn, 82, 24)
    editModeBtn:SetPoint("LEFT", newBarBtn, "RIGHT", 6, 0)
    editModeBtn:SetText("Edit Mode")
    editModeBtn:SetScript("OnClick", function()
        if LibEditmode then
            LibEditmode:ToggleEditMode("AuraTracker")
        end
    end)

    -- "Import" button
    local importBtn = CreateFrame("Button", nil, topToolbar)
    StyleAsCustomButton(importBtn, 72, 24)
    importBtn:SetPoint("LEFT", editModeBtn, "RIGHT", 6, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function() RightPanelShowImport() end)

    -- "Predefined" button (formerly "Examples")
    local predefinedBtn = CreateFrame("Button", nil, topToolbar)
    StyleAsCustomButton(predefinedBtn, 90, 24)
    predefinedBtn:SetPoint("LEFT", importBtn, "RIGHT", 6, 0)
    predefinedBtn:SetText("Predefined")
    predefinedBtn:SetScript("OnClick", function() RightPanelShowExamples() end)

    -- ── Left panel ───────────────────────────────────────────
    local leftPanel = CreateFrame("Frame", nil, mainFrame)
    leftPanel:SetPoint("TOPLEFT",    topToolbar, "BOTTOMLEFT",  0, -2)
    leftPanel:SetPoint("BOTTOMLEFT", mainFrame,  "BOTTOMLEFT",  3,  3)
    leftPanel:SetWidth(LEFT_W)
    leftPanel:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    leftPanel:SetBackdropColor(C_LEFT_BG[1], C_LEFT_BG[2], C_LEFT_BG[3], C_LEFT_BG[4])

    -- New-bar input (hidden until "New Bar" clicked)
    local newBarBox = CreateFrame("EditBox", nil, leftPanel, "InputBoxTemplate")
    newBarBox:SetSize(LEFT_W - 28, 20)
    newBarBox:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 8, -5)
    newBarBox:SetAutoFocus(false)
    newBarBox:SetMaxLetters(64)
    local placeholder = newBarBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetAllPoints()
    placeholder:SetText("Bar name, then Enter...")
    placeholder:SetJustifyH("LEFT")
    newBarBox:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" then placeholder:Show() else placeholder:Hide() end
    end)
    newBarBox:SetScript("OnEnterPressed", function(self)
        local val = self:GetText():match("^%s*(.-)%s*$")
        if val and val ~= "" then
            local ctrl = GetController()
            if ctrl then
                local allBars = ctrl:GetBars()
                if allBars[val] then
                    print("|cFFFF0000Aura Tracker:|r Bar '" .. val .. "' already exists.")
                else
                    ctrl:CreateBar(val)
                    self:SetText("")
                    self:Hide()
                    SU.NotifyChange()
                end
            end
        else
            self:Hide()
        end
    end)
    newBarBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:Hide()
    end)
    newBarBox:Hide()
    newBarInput = newBarBox
    -- Raise above the scroll-content rows so it draws on top when visible
    newBarBox:SetFrameLevel(newBarBox:GetFrameLevel() + 10)

    -- Toolbar/input separator
    local toolSep = leftPanel:CreateTexture(nil, "BACKGROUND")
    toolSep:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    toolSep:SetVertexColor(C_DIVIDER[1], C_DIVIDER[2], C_DIVIDER[3], C_DIVIDER[4])
    toolSep:SetPoint("TOPLEFT",  leftPanel, "TOPLEFT",  4, -INPUT_AREA_H)
    toolSep:SetPoint("TOPRIGHT", leftPanel, "TOPRIGHT", -4, -INPUT_AREA_H)
    toolSep:SetHeight(1)

    -- Scroll frame for bar/icon list
    scrollFrame = CreateFrame("ScrollFrame", "AuraTrackerMainScrollFrame", leftPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     leftPanel, "TOPLEFT",     4, -(INPUT_AREA_H + 4))
    scrollFrame:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -22, 4)

    scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetWidth(LEFT_W - 30)
    scrollContent:SetHeight(1)
    scrollFrame:SetScrollChild(scrollContent)

    -- ── Vertical divider ─────────────────────────────────────
    local divider = mainFrame:CreateTexture(nil, "BACKGROUND")
    divider:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    divider:SetVertexColor(C_DIVIDER[1], C_DIVIDER[2], C_DIVIDER[3], C_DIVIDER[4])
    divider:SetPoint("TOPLEFT",    leftPanel, "TOPRIGHT",    1, 0)
    divider:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMRIGHT", 1, 0)
    divider:SetWidth(1)

    -- ── Right panel (AceGUI container) ───────────────────────
    rightGroup = AceGUI:Create("SimpleGroup")
    rightGroup:SetLayout("fill")
    -- Explicitly set dimensions so AceGUI knows the available size
    rightGroup:SetWidth(RIGHT_W)
    rightGroup:SetHeight(RIGHT_H)

    -- Parent the widget's frame to our main frame and anchor it
    rightGroup.frame:SetParent(mainFrame)
    rightGroup.frame:ClearAllPoints()
    rightGroup.frame:SetPoint("TOPLEFT",    leftPanel, "TOPRIGHT",    PAD, 0)
    rightGroup.frame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -PAD, PAD)
    rightGroup.frame:Show()

    -- Register in BlizOptions so AceConfigDialog's NotifyChange
    -- mechanism auto-refreshes the right panel when options change.
    AceConfigDialog.BlizOptions = AceConfigDialog.BlizOptions or {}
    AceConfigDialog.BlizOptions[addonName] = AceConfigDialog.BlizOptions[addonName] or {}
    AceConfigDialog.BlizOptions[addonName]["ATMainFrame"] = rightGroup
    rightGroup:SetUserData("appName", addonName)
    rightGroup:SetUserData("iscustom", true)

    RightPanelShowPlaceholder()
end

-- ======================================================
-- PUBLIC MODULE API
-- ======================================================

local AT_MainFrame = {}
ns.AuraTracker.MainFrame = AT_MainFrame

function AT_MainFrame:Open(barKey)
    BuildMainFrame()
    mainFrame:Show()
    mainFrame:Raise()

    -- Restore or set initial selection
    if barKey then
        currentBar  = barKey
        currentIcon = nil
        SU.editState.selectedBar  = barKey
        SU.editState.selectedAura = nil
        expandedBars[barKey]  = true
    end

    RebuildList()

    if currentBar then
        RightPanelShowBar(currentBar)
    else
        RightPanelShowPlaceholder()
    end
end

function AT_MainFrame:Close()
    if mainFrame then mainFrame:Hide() end
end

function AT_MainFrame:IsOpen()
    return mainFrame and mainFrame:IsShown()
end

function AT_MainFrame:SelectBar(barKey)
    currentBar  = barKey
    currentIcon = nil
    SU.editState.selectedBar  = barKey
    SU.editState.selectedAura = nil
    expandedBars[barKey] = expandedBars[barKey] or nil
    RebuildList()
    if barKey then
        RightPanelShowBar(barKey)
    else
        RightPanelShowPlaceholder()
    end
end

function AT_MainFrame:SelectIcon(barKey, spellId)
    currentBar  = barKey
    currentIcon = spellId
    SU.editState.selectedBar  = barKey
    SU.editState.selectedAura = spellId
    expandedBars[barKey] = true
    RebuildList()
    RightPanelShowIcon(barKey, spellId)
end

function AT_MainFrame:RefreshList()
    if mainFrame and mainFrame:IsShown() then
        RebuildList()
    end
end

-- ======================================================
-- HOOK NotifyChange to keep the left-panel list in sync
-- ======================================================

local _origNotifyChange = SU.NotifyChange
SU.NotifyChange = function()
    _origNotifyChange()
    if mainFrame and mainFrame:IsShown() then
        -- Validate selection (bar/icon might have been deleted)
        local selectionInvalid = false
        if currentBar then
            local ctrl = GetController()
            local bars  = ctrl and ctrl:GetBars()
            if not bars or not bars[currentBar] then
                currentBar  = nil
                currentIcon = nil
                SU.editState.selectedBar  = nil
                SU.editState.selectedAura = nil
                selectionInvalid = true
            elseif currentIcon and (not bars[currentBar].trackedItems
                                    or not bars[currentBar].trackedItems[currentIcon]) then
                currentIcon = nil
                SU.editState.selectedAura = nil
                selectionInvalid = true
            end
        end
        RebuildList()
        -- If selection was invalidated, clear the right panel so the old
        -- basepath is not used by AceConfigDialog's auto-refresh mechanism.
        if selectionInvalid then
            RightPanelShowPlaceholder()
        end
    end
end

-- Also keep NotifyAndRebuild consistent
local _origNotifyAndRebuild = SU.NotifyAndRebuild
SU.NotifyAndRebuild = function(barKey)
    _origNotifyAndRebuild(barKey)
    -- Rebuild list only (right panel auto-refreshes via BlizOptions hook above)
    if mainFrame and mainFrame:IsShown() then
        RebuildList()
    end
end

-- Export the hooks update back to SettingsUtils so other callers get them
ns.AuraTracker.SettingsUtils.NotifyChange     = SU.NotifyChange
ns.AuraTracker.SettingsUtils.NotifyAndRebuild = SU.NotifyAndRebuild
