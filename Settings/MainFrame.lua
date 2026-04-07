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

local state = {
    expandedBars = {},
    barRowPool   = {},
    icoRowPool   = {},
    activeRows   = {},
}
ns.AuraTracker._MFState = state
-- mainFrame, scrollFrame, scrollContent, rightGroup, currentBar, currentIcon, newBarInput start nil

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
    if not state.rightGroup or not barKey then return end
    local classKey = GetBarClassKey(barKey)
    local path = { "bars", "class_" .. classKey, barKey }
    state.rightGroup:SetUserData("basepath", path)
    state.rightGroup:SetUserData("appName", addonName)
    AceConfigDialog:Open(addonName, state.rightGroup, "bars", "class_" .. classKey, barKey)
end

local function RightPanelShowIcon(barKey, spellId)
    if not state.rightGroup or not barKey then return end
    local classKey = GetBarClassKey(barKey)
    local path = { "bars", "class_" .. classKey, barKey }
    -- Force the Icons tab active
    local barStatus = AceConfigDialog:GetStatusTable(addonName, path)
    barStatus.groups        = barStatus.groups or {}
    barStatus.groups.selected = "icons"
    state.rightGroup:SetUserData("basepath", path)
    state.rightGroup:SetUserData("appName", addonName)
    AceConfigDialog:Open(addonName, state.rightGroup, "bars", "class_" .. classKey, barKey)
end

local function RightPanelShowImport()
    if not state.rightGroup then return end
    state.rightGroup:SetUserData("basepath", nil)
    state.rightGroup:SetUserData("appName", addonName)
    AceConfigDialog:Open(addonName, state.rightGroup, "importBar")
end

local function RightPanelShowExamples()
    if not state.rightGroup then return end
    state.rightGroup:SetUserData("basepath", nil)
    state.rightGroup:SetUserData("appName", addonName)
    AceConfigDialog:Open(addonName, state.rightGroup, "exampleBars")
end

local function RightPanelShowPlaceholder()
    if not state.rightGroup then return end
    -- Clear basepath so auto-refresh doesn't navigate away
    state.rightGroup:SetUserData("basepath", nil)
    state.rightGroup:SetUserData("appName", addonName)
    state.rightGroup:ReleaseChildren()
    state.rightGroup:SetLayout("fill")
    local lbl = AceGUI:Create("Label")
    lbl:SetText("\n\n\n\n   |cFF888888← Select a bar from the list to configure it.\n\n"
             .. "   Use the |cFFFFFFFFNew Bar|r button to create your first bar, "
             .. "or use |cFFFFFFFFEdit Mode|r to drag bars on screen.|r")
    lbl:SetFullWidth(true)
    state.rightGroup:AddChild(lbl)
end

local function RefreshRightPanel()
    if not state.mainFrame or not state.mainFrame:IsShown() then return end
    if state.currentBar then
        if state.currentIcon then
            RightPanelShowIcon(state.currentBar, state.currentIcon)
        else
            RightPanelShowBar(state.currentBar)
        end
    else
        RightPanelShowPlaceholder()
    end
end

-- ======================================================
-- STATE HELPER EXPORTS  (for MainFrameRows.lua)
-- ======================================================

state.SetTexColor       = SetTexColor
state.ClassColor        = ClassColor
state.GetController     = GetController
state.GetSortedBars     = GetSortedBars
state.GetSortedIcons    = GetSortedIcons
state.GetIconTexture    = GetIconTexture
state.GetBarClassKey    = GetBarClassKey
state.RightPanelShowBar  = RightPanelShowBar
state.RightPanelShowIcon = RightPanelShowIcon
state.ROW_H_BAR   = ROW_H_BAR
state.ROW_H_ICO   = ROW_H_ICO
state.ICON_SIZE   = ICON_SIZE
state.C_ROW_NORMAL = C_ROW_NORMAL
state.C_ROW_HOVER  = C_ROW_HOVER
state.C_ROW_SEL    = C_ROW_SEL



-- ======================================================
-- NEW-BAR INPUT
-- ======================================================

local function ShowNewBarInput()
    if not state.newBarInput then return end
    state.newBarInput:Show()
    state.newBarInput:SetFocus()
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
    if state.mainFrame then return end

    -- ── Backdrop template safe for WotLK ────────────────────
    local backdrop = {
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    }

    state.mainFrame = CreateFrame("Frame", "AuraTrackerMainFrame", UIParent)
    state.mainFrame:SetSize(FRAME_W, FRAME_H)
    state.mainFrame:SetPoint("CENTER")
    state.mainFrame:SetFrameStrata("DIALOG")
    state.mainFrame:SetBackdrop(backdrop)
    state.mainFrame:SetBackdropColor(C_MAIN_BG[1], C_MAIN_BG[2], C_MAIN_BG[3], C_MAIN_BG[4])
    state.mainFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    state.mainFrame:EnableMouse(true)
    state.mainFrame:SetMovable(true)
    state.mainFrame:RegisterForDrag("LeftButton")
    state.mainFrame:SetScript("OnDragStart", state.mainFrame.StartMoving)
    state.mainFrame:SetScript("OnDragStop",  state.mainFrame.StopMovingOrSizing)
    state.mainFrame:SetToplevel(true)
    state.mainFrame:Hide()

    -- Close with Escape
    table_insert(UISpecialFrames, "AuraTrackerMainFrame")

    -- ── Title bar ────────────────────────────────────────────
    local titleBar = CreateFrame("Frame", nil, state.mainFrame)
    titleBar:SetPoint("TOPLEFT",  state.mainFrame, "TOPLEFT",   3, -3)
    titleBar:SetPoint("TOPRIGHT", state.mainFrame, "TOPRIGHT",  -3, -3)
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
    closeBtn:SetScript("OnClick", function() state.mainFrame:Hide() end)

    -- ── Full-width top toolbar (below title bar) ─────────────
    local topToolbar = CreateFrame("Frame", nil, state.mainFrame)
    topToolbar:SetPoint("TOPLEFT",  titleBar, "BOTTOMLEFT",  0, -2)
    topToolbar:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -2)
    topToolbar:SetHeight(TOP_TOOLBAR_H)
    topToolbar:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    topToolbar:SetBackdropColor(C_LEFT_BG[1], C_LEFT_BG[2], C_LEFT_BG[3], C_LEFT_BG[4])

    -- Separator below top toolbar
    local ttSep = state.mainFrame:CreateTexture(nil, "BACKGROUND")
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
    local leftPanel = CreateFrame("Frame", nil, state.mainFrame)
    leftPanel:SetPoint("TOPLEFT",    topToolbar, "BOTTOMLEFT",  0, -2)
    leftPanel:SetPoint("BOTTOMLEFT", state.mainFrame,  "BOTTOMLEFT",  3,  3)
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
    state.newBarInput = newBarBox
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
    state.scrollFrame = CreateFrame("ScrollFrame", "AuraTrackerMainScrollFrame", leftPanel, "UIPanelScrollFrameTemplate")
    state.scrollFrame:SetPoint("TOPLEFT",     leftPanel, "TOPLEFT",     4, -(INPUT_AREA_H + 4))
    state.scrollFrame:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -22, 4)

    state.scrollContent = CreateFrame("Frame", nil, state.scrollFrame)
    state.scrollContent:SetWidth(LEFT_W - 30)
    state.scrollContent:SetHeight(1)
    state.scrollFrame:SetScrollChild(state.scrollContent)

    -- ── Vertical divider ─────────────────────────────────────
    local divider = state.mainFrame:CreateTexture(nil, "BACKGROUND")
    divider:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    divider:SetVertexColor(C_DIVIDER[1], C_DIVIDER[2], C_DIVIDER[3], C_DIVIDER[4])
    divider:SetPoint("TOPLEFT",    leftPanel, "TOPRIGHT",    1, 0)
    divider:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMRIGHT", 1, 0)
    divider:SetWidth(1)

    -- ── Right panel (AceGUI container) ───────────────────────
    state.rightGroup = AceGUI:Create("SimpleGroup")
    state.rightGroup:SetLayout("fill")
    -- Explicitly set dimensions so AceGUI knows the available size
    state.rightGroup:SetWidth(RIGHT_W)
    state.rightGroup:SetHeight(RIGHT_H)

    -- Parent the widget's frame to our main frame and anchor it
    state.rightGroup.frame:SetParent(state.mainFrame)
    state.rightGroup.frame:ClearAllPoints()
    state.rightGroup.frame:SetPoint("TOPLEFT",    leftPanel, "TOPRIGHT",    PAD, 0)
    state.rightGroup.frame:SetPoint("BOTTOMRIGHT", state.mainFrame, "BOTTOMRIGHT", -PAD, PAD)
    state.rightGroup.frame:Show()

    -- Register in BlizOptions so AceConfigDialog's NotifyChange
    -- mechanism auto-refreshes the right panel when options change.
    AceConfigDialog.BlizOptions = AceConfigDialog.BlizOptions or {}
    AceConfigDialog.BlizOptions[addonName] = AceConfigDialog.BlizOptions[addonName] or {}
    AceConfigDialog.BlizOptions[addonName]["ATMainFrame"] = state.rightGroup
    state.rightGroup:SetUserData("appName", addonName)
    state.rightGroup:SetUserData("iscustom", true)

    RightPanelShowPlaceholder()
end

-- ======================================================
-- PUBLIC MODULE API
-- ======================================================

local AT_MainFrame = {}
ns.AuraTracker.MainFrame = AT_MainFrame

function AT_MainFrame:Open(barKey)
    BuildMainFrame()
    state.mainFrame:Show()
    state.mainFrame:Raise()

    -- Restore or set initial selection
    if barKey then
        state.currentBar  = barKey
        state.currentIcon = nil
        SU.editState.selectedBar  = barKey
        SU.editState.selectedAura = nil
        state.expandedBars[barKey]  = true
    end

    state.RebuildList()

    if state.currentBar then
        RightPanelShowBar(state.currentBar)
    else
        RightPanelShowPlaceholder()
    end
end

function AT_MainFrame:Close()
    if state.mainFrame then state.mainFrame:Hide() end
end

function AT_MainFrame:IsOpen()
    return state.mainFrame and state.mainFrame:IsShown()
end

function AT_MainFrame:SelectBar(barKey)
    state.currentBar  = barKey
    state.currentIcon = nil
    SU.editState.selectedBar  = barKey
    SU.editState.selectedAura = nil
    state.expandedBars[barKey] = state.expandedBars[barKey] or nil
    state.RebuildList()
    if barKey then
        RightPanelShowBar(barKey)
    else
        RightPanelShowPlaceholder()
    end
end

function AT_MainFrame:SelectIcon(barKey, spellId)
    state.currentBar  = barKey
    state.currentIcon = spellId
    SU.editState.selectedBar  = barKey
    SU.editState.selectedAura = spellId
    state.expandedBars[barKey] = true
    state.RebuildList()
    RightPanelShowIcon(barKey, spellId)
end

function AT_MainFrame:RefreshList()
    if state.mainFrame and state.mainFrame:IsShown() then
        state.RebuildList()
    end
end

-- ======================================================
-- HOOK NotifyChange to keep the left-panel list in sync
-- ======================================================

local _origNotifyChange = SU.NotifyChange
SU.NotifyChange = function()
    _origNotifyChange()
    if state.mainFrame and state.mainFrame:IsShown() then
        -- Validate selection (bar/icon might have been deleted)
        local selectionInvalid = false
        if state.currentBar then
            local ctrl = GetController()
            local bars  = ctrl and ctrl:GetBars()
            if not bars or not bars[state.currentBar] then
                state.currentBar  = nil
                state.currentIcon = nil
                SU.editState.selectedBar  = nil
                SU.editState.selectedAura = nil
                selectionInvalid = true
            elseif state.currentIcon and (not bars[state.currentBar].trackedItems
                                    or not bars[state.currentBar].trackedItems[state.currentIcon]) then
                state.currentIcon = nil
                SU.editState.selectedAura = nil
                selectionInvalid = true
            end
        end
        state.RebuildList()
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
    if state.mainFrame and state.mainFrame:IsShown() then
        -- Validate state.currentIcon: the icon (or bar) may have just been deleted.
        -- Clearing stale references here prevents SU.NotifyChange (which may be
        -- called synchronously later, e.g. from inside an AceConfigDialog execute
        -- callback) from detecting selectionInvalid=true and calling
        -- RightPanelShowPlaceholder() → state.rightGroup:ReleaseChildren() while
        -- AceConfigDialog's ActivateControl is still running on the clicked widget,
        -- which would nil out user.rootframe and cause an "attempt to index field
        -- 'rootframe' (a nil value)" crash at AceConfigDialog-3.0.lua:853.
        if state.currentBar then
            local ctrl = GetController()
            local bars  = ctrl and ctrl:GetBars()
            if not bars or not bars[state.currentBar] then
                state.currentBar  = nil
                state.currentIcon = nil
                SU.editState.selectedBar  = nil
                SU.editState.selectedAura = nil
            elseif state.currentIcon and (not bars[state.currentBar].trackedItems
                                    or not bars[state.currentBar].trackedItems[state.currentIcon]) then
                state.currentIcon = nil
                SU.editState.selectedAura = nil
            end
        end
        state.RebuildList()
        -- If the currently-selected bar's class restriction changed, the bar
        -- moves to a different class bucket in the options tree.  Refresh the
        -- basepath stored in state.rightGroup NOW (before the next-frame auto-refresh
        -- fires) so AceConfigDialog navigates to the correct path.
        if state.currentBar == barKey and state.rightGroup then
            local classKey = GetBarClassKey(barKey)
            state.rightGroup:SetUserData("basepath", { "bars", "class_" .. classKey, barKey })
        end
    end
end

-- Export the hooks update back to SettingsUtils so other callers get them
ns.AuraTracker.SettingsUtils.NotifyChange     = SU.NotifyChange
ns.AuraTracker.SettingsUtils.NotifyAndRebuild = SU.NotifyAndRebuild
