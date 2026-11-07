local Plugin = ...
local Shine = Shine
local StringFormat = string.format
local ALL_CHAT_COOLDOWN = 60

local function GetPlayerTeamNumber( Player )
	if Player and Player.GetTeamNumber then
		return Player:GetTeamNumber()
	end
	return nil
end

local function IsActiveRound()
	local GameInfo = GetGameInfoEntity and GetGameInfoEntity()
	return GameInfo and GameInfo.state == kGameState.Started
end

local function GetQueuePosition( Client )
	local RRQueue = Shine.Plugins and Shine.Plugins[ "mngareadyroomqueue" ]
	if not RRQueue or not RRQueue.Enabled or not RRQueue.GetPosition then
		return nil
	end

	local SteamID = Client and Client.GetUserId and Client:GetUserId()
	if not SteamID or SteamID < 1 then return nil end

	return RRQueue:GetPosition( SteamID )
end

local function GetClientName( Client )
	if Shine.GetClientName then
		return Shine.GetClientName( Client )
	end

	local Player = Client and Client.GetControllingPlayer and Client:GetControllingPlayer()
	return Player and Player.GetName and Player:GetName() or "Unknown"
end

function Plugin:ApplySpectatorAllChatLimitConfig()
	local Config = self.Config and self.Config.SpectatorAllChatLimit or {}

	self.SpectatorAllChatLimitEnabled = Config.Enabled ~= false
	self.SpectatorAllChatLimitAllowedQueuedSpectators =
		math.floor( math.max( 0, tonumber( Config.AllowedQueuedSpectators ) or 5 ) )
	self.SpectatorAllChatLimitCooldown = ALL_CHAT_COOLDOWN
	self.SpectatorAllChatLimitAdminBypassPermission =
		Config.AdminBypassPermission or "mnga.spectatorchat.bypass"
	self.SpectatorAllChatLimitNotifyCooldown =
		math.max( 0, tonumber( Config.NotifyCooldown ) or 10 )
	self.SpectatorAllChatLimitLastNotify = self.SpectatorAllChatLimitLastNotify or {}
	self.SpectatorAllChatLimitLastAllChat = self.SpectatorAllChatLimitLastAllChat or {}

	Print( "%s", StringFormat(
		"[specchat] config enabled=%s allowedQueuedSpectators=%d cooldown=%.1f adminBypassPermission=%s notifyCooldown=%.1f",
		tostring( self.SpectatorAllChatLimitEnabled ),
		self.SpectatorAllChatLimitAllowedQueuedSpectators,
		self.SpectatorAllChatLimitCooldown,
		tostring( self.SpectatorAllChatLimitAdminBypassPermission ),
		self.SpectatorAllChatLimitNotifyCooldown
	) )
end

local function HasBypass( self, Client )
	local Permission = self.SpectatorAllChatLimitAdminBypassPermission
	if not Permission or Permission == "" then return false end
	return Shine.HasAccess and Shine:HasAccess( Client, Permission )
end

local function NotifyRedirected( self, Client, Remaining )
	local Cooldown = self.SpectatorAllChatLimitNotifyCooldown or 10
	if Cooldown <= 0 then return end

	local SteamID = Client and Client.GetUserId and Client:GetUserId()
	if not SteamID then return end

	local Now = Shared.GetTime()
	local LastNotify = self.SpectatorAllChatLimitLastNotify
	if LastNotify[ SteamID ] and LastNotify[ SteamID ] + Cooldown > Now then
		return
	end

	LastNotify[ SteamID ] = Now
	Shine:NotifyColour( Client, 255, 200, 100,
		StringFormat(
			"Spectator all-chat has a %d-second cooldown (%d seconds remaining). Your message was sent to spectator team chat.",
			self.SpectatorAllChatLimitCooldown or 60,
			math.ceil( Remaining )
		) )
end

function Plugin:ClearSpectatorAllChatCooldown( Client, Reason )
	if not Client or Client:GetIsVirtual() then return end
	local SteamID = Client and Client.GetUserId and Client:GetUserId()
	if not SteamID or SteamID == 0 then return end
	if self.SpectatorAllChatLimitLastAllChat then
		self.SpectatorAllChatLimitLastAllChat[ SteamID ] = nil
	end
	if self.SpectatorAllChatLimitLastNotify then
		self.SpectatorAllChatLimitLastNotify[ SteamID ] = nil
	end
	Print( "%s", StringFormat( "[specchat] cleared cooldown | steamId=%s reason=%s",
		tostring( SteamID ), tostring( Reason or "unspecified" ) ) )
end

function Plugin:CleanupSpectatorAllChatLimit()
	self.SpectatorAllChatLimitLastAllChat = {}
	self.SpectatorAllChatLimitLastNotify = {}
	Print( "[specchat] cooldown state cleared during plugin cleanup." )
end

function Plugin:PlayerSay( Client, Message )
	if not self.SpectatorAllChatLimitEnabled then return end
	if not Client or not Message or Message.teamOnly then return end
	if Client:GetIsVirtual() then return end
	if not IsActiveRound() then return end

	local Player = Client:GetControllingPlayer()
	if not Player then return end

	local TeamNumber = GetPlayerTeamNumber( Player )
	if TeamNumber ~= kSpectatorIndex and not Client:GetIsSpectator() then
		return
	end

	if HasBypass( self, Client ) then return end

	local Position = GetQueuePosition( Client )
	local Allowed = self.SpectatorAllChatLimitAllowedQueuedSpectators or 5
	if Position and Position <= Allowed then return end

	local Now = Shared.GetTime()
	local SteamID = Client:GetUserId()
	local Cooldown = self.SpectatorAllChatLimitCooldown or 60
	local LastAllChat = self.SpectatorAllChatLimitLastAllChat[ SteamID ]
	local Remaining = LastAllChat and LastAllChat + Cooldown - Now or 0
	if Remaining <= 0 then
		self.SpectatorAllChatLimitLastAllChat[ SteamID ] = Now
		Print( "%s", StringFormat(
			"[specchat] allowed cooldown all-chat | time=%.2f name=%s steamId=%s queuePosition=%s cooldown=%.1f",
			Now, GetClientName( Client ), tostring( SteamID ), tostring( Position ), Cooldown
		) )
		return
	end

	Message.teamOnly = true
	NotifyRedirected( self, Client, Remaining )

	Print( "%s", StringFormat(
		"[specchat] redirected cooldown all-chat to team-chat | time=%.2f name=%s steamId=%s queuePosition=%s allowed=%d remaining=%.2f",
		Now,
		GetClientName( Client ),
		tostring( SteamID ),
		tostring( Position ),
		Allowed,
		Remaining
	) )
end
