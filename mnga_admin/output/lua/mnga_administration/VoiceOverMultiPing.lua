
-- MNGA multi-ping: the "Ping" voiceover gives each player their own ping.

local kPlayerPingCooldown = 30 -- seconds between pings for a regular player

-- Cooldowns keyed by owner id (steam id), NOT stored on the player entity:
-- NS2 replaces the player entity on every class change (comm chair, evolving,
-- exo, respawn), which would wipe an entity field and reset the cooldown.
local lastPingTimeByOwner = {}

-- Drop expired entries so the table doesn't accumulate players who left.
local function PrunePingCooldowns(now)

    for ownerId, pingTime in pairs(lastPingTimeByOwner) do
        if pingTime + kPlayerPingCooldown < now then
            lastPingTimeByOwner[ownerId] = nil
        end
    end

end

-- Globals (MNGA_ prefix): also used by the dead-player map ping handler in
-- NetworkMessages_ServerMultiPing.lua, so both ping paths share one cooldown.

function MNGA_GetPingOwnerId(player)

    local client = Server.GetOwner(player)
    local ownerId = client and client:GetUserId() or 0
    if ownerId == 0 then
        -- bots and clients without a steam id: derive a non-colliding id
        ownerId = -100 - player:GetId()
    end
    return ownerId

end

-- Returns seconds left on the owner's ping cooldown (0 = may ping).
function MNGA_GetPlayerPingCooldownRemaining(ownerId)

    local now = Shared.GetTime()
    PrunePingCooldowns(now)

    local lastTime = lastPingTimeByOwner[ownerId]
    if lastTime and lastTime + kPlayerPingCooldown >= now then
        return lastTime + kPlayerPingCooldown - now
    end

    return 0

end

function MNGA_StartPlayerPingCooldown(ownerId)
    lastPingTimeByOwner[ownerId] = Shared.GetTime()
end

-- Contextual ping refund: the marked target died (PlayingTeamMultiPing.lua).
function MNGA_ResetPlayerPingCooldown(ownerId)
    lastPingTimeByOwner[ownerId] = nil
end

local function NewPingInViewDirection(player)

    if not player then
        return
    end

    local ownerId = MNGA_GetPingOwnerId(player)

    local cooldownLeft = MNGA_GetPlayerPingCooldownRemaining(ownerId)
    if cooldownLeft > 0 then
        -- Print("NewPingInViewDirection: cooldown for owner %s (%.1fs left)", ToString(ownerId), cooldownLeft)
        return
    end

    local team = player:GetTeam()

    -- Contextual ping (ContextPingServer.lua): a highlighted target or a
    -- dropped-item ping replaces the location ping. Shares this cooldown.
    if MNGA_ContextPing_TryPlayerPing then
        local handled, accepted = MNGA_ContextPing_TryPlayerPing(player, ownerId, team)
        if handled then
            if accepted then
                MNGA_StartPlayerPingCooldown(ownerId)
            end
            return
        end
    end

    local startPoint = player:GetEyePos()
    local endPoint = startPoint + player:GetViewCoords().zAxis * 40
    local trace = Shared.TraceRay(startPoint, endPoint, CollisionRep.Default, PhysicsMask.Bullets, EntityFilterOne(player))

    if team and team.SetPlayerPing then

        if team:SetPlayerPing(ownerId, trace.endPoint, player:GetName(), player) then
            -- only start the cooldown if the ping was accepted
            MNGA_StartPlayerPingCooldown(ownerId)
        end

    end

end

-- GetVoiceSoundData closes over kSoundData, so we can retrieve it from there
local kSoundData = debug.getupvaluex(GetVoiceSoundData, "kSoundData")
if kSoundData and kVoiceId and kVoiceId.Ping then
    kSoundData[kVoiceId.Ping].Function = NewPingInViewDirection
end
