-- Preserve sv_maxbots as the vanilla-mode authority while preventing the base
-- controller from performing synchronous bulk reconciliation.
if Server and BotTeamController and not BotTeamController.mngaGradualHookInstalled then

BotTeamController.mngaGradualHookInstalled = true
local OldSetMaxBots = BotTeamController.SetMaxBots
local OldUpdateBots = BotTeamController.UpdateBots

local function IsVanillaMode()
    -- NS2 Combat v2 owns bots with the plain vanilla controller (gCombatModeActive, set in its FileHooks).
    return gMNGABotMode == "vanilla" and gCombatModeActive ~= true
end

local function Schedule( Reason )
    if gMNGAAdministrationPlugin and not gMNGAAdministrationPlugin.BotControllerHardOffInProgress
    and gMNGAAdministrationPlugin.ScheduleBotReconcile then
        gMNGAAdministrationPlugin:ScheduleBotReconcile( Reason, 0 )
    end
end

function BotTeamController:SetMaxBots( NewMaxBots, CommanderBots )
    if not IsVanillaMode() then
        return OldSetMaxBots( self, NewMaxBots, CommanderBots )
    end
    NewMaxBots = math.max( 0, tonumber( NewMaxBots ) or 0 )
    local OldTarget = self.mngaVanillaMaxBots
    self.mngaVanillaMaxBots = NewMaxBots
    self.MaxBots = NewMaxBots
    self.addCommander1 = CommanderBots == true
    self.addCommander2 = CommanderBots == true
    Print( "%s", string.format( "[mngabots] vanilla target changed old=%s new=%s commanderBots=%s",
        tostring( OldTarget ), tostring( NewMaxBots ), tostring( CommanderBots == true ) ) )
    Schedule( "sv_maxbots changed" )
end

function BotTeamController:UpdateBots()
    if not IsVanillaMode() then
        return OldUpdateBots( self )
    end
    Schedule( "vanilla team population changed" )
end

Print( "[mngabots] gradual vanilla BotTeamController hook installed" )

end
