-- Muted voice indicator (.claude/docs/muted-voice-indicator.md): shared
-- constants and the server -> listener "a player you muted is talking" message.

MNGA_MUTED_VOICE = MNGA_MUTED_VOICE or {
    -- Server: minimum seconds between notifications per listener/speaker pair.
    NotifyInterval = 0.25,
    -- Client: seconds a "Muted" bar stays up after the last notification.
    -- Must exceed NotifyInterval plus network jitter to avoid flicker.
    ClientHoldTime = 0.6,
    OptionPath = "shimizu/showMutedVoiceIndicator"
}

Shared.RegisterNetworkMessage( "MNGAMutedVoice", {
    speakerClientIndex = "entityid"
} )
