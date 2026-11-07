local Plugin = Shine.Plugin(...)

Plugin.HasConfig = true
Plugin.PrintName = "Shimizu Scoreboard"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.ConfigName = "shimizuscoreboard.json"
Plugin.DefaultState = true
Plugin.DefaultConfig = {
    SpectatorScoreboardViewMode = "USE_SERVER_SETTINGS",
    EnableTeamAvgSkill = false,
    EnableTeamAvgSkillPregame = false,
    EnableTeamTotalSkill = false,
    EnableLocationInfo = true,
    EnableQueueInfo = true,
    EnableShowAdmin = false,
    LocationLookupURL = "http://ip-api.com/json/%s?fields=status,proxy,country",
    SensitiveInfoPermission = "sh_esbinfo",
    DebugEnhancedInfo = false,
    -- A player is flagged "Low voice volume" when voiceVolume <= ratio * soundVolume.
    LowVoiceVolumeRatio = 1 / 3
}

function Plugin:SetupDataTable()
    self:AddDTVar("boolean", "EnableTeamAvgSkill", false)
    self:AddDTVar("boolean", "EnableTeamAvgSkillPregame", false)
    self:AddDTVar("boolean", "EnableTeamTotalSkill", false)
    self:AddDTVar("boolean", "EnableLocationInfo", true)
    self:AddDTVar("boolean", "EnableQueueInfo", true)
    self:AddDTVar("boolean", "EnableShowAdmin", false)
    self:AddDTVar("integer (0 to 65535)", "MarineAvgSkill", 0)
    self:AddDTVar("integer (0 to 65535)", "AlienAvgSkill", 0)
    self:AddDTVar("integer (0 to 2147483647)", "MarineTotalSkill", 0)
    self:AddDTVar("integer (0 to 2147483647)", "AlienTotalSkill", 0)
    self:AddNetworkMessage("EnhancedPlayerData", {
        SteamID = "string (32)", Country = "string (64)",
        IsProxy = "boolean", IsAdmin = "boolean"
    }, "Client")
    self:AddNetworkMessage("EnhancedPlayerRemoved", { SteamID = "string (32)" }, "Client")
end

return Plugin
