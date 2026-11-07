--[[
	Shine commander bans plugin.
]]

local JSON = require "shine/lib/json"

local Plugin = ...

local Shine = Shine

local GetClientForPlayer = Shine.GetClientForPlayer
local Max = math.max
local StringFormat = string.format
local Time = os.time

Plugin.Version = "1.0"
Plugin.HasConfig = true
Plugin.ConfigName = "CommRestrict.json"
Plugin.PrintName = "CommRestrict"

Plugin.DefaultConfig = {
	Banned = JSON.Object(),
	BansSubmitURL = "",
	BansSubmitArguments = JSON.Object(),
	LogLevel = "Info",
	MaxSubmitRetries = 3,
	SubmitTimeout = 5,
	DefaultBanTime = 60,
	EloThreshold = 2100,
	-- Restriction is waived when humans in teams + ready room are at most this many.
	WaiveMaxPlayers = 16,
	-- Restriction is always fully enforced for this long after map load.
	FullLockSeconds = 15
}

Plugin.CheckConfig = true
Plugin.ListPermission = "sh_uncommrestrict"
Plugin.OnBannedHookName = "OnCommanderRestrict"
Plugin.OnUnbannedHookName = "OnCommanderUnrestrict"
Plugin.CanUnbanPlayerInGame = true

function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )
	self:BuildInitialNetworkData()

	self:VerifyConfig()

	self.Retries = {}

	self:CreateCommands()
	self:CheckBans()

	self.Enabled = true

	return true
end


--[[
    Standalone Hive skill average calculator for all players on the server.
    Extracted and simplified from the Shine voterandom plugin's team_balance.lua.
 
    Simplifications vs. the original:
      - Uses base player skill only (no per-team offsets).
      - Ignores commander skill entirely; commanders are treated as field players.
      - Covers all human players on the server regardless of team, including ready room.
      - Bots are ignored.
]]
 
local GetClientForPlayer = Shine.GetClientForPlayer
 
local function GetBaseHiveSkill( Ply )
    local Client = GetClientForPlayer( Ply )
    if not Client or Client:GetIsVirtual() then
        return nil -- Ignore bots.
    end
 
    if not Ply.GetPlayerSkill then
        return nil
    end
 
    return Ply:GetPlayerSkill() or nil
end
 
--[[
    Returns average Hive skill stats for all human players currently on the server,
    including players in the ready room.
 
    Usage:
        local Result = GetAllPlayersAverageHiveSkill()
        if Result then
            Shared.Message( "Server avg skill: " .. Result.Average )
            Shared.Message( "Players with data: " .. Result.Count )
        end
]]
function GetAllPlayersAverageHiveSkill()
    local Gamerules = GetGamerules()
    if not Gamerules then return nil end
 
    local Players, PlayerCount = Shine.GetAllPlayers()
 
    local SkillSum = 0
    local Count   = 0
    local Skills  = {}
 
    for i = 1, PlayerCount do
        local Ply = Players[ i ]
        if Ply then
            local Skill = GetBaseHiveSkill( Ply )
            if Skill then
                Count           = Count + 1
                SkillSum        = SkillSum + Skill
                Skills[ Count ] = Skill
            end
        end
    end
 
    if Count == 0 then
        return { Average = 0, Total = 0, Count = 0, Skills = {} }
    end
 
    table.sort( Skills, function( A, B ) return A > B end )
 
    return {
        Average = SkillSum / Count,
        Total   = SkillSum,
        Count   = Count,
        Skills  = Skills
    }
end


--[[
	Counts human players in the ready room and on teams (spectators and bots excluded).
]]
local function GetHumanPlayerCount()
	local Players, PlayerCount = Shine.GetAllPlayers()
	local Count = 0

	for i = 1, PlayerCount do
		local Ply = Players[ i ]
		if Ply then
			local Team = Ply:GetTeamNumber()
			local Client = GetClientForPlayer( Ply )
			if ( Team == kTeamReadyRoom or Team == kTeam1Index or Team == kTeam2Index )
			and Client and not Client:GetIsVirtual() then
				Count = Count + 1
			end
		end
	end

	return Count
end

--[[
	Deny commanding if they're banned.
]]
function Plugin:ValidateCommanderLogin( Gamerules, CommandStation, Player )
	local Client = GetClientForPlayer( Player )
	if not Client then
		self.Logger:Error( "Unable to get client for player %s! Cannot check for commander restrict.", Player )
		return
	end

	local ID = tostring( Client:GetUserId() )
	local BanData = self.Config.Banned[ ID ]
	if not BanData then
		if self.Logger:IsDebugEnabled() then
			self.Logger:Debug( "No commander restrict on record for %s, allowing to command.",
				Shine.GetClientInfo( Client ) )
		end
		return
	end

	local CurTime = Time()

	if BanData.UnbanTime ~= 0 and BanData.UnbanTime <= CurTime then
		if self.Logger:IsDebugEnabled() then
			self.Logger:Debug( "Removing expired commander restrict for %s (expired at %d)",
				Shine.GetClientInfo( Client ), BanData.UnbanTime )
		end

		self:RemoveBan( ID, nil, 0 )
		return
	end

	-- Right after map load few players have joined, so skill/player count are unreliable and a fast loader
	-- could grab the chair. Fully restrict during this window.
	local MapTime = Shared.GetTime()
	local FullLock = MapTime < self.Config.FullLockSeconds

	if not FullLock then
		-- Once the round has started the restriction no longer applies (unlike a comm ban).
		if Gamerules:GetGameStarted() then
			return
		end

		local Count = GetHumanPlayerCount()
		if Count <= self.Config.WaiveMaxPlayers then
			return
		end

		local Result = GetAllPlayersAverageHiveSkill()
		if not Result or Result.Average <= self.Config.EloThreshold then
			return
		end
	end

	if Shine:CanNotify( Client ) then
		local Duration = BanData.UnbanTime == 0 and 0
			or ( BanData.UnbanTime - CurTime )

		self:SendTranslatedNotify( Client, "RESTRICTED_WARNING", {
			Duration = Duration
		} )
	end

	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug( "Preventing %s from commanding due to restrict with expiry time: %s.",
			Shine.GetClientInfo( Client ), BanData.UnbanTime == 0 and "never" or BanData.UnbanTime )
	end

	return false
end

Plugin.OperationSuffix = " from commanding"
Plugin.CommandNames = {
	Ban = { "sh_commrestrict", "commrestrict" },
	BanID = { "sh_commrestrictid", "commrestrictid" },
	Unban = { "sh_uncommrestrict", "uncommrestrict" }
}

function Plugin:PerformBan( Target, Player )
	if Player:isa( "Commander" ) then
		Player:Eject()
	end
end

--[[
	Creates the plugins console/chat commands.
]]
function Plugin:CreateCommands()
	self:CreateBanCommands()
end
