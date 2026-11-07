local Plugin = ...

local COOLDOWN_SECONDS = 60
local UPDATE_TIMER = "SpectatorAllChatCooldownUpdate"
local CHAT_HOOK = "MNGAAdministrationSpectatorAllChatObserved"

local function IsActiveRound()
	local GameInfo = GetGameInfoEntity and GetGameInfoEntity()
	return GameInfo and GameInfo.state == kGameState.Started
end

local function IsLocalSpectator()
	local Player = Client.GetLocalPlayer and Client.GetLocalPlayer()
	return Player and Player.GetTeamNumber and Player:GetTeamNumber() == kSpectatorIndex
end

local function IsOutsideAllowedQueuePositions()
	local Positions = MNGAReadyRoomQueuePositions
	local SteamID = Client.GetSteamId and Client.GetSteamId()
	local Position = Positions and SteamID and Positions[ tonumber( SteamID ) ]
	return not Position or Position > 5
end

function Plugin:IsSpectatorAllChatCooldownApplicable()
	return IsActiveRound() and IsLocalSpectator() and IsOutsideAllowedQueuePositions()
end

function Plugin:UpdateSpectatorAllChatPlaceholder()
	local Chatbox = Shine.Plugins and Shine.Plugins.chatbox
	if not Chatbox or not Chatbox.Enabled or not Chatbox.TextEntry then return end

	local Remaining = math.ceil( ( self.SpectatorAllChatCooldownEndTime or 0 ) - Shared.GetTime() )
	if Remaining <= 0 then
		self.SpectatorAllChatCooldownEndTime = nil
		self:DestroyTimer( UPDATE_TIMER )
	end

	local Placeholder
	if not Chatbox.TeamChat and Remaining > 0 and self:IsSpectatorAllChatCooldownApplicable() then
		Placeholder = string.format( "%d second allchat cooldown", Remaining )
	else
		Placeholder = Chatbox.TeamChat and Chatbox:GetPhrase( "SAY_TEAM" ) or Chatbox:GetPhrase( "SAY_ALL" )
	end

	if Chatbox.TextEntry.Placeholder ~= Placeholder then
		Chatbox.TextEntry:SetPlaceholderText( Placeholder )
	end
end

function Plugin:StartSpectatorAllChatClientCooldown()
	self.SpectatorAllChatCooldownEndTime = Shared.GetTime() + COOLDOWN_SECONDS
	self.SpectatorAllChatLastDisplayedSecond = nil
	self:DestroyTimer( UPDATE_TIMER )
	self:CreateTimer( UPDATE_TIMER, 1, -1, function()
		local Remaining = math.ceil( ( self.SpectatorAllChatCooldownEndTime or 0 ) - Shared.GetTime() )
		if Remaining ~= self.SpectatorAllChatLastDisplayedSecond then
			self.SpectatorAllChatLastDisplayedSecond = Remaining
			self:UpdateSpectatorAllChatPlaceholder()
		end
	end )
	self:UpdateSpectatorAllChatPlaceholder()
	Print( "%s", string.format( "[specchat] client observed permitted all-chat; local cooldown started duration=%d.",
		COOLDOWN_SECONDS ) )
end

function Plugin:HandleSpectatorAllChatMessageReceived( Data )
	if not Data or Data.TeamOnly or not self:IsSpectatorAllChatCooldownApplicable() then return end
	local LocalSteamID = Client.GetSteamId and tonumber( Client.GetSteamId() )
	if not LocalSteamID or tonumber( Data.SteamID ) ~= LocalSteamID then return end

	-- Only an echoed global message starts the cosmetic timer. Silent commands and
	-- server-redirected team messages therefore cannot desynchronise it.
	self:StartSpectatorAllChatClientCooldown()
end

function Plugin:InstallSpectatorAllChatChatboxPatch()
	local Chatbox = Shine.Plugins and Shine.Plugins.chatbox
	if not Chatbox or not Chatbox.Enabled or type( Chatbox.StartChat ) ~= "function" then return false end
	if Chatbox.MNGASpectatorAllChatOwner == self
		and Chatbox.StartChat == Chatbox.MNGASpectatorAllChatWrappedStartChat then
		return true
	end

	local Original = Chatbox.StartChat
	local Wrapped = function( ChatboxPlugin, Team )
		local Result = Original( ChatboxPlugin, Team )
		self:UpdateSpectatorAllChatPlaceholder()
		return Result
	end
	Chatbox.MNGASpectatorAllChatOwner = self
	Chatbox.MNGASpectatorAllChatOriginalStartChat = Original
	Chatbox.MNGASpectatorAllChatWrappedStartChat = Wrapped
	Chatbox.StartChat = Wrapped
	Print( "[specchat] client installed Shine chatbox cooldown placeholder integration." )
	return true
end

function Plugin:InitialiseSpectatorAllChatCooldown()
	self.SpectatorAllChatCooldownEndTime = nil
	self:InstallSpectatorAllChatChatboxPatch()
	Shine.Hook.Add( "OnChatMessageReceived", CHAT_HOOK, function( Data )
		self:HandleSpectatorAllChatMessageReceived( Data )
	end, Shine.Hook.MAX_PRIORITY )
	self.SpectatorAllChatPluginLoadHook = "MNGAAdministrationSpectatorAllChatPluginLoad"
	Shine.Hook.Add( "OnPluginLoad", self.SpectatorAllChatPluginLoadHook, function( Name, LoadedPlugin )
		if Name == "chatbox" and LoadedPlugin then
			self:InstallSpectatorAllChatChatboxPatch()
		end
	end )
end

function Plugin:CleanupSpectatorAllChatCooldown()
	self:DestroyTimer( UPDATE_TIMER )
	Shine.Hook.Remove( "OnChatMessageReceived", CHAT_HOOK )
	Shine.Hook.Remove( "OnPluginLoad", self.SpectatorAllChatPluginLoadHook or
		"MNGAAdministrationSpectatorAllChatPluginLoad" )
	local Chatbox = Shine.Plugins and Shine.Plugins.chatbox
	if Chatbox and Chatbox.MNGASpectatorAllChatOwner == self
		and Chatbox.StartChat == Chatbox.MNGASpectatorAllChatWrappedStartChat then
		Chatbox.StartChat = Chatbox.MNGASpectatorAllChatOriginalStartChat
	end
	if Chatbox and Chatbox.MNGASpectatorAllChatOwner == self then
		Chatbox.MNGASpectatorAllChatOriginalStartChat = nil
		Chatbox.MNGASpectatorAllChatWrappedStartChat = nil
		Chatbox.MNGASpectatorAllChatOwner = nil
	end
	self.SpectatorAllChatCooldownEndTime = nil
	Print( "[specchat] client cooldown state and chatbox integration cleaned up." )
end
