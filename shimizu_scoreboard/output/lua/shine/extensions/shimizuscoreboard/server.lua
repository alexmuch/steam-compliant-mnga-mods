local Plugin = ...
local POST_JOIN_HOOK = "SSBEnhancedInfoPostJoin"
local HIVE_DATA_HOOK = "SSBEnhancedInfoHiveData"
local USER_RELOAD_HOOK = "SSBEnhancedInfoUserReload"

local function IsIPv4(Address)
    if type(Address) ~= "string" then return false end
    local A, B, C, D = Address:match("^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$")
    A, B, C, D = tonumber(A), tonumber(B), tonumber(C), tonumber(D)
    return A and B and C and D and A <= 255 and B <= 255 and C <= 255 and D <= 255
end

function Plugin:EnhancedLog() end

function Plugin:CanViewSensitiveInfo(Client)
    return Client and (Shine:HasAccess(Client, self.Config.SensitiveInfoPermission)
        or Shine:GetUserImmunity(Client) > 0) or false
end

function Plugin:SendEnhancedPlayerData(Target, SteamID)
    local Data = self.EnhancedPlayerData[tonumber(SteamID)]
    if not Data then return end
    self:SendNetworkMessage(Target, "EnhancedPlayerData", {
        SteamID = tostring(SteamID), Country = Data.Country or "Unknown",
        IsProxy = self:CanViewSensitiveInfo(Target) and Data.IsProxy == true or false,
        IsAdmin = Data.IsAdmin == true
    }, true)
end

function Plugin:BroadcastEnhancedPlayerData(SteamID)
    for Client in Shine.IterateClients() do self:SendEnhancedPlayerData(Client, SteamID) end
end

function Plugin:RequestLocation(Client)
    if not self.Config.EnableLocationInfo or not Shine:IsValidClient(Client) then return end
    local SteamID = tonumber(Client:GetUserId())
    local Entry = SteamID and self.EnhancedPlayerData[SteamID]
    if not Entry or Entry.LocationPending or Entry.LocationComplete then return end
    local Address = IPAddressToString(Server.GetClientAddress(Client))
    if not IsIPv4(Address) or Address == "127.0.0.1" then
        Entry.Country, Entry.IsProxy, Entry.LocationComplete = "Unknown", false, true
        self:BroadcastEnhancedPlayerData(SteamID)
        self:EnhancedLog("location skipped steam_id=%s address=%s", tostring(SteamID), tostring(Address))
        return
    end
    Entry.LocationPending = true
    Shared.SendHTTPRequest(string.format(self.Config.LocationLookupURL, Address), "GET", {}, function(Response)
        local Current = self.EnhancedPlayerData[SteamID]
        if not Current then return end
        Current.LocationPending = false
        local Success, Decoded = pcall(json.decode, Response or "")
        if Success and type(Decoded) == "table" and Decoded.status == "success" then
            Current.Country = tostring(Decoded.country or "Unknown"):sub(1, 64)
            Current.IsProxy = Decoded.proxy == true
            Current.LocationComplete = true
            self:EnhancedLog("location resolved steam_id=%s country=%s proxy=%s",
                tostring(SteamID), Current.Country, tostring(Current.IsProxy))
        else
            Current.Country, Current.IsProxy, Current.LocationComplete = "Unknown", false, true
            self:EnhancedLog("location failed steam_id=%s", tostring(SteamID))
        end
        self:BroadcastEnhancedPlayerData(SteamID)
    end)
end

function Plugin:TrackClient(Client)
    if not Shine:IsValidClient(Client) or Client:GetUserId() == 0 then return end
    local SteamID = tonumber(Client:GetUserId())
    local Entry = self.EnhancedPlayerData[SteamID] or {}
    Entry.Country = Entry.Country or "Unknown"
    Entry.IsProxy = Entry.IsProxy == true
    Entry.IsAdmin = self:CanViewSensitiveInfo(Client)
    self.EnhancedPlayerData[SteamID] = Entry
    self:BroadcastEnhancedPlayerData(SteamID)
    self:RequestLocation(Client)
end

function Plugin:UpdateEnhancedTeamSkills()
    local VoteRandom = Shine.Plugins and Shine.Plugins.voterandom
    if not VoteRandom or not VoteRandom.Enabled or type(VoteRandom.GetTeamStats) ~= "function" then return end
    local Stats = VoteRandom:GetTeamStats()
    if not Stats or not Stats[1] or not Stats[2] then return end
    self.dt.MarineAvgSkill = math.max(0, math.floor(tonumber(Stats[1].Average) or 0))
    self.dt.AlienAvgSkill = math.max(0, math.floor(tonumber(Stats[2].Average) or 0))
    self.dt.MarineTotalSkill = math.max(0, math.floor(tonumber(Stats[1].Total) or 0))
    self.dt.AlienTotalSkill = math.max(0, math.floor(tonumber(Stats[2].Total) or 0))
    self:EnhancedLog("team skills marine_avg=%d alien_avg=%d marine_total=%d alien_total=%d",
        self.dt.MarineAvgSkill, self.dt.AlienAvgSkill,
        self.dt.MarineTotalSkill, self.dt.AlienTotalSkill)
end

function Plugin:RefreshEnhancedPermissions()
    for Client in Shine.IterateClients() do
        local SteamID = tonumber(Client:GetUserId())
        local Entry = SteamID and self.EnhancedPlayerData[SteamID]
        if Entry then Entry.IsAdmin = self:CanViewSensitiveInfo(Client) end
    end
    for SteamID in pairs(self.EnhancedPlayerData) do self:BroadcastEnhancedPlayerData(SteamID) end
    self:EnhancedLog("refreshed permission-derived metadata")
end

function Plugin:Initialise()
    self.EnhancedPlayerData = {}
    self.dt.EnableTeamAvgSkill = self.Config.EnableTeamAvgSkill
    self.dt.EnableTeamAvgSkillPregame = self.Config.EnableTeamAvgSkillPregame
    self.dt.EnableTeamTotalSkill = self.Config.EnableTeamTotalSkill
    self.dt.EnableLocationInfo = self.Config.EnableLocationInfo
    self.dt.EnableQueueInfo = self.Config.EnableQueueInfo
    self.dt.EnableShowAdmin = self.Config.EnableShowAdmin
    Shine.Hook.Add("PostJoinTeam", POST_JOIN_HOOK, function() self:UpdateEnhancedTeamSkills() end)
    Shine.Hook.Add("OnReceiveHiveData", HIVE_DATA_HOOK, function(Client) self:TrackClient(Client) end)
    Shine.Hook.Add("OnUserReload", USER_RELOAD_HOOK, function() self:RefreshEnhancedPermissions() end)
    for Client in Shine.IterateClients() do self:TrackClient(Client) end
    self:UpdateEnhancedTeamSkills()
    self.Enabled = true
    if SSB_RecomputeLowVoice then SSB_RecomputeLowVoice() end
    return true
end

function Plugin:ClientConnect(Client)
    for SteamID in pairs(self.EnhancedPlayerData) do self:SendEnhancedPlayerData(Client, SteamID) end
    self:TrackClient(Client)
end

function Plugin:ClientDisconnect(Client)
    if not Client then return end
    local SteamID = tonumber(Client:GetUserId())
    if not SteamID then return end
    self.EnhancedPlayerData[SteamID] = nil
    self:SendNetworkMessage(nil, "EnhancedPlayerRemoved", { SteamID = tostring(SteamID) }, true)
    self:EnhancedLog("removed steam_id=%s", tostring(SteamID))
end

function Plugin:Cleanup()
    Shine.Hook.Remove("PostJoinTeam", POST_JOIN_HOOK)
    Shine.Hook.Remove("OnReceiveHiveData", HIVE_DATA_HOOK)
    Shine.Hook.Remove("OnUserReload", USER_RELOAD_HOOK)
    self.EnhancedPlayerData = {}
    self.BaseClass.Cleanup(self)
    self.Enabled = false
end

return Plugin
