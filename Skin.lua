local addonName, ns = ...

local pairs, select, unpack = pairs, select, unpack
local CreateFrame, UIParent = CreateFrame, UIParent

local AceGUI = LibStub("AceGUI-3.0")

-- ==========================================================
-- THEME COLOURS
-- ==========================================================

local C = {
    bg          = { 0.06, 0.06, 0.06, 0.92 },  -- main background
    bgLight     = { 0.12, 0.12, 0.12, 1 },      -- lighter panels (tree, tabs)
    border      = { 0.20, 0.20, 0.20, 1 },      -- thin border colour
    borderLight = { 0.30, 0.30, 0.30, 1 },      -- hover / accent border
    accent      = { 0.00, 0.44, 0.87, 1 },      -- ElvUI blue accent
    btn         = { 0.18, 0.18, 0.18, 1 },      -- button normal
    btnHover    = { 0.28, 0.28, 0.28, 1 },      -- button hover
    btnPress    = { 0.10, 0.10, 0.10, 1 },      -- button pressed
    gold        = { 1, 0.82, 0, 1 },             -- label text
    white       = { 1, 1, 1, 1 },                -- value text
    disabled    = { 0.40, 0.40, 0.40, 1 },       -- disabled text
    headerLine  = { 0.00, 0.44, 0.87, 0.6 },     -- heading separator
}

-- ==========================================================
-- BACKDROP TEMPLATES
-- ==========================================================

local flatBackdrop = {
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile     = false, tileSize = 0, edgeSize = 1,
    insets   = { left = 0, right = 0, top = 0, bottom = 0 },
}

-- ==========================================================
-- HELPERS
-- ==========================================================

local function SetFlat(frame, bgColor, borderColor)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop(flatBackdrop)
    frame:SetBackdropColor(unpack(bgColor or C.bg))
    frame:SetBackdropBorderColor(unpack(borderColor or C.border))
end

local function StripTextures(frame)
    if not frame then return end
    if frame.GetNumRegions then
        for i = 1, frame:GetNumRegions() do
            local region = select(i, frame:GetRegions())
            if region and region:IsObjectType("Texture") then
                region:SetTexture(nil)
            end
        end
    end
end

local function SkinCloseButton(btn)
    if not btn then return end
    StripTextures(btn)
    btn:SetNormalTexture(nil)
    btn:SetPushedTexture(nil)
    btn:SetHighlightTexture(nil)
    btn:SetDisabledTexture(nil)

    if not btn._flatBG then
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        bg:SetVertexColor(unpack(C.btn))
        btn._flatBG = bg
    end

    if not btn._flatBorder then
        local border = CreateFrame("Frame", nil, btn)
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetBackdrop(flatBackdrop)
        border:SetBackdropColor(0, 0, 0, 0)
        border:SetBackdropBorderColor(unpack(C.border))
        btn._flatBorder = border
    end

    btn:SetText(btn:GetText() or CLOSE or "Close")
    if btn:GetFontString() then
        btn:GetFontString():SetTextColor(unpack(C.gold))
    end

    btn:HookScript("OnEnter", function(self)
        if self._flatBG then self._flatBG:SetVertexColor(unpack(C.btnHover)) end
    end)
    btn:HookScript("OnLeave", function(self)
        if self._flatBG then self._flatBG:SetVertexColor(unpack(C.btn)) end
    end)
end

local function SkinFlatButton(frame)
    if not frame or frame._flatSkinned then return end
    frame._flatSkinned = true

    StripTextures(frame)
    frame:SetNormalTexture(nil)
    frame:SetPushedTexture(nil)
    frame:SetHighlightTexture(nil)
    if frame.SetDisabledTexture then frame:SetDisabledTexture(nil) end

    if not frame._flatBG then
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        bg:SetVertexColor(unpack(C.btn))
        frame._flatBG = bg
    end

    if not frame._flatBorder then
        local border = CreateFrame("Frame", nil, frame)
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetBackdrop(flatBackdrop)
        border:SetBackdropColor(0, 0, 0, 0)
        border:SetBackdropBorderColor(unpack(C.border))
        frame._flatBorder = border
    end

    if frame:GetFontString() then
        frame:GetFontString():SetTextColor(unpack(C.gold))
    end

    frame:HookScript("OnEnter", function(self)
        if self._flatBG then self._flatBG:SetVertexColor(unpack(C.btnHover)) end
        if self._flatBorder then self._flatBorder:SetBackdropBorderColor(unpack(C.borderLight)) end
    end)
    frame:HookScript("OnLeave", function(self)
        if self._flatBG then self._flatBG:SetVertexColor(unpack(C.btn)) end
        if self._flatBorder then self._flatBorder:SetBackdropBorderColor(unpack(C.border)) end
    end)
    frame:HookScript("OnMouseDown", function(self)
        if self._flatBG then self._flatBG:SetVertexColor(unpack(C.btnPress)) end
    end)
    frame:HookScript("OnMouseUp", function(self)
        if self._flatBG then self._flatBG:SetVertexColor(unpack(C.btn)) end
    end)
end

local function SkinEditBoxFrame(editbox)
    if not editbox or editbox._flatSkinned then return end
    editbox._flatSkinned = true

    -- Remove InputBoxTemplate textures (Left, Right, Middle)
    local name = editbox:GetName()
    if name then
        for _, suffix in pairs({ "Left", "Right", "Middle", "Mid" }) do
            local tex = _G[name .. suffix]
            if tex then tex:SetTexture(nil) end
        end
    end

    editbox:SetBackdrop(flatBackdrop)
    editbox:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    editbox:SetBackdropBorderColor(unpack(C.border))
    editbox:SetTextInsets(4, 4, 2, 2)

    editbox:HookScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(unpack(C.accent))
    end)
    editbox:HookScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(unpack(C.border))
    end)
end

-- ==========================================================
-- PER-WIDGET SKINNERS
-- ==========================================================

local skinners = {}

-- ------- Frame Container (main settings window) ----------
skinners["Frame"] = function(widget)
    local frame = widget.frame
    if not frame then return end

    -- Main frame background
    SetFlat(frame, C.bg, C.border)

    -- Hide Blizzard title textures
    if widget.titlebg then widget.titlebg:SetTexture(nil) end

    -- Hide all ornamental header textures
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region:IsObjectType("Texture") then
            local tex = region:GetTexture()
            if tex and type(tex) == "string" and tex:find("DialogFrame") then
                region:SetTexture(nil)
            end
        end
    end

    -- Title text styling
    if widget.titletext then
        widget.titletext:SetTextColor(unpack(C.gold))
    end

    -- Title bar background strip
    if not frame._titleBar then
        local titleBar = frame:CreateTexture(nil, "ARTWORK")
        titleBar:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        titleBar:SetVertexColor(0.10, 0.10, 0.10, 1)
        titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
        titleBar:SetHeight(24)
        frame._titleBar = titleBar
    end

    -- Status bar
    if widget.statustext and widget.statustext:GetParent() then
        local statusbg = widget.statustext:GetParent()
        SetFlat(statusbg, { 0.08, 0.08, 0.08, 1 }, C.border)
    end

    -- Close button
    for i = 1, frame:GetNumChildren() do
        local child = select(i, frame:GetChildren())
        if child:IsObjectType("Button") then
            local text = child:GetText()
            if text and (text == CLOSE or text == "Close") then
                SkinFlatButton(child)
                break
            end
        end
    end

    -- Sizer lines
    if widget.sizer_se then
        for i = 1, widget.sizer_se:GetNumRegions() do
            local region = select(i, widget.sizer_se:GetRegions())
            if region and region:IsObjectType("Texture") then
                region:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                region:SetVertexColor(unpack(C.border))
            end
        end
    end
end

-- ------- TreeGroup Container ----------
skinners["TreeGroup"] = function(widget)
    -- Tree pane
    if widget.treeframe then
        SetFlat(widget.treeframe, C.bgLight, C.border)
    end
    -- Content border
    if widget.border then
        SetFlat(widget.border, C.bg, C.border)
    end
    -- Dragger
    if widget.dragger then
        widget.dragger:SetBackdrop(flatBackdrop)
        widget.dragger:SetBackdropColor(0, 0, 0, 0)
        widget.dragger:SetBackdropBorderColor(0, 0, 0, 0)

        -- Override enter/leave for dragger
        widget.dragger:SetScript("OnEnter", function(self)
            self:SetBackdropColor(unpack(C.accent))
        end)
        widget.dragger:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0, 0, 0, 0)
        end)
    end
    -- Scrollbar background
    if widget.scrollbar then
        for i = 1, widget.scrollbar:GetNumRegions() do
            local region = select(i, widget.scrollbar:GetRegions())
            if region and region:IsObjectType("Texture") then
                local tex = region:GetTexture()
                if tex == 0 or (type(tex) == "number") then
                    region:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                    region:SetVertexColor(0.05, 0.05, 0.05, 0.5)
                end
            end
        end
    end

    -- Hook RefreshTree to skin tree buttons after they're laid out
    if not widget._treeSkinHooked then
        widget._treeSkinHooked = true
        local origRefreshTree = widget.RefreshTree
        widget.RefreshTree = function(self, ...)
            origRefreshTree(self, ...)
            if self.buttons then
                for _, btn in pairs(self.buttons) do
                    if btn:IsShown() and not btn._flatSkinned then
                        btn._flatSkinned = true
                        -- Remove the default highlight
                        local hl = btn:GetHighlightTexture()
                        if hl then
                            hl:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                            hl:SetVertexColor(unpack(C.accent))
                            hl:SetAlpha(0.2)
                        end
                    end
                end
            end
        end
    end
end

-- ------- TabGroup Container ----------
skinners["TabGroup"] = function(widget)
    -- Content border
    if widget.border then
        SetFlat(widget.border, C.bg, C.border)
    end

    -- Hook BuildTabs to skin tabs after they're created
    if not widget._tabSkinHooked then
        widget._tabSkinHooked = true
        local origBuildTabs = widget.BuildTabs
        widget.BuildTabs = function(self, ...)
            origBuildTabs(self, ...)
            -- Skin each tab after build
            if self.tabs then
                for _, tab in pairs(self.tabs) do
                    if tab:IsShown() and not tab._flatSkinned then
                        tab._flatSkinned = true

                        -- Strip Blizzard tab textures
                        StripTextures(tab)

                        if not tab._flatBG then
                            local bg = tab:CreateTexture(nil, "BACKGROUND")
                            bg:SetPoint("TOPLEFT", 0, 0)
                            bg:SetPoint("BOTTOMRIGHT", 0, 0)
                            bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                            tab._flatBG = bg
                        end

                        if not tab._flatBorderFrame then
                            local bf = CreateFrame("Frame", nil, tab)
                            bf:SetPoint("TOPLEFT", -1, 1)
                            bf:SetPoint("BOTTOMRIGHT", 1, -1)
                            bf:SetBackdrop(flatBackdrop)
                            bf:SetBackdropColor(0, 0, 0, 0)
                            bf:SetBackdropBorderColor(unpack(C.border))
                            tab._flatBorderFrame = bf
                        end

                        -- Replace the tab look function entirely (Blizzard PanelTemplates
                        -- functions are bypassed because we stripped their textures).
                        tab.SetSelected = function(self, selected)
                            self.selected = selected
                            if self._flatBG then
                                if selected then
                                    self._flatBG:SetVertexColor(unpack(C.accent))
                                    if self.text then self.text:SetTextColor(1, 1, 1) end
                                elseif self.disabled then
                                    self._flatBG:SetVertexColor(0.08, 0.08, 0.08, 1)
                                    if self.text then self.text:SetTextColor(unpack(C.disabled)) end
                                else
                                    self._flatBG:SetVertexColor(unpack(C.btn))
                                    if self.text then self.text:SetTextColor(unpack(C.gold)) end
                                end
                            end
                        end

                        tab:HookScript("OnEnter", function(self)
                            if not self.selected and not self.disabled and self._flatBG then
                                self._flatBG:SetVertexColor(unpack(C.btnHover))
                            end
                        end)
                        tab:HookScript("OnLeave", function(self)
                            if not self.selected and not self.disabled and self._flatBG then
                                self._flatBG:SetVertexColor(unpack(C.btn))
                            end
                        end)
                    end
                    -- Re-apply the selected look each BuildTabs call
                    if tab._flatBG then
                        if tab.selected then
                            tab._flatBG:SetVertexColor(unpack(C.accent))
                            if tab.text then tab.text:SetTextColor(1, 1, 1) end
                        elseif tab.disabled then
                            tab._flatBG:SetVertexColor(0.08, 0.08, 0.08, 1)
                            if tab.text then tab.text:SetTextColor(unpack(C.disabled)) end
                        else
                            tab._flatBG:SetVertexColor(unpack(C.btn))
                            if tab.text then tab.text:SetTextColor(unpack(C.gold)) end
                        end
                    end
                end
            end
        end
    end
end

-- ------- InlineGroup Container ----------
skinners["InlineGroup"] = function(widget)
    -- The border is the second frame child
    local frame = widget.frame
    if not frame then return end
    for i = 1, frame:GetNumChildren() do
        local child = select(i, frame:GetChildren())
        if child and child.SetBackdrop and child ~= widget.content then
            SetFlat(child, { 0.09, 0.09, 0.09, 0.7 }, C.border)
        end
    end
    if widget.titletext then
        widget.titletext:SetTextColor(unpack(C.accent))
    end
end

-- ------- Button Widget ----------
skinners["Button"] = function(widget)
    SkinFlatButton(widget.frame)
end

-- ------- CheckBox Widget ----------
skinners["CheckBox"] = function(widget)
    if not widget.checkbg then return end
    if widget.checkbg._flatSkinned then return end
    widget.checkbg._flatSkinned = true

    -- Replace checkbox background texture with flat square
    widget.checkbg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    widget.checkbg:SetVertexColor(0.12, 0.12, 0.12, 1)

    -- Replace check texture with a simpler look
    widget.check:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    widget.check:SetVertexColor(unpack(C.accent))

    -- Remove the blizzard highlight
    if widget.highlight then
        widget.highlight:SetTexture(nil)
    end

    -- Add a flat border frame behind the checkbox
    if not widget.frame._checkBorder then
        local borderFrame = CreateFrame("Frame", nil, widget.frame)
        borderFrame:SetPoint("TOPLEFT", widget.checkbg, "TOPLEFT", -1, 1)
        borderFrame:SetPoint("BOTTOMRIGHT", widget.checkbg, "BOTTOMRIGHT", 1, -1)
        borderFrame:SetBackdrop(flatBackdrop)
        borderFrame:SetBackdropColor(0, 0, 0, 0)
        borderFrame:SetBackdropBorderColor(unpack(C.border))
        borderFrame:SetFrameLevel(widget.frame:GetFrameLevel())
        widget.frame._checkBorder = borderFrame
    end

    -- Override SetType to keep flat look for both checkbox and radio
    local origSetType = widget.SetType
    widget.SetType = function(self, checkType)
        local checkbg = self.checkbg
        local check = self.check
        local highlight = self.highlight

        local size
        if checkType == "radio" then
            size = 16
        else
            size = 24
        end
        checkbg:SetHeight(size)
        checkbg:SetWidth(size)
        checkbg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        checkbg:SetVertexColor(0.12, 0.12, 0.12, 1)
        checkbg:SetTexCoord(0, 1, 0, 1)
        check:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        check:SetVertexColor(unpack(C.accent))
        check:SetTexCoord(0, 1, 0, 1)
        check:SetBlendMode("BLEND")
        if highlight then
            highlight:SetTexture(nil)
        end
    end
end

-- ------- Slider Widget ----------
skinners["Slider"] = function(widget)
    local slider = widget.slider
    if not slider or slider._flatSkinned then return end
    slider._flatSkinned = true

    -- Flat track
    slider:SetBackdrop(flatBackdrop)
    slider:SetBackdropColor(0.10, 0.10, 0.10, 1)
    slider:SetBackdropBorderColor(unpack(C.border))

    -- Flat thumb - use a solid texture
    slider:SetThumbTexture("Interface\\ChatFrame\\ChatFrameBackground")
    local thumb = slider:GetThumbTexture()
    if thumb then
        thumb:SetVertexColor(unpack(C.accent))
        thumb:SetWidth(12)
        thumb:SetHeight(18)
    end

    -- Slider value editbox
    if widget.editbox then
        widget.editbox:SetBackdrop(flatBackdrop)
        widget.editbox:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
        widget.editbox:SetBackdropBorderColor(unpack(C.border))
    end
end

-- ------- EditBox Widget ----------
skinners["EditBox"] = function(widget)
    if widget.editbox then
        SkinEditBoxFrame(widget.editbox)
    end
    -- Skin the OK button
    if widget.button then
        SkinFlatButton(widget.button)
    end
end

-- ------- MultiLineEditBox Widget ----------
skinners["MultiLineEditBox"] = function(widget)
    if widget.scrollBG then
        SetFlat(widget.scrollBG, { 0.08, 0.08, 0.08, 0.9 }, C.border)
    end
    if widget.button then
        SkinFlatButton(widget.button)
    end
end

-- ------- Dropdown Widget ----------
skinners["Dropdown"] = function(widget)
    if not widget.dropdown or widget.dropdown._flatSkinned then return end
    widget.dropdown._flatSkinned = true

    local dropdown = widget.dropdown
    local name = dropdown:GetName()
    if not name then return end

    -- Hide the Blizzard dropdown textures
    local left = _G[name .. "Left"]
    local middle = _G[name .. "Middle"]
    local right = _G[name .. "Right"]
    if left then left:SetAlpha(0) end
    if middle then middle:SetAlpha(0) end
    if right then right:SetAlpha(0) end

    -- Create flat background
    if not dropdown._flatBG then
        local bg = dropdown:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        bg:SetVertexColor(0.10, 0.10, 0.10, 1)
        bg:SetPoint("TOPLEFT", 18, -2)
        bg:SetPoint("BOTTOMRIGHT", -20, 4)
        dropdown._flatBG = bg
    end

    -- Flat border around dropdown
    if not dropdown._flatBorder then
        local border = CreateFrame("Frame", nil, dropdown)
        border:SetPoint("TOPLEFT", 17, -1)
        border:SetPoint("BOTTOMRIGHT", -21, 3)
        border:SetBackdrop(flatBackdrop)
        border:SetBackdropColor(0, 0, 0, 0)
        border:SetBackdropBorderColor(unpack(C.border))
        dropdown._flatBorder = border
    end

    -- Style the dropdown button (arrow)
    local button = _G[name .. "Button"]
    if button then
        button:SetNormalTexture(nil)
        button:SetPushedTexture(nil)
        button:SetHighlightTexture(nil)
        if button.SetDisabledTexture then button:SetDisabledTexture(nil) end

        if not button._flatBG then
            local bg = button:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
            bg:SetVertexColor(unpack(C.btn))
            button._flatBG = bg
        end

        -- Simple arrow text indicator
        if not button._arrowText then
            local arrow = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            arrow:SetPoint("CENTER", 0, 1)
            arrow:SetText("▼")
            arrow:SetTextColor(unpack(C.gold))
            button._arrowText = arrow
        end
    end
end

-- ------- Dropdown-Pullout ----------
skinners["Dropdown-Pullout"] = function(widget)
    local frame = widget.frame
    if not frame then return end
    SetFlat(frame, C.bg, C.border)

    -- Skin the slider / scrollbar if present
    if widget.slider then
        widget.slider:SetBackdrop(flatBackdrop)
        widget.slider:SetBackdropColor(0.10, 0.10, 0.10, 1)
        widget.slider:SetBackdropBorderColor(unpack(C.border))
        widget.slider:SetThumbTexture("Interface\\ChatFrame\\ChatFrameBackground")
        local thumb = widget.slider:GetThumbTexture()
        if thumb then
            thumb:SetVertexColor(unpack(C.accent))
            thumb:SetWidth(8)
            thumb:SetHeight(16)
        end
    end
end

-- ------- Dropdown Items (shared skinner for all item types) ----------
local function SkinDropdownItem(widget)
    if not widget.highlight then return end
    if widget.highlight._flatSkinned then return end
    widget.highlight._flatSkinned = true

    widget.highlight:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    widget.highlight:SetBlendMode("BLEND")
    widget.highlight:SetVertexColor(unpack(C.accent))
    widget.highlight:SetAlpha(0.3)

    if widget.check then
        widget.check:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        widget.check:SetVertexColor(unpack(C.accent))
        widget.check:SetWidth(10)
        widget.check:SetHeight(10)
    end
end

skinners["Dropdown-Item-Toggle"]  = SkinDropdownItem
skinners["Dropdown-Item-Execute"] = SkinDropdownItem
skinners["Dropdown-Item-Menu"]    = SkinDropdownItem

-- ------- Heading Widget ----------
skinners["Heading"] = function(widget)
    -- Replace the Blizzard tooltip border lines with flat accent lines
    if widget.left then
        widget.left:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        widget.left:SetVertexColor(unpack(C.headerLine))
        widget.left:SetHeight(1)
        widget.left:SetTexCoord(0, 1, 0, 1)
    end
    if widget.right then
        widget.right:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        widget.right:SetVertexColor(unpack(C.headerLine))
        widget.right:SetHeight(1)
        widget.right:SetTexCoord(0, 1, 0, 1)
    end
    if widget.label then
        widget.label:SetTextColor(unpack(C.gold))
    end
end

-- ------- Label Widget ----------
skinners["Label"] = function(widget)
    -- No changes needed; labels inherit font colours from AceConfig
end

-- ------- Icon Widget ----------
skinners["Icon"] = function(widget)
    -- No changes needed; icon images should remain unchanged
end

-- ------- ScrollFrame Container ----------
skinners["ScrollFrame"] = function(widget)
    -- Skin the scrollbar if the container has one
    if widget.scrollbar then
        StripTextures(widget.scrollbar)
    end
end

-- ------- BlizOptionsGroup Container ----------
skinners["BlizOptionsGroup"] = function(widget)
    -- No special skinning needed for Blizzard options integration
end

-- ==========================================================
-- HOOK AceGUI:Create
-- ==========================================================

local origCreate = AceGUI.Create
AceGUI.Create = function(self, widgetType, ...)
    local widget = origCreate(self, widgetType, ...)
    if widget then
        local skinner = skinners[widgetType]
        if skinner then
            skinner(widget)
        end
    end
    return widget
end
