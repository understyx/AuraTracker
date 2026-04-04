local addonName, ns = ...

local _S = ns.AuraTracker._Skin
local C = _S.C
local flatBackdrop = _S.flatBackdrop
local StripTextures = _S.StripTextures
local skinners = _S.skinners
local TAB_FONT = _S.TAB_FONT
local TAB_FONTSIZE = _S.TAB_FONTSIZE
local CreateFrame = CreateFrame
local unpack = unpack

-- ------- TabGroup Container ----------

-- Flat tab look helper (no PanelTemplates dependency)
local function FlatTab_UpdateLook(tab)
    if not tab._flatBG then return end
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

local function SkinOneTab(tab)
    if tab.isSkinned then return end
    tab.isSkinned = true

    -- Strip Blizzard tab textures
    StripTextures(tab)

    -- Remove the Blizzard OnShow handler that resizes stripped HighlightTexture
    tab:SetScript("OnShow", nil)

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

    -- Replace SetText so it no longer calls PanelTemplates_TabResize.
    -- Note: _SetText was saved by CreateTab (AceGUIContainer-TabGroup line 120).
    if not tab._flatSetTextInstalled then
        tab._flatSetTextInstalled = true
        tab.SetText = function(self, text)
            if self._SetText then
                self:_SetText(text)
            end
            -- Ensure consistent font size each time text is set
            if self.text then
                self.text:SetFont(TAB_FONT, TAB_FONTSIZE, "")
            end
        end
    end

    -- Set initial font size
    if tab.text then
        tab.text:SetFont(TAB_FONT, TAB_FONTSIZE, "")
    end

    -- Replace SetSelected / SetDisabled so they no longer call PanelTemplates
    tab.SetSelected = function(self, selected)
        self.selected = selected
        FlatTab_UpdateLook(self)
    end

    tab.SetDisabled = function(self, disabled)
        self.disabled = disabled
        FlatTab_UpdateLook(self)
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

local TAB_PADDING  = 8   -- horizontal text padding per side
local TAB_HEIGHT   = 24
local TAB_GAP      = 2   -- gap between flat tabs

skinners["TabGroup"] = function(widget)
    -- Content border
    if widget.border then
        SetFlat(widget.border, C.bg, C.border)
    end

    -- Replace BuildTabs entirely so we control positioning without PanelTemplates
    if not widget._tabSkinHooked then
        widget._tabSkinHooked = true

        widget.BuildTabs = function(self)
            local titleText = self.titletext:GetText()
            local hastitle = (titleText and titleText ~= "")
            local tablist = self.tablist
            local tabs = self.tabs

            if not tablist then return end

            local containerWidth = self.frame.width or self.frame:GetWidth() or 0

            -- Ensure enough tab buttons exist and apply text / state
            for i, v in ipairs(tablist) do
                local tab = tabs[i]
                if not tab then
                    tab = self:CreateTab(i)
                    tabs[i] = tab
                end
                tab:Show()
                tab:SetText(v.text)
                tab:SetDisabled(v.disabled)
                tab.value = v.value

                SkinOneTab(tab)
            end

            -- Hide surplus tabs
            for i = (#tablist) + 1, #tabs do
                tabs[i]:Hide()
            end

            -- Measure natural widths (text + padding)
            local naturalWidths = {}
            local totalNatural = 0
            for i = 1, #tablist do
                local tw = (tabs[i].text and tabs[i].text:GetStringWidth() or 40) + TAB_PADDING * 2
                naturalWidths[i] = tw
                totalNatural = totalNatural + tw
            end

            -- Distribute extra space if tabs don't fill the row
            local numtabs = #tablist
            local totalGaps = (numtabs - 1) * TAB_GAP
            local availableForTabs = containerWidth - totalGaps
            local finalWidths = {}
            if totalNatural < availableForTabs and numtabs > 0 then
                local extra = (availableForTabs - totalNatural) / numtabs
                for i = 1, numtabs do
                    finalWidths[i] = naturalWidths[i] + extra
                end
            else
                for i = 1, numtabs do
                    finalWidths[i] = naturalWidths[i]
                end
            end

            -- Position tabs in a single row
            local topOffset = hastitle and 14 or 7
            for i = 1, numtabs do
                local tab = tabs[i]
                tab:SetHeight(TAB_HEIGHT)
                tab:SetWidth(finalWidths[i])
                tab:ClearAllPoints()
                if i == 1 then
                    tab:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -topOffset)
                else
                    tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", TAB_GAP, 0)
                end
                FlatTab_UpdateLook(tab)
            end

            -- Update content border offset
            self.borderoffset = topOffset + TAB_HEIGHT + 2
            self.border:SetPoint("TOPLEFT", 1, -self.borderoffset)
        end
    end
end
