-- Muted voice indicator (.claude/docs/muted-voice-indicator.md).
--
-- Voice mutes are enforced on the server: the engine asks CanPlayerHearPlayer
-- for every voice packet and a muted speaker's audio is never relayed, so the
-- listener's client cannot tell that the muted player is talking. Both vanilla
-- NS2Gamerules:GetCanPlayerHearPlayer and Shine basecommands consult
-- Listener:GetClientMuted(speakerIndex) inside that check, so wrapping it here
-- sees every blocked packet regardless of which implementation is active.
--
-- When a mute is what blocks a packet, the hear check is re-run once with mutes
-- bypassed; if the listener would otherwise have heard the speaker, the listener
-- gets a tiny "MNGAMutedVoice" message. Per listener/speaker pair this happens
-- at most once per kNotifyInterval, so the steady-state extra cost is one table
-- lookup per blocked packet.
--
-- The probe must use the channel of the blocked packet: spvc proximity voice
-- (VoiceChannel.Entity) is distance-gated, team voice is not. GetClientMuted
-- does not receive the channel, so an outermost GetCanPlayerHearPlayer wrapper
-- records it. Shine replaces that method in its first-Think "ReplaceMethods"
-- hook (default priority), so ours is installed from a MIN_PRIORITY Think hook
-- to guarantee it wraps outside Shine's.

-- Loaded as a Player_Server.lua post-hook: Player and Player:GetClientMuted
-- exist here. (NS2Gamerules.lua loads before Player.lua, so it cannot host this.)
if not Server or MNGAMutedVoiceIndicatorInstalled then return end
if not Player or not Player.GetClientMuted or not MNGA_MUTED_VOICE then
    Print("[MutedVoice] prerequisites missing (Player=%s, GetClientMuted=%s, MNGA_MUTED_VOICE=%s); indicator disabled",
        tostring(Player ~= nil), tostring(Player ~= nil and Player.GetClientMuted ~= nil), tostring(MNGA_MUTED_VOICE ~= nil))
    return
end
MNGAMutedVoiceIndicatorInstalled = true

-- Client keeps a bar visible for MNGA_MUTED_VOICE.ClientHoldTime after each
-- notification, which must stay comfortably above this interval.
local kNotifyInterval = MNGA_MUTED_VOICE.NotifyInterval

-- [listenerClientIndex][speakerClientIndex] = next allowed notify time
local nextNotifyTime = {}
local probing = false
-- Channel of the hear check currently on the stack; nil means global (both
-- vanilla and spvc treat nil as VoiceChannel.Global).
local currentChannel = nil

local function GetSpeakerPlayer(speakerClientIndex)
    local client = Server.GetClientById(speakerClientIndex)
    return client and client:GetControllingPlayer()
end

local function WouldHearWithoutMute(listener, speaker)
    local gamerules = GetGamerules()
    if not gamerules then return false end

    probing = true
    local ok, canHear = pcall(gamerules.GetCanPlayerHearPlayer, gamerules, listener, speaker, currentChannel)
    probing = false

    if not ok then
        Print("[MutedVoice] hear probe failed: %s", tostring(canHear))
        return false
    end
    return canHear == true
end

local function OnMutedPacketBlocked(listener, speakerClientIndex)
    local listenerClient = Server.GetOwner(listener)
    if not listenerClient or listenerClient:GetIsVirtual() then return end

    local listenerIndex = listenerClient:GetId()
    local now = Shared.GetTime()
    local pairTimes = nextNotifyTime[listenerIndex]
    if not pairTimes then
        pairTimes = {}
        nextNotifyTime[listenerIndex] = pairTimes
    end
    local nextTime = pairTimes[speakerClientIndex]
    if nextTime and now < nextTime then return end
    pairTimes[speakerClientIndex] = now + kNotifyInterval

    local speaker = GetSpeakerPlayer(speakerClientIndex)
    if not speaker or speaker == listener then return end
    if not WouldHearWithoutMute(listener, speaker) then return end

    Server.SendNetworkMessage(listenerClient, "MNGAMutedVoice", { speakerClientIndex = speakerClientIndex }, false)
end

local oldGetClientMuted = Player.GetClientMuted
function Player:GetClientMuted(checkClientIndex)
    if probing then return false end

    local muted = oldGetClientMuted(self, checkClientIndex)
    if muted and checkClientIndex then
        OnMutedPacketBlocked(self, checkClientIndex)
    end
    return muted
end

Event.Hook("ClientDisconnect", function(client)
    if client then
        nextNotifyTime[client:GetId()] = nil
    end
end)

local function InstallChannelRecorder()
    local inner = NS2Gamerules and NS2Gamerules.GetCanPlayerHearPlayer
    if not inner then
        Print("[MutedVoice] NS2Gamerules:GetCanPlayerHearPlayer missing; probing team voice only")
        return
    end

    -- Explicit parameters: Shine's code-generated hooks size their argument
    -- lists from the wrapped function, so avoid varargs here.
    local function Recorder(self, listener, speaker, channelType)
        local previous = currentChannel
        currentChannel = channelType
        local canHear = inner(self, listener, speaker, channelType)
        currentChannel = previous
        return canHear
    end

    if Shine and Shine.ReplaceClassMethod then
        -- Also updates gamerules subclasses still sharing the method.
        Shine.ReplaceClassMethod("NS2Gamerules", "GetCanPlayerHearPlayer", Recorder)
    else
        NS2Gamerules.GetCanPlayerHearPlayer = Recorder
    end
    Print("[MutedVoice] channel recorder installed (shine=%s)", tostring(Shine ~= nil))
end

-- Shine may not be loaded yet at Player_Server.lua time, so decide on the
-- first server update.
local function OnFirstUpdateServer()
    Event.RemoveHook("UpdateServer", OnFirstUpdateServer)
    if Shine and Shine.Hook then
        Shine.Hook.Add("Think", "MNGAMutedVoiceChannelRecorder", function()
            Shine.Hook.Remove("Think", "MNGAMutedVoiceChannelRecorder")
            InstallChannelRecorder()
        end, Shine.Hook.MIN_PRIORITY)
    else
        InstallChannelRecorder()
    end
end
Event.Hook("UpdateServer", OnFirstUpdateServer)

Print("[MutedVoice] server hook installed")
