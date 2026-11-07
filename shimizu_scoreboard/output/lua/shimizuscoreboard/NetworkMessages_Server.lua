local kMaxCallMutes = 3
local VanillaCreateVoiceMessage = CreateVoiceMessage
local callMutesByListener = {}
local teamVoiceMutesByListener = {}
local lifeformSelectionsBySteamId = {}

local function NormalizeLifeform(value)
    value = type(value) == "string" and string.lower(value) or nil
    if value == "gorge" then return "Gorge" end
    if value == "lerk" then return "Lerk" end
    if value == "fade" then return "Fade" end
    if value == "onos" then return "Onos" end
    return nil
end

local function IsLifeformViewerEligible(client)
    local player = client and client:GetControllingPlayer()
    local teamNumber = player and player:GetTeamNumber()
    return teamNumber == kTeam2Index or teamNumber == kSpectatorIndex
end

local function SendLifeformSelection(client, steamId, lifeform)
    Server.SendNetworkMessage(client, "SSBLifeformSelectionState", {
        steamId = tostring(steamId), lifeform = lifeform, accepted = true
    }, true)
end

local function BroadcastLifeformSelection(steamId, lifeform)
    local players = EntityListToTable(Shared.GetEntitiesWithClassname("Player"))
    for i = 1, #players do
        local client = Server.GetOwner(players[i])
        if IsLifeformViewerEligible(client) then
            SendLifeformSelection(client, steamId, lifeform)
        end
    end
end

local function OnSetLifeformSelection(client, message)
    local player = client and client:GetControllingPlayer()
    local lifeform = NormalizeLifeform(message.lifeform)
    if not player or player:GetTeamNumber() ~= kTeam2Index or not lifeform or client:GetIsVirtual() then
        Print("[SSBLifeform] Rejected selection steamId=%s team=%s lifeform=%s virtual=%s",
            ToString(client and client:GetUserId()), ToString(player and player:GetTeamNumber()),
            ToString(message.lifeform), ToString(client and client:GetIsVirtual()))
        if client and client:GetUserId() then
            local steamId = tostring(client:GetUserId())
            local previous = lifeformSelectionsBySteamId[steamId]
            Server.SendNetworkMessage(client, "SSBLifeformSelectionState", {
                steamId = steamId, lifeform = previous or "Onos", accepted = false
            }, true)
        end
        return
    end
    local steamId = client:GetUserId()
    local steamIdKey = tostring(steamId)
    if lifeformSelectionsBySteamId[steamIdKey] == lifeform then
        SendLifeformSelection(client, steamId, lifeform)
        return
    end
    lifeformSelectionsBySteamId[steamIdKey] = lifeform
    Print("[SSBLifeform] Accepted manual selection steamId=%s lifeform=%s",
        ToString(steamId), lifeform)
    BroadcastLifeformSelection(steamId, lifeform)
end

local function OnRequestLifeformSelections(client)
    if not IsLifeformViewerEligible(client) then
        Print("[SSBLifeform] Rejected sync request steamId=%s reason=ineligible_viewer",
            ToString(client and client:GetUserId()))
        return
    end
    local sent = 0
    for steamId, lifeform in pairs(lifeformSelectionsBySteamId) do
        SendLifeformSelection(client, steamId, lifeform)
        sent = sent + 1
    end
    Print("[SSBLifeform] Synchronized %d manual selection(s) to steamId=%s",
        sent, ToString(client:GetUserId()))
end

Server.HookNetworkMessage("SSBSetLifeformSelection", OnSetLifeformSelection)
Server.HookNetworkMessage("SSBRequestLifeformSelections", OnRequestLifeformSelections)

local function GetAllPlayers()
    return EntityListToTable(Shared.GetEntitiesWithClassname("Player"))
end

local function GetListenerPlayer(client)
    return client and client:GetControllingPlayer()
end

local function GetPlayerIndex(player)
    return player and player.GetClientIndex and player:GetClientIndex() or nil
end

local function CountCallMutes(mutedClients)
    local count = 0
    for _, muted in pairs(mutedClients or {}) do
        if muted then count = count + 1 end
    end
    return count
end

local function SendCallMuteState(client, clientIndex, muted, accepted, clearAll)
    Server.SendNetworkMessage(client, "SSBCallMuteState", {
        clientIndex = clientIndex,
        muted = muted == true,
        accepted = accepted == true,
        clearAll = clearAll == true
    }, true)
end

local function OnSetCallMute(client, message)
    local listener = GetListenerPlayer(client)
    if not listener then return end
    local targetClient = Server.GetClientById(message.clientIndex)
    local targetPlayer = targetClient and targetClient:GetControllingPlayer()
    if listener:GetClientIndex() == message.clientIndex or not targetPlayer then
        SendCallMuteState(client, message.clientIndex, false, false, false)
        Print("[SSBCallMute] Rejected invalid/self target: listener=%d speaker=%d",
            listener:GetClientIndex(), message.clientIndex)
        return
    end

    local listenerIndex = listener:GetClientIndex()
    local mutedClients = callMutesByListener[listenerIndex] or {}
    callMutesByListener[listenerIndex] = mutedClients
    local alreadyMuted = mutedClients[message.clientIndex] == true
    local accepted = not message.muted or alreadyMuted or CountCallMutes(mutedClients) < kMaxCallMutes
    if accepted then mutedClients[message.clientIndex] = message.muted or nil end
    if next(mutedClients) == nil then callMutesByListener[listenerIndex] = nil end
    -- Reply with the authoritative state. Avoid `accepted and muted or
    -- alreadyMuted`: an accepted unmute would fall through to alreadyMuted.
    local resultMuted
    if accepted then
        resultMuted = message.muted == true
    else
        resultMuted = alreadyMuted
    end
    SendCallMuteState(client, message.clientIndex, resultMuted, accepted, false)
end
Server.HookNetworkMessage("SSBSetCallMute", OnSetCallMute)

local function IsCallsMuted(listener, speakerIndex)
    local mutedClients = callMutesByListener[listener:GetClientIndex()]
    return mutedClients and mutedClients[speakerIndex] == true
end

local function SendSupplementalCallToVoiceMutedListeners(player, soundName)
    local players = GetAllPlayers()
    local speakerIndex = player:GetClientIndex()
    local sent = 0
    for i = 1, #players do
        local listener = players[i]
        local listenerClient = Server.GetOwner(listener)
        if listenerClient and listener:GetClientMuted(speakerIndex) and not IsCallsMuted(listener, speakerIndex) then
            Server.SendNetworkMessage(listenerClient, "SSBPlayerCall", {
                entityId = player:GetId(), origin = player:GetOrigin(), soundName = soundName
            }, true)
            sent = sent + 1
        end
    end
    if sent > 0 then
        Print("[SSBCallMute] Sent supplemental call from client %d to %d voice-muted listener(s)",
            speakerIndex, sent)
    end
end

function CreateVoiceMessage(player, voiceId)
    local soundData = GetVoiceSoundData(voiceId)
    if not soundData or not soundData.Sound then
        return VanillaCreateVoiceMessage(player, voiceId)
    end
    local client = player:GetClient()
    if client and player.OnTaunt and (voiceId == kVoiceId.MarineTaunt or voiceId == kVoiceId.AlienTaunt) then
        player:OnTaunt()
    end
    if voiceId == kVoiceId.MarineTaunt and GetHasDLC(kShadowProductId, client) then
        voiceId = kVoiceId.MarineTauntExclusive
        soundData = GetVoiceSoundData(voiceId)
    end
    local soundName = soundData.Sound
    if HasMixin(player, "MarineVariant") and player:GetMarineType() == kMarineVariantsBaseType.female and soundData.SoundFemale then
        soundName = soundData.SoundFemale
    end
    if soundData.Function then soundName = soundData.Function(player) or soundName end
    if soundName then
        StartSoundEffectOnEntity(soundName, player)
        SendSupplementalCallToVoiceMutedListeners(player, soundName)
    end
    local team = player:GetTeam()
    if team and not GetIsPointInGorgeTunnel(player:GetOrigin()) and soundData.AlertTechId and soundData.AlertTechId ~= kTechId.None then
        local teamPlayers = GetEntitiesForTeam("Player", player:GetTeamNumber())
        local oldMutes = {}
        for i = 1, #teamPlayers do
            local listener = teamPlayers[i]
            listener.mutedClients = listener.mutedClients or {}
            oldMutes[listener] = listener.mutedClients[player:GetClientIndex()]
            listener.mutedClients[player:GetClientIndex()] = IsCallsMuted(listener, player:GetClientIndex()) or nil
        end
        team:TriggerAlert(soundData.AlertTechId, player)
        for i = 1, #teamPlayers do
            local listener = teamPlayers[i]
            listener.mutedClients[player:GetClientIndex()] = oldMutes[listener]
        end
    end
end

function SSB_ClearAllCallMutes()
    callMutesByListener = {}
    local players = GetAllPlayers()
    for i = 1, #players do
        local client = Server.GetOwner(players[i])
        if client then SendCallMuteState(client, 0, false, true, true) end
    end
    Print("[SSBCallMute] Cleared every listener's call mutes")
end

local function SendTeamMuteState(client, teamNumber, muted, accepted, reset)
    if not client then return end
    Server.SendNetworkMessage(client, "SSBTeamVoiceMuteState", {
        teamNumber = teamNumber, muted = muted == true,
        accepted = accepted == true, reset = reset == true
    }, true)
end

function SSB_GetTeamVoiceMutedForListener(listenerPlayer, speakerTeamNumber)
    if not listenerPlayer or listenerPlayer:GetTeamNumber() ~= kSpectatorIndex then return false end
    local listenerIndex = GetPlayerIndex(listenerPlayer)
    local states = listenerIndex and teamVoiceMutesByListener[listenerIndex]
    return states and states[speakerTeamNumber] == true or false
end

function SSB_ClearTeamVoiceMutesForClient(client, reason)
    if not client then return end
    local player = client:GetControllingPlayer()
    local listenerIndex = GetPlayerIndex(player) or client:GetId()
    if not listenerIndex then return end
    local hadState = teamVoiceMutesByListener[listenerIndex] ~= nil
    teamVoiceMutesByListener[listenerIndex] = nil
    SendTeamMuteState(client, kTeam1Index, false, true, true)
    Print("[SSBTeamVoiceMute] Reset listener %s (%s, hadState=%s)",
        ToString(listenerIndex), reason or "unspecified", ToString(hadState))
end

local function OnSetTeamVoiceMute(client, message)
    local player = client and client:GetControllingPlayer()
    local listenerIndex = GetPlayerIndex(player)
    local validTeam = message.teamNumber == kTeam1Index or message.teamNumber == kTeam2Index
    if not player or not listenerIndex or player:GetTeamNumber() ~= kSpectatorIndex or not validTeam then
        SendTeamMuteState(client, validTeam and message.teamNumber or kTeam1Index, false, false, false)
        Print("[SSBTeamVoiceMute] Rejected request: listener=%s playerTeam=%s targetTeam=%s muted=%s",
            ToString(listenerIndex), ToString(player and player:GetTeamNumber()),
            ToString(message.teamNumber), ToString(message.muted))
        return
    end
    local states = teamVoiceMutesByListener[listenerIndex] or {}
    teamVoiceMutesByListener[listenerIndex] = states
    states[message.teamNumber] = message.muted == true or nil
    if not states[kTeam1Index] and not states[kTeam2Index] then
        teamVoiceMutesByListener[listenerIndex] = nil
    end
    SendTeamMuteState(client, message.teamNumber, message.muted, true, false)
    Print("[SSBTeamVoiceMute] Listener %d set team %d %s", listenerIndex,
        message.teamNumber, message.muted and "muted" or "unmuted")
end
Server.HookNetworkMessage("SSBSetTeamVoiceMute", OnSetTeamVoiceMute)

Event.Hook("ClientDisconnect", function(client)
    local player = client and client:GetControllingPlayer()
    local disconnectedIndex = GetPlayerIndex(player) or (client and client:GetId())
    if not disconnectedIndex then return end
    callMutesByListener[disconnectedIndex] = nil
    teamVoiceMutesByListener[disconnectedIndex] = nil
    for listenerIndex, mutedClients in pairs(callMutesByListener) do
        if mutedClients[disconnectedIndex] then
            mutedClients[disconnectedIndex] = nil
            local listenerClient = Server.GetClientById(listenerIndex)
            if listenerClient then SendCallMuteState(listenerClient, disconnectedIndex, false, true, false) end
            Print("[SSBCallMute] Removed disconnected speaker %d from listener %d",
                disconnectedIndex, listenerIndex)
        end
    end
end)

Print("[SSB] Server owns call-mute and spectator team-voice state")

----------------------------------------------------------------------------
-- Low voice volume icon + "[muted by v/t]" team header (server side)
----------------------------------------------------------------------------
local kDefaultLowVoiceRatio = 1 / 3
local kVolumeReportMinInterval = 0.5
local kMutedByScanInterval = 1
local kMaxMutedByCount = 31

local voiceVolumeBySteamId = {} -- steamIdKey -> { voice, sound, low }
local lastVolumeReportTime = {} -- steamIdKey -> time
local textMutesByListener = {} -- listenerClientIndex -> { targetClientIndex -> true }
local mutedBySent = {} -- targetClientIndex -> { voice, text }
local nextMutedByScan = 0

local function GetLowVoiceRatio()
    local plugin = Shine and Shine.Plugins and Shine.Plugins.shimizuscoreboard
    local ratio = plugin and plugin.Enabled and plugin.Config and tonumber(plugin.Config.LowVoiceVolumeRatio)
    return ratio or kDefaultLowVoiceRatio
end

local function BroadcastLowVoice(steamIdKey, low)
    Server.SendNetworkMessage("SSBLowVoiceState", { steamId = steamIdKey, low = low == true }, true)
end

local function EvaluateLowVoice(steamIdKey, entry, ratio)
    local low = entry.voice <= ratio * entry.sound
    if low ~= entry.low then
        entry.low = low
        BroadcastLowVoice(steamIdKey, low)
    end
end

function SSB_RecomputeLowVoice()
    local ratio = GetLowVoiceRatio()
    local count = 0
    for steamIdKey, entry in pairs(voiceVolumeBySteamId) do
        EvaluateLowVoice(steamIdKey, entry, ratio)
        count = count + 1
    end
    Print("[SSBLowVoice] Recomputed %d stored report(s) with ratio=%.2f", count, ratio)
end

local function OnVoiceVolumeReport(client, message)
    if not client or client:GetIsVirtual() then return end
    local steamId = client:GetUserId()
    if not steamId or steamId == 0 then return end
    local steamIdKey = tostring(steamId)
    local now = Shared.GetTime()
    if lastVolumeReportTime[steamIdKey] and now - lastVolumeReportTime[steamIdKey] < kVolumeReportMinInterval then
        return
    end
    lastVolumeReportTime[steamIdKey] = now
    local entry = voiceVolumeBySteamId[steamIdKey] or { low = false }
    voiceVolumeBySteamId[steamIdKey] = entry
    entry.voice = Clamp(message.voice, 0, 100)
    entry.sound = Clamp(message.sound, 0, 100)
    EvaluateLowVoice(steamIdKey, entry, GetLowVoiceRatio())
end
Server.HookNetworkMessage("SSBVoiceVolumeReport", OnVoiceVolumeReport)

local function OnRequestLowVoiceStates(client)
    if not client then return end
    for steamIdKey, entry in pairs(voiceVolumeBySteamId) do
        if entry.low then
            Server.SendNetworkMessage(client, "SSBLowVoiceState", { steamId = steamIdKey, low = true }, true)
        end
    end
end
Server.HookNetworkMessage("SSBRequestLowVoiceStates", OnRequestLowVoiceStates)

local function OnTextMuteReport(client, message)
    local player = client and client:GetControllingPlayer()
    local listenerIndex = GetPlayerIndex(player)
    if not listenerIndex or client:GetIsVirtual() or message.clientIndex == listenerIndex then return end
    local mutes = textMutesByListener[listenerIndex] or {}
    mutes[message.clientIndex] = message.muted or nil
    textMutesByListener[listenerIndex] = next(mutes) and mutes or nil
end
Server.HookNetworkMessage("SSBTextMuteReport", OnTextMuteReport)

local function SendMutedBy(client, targetIndex, voice, text)
    local last = mutedBySent[targetIndex]
    if last and last.voice == voice and last.text == text then return end
    if not last and voice == 0 and text == 0 then return end
    Server.SendNetworkMessage(client, "SSBMutedByCount", { voice = voice, text = text }, true)
    mutedBySent[targetIndex] = (voice > 0 or text > 0) and { voice = voice, text = text } or nil
end

local function ScanMutedBy()
    local gamerules = GetGamerules and GetGamerules()
    local gameStarted = gamerules and gamerules:GetGameStarted()
    local seen = {}
    if gameStarted then
        for teamNumber = kTeam1Index, kTeam2Index do
            local teamPlayers = GetEntitiesForTeam("Player", teamNumber)
            for i = 1, #teamPlayers do
                local target = teamPlayers[i]
                local targetClient = Server.GetOwner(target)
                local targetIndex = GetPlayerIndex(target)
                if targetClient and targetIndex and not targetClient:GetIsVirtual() then
                    local voice, text = 0, 0
                    for j = 1, #teamPlayers do
                        local listener = teamPlayers[j]
                        if j ~= i then
                            local listenerIndex = GetPlayerIndex(listener)
                            -- Read the raw table: GetClientMuted is wrapped by
                            -- other mods with side effects (probe/notify).
                            if listener.mutedClients and listener.mutedClients[targetIndex] == true then
                                voice = voice + 1
                            end
                            local textMutes = listenerIndex and textMutesByListener[listenerIndex]
                            if textMutes and textMutes[targetIndex] then
                                text = text + 1
                            end
                        end
                    end
                    seen[targetIndex] = true
                    SendMutedBy(targetClient, targetIndex,
                        math.min(voice, kMaxMutedByCount), math.min(text, kMaxMutedByCount))
                end
            end
        end
    end
    -- Anyone with a non-zero last send who is no longer counted (game stopped,
    -- left a playing team) gets a single 0/0.
    for targetIndex in pairs(mutedBySent) do
        if not seen[targetIndex] then
            local client = Server.GetClientById(targetIndex)
            if client then
                SendMutedBy(client, targetIndex, 0, 0)
            else
                mutedBySent[targetIndex] = nil
            end
        end
    end
end

Event.Hook("UpdateServer", function()
    local now = Shared.GetTime()
    if now < nextMutedByScan then return end
    nextMutedByScan = now + kMutedByScanInterval
    ScanMutedBy()
end)

Event.Hook("ClientDisconnect", function(client)
    if not client then return end
    local player = client:GetControllingPlayer()
    local index = GetPlayerIndex(player) or client:GetId()
    if index then
        textMutesByListener[index] = nil
        mutedBySent[index] = nil
        for _, mutes in pairs(textMutesByListener) do mutes[index] = nil end
    end
    local steamId = client:GetUserId()
    local steamIdKey = steamId and steamId ~= 0 and tostring(steamId)
    if steamIdKey then
        local entry = voiceVolumeBySteamId[steamIdKey]
        voiceVolumeBySteamId[steamIdKey] = nil
        lastVolumeReportTime[steamIdKey] = nil
        if entry and entry.low then
            BroadcastLowVoice(steamIdKey, false)
        end
    end
end)

Print("[SSB] Server owns low-voice and muted-by state")
