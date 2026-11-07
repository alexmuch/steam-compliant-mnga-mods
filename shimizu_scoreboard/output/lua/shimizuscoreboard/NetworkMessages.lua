Shared.RegisterNetworkMessage("SSBSetCallMute", {
    clientIndex = "entityid",
    muted = "boolean"
})

Shared.RegisterNetworkMessage("SSBCallMuteState", {
    clientIndex = "entityid",
    muted = "boolean",
    accepted = "boolean",
    clearAll = "boolean"
})

Shared.RegisterNetworkMessage("SSBPlayerCall", {
    entityId = "entityid",
    origin = "vector",
    soundName = "string (128)"
})

Shared.RegisterNetworkMessage("SSBSetTeamVoiceMute", {
    teamNumber = "integer (1 to 2)",
    muted = "boolean"
})

Shared.RegisterNetworkMessage("SSBTeamVoiceMuteState", {
    teamNumber = "integer (1 to 2)",
    muted = "boolean",
    accepted = "boolean",
    reset = "boolean"
})

Shared.RegisterNetworkMessage("SSBSetLifeformSelection", {
    lifeform = "string (8)"
})

Shared.RegisterNetworkMessage("SSBLifeformSelectionState", {
    steamId = "string (16)",
    lifeform = "string (8)",
    accepted = "boolean"
})

Shared.RegisterNetworkMessage("SSBRequestLifeformSelections", {})

-- Low voice volume: client reports raw option values, server decides and broadcasts.
Shared.RegisterNetworkMessage("SSBVoiceVolumeReport", {
    voice = "integer (0 to 100)",
    sound = "integer (0 to 100)"
})

Shared.RegisterNetworkMessage("SSBLowVoiceState", {
    steamId = "string (16)",
    low = "boolean"
})

Shared.RegisterNetworkMessage("SSBRequestLowVoiceStates", {})

-- Muted-by: client reports its local-only text mutes; server sends each
-- playing-team player how many current teammates voice/text-muted them.
Shared.RegisterNetworkMessage("SSBTextMuteReport", {
    clientIndex = "entityid",
    muted = "boolean"
})

Shared.RegisterNetworkMessage("SSBMutedByCount", {
    voice = "integer (0 to 31)",
    text = "integer (0 to 31)"
})

Print("[SSB] Scoreboard mute and lifeform-selector network messages registered")
