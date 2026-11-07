Script.Load("lua/mnga_administration/GUIMenuMNGAInfoButton.lua")

local oldCreateLinksButtons = GUIMainMenu.CreateLinksButtons

function GUIMainMenu:CreateLinksButtons()
    oldCreateLinksButtons(self)

    Print("[mnga_menu] Creating MNGA main-menu information button.")
    self.mngaInfoButton = CreateGUIObject(
        "mngaInfoButton",
        GUIMenuMNGAInfoButton,
        self.linkButtonsHolder
    )
end
