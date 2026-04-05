local addonName, ns = ...

local _S = ns.AuraTracker._Skin
local C = _S.C
local flatBackdrop = _S.flatBackdrop
local SetFlat = _S.SetFlat
local StripTextures = _S.StripTextures
local SkinFlatButton = _S.SkinFlatButton
local skinners = _S.skinners
local CreateFrame = CreateFrame
local _G = _G
local select = select

-- ------- Dropdown Widget ----------
skinners["Dropdown"] = function(widget)
    if not widget.dropdown or widget.dropdown.isSkinned then return end
    widget.dropdown.isSkinned = true

    local dropdown = widget.dropdown
    local name = dropdown:GetName()
    if not name then return end

    -- Hide the Blizzard dropdown textures (ElvUI HandleDropDownBox pattern)
    local left = _G[name .. "Left"]
    local middle = _G[name .. "Middle"]
    local right = _G[name .. "Right"]
    if left   then left:SetAlpha(0)   end
    if middle then middle:SetAlpha(0) end
    if right  then right:SetAlpha(0)  end

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
        if button.SetNormalTexture   then button:SetNormalTexture("")   end
        if button.SetPushedTexture   then button:SetPushedTexture("")   end
        if button.SetHighlightTexture then button:SetHighlightTexture("") end
        if button.SetDisabledTexture then button:SetDisabledTexture("") end

        if not button._flatBG then
            local bg = button:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
            bg:SetVertexColor(unpack(C.btn))
            button._flatBG = bg
        end

        -- Arrow texture indicator (avoids font glyph issues with Unicode)
        if not button._arrowTex then
            local arrow = button:CreateTexture(nil, "OVERLAY")
            arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
            arrow:SetVertexColor(unpack(C.gold))
            arrow:SetWidth(12)
            arrow:SetHeight(12)
            arrow:SetPoint("CENTER", 0, 0)
            button._arrowTex = arrow
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
    if widget.highlight.isSkinned then return end
    widget.highlight.isSkinned = true

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
    local frame = widget.frame
    if not frame or frame.isSkinned then return end
    frame.isSkinned = true

    -- Flat border around the icon image
    if not frame._flatBorder then
        local border = CreateFrame("Frame", nil, frame)
        border:SetPoint("TOPLEFT", widget.image, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", widget.image, "BOTTOMRIGHT", 1, -1)
        border:SetBackdrop(flatBackdrop)
        border:SetBackdropColor(0, 0, 0, 0)
        border:SetBackdropBorderColor(unpack(C.border))
        frame._flatBorder = border
    end

    -- Replace default highlight with flat accent overlay
    if widget.highlight then
        widget.highlight:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        widget.highlight:SetVertexColor(unpack(C.accent))
        widget.highlight:SetAlpha(0.3)
    end

    -- Style the label text if present
    if widget.label then
        widget.label:SetTextColor(unpack(C.white))
    end
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
