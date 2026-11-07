
-- MNGA multi-ping: per-slot ping info for the GUI scripts.

-- Call-muted players' pings are hidden. The slot's clientIndex is the owner's
-- client:GetId(), the same key Shimizu Scoreboard uses for its Mute Calls state.
function MNGA_GetPingOwnerMuted(teamInfo, slot)

    local clientIndex = teamInfo.GetPingOwnerClientIndex and teamInfo:GetPingOwnerClientIndex(slot) or -1
    if clientIndex > 0 and SSB_GetClientCallsMuted ~= nil then
        return SSB_GetClientCallsMuted(clientIndex)
    end
    return false

end

function PlayerUI_GetPingInfoForSlot(player, teamInfo, slot, onMiniMap)

    local position = Vector(0,0,0)

    local pingPos = teamInfo:GetPingPosition(slot)

    local location = GetLocationForPoint(pingPos)
    local locationName = location and location:GetName() or ""

    local playerName = teamInfo:GetPingName(slot)

    if not onMiniMap then
        position = GetClampedScreenPosition(pingPos, 40)
    else
        position = pingPos
    end
    local pingTime = teamInfo:GetPingTime(slot)

    local timeSincePing = Shared.GetTime() - pingTime
    local distance = (player:GetEyePos() - pingPos):GetLength()

    return timeSincePing, position, distance, locationName, pingTime, playerName

end

-- compat: no slot means "the most recent ping"
function PlayerUI_GetPingInfo(player, teamInfo, onMiniMap)

    return PlayerUI_GetPingInfoForSlot(player, teamInfo, nil, onMiniMap)

end

function PlayerUI_GetCommanderPingInfo(onMiniMap)

    local player = Client.GetLocalPlayer()

    if player then

        for _, teamInfo in ipairs(GetEntitiesForTeam("TeamInfo", player:GetTeamNumber())) do

            return PlayerUI_GetPingInfo(player, teamInfo, onMiniMap)

        end

    end

    return kCommanderPingDuration, Vector(0,0,0), 0, nil, 0, ""

end

-- Don't play the ping sound for call-muted players' pings.
-- The sound assets are file-locals of Player_Client.lua, so re-precache them here.
local kDefaultPingSound = PrecacheAsset("sound/NS2.fev/common/ping")
local kMarinePingSound = PrecacheAsset("sound/NS2.fev/marine/commander/ping")
local kAlienPingSound = PrecacheAsset("sound/NS2.fev/alien/commander/ping")

-- Direct redefinition is safe here: this post-hook runs right after
-- Player_Client.lua, which Player.lua loads BEFORE any subclass (Marine etc.)
-- is declared, so all subclasses copy this version.
function Player:UpdateCommanderPingSound()

    local teamInfoEnts = GetEntitiesForTeam("TeamInfo", self:GetTeamNumber())
    local teamInfo = #teamInfoEnts > 0 and teamInfoEnts[1]

    if teamInfo then

        local slot = teamInfo:GetLatestPingSlot()
        local pingTime = teamInfo:GetPingTime(slot)
        if self.timeLastCommanderPing ~= nil and pingTime > self.timeLastCommanderPing then

            if not MNGA_GetPingOwnerMuted(teamInfo, slot) then

                local pingSound = kDefaultPingSound
                if self:GetTeamType() == kMarineTeamType then
                    pingSound = kMarinePingSound
                elseif self:GetTeamType() == kAlienTeamType then
                    pingSound = kAlienPingSound
                end

                Shared.PlaySound(nil, pingSound)

            end

        end

        self.timeLastCommanderPing = pingTime

    end

end
