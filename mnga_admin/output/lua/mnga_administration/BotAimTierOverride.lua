-- Runtime-configurable bot aim tuning. The active profile is owned by the
-- mngaadministration Shine plugin and may change without recreating bots.
if Server then

local OldGetAccuracyGoal = BotAim.GetAccuracyGoal
local OldGetAimPoint = BotAim_GetAimPoint

local function GetTuning()
    return gMNGABotTuning
end

function BotAim:GetServerSkillTier()
    local Tuning = GetTuning()
    return Tuning and Tuning.AimTier or 1
end

BotAim.kMinimumAccuracy = 0

function BotAim:GetAccuracyGoal( WeaponGroup )
    local Goal = OldGetAccuracyGoal( self, WeaponGroup )
    local Tuning = GetTuning()
    return math.min( Goal, Tuning and tonumber( Tuning.AccuracyCap ) or 15 )
end

function BotAim:GetTargetAcquisitionDelay()
    local Tuning = GetTuning()
    return Tuning and tonumber( Tuning.TargetAcquisitionDelay ) or 1
end

function BotAim_GetAimPoint( Self, Now, AimPoint, WeaponGroup )
    local Result = OldGetAimPoint( Self, Now, AimPoint, WeaponGroup )
    local Player = Self.owner and Self.owner:GetPlayer()
    local Tuning = GetTuning()
    local Multiplier = Tuning and tonumber( Tuning.MarineMissOffsetMultiplier ) or 2
    if Result and Self.missing and Self.missingOffset and Player
    and Player:GetTeamNumber() == kTeam1Index and Multiplier > 1 then
        Result = Result + Self.missingOffset * ( Multiplier - 1 )
    end
    return Result
end

Print( "[mngabots] configurable BotAim tuning hook installed" )

end
