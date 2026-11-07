local Plugin = ...

local Shine = Shine
local StringFormat = string.format

-- Shounen-only extension to Shine's stock Steam ban plugin. Adds exact IPv4
-- correlation, durable custom-operation retries, and a combined manual sync.
-- Off by default: main MaNGA must not enable this (see .codex/docs/banssync.md).
-- With SharedBans.Enabled = false no hook, timer or command is installed.
-- The file names stay shounen_* so existing caches and queues carry over.

local CACHE_PATH = "config://shine/shounen_ip_bans_cache.json"
local QUEUE_PATH = "config://shine/shounen_ban_pending.json"
local RETRY_INTERVAL = 30
local INSTALL_INTERVAL = 1
local INSTALL_TIMER = "MNGASharedBansInstall"
local RETRY_TIMER = "MNGASharedBansRetry"
local HOOK_ID = "MNGASharedBans"
local LOAD_PROBE_URL = "https://api.ns2manga.com/"

local State

local function ResetState()
	State = {
		IPBanned = {},
		Revision = 0,
		Connections = {},
		DerivedGuard = {},
		Pending = {},
		Ready = false
	}
end
ResetState()

local function Log( FormatString, ... )
	-- Print() formats its first argument, so names containing "%" must stay in the arguments.
	Print( "%s", "[shounen_bans] " .. StringFormat( FormatString, ... ) )
end

local function TableCount( Value )
	local Count = 0
	for _ in pairs( Value or {} ) do Count = Count + 1 end
	return Count
end

local function CanonicalIPv4( Value )
	if type( Value ) ~= "string" then return nil end
	-- IPAddressToString normally returns only the address, but tolerate an
	-- IPv4 address followed by a transport port for engine-version variance.
	local Address = string.match( Value, "^(%d+%.%d+%.%d+%.%d+):?%d*$" )
	if not Address then return nil end
	local A, B, C, D = string.match( Address, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$" )
	A, B, C, D = tonumber( A ), tonumber( B ), tonumber( C ), tonumber( D )
	if not A or A > 255 or B > 255 or C > 255 or D > 255 then return nil end
	if A == 0 or A == 127 then return nil end
	if A == 10 or ( A == 172 and B >= 16 and B <= 31 )
		or ( A == 192 and B == 168 ) or ( A == 169 and B == 254 )
		or A >= 224 then return nil end
	return StringFormat( "%d.%d.%d.%d", A, B, C, D )
end

local function GetClientIP( Client )
	if not Client or Client:GetIsVirtual() then return nil end
	local Success, Result = pcall( function()
		return IPAddressToString( Server.GetClientAddress( Client ) )
	end )
	if not Success then
		Log( "failed reading client address steamID=%s error=%s",
			tostring( Client:GetUserId() ), tostring( Result ) )
		return nil
	end
	return CanonicalIPv4( Result )
end

local function IsValidIPEntry( IP, Entry )
	if not CanonicalIPv4( IP ) or type( Entry ) ~= "table" then return false end
	if not string.match( tostring( Entry.SourceSteamID or "" ), "^%d+$" ) then return false end
	if type( Entry.Reason ) ~= "string" or type( Entry.BannedBy ) ~= "string" then return false end
	if tonumber( Entry.BannerID ) == nil or tonumber( Entry.Issued ) == nil then return false end
	return true
end

local function ValidateIPSnapshot( Document )
	if type( Document ) ~= "table" or type( Document.IPBanned ) ~= "table" then
		return nil, "missing IPBanned object"
	end
	local Validated = {}
	for RawIP, Entry in pairs( Document.IPBanned ) do
		local IP = CanonicalIPv4( RawIP )
		if not IP or not IsValidIPEntry( IP, Entry ) then
			return nil, "invalid IP entry for " .. tostring( RawIP )
		end
		Validated[ IP ] = {
			SourceSteamID = tostring( Entry.SourceSteamID ),
			Name = tostring( Entry.Name or "<unknown>" ),
			BannedBy = Entry.BannedBy,
			BannerID = tonumber( Entry.BannerID ) or 0,
			Reason = Entry.Reason,
			Issued = tonumber( Entry.Issued ) or 0
		}
	end
	return Validated
end

local function SaveCache()
	local Success, ErrorMessage = Shine.SaveJSONFile( {
		IPBanned = State.IPBanned,
		Revision = State.Revision,
		SavedAt = os.time()
	}, CACHE_PATH )
	if not Success then
		Log( "failed saving IP cache error=%s", tostring( ErrorMessage ) )
	end
end

local function LoadCache()
	local Document = Shine.LoadJSONFile( CACHE_PATH )
	if type( Document ) ~= "table" then
		Log( "no valid saved IP cache found path=%s", CACHE_PATH )
		return
	end
	local Validated, ErrorMessage = ValidateIPSnapshot( Document )
	if not Validated then
		Log( "rejected saved IP cache error=%s", tostring( ErrorMessage ) )
		return
	end
	State.IPBanned = Validated
	State.Revision = tonumber( Document.Revision ) or 0
	Log( "loaded saved IP cache count=%d revision=%s", TableCount( Validated ), tostring( State.Revision ) )
end

local function SavePending()
	local Success, ErrorMessage = Shine.SaveJSONFile( { Pending = State.Pending }, QUEUE_PATH )
	if not Success then
		Log( "failed saving pending queue error=%s", tostring( ErrorMessage ) )
	end
end

local function LoadPending()
	local Document = Shine.LoadJSONFile( QUEUE_PATH )
	if type( Document ) == "table" and type( Document.Pending ) == "table" then
		State.Pending = Document.Pending
	end
	Log( "loaded pending mutation queue count=%d", TableCount( State.Pending ) )
end

local function BanPlugin()
	local BanExtension = Shine.Plugins and Shine.Plugins.ban
	if BanExtension and BanExtension.Enabled then return BanExtension end
	return nil
end

local function BanArguments()
	local BanExtension = BanPlugin()
	local Arguments = BanExtension and BanExtension.Config and BanExtension.Config.BansSubmitArguments
	if type( Arguments ) ~= "table" then return nil end
	if type( Arguments.auth ) ~= "string" or Arguments.auth == "" then return nil end
	if type( Arguments.server_id ) ~= "string" or Arguments.server_id == "" then return nil end
	return Arguments
end

local function Endpoint( Suffix )
	local BanExtension = BanPlugin()
	local URL = BanExtension and BanExtension.Config and BanExtension.Config.BansURL or ""
	if type( URL ) ~= "string" then return nil end
	local Base = string.gsub( URL, "/snapshot/?$", "" )
	if Base == URL then return nil end
	return Base .. "/" .. Suffix
end

local function CopyRequestArguments( Extra )
	local Source = BanArguments()
	if not Source then return nil end
	local Result = {}
	for Key, Value in pairs( Source ) do Result[ Key ] = Value end
	for Key, Value in pairs( Extra or {} ) do Result[ Key ] = Value end
	return Result
end

local SendPending
local OnClientConnect

local function QueueMutation( Operation, SteamID, IP )
	local Key = Operation .. "|" .. tostring( SteamID ) .. "|" .. tostring( IP )
	local Existing = State.Pending[ Key ]
	State.Pending[ Key ] = {
		OperationID = Key,
		Operation = Operation,
		SteamID = tostring( SteamID ),
		IP = IP,
		Attempts = tonumber( Existing and Existing.Attempts ) or 0,
		QueuedAt = tonumber( Existing and Existing.QueuedAt ) or os.time(),
		NextAttempt = tonumber( Existing and Existing.NextAttempt ) or 0,
		InFlight = Existing and Existing.InFlight or nil
	}
	SavePending()
	Log( "queued mutation operation=%s steamID=%s ip=%s", Operation, tostring( SteamID ), tostring( IP ) )
	SendPending( Key )
end

SendPending = function( Key )
	local Item = State.Pending[ Key ]
	if not Item or Item.InFlight then return end
	local URL = Endpoint( Item.Operation )
	local Params = CopyRequestArguments( {
		steam_id = Item.SteamID,
		ip = Item.IP,
		operation_id = Item.OperationID
	} )
	if not URL or not Params then
		Log( "cannot send queued mutation; ban web configuration is incomplete operation=%s",
			tostring( Item.Operation ) )
		return
	end
	Item.InFlight = true
	Item.Attempts = ( tonumber( Item.Attempts ) or 0 ) + 1
	SavePending()
	Shine.HTTPRequestWithRetry( URL, "POST", Params, {
		OnSuccess = function( Body, RequestError )
			Item.InFlight = nil
			local Decoded = Body and json.decode( Body ) or nil
			if not RequestError and type( Decoded ) == "table" and Decoded.success == true then
				State.Pending[ Key ] = nil
				SavePending()
				Log( "mutation accepted operation=%s steamID=%s ip=%s attempts=%d",
					tostring( Item.Operation ), tostring( Item.SteamID ), tostring( Item.IP ), Item.Attempts )
				return
			end
			Item.NextAttempt = os.time() + math.min( 300, 2 ^ math.min( Item.Attempts, 8 ) )
			SavePending()
			Log( "mutation rejected; retained for retry operation=%s steamID=%s ip=%s error=%s",
				tostring( Item.Operation ), tostring( Item.SteamID ), tostring( Item.IP ),
				tostring( RequestError or ( Decoded and Decoded.error ) or "invalid response" ) )
		end,
		OnFailure = function()
			Item.InFlight = nil
			Item.NextAttempt = os.time() + math.min( 300, 2 ^ math.min( Item.Attempts, 8 ) )
			SavePending()
			Log( "mutation timed out; retained for retry operation=%s steamID=%s ip=%s attempts=%d",
				tostring( Item.Operation ), tostring( Item.SteamID ), tostring( Item.IP ), Item.Attempts )
		end
	}, 3, 5 )
end

local function RetryPending( Force )
	local Now = os.time()
	for Key, Item in pairs( State.Pending ) do
		if Force or ( not Item.InFlight and Now >= ( tonumber( Item.NextAttempt ) or 0 ) ) then
			Item.InFlight = nil -- A map restart cannot retain a real HTTP request.
			SendPending( Key )
		end
	end
end

local function RecheckConnectedClients()
	for SteamID in pairs( State.Connections ) do
		local ConnectedClient = Shine.GetClientByNS2ID( tonumber( SteamID ) )
		if ConnectedClient then OnClientConnect( ConnectedClient ) end
	end
end

local function RequestIPSnapshot( Client )
	local URL = Endpoint( "snapshot" )
	local Params = CopyRequestArguments()
	if not URL or not Params then
		Log( "cannot refresh IP snapshot; ban web configuration is incomplete" )
		if Client then Shine:AdminPrint( Client, "Shounen IP ban sync is not configured." ) end
		return
	end
	Log( "requesting IP snapshot url=%s", URL )
	Shine.HTTPRequestWithRetry( URL, "POST", Params, {
		OnSuccess = function( Body, RequestError )
			local Decoded = Body and json.decode( Body ) or nil
			if RequestError or type( Decoded ) ~= "table" then
				Log( "IP snapshot failed; retaining cache error=%s", tostring( RequestError or "invalid JSON" ) )
				if Client then Shine:AdminPrint( Client, "Shounen IP ban sync failed; retained cache." ) end
				return
			end
			if Decoded.success == false or Decoded.error ~= nil then
				Log( "IP snapshot API rejected request; retaining cache error=%s",
					tostring( Decoded.error or "unspecified API error" ) )
				if Client then
					Shine:AdminPrint( Client, "Shounen IP ban sync was rejected by the API; retained cache." )
				end
				return
			end
			local Validated, ErrorMessage = ValidateIPSnapshot( Decoded )
			if not Validated then
				Log( "IP snapshot rejected; retaining cache error=%s", tostring( ErrorMessage ) )
				if Client then Shine:AdminPrint( Client, "Shounen IP snapshot was invalid; retained cache." ) end
				return
			end
			State.IPBanned = Validated
			State.Revision = tonumber( Decoded.Revision ) or 0
			SaveCache()
			Log( "IP snapshot loaded count=%d revision=%s",
				TableCount( Validated ), tostring( State.Revision ) )
			if Client then
				Shine:AdminPrint( Client, "Shounen IP bans updated: %d exact addresses (revision %s).",
					true, TableCount( Validated ), tostring( State.Revision ) )
			end
			-- Close the small startup race where a client connected after the
			-- disk cache loaded but before the fresh web snapshot arrived.
			RecheckConnectedClients()
		end,
		OnFailure = function()
			Log( "IP snapshot timed out; retaining cache" )
			if Client then Shine:AdminPrint( Client, "Shounen IP ban sync timed out; retained cache." ) end
		end
	}, 3, 5 )
end

local function OnPlayerBanned( ID, Name, Duration )
	local SteamID = tostring( ID )
	if tonumber( Duration ) ~= 0 then
		Log( "temporary ban will not associate IP steamID=%s duration=%s", SteamID, tostring( Duration ) )
		return
	end
	if State.DerivedGuard[ SteamID ] then
		Log( "derived guard suppressed source association steamID=%s", SteamID )
		return
	end
	local Connection = State.Connections[ SteamID ]
	if not Connection or not Connection.IP then
		Log( "permanent ban has no connected exact IPv4; Steam-only steamID=%s name=%s",
			SteamID, tostring( Name ) )
		return
	end
	QueueMutation( "associate-ip", SteamID, Connection.IP )
end

OnClientConnect = function( Client )
	if not Client or Client:GetIsVirtual() then return end
	local SteamID = tostring( Client:GetUserId() )
	local IP = GetClientIP( Client )
	local Player = Client:GetControllingPlayer()
	local Name = Player and Player:GetName() or "<unknown>"
	State.Connections[ SteamID ] = { IP = IP, Name = Name, ConnectedAt = os.time() }
	Log( "client observed steamID=%s ip=%s name=%s", SteamID, tostring( IP ), tostring( Name ) )
	if not IP then return end

	local Source = State.IPBanned[ IP ]
	if not Source then return end
	local BanExtension = BanPlugin()
	if not BanExtension then
		Log( "banned IP matched before Shine ban plugin became ready steamID=%s ip=%s", SteamID, IP )
		return
	end
	if BanExtension:IsIDBanned( SteamID ) then
		local Existing = BanExtension:GetBanEntry( SteamID )
		Log( "banned IP account already Steam-banned steamID=%s ip=%s source=%s",
			SteamID, IP, Source.SourceSteamID )
		Shine:DisconnectClient( Client, BanExtension:GetBanMessage( Existing ) )
		return
	end

	State.DerivedGuard[ SteamID ] = true
	local CallOK, BanOK, BanError = pcall( function()
		return BanExtension:AddBan(
			SteamID, Name, 0, Source.BannedBy,
			tonumber( Source.BannerID ) or 0, Source.Reason
		)
	end )
	State.DerivedGuard[ SteamID ] = nil
	if not CallOK or not BanOK then
		Log( "failed local derived ban steamID=%s ip=%s error=%s",
			SteamID, IP, tostring( CallOK and BanError or BanOK ) )
		return
	end

	Log( "exact IP match created permanent Steam ban steamID=%s ip=%s source=%s",
		SteamID, IP, Source.SourceSteamID )
	QueueMutation( "mark-derived", SteamID, IP )
	local Entry = BanExtension:GetBanEntry( SteamID ) or Source
	Shine:DisconnectClient( Client, BanExtension:GetBanMessage( Entry ) )
end

local function OnClientDisconnect( Client )
	if not Client or Client:GetIsVirtual() then return end
	local SteamID = tostring( Client:GetUserId() )
	State.Connections[ SteamID ] = nil
	State.DerivedGuard[ SteamID ] = nil
	Log( "cleared connected-address record steamID=%s", SteamID )
end

function Plugin:InstallSharedBansWhenReady()
	if State.Ready then return true end
	if not BanPlugin() or not Shine.HTTPRequestWithRetry then return false end

	Shine.Hook.Add( "OnPlayerBanned", HOOK_ID, OnPlayerBanned )
	local Command = self:BindCommand( "sh_shounenbansync", nil, function( Client )
		local BanExtension = BanPlugin()
		if BanExtension then BanExtension:LoadBansFromWeb() end
		RequestIPSnapshot( Client )
		RetryPending( true )
		Shine:AdminPrint( Client, "Updating Shounen Steam and IP bans from the web..." )
	end, false, false )
	Command:Help( "Reload Shounen Steam/IP bans and retry queued central mutations." )

	State.Ready = true
	local Arguments = BanArguments()
	Log( "integration ready serverID=%s cachedIPs=%d pending=%d",
		tostring( Arguments and Arguments.server_id or "unconfigured" ),
		TableCount( State.IPBanned ), TableCount( State.Pending ) )
	RequestIPSnapshot()
	RetryPending( true )

	local Clients, Count = Shine.GetAllClients()
	for i = 1, Count do
		OnClientConnect( Clients[ i ] )
	end

	self:CreateTimer( RETRY_TIMER, RETRY_INTERVAL, -1, function()
		RetryPending( false )
	end )
	return true
end

-- Crash test for the map-load request bug, off by default and independent of
-- SharedBans.Enabled. Deliberately sends from Initialise: the same call and the same
-- moment as the old snapshot, but no ban code. Empty servers only.
local function SendLoadHTTPProbe()
	Log( "[loadprobe] sending url=%s", LOAD_PROBE_URL )
	Shine.HTTPRequestWithRetry( LOAD_PROBE_URL, "POST", {}, {
		OnSuccess = function( Body, RequestError )
			Log( "[loadprobe] response length=%d error=%s", #( Body or "" ), tostring( RequestError ) )
		end,
		OnFailure = function()
			Log( "[loadprobe] timed out" )
		end
	}, 3, 5 )
end

function Plugin:InitialiseSharedBans()
	local Config = self.Config and self.Config.SharedBans
	if Config and Config.LoadHTTPProbe == true then
		SendLoadHTTPProbe()
	end

	if not Config or Config.Enabled ~= true then
		Log( "disabled by config" )
		return
	end

	ResetState()
	LoadCache()
	LoadPending()

	Shine.Hook.Add( "ClientConnect", HOOK_ID, OnClientConnect )
	Shine.Hook.Add( "ClientDisconnect", HOOK_ID, OnClientDisconnect )

	-- Never send a request from here: Initialise runs during map load, and an HTTP
	-- request at that point crashed about 10% of map changes (exit 11/139, Lua PANIC).
	-- Timers only start ticking once the server is running, as in Shine's ban plugin.
	Log( "module loaded; web requests wait until after map load" )
	self:CreateTimer( INSTALL_TIMER, INSTALL_INTERVAL, -1, function()
		if self:InstallSharedBansWhenReady() then
			self:DestroyTimer( INSTALL_TIMER )
		end
	end )
end

function Plugin:CleanupSharedBans()
	Shine.Hook.Remove( "ClientConnect", HOOK_ID )
	Shine.Hook.Remove( "ClientDisconnect", HOOK_ID )
	Shine.Hook.Remove( "OnPlayerBanned", HOOK_ID )
	self:DestroyTimer( INSTALL_TIMER )
	self:DestroyTimer( RETRY_TIMER )
	ResetState()
end
