Script.Load("lua/menu2/GUIMenuExitButton.lua")
Script.Load("lua/menu2/wrappers/Tooltip.lua")
Script.Load("lua/mnga_administration/GUIMNGAInfo.lua")
Script.Load("lua/mnga_administration/GUIMNGAInfoData.lua")

local baseClass = GUIMenuExitButton
baseClass = GetTooltipWrappedClass(baseClass)
class "GUIMenuMNGAInfoButton" (baseClass)

GUIMenuMNGAInfoButton.kTextureRegular = PrecacheAsset("ui/newMenu/mnga_icon.dds")
GUIMenuMNGAInfoButton.kTextureHover = PrecacheAsset("ui/newMenu/mnga_icon_hover.dds")
GUIMenuMNGAInfoButton.kShadowScale = Vector(10, 5, 1)

function GUIMenuMNGAInfoButton:OnPressed()
    Print("[mnga_menu] Opening MNGA information panel.")
    self.infoPanel:Open()
end

function GUIMenuMNGAInfoButton:OnMainMenuClosed()
    self.infoPanel:Close()
end

function GUIMenuMNGAInfoButton:AttachInfoPanelToNavBar()
    local navBar = GetNavBar()
    if not navBar then
        return
    end

    self.infoPanel:SetParent(navBar)
    self:RemoveTimedCallback(self.navBarPollCallback)
    self.navBarPollCallback = nil
    Print("[mnga_menu] Attached MNGA information panel to navigation bar.")
end

function GUIMenuMNGAInfoButton:Initialize(params, errorDepth)
    errorDepth = (errorDepth or 1) + 1
    baseClass.Initialize(self, params, errorDepth)

    self:SetTooltip("MNGA Information")
    self.infoPanel = CreateGUIObject("mngaInfoPanel", GUIMNGAInfo)
    self.infoPanel:LoadText(gMNGAInfoData)

    self:HookEvent(GetMainMenu(), "OnClosed", self.OnMainMenuClosed)
    self.navBarPollCallback = self:AddTimedCallback(self.AttachInfoPanelToNavBar, 0.5, true)
end
