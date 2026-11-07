local Plugin = ...

local Shine = Shine
local Time = os.time
local ToString = tostring
local Ceil = math.ceil
local Clamp = math.Clamp
local Max = math.max

local DEFAULT_REASON = "No reason given."
local LIST_PERMISSION = "sh_ungag"
local MAX_GAGS_PER_MESSAGE = 15

Plugin.DependsOnPlugins = {
	"basecommands"
}

local function GetAdminName( Client )
	if not Client then return "Console" end

	local Player = Client:GetControllingPlayer()
	return Player and Player:GetName() or "Console"
end

local function GetTargetName( Client )
	local Player = Client and Client:GetControllingPlayer()
	return Player and Player:GetName() or "Unknown"
end

local function FormatDuration( Duration )
	return Duration == 0 and "permanently" or "for "..string.TimeToString( Duration )
end

function Plugin:IsExpired( Entry, Now )
	if type( Entry ) ~= "table" then return true end

	local Expires = tonumber( Entry.Expires )
	if not Expires then return true end

	return Expires ~= 0 and Expires <= ( Now or Time() )
end

function Plugin:RemoveExpiredEntries()
	local Now = Time()
	local Changed = false
	local Stores = { self.Config.Gagged, self.Config.GameGagged }

	for i = 1, #Stores do
		for ID, Entry in pairs( Stores[ i ] ) do
			if self:IsExpired( Entry, Now ) then
				Stores[ i ][ ID ] = nil
				Changed = true
			end
		end
	end

	if Changed then
		self:SaveConfig()
		self:NotifyGagDataChanged()
	end
end

function Plugin:GetEntry( Store, ID )
	local Entry = Store[ ID ]
	if not Entry then return nil end
	if not self:IsExpired( Entry ) then return Entry end

	Store[ ID ] = nil
	self:SaveConfig()
	return nil
end

function Plugin:IsGameGagApplicable( Client )
	local Gamerules = GetGamerules and GetGamerules()
	if not Gamerules or Gamerules:GetGameState() ~= kGameState.Started then return false end

	local Player = Client and Client:GetControllingPlayer()
	if not Player then return false end

	local TeamNumber = Player:GetTeamNumber()
	return TeamNumber == kTeam1Index or TeamNumber == kTeam2Index
end

-- Client -> NS2ID string, so the per-voice-packet gag check does not convert
-- the ID on every call.
local ClientIDStrings = setmetatable( {}, { __mode = "k" } )

function Plugin:GetActiveGagType( Client )
	if not Client then return nil end

	local ID = ClientIDStrings[ Client ]
	if not ID then
		ID = ToString( Client:GetUserId() )
		ClientIDStrings[ Client ] = ID
	end
	if self:GetEntry( self.Config.Gagged, ID ) then return "gag" end
	if self:GetEntry( self.Config.GameGagged, ID ) and self:IsGameGagApplicable( Client ) then
		return "gaggame"
	end

	return nil
end

function Plugin:IsClientGagged( Client )
	return self:GetActiveGagType( Client ) ~= nil
end

function Plugin:AddGag( Store, ID, Name, Duration, AdminName, AdminID, Reason )
	ID = ToString( ID )
	local Now = Time()
	Store[ ID ] = {
		ID = ID,
		Name = Name,
		Duration = Duration,
		Issued = Now,
		Expires = Duration == 0 and 0 or Now + Duration,
		GaggedBy = AdminName,
		GaggerID = AdminID,
		Reason = Reason
	}
	self:SaveConfig()
	self:NotifyGagDataChanged()
	Shared.Message( string.format( "[MNGAGags] Stored gag for %s [%s].", Name, ID ) )
end

function Plugin:ClearLegacyGag( ID )
	local Enabled, BaseCommands = Shine:IsExtensionEnabled( "basecommands" )
	if not Enabled or not BaseCommands then return false end

	local NumericID = tonumber( ID )
	local IDString = ToString( ID )
	local Removed = BaseCommands.Gagged and BaseCommands.Gagged[ NumericID ] ~= nil
	if BaseCommands.Gagged then BaseCommands.Gagged[ NumericID ] = nil end

	if BaseCommands.Config and BaseCommands.Config.GaggedPlayers
	and BaseCommands.Config.GaggedPlayers[ IDString ] then
		BaseCommands.Config.GaggedPlayers[ IDString ] = nil
		BaseCommands:SaveConfig()
		Removed = true
	end

	return Removed
end

function Plugin:RemoveAllGags( ID )
	ID = ToString( ID )
	local Removed = self.Config.Gagged[ ID ] ~= nil or self.Config.GameGagged[ ID ] ~= nil
	self.Config.Gagged[ ID ] = nil
	self.Config.GameGagged[ ID ] = nil
	if Removed then self:SaveConfig() end

	local LegacyRemoved = self:ClearLegacyGag( ID )
	if Removed or LegacyRemoved then
		self:NotifyGagDataChanged()
		Shared.Message( string.format( "[MNGAGags] Removed all gags for NS2ID %s.", ID ) )
	end
	return LegacyRemoved or Removed
end

function Plugin:NotifyGagDataChanged()
	if not self.Enabled then return end
	local Clients = Shine:GetClientsWithAccess( LIST_PERMISSION )
	if #Clients > 0 then
		self:SendNetworkMessage( Clients, "GagDataChanged", {}, true )
	end
end

local function NotifyIssuer( Client, Message )
	if not Client then return end
	Shine:NotifyDualColour( Client, 255, 160, 0, "[Gag] ", 255, 255, 255, Message )
end

-- NotifyIssuer with MNGA_Name() arguments resolved to the issuer's SSB alias.
local function NotifyIssuerNames( Client, Format, ... )
	if not Client then return end
	MNGA_NotifyNamesDual( Client, 255, 160, 0, "[Gag] ", 255, 255, 255, Format, ... )
end

local function EchoChatToSender( Client, Message )
	local Player = Client and Client:GetControllingPlayer()
	if not Player or type( Message ) ~= "table" or type( Message.message ) ~= "string"
	or Message.message == "" then
		return false
	end

	local TeamOnly = Message.teamOnly == true
	Server.SendNetworkMessage( Player, "Chat", BuildChatMessage(
		TeamOnly,
		Player:GetName(),
		Player.locationId,
		Player:GetTeamNumber(),
		Player:GetTeamType(),
		Message.message
	), true )

	return true
end

function Plugin:PlayerSay( Client, Message )
	if not self:IsClientGagged( Client ) then return end

	EchoChatToSender( Client, Message )
	return ""
end

-- Voice is gated outside every Shine CanPlayerHearPlayer hook. Shine plugin
-- hooks run at MAX_PRIORITY + 0.5, so a standalone hook at MAX_PRIORITY (SPVC
-- proximity voice) can return an authoritative true for VoiceChannel.Entity or
-- global alltalk before this plugin is asked. Wrapping
-- NS2Gamerules:GetCanPlayerHearPlayer outside Shine's replacement blocks every
-- channel, whatever other voice mods do. The gag short-circuits before any
-- GetClientMuted call, so the muted-voice indicator never reveals a gag.
local VoiceGuardLogged = {}

local function IsSpeakerGagged( Listener, Speaker )
	if Listener == Speaker then return false end

	local Self = Shine.Plugins.mngagags
	if not Self or not Self.Enabled then return false end

	local Config = Self.Config
	if next( Config.Gagged ) == nil and next( Config.GameGagged ) == nil then return false end

	local SpeakerClient = Server.GetOwner( Speaker )
	local GagType = SpeakerClient and Self:GetActiveGagType( SpeakerClient )
	if not GagType then return false end

	local ID = ClientIDStrings[ SpeakerClient ]
	if not VoiceGuardLogged[ ID ] then
		VoiceGuardLogged[ ID ] = true
		Shared.Message( string.format( "[MNGAGags] Voice blocked for %s speaker %s (first packet only).",
			GagType, ToString( ID ) ) )
	end
	return true
end

local function InstallVoiceGuard()
	if MNGAGagsVoiceGuardInstalled then return end

	local Inner = NS2Gamerules and NS2Gamerules.GetCanPlayerHearPlayer
	if not Inner then
		Shared.Message( "[MNGAGags] ERROR: NS2Gamerules:GetCanPlayerHearPlayer missing; voice gags not enforced." )
		return
	end
	MNGAGagsVoiceGuardInstalled = true

	-- Explicit parameters: Shine's code-generated hooks size their argument
	-- lists from the wrapped function, so avoid varargs here.
	local function GagGuard( Gamerules, Listener, Speaker, ChannelType )
		if IsSpeakerGagged( Listener, Speaker ) then return false end
		return Inner( Gamerules, Listener, Speaker, ChannelType )
	end

	if Shine.ReplaceClassMethod then
		Shine.ReplaceClassMethod( "NS2Gamerules", "GetCanPlayerHearPlayer", GagGuard )
	else
		NS2Gamerules.GetCanPlayerHearPlayer = GagGuard
	end
	Shared.Message( "[MNGAGags] Voice gag guard installed outside Shine voice hooks." )
end

function Plugin:CreateCommands()
	local function Add( Client, Target, Duration, Reason, IsGameGag )
		if Target:GetIsVirtual() then
			Shine:NotifyError( Client, "Bots cannot be gagged." )
			return
		end

		local ID = Target:GetUserId()
		local AdminName = GetAdminName( Client )
		local AdminID = Client and Client:GetUserId() or 0
		local Name = GetTargetName( Target )
		local Store = IsGameGag and self.Config.GameGagged or self.Config.Gagged
		self:AddGag( Store, ID, Name, Duration, AdminName, AdminID, Reason )

		Shine:AdminPrint( nil, "%s %s %s %s (%s).", true,
			Shine.GetClientInfo( Client ), IsGameGag and "game-gagged" or "gagged",
			Shine.GetClientInfo( Target ), FormatDuration( Duration ), Reason )
		NotifyIssuerNames( Client, "%s was %s %s. Reason: %s",
			MNGA_Name( ID, Name ), IsGameGag and "game-gagged" or "gagged", FormatDuration( Duration ), Reason )
	end

	local function AddID( Client, ID, Duration, Reason, IsGameGag )
		local Target = Shine.GetClientByNS2ID( ID )
		local AdminName = GetAdminName( Client )
		local AdminID = Client and Client:GetUserId() or 0
		local Name = GetTargetName( Target )
		local Store = IsGameGag and self.Config.GameGagged or self.Config.Gagged
		self:AddGag( Store, ID, Name, Duration, AdminName, AdminID, Reason )

		Shine:AdminPrint( nil, "%s %s %s[%s] %s (%s).", true,
			Shine.GetClientInfo( Client ), IsGameGag and "game-gagged" or "gagged",
			Name, ToString( ID ), FormatDuration( Duration ), Reason )
		NotifyIssuerNames( Client, "%s [%s] was %s %s. Reason: %s",
			MNGA_Name( ID, Name ), ToString( ID ), IsGameGag and "game-gagged" or "gagged",
			FormatDuration( Duration ), Reason )
	end

	local function AddDurationAndReason( Command )
		Command:AddParam{ Type = "time", Min = 0, Round = true, Optional = true,
			Default = self.Config.DefaultGagTime, Help = "duration" }
		Command:AddParam{ Type = "string", Optional = true, TakeRestOfLine = true,
			Default = DEFAULT_REASON, Help = "reason" }
	end

	local Gag = self:BindCommand( "sh_gag", "gag", function( Client, Target, Duration, Reason )
		Add( Client, Target, Duration, Reason, false )
	end )
	Gag:AddParam{ Type = "client", NotSelf = true }
	AddDurationAndReason( Gag )
	Gag:Help( "Gags a player. Durations persist across map changes; 0 is permanent." )

	local GagID = self:BindCommand( "sh_gagid", "gagid", function( Client, ID, Duration, Reason )
		AddID( Client, ID, Duration, Reason, false )
	end )
	GagID:AddParam{ Type = "steamid", Error = "Please specify an NS2 ID to gag." }
	AddDurationAndReason( GagID )
	GagID:Help( "Gags an NS2 ID. Durations persist across map changes; 0 is permanent." )

	local GagGame = self:BindCommand( "sh_gaggame", "gaggame", function( Client, Target, Duration, Reason )
		Add( Client, Target, Duration, Reason, true )
	end )
	GagGame:AddParam{ Type = "client", NotSelf = true }
	AddDurationAndReason( GagGame )
	GagGame:Help( "Gags a player only during live rounds while on Marines or Aliens; 0 is permanent." )

	local GagGameID = self:BindCommand( "sh_gaggameid", "gaggameid", function( Client, ID, Duration, Reason )
		AddID( Client, ID, Duration, Reason, true )
	end )
	GagGameID:AddParam{ Type = "steamid", Error = "Please specify an NS2 ID to game-gag." }
	AddDurationAndReason( GagGameID )
	GagGameID:Help( "Game-gags an NS2 ID; 0 is permanent." )

	local function Ungag( Client, Target )
		local ID = Target:GetUserId()
		if not self:RemoveAllGags( ID ) then
			Shine:NotifyError( Client, string.format( "%s is not gagged.", GetTargetName( Target ) ) )
			return
		end

		Shine:AdminPrint( nil, "%s ungagged %s.", true,
			Shine.GetClientInfo( Client ), Shine.GetClientInfo( Target ) )
		NotifyIssuerNames( Client, "%s was ungagged.", MNGA_Name( ID, GetTargetName( Target ) ) )
	end

	local Ungag = self:BindCommand( "sh_ungag", "ungag", Ungag )
	Ungag:AddParam{ Type = "client" }
	Ungag:Help( "Removes all normal and game gags from a player." )

	local UngagID = self:BindCommand( "sh_ungagid", "ungagid", function( Client, ID )
		if not self:RemoveAllGags( ID ) then
			Shine:NotifyError( Client, string.format( "%s is not gagged.", ToString( ID ) ) )
			return
		end

		Shine:AdminPrint( nil, "%s ungagged %s.", true,
			Shine.GetClientInfo( Client ), ToString( ID ) )
		NotifyIssuer( Client, string.format( "%s was ungagged.", ToString( ID ) ) )
	end )
	UngagID:AddParam{ Type = "steamid", Error = "Please specify an NS2 ID to ungag." }
	UngagID:Help( "Removes all normal and game gags from an NS2 ID." )
end

local function AddRows( Rows, Store, GagType )
	for ID, Entry in pairs( Store ) do
		Rows[ #Rows + 1 ] = {
			ID = ID,
			Name = Entry.Name or "Unknown",
			GagType = GagType,
			Duration = tonumber( Entry.Duration ) or 0,
			Expires = tonumber( Entry.Expires ) or 0,
			GaggedBy = Entry.GaggedBy or "Unknown",
			GaggerID = tonumber( Entry.GaggerID ) or 0,
			Reason = Entry.Reason or "",
			Issued = tonumber( Entry.Issued ) or 0
		}
	end
end

function Plugin:ReceiveRequestGagPage( Client, Request )
	if not Shine:GetPermission( Client, LIST_PERMISSION ) then
		Shared.Message( string.format( "[MNGAGags] Page request denied for %s: missing %s.",
			Shine.GetClientInfo( Client ), LIST_PERMISSION ) )
		return
	end
	self:RemoveExpiredEntries()
	local NumGagged, NumGameGagged = 0, 0
	for _ in pairs( self.Config.Gagged ) do NumGagged = NumGagged + 1 end
	for _ in pairs( self.Config.GameGagged ) do NumGameGagged = NumGameGagged + 1 end
	Shared.Message( string.format( "[MNGAGags] Page request from %s: page %s filter '%s', stored %s gags / %s game gags.",
		Shine.GetClientInfo( Client ), ToString( Request.Page ), ToString( Request.Filter ),
		ToString( NumGagged ), ToString( NumGameGagged ) ) )

	local Rows = {}
	AddRows( Rows, self.Config.Gagged, 1 )
	AddRows( Rows, self.Config.GameGagged, 2 )
	local Filter = string.UTF8Lower( Request.Filter or "" )
	if Filter ~= "" then
		local Filtered = {}
		for i = 1, #Rows do
			local Row = Rows[ i ]
			if Row.ID == Filter
			or string.StartsWith( string.UTF8Lower( Row.Name ), Filter )
			or string.StartsWith( string.UTF8Lower( Row.GaggedBy ), Filter ) then
				Filtered[ #Filtered + 1 ] = Row
			end
		end
		Rows = Filtered
	end

	local SortColumn = Clamp( Request.SortColumn, 1, 4 )
	table.sort( Rows, function( A, B )
		local AV, BV
		if SortColumn == 1 then
			AV, BV = string.UTF8Lower( A.Name ), string.UTF8Lower( B.Name )
		elseif SortColumn == 2 then
			AV, BV = A.GagType, B.GagType
		elseif SortColumn == 3 then
			AV, BV = string.UTF8Lower( A.GaggedBy ), string.UTF8Lower( B.GaggedBy )
		else
			AV, BV = A.Expires == 0 and math.huge or A.Expires, B.Expires == 0 and math.huge or B.Expires
		end
		if AV == BV then return A.ID < B.ID end
		return Request.SortAscending and AV < BV or AV > BV
	end )

	local MaxResults = Clamp( Request.MaxResults, 5, MAX_GAGS_PER_MESSAGE )
	local NumPages = Max( 1, Ceil( #Rows / MaxResults ) )
	local Page = Clamp( Request.Page, 1, NumPages )
	self:SendNetworkMessage( Client, "GagPage", {
		Page = Page, NumPages = NumPages, MaxResults = MaxResults, TotalNumResults = #Rows
	}, true )
	Shared.Message( string.format( "[MNGAGags] Sending page %s/%s with %s total rows.",
		ToString( Page ), ToString( NumPages ), ToString( #Rows ) ) )
	local First = ( Page - 1 ) * MaxResults + 1
	for i = First, math.min( First + MaxResults - 1, #Rows ) do
		self:SendNetworkMessage( Client, "GagData", Rows[ i ], true )
	end
end

function Plugin:Initialise()
	self:RemoveExpiredEntries()
	self:CreateCommands()

	-- Shine replaces GetCanPlayerHearPlayer in its first-Think "ReplaceMethods"
	-- hook (default priority); install from a MIN_PRIORITY Think so the guard
	-- wraps outside it.
	if not MNGAGagsVoiceGuardInstalled then
		Shine.Hook.Add( "Think", "MNGAGagsVoiceGuard", function()
			Shine.Hook.Remove( "Think", "MNGAGagsVoiceGuard" )
			InstallVoiceGuard()
		end, Shine.Hook.MIN_PRIORITY )
	end
	self.Enabled = true
	return true
end
