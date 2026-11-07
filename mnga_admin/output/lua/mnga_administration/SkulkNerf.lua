-- Runtime-configurable version of Shounen's Skulk combat nerf.
if Server then

local OldGenerateMove = PlayerBot.GenerateMove

local function GetNearbyMarineTarget( PlayerBot, Player, Tuning )
    local Target = PlayerBot.aim and PlayerBot.aim.target
    if not Target or not Player or not Player:isa( "Skulk" ) then return end
    if not IsValid( Target ) then
        PlayerBot.aim.target = nil
        Print( "[mngabots] cleared destroyed Skulk aim target" )
        return
    end
    if not Target:isa( "Marine" ) and not Target:isa( "Exo" ) then return end
    local Range = tonumber( Tuning.SkulkTargetRange ) or 25
    if Target:GetOrigin():GetDistanceSquared( Player:GetOrigin() ) <= Range * Range then
        return Target
    end
end

local function ApplyBiteTuning( PlayerBot, Player, Target, GeneratedMove, Tuning )
    if not HasMoveCommand( GeneratedMove.commands, Move.PrimaryAttack ) then return end
    if GetDistanceToTouch( Player:GetEyePos(), Target ) >= ( tonumber( Tuning.SkulkBiteGateRange ) or 1.5 ) then return end
    local Now = Shared.GetTime()
    if PlayerBot.mngaNextBiteDecisionTime and Now < PlayerBot.mngaNextBiteDecisionTime then
        GeneratedMove.commands = RemoveMoveCommand( GeneratedMove.commands, Move.PrimaryAttack )
        return
    end
    local Interval = math.max( 0, tonumber( Tuning.SkulkBiteDecisionInterval ) or 0.65 )
    local Chance = math.max( 0, math.min( 1, tonumber( Tuning.SkulkBiteAttemptChance ) or 0.5 ) )
    PlayerBot.mngaNextBiteDecisionTime = Now + Interval
    if math.random() >= Chance then
        GeneratedMove.commands = RemoveMoveCommand( GeneratedMove.commands, Move.PrimaryAttack )
    end
end

function PlayerBot:GenerateMove()
    local GeneratedMove = OldGenerateMove( self )
    local Tuning = gMNGABotTuning
    if not Tuning then return GeneratedMove end
    local Player = self:GetPlayer()
    local Target = GetNearbyMarineTarget( self, Player, Tuning )
    if not Target then return GeneratedMove end
    if Tuning.SkulkRemoveJump ~= false then
        GeneratedMove.commands = RemoveMoveCommand( GeneratedMove.commands, Move.Jump )
    end
    if Tuning.SkulkForceForward ~= false then
        GeneratedMove.move = Vector( 0, 0, 1 )
    end
    ApplyBiteTuning( self, Player, Target, GeneratedMove, Tuning )
    return GeneratedMove
end

Print( "[mngabots] configurable Skulk combat tuning hook installed" )

end
