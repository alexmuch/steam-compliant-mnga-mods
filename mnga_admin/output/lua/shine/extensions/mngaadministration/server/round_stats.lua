local Plugin = ...
local Shine = Shine
local StringFormat = string.format
local IsType = Shine.IsType

myRtTotals = { marineRtDamage = {}, alienRtDamage = {} }
function Plugin:EndGame( Gamerules, WinningTeam )
	-- Link the observed result to the file-only VoteRandom prediction audit.
	-- This intentionally records no Elo update request/response data.
	if self.VoteRandomEnhanceEndGame then
		self:VoteRandomEnhanceEndGame( Gamerules, WinningTeam )
	end

	-- Kill bot management for the won -> ready-room transition. UpdateToReadyRoom
	-- runs kTimeToReadyRoom (8s) after this, synchronously moving every player to
	-- the ready room; base JoinTeam fires botTeamController:UpdateBots() on EACH
	-- move. With MaxBots left non-zero, UpdateBotsForTeam back-fills every draining
	-- team, spawning bots into the emptying game right as the round ends. Zeroing
	-- MaxBots makes GetUpdateEnabled() false, so UpdateBots short-circuits for the
	-- whole drain. Removing the existing bots first is cheap; it's adds that hitch.
	if self.CombatOwnsBots and self:CombatOwnsBots() then
		-- NS2 Combat v2: vanilla controller owns bots; zeroing MaxBots here would keep them off next round.
	elseif self.BotMode == "vanilla" then
		self.BotTarget = nil
		self:StopBotAdjustTimer()
		if Gamerules.botTeamController then
			Gamerules.botTeamController.updateLock = 999
		end
		Print( "%s", StringFormat( "[mngabots] vanilla round-end purge retaining sv_maxbots=%s",
			tostring( Gamerules.botTeamController and Gamerules.botTeamController.mngaVanillaMaxBots or 0 ) ) )
	elseif self.SetBotControllerHardOff then
		self:SetBotControllerHardOff( Gamerules, "round end" )
	elseif Gamerules.botTeamController then
		Gamerules.botTeamController.MaxBots = 0
	end

	if OnConsoleRemoveBots and not ( self.CombatOwnsBots and self:CombatOwnsBots() ) then
		OnConsoleRemoveBots(nil, 100, kTeam1Index);
		OnConsoleRemoveBots(nil, 100, kTeam2Index);
	end

	if not Gamerules.gameStartTime then return end


	local RoundLength = Shared.GetTime() - Gamerules.gameStartTime -- string.TimeToString(  )
	local RoundResult

	-- local StartLoc1 = Gamerules.startingLocationNameTeam1
	-- local StartLoc2 = Gamerules.startingLocationNameTeam2

	-- local Team1Name = Shine:GetTeamName( 1, true )
	-- local Team2Name = Shine:GetTeamName( 2, true )
	
	local seeding = true
	if self:CountTeamPlayers(true) > smallGameThreshold then seeding = false end


	---- apparently not working
	-- local Players1 = GetEntitiesForTeam("Player", kTeam1Index);
	-- local Players2 = GetEntitiesForTeam("Player", kTeam2Index);

	-- local infoParts = {}
	-- for _, player in ipairs(Players1) do
		-- Shine.GetClientInfo( Shine.GetClientForPlayer( player ) )
	-- end

	-- Print( StringFormat( ">;> ROUNDENDTEAM1 | marineteam %s",
	-- Players1,
	-- table.concat(infoParts, "|;&")
	-- ))
	
	-- infoParts = {}
	-- for _, player in ipairs(Players2) do
		-- Shine.GetClientInfo( Shine.GetClientForPlayer( player ) )
	-- end

	-- Print( StringFormat( ">;> ROUNDENDTEAM2 | alienteam %s",
	-- Players1,
	-- table.concat(infoParts, "|;&")
	-- ))

	-- might as well use devnull's data since it's already collected
	-- local lastRoundStats = CHUDGetLastRoundStats()
	

	
	-- local roundMinutes = lastRoundStats.RoundInfo.roundLength / 60

	-- local function filterByPlayTime(players, threshold)
		-- threshold = threshold or 0.5  -- 50% default
		-- local filtered = {}
		-- for _, player in ipairs(players) do
			-- if player.minutesPlaying and player.minutesPlaying >= roundMinutes * threshold then
				-- table.insert(filtered, player)
			-- end
		-- end
		-- return filtered
	-- end
	
	-- Print( StringFormat( ">;> ROUNDENDTEAM1 | marineteam %s",
	-- Players1,
	-- table.concat(filterByPlayTime(playerStats[1]), "|;&")
	-- ))
	
	-- Print( StringFormat( ">;> ROUNDENDTEAM2 | alienteam %s",
	-- Players1,
	-- table.concat(filterByPlayTime(playerStats[2]), "|;&")
	-- ))
	
	
	-- lastRoundStats.PlayerStats
	
	-- local topmarinecomm
	-- local topmarinecommtime
	-- local topaliencomm
	-- local topaliencommtime
	-- for _, playerStats in pairs(lastRoundStats.MarineCommStats) do
		-- for index, stats in pairs(playerStats) do
			-- stats.minutesComm

	
	if not WinningTeam or WinningTeam == kNeutralTeamType then
		RoundResult = 'draw'
	else
	
		local WinnerNum = IsType( WinningTeam, "number" ) and WinningTeam
			or ( WinningTeam.GetTeamType and WinningTeam:GetTeamType() )

		if WinnerNum then 
			local TeamString = Shine:GetTeamName( WinnerNum )
			RoundResult = TeamString
			-- Print( StringFormat( " >;> ROUNDEND | Round ended with %s winning. Round length: %s. %s %s ",
				-- TeamString, RoundLength
			-- ) )
		else
			RoundResult = 'unknown'
			-- Print( StringFormat( " >;> ROUNDEND | Round ended with unknown winning. Round length: %s. %s %s ",
				-- TeamString, RoundLength
			-- ) )
		end
	end
	
	-- Wait a moment for CHUD to populate its stats
	Shine.Timer.Simple( 1.5, function()
	
		-- local statsData = {}
		-- if not Server.GetLastProcessedRoundStats(statsData) then
			-- Print("Failed to retrieve processed round-stats data. No data processed, or failure occurred")
			-- Print("Failed to retrieve processed round-stats data. No data processed, or failure occurred")
			-- Print("Failed to retrieve processed round-stats data. No data processed, or failure occurred")
		-- else
			
			-- for k, v in pairs( statsData ) do
				-- Print( "%s = %s", tostring( k ), tostring( v ) )
			-- end
		-- end
		
		
		local stats = CHUDGetLastRoundStats()
		if not stats then
			Print( "ERROR XP Plugin: CHUDGetLastRoundStats returned nil" )
			return
		end
		-- process stats here
		-- for k, v in pairs( stats ) do
			-- Print( "%s = %s", tostring( k ), tostring( v ) )
		-- end
		
		local playerStats = stats.PlayerStats

		local function getTopCommander( playerStats, teamNumber )
			if not playerStats then return "null" end
			local topSteamId = nil
			local topTime = 0
			for steamId, stats in pairs( playerStats ) do
				if type( steamId ) == "number" then
					local entry = stats[teamNumber]
					if entry and entry.commanderTime and entry.commanderTime > topTime then
						topTime = entry.commanderTime
						topSteamId = steamId
					end
				end
			end
			return topSteamId and tostring( topSteamId ) or "null"
		end
		
		local marineComm = getTopCommander( stats.PlayerStats, 1 )
		local alienComm  = getTopCommander( stats.PlayerStats, 2 )
		
		local function getTopKiller(playerStats)
			if not playerStats then return "null" end
			local topSteamId = nil
			local topKills = 19
			for steamId, stats in pairs(playerStats) do
				if type(steamId) == "number" then
					for teamNumber = 1, 2 do
						local entry = stats[teamNumber]
						if entry and entry.kills and entry.kills > topKills then
							topKills = entry.kills
							topSteamId = steamId
						end
					end
				end
			end
			return topSteamId and tostring(topSteamId) or "null"
		end

		local topKiller = getTopKiller(stats.PlayerStats)
	
		local function formatPlayerList( playerStats )
			if not playerStats then return "[]" end
			local parts = {}
			for steamId, stats in pairs( playerStats ) do
				if type( steamId ) == "number" then
					for teamNumber = 1, 2 do
						local entry = stats[teamNumber]
						if entry and entry.timePlayed and entry.timePlayed > 0 then
							parts[#parts + 1] = StringFormat( '{"sid":%s,"team":%d,"plyd":%.1f,"score":%d}',
								tostring( steamId ), teamNumber,
								entry.timePlayed,
								entry.score or 0
							)
						end
					end
				end
			end
			return "[" .. table.concat( parts, "," ) .. "]"
		end
		
		local function getTopRtDamage( rtTotals )
			if not rtTotals then return "null" end
			local topSteamId = nil
			local topDamage  = 6500 -- ~3 rt
			for steamId, damage in pairs( rtTotals ) do
				if damage > topDamage then
					topDamage  = damage
					topSteamId = steamId
				end
			end
			return topSteamId and tostring( topSteamId ) or "null"
		end

		local topMarineRtDamage = getTopRtDamage( myRtTotals.marineRtDamage )
		local topAlienRtDamage  = getTopRtDamage( myRtTotals.alienRtDamage )
		
		-- "gamemode" lets ns2xp skip winstreak updates on combat maps (gCombatModeActive is set by sourcecombatv2).
		local RoundGamemode = gCombatModeActive == true and "combat" or "ns2"
		Print( "%s", StringFormat( ' >;> ROUNDEND | {"result":"%s","length":%.2f,"marinecomm":%s,"aliencomm":%s,"topkiller":%s,"topmarinertdmg":%s,"topalienrtdmg":%s,"gamemode":"%s","players":%s}',
			RoundResult, RoundLength, marineComm, alienComm, topKiller, topMarineRtDamage, topAlienRtDamage, RoundGamemode, formatPlayerList( stats.PlayerStats )
		) )

		
	end )
end
