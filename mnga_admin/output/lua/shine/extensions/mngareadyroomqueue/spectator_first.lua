local Plugin = ...
local HANDOFF_SECONDS = 120
local HISTORY_FILE = "config://shine/temp/mnga_rr_connection_history.json"

local function Call( Object, Method, Default )
	if not Object or type( Object[ Method ] ) ~= "function" then return Default end
	local OK, Value = pcall( Object[ Method ], Object )
	return OK and Value or Default
end

local function ID( Client ) return tonumber( Call( Client, "GetUserId", 0 ) ) or 0 end
local function Human( Client ) return Client and not Call( Client, "GetIsVirtual", false ) end
local function Spectator( Client ) return Call( Client, "GetIsSpectator", false ) end
local function Now() return Shared.GetSystemTime() end
local SPECTATOR_FIRST_MIN_EXISTING_HUMANS = 15

local function CountOtherHumans( SteamID )
	local Clients, Count = Shine.GetAllClients()
	local Humans = 0
	for i = 1, Count do
		local Client = Clients[ i ]
		if Human( Client ) and ID( Client ) ~= SteamID then Humans = Humans + 1 end
	end
	return Humans
end

function Plugin:LogSpectatorFirst( Phase, SteamID, Detail, Important )
	-- Keep failures and one ownership report per map in production. Detailed
	-- lifecycle evidence can be restored independently of the passive shadow.
	if not Important and not self.Config.Debug then return end
	self:LogImportant( "spectator_first", string.format( "phase=%s steam_id=%s %s",
		Phase, tostring( SteamID or 0 ), Detail or "" ) )
end

function Plugin:InitialiseSpectatorFirst()
	self.SFAdmission, self.SFLoading, self.SFReconnectUntil = {}, {}, {}
	self.SFMapReturn, self.SFQueueAwaiting = {}, {}
	self.SFReady = setmetatable( {}, { __mode = "k" } )
	self.SFClientEntry = setmetatable( {}, { __mode = "k" } )
	self.SFClientSlot = setmetatable( {}, { __mode = "k" } )
	self.SFGeneration = 0
	self.SFStatusReported = false
	self.QueueMapChanging = false
	-- A same-object disable/re-enable may still own the installed wrapper. A
	-- fresh/late-loaded object must wait for native registration on a new map.
	self.SFWrapperReady = self.SFWrapperReady == true
	local Time = Now()
	local History = Shine.LoadJSONFile( HISTORY_FILE )
	if History and History.Version == 1 and type( History.TimeStamp ) == "number"
		and Time >= History.TimeStamp and Time - History.TimeStamp <= self.Config.QueueHistoryLifeTime then
		for _, Saved in ipairs( History.Returning or {} ) do
			local SteamID = tonumber( Saved.SteamID )
			if SteamID then
				self.SFMapReturn[ SteamID ] = {
					Player = Saved.Player == true,
					Expires = History.TimeStamp + self.Config.QueueHistoryLifeTime
				}
			end
		end
		for _, Saved in ipairs( History.Reconnect or {} ) do
			local SteamID, Expires = tonumber( Saved.SteamID ), tonumber( Saved.Expires )
			if SteamID and Expires and Expires > Time then self.SFReconnectUntil[ SteamID ] = Expires end
		end
		if self.Config.SpectatorFirst then
			for _, Saved in ipairs( History.Loading or {} ) do
				local SteamID, Deadline = tonumber( Saved.SteamID ), tonumber( Saved.Deadline )
				if SteamID and Deadline and Deadline > Time then
					self.SFGeneration = self.SFGeneration + 1
					self.SFLoading[ SteamID ] = {
						Token = self.SFGeneration, Deadline = Deadline,
						Eligible = Saved.Eligible == true, Restored = true
					}
					self:LogSpectatorFirst( "restore_loading", SteamID, "deadline="..Deadline )
				end
			end
		end
	end
	-- Consume the transition snapshot; a later hot-enable must not replay it.
	Shine.SaveJSONFile( { Version = 1, TimeStamp = 0 }, HISTORY_FILE )
	for SteamID in pairs( self.Positions ) do
		self.SFQueueAwaiting[ SteamID ] = true
		Print( "%s", "[rrqdiag] sf_queue_awaiting_set steam_id="..tostring( SteamID ).." position="..tostring( self.Positions[ SteamID ] ) )
	end
	-- Hot enabling must never reinterpret already connected humans as arrivals.
	local Clients, Count = Shine.GetAllClients()
	for i = 1, Count do
		local Client = Clients[ i ]
		if Human( Client ) then
			self.SFReady[ Client ] = true
			self.SFClientSlot[ Client ] = not Spectator( Client )
		end
	end
end

function Plugin:SaveSpectatorFirst()
	local History = { Version = 1, TimeStamp = Now(), Returning = {}, Loading = {}, Reconnect = {} }
	local Seen = {}
	local Clients, Count = Shine.GetAllClients()
	for i = 1, Count do
		local Client = Clients[ i ]
		if Human( Client ) and ID( Client ) > 0 then
			local SteamID = ID( Client )
			Seen[ SteamID ] = true
			History.Returning[ #History.Returning + 1 ] = { SteamID = SteamID, Player = not Spectator( Client ) }
		end
	end
	-- Preserve an earlier map snapshot through another transition during loading.
	for SteamID, Entry in pairs( self.SFMapReturn ) do
		if not Seen[ SteamID ] and Entry.Expires > History.TimeStamp then
			History.Returning[ #History.Returning + 1 ] = { SteamID = SteamID, Player = Entry.Player }
			Seen[ SteamID ] = true
		end
	end
	for SteamID, Entry in pairs( self.SFLoading ) do
		if Entry.Deadline > History.TimeStamp then
			if not Seen[ SteamID ] then
				History.Returning[ #History.Returning + 1 ] = { SteamID = SteamID, Player = false }
				Seen[ SteamID ] = true
			end
			History.Loading[ #History.Loading + 1 ] = {
				SteamID = SteamID, Eligible = Entry.Eligible, Deadline = Entry.Deadline
			}
		end
	end
	for SteamID, Expires in pairs( self.SFReconnectUntil ) do
		if Expires > History.TimeStamp then
			History.Reconnect[ #History.Reconnect + 1 ] = { SteamID = SteamID, Expires = Expires }
		end
	end
	local Saved, SaveError = Shine.SaveJSONFile( History, HISTORY_FILE )
	if not Saved then self:LogSpectatorFirst( "save_failed", 0, "error="..tostring( SaveError ), true ) end
	self:LogSpectatorFirst( "save_transition", 0, string.format( "returning=%d loading=%d queue=%d",
		#History.Returning, #History.Loading, #self.Queue ) )
end

function Plugin:IsSpectatorFirstPlayerReturn( SteamID )
	local Client = Shine.GetClientByNS2ID( SteamID )
	if Human( Client ) and not Spectator( Client ) then return true end
	local Return = self.SFMapReturn[ SteamID ]
	return ( Return and Return.Player and Return.Expires > Now() )
		or ( self.SFReconnectUntil[ SteamID ] or 0 ) > Now()
end

-- Called from admission, but never accepts on behalf of vanilla/ban hooks.
-- Only a usable installed assignment wrapper can replace reservation rejection.
function Plugin:PrepareSpectatorFirst( SteamID, Assignment, Capacity )
	if not self.Config.SpectatorFirst or not self.SFWrapperReady or self.QueueMapChanging then return false end
	SteamID = tonumber( SteamID )
	if not SteamID or SteamID <= 0 then return false end
	if self:IsSpectatorFirstPlayerReturn( SteamID ) then
		self.SFAdmission[ SteamID ] = nil
		self:LogSpectatorFirst( "admission_passthrough", SteamID, "reason=player_return" )
		return true -- Preserve native reconnect admission, including queue exemption.
	end
	local Previous = self.SFLoading[ SteamID ]
	-- Each new native admission attempt gets its own generation. Only an
	-- unbound, explicitly restored map handoff retains the original deadline.
	local Restored = Previous and Previous.Restored and not Previous.Client and Previous.Deadline > Now()
	if Previous and not Restored then
		self:LogSpectatorFirst( "superseded", SteamID, "token="..Previous.Token )
		self.SFLoading[ SteamID ] = nil
	end
	self.SFAdmission[ SteamID ] = nil
	local ExistingHumans = CountOtherHumans( SteamID )
	if not Restored and ExistingHumans < SPECTATOR_FIRST_MIN_EXISTING_HUMANS then
		self:LogSpectatorFirst( "admission_passthrough", SteamID,
			string.format( "reason=human_threshold existing_humans=%d threshold=%d",
				ExistingHumans, SPECTATOR_FIRST_MIN_EXISTING_HUMANS ) )
		return false
	end
	local Room = Capacity.EngineSpectators < Capacity.MaxSpectators
		and Capacity.AdjustedTotal < Capacity.MaxPlayers + Capacity.MaxSpectators
	if not Room then
		self:LogSpectatorFirst( "admission_passthrough", SteamID, "reason=spectator_capacity", true )
		return false
	end
	local MapReturn = self.SFMapReturn[ SteamID ]
	local ReturningViewer = MapReturn and not MapReturn.Player and MapReturn.Expires > Now()
	self.SFGeneration = self.SFGeneration + 1
	local Entry = {
		Token = self.SFGeneration,
		Deadline = Restored and Previous.Deadline or Now() + HANDOFF_SECONDS,
		Eligible = not ReturningViewer and not self.Positions[ SteamID ]
			and Capacity.SettledHumans < self.Config.PlayerSlotLimit
			and ( Assignment == "public_player_slot" or Assignment == "reserved_player_slot" ) or false
	}
	if Restored then Entry.Eligible = Previous.Eligible end
	self.SFAdmission[ SteamID ] = Entry
	self:LogSpectatorFirst( "admission", SteamID, string.format(
		"token=%d eligible=%s deadline=%d ep=%d existing_humans=%d threshold=%d queue_position=%s restored=%s",
		Entry.Token, tostring( Entry.Eligible ), Entry.Deadline, Capacity.EnginePlayers,
		ExistingHumans, SPECTATOR_FIRST_MIN_EXISTING_HUMANS,
		tostring( self.Positions[ SteamID ] ), tostring( Restored == true ) ) )
	return true
end

-- Invoked after the original callback consumed its own spectator marker.
function Plugin:ApplySpectatorFirstAssignment( SteamID, Original )
	if not self.Config.SpectatorFirst or not self.SFWrapperReady or self.QueueMapChanging then return Original end
	SteamID = tonumber( SteamID )
	local Entry = SteamID and self.SFAdmission[ SteamID ]
	if not Entry then return Original end
	self.SFAdmission[ SteamID ] = nil -- One-shot, independent of confirmation.
	if Entry.Deadline < Now() or self:IsSpectatorFirstPlayerReturn( SteamID ) then return Original end
	-- Admission has already checked total capacity. Recheck spectator capacity
	-- at the assignment boundary without assuming counters have applied Original.
	if not Original and Server.GetNumSpectators() >= Server.GetMaxSpectators() then
		self:LogSpectatorFirst( "assignment_passthrough", SteamID, "reason=spectator_capacity_changed", true )
		return Original
	end
	self.SFLoading[ SteamID ] = Entry
	self:LogSpectatorFirst( "assignment", SteamID, string.format(
		"token=%d original=%s result=true eligible=%s deadline=%d",
		Entry.Token, tostring( Original ), tostring( Entry.Eligible ), Entry.Deadline ) )
	return true
end

function Plugin:IsSpectatorFirstWaiting( Client, SteamID )
	if not self.Config.SpectatorFirst or self.SFReady[ Client ] then return false end
	local Entry = self.SFLoading[ SteamID ]
	return self.SFQueueAwaiting[ SteamID ] == true
		or ( Entry and Entry.Deadline > Now() and ( not Entry.Client or Entry.Client == Client ) ) or false
end

function Plugin:SpectatorFirstConnected( Client )
	if not Human( Client ) then return end
	local SteamID = ID( Client )
	self.SFClientSlot[ Client ] = not Spectator( Client )
	local Entry = self.SFLoading[ SteamID ]
	if Entry and not Entry.Client then
		Entry.Client = Client
		Entry.Restored = nil
		self.SFClientEntry[ Client ] = Entry
	end
	if self.Config.SpectatorFirst then
		local Returning = self.SFMapReturn[ SteamID ]
		self:LogSpectatorFirst( "connect", SteamID, string.format( "token=%s spectator=%s queue_position=%s map_player=%s reconnect_player=%s",
			Entry and tostring( Entry.Token ) or "none", tostring( Spectator( Client ) ),
			tostring( self.Positions[ SteamID ] ), tostring( Returning and Returning.Player or false ),
			tostring( ( self.SFReconnectUntil[ SteamID ] or 0 ) > Now() ) ) )
	end
	self.SFMapReturn[ SteamID ] = nil
	-- A restored queue member keeps advancing once loaded. Waiting for the first
	-- key press (ClientConfirmConnect) froze tabbed-out players at their position
	-- while everyone behind them was promoted. Fresh-arrival SFLoading handoffs
	-- still wait for confirmation.
	if self.SFQueueAwaiting[ SteamID ] then
		self.SFQueueAwaiting[ SteamID ] = nil
		Print( "%s", "[rrqdiag] sf_queue_awaiting_cleared_on_connect steam_id="..tostring( SteamID )
			.." position="..tostring( self.Positions[ SteamID ] ) )
	end
	-- Do not move tokenless map returnees or native player reconnects. Their
	-- assignment is already established and must remain native.
end

function Plugin:SpectatorFirstConfirmed( Client )
	if not Human( Client ) or self.SFReady[ Client ] then return end
	local SteamID = ID( Client )
	local Entry = self.SFClientEntry[ Client ]
	local Current = Shine.GetClientByNS2ID( SteamID )
	if Current ~= Client then return end
	self.SFReady[ Client ] = true
	Print( "%s", "[rrqdiag] sf_confirmed steam_id="..tostring( SteamID ).." was_awaiting="..tostring( self.SFQueueAwaiting[ SteamID ] == true )
		.." position="..tostring( self.Positions[ SteamID ] ) )
	self.SFQueueAwaiting[ SteamID ] = nil
	if not self.Config.SpectatorFirst then return end
	local Existing = self.Positions[ SteamID ]
	local Action = "preserve_native"
	if Entry and self.SFLoading[ SteamID ] == Entry then
		self.SFLoading[ SteamID ] = nil
		if Now() > Entry.Deadline then
			Action = "late_no_autoqueue"
		elseif not Entry.Eligible then
			Action = "viewer_no_autoqueue"
		elseif Spectator( Client ) then
			local Player = Call( Client, "GetControllingPlayer", nil )
			if Call( Player, "GetTeamNumber", -1 ) == kSpectatorIndex then
				if not Existing then self:Enqueue( Client, { Silent = true } ) end
				Action = "queue_then_process"
			end
		end
	elseif Entry then
		Action = "expired_or_superseded_no_autoqueue"
	end
	self.SFClientEntry[ Client ] = nil
	self:LogSpectatorFirst( "confirm", SteamID, "action="..Action.." position="..tostring( self.Positions[ SteamID ] ) )
	-- Use the normal processor: no forced move, capacity bypass or position reset.
	-- The caller also requests processing after its history claim/snapshot work.
	if Action == "queue_then_process" then
		self:RequestProcess( "spectator_first_confirm" )
		if not Existing and self.Positions[ SteamID ] then self:NotifyPosition( Client, "[PlayerSlotQueue] Added." ) end
	end
end

function Plugin:SpectatorFirstDisconnected( Client )
	if not Human( Client ) or self.QueueMapChanging then return end
	local SteamID = ID( Client )
	local Current = Shine.GetClientByNS2ID( SteamID )
	if self.SFClientSlot[ Client ] and ( not Current or Current == Client ) then
		-- This is a passthrough exemption, not a new reserved capacity claim.
		self.SFReconnectUntil[ SteamID ] = Now() + self.Config.QueueHistoryLifeTime
		if self.Config.SpectatorFirst then
			self:LogSpectatorFirst( "reconnect_exemption", SteamID,
				"until="..self.SFReconnectUntil[ SteamID ].." reserves_capacity=false" )
		end
	end
	local Entry = self.SFClientEntry[ Client ]
	if Entry and self.SFLoading[ SteamID ] == Entry then
		self.SFLoading[ SteamID ] = nil
		self:LogSpectatorFirst( "disconnect", SteamID, "token="..Entry.Token )
	end
	self.SFClientEntry[ Client ], self.SFReady[ Client ], self.SFClientSlot[ Client ] = nil, nil, nil
end

function Plugin:SpectatorFirstTeamChanged( Client, NewTeam )
	if not Human( Client ) then return end
	local SteamID = ID( Client )
	self.SFClientSlot[ Client ] = NewTeam ~= kSpectatorIndex
	if NewTeam == kSpectatorIndex then self.SFReconnectUntil[ SteamID ] = nil end
	local Entry = self.SFLoading[ SteamID ]
	if NewTeam ~= kSpectatorIndex and Entry and Entry.Client == Client then
		self.SFLoading[ SteamID ] = nil
		self.SFClientEntry[ Client ] = nil
		self:LogSpectatorFirst( "handoff_cancelled", SteamID, "reason=already_left_spectator" )
	end
end

function Plugin:SweepSpectatorFirst()
	if self.Config.SpectatorFirst and not self.SFStatusReported then
		self.SFStatusReported = true
		local Callbacks = Shine.Hook.GetEventCallbacks
			and Shine.Hook.GetEventCallbacks( "CheckConnectionIsSpectator" ) or {}
		local Owned = #Callbacks == 1 and Callbacks[ 1 ] == self.SpectatorFirstShadowAssignmentWrapper
		self.SFWrapperReady = Owned
		self:LogSpectatorFirst( "hook_status", 0,
			"owned="..tostring( Owned ).." callbacks="..#Callbacks.." timeout=120", true )
	end
	local Time = Now()
	for SteamID, Entry in pairs( self.SFAdmission ) do
		if Entry.Deadline < Time then self.SFAdmission[ SteamID ] = nil end
	end
	for SteamID, Entry in pairs( self.SFLoading ) do
		if Entry.Deadline < Time then
			self.SFLoading[ SteamID ] = nil
			if Entry.Client and self.SFClientEntry[ Entry.Client ] == Entry then
				self.SFClientEntry[ Entry.Client ] = nil
			end
			Entry.Client = nil
			self:LogSpectatorFirst( "expired", SteamID, "token="..Entry.Token.." autoqueue=false" )
		end
	end
	for SteamID, TimeLimit in pairs( self.SFReconnectUntil ) do
		if TimeLimit < Time then self.SFReconnectUntil[ SteamID ] = nil end
	end
	for SteamID, Entry in pairs( self.SFMapReturn ) do
		if Entry.Expires < Time then self.SFMapReturn[ SteamID ] = nil end
	end
end

return Plugin
