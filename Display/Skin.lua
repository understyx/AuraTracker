local addonName, ns = ...

local _G = _G
local pairs, ipairs, select, type, unpack = pairs, ipairs, select, type, unpack
local hooksecurefunc = hooksecurefunc
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
    if btn.isSkinned then return end
    btn.isSkinned = true

    -- Strip named subtextures (ElvUI HandleButton pattern)
    local name = btn.GetName and btn:GetName()
    if name then
        local left   = _G[name .. "Left"]
        local middle = _G[name .. "Middle"]
        local right  = _G[name .. "Right"]
        if left   then left:SetAlpha(0)   end
        if middle then middle:SetAlpha(0) end
        if right  then right:SetAlpha(0)  end
    end
    if btn.Left   then btn.Left:SetAlpha(0)   end
    if btn.Middle then btn.Middle:SetAlpha(0) end
    if btn.Right  then btn.Right:SetAlpha(0)  end

    StripTextures(btn)
    if btn.SetNormalTexture    then btn:SetNormalTexture("")    end
    if btn.SetPushedTexture    then btn:SetPushedTexture("")    end
    if btn.SetHighlightTexture then btn:SetHighlightTexture("") end
    if btn.SetDisabledTexture  then btn:SetDisabledTexture("")  end

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
    if not frame or frame.isSkinned then return end
    frame.isSkinned = true

    -- Strip named subtextures (ElvUI HandleButton pattern)
    local name = frame.GetName and frame:GetName()
    if name then
        local left   = _G[name .. "Left"]
        local middle = _G[name .. "Middle"]
        local right  = _G[name .. "Right"]
        if left   then left:SetAlpha(0)   end
        if middle then middle:SetAlpha(0) end
        if right  then right:SetAlpha(0)  end
    end
    if frame.Left   then frame.Left:SetAlpha(0)   end
    if frame.Middle then frame.Middle:SetAlpha(0) end
    if frame.Right  then frame.Right:SetAlpha(0)  end

    StripTextures(frame)
    if frame.SetNormalTexture   then frame:SetNormalTexture("")   end
    if frame.SetPushedTexture   then frame:SetPushedTexture("")   end
    if frame.SetHighlightTexture then frame:SetHighlightTexture("") end
    if frame.SetDisabledTexture then frame:SetDisabledTexture("") end

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
    if not editbox or editbox.isSkinned then return end
    editbox.isSkinned = true

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

-- ------- Shared Font Constants ----------
local TAB_FONT     = "Fonts\\FRIZQT__.TTF"
local TAB_FONTSIZE = 12

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
                    if btn:IsShown() then
                        if not btn.isSkinned then
                            btn.isSkinned = true
                            -- Remove the default highlight
                            local hl = btn:GetHighlightTexture()
                            if hl then
                                hl:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                                hl:SetVertexColor(unpack(C.accent))
                                hl:SetAlpha(0.2)
                            end
                        end
                        -- Apply consistent font to tree button text
                        local text = btn.text or btn:GetFontString()
                        if text and text.SetFont then
                            text:SetFont(TAB_FONT, TAB_FONTSIZE, "")
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

-- Export shared skinning primitives so SkinTabs.lua and SkinDropdown.lua
-- can access them after loading.
ns.AuraTracker._Skin = {
    C              = C,
    flatBackdrop   = flatBackdrop,
    SetFlat        = SetFlat,
    StripTextures  = StripTextures,
    SkinFlatButton = SkinFlatButton,
    skinners       = skinners,
    TAB_FONT       = TAB_FONT,
    TAB_FONTSIZE   = TAB_FONTSIZE,
}


-- ==========================================================
-- SCOPE SKINNING TO AURATRACKER WIDGETS ONLY
-- ==========================================================
-- AceGUI is a shared library – hooking Create globally would
-- re-skin every AceGUI widget from every addon (ElvUI config,
-- DBM options, etc.).  Instead we track when AceConfigDialog
-- is building *our* options and only apply skinning then.
--
-- If ElvUI is loaded we skip our AceGUI hooks entirely so we
-- don't overwrite its own skin and cause visual glitches when
-- widgets are pooled and reused across addon panels.

local function SetupSkinningHooks()
    -- If ElvUI is present, let it handle all AceGUI skinning.
    if _G.ElvUI then return end

    local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
    if not AceConfigDialog then return end

    local skinningDepth = 0

    local origOpen = AceConfigDialog.Open
    AceConfigDialog.Open = function(self, appName, ...)
        if appName ~= addonName then return origOpen(self, appName, ...) end
        skinningDepth = skinningDepth + 1
        local ok, result = pcall(origOpen, self, appName, ...)
        skinningDepth = skinningDepth - 1
        if not ok then error(result, 0) end
        return result
    end

    local origFeedGroup = AceConfigDialog.FeedGroup
    AceConfigDialog.FeedGroup = function(self, appName, ...)
        if appName ~= addonName then return origFeedGroup(self, appName, ...) end
        skinningDepth = skinningDepth + 1
        local ok, err = pcall(origFeedGroup, self, appName, ...)
        skinningDepth = skinningDepth - 1
        if not ok then error(err, 0) end
    end

    local origCreate = AceGUI.Create
    AceGUI.Create = function(self, widgetType, ...)
        local widget = origCreate(self, widgetType, ...)
        if widget and skinningDepth > 0 then
            local skinner = skinners[widgetType]
            if skinner then
                skinner(widget)
            end
        end
        return widget
    end
end

-- Defer hook setup until all addons have loaded so we can
-- reliably detect ElvUI (which loads after us alphabetically).
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    SetupSkinningHooks()
end)
