--=============================================================================
--
-- lua/Chat.lua
--
-- Created by Max McGuire (max@unknownworlds.com)
-- Copyright 2011, Unknown Worlds Entertainment
--
--=============================================================================

-- color, playername, color, message
local chatMessages = { }
local enteringChatMessage = false
local startedChatTime = 0
local teamOnlyChat = false
-- Note: Nothing clears this out but it is probably safe to assume the player won't
-- mute enough clients to run out of memory.
local mutedClients = { }
local mutedTextClients = { }
-- This is only a table with SteamIds for persistent mutes, muted voice uses clientIndex
local mutedVoiceClients = { }
local mutedPlayersFileName = "config://mngaMutedPlayers.json"
local vanillaMutedPlayersFileName = "config://MutedPlayers.json"
-- Player-selected voice and text mutes persist until explicitly removed.

local function SaveMutedPlayers()
    local savedMutes = {}
    local textMutes = {}
    local voiceMutes = {}
    
    for steamId, player in pairs(mutedTextClients) do
        if steamId > 0 and player.isMuted then
            textMutes[steamId] = player
        end
    end
    
    for steamId, player in pairs(mutedVoiceClients) do
        if steamId > 0 and player.isMuted then
            voiceMutes[steamId] = player
        end
    end
    
    savedMutes.textMutes = textMutes
    savedMutes.voiceMutes = voiceMutes
    
    local mutedPlayersFile = io.open(mutedPlayersFileName, "w+")
    
    if mutedPlayersFile then
        mutedPlayersFile:write(json.encode(savedMutes, { indent = true }))
        
        io.close(mutedPlayersFile)
    end
end

local function LoadMutedPlayers(fileName, requireActiveVanillaMute)
    local mutedPlayersFile = GetFileExists(fileName) and io.open(fileName, "r")
    local loadedTextMutes = 0
    local loadedVoiceMutes = 0

    if mutedPlayersFile then
        local parsedFile, _, errStr = json.decode(mutedPlayersFile:read("*all"))

        if not errStr and parsedFile then
            -- When saving this to file and back, it will assume the steamId is a string
            -- When we do the table lookup, it won't match, because it's a number
            -- So parse the index as a number and save properly to our local table
            for steamId, player in pairs(parsedFile.textMutes or {}) do
                local isActive = not requireActiveVanillaMute or
                    (player.targetTime and player.targetTime > Shared.GetSystemTime())
                if IsNumber(tonumber(steamId)) and player.isMuted and isActive then
                    mutedTextClients[tonumber(steamId)] = player
                    loadedTextMutes = loadedTextMutes + 1
                end
            end

            for steamId, player in pairs(parsedFile.voiceMutes or {}) do
                local isActive = not requireActiveVanillaMute or
                    (player.targetTime and player.targetTime > Shared.GetSystemTime())
                if IsNumber(tonumber(steamId)) and player.isMuted and isActive then
                    mutedVoiceClients[tonumber(steamId)] = player
                    loadedVoiceMutes = loadedVoiceMutes + 1
                end
            end
        end

        io.close(mutedPlayersFile)
    end

    return loadedTextMutes, loadedVoiceMutes
end

local function OnLoadComplete()
    local isFirstMNGALoad = not GetFileExists(mutedPlayersFileName)
    local loadedTextMutes
    local loadedVoiceMutes

    if isFirstMNGALoad then
        loadedTextMutes, loadedVoiceMutes = LoadMutedPlayers(vanillaMutedPlayersFileName, true)
        Shared.Message(string.format(
            "[PermanentMutes] First run imported %d active text and %d active voice mutes from vanilla",
            loadedTextMutes, loadedVoiceMutes))
    else
        loadedTextMutes, loadedVoiceMutes = LoadMutedPlayers(mutedPlayersFileName, false)
    end

    -- Save the table to cleanup old players that are no longer muted
    SaveMutedPlayers()
    Shared.Message(string.format("[PermanentMutes] Loaded %d text and %d voice mutes", loadedTextMutes, loadedVoiceMutes))
end

--
-- Returns true if the passed in client is currently speaking.
--
function ChatUI_GetVoiceChannelForClient(clientIndex)
    if clientIndex == nil then
        return VoiceChannel.Invalid, false
    end

    local steamId = GetSteamIdForClientIndex(clientIndex)
    local currentPlayer = mutedVoiceClients[steamId]
    if currentPlayer and currentPlayer.isMuted then
        if not mutedClients[clientIndex] then
            local message = BuildMutePlayerMessage(clientIndex, true)
            Client.SendNetworkMessage("MutePlayer", message, true)
            mutedClients[clientIndex] = true
        end
    end
    
    -- Handle the local client specially.
    if Client.GetLocalClientIndex() == clientIndex then
        return Client.GetVoiceChannelForRecording(), true
    end

    return Client.GetVoiceChannelForClient(clientIndex), false
    
end

function ChatUI_SetClientMuted(muteClientIndex, setMute)

    -- Player cannot mute themselves.
    local localPlayer = Client.GetLocalPlayer()
    if localPlayer and localPlayer:GetClientIndex() == muteClientIndex and not localPlayer:GetTeamNumber() == kSpectatorIndex then
        return
    end
    
    local message = BuildMutePlayerMessage(muteClientIndex, setMute)
    Client.SendNetworkMessage("MutePlayer", message, true)
    mutedClients[muteClientIndex] = setMute

    -- Persistent mutes
    local steamId = GetSteamIdForClientIndex(muteClientIndex)
    if not mutedVoiceClients[steamId] then
        mutedVoiceClients[steamId] = { }
    end
    
    mutedVoiceClients[steamId].isMuted = setMute
    mutedVoiceClients[steamId].targetTime = nil
    Shared.Message(string.format("[PermanentMutes] Voice mute steamId=%s muted=%s", tostring(steamId), tostring(setMute)))
    
    SaveMutedPlayers()
end

function ChatUI_GetClientMuted(clientIndex)
    return mutedClients[clientIndex] == true
end

function ChatUI_SetSteamIdTextMuted(steamId, setTextMute)
    -- Player cannot mute themselves.
    local localPlayer = Client.GetSteamId()
    if localPlayer == steamId then
        return
    end
    
    if not mutedTextClients[steamId] then
        mutedTextClients[steamId] = {}
    end
    
    mutedTextClients[steamId].isMuted = setTextMute
    mutedTextClients[steamId].targetTime = nil
    Shared.Message(string.format("[PermanentMutes] Text mute steamId=%s muted=%s", tostring(steamId), tostring(setTextMute)))

    SaveMutedPlayers()
end

function ChatUI_GetSteamIdTextMuted(steamId)
    -- Bots and the client should never be muted
    if steamId == Client.GetSteamId() or steamId == 0 then
        return false
    else
        return mutedTextClients[steamId] and mutedTextClients[steamId].isMuted == true or false
    end
end

function ChatUI_GetMessages()

    local uiChatMessages = { }
    
    if table.icount(chatMessages) > 0 then
    
        table.copy(chatMessages, uiChatMessages)
        chatMessages = { }
        
    end
    
    return uiChatMessages
    
end

-- Return true if we want the UI to take key input for chat
function ChatUI_EnteringChatMessage()

    if MainMenu_GetIsOpened() then
        return false
    else 
        return enteringChatMessage
    end
    
end

function ChatUI_GetStartedChatTime()
    return startedChatTime
end

-- Return string prefix to display in front of the chat input
function ChatUI_GetChatMessageType()

    if teamOnlyChat then
        return "Team: "
    end
    
    return "All: "
    
end

--
--Called when player hits return after entering a chat message. Send it to the server.
--
function ChatUI_SubmitChatMessageBody(chatMessage)

    -- Quote string so spacing doesn't come through as multiple arguments
    if chatMessage ~= nil and string.len(chatMessage) > 0 then
    
        chatMessage = string.UTF8Sub(chatMessage, 1, kMaxChatLength)
        Client.SendNetworkMessage("ChatClient", BuildChatClientMessage(teamOnlyChat, chatMessage), true)
        
        teamOnlyChat = false
        
    end
    
    enteringChatMessage = false
    
    SetMoveInputBlocked(false)
    
end

--
--Client should call this when player hits key to enter a chat message.
--
function ChatUI_EnterChatMessage(teamOnly)

    if not enteringChatMessage then
    
        enteringChatMessage = true
        startedChatTime = Shared.GetTime()
        teamOnlyChat = teamOnly
        
        SetMoveInputBlocked(true)
        
    end
    
end

local function GetIsVisibleTeam(teamNumber)
    local isVisibleTeam = false
    local localPlayer = Client.GetLocalPlayer()
    if localPlayer then
    
        local localPlayerTeamNum = localPlayer:GetTeamNumber()
        -- Can see secret information if the player is on the team or is a spectator.
        if teamNumber == kTeamReadyRoom or localPlayerTeamNum == teamNumber or localPlayerTeamNum == kSpectatorIndex then
            isVisibleTeam = true
        end
        
    end
    
    return isVisibleTeam
end

local function OnChatMessageInternal(message, needsLocalization)
    PROFILE("Chat:OnChatMessageInternal")

    local player = Client.GetLocalPlayer()

    if player then

        -- color, playername, color, message

        local isCommander = false
        local drawRookie = false
        local isRookie = false
        local steamId = 0

        local playerData = ScoreboardUI_GetAllScores()

        for _, playerRecord in ipairs(playerData) do

            if playerRecord.Name == message.playerName then
                isCommander = playerRecord.IsCommander and GetIsVisibleTeam(playerRecord.EntityTeamNumber)
                isRookie = playerRecord.IsRookie
                drawRookie = isRookie and ((player:GetTeamNumber() == playerRecord.EntityTeamNumber) or (player:GetTeamNumber() == kSpectatorIndex))
                steamId = GetSteamIdForClientIndex(playerRecord.ClientIndex)
                break
            end

        end

        if steamId and steamId > 0 and not ChatUI_GetSteamIdTextMuted(steamId) or steamId == 0 then
            table.insert(chatMessages, GetColorForTeamNumber(message.teamNumber))

            -- Tack on location name if any
            local locationNameText = ""

            -- Lookup location name from passed in id
            local locationName = ""
            if message.locationId > 0 then
                locationNameText = string.format("(Team, %s) ", Shared.GetString(message.locationId))
            else
                locationNameText = "(Team) "
            end

            -- Pre-pend "team" or "all"
            local preMessageString = string.format("%s%s: ", message.teamOnly and locationNameText or "(All) ", message.playerName, locationNameText)

            table.insert(chatMessages, preMessageString)

            table.insert(chatMessages, kChatTextColor[message.teamType])

            local chatMessage = needsLocalization and Locale.ResolveString(message.message) or message.message
            table.insert(chatMessages, chatMessage)

            table.insert(chatMessages, isCommander)

            table.insert(chatMessages, isRookie)
            -- Reserved
            table.insert(chatMessages, 0)
            -- Reserved
            table.insert(chatMessages, 0)

            StartSoundEffect(player:GetChatSound())
        end

        -- Only print to log if the client isn't running a local server
        -- which has already printed to log.
        if not Client.GetIsRunningServer() then

            local prefixText = "Chat All"
            if message.teamOnly then
                prefixText = "Chat Team " .. message.teamNumber
            end

            Shared.Message(prefixText .. " - " .. message.playerName .. ": " .. message.message)

        end

    end

end

--
--This function is called when the client receives a chat message.
--
local function OnMessageChat(message)
    PROFILE("Chat:OnMessageChat")
    OnChatMessageInternal(message, false)
end

local function OnMessageChatUnlocalized(message)
    PROFILE("Chat:OnMessageChatUnlocalized")
    OnChatMessageInternal(message, true)
end

local kSystemMessageHexColor = 0xFFD800
local kSystemMessageColor = Color(1.0, 0.8, 0.0, 1)

-- Let other modules add messages to the chat system - useful for system messages
function ChatUI_AddSystemMessage(msgText)

    local player = Client.GetLocalPlayer()    
    
    if player then
    
        table.insert(chatMessages, kSystemMessageHexColor)
        table.insert(chatMessages, "")
        
        table.insert(chatMessages, kSystemMessageColor)
        table.insert(chatMessages, msgText)

        table.insert(chatMessages, false)
        table.insert(chatMessages, false)
        -- Reserved
        table.insert(chatMessages, 0)
        -- Reserved
        table.insert(chatMessages, 0)

        StartSoundEffect(player:GetChatSound())
        
    end
    
end

Client.HookNetworkMessage("Chat", OnMessageChat)
Client.HookNetworkMessage("ChatUnlocalized", OnMessageChatUnlocalized)
Event.Hook("LoadComplete", OnLoadComplete)
