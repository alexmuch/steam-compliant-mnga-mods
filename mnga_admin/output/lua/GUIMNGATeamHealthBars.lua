-- Non-visual key script for teammate health bars "On press" mode (hold to show).
-- State lives in mnga_administration/TeamHealthBars_Client.lua.
Script.Load( "lua/BindingsDialog.lua" )

class "GUIMNGATeamHealthBars" ( GUIScript )

local kBindingName = "MNGATeamHealthBars"

function GUIMNGATeamHealthBars:Initialize()
    -- Only used to clear a held key whose release was lost to chat or the menu.
    self.updateInterval = 0.25
end

function GUIMNGATeamHealthBars:Uninitialize()
    if MNGA_TeamHealthBars then
        MNGA_TeamHealthBars.SetHeld( false )
    end
end

function GUIMNGATeamHealthBars:SendKeyEvent( Key, Down )
    local Module = MNGA_TeamHealthBars
    if not Module or not Module.GetIsOnPressMode() then return false end
    if not GetIsBinding( Key, kBindingName ) then return false end

    if Down and ( ChatUI_EnteringChatMessage() or MainMenu_GetIsOpened() ) then
        return false
    end
    Module.SetHeld( Down )
    -- Don't eat the key, other bindings on it keep working.
    return false
end

function GUIMNGATeamHealthBars:Update( DeltaTime )
    local Module = MNGA_TeamHealthBars
    if Module and Module.GetIsHeld() and ( ChatUI_EnteringChatMessage() or MainMenu_GetIsOpened() ) then
        Module.SetHeld( false )
    end
end
