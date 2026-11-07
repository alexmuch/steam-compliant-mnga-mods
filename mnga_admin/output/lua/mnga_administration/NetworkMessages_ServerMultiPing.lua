local function OnCommandCommPing(client, message)

    if Server then

        local player = client:GetControllingPlayer()
        if player then
            local team = player:GetTeam()
            if team and team.SetCommanderPing then
                team:SetCommanderPing(message.position, "Commander", player)
            end
        end

    end

end


Server.HookNetworkMessage("CommanderPing", OnCommandCommPing)

-- Dead players right-click the big map to ping (message sent by
-- GUIMinimapFrameMultiPing.lua). Shares the 30s player ping cooldown with the
-- "Ping" voiceover (MNGA_ globals from VoiceOverMultiPing.lua).
local function OnMNGAMapPing(client, message)

    if not client then
        return
    end

    local player = client:GetControllingPlayer()
    local spectated = client:GetSpectatingPlayer()

    if spectated and player == spectated then

        -- First-person spectate switcheroo: GetControllingPlayer() returned the
        -- spectated alive teammate. Find the spectator entity this client owns.
        player = nil
        for _, spec in ientitylist(Shared.GetEntitiesWithClassname("TeamSpectator")) do
            if Server.GetOwner(spec) == client then
                player = spec
                break
            end
        end

    end

    if not player or not player:isa("TeamSpectator") then
        Print("OnMNGAMapPing: rejected, sender is not a dead team player (%s)", ToString(player))
        return
    end

    local team = player:GetTeam()
    if not team or not team.SetPlayerPing then
        Print("OnMNGAMapPing: rejected, no valid team for %s", ToString(player:GetName()))
        return
    end

    local ownerId = MNGA_GetPingOwnerId(player)

    local cooldownLeft = MNGA_GetPlayerPingCooldownRemaining(ownerId)
    if cooldownLeft > 0 then
        -- Print("OnMNGAMapPing: cooldown for owner %s (%.1fs left)", ToString(ownerId), cooldownLeft)
        return
    end

    -- The client sends the minimap click as world x/z with y = 0; drop it onto
    -- the floor the same way the commander minimap ping does
    -- (CommanderUI_TriggerPingOnMinimap in Commander_Client.lua).
    local startPos = Vector(message.position.x, player:GetOrigin().y + 1, message.position.z)
    local trace = Shared.TraceRay(startPos, startPos + Vector(0, -250, 0), CollisionRep.Select, PhysicsMask.CommanderSelect, EntityFilterAll())

    local pingPosition
    if trace.fraction ~= 1 then
        pingPosition = trace.endPoint
    else
        -- no floor found below: keep the click position at the pinger's height
        pingPosition = Vector(message.position.x, player:GetOrigin().y, message.position.z)
    end

    -- Print("OnMNGAMapPing: %s pings %s (floor trace fraction %.2f)", ToString(player:GetName()), ToString(pingPosition), trace.fraction)

    if team:SetPlayerPing(ownerId, pingPosition, player:GetName(), player) then
        MNGA_StartPlayerPingCooldown(ownerId)
    end

end

Server.HookNetworkMessage("MNGAMapPing", OnMNGAMapPing)
