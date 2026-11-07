local kMaxCallMutes = 3
local mutedCallClients = {}
local mutedCallClientCount = 0
local mutedTeams = {
    [kTeam1Index] = false,
    [kTeam2Index] = false
}

local function IsLocalClientSpectator()
    -- Client.GetLocalPlayer() is the followed playing-team player while using
    -- first-person spectate, so use the client's actual assigned team when the
    -- engine exposes it.
    if Client.GetLocalClientTeamNumber then
        return Client.GetLocalClientTeamNumber() == kSpectatorIndex
    end
    local player = Client.GetLocalPlayer()
    return player and player:GetTeamNumber() == kSpectatorIndex
end

function SSB_GetClientCallsMuted(clientIndex)
    return mutedCallClients[clientIndex] == true
end

function SSB_GetHasClientCallsMuted()
    return mutedCallClientCount > 0
end

-- Requests sent per target whose server reply has not arrived yet. Replies
-- are reliable and ordered, so only the reply to the newest request is
-- applied; earlier replies would briefly undo a later optimistic toggle.
local pendingCallMuteRequests = {}

local function SetLocalCallMuted(clientIndex, muted)
    local wasMuted = mutedCallClients[clientIndex] == true
    mutedCallClients[clientIndex] = muted or nil
    if muted and not wasMuted then
        mutedCallClientCount = mutedCallClientCount + 1
    elseif not muted and wasMuted then
        mutedCallClientCount = math.max(0, mutedCallClientCount - 1)
    end
end

function SSB_SetClientCallsMuted(clientIndex, muted)
    muted = muted == true
    if muted and not mutedCallClients[clientIndex] and mutedCallClientCount >= kMaxCallMutes then
        Print("[SSBCallMute] Cannot mute calls from more than %d players", kMaxCallMutes)
        return false
    end
    Client.SendNetworkMessage("SSBSetCallMute", { clientIndex = clientIndex, muted = muted }, true)
    pendingCallMuteRequests[clientIndex] = (pendingCallMuteRequests[clientIndex] or 0) + 1
    -- Apply immediately like vanilla voice mute; the server reply corrects it.
    SetLocalCallMuted(clientIndex, muted)
    return true
end

function SSB_OnCallMuteState(message)
    if message.clearAll then
        mutedCallClients = {}
        mutedCallClientCount = 0
        pendingCallMuteRequests = {}
        return
    end
    local clientIndex = message.clientIndex
    local pending = pendingCallMuteRequests[clientIndex]
    if pending and pending > 1 then
        pendingCallMuteRequests[clientIndex] = pending - 1
        return
    end
    pendingCallMuteRequests[clientIndex] = nil
    if not message.accepted then
        Print("[SSBCallMute] Server rejected call mute for client %d (maximum %d or invalid target)",
            clientIndex, kMaxCallMutes)
    end
    -- Rejected replies still carry the server's actual state, so this rolls
    -- back an optimistic toggle as well as confirming an accepted one.
    SetLocalCallMuted(clientIndex, message.muted == true)
end

function SSB_GetTeamVoiceMuted(teamNumber)
    return mutedTeams[teamNumber] == true
end

function SSB_SetTeamVoiceMuted(teamNumber, muted)
    if not IsLocalClientSpectator() then
        Print("[SSBTeamVoiceMute] Ignored request outside spectator: team=%s muted=%s",
            ToString(teamNumber), ToString(muted))
        return false
    end
    if teamNumber ~= kTeam1Index and teamNumber ~= kTeam2Index then
        Print("[SSBTeamVoiceMute] Ignored invalid team request: %s", ToString(teamNumber))
        return false
    end
    Client.SendNetworkMessage("SSBSetTeamVoiceMute", {
        teamNumber = teamNumber,
        muted = muted == true
    }, true)
    Print("[SSBTeamVoiceMute] Requested team %d %s", teamNumber, muted and "muted" or "unmuted")
    return true
end

function SSB_OnTeamVoiceMuteState(message)
    if message.reset then
        mutedTeams[kTeam1Index] = false
        mutedTeams[kTeam2Index] = false
        Print("[SSBTeamVoiceMute] Reset both client team mute states")
        return
    end
    if message.teamNumber == kTeam1Index or message.teamNumber == kTeam2Index then
        mutedTeams[message.teamNumber] = message.muted == true
        Print("[SSBTeamVoiceMute] Team %d is %s (accepted=%s)", message.teamNumber,
            message.muted and "muted" or "unmuted", ToString(message.accepted))
    end
end
