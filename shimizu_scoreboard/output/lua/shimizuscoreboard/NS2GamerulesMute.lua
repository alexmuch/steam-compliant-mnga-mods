if Server then
    local VanillaGetCanPlayerHearPlayer = NS2Gamerules.GetCanPlayerHearPlayer
    function NS2Gamerules:GetCanPlayerHearPlayer(listenerPlayer, speakerPlayer, channelType)
        if speakerPlayer and SSB_GetTeamVoiceMutedForListener and
                SSB_GetTeamVoiceMutedForListener(listenerPlayer, speakerPlayer:GetTeamNumber()) then
            return false
        end
        return VanillaGetCanPlayerHearPlayer(self, listenerPlayer, speakerPlayer, channelType)
    end

    local VanillaJoinTeam = NS2Gamerules.JoinTeam
    function NS2Gamerules:JoinTeam(player, newTeamNumber, force)
        local oldTeamNumber = player and player:GetTeamNumber()
        local client = player and Server.GetOwner(player)
        local success, newPlayer = VanillaJoinTeam(self, player, newTeamNumber, force)
        if success and oldTeamNumber == kSpectatorIndex and newTeamNumber ~= kSpectatorIndex and
                SSB_ClearTeamVoiceMutesForClient then
            SSB_ClearTeamVoiceMutesForClient(client,
                string.format("left spectator for team %s", ToString(newTeamNumber)))
        end
        return success, newPlayer
    end

    local VanillaEndGame = NS2Gamerules.EndGame
    function NS2Gamerules:EndGame(winningTeam, autoConceded)
        local result = VanillaEndGame(self, winningTeam, autoConceded)
        if SSB_ClearAllCallMutes then SSB_ClearAllCallMutes() end
        return result
    end
end
