function PlayingTeam:TriggerAlert(techId, entity, force)

    

    local triggeredAlert = false
    
    assert(techId ~= kTechId.None)
    assert(techId ~= nil)
    assert(entity ~= nil)
    
    if GetGamerules():GetGameStarted() then
        
        if self.brain ~= nil then
            self.brain:AddNewAlert( techId, entity:GetId(), entity:GetOrigin() )
        end

        -- Lookup sound name
        local soundName = LookupTechData(techId, kTechDataAlertSound, "")
        if soundName ~= "" then
        
            local location = entity:GetOrigin()
            local isRepeat = (self.lastPlayedTeamAlertName ~= nil and self.lastPlayedTeamAlertName == soundName)
            
            local timeElapsed = math.huge
            if self.timeOfLastPlayedTeamAlert ~= nil then
                timeElapsed = Shared.GetTime() - self.timeOfLastPlayedTeamAlert
            end
            
            -- Ignore source players for some alerts
            local ignoreSourcePlayer = ConditionalValue(LookupTechData(techId, kTechDataAlertOthersOnly, false), nil, entity)
            local ignoreInterval = LookupTechData(techId, kTechDataAlertIgnoreInterval, false)
            
            local newAlertPriority = LookupTechData(techId, kTechDataAlertPriority, 0)
            if not self.lastAlertPriority then
                self.lastAlertPriority = 0
            end

            -- If time elapsed > kBaseAlertInterval and not a repeat, play it OR
            -- If time elapsed > kRepeatAlertInterval then play it no matter what
            if force or ignoreInterval or (timeElapsed >= PlayingTeam.kBaseAlertInterval and not isRepeat) or timeElapsed >= PlayingTeam.kRepeatAlertInterval or newAlertPriority  > self.lastAlertPriority then
            
                -- Play for commanders only or for the whole team
                local commandersOnly = not LookupTechData(techId, kTechDataAlertTeam, false)
                
                local ignoreDistance = LookupTechData(techId, kTechDataAlertIgnoreDistance, false)
                

                local isBot = entity.GetClient and entity:GetClient() and entity:GetClient():GetIsVirtual()
              
                -- bad code, 64 is the ammo request, 63 med request
                if isBot and (techId == 64 or techId == 63) then 
        
                else

                    self:PlayPrivateTeamSound(soundName, location, commandersOnly, ignoreSourcePlayer, ignoreDistance, entity)
                
										  
                
                    if not ignoreInterval then
                    
                        self.lastPlayedTeamAlertName = soundName
                        self.lastAlertPriority = newAlertPriority
                        self.timeOfLastPlayedTeamAlert = Shared.GetTime()
                        
                    end
                    
                    triggeredAlert = true
                    
                end

									 
				
                -- Check if we should also send out a team message for this alert.
                local sendTeamMessageType = LookupTechData(techId, kTechDataAlertSendTeamMessage)
                if sendTeamMessageType then
                    SendTeamMessage(self, sendTeamMessageType, entity:GetLocationId())
                end

                local TriggerAlert = Closure [=[
                    self techId entity
                    args player
                    player:TriggerAlert(techId, entity)
                ]=]{techId, entity}
                self:ForEachPlayer(TriggerAlert)
                
            end
            
        end
  
    end
    
    return triggeredAlert
    
end