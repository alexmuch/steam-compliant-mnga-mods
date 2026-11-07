local Plugin = ...

local Shine = Shine
local StringFormat = string.format

local TimerName = "RoundStartBaseAFK"

local function IsPlayingTeam( TeamNumber )
	return TeamNumber == kTeam1Index or TeamNumber == kTeam2Index
end

local function GetPlayerScore( Player )
	if Player.GetScore then
		return Player:GetScore() or 0
	end
	return 0
end

local function GetPlayerDeaths( Player )
	if Player.GetDeaths then
		return Player:GetDeaths() or 0
	end
	return 0
end

local function GetPlayerLocationName( Player )
	if Player.GetLocationName then
		return Player:GetLocationName() or ""
	end
	return ""
end

local function GetResolvedPlayerLocationName( Player )
	local CachedLocationName = GetPlayerLocationName( Player )
	local OriginLocationName = ""

	-- GetLocationName() is a cached location-trigger value. Spawn/teleport paths
	-- can leave it non-empty but stale, so prefer the current physical origin.
	if GetLocationForPoint and Player.GetOrigin then
		local Location = GetLocationForPoint( Player:GetOrigin() )
		OriginLocationName = Location and Location:GetName() or ""
	end

	return OriginLocationName ~= "" and OriginLocationName or CachedLocationName,
		CachedLocationName, OriginLocationName
end

local function GetTeamBaseLocation( Gamerules, TeamNumber )
	if not Gamerules then return nil end
	if TeamNumber == kTeam1Index then
		return Gamerules.startingLocationNameTeam1
	end
	if TeamNumber == kTeam2Index then
		return Gamerules.startingLocationNameTeam2
	end
	return nil
end

local function GetClientKey( Client )
	if not Client or not Client.GetUserId then return nil end
	return Client:GetUserId()
end

local function GetConfig( self )
	return self.Config and self.Config.RoundStartBaseAFK or {}
end

local function IsDebugEnabled( self )
	return GetConfig( self ).Debug == true
end

local function DebugPrint( self, Message )
	if IsDebugEnabled( self ) then
		Print( "%s", Message )
	end
end

local function IsHumanPlayingPlayer( Player, Client )
	if not Player or not Client or Client:GetIsVirtual() then return false end

	local TeamNumber = Player:GetTeamNumber()
	if not IsPlayingTeam( TeamNumber ) then return false end

	return true
end

local function GetCommandStructureOccupantClient( Structure )
	if not Structure or not Structure.GetCommander then return nil end

	local Commander = Structure:GetCommander()
	if not Commander or Commander:GetIsVirtual() then return nil end

	return Shine.GetClientForPlayer( Commander )
end

local function IsClientInCommandStructure( Player, Client )
	if not IsHumanPlayingPlayer( Player, Client ) then return false end
	if not GetEntitiesForTeam then return Player:isa( "Commander" ) end

	local CommandStructures = GetEntitiesForTeam( "CommandStructure", Player:GetTeamNumber() )
	for i = 1, #CommandStructures do
		if GetCommandStructureOccupantClient( CommandStructures[ i ] ) == Client then
			return true
		end
	end

	return Player:isa( "Commander" )
end

local function IsEligiblePlayer( Player, Client )
	if not IsHumanPlayingPlayer( Player, Client ) then return false end

	if Player:isa( "Commander" ) or Player:isa( "Gorge" ) then return false end

	return true
end

function Plugin:StopRoundStartBaseAFKCheck()
	self:DestroyTimer( TimerName )
	self.RoundStartBaseAFK = nil
end

function Plugin:UpdateRoundStartBaseAFKTracking( Gamerules, ForceCheck )
	local State = self.RoundStartBaseAFK
	if not State then return end

	local Now = Shared.GetTime()

	for _, Player in ientitylist( Shared.GetEntitiesWithClassname( "Player" ) ) do
		local Client = Shine.GetClientForPlayer( Player )
		local ClientKey = GetClientKey( Client )

		if ClientKey and State.RoundStartClients[ ClientKey ] and IsHumanPlayingPlayer( Player, Client ) then
			local InCommandStructure = IsClientInCommandStructure( Player, Client )
			local TeamNumber = Player:GetTeamNumber()
			local LocationName, CachedLocationName, OriginLocationName = GetResolvedPlayerLocationName( Player )

			if LocationName ~= "" then
				local Record = State.Players[ ClientKey ]
				if not Record then
					Record = {
						Name = Player:GetName(),
						TeamNumber = TeamNumber,
						StartLocation = LocationName,
						ExitedStartLocation = false,
						WasInCommandStructure = InCommandStructure
					}
					State.Players[ ClientKey ] = Record

					DebugPrint( self, StringFormat(
						"[RoundStartBaseAFK] tracking %s team=%s startLocation=%s cachedLocation=%s originLocation=%s exitedStart=%s inCommandStructure=%s",
						Record.Name or "<unknown>", tostring( TeamNumber ), tostring( Record.StartLocation ),
						tostring( CachedLocationName ), tostring( OriginLocationName ),
						tostring( Record.ExitedStartLocation ), tostring( Record.WasInCommandStructure )
					) )
				else
					Record.Name = Player:GetName()
					Record.TeamNumber = TeamNumber
				end

				if InCommandStructure and Record and not Record.WasInCommandStructure then
					Record.WasInCommandStructure = true
					DebugPrint( self, StringFormat(
						"[RoundStartBaseAFK] exempting %s; occupied command structure during round-start AFK window",
						Record.Name or "<unknown>"
					) )
				end

				if Record and not Record.ExitedStartLocation and LocationName ~= Record.StartLocation then
					Record.ExitedStartLocation = true
					DebugPrint( self, StringFormat(
						"[RoundStartBaseAFK] %s exited start location %s into %s (cached=%s origin=%s)",
						Record.Name or "<unknown>", tostring( Record.StartLocation ), tostring( LocationName ),
						tostring( CachedLocationName ), tostring( OriginLocationName )
					) )
				end
			end
		end
	end

	if ForceCheck or Now >= State.CheckAt then
		self:RunRoundStartBaseAFKCheck( Gamerules )
	end
end

function Plugin:RunRoundStartBaseAFKCheck( Gamerules )
	local State = self.RoundStartBaseAFK
	if not State then return end

	local Moved = 0
	local Checked = 0
	local PlayersToMove = {}

	for _, Player in ientitylist( Shared.GetEntitiesWithClassname( "Player" ) ) do
		local Client = Shine.GetClientForPlayer( Player )
		local ClientKey = GetClientKey( Client )
		local Record = ClientKey and State.Players[ ClientKey ]

		if ClientKey and State.RoundStartClients[ ClientKey ] and Record and IsEligiblePlayer( Player, Client ) then
			Checked = Checked + 1

			local TeamNumber = Player:GetTeamNumber()
			local LocationName, CachedLocationName, OriginLocationName = GetResolvedPlayerLocationName( Player )
			local Score = GetPlayerScore( Player )
			local Deaths = GetPlayerDeaths( Player )
			local WasInCommandStructure = Record.WasInCommandStructure
				or IsClientInCommandStructure( Player, Client )

			local ShouldMove = not Record.ExitedStartLocation
				and not WasInCommandStructure
				and Record.StartLocation and Record.StartLocation ~= ""
				and LocationName == Record.StartLocation
				and Score == 0
				and Deaths == 0

			DebugPrint( self, StringFormat(
				"[RoundStartBaseAFK] check %s team=%s location=%s startLocation=%s cachedLocation=%s originLocation=%s exitedStart=%s wasInCommandStructure=%s score=%s deaths=%s move=%s",
				Player:GetName(), tostring( TeamNumber ), tostring( LocationName ), tostring( Record.StartLocation ),
				tostring( CachedLocationName ), tostring( OriginLocationName ),
				tostring( Record.ExitedStartLocation ), tostring( WasInCommandStructure ), tostring( Score ),
				tostring( Deaths ), tostring( ShouldMove )
			) )

			if ShouldMove then
				PlayersToMove[ #PlayersToMove + 1 ] = {
					Player = Player,
					Client = Client,
					Name = Player:GetName(),
					Team = Shine:GetTeamName( TeamNumber, true )
				}
			end
		end
	end

	for i = 1, #PlayersToMove do
		local Entry = PlayersToMove[ i ]
		local Player = Entry.Player
		local Client = Entry.Client

		if Player and Client and Shine:IsValidClient( Client ) and IsEligiblePlayer( Player, Client )
		and not IsClientInCommandStructure( Player, Client ) then
			Moved = Moved + 1
			local Announcement = "%s (%s) was afk at round start, moved to spec"
			if Shine.NotifyDualColour then
				Shine:NotifyDualColour( Client, 255, 80, 80, "[AFK]", 255, 255, 255,
					"Moved to spectator for not leaving the starting room." )
			else
				Shine:NotifyColour( Client, 255, 80, 80,
					"Moved to spectator for not leaving the starting room." )
			end
			local Name, Team = Entry.Name or "<unknown>", Entry.Team or "Unknown"
			MNGA_NotifyNames( nil, 255, 80, 80, Announcement, MNGA_Name( Client:GetUserId(), Name ), Team )
			DebugPrint( self, StringFormat( "[RoundStartBaseAFK] announced " .. Announcement, Name, Team ) )
			Gamerules:JoinTeam( Player, kSpectatorIndex, true, true )
		end
	end

	DebugPrint( self, StringFormat( "[RoundStartBaseAFK] completed checked=%d moved=%d", Checked, Moved ) )
	self:StopRoundStartBaseAFKCheck()
end

function Plugin:StartRoundStartBaseAFKCheck( Gamerules )
	local Config = GetConfig( self )
	if Config.Enabled == false then
		DebugPrint( self, "[RoundStartBaseAFK] disabled by config." )
		return
	end

	self:StopRoundStartBaseAFKCheck()

	local CheckTime = tonumber( Config.CheckTime ) or 40
	if CheckTime <= 0 then
		DebugPrint( self, StringFormat( "[RoundStartBaseAFK] invalid CheckTime=%s; skipping.", tostring( Config.CheckTime ) ) )
		return
	end

	local Interval = tonumber( Config.TrackInterval ) or 1
	if Interval <= 0 then
		Interval = 1
	end

	self.RoundStartBaseAFK = {
		CheckAt = Shared.GetTime() + CheckTime,
		RoundStartClients = {},
		Players = {}
	}

	local RoundStartCount = 0
	for _, Player in ientitylist( Shared.GetEntitiesWithClassname( "Player" ) ) do
		local Client = Shine.GetClientForPlayer( Player )
		local ClientKey = GetClientKey( Client )
		if ClientKey and IsHumanPlayingPlayer( Player, Client ) then
			self.RoundStartBaseAFK.RoundStartClients[ ClientKey ] = true
			RoundStartCount = RoundStartCount + 1
		end
	end

	DebugPrint( self, StringFormat(
		"[RoundStartBaseAFK] armed checkTime=%s interval=%s roundStartPlayers=%d marineBase=%s alienBase=%s",
		tostring( CheckTime ), tostring( Interval ),
		RoundStartCount,
		tostring( GetTeamBaseLocation( Gamerules, kTeam1Index ) ),
		tostring( GetTeamBaseLocation( Gamerules, kTeam2Index ) )
	) )

	self:UpdateRoundStartBaseAFKTracking( Gamerules, false )
	self:CreateTimer( TimerName, Interval, -1, function()
		local CurrentGamerules = GetGamerules()
		local GameInfo = GetGameInfoEntity and GetGameInfoEntity()
		if not CurrentGamerules or not GameInfo or GameInfo.state ~= kGameState.Started then
			DebugPrint( self, "[RoundStartBaseAFK] cancelled; game left started state before check time." )
			self:StopRoundStartBaseAFKCheck()
			return
		end

		self:UpdateRoundStartBaseAFKTracking( CurrentGamerules, false )
	end )
end

return Plugin
