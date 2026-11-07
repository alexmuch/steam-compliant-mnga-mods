if Server then
    local function ResetTeamPingsForRoundStart(team)

        if team and team.ResetPlayerPings then
            team:ResetPlayerPings()
        end

    end

    local oldSetGameState = NS2Gamerules.SetGameState
    function NS2Gamerules:SetGameState(state)

        local oldState = self:GetGameState()
        oldSetGameState(self, state)

        if state == kGameState.Started and oldState ~= kGameState.Started then
            ResetTeamPingsForRoundStart(self.team1)
            ResetTeamPingsForRoundStart(self.team2)
        end

    end

	function NS2Gamerules:KillEnemiesNearCommandStructureInPreGame(timePassed)
    
        if self:GetGameState() < kGameState.Countdown then
        
            local commandStations = Shared.GetEntitiesWithClassname("CommandStructure")
            for _, ent in ientitylist(commandStations) do

                local location = GetLocationForPoint(ent:GetOrigin())
            
                local enemyPlayers = GetEntitiesForTeam("Player", GetEnemyTeamNumber(ent:GetTeamNumber()))
                for e = 1, #enemyPlayers do
                
                    local enemy = enemyPlayers[e]
                    local enemyLocation = GetLocationForPoint(enemy:GetOrigin())
                    if enemyLocation and location:GetName() == enemyLocation:GetName() then
                        local health = enemy:GetMaxHealth() * 0.2 * timePassed
                        local armor = enemy:GetMaxArmor() * 0.2 * timePassed
                        local damage = health + armor
                        -- enemy:TakeDamage(damage, nil, nil, nil, nil, armor, health, kDamageType.Normal)

                        if not enemy.lastReturnToBaseSend or enemy.lastReturnToBaseSend + 5 < Shared.GetTime() then
                            Server.SendNetworkMessage(enemy, "TeamMessage", { type = kTeamMessageTypes.ReturnToBase, data =  0 }, true)
                            enemy.lastReturnToBaseSend = Shared.GetTime()
                        end
                    end
                    
                end
                
            end
            
        end
        
    end
end
