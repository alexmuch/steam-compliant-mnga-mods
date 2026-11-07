if Server then
    MNGA_RADIO = MNGA_RADIO or {}
    MNGA_RADIO.RecentLifeformKills = MNGA_RADIO.RecentLifeformKills or {}

    local Lifeforms = { "Gorge", "Lerk", "Fade", "Onos" }
    local OldOnEntityKilled = NS2Gamerules.OnEntityKilled

    function NS2Gamerules:OnEntityKilled( Target, Attacker, Doer, Point, Direction )
        local Result = OldOnEntityKilled( self, Target, Attacker, Doer, Point, Direction )
        if not GetConcedeSequenceActive() and Target and Target:isa( "Player" )
        and Target:GetTeamNumber() == kTeam2Index and Target.GetName
        and Target.GetSendDeathMessage and Target:GetSendDeathMessage( self.team1, Attacker ) then
            for _, Lifeform in ipairs( Lifeforms ) do
                if Target:isa( Lifeform ) then
                    local Name = Target:GetName()
                    MNGA_RADIO.RecentLifeformKills[ Lifeform ] = { Name = Name, Time = Shared.GetTime() }
                    break
                end
            end
        end
        return Result
    end

    local OldResetGame = NS2Gamerules.ResetGame
    function NS2Gamerules:ResetGame( ... )
        MNGA_RADIO.RecentLifeformKills = {}
        return OldResetGame( self, ... )
    end
end
