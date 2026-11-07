local Plugin = ...
local Shine = Shine

Shine.LoadPluginFile( "mngareadyroomqueue", "spectator_first.lua", Plugin )

local StringFormat = string.format
local TableConcat = table.concat
local ToString = tostring
local PROCESS_TIMER = "mngareadyroomqueue_process"
local CAPACITY_TIMER = "mngareadyroomqueue_capacity"
local SHADOW_REALM_DENIAL_COOLDOWN = 5
-- After a map load, restored entries that have not reconnected yet hold their
-- place for this long, so the fastest loader cannot take the first free slot.
local RESTORE_GRACE_SECONDS = 30

Plugin.QueueHistoryFile = "config://shine/temp/mnga_rr_queue_history.json"
Plugin.LegacyQueueHistoryFile = "config://shine/temp/rr_queue_history.json"
Plugin.ShadowRealmRestrictionsFile = "config://shine/temp/mnga_rr_queue_shadow_realm.json"
Plugin.LeaveBansFile = "config://shine/temp/mnga_rr_queue_leave_bans.json"

local function SafeCall( Object, MethodName, Default, ... )
	if not Object or type( Object[ MethodName ] ) ~= "function" then return Default end
	local Success, Value = pcall( Object[ MethodName ], Object, ... )
	if not Success then return Default end
	return Value
end

local function GetSteamID( Client, Player )
	return tonumber( SafeCall( Client, "GetUserId", nil ) or SafeCall( Player, "GetSteamId", 0 ) ) or 0
end

local function GetPlayer( Client )
	return SafeCall( Client, "GetControllingPlayer", nil )
end

local function GetTeam( Player )
	return SafeCall( Player, "GetTeamNumber", -1 )
end

local function IsConnectedSpectator( Client )
	return Client ~= nil and SafeCall( Client, "GetIsSpectator", false )
		and GetTeam( GetPlayer( Client ) ) == kSpectatorIndex
end

function Plugin:Log( Event, Message )
	if not self.Config.Debug and Event ~= "startup" and Event ~= "error" then return end
	Print( "%s", StringFormat( "[mngarrq] mode=authoritative event=%s %s", Event, Message or "" ) )
end

-- Retain rare, actionable production evidence without requiring the general
-- lifecycle debug stream or the expensive capacity snapshots.
function Plugin:LogImportant( Event, Message )
	Print( "%s", StringFormat( "[mngarrq] mode=authoritative event=%s %s", Event, Message or "" ) )
end

-- Shadow state is separate from active admission state in spectator_first.lua.
function Plugin:EndSpectatorFirstShadow( SteamID, Entry, Phase )
	self:LogImportant( "spectator_first_shadow", StringFormat(
		"token=%d phase=%s steam_id=%s start_eligible=%s connected=%s confirmed=%s age=%.2f",
		Entry.Token, Phase, SteamID, ToString( Entry.StartEligible ),
		ToString( Entry.Connected == true ), ToString( Entry.Confirmed == true ),
		Shared.GetTime() - Entry.StartedAt ) )
	if self.SpectatorFirstShadowPending[ SteamID ] == Entry then
		self.SpectatorFirstShadowPending[ SteamID ] = nil
	end
end

function Plugin:ClearSpectatorFirstShadow( Phase )
	for SteamID, Entry in pairs( self.SpectatorFirstShadowPending or {} ) do
		self:EndSpectatorFirstShadow( SteamID, Entry, Phase )
	end
end

function Plugin:ReportSpectatorFirstShadowObserver()
	local Callbacks = Shine.Hook.GetEventCallbacks
		and Shine.Hook.GetEventCallbacks( "CheckConnectionIsSpectator" ) or {}
	local Registered = false
	for i = 1, #Callbacks do
		if Callbacks[ i ] == self.SpectatorFirstShadowAssignmentWrapper then Registered = true end
	end
	self:LogImportant( "spectator_first_shadow", StringFormat(
		"phase=observer_status registered=%s callbacks=%d assignment_calls=%d scope=all_admissions spectator_first=%s",
		ToString( Registered ), #Callbacks, self.SpectatorFirstShadowAssignmentCalls or 0, ToString( self.Config.SpectatorFirst ) ) )
	-- Shine's registration list is not proof of later execution/ownership. Actual
	-- assignment records are required; do not retrofit native callbacks here.
end

function Plugin:SweepSpectatorFirstShadow()
	if not self.Config.SpectatorFirstShadow then return end
	if not self.SpectatorFirstShadowStatusReported then
		self.SpectatorFirstShadowStatusReported = true
		self:ReportSpectatorFirstShadowObserver()
	end
	local Now = Shared.GetTime()
	local Snapshot
	for SteamID, Entry in pairs( self.SpectatorFirstShadowPending ) do
		if Now >= Entry.ExpiresAt then
			self:EndSpectatorFirstShadow( SteamID, Entry, "expired" )
		elseif not Entry.Sampled and Now - Entry.StartedAt >= 5 then
			-- One loading observation per attempt, sharing one snapshot per sweep.
			-- It records real occupancy, not a simulated diverted-client count.
			Entry.Sampled = true
			Snapshot = Snapshot or self:GetCapacitySnapshot( false )
			self:LogImportant( "spectator_first_shadow", StringFormat(
				"token=%d phase=loading_sample steam_id=%s start_eligible=%s age=%.2f connected=%s ep=%d sh=%d es=%d total=%d",
				Entry.Token, SteamID, ToString( Entry.StartEligible ), Now - Entry.StartedAt,
				ToString( Entry.Connected == true ), Snapshot.EnginePlayers,
				Snapshot.SettledHumans, Snapshot.EngineSpectators, Snapshot.RawTotal ) )
		end
	end
end

function Plugin:RecordSpectatorFirstShadowDecision( SteamID, Reserve, Assignment, Capacity, FrontID )
	if not self.Config.SpectatorFirstShadow then return end
	SteamID = tonumber( SteamID )
	if not SteamID or SteamID <= 0 then return end
	self:SweepSpectatorFirstShadow()
	local Previous = self.SpectatorFirstShadowPending[ SteamID ]
	if Previous then self:EndSpectatorFirstShadow( SteamID, Previous, "superseded" ) end
	local SpectatorCapacity = Capacity.EngineSpectators < Capacity.MaxSpectators
		and Capacity.AdjustedTotal < Capacity.MaxPlayers + Capacity.MaxSpectators
	local StartOpen = Capacity.EnginePlayers < math.min( self.Config.PlayerSlotLimit, Capacity.MaxPlayers )
	local StartEligible = StartOpen and Capacity.SettledHumans < self.Config.PlayerSlotLimit
		and ( Assignment == "public_player_slot" or Assignment == "reserved_player_slot" )
	local Rejected = Reserve and self.Config.ConnectionReservation == "enforce"
	local Predicted = not StartEligible and "spectator_no_auto_handoff"
		or ( SpectatorCapacity and "divert_then_handoff" or "spectator_capacity_fallback" )
	self.SpectatorFirstShadowToken = self.SpectatorFirstShadowToken + 1
	local Now = Shared.GetTime()
	local Entry = {
		Token = self.SpectatorFirstShadowToken, StartedAt = Now,
		StartEligible = StartEligible, StartOpen = StartOpen,
		ExpiresAt = Now + math.max( tonumber( self.Config.SpectatorFirstShadowLifetime ) or 180, 30 )
	}
	self:LogImportant( "spectator_first_shadow", StringFormat(
		"token=%d phase=decision steam_id=%s predicted=%s actual=%s start_open=%s start_eligible=%s assignment=%s spectator_capacity=%s ep=%d sh=%d es=%d ms=%d raw=%d adj=%d max_players=%d limit=%d reserved=%d queue=%d position=%s historic=%s front=%s correlation=steam_id_only",
		Entry.Token, SteamID, Predicted, Rejected and "enforcement_reject" or "abstain",
		ToString( StartOpen ), ToString( StartEligible ), Assignment, ToString( SpectatorCapacity ),
		Capacity.EnginePlayers, Capacity.SettledHumans, Capacity.EngineSpectators,
		Capacity.MaxSpectators, Capacity.RawTotal, Capacity.AdjustedTotal, Capacity.MaxPlayers,
		self.Config.PlayerSlotLimit, Capacity.ReservedSlots, #self.Queue,
		ToString( self.Positions[ SteamID ] ), ToString( self.Metadata[ SteamID ] and self.Metadata[ SteamID ].Historic == true or false ),
		ToString( FrontID or 0 ) ) )
	-- Abstaining here is NOT proof of admission: vanilla/other hooks still decide.
	if Rejected then
		self:EndSpectatorFirstShadow( SteamID, Entry, "enforcement_reject" )
	else
		self.SpectatorFirstShadowPending[ SteamID ] = Entry
	end
end

function Plugin:RecordSpectatorFirstShadowAssignment( SteamID, Result )
	self.SpectatorFirstShadowAssignmentCalls = ( self.SpectatorFirstShadowAssignmentCalls or 0 ) + 1
	SteamID = tonumber( SteamID )
	local Entry = SteamID and self.SpectatorFirstShadowPending[ SteamID ]
	if Entry and Shared.GetTime() >= Entry.ExpiresAt then
		self:EndSpectatorFirstShadow( SteamID, Entry, "expired" )
		Entry = nil
	end
	local Snapshot = self:GetCapacitySnapshot( false )
	self:LogImportant( "spectator_first_shadow", StringFormat(
		"token=%s phase=assignment steam_id=%s original_spectator=%s start_eligible=%s age=%s ep=%d es=%d total=%d original_observation=true",
		ToString( Entry and Entry.Token or "none" ), ToString( SteamID ), ToString( Result ),
		Entry and ToString( Entry.StartEligible ) or "unknown",
		Entry and StringFormat( "%.2f", Shared.GetTime() - Entry.StartedAt ) or "unknown",
		Snapshot.EnginePlayers, Snapshot.EngineSpectators, Snapshot.RawTotal ) )
end

function Plugin:NS2EventHook( Name, Original )
	if Name ~= "CheckConnectionIsSpectator"
		or not ( self.Config.SpectatorFirstShadow or self.Config.SpectatorFirst ) then return end
	local Wrapper
	local function ApplyResult( SteamID, Result, ... )
		if self.Enabled and not self.AuthorityDisabled
			and self.SpectatorFirstShadowAssignmentWrapper == Wrapper then
			local Success, Value = pcall( self.ApplySpectatorFirstAssignment, self, SteamID, Result )
			if Success then return Value, ... end
			self:LogImportant( "error", "reason=spectator_first_assignment_failed fallback=native error="..ToString( Value ) )
		end
		return Result, ...
	end
	local function ObserveResult( SteamID, ... )
		if self.Enabled and not self.AuthorityDisabled and self.Config.SpectatorFirstShadow
			and self.SpectatorFirstShadowAssignmentWrapper == Wrapper then
			-- Diagnostics cannot turn a successful native callback into an error.
			local Success, Error = pcall( self.RecordSpectatorFirstShadowAssignment, self, SteamID, ... )
			if not Success and not self.SpectatorFirstShadowAssignmentError then
				self.SpectatorFirstShadowAssignmentError = true
				Print( "%s", "[mngarrq] event=shadow_assignment_error error="..ToString( Error ) )
			end
		end
		if self.Config.SpectatorFirst then return ApplyResult( SteamID, ... ) end
		return ...
	end
	Wrapper = function( SteamID, ... )
		-- Preserve original arguments and all trailing returns (including nils). Never
		-- invoke the original twice. Active mode may override only its first result.
		return ObserveResult( SteamID, Original( SteamID, ... ) )
	end
	self.SpectatorFirstShadowAssignmentWrapper = Wrapper
	self.SFWrapperReady = true
	if self.Config.SpectatorFirstShadow then
		self:LogImportant( "spectator_first_shadow", "phase=observer_registration event_name=CheckConnectionIsSpectator wrapper=owned" )
	end
	return true, Wrapper
end

function Plugin:RecordSpectatorFirstShadowLifecycle( Phase, Client )
	if not self.Config.SpectatorFirstShadow or not Client or SafeCall( Client, "GetIsVirtual", false ) then return end
	local SteamID = GetSteamID( Client )
	local Entry = self.SpectatorFirstShadowPending[ SteamID ]
	local Now = Shared.GetTime()
	if Entry and Now >= Entry.ExpiresAt then
		self:EndSpectatorFirstShadow( SteamID, Entry, "expired" )
		Entry = nil
	end
	-- A callback for an older connected client must not consume the replacement
	-- attempt. Before ClientConnect the engine exposes only the Steam ID; log
	-- this limitation rather than claiming transport-level token correlation.
	local BoundToken = self.SpectatorFirstShadowClientTokens[ Client ]
	if Entry and ( ( Entry.Client and Entry.Client ~= Client )
		or ( BoundToken and BoundToken ~= Entry.Token ) ) then
		self:LogImportant( "spectator_first_shadow", StringFormat(
			"token=%d phase=client_mismatch callback=%s steam_id=%s retained=true", Entry.Token, Phase, SteamID ) )
		return
	end
	local Snapshot = self:GetCapacitySnapshot( false )
	local Available, Assignment = self:WouldConnectionConsumePlayerSlot( SteamID, Snapshot )
	local Position = self.Positions[ SteamID ]
	local Handoff = not Entry and "unknown_start"
		or ( Entry.StartEligible and "queue_then_try_readyroom"
			or ( Position and "preserve_existing_queue" or "leave_spectator" ) )
	if Entry then
		if Phase == "client_connect" then
			Entry.Connected = true
			Entry.Client = Client
			self.SpectatorFirstShadowClientTokens[ Client ] = Entry.Token
		end
		if Phase == "client_confirm" then Entry.Confirmed = true end
	end
	self:LogImportant( "spectator_first_shadow", StringFormat(
		"token=%s phase=%s steam_id=%s start_eligible=%s age=%s client_spectator=%s team=%s queue_position=%s handoff=%s current_slot=%s current_assignment=%s ep=%d sh=%d es=%d total=%d queue=%d",
		ToString( Entry and Entry.Token or "none" ), Phase, SteamID,
		Entry and ToString( Entry.StartEligible ) or "unknown",
		Entry and StringFormat( "%.2f", Now - Entry.StartedAt ) or "unknown",
		ToString( SafeCall( Client, "GetIsSpectator", false ) ), ToString( GetTeam( GetPlayer( Client ) ) ),
		ToString( Position ), Handoff, ToString( Available ), Assignment,
		Snapshot.EnginePlayers, Snapshot.SettledHumans, Snapshot.EngineSpectators, Snapshot.RawTotal, #self.Queue ) )
	-- current_slot is the REAL state: vanilla player arrivals still occupy their
	-- slot. It is not a counterfactual promotion prediction with that slot removed.
	if Entry and ( Phase == "client_confirm" or Phase == "client_disconnect" ) then
		self.SpectatorFirstShadowPending[ SteamID ] = nil
	end
end

function Plugin:LogVerbose( Event, Message )
	if not self.Config.VerboseDebug then return end
	Print( "%s", StringFormat( "[mngarrq] mode=authoritative event=%s %s", Event, Message or "" ) )
end

function Plugin:GetCapacitySnapshot( AdmissionCheck )
	local RawTotal = Server.GetNumClientsTotal()
	local AdjustedTotal = AdmissionCheck and math.max( RawTotal - 1, 0 ) or RawTotal
	local EngineSpectators = Server.GetNumSpectators()
	local Snapshot = {
		RawTotal = RawTotal,
		AdjustedTotal = AdjustedTotal,
		MaxPlayers = Server.GetMaxPlayers(),
		MaxSpectators = Server.GetMaxSpectators(),
		ReservedSlots = Server.GetReservedSlotLimit(),
		EngineSpectators = EngineSpectators,
		EnginePlayers = math.max( AdjustedTotal - EngineSpectators, 0 ),
		ShineClients = 0,
		SettledHumans = 0,
		ReadyRoomHumans = 0,
		MarineHumans = 0,
		AlienHumans = 0,
		SpectatorHumans = 0,
		OtherHumans = 0,
		NoPlayerHumans = 0,
		ClientSpectatorHumans = 0,
		ClientPlayerHumans = 0,
		PlayingBots = 0,
		SpectatorBots = 0,
		NoPlayerBots = 0
	}

	local Clients, Count = Shine.GetAllClients()
	Snapshot.ShineClients = Count
	for i = 1, Count do
		local Client = Clients[ i ]
		local IsVirtual = SafeCall( Client, "GetIsVirtual", false )
		local IsClientSpectator = SafeCall( Client, "GetIsSpectator", false )
		local Player = GetPlayer( Client )
		local Team = GetTeam( Player )

		if IsVirtual then
			if not Player then
				Snapshot.NoPlayerBots = Snapshot.NoPlayerBots + 1
			elseif Team == kSpectatorIndex then
				Snapshot.SpectatorBots = Snapshot.SpectatorBots + 1
			elseif Team == kTeamReadyRoom or Team == kTeam1Index or Team == kTeam2Index then
				Snapshot.PlayingBots = Snapshot.PlayingBots + 1
			end
		else
			if IsClientSpectator then
				Snapshot.ClientSpectatorHumans = Snapshot.ClientSpectatorHumans + 1
			else
				Snapshot.ClientPlayerHumans = Snapshot.ClientPlayerHumans + 1
			end
			if not Player then
				Snapshot.NoPlayerHumans = Snapshot.NoPlayerHumans + 1
			elseif Team == kTeamReadyRoom then
				Snapshot.ReadyRoomHumans = Snapshot.ReadyRoomHumans + 1
				Snapshot.SettledHumans = Snapshot.SettledHumans + 1
			elseif Team == kTeam1Index then
				Snapshot.MarineHumans = Snapshot.MarineHumans + 1
				Snapshot.SettledHumans = Snapshot.SettledHumans + 1
			elseif Team == kTeam2Index then
				Snapshot.AlienHumans = Snapshot.AlienHumans + 1
				Snapshot.SettledHumans = Snapshot.SettledHumans + 1
			elseif Team == kSpectatorIndex then
				Snapshot.SpectatorHumans = Snapshot.SpectatorHumans + 1
			else
				Snapshot.OtherHumans = Snapshot.OtherHumans + 1
			end
		end
	end

	Snapshot.SettledSlots = Snapshot.SettledHumans + Snapshot.PlayingBots
	Snapshot.EngineDelta = Snapshot.EnginePlayers - Snapshot.SettledSlots
	Snapshot.ClientFlagDelta = Snapshot.ClientPlayerHumans - Snapshot.SettledHumans
	Snapshot.Anomalous = Snapshot.EngineDelta ~= 0 or Snapshot.ClientFlagDelta ~= 0
		or Snapshot.EnginePlayers > self.Config.PlayerSlotLimit
		or Snapshot.SettledHumans > self.Config.PlayerSlotLimit
	return Snapshot
end

function Plugin:GetCapacityClientDetails()
	local Details = {}
	local Clients, Count = Shine.GetAllClients()
	for i = 1, Count do
		local Client = Clients[ i ]
		local Player = GetPlayer( Client )
		Details[ #Details + 1 ] = StringFormat( "%s:v%s:cs%s:p%s:t%s:%s",
			GetSteamID( Client, Player ), SafeCall( Client, "GetIsVirtual", false ) and 1 or 0,
			SafeCall( Client, "GetIsSpectator", false ) and 1 or 0, Player and 1 or 0,
			GetTeam( Player ), Player and ToString( SafeCall( Player, "GetClassName", "unknown" ) ) or "none" )
	end
	return Details
end

function Plugin:GetCapacitySignature( Snapshot )
	return TableConcat( {
		Snapshot.RawTotal, Snapshot.AdjustedTotal, Snapshot.MaxPlayers,
		Snapshot.MaxSpectators, Snapshot.ReservedSlots, Snapshot.EngineSpectators,
		Snapshot.EnginePlayers, Snapshot.ShineClients, Snapshot.SettledHumans,
		Snapshot.ReadyRoomHumans, Snapshot.MarineHumans, Snapshot.AlienHumans,
		Snapshot.SpectatorHumans, Snapshot.OtherHumans, Snapshot.NoPlayerHumans,
		Snapshot.ClientSpectatorHumans, Snapshot.ClientPlayerHumans,
		Snapshot.PlayingBots, Snapshot.SpectatorBots, Snapshot.NoPlayerBots
	}, ":" )
end

function Plugin:LogCapacity( Reason, AdmissionCheck, ForceSummary, SubjectSteamID, Extra, Snapshot, ForceDetail )
	if not self.Config.CapacityDebug then return Snapshot end
	Snapshot = Snapshot or self:GetCapacitySnapshot( AdmissionCheck )
	local Signature = self:GetCapacitySignature( Snapshot )
	local Now = Shared.GetTime()
	local EventKey = ToString( Reason )..":"..ToString( SubjectSteamID or 0 )
	if Signature == self.LastCapacitySignature then
		if not ForceSummary then return Snapshot end
		local EventCooldown = math.max( tonumber( self.Config.CapacityEventCooldown ) or 5, 1 )
		local LastEventTime = self.LastCapacityEventTimes[ EventKey ]
		if LastEventTime and Now - LastEventTime < EventCooldown then return Snapshot end
	end
	if ForceSummary then self.LastCapacityEventTimes[ EventKey ] = Now end
	self.LastCapacitySignature = Signature
	local _, FrontSteamID = self:GetEligibleFront()

	Print( "%s", StringFormat(
		"[mngarrq-cap] reason=%s subject=%s admission=%s tc=%d adj=%d mp=%d ms=%d rs=%d es=%d ep=%d lc=%d hc=%d sh=%d rr=%d m=%d a=%d sp=%d oh=%d np=%d csp=%d cpl=%d bots=%d bspec=%d bnp=%d ed=%d cd=%d limit=%d q=%d front=%s %s",
		ToString( Reason ), ToString( SubjectSteamID or 0 ), ToString( AdmissionCheck == true ),
		Snapshot.RawTotal, Snapshot.AdjustedTotal, Snapshot.MaxPlayers, Snapshot.MaxSpectators,
		Snapshot.ReservedSlots, Snapshot.EngineSpectators, Snapshot.EnginePlayers,
		Snapshot.ShineClients, Snapshot.ClientSpectatorHumans + Snapshot.ClientPlayerHumans,
		Snapshot.SettledHumans, Snapshot.ReadyRoomHumans,
		Snapshot.MarineHumans, Snapshot.AlienHumans, Snapshot.SpectatorHumans,
		Snapshot.OtherHumans, Snapshot.NoPlayerHumans, Snapshot.ClientSpectatorHumans,
		Snapshot.ClientPlayerHumans, Snapshot.PlayingBots, Snapshot.SpectatorBots,
		Snapshot.NoPlayerBots, Snapshot.EngineDelta, Snapshot.ClientFlagDelta,
		self.Config.PlayerSlotLimit, #self.Queue, ToString( FrontSteamID or 0 ),
		Extra or "" ) )

	if not Snapshot.Anomalous and not ForceDetail then return Snapshot end
	local Cooldown = math.max( tonumber( self.Config.CapacityDetailCooldown ) or 10, 1 )
	if not ForceDetail and self.LastCapacityDetailSignature == Signature
		and Now - ( self.LastCapacityDetailTime or 0 ) < Cooldown then return Snapshot end
	self.LastCapacityDetailSignature = Signature
	self.LastCapacityDetailTime = Now
	Print( "%s", StringFormat( "[mngarrq-cap-detail] reason=%s signature=%s clients=%s",
		ToString( Reason ), Signature, TableConcat( self:GetCapacityClientDetails(), ";" ) ) )
	return Snapshot
end

function Plugin:GetPosition( SteamID )
	return self.Positions[ tonumber( SteamID ) ]
end

function Plugin:GetQueuePosition( Client )
	return Client and self:GetPosition( GetSteamID( Client ) ) or nil
end

function Plugin:GetQueueCount()
	return #self.Queue
end

-- Connected human clients in queue order. Historic entries restored after a map
-- change have no client until the player reconnects, so they are only counted.
function Plugin:GetQueuedClients()
	local Clients = {}
	local Disconnected = 0
	for i = 1, #self.Queue do
		local Client = Shine.GetClientByNS2ID( self.Queue[ i ] )
		if Client and not SafeCall( Client, "GetIsVirtual", false ) then
			Clients[ #Clients + 1 ] = Client
		else
			Disconnected = Disconnected + 1
		end
	end
	return Clients, Disconnected
end

function Plugin:SaveShadowRealmRestrictions()
	local Entries = {}
	local Now = Shared.GetSystemTime()
	for SteamID, ExpiresAt in pairs( self.ShadowRealmRestrictions or {} ) do
		if ExpiresAt > Now then
			Entries[ #Entries + 1 ] = { SteamID = SteamID, ExpiresAt = ExpiresAt }
		end
	end
	local Saved, SaveError = Shine.SaveJSONFile( { Version = 1, Restrictions = Entries }, self.ShadowRealmRestrictionsFile )
	if not Saved then
		self:LogImportant( "error", "reason=shadow_realm_save_failed error="..ToString( SaveError ) )
	end
	self:LogImportant( "shadow_realm", StringFormat( "phase=save count=%d success=%s", #Entries, ToString( Saved ) ) )
	return Saved == true
end

function Plugin:LoadShadowRealmRestrictions()
	local Data = Shine.LoadJSONFile( self.ShadowRealmRestrictionsFile )
	local Now = Shared.GetSystemTime()
	local Loaded, Expired = 0, 0
	local Restrictions = Data and Data.Restrictions
	if Restrictions ~= nil and type( Restrictions ) ~= "table" then
		self:LogImportant( "error", "reason=shadow_realm_load_invalid restrictions_type="..type( Restrictions ) )
		Restrictions = nil
	end
	for i = 1, #( Restrictions or {} ) do
		local Entry = Restrictions[ i ]
		local SteamID = type( Entry ) == "table" and tonumber( Entry.SteamID ) or nil
		local ExpiresAt = type( Entry ) == "table" and tonumber( Entry.ExpiresAt ) or nil
		if SteamID and SteamID > 0 and ExpiresAt and ExpiresAt > Now then
			self.ShadowRealmRestrictions[ SteamID ] = ExpiresAt
			Loaded = Loaded + 1
		else
			Expired = Expired + 1
		end
	end
	self:LogImportant( "shadow_realm", StringFormat( "phase=load restored=%d expired=%d", Loaded, Expired ) )
	if Expired > 0 then self:SaveShadowRealmRestrictions() end
end

function Plugin:AddShadowRealmRestriction( SteamID, DurationSeconds )
	SteamID = tonumber( SteamID )
	if not SteamID or SteamID < 1 then return false end
	local Duration = math.max( tonumber( DurationSeconds ) or 600, 1 )
	local ExpiresAt = Shared.GetSystemTime() + Duration
	self.ShadowRealmRestrictions[ SteamID ] = ExpiresAt
	self.ShadowRealmDenialState[ SteamID ] = nil
	local RemovedFromQueue = self:RemoveSteamID( SteamID, "shadow_realm_restriction" )
	self:LogImportant( "shadow_realm", StringFormat(
		"phase=add steam_id=%s duration=%d expires_at=%d queue=%d removed_from_queue=%s",
		SteamID, Duration, ExpiresAt, #self.Queue, ToString( RemovedFromQueue ) ) )
	self:SaveShadowRealmRestrictions()
	return true
end

function Plugin:GetShadowRealmRestrictionRemaining( SteamID )
	SteamID = tonumber( SteamID )
	local ExpiresAt = SteamID and self.ShadowRealmRestrictions[ SteamID ]
	if not ExpiresAt then return nil end
	local Remaining = ExpiresAt - Shared.GetSystemTime()
	if Remaining > 0 then return Remaining end
	self.ShadowRealmRestrictions[ SteamID ] = nil
	self.ShadowRealmDenialState[ SteamID ] = nil
	self:LogImportant( "shadow_realm", StringFormat( "phase=expire steam_id=%s", SteamID ) )
	self:SaveShadowRealmRestrictions()
	return nil
end

--[[ Ready-check early-leave bans (mngareadycheck, .claude/docs/ready-check.md).
	Same effect as a Shadow-Realm restriction (no queueing, no leaving
	spectator) but stored separately with its own message, so admins can lift
	it with sh_readycheck_unban without touching Shadow-Realm votes. Saved on
	every change; ExpiresAt is wall-clock so it survives map changes. ]]
function Plugin:SaveLeaveBans()
	local Entries = {}
	local Now = Shared.GetSystemTime()
	for SteamID, Ban in pairs( self.LeaveBans or {} ) do
		if Ban.ExpiresAt > Now then
			Entries[ #Entries + 1 ] = { SteamID = SteamID, ExpiresAt = Ban.ExpiresAt, Name = Ban.Name, Reason = Ban.Reason }
		end
	end
	local Saved, SaveError = Shine.SaveJSONFile( { Version = 1, Bans = Entries }, self.LeaveBansFile )
	if not Saved then
		self:LogImportant( "error", "reason=leave_ban_save_failed error="..ToString( SaveError ) )
	end
	self:LogImportant( "leave_ban", StringFormat( "phase=save count=%d success=%s", #Entries, ToString( Saved ) ) )
	return Saved == true
end

function Plugin:LoadLeaveBans()
	local Data = Shine.LoadJSONFile( self.LeaveBansFile )
	local Bans = Data and Data.Bans
	if type( Bans ) ~= "table" then Bans = {} end
	local Now = Shared.GetSystemTime()
	local Loaded = 0
	for i = 1, #Bans do
		local Entry = Bans[ i ]
		local SteamID = type( Entry ) == "table" and tonumber( Entry.SteamID ) or nil
		local ExpiresAt = type( Entry ) == "table" and tonumber( Entry.ExpiresAt ) or nil
		if SteamID and SteamID > 0 and ExpiresAt and ExpiresAt > Now then
			self.LeaveBans[ SteamID ] = { ExpiresAt = ExpiresAt, Name = ToString( Entry.Name or "" ),
				Reason = ToString( Entry.Reason or "" ) }
			Loaded = Loaded + 1
		end
	end
	self:LogImportant( "leave_ban", StringFormat( "phase=load restored=%d", Loaded ) )
end

function Plugin:AddLeaveBan( SteamID, DurationSeconds, Name, Reason )
	SteamID = tonumber( SteamID )
	if not SteamID or SteamID < 1 then return false end
	local Duration = math.max( tonumber( DurationSeconds ) or 1800, 1 )
	local ExpiresAt = Shared.GetSystemTime() + Duration
	self.LeaveBans[ SteamID ] = { ExpiresAt = ExpiresAt, Name = ToString( Name or "" ), Reason = ToString( Reason or "" ) }
	self.ShadowRealmDenialState[ SteamID ] = nil
	local RemovedFromQueue = self:RemoveSteamID( SteamID, "leave_ban" )
	self:LogImportant( "leave_ban", StringFormat(
		"phase=add steam_id=%s duration=%d expires_at=%d reason=%s removed_from_queue=%s",
		SteamID, Duration, ExpiresAt, ToString( Reason ), ToString( RemovedFromQueue ) ) )
	self:SaveLeaveBans()
	return true
end

function Plugin:RemoveLeaveBan( SteamID )
	SteamID = tonumber( SteamID )
	local Ban = SteamID and self.LeaveBans[ SteamID ]
	if not Ban then return false end
	self.LeaveBans[ SteamID ] = nil
	self:LogImportant( "leave_ban", StringFormat( "phase=remove steam_id=%s", SteamID ) )
	self:SaveLeaveBans()
	return true, Ban.Name
end

function Plugin:GetLeaveBanRemaining( SteamID )
	SteamID = tonumber( SteamID )
	local Ban = SteamID and self.LeaveBans[ SteamID ]
	if not Ban then return nil end
	local Remaining = Ban.ExpiresAt - Shared.GetSystemTime()
	if Remaining > 0 then return Remaining end
	self.LeaveBans[ SteamID ] = nil
	self:LogImportant( "leave_ban", StringFormat( "phase=expire steam_id=%s", SteamID ) )
	self:SaveLeaveBans()
	return nil
end

function Plugin:GetLeaveBans()
	local List = {}
	local Now = Shared.GetSystemTime()
	for SteamID, Ban in pairs( self.LeaveBans ) do
		if Ban.ExpiresAt > Now then
			List[ #List + 1 ] = { SteamID = SteamID, Name = Ban.Name, Reason = Ban.Reason, Remaining = Ban.ExpiresAt - Now }
		end
	end
	table.sort( List, function( A, B ) return A.Remaining > B.Remaining end )
	return List
end

function Plugin:ReportLeaveBanDenial( Client, SteamID, Remaining, Action )
	local Now = Shared.GetTime()
	local State = self.ShadowRealmDenialState[ SteamID ]
	if State and Now - State.LastReportedAt < SHADOW_REALM_DENIAL_COOLDOWN then return end
	self.ShadowRealmDenialState[ SteamID ] = { LastReportedAt = Now, Suppressed = 0 }
	self:LogImportant( "leave_ban", StringFormat( "phase=deny steam_id=%s action=%s remaining=%d",
		SteamID, Action, math.ceil( Remaining ) ) )
	if not Client then return end
	local Seconds = math.max( math.ceil( Remaining or 0 ), 1 )
	Shine:NotifyColour( Client, 255, 112, 77, StringFormat(
		"[READY] You left a ready-checked game early and cannot %s for another %d:%02d.",
		Action == "enqueue" and "join the player-slot queue" or "leave spectator",
		math.floor( Seconds / 60 ), Seconds % 60 ) )
end

function Plugin:SweepShadowRealmRestrictions()
	local Now = Shared.GetSystemTime()
	local Changed = false
	for SteamID, ExpiresAt in pairs( self.ShadowRealmRestrictions ) do
		if ExpiresAt <= Now then
			self.ShadowRealmRestrictions[ SteamID ] = nil
			self.ShadowRealmDenialState[ SteamID ] = nil
			Changed = true
			self:LogImportant( "shadow_realm", StringFormat( "phase=expire steam_id=%s", SteamID ) )
		end
	end
	if Changed then self:SaveShadowRealmRestrictions() end
end

function Plugin:ReportShadowRealmDenial( Client, SteamID, Remaining, Action, Details )
	local Now = Shared.GetTime()
	local State = self.ShadowRealmDenialState[ SteamID ]
	if State and Now - State.LastReportedAt < SHADOW_REALM_DENIAL_COOLDOWN then
		State.Suppressed = State.Suppressed + 1
		return
	end
	local Suppressed = State and State.Suppressed or 0
	self.ShadowRealmDenialState[ SteamID ] = { LastReportedAt = Now, Suppressed = 0 }
	self:LogImportant( "shadow_realm", StringFormat(
		"phase=deny steam_id=%s action=%s remaining=%d queue=%d suppressed=%d %s",
		SteamID, Action, math.ceil( Remaining ), #self.Queue, Suppressed, Details or "" ) )
	if not Client then return end
	local Seconds = math.max( math.ceil( Remaining or 0 ), 1 )
	local Description = Action == "enqueue" and "join the player-slot queue" or "leave spectator"
	Shine:NotifyColour( Client, 255, 112, 77, StringFormat(
		"[Shadow-Realm] You cannot %s for another %d:%02d.",
		Description, math.floor( Seconds / 60 ), Seconds % 60 ) )
end

function Plugin:Reindex()
	self.Positions = {}
	for i = 1, #self.Queue do self.Positions[ self.Queue[ i ] ] = i end
end

function Plugin:GetEntry( SteamID )
	return self.Metadata[ tonumber( SteamID ) ]
end

function Plugin:IsPriority( SteamID, Client )
	local Entry = self.Metadata[ SteamID ]
	if Entry and ( Entry.SkipToken or Entry.Priority ) then return true end
	return self.Config.VIPPlayers.Enabled and Client
		and Shine:HasAccess( Client, self.Config.VIPPlayers.PermissionString ) or false
end

function Plugin:GetInsertPosition( SteamID, Client )
	if not self:IsPriority( SteamID, Client ) then return #self.Queue + 1 end
	local Position = 1
	for i = 1, #self.Queue do
		local ExistingID = self.Queue[ i ]
		local ExistingClient = Shine.GetClientByNS2ID( ExistingID )
		if self:IsPriority( ExistingID, ExistingClient ) then Position = Position + 1 else break end
	end
	return Position
end

function Plugin:BroadcastSnapshot( Reason, Target )
	self.QueueRevision = self.QueueRevision + 1
	self:SendNetworkMessage( Target, "QueueSnapshotReset", { Revision = self.QueueRevision }, true )
	for i = 1, #self.Queue do
		self:SendNetworkMessage( Target, "QueueStatus", {
			Revision = self.QueueRevision, SteamID = ToString( self.Queue[ i ] ), Position = i
		}, true )
	end
	self:Log( "broadcast", StringFormat( "reason=%s revision=%d count=%d target=%s",
		ToString( Reason ), self.QueueRevision, #self.Queue,
		Target and ToString( GetSteamID( Target ) ) or "all" ) )
end

-- [rrqdiag] Temporary label investigation: why a queued entry is or is not the
-- eligible front. Only called from rare events/admin commands, never per tick.
function Plugin:DescribeQueueEntry( SteamID )
	local Client = Shine.GetClientByNS2ID( SteamID )
	local Player = Client and GetPlayer( Client )
	local Entry = self.Metadata[ SteamID ]
	local Loading = self.SFLoading and self.SFLoading[ SteamID ]
	return StringFormat( "id=%s pos=%s client=%s name=%s is_spec_flag=%s team=%s connected_spec=%s sf_ready=%s sf_awaiting=%s sf_loading_left=%s sf_waiting=%s historic=%s",
		ToString( SteamID ), ToString( self.Positions[ SteamID ] ), ToString( Client ~= nil ),
		Client and ToString( Shine.GetClientName( Client ) ) or "-",
		ToString( SafeCall( Client, "GetIsSpectator", nil ) ), ToString( GetTeam( Player ) ),
		ToString( IsConnectedSpectator( Client ) ),
		ToString( Client and self.SFReady and self.SFReady[ Client ] == true ),
		ToString( self.SFQueueAwaiting and self.SFQueueAwaiting[ SteamID ] == true ),
		Loading and ToString( math.floor( Loading.Deadline - Shared.GetSystemTime() ) ) or "-",
		ToString( Client and self:IsSpectatorFirstWaiting( Client, SteamID ) ),
		ToString( Entry and Entry.Historic == true ) )
end

function Plugin:NotifyPosition( Client, Prefix )
	local Position = self:GetQueuePosition( Client )
	Print( "%s", StringFormat( "[rrqdiag] notify_position prefix=%s position=%s %s", ToString( Prefix ), ToString( Position ),
		Client and self:DescribeQueueEntry( GetSteamID( Client ) ) or "client=nil" ) )
	if not Position then return end
	Shine:NotifyColour( Client, 255, 180, 0, StringFormat( "%s Queue position: %d.", Prefix or "[PlayerSlotQueue]", Position ) )
end

function Plugin:Enqueue( Client, Options )
	if self.AuthorityDisabled then return false end
	if not Client or SafeCall( Client, "GetIsVirtual", false )
		or not IsConnectedSpectator( Client ) then return false end
	local SteamID = GetSteamID( Client )
	if SteamID < 1 then return false end
	local RestrictedFor = self:GetShadowRealmRestrictionRemaining( SteamID )
	if RestrictedFor then
		self:ReportShadowRealmDenial( Client, SteamID, RestrictedFor, "enqueue" )
		return false
	end
	local LeaveBanFor = self:GetLeaveBanRemaining( SteamID )
	if LeaveBanFor then
		self:ReportLeaveBanDenial( Client, SteamID, LeaveBanFor, "enqueue" )
		return false
	end
	if self.Positions[ SteamID ] then
		self:NotifyPosition( Client )
		return false
	end
	Options = Options or {}
	self.Metadata[ SteamID ] = self.Metadata[ SteamID ] or {}
	local Entry = self.Metadata[ SteamID ]
	Entry.Historic = Options.Historic == true
	Entry.Priority = Options.Priority == true or Entry.Priority == true
		or ( self.Config.VIPPlayers.Enabled
			and Shine:HasAccess( Client, self.Config.VIPPlayers.PermissionString ) )
	Entry.SkipToken = Options.SkipToken == true or Entry.SkipToken
	Entry.PendingSkipToken = nil
	local Position = Options.Position or self:GetInsertPosition( SteamID, Client )
	Position = math.max( 1, math.min( Position, #self.Queue + 1 ) )
	table.insert( self.Queue, Position, SteamID )
	self:Reindex()
	self:Log( "enqueue", StringFormat( "steam_id=%s position=%d count=%d priority=%s skip=%s historic=%s",
		SteamID, Position, #self.Queue, ToString( Entry.Priority ), ToString( Entry.SkipToken ), ToString( Entry.Historic ) ) )
	if not Options.Silent then
		self:NotifyPosition( Client, "[PlayerSlotQueue] Added." )
		Shine:NotifyDualColour( Client, 255, 180, 0, "[PlayerSlotQueue]", 255, 255, 255,
			"You will hear a sound when promoted. Toggle it in Options > Mods > Shimizu QoL (or 'sh_dfn' in console)" )
	end
	self:BroadcastSnapshot( "enqueue" )
	return true
end

function Plugin:RemoveSteamID( SteamID, Reason, KeepMetadata )
	if self.AuthorityDisabled then return false end
	SteamID = tonumber( SteamID )
	local Position = SteamID and self.Positions[ SteamID ]
	if not Position then return false end
	table.remove( self.Queue, Position )
	if not KeepMetadata then self.Metadata[ SteamID ] = nil end
	self:Reindex()
	self:Log( "dequeue", StringFormat( "steam_id=%s old_position=%d reason=%s count=%d",
		SteamID, Position, ToString( Reason ), #self.Queue ) )
	self:BroadcastSnapshot( Reason or "dequeue" )
	return true
end

function Plugin:Dequeue( Client, Reason )
	return Client and self:RemoveSteamID( GetSteamID( Client ), Reason or "dequeue" ) or false
end

function Plugin:CompactQueue( Reason )
	local Changed = false
	local Now = Shared.GetSystemTime()
	for i = #self.Queue, 1, -1 do
		local SteamID = self.Queue[ i ]
		local Entry = self.Metadata[ SteamID ] or {}
		local Client = Shine.GetClientByNS2ID( SteamID )
		if not Client and ( not Entry.Historic or ( Entry.ExpiresAt and Entry.ExpiresAt < Now ) ) then
			table.remove( self.Queue, i )
			self.Metadata[ SteamID ] = nil
			Changed = true
			self:Log( "compact", StringFormat( "steam_id=%s reason=%s", SteamID, ToString( Reason ) ) )
		end
	end
	if Changed then self:Reindex(); self:BroadcastSnapshot( "compact:"..ToString( Reason ) ) end
	return Changed
end

function Plugin:GetEligibleFront()
	for i = 1, #self.Queue do
		local SteamID = self.Queue[ i ]
		local Client = Shine.GetClientByNS2ID( SteamID )
		if IsConnectedSpectator( Client ) and not self:IsSpectatorFirstWaiting( Client, SteamID ) then return Client, SteamID, i end
	end
	return nil
end

-- Returns the first restored entry ahead of Position that has not reconnected,
-- while the post-map-load grace is running. Free once the grace has elapsed.
function Plugin:GetRestoreGraceBlocker( Position )
	local RestoredAt = self.QueueRestoredAt
	if not RestoredAt then return nil end
	if Shared.GetSystemTime() - RestoredAt >= RESTORE_GRACE_SECONDS then
		self.QueueRestoredAt = nil
		return nil
	end
	for i = 1, math.min( ( Position or #self.Queue + 1 ) - 1, #self.Queue ) do
		local SteamID = self.Queue[ i ]
		local Entry = self.Metadata[ SteamID ]
		if Entry and Entry.Historic and not Shine.GetClientByNS2ID( SteamID ) then return SteamID, i end
	end
	return nil
end

function Plugin:LogRestoreGraceHold( Path, SteamID, Position, BlockerID, BlockerPosition )
	local Key = Path..":"..ToString( SteamID )
	if self.RestoreGraceLogged[ Key ] then return end
	self.RestoreGraceLogged[ Key ] = true
	Print( "%s", StringFormat( "[rrqdiag] restore_grace_hold path=%s steam_id=%s position=%s blocker=%s blocker_position=%s grace_left=%d",
		Path, ToString( SteamID ), ToString( Position ), ToString( BlockerID ), ToString( BlockerPosition ),
		math.max( math.ceil( RESTORE_GRACE_SECONDS - ( Shared.GetSystemTime() - ( self.QueueRestoredAt or 0 ) ) ), 0 ) ) )
end

function Plugin:GetCounts( AdmissionCheck )
	local Snapshot = self:GetCapacitySnapshot( AdmissionCheck )
	return Snapshot.EnginePlayers, Snapshot.SettledHumans, Snapshot.NoPlayerHumans,
		Snapshot.PlayingBots, Snapshot
end

-- Mirror vanilla's connection assignment boundary before reserving a vacancy.
-- A connection that vanilla will place in a spectator slot cannot steal the
-- queue's player vacancy and must not be rejected on the queue's behalf.
function Plugin:WouldConnectionConsumePlayerSlot( SteamID, Snapshot )
	local EnginePlayers = Snapshot.EnginePlayers
	local PlayerLimit = math.min( self.Config.PlayerSlotLimit, Snapshot.MaxPlayers )
	if EnginePlayers >= PlayerLimit then return false, "queue_limit_full" end

	local PublicPlayerLimit = math.max( Snapshot.MaxPlayers - Snapshot.ReservedSlots, 0 )
	if EnginePlayers < PublicPlayerLimit then return true, "public_player_slot" end
	if EnginePlayers >= Snapshot.MaxPlayers then return false, "engine_player_slots_full" end

	local HasReservedAccess = type( GetHasReservedSlotAccess ) == "function"
		and GetHasReservedSlotAccess( SteamID ) == true
	return HasReservedAccess, HasReservedAccess and "reserved_player_slot" or "reserved_only"
end

-- Use client spectator flags as the authoritative human player-slot assignment.
-- Virtual clients do not consume NS2 network player slots and MNGA's bot manager
-- deliberately replaces them as humans join, so counting bots here deadlocks
-- humans in the queue during seeded games.
function Plugin:GetAssignedPlayerSlotCount()
	local Count = 0
	local GameIDs = Shine.GameIDs
	if GameIDs and type( GameIDs.Iterate ) == "function" then
		for Client in GameIDs:Iterate() do
			if not SafeCall( Client, "GetIsVirtual", false )
				and not SafeCall( Client, "GetIsSpectator", false ) then
				Count = Count + 1
			end
		end
		return Count
	end

	local Clients, NumClients = Shine.GetAllClients()
	for i = 1, NumClients do
		if not SafeCall( Clients[ i ], "GetIsVirtual", false )
			and not SafeCall( Clients[ i ], "GetIsSpectator", false ) then
			Count = Count + 1
		end
	end
	return Count
end

function Plugin:CanPromote( Player )
	if not Player or GetTeam( Player ) ~= kSpectatorIndex then return false, "not_spectator" end
	if not GetGamerules() then return false, "no_gamerules" end
	if self:GetAssignedPlayerSlotCount() >= self.Config.PlayerSlotLimit then
		return false, "assigned_full"
	end

	-- Gamerules:GetCanJoinPlayingTeam() sends a JoinError as a side effect when
	-- its engine counters are full. During map reconstruction those counters can
	-- remain at 20 while only a few clients have re-registered. Mirror the
	-- capacity portion of that check here so the automatic retry loop waits
	-- silently instead of repeatedly invoking the side-effecting vanilla path.
	local EnginePlayers = math.max( Server.GetNumClientsTotal() - Server.GetNumSpectators(), 0 )
	local MaxPlayers = Server.GetMaxPlayers()
	if EnginePlayers >= MaxPlayers then return false, "engine_full" end

	local ReservedSlots = Server.GetReservedSlotLimit()
	if ReservedSlots > 0 and EnginePlayers >= MaxPlayers - ReservedSlots then
		local SteamID = GetSteamID( nil, Player )
		if type( GetHasReservedSlotAccess ) ~= "function"
			or not GetHasReservedSlotAccess( SteamID ) then
			return false, "engine_reserved"
		end
	end
	return true, "available"
end

function Plugin:RequestProcess( Reason )
	if self.AuthorityDisabled or self.QueueMapChanging then return end
	self.QueueProcessPending = true
	self.QueueProcessReason = Reason or "unspecified"
	if self.TransactionDepth > 0 or self.QueueProcessing then
		self:Log( "process_request", StringFormat( "reason=%s deferred=true transaction=%d processing=%s",
			ToString( Reason ), self.TransactionDepth, ToString( self.QueueProcessing ) ) )
		return
	end
	self:ProcessQueue()
end

function Plugin:ProcessQueue()
	if self.QueueMapChanging then return false end
	if self.QueueProcessing or self.TransactionDepth > 0 or not self.QueueProcessPending then return false end
	self.QueueProcessing = true
	self.QueueProcessPending = false
	local Reason = self.QueueProcessReason
	local Result = false
	local ProcessSuccess, ProcessError = xpcall( function()
		self:CompactQueue( Reason )
		local Client, SteamID, Position = self:GetEligibleFront()
		local BlockerID, BlockerPosition = self:GetRestoreGraceBlocker( Position )
		if Client and BlockerID then
			self:LogRestoreGraceHold( "process", SteamID, Position, BlockerID, BlockerPosition )
		elseif Client then
			local Player = GetPlayer( Client )
			local EnginePlayers, SettledPlayers, Connecting, PlayingBots, Capacity = self:GetCounts( false )
			local CanPromote, PromotionPreflight = self:CanPromote( Player )
			self:LogCapacity( "process_attempt", false, false, SteamID,
				StringFormat( "trigger=%s can=%s preflight=%s", ToString( Reason ), ToString( CanPromote ),
					ToString( PromotionPreflight ) ), Capacity )
			self:LogVerbose( "process_attempt", StringFormat( "reason=%s steam_id=%s position=%s ep=%d sh=%d bots=%d cn=%d can=%s preflight=%s",
				ToString( Reason ), SteamID, Position, EnginePlayers, SettledPlayers, PlayingBots, Connecting,
				ToString( CanPromote ), ToString( PromotionPreflight ) ) )
			if CanPromote then
				self.InternalPromotionSteamID = SteamID
				local Gamerules = GetGamerules()
				local Success, NewPlayer = Gamerules:JoinTeam( Player, kTeamReadyRoom )
				self.InternalPromotionSteamID = nil
				local PromotedPlayer = NewPlayer or GetPlayer( Client )
				Result = Success == true and GetTeam( PromotedPlayer ) == kTeamReadyRoom
				local ProcessResultMessage = StringFormat( "steam_id=%s success=%s team=%s",
					SteamID, ToString( Result ), ToString( GetTeam( PromotedPlayer ) ) )
				if Result then
					self:Log( "process_result", ProcessResultMessage )
				else
					self:LogImportant( "process_result", ProcessResultMessage )
				end
				Print( "%s", StringFormat( "[rrqdiag] process_promote steam_id=%s raw_position=%s result=%s trigger=%s queue=%s",
					ToString( SteamID ), ToString( Position ), ToString( Result ), ToString( Reason ), TableConcat( self.Queue, "," ) ) )
				if Result then
					SafeCall( PromotedPlayer, "SetCameraDistance", nil, 0 )
					self:RemoveSteamID( SteamID, "promoted" )
					self:SendNetworkMessage( Client, "QueueLeft", {}, true )
					local MNGA = Shine.Plugins and Shine.Plugins.mngaadministration
					if MNGA and MNGA.Enabled then
						MNGA:SendNetworkMessage( Client, "QueuePromotionAttention", {}, true )
						if MNGA.ArmQueuePromotionTimeout then MNGA:ArmQueuePromotionTimeout( Client ) end
					end
				end
			end
		end
	end, debug.traceback )
	self.InternalPromotionSteamID = nil
	self.QueueProcessing = false
	if not ProcessSuccess then
		self.QueueProcessPending = true
		self:Log( "error", StringFormat( "reason=process_error trigger=%s error=%s",
			ToString( Reason ), ToString( ProcessError ) ) )
	end
	if ProcessSuccess and self.QueueProcessPending and self.TransactionDepth == 0 then self:ProcessQueue() end
	return Result
end

function Plugin:BeginTransaction( Reason )
	self.TransactionDepth = self.TransactionDepth + 1
	self.TransactionGeneration = self.TransactionGeneration + 1
	local Generation = self.TransactionGeneration
	self:Log( "transaction_begin", StringFormat( "reason=%s depth=%d", ToString( Reason ), self.TransactionDepth ) )
	-- Queue transactions are synchronous. If a caller errors before EndTransaction(),
	-- unwind on the next tick instead of suppressing queue processing forever.
	Shine.Timer.Simple( 0, function()
		if not self.Enabled or self.TransactionDepth == 0 or self.TransactionGeneration ~= Generation then return end
		self:Log( "error", StringFormat( "reason=transaction_forced_unwind transaction=%s depth=%d",
			ToString( Reason ), self.TransactionDepth ) )
		self.TransactionDepth = 0
		self:RequestProcess( "transaction_forced_unwind:"..ToString( Reason ) )
	end )
end

function Plugin:EndTransaction( Reason )
	self.TransactionDepth = math.max( self.TransactionDepth - 1, 0 )
	self.TransactionGeneration = self.TransactionGeneration + 1
	self:Log( "transaction_end", StringFormat( "reason=%s depth=%d", ToString( Reason ), self.TransactionDepth ) )
	if self.TransactionDepth == 0 then self:RequestProcess( "transaction_end:"..ToString( Reason ) ) end
end

function Plugin:RunTransaction( Reason, Callback )
	self:BeginTransaction( Reason )
	local Results
	local Success, Error = xpcall( function()
		Results = { Callback() }
	end, debug.traceback )
	self:EndTransaction( Reason )
	if not Success then
		self:Log( "error", StringFormat( "reason=transaction_error transaction=%s error=%s",
			ToString( Reason ), ToString( Error ) ) )
		return false, Error
	end
	return true, unpack( Results )
end

function Plugin:SetPriority( SteamID, Priority, SkipToken )
	if self.AuthorityDisabled then return false end
	SteamID = tonumber( SteamID )
	if not SteamID then return false end
	self.Metadata[ SteamID ] = self.Metadata[ SteamID ] or {}
	self.Metadata[ SteamID ].Priority = Priority == true
	self.Metadata[ SteamID ].SkipToken = SkipToken == true
	local Client = Shine.GetClientByNS2ID( SteamID )
	if self.Positions[ SteamID ] then
		table.remove( self.Queue, self.Positions[ SteamID ] )
		table.insert( self.Queue, self:GetInsertPosition( SteamID, Client ), SteamID )
		self:Reindex()
		self:BroadcastSnapshot( "priority" )
	end
	self:Log( "priority", StringFormat( "steam_id=%s priority=%s skip=%s position=%s",
		SteamID, ToString( Priority ), ToString( SkipToken ), ToString( self.Positions[ SteamID ] ) ) )
	return true
end

-- Applies an accepted skip token to the beneficiary. Shared by self-skips and
-- supporter-token gifts (Payer set, see .claude/docs/donate.md section 3.1).
function Plugin:ApplySkipToken( Client, SteamID, TokenType, Payer )
	local TokenName = ( TokenType == "donation" or TokenType == "donation_gift" ) and "Supporter token" or "Seeding token"
	local Name = Shine.GetClientName( Client )
	-- Beneficiary name slot so each viewer sees their SSB alias.
	local NameRef = MNGA_Name( SteamID, Name )
	if not IsConnectedSpectator( Client ) then
		-- The HTTP service has already consumed the token. Preserve its value as
		-- pending metadata so the next successful spectator enqueue receives it.
		self:SetPriority( SteamID, true, true )
		self.Metadata[ SteamID ].PendingSkipToken = true
		self:Log( "skip_token_result", StringFormat(
			"steam_id=%s success=true token_type=%s applied=false pending=true reason=left_spectator_after_request",
			SteamID, TokenType ) )
		Print( "%s", StringFormat( "[skipqueue] token pending steam_id=%s token_type=%s payer=%s",
			SteamID, TokenType, Payer and GetSteamID( Payer ) or "self" ) )
		Shine:NotifyColour( Client, 255, 200, 100,
			TokenName.." accepted. Its queue priority will apply when you next enter the spectator queue." )
		if Payer and Shine:IsValidClient( Payer ) then
			MNGA_NotifyNames( Payer, 255, 200, 100,
				"Supporter token spent on %s. They left the spectators, so it will apply when they next queue.", NameRef )
		end
		return
	end
	if not self.Positions[ SteamID ] then self:Enqueue( Client ) end
	if not self.Positions[ SteamID ] then
		self:Log( "skip_token_result", StringFormat(
			"steam_id=%s success=false reason=enqueue_failed", SteamID ) )
		Print( "%s", StringFormat( "[skipqueue] enqueue failed steam_id=%s token_type=%s", SteamID, TokenType ) )
		Shine:NotifyColour( Client, 255, 80, 80, "Could not apply seeding-token queue priority." )
		if Payer and Shine:IsValidClient( Payer ) then
			MNGA_NotifyNames( Payer, 255, 80, 80,
				"Could not apply queue priority to %s. Please notify an administrator.", NameRef )
		end
		return
	end
	self:SetPriority( SteamID, true, true )
	local Spectators = {}
	local Clients, Count = Shine.GetAllClients()
	for i = 1, Count do if SafeCall( Clients[ i ], "GetIsSpectator", false ) then Spectators[ #Spectators + 1 ] = Clients[ i ] end end
	if Payer then
		MNGA_NotifyNames( Spectators, 255, 200, 100,
			"%s used a supporter token to skip the queue for %s. Thank you for supporting the server!",
			MNGA_Name( Payer ), NameRef )
	elseif TokenType == "donation_gift" then
		-- Payer disconnected before the response arrived.
		MNGA_NotifyNames( Spectators, 255, 200, 100,
			"%s was given a supporter-token queue skip. Thank you for supporting the server!", NameRef )
	elseif TokenType == "donation" then
		MNGA_NotifyNames( Spectators, 255, 200, 100,
			"%s used a supporter token to skip the queue. Thank you for supporting the server!", NameRef )
	else
		MNGA_NotifyNames( Spectators, 255, 200, 100,
			"%s used a seeding token to skip the queue. Tokens are earned by seeding the server.", NameRef )
	end
	if Payer and Shine:IsValidClient( Payer ) and not SafeCall( Payer, "GetIsSpectator", false ) then
		MNGA_NotifyNames( Payer, 255, 200, 100, "Supporter token spent on %s.", NameRef )
	end
	Print( "%s", StringFormat( "[skipqueue] token accepted steam_id=%s name=%s token_type=%s payer=%s spectators=%d position=%s",
		SteamID, Name, TokenType, Payer and GetSteamID( Payer ) or "self", #Spectators, ToString( self.Positions[ SteamID ] ) ) )
	self:NotifyPosition( Client, Payer and StringFormat( "[PlayerSlotQueue] %s spent a supporter token on you.",
		Shine.GetClientName( Payer ) ) or "[PlayerSlotQueue] Token accepted." )
	self:Log( "skip_token_result", StringFormat( "steam_id=%s success=true token_type=%s position=%s",
		SteamID, TokenType, ToString( self.Positions[ SteamID ] ) ) )
end

-- Target (optional, ~= Client): spend Client's donation token on Target.
function Plugin:Skipqueue( Client, Target )
	if self.AuthorityDisabled then return end
	if Target == Client then Target = nil end
	local Beneficiary = Target or Client
	if not Beneficiary or not IsConnectedSpectator( Beneficiary ) then
		if Client then
			if Target then
				MNGA_NotifyNames( Client, 255, 80, 80, "%s must be a spectator to receive a queue skip.", MNGA_Name( Target ) )
			else
				Shine:NotifyColour( Client, 255, 80, 80, "You must be a spectator to use a seeding token." )
			end
		end
		return
	end
	local SteamID = GetSteamID( Client )
	if SteamID < 1 then return end
	local BeneficiaryID = GetSteamID( Beneficiary )
	if BeneficiaryID < 1 then
		Shine:NotifyColour( Client, 255, 80, 80, "Bots cannot receive a queue skip." )
		return
	end
	local MNGAAdministration = Shine.Plugins and Shine.Plugins.mngaadministration
	local XPConfig = MNGAAdministration and MNGAAdministration.Config
	local BaseURL = ToString( XPConfig and XPConfig.xpCentralURL or "http://127.0.0.1:25386" ):gsub( "/+$", "" )
	local ServerID = ToString( XPConfig and XPConfig.xpServerID or "" )
	local SharedSecret = ToString( XPConfig and XPConfig.xpSharedSecret or "" )
	self:Log( "skip_token_request", StringFormat(
		"steam_id=%s beneficiary=%s url=%s server_id=%s credentials=%s", SteamID, BeneficiaryID, BaseURL, ServerID,
		ServerID ~= "" and SharedSecret ~= "" and "configured" or "missing" ) )
	Print( "%s", StringFormat( "[skipqueue] request payer=%s beneficiary=%s gift=%s",
		SteamID, BeneficiaryID, ToString( Target ~= nil ) ) )
	local Params = {
		steamid = SteamID,
		server_id = ServerID,
		secret = SharedSecret
	}
	if Target then Params.beneficiary = BeneficiaryID end
	Shine.TimedHTTPRequest( BaseURL.."/skip", "POST", Params, function( Response )
		if not self.Enabled then return end
		local ClientValid = Shine:IsValidClient( Client )
		local Data = Response and Response ~= "" and json.decode( Response, 1, nil ) or nil
		local TokenType = Data and ToString( Data.token_type or "seeding" ) or "none"
		Print( "%s", StringFormat( "[skipqueue] response payer=%s beneficiary=%s success=%s token_type=%s",
			SteamID, BeneficiaryID, ToString( Data and Data.success ), TokenType ) )
		if not Data or not Data.success then
			self:Log( "skip_token_result", StringFormat( "steam_id=%s success=false response=%s", SteamID, ToString( Response ) ) )
			if not ClientValid then return end
			if Data and Data.error == "unauthorised" then
				Shine:NotifyColour( Client, 255, 80, 80,
					"The seeding-token service rejected this server's credentials. Please notify an administrator." )
			elseif Target then
				MNGA_NotifyNames( Client, 255, 80, 80,
					"You have no supporter token to spend on %s (seeding tokens cannot be given away).",
					MNGA_Name( BeneficiaryID, Shine.GetClientName( Target ) ) )
			else
				Shine:NotifyColour( Client, 255, 80, 80, "No supporter or seeding token was available." )
			end
			return
		end
		if Target and TokenType ~= "donation_gift" then
			-- Central predates gifting and charged the caller as a self-skip.
			self:LogImportant( "skip_gift_unsupported", StringFormat( "payer=%s beneficiary=%s token_type=%s",
				SteamID, BeneficiaryID, TokenType ) )
			if ClientValid then
				Shine:NotifyColour( Client, 255, 80, 80,
					"The token service does not support gifting yet. Please notify an administrator." )
			end
			return
		end
		if not Shine:IsValidClient( Beneficiary ) then
			-- Token already spent; keep it as pending priority for the beneficiary.
			self:SetPriority( BeneficiaryID, true, true )
			self.Metadata[ BeneficiaryID ].PendingSkipToken = true
			Print( "%s", StringFormat( "[skipqueue] beneficiary gone, token pending steam_id=%s", BeneficiaryID ) )
			if Target and ClientValid then
				Shine:NotifyColour( Client, 255, 200, 100,
					"Supporter token spent, but that player disconnected. It will apply when they next queue." )
			end
			return
		end
		self:ApplySkipToken( Beneficiary, BeneficiaryID, TokenType, Target and ClientValid and Client or nil )
	end, function()
		self:Log( "skip_token_timeout", StringFormat( "steam_id=%s beneficiary=%s", SteamID, BeneficiaryID ) )
		Print( "%s", StringFormat( "[skipqueue] timeout payer=%s beneficiary=%s", SteamID, BeneficiaryID ) )
		if Shine:IsValidClient( Client ) then Shine:NotifyColour( Client, 255, 80, 80, "Seeding-token request timed out." ) end
	end, 1.5 )
end

function Plugin:InsertAtFront( Client, Reason )
	if not Client then return false end
	local SteamID = GetSteamID( Client )
	if self.Positions[ SteamID ] then table.remove( self.Queue, self.Positions[ SteamID ] ) end
	self.Metadata[ SteamID ] = self.Metadata[ SteamID ] or {}
	table.insert( self.Queue, 1, SteamID )
	self:Reindex()
	self:BroadcastSnapshot( Reason or "insert_front" )
	self:Log( "insert_front", StringFormat( "steam_id=%s reason=%s", SteamID, ToString( Reason ) ) )
	return true
end

function Plugin:SwapPlayer( AdminClient, SpecClient, PlayerClient )
	if self.AuthorityDisabled then return false end
	if not SpecClient or not PlayerClient then return false end
	local SpecPlayer, PlayingPlayer = GetPlayer( SpecClient ), GetPlayer( PlayerClient )
	if not SpecPlayer or not PlayingPlayer or not IsConnectedSpectator( SpecClient )
		or SafeCall( PlayerClient, "GetIsSpectator", true ) or SpecClient == PlayerClient then
		Shine:AdminPrint( AdminClient, "Swap: invalid spectator/player targets." )
		return false
	end
	local Gamerules = GetGamerules()
	if not Gamerules then return false end
	local Team = GetTeam( PlayingPlayer )
	local ExistingOthers = #self.Queue - ( self:GetPosition( GetSteamID( SpecClient ) ) and 1 or 0 ) > 0
	local OutSuccess, InSuccess, RollbackSuccess = false, false, nil
	local TransactionSuccess = self:RunTransaction( "admin_swap", function()
		OutSuccess = Gamerules:JoinTeam( PlayingPlayer, kSpectatorIndex, true, true ) == true
		if not OutSuccess then return end
		if ExistingOthers then self:InsertAtFront( PlayerClient, "admin_swap_displaced" ) end
		InSuccess = Gamerules:JoinTeam( GetPlayer( SpecClient ) or SpecPlayer, Team, true, true ) == true
		if InSuccess then return end

		-- The second leg failed. Remove the temporary displaced-player claim and
		-- restore the original player to their team; the selected spectator was
		-- deliberately left queued until their successful PostJoinTeam dequeue.
		if ExistingOthers then self:RemoveSteamID( GetSteamID( PlayerClient ), "admin_swap_rollback" ) end
		local RollbackPlayer = GetPlayer( PlayerClient )
		RollbackSuccess = RollbackPlayer ~= nil
			and Gamerules:JoinTeam( RollbackPlayer, Team, true, true ) == true
	end )
	if not TransactionSuccess then InSuccess = false end
	self:Log( "swap", StringFormat( "admin=%s spectator=%s player=%s team=%s out=%s in=%s queued_displaced=%s",
		GetSteamID( AdminClient ), GetSteamID( SpecClient ), GetSteamID( PlayerClient ), Team,
		ToString( OutSuccess ), ToString( InSuccess ), ToString( ExistingOthers ) ) )
	Print( "%s", StringFormat( "[swap] admin=%s spectator=%s player=%s team=%s out=%s in=%s queued_displaced=%s",
		GetSteamID( AdminClient ), GetSteamID( SpecClient ), GetSteamID( PlayerClient ), Team,
		ToString( OutSuccess ), ToString( InSuccess ), ToString( ExistingOthers ) ) )
	if InSuccess then
		Shine:AdminPrint( AdminClient, "Swap completed." )
		MNGA_NotifyNames( nil, 255, 200, 100, "Swap: %s (spec) swapped with %s.",
			MNGA_Name( SpecClient ), MNGA_Name( PlayerClient ) )
	end
	if OutSuccess and not InSuccess then
		Shine:AdminPrint( AdminClient, "Swap failed during the second move; original player rollback: %s.",
			true, RollbackSuccess and "successful" or "FAILED" )
		self:LogImportant( "swap_rollback", StringFormat( "player=%s team=%s success=%s",
			GetSteamID( PlayerClient ), Team, ToString( RollbackSuccess ) ) )
	end
	return InSuccess == true
end

-- Pregame ready check (mngareadycheck, .claude/docs/ready-check.md): a ready
-- queued spectator (any queue position) takes the slot of an unready Ready
-- Room/team player. The displaced player goes to spectator and is NOT
-- re-queued. Runs as one queue transaction so the vacated slot is never handed
-- to the queue front in between; the out-move is rolled back if the in-move
-- fails.
function Plugin:ReadyCheckSwap( OutClient, InClient )
	if self.AuthorityDisabled then return false, "authority_disabled" end
	if not OutClient or not InClient or OutClient == InClient then return false, "invalid_clients" end
	local OutPlayer, InPlayer = GetPlayer( OutClient ), GetPlayer( InClient )
	if not OutPlayer or not InPlayer then return false, "missing_player" end
	if not IsConnectedSpectator( InClient ) then return false, "in_not_spectator" end
	if SafeCall( OutClient, "GetIsSpectator", true ) then return false, "out_is_spectator" end
	local InSteamID, OutSteamID = GetSteamID( InClient ), GetSteamID( OutClient )
	if not self.Positions[ InSteamID ] then return false, "in_not_queued" end
	local Gamerules = GetGamerules()
	if not Gamerules then return false, "no_gamerules" end

	local OutTeam = GetTeam( OutPlayer )
	local OutSuccess, InSuccess, RollbackSuccess = false, false, nil
	local TransactionSuccess = self:RunTransaction( "ready_check_swap", function()
		OutSuccess = Gamerules:JoinTeam( OutPlayer, kSpectatorIndex, true, true ) == true
		if not OutSuccess then return end

		self.InternalPromotionSteamID = InSteamID
		local Success = Gamerules:JoinTeam( GetPlayer( InClient ) or InPlayer, kTeamReadyRoom, true, true )
		self.InternalPromotionSteamID = nil
		InSuccess = Success == true and GetTeam( GetPlayer( InClient ) ) == kTeamReadyRoom
		if InSuccess then
			self:RemoveSteamID( InSteamID, "ready_check_promoted" )
			return
		end

		-- Second leg failed: put the original player back where they were. The
		-- spectator->Ready Room gate needs the internal bypass for that move.
		local RollbackPlayer = GetPlayer( OutClient )
		self.InternalPromotionSteamID = OutSteamID
		RollbackSuccess = RollbackPlayer ~= nil
			and Gamerules:JoinTeam( RollbackPlayer, OutTeam, true, true ) == true
		self.InternalPromotionSteamID = nil
	end )
	self.InternalPromotionSteamID = nil
	if not TransactionSuccess then InSuccess = false end

	local Summary = StringFormat( "out=%s out_team=%s in=%s out_ok=%s in_ok=%s rollback=%s",
		OutSteamID, ToString( OutTeam ), InSteamID, ToString( OutSuccess ), ToString( InSuccess ),
		ToString( RollbackSuccess ) )
	Shared.Message( "[swap] ready_check_swap "..Summary )
	if InSuccess then
		self:Log( "ready_check_swap", Summary )
		SafeCall( GetPlayer( InClient ), "SetCameraDistance", nil, 0 )
		self:SendNetworkMessage( InClient, "QueueLeft", {}, true )
		return true
	end
	self:LogImportant( "ready_check_swap", Summary )
	if not OutSuccess then return false, "out_move_failed" end
	return false, "in_move_failed"
end

function Plugin:CheckConnectionAllowed( SteamID )
	if self.AuthorityDisabled then return nil end
	local Client, FrontID = self:GetEligibleFront()
	local EnginePlayers, SettledPlayers, Connecting, PlayingBots, Capacity = self:GetCounts( true )
	local Entry = self.Metadata[ tonumber( SteamID ) ]
	local Exempt = tonumber( SteamID ) == FrontID or ( Entry and Entry.Historic ) or false
	local WouldConsumePlayerSlot, Assignment = self:WouldConnectionConsumePlayerSlot( SteamID, Capacity )
	local FrontCanConsumePlayerSlot, FrontAssignment = false, "no_eligible_front"
	if FrontID then
		FrontCanConsumePlayerSlot, FrontAssignment = self:WouldConnectionConsumePlayerSlot( FrontID, Capacity )
	end
	local QueueVacancy = SettledPlayers < self.Config.PlayerSlotLimit and FrontCanConsumePlayerSlot
	local Reserve = Client ~= nil and QueueVacancy and WouldConsumePlayerSlot and not Exempt
	if self:PrepareSpectatorFirst( SteamID, Assignment, Capacity ) then Reserve = false end
	self:RecordSpectatorFirstShadowDecision( SteamID, Reserve, Assignment, Capacity, FrontID )
	self:LogCapacity( "connection_check", true, true, SteamID,
		StringFormat( "front=%s historic=%s vacancy=%s front_assignment=%s front_player_slot=%s assignment=%s player_slot=%s exempt=%s reserve=%s mode=%s",
			ToString( FrontID or 0 ), ToString( Entry and Entry.Historic or false ), ToString( QueueVacancy ),
			FrontAssignment, ToString( FrontCanConsumePlayerSlot ), Assignment, ToString( WouldConsumePlayerSlot ),
			ToString( Exempt ), ToString( Reserve ),
			self.Config.ConnectionReservation ), Capacity )
	local DecisionMessage = StringFormat(
		"incoming=%s mode=%s action=%s reserve=%s assignment=%s player_slot=%s vacancy=%s front_assignment=%s front_player_slot=%s exempt=%s front=%s historic=%s ep=%d sh=%d bots=%d cn=%d",
		ToString( SteamID ), self.Config.ConnectionReservation,
		Reserve and self.Config.ConnectionReservation == "enforce" and "reject" or "allow",
		ToString( Reserve ), Assignment, ToString( WouldConsumePlayerSlot ), ToString( QueueVacancy ),
		FrontAssignment, ToString( FrontCanConsumePlayerSlot ), ToString( Exempt ), ToString( FrontID or 0 ),
		ToString( Entry and Entry.Historic or false ),
		EnginePlayers, SettledPlayers, PlayingBots, Connecting )
	if Reserve and self.Config.ConnectionReservation == "enforce" then
		self:LogImportant( "connection_decision", DecisionMessage )
		return false, "A player slot is reserved for the spectator queue; please retry shortly."
	end
	self:Log( "connection_decision", DecisionMessage )
	return nil
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	if self.AuthorityDisabled then return nil end
	local OldTeam = GetTeam( Player )
	if OldTeam == kSpectatorIndex and NewTeam ~= kSpectatorIndex then
		local Client = SafeCall( Player, "GetClient", nil )
		local SteamID = GetSteamID( Client, Player )
		local RestrictedFor = self:GetShadowRealmRestrictionRemaining( SteamID )
		if RestrictedFor then
			self:ReportShadowRealmDenial( Client, SteamID, RestrictedFor, "leave_spectator", StringFormat(
				"new_team=%s force=%s shine_force=%s",
				ToString( NewTeam ), ToString( Force ), ToString( ShineForce ) ) )
			return false
		end
		local LeaveBanFor = self:GetLeaveBanRemaining( SteamID )
		if LeaveBanFor then
			self:ReportLeaveBanDenial( Client, SteamID, LeaveBanFor, "leave_spectator" )
			return false
		end
	end
	local LoadingClient = SafeCall( Player, "GetClient", nil )
	if LoadingClient and GetTeam( Player ) == kSpectatorIndex and NewTeam ~= kSpectatorIndex
		and self:IsSpectatorFirstWaiting( LoadingClient, GetSteamID( LoadingClient ) ) then
		return false
	end
	if OldTeam == kSpectatorIndex and NewTeam == kTeamReadyRoom then
		self:LogCapacity( "join_attempt", false, true, GetSteamID( nil, Player ),
			StringFormat( "old=%s new=%s", OldTeam, NewTeam ) )
	end
	if OldTeam ~= kSpectatorIndex or NewTeam ~= kTeamReadyRoom or #self.Queue == 0 then return nil end
	local Client = SafeCall( Player, "GetClient", nil )
	if SafeCall( Client, "GetIsVirtual", false ) then return nil end
	local SteamID = GetSteamID( nil, Player )
	if SteamID == self.InternalPromotionSteamID then return nil end
	local _, FrontID, FrontPosition = self:GetEligibleFront()
	local Deny = SteamID ~= FrontID
	local Position = self.Positions[ SteamID ]
	if not Deny then
		local BlockerID, BlockerPosition = self:GetRestoreGraceBlocker( FrontPosition )
		if BlockerID then
			Deny = true
			self:LogRestoreGraceHold( "f4", SteamID, FrontPosition, BlockerID, BlockerPosition )
		end
	end
	Print( "%s", StringFormat( "[rrqdiag] f4_join steam_id=%s front=%s deny=%s position=%s queue=%s can_promote=%s",
		ToString( SteamID ), ToString( FrontID ), ToString( Deny ), ToString( Position ),
		TableConcat( self.Queue, "," ), ToString( select( 2, self:CanPromote( Player ) ) ) ) )
	for i = 1, #self.Queue do Print( "%s", "[rrqdiag] f4_join_entry "..self:DescribeQueueEntry( self.Queue[ i ] ) ) end
	local Action = Deny and ( Position and "deny_queued" or "deny_enqueue" ) or "allow"
	self:Log( "join_decision", StringFormat( "steam_id=%s action=%s front=%s position=%s",
		SteamID, Action, ToString( FrontID or 0 ), ToString( Position ) ) )
	if Deny then
		if Client then
			-- Returning false from Shine's JoinTeam hook prevents the vanilla
			-- GetCanJoinPlayingTeam() call, so its denial observer cannot enqueue
			-- this first F4 attempt. Enqueue here before stopping a queue bypass.
			if not Position then
				-- Do not announce a transient raw position before determining whether
				-- this spectator is actually the eligible front. A historic or
				-- disconnected persisted entry can precede an immediately eligible F4.
				self:Enqueue( Client, { Silent = true } )
				local EligibleClient, EligibleID, EligiblePosition = self:GetEligibleFront()
				local DiagCan, DiagReason = self:CanPromote( Player )
				Print( "%s", StringFormat( "[rrqdiag] f4_after_enqueue steam_id=%s eligible_id=%s eligible_pos=%s same_client=%s can_promote=%s reason=%s",
					ToString( SteamID ), ToString( EligibleID ), ToString( EligiblePosition ),
					ToString( EligibleClient == Client ), ToString( DiagCan ), ToString( DiagReason ) ) )
				local GraceBlockerID = EligibleID == SteamID and self:GetRestoreGraceBlocker( EligiblePosition )
				if GraceBlockerID then
					self:LogRestoreGraceHold( "f4_new", SteamID, EligiblePosition, GraceBlockerID )
				end
				if EligibleClient == Client and EligibleID == SteamID and not GraceBlockerID and self:CanPromote( Player ) then
					self:Log( "join_decision_resolved", StringFormat(
						"steam_id=%s action=allow_new_eligible raw_position=%s",
						SteamID, ToString( EligiblePosition ) ) )
					-- The original JoinTeam call should now complete synchronously. If
					-- another hook still refuses it, reveal the retained queue entry on
					-- the next tick instead of leaving the spectator silently queued.
					Shine.Timer.Simple( 0, function()
						if not self.Enabled or not Shine:IsValidClient( Client )
							or not self.Positions[ SteamID ] or not IsConnectedSpectator( Client ) then return end
						self:Log( "join_decision_resolved", StringFormat(
							"steam_id=%s action=allowed_join_failed position=%s",
							SteamID, ToString( self.Positions[ SteamID ] ) ) )
						self:NotifyPosition( Client, "[PlayerSlotQueue] Join deferred." )
						self:RequestProcess( "allowed_join_failed" )
					end )
					return nil
				end
				self:NotifyPosition( Client, "[PlayerSlotQueue] Added." )
				Shine:NotifyDualColour( Client, 255, 180, 0, "[PlayerSlotQueue]", 255, 255, 255,
					"You will hear a sound when promoted. Toggle it in Options > Mods > Shimizu QoL (or 'sh_dfn' in console)" )
			else
				self:NotifyPosition( Client, "[PlayerSlotQueue] Please wait." )
			end
		end
		return false
	end
	return nil
end

function Plugin:OnGetCanJoinPlayingTeam( _, Player, Allowed )
	if self.AuthorityDisabled then return end
	if GetTeam( Player ) ~= kSpectatorIndex then return end
	local Client = SafeCall( Player, "GetClient", nil )
	if SafeCall( Client, "GetIsVirtual", false ) then return end
	local EnginePlayers, SettledPlayers, _, PlayingBots, Capacity = self:GetCounts( false )
	local AssignedSlots = self:GetAssignedPlayerSlotCount()
	local OwnedFull = AssignedSlots >= self.Config.PlayerSlotLimit
	if not Allowed or OwnedFull or Capacity.Anomalous then
		self:LogCapacity( "admission_result", false, true, GetSteamID( Client, Player ),
			StringFormat( "vanilla=%s owned_full=%s assigned=%d", ToString( Allowed ),
				ToString( OwnedFull ), AssignedSlots ), Capacity )
	end
	if not Allowed or OwnedFull then
		if Client then
			self:Log( "admission_denied", StringFormat(
				"steam_id=%s vanilla=%s owned_full=%s assigned=%d ep=%d sh=%d bots=%d limit=%d",
				GetSteamID( Client, Player ), ToString( Allowed ), ToString( OwnedFull ),
				AssignedSlots, EnginePlayers, SettledPlayers, PlayingBots, self.Config.PlayerSlotLimit ) )
			Print( "%s", StringFormat( "[rrqdiag] can_join_denied_enqueue steam_id=%s vanilla=%s owned_full=%s assigned=%d",
				ToString( GetSteamID( Client, Player ) ), ToString( Allowed ), ToString( OwnedFull ), AssignedSlots ) )
			self:Enqueue( Client )
		end
		-- Never override a vanilla denial. This restores the original queue's
		-- second admission boundary after its explicit client-slot count.
		return false
	end
end

function Plugin:LogHistoryClaimShadow( Phase, SteamID, Client )
	if not self.Config.HistoryClaimShadowDebug then return end
	local Shadow = self.HistoryClaimShadow and self.HistoryClaimShadow[ SteamID ]
	if not Shadow or Shadow[ Phase ] then return end
	Shadow[ Phase ] = true
	local Entry = self.Metadata[ SteamID ]
	local Registered = Shine.GetClientByNS2ID( SteamID )
	local CurrentPosition = self.Positions[ SteamID ]
	if Phase == "post_join_team" then
		Shadow.PositionAtPostJoin = CurrentPosition
	end
	Print( "%s", StringFormat(
		"[mngarrq-history-shadow] phase=%s steam_id=%s loaded_position=%s observed_position=%s current_position=%s historic=%s registered=%s same_client=%s candidate=claim_at_client_connect",
		Phase, SteamID, ToString( Shadow.LoadedPosition ), ToString( Shadow.PositionAtPostJoin ),
		ToString( CurrentPosition ), ToString( Entry and Entry.Historic == true ),
		ToString( Registered ~= nil ), ToString( Registered ~= nil and Registered == Client ) ) )
end

function Plugin:PostJoinTeam( _, Player, OldTeam, NewTeam )
	if self.AuthorityDisabled or self.QueueMapChanging then return end
	local Client = SafeCall( Player, "GetClient", nil )
	local SteamID = GetSteamID( Client, Player )
	self:SpectatorFirstTeamChanged( Client, NewTeam )
	self:LogCapacity( "post_join_team", false, true, SteamID,
		StringFormat( "old=%s new=%s", ToString( OldTeam ), ToString( NewTeam ) ) )
	if NewTeam ~= kSpectatorIndex and SteamID ~= self.InternalPromotionSteamID then
		self:RemoveSteamID( SteamID, "joined_non_spectator" )
	elseif NewTeam == kSpectatorIndex then
		local Entry = self.Metadata[ SteamID ]
		if Entry and Entry.Historic then
			-- Map-change reconstruction invokes PostJoinTeam before Shine has
			-- registered the client. Keep the entry historic so CompactQueue cannot
			-- discard it during this gap; ClientConnect claims it below.
			self:LogHistoryClaimShadow( "post_join_team", SteamID, Client )
		end
	end
	if OldTeam == kSpectatorIndex or NewTeam == kSpectatorIndex
		or OldTeam == kTeamReadyRoom or NewTeam == kTeamReadyRoom then self:RequestProcess( "post_join_team" ) end
end

function Plugin:ClientConnect( Client )
	if self.AuthorityDisabled or self.QueueMapChanging then return end
	self:SpectatorFirstConnected( Client )
	local SteamID = GetSteamID( Client )
	self:RecordSpectatorFirstShadowLifecycle( "client_connect", Client )
	self:LogCapacity( "client_connect", false, true, SteamID )
	self:LogHistoryClaimShadow( "client_connect", SteamID, Client )
	local Entry = self.Metadata[ SteamID ]
	-- Vanilla creates a player-slot arrival directly in the Ready Room (no
	-- JoinTeam, so PostJoinTeam never dequeues it). A queued spectator who got a
	-- player slot this way no longer needs the queue. Over the limit, the overflow
	-- move below returns them to spectator, so they keep their position.
	if Entry and self.Positions[ SteamID ] and not SafeCall( Client, "GetIsVirtual", false )
		and not SafeCall( Client, "GetIsSpectator", false )
		and self:GetAssignedPlayerSlotCount() <= self.Config.PlayerSlotLimit then
		Print( "%s", StringFormat( "[rrqdiag] connected_to_player_slot steam_id=%s position=%s historic=%s team=%s",
			ToString( SteamID ), ToString( self.Positions[ SteamID ] ), ToString( Entry.Historic == true ),
			ToString( GetTeam( GetPlayer( Client ) ) ) ) )
		self:RemoveSteamID( SteamID, "connected_to_player_slot" )
		self:SendNetworkMessage( Client, "QueueLeft", {}, true )
		Entry = nil
	end
	if Entry and Entry.Historic then
		Entry.Historic = false
		self:Log( "history_claim", StringFormat( "steam_id=%s position=%s phase=client_connect",
			SteamID, ToString( self.Positions[ SteamID ] ) ) )
		self:NotifyPosition( Client, "[PlayerSlotQueue] Welcome back." )
	end

	-- A ready-check early leaver who reconnects natively into a player slot
	-- (player-return passthrough) is sent back to spectator for the ban.
	if not SafeCall( Client, "GetIsVirtual", false ) and not SafeCall( Client, "GetIsSpectator", false )
		and self:GetLeaveBanRemaining( SteamID ) then
		Shine.Timer.Simple( 0, function()
			if not self.Enabled or not Shine:IsValidClient( Client )
				or SafeCall( Client, "GetIsSpectator", false ) then return end
			local Remaining = self:GetLeaveBanRemaining( SteamID )
			local Player = GetPlayer( Client )
			local Gamerules = GetGamerules()
			if not Remaining or not Player or not Gamerules then return end
			SafeCall( Client, "SetIsSpectator", nil, true )
			local Success = Gamerules:JoinTeam( Player, kSpectatorIndex, true, true )
			self:LogImportant( "leave_ban", StringFormat( "phase=connect_to_spectator steam_id=%s success=%s",
				SteamID, ToString( Success == true ) ) )
			self:ReportLeaveBanDenial( Client, SteamID, Remaining, "leave_spectator" )
		end )
	end

	-- On map change, Gamerules creates the ReadyRoomPlayer before this hook and
	-- can carry an incorrect non-spectator assignment across the new VM. Apply
	-- the original queue's client-slot count once the client is registered and
	-- move only this newly connected overflow client back to spectator.
	if SafeCall( Client, "GetIsVirtual", false ) or SafeCall( Client, "GetIsSpectator", false ) then return end
	local AssignedSlots = self:GetAssignedPlayerSlotCount()
	if AssignedSlots <= self.Config.PlayerSlotLimit then return end
	Shine.Timer.Simple( 0, function()
		if not self.Enabled or not Shine:IsValidClient( Client )
			or SafeCall( Client, "GetIsSpectator", false ) then return end
		local CurrentAssignedSlots = self:GetAssignedPlayerSlotCount()
		if CurrentAssignedSlots <= self.Config.PlayerSlotLimit then return end
		local Player = GetPlayer( Client )
		local Gamerules = GetGamerules()
		if not Player or not Gamerules then return end
		SafeCall( Client, "SetIsSpectator", nil, true )
		local Success, NewPlayer = Gamerules:JoinTeam( Player, kSpectatorIndex, true, true )
		local FinalPlayer = NewPlayer or GetPlayer( Client )
		self:LogImportant( "connection_overflow", StringFormat(
			"steam_id=%s assigned=%d limit=%d success=%s final_team=%s action=move_to_spectator",
			SteamID, CurrentAssignedSlots, self.Config.PlayerSlotLimit, ToString( Success == true ),
			ToString( GetTeam( FinalPlayer ) ) ) )
		self:LogCapacity( "connection_overflow", false, true, SteamID,
			StringFormat( "assigned_before=%d success=%s", CurrentAssignedSlots, ToString( Success == true ) ) )
		if Success == true and GetTeam( FinalPlayer ) == kSpectatorIndex then
			self:Enqueue( Client )
		end
	end )
end

function Plugin:ClientConfirmConnect( Client )
	if self.AuthorityDisabled or self.QueueMapChanging then return end
	if not Client or Shine.GetClientByNS2ID( GetSteamID( Client ) ) ~= Client then return end
	self:RecordSpectatorFirstShadowLifecycle( "client_confirm", Client )
	self:LogCapacity( "client_confirm_connect", false, true, GetSteamID( Client ) )
	local Entry = self.Metadata[ GetSteamID( Client ) ]
	-- Defensive fallback in case a future Shine event-order change skips the
	-- normal ClientConnect claim. Do not notify twice after a successful claim.
	if Entry and Entry.Historic then
		Entry.Historic = false
		self:Log( "history_claim", StringFormat( "steam_id=%s position=%s phase=client_confirm_connect",
			GetSteamID( Client ), ToString( self.Positions[ GetSteamID( Client ) ] ) ) )
		self:NotifyPosition( Client, "[PlayerSlotQueue] Welcome back." )
	end
	self:SpectatorFirstConfirmed( Client )
	self:BroadcastSnapshot( "client_confirm", Client )
	self:RequestProcess( "client_confirm" )
end

function Plugin:ClientDisconnect( Client )
	if self.AuthorityDisabled or self.QueueMapChanging then return end
	self:SpectatorFirstDisconnected( Client )
	if not Client or SafeCall( Client, "GetIsVirtual", false ) then return end
	local Current = Shine.GetClientByNS2ID( GetSteamID( Client ) )
	if Current and Current ~= Client then return end
	local SteamID = GetSteamID( Client )
	self:RecordSpectatorFirstShadowLifecycle( "client_disconnect", Client )
	self:LogCapacity( "client_disconnect", false, true, SteamID )
	if IsConnectedSpectator( Client ) then
		self:RemoveSteamID( SteamID, "spectator_disconnect" )
	else
		self:RequestProcess( "playing_disconnect" )
	end
	Shine.Timer.Simple( 0, function()
		if self.Enabled then self:LogCapacity( "disconnect_settled", false, true, SteamID ) end
	end )
end

function Plugin:LoadQueueHistory()
	if not self.Config.RestoreQueueAfterMapchange then return end
	local History = Shine.LoadJSONFile( self.QueueHistoryFile )
	local Imported = false
	if not History then History = Shine.LoadJSONFile( self.LegacyQueueHistoryFile ); Imported = History ~= nil end
	if not History or not History.TimeStamp
		or tonumber( History.TimeStamp ) + self.Config.QueueHistoryLifeTime < Shared.GetSystemTime() then
		self:Log( "history_load", "result=none_or_expired" ); return
	end
	local SourceQueue = History.Queue or History.PlayerQueue or {}
	local LegacyPriority = {}
	for i = 1, #( History.ReservedQueue or {} ) do
		LegacyPriority[ tonumber( History.ReservedQueue[ i ] ) ] = true
	end
	local ExpiresAt = Shared.GetSystemTime() + self.Config.QueuePositionMaxReservationTime
	for i = 1, #SourceQueue do
		local SavedEntry = SourceQueue[ i ]
		local SteamID = tonumber( type( SavedEntry ) == "table" and SavedEntry.SteamID or SavedEntry )
		if SteamID and SteamID > 0 and not self.Positions[ SteamID ] then
			self.Queue[ #self.Queue + 1 ] = SteamID
			self.Metadata[ SteamID ] = {
				Historic = true,
				ExpiresAt = ExpiresAt,
				Priority = ( type( SavedEntry ) == "table" and SavedEntry.Priority == true )
					or LegacyPriority[ SteamID ] == true,
				SkipToken = type( SavedEntry ) == "table" and SavedEntry.SkipToken == true or false
			}
			self.HistoryClaimShadow[ SteamID ] = { LoadedPosition = i }
		end
	end
	self:Reindex()
	self:Log( "history_load", StringFormat( "result=loaded count=%d imported_legacy=%s", #self.Queue, ToString( Imported ) ) )
	if self.Config.SpectatorFirst then
		self:Log( "history_order", "phase=load queue="..TableConcat( self.Queue, "," ) )
	end
	if Imported then self:SaveQueueHistory() end
end

function Plugin:SaveQueueHistory()
	local Entries = {}
	for i = 1, #self.Queue do
		local SteamID = self.Queue[ i ]
		local Entry = self.Metadata[ SteamID ] or {}
		Entries[ i ] = { SteamID = SteamID, Priority = Entry.Priority == true, SkipToken = Entry.SkipToken == true }
	end
	local Saved, SaveError = Shine.SaveJSONFile( { Version = 1, TimeStamp = Shared.GetSystemTime(), Queue = Entries }, self.QueueHistoryFile )
	if not Saved then self:LogImportant( "error", "reason=queue_history_save_failed error="..ToString( SaveError ) ) end
	self:Log( "history_save", StringFormat( "count=%d", #Entries ) )
	if self.Config.SpectatorFirst then
		self:Log( "history_order", "phase=save queue="..TableConcat( self.Queue, "," ) )
	end
end

function Plugin:MapChange()
	if self.QueueMapChanging then return end
	self.QueueMapChanging = true
	self:SaveSpectatorFirst()
	self:ClearSpectatorFirstShadow( "map_change" )
	self:SaveShadowRealmRestrictions()
	if self.Config.RestoreQueueAfterMapchange then self:SaveQueueHistory() end
end

function Plugin:OnFirstThink()
	local Legacy = Shine.Plugins and Shine.Plugins.readyroomqueue
	if Legacy and Legacy.Enabled then
		self.AuthorityDisabled = true
		self:Log( "error", "reason=legacy_readyroomqueue_enabled authority_disabled=true" )
		return
	end
	Shine.Hook.SetupClassHook( "Gamerules", "GetCanJoinPlayingTeam", "OnGetCanJoinPlayingTeam",
		function( OldFunc, Gamerules, Player, SkipHook )
			local Result = OldFunc( Gamerules, Player )
			if not SkipHook then
				local Override = Shine.Hook.Call( "OnGetCanJoinPlayingTeam", Gamerules, Player, Result )
				if Override ~= nil then Result = Override end
			end
			return Result
		end )
	self:Log( "authority_check", "legacy=false authority_enabled=true" )
end

function Plugin:OnPluginLoad( Name, LoadedPlugin, IsShared )
	if Name ~= "readyroomqueue" or IsShared or not LoadedPlugin or not LoadedPlugin.Enabled then return end
	self.AuthorityDisabled = true
	self:Log( "error", "reason=legacy_readyroomqueue_loaded_late authority_disabled=true unloading_legacy=true" )
	Shine.Timer.Simple( 0, function()
		local Current = Shine.Plugins and Shine.Plugins.mngareadyroomqueue
		if Current ~= self or not self.Enabled then return end
		local Unloaded = Shine:UnloadExtension( "readyroomqueue" )
		if not Unloaded then
			self:Log( "error", "reason=legacy_readyroomqueue_unload_failed authority_disabled=true" )
			return
		end
		-- Legacy command cleanup removes the shared rr_* names it temporarily
		-- replaced. Restore this plugin's command objects after that cleanup.
		self:CreateCommands()
		self.AuthorityDisabled = false
		self:Log( "authority_check", "legacy_loaded_late=true legacy_unloaded=true authority_enabled=true" )
		self:RequestProcess( "legacy_unloaded" )
	end )
end

function Plugin:PrintQueue( Client )
	local Lines = { #self.Queue == 0 and "Player Slot Queue is empty." or "Player Slot Queue:" }
	for i = 1, #self.Queue do
		local SteamID = self.Queue[ i ]
		local QueuedClient = Shine.GetClientByNS2ID( SteamID )
		Lines[ #Lines + 1 ] = StringFormat( "%d - %s[%s]", i,
			QueuedClient and Shine.GetClientName( QueuedClient ) or "Historic/Disconnected", SteamID )
		Lines[ #Lines + 1 ] = "    [rrqdiag] "..self:DescribeQueueEntry( SteamID )
	end
	for i = 1, #Lines do if Client then ServerAdminPrint( Client, Lines[ i ] ) else Shared.Message( Lines[ i ] ) end end
end

function Plugin:CreateCommands()
	self:BindCommand( "sh_rr_enqueue", "rr_enqueue", function( Client ) if Client then self:Enqueue( Client ) end end, true )
		:Help( "Enter the queue for a player slot" )
	self:BindCommand( "sh_rr_dequeue", "rr_dequeue", function( Client )
		if Client and self:Dequeue( Client, "command" ) then Shine:NotifyColour( Client, 255, 180, 0, "Left player-slot queue." ) end
	end, true ):Help( "Leave the player-slot queue" )
	self:BindCommand( "sh_rr_position", "rr_position", function( Client ) if Client then self:NotifyPosition( Client ) end end, true )
		:Help( "Show your player-slot queue position" )
	self:BindCommand( "sh_rr_printqueue", nil, function( Client ) self:PrintQueue( Client ) end, true )
	self:BindCommand( "sh_mngarrq_dump", nil, function( Client )
		self:Log( "dump", StringFormat( "requester=%s count=%d revision=%d transaction=%d processing=%s queue=%s",
			GetSteamID( Client ), #self.Queue, self.QueueRevision, self.TransactionDepth,
			ToString( self.QueueProcessing ), TableConcat( self.Queue, "," ) ) )
		self:LogCapacity( "manual_dump", false, true, GetSteamID( Client ), nil, nil, true )
		self:PrintQueue( Client )
	end ):Help( "Dump authoritative MNGA ReadyRoomQueue state" )
end

function Plugin:Initialise()
	if self.Config.OperatingMode ~= "authoritative" then return false, "OperatingMode must be authoritative." end
	if self.Config.ConnectionReservation ~= "disabled" and self.Config.ConnectionReservation ~= "shadow"
		and self.Config.ConnectionReservation ~= "enforce" then return false, "Invalid ConnectionReservation." end
	local Legacy = Shine.Plugins and Shine.Plugins.readyroomqueue
	if Legacy and Legacy.Enabled then
		self:Log( "error", "reason=legacy_readyroomqueue_enabled refusing_initialise=true" )
		return false, "Disable readyroomqueue before enabling mngareadyroomqueue."
	end
	self.Queue, self.Positions, self.Metadata = {}, {}, {}
	self.ShadowRealmRestrictions = {}
	self.ShadowRealmDenialState = {}
	self.LeaveBans = {}
	self.HistoryClaimShadow = {}
	self.SpectatorFirstShadowPending = {}
	self.SpectatorFirstShadowClientTokens = setmetatable( {}, { __mode = "k" } )
	self.SpectatorFirstShadowToken = 0
	self.SpectatorFirstShadowAssignmentCalls = 0
	self.SpectatorFirstShadowStatusReported = false
	self.SpectatorFirstShadowAssignmentError = false
	self.QueueRevision, self.TransactionDepth, self.TransactionGeneration = 0, 0, 0
	self.QueueProcessing, self.QueueProcessPending = false, false
	self.LastCapacitySignature, self.LastCapacityDetailSignature, self.LastCapacityDetailTime = nil, nil, nil
	self.LastCapacityEventTimes = {}
	self:LoadQueueHistory()
	self.QueueRestoredAt = #self.Queue > 0 and Shared.GetSystemTime() or nil
	self.RestoreGraceLogged = {}
	self:LoadShadowRealmRestrictions()
	self:LoadLeaveBans()
	self:InitialiseSpectatorFirst()
	self.Enabled = true
	self:CreateCommands()
	self:CreateTimer( PROCESS_TIMER, math.max( tonumber( self.Config.ProcessInterval ) or 0.5, 0.1 ), -1,
		function() if not self.AuthorityDisabled then self:RequestProcess( "timer" ) end end )
	self:CreateTimer( CAPACITY_TIMER, math.max( tonumber( self.Config.CapacitySampleInterval ) or 5, 1 ), -1,
		function()
			if not self.AuthorityDisabled then
				self:LogCapacity( "sample", false, false )
				self:SweepSpectatorFirstShadow()
				self:SweepSpectatorFirst()
				self:SweepShadowRealmRestrictions()
			end
		end )
	self:Log( "startup", StringFormat(
		"version=%s authority=true reservation=%s spectator_first_shadow=%s shadow_lifetime=%s queue=%d shadow_scope=all_admissions handoff_policy=start_slot spectator_first=%s handoff_timeout=120",
		self.Version, self.Config.ConnectionReservation, ToString( self.Config.SpectatorFirstShadow == true ),
		ToString( self.Config.SpectatorFirstShadowLifetime ), #self.Queue, ToString( self.Config.SpectatorFirst ) ) )
	self:LogCapacity( "startup", false, true, 0, nil, nil, true )
	return true
end

function Plugin:Cleanup()
	self:ClearSpectatorFirstShadow( "cleanup" )
	if not self.QueueMapChanging then self:SaveShadowRealmRestrictions() end
	if self.SFLoading and not self.QueueMapChanging then
		self:SaveSpectatorFirst()
		if self.Config.RestoreQueueAfterMapchange then self:SaveQueueHistory() end
	end
	self:Log( "cleanup", StringFormat( "authority=true queue=%d", #self.Queue ) )
	self.BaseClass.Cleanup( self )
end

return Plugin
