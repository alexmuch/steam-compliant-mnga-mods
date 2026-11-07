-- Persist client-selected voice/text mutes without replacing vanilla Chat.lua.

if not Client or MNGAPermanentMutesInstalled then return end
MNGAPermanentMutesInstalled = true

local kMuteFile = "config://mngaMutedPlayers.json"
-- Refreshed from disk every client VM; effectively permanent while remaining
-- a finite JSON-safe value for vanilla's voice-mute expiry comparison.
local kPermanentTargetTime = 253402300799 -- 9999-12-31 UTC

local mutedTextClients = Shine.GetUpValue(ChatUI_GetSteamIdTextMuted, "mutedTextClients", true)
local mutedVoiceClients = Shine.GetUpValue(ChatUI_GetVoiceChannelForClient, "mutedVoiceClients", true)
local mutedClients = Shine.GetUpValue(ChatUI_GetClientMuted, "mutedClients", true)

if type(mutedTextClients) ~= "table" or type(mutedVoiceClients) ~= "table" or type(mutedClients) ~= "table" then
    Print("[PermanentMutes] Failed to access vanilla mute state")
    return
end

local function ClearTable(values)
    for key in pairs(values) do
        values[key] = nil
    end
end

local function SavePermanentMutes()
    local data = {
        textMutes = {},
        voiceMutes = {}
    }

    for steamId, state in pairs(mutedTextClients) do
        if tonumber(steamId) and tonumber(steamId) > 0 and state.isMuted then
            data.textMutes[tostring(steamId)] = { isMuted = true }
        end
    end
    for steamId, state in pairs(mutedVoiceClients) do
        if tonumber(steamId) and tonumber(steamId) > 0 and state.isMuted then
            data.voiceMutes[tostring(steamId)] = { isMuted = true }
        end
    end

    local ok, err = Shine.SaveJSONFile(data, kMuteFile, { indent = true })
    if not ok then
        Print("[PermanentMutes] Failed to save mute state: %s", ToString(err))
    end
end

local function LoadEntries(target, entries)
    local count = 0
    for steamId, state in pairs(type(entries) == "table" and entries or {}) do
        steamId = tonumber(steamId)
        if steamId and steamId > 0 and type(state) == "table" and state.isMuted then
            target[steamId] = {
                isMuted = true,
                targetTime = kPermanentTargetTime
            }
            count = count + 1
        end
    end
    return count
end

local function LoadPermanentMutes()
    -- Vanilla's earlier LoadComplete handler may have populated its six-hour
    -- store. MNGA intentionally uses only its own independent persisted state.
    ClearTable(mutedTextClients)
    ClearTable(mutedVoiceClients)

    local data = Shine.LoadJSONFile(kMuteFile)
    if type(data) ~= "table" then
        Print("[PermanentMutes] Loaded 0 text and 0 voice mutes")
        return
    end

    local textCount = LoadEntries(mutedTextClients, data.textMutes)
    local voiceCount = LoadEntries(mutedVoiceClients, data.voiceMutes)
    Print("[PermanentMutes] Loaded %d text and %d voice mutes", textCount, voiceCount)
end

-- The setters are replaced, not wrapped: vanilla's setters end with its private
-- SaveMutedPlayers(), which would write MNGA's state into the vanilla
-- config://MutedPlayers.json. Bodies mirror vanilla Chat.lua minus that save.
function ChatUI_SetSteamIdTextMuted(steamId, muted)
    -- Player cannot mute themselves.
    if Client.GetSteamId() == steamId then
        return
    end

    if not mutedTextClients[steamId] then
        mutedTextClients[steamId] = {}
    end
    mutedTextClients[steamId].isMuted = muted
    mutedTextClients[steamId].targetTime = muted and kPermanentTargetTime or 0
    Print("[PermanentMutes] Text mute steamId=%s muted=%s", ToString(steamId), ToString(muted))

    SavePermanentMutes()
end

function ChatUI_SetClientMuted(clientIndex, muted)
    -- Player cannot mute themselves (vanilla's guard, kept verbatim).
    local localPlayer = Client.GetLocalPlayer()
    if localPlayer and localPlayer:GetClientIndex() == clientIndex and not localPlayer:GetTeamNumber() == kSpectatorIndex then
        return
    end

    Client.SendNetworkMessage("MutePlayer", BuildMutePlayerMessage(clientIndex, muted), true)
    mutedClients[clientIndex] = muted

    local steamId = GetSteamIdForClientIndex(clientIndex)
    if not mutedVoiceClients[steamId] then
        mutedVoiceClients[steamId] = {}
    end
    mutedVoiceClients[steamId].isMuted = muted
    mutedVoiceClients[steamId].targetTime = muted and kPermanentTargetTime or 0
    Print("[PermanentMutes] Voice mute steamId=%s muted=%s", ToString(steamId), ToString(muted))

    SavePermanentMutes()
end

-- Vanilla registered its loader while Chat.lua was loading. This module loads
-- later, so its handler runs afterward and replaces temporary state atomically.
Event.Hook("LoadComplete", LoadPermanentMutes)
