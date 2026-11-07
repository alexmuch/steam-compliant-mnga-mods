local Plugin = ...
local Shine = Shine
local StringFormat = string.format
function Plugin:GetClientInfo( Client, NoTeam )
	if not Client then return "Console" end

	local Player = Client:GetControllingPlayer()
	local PlayerName = Player and Player:GetName() or "<unknown>"
	local ID = Client.GetUserId and Client:GetUserId() or 0

	if not NoTeam then
		local Team = Player and Shine:GetTeamName( Player:GetTeamNumber(), true ) or "No team"

		return StringFormat( "[%s][%s]%s", ID, Team, PlayerName )
	end

	return StringFormat( "[%s - %s]<%s>%s", ID,
		Shine.NS2ToSteamID( ID ), IPAddressToString( Server.GetClientAddress( Client ) ), PlayerName )
end

function Plugin:ClientConnect( Client )
	if not Client then return end
	if Client:GetIsVirtual() then
		return
	end

	-- Print() treats its first argument as a format string. Keep player-controlled
	-- names in a value argument so names containing '%' cannot become directives.
	Print( "%s", StringFormat( " >;> CONNECT | %s | Client %s connected.",
		Shared.GetTime(), self:GetClientInfo( Client, true ) ) )

	if self.ScheduleBotReconcile then
		self:ScheduleBotReconcile( "client connect", 1 )
	end

	if Shared.GetTime() > 15 then
		local steamid = Client:GetUserId()		
		self:GetUserStats( { steamid } )
	end
	
end
	
function Plugin:ClientConfirmConnect( Client )
	if not Client then return end
	if Client:GetIsVirtual() then
		return
	end
	
	Print( "%s", StringFormat( " >;> CONFIRMCONNECT | %s | Client %s connected.",
		Shared.GetTime(), self:GetClientInfo( Client, true ) ) )
	-- Shine:LogString( StringFormat( ">> CONNECT | %s | Client %s connected.", Shared.GetTime() , self:GetClientInfo( Client, true ) ) )
	
end

local function IsActiveMatch()
	local gameInfo = GetGameInfoEntity and GetGameInfoEntity()
	return gameInfo and gameInfo.state == kGameState.Started
end

local function IsPlayingTeamNumber( TeamNumber )
	return TeamNumber == kTeam1Index or TeamNumber == kTeam2Index
end

-- A disconnect may be delivered after NS2 has detached/destroyed the player's
-- entity. Keep a stable per-client key so the active-round snapshot can still
-- identify which team the client was playing on.
local function GetLeaveAnnouncementClientKey( Client )
	if not Client then return end

	local UserId = Client.GetUserId and Client:GetUserId()
	if UserId and UserId ~= 0 then
		return "user:" .. tostring( UserId )
	end

	local ClientId = Client.GetId and Client:GetId()
	if ClientId then
		return "client:" .. tostring( ClientId )
	end
end

local function GetLeaveAnnouncementInfo( Client, Player )
	if not Client or not Player then return end

	local TeamNumber = Player:GetTeamNumber()
	if not IsPlayingTeamNumber( TeamNumber ) then return end

	return {
		ClientId = GetLeaveAnnouncementClientKey( Client ),
		Name = Player:GetName(),
		-- Kept so the leave line can resolve SSB aliases after the client is gone.
		SteamID = Client:GetUserId(),
		Team = Shine:GetTeamName( TeamNumber, true ),
		IsCommander = Player:isa( "Commander" )
	}
end

local function CacheActiveMatchLeaveInfo( Plugin, Client, Player )
	local ClientKey = GetLeaveAnnouncementClientKey( Client )
	if not ClientKey then return end

	Plugin.ActiveMatchLeaveInfo = Plugin.ActiveMatchLeaveInfo or {}

	local Info = GetLeaveAnnouncementInfo( Client, Player )
	if Info then
		Plugin.ActiveMatchLeaveInfo[ ClientKey ] = Info
		return Info
	end

	Plugin.ActiveMatchLeaveInfo[ ClientKey ] = nil
end

local function GetCachedActiveMatchLeaveInfo( Plugin, Client )
	local ClientKey = GetLeaveAnnouncementClientKey( Client )
	return ClientKey and Plugin.ActiveMatchLeaveInfo and Plugin.ActiveMatchLeaveInfo[ ClientKey ]
end

local function ClearActiveMatchLeaveInfo( Plugin, Client )
	local ClientKey = GetLeaveAnnouncementClientKey( Client )
	if not ClientKey or not Plugin.ActiveMatchLeaveInfo then return end

	Plugin.ActiveMatchLeaveInfo[ ClientKey ] = nil
end

function Plugin:AnnounceActiveMatchLeave( Info, Destination )
	if not Info or not Destination then return end
	if not IsActiveMatch() then
		return
	end

	local CommTag = Info.IsCommander and " [comm]" or ""
	MNGA_NotifyNames( nil, 255, 80, 80, "%s (%s)%s has left %s",
		MNGA_Name( Info.SteamID or 0, Info.Name or "<unknown>" ), Info.Team or "Unknown", CommTag, Destination )
end

function Plugin:AnnounceActiveMatchJoin( Client, Player )
	if not Client or not Player or Client:GetIsVirtual() then return end
	if not IsActiveMatch() then return end

	local TeamNumber = Player:GetTeamNumber()
	if not IsPlayingTeamNumber( TeamNumber ) then return end

	MNGA_NotifyNames( nil, 80, 255, 80, "%s has joined %s",
		MNGA_Name( Player ), Shine:GetTeamName( TeamNumber, true ) )
	Print( "%s", StringFormat( "[active-join] announced %s", Message ) )
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	if not Player then return end
	if not IsActiveMatch() then return end

	local Client = Shine.GetClientForPlayer( Player )
	if not Client or Client:GetIsVirtual() then return end

	local Info = GetLeaveAnnouncementInfo( Client, Player )
	if not Info then return end

	if NewTeam == kTeamReadyRoom then
		self.PendingLeaveAnnouncements = self.PendingLeaveAnnouncements or {}
		self.PendingLeaveAnnouncements[ Info.ClientId ] = Info
	end
end

function Plugin:ClientDisconnect( Client )
	if not Client then return end
	if Client:GetIsVirtual() then
		return
	end
	if self.ClearSpectatorAllChatCooldown then
		self:ClearSpectatorAllChatCooldown( Client, "client disconnected" )
	end
	if self.HandleSpectatorDrawingClientDisconnect then
		self:HandleSpectatorDrawingClientDisconnect( Client )
	end
	self:CancelQueuePromotionTimeout( Client, "client disconnected" )
	local Player = Client:GetControllingPlayer()
	local LeaveInfo = GetLeaveAnnouncementInfo( Client, Player )
	if not LeaveInfo then
		LeaveInfo = GetCachedActiveMatchLeaveInfo( self, Client )
	end
	ClearActiveMatchLeaveInfo( self, Client )
	if LeaveInfo then
		self:AnnounceActiveMatchLeave( LeaveInfo, "the server" )
	end

	Print( "%s", StringFormat( " >;> DISCONNECT | %s | Client %s disconnected.",
		Shared.GetTime(), self:GetClientInfo( Client, true ) ) )

	if self.ScheduleBotReconcile then
		self:ScheduleBotReconcile( "client disconnect", 1 )
	end
end


function Plugin:SetGameState( Gamerules, State, OldState )
	if OldState == kGameState.Started and State ~= kGameState.Started then
		self:ClearQueuePromotionTimeouts( "round ended" )
	end

	if State == kGameState.Started then
		self.ActiveMatchLeaveInfo = {}
		self.PendingLeaveAnnouncements = {}

		local Clients = Shine.GetAllClients()
		for i = 1, #Clients do
			local Client = Clients[ i ]
			if Client and not Client:GetIsVirtual() then
				local Player = Client:GetControllingPlayer()
				CacheActiveMatchLeaveInfo( self, Client, Player )
			end
		end

		Print( "%s", StringFormat( " >;> ROUNDSTART | %s | Round started. Build: %s. Map: %s.",
			Shared.GetTime(), Shared.GetBuildNumber(), Shared.GetMapName() ) )
		if self.StartRoundStartBaseAFKCheck then
			self:StartRoundStartBaseAFKCheck( Gamerules )
		end
	elseif self.StopRoundStartBaseAFKCheck then
		self:StopRoundStartBaseAFKCheck()
	end

	if State ~= kGameState.Started and self.ActiveMatchLeaveInfo then
		self.ActiveMatchLeaveInfo = nil
		self.PendingLeaveAnnouncements = nil
	end

	if self.VoteRandomEnhanceSetGameState then
		self:VoteRandomEnhanceSetGameState( Gamerules, State, OldState )
	end
end

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force )
	if not Player then return end

	local Client = Shine.GetClientForPlayer( Player )
	if not Client then return end
	if self.HandleSpectatorDrawingPostJoinTeam then
		self:HandleSpectatorDrawingPostJoinTeam( Client, NewTeam )
	end
	if NewTeam == kTeam1Index or NewTeam == kTeam2Index then
		self:CancelQueuePromotionTimeout( Client, "joined a playing team" )
	elseif NewTeam == kSpectatorIndex then
		self:CancelQueuePromotionTimeout( Client, "entered spectator" )
	end
	if IsActiveMatch() and IsPlayingTeamNumber( NewTeam ) and not IsPlayingTeamNumber( OldTeam ) then
		self:AnnounceActiveMatchJoin( Client, Player )
	end
	if IsActiveMatch() then
		CacheActiveMatchLeaveInfo( self, Client, Player )
	end

	if NewTeam == kTeamReadyRoom and IsPlayingTeamNumber( OldTeam )
	and self.PendingLeaveAnnouncements then
		local ClientId = GetLeaveAnnouncementClientKey( Client )
		local LeaveInfo = ClientId and self.PendingLeaveAnnouncements[ ClientId ]
		if ClientId then
			self.PendingLeaveAnnouncements[ ClientId ] = nil
		end

		if LeaveInfo then
			self:AnnounceActiveMatchLeave( LeaveInfo, "to ready room" )
		end
	end

	Print( "%s", StringFormat( " >;> JOINTEAM | %s | joined team %s Player %s",
		Shared.GetTime(),
		Shine:GetTeamName( NewTeam ),
		self:GetClientInfo( Client, true )
	) )

	if not Client:GetIsVirtual() and self.ScheduleBotReconcile then
		self:ScheduleBotReconcile( "join team", 1 )
	end
	-- Shine:LogString( StringFormat( ">> JOINTEAM | %s | joined team %s | Player %s",
		-- Shared.GetTime(),
		-- Shine.GetClientInfo( Client ),
		-- Shine:GetTeamName( NewTeam )
	-- ) )
end

function Plugin:CommLoginPlayer( Chair, Player )
	if not Player then return end
	local Client = Shine.GetClientForPlayer( Player )
	if IsActiveMatch() then
		CacheActiveMatchLeaveInfo( self, Client, Player )
	end

	Print( "%s", StringFormat( " >;> COMMJOIN | became %s commander %s",
		Shine:GetTeamName( Player:GetTeamNumber(), nil, true ),
		self:GetClientInfo( Client, true )
		
	) )
end

function Plugin:CommLogout( Chair )

	
	  local this = self;

	  local gameInfo = GetGameInfoEntity();
	  if (gameInfo.state ~= kGameState.Started) then return end
	  local PlayingHumans = this:CountTeamPlayers( true )
	  local ServerHumans = this:GetPopulationHumanCount()
	  if not ( PlayingHumans >= 1 and ServerHumans <= commBotHumanThreshold ) then return end

	  Shine.Timer.Simple(1 * 30, function(Timer)
		if (gameInfo.state == kGameState.Started) then
		  local Gamerules = GetGamerules()
		  if not Gamerules then return end

		  -- Add comm bots when there's 1 to 10 players
		  local CurrentPlayingHumans = this:CountTeamPlayers( true )
		  local CurrentServerHumans = this:GetPopulationHumanCount()
		  if CurrentPlayingHumans >= 1 and CurrentServerHumans <= commBotHumanThreshold and readdComBot then
			Plugin.AddCommanderBots(this,  Gamerules);
		  end
		end
	  end);

	local Commander = Chair:GetCommander()
	if not Commander then return end
	local Client = Shine.GetClientForPlayer( Commander )
	local LeaveInfo = GetCachedActiveMatchLeaveInfo( self, Client )
	if LeaveInfo then
		-- CommLogout runs before NS2 replaces the Commander entity. Preserve the
		-- team/name snapshot but ensure a later disconnect is not labelled [comm].
		LeaveInfo.IsCommander = false
	end

	Print( "%s", StringFormat( " >;> COMMLEAVE | stopped %s commanding %s",
		Shine:GetTeamName( Commander:GetTeamNumber(), nil, true ),
		self:GetClientInfo( Client, true )
	) )
end
