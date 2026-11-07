if not Server then return end

Log("[NNSLBadges] NNSL Badges Manager Registered.")

Script.Load("lua/UnorderedSet.lua")
Script.Load("lua/mnga_administration/Globals.lua")

local kNNSLPlacementsFilePath = "config://mvp.json"


kBadgeStatus = enum(
{
    'NotRequested',
    'RequestSent',
    'RequestFailed',
    'RequestParseFailed',
    'RequestDataInvalid',
    'RequestSuccess',
})

local _NNSLBadgesManager
function GetNNSLBadgesManager()
    if not _NNSLBadgesManager then
        _NNSLBadgesManager = NNSLBadgesManager()
        _NNSLBadgesManager:Initialize()
    end

    return _NNSLBadgesManager
end


class "NNSLBadgesManager"

function NNSLBadgesManager:Initialize()

    self.placementData = { _empty= true }
    self.status = kBadgeStatus.NotRequested
    self.failReason = "None, it worked!"

    self.clientsWaiting = UnorderedSet()

end

function NNSLBadgesManager:InitializeData()

    self:SetStatus(kBadgeStatus.RequestSent)

    local file, openError = io.open(kNNSLPlacementsFilePath, "r")
    if not file then
        self:SetStatus(kBadgeStatus.RequestFailed,
            string.format("Could not open %s: %s", kNNSLPlacementsFilePath, tostring(openError)))
        return
    end

    local data = file:read("*all")
    file:close()

    if not data or data:match("^%s*$") then
        self:SetStatus(kBadgeStatus.RequestFailed,
            string.format("%s is empty; no MVP belt is available for this map", kNNSLPlacementsFilePath))
        return
    end

    Log("[NNSLBadges] Loading MVP belt data from %s (%d bytes).", kNNSLPlacementsFilePath, #data)
    self:ProcessPlacementData(data)

end

function NNSLBadgesManager:ProcessPlacementData(data)

    if not data then
        self:SetStatus(kBadgeStatus.RequestFailed, "MVP belt file data was nil")
        return
    end

    local parsed, err, errMsg = json.decode(data, 1, nil)
    if errMsg then
        self:SetStatus(kBadgeStatus.RequestParseFailed, string.format("JSON decode error at %s: %s", tostring(err), tostring(errMsg)))
        return
    end

    if not self:ValidateJson(parsed) then
        self:SetStatus(kBadgeStatus.RequestDataInvalid, "MVP belt JSON failed schema validation")
        return
    end

    -- Now to parse!
    for _, placementKey in ipairs(kNNSLPlacementRankKey) do
        self:ParsePlacementData(parsed, placementKey)
    end

    self:SetStatus(kBadgeStatus.RequestSuccess)
    Log("[NNSLBadges] MVP belt data loaded successfully from %s.", kNNSLPlacementsFilePath)
    NNSL_DebugLog("\tParsed Data (Memory): \n\t%s", self.placementData)

end

function NNSLBadgesManager:ValidateJson(data)

    if type(data) ~= "table" then
        NNSL_DebugLog("MVP belt JSON root is not a table! Was Type: %s", type(data))
        return false
    end

    -- Check tournament name
    if not data.tournament_name or type(data.tournament_name) ~= "string" then
        NNSL_DebugLog("tournament_name is not a string! Was Type: %s", type(data.tournamentName))
        return false
    end

    for i = 1, #kNNSLPlacementRankKey do

        local placementKey = kNNSLPlacementRankKey[i]
        if not self:ValidatePlacementData(data, placementKey) then
            return false
        end

    end

    return true

end

function NNSLBadgesManager:ValidatePlacementData(data, placementName)

    if data[placementName] then

        local placementData = data[placementName]
        if not placementData.team_name or type(placementData.team_name) ~= "string" then
            NNSL_DebugLog("team_name is not a string! Was Type: %s", type(placementData.team_name))
            return false
        end

        if not placementData.players or type(placementData.players) ~= "table" then
            NNSL_DebugLog("palyers is not a table! Was Type: %s", type(placementData.players))
            return false
        end

        for i = 1, #placementData.players do

            if type(placementData.players[i]) ~= "number" then
                NNSL_DebugLog("player id is not a number! Was Type: %s", type(placementData.players[i]))
                return false
            end

        end

    end

    return true

end

function NNSLBadgesManager:SetStatus(newStatus, statusReason)

    if newStatus == kBadgeStatus.RequestFailed or newStatus == kBadgeStatus.RequestParseFailed or newStatus == kBadgeStatus.RequestDataInvalid then
        self.failReason = statusReason
        Log("[NNSLBadges] MVP belt load failed (%s): %s", EnumToString(kBadgeStatus, newStatus), tostring(self.failReason))
    end

    self.status = newStatus
    self.placementData._empty = self.status ~= kBadgeStatus.RequestSuccess

    if self.status == kBadgeStatus.RequestSuccess then
        self:SendTeamPlacementDataToWaitingClients()
    end

end

function NNSLBadgesManager:ParsePlacementData(jsonData, placementKey)

    local teamPlacementData = jsonData[placementKey]

    -- We don't have it!
    if not teamPlacementData then
        NNSL_DebugLog("%s does not exist!", placementKey)
        return
    end

    local teamName = teamPlacementData.team_name
    local players = teamPlacementData.players

    if not self.placementData.tournament_name then
        self.placementData.tournament_name = string.UTF8SanitizeForNS2( jsonData.tournament_name )
    end

    if not teamName then
        self:SetStatus(kBadgeStatus.RequestParseFailed, "Request Parse Failed: 'team_name' does not exist!")
        return
    end

    if not players then
        self:SetStatus(kBadgeStatus.RequestParseFailed, "Request Parse Failed: 'players' does not exist!")
        return
    end

    NNSL_DebugLog("Rank From Enum: %s", kNNSLPlacementRankKey[placementKey])

    local teamData = {}
    teamData.teamName = string.UTF8SanitizeForNS2( teamName )
    teamData.teamPlacement = kNNSLPlacementRankKey[placementKey]

    -- Add team members as array of integers (ns2 id)
    teamData.playerIds = ""
    for i = 1, #players do
        local playerId = players[i]

        if i == 1 then
            teamData.playerIds = string.format("%u", playerId)
        else
            teamData.playerIds = string.format("%s,%u", teamData.playerIds, playerId)
        end

    end

    NNSL_DebugLog("\tteamData Table: %s", teamData)

    self.placementData[kNNSLPlacementRankKey[placementKey]] = teamData

end

function NNSLBadgesManager:SendTeamPlacementDataToWaitingClients()

    if #self.placementData == 0 or self.status ~= kBadgeStatus.RequestSuccess then
        LogError("[NNSLBadges] Tried to send team placement data, but there is no data or status is not Success!")
        return
    end

    NNSL_DebugLog("Sending Network Messages to Clients")
    for _, client in ipairs(self.clientsWaiting) do

        Server.SendNetworkMessage("NNSLTournamentName", {tournamentName = self.placementData.tournament_name}, true)

        -- Send each prepared team badge data and sent it to the client.
        for i = 1, #self.placementData do
            local teamPlacementData = self.placementData[i]
            Server.SendNetworkMessage("NNSLTeamPlacement", teamPlacementData, true)
        end

    end

end

function NNSLBadgesManager:OnClientConnect(newClient)

    self.clientsWaiting:Add(newClient)

    -- We have the data already, go ahead and send it to our new client.
    if self.status == kBadgeStatus.RequestSuccess then
        self:SendTeamPlacementDataToWaitingClients()
    end

end

function NNSLBadgesManager:OnClientDisconnect(disconnectingClient)
    if self.clientsWaiting:Contains(disconnectingClient) then
        self.clientsWaiting:RemoveElement(disconnectingClient)
    end
end

local function OnClientConnect(serverClient)
    GetNNSLBadgesManager():OnClientConnect(serverClient)
end
Event.Hook("ClientConnect", OnClientConnect)

local function OnClientDisconnect(serverClient)
    GetNNSLBadgesManager():OnClientDisconnect(serverClient)
end
Event.Hook("ClientDisconnect", OnClientDisconnect)

-- Load the one-round MVP belt handoff after the map and server scripts are ready.
local function OnMapPostLoad()
    GetNNSLBadgesManager():InitializeData()
end
Event.Hook("MapPostLoad", OnMapPostLoad)
