-- MNGA multi-ping: client->server map ping from dead players.
-- Registered as a post-hook on NetworkMessages.lua so the registration runs
-- identically in every VM that loads it (Server/Client/Predict).

local kMNGAMapPingMessage =
{
    position = "vector",
}

Shared.RegisterNetworkMessage("MNGAMapPing", kMNGAMapPingMessage)

-- MNGA contextual ping (see ContextPingShared.lua / ContextPingServer.lua).
Script.Load("lua/mnga_administration/ContextPingShared.lua")

-- Client -> server: the entity under the pinger's crosshair, picked on the
-- client (no lag) right before the vanilla "Ping" VoiceMessage is sent. The
-- server validates it; Entity.invalidId means "no contextual target".
Shared.RegisterNetworkMessage("MNGAContextPingTarget", { targetId = "entityid" })

-- Commander world-click ping with the entity under the cursor.
Shared.RegisterNetworkMessage("MNGACommanderContextPing", { position = "vector", targetId = "entityid" })

if Client and not Predict then

    -- GUIRequestMenu's local SendRequest calls this global right before
    -- sending "VoiceMessage" (both the Ping key and the request menu entry).
    local oldBuildVoiceMessage = BuildVoiceMessage
    function BuildVoiceMessage(voiceId)

        if kMNGAContextPingEnabled and kVoiceId and voiceId == kVoiceId.Ping then

            local player = Client.GetLocalPlayer()
            if player then
                local target = MNGA_ContextPing_PickTarget(player)
                local targetId = target and target:GetId() or Entity.invalidId
                Client.SendNetworkMessage("MNGAContextPingTarget", { targetId = targetId }, true)
            end

        end

        return oldBuildVoiceMessage(voiceId)

    end

end
