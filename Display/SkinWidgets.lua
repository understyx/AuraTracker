local _, ns = ...

-- Widget skinners added to the shared skinners table exported by Skin.lua
local _Skin       = ns.AuraTracker._Skin
local C           = _Skin.C
local SetFlat     = _Skin.SetFlat
local StripTextures = _Skin.StripTextures
local SkinFlatButton = _Skin.SkinFlatButton
local skinners    = _Skin.skinners
local CreateFrame = CreateFrame
local select      = select

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
    if widget.checkbg.isSkinned then return end
    widget.checkbg.isSkinned = true

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

    -- Use hooksecurefunc to prevent Blizzard/AceGUI from restoring stock textures
    -- (mirrors ElvUI's HandleCheckBox pattern; the "" guard breaks any re-entry)
    local frame = widget.frame
    if frame.SetNormalTexture then
        hooksecurefunc(frame, "SetNormalTexture", function(self, texPath)
            if texPath and texPath ~= "" then self:SetNormalTexture("") end
        end)
    end
    if frame.SetPushedTexture then
        hooksecurefunc(frame, "SetPushedTexture", function(self, texPath)
            if texPath and texPath ~= "" then self:SetPushedTexture("") end
        end)
    end
    if frame.SetHighlightTexture then
        hooksecurefunc(frame, "SetHighlightTexture", function(self, texPath)
            if texPath and texPath ~= "" then self:SetHighlightTexture("") end
        end)
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
    if not slider or slider.isSkinned then return end
    slider.isSkinned = true

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
