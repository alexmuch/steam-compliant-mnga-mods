Client.HookNetworkMessage("SSBCallMuteState", function(message)
    if SSB_OnCallMuteState then
        SSB_OnCallMuteState(message)
    end
end)

Client.HookNetworkMessage("SSBPlayerCall", function(message)
    local speaker = Shared.GetEntity(message.entityId)
    if speaker then
        Shared.PlaySound(speaker, message.soundName, 1)
    else
        Shared.PlayWorldSound(nil, message.soundName, nil, message.origin, 1)
        Print("[SSBCallMute] Speaker entity %s unavailable; playing supplemental call at sent origin",
            ToString(message.entityId))
    end
end)

Client.HookNetworkMessage("SSBTeamVoiceMuteState", function(message)
    if SSB_OnTeamVoiceMuteState then
        SSB_OnTeamVoiceMuteState(message)
    end
end)

local lifeformSelections = {}
local pendingLifeformSelections = {}

local function NormalizeLifeform(value)
    value = type(value) == "string" and string.lower(value) or nil
    if value == "gorge" then return "Gorge" end
    if value == "lerk" then return "Lerk" end
    if value == "fade" then return "Fade" end
    if value == "onos" then return "Onos" end
    return nil
end

function SSB_GetLifeformSelection(steamId)
    return steamId and lifeformSelections[tostring(steamId)] or nil
end

function SSB_SetLocalLifeformSelection(lifeform)
    local normalized = NormalizeLifeform(lifeform)
    local steamId = Client.GetSteamId()
    if not normalized or not steamId or steamId == 0 then return false end
    local steamIdKey = tostring(steamId)
    local existingPending = pendingLifeformSelections[steamIdKey]
    pendingLifeformSelections[steamIdKey] = {
        desired = normalized,
        previous = existingPending and existingPending.previous or lifeformSelections[steamIdKey]
    }
    lifeformSelections[steamIdKey] = normalized
    Client.SendNetworkMessage("SSBSetLifeformSelection", { lifeform = normalized }, true)
    Print("[SSBLifeform] Optimistically selected %s for local steamId=%s",
        normalized, ToString(steamId))
    return true
end

function SSB_RequestLifeformSelectionSync(reason)
    Client.SendNetworkMessage("SSBRequestLifeformSelections", {}, true)
    Print("[SSBLifeform] Requested manual-selection sync reason=%s", reason or "unspecified")
end

Client.HookNetworkMessage("SSBLifeformSelectionState", function(message)
    local steamIdKey = tostring(message.steamId)
    local pending = pendingLifeformSelections[steamIdKey]
    if message.accepted == false then
        if pending then
            lifeformSelections[steamIdKey] = pending.previous
            pendingLifeformSelections[steamIdKey] = nil
        end
        Print("[SSBLifeform] Server rejected optimistic selection steamId=%s; restored previous=%s",
            ToString(message.steamId), ToString(pending and pending.previous))
        return
    end
    local normalized = NormalizeLifeform(message.lifeform)
    if not normalized or not message.steamId or message.steamId == "" then
        Print("[SSBLifeform] Rejected malformed replicated state steamId=%s lifeform=%s",
            ToString(message.steamId), ToString(message.lifeform))
        return
    end
    if pending and normalized ~= pending.desired then
        Print("[SSBLifeform] Ignored stale replicated selection steamId=%s lifeform=%s pending=%s",
            ToString(message.steamId), normalized, pending.desired)
        return
    end
    if pending then
        pendingLifeformSelections[steamIdKey] = nil
    end
    lifeformSelections[steamIdKey] = normalized
end)
