if Server then
    local VanillaGetClientMuted = Player.GetClientMuted
    local loggedBlockedPairs = {}

    function Player:GetClientMuted(checkClientIndex)
        if VanillaGetClientMuted(self, checkClientIndex) then return true end
        if self:GetTeamNumber() ~= kSpectatorIndex or not SSB_GetTeamVoiceMutedForListener then
            return false
        end
        local speakerClient = Server.GetClientById(checkClientIndex)
        local speaker = speakerClient and speakerClient:GetControllingPlayer()
        if not speaker or not SSB_GetTeamVoiceMutedForListener(self, speaker:GetTeamNumber()) then
            return false
        end
        local key = string.format("%s:%s:%s", ToString(self:GetClientIndex()),
            ToString(checkClientIndex), ToString(speaker:GetTeamNumber()))
        if not loggedBlockedPairs[key] then
            loggedBlockedPairs[key] = true
            Print("[SSBTeamVoiceMute] Blocked speaker %s team %d for spectator %s",
                ToString(checkClientIndex), speaker:GetTeamNumber(), ToString(self:GetClientIndex()))
        end
        return true
    end

    Print("[SSBTeamVoiceMute] Installed Player:GetClientMuted routing guard")
end
