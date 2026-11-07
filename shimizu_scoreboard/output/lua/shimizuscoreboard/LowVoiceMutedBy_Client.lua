-- Low voice volume icon + "[muted by v/t]" team header (client side).
-- Reports local voice/sound option values and local-only text mutes to the
-- server; stores replicated low-voice flags and this client's muted-by counts.
local kVolumeReportInterval = 1
local kTextMuteReportInterval = 2

local lowVoiceBySteamId = {}
local mutedByVoice, mutedByText = 0, 0

local lastSentVoice, lastSentSound
local nextVolumeCheck = 0
local nextTextMuteCheck = 0
local reportedTextMutes = {} -- clientIndex -> true (as last reported to server)
local requestedLowVoiceSync = false

function SSB_GetLowVoice(steamId)
    return steamId ~= nil and lowVoiceBySteamId[tostring(steamId)] == true
end

function SSB_GetMutedByCounts()
    return mutedByVoice, mutedByText
end

Client.HookNetworkMessage("SSBLowVoiceState", function(message)
    local key = tostring(message.steamId)
    lowVoiceBySteamId[key] = message.low or nil
end)

Client.HookNetworkMessage("SSBMutedByCount", function(message)
    mutedByVoice, mutedByText = message.voice, message.text
end)

local function CheckVolumeReport()
    local voice = Clamp(Client.GetOptionInteger(kVoiceVolumeOptionsKey, 90), 0, 100)
    local sound = Clamp(Client.GetOptionInteger(kSoundVolumeOptionsKey, 90), 0, 100)
    if voice == lastSentVoice and sound == lastSentSound then return end
    Client.SendNetworkMessage("SSBVoiceVolumeReport", { voice = voice, sound = sound }, true)
    lastSentVoice, lastSentSound = voice, sound
end

local function CheckTextMuteReport()
    if not ScoreboardUI_GetAllScores then return end
    local present = {}
    local scores = ScoreboardUI_GetAllScores()
    for i = 1, #scores do
        local record = scores[i]
        local clientIndex = record.ClientIndex
        local steamId = record.SteamId or (clientIndex and GetSteamIdForClientIndex(clientIndex))
        if clientIndex and steamId and steamId > 0 then
            local muted = ChatUI_GetSteamIdTextMuted(steamId) == true
            present[clientIndex] = true
            if muted ~= (reportedTextMutes[clientIndex] == true) then
                Client.SendNetworkMessage("SSBTextMuteReport", { clientIndex = clientIndex, muted = muted }, true)
                reportedTextMutes[clientIndex] = muted or nil
            end
        end
    end
    -- Forget departed clients locally; the server clears them on disconnect.
    for clientIndex in pairs(reportedTextMutes) do
        if not present[clientIndex] then reportedTextMutes[clientIndex] = nil end
    end
end

Event.Hook("UpdateClient", function()
    local now = Shared.GetTime()
    if now < nextVolumeCheck then return end
    nextVolumeCheck = now + kVolumeReportInterval
    if not Client.GetLocalPlayer() then return end

    if not requestedLowVoiceSync then
        requestedLowVoiceSync = true
        Client.SendNetworkMessage("SSBRequestLowVoiceStates", {}, true)
    end
    CheckVolumeReport()

    if now >= nextTextMuteCheck then
        nextTextMuteCheck = now + kTextMuteReportInterval
        CheckTextMuteReport()
    end
end)

Print("[SSB] Low-voice and muted-by client loaded")
