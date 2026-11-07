-- Muted voice indicator (.claude/docs/muted-voice-indicator.md): records when
-- the server reports that a voice-muted player is talking. The GUIVoiceChat
-- post-hook (GUIVoiceChatMutedIndicator.lua) draws the "Muted" bars.

if not Client or MNGAMutedVoiceClientInstalled then return end
MNGAMutedVoiceClientInstalled = true

-- [speakerClientIndex] = Shared.GetTime() of the last notification
MNGAMutedVoiceLastHeard = MNGAMutedVoiceLastHeard or {}

local function OnMutedVoice(message)
    local speakerIndex = message.speakerClientIndex
    -- The option is read here rather than per frame: at most a few messages
    -- per second while a muted player talks, none otherwise.
    if not Client.GetOptionBoolean(MNGA_MUTED_VOICE.OptionPath, true) then return end
    -- The server only sends for mutes it holds; this guards a mute lifted
    -- while a notification was in flight.
    if not ChatUI_GetClientMuted(speakerIndex) then return end

    MNGAMutedVoiceLastHeard[speakerIndex] = Shared.GetTime()
end

Client.HookNetworkMessage("MNGAMutedVoice", OnMutedVoice)
