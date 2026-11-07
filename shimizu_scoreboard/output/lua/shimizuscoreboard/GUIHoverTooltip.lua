-- Correct the base tooltip's first-use size calculation. The base implementation
-- measures before applying its scaled font, so a newly-created tooltip's first
-- background is too small until a later hover reuses the scaled text item.

local kTextCutoff = 400
local kBorderWidth
local kTooltipOffset

function GUIHoverTooltip:UpdateBorders()
    local borderSize = Vector(self.background:GetSize())
    borderSize.x = borderSize.x + 2 * kBorderWidth

    self.borderTop:SetPosition(Vector(-kBorderWidth, -kBorderWidth, 0))
    self.borderTop:SetSize(Vector(borderSize.x, kBorderWidth, 0))

    self.borderBottom:SetPosition(Vector(-kBorderWidth, 0, 0))
    self.borderBottom:SetSize(Vector(borderSize.x, kBorderWidth, 0))

    self.borderLeft:SetPosition(Vector(-kBorderWidth, 0, 0))
    self.borderLeft:SetSize(Vector(kBorderWidth, borderSize.y, 0))

    self.borderRight:SetPosition(Vector(0, 0, 0))
    self.borderRight:SetSize(Vector(kBorderWidth, borderSize.y, 0))
end

function GUIHoverTooltip:SetText(string, texture, textureSize)
    kBorderWidth = GUIScale(2)
    kTooltipOffset = GUIScale(10)

    -- Font state must be final before WordWrap() and dimension measurement.
    -- This is the only difference that matters for a fresh map-load tooltip.
    self.tooltip:SetScale(GetScaledVector())
    self.tooltip:SetFontName(Fonts.kAgencyFB_Small)
    GUIMakeFontScale(self.tooltip)

    local wrappedText = WordWrap(self.tooltip, string, 0, GUIScale(kTextCutoff))
    local width = self.tooltip:GetTextWidth(wrappedText) * self.tooltip:GetScale().x + kTooltipOffset * 2
    local height = self.tooltip:GetTextHeight(wrappedText) * self.tooltip:GetScale().y + kTooltipOffset * 2

    self.tooltip:SetText(wrappedText)
    self.tooltip:SetPosition(Vector(kTooltipOffset, kTooltipOffset, 0))

    if texture then
        textureSize = GUIScale(textureSize)

        self.image:SetTexture(texture)
        self.image:SetSize(textureSize)
        self.image:SetPosition(Vector(-textureSize.x / 2, -kTooltipOffset - textureSize.y, 0))
        width = math.max(width, self.image:GetSize().x + kTooltipOffset * 2)
        height = height + textureSize.y + GUIScale(5)
    else
        self.image:SetTexture(nil)
        self.image:SetSize(Vector(0, 0, 0))
    end

    self.background:SetSize(Vector(width, height, 0))
    self:UpdateBorders()
end
