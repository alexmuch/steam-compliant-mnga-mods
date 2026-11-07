-- Post-hook on lua/Hud/Marine/GUIMarineHUD.lua.
-- Marine_Client hides the whole marine HUD ("Alive" invoker) the moment the
-- marine dies, and the research list (GUIEvent) is a child of that HUD
-- background, so it vanished during the death screen. The alien HUD stays up
-- while dying, so aliens already kept it. Detach the list frame into its own
-- root item (same layer/position: the HUD background is a full-screen,
-- non-scaling item at 0,0) and keep it visible while the local player is dead.
-- See .claude/docs/dead-research-list.md.

local oldInitialize = GUIMarineHUD.Initialize
function GUIMarineHUD:Initialize()

    oldInitialize(self)

    local frame = self.eventDisplay and self.eventDisplay.notificationFrame
    if frame and self.background then
        self.background.guiItem:RemoveChild(frame)
        frame:SetLayer(kGUILayerPlayerHUDBackground)
    end

    self:UpdateVisibility()

end

local oldUpdateVisibility = GUIMarineHUD.UpdateVisibility
function GUIMarineHUD:UpdateVisibility()

    oldUpdateVisibility(self)

    local frame = self.eventDisplay and self.eventDisplay.notificationFrame
    if frame then

        local player = Client.GetLocalPlayer()
        local dead = player ~= nil and not player:GetIsAlive()
        local show = GetAdvancedOption("unlocks") and (self.visible or dead) and true or false
        frame:SetIsVisible(show)

    end

end
