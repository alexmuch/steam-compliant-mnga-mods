-- MNGA multi-ping: while the dead-player map cursor is up, mouse clicks belong
-- to the map (right-click ping / alien left-click spawn select) and must not
-- cycle the first-person spectate target. Vanilla GUIFirstPersonSpectate fires
-- SwitchFirstPersonSpectatePlayer on any click, regardless of the map state.

local oldSendKeyEvent = GUIFirstPersonSpectate.SendKeyEvent

function GUIFirstPersonSpectate:SendKeyEvent(key, down)

    if (key == InputKey.MouseButton0 or key == InputKey.MouseButton1)
            and MNGA_GetMapCursorActive and MNGA_GetMapCursorActive() then

        if down then
            -- Print("MNGA GUIFirstPersonSpectate: swallowed mouse click, map cursor active")
        end
        return

    end

    return oldSendKeyEvent(self, key, down)

end
