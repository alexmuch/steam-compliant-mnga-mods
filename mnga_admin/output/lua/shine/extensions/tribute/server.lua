-- Tribute system for commander volunteering.

local Plugin = ...
local Shine = Shine
local StringFormat = string.format

local COMM_HISTORY_PATH = "config://shine/temp/mnga_comm_history.json"
local TRIBUTE_UNLOCK_DELAY = 180
local TRIBUTE_COUNTDOWN_DURATION = 30
local TRIBUTE_FINAL_COUNTDOWN = 5
local TRIBUTE_IMMUNITY_PREVIEW = 15
local TRIBUTE_TICKETS_PER_PLAYER = 4
-- Granted to every supporter tier through the "Server Supporter" Shine group.
local SUPPORTER_IMMUNE_PERMISSION = "mnga.tribute.immune"
local SPEC_REMINDER_DELAY_TIMER = "tribute_spec_reminder_delay"
local SPEC_REMINDER_INTERVAL_TIMER = "tribute_spec_reminder_interval"
local SPEC_REMINDER_INTERVAL = 60
local MAP_VOTE_HOOK_NAME = "TributeMapVote"
local SPEC_REMINDER_MESSAGE = "You may volunteer to be commander to skip the queue, '!tribute help' for more info"
local commHistory = {}
local currentRound = 0

Plugin.ActiveTributes = Plugin.ActiveTributes or {}
local ActiveTributes = Plugin.ActiveTributes
Plugin.CommanderMonitors = Plugin.CommanderMonitors or {}
local CommanderMonitors = Plugin.CommanderMonitors

local function Log( Message, ... )
	if Plugin.Config and Plugin.Config.EnableDebugLogs == false then return end

	local Success, Formatted = pcall( StringFormat, Message, ... )
	if not Success then
		local Parts = { tostring( Message ) }
		for i = 1, select( "#", ... ) do
			Parts[ #Parts + 1 ] = tostring( select( i, ... ) )
		end
		Formatted = table.concat( Parts, " " )
	end

	local Line = StringFormat( "[TRIBUTE] %s | %s", tostring( Shared.GetTime() ), Formatted )
	if Shared and Shared.Message then
		Shared.Message( Line )
	else
		Print( "%s", Line )
	end
end

local function GetClientInfo( Client )
	if not Client then return "Console" end
	if Shine.GetClientInfo then
		return Shine.GetClientInfo( Client )
	end

	local Player = Client:GetControllingPlayer()
	local Name = Player and Player:GetName() or "<unknown>"
	local ID = Client.GetUserId and Client:GetUserId() or 0
	return StringFormat( "[%s]%s", ID, Name )
end

local function sideName( Side )
	return Side == "marine" and "Marine" or "Alien"
end

local function sideTeamIndex( Side )
	return Side == "marine" and kTeam1Index or kTeam2Index
end

local function teamName( TeamIndex )
	if TeamIndex == kTeamReadyRoom then return "Ready Room" end
	if TeamIndex == kTeam1Index then return "Marine" end
	if TeamIndex == kTeam2Index then return "Alien" end
	if TeamIndex == kSpectatorIndex then return "Spectator" end
	return tostring( TeamIndex )
end

local TributeSideAliases = {
	marines = "marine",
	marine = "marine",
	m = "marine",
	comm = "marine",
	aliens = "alien",
	alien = "alien",
	a = "alien",
	kham = "alien",
	khamm = "alien"
}

local function normaliseSteamId( SteamID )
	local ID = tonumber( SteamID )
	return ID or SteamID
end

-- A tribute forces the volunteer into command, so honour both commander-ban
-- extensions before starting or executing a tribute.
local CommanderRestrictionPlugins = {
	{ Name = "commrestrict", Description = "comm-restricted" },
	{ Name = "commbans", Description = "comm-banned" }
}

local function getActiveCommanderRestriction( Client )
	local UserID = Client and Client.GetUserId and tostring( Client:GetUserId() )
	if not UserID then return end

	local CurrentTime = os.time()
	for i = 1, #CommanderRestrictionPlugins do
		local Restriction = CommanderRestrictionPlugins[ i ]
		local Enabled, BanPlugin = Shine:IsExtensionEnabled( Restriction.Name )
		local Banned = Enabled and BanPlugin and BanPlugin.Config and BanPlugin.Config.Banned
		local BanData = Banned and Banned[ UserID ]
		if BanData and ( BanData.UnbanTime == 0 or BanData.UnbanTime > CurrentTime ) then
			return Restriction
		end
	end
end

local function cannotUseTributeDueToCommanderRestriction( Client, Side )
	local Restriction = getActiveCommanderRestriction( Client )
	if not Restriction then return false end

	Log( "%s denied tribute for %s: active %s", GetClientInfo( Client ),
		Side and sideName( Side ) or "unknown side", Restriction.Description )
	Shine:NotifyColour( Client, 255, 112, 77,
		StringFormat( "Tribute: You cannot volunteer while you are %s from commanding.",
			Restriction.Description ) )
	return true
end

local getClientPlayer

local function getPlayerClassName( Player )
	return Player and Player.GetClassName and Player:GetClassName() or "<unknown>"
end

local TributeSelectionTeams = {
	kTeamReadyRoom,
	kTeam1Index,
	kTeam2Index
}

local function isTributeSelectionTeam( TeamIndex )
	for i = 1, #TributeSelectionTeams do
		if TributeSelectionTeams[ i ] == TeamIndex then return true end
	end
	return false
end

local function getHumanPlayersInTributePool( ExcludedClient )
	local Humans = {}
	local SeenClients = {}
	local Clients = Shine.GetAllClients and Shine.GetAllClients() or {}
	for i = 1, #Clients do
		local Client = Clients[ i ]
		local Player = getClientPlayer( Client )
		local TeamNumber = Player and Player:GetTeamNumber()
		if Player
			and Client
			and Client ~= ExcludedClient
			and not SeenClients[ Client ]
			and not Player:GetIsVirtual()
			and not Player:isa( "Commander" )
			and isTributeSelectionTeam( TeamNumber ) then

			SeenClients[ Client ] = true
			Humans[ #Humans + 1 ] = Player
			Log( "Tribute pool candidate: %s team=%s class=%s",
				Player:GetName(), teamName( TeamNumber ), getPlayerClassName( Player ) )
		elseif Player and Client then
			Log( "Tribute pool skipped: %s team=%s class=%s excluded=%s virtual=%s commander=%s",
				Player:GetName(), teamName( TeamNumber ), getPlayerClassName( Player ),
				tostring( Client == ExcludedClient ), tostring( Player:GetIsVirtual() ),
				tostring( Player:isa( "Commander" ) ) )
		end
	end
	Log( "Tribute pool contains %d eligible human player(s)", #Humans )
	return Humans
end

local function getCommandStructures( TeamIndex )
	return GetEntitiesForTeam( "CommandStructure", TeamIndex )
end

local function getHumanCommanderPlayer( TeamIndex )
	local CommandStructures = getCommandStructures( TeamIndex )
	for i = 1, #CommandStructures do
		local Structure = CommandStructures[ i ]
		local Commander = Structure and Structure:GetCommander()
		if Commander and not Commander:GetIsVirtual() then
			return Commander
		end
	end
end

local function hasHumanCommander( TeamIndex )
	return getHumanCommanderPlayer( TeamIndex ) ~= nil
end

local function isRoundStarted()
	local GameInfo = GetGameInfoEntity()
	return GameInfo and GameInfo.state >= kGameState.Started
end

local function isRoundEnded()
	local GameInfo = GetGameInfoEntity()
	return GameInfo and GameInfo.state >= kGameState.Team1Won
end

local function isMapVoteInProgress()
	local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )
	if not Enabled or not MapVote or not MapVote.VoteStarted then return false end

	local Success, Started = pcall( MapVote.VoteStarted, MapVote )
	return Success and Started and true or false
end

local function isClientSpectator( Client )
	return Client and Shine:IsValidClient( Client ) and Client:GetIsSpectator()
end

function getClientPlayer( Client )
	if not Client or not Shine:IsValidClient( Client ) then return nil end
	return Client:GetControllingPlayer()
end

local function BroadcastTribute( Message )
	Shine:NotifyColour( nil, 255, 200, 100, Message )
end

-- BroadcastTribute with MNGA_Name() arguments resolved to each viewer's SSB alias.
local function BroadcastTributeNames( Format, ... )
	MNGA_NotifyNames( nil, 255, 200, 100, Format, ... )
end

local function NotifySpectators( Message )
	local Clients = Shine.GetAllClients and Shine.GetAllClients() or {}
	local Count = 0
	for i = 1, #Clients do
		local Client = Clients[ i ]
		if Client and Shine:IsValidClient( Client ) and Client:GetIsSpectator() then
			Shine:NotifyColour( Client, 255, 200, 100, Message )
			Count = Count + 1
		end
	end

end

local function StopSpecReminder()
	Shine.Timer.Destroy( SPEC_REMINDER_DELAY_TIMER )
	Shine.Timer.Destroy( SPEC_REMINDER_INTERVAL_TIMER )
end

local function StartSpecReminder()
	StopSpecReminder()

	Shine.Timer.Create( SPEC_REMINDER_DELAY_TIMER, TRIBUTE_UNLOCK_DELAY, 1, function()
		if isRoundStarted() then
			Log( "Spec reminder skipped because game already started" )
			return
		end

		NotifySpectators( SPEC_REMINDER_MESSAGE )
		Shine.Timer.Create( SPEC_REMINDER_INTERVAL_TIMER, SPEC_REMINDER_INTERVAL, -1, function()
			if isRoundStarted() then
				Log( "Spec reminder stopped because game started" )
				StopSpecReminder()
				return
			end

			NotifySpectators( SPEC_REMINDER_MESSAGE )
		end )
	end )
end

local function EnqueueSpectatorForPlayerSlot( RRQueue, Client )
	if not RRQueue or not Client or not Shine:IsValidClient( Client ) then return end
	if not Client:GetIsSpectator() then return end

	if RRQueue.Enqueue then
		RRQueue:Enqueue( Client )
	end
end

local function DestroyTributeTimers( Side, Tribute )
	if not Tribute then return end

	if Tribute.countdownTimer then
		Tribute.countdownTimer:Destroy()
		Tribute.countdownTimer = nil
	end
	if Tribute.kickTimer then
		Tribute.kickTimer:Destroy()
		Tribute.kickTimer = nil
	end
	if Tribute.immunityTimer then
		Tribute.immunityTimer:Destroy()
		Tribute.immunityTimer = nil
	end

	Shine.Timer.Destroy( "tribute_interval_" .. Side )
	Shine.Timer.Destroy( "tribute_finalcount_" .. Side )

	Tribute.intervalTimer = nil
end

local function ClearTribute( Side, Reason, NotifyClient )
	local Tribute = ActiveTributes[ Side ]
	if not Tribute then return end

	DestroyTributeTimers( Side, Tribute )
	ActiveTributes[ Side ] = nil
	Log( "Tribute for %s cleared: %s", Side, Reason or "unknown" )

	if NotifyClient and Tribute.client and Shine:IsValidClient( Tribute.client ) then
		Shine:NotifyColour( Tribute.client, 255, 150, 50, StringFormat(
			"Tribute cancelled: %s", Reason or "unknown"
		) )
	end
end

local function StopCountdownTimers( Side, Tribute )
	if Tribute and Tribute.countdownTimer then
		Tribute.countdownTimer:Destroy()
		Tribute.countdownTimer = nil
	end
	if Tribute and Tribute.immunityTimer then
		Tribute.immunityTimer:Destroy()
		Tribute.immunityTimer = nil
	end
	Shine.Timer.Destroy( "tribute_interval_" .. Side )
	Shine.Timer.Destroy( "tribute_finalcount_" .. Side )
	if Tribute then
		Tribute.intervalTimer = nil
	end
end

local function ConvertKeysToNumbers( Table )
	local New = {}
	for Key, Value in pairs( Table ) do
		local Num = tonumber( Key )
		New[ Num or Key ] = Value
	end
	return New
end

function Plugin.LoadCommHistory()
	local Data = Shine.LoadJSONFile( COMM_HISTORY_PATH )
	if type( Data ) == "table" then
		if type( Data.commHistory ) == "table" then
			commHistory = ConvertKeysToNumbers( Data.commHistory )
		end
		if type( Data.currentRound ) == "number" then
			currentRound = Data.currentRound
		end
	end

	Log( "Loaded comm history: round=%d, entries=%d", currentRound, table.Count( commHistory ) )
end

function Plugin.SaveCommHistory()
	local Data = {
		commHistory = commHistory,
		currentRound = currentRound
	}
	local Success, Err = Shine.SaveJSONFile( Data, COMM_HISTORY_PATH )
	if not Success then
		Log( "Failed to save comm history: %s", tostring( Err ) )
		return
	end
	Log( "Saved comm history: round=%d, entries=%d", currentRound, table.Count( commHistory ) )
end

function Plugin.RecordCommsAtRoundEnd( Gamerules )
	if not Gamerules or not Gamerules.gameStartTime then return end

	local HumanCount = Shine.GetHumanPlayerCount()
	if HumanCount < 16 then
		Log( "Skipping comm record: only %d players (< 16)", HumanCount )
		return
	end

	currentRound = currentRound + 1

	Shine.Timer.Simple( 1.5, function()
		local Stats = CHUDGetLastRoundStats()
		if not Stats or not Stats.PlayerStats then
			Log( "No stats available for comm recording" )
			Plugin.SaveCommHistory()
			return
		end

		local function GetTopCommander( PlayerStats, TeamNumber )
			local TopSteamId, TopTime
			TopTime = 0

			for SteamId, Stat in pairs( PlayerStats ) do
				local Entry = type( SteamId ) == "number" and Stat[ TeamNumber ]
				if Entry and Entry.commanderTime and Entry.commanderTime > TopTime then
					TopTime = Entry.commanderTime
					TopSteamId = SteamId
				end
			end

			return TopSteamId and TopTime > 0 and normaliseSteamId( TopSteamId ) or nil
		end

		local MarineSid = GetTopCommander( Stats.PlayerStats, 1 )
		local AlienSid = GetTopCommander( Stats.PlayerStats, 2 )

		if not MarineSid then
			local MarineComm = getHumanCommanderPlayer( kTeam1Index )
			local Client = MarineComm and Shine.GetClientForPlayer( MarineComm )
			MarineSid = Client and normaliseSteamId( Client:GetUserId() ) or nil
		end
		if not AlienSid then
			local AlienComm = getHumanCommanderPlayer( kTeam2Index )
			local Client = AlienComm and Shine.GetClientForPlayer( AlienComm )
			AlienSid = Client and normaliseSteamId( Client:GetUserId() ) or nil
		end

		if MarineSid then
			commHistory[ MarineSid ] = currentRound
			Log( "Recorded marine comm: %s at round %d", tostring( MarineSid ), currentRound )
		end
		if AlienSid then
			commHistory[ AlienSid ] = currentRound
			Log( "Recorded alien comm: %s at round %d", tostring( AlienSid ), currentRound )
		end

		Plugin.SaveCommHistory()
	end )
end

function Plugin.GetImmunity( SteamID )
	local LastCommed = commHistory[ normaliseSteamId( SteamID ) ]
	if not LastCommed then return 0 end

	local RoundsAgo = currentRound - LastCommed
	if RoundsAgo <= 10 then return 1 end
	if RoundsAgo <= 20 then return 0.75 end
	if RoundsAgo <= 30 then return 0.5 end
	if RoundsAgo <= 40 then return 0.25 end
	return 0
end

function Plugin.GetImmunityInfo( SteamID )
	local LastCommed = commHistory[ normaliseSteamId( SteamID ) ]
	if not LastCommed then return "no immunity (never commed)" end

	local RoundsAgo = currentRound - LastCommed
	local Percent
	if RoundsAgo <= 10 then
		Percent = "100%"
	elseif RoundsAgo <= 20 then
		Percent = "75%"
	elseif RoundsAgo <= 30 then
		Percent = "50%"
	elseif RoundsAgo <= 40 then
		Percent = "25%"
	else
		return "no immunity (commed >40 rounds ago)"
	end

	return StringFormat( "%s immune (commed %d round(s) ago)", Percent, RoundsAgo + 1 )
end

-- Supporters (any tier) are always 100% immune, regardless of comm history.
function Plugin.IsSupporterImmune( Client )
	if not Client then return false end
	local Ok, Result = pcall( Shine.HasAccess, Shine, Client, SUPPORTER_IMMUNE_PERMISSION )
	if not Ok then
		Log( "[tributesupporter] HasAccess failed for %s: %s", tostring( Client:GetUserId() ), tostring( Result ) )
		return false
	end
	return Result and true or false
end

function Plugin.GetClientImmunity( Client )
	if Plugin.IsSupporterImmune( Client ) then return 1 end
	return Plugin.GetImmunity( Client:GetUserId() )
end

function Plugin.GetClientImmunityInfo( Client )
	if Plugin.IsSupporterImmune( Client ) then
		return "100% immune (server supporter)"
	end
	return Plugin.GetImmunityInfo( Client:GetUserId() )
end

local function GetSwapImmunityInfo( SteamID )
	local ImmunityPercent = math.floor( Plugin.GetImmunity( SteamID ) * 100 + 0.5 )
	local LastCommed = commHistory[ normaliseSteamId( SteamID ) ]
	if not LastCommed then
		return StringFormat( "%d%% immunity, commed unknown", ImmunityPercent )
	end

	local RoundsAgo = currentRound - LastCommed + 1
	return StringFormat( "%d%% immunity, commed %d rounds ago", ImmunityPercent, RoundsAgo )
end

-- Each pool player gets TRIBUTE_TICKETS_PER_PLAYER numbers, minus one per 25%
-- immunity (0% = 4, 50% = 2, 100% = 0). This is the same distribution as
-- weighting by 1 - immunity, but players can see their numbers and the roll.
local function getTicketCount( Immunity )
	return math.max( 0, math.floor( ( 1 - Immunity ) * TRIBUTE_TICKETS_PER_PLAYER + 0.5 ) )
end

-- Returns the selected player and client plus the draw details:
-- { entries = { { client, player, immunity, tickets, first, last } }, total, roll }.
-- Entries include 0-ticket (100% immune) players so they can be told why they are safe.
function Plugin.SelectRandomPlayer( ExcludedClient )
	local Players = getHumanPlayersInTributePool( ExcludedClient )
	local Draw = { entries = {}, total = 0 }

	for i = 1, #Players do
		local Player = Players[ i ]
		local Client = Shine.GetClientForPlayer( Player )
		if Client then
			local Immunity = Plugin.GetClientImmunity( Client )
			if Immunity >= 1 and Plugin.IsSupporterImmune( Client ) then
				Log( "[tributesupporter] %s userid=%s immune as supporter", Player:GetName(), tostring( Client:GetUserId() ) )
			end
			local Tickets = getTicketCount( Immunity )
			local Entry = {
				player = Player,
				client = Client,
				immunity = Immunity,
				tickets = Tickets,
				team = Player:GetTeamNumber()
			}
			if Tickets > 0 then
				Entry.first = Draw.total + 1
				Entry.last = Draw.total + Tickets
				Draw.total = Entry.last
			end
			Draw.entries[ #Draw.entries + 1 ] = Entry
			Log( "Tribute draw candidate %s userid=%s immunity=%.2f tickets=%d numbers=%s",
				Player:GetName(), tostring( Client:GetUserId() ), Immunity, Tickets,
				Tickets > 0 and StringFormat( "%d-%d", Entry.first, Entry.last ) or "none" )
		end
	end

	if Draw.total == 0 then
		Log( "No eligible players in ready room/team tribute pool (total tickets 0)" )
		return nil, nil, Draw
	end

	Draw.roll = math.random( 1, Draw.total )
	Log( "Tribute draw: %d candidate(s), %d ticket(s), lucky number %d",
		#Draw.entries, Draw.total, Draw.roll )

	for i = 1, #Draw.entries do
		local Entry = Draw.entries[ i ]
		if Entry.tickets > 0 and Draw.roll >= Entry.first and Draw.roll <= Entry.last then
			Log( "Selected tribute target %s from %s immunity=%s numbers=%d-%d",
				Entry.player:GetName(), teamName( Entry.team ),
				tostring( Entry.immunity ), Entry.first, Entry.last )
			return Entry.player, Entry.client, Draw
		end
	end

	Log( "Tribute draw roll %d matched no entry (should not happen)", Draw.roll )
	return nil, nil, Draw
end

-- Line 1 of the draw feedback: each pool player privately sees their own numbers.
local function NotifyDrawNumbers( Draw )
	if not Draw then return end

	for i = 1, #Draw.entries do
		local Entry = Draw.entries[ i ]
		if Entry.client and Shine:IsValidClient( Entry.client ) then
			local Message
			if Entry.tickets > 1 then
				Message = StringFormat( "Tribute: Your numbers are %d-%d.", Entry.first, Entry.last )
			elseif Entry.tickets == 1 then
				Message = StringFormat( "Tribute: Your number is %d.", Entry.first )
			else
				Message = "Tribute: You are immune."
			end
			Shine:NotifyColour( Entry.client, 255, 200, 100, Message )
		end
	end
end

-- 15 seconds before the draw, tell every current pool player their immunity and
-- how many numbers it gives them. The pool is re-read at the draw itself.
local function NotifyPoolImmunity( Side, Tribute )
	local Players = getHumanPlayersInTributePool( Tribute.client )
	Log( "Sending %s tribute immunity preview to %d pool player(s)", Side, #Players )

	for i = 1, #Players do
		local Client = Shine.GetClientForPlayer( Players[ i ] )
		if Client and Shine:IsValidClient( Client ) then
			Shine:NotifyColour( Client, 255, 200, 100,
				"Comm Immunity: " .. Plugin.GetClientImmunityInfo( Client ) )
		end
	end
end

local function tryForceCommander( Player, TeamIndex )
	if not Player or Player:GetTeamNumber() ~= TeamIndex then return false end

	local CommandStructures = getCommandStructures( TeamIndex )
	for i = 1, #CommandStructures do
		local Structure = CommandStructures[ i ]
		local Destroyed = Structure and Structure.GetIsDestroyed and Structure:GetIsDestroyed()
		if Structure and not Destroyed and not Structure:GetCommander() then
			if Structure.GetIsBuilt and not Structure:GetIsBuilt() then
				Log( "Skipping unbuilt command structure for %s", Player:GetName() )
			else
				if Structure.GetDefaultEntryOrigin then
					Player:SetOrigin( Structure:GetDefaultEntryOrigin() )
				end
				Structure.occupied = true

				Log( "Attempting to force %s into %s command", Player:GetName(), sideName( TeamIndex == kTeam1Index and "marine" or "alien" ) )
				local Commander = Structure:LoginPlayer( Player, true )
				if Commander and Commander:isa( "Commander" ) then
					return true, Commander
				end
				if Structure:GetCommander() and not Structure:GetCommander():GetIsVirtual() then
					return true, Structure:GetCommander()
				end
			end
		end
	end

	return false
end

local function ClearCommanderMonitor( Side, Reason )
	local Monitor = CommanderMonitors[ Side ]
	if not Monitor then return end

	Shine.Timer.Destroy( "tribute_chairmonitor_" .. Side )
	CommanderMonitors[ Side ] = nil
	Log( "Commander monitor for %s cleared: %s", Side, Reason or "unknown" )
end

local function StartChairMonitor( Side, CommanderClient, Mode )
	if not CommanderClient or not Shine:IsValidClient( CommanderClient ) then return end
	if Mode == "tribute_commander" then
		ClearTribute( Side, "tribute commander seated", false )
	end

	ClearCommanderMonitor( Side, "replaced" )

	local Monitor = {
		client = CommanderClient,
		mode = Mode or "cancel_commander"
	}
	CommanderMonitors[ Side ] = Monitor

	local Player = getClientPlayer( CommanderClient )
	local CommanderName = Player and Player:GetName() or "<unknown>"
	Log( "Monitoring %s as %s commander until round start, mode=%s",
		CommanderName, sideName( Side ), Monitor.mode )

	Monitor.timer = Shine.Timer.Create( "tribute_chairmonitor_" .. Side, 1, -1, function()
		if CommanderMonitors[ Side ] ~= Monitor then return end

		if isRoundStarted() then
			Log( "Round started, ending chair monitor for %s", Side )
			ClearCommanderMonitor( Side, "round started" )
			return
		end

		if not CommanderClient or not Shine:IsValidClient( CommanderClient ) then
			Log( "Monitored commander disconnected before round start for %s", Side )
			ClearCommanderMonitor( Side, "monitored commander disconnected" )
			return
		end

		local CommanderPlayer = CommanderClient:GetControllingPlayer()
		local TeamIndex = sideTeamIndex( Side )
		if CommanderPlayer and CommanderPlayer:isa( "Commander" ) and CommanderPlayer:GetTeamNumber() == TeamIndex then
			return
		end

		local Name = CommanderPlayer and CommanderPlayer:GetName() or CommanderName
		if Monitor.mode == "tribute_commander" then
			Log( "%s left %s command after tribute swap, kicking", Name, sideName( Side ) )
			BroadcastTributeNames( "%s left %s commander before round start after tribute - kicked!",
				MNGA_Name( CommanderClient:GetUserId(), Name ), sideName( Side ) )
			Server.DisconnectClient( CommanderClient,
				StringFormat( "Left %s commander before round start after tribute.", sideName( Side ) ) )
		else
			Log( "%s left %s command after cancelling tribute, forcing spec", Name, sideName( Side ) )
			BroadcastTributeNames( "%s left %s commander after cancelling tribute - forced to spec!",
				MNGA_Name( CommanderClient:GetUserId(), Name ), sideName( Side ) )
			local Gamerules = GetGamerules()
			if Gamerules and CommanderPlayer then
				Gamerules:JoinTeam( CommanderPlayer, kSpectatorIndex, true, true )
			end
		end

		ClearCommanderMonitor( Side, "monitored commander left chair" )
	end )
end

local function CancelCountdownForCommander( Side, CommanderClient, CommanderName )
	local Tribute = ActiveTributes[ Side ]
	if not Tribute then return end

	local Name = CommanderName or "A player"
	BroadcastTributeNames(
		"%s has cancelled tribute by comming %s, leaving the chair/hive = force spec",
		MNGA_Name( CommanderClient and CommanderClient:GetUserId() or 0, Name ), sideName( Side )
	)
	ClearTribute( Side, "commander took chair", true )
	StartChairMonitor( Side, CommanderClient, "cancel_commander" )
end

local ExecuteTribute

local function CheckCountdownStillValid( Side )
	local Tribute = ActiveTributes[ Side ]
	if not Tribute then return false end

	local TeamIndex = sideTeamIndex( Side )
	local Commander = getHumanCommanderPlayer( TeamIndex )
	if Commander then
		CancelCountdownForCommander( Side, Shine.GetClientForPlayer( Commander ), Commander:GetName() )
		return false
	end

	-- Leaving spectator is only a cancellation while the volunteer is waiting.
	-- ExecuteTribute intentionally moves them to the requested playing team before
	-- force-login, so applying this check during that handoff cancels valid tributes.
	if Tribute.stage == "counting" and not isClientSpectator( Tribute.client ) then
		Log( "Countdown validation found %s outside spectator during counting stage", Tribute.playerName )
		BroadcastTribute( "Tribute cancelled" )
		ClearTribute( Side, "tributer left spectator", true )
		return false
	end

	return true
end

local function StartTributeCountdown( Client, Side )
	local Player = Client:GetControllingPlayer()
	local PlayerName = Player and Player:GetName() or "<unknown>"
	local SideName = sideName( Side )

	local Tribute = {
		client = Client,
		playerName = PlayerName,
		steamId = Client:GetUserId(),
		side = Side,
		startTime = Shared.GetTime(),
		stage = "counting"
	}
	ActiveTributes[ Side ] = Tribute

	BroadcastTributeNames(
		"%s has volunteered as tribute to be %s commander!", MNGA_Name( Tribute.steamId, PlayerName ), SideName
	)
	BroadcastTribute( StringFormat(
		"If %s has no commander in 30 seconds, a player will be moved to spec, !tribute info to check immunity, !tribute help for more info",
		SideName
	) )

	local IntervalCount = 0
	Tribute.intervalTimer = Shine.Timer.Create( "tribute_interval_" .. Side, 10, -1, function()
		local Active = ActiveTributes[ Side ]
		if not Active then
			Shine.Timer.Destroy( "tribute_interval_" .. Side )
			return
		end
		if not CheckCountdownStillValid( Side ) then return end

		IntervalCount = IntervalCount + 1
		local Remaining = TRIBUTE_COUNTDOWN_DURATION - IntervalCount * 10
		if Remaining > TRIBUTE_FINAL_COUNTDOWN then
			Log( "Announcing nominal tribute countdown for %s: %d seconds", Side, Remaining )
			BroadcastTributeNames( "%s tribute countdown: %d seconds", MNGA_Name( Active.steamId or 0, Active.playerName ), Remaining )
		end
	end )

	Tribute.immunityTimer = Shine.Timer.Simple( TRIBUTE_COUNTDOWN_DURATION - TRIBUTE_IMMUNITY_PREVIEW, function()
		Tribute.immunityTimer = nil
		if ActiveTributes[ Side ] ~= Tribute then return end
		if not CheckCountdownStillValid( Side ) then return end
		NotifyPoolImmunity( Side, Tribute )
	end )

	Tribute.countdownTimer = Shine.Timer.Simple( TRIBUTE_COUNTDOWN_DURATION - TRIBUTE_FINAL_COUNTDOWN, function()
		if not CheckCountdownStillValid( Side ) then return end

		Shine.Timer.Destroy( "tribute_interval_" .. Side )
		local FinalCount = TRIBUTE_FINAL_COUNTDOWN
		local Active = ActiveTributes[ Side ]
		Log( "Announcing nominal tribute countdown for %s: %d seconds", Side, FinalCount )
		BroadcastTributeNames( "%s tribute countdown: %d seconds", MNGA_Name( Active.steamId or 0, Active.playerName ), FinalCount )
		FinalCount = FinalCount - 1

		Shine.Timer.Create( "tribute_finalcount_" .. Side, 1, TRIBUTE_FINAL_COUNTDOWN, function()
			Active = ActiveTributes[ Side ]
			if not Active then
				Shine.Timer.Destroy( "tribute_finalcount_" .. Side )
				return
			end
			if not CheckCountdownStillValid( Side ) then return end

			if FinalCount > 0 then
				Log( "Announcing nominal tribute countdown for %s: %d seconds", Side, FinalCount )
				BroadcastTributeNames( "%s tribute countdown: %d seconds", MNGA_Name( Active.steamId or 0, Active.playerName ), FinalCount )
				FinalCount = FinalCount - 1
				return
			end

			Shine.Timer.Destroy( "tribute_finalcount_" .. Side )
			Log( "Final countdown reached 0 for %s, executing tribute", Side )
			local Success, Err = xpcall( function()
				ExecuteTribute( Side )
			end, debug.traceback )
			if not Success then
				Log( "ExecuteTribute error for %s: %s", Side, tostring( Err ) )
			end
		end )
	end )
end

ExecuteTribute = function( Side )
	local Tribute = ActiveTributes[ Side ]
	if not Tribute then return end
	Log( "ExecuteTribute start for %s stage=%s tributer=%s", Side, tostring( Tribute.stage ), tostring( Tribute.playerName ) )
	if not CheckCountdownStillValid( Side ) then return end

	local Client = Tribute.client
	if cannotUseTributeDueToCommanderRestriction( Client, Side ) then
		ClearTribute( Side, "tributer has an active commander restriction", false )
		return
	end

	local TeamIndex = sideTeamIndex( Side )
	local SideName = sideName( Side )
	local Gamerules = GetGamerules()
	if not Gamerules then
		ClearTribute( Side, "no gamerules", true )
		return
	end

	local SelectedPlayer, SelectedClient, Draw = Plugin.SelectRandomPlayer( Client )
	if not SelectedPlayer or not SelectedClient then
		if Draw and #Draw.entries > 0 then
			NotifyDrawNumbers( Draw )
		end
		if Client and Shine:IsValidClient( Client ) then
			Shine:NotifyColour( Client, 255, 80, 80,
				"Tribute failed: No eligible ready room or team players to swap." )
		end
		ClearTribute( Side, "no valid target", true )
		return
	end

	local SelectedTeam = SelectedPlayer:GetTeamNumber()
	local SelectedImmunityInfo = GetSwapImmunityInfo( SelectedClient:GetUserId() )
	Log( "Executing tribute for %s: %s swaps with %s",
		Side, Tribute.playerName, SelectedPlayer:GetName() )
	NotifyDrawNumbers( Draw )
	BroadcastTribute( StringFormat( "Tribute: System picks lucky number %d (out of 1-%d)",
		Draw.roll, Draw.total ) )
	BroadcastTributeNames( "Tribute: Swapping %s with %s (%s)",
		MNGA_Name( Tribute.steamId or 0, Tribute.playerName ), MNGA_Name( SelectedClient:GetUserId(), SelectedPlayer:GetName() ),
		SelectedImmunityInfo )

	local RRQueue = Shine.Plugins and Shine.Plugins[ "mngareadyroomqueue" ]
	if RRQueue and RRQueue.BeginTransaction then RRQueue:BeginTransaction( "tribute:"..Side ) end

	Log( "Moving selected player %s from %s to Spectator", SelectedPlayer:GetName(), teamName( SelectedTeam ) )
	local SelectedSuccess, NewSelectedPlayer = Gamerules:JoinTeam( SelectedPlayer, kSpectatorIndex, true )
	Log( "Selected player spectator move success=%s newPlayer=%s newTeam=%s",
		tostring( SelectedSuccess ), tostring( NewSelectedPlayer ),
		NewSelectedPlayer and teamName( NewSelectedPlayer:GetTeamNumber() ) or "nil" )
	if not SelectedSuccess then
		if RRQueue and RRQueue.EndTransaction then RRQueue:EndTransaction( "tribute_failed:"..Side ) end
		ClearTribute( Side, "selected player failed to move spectator", true )
		return
	end
	EnqueueSpectatorForPlayerSlot( RRQueue, SelectedClient )

	local TributerPlayer = getClientPlayer( Client )
	if not TributerPlayer then
		if RRQueue and RRQueue.EndTransaction then RRQueue:EndTransaction( "tribute_lost:"..Side ) end
		ClearTribute( Side, "tributer lost during swap", true )
		return
	end

	-- Set this before JoinTeam(), because PostJoinTeam fires synchronously from the
	-- intentional move and must not mistake it for the volunteer abandoning tribute.
	Tribute.stage = "force_join"
	Log( "Tribute %s entering force_join stage before intentional team move", Tribute.playerName )
	Log( "Moving tributer %s from %s to %s", TributerPlayer:GetName(), teamName( TributerPlayer:GetTeamNumber() ), SideName )
	local TributeJoinSuccess, NewTributerPlayer = Gamerules:JoinTeam( TributerPlayer, TeamIndex, true )
	Log( "Tributer team move success=%s newPlayer=%s newTeam=%s",
		tostring( TributeJoinSuccess ), tostring( NewTributerPlayer ),
		NewTributerPlayer and teamName( NewTributerPlayer:GetTeamNumber() ) or "nil" )
	if RRQueue and RRQueue.EndTransaction then RRQueue:EndTransaction( "tribute:"..Side ) end
	if RRQueue and RRQueue.Dequeue then
		RRQueue:Dequeue( Client )
	end

	if not TributeJoinSuccess then
		ClearTribute( Side, "tributer failed to join team", true )
		return
	end

	Shine.Timer.Simple( 0.1, function()
		local Active = ActiveTributes[ Side ]
		if not Active then return end

		local CurrentPlayer = NewTributerPlayer or getClientPlayer( Client )
		local Forced, Commander = tryForceCommander( CurrentPlayer, TeamIndex )
		if Forced then
			Log( "Forced %s into %s command", Active.playerName, SideName )
			StartChairMonitor( Side, Client, "tribute_commander" )
			return
		end

		Shine:NotifyColour( Client, 255, 200, 100,
			StringFormat( "Join %s commander in 10 seconds or be kicked!", SideName ) )
		Log( "Could not force %s into %s command, starting kick timer", Active.playerName, SideName )

		Active.kickTimer = Shine.Timer.Simple( 10, function()
			local StillActive = ActiveTributes[ Side ]
			if not StillActive or not Client or not Shine:IsValidClient( Client ) then return end

			local CommanderPlayer = getHumanCommanderPlayer( TeamIndex )
			if CommanderPlayer then
				local CommanderClient = Shine.GetClientForPlayer( CommanderPlayer )
				if CommanderClient == Client then
					StartChairMonitor( Side, Client, "tribute_commander" )
				else
					CancelCountdownForCommander( Side, CommanderClient, CommanderPlayer:GetName() )
				end
				return
			end

			Log( "Kicking %s for not joining %s command", StillActive.playerName, SideName )
			Server.DisconnectClient( Client,
				StringFormat( "Did not join %s commander in time after tribute.", SideName ) )
			ClearTribute( Side, "tributer failed to command", false )
		end )
	end )
end

function Plugin.HandleTributeCommand( Client, Subcommand )
	if not Client or not Shine:IsValidClient( Client ) then return end

	local Player = Client:GetControllingPlayer()
	if not Player then return end

	Subcommand = string.lower( Subcommand or "help" )

	if Subcommand == "help" then
		Shine:NotifyColour( Client, 255, 200, 100,
			"Tribute system: 4 mins after mapchange, a spectator may tribute themself as a commander for either side if that commander position is empty. A 30-second countdown begins, and at the end of it, if that side has no commander, a random player will be swapped with the spectator.\n\n" ..
			"Immunity: Commed once in last\n" ..
			"\t10 rounds - 100% immune.\n" ..
			"\t20 rounds - 75% immune\n" ..
			"\t30 rounds - 50% immune\n" ..
			"\t40 rounds - 25% immune\n" ..
			"\tServer supporters - always 100% immune\n\n" ..
			"Draw: 15 seconds before the swap, each ready room/team player is told their immunity. Each player gets 4 numbers, minus 1 per 25% immunity, and the system picks one lucky number to decide who is moved to spec.\n\n" ..
			"Commands: !tribute marines / m, !tribute aliens / a, !tribute info, !tribute help\n\n" ..
			"Attempting to cancel tribute unfairly by entering+leaving chair will result in being forced to spec." )
		return
	end

	if Subcommand == "info" then
		Shine:NotifyColour( Client, 255, 200, 100,
			"Comm Immunity: " .. Plugin.GetClientImmunityInfo( Client ) )
		return
	end

	local Side = TributeSideAliases[ Subcommand ]
	if not Side then
		Shine:NotifyColour( Client, 255, 112, 77,
			"Usage: !tribute marines, !tribute aliens, !tribute info, or !tribute help" )
		return
	end

	local TeamIndex = sideTeamIndex( Side )
	local SideName = sideName( Side )

	if cannotUseTributeDueToCommanderRestriction( Client, Side ) then return end

	if not Client:GetIsSpectator() then
		Shine:NotifyColour( Client, 255, 112, 77,
			"Tribute: You must be in spectator to volunteer as tribute." )
		return
	end

	local TimeSinceMapChange = Shared.GetTime() - ( Plugin.MapChangeTime or 0 )
	if TimeSinceMapChange < TRIBUTE_UNLOCK_DELAY then
		Shine:NotifyColour( Client, 255, 112, 77,
			StringFormat( "Tribute: Please wait %d more seconds. Tribute is available 3 minutes after map change.",
				math.ceil( TRIBUTE_UNLOCK_DELAY - TimeSinceMapChange ) ) )
		return
	end

	if isRoundStarted() then
		Shine:NotifyColour( Client, 255, 112, 77,
			"Tribute: Cannot use tribute while a round is in progress." )
		return
	end

	if isRoundEnded() then
		Shine:NotifyColour( Client, 255, 112, 77,
			"Tribute: Cannot use tribute after round end." )
		return
	end

	if isMapVoteInProgress() then
		Log( "%s denied tribute for %s: map vote in progress", GetClientInfo( Client ), SideName )
		Shine:NotifyColour( Client, 255, 112, 77,
			"Tribute: Cannot use tribute while a map vote is in progress." )
		return
	end

	if hasHumanCommander( TeamIndex ) then
		Shine:NotifyColour( Client, 255, 112, 77,
			StringFormat( "Tribute: %s already has a human commander.", SideName ) )
		return
	end

	if ActiveTributes[ Side ] then
		Shine:NotifyColour( Client, 255, 112, 77,
			StringFormat( "Tribute: A tribute is already active for %s.", SideName ) )
		return
	end

	for _, Tribute in pairs( ActiveTributes ) do
		if Tribute.client == Client then
			Shine:NotifyColour( Client, 255, 112, 77,
				"You are already volunteering as tribute." )
			return
		end
	end

	Log( "%s started tribute for %s", GetClientInfo( Client ), SideName )
	StartTributeCountdown( Client, Side )
end

function Plugin.Tribute_CommLoginPlayer( Chair, Player )
	if not Player or Player:GetIsVirtual() then return end

	local TeamIndex = Player:GetTeamNumber()
	if TeamIndex ~= kTeam1Index and TeamIndex ~= kTeam2Index then return end

	local Side = TeamIndex == kTeam1Index and "marine" or "alien"
	local Tribute = ActiveTributes[ Side ]
	if not Tribute then return end

	local CommanderClient = Shine.GetClientForPlayer( Player )
	if not CommanderClient then return end

	Log( "%s became %s commander during tribute stage %s",
		Player:GetName(), sideName( Side ), tostring( Tribute.stage ) )

	if Tribute.stage == "force_join" and CommanderClient == Tribute.client then
		StartChairMonitor( Side, CommanderClient, "tribute_commander" )
		return
	end

	if Tribute.stage == "counting" or Tribute.stage == "force_join" then
		CancelCountdownForCommander( Side, CommanderClient, Player:GetName() )
	end
end

function Plugin.Tribute_PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force )
	if not Player or Player:GetIsVirtual() then return end

	local Client = Shine.GetClientForPlayer( Player )
	if not Client then return end

	for Side, Tribute in pairs( ActiveTributes ) do
		if Tribute.client == Client and Tribute.stage == "counting" and NewTeam ~= kSpectatorIndex then
			Log( "%s left spectator during tribute for %s", Tribute.playerName, Side )
			BroadcastTribute( "Tribute cancelled" )
			ClearTribute( Side, "tributer left spectator", true )
		elseif Tribute.client == Client and Tribute.stage == "force_join" then
			Log( "Ignoring tributer PostJoinTeam cancellation during force_join for %s: %s -> %s",
				Side, teamName( OldTeam ), teamName( NewTeam ) )
		end
	end
end

function Plugin.Tribute_OnVoteToEjectCommander( Team, VotingPlayer, TargetCommander )
	if not Team or not VotingPlayer or not TargetCommander or isRoundStarted() then return end

	local TeamIndex = TargetCommander:GetTeamNumber()
	local Side = TeamIndex == kTeam1Index and "marine"
		or TeamIndex == kTeam2Index and "alien"
	if not Side then return end

	local Monitor = CommanderMonitors[ Side ]
	if not Monitor or Monitor.mode ~= "tribute_commander" then return end

	local TargetClient = Shine.GetClientForPlayer( TargetCommander )
	if not TargetClient or TargetClient ~= Monitor.client then return end

	-- Shine's OnVoteToEjectCommander hook is PassivePost, so the vote has already
	-- been recorded. Reset it synchronously before PlayingTeam:UpdateVotes() can
	-- observe a passed vote and eject the protected tribute commander.
	if Team.ejectCommVoteManager then
		Team.ejectCommVoteManager:Reset()
	end

	local VotingClient = Shine.GetClientForPlayer( VotingPlayer )
	if VotingClient and Shine:IsValidClient( VotingClient ) then
		Shine:NotifyColour( VotingClient, 255, 150, 50,
			"Tribute: A successful tribute commander cannot be ejected before the game starts." )
	end

	Log( "Blocked pregame eject vote from %s against successful tribute commander %s on %s",
		GetClientInfo( VotingClient ), TargetCommander:GetName(), sideName( Side ) )
end

-- A map vote means the map is likely about to change, so a pending tribute
-- would swap players for nothing. Cancel every active tribute, including one in
-- force_join, so the tributer is not kicked for failing to command.
function Plugin.Tribute_OnMapVoteStarted()
	for Side, Tribute in pairs( ActiveTributes ) do
		Log( "Map vote started during tribute for %s (stage %s, tributer %s)",
			Side, tostring( Tribute.stage ), tostring( Tribute.playerName ) )
		if Tribute.stage == "counting" then
			BroadcastTribute( StringFormat( "%s tribute cancelled: map vote started", sideName( Side ) ) )
		end
		ClearTribute( Side, "map vote started", true )
	end
end

function Plugin.Tribute_ClientDisconnect( Client )
	if not Client then return end

	for Side, Tribute in pairs( ActiveTributes ) do
		if Tribute.client == Client then
			Log( "%s disconnected during tribute for %s", Tribute.playerName, Side )
			if Tribute.stage == "counting" then
				BroadcastTribute( "Tribute cancelled" )
			end
			ClearTribute( Side, "tributer disconnected", false )
		end
	end

	for Side, Monitor in pairs( CommanderMonitors ) do
		if Monitor.client == Client then
			Log( "Monitored commander disconnected during tribute enforcement for %s", Side )
			ClearCommanderMonitor( Side, "monitored commander disconnected" )
		end
	end
end

function Plugin.Tribute_MapPostLoad()
	Plugin.MapChangeTime = Shared.GetTime()

	for Side in pairs( ActiveTributes ) do
		ClearTribute( Side, "map change", false )
	end
	for Side in pairs( CommanderMonitors ) do
		ClearCommanderMonitor( Side, "map change" )
	end

	Plugin.LoadCommHistory()
	StartSpecReminder()
	Log( "Tribute system ready on map %s. Map change time: %.0f",
		Shared.GetMapName(), Plugin.MapChangeTime )
end

function Plugin.Tribute_Cleanup()
	StopSpecReminder()
	for Side in pairs( ActiveTributes ) do
		ClearTribute( Side, "plugin cleanup", false )
	end
	for Side in pairs( CommanderMonitors ) do
		ClearCommanderMonitor( Side, "plugin cleanup" )
	end
end

local function TributeCmd( Client, Subcommand )
	if not Client then return end
	Plugin.HandleTributeCommand( Client, Subcommand or "help" )
end

function Plugin:CreateCommands()
	local TributeCommand = self:BindCommand( "sh_tribute", "tribute", TributeCmd, true )
	TributeCommand:AddParam{ Type = "string", Optional = true,
		Default = "help",
		Error = "Usage: !tribute marines, !tribute aliens, !tribute info, or !tribute help" }
	TributeCommand:Help( "Volunteer as tribute to become commander. Usage: !tribute marines or !tribute aliens" )
end

function Plugin:Initialise()
	self.ActiveTributes = ActiveTributes
	self:CreateCommands()
	self.LoadCommHistory()
	-- Map vote broadcasts this event dynamically, so subscribe explicitly rather
	-- than relying on Shine's plugin-method hook discovery at load time.
	Shine.Hook.Add( "OnMapVoteStarted", MAP_VOTE_HOOK_NAME, function()
		Plugin.Tribute_OnMapVoteStarted()
	end )
	self.Enabled = true
	Log( "Tribute extension initialised" )
	return true
end

function Plugin:MapPostLoad()
	self.Tribute_MapPostLoad()
end

function Plugin:EndGame( Gamerules )
	self.RecordCommsAtRoundEnd( Gamerules )
end

function Plugin:CommLoginPlayer( Chair, Player )
	self.Tribute_CommLoginPlayer( Chair, Player )
end

function Plugin:OnVoteToEjectCommander( Team, VotingPlayer, TargetCommander )
	self.Tribute_OnVoteToEjectCommander( Team, VotingPlayer, TargetCommander )
end

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force )
	self.Tribute_PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force )
end

function Plugin:ClientDisconnect( Client )
	self.Tribute_ClientDisconnect( Client )
end

function Plugin:Cleanup()
	Shine.Hook.Remove( "OnMapVoteStarted", MAP_VOTE_HOOK_NAME )
	self.Tribute_Cleanup()
end

Log( "server.lua loaded successfully" )

return Plugin
