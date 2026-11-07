local Plugin = ...
local Shine = Shine
local StringFormat = string.format
local VoteRandomAutoShufflePatchHook = "MNGAAdministrationVoteRandomAutoShufflePatch"
Plugin.VoteRandomAutoShufflePatchHook = VoteRandomAutoShufflePatchHook
local MapVoteResultsPath = "config://shine/temp/mnga_mapvote_results.json"

-- Shine votesurrender skips the "X has voted to concede" announcement for the
-- vote that passes (Surrender() runs inside AddVote and sets Surrendered).
-- Remember who is casting the vote and announce them as the last voter right
-- before the surrender goes through.
local VoteSurrenderLastVotePatchHook = "MNGAAdministrationVoteSurrenderLastVotePatch"
Plugin.VoteSurrenderLastVotePatchHook = VoteSurrenderLastVotePatchHook

local function PatchVoteSurrenderLastVote( VoteSurrender )
	if not VoteSurrender then return end

	if VoteSurrender.MNGALastVotePatchVersion == 1 then
		Print( "[mngasurrender] Last-vote announcement patch already installed." )
		return
	end
	if type( VoteSurrender.AddVote ) ~= "function" or type( VoteSurrender.Surrender ) ~= "function" then
		Print( "[mngasurrender] ERROR | votesurrender AddVote/Surrender missing; last-vote announcement patch disabled." )
		return
	end

	local OriginalAddVote = VoteSurrender.AddVote
	VoteSurrender.AddVote = function( self, Client, Team, ... )
		self.MNGAPendingVoter = Client
		local Success, Err = OriginalAddVote( self, Client, Team, ... )
		self.MNGAPendingVoter = nil
		return Success, Err
	end

	local OriginalSurrender = VoteSurrender.Surrender
	VoteSurrender.Surrender = function( self, Team, ... )
		local Client = self.MNGAPendingVoter
		self.MNGAPendingVoter = nil

		local Gamerules = GetGamerules()
		local Player = Client and Client.GetControllingPlayer and Client:GetControllingPlayer()
		if Player and Gamerules and Gamerules:GetGameState() == kGameState.Started then
			MNGA_NotifyNames( GetEntitiesForTeam( "Player", Team ), 255, 200, 100,
				"%s is the last to vote to concede.", MNGA_Name( Player ) )
		end

		return OriginalSurrender( self, Team, ... )
	end

	VoteSurrender.MNGALastVotePatchVersion = 1
	Print( "[mngasurrender] Last-vote announcement patch installed." )
end

local function InstallVoteSurrenderLastVotePatch()
	Shine.Hook.Remove( "OnPluginLoad", VoteSurrenderLastVotePatchHook )
	Shine.Hook.Add( "OnPluginLoad", VoteSurrenderLastVotePatchHook, function( Name, LoadedPlugin )
		if Name == "votesurrender" then
			PatchVoteSurrenderLastVote( LoadedPlugin )
		end
	end )

	PatchVoteSurrenderLastVote( Shine.Plugins and Shine.Plugins[ "votesurrender" ] )
end

Plugin.InstallVoteSurrenderLastVotePatch = InstallVoteSurrenderLastVotePatch

-- Shine basecommands' sh_stopvote finds the vote state by scanning UpdateServer
-- callbacks for source "@lua/Voting.lua". Ours is replaced by
-- lua/mnga_administration/Voting.lua, so point StopVote at our own state.
local BaseCommandsStopVotePatchHook = "MNGAAdministrationBaseCommandsStopVotePatch"
Plugin.BaseCommandsStopVotePatchHook = BaseCommandsStopVotePatchHook

local function PatchBaseCommandsStopVote( BaseCommands )
	if not BaseCommands then return end

	if BaseCommands.MNGAStopVotePatchVersion == 1 then
		Print( "[mngastopvote] StopVote patch already installed." )
		return
	end
	if type( StopActiveVote ) ~= "function" then
		Print( "[mngastopvote] ERROR | StopActiveVote missing; sh_stopvote patch disabled." )
		return
	end

	Print( "[mngastopvote] Shine's own StopVote hack found=%s", tostring( type( BaseCommands.StopVote ) == "function" ) )
	BaseCommands.StopVote = function( self )
		return StopActiveVote( "sh_stopvote" )
	end

	BaseCommands.MNGAStopVotePatchVersion = 1
	Print( "[mngastopvote] StopVote patch installed." )
end

local function InstallBaseCommandsStopVotePatch()
	Shine.Hook.Remove( "OnPluginLoad", BaseCommandsStopVotePatchHook )
	Shine.Hook.Add( "OnPluginLoad", BaseCommandsStopVotePatchHook, function( Name, LoadedPlugin )
		if Name == "basecommands" then
			PatchBaseCommandsStopVote( LoadedPlugin )
		end
	end )

	PatchBaseCommandsStopVote( Shine.Plugins and Shine.Plugins[ "basecommands" ] )
end

Plugin.InstallBaseCommandsStopVotePatch = InstallBaseCommandsStopVotePatch

function Plugin:StoreMapVoteResultsForNextMap( VoteResults, Winner, WinnerVotes, TotalVotes )
	if not VoteResults or VoteResults == "" then
		Print( "[mngamapvote] No final vote results to save for next map." )
		return
	end

	local CurrentMap = Shared.GetMapName()
	if Winner == CurrentMap then
		Print( "%s", StringFormat(
			"[mngamapvote] Vote winner is the current map (%s); not saving results for mapchange display.",
			tostring( Winner )
		) )
		return
	end

	local Data = {
		Map = CurrentMap,
		Results = VoteResults,
		Winner = Winner,
		WinnerVotes = WinnerVotes,
		TotalVotes = TotalVotes,
		Time = Shared.GetSystemTime()
	}

	local Success, Err = Shine.SaveJSONFile( Data, MapVoteResultsPath )
	if Success then
		Print( "%s", StringFormat( "[mngamapvote] Saved vote results for next map display: %s", VoteResults ) )
	else
		Print( "%s", StringFormat( "[mngamapvote] ERROR | Failed to save vote results for next map display: %s", tostring( Err ) ) )
	end
end

function Plugin:ShowPreviousMapVoteResults()
	local Data = Shine.LoadJSONFile( MapVoteResultsPath )
	if not Data or not Data.Results or Data.Results == "" then
		Print( "[mngamapvote] No previous map vote results to display after map load." )
		return
	end

	local Success, Err = Shine.SaveJSONFile( {}, MapVoteResultsPath )
	if not Success then
		Print( "%s", StringFormat( "[mngamapvote] ERROR | Failed to clear previous map vote results: %s", tostring( Err ) ) )
	end

	local CurrentMap = Shared.GetMapName()
	if Data.Winner and Data.Winner ~= CurrentMap then
		Print( "%s", StringFormat(
			"[mngamapvote] Saved vote winner was %s but current map is %s; skipping stale post-load results.",
			tostring( Data.Winner ), tostring( CurrentMap )
		) )
		return
	end

	Print( "%s", StringFormat( "[mngamapvote] Displaying previous map vote results after map load: %s", Data.Results ) )
	Shine:NotifyDualColour( nil, 255, 255, 0, "Map Vote",
		255, 255, 255, StringFormat( "Previous vote results: %s", Data.Results ) )

	if Data.Winner and Data.WinnerVotes and Data.TotalVotes then
		Shine:NotifyDualColour( nil, 255, 255, 0, "Map Vote",
			255, 255, 255, StringFormat( "%s won with %d/%d votes.",
				Data.Winner, Data.WinnerVotes, Data.TotalVotes ) )
	end
end

local function GetAutoShufflePlayerCount()
	if Plugin and type( Plugin.GetPopulationHumanCount ) == "function" then
		return Plugin:GetPopulationHumanCount(), "MNGA non-spectating humans"
	end

	if Shine and type( Shine.GetHumanPlayerCount ) == "function" then
		return Shine.GetHumanPlayerCount(), "Shine.GetHumanPlayerCount"
	end

	if Server and type( Server.GetNumPlayers ) == "function" then
		return Server.GetNumPlayers(), "Server.GetNumPlayers"
	end

	return 0, "unavailable"
end

local function GetAutoShuffleAtRoundStartPlayerMin()
	local Enhance = Plugin.Config and Plugin.Config.VoteRandomEnhance
	local AutoShuffle = Enhance and Enhance.AutoShuffle
	if type( AutoShuffle ) == "table" then
		if AutoShuffle.MinimumHumansEnabled == false then return 0 end
		local Configured = tonumber( AutoShuffle.MinimumHumans )
		if Configured then return math.max( Configured, 0 ) end
	end
	local MinPlayers = Plugin.Config and Plugin.Config.AutoShuffleAtRoundStartPlayerMin or 0
	MinPlayers = tonumber( MinPlayers ) or 0
	if MinPlayers < 0 then
		return 0
	end
	return MinPlayers
end

local function PatchVoteRandomAutoShuffle( VoteRandom )
	if not VoteRandom then return end

	if VoteRandom.MNGAAutoShufflePlayerMinPatch then
		Print( "%s", StringFormat( "[mngavoterandom] Auto-shuffle player-min patch already installed." ) )
		return
	end

	if type( VoteRandom.ApplyAutoShuffle ) ~= "function" then
		Print( "%s", StringFormat( "[mngavoterandom] ERROR | voterandom.ApplyAutoShuffle missing; auto-shuffle player-min patch disabled." ) )
		return
	end

	local OriginalApplyAutoShuffle = VoteRandom.ApplyAutoShuffle

	VoteRandom.ApplyAutoShuffle = function( self, ... )
		if self.Config and self.Config.AutoShuffleAtRoundStart then
			-- Match the voterandommnga hotfix: reset the round-start vote and
			-- honour the admin suppression vote before applying the player floor.
			if self.Vote and type( self.Vote.Reset ) == "function" then
				self.Vote:Reset()
			end

			if self.SuppressAutoShuffle then
				return
			end

			local MinPlayers = GetAutoShuffleAtRoundStartPlayerMin()
			local PlayerCount, CountSource = GetAutoShufflePlayerCount()
			Print( "%s", StringFormat(
				"[mngavoterandom] Auto-shuffle player-min check: playerCount=%d min=%d source=%s",
				PlayerCount, MinPlayers, CountSource
			) )
			if MinPlayers > 0 and PlayerCount <= MinPlayers then
				local Message = StringFormat(
					"Skipping auto-shuffle: player count (%d) is below AutoShuffleAtRoundStartPlayerMin (%d).",
					PlayerCount, MinPlayers
				)
				if self.Logger and type( self.Logger.Info ) == "function" then
					self.Logger:Info( Message )
				end
				Print( "%s", StringFormat( "[mngavoterandom] %s", Message ) )
				return
			end
		end

		return OriginalApplyAutoShuffle( self, ... )
	end

	VoteRandom.MNGAAutoShufflePlayerMinPatch = true
	VoteRandom.MNGAOriginalApplyAutoShuffle = OriginalApplyAutoShuffle
	Print( "%s", StringFormat( "[mngavoterandom] Auto-shuffle player-min patch installed." ) )
end

local function InstallVoteRandomAutoShufflePatch()
	Shine.Hook.Remove( "OnPluginLoad", VoteRandomAutoShufflePatchHook )
	Shine.Hook.Add( "OnPluginLoad", VoteRandomAutoShufflePatchHook, function( Name, LoadedPlugin )
		if Name ~= "voterandom" then return end
		PatchVoteRandomAutoShuffle( LoadedPlugin )
	end )

	local VoteRandom = Shine.Plugins and Shine.Plugins[ "voterandom" ]
	if VoteRandom then
		PatchVoteRandomAutoShuffle( VoteRandom )
	end
end

Plugin.InstallVoteRandomAutoShufflePatch = InstallVoteRandomAutoShufflePatch

 Shine.Timer.Simple(5, function()
	if type(StatsUI_RegisterTSS) == "function" then

		local originalRegisterTSS = StatsUI_RegisterTSS

		StatsUI_RegisterTSS = function(TechName, msg)
			originalRegisterTSS(TechName, msg)
			if TechName == "marineRtDamage"
			or TechName == "alienRtDamage" then
				local steamId = msg.steamId
				if steamId and steamId > 0 then
					myRtTotals[TechName][steamId] =
						(myRtTotals[TechName][steamId] or 0) + msg.Value
				end
			end
		end
	else
		Print( "%s", StringFormat(" >;> ERROR | %s | CHUD not detected; RT damage tracking disabled", Shared.GetTime() ))
	end

	if not Plugin.InstallVoteRandomEnhancePatch or not Plugin:InstallVoteRandomEnhancePatch() then
		InstallVoteRandomAutoShufflePatch()
	end
	
	
	-- Retired compatibility block. Queue policy now lives in the authoritative
	-- mngareadyroomqueue extension. Keep the old body temporarily for production
	-- rollback reference, but never install its wrappers.
	do
		local rrqueue = Shine.Plugins and Shine.Plugins[ "readyroomqueue" ]
		if false and rrqueue and type( rrqueue.Enqueue ) == "function" then

			-- Data: track players who used a skip token (persists until Dequeue/Pop)
			if not rrqueue.SkipQueueUsers then
				rrqueue.SkipQueueUsers = Shine.Set()
			end

			-- Add MNGA's DFN hint only for a new player-slot queue entry. Repeated
			-- Enqueue calls from F4 merely repeat position feedback and must not spam it.
			local originalEnqueue = rrqueue.Enqueue
			rrqueue.Enqueue = function( self, Client )
				local SteamID = Client and Client:GetUserId()
				local WasQueued = SteamID and self.PlayerQueue
					and self.PlayerQueue:Get( SteamID ) ~= nil
				local Result = originalEnqueue( self, Client )
				local JoinedQueue = not WasQueued and SteamID and self.PlayerQueue
					and self.PlayerQueue:Get( SteamID ) ~= nil

				if JoinedQueue then
					Print( "%s", StringFormat(
						"[mnganotify] queue sound hint sent | steamId=%s",
						tostring( SteamID )
					) )
					Shine:NotifyDualColour(
						Client, 255, 180, 0, "[PlayerSlotQueue]", 255, 255, 255,
						"You will hear a sound when you enter Ready Room from queue. Toggle it in Options > Mods > Shimizu QoL (or 'sh_dfn' in console)"
					)
				end

				return Result
			end

			-- Wrap GetQueueInsertPosition to also respect SkipQueueUsers
			-- (in addition to the existing VIP check).
			local originalGetQueueInsertPosition = rrqueue.GetQueueInsertPosition
			rrqueue.GetQueueInsertPosition = function( self, Queue, Client )
				local VIPEnabled = self.Config.VIPPlayers.Enabled
				local Permission = self.Config.VIPPlayers.PermissionString
				local IsSkip = self.SkipQueueUsers
					and self.SkipQueueUsers:Contains( Client:GetUserId() )

				if IsSkip or (VIPEnabled and Shine:HasAccess(Client, Permission)) then
					local pos = 1
					for SteamID in Queue:Iterate() do
						local c = Shine.GetClientByNS2ID(SteamID)
						if c then
							if (self.SkipQueueUsers
							and self.SkipQueueUsers:Contains( SteamID ))
							or Shine:HasAccess(c, Permission) then
								pos = pos + 1
							else
								break
							end
						end
					end
					return pos
				end
				return Queue:GetCount() + 1
			end

			-- Wrap Dequeue to clean up SkipQueueUsers
			local originalDequeue = rrqueue.Dequeue
			rrqueue.Dequeue = function( self, Client )
				if not Client then return end
				local sid = Client:GetUserId()
				if self.SkipQueueUsers then
					self.SkipQueueUsers:Remove( sid )
				end
				return originalDequeue( self, Client )
			end

			-- Wrap Pop to support SuppressNextPop (used by SwapPlayer) and arm a
			-- confirmation timeout only for a verified queue promotion.
			local originalPop = rrqueue.Pop
			rrqueue.Pop = function( self, ... )
				if self.SuppressNextPop then
					self.SuppressNextPop = nil
					Print( "[queue-timeout] pop suppressed; no promotion timeout armed" )
					return
				end

				local FrontClient = self.GetFirstClient and self.PlayerQueue
					and self:GetFirstClient( self.PlayerQueue ) or nil
				local SteamID = FrontClient and FrontClient:GetUserId()
				local Result = originalPop( self, ... )
				local Player = FrontClient and FrontClient:GetControllingPlayer()
				local Promoted = Result == true and Player
					and Player:GetTeamNumber() == kTeamReadyRoom

				Print( "%s", StringFormat(
					"[queue-timeout] pop result | result=%s frontSteamId=%s promoted=%s team=%s",
					tostring( Result ), tostring( SteamID or "none" ),
					tostring( Promoted and true or false ),
					tostring( Player and Player:GetTeamNumber() or "none" )
				) )
				if Promoted then
					Print( "%s", StringFormat(
						"[mnganotify] sending queue promotion attention | steamId=%s",
						tostring( SteamID or "none" )
					) )
					Plugin:SendNetworkMessage( FrontClient, "QueuePromotionAttention", {}, true )
				end
				if Promoted and Plugin.ArmQueuePromotionTimeout then
					Plugin:ArmQueuePromotionTimeout( FrontClient )
				end
				return Result
			end

			local function InsertClientAtQueueFront( QueuePlugin, Client )
				if not QueuePlugin.PlayerQueue or not Client then return false end

				local SteamID = Client:GetUserId()
				if not SteamID or SteamID < 1 then return false end

				QueuePlugin.PlayerQueue:Remove( SteamID )
				if QueuePlugin.ReservedQueue then
					QueuePlugin.ReservedQueue:Remove( SteamID )
				end
				if QueuePlugin.PriorityPlayers then
					QueuePlugin.PriorityPlayers:Remove( SteamID )
				end
				if QueuePlugin.SkipQueueUsers then
					QueuePlugin.SkipQueueUsers:Remove( SteamID )
				end

				QueuePlugin:InsertIntoQueue( QueuePlugin.PlayerQueue, SteamID, 1 )
				QueuePlugin:UpdateQueuePositions( QueuePlugin.PlayerQueue, "QUEUE_CHANGED_VIP" )

				if QueuePlugin.BroadcastQueueStatus then
					QueuePlugin:BroadcastQueueStatus( SteamID, QueuePlugin.PlayerQueue:Get( SteamID ) or 1 )
				end
				if QueuePlugin.SendTranslatedNotify then
					QueuePlugin:SendTranslatedNotify( Client, "QUEUE_ADDED", {
						Position = QueuePlugin.PlayerQueue:Get( SteamID ) or 1
					} )
				end
				return true
			end

			-- Skip-queue helper: validates token via HTTP, then re-inserts at front
			local function QuerySkipToken( steamid, callback )
				local function OnSuccess( response )
					if not GetGamerules or not GetGamerules() then return end
					if not response or response == "" then return end
					local data = json.decode(response, 1, nil)
					if not data then
						Print("%s", StringFormat(" >;> ERROR | %s | failed to decode skip token response", Shared.GetTime()))
						return
					end
					Print("%s", StringFormat(" >;> SKIPTOKEN http | %s | query %s", Shared.GetTime(), steamid))
					if data['success'] then callback( data['token_type'] ) end
				end
				local function OnTimeout()
					Print( "%s", StringFormat(" >;> SKIPTOKEN TIMEOUT | %s | request for stats timed out %s", Shared.GetTime(), steamid ))
				end
				local BaseURL = tostring( self.Config.xpCentralURL or "http://127.0.0.1:25386" ):gsub( "/+$", "" )
				Shine.TimedHTTPRequest( BaseURL.."/skip", "POST", {
					steamid = steamid,
					server_id = tostring( self.Config.xpServerID or "" ),
					secret = tostring( self.Config.xpSharedSecret or "" )
				}, OnSuccess, OnTimeout, 1.5 )
			end

			local function NotifySpectatorsOfSkipTokenUse( Client, TokenType )
				local Player = Client:GetControllingPlayer()
				local PlayerName = Player and Player.GetName and Player:GetName() or "Unknown"
				local Spectators = {}
				local Clients, Count = Shine.GetAllClients()

				for i = 1, Count do
					local SpectatorClient = Clients[ i ]
					if SpectatorClient.GetIsSpectator and SpectatorClient:GetIsSpectator() then
						Spectators[ #Spectators + 1 ] = SpectatorClient
					end
				end

				local Message = StringFormat( TokenType == "donation"
					and "%s has used a supporter token to skip the queue. Thank you for supporting the server!"
					or "%s has used a seeding token to skip the queue. (reminder: seeding tokens are earned by seeding the server)",
					PlayerName
				)
				Print( "%s", StringFormat( "[skipqueue] announcing successful seeding-token use by %s to %d spectators", PlayerName, #Spectators ) )
				Shine:NotifyColour( Spectators, 255, 200, 100, Message )
			end

			rrqueue.Skipqueue = function( self, Client )
				if not Client:GetIsSpectator() then
					self:NotifyTranslatedError( Client, "ENQUEUE_ERROR_PLAYER" )
					return
				end
				local SteamID = Client:GetUserId()
				if not SteamID or SteamID < 1 then return end

				QuerySkipToken( SteamID, function( TokenType )
					self.SkipQueueUsers:Add( SteamID )
					self.PlayerQueue:Remove( SteamID )
					self.ReservedQueue:Remove( SteamID )

					local pos = self:GetQueueInsertPosition( self.PlayerQueue, Client )
					self:InsertIntoQueue( self.PlayerQueue, SteamID, pos, "QUEUE_CHANGED_VIP" )
					self:SendTranslatedNotify( Client, "QUEUE_ADDED", { Position = pos } )

					local rPos = self:GetQueueInsertPosition( self.ReservedQueue, Client )
					self:InsertIntoQueue( self.ReservedQueue, SteamID, rPos, "PIORITY_QUEUE_CHANGED_VIP" )
					self:SendTranslatedNotify( Client, "PIORITY_QUEUE_ADDED", { Position = rPos } )

					NotifySpectatorsOfSkipTokenUse( Client, TokenType )
				end )
			end

			-- Swap a spectator with a playing player.  Suppresses the automatic
			-- queue Pop so the vacant slot goes to the chosen spectator, not #1.
			rrqueue.SwapPlayer = function( self, AdminClient, SpecClient, PlayerClient )
				if not SpecClient or not PlayerClient then
					Shine:AdminPrint( AdminClient, "Swap: Please specify both a spectator and a player." )
					return
				end
				local SpecPlayer = SpecClient:GetControllingPlayer()
				local PlayerPlayer = PlayerClient:GetControllingPlayer()
				if not SpecPlayer or not PlayerPlayer then
					Shine:AdminPrint( AdminClient, "Swap: Invalid targets." )
					return
				end
				if not SpecClient:GetIsSpectator() then
					Shine:AdminPrint( AdminClient, "Swap: %s is not a spectator.", true,
						Shine.GetClientName( SpecClient ) )
					return
				end
				if PlayerClient:GetIsSpectator() then
					Shine:AdminPrint( AdminClient, "Swap: %s is already a spectator.", true,
						Shine.GetClientName( PlayerClient ) )
					return
				end
				if SpecClient == PlayerClient then
					Shine:AdminPrint( AdminClient, "Swap: Cannot swap a player with themselves." )
					return
				end
				local Gamerules = GetGamerules()
				if not Gamerules then return end

				local PlayerTeam = PlayerPlayer:GetTeamNumber()
				local SpecSteamID = SpecClient:GetUserId()
				local QueuedCount = self.PlayerQueue and self.PlayerQueue:GetCount() or 0
				local SpecWasQueued = self.PlayerQueue and SpecSteamID and self.PlayerQueue:Get( SpecSteamID ) ~= nil
				local ShouldQueueDisplacedPlayer = QueuedCount - ( SpecWasQueued and 1 or 0 ) > 0

				self:Dequeue( SpecClient )

				self.SuppressNextPop = true
				Gamerules:JoinTeam( PlayerPlayer, kSpectatorIndex, true, true )
				self.SuppressNextPop = nil

				local QueuedDisplacedPlayer = false
				if ShouldQueueDisplacedPlayer then
					QueuedDisplacedPlayer = InsertClientAtQueueFront( self, PlayerClient )
				end

				Gamerules:JoinTeam( SpecPlayer, PlayerTeam, true, true )

				Print( "%s", StringFormat("[swap] %s | admin %s | spec %s <-> player %s (team %d) queued_displaced=%s",
					Shared.GetTime(), Shine.GetClientInfo( AdminClient ),
					Shine.GetClientInfo( SpecClient ), Shine.GetClientInfo( PlayerClient ),
					PlayerTeam, tostring( QueuedDisplacedPlayer ) ) )

				Shine:AdminPrint( AdminClient, "Swap: %s (spec) swapped with %s (team %d).", true,
					Shine.GetClientName( SpecClient ), Shine.GetClientName( PlayerClient ),
					PlayerTeam )
				Shine:NotifyColour( nil, 255, 200, 100, StringFormat( "Swap: %s (spec) swapped with %s.",
					Shine.GetClientName( SpecClient ), Shine.GetClientName( PlayerClient ) ) )
				return true
			end

			Print( "[mngagate] SkipQ + Swap hooks installed." )
		else
			Print( "[mngagate] legacy readyroomqueue wrappers retired; mngareadyroomqueue owns skipq/swap." )
		end
	end

	-- patch afkkick to not kick comms, which often happens pregame
    local afkkick = Shine.Plugins and Shine.Plugins[ "afkkick" ]
    if afkkick and type( afkkick.IsPlayerFrozen ) == "function" then
		local OriginalIsPlayerFrozen = afkkick.IsPlayerFrozen
		afkkick.IsPlayerFrozen = function( self, Player )
			if Player:isa( "Commander" ) then
				return true
			end
			return OriginalIsPlayerFrozen( self, Player )
		end

		-- AFK players used to be force-connected to the queue server instead of
		-- kicked. The queue server is decommissioned, so the redirect left them on
		-- a dead "Couldn't establish a connection" (and NS2 retry targets the dead
		-- address too). Plain Shine AFK kick now.
		Print( "[mngagate] AFKKick queue force-connect retired; vanilla Shine AFK kick in use." )
	else
		if Plugin.Logger and Plugin.Logger.Warn then
			Plugin.Logger:Warn( "AFKKick plugin not found or IsPlayerFrozen missing — patch not applied." )
		else
			Print( "AFKKick plugin not found or IsPlayerFrozen missing — patch not applied." )
		end
    end

	-- patch mapvote to optionally hide live vote tallies (anti dog-pile).
	-- Whether hiding is active is read live from Plugin.HideMapVoteCounts every
	-- call, so sh_hidevotes can flip it mid-vote. We grab the plugin even if it
	-- is currently disabled so the wrappers are in place if it gets enabled.
	local mapvote = Shine.Plugins and Shine.Plugins[ "mapvote" ]
	if mapvote then
		-- Channel 1: the vote menu tiles. SendMapVoteCount pushes the per-map
		-- count to clients (both live updates and the initial menu population
		-- for late joiners). Force the count to 0 while hiding so every tile
		-- reads "(0)" and the client-side winner highlight never triggers.
		if type( mapvote.SendMapVoteCount ) == "function" then
			local OriginalSendMapVoteCount = mapvote.SendMapVoteCount
			mapvote.SendMapVoteCount = function( self, Client, Map, Count )
				if Plugin.HideMapVoteCounts then
					Count = 0
				end
				return OriginalSendMapVoteCount( self, Client, Map, Count )
			end
			Print( "[mngamapvote] SendMapVoteCount hook installed." )
		else
			Print( "[mngamapvote] ERROR | mapvote.SendMapVoteCount missing; tile hiding disabled." )
		end

		-- Channel 2: the chat broadcast. PLAYER_VOTED tells everyone "X voted
		-- for <map> (N votes for this, M total)" and PLAYER_VOTED_PRIVATE echoes
		-- the same counts back to the voter. While hiding, swap both for a plain
		-- announcement that names neither the map nor any count.
		if type( mapvote.SendTranslatedNotify ) == "function" then
			local OriginalSendTranslatedNotify = mapvote.SendTranslatedNotify
			local function FormatMapVoteResults( VoteList, ExtendMap, ExcludeVoteCount )
				local Results = {}
				for Map, Votes in pairs( VoteList ) do
					if Votes and Votes > 0 and Votes ~= ExcludeVoteCount then
						Results[ #Results + 1 ] = {
							Map = Map,
							Votes = Votes
						}
					end
				end

				table.sort( Results, function( A, B )
					if A.Votes == B.Votes then
						return tostring( A.Map ) < tostring( B.Map )
					end
					return A.Votes > B.Votes
				end )

				local Parts = {}
				for i = 1, #Results do
					local Result = Results[ i ]
					local DisplayName = Result.Map == ExtendMap and "Extend Map" or Result.Map
					Parts[ #Parts + 1 ] = StringFormat( "%s: %d", DisplayName, Result.Votes )
				end

				return table.concat( Parts, ", " )
			end

			local function FormatTopMapVoteResults( VoteList )
				local MaxVotes = 0
				for _, Votes in pairs( VoteList ) do
					if Votes and Votes > MaxVotes then
						MaxVotes = Votes
					end
				end

				local Results = {}
				for Map, Votes in pairs( VoteList ) do
					if Votes and Votes == MaxVotes and Votes > 0 then
						Results[ #Results + 1 ] = Map
					end
				end

				table.sort( Results, function( A, B )
					return tostring( A ) < tostring( B )
				end )

				local Parts = {}
				for i = 1, #Results do
					Parts[ #Parts + 1 ] = StringFormat( "%s: %d", Results[ i ], MaxVotes )
				end

				return table.concat( Parts, ", " ), MaxVotes
			end

			local function SendFinalVoteResults( Target, VoteList, Winner, WinnerVotes, TotalVotes )
				local CurrentMap = mapvote.GetCurrentMap and mapvote:GetCurrentMap()
				local VoteResults = FormatMapVoteResults( VoteList, CurrentMap )
				if VoteResults ~= "" then
					-- Keep the vote table as the marker rather than a boolean. Shine reuses
					-- the mapvote plugin across votes but replaces self.Vote for each one.
					mapvote.MNGAFinalResultsSentForVote = mapvote.Vote
					Print( "%s", StringFormat( "[mngamapvote] Final hidden vote results: %s", VoteResults ) )
					Shine:NotifyDualColour( Target, 255, 255, 0, "Map Vote",
						255, 255, 255, StringFormat( "Vote results: %s", VoteResults ) )
					Plugin:StoreMapVoteResultsForNextMap( VoteResults, Winner, WinnerVotes, TotalVotes )
				else
					Print( "[mngamapvote] Final hidden vote results: no maps received votes." )
				end
			end

			local function SendExtensionVoteResults( MapVotePlugin, Target )
				local Vote = MapVotePlugin.Vote
				if not Vote or not Vote.VoteList
					or MapVotePlugin.MNGAFinalResultsSentForVote == Vote then
					return
				end

				local Winner = MapVotePlugin.NextMap and MapVotePlugin.NextMap.Winner
				local WinnerVotes = Winner and Vote.VoteList[ Winner ]
				local TotalVotes = Vote.TotalVotes
				if not Winner or not WinnerVotes or not TotalVotes then
					Print( "[mngamapvote] Extension announced without complete winning vote data; tally not displayed." )
					return
				end

				Print( "%s", StringFormat(
					"[mngamapvote] Extension winner detected: %s with %d/%d votes.",
					tostring( Winner ), WinnerVotes, TotalVotes
				) )
				SendFinalVoteResults( Target, Vote.VoteList, Winner, WinnerVotes, TotalVotes )
				Shine:NotifyDualColour( Target, 255, 255, 0, "Map Vote",
					255, 255, 255, StringFormat(
						"Extend Map won the vote with %d/%d votes.", WinnerVotes, TotalVotes
					) )
			end

			local function SendTiedVoteResults( MapVotePlugin, Target )
				if not MapVotePlugin.Vote or not MapVotePlugin.Vote.VoteList then
					return false
				end

				local TiedResults, TiedVotes = FormatTopMapVoteResults( MapVotePlugin.Vote.VoteList )
				local CurrentMap = MapVotePlugin.GetCurrentMap and MapVotePlugin:GetCurrentMap()
				local RemainingResults = FormatMapVoteResults(
					MapVotePlugin.Vote.VoteList, CurrentMap, TiedVotes
				)
				if TiedResults == "" then
					return false
				end

				Print( "%s", StringFormat(
					"[mngamapvote] Tied vote results: tied=%s remaining=%s", TiedResults, RemainingResults
				) )
				local Message = StringFormat( "Votes tied between: %s.", TiedResults )
				if RemainingResults ~= "" then
					Message = StringFormat( "%s %s.", Message, RemainingResults )
				end
				Shine:NotifyDualColour( Target, 255, 255, 0, "Map Vote",
					255, 255, 255, Message )
				return true
			end

			mapvote.SendTranslatedNotify = function( self, Target, Name, Params )
				-- Vote conclusion/tie messages. Runs regardless of HideMapVoteCounts
				-- -- the vote is over, so there's nothing left to dog-pile.
				-- self.Vote is still intact here (EndVote doesn't clear
				-- VoteList/TotalVotes).
				if Name == "VOTES_TIED" then
					if SendTiedVoteResults( self, Target ) then
						return
					end
				end

				-- A next-map vote won by the current map does not emit any of the
				-- WINNER_* messages above; Shine proceeds directly to its extension
				-- announcement. Reveal the completed tally here. RTV extensions have
				-- already emitted WINNER_VOTES and are suppressed by the vote marker.
				if Name == "EXTENDING_TIME" then
					SendExtensionVoteResults( self, Target )
				end

				if Name == "WINNER_VOTES"
				and Params and Params.MapName and Params.Votes and Params.TotalVotes
				and self.Vote and self.Vote.VoteList then
					SendFinalVoteResults( Target, self.Vote.VoteList, Params.MapName, Params.Votes, Params.TotalVotes )
					local CurrentMap = self.GetCurrentMap and self:GetCurrentMap()
					local WinnerName = Params.MapName == CurrentMap and "Extend Map" or Params.MapName
					local Message = StringFormat( "%s won the vote with %d/%d votes.",
						WinnerName, Params.Votes, Params.TotalVotes )
					Shine:NotifyDualColour( Target, 255, 255, 0, "Map Vote",
						255, 255, 255, Message )
					return
				end

				if ( Name == "WINNER_NEXT_MAP" or Name == "WINNER_CYCLING" )
				and Params and Params.MapName and self.Vote and self.Vote.VoteList then
					local Winner = Params.MapName
					local WinnerVotes = self.Vote.VoteList[ Winner ]
					local Total = self.Vote.TotalVotes
					if WinnerVotes and Total then
						local Action = ( Name == "WINNER_CYCLING" )
							and "Cycling map..." or "Setting as next map..."
						SendFinalVoteResults( Target, self.Vote.VoteList, Winner, WinnerVotes, Total )
						local Message = StringFormat( "%s won the vote with %d/%d votes. %s",
							Winner, WinnerVotes, Total, Action )
						Shine:NotifyDualColour( Target, 255, 255, 0, "Map Vote",
							255, 255, 255, Message )
						return
					end
				end

				if Plugin.HideMapVoteCounts then
					if Name == "PLAYER_VOTED" then
						local PlayerName = ( Params and Params.TargetName ) or "A player"
						local Message = Params and Params.Revote
							and StringFormat( "%s changed their vote.", PlayerName )
							or StringFormat( "%s voted for a map.", PlayerName )
						-- Target nil here means broadcast to everyone.
						Shine:NotifyDualColour( Target, 255, 255, 0, "Map Vote",
							255, 255, 255, Message )
						return
					elseif Name == "PLAYER_VOTED_PRIVATE" then
						Shine:NotifyDualColour( Target, 255, 255, 0, "Map Vote",
							255, 255, 255, "Your vote has been counted." )
						return
					end
				end
				return OriginalSendTranslatedNotify( self, Target, Name, Params )
			end

			-- Round-limited servers announce extensions through NotifyTranslated
			-- rather than SendTranslatedNotify, so cover that equivalent path too.
			if type( mapvote.NotifyTranslated ) == "function" then
				local OriginalNotifyTranslated = mapvote.NotifyTranslated
				mapvote.NotifyTranslated = function( self, Target, Name, Params )
					if Name == "EXTENDING_ROUND" then
						SendExtensionVoteResults( self, Target )
					end
					return OriginalNotifyTranslated( self, Target, Name, Params )
				end
				Print( "[mngamapvote] NotifyTranslated extension-result hook installed." )
			else
				Print( "[mngamapvote] ERROR | mapvote.NotifyTranslated missing; round-extension tally disabled." )
			end
			Print( "[mngamapvote] SendTranslatedNotify hook installed." )
		else
			Print( "[mngamapvote] ERROR | mapvote.SendTranslatedNotify missing; chat hiding disabled." )
		end
	else
		Print( "[mngamapvote] ERROR | mapvote plugin not found; vote hiding disabled." )
	end

end);
