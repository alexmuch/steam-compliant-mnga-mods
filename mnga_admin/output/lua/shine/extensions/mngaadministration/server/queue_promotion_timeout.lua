local Plugin = ...
local Shine = Shine
local StringFormat = string.format

local function GetConfig( Self )
	return Self.Config and Self.Config.QueuePromotionTimeout or {}
end

local function GetPlayerName( Client )
	local Player = Client and Client:GetControllingPlayer()
	return Player and Player.GetName and Player:GetName() or "<unknown>"
end

function Plugin:CancelQueuePromotionTimeout( Client, Reason )
	if not Client or not self.QueuePromotionTimeouts then return false end

	local SteamID = Client:GetUserId()
	local Pending = SteamID and self.QueuePromotionTimeouts[ SteamID ]
	if not Pending or Pending.Client ~= Client then return false end

	self.QueuePromotionTimeouts[ SteamID ] = nil
	Print( "%s", StringFormat(
		"[queue-timeout] cancelled | steamId=%s name=%s token=%d reason=%s",
		tostring( SteamID ), GetPlayerName( Client ), Pending.Token,
		tostring( Reason or "unspecified" )
	) )
	return true
end

function Plugin:ClearQueuePromotionTimeouts( Reason )
	local PendingTimeouts = self.QueuePromotionTimeouts
	if not PendingTimeouts then return end

	local Count = 0
	for _ in pairs( PendingTimeouts ) do
		Count = Count + 1
	end
	self.QueuePromotionTimeouts = {}
	Print( "%s", StringFormat(
		"[queue-timeout] cleared all | count=%d reason=%s",
		Count, tostring( Reason or "unspecified" )
	) )
end

function Plugin:ArmQueuePromotionTimeout( Client )
	local Config = GetConfig( self )
	if Config.Enabled == false then
		Print( "[queue-timeout] promotion observed but feature is disabled" )
		return false
	end

	local Gamerules = GetGamerules()
	if not Gamerules or not Gamerules:GetGameStarted() then
		-- Print( StringFormat(
			-- "[queue-timeout] skipped arm | steamId=%s name=%s reason=game_not_started state=%s",
			-- tostring( Client and Client:GetUserId() or "none" ), GetPlayerName( Client ),
			-- tostring( Gamerules and Gamerules:GetGameState() or "none" )
		-- ) )
		return false
	end

	if not Client or not Shine:IsValidClient( Client ) or Client:GetIsVirtual() then
		Print( "[queue-timeout] ERROR | cannot arm timeout for invalid or virtual client" )
		return false
	end

	local Player = Client:GetControllingPlayer()
	if not Player or Player:GetTeamNumber() ~= kTeamReadyRoom then
		Print( "%s", StringFormat(
			"[queue-timeout] skipped arm | steamId=%s name=%s reason=not_in_ready_room team=%s",
			tostring( Client:GetUserId() ), GetPlayerName( Client ),
			tostring( Player and Player:GetTeamNumber() or "none" )
		) )
		return false
	end

	local Timeout = math.max( tonumber( Config.Timeout ) or 20, 1 )
	local SteamID = Client:GetUserId()
	if not SteamID or SteamID < 1 then
		Print( "[queue-timeout] ERROR | cannot arm timeout without a valid Steam ID" )
		return false
	end

	self.QueuePromotionTimeouts = self.QueuePromotionTimeouts or {}
	self.QueuePromotionTimeoutSequence = ( self.QueuePromotionTimeoutSequence or 0 ) + 1
	local Token = self.QueuePromotionTimeoutSequence
	self.QueuePromotionTimeouts[ SteamID ] = {
		Client = Client,
		Token = Token,
		Deadline = Shared.GetTime() + Timeout
	}

	Print( "%s", StringFormat(
		"[queue-timeout] armed | steamId=%s name=%s token=%d timeout=%.1f deadline=%.2f",
		tostring( SteamID ), GetPlayerName( Client ), Token, Timeout,
		Shared.GetTime() + Timeout
	) )
	Shine:NotifyDualColour( Client, 255, 80, 80, "[QUEUE]", 255, 255, 255,
		StringFormat( "Your slot is ready. Join Marines or Aliens within %d seconds or return to spectator.",
			math.ceil( Timeout ) ) )

	self:SimpleTimer( Timeout, function()
		local Pending = self.QueuePromotionTimeouts
			and self.QueuePromotionTimeouts[ SteamID ]
		if not Pending or Pending.Token ~= Token or Pending.Client ~= Client then
			Print( "%s", StringFormat(
				"[queue-timeout] stale timer ignored | steamId=%s token=%d",
				tostring( SteamID ), Token
			) )
			return
		end

		local Gamerules = GetGamerules()
		if not Gamerules or not Gamerules:GetGameStarted() then
			self.QueuePromotionTimeouts[ SteamID ] = nil
			Print( "%s", StringFormat(
				"[queue-timeout] expiry cancelled | steamId=%s name=%s token=%d reason=game_not_started state=%s",
				tostring( SteamID ), GetPlayerName( Client ), Token,
				tostring( Gamerules and Gamerules:GetGameState() or "none" )
			) )
			return
		end

		self.QueuePromotionTimeouts[ SteamID ] = nil
		if not Shine:IsValidClient( Client ) then
			Print( "%s", StringFormat(
				"[queue-timeout] expiry ignored | steamId=%s token=%d reason=invalid_client",
				tostring( SteamID ), Token
			) )
			return
		end

		local CurrentPlayer = Client:GetControllingPlayer()
		local TeamNumber = CurrentPlayer and CurrentPlayer:GetTeamNumber()
		if not CurrentPlayer or TeamNumber ~= kTeamReadyRoom then
			Print( "%s", StringFormat(
				"[queue-timeout] expiry ignored | steamId=%s name=%s token=%d reason=not_in_ready_room team=%s",
				tostring( SteamID ), GetPlayerName( Client ), Token,
				tostring( TeamNumber or "none" )
			) )
			return
		end

		Print( "%s", StringFormat(
			"[queue-timeout] expired | steamId=%s name=%s token=%d action=move_to_spectator",
			tostring( SteamID ), GetPlayerName( Client ), Token
		) )
		Shine:NotifyDualColour( Client, 255, 80, 80, "[QUEUE]", 255, 255, 255,
			"You did not join a team in time. Your player slot was given to the next queued player." )

		local Success, NewPlayer = Gamerules:JoinTeam(
			CurrentPlayer, kSpectatorIndex, true, true
		)
		Print( "%s", StringFormat(
			"[queue-timeout] spectator move result | steamId=%s token=%d success=%s newTeam=%s",
			tostring( SteamID ), Token, tostring( Success ),
			tostring( NewPlayer and NewPlayer:GetTeamNumber() or "none" )
		) )
	end )

	return true
end

return Plugin
