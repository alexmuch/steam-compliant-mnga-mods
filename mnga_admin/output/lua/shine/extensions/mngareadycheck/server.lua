--[[
	MNGA Ready Check - server (.claude/docs/ready-check.md).

	Cost model: one CheckGameStart callback that is already called every
	gamerules tick before the round starts (Shine pregame uses the same hook).
	While no check runs it is a state compare and two GetCommander() calls.
	Player counting only happens when a new commander pair appears. A running
	check uses one TickInterval timer and event-driven messages. After an
	all-ready start, the leave-ban watch adds one timer for LeaveBanWindow
	seconds plus cheap set lookups in PostJoinTeam/ClientDisconnect.
]]

local Plugin = ...
local Shine = Shine

local StringFormat = string.format
local TableSort = table.sort
local Max = math.max
local Min = math.min
local Floor = math.floor
local Ceil = math.ceil
local SharedTime = Shared.GetTime
local ToString = tostring

local HOLD_HOOK = "MNGAReadyCheckHold"
local TICK_TIMER = "MNGAReadyCheckTick"
local LEAVE_WATCH_TIMER = "MNGAReadyCheckLeaveWatch"
local VOTE_NAME = "VoteReadyCheckStart"
local LOG_RETRY_INTERVAL = 10
-- A release's pending leave watch / team placement expires if the round has
-- not reached Countdown/Started this many seconds later (aborted start).
local PENDING_MAX_AGE = 120

local Phase = Plugin.Phase

local PhaseNames = {
	[ Phase.Idle ] = "idle",
	[ Phase.Commanders ] = "commanders",
	[ Phase.Pool ] = "pool",
	[ Phase.Open ] = "open",
	[ Phase.Vote ] = "vote",
	[ Phase.Waiting ] = "waiting"
}

-- Phases in which ready queued spectators take slots from unready players.
local SwapPhases = {
	[ Phase.Open ] = true,
	[ Phase.Vote ] = true,
	[ Phase.Waiting ] = true
}

local function SafeCall( Object, MethodName, Default, ... )
	if not Object or type( Object[ MethodName ] ) ~= "function" then return Default end
	local Success, Value = pcall( Object[ MethodName ], Object, ... )
	if not Success then return Default end
	return Value
end

local function GetSteamID( Client )
	return tonumber( SafeCall( Client, "GetUserId", 0 ) ) or 0
end

local function GetPlayer( Client )
	return SafeCall( Client, "GetControllingPlayer", nil )
end

local function GetTeam( Player )
	return SafeCall( Player, "GetTeamNumber", -1 )
end

local function IsHuman( Client )
	return Client ~= nil and not SafeCall( Client, "GetIsVirtual", true )
end

local function GetName( Client )
	return Client and Shine.GetClientName( Client ) or "<unknown>"
end

local function FormatDuration( Seconds )
	Seconds = Max( 0, Ceil( Seconds ) )
	return StringFormat( "%d:%02d", Floor( Seconds / 60 ), Seconds % 60 )
end

local function GetQueuePlugin()
	local Queue = Shine.Plugins and Shine.Plugins.mngareadyroomqueue
	if Queue and Queue.Enabled then return Queue end
	return nil
end

local function GetPregamePlugin()
	local Pregame = Shine.Plugins and Shine.Plugins.pregame
	if Pregame and Pregame.Enabled then return Pregame end
	return nil
end

local function IsNS20KStartOwner()
	return type( NS20KIsEnabled ) == "function" and NS20KIsEnabled( "CommanderlessStart" ) == true
end

local function GetCommanderPlayers( Gamerules )
	local Team1, Team2 = Gamerules.team1, Gamerules.team2
	return Team1 and Team1:GetCommander(), Team2 and Team2:GetCommander()
end

local function GetCommanderClients( Gamerules )
	local Com1, Com2 = GetCommanderPlayers( Gamerules )
	return Com1 and SafeCall( Com1, "GetClient", nil ), Com2 and SafeCall( Com2, "GetClient", nil )
end

-- Clicking READY is consumed by the GUI, so afkkick never sees it as
-- activity. VoteRandom's countdown shuffle (RemoveAFKPlayersFromTeams) moves
-- afkkick-AFK team players to the Ready Room, so ready players must count as
-- active: refreshed on each ready and again for everyone ready at release.
local function RefreshAFK( Client, Reason )
	local AFK = Shine.Plugins and Shine.Plugins.afkkick
	if not AFK or not AFK.Enabled or type( AFK.ResetAFKTime ) ~= "function" then return false end
	local Success = pcall( AFK.ResetAFKTime, AFK, Client, Reason )
	return Success
end

function Plugin:Log( Message, ... )
	if not self.Config.Debug then return end
	Shared.Message( "[readycheck] "..StringFormat( Message, ... ) )
end

-- Always printed: decisions an operator needs when reviewing a round.
function Plugin:LogImportant( Message, ... )
	Shared.Message( "[readycheck] "..StringFormat( Message, ... ) )
end

function Plugin:Announce( Client, Message )
	Shine:NotifyDualColour( Client, 80, 220, 120, "[READY]", 255, 255, 255, Message )
end

-- Like Announce, with MNGA_Name() arguments resolved to each viewer's SSB alias.
function Plugin:AnnounceNames( Client, Format, ... )
	MNGA_NotifyNamesDual( Client, 80, 220, 120, "[READY]", 255, 255, 255, Format, ... )
end

function Plugin:ApplyConfig()
	local Config = self.Config
	Config.TargetPlayers = Max( 1, Floor( tonumber( Config.TargetPlayers ) or 18 ) )
	Config.CommanderReadyWindow = Max( 0, tonumber( Config.CommanderReadyWindow ) or 60 )
	Config.PoolWindow = Max( 1, tonumber( Config.PoolWindow ) or 30 )
	Config.OpenWindow = Max( 1, tonumber( Config.OpenWindow ) or 60 )
	Config.WarnBeforePoolEnd = Max( 0, tonumber( Config.WarnBeforePoolEnd ) or 10 )
	Config.VoteDuration = Max( 5, tonumber( Config.VoteDuration ) or 20 )
	Config.VoteExecuteDelay = Max( 0, tonumber( Config.VoteExecuteDelay ) or 1 )
	Config.VoteStartTimeout = Max( 1, tonumber( Config.VoteStartTimeout ) or 60 )
	Config.TickInterval = Max( 0.25, tonumber( Config.TickInterval ) or 1 )
	Config.ReadyRateLimit = Max( 0, tonumber( Config.ReadyRateLimit ) or 0.5 )
	Config.LeaveBanWindow = Max( 0, tonumber( Config.LeaveBanWindow ) or 60 )
	Config.LeaveBanDuration = Max( 1, tonumber( Config.LeaveBanDuration ) or 1800 )
	Config.MaxHoldTime = Max( 0, tonumber( Config.MaxHoldTime ) or 300 )
	if Config.ReleaseMode ~= "countdown" and Config.ReleaseMode ~= "pregame" then
		self:LogImportant( "invalid ReleaseMode=%s; using countdown", ToString( Config.ReleaseMode ) )
		Config.ReleaseMode = "countdown"
	end

	if type( MNGAReadyCheckVote_Configure ) == "function" then
		MNGAReadyCheckVote_Configure( Config.VoteDuration, Config.VoteExecuteDelay )
	else
		self:LogImportant( "VotingReadyCheckStart.lua not loaded; the under-full start vote is unavailable" )
	end

	self:LogImportant( "config enabled=%s maxHold=%.1f testAlwaysActivate=%s",
		ToString( Config.ReadyCheckEnabled ), Config.MaxHoldTime, ToString( Config.TestAlwaysActivate ) )
	self:LogImportant( "config target=%d comWindow=%.1f pool=%.1f open=%.1f warn=%.1f vote=%s voteDuration=%.1f voteDelay=%.1f voteStartTimeout=%.1f tick=%.2f rate=%.2f release=%s leaveBan=%s window=%.1f duration=%.1f botComms=%s debug=%s",
		Config.TargetPlayers, Config.CommanderReadyWindow, Config.PoolWindow, Config.OpenWindow,
		Config.WarnBeforePoolEnd, ToString( Config.VoteEnabled ), Config.VoteDuration, Config.VoteExecuteDelay,
		Config.VoteStartTimeout, Config.TickInterval, Config.ReadyRateLimit, Config.ReleaseMode,
		ToString( Config.LeaveBanEnabled ), Config.LeaveBanWindow, Config.LeaveBanDuration,
		ToString( Config.AllowBotCommanders ), ToString( Config.Debug ) )
end

function Plugin:Initialise()
	self.ReadyFlags = {}
	self.LastReadyRequest = {}
	self.LastSentState = {}
	self.Token = 0
	self:ApplyConfig()
	self:CreateCommands()

	-- Runs before every plugin's CheckGameStart (plugins sit at MAX_PRIORITY
	-- + 0.5), so returning false holds Shine pregame and vanilla in one place.
	-- Fails open: any error ends the check and lets pregame run; after three
	-- errors the system turns itself off for the rest of the map.
	self.HookErrors = 0
	self.DisabledByErrors = false
	Shine.Hook.Add( "CheckGameStart", HOLD_HOOK, function( Gamerules )
		local Success, Result = xpcall( self.OnCheckGameStart, debug.traceback, self, Gamerules )
		if Success then return Result end
		self:OnHoldHookError( Result )
		return nil
	end, Shine.Hook.MAX_PRIORITY )

	self.Enabled = true
	return true
end

function Plugin:Cleanup()
	Shine.Hook.Remove( "CheckGameStart", HOLD_HOOK )
	if self.Check then
		self:EndCheck( "plugin_cleanup" )
	end
	self:StopLeaveWatch( "plugin_cleanup" )
	self:ClearPendingRelease( "plugin_cleanup" )
	self:ClearReadyFlags( "plugin_cleanup" )
	self.BaseClass.Cleanup( self )
end

function Plugin:OnHoldHookError( Error )
	self.HookErrors = self.HookErrors + 1
	self:LogImportant( "ERROR hold hook (%d): %s", self.HookErrors, ToString( Error ) )
	if self.Check then
		local Success, EndError = pcall( self.EndCheck, self, "hook_error" )
		if not Success then
			self.Check = nil
			self:DestroyTimer( TICK_TIMER )
			self:LogImportant( "ERROR ending check after hook error: %s", ToString( EndError ) )
		end
	end
	if self.HookErrors >= 3 and not self.DisabledByErrors then
		self.DisabledByErrors = true
		self:LogImportant( "DISABLED for this map after repeated hold-hook errors; pregame starts games normally" )
	end
end

function Plugin:IsSystemActive()
	return self.Config.ReadyCheckEnabled == true and not self.DisabledByErrors
end

--[[ Snapshot of who may ready and who is ready. Called on events and once per
	tick while a check runs; never while idle. ]]
local function SortQueued( A, B )
	return A.Position < B.Position
end

local function SortDisplaceOrder( A, B )
	-- Ready Room players go before team players; then lowest client id first.
	local ARank = A.Team == kTeamReadyRoom and 0 or 1
	local BRank = B.Team == kTeamReadyRoom and 0 or 1
	if ARank ~= BRank then return ARank < BRank end
	return A.ClientID < B.ClientID
end

function Plugin:BuildSnapshot( Gamerules )
	Gamerules = Gamerules or GetGamerules()
	local Com1, Com2
	if Gamerules then Com1, Com2 = GetCommanderClients( Gamerules ) end

	local Queue = GetQueuePlugin()
	local Snapshot = {
		Commanders = {},
		CommanderSet = {},
		ReadyComms = 0,
		UnreadyComms = 0,
		SlotHolders = {},
		SlotHolderSet = {},
		Queued = {},
		Eligible = {},
		ReadySlot = 0,
		UnreadySlot = 0,
		QueueReady = 0
	}

	-- Bot commanders (AllowBotCommanders testing) count as ready.
	local Coms = { Com1, Com2 }
	for i = 1, 2 do
		local Client = Coms[ i ]
		if Client then
			local Human = IsHuman( Client )
			local SteamID = GetSteamID( Client )
			local Ready = not Human or self.ReadyFlags[ SteamID ] == true
			Snapshot.Commanders[ #Snapshot.Commanders + 1 ] = {
				Client = Client, SteamID = SteamID, Ready = Ready, Human = Human, Team = i
			}
			if Human then Snapshot.CommanderSet[ Client ] = true end
			if Ready then
				Snapshot.ReadyComms = Snapshot.ReadyComms + 1
			else
				Snapshot.UnreadyComms = Snapshot.UnreadyComms + 1
			end
		end
	end

	local Clients, Count = Shine.GetAllClients()
	for i = 1, Count do
		local Client = Clients[ i ]
		if IsHuman( Client ) and Client ~= Com1 and Client ~= Com2 then
			local Player = GetPlayer( Client )
			local Team = GetTeam( Player )
			local SteamID = GetSteamID( Client )
			local Ready = self.ReadyFlags[ SteamID ] == true
			local Entry = {
				Client = Client, SteamID = SteamID, Team = Team, Ready = Ready,
				ClientID = SafeCall( Client, "GetId", 0 )
			}

			if not SafeCall( Client, "GetIsSpectator", true )
				and ( Team == kTeamReadyRoom or Team == kTeam1Index or Team == kTeam2Index ) then
				Snapshot.SlotHolders[ #Snapshot.SlotHolders + 1 ] = Entry
				Snapshot.SlotHolderSet[ Client ] = true
				Snapshot.Eligible[ Client ] = true
				if Ready then
					Snapshot.ReadySlot = Snapshot.ReadySlot + 1
				else
					Snapshot.UnreadySlot = Snapshot.UnreadySlot + 1
				end
			elseif Queue and Team == kSpectatorIndex then
				local Position = Queue:GetPosition( SteamID )
				if Position and not SafeCall( Queue, "IsSpectatorFirstWaiting", false, Client, SteamID ) then
					Entry.Position = Position
					Snapshot.Queued[ #Snapshot.Queued + 1 ] = Entry
					Snapshot.Eligible[ Client ] = true
					if Ready then Snapshot.QueueReady = Snapshot.QueueReady + 1 end
				end
			end
		end
	end

	TableSort( Snapshot.Queued, SortQueued )
	return Snapshot
end

-- Commanders may always ready (they are the only ones in the commander
-- phase); everyone else only once the commander phase is over.
function Plugin:IsEligibleNow( Snapshot, Client )
	if not self.Check or not Snapshot then return false end
	if Snapshot.CommanderSet[ Client ] then return true end
	return self.Check.Phase ~= Phase.Commanders and Snapshot.Eligible[ Client ] == true
end

function Plugin:IsFullyReady( Snapshot )
	return Snapshot.UnreadySlot == 0 and Snapshot.ReadySlot >= self.Config.TargetPlayers
end

--[[ Timer speed ]]
-- Pool and Open drain their timer at Plugin.GreenTimerRate while ready slot holders
-- + ready queued spectators reach TargetPlayers (the green x+y count).
-- PhaseEnd stays "Now + timer seconds left", so AdvancePhaseClock pulls it
-- in by the extra (rate - 1) seconds for the time since the last call.
function Plugin:GetTimerRate()
	local Check = self.Check
	if not Check or ( Check.Phase ~= Phase.Pool and Check.Phase ~= Phase.Open ) then return 1 end
	return Check.TimerRate or 1
end

function Plugin:AdvancePhaseClock( Now )
	local Check = self.Check
	if not Check then return end
	local Rate = self:GetTimerRate()
	if Rate > 1 and Check.PhaseEnd and Check.ClockAt and Now > Check.ClockAt then
		Check.PhaseEnd = Check.PhaseEnd - ( Now - Check.ClockAt ) * ( Rate - 1 )
	end
	Check.ClockAt = Now
end

function Plugin:UpdateTimerRate( Snapshot, Now )
	local Check = self.Check
	if not Check then return end
	local Rate = self:GetPhaseTimerRate( Check.Phase, Snapshot.ReadySlot, Snapshot.QueueReady,
		self.Config.TargetPlayers )
	if Rate == ( Check.TimerRate or 1 ) then return end
	self:AdvancePhaseClock( Now )
	Check.TimerRate = Rate
end

--[[ Client state ]]
function Plugin:GetTimeLeft( Now )
	local Check = self.Check
	if not Check then return 0, false end
	if Check.PhaseEnd and ( Check.Phase == Phase.Commanders or Check.Phase == Phase.Pool
		or Check.Phase == Phase.Open ) then
		return Max( 0, Ceil( Check.PhaseEnd - Now ) ), false
	end
	if Check.Phase == Phase.Vote then
		if Check.VoteEnd then return Max( 0, Ceil( Check.VoteEnd - Now ) ), false end
		return 0, true
	end
	return 0, false
end

-- During the commander phase the counts describe the commanders; afterwards
-- they describe the field players.
function Plugin:GetDisplayCounts( Snapshot )
	if not Snapshot then return 0, 0, 0, 0 end
	if self.Check and self.Check.Phase == Phase.Commanders then
		return Snapshot.ReadyComms, #Snapshot.Commanders, Snapshot.UnreadyComms, 0
	end
	return Snapshot.ReadySlot, self.Config.TargetPlayers, Snapshot.UnreadySlot, Snapshot.QueueReady
end

-- Sends ReadyCheckState to each client whose view changed. Global fields
-- changing (phase, counts, vote start) resend to everyone; per-client fields
-- (eligibility, own ready flag) only to that client. Force resends all.
function Plugin:BroadcastState( Snapshot, Force, OnlyClient )
	local Check = self.Check
	local Now = SharedTime()
	self:AdvancePhaseClock( Now )
	local TimeLeft, VotePending = self:GetTimeLeft( Now )
	local PhaseValue = Check and Check.Phase or Phase.Idle
	local ReadyCount, Needed, NotReady, QueueReady = self:GetDisplayCounts( Snapshot )
	-- PhaseStart, not PhaseEnd: a fast timer moves PhaseEnd every tick, and
	-- clients extrapolate it from the counts (GetPhaseTimerRate) without a resend.
	local GlobalKey = StringFormat( "%d:%d:%d:%d:%d:%s:%s:%s", PhaseValue, ReadyCount, Needed, NotReady,
		QueueReady, ToString( VotePending ), ToString( Check and Check.VoteEnd ), ToString( Check and Check.PhaseStart ) )
	local GlobalChanged = Force or GlobalKey ~= self.LastGlobalKey
	-- A single-client resend must not mark the global change as delivered.
	if not OnlyClient then
		self.LastGlobalKey = GlobalKey
	end

	local Clients, Count = Shine.GetAllClients()
	for i = 1, Count do
		local Client = Clients[ i ]
		if IsHuman( Client ) and ( not OnlyClient or OnlyClient == Client ) then
			local SteamID = GetSteamID( Client )
			local Eligible = self:IsEligibleNow( Snapshot, Client )
			local IsReady = self.ReadyFlags[ SteamID ] == true
			local CanSpectate = Check ~= nil and Snapshot ~= nil and Snapshot.SlotHolderSet[ Client ] == true
			local ClientKey = StringFormat( "%s:%s:%s", ToString( Eligible ), ToString( IsReady ), ToString( CanSpectate ) )
			if GlobalChanged or OnlyClient or self.LastSentState[ SteamID ] ~= ClientKey then
				self.LastSentState[ SteamID ] = ClientKey
				self:SendNetworkMessage( Client, "ReadyCheckState", {
					Phase = PhaseValue,
					TimeLeft = Min( 4095, Max( 0, Floor( TimeLeft ) ) ),
					ReadyCount = Min( 255, ReadyCount ),
					Needed = Min( 255, Needed ),
					NotReady = Min( 255, NotReady ),
					QueueReady = Min( 255, QueueReady ),
					Eligible = Eligible,
					IsReady = IsReady,
					CanSpectate = CanSpectate,
					VotePending = VotePending
				}, true )
			end
		end
	end
end

function Plugin:SendAttention( Clients, Reason )
	local Sent = 0
	for Client in pairs( Clients ) do
		self:SendNetworkMessage( Client, "ReadyCheckAttention", {}, true )
		Sent = Sent + 1
	end
	self:Log( "attention reason=%s clients=%d", Reason, Sent )
end

function Plugin:ClearReadyFlags( Reason )
	if next( self.ReadyFlags ) == nil then return end
	self.ReadyFlags = {}
	self.LastReadyRequest = {}
	self:SendNetworkMessage( nil, "ReadyFlagsReset", {}, true )
	self:Log( "ready flags cleared reason=%s", Reason )
end

--[[ Hold / activation ]]
function Plugin:IsStartDelayActive()
	local Pregame = GetPregamePlugin()
	local Delay = Pregame and Pregame.Config and tonumber( Pregame.Config.StartDelayInSeconds ) or 0
	return Delay > 0 and SharedTime() < Delay
end

function Plugin:IsAllowedCommander( Client )
	if not Client then return false end
	return IsHuman( Client ) or self.Config.AllowBotCommanders == true
end

function Plugin:OnCheckGameStart( Gamerules )
	if Gamerules:GetGameState() > kGameState.PreGame then return nil end

	if not self:IsSystemActive() then return nil end

	local Com1, Com2 = GetCommanderClients( Gamerules )
	local Check = self.Check
	if Check then
		if Com1 ~= Check.Com1 or Com2 ~= Check.Com2 then
			self:CancelCheck( Com1 ~= Check.Com1 and kTeam1Index or kTeam2Index )
			return nil
		end
		-- Safety net: never hold longer than MaxHoldTime. Fall back to the
		-- normal pregame start for this commander pair.
		if self.Config.MaxHoldTime > 0 and SharedTime() - Check.BeganAt >= self.Config.MaxHoldTime then
			self:Announce( nil, "The ready check took too long. Starting the game normally." )
			self:EndCheck( "max_hold_time" )
			self:ClearReadyFlags( "max_hold_time" )
			return nil
		end
		return false
	end

	local Decision = self.PairDecision
	if not Com1 or not Com2 then
		if Decision then
			self:Log( "commander pair cleared; next pair will be re-evaluated" )
			self.PairDecision = nil
			self:ClearPendingRelease( "commander_left" )
		end
		return nil
	end
	if Decision and Decision.Com1 == Com1 and Decision.Com2 == Com2 then return nil end
	if self:IsStartDelayActive() then return nil end

	self.PairDecision = { Com1 = Com1, Com2 = Com2 }

	if IsNS20KStartOwner() then
		self:LogImportant( "not activating: NS20K CommanderlessStart owns the round start" )
		return nil
	end
	if not self:IsAllowedCommander( Com1 ) or not self:IsAllowedCommander( Com2 ) then
		self:LogImportant( "not activating: bot commander present (com1Human=%s com2Human=%s)",
			ToString( IsHuman( Com1 ) ), ToString( IsHuman( Com2 ) ) )
		return nil
	end

	local Snapshot = self:BuildSnapshot( Gamerules )
	local Candidates = #Snapshot.SlotHolders + #Snapshot.Queued
	if self.Config.TestAlwaysActivate then
		self:LogImportant( "TestAlwaysActivate: ignoring candidates=%d target=%d", Candidates, self.Config.TargetPlayers )
	elseif Candidates <= self.Config.TargetPlayers then
		self:LogImportant( "not activating: candidates=%d (slotHolders=%d queued=%d) <= target=%d",
			Candidates, #Snapshot.SlotHolders, #Snapshot.Queued, self.Config.TargetPlayers )
		return nil
	end

	self:BeginCheck( Gamerules, Com1, Com2, false, Snapshot )
	return false
end

-- Stops Shine pregame's own start machinery so a later cancel lets it resolve
-- the commander state from scratch instead of firing a stale timer.
function Plugin:PausePregame( Gamerules )
	local Pregame = GetPregamePlugin()
	if Pregame then
		local WasStarting = Pregame.GameStarting
		if WasStarting and Pregame.AbortGameStart then
			Pregame:AbortGameStart( Gamerules )
		end
		SafeCall( Pregame, "ResetStartEndTime" )
		SafeCall( Pregame, "DestroyTimers" )
		Pregame.GameStarting = false
		Pregame.SentCountdown = nil
		self:Log( "pregame paused wasStarting=%s", ToString( WasStarting ) )
	end
	if Gamerules:GetGameState() == kGameState.PreGame then
		Gamerules:SetGameState( kGameState.NotStarted )
	end
end

function Plugin:BeginCheck( Gamerules, Com1, Com2, Forced, Snapshot )
	self.Token = self.Token + 1
	self:ClearReadyFlags( "begin" )
	self.Check = {
		Token = self.Token,
		Com1 = Com1,
		Com2 = Com2,
		Forced = Forced == true,
		Phase = Phase.Idle,
		BeganAt = SharedTime()
	}
	self.PairDecision = { Com1 = Com1, Com2 = Com2 }
	self.LastSentState = {}
	self:ClearPendingRelease( "begin" )
	self:PausePregame( Gamerules )

	self:CreateTimer( TICK_TIMER, self.Config.TickInterval, -1, function()
		self:Tick()
	end )

	Snapshot = Snapshot or self:BuildSnapshot( Gamerules )
	self:LogImportant( "BEGIN token=%d forced=%s com1=%s com2=%s slotHolders=%d queued=%d target=%d",
		self.Token, ToString( Forced ), GetName( Com1 ), GetName( Com2 ), #Snapshot.SlotHolders,
		#Snapshot.Queued, self.Config.TargetPlayers )

	self:SetPhase( Phase.Commanders )
	-- Bot commanders (testing) are already ready.
	self:Evaluate( "begin" )
end

function Plugin:EndCheck( Reason )
	local Check = self.Check
	if not Check then return end
	self.Check = nil
	self:DestroyTimer( TICK_TIMER )
	self:LogImportant( "END token=%d reason=%s phase=%s", Check.Token, ToString( Reason ),
		PhaseNames[ Check.Phase ] or ToString( Check.Phase ) )
	-- Close our under-full vote if it is still open (e.g. everyone readied
	-- during the vote, or a commander left). Not from inside the vote's own
	-- pass callback: the voting system finishes that vote itself.
	if Check.VoteStarted and not self.InVotePassCallback and type( CancelActiveVote ) == "function" then
		local ActiveData = type( GetActiveVoteData ) == "function" and GetActiveVoteData() or nil
		if ActiveData and tonumber( ActiveData.token ) == Check.Token then
			CancelActiveVote( VOTE_NAME, Reason )
		end
	end
	self:BroadcastState( nil, true )
end

function Plugin:CancelCheck( Team )
	self:Announce( nil, StringFormat( "Ready check cancelled: the %s commander left the chair.",
		Team == kTeam1Index and "Marine" or "Alien" ) )
	self:EndCheck( StringFormat( "commander_left_team%d", Team ) )
	self:ClearReadyFlags( "cancel" )
	self.PairDecision = nil
end

--[[ Phases ]]
function Plugin:SetPhase( NewPhase, Now )
	local Check = self.Check
	if not Check then return end
	Now = Now or SharedTime()
	local OldPhase = Check.Phase
	Check.Phase = NewPhase
	Check.PhaseStart = Now
	Check.PhaseEnd = nil
	Check.ClockAt = Now
	self:LogImportant( "phase token=%d %s -> %s", Check.Token, PhaseNames[ OldPhase ] or ToString( OldPhase ),
		PhaseNames[ NewPhase ] or ToString( NewPhase ) )

	if NewPhase == Phase.Commanders then
		if self.Config.CommanderReadyWindow > 0 then
			Check.PhaseEnd = Now + self.Config.CommanderReadyWindow
		end
		local Snapshot = self:BuildSnapshot()
		local Unready = {}
		for i = 1, #Snapshot.Commanders do
			local Entry = Snapshot.Commanders[ i ]
			if not Entry.Ready then Unready[ Entry.Client ] = true end
		end
		local Limit = self.Config.CommanderReadyWindow > 0
			and StringFormat( " within %d seconds", Floor( self.Config.CommanderReadyWindow ) ) or ""
		self:Announce( nil, StringFormat(
			"Ready check: both commanders must click READY (or type !ready)%s, then everyone else readies up.", Limit ) )
		self:SendAttention( Unready, "commanders" )
		self:BroadcastState( Snapshot, true )
	elseif NewPhase == Phase.Pool then
		Check.PhaseEnd = Now + self.Config.PoolWindow
		Check.WarnSent = self.Config.WarnBeforePoolEnd <= 0
		local Snapshot = self:BuildSnapshot()
		local Unready = {}
		for Client in pairs( Snapshot.Eligible ) do
			if not self.ReadyFlags[ GetSteamID( Client ) ] then Unready[ Client ] = true end
		end
		self:Announce( nil, StringFormat(
			"Both commanders are ready! Click READY or type !ready within %d seconds. Queued spectators can ready too.",
			Floor( self.Config.PoolWindow ) ) )
		self:SendAttention( Unready, "pool" )
		self:BroadcastState( Snapshot, true )
	elseif NewPhase == Phase.Open then
		Check.PhaseEnd = Now + self.Config.OpenWindow
		self:Announce( nil, StringFormat(
			"Slots are now open: ready queued spectators replace players who are not ready. %d seconds until a start vote.",
			Floor( self.Config.OpenWindow ) ) )
	elseif NewPhase == Phase.Vote then
		Check.VoteStarted = false
		Check.VoteEnd = nil
		Check.LastVoteRetryLog = nil
		if not self.Config.VoteEnabled or type( StartVote ) ~= "function" then
			self:LogImportant( "vote skipped enabled=%s startVote=%s", ToString( self.Config.VoteEnabled ),
				ToString( type( StartVote ) == "function" ) )
			return self:SetPhase( Phase.Waiting, Now )
		end
		self:TryStartVote( Now )
	elseif NewPhase == Phase.Waiting then
		self:Announce( nil,
			"Waiting for ready players. A commander can leave and re-enter the chair to restart the ready check." )
	end
end

-- Commander phase timeout: unready human commanders are logged out of the
-- chair, which cancels the check so someone else can take the chair.
function Plugin:ExpireCommanderPhase()
	local Gamerules = GetGamerules()
	if not Gamerules then return end
	local Snapshot = self:BuildSnapshot( Gamerules )
	local ComPlayers = { GetCommanderPlayers( Gamerules ) }
	for i = 1, #Snapshot.Commanders do
		local Entry = Snapshot.Commanders[ i ]
		if not Entry.Ready then
			local ComPlayer = ComPlayers[ Entry.Team ]
			local LoggedOut = ComPlayer ~= nil and SafeCall( ComPlayer, "Logout", nil ) ~= nil
			self:LogImportant( "commander did not ready in time: %s(%s team=%d) logout=%s",
				GetName( Entry.Client ), Entry.SteamID, Entry.Team, ToString( LoggedOut ) )
			self:AnnounceNames( nil,
				"%s did not ready in time and was removed from the command chair.", MNGA_Name( Entry.Client ) )
		end
	end
	-- The hold hook sees the empty chair on the next tick and cancels.
end

function Plugin:TryStartVote( Now )
	local Check = self.Check
	if not Check or Check.VoteStarted then return end

	if Now - Check.PhaseStart >= self.Config.VoteStartTimeout then
		self:LogImportant( "vote could not start within %.1fs; waiting", self.Config.VoteStartTimeout )
		return self:SetPhase( Phase.Waiting, Now )
	end

	local Snapshot = self:BuildSnapshot()
	-- Pass rule: a majority of the READY humans (field + commanders), so AFK
	-- players in the electorate cannot make the vote impossible to pass.
	local ReadyHumans = Snapshot.ReadySlot
	for i = 1, #Snapshot.Commanders do
		local Entry = Snapshot.Commanders[ i ]
		if Entry.Human and Entry.Ready then ReadyHumans = ReadyHumans + 1 end
	end
	local Required = Max( 1, Floor( ReadyHumans / 2 ) + 1 )
	if type( MNGAReadyCheckVote_SetRequiredVotes ) == "function" then
		MNGAReadyCheckVote_SetRequiredVotes( Required )
	end
	local Started, Reason = StartVote( VOTE_NAME, nil, {
		ready = Snapshot.ReadySlot,
		needed = self.Config.TargetPlayers,
		token = Check.Token
	} )
	if Started then
		Check.VoteStarted = true
		Check.VoteEnd = Now + self.Config.VoteDuration
		self:LogImportant( "vote started token=%d ready=%d/%d readyHumans=%d required=%d duration=%.1f", Check.Token,
			Snapshot.ReadySlot, self.Config.TargetPlayers, ReadyHumans, Required, self.Config.VoteDuration )
		self:Announce( nil, StringFormat(
			"Not enough ready players (%d/%d). Vote now: start the game with less than full teams?",
			Snapshot.ReadySlot, self.Config.TargetPlayers ) )
		return
	end

	if not Check.LastVoteRetryLog or Now - Check.LastVoteRetryLog >= LOG_RETRY_INTERVAL then
		Check.LastVoteRetryLog = Now
		self:LogImportant( "vote start blocked reason=%s; retrying", ToString( Reason ) )
	end
end

function Plugin:UpdateVote( Now )
	local Check = self.Check
	if not Check.VoteStarted then
		return self:TryStartVote( Now )
	end

	-- A pass releases the game from the vote callback before the vote is
	-- cleared, so a vote that is gone while the check still runs has failed.
	local ActiveName = type( GetActiveVoteName ) == "function" and GetActiveVoteName() or nil
	local ActiveData = type( GetActiveVoteData ) == "function" and GetActiveVoteData() or nil
	if ActiveName == VOTE_NAME and ActiveData and ActiveData.token == Check.Token then return end

	self:LogImportant( "vote ended without passing token=%d active=%s", Check.Token, ToString( ActiveName ) )
	self:Announce( nil, "The vote to start with less than full teams failed." )
	self:SetPhase( Phase.Waiting, Now )
end

function Plugin:Tick()
	local Check = self.Check
	if not Check then
		self:DestroyTimer( TICK_TIMER )
		return
	end
	local Gamerules = GetGamerules()
	if not Gamerules or Gamerules:GetGameState() > kGameState.PreGame then
		self:EndCheck( "game_state" )
		return
	end
	if not self:IsSystemActive() then
		self:EndCheck( "system_disabled" )
		self:ClearReadyFlags( "system_disabled" )
		return
	end

	local Now = SharedTime()
	self:AdvancePhaseClock( Now )
	if Check.Phase == Phase.Commanders then
		if Check.PhaseEnd and Now >= Check.PhaseEnd and not Check.CommanderExpired then
			Check.CommanderExpired = true
			self:ExpireCommanderPhase()
		end
	elseif Check.Phase == Phase.Pool then
		if not Check.WarnSent and Now >= Check.PhaseEnd - self.Config.WarnBeforePoolEnd then
			Check.WarnSent = true
			-- Chat only: players get one taskbar flash per round (pool start).
			local Snapshot = self:BuildSnapshot( Gamerules )
			local Warned = 0
			for i = 1, #Snapshot.SlotHolders do
				local Entry = Snapshot.SlotHolders[ i ]
				if not Entry.Ready then
					Warned = Warned + 1
					self:Announce( Entry.Client, StringFormat(
						"You are not ready! Click READY or type !ready within %d seconds or a queued player may take your slot.",
						Max( 0, Ceil( ( Check.PhaseEnd - Now ) / self:GetTimerRate() ) ) ) )
				end
			end
			self:Log( "pool warning sent (chat) unready=%d", Warned )
		end
		if Now >= Check.PhaseEnd then self:SetPhase( Phase.Open, Now ) end
	elseif Check.Phase == Phase.Open then
		if Now >= Check.PhaseEnd then self:SetPhase( Phase.Vote, Now ) end
	elseif Check.Phase == Phase.Vote then
		self:UpdateVote( Now )
	end

	if self.Check then
		self:Evaluate( "tick" )
	end
end

--[[ Ready requests ]]
function Plugin:TrySetReady( Client, Source )
	if not IsHuman( Client ) then return false end
	local Check = self.Check
	if not Check then
		self:Announce( Client, "There is no ready check running." )
		return false
	end

	local SteamID = GetSteamID( Client )
	local Now = SharedTime()
	local Last = self.LastReadyRequest[ SteamID ]
	if Last and Now - Last < self.Config.ReadyRateLimit then return false end
	self.LastReadyRequest[ SteamID ] = Now

	local Snapshot = self:BuildSnapshot()
	if self.ReadyFlags[ SteamID ] then
		self:BroadcastState( Snapshot, false, Client )
		return false
	end

	if not self:IsEligibleNow( Snapshot, Client ) then
		self:Log( "ready rejected (ineligible) name=%s steamid=%s source=%s phase=%s", GetName( Client ), SteamID,
			Source, PhaseNames[ Check.Phase ] or ToString( Check.Phase ) )
		if Check.Phase == Phase.Commanders and Snapshot.Eligible[ Client ] then
			self:Announce( Client, "Waiting for both commanders to ready first." )
		else
			self:Announce( Client, "Only players and queued spectators can ready up. Spectators: press F4 to queue first." )
		end
		return false
	end

	self.ReadyFlags[ SteamID ] = true
	RefreshAFK( Client, "ready check: ready" )
	self:Announce( Client, "You are ready." )
	self:SendNetworkMessage( nil, "ReadyFlag", { SteamID = ToString( SteamID ), Ready = true }, true )
	self:Log( "ready name=%s steamid=%s source=%s phase=%s commander=%s", GetName( Client ), SteamID, Source,
		PhaseNames[ Check.Phase ] or ToString( Check.Phase ), ToString( Snapshot.CommanderSet[ Client ] == true ) )
	self:Evaluate( "ready" )
	return true
end

function Plugin:ReceiveRequestReady( Client )
	self:TrySetReady( Client, "button" )
end

-- "Go to spectator" button: the ready check holds the mouse cursor, so a
-- field player who would rather spectate cannot walk to the spectator
-- entrance. Moves them to spectator (not queued); the queue refills the slot.
function Plugin:TryGoSpectate( Client, Source )
	if not IsHuman( Client ) or not self.Check then return false end
	local SteamID = GetSteamID( Client )
	local Now = SharedTime()
	local Last = self.LastReadyRequest[ SteamID ]
	if Last and Now - Last < self.Config.ReadyRateLimit then return false end
	self.LastReadyRequest[ SteamID ] = Now

	local Snapshot = self:BuildSnapshot()
	if not Snapshot.SlotHolderSet[ Client ] then
		self:Log( "spectate rejected (not a field slot holder) name=%s steamid=%s source=%s", GetName( Client ),
			SteamID, ToString( Source ) )
		self:BroadcastState( Snapshot, false, Client )
		return false
	end

	local Gamerules = GetGamerules()
	local Player = GetPlayer( Client )
	local OldTeam = GetTeam( Player )
	local Moved = Gamerules ~= nil and Player ~= nil and Gamerules:JoinTeam( Player, kSpectatorIndex, true, true ) == true
	self:LogImportant( "go to spectator name=%s steamid=%s team=%d phase=%s source=%s success=%s", GetName( Client ),
		SteamID, OldTeam, PhaseNames[ self.Check.Phase ] or ToString( self.Check.Phase ), ToString( Source ),
		ToString( Moved ) )
	if not Moved then
		self:Announce( Client, "Could not move you to spectator." )
		self:BroadcastState( Snapshot, false, Client )
		return false
	end

	if self.ReadyFlags[ SteamID ] then
		self.ReadyFlags[ SteamID ] = nil
		self:SendNetworkMessage( nil, "ReadyFlag", { SteamID = ToString( SteamID ), Ready = false }, true )
	end
	self:Announce( Client, "You left the player pool and are now spectating. Press F4 to queue again." )
	self:Evaluate( "spectate" )
	return true
end

function Plugin:ReceiveRequestSpectate( Client )
	self:TryGoSpectate( Client, "button" )
end

function Plugin:ReceiveRequestReadyCheckSnapshot( Client )
	if not IsHuman( Client ) then return end
	for SteamID in pairs( self.ReadyFlags ) do
		self:SendNetworkMessage( Client, "ReadyFlag", { SteamID = ToString( SteamID ), Ready = true }, true )
	end
	self:BroadcastState( self.Check and self:BuildSnapshot() or nil, false, Client )
	self:Log( "snapshot sent name=%s flags=%d", GetName( Client ), self:CountReadyFlags() )
end

function Plugin:CountReadyFlags()
	local Count = 0
	for _ in pairs( self.ReadyFlags ) do Count = Count + 1 end
	return Count
end

--[[ Evaluation, swaps and release ]]
function Plugin:Evaluate( Reason )
	local Check = self.Check
	if not Check or self.Evaluating then return end
	self.Evaluating = true

	local Success, Error = xpcall( function()
		local Snapshot = self:BuildSnapshot()

		if Check.Phase == Phase.Commanders then
			if Snapshot.UnreadyComms == 0 and #Snapshot.Commanders == 2 then
				self:SetPhase( Phase.Pool )
				Snapshot = self:BuildSnapshot()
			else
				self:BroadcastState( Snapshot, false )
				return
			end
		end

		if SwapPhases[ Check.Phase ] and self:Reconcile( Snapshot, Reason ) then
			Snapshot = self:BuildSnapshot()
		end

		if self:IsFullyReady( Snapshot ) then
			self:Announce( nil, StringFormat( "All %d players are ready. The game is starting!", Snapshot.ReadySlot ) )
			self:Release( "all_ready", Snapshot )
			return
		end

		self:UpdateTimerRate( Snapshot, SharedTime() )
		self:BroadcastState( Snapshot, false )
	end, debug.traceback )

	self.Evaluating = false
	if not Success then
		self:LogImportant( "ERROR evaluate reason=%s error=%s", ToString( Reason ), ToString( Error ) )
	end
end

-- Swaps ready queued spectators (queue order) into slots held by unready
-- players. Returns true if anyone moved.
function Plugin:Reconcile( Snapshot, Reason )
	local Queue = GetQueuePlugin()
	if not Queue or type( Queue.ReadyCheckSwap ) ~= "function" then
		if not self.LoggedNoQueue then
			self.LoggedNoQueue = true
			self:LogImportant( "mngareadyroomqueue missing or without ReadyCheckSwap; no swaps possible" )
		end
		return false
	end

	local Incoming = {}
	for i = 1, #Snapshot.Queued do
		local Entry = Snapshot.Queued[ i ]
		if Entry.Ready then Incoming[ #Incoming + 1 ] = Entry end
	end
	if #Incoming == 0 then return false end

	local Outgoing = {}
	for i = 1, #Snapshot.SlotHolders do
		local Entry = Snapshot.SlotHolders[ i ]
		if not Entry.Ready then Outgoing[ #Outgoing + 1 ] = Entry end
	end
	if #Outgoing == 0 then return false end
	TableSort( Outgoing, SortDisplaceOrder )

	local Moved = false
	for i = 1, Min( #Incoming, #Outgoing ) do
		local In, Out = Incoming[ i ], Outgoing[ i ]
		local Success, FailReason = Queue:ReadyCheckSwap( Out.Client, In.Client )
		self:LogImportant( "swap reason=%s out=%s(%s team=%d) in=%s(%s queue=%d) success=%s fail=%s",
			ToString( Reason ), GetName( Out.Client ), Out.SteamID, Out.Team, GetName( In.Client ), In.SteamID,
			In.Position, ToString( Success ), ToString( FailReason ) )
		if not Success then break end
		Moved = true
		self:AnnounceNames( nil, "%s was not ready and was moved to spectator; %s (queue: %s) takes the slot.",
			MNGA_Name( Out.Client ), MNGA_Name( In.Client ), ToString( In.Position ) )
		self:Announce( Out.Client,
			"You were not ready in time and were moved to spectator. Press F4 to queue again." )
	end
	return Moved
end

function Plugin:StartGame( Gamerules )
	local Pregame = GetPregamePlugin()
	if self.Config.ReleaseMode == "pregame" and Pregame and Pregame.QueueGameStart then
		SafeCall( Pregame, "ResetStartEndTime" )
		Pregame:QueueGameStart( Gamerules )
		return "pregame_queue"
	end
	if Pregame and Pregame.StartCountdown then
		Pregame:StartCountdown()
		return "pregame_countdown"
	end
	Gamerules:ResetGame()
	Gamerules:SetGameState( kGameState.Countdown )
	Gamerules.countdownTime = kCountDownLength
	Gamerules.lastCountdownPlayed = nil
	return "direct_countdown"
end

function Plugin:Release( Reason, Snapshot )
	local Check = self.Check
	if not Check then return end
	local Gamerules = GetGamerules()
	self:LogImportant( "RELEASE token=%d reason=%s ready=%d/%d unready=%d mode=%s", Check.Token, Reason,
		Snapshot and Snapshot.ReadySlot or -1, self.Config.TargetPlayers, Snapshot and Snapshot.UnreadySlot or -1,
		self.Config.ReleaseMode )
	-- Keep the commander pair cached so the hold does not re-activate while
	-- Shine pregame runs its own wait in "pregame" release mode.
	-- Ready non-commander players, captured before the flags are cleared at
	-- Countdown; the ones still in the Ready Room after the countdown shuffle
	-- are put on a team (PlaceReadyRoomPlayers).
	local ReadySteamIDs, ReadyCount = {}, 0
	if Snapshot then
		for i = 1, #Snapshot.SlotHolders do
			local Entry = Snapshot.SlotHolders[ i ]
			if Entry.Ready then
				ReadySteamIDs[ Entry.SteamID ] = true
				ReadyCount = ReadyCount + 1
			end
		end
	end
	self:EndCheck( "released:"..Reason )
	self.PairDecision = { Com1 = Check.Com1, Com2 = Check.Com2 }
	local Now = SharedTime()
	self.PendingPlacement = { Token = Check.Token, At = Now, SteamIDs = ReadySteamIDs }
	-- Only an all-ready start arms the early-leave ban; it is captured when the
	-- round actually reaches Started (SetGameState). It survives the
	-- NotStarted that ResetGame sets inside StartCountdown.
	if Reason == "all_ready" and self.Config.LeaveBanEnabled == true and self.Config.LeaveBanWindow > 0 then
		-- Members: the ready humans at release (human commanders + ready field
		-- players), wherever they are (team or Ready Room before placement).
		local Members, MemberCount = {}, 0
		if Snapshot then
			for i = 1, #Snapshot.Commanders do
				local Entry = Snapshot.Commanders[ i ]
				if Entry.Human then
					Members[ Entry.SteamID ] = GetName( Entry.Client )
					MemberCount = MemberCount + 1
				end
			end
			for i = 1, #Snapshot.SlotHolders do
				local Entry = Snapshot.SlotHolders[ i ]
				if Entry.Ready then
					Members[ Entry.SteamID ] = GetName( Entry.Client )
					MemberCount = MemberCount + 1
				end
			end
		end
		self.PendingLeaveWatch = { Token = Check.Token, At = Now, Members = Members, Count = MemberCount }
	else
		self.PendingLeaveWatch = nil
	end
	if not Gamerules then
		self:LogImportant( "ERROR release without gamerules" )
		return
	end
	-- Before StartGame: the countdown shuffle runs inside it.
	local Refreshed = 0
	if Snapshot then
		for i = 1, #Snapshot.Commanders do
			local Entry = Snapshot.Commanders[ i ]
			if Entry.Human and RefreshAFK( Entry.Client, "ready check: release" ) then Refreshed = Refreshed + 1 end
		end
		for i = 1, #Snapshot.SlotHolders do
			local Entry = Snapshot.SlotHolders[ i ]
			if Entry.Ready and RefreshAFK( Entry.Client, "ready check: release" ) then Refreshed = Refreshed + 1 end
		end
	end
	self:Log( "afk timers refreshed for ready players count=%d", Refreshed )
	local Path = self:StartGame( Gamerules )
	-- In countdown mode the watch was already armed inside StartGame
	-- (SetGameState Countdown); in pregame mode it is still pending.
	self:LogImportant( "release path=%s state=%s leaveWatch=%s placeReady=%d", Path,
		ToString( Gamerules:GetGameState() ),
		self.LeaveWatch and "armed" or ( self.PendingLeaveWatch and "pending" or "off" ), ReadyCount )
end

function Plugin:ClearPendingRelease( Reason )
	if not self.PendingLeaveWatch and not self.PendingPlacement then return end
	self:Log( "pending release state cleared reason=%s leaveWatch=%s placement=%s", ToString( Reason ),
		ToString( self.PendingLeaveWatch ~= nil ), ToString( self.PendingPlacement ~= nil ) )
	self.PendingLeaveWatch = nil
	self.PendingPlacement = nil
end

local function IsPendingFresh( Pending )
	return Pending ~= nil and SharedTime() - Pending.At <= PENDING_MAX_AGE
end

local function PickSmallerTeam( Gamerules )
	local Team1 = Gamerules:GetTeam( kTeam1Index ):GetNumPlayers()
	local Team2 = Gamerules:GetTeam( kTeam2Index ):GetNumPlayers()
	if Team1 ~= Team2 then return Team1 < Team2 and kTeam1Index or kTeam2Index end
	return math.random() < 0.5 and kTeam1Index or kTeam2Index
end

-- Runs one tick after Countdown starts, so VoteRandom's countdown auto-shuffle
-- has already run. Ready players it left in the Ready Room (auto-shuffle off,
-- vote-suppressed, or below its player minimum) join a team: VoteRandom's
-- JoinRandomTeam when available (balances like a late join), else the
-- smaller team. Players promoted from the queue after release were never
-- ready and stay in the Ready Room.
function Plugin:PlaceReadyRoomPlayers( Placement )
	local Gamerules = GetGamerules()
	if not Gamerules or Gamerules:GetGameState() ~= kGameState.Countdown then
		self:LogImportant( "placement skipped token=%d state=%s", Placement.Token,
			ToString( Gamerules and Gamerules:GetGameState() ) )
		return
	end
	local Checked, Placed = 0, 0
	local Clients, Count = Shine.GetAllClients()
	for i = 1, Count do
		local Client = Clients[ i ]
		local Player = IsHuman( Client ) and GetPlayer( Client )
		local SteamID = Player and GetSteamID( Client )
		if Player and GetTeam( Player ) == kTeamReadyRoom and Placement.SteamIDs[ SteamID ] then
			Checked = Checked + 1
			if self:PlaceClientOnTeam( Gamerules, Client, "ready" ) then Placed = Placed + 1 end
		end
	end
	self:LogImportant( "placement done token=%d readyRoomReady=%d placed=%d", Placement.Token, Checked, Placed )
end

-- Ready Room -> a team: VoteRandom's JoinRandomTeam (balances like a late
-- join), else the smaller team. Returns true when the player is on a team.
function Plugin:PlaceClientOnTeam( Gamerules, Client, Why )
	local Player = GetPlayer( Client )
	if not Player or GetTeam( Player ) ~= kTeamReadyRoom then return false end
	local SteamID = GetSteamID( Client )
	local VoteRandom = Shine.Plugins and Shine.Plugins.voterandom
	local Method = "voterandom"
	if VoteRandom and VoteRandom.Enabled and type( VoteRandom.JoinRandomTeam ) == "function" then
		local Success, Error = pcall( VoteRandom.JoinRandomTeam, VoteRandom, Gamerules, Player )
		if not Success then
			self:LogImportant( "ERROR voterandom JoinRandomTeam for %s: %s", SteamID, ToString( Error ) )
		end
	end
	Player = GetPlayer( Client )
	if Player and GetTeam( Player ) == kTeamReadyRoom then
		Method = "smaller_team"
		Gamerules:JoinTeam( Player, PickSmallerTeam( Gamerules ) )
	end
	local NewTeam = GetTeam( GetPlayer( Client ) )
	local Success = NewTeam == kTeam1Index or NewTeam == kTeam2Index
	self:LogImportant( "placed Ready Room player (%s) %s(%s) team=%s method=%s success=%s", ToString( Why ),
		GetName( Client ), SteamID, ToString( NewTeam ), Method, ToString( Success ) )
	return Success
end

function Plugin:OnUnderfullVotePassed( Token )
	local Check = self.Check
	if not Check or Check.Token ~= tonumber( Token ) then
		self:LogImportant( "stale under-full vote pass token=%s current=%s", ToString( Token ),
			ToString( Check and Check.Token ) )
		return
	end

	local Gamerules = GetGamerules()
	local Snapshot = self:BuildSnapshot( Gamerules )
	local Queue = GetQueuePlugin()

	-- Unready slot holders leave before the start. Inside a queue transaction
	-- so the queue only refills the freed slots after the countdown (and the
	-- countdown shuffle) has begun; late promotions stay in the Ready Room.
	local function MoveUnreadyAndStart()
		for i = 1, #Snapshot.SlotHolders do
			local Entry = Snapshot.SlotHolders[ i ]
			if not Entry.Ready then
				local Player = GetPlayer( Entry.Client )
				local Moved = Player and Gamerules:JoinTeam( Player, kSpectatorIndex, true, true ) == true
				self:LogImportant( "vote pass: moved unready %s(%s team=%d) to spectator success=%s",
					GetName( Entry.Client ), Entry.SteamID, Entry.Team, ToString( Moved ) )
				if Moved then
					self:Announce( nil, StringFormat( "%s was not ready and was moved to spectator.",
						GetName( Entry.Client ) ) )
					self:Announce( Entry.Client,
						"You were not ready and were moved to spectator. Press F4 to queue again." )
				end
			end
		end
		self:Announce( nil, StringFormat( "Vote passed. Starting with %d ready players.", Snapshot.ReadySlot ) )
		self:Release( "vote_passed", Snapshot )
	end

	self.InVotePassCallback = true
	if Queue and Queue.RunTransaction then
		local Success, Error = Queue:RunTransaction( "ready_check_vote_release", MoveUnreadyAndStart )
		if not Success then
			self:LogImportant( "ERROR vote release transaction failed: %s", ToString( Error ) )
		end
	else
		local Success, Error = pcall( MoveUnreadyAndStart )
		if not Success then
			self:LogImportant( "ERROR vote release failed: %s", ToString( Error ) )
		end
	end
	self.InVotePassCallback = false
end

--[[ Early-leave ban after an all-ready start.
	Members are the ready humans at release (human commanders + ready field
	players). The watch arms when the countdown starts, so leaving during the
	6s countdown counts, and ends LeaveBanWindow seconds after the round
	reaches Started. Leaving = disconnecting (any reason, including AFK kicks),
	moving to spectator from anywhere (including the round-start base-AFK
	move), or moving from Marines/Aliens to the Ready Room. A Ready Room
	leaver is also moved to spectator so the slot frees up. The watch stops
	if the countdown aborts, when the round ends, or on map change, so
	round-end and map-change moves never ban. ]]
function Plugin:ArmLeaveWatch()
	local Pending = self.PendingLeaveWatch
	self.PendingLeaveWatch = nil
	if not Pending then return end
	if not IsPendingFresh( Pending ) then
		self:LogImportant( "leave watch not armed: release token=%d is %.0fs old", Pending.Token,
			SharedTime() - Pending.At )
		return
	end
	self:DestroyTimer( LEAVE_WATCH_TIMER )
	self.LeaveWatch = { Token = Pending.Token, Members = Pending.Members, EndsAt = nil }
	self:LogImportant( "leave watch armed (countdown) token=%d members=%d", Pending.Token, Pending.Count or 0 )
end

function Plugin:StartLeaveWatchWindow()
	local Watch = self.LeaveWatch
	if not Watch then return end
	Watch.EndsAt = SharedTime() + self.Config.LeaveBanWindow
	self:CreateTimer( LEAVE_WATCH_TIMER, self.Config.LeaveBanWindow, 1, function()
		self:StopLeaveWatch( "window_elapsed" )
	end )
	local Count = 0
	for _ in pairs( Watch.Members ) do Count = Count + 1 end
	self:LogImportant( "leave watch started token=%d members=%d window=%.1f banDuration=%.1f", Watch.Token, Count,
		self.Config.LeaveBanWindow, self.Config.LeaveBanDuration )
end

function Plugin:StopLeaveWatch( Reason )
	if not self.LeaveWatch then return end
	self:LogImportant( "leave watch stopped token=%d reason=%s", self.LeaveWatch.Token, ToString( Reason ) )
	self.LeaveWatch = nil
	self:DestroyTimer( LEAVE_WATCH_TIMER )
end

function Plugin:OnWatchedLeave( Client, SteamID, How )
	local Watch = self.LeaveWatch
	if not Watch or not Watch.Members[ SteamID ] then return end
	if Watch.EndsAt and SharedTime() > Watch.EndsAt then return end
	local Name = Watch.Members[ SteamID ]
	Watch.Members[ SteamID ] = nil

	local Queue = GetQueuePlugin()
	local Banned = Queue and Queue.AddLeaveBan
		and Queue:AddLeaveBan( SteamID, self.Config.LeaveBanDuration, Name, How ) or false
	self:LogImportant( "early leave %s(%s) how=%s banned=%s duration=%.1f", Name, SteamID, How,
		ToString( Banned ), self.Config.LeaveBanDuration )
	if not Banned then return end

	local Minutes = Ceil( self.Config.LeaveBanDuration / 60 )
	self:Announce( nil, StringFormat( "%s left a ready-checked game early and cannot queue for %d minutes.",
		Name, Minutes ) )
	if How ~= "disconnect" and Client then
		self:Announce( Client, StringFormat(
			"You left a ready-checked game within %d seconds of the start. You cannot queue for %d minutes.",
			Floor( self.Config.LeaveBanWindow ), Minutes ) )
	end
end

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force, ShineForce )
	if OldTeam == NewTeam then return end
	local InCountdown = Gamerules:GetGameState() == kGameState.Countdown

	-- A queued spectator promoted into a freed slot during a ready-checked
	-- countdown joins a team instead of waiting in the Ready Room.
	if InCountdown and self.CountdownPlacementToken and OldTeam == kSpectatorIndex and NewTeam == kTeamReadyRoom then
		local Client = SafeCall( Player, "GetClient", nil )
		if IsHuman( Client ) then
			self:SimpleTimer( 0, function()
				local Rules = GetGamerules()
				if not Shine:IsValidClient( Client ) or not Rules
					or Rules:GetGameState() ~= kGameState.Countdown then return end
				self:PlaceClientOnTeam( Rules, Client, "countdown_promotion" )
			end )
		end
	end

	local Watch = self.LeaveWatch
	if not Watch then return end
	local FromTeam = OldTeam == kTeam1Index or OldTeam == kTeam2Index
	-- Spectator from anywhere (a member may still be in the Ready Room during
	-- the countdown); Ready Room only when coming from a team.
	if NewTeam ~= kSpectatorIndex and not ( NewTeam == kTeamReadyRoom and FromTeam ) then return end

	local Client = SafeCall( Player, "GetClient", nil )
	if not IsHuman( Client ) then return end
	local SteamID = GetSteamID( Client )
	if not Watch.Members[ SteamID ] then return end

	-- Forced moves during the countdown are the system's (VoteRandom shuffle
	-- AFK removal, team balancing), not the player leaving: no ban, and the
	-- player stays where the system put them. Forced moves after the start
	-- (round-start base-AFK mover) still count.
	if InCountdown and ( Force or ShineForce ) then
		Watch.Members[ SteamID ] = nil
		self:LogImportant( "system move during countdown, not a leave: %s(%s) %s -> %s force=%s shineForce=%s",
			GetName( Client ), SteamID, ToString( OldTeam ), ToString( NewTeam ), ToString( Force ),
			ToString( ShineForce ) )
		return
	end

	self:OnWatchedLeave( Client, SteamID, NewTeam == kSpectatorIndex and "spectator" or "ready_room" )

	-- A banned leaver may not keep a player slot in the Ready Room.
	if NewTeam == kTeamReadyRoom then
		self:SimpleTimer( 0, function()
			local CurrentPlayer = Shine:IsValidClient( Client ) and GetPlayer( Client )
			local CurrentRules = GetGamerules()
			if not CurrentPlayer or not CurrentRules or GetTeam( CurrentPlayer ) ~= kTeamReadyRoom then return end
			local Moved = CurrentRules:JoinTeam( CurrentPlayer, kSpectatorIndex, true, true ) == true
			self:LogImportant( "early leaver %s moved from Ready Room to spectator success=%s", SteamID,
				ToString( Moved ) )
		end )
	end
end

--[[ Shine hooks ]]
function Plugin:SetGameState( Gamerules, NewState, OldState )
	if NewState ~= kGameState.Countdown then
		self.CountdownPlacementToken = nil
	end
	if NewState == kGameState.Started then
		self.PendingPlacement = nil
		self:StartLeaveWatchWindow()
		return
	end
	if NewState ~= kGameState.Countdown then
		-- Aborted countdown, round over or reset: never ban for those moves.
		-- Pending release state is kept: StartCountdown's ResetGame passes
		-- NotStarted before Countdown.
		self:StopLeaveWatch( "game_state_"..ToString( NewState ) )
	end
	if NewState == kGameState.Countdown then
		self:ArmLeaveWatch()
		local Placement = self.PendingPlacement
		self.PendingPlacement = nil
		self.CountdownPlacementToken = IsPendingFresh( Placement ) and Placement.Token or nil
		if IsPendingFresh( Placement ) and next( Placement.SteamIDs ) ~= nil then
			-- Next tick: after every SetGameState hook, including the shuffle.
			self:SimpleTimer( 0, function()
				self:PlaceReadyRoomPlayers( Placement )
			end )
		end
	end
	if NewState < kGameState.Countdown then return end
	if self.Check then self:EndCheck( "game_state_"..ToString( NewState ) ) end
	self.PairDecision = nil
	self:ClearReadyFlags( "game_state_"..ToString( NewState ) )
end

function Plugin:MapChange()
	self:StopLeaveWatch( "map_change" )
	self:ClearPendingRelease( "map_change" )
end

function Plugin:ClientDisconnect( Client )
	local SteamID = GetSteamID( Client )
	if IsHuman( Client ) then
		self:OnWatchedLeave( nil, SteamID, "disconnect" )
	end
	self.LastSentState[ SteamID ] = nil
	self.LastReadyRequest[ SteamID ] = nil
	if self.ReadyFlags[ SteamID ] then
		self.ReadyFlags[ SteamID ] = nil
		self:SendNetworkMessage( nil, "ReadyFlag", { SteamID = ToString( SteamID ), Ready = false }, true )
		self:Log( "ready flag dropped on disconnect steamid=%s", SteamID )
	end
	-- Team/eligibility changes are picked up by the next tick.
end

--[[ Commands ]]
-- Accepts an NS2 ID (number) or part of a connected player's name.
local function ResolveSteamID( Text )
	local SteamID = tonumber( Text )
	if SteamID and SteamID > 0 then return Floor( SteamID ) end
	local Target = Shine:GetClient( Text )
	if Target then return GetSteamID( Target ) end
	return nil
end

function Plugin:CreateCommands()
	local ReadyCommand = self:BindCommand( "sh_mngaready", { "ready", "rdy" }, function( Client )
		self:TrySetReady( Client, "command" )
	end, true )
	ReadyCommand:Help( "Ready up during the pregame ready check." )

	local EnabledCommand = self:BindCommand( "sh_readycheck_enabled", nil, function( Client, Enable )
		self.Config.ReadyCheckEnabled = Enable == true
		self.DisabledByErrors = false
		self.HookErrors = 0
		self:SaveConfig( true )
		self:LogImportant( "ReadyCheckEnabled=%s set by %s (saved to config)", ToString( Enable ),
			Client and GetName( Client ) or "console" )
		if not Enable and self.Check then
			self:Announce( nil, "The ready check was turned off by an admin. Starting the game normally." )
			-- Keep the commander pair cached; pregame takes over immediately.
			self:EndCheck( "admin_disabled" )
			self:ClearReadyFlags( "admin_disabled" )
		end
		Shine:AdminPrint( Client, StringFormat( "Ready check system is now %s (saved).", Enable and "ON" or "OFF" ) )
	end )
	EnabledCommand:AddParam{ Type = "boolean" }
	EnabledCommand:Help( "Turns the whole ready check on/off immediately and saves it to the config (emergency switch)." )

	local StartCommand = self:BindCommand( "sh_readycheck_start", nil, function( Client )
		if not self:IsSystemActive() then
			Shine:AdminPrint( Client, "Ready check: the system is turned off (sh_readycheck_enabled true)." )
			return
		end
		local Gamerules = GetGamerules()
		if not Gamerules or Gamerules:GetGameState() > kGameState.PreGame then
			Shine:AdminPrint( Client, "Ready check: the game has already started." )
			return
		end
		if self.Check then
			Shine:AdminPrint( Client, "Ready check: already running." )
			return
		end
		local Com1, Com2 = GetCommanderClients( Gamerules )
		if not Com1 or not Com2 then
			Shine:AdminPrint( Client, "Ready check: both command chairs must be occupied." )
			return
		end
		self:BeginCheck( Gamerules, Com1, Com2, true )
		Shine:AdminPrint( Client, "Ready check: forced start." )
	end )
	StartCommand:Help( "Forces a ready check (both chairs must be occupied), ignoring the player-count threshold." )

	local CancelCommand = self:BindCommand( "sh_readycheck_cancel", nil, function( Client )
		if not self.Check then
			Shine:AdminPrint( Client, "Ready check: none running." )
			return
		end
		self:Announce( nil, "Ready check cancelled by an admin." )
		self:EndCheck( "admin_cancel" )
		self:ClearReadyFlags( "admin_cancel" )
		-- Keep the pair cached so the check does not instantly re-activate.
		Shine:AdminPrint( Client, "Ready check: cancelled. Pregame resumes for this commander pair." )
	end )
	CancelCommand:Help( "Cancels the running ready check and lets pregame continue." )

	local StatusCommand = self:BindCommand( "sh_readycheck_status", nil, function( Client )
		local Check = self.Check
		local Snapshot = self:BuildSnapshot()
		Shine:AdminPrint( Client, StringFormat( "Ready check: enabled=%s disabledByErrors=%s phase=%s token=%s timeLeft=%d held=%d ready=%d unready=%d queued=%d queueReady=%d target=%d leaveWatch=%s",
			ToString( self.Config.ReadyCheckEnabled ), ToString( self.DisabledByErrors ),
			Check and ( PhaseNames[ Check.Phase ] or ToString( Check.Phase ) ) or "idle", ToString( Check and Check.Token ),
			( self:GetTimeLeft( SharedTime() ) ), Check and Floor( SharedTime() - Check.BeganAt ) or 0,
			Snapshot.ReadySlot, Snapshot.UnreadySlot, #Snapshot.Queued,
			Snapshot.QueueReady, self.Config.TargetPlayers, ToString( self.LeaveWatch ~= nil ) ) )
		for i = 1, #Snapshot.Commanders do
			local Entry = Snapshot.Commanders[ i ]
			Shine:AdminPrint( Client, StringFormat( "  comm  team=%d ready=%s human=%s %s", Entry.Team,
				ToString( Entry.Ready ), ToString( Entry.Human ), GetName( Entry.Client ) ) )
		end
		for i = 1, #Snapshot.SlotHolders do
			local Entry = Snapshot.SlotHolders[ i ]
			Shine:AdminPrint( Client, StringFormat( "  slot  team=%d ready=%s %s", Entry.Team, ToString( Entry.Ready ),
				GetName( Entry.Client ) ) )
		end
		for i = 1, #Snapshot.Queued do
			local Entry = Snapshot.Queued[ i ]
			Shine:AdminPrint( Client, StringFormat( "  queue #%d ready=%s %s", Entry.Position, ToString( Entry.Ready ),
				GetName( Entry.Client ) ) )
		end
	end )
	StatusCommand:Help( "Prints the ready check phase, counts and every eligible player." )

	local SetReadyCommand = self:BindCommand( "sh_readycheck_setready", nil, function( Client, Target )
		if not self.Check then
			Shine:AdminPrint( Client, "Ready check: none running." )
			return
		end
		-- Bypass the rate limit for admin testing.
		self.LastReadyRequest[ GetSteamID( Target ) ] = nil
		local Success = self:TrySetReady( Target, "admin" )
		Shine:AdminPrint( Client, StringFormat( "Ready check: %s ready=%s", GetName( Target ), ToString( Success ) ) )
	end )
	SetReadyCommand:AddParam{ Type = "client" }
	SetReadyCommand:Help( "Marks a player ready during the ready check (testing)." )

	local UnbanCommand = self:BindCommand( "sh_readycheck_unban", nil, function( Client, Text )
		local Queue = GetQueuePlugin()
		if not Queue or not Queue.RemoveLeaveBan then
			Shine:AdminPrint( Client, "Ready check: the queue plugin is not loaded." )
			return
		end
		local SteamID = ResolveSteamID( Text )
		if not SteamID then
			Shine:AdminPrint( Client, "Ready check: no player or NS2 ID matches '"..ToString( Text ).."'." )
			return
		end
		local Removed, Name = Queue:RemoveLeaveBan( SteamID )
		self:LogImportant( "unban steamid=%s removed=%s admin=%s", SteamID, ToString( Removed ),
			Client and GetName( Client ) or "console" )
		Shine:AdminPrint( Client, StringFormat( "Ready check: %s %s(%s).",
			Removed and "removed the early-leave ban of" or "no early-leave ban for",
			ToString( Name or "" ), SteamID ) )
	end )
	UnbanCommand:AddParam{ Type = "string", TakeRestOfLine = true, Help = "NS2 ID or player name" }
	UnbanCommand:Help( "Removes a ready-check early-leave queue ban (e.g. the player crashed)." )

	local BansCommand = self:BindCommand( "sh_readycheck_bans", nil, function( Client )
		local Queue = GetQueuePlugin()
		if not Queue or not Queue.GetLeaveBans then
			Shine:AdminPrint( Client, "Ready check: the queue plugin is not loaded." )
			return
		end
		local Bans = Queue:GetLeaveBans()
		Shine:AdminPrint( Client, StringFormat( "Ready check early-leave bans: %d", #Bans ) )
		for i = 1, #Bans do
			local Ban = Bans[ i ]
			Shine:AdminPrint( Client, StringFormat( "  %s %s remaining=%s reason=%s", ToString( Ban.SteamID ),
				ToString( Ban.Name ), FormatDuration( Ban.Remaining ), ToString( Ban.Reason ) ) )
		end
	end )
	BansCommand:Help( "Lists ready-check early-leave queue bans." )
end
