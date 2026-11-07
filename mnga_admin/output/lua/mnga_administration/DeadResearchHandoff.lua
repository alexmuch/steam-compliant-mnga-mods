-- Post-hook on lua/Hud/GUIEvent.lua (GUINotificationItem is loaded by it).
-- Makes the alive HUD list <-> dead list (GUIMNGADeadResearch) switch look
-- continuous. During a short window after ClientUI swaps scripts
-- (DeadResearchClientUI.lua opens it):
--  * new notification items skip the 0.2 s hidden pause and 0.5 s fade-in;
--  * a HUD GUIEvent drains every queued notification in one update instead
--    of one per 1/30 s.
-- See .claude/docs/dead-research-list.md.

local kInstantFadeTime = 0.05

gMNGAResearchHandoffUntil = gMNGAResearchHandoffUntil or 0

function MNGAGetResearchHandoffActive()
    return Shared.GetTime() < gMNGAResearchHandoffUntil
end

local oldCreateNotificationItem = CreateNotificationItem
function CreateNotificationItem(scriptHandle, techId, scale, parent, useMarineStyle, entityId)

    local item = oldCreateNotificationItem(scriptHandle, techId, scale, parent, useMarineStyle, entityId)
    if item and MNGAGetResearchHandoffActive() then
        item.mngaInstant = true
        if item.background then
            item.background:SetIsVisible(true)
        end
    end
    return item

end

local oldFadeIn = GUINotificationItem.FadeIn
function GUINotificationItem:FadeIn(animDuration)

    if self.mngaInstant then
        animDuration = kInstantFadeTime
    end
    oldFadeIn(self, animDuration)

end

local oldUpdate = GUIEvent.Update
function GUIEvent:Update(deltaTime, newNotification)

    oldUpdate(self, deltaTime, newNotification)

    -- Dead-list script drains its own queue; only the vanilla HUDs pull here.
    if newNotification ~= nil and MNGAGetResearchHandoffActive()
            and not (self.script and self.script.mngaDeadResearch) then

        local drained = 0
        local nextNotification = PlayerUI_GetRecentNotification()
        while nextNotification ~= nil and drained < 32 do
            oldUpdate(self, 0, nextNotification)
            drained = drained + 1
            nextNotification = PlayerUI_GetRecentNotification()
        end

    end

end
