local Plugin = ...
local Shine = Shine
local StringFormat = string.format

local Abs = math.abs
local Clamp = math.Clamp
local Max = math.max
local Remap = math.Remap
local Round = math.Round
local TableCopy = table.Copy
local TableShallowMerge = table.ShallowMerge
local TableSort = table.sort

local ExpectedVoteRandomVersion = "2.12"
local PatchImplementationVersion = "local-nselo2-v8"
local AuditSchemaVersion = 2
local PatchHookName = "MNGAAdministrationVoteRandomEnhancePatch"
local EnemyGroupClientConnectHook = "MNGAAdministrationEnemyGroupClientSync"
local EnemyGroupClientDisconnectHook = "MNGAAdministrationEnemyGroupDisconnectCleanup"
local EnemyGroupMapChangeHook = "MNGAAdministrationEnemyGroupMapChangeSave"
local EnemyGroupRestoreTimerName = "MNGAAdministrationEnemyGroupRestorePrune"
-- Enemy groups follow voterandom friend-group lifetime: in-memory while both
-- players are connected, persisted only across a map change, and dropped if
-- either side has not reconnected by the restore timeout.
local EnemyGroupsPath = "config://shine/temp/mnga_enemy_groups.json"
local EnemyGroupsMaxRestoreAge = 60 * 60
local EnemyGroupsDefaultRestoreTimeout = 300
local StreakHistoryPath = "config://shine/temp/mnga_voterandom_history.json"

Plugin.VoteRandomEnhancePatchHook = PatchHookName

local DefaultConfig = {
	Enabled = true,
	Debug = true,
	Compatibility = {
		ExpectedVoteRandomVersion = ExpectedVoteRandomVersion,
		FallBackToStockOnError = true
	},
	AutoShuffle = {
		MinimumHumansEnabled = true,
		MinimumHumans = 14
	},
	RatingSource = {
		Mode = "PLAYER_SKILL_FIELDS",
		AssumeCurrentValuesDefinitive = true,
		UseTeamSpecificFieldSkill = true,
		UseCommanderSkillInPrediction = true
	},
	Optimiser = {
		Enabled = true,
		Starts = 10,
		MaximumStarts = 50,
		CostSafety = {
			Enabled = true,
			ExponentCap = 600,
			MaximumFiniteCost = 1e300
		}
	},
	RosterValidation = {
		-- Set to zero to retain diagnostics without reassigning a second time.
		MaximumRetries = 1
	},
	AuditLog = {
		-- Use one fresh file per map; no historical log is read back into Lua.
		Enabled = true,
		FilePath = "config://shine/logs/shuffle6",
		FlushEachEvent = true,
		IncludePlayerNames = true,
		ServerID = "mnga-main",
		IncludeTiming = true
	},
	Variety = {
		Diagnostics = true,
		SelectionEnabled = true,
		SimilarityThreshold = 0.70,
		MaxCostDeltaForVariety = 5
	},
	Streaks = {
		Enabled = true,
		-- 2026-10-25: grace 1 / scale 3 (was 2 / 1); see .claude/docs/shuffle_implementation.md §14.
		GraceRounds = 1,
		WeightScale = 3,
		MaxWeight = 300
	},
	XPWeighting = {
		Enabled = false,
		LevelScale = 100,
		MaxPreferenceWeight = 60,
		ApplyToStreaks = false
	},
	OffsetDampening = {
		Enabled = false,
		Factor = 1.0
	},
	EnemyGroups = {
		Enabled = true,
		MaxEnemyGroupSize = 1,
		Weighting = 50
	},
	Supporters = {
		-- Donator shuffle priority; see .claude/docs/shuffle_implementation.md §5.8.
		Enabled = true,
		TierGroups = {
			[ "Server Supporter" ] = 1,
			[ "Server Supporter 2" ] = 2,
			[ "Server Supporter 3" ] = 3
		},
		PreferenceBonus = { 5, 10, 15 },
		EnemyWeighting = { 60, 75, 100 }
	},
	NewPlayers = {
		-- Spreads humans under this rating evenly; see .claude/docs/shuffle_implementation.md §5.9.
		-- Weighting is per player who has to cross, so it must outweigh friend groups (50).
		Enabled = true,
		EloThreshold = 500,
		Weighting = 200
	},
	EloPrediction = {
		-- Must match NSELO2's field_commander_logit_v3 deployment config.
		-- Candidate generation remains the conservative stock optimiser; final
		-- selection uses this model among candidates within the stock-cost cap.
		Enabled = true,
		ModelVersion = "field_commander_logit_v3",
		CutoverDate = "2026-07-14",
		LogitScale = 400,
		MarineWinBiasLogit = 0,
		CommanderPredictionWeight = 0.1,
		MaxStockCostDelta = 5,
		SimilarityTieBreak = true
	}
}

local PatchState = {
	Installed = false,
	AppliedCount = 0,
	LastVersion = nil,
	VersionMatches = nil,
	Patches = {},
	PatchedPlugins = {}
}

-- ApplyPatches is defined before the helper implementation below, so reserve
-- the local binding now and assign it before the plugin is initialised.
local PatchFriendGroupExclusivity

local EnemyGroups = {}
local UnluckyStreaks = {}
local LastCommittedTeams = {}
local StagedShuffle
local StagedAudit
local ActiveAuditRound

local AuditState = {
	Handle = nil,
	Path = nil,
	Sequence = 0,
	ShuffleSequence = 0,
	RoundSequence = 0,
	LastError = nil,
	DroppedEvents = 0,
	RunID = nil,
	WriteSeconds = 0
}

-- Simulation time is constant during a synchronous shuffle, and
-- Shared.GetSystemTime() only has whole-second resolution.
local function WallTime()
	return Shared.GetSystemTimeReal()
end

local function CopyDefaults( Source )
	local Copy = {}
	for Key, Value in pairs( Source ) do
		Copy[ Key ] = type( Value ) == "table" and CopyDefaults( Value ) or Value
	end
	return Copy
end

local function MergeDefaults( Defaults, Target )
	Target = type( Target ) == "table" and Target or {}
	for Key, Value in pairs( Defaults ) do
		if Target[ Key ] == nil then
			Target[ Key ] = type( Value ) == "table" and CopyDefaults( Value ) or Value
		elseif type( Value ) == "table" then
			Target[ Key ] = MergeDefaults( Value, Target[ Key ] )
		end
	end
	return Target
end

local function GetConfig( self )
	local Config = self.Config and self.Config.VoteRandomEnhance
	return MergeDefaults( DefaultConfig, Config )
end

local function IsFiniteNumber( Value )
	return type( Value ) == "number" and Value == Value and Value > -math.huge and Value < math.huge
end

local function NormaliseForJSON( Value, Seen )
	if type( Value ) == "number" then
		return IsFiniteNumber( Value ) and Value or nil
	end
	if type( Value ) ~= "table" then return Value end
	Seen = Seen or {}
	if Seen[ Value ] then return "<cycle>" end
	Seen[ Value ] = true
	local Output = {}
	for Key, Child in pairs( Value ) do
		local Normalised = NormaliseForJSON( Child, Seen )
		if Normalised ~= nil then Output[ Key ] = Normalised end
	end
	Seen[ Value ] = nil
	return Output
end

local function SanitiseFilePart( Value )
	return tostring( Value or "unknown" ):gsub( "[^%w_-]", "_" )
end

local function CloseAuditLog()
	if AuditState.Handle then
		pcall( AuditState.Handle.flush, AuditState.Handle )
		pcall( AuditState.Handle.close, AuditState.Handle )
	end
	AuditState.Handle = nil
end

local function ResetAuditState()
	CloseAuditLog()
	AuditState.Path = nil
	AuditState.Sequence = 0
	AuditState.ShuffleSequence = 0
	AuditState.RoundSequence = 0
	AuditState.LastError = nil
	AuditState.DroppedEvents = 0
	AuditState.Failed = false
	AuditState.RunID = nil
end

local function RecordAuditFailure( Error )
	AuditState.LastError = tostring( Error )
	AuditState.DroppedEvents = AuditState.DroppedEvents + 1
end

local function OpenAuditLog( OwnerPlugin )
	local AuditConfig = GetConfig( OwnerPlugin ).AuditLog or {}
	if not AuditConfig.Enabled then return nil, "disabled" end
	if AuditState.Failed then return nil, AuditState.LastError end

	CloseAuditLog()
	local Directory = AuditConfig.FilePath or "config://shine/logs/shuffle6"
	AuditState.RunID = AuditState.RunID or os.date( "%Y%m%d-%H%M%S" )
	AuditState.Path = StringFormat(
		"%s/%s-%s.txt",
		Directory,
		AuditState.RunID,
		SanitiseFilePart( Shared.GetMapName and Shared.GetMapName() or "unknown" )
	)

	local Handle, Error = io.open( AuditState.Path, "w+" )
	if not Handle then
		RecordAuditFailure( Error or "open_failed" )
		AuditState.Failed = true
		return nil, Error
	end
	AuditState.Handle = Handle
	return Handle
end

local function WriteAuditEvent( OwnerPlugin, VRPlugin, EventName, Payload, ShuffleID )
	local AuditConfig = GetConfig( OwnerPlugin ).AuditLog or {}
	if not AuditConfig.Enabled then return false end
	local WriteStartedAt = WallTime()

	local Handle = AuditState.Handle
	if not Handle then
		local OpenOK, OpenedHandle, OpenError = pcall( OpenAuditLog, OwnerPlugin )
		if not OpenOK or not OpenedHandle then
			if not AuditState.Failed then RecordAuditFailure( OpenError or OpenedHandle or "open_failed" ) end
			AuditState.Failed = true
			CloseAuditLog()
			return false
		end
		Handle = OpenedHandle
	end

	AuditState.Sequence = AuditState.Sequence + 1
	local EffectiveShuffleID
	if ShuffleID ~= false then
		EffectiveShuffleID = ShuffleID or ( VRPlugin and VRPlugin.MNGAAuditShuffleID )
	end
	local Event = {
		schemaVersion = AuditSchemaVersion,
		implementationVersion = PatchImplementationVersion,
		event = EventName,
		sequence = AuditState.Sequence,
		shuffleId = EffectiveShuffleID,
		timestampUnix = os.time(),
		timestampUtc = os.date( "!%Y-%m-%dT%H:%M:%SZ" ),
		serverTime = Shared.GetTime and Shared.GetTime() or 0,
		serverId = tostring( AuditConfig.ServerID or "unknown" ),
		map = Shared.GetMapName and Shared.GetMapName() or "unknown",
		voterandomVersion = VRPlugin and VRPlugin.Version,
		payload = Payload or {}
	}
	local EncodedOK, Encoded = pcall( table.ToJSON, NormaliseForJSON( Event ), { PrettyPrint = false } )
	if not EncodedOK then
		RecordAuditFailure( Encoded )
		return false
	end
	local Line = StringFormat( "[%s][VoteRandomEnhance] %s: %s\n", os.date( "%H:%M:%S" ), EventName, Encoded )
	local WriteOK, WriteResult, Error = pcall( Handle.write, Handle, Line )
	if not WriteOK or not WriteResult then
		RecordAuditFailure( Error or WriteResult or "write_failed" )
		AuditState.Failed = true
		CloseAuditLog()
		return false
	end
	if AuditConfig.FlushEachEvent then
		local FlushOK, FlushResult, FlushError = pcall( Handle.flush, Handle )
		if not FlushOK or not FlushResult then
			RecordAuditFailure( FlushError or FlushResult or "flush_failed" )
			AuditState.Failed = true
			CloseAuditLog()
		end
	end
	AuditState.WriteSeconds = AuditState.WriteSeconds + WallTime() - WriteStartedAt
	return true
end

local function GetSteamID( Player )
	local Client = Player and Player.GetClient and Player:GetClient()
	local SteamID = Client and Client.GetUserId and Client:GetUserId()
	return SteamID, Client
end

local function ReadNumericGetter( Player, GetterName, DefaultValue )
	local Getter = Player and Player[ GetterName ]
	if type( Getter ) ~= "function" then
		return DefaultValue, false
	end
	local OK, Value = pcall( Getter, Player )
	if not OK or not IsFiniteNumber( Value ) then
		return DefaultValue, false
	end
	return Value, true
end

local function GetLocalSkillSnapshot( Player )
	local BaseField, FieldValid = ReadNumericGetter( Player, "GetPlayerSkill", 0 )
	local FieldOffset, FieldOffsetValid = ReadNumericGetter( Player, "GetPlayerSkillOffset", 0 )
	local BaseCommander, CommanderValid = ReadNumericGetter( Player, "GetCommanderSkill", 0 )
	local CommanderOffset, CommanderOffsetValid = ReadNumericGetter( Player, "GetCommanderSkillOffset", 0 )
	return {
		source = "player_skill_fields",
		baseField = BaseField,
		fieldOffset = FieldOffset,
		marineField = BaseField + FieldOffset,
		alienField = BaseField - FieldOffset,
		baseCommander = BaseCommander,
		commanderOffset = CommanderOffset,
		marineCommander = BaseCommander + CommanderOffset,
		alienCommander = BaseCommander - CommanderOffset,
		gettersValid = FieldValid and FieldOffsetValid and CommanderValid and CommanderOffsetValid
	}
end

local function GetLocalSideSkills( Player, TeamNumber )
	local Rating = GetLocalSkillSnapshot( Player )
	if TeamNumber == 1 then return Rating.marineField, Rating.marineCommander, Rating end
	return Rating.alienField, Rating.alienCommander, Rating
end

local function SnapshotPlayer( OwnerPlugin, VRPlugin, Player, CandidateTeam, Preferences, RankFunc )
	local SteamID, Client = GetSteamID( Player )
	local Preference = Preferences and ( Preferences[ Player ] or ( Client and Preferences[ Client ] ) )
	local Snapshot = {
		steamId = SteamID and tostring( SteamID ) or "unknown",
		rosterId = SteamID and SteamID ~= 0 and tostring( SteamID )
			or ( "client:"..tostring( Client and Client.GetId and Client:GetId() or "unknown" ) ),
		currentTeam = Player.GetTeamNumber and Player:GetTeamNumber() or nil,
		candidateTeam = CandidateTeam,
		isCommander = VRPlugin and VRPlugin.IsPlayerCommander and VRPlugin.IsPlayerCommander( Player ) or false,
		preference = Shine.IsType( Preference, "number" ) and Preference or nil,
		lastCommittedTeam = SteamID and LastCommittedTeams[ SteamID ] or nil,
		deniedPreference = SteamID and UnluckyStreaks[ SteamID ] and UnluckyStreaks[ SteamID ].Pref or nil,
		deniedPreferenceStreak = SteamID and UnluckyStreaks[ SteamID ] and UnluckyStreaks[ SteamID ].Streak or nil
	}
	if GetConfig( OwnerPlugin ).AuditLog.IncludePlayerNames and Player.GetName then
		Snapshot.name = Player:GetName()
	end
	if RankFunc and CandidateTeam then
		local OK, Rank = pcall( RankFunc, Player, CandidateTeam )
		if OK then Snapshot.rankUsed = Rank end
	end
	Snapshot.rating = GetLocalSkillSnapshot( Player )
	return Snapshot
end

local function SnapshotTeams( OwnerPlugin, VRPlugin, TeamMembers, RankFunc )
	local Output = { {}, {} }
	local Preferences = TeamMembers and TeamMembers.TeamPreferences or {}
	for TeamNumber = 1, 2 do
		local Team = TeamMembers and TeamMembers[ TeamNumber ] or {}
		for i = 1, #Team do
			Output[ TeamNumber ][ #Output[ TeamNumber ] + 1 ] = SnapshotPlayer(
				OwnerPlugin, VRPlugin, Team[ i ], TeamNumber, Preferences, RankFunc
			)
		end
		TableSort( Output[ TeamNumber ], function( A, B ) return A.steamId < B.steamId end )
	end
	return Output
end

local function SnapshotPlayerGroups( TeamMembers )
	local Output = {}
	for i = 1, #( TeamMembers and TeamMembers.PlayerGroups or {} ) do
		local Group = TeamMembers.PlayerGroups[ i ]
		local SteamIDs = {}
		for j = 1, #( Group.Players or {} ) do
			local SteamID = GetSteamID( Group.Players[ j ] )
			if SteamID then SteamIDs[ #SteamIDs + 1 ] = tostring( SteamID ) end
		end
		TableSort( SteamIDs )
		Output[ #Output + 1 ] = {
			steamIds = SteamIDs,
			type = Group.MNGANewPlayers and "new_player" or Group.MNGAEnemy and "enemy" or "friend",
			ownerSteamId = Group.OwnerID and tostring( Group.OwnerID ) or nil,
			weighting = Group.Weighting,
			baseWeighting = Group.BaseWeighting,
			friendGroupSize = Group.FriendGroupSize
		}
	end
	return Output
end

local function CaptureLiveTeams()
	local Teams = { {}, {} }
	local Clients = Shine.GetAllClients and Shine.GetAllClients() or {}
	for i = 1, #Clients do
		local Player = Clients[ i ].GetControllingPlayer and Clients[ i ]:GetControllingPlayer()
		local TeamNumber = Player and Player.GetTeamNumber and Player:GetTeamNumber()
		if TeamNumber == 1 or TeamNumber == 2 then
			Teams[ TeamNumber ][ #Teams[ TeamNumber ] + 1 ] = Player
		end
	end
	return Teams
end

-- Compare stable client identities, not player entities replaced by JoinTeam.
local function CompareShuffleRosters( Expected, Actual )
	local Before, After = {}, {}
	for Team = 1, 2 do
		for i = 1, #( Expected[ Team ] or {} ) do
			local Player = Expected[ Team ][ i ]
			Before[ Player.rosterId or Player.steamId ] = Team
		end
		for i = 1, #( Actual[ Team ] or {} ) do
			local Player = Actual[ Team ][ i ]
			After[ Player.rosterId or Player.steamId ] = Team
		end
	end
	local Added, Removed, Changed = {}, {}, {}
	for ID, Team in pairs( After ) do
		if not Before[ ID ] then Added[ #Added + 1 ] = { rosterId = ID, team = Team }
		elseif Before[ ID ] ~= Team then
			Changed[ #Changed + 1 ] = { rosterId = ID, beforeTeam = Before[ ID ], afterTeam = Team }
		end
	end
	for ID, Team in pairs( Before ) do
		if not After[ ID ] then Removed[ #Removed + 1 ] = { rosterId = ID, team = Team } end
	end
	return { added = Added, removed = Removed, changed = Changed,
		matches = #Added == 0 and #Removed == 0 and #Changed == 0 }
end

local function SnapshotScalarFields( Source )
	local Output = {}
	for Key, Value in pairs( Source or {} ) do
		local ValueType = type( Value )
		if type( Key ) == "string" and ( ValueType == "string" or ValueType == "number" or ValueType == "boolean" ) then
			Output[ Key ] = Value
		end
	end
	return Output
end

local function Logistic( Value )
	if Value >= 0 then
		local Z = math.exp( -Value )
		return 1 / ( 1 + Z )
	end
	local Z = math.exp( Value )
	return Z / ( 1 + Z )
end

local function GetPredictionParameters( OwnerPlugin, Model )
	local Parameters = {
		Version = tostring( Model.ModelVersion or "" ),
		Beta = tonumber( Model.CommanderPredictionWeight ),
		Scale = tonumber( Model.LogitScale ),
		Bias = tonumber( Model.MarineWinBiasLogit )
	}
	if Parameters.Version == "" or Parameters.Beta == nil or Parameters.Scale == nil or Parameters.Bias == nil then
		return nil, "invalid_local_prediction_parameters"
	end
	if Parameters.Scale <= 0 then return nil, "invalid_logit_scale" end
	return Parameters
end

local function GetPredictionReadiness( OwnerPlugin, VRPlugin, Targets, TeamMembers, Config )
	local Model = Config.EloPrediction or {}
	if not Model.Enabled then return false, "disabled" end
	if not VRPlugin.MNGAVoteRandomEnhanceOptimiseTeamsPatched then
		return false, "optimiser_patch_unavailable"
	end
	local Parameters, ParameterReason = GetPredictionParameters( OwnerPlugin, Model )
	if not Parameters or Parameters.Beta == nil or Parameters.Scale == nil or Parameters.Bias == nil then
		return false, ParameterReason or "invalid_prediction_parameters"
	end
	if Parameters.Scale <= 0 then return false, "invalid_logit_scale" end

	return true, "local_player_fields_definitive"
end

-- Evaluate a shuffle candidate with the same field + beta_commander logit as
-- NSELO2. Shuffle does not know future chair time, so a presently seated
-- commander is the sole primary commander for that side and every player has
-- equal pre-round participation weight. If no custom skill is cached, return
-- nil and leave the candidate on the stock safety path.
local function ComputeEloPrediction( OwnerPlugin, VRPlugin, TeamMembers, Config, IgnorePreflight )
	local Model = Config.EloPrediction or {}
	if not Model.Enabled then return nil, "disabled" end
	local Parameters, ParameterReason = GetPredictionParameters( OwnerPlugin, Model )
	if not Parameters then
		return nil, ParameterReason or "invalid_prediction_parameters"
	end

	local FieldSums = { 0, 0 }
	local FieldWeights = { 0, 0 }
	local CommanderSums = { 0, 0 }
	local CommanderWeights = { 0, 0 }
	local Commanders = {}

	for TeamNumber = 1, 2 do
		local Team = TeamMembers[ TeamNumber ]
		for i = 1, #Team do
			if VRPlugin.IsPlayerCommander( Team[ i ] ) then
				Commanders[ TeamNumber ] = Commanders[ TeamNumber ] or Team[ i ]
				CommanderWeights[ TeamNumber ] = CommanderWeights[ TeamNumber ] + 1
			end
		end
	end

	-- The commander model requires a seated pair. With no commanders the
	-- field-only model is valid; a partial pair must not use field substitutes.
	local UseCommanderPair = CommanderWeights[ 1 ] == 1 and CommanderWeights[ 2 ] == 1
	-- Never substitute a seated commander's field Elo. The service model has
	-- no defined one-sided commander term; retain stock-cost selection there.
	if not UseCommanderPair and CommanderWeights[ 1 ] + CommanderWeights[ 2 ] > 0 then
		return nil, "incomplete_commander_pair"
	end
	local ObservedCommanderCounts = { CommanderWeights[ 1 ], CommanderWeights[ 2 ] }
	CommanderWeights[ 1 ] = 0
	CommanderWeights[ 2 ] = 0

	for TeamNumber = 1, 2 do
		local Team = TeamMembers[ TeamNumber ]
		for i = 1, #Team do
			local Player = Team[ i ]
			local FieldSkill, CommanderSkill = GetLocalSideSkills( Player, TeamNumber )

			if not UseCommanderPair or Player ~= Commanders[ TeamNumber ] then
				FieldWeights[ TeamNumber ] = FieldWeights[ TeamNumber ] + 1
				FieldSums[ TeamNumber ] = FieldSums[ TeamNumber ] + FieldSkill
			end
			if UseCommanderPair and Player == Commanders[ TeamNumber ] then
				CommanderWeights[ TeamNumber ] = CommanderWeights[ TeamNumber ] + 1
				CommanderSums[ TeamNumber ] = CommanderSums[ TeamNumber ] + CommanderSkill
			end
		end
	end

	if FieldWeights[ 1 ] <= 0 or FieldWeights[ 2 ] <= 0 then return nil, "no_field_players" end
	local FieldTerm = 0.5 * (
		FieldSums[ 1 ] / FieldWeights[ 1 ] - FieldSums[ 2 ] / FieldWeights[ 2 ]
	)
	local CommanderTerm = 0
	if UseCommanderPair then
		CommanderTerm = 0.5 * (
			CommanderSums[ 1 ] / CommanderWeights[ 1 ] - CommanderSums[ 2 ] / CommanderWeights[ 2 ]
		)
	end
	if Parameters.Scale <= 0 then return nil, "invalid_logit_scale" end
	local Logit = ( FieldTerm + Parameters.Beta * CommanderTerm ) / Parameters.Scale + Parameters.Bias
	local MarineProbability = Logistic( Logit )
	local FieldAverages = {
		FieldSums[ 1 ] / FieldWeights[ 1 ],
		FieldSums[ 2 ] / FieldWeights[ 2 ]
	}
	local CommanderAverages = UseCommanderPair and {
		CommanderSums[ 1 ] / CommanderWeights[ 1 ],
		CommanderSums[ 2 ] / CommanderWeights[ 2 ]
	} or nil

	return {
		FieldSums = FieldSums,
		FieldWeights = FieldWeights,
		FieldAverages = FieldAverages,
		FieldDifference = FieldAverages[ 1 ] - FieldAverages[ 2 ],
		CommanderSums = CommanderSums,
		CommanderWeights = CommanderWeights,
		CommanderAverages = CommanderAverages,
		CommanderDifference = UseCommanderPair and CommanderAverages[ 1 ] - CommanderAverages[ 2 ] or 0,
		FieldTerm = FieldTerm,
		CommanderTerm = CommanderTerm,
		WeightedCommanderTerm = Parameters.Beta * CommanderTerm,
		Numerator = FieldTerm + Parameters.Beta * CommanderTerm,
		MarineProbability = MarineProbability,
		ProbabilityDistance = Abs( MarineProbability - 0.5 ),
		Logit = Logit,
		Beta = Parameters.Beta,
		Scale = Parameters.Scale,
		Bias = Parameters.Bias,
		PredictionBasis = UseCommanderPair
			and "field_commander_logit_v3_equal_player_weight_seated_commander_pair"
			or "field_commander_logit_v3_equal_player_weight_no_commanders",
		CommanderPair = UseCommanderPair,
		ObservedCommanderCounts = ObservedCommanderCounts,
		CommanderCount = UseCommanderPair and 2 or 0,
		CommanderSteamIds = UseCommanderPair and {
			tostring( GetSteamID( Commanders[ 1 ] ) ),
			tostring( GetSteamID( Commanders[ 2 ] ) )
		} or nil,
		ModelVersion = Parameters.Version
	}
end

local function SaveEnemyGroups()
	Shine.SaveJSONFile( {
		Groups = EnemyGroups,
		Time = os.time()
	}, EnemyGroupsPath )
end

local function SendEnemyGroupState( Plugin, Client, TargetSteamID, IsEnemy )
	if not Client or not TargetSteamID then return end
	Plugin:SendNetworkMessage( Client, "EnemyGroupState", {
		TargetSteamID = TargetSteamID,
		IsEnemy = IsEnemy == true
	}, true )
end

local function SyncEnemyGroupState( Plugin, Client )
	if not Client or not Client.GetUserId then return end
	local OwnerID = Client:GetUserId()
	if not OwnerID then return end

	-- Target 0 is a protocol-only clear marker; it is never a valid Steam ID.
	SendEnemyGroupState( Plugin, Client, 0, false )
	local List = EnemyGroups[ tostring( OwnerID ) ] or {}
	for i = 1, #List do
		local TargetID = tonumber( List[ i ] )
		if TargetID then
			SendEnemyGroupState( Plugin, Client, TargetID, true )
		end
	end
end

local function IsEnemyGroupClientConnected( SteamID )
	local Client = SteamID and Shine.GetClientByNS2ID and Shine.GetClientByNS2ID( SteamID )
	return Client ~= nil and not ( Client.GetIsVirtual and Client:GetIsVirtual() )
end

local function NotifyEnemyTargetRemoved( Plugin, OwnerID, TargetID )
	local OwnerClient = Shine.GetClientByNS2ID and Shine.GetClientByNS2ID( OwnerID )
	if OwnerClient then
		SendEnemyGroupState( Plugin, OwnerClient, TargetID, false )
	end
end

-- Mirrors voterandom's HandleFriendGroupClientDisconnect: a leaving player
-- frees every slot they occupy, both their own list and other owners' lists.
local function RemoveDisconnectedEnemyPlayer( Plugin, SteamID )
	if not SteamID then return end
	local OwnedCount = EnemyGroups[ tostring( SteamID ) ] and #EnemyGroups[ tostring( SteamID ) ] or 0
	EnemyGroups[ tostring( SteamID ) ] = nil

	local Removed = 0
	for OwnerKey, List in pairs( EnemyGroups ) do
		for i = #List, 1, -1 do
			if tonumber( List[ i ] ) == SteamID then
				table.remove( List, i )
				Removed = Removed + 1
				NotifyEnemyTargetRemoved( Plugin, tonumber( OwnerKey ), SteamID )
			end
		end
		if #List == 0 then EnemyGroups[ OwnerKey ] = nil end
	end

	if OwnedCount > 0 or Removed > 0 then
		Print( "[enemygroup] %s disconnected: dropped own list (%d) and %d slot(s) in other lists.",
			tostring( SteamID ), OwnedCount, Removed )
	end
end

-- Drops relations whose owner or target is not connected. OwnerFilter limits
-- the prune to one owner's list (used before checking the slot cap).
local function PruneDisconnectedEnemyGroups( Plugin, OwnerFilter, Reason )
	local Removed = 0
	for OwnerKey, List in pairs( EnemyGroups ) do
		local OwnerID = tonumber( OwnerKey )
		if not OwnerFilter or OwnerID == OwnerFilter then
			local OwnerConnected = IsEnemyGroupClientConnected( OwnerID )
			for i = #List, 1, -1 do
				local TargetID = tonumber( List[ i ] )
				if not OwnerConnected or not IsEnemyGroupClientConnected( TargetID ) then
					table.remove( List, i )
					Removed = Removed + 1
					if OwnerConnected then
						NotifyEnemyTargetRemoved( Plugin, OwnerID, TargetID )
					end
				end
			end
			if #List == 0 then EnemyGroups[ OwnerKey ] = nil end
		end
	end

	if Removed > 0 then
		Print( "[enemygroup] Pruned %d disconnected relation(s) (%s).", Removed, tostring( Reason ) )
	end
	return Removed
end

local function WriteEnemyGroupAudit( Plugin, EventName, OwnerID, TargetID, Source )
	WriteAuditEvent( Plugin, Shine.Plugins and Shine.Plugins[ "voterandom" ], EventName, {
		ownerSteamId = tostring( OwnerID ),
		targetSteamId = TargetID and tostring( TargetID ) or nil,
		source = Source or "command",
		maxEnemyGroupSize = ( GetConfig( Plugin ).EnemyGroups or {} ).MaxEnemyGroupSize,
		weighting = ( GetConfig( Plugin ).EnemyGroups or {} ).Weighting
	}, false )
end

local function LoadEnemyGroups( Plugin )
	EnemyGroups = {}
	local Loaded = Shine.LoadJSONFile( EnemyGroupsPath )
	if type( Loaded ) ~= "table" then return end
	-- Consume the snapshot so a later crash/restart cannot resurrect it.
	Shine.SaveJSONFile( {}, EnemyGroupsPath )

	if type( Loaded.Time ) ~= "number" or os.time() - Loaded.Time > EnemyGroupsMaxRestoreAge
		or type( Loaded.Groups ) ~= "table" then
		Print( "[enemygroup] Skipping enemy-group restore (missing or stale snapshot)." )
		return
	end

	local MaxGroupSize = Max( 1, tonumber( ( GetConfig( Plugin ).EnemyGroups or {} ).MaxEnemyGroupSize ) or 1 )
	local Restored = 0
	for Owner, List in pairs( Loaded.Groups ) do
		local OwnerID = tonumber( Owner )
		if OwnerID and type( List ) == "table" then
			local Clean = {}
			local Seen = {}
			for i = 1, #List do
				if #Clean >= MaxGroupSize then break end
				local SteamID = tonumber( List[ i ] )
				if SteamID and SteamID ~= OwnerID and not Seen[ SteamID ] then
					Clean[ #Clean + 1 ] = SteamID
					Seen[ SteamID ] = true
				end
			end
			if #Clean > 0 then
				EnemyGroups[ tostring( OwnerID ) ] = Clean
				Restored = Restored + #Clean
			end
		end
	end
	Print( "[enemygroup] Restored %d relation(s) from the previous map.", Restored )
end

local function ScheduleEnemyGroupRestorePrune( Plugin )
	local VoteRandom = Shine.Plugins and Shine.Plugins[ "voterandom" ]
	local VRConfig = VoteRandom and VoteRandom.Config and VoteRandom.Config.TeamPreferences
	local Timeout = tonumber( VRConfig and VRConfig.FriendGroupRestoreTimeoutSeconds ) or EnemyGroupsDefaultRestoreTimeout
	local Delay = Max( 1, Timeout - Shared.GetTime() )
	Shine.Timer.Create( EnemyGroupRestoreTimerName, Delay, 1, function()
		PruneDisconnectedEnemyGroups( Plugin, nil, "restore timeout" )
	end )
end

local function SaveStreakHistory()
	Shine.SaveJSONFile( {
		LastTeams = LastCommittedTeams,
		Unlucky = UnluckyStreaks
	}, StreakHistoryPath )
end

local function LoadStreakHistory()
	UnluckyStreaks = {}
	LastCommittedTeams = {}

	local Loaded = Shine.LoadJSONFile( StreakHistoryPath )
	if type( Loaded ) ~= "table" then return end

	if type( Loaded.LastTeams ) == "table" then
		for Key, Value in pairs( Loaded.LastTeams ) do
			local SteamID = tonumber( Key )
			if SteamID and ( Value == 1 or Value == 2 ) then
				LastCommittedTeams[ SteamID ] = Value
			end
		end
	end

	if type( Loaded.Unlucky ) == "table" then
		for Key, Entry in pairs( Loaded.Unlucky ) do
			local SteamID = tonumber( Key )
			if SteamID and type( Entry ) == "table" and ( Entry.Pref == 1 or Entry.Pref == 2 ) then
				UnluckyStreaks[ SteamID ] = {
					Pref = Entry.Pref,
					Streak = tonumber( Entry.Streak ) or 1
				}
			end
		end
	end
end

local function GetUnluckyStreak( SteamID )
	local Entry = UnluckyStreaks[ SteamID ]
	if not Entry then return nil, 0 end
	return Entry.Pref, Entry.Streak or 0
end

local function GetXPFactor( self, SteamID )
	local Config = GetConfig( self )
	local XPCfg = Config.XPWeighting
	if not ( XPCfg and XPCfg.Enabled ) then return 1 end
	if not ( self.Config and self.Config.xpsystem ) then return 1 end
	if not self.GetXPLevel then return 1 end

	local Scale = tonumber( XPCfg.LevelScale ) or 100
	if Scale <= 0 then return 1 end

	return 1 + ( self:GetXPLevel( SteamID ) or 0 ) / Scale
end

-- Walks the user's Shine group and its InheritsFrom chain instead of using
-- HasAccess: SuperAdmin is a blacklist group and would pass any permission.
local function FindSupporterTier( TierGroups, Client )
	local User = Shine:GetUserData( Client )
	local Pending = { User and User.Group }
	local Visited = {}
	local Tier = 0
	local i = 1
	while Pending[ i ] do
		local GroupName = Pending[ i ]
		i = i + 1
		if not Visited[ GroupName ] then
			Visited[ GroupName ] = true
			local GroupTier = tonumber( TierGroups[ GroupName ] ) or 0
			if GroupTier > Tier then Tier = GroupTier end

			local GroupData = Shine:GetGroupData( GroupName )
			local Inherits = GroupData and GroupData.InheritsFrom
			if type( Inherits ) == "table" then
				for j = 1, #Inherits do
					Pending[ #Pending + 1 ] = Inherits[ j ]
				end
			end
		end
	end
	return Tier
end

-- Returns tier (0 = none) and, if the lookup threw, the error string for the audit log.
local function GetSupporterTier( SupporterCfg, Client )
	if not ( SupporterCfg and SupporterCfg.Enabled and Client ) then return 0 end
	if type( SupporterCfg.TierGroups ) ~= "table" then return 0 end

	local Success, Tier = pcall( FindSupporterTier, SupporterCfg.TierGroups, Client )
	if not Success then return 0, tostring( Tier ) end
	return Tier
end

local function GetSupporterValue( SupporterCfg, Key, Tier )
	if Tier <= 0 then return 0 end
	local Values = SupporterCfg and SupporterCfg[ Key ]
	return type( Values ) == "table" and tonumber( Values[ Tier ] ) or 0
end

local function CountPreferencesSatisfied( TeamMembers )
	local Held, Total = 0, 0
	local Preferences = TeamMembers.TeamPreferences or {}

	for TeamNumber = 1, 2 do
		local Team = TeamMembers[ TeamNumber ]
		for i = 1, #Team do
			local Player = Team[ i ]
			local Preference = Preferences[ Player ]
			if not Shine.IsType( Preference, "number" ) and Player.GetClient then
				Preference = Preferences[ Player:GetClient() ]
			end
			if Shine.IsType( Preference, "number" ) then
				Total = Total + 1
				if Preference == TeamNumber then
					Held = Held + 1
				end
			end
		end
	end

	return Held, Total
end

local function ComputeSimilarity( TeamMembers )
	if not next( LastCommittedTeams ) then return 0, 0, 0 end

	local Same, Total = 0, 0
	for TeamNumber = 1, 2 do
		local Team = TeamMembers[ TeamNumber ]
		for i = 1, #Team do
			local Player = Team[ i ]
			local Client = Player.GetClient and Player:GetClient()
			local SteamID = Client and Client.GetUserId and Client:GetUserId()
			local Previous = SteamID and LastCommittedTeams[ SteamID ]
			if Previous then
				Total = Total + 1
				if Previous == TeamNumber then Same = Same + 1 end
			end
		end
	end

	if Total == 0 then return 0, Same, Total end
	return Same / Total, Same, Total
end

local function CapturePreferencesFromTeamMembers( VRPlugin, TeamMembers )
	if not TeamMembers or not TeamMembers.TeamPreferences then return end

	local Preferences = TeamMembers.TeamPreferences
	local Lookup = {}

	for TeamNumber = 1, 2 do
		local Team = TeamMembers[ TeamNumber ]
		for i = 1, #Team do
			local Player = Team[ i ]
			local Client = Player.GetClient and Player:GetClient()
			if Client then
				local Preference = Preferences[ Player ] or Preferences[ Client ]
				if Preference == 1 or Preference == 2 then
					Lookup[ Client:GetUserId() ] = Preference
				end
			end
		end
	end

	VRPlugin.MNGALastShufflePreferences = Lookup
	VRPlugin.LastShufflePreferences = Lookup
end

local function CaptureOffsetDiagnostics( VRPlugin, Staged )
	local GetHiveSkill = VRPlugin.SkillGetters and VRPlugin.SkillGetters.GetHiveSkill
	local TeamSkillEnabled = VRPlugin.IsPerTeamSkillEnabled and VRPlugin:IsPerTeamSkillEnabled()
	local CommanderSkillEnabled = VRPlugin.IsCommanderSkillEnabled and VRPlugin:IsCommanderSkillEnabled()

	local OffsetSum = { 0, 0 }
	local Counts = { 0, 0 }

	if not GetHiveSkill then
		return OffsetSum, Counts
	end

	for SteamID, Info in pairs( Staged ) do
		local Client = Shine.GetClientByNS2ID and Shine.GetClientByNS2ID( SteamID )
		local Player = Client and Client.GetControllingPlayer and Client:GetControllingPlayer()
		if Player then
			local MarineSkill = GetHiveSkill( Player, 1, TeamSkillEnabled, CommanderSkillEnabled ) or 0
			local AlienSkill = GetHiveSkill( Player, 2, TeamSkillEnabled, CommanderSkillEnabled ) or 0
			local Offset = ( MarineSkill - AlienSkill ) * 0.5
			OffsetSum[ Info.Team ] = OffsetSum[ Info.Team ] + Offset
			Counts[ Info.Team ] = Counts[ Info.Team ] + 1
		end
	end

	return OffsetSum, Counts
end

local function StageShuffleFromLookup( OwnerPlugin, VRPlugin )
	local Lookup = VRPlugin.LastShuffleTeamLookup
	if not Lookup then return end

	local Preferences = VRPlugin.LastShufflePreferences or VRPlugin.MNGALastShufflePreferences or {}
	local FinalTeams = CaptureLiveTeams()
	local ActualByID = {}
	for Team = 1, 2 do
		for i = 1, #FinalTeams[ Team ] do
			local ID = GetSteamID( FinalTeams[ Team ][ i ] )
			if ID then ActualByID[ ID ] = Team end
		end
	end
	local Staged = {}
	local Count = 0
	local Same = 0
	local Total = 0
	local PreferencesHeld, PreferencesTotal = 0, 0
	local ReconciledLookup = TableCopy( Lookup )

	for SteamID, Team in pairs( Lookup ) do
		if type( SteamID ) == "number" and ( Team == 1 or Team == 2 ) and ActualByID[ SteamID ] then
			-- Even after a retry limit, never record an assignment that failed.
			Team = ActualByID[ SteamID ]
			ReconciledLookup[ SteamID ] = Team
			local Preference = Preferences[ SteamID ]
			if Preference == 1 or Preference == 2 then
				PreferencesTotal = PreferencesTotal + 1
				if Preference == Team then PreferencesHeld = PreferencesHeld + 1 end
			end
			Staged[ SteamID ] = {
				Team = Team,
				Pref = ( Preference == 1 or Preference == 2 ) and Preference or nil
			}
			Count = Count + 1

			local Previous = LastCommittedTeams[ SteamID ]
			if Previous then
				Total = Total + 1
				if Previous == Team then Same = Same + 1 end
			end
		elseif type( SteamID ) == "number" then
			ReconciledLookup[ SteamID ] = nil
		end
	end
	ReconciledLookup.NumPreferencesHeld = PreferencesHeld
	ReconciledLookup.NumPreferencesTotal = PreferencesTotal
	VRPlugin.LastShuffleTeamLookup = ReconciledLookup

	if StagedAudit then
		WriteAuditEvent( OwnerPlugin, VRPlugin, "shuffle_superseded", {
			supersededShuffleId = StagedAudit.ShuffleID
		}, StagedAudit.ShuffleID )
	end
	StagedShuffle = Staged
	StagedAudit = {
		ShuffleID = VRPlugin.MNGAAuditShuffleID,
		StagedAt = Shared.GetTime and Shared.GetTime() or 0
	}

	local Similarity = Total > 0 and Same / Total or 0
	local OffsetSum, OffsetCounts = CaptureOffsetDiagnostics( VRPlugin, Staged )
	StagedAudit.Teams = SnapshotTeams( OwnerPlugin, VRPlugin, FinalTeams )
	StagedAudit.SelectedRosterValid = VRPlugin.MNGASelectedRosterValid
	local FinalPrediction, FinalPredictionReason = ComputeEloPrediction(
		OwnerPlugin, VRPlugin, FinalTeams, GetConfig( OwnerPlugin ), true
	)
	local Assignments = {}
	for SteamID, Info in pairs( Staged ) do
		Assignments[ #Assignments + 1 ] = {
			steamId = tostring( SteamID ),
			team = Info.Team,
			preference = Info.Pref
		}
	end
	TableSort( Assignments, function( A, B ) return A.steamId < B.steamId end )
	WriteAuditEvent( OwnerPlugin, VRPlugin, "shuffle_staged", {
		selectedRosterValid = VRPlugin.MNGASelectedRosterValid,
		assignments = Assignments,
		playerCount = Count,
		similarity = Similarity,
		sameTeamCount = Same,
		comparisonCount = Total,
		preferencesHeld = PreferencesHeld,
		preferencesTotal = PreferencesTotal,
		diagnosticRankSource = "player_skill_fields",
		offsetSums = OffsetSum,
		offsetCounts = OffsetCounts,
		actualTeams = StagedAudit.Teams,
		actualPrediction = FinalPrediction,
		actualPredictionReason = FinalPredictionReason
	} )
end

local function CommitStagedShuffle( OwnerPlugin, VRPlugin )
	if not StagedShuffle then return end

	local Unlucky, Lucky, NoPref = 0, 0, 0
	for SteamID, Info in pairs( StagedShuffle ) do
		local Team = Info.Team
		local Preference = Info.Pref
		LastCommittedTeams[ SteamID ] = Team

		if not Preference then
			UnluckyStreaks[ SteamID ] = nil
			NoPref = NoPref + 1
		elseif Team == Preference then
			UnluckyStreaks[ SteamID ] = nil
			Lucky = Lucky + 1
		else
			local Entry = UnluckyStreaks[ SteamID ]
			if Entry and Entry.Pref == Preference then
				Entry.Streak = ( Entry.Streak or 0 ) + 1
			else
				UnluckyStreaks[ SteamID ] = {
					Pref = Preference,
					Streak = 1
				}
			end
			Unlucky = Unlucky + 1
		end
	end

	SaveStreakHistory()
	WriteAuditEvent( OwnerPlugin, VRPlugin, "streak_history_committed", {
		unlucky = Unlucky,
		lucky = Lucky,
		noPreference = NoPref
	}, StagedAudit and StagedAudit.ShuffleID )
	StagedShuffle = nil
end

function Plugin:VoteRandomEnhanceSetGameState( Gamerules, State, OldState )
	if State == kGameState.Started then
		local VoteRandom = Shine.Plugins and Shine.Plugins[ "voterandom" ]
		AuditState.RoundSequence = AuditState.RoundSequence + 1
		local RoundAuditID = StringFormat( "%s-%d-round-%d",
			SanitiseFilePart( ( GetConfig( self ).AuditLog or {} ).ServerID or "unknown" ),
			os.time(), math.floor( ( Shared.GetTime and Shared.GetTime() or 0 ) * 1000 ) + AuditState.RoundSequence )
		local LiveTeams = CaptureLiveTeams()
		local Prediction, Reason
		if VoteRandom then
			Prediction, Reason = ComputeEloPrediction( self, VoteRandom, LiveTeams, GetConfig( self ), true )
		end
		local ShuffleID = StagedAudit and StagedAudit.ShuffleID
		local LiveSnapshot = SnapshotTeams( self, VoteRandom, LiveTeams )
		local Drift = StagedAudit and StagedAudit.Teams
			and CompareShuffleRosters( StagedAudit.Teams, LiveSnapshot )
		local SelectedRosterValid = StagedAudit and StagedAudit.SelectedRosterValid
		if Drift and not Drift.matches then
			SelectedRosterValid = false
			Drift.phase = "round_started"
			Drift.retryScheduled = false
			WriteAuditEvent( self, VoteRandom, "shuffle_roster_drift", Drift, ShuffleID )
			Print( "[ShuffleRoster] Roster changed between staging and round start; using fresh start prediction." )
		end
		WriteAuditEvent( self, VoteRandom, "round_started", {
			roundAuditId = RoundAuditID,
			oldState = OldState,
			teams = LiveSnapshot,
			stagedRosterMatches = Drift and Drift.matches,
			selectedRosterValid = SelectedRosterValid,
			prediction = Prediction,
			predictionReason = Reason
		}, ShuffleID or false )
		ActiveAuditRound = {
			RoundAuditID = RoundAuditID,
			ShuffleID = ShuffleID,
			StartedAt = Gamerules and Gamerules.gameStartTime or ( Shared.GetTime and Shared.GetTime() or 0 ),
			Prediction = Prediction
		}
		CommitStagedShuffle( self, VoteRandom )
		StagedAudit = nil
	elseif State == kGameState.NotStarted and StagedShuffle then
		local VoteRandom = Shine.Plugins and Shine.Plugins[ "voterandom" ]
		WriteAuditEvent( self, VoteRandom, "shuffle_discarded", {
			oldState = OldState,
			newState = State,
			reason = "returned_to_not_started"
		}, StagedAudit and StagedAudit.ShuffleID )
		StagedShuffle = nil
		StagedAudit = nil
	end
end

function Plugin:VoteRandomEnhanceEndGame( Gamerules, WinningTeam )
	local VoteRandom = Shine.Plugins and Shine.Plugins[ "voterandom" ]
	local Winner = Shine.IsType( WinningTeam, "number" ) and WinningTeam
		or ( WinningTeam and WinningTeam.GetTeamType and WinningTeam:GetTeamType() )
	local LiveTeams = CaptureLiveTeams()
	WriteAuditEvent( self, VoteRandom, "round_outcome", {
		roundAuditId = ActiveAuditRound and ActiveAuditRound.RoundAuditID,
		winner = Winner,
		duration = Gamerules and Gamerules.gameStartTime
			and Shared.GetTime() - Gamerules.gameStartTime or nil,
		startPrediction = ActiveAuditRound and ActiveAuditRound.Prediction,
		finalTeams = SnapshotTeams( self, VoteRandom, LiveTeams )
	}, ActiveAuditRound and ActiveAuditRound.ShuffleID or false )
	ActiveAuditRound = nil
end

local function MakeCombinedWeighting( OwnerPlugin, VRPlugin, TeamMembers, TeamPreferenceWeighting )
	local TeamPreferences = TeamMembers.TeamPreferences or {}
	local Config = GetConfig( OwnerPlugin )
	local Streaks = Config.Streaks or {}
	local XPCfg = Config.XPWeighting or {}
	local Grace = tonumber( Streaks.GraceRounds ) or 1
	local StreakScale = Streaks.Enabled and ( tonumber( Streaks.WeightScale ) or 0 ) or 0
	local MaxStreak = tonumber( Streaks.MaxWeight ) or 0
	local MaxPref = tonumber( XPCfg.MaxPreferenceWeight ) or math.huge
	local ApplyXPToStreaks = XPCfg.ApplyToStreaks
	local SupporterCfg = Config.Supporters
	local Cache = {}

	local function Compute( Player )
		local Client = Player.GetClient and Player:GetClient()
		local SteamID = Client and Client.GetUserId and Client:GetUserId()
		local XPFactor = SteamID and GetXPFactor( OwnerPlugin, SteamID ) or 1
		local Preference = TeamPreferences[ Player ] or ( Client and TeamPreferences[ Client ] )
		local HasPreference = Shine.IsType( Preference, "number" )

		local ExplicitMag = 0
		if HasPreference and TeamPreferenceWeighting > 0 then
			ExplicitMag = VRPlugin:GetHistoricHappinessWeight( Player ) * TeamPreferenceWeighting * XPFactor
			if ExplicitMag > MaxPref then ExplicitMag = MaxPref end
		end

		-- Added after the cap so MaxPreferenceWeight never swallows it.
		local SupporterTier = 0
		local SupporterBonus = 0
		local SupporterTierError
		if HasPreference and TeamPreferenceWeighting > 0 then
			SupporterTier, SupporterTierError = GetSupporterTier( SupporterCfg, Client )
			SupporterBonus = GetSupporterValue( SupporterCfg, "PreferenceBonus", SupporterTier )
			ExplicitMag = ExplicitMag + SupporterBonus
		end

		local StreakMag = 0
		local StreakTeam
		local StreakLength = 0
		if SteamID and StreakScale > 0 and MaxStreak > 0 then
			local DeniedTeam
			DeniedTeam, StreakLength = GetUnluckyStreak( SteamID )
			if DeniedTeam and StreakLength >= Grace and not ( HasPreference and Preference ~= DeniedTeam ) then
				local K = StreakLength - Grace + 1
				StreakMag = StreakScale * ( K * K + K + 1 )
				if ApplyXPToStreaks then StreakMag = StreakMag * XPFactor end
				if StreakMag > MaxStreak then StreakMag = MaxStreak end
				StreakTeam = DeniedTeam
			end
		end

		local Weights = { 0, 0 }
		for TeamNumber = 1, 2 do
			local Weight = 0
			if ExplicitMag > 0 then
				Weight = Weight + ( Preference == TeamNumber and -ExplicitMag or ExplicitMag )
			end
			if StreakMag > 0 then
				Weight = Weight + ( StreakTeam == TeamNumber and -StreakMag or StreakMag )
			end
			Weights[ TeamNumber ] = Weight
		end

		if SteamID and ( ExplicitMag > 0 or StreakMag > 0 ) then
			WriteAuditEvent( OwnerPlugin, VRPlugin, "player_preference_weight", {
				steamId = tostring( SteamID ), preference = HasPreference and Preference or nil,
				explicitMagnitude = ExplicitMag, streakMagnitude = StreakMag,
				streakTeam = StreakTeam, streakLength = StreakLength,
				supporterTier = SupporterTier, supporterBonus = SupporterBonus,
				supporterTierError = SupporterTierError,
				marineCost = Weights[ 1 ], alienCost = Weights[ 2 ]
			} )
		end

		return Weights
	end

	return function( Optimiser, Player, TeamNumber )
		local Cached = Cache[ Player ]
		if not Cached then
			Cached = Compute( Player )
			Cache[ Player ] = Cached
		end
		return Cached[ TeamNumber ]
	end
end

local function IsSameFriendGroup( VRPlugin, OwnerID, EnemyID )
	local GroupsBySteamID = VRPlugin.FriendGroupsBySteamID
	return GroupsBySteamID and GroupsBySteamID[ OwnerID ] and GroupsBySteamID[ OwnerID ] == GroupsBySteamID[ EnemyID ]
end

local function GetEnemyOwnerFriendGroupSize( VRPlugin, OwnerID )
	local GroupsBySteamID = VRPlugin.FriendGroupsBySteamID
	local Group = GroupsBySteamID and GroupsBySteamID[ OwnerID ]
	return Max( 1, Group and #( Group.Clients or {} ) or 1 )
end

local function BuildEnemyPlayerGroups( OwnerPlugin, VRPlugin, PlayersBySteamID )
	local Config = GetConfig( OwnerPlugin )
	local EnemyCfg = Config.EnemyGroups or {}
	if not EnemyCfg.Enabled then return {}, 0, 0 end

	local MaxEnemies = Max( 1, tonumber( EnemyCfg.MaxEnemyGroupSize ) or 1 )
	local BaseWeighting = tonumber( EnemyCfg.Weighting ) or 0
	if BaseWeighting <= 0 then return {}, 0, 0 end

	local SupporterCfg = Config.Supporters
	local Groups = {}
	local UsedPlayers = {}
	local SkippedPairs = 0

	for OwnerKey, List in pairs( EnemyGroups ) do
		local OwnerID = tonumber( OwnerKey )
		local OwnerPlayer = OwnerID and PlayersBySteamID[ OwnerID ]
		if OwnerPlayer and not UsedPlayers[ OwnerPlayer ] and type( List ) == "table" then
			local Players = { OwnerPlayer }
			for i = 1, #List do
				if #Players >= MaxEnemies + 1 then break end

				local EnemyID = tonumber( List[ i ] )
				local EnemyPlayer = EnemyID and PlayersBySteamID[ EnemyID ]
				if EnemyPlayer and not UsedPlayers[ EnemyPlayer ] then
					if IsSameFriendGroup( VRPlugin, OwnerID, EnemyID ) then
						SkippedPairs = SkippedPairs + 1
					else
						Players[ #Players + 1 ] = EnemyPlayer
					end
				end
			end

			if #Players > 1 then
				local FriendGroupSize = GetEnemyOwnerFriendGroupSize( VRPlugin, OwnerID )
				for i = 1, #Players do
					UsedPlayers[ Players[ i ] ] = true
				end

				-- Supporter priority: the owner's tier, or a listed enemy's tier when
				-- they list the owner back (a mutual pair only builds one group).
				local _, OwnerClient = GetSteamID( OwnerPlayer )
				local SupporterTier, SupporterTierError = GetSupporterTier( SupporterCfg, OwnerClient )
				for i = 2, #Players do
					local EnemyID, EnemyClient = GetSteamID( Players[ i ] )
					local EnemyList = EnemyID and EnemyGroups[ tostring( EnemyID ) ]
					if type( EnemyList ) == "table" then
						for j = 1, #EnemyList do
							if tonumber( EnemyList[ j ] ) == OwnerID then
								local EnemyTier, EnemyTierError = GetSupporterTier( SupporterCfg, EnemyClient )
								if EnemyTier > SupporterTier then SupporterTier = EnemyTier end
								SupporterTierError = SupporterTierError or EnemyTierError
								break
							end
						end
					end
				end
				local GroupBase = Max( BaseWeighting, GetSupporterValue( SupporterCfg, "EnemyWeighting", SupporterTier ) )

				Groups[ #Groups + 1 ] = {
					Players = Players,
					MNGAEnemy = true,
					OwnerID = OwnerID,
					BaseWeighting = GroupBase,
					SupporterTier = SupporterTier,
					SupporterTierError = SupporterTierError,
					FriendGroupSize = FriendGroupSize,
					Weighting = GroupBase / FriendGroupSize
				}
			end
		end
	end

	return Groups, #Groups, SkippedPairs
end

local function AppendEnemyGroups( OwnerPlugin, VRPlugin, TeamMembers )
	if not TeamMembers then return end
	if not VRPlugin.MNGAVoteRandomEnhanceOptimiseTeamsPatched then return end

	local PlayersBySteamID = {}
	for TeamNumber = 1, 2 do
		local Team = TeamMembers[ TeamNumber ]
		for i = 1, #Team do
			local Player = Team[ i ]
			local Client = Player.GetClient and Player:GetClient()
			local SteamID = Client and Client.GetUserId and Client:GetUserId()
			if SteamID then PlayersBySteamID[ SteamID ] = Player end
		end
	end

	local EnemyPlayerGroups, Count, SkippedPairs = BuildEnemyPlayerGroups( OwnerPlugin, VRPlugin, PlayersBySteamID )
	if Count == 0 then
		return
	end

	local Existing = TeamMembers.PlayerGroups or {}
	local Combined = {}
	for i = 1, #EnemyPlayerGroups do
		Combined[ #Combined + 1 ] = EnemyPlayerGroups[ i ]
	end
	for i = 1, #Existing do
		Combined[ #Combined + 1 ] = Existing[ i ]
	end
	TeamMembers.PlayerGroups = Combined

	WriteAuditEvent( OwnerPlugin, VRPlugin, "enemy_groups_active", {
		activeGroupCount = Count,
		skippedFriendPairs = SkippedPairs,
		baseWeighting = ( GetConfig( OwnerPlugin ).EnemyGroups or {} ).Weighting,
		groups = ( function()
			local Output = {}
			for i = 1, #EnemyPlayerGroups do
				local Group = EnemyPlayerGroups[ i ]
				local Players = {}
				for j = 1, #( Group.Players or {} ) do
					local SteamID = GetSteamID( Group.Players[ j ] )
					if SteamID then Players[ #Players + 1 ] = tostring( SteamID ) end
				end
				Output[ #Output + 1 ] = {
					ownerSteamId = tostring( Group.OwnerID ),
					playerSteamIds = Players,
					baseWeighting = Group.BaseWeighting,
					supporterTier = Group.SupporterTier,
					supporterTierError = Group.SupporterTierError,
					friendGroupSize = Group.FriendGroupSize,
					effectiveWeighting = Group.Weighting
				}
			end
			return Output
		end )()
	} )
end

local function BuildNewPlayerGroup( Config, TeamMembers )
	local NewPlayerCfg = Config.NewPlayers or {}
	local Weighting = tonumber( NewPlayerCfg.Weighting ) or 0
	if not NewPlayerCfg.Enabled or Weighting <= 0 then return nil end

	local Threshold = tonumber( NewPlayerCfg.EloThreshold ) or 0
	local Players = {}
	for TeamNumber = 1, 2 do
		local Team = TeamMembers[ TeamNumber ]
		for i = 1, #Team do
			local Player = Team[ i ]
			local SteamID = GetSteamID( Player )
			local Skill, SkillValid = ReadNumericGetter( Player, "GetPlayerSkill", 0 )
			if SteamID and SteamID ~= 0 and SkillValid and Skill < Threshold then
				Players[ #Players + 1 ] = Player
			end
		end
	end

	-- A single new player has nobody to be stacked with.
	if #Players < 2 then return nil end

	return { Players = Players, MNGANewPlayers = true, Weighting = Weighting }
end

local function GetNewPlayerSplit( Group, TeamMembers )
	local Split = { 0, 0 }
	if not Group then return Split end

	local IsNewPlayer = {}
	for i = 1, #Group.Players do
		IsNewPlayer[ Group.Players[ i ] ] = true
	end
	for TeamNumber = 1, 2 do
		local Team = TeamMembers[ TeamNumber ]
		for i = 1, #Team do
			if IsNewPlayer[ Team[ i ] ] then Split[ TeamNumber ] = Split[ TeamNumber ] + 1 end
		end
	end
	return Split
end

-- Strips every MNGA group (enemy and new player), which stock cost code can't read.
local function RemoveEnemyGroups( TeamMembers )
	if not TeamMembers or not TeamMembers.PlayerGroups then return end

	local Filtered = {}
	local Removed = 0
	for i = 1, #TeamMembers.PlayerGroups do
		local Group = TeamMembers.PlayerGroups[ i ]
		if Group.MNGAEnemy or Group.MNGANewPlayers then
			Removed = Removed + 1
		else
			Filtered[ #Filtered + 1 ] = Group
		end
	end

	if Removed > 0 then
		TeamMembers.PlayerGroups = Filtered
	end
end

local function FilterPlayerGroupsPreservingFlags( PlayerGroups, TeamMembers )
	local PlayersBeingOptimised = {}
	for TeamNumber = 1, 2 do
		local Team = TeamMembers[ TeamNumber ]
		for i = 1, #Team do
			PlayersBeingOptimised[ Team[ i ] ] = true
		end
	end

	local Filtered = {}
	for i = 1, #PlayerGroups do
		local Group = PlayerGroups[ i ]
		local Players = {}
		for j = 1, #Group.Players do
			local Player = Group.Players[ j ]
			if PlayersBeingOptimised[ Player ] then
				Players[ #Players + 1 ] = Player
			end
		end
		if #Players > 1 then
			Filtered[ #Filtered + 1 ] = {
				Players = Players,
				MNGAEnemy = Group.MNGAEnemy,
				OwnerID = Group.OwnerID,
				Weighting = Group.Weighting
			}
		end
	end

	return Filtered
end

local function MakeGroupWeighting( PlayWithFriendsWeighting )
	return function( Optimiser, Group, ChangedPlayer, NewTeam )
		local Players = Group.Players
		local TeamLookup = Optimiser.TeamLookup

		if Group.MNGAEnemy then
			local SamePairs = 0
			local TotalPairs = 0
			for i = 1, #Players do
				local PlayerI = Players[ i ]
				local TeamI = TeamLookup[ PlayerI ]
				if PlayerI == ChangedPlayer then TeamI = NewTeam end

				for j = i + 1, #Players do
					local PlayerJ = Players[ j ]
					local TeamJ = TeamLookup[ PlayerJ ]
					if PlayerJ == ChangedPlayer then TeamJ = NewTeam end

					TotalPairs = TotalPairs + 1
					if TeamI == TeamJ then SamePairs = SamePairs + 1 end
				end
			end

			if TotalPairs == 0 then return 0 end
			return ( SamePairs / TotalPairs ) * ( Group.Weighting or 0 )
		end

		local NumOnTeam1 = 0
		local NumOnTeam2 = 0
		for i = 1, #Players do
			local Player = Players[ i ]
			local Team = TeamLookup[ Player ]
			if Player == ChangedPlayer then Team = NewTeam end

			NumOnTeam1 = NumOnTeam1 + Team % 2
			NumOnTeam2 = NumOnTeam2 + ( Team - 1 )
		end

		if Group.MNGANewPlayers then
			-- Players who must cross to even the sides: 2-0 and 3-0 cost 1, 4-0 costs 2.
			return math.floor( Abs( NumOnTeam1 - NumOnTeam2 ) * 0.5 ) * Group.Weighting
		end

		local MajorityOnTeam = Max( NumOnTeam1, NumOnTeam2 )
		return Remap( MajorityOnTeam, 0.5 * #Players, #Players, 1, 0 ) * PlayWithFriendsWeighting
	end
end

local function MakeFullGroupRecompute( PlayWithFriendsWeighting )
	return function( Optimiser, Team1Player, Team2Player )
		local OriginalTeam1 = Team1Player and Optimiser.TeamLookup[ Team1Player ]
		local OriginalTeam2 = Team2Player and Optimiser.TeamLookup[ Team2Player ]
		if Team1Player then Optimiser.TeamLookup[ Team1Player ] = 2 end
		if Team2Player then Optimiser.TeamLookup[ Team2Player ] = 1 end
		local Total = 0
		for i = 1, #Optimiser.PlayerGroups do
			Total = Total + Optimiser:GetGroupWeighting( Optimiser.PlayerGroups[ i ] )
		end
		if Team1Player then Optimiser.TeamLookup[ Team1Player ] = OriginalTeam1 end
		if Team2Player then Optimiser.TeamLookup[ Team2Player ] = OriginalTeam2 end
		return Total
	end
end

local function SnapshotGroupDisposition( TeamMembers, GetGroupWeighting )
	local Lookup = {}
	for TeamNumber = 1, 2 do
		for i = 1, #TeamMembers[ TeamNumber ] do Lookup[ TeamMembers[ TeamNumber ][ i ] ] = TeamNumber end
	end
	local Fake = { TeamLookup = Lookup }
	local Output = SnapshotPlayerGroups( TeamMembers )
	for i = 1, #( TeamMembers.PlayerGroups or {} ) do
		local Group = TeamMembers.PlayerGroups[ i ]
		local TeamCounts = { 0, 0 }
		for j = 1, #Group.Players do
			local Team = Lookup[ Group.Players[ j ] ]
			if Team then TeamCounts[ Team ] = TeamCounts[ Team ] + 1 end
		end
		Output[ i ].teamCounts = TeamCounts
		Output[ i ].contributedCost = GetGroupWeighting and GetGroupWeighting( Fake, Group ) or 0
	end
	return Output
end

local function GetFiniteSafeCost( Config, AverageDiff, StdDiff, PreferenceCost, GroupCost )
	local Safety = Config.Optimiser and Config.Optimiser.CostSafety or {}
	local Enabled = Safety.Enabled ~= false
	local ExponentCap = tonumber( Safety.ExponentCap ) or 600
	local MaximumCost = tonumber( Safety.MaximumFiniteCost ) or 1e300
	local Capped = false
	local function Component( Value, Bound )
		Value = tonumber( Value ) or 0
		local Exponent = Max( Value - Bound, 0 )
		if Enabled and Exponent > ExponentCap then
			Exponent = ExponentCap
			Capped = true
		end
		return Value * math.exp( Exponent )
	end
	local Cost = Component( AverageDiff, 75 ) + Component( StdDiff, 150 )
		+ ( tonumber( PreferenceCost ) or 0 ) + ( tonumber( GroupCost ) or 0 )
	if not IsFiniteNumber( Cost ) or Cost > MaximumCost then
		Cost = MaximumCost
		Capped = true
	end
	return Cost, Capped
end

local function PatchApplyAutoShuffle( OwnerPlugin, VRPlugin )
	if VRPlugin.MNGAVoteRandomEnhanceOriginalApplyAutoShuffle then return end
	if type( VRPlugin.ApplyAutoShuffle ) ~= "function" then return end

	VRPlugin.MNGAVoteRandomEnhanceOriginalApplyAutoShuffle = VRPlugin.ApplyAutoShuffle

	function VRPlugin:ApplyAutoShuffle( ... )
		WriteAuditEvent( OwnerPlugin, self, "auto_shuffle_attempt", {
			autoShuffleAtRoundStart = self.Config and self.Config.AutoShuffleAtRoundStart == true,
			suppressed = self.SuppressAutoShuffle == true
		}, false )
		if self.Config and self.Config.AutoShuffleAtRoundStart then
			if self.Vote and type( self.Vote.Reset ) == "function" then
				self.Vote:Reset()
			end

			if self.SuppressAutoShuffle then
				WriteAuditEvent( OwnerPlugin, self, "auto_shuffle_skipped", {
					reason = "suppressed"
				}, false )
				return
			end

		local AutoShuffle = GetConfig( OwnerPlugin ).AutoShuffle or {}
		local MinPlayers = AutoShuffle.MinimumHumansEnabled == false and 0
			or tonumber( AutoShuffle.MinimumHumans ) or 0
			local PlayerCount, CountSource
			if OwnerPlugin.GetPopulationHumanCount then
				PlayerCount = OwnerPlugin:GetPopulationHumanCount()
				CountSource = "MNGA non-spectating humans"
			else
				PlayerCount = Shine.GetHumanPlayerCount and Shine.GetHumanPlayerCount() or 0
				CountSource = "Shine.GetHumanPlayerCount"
			end
			if MinPlayers > 0 and PlayerCount <= MinPlayers then
				WriteAuditEvent( OwnerPlugin, self, "auto_shuffle_skipped", {
					reason = "population_at_or_below_minimum",
					playerCount = PlayerCount,
					minimum = MinPlayers,
					countSource = CountSource
				}, false )
				return
			end
		end

		WriteAuditEvent( OwnerPlugin, self, "auto_shuffle_proceeding", {}, false )
		return self.MNGAVoteRandomEnhanceOriginalApplyAutoShuffle( self, ... )
	end

	PatchState.Patches[ #PatchState.Patches + 1 ] = "ApplyAutoShuffle player minimum"
end

local function PatchGetTargetsForSorting( OwnerPlugin, VRPlugin )
	if VRPlugin.MNGAVoteRandomEnhanceOriginalGetTargetsForSorting then return end
	if type( VRPlugin.GetTargetsForSorting ) ~= "function" then return end

	VRPlugin.MNGAVoteRandomEnhanceOriginalGetTargetsForSorting = VRPlugin.GetTargetsForSorting

	function VRPlugin:GetTargetsForSorting( ... )
		local Targets, TeamMembers = self.MNGAVoteRandomEnhanceOriginalGetTargetsForSorting( self, ... )
		if TeamMembers then
			CapturePreferencesFromTeamMembers( self, TeamMembers )
			AppendEnemyGroups( OwnerPlugin, self, TeamMembers )
		end
		local Ready, Reason = GetPredictionReadiness(
			OwnerPlugin, self, Targets, TeamMembers, GetConfig( OwnerPlugin )
		)
		self.MNGAEloPredictionReady = Ready
		self.MNGAEloPredictionReason = Reason
		local Config = GetConfig( OwnerPlugin )
		local TargetSnapshots = {}
		for i = 1, #( Targets or {} ) do
			TargetSnapshots[ #TargetSnapshots + 1 ] = SnapshotPlayer(
				OwnerPlugin, self, Targets[ i ], nil, TeamMembers and TeamMembers.TeamPreferences
			)
		end
		WriteAuditEvent( OwnerPlugin, self, "prediction_preflight", {
			ready = Ready,
			reason = Reason,
			rankSource = "player_skill_fields",
			configuredModel = Config.EloPrediction,
			targets = TargetSnapshots,
			fixedTeams = SnapshotTeams( OwnerPlugin, self, TeamMembers ),
			playerGroups = SnapshotPlayerGroups( TeamMembers )
		} )
		return Targets, TeamMembers
	end

	PatchState.Patches[ #PatchState.Patches + 1 ] = "GetTargetsForSorting preference capture + enemy groups"
end

local function PatchOptimiseHappiness( VRPlugin )
	if VRPlugin.MNGAVoteRandomEnhanceOriginalOptimiseHappiness then return end
	if type( VRPlugin.OptimiseHappiness ) ~= "function" then return end

	VRPlugin.MNGAVoteRandomEnhanceOriginalOptimiseHappiness = VRPlugin.OptimiseHappiness

	function VRPlugin:OptimiseHappiness( TeamMembers, ... )
		local A, B = self.MNGAVoteRandomEnhanceOriginalOptimiseHappiness( self, TeamMembers, ... )
		CapturePreferencesFromTeamMembers( self, TeamMembers )
		return A, B
	end

	PatchState.Patches[ #PatchState.Patches + 1 ] = "OptimiseHappiness preference capture"
end

local function PatchShuffleTeams( OwnerPlugin, VRPlugin )
	if VRPlugin.MNGAVoteRandomEnhanceOriginalShuffleTeams then return end
	if type( VRPlugin.ShuffleTeams ) ~= "function" then return end

	VRPlugin.MNGAVoteRandomEnhanceOriginalShuffleTeams = VRPlugin.ShuffleTeams

	function VRPlugin:ShuffleTeams( ResetScores, ForceMode )
		local Result
		local RetryOf
		local ShuffleStartedAt = WallTime()
		local MaximumAttempts = 1 + Clamp( math.floor( tonumber(
			GetConfig( OwnerPlugin ).RosterValidation.MaximumRetries ) or 1 ), 0, 1 )
		for Attempt = 1, MaximumAttempts do
			self.MNGASelectedTeams = nil
			self.MNGASelectedRosterValid = nil
			AuditState.ShuffleSequence = AuditState.ShuffleSequence + 1
			local ServerID = ( GetConfig( OwnerPlugin ).AuditLog or {} ).ServerID or "unknown"
			self.MNGAAuditShuffleID = StringFormat(
				"%s-%d-%d", SanitiseFilePart( ServerID ), os.time(),
				math.floor( ( Shared.GetTime and Shared.GetTime() or 0 ) * 1000 ) + AuditState.ShuffleSequence
			)
			WriteAuditEvent( OwnerPlugin, self, "shuffle_started", {
				attempt = Attempt,
				retryOfShuffleId = RetryOf,
				optimisingTeams = self.OptimisingTeams == true,
				gameState = GetGamerules and GetGamerules() and GetGamerules():GetGameState() or nil
			} )
			Result = { self.MNGAVoteRandomEnhanceOriginalShuffleTeams(
				self, Attempt == 1 and ResetScores or false, ForceMode ) }
			local Drift
			if self.MNGASelectedTeams then
				Drift = CompareShuffleRosters( self.MNGASelectedTeams,
					SnapshotTeams( OwnerPlugin, self, CaptureLiveTeams() ) )
				self.MNGASelectedRosterValid = Drift.matches
			end
			if not Drift or Drift.matches then break end
			Drift.phase = "assignment"
			Drift.retryScheduled = Attempt < MaximumAttempts
			WriteAuditEvent( OwnerPlugin, self, "shuffle_roster_drift", Drift )
			Print( "[ShuffleRoster] Roster changed after assignment: added=%d removed=%d changed=%d retry=%s",
				#Drift.added, #Drift.removed, #Drift.changed, tostring( Drift.retryScheduled ) )
			if Drift.retryScheduled then
				RetryOf = self.MNGAAuditShuffleID
				WriteAuditEvent( OwnerPlugin, self, "shuffle_discarded", { reason = "roster_drift_retry" } )
			end
		end
		StageShuffleFromLookup( OwnerPlugin, self )
		WriteAuditEvent( OwnerPlugin, self, "shuffle_completed", {
			totalElapsedMilliseconds = ( WallTime() - ShuffleStartedAt ) * 1000,
			timingClock = "Shared.GetSystemTimeReal",
			retried = RetryOf ~= nil,
			selectedRosterValid = self.MNGASelectedRosterValid
		} )
		self.MNGASelectedTeams = nil
		self.MNGAAuditShuffleID = nil
		self.MNGAEloPredictionReady = nil
		self.MNGAEloPredictionReason = nil
		return unpack( Result )
	end

	PatchState.Patches[ #PatchState.Patches + 1 ] = "ShuffleTeams final diagnostics + staging"
end

local function PatchOptimiseTeams( OwnerPlugin, VRPlugin )
	if VRPlugin.MNGAVoteRandomEnhanceOriginalOptimiseTeams then return end
	if type( VRPlugin.OptimiseTeams ) ~= "function" then return end

	VRPlugin.MNGAVoteRandomEnhanceOriginalOptimiseTeams = VRPlugin.OptimiseTeams

	local function DebugLogTeamMembers( Logger, self, TeamMembers )
		local Output = { self:AsLogOutput( TeamMembers[ 1 ] ), self:AsLogOutput( TeamMembers[ 2 ] ) }
		Logger:Debug( "Assigned team members:\n%s", table.ToString( Output ) )
	end

	local function OptimiseTeamsEnhanced( self, TeamMembers, RankFunc, TeamSkills )
		local Config = GetConfig( OwnerPlugin )
		local OptimiserConfig = Config.Optimiser or {}
		if OptimiserConfig.Enabled == false then
			RemoveEnemyGroups( TeamMembers )
			return self.MNGAVoteRandomEnhanceOriginalOptimiseTeams( self, TeamMembers, RankFunc, TeamSkills )
		end
		local function LocalRoleRank( Player, TeamNumber )
			local FieldSkill, CommanderSkill = GetLocalSideSkills( Player, TeamNumber )
			return self.IsPlayerCommander( Player ) and CommanderSkill or FieldSkill
		end
		RankFunc = LocalRoleRank
		Print( "[ShuffleRating] Using commander Elo for seated commanders and field Elo for field players." )
		TeamSkills = self:ComputeTeamSkills( TeamMembers, RankFunc )
		local TeamPreferences = TeamMembers.TeamPreferences
		local function GetNumPasses()
			return next( TeamPreferences ) and 2 or 1
		end

		local IgnoreCommanders = self.Config.IgnoreCommanders
		local function IsValidForSwapSinglePass( _, Player )
			return not ( IgnoreCommanders and self.IsPlayerCommander( Player ) )
		end

		local function IsValidForSwapMultiPass( SelfArg, Player, Pass, TeamNumber )
			if not IsValidForSwapSinglePass( SelfArg, Player ) then
				return false
			end
			if Pass == 1 and TeamPreferences[ Player ] == TeamNumber then
				return false
			end
			return true
		end

		local TeamPreferenceWeighting = self.TeamPreferenceWeighting
		local Streaks = Config.Streaks or {}
		local StreaksActive = Streaks.Enabled and ( tonumber( Streaks.WeightScale ) or 0 ) > 0
			and ( tonumber( Streaks.MaxWeight ) or 0 ) > 0
		local WeightingActive = TeamPreferenceWeighting > 0 or StreaksActive
		local GetTeamPreferenceWeighting
		if WeightingActive then
			GetTeamPreferenceWeighting = MakeCombinedWeighting( OwnerPlugin, self, TeamMembers, TeamPreferenceWeighting )
		end

		local PlayWithFriendsWeighting = self.PlayWithFriendsWeighting
		local EnemyCfg = Config.EnemyGroups or {}
		local NewPlayerGroup = BuildNewPlayerGroup( Config, TeamMembers )
		local GroupsActive = PlayWithFriendsWeighting > 0 or NewPlayerGroup
			or ( EnemyCfg.Enabled and ( tonumber( EnemyCfg.Weighting ) or 0 ) > 0 )
		local RecomputeGroupWeighting
		local ComputeInitialGroupWeightings
		local GetGroupWeighting

		if not GroupsActive then
			RecomputeGroupWeighting = function() return 0 end
			ComputeInitialGroupWeightings = function() return 0 end
		else
			GetGroupWeighting = MakeGroupWeighting( PlayWithFriendsWeighting )
			RecomputeGroupWeighting = MakeFullGroupRecompute( PlayWithFriendsWeighting )
			if TeamMembers.PlayerGroups then
				TeamMembers.PlayerGroups = FilterPlayerGroupsPreservingFlags( TeamMembers.PlayerGroups, TeamMembers )
			end
		end

		-- Built here, not with the enemy groups, so ready room players seated since then count.
		if NewPlayerGroup then
			local PlayerGroups = TeamMembers.PlayerGroups or {}
			PlayerGroups[ #PlayerGroups + 1 ] = NewPlayerGroup
			TeamMembers.PlayerGroups = PlayerGroups
		end

		local NumPlayers = #TeamMembers[ 1 ] + #TeamMembers[ 2 ]
		local Params = self.OptimisationParams
		local StockIterations = Round( Remap( Clamp( NumPlayers, 24, 50 ), 50, 24, 1, 5 ) )
		local RequestedStarts = math.floor( tonumber( OptimiserConfig.Starts ) or 10 )
		local MaximumStarts = Max( 1, math.floor( tonumber( OptimiserConfig.MaximumStarts ) or 50 ) )
		RequestedStarts = Clamp( RequestedStarts, 1, MaximumStarts )
		local NumIterations = Max( StockIterations, RequestedStarts )
		local Results = {}
		local OptimiserStartedAt = WallTime()
		local AuditSecondsAtStart = AuditState.WriteSeconds
		local UniqueRosters = {}
		local UniqueRosterCount = 0

		local Players
		local Commanders
		if NumIterations > 1 then
			Players = {}
			Commanders = {}
			for TeamNumber = 1, 2 do
				local Team = TeamMembers[ TeamNumber ]
				for i = 1, #Team do
					local Player = Team[ i ]
					if IgnoreCommanders and self.IsPlayerCommander( Player ) then
						Commanders[ TeamNumber ] = Player
					else
						Players[ #Players + 1 ] = Player
					end
				end
			end
		end

		WriteAuditEvent( OwnerPlugin, self, "optimiser_setup", {
			playerCount = NumPlayers,
			requestedStarts = RequestedStarts,
			effectiveStarts = NumIterations,
			stockIterations = StockIterations,
			passes = GetNumPasses(),
			ignoreCommanders = IgnoreCommanders == true,
			rankSource = "player_skill_fields",
			rankBasis = "seated_commander_elo_otherwise_field_elo",
			timingClock = "Shared.GetSystemTimeReal",
			costSafety = OptimiserConfig.CostSafety,
			optimisationParams = SnapshotScalarFields( Params ),
			varietyConfig = Config.Variety,
			predictionConfig = Config.EloPrediction,
			supportersConfig = Config.Supporters,
			newPlayersConfig = Config.NewPlayers,
			playerGroups = SnapshotPlayerGroups( TeamMembers )
		} )

		for Iteration = 1, NumIterations do
			local IterationStartedAt = WallTime()
			local IterationTeamMembers
			local IterationTeamSkills

			if Iteration > 1 then
				IterationTeamMembers = self:RandomisePlayers( Players, Commanders )
				IterationTeamMembers.PlayerGroups = TeamMembers.PlayerGroups
				IterationTeamMembers.TeamPreferences = TeamMembers.TeamPreferences
				IterationTeamSkills = self:ComputeTeamSkills( IterationTeamMembers, RankFunc )
			else
				IterationTeamMembers = TableCopy( TeamMembers )
				IterationTeamSkills = TableCopy( TeamSkills )
			end

			local Optimiser = self.TeamOptimiser( IterationTeamMembers, IterationTeamSkills, RankFunc )
			if Params.NeedsMultiPass or not WeightingActive then
				Optimiser.GetNumPasses = GetNumPasses
				Optimiser.IsValidForSwap = IsValidForSwapMultiPass
			else
				Optimiser.IsValidForSwap = IsValidForSwapSinglePass
			end

			if RecomputeGroupWeighting then
				Optimiser.RecomputeGroupWeighting = RecomputeGroupWeighting
				Optimiser.ComputeInitialGroupWeightings = ComputeInitialGroupWeightings
			end
			if GetGroupWeighting then
				Optimiser.GetGroupWeighting = GetGroupWeighting
			end
			if GetTeamPreferenceWeighting then
				Optimiser.GetTeamPreferenceWeighting = GetTeamPreferenceWeighting
			end

			TableShallowMerge( Params, Optimiser, true )
			Optimiser.SwapPassesRequirements = function( OptimiserSelf, AverageDiff, StdDiff, PreferenceCost, GroupCost )
				local NewCost = GetFiniteSafeCost( Config, AverageDiff, StdDiff, PreferenceCost, GroupCost )
				local CurrentCost = OptimiserSelf.CurrentPotentialState.Cost
				if not CurrentCost or NewCost < CurrentCost then return true, NewCost end
				return false
			end
			Optimiser:CacheStats()
			local InitialAverageDiff = Abs( Optimiser.TeamSkills[ 1 ].Average - Optimiser.TeamSkills[ 2 ].Average )
			local InitialStdDiff = Abs( Optimiser.StandardDeviationCache[ 1 ] - Optimiser.StandardDeviationCache[ 2 ] )
			local InitialGroupCost = Optimiser:ComputeInitialGroupWeightings()
			Optimiser.CurrentPotentialState.Cost = GetFiniteSafeCost( Config,
				InitialAverageDiff, InitialStdDiff, Optimiser.InitialTeamPreferenceWeighting, InitialGroupCost )

			Optimiser:Optimise()

			local State = Optimiser.CurrentPotentialState
			local Cost, CostCapped = GetFiniteSafeCost( Config,
				State.AverageDiffBefore, State.StdDiffBefore,
				State.TeamPreferenceWeighting, State.PlayWithFriendsWeighting )
			local IterationElapsedMS = ( WallTime() - IterationStartedAt ) * 1000
			local Similarity = ComputeSimilarity( IterationTeamMembers )
			local PrefHeld, PrefTotal = CountPreferencesSatisfied( IterationTeamMembers )
			local EloPrediction, EloPredictionReason = ComputeEloPrediction(
				OwnerPlugin, self, IterationTeamMembers, Config
			)
			local CandidateSnapshot = SnapshotTeams( OwnerPlugin, self, IterationTeamMembers, RankFunc )
			local RosterIDs = {}
			for Team = 1, 2 do
				for i = 1, #CandidateSnapshot[ Team ] do
					RosterIDs[ #RosterIDs + 1 ] = Team..":"..CandidateSnapshot[ Team ][ i ].rosterId
				end
			end
			TableSort( RosterIDs )
			local RosterKey = table.concat( RosterIDs, "," )
			if not UniqueRosters[ RosterKey ] then
				UniqueRosters[ RosterKey ] = true
				UniqueRosterCount = UniqueRosterCount + 1
			end

			Results[ Iteration ] = {
				Iteration = Iteration,
				Cost = Cost,
				AvgDiff = State.AverageDiffBefore or 0,
				StdDiff = State.StdDiffBefore or 0,
				PrefCost = State.TeamPreferenceWeighting or 0,
				GroupCost = State.PlayWithFriendsWeighting or 0,
				Similarity = Similarity,
				PrefHeld = PrefHeld,
				PrefTotal = PrefTotal,
				EloPrediction = EloPrediction,
				EloPredictionReason = EloPredictionReason,
				CostCapped = CostCapped,
				ElapsedMS = IterationElapsedMS,
				TeamMembers = IterationTeamMembers,
				TeamSkills = IterationTeamSkills
			}
			WriteAuditEvent( OwnerPlugin, self, "candidate_evaluated", {
				iteration = Iteration,
				cost = Cost,
				costCapped = CostCapped,
				elapsedMilliseconds = IterationElapsedMS,
				averageDifference = State.AverageDiffBefore or 0,
				standardDeviationDifference = State.StdDiffBefore or 0,
				preferenceCost = State.TeamPreferenceWeighting or 0,
				groupCost = State.PlayWithFriendsWeighting or 0,
				similarity = Similarity,
				preferencesHeld = PrefHeld,
				preferencesTotal = PrefTotal,
				prediction = EloPrediction,
				predictionReason = EloPredictionReason,
				groups = SnapshotGroupDisposition( IterationTeamMembers, GetGroupWeighting ),
				teams = CandidateSnapshot,
				rosterKey = RosterKey
			} )
		end

		TableSort( Results, function( A, B )
			if A.Cost == B.Cost then return A.Iteration < B.Iteration end
			return A.Cost < B.Cost
		end )

		local Variety = Config.Variety or {}
		local Delta = tonumber( Variety.MaxCostDeltaForVariety ) or 0
		local Threshold = tonumber( Variety.SimilarityThreshold ) or 1
		local BestResult = Results[ 1 ]
		local BestCost = BestResult.Cost
		local Chosen = BestResult
		local PredictionConfig = Config.EloPrediction or {}
		local PredictionSelection = false
		local PredictionCostDelta = tonumber( PredictionConfig.MaxStockCostDelta ) or 0

		if PredictionConfig.Enabled then
			for i = 1, #Results do
				local Result = Results[ i ]
				local Prediction = Result.EloPrediction
				if Prediction and Result.Cost <= BestCost + PredictionCostDelta then
					if not PredictionSelection
					or Prediction.ProbabilityDistance < Chosen.EloPrediction.ProbabilityDistance
					or (
						Prediction.ProbabilityDistance == Chosen.EloPrediction.ProbabilityDistance
						and Result.Cost < Chosen.Cost
					) or (
						Prediction.ProbabilityDistance == Chosen.EloPrediction.ProbabilityDistance
						and Result.Cost == Chosen.Cost
						and (
							( PredictionConfig.SimilarityTieBreak ~= false and (
								Result.Similarity < Chosen.Similarity or (
									Result.Similarity == Chosen.Similarity and Result.Iteration < Chosen.Iteration
								)
							) ) or (
								PredictionConfig.SimilarityTieBreak == false and Result.Iteration < Chosen.Iteration
							)
						)
					) then
						Chosen = Result
						PredictionSelection = true
					end
				end
			end
		end

		for i = 1, #Results do
			local Result = Results[ i ]
			local WithinDelta = Result.Cost <= BestCost + Delta
			if not PredictionSelection and Variety.SelectionEnabled and BestResult.Similarity >= Threshold and WithinDelta then
				if Result.Similarity < Chosen.Similarity
				or ( Result.Similarity == Chosen.Similarity and Result.Cost < Chosen.Cost ) then
					Chosen = Result
				end
			end
		end

		local SelectionReason = PredictionSelection and "prediction" or "minimum_cost"
		if not PredictionSelection and Chosen ~= BestResult then SelectionReason = "variety" end
		local SortedCandidates = {}
		for i = 1, #Results do
			local Result = Results[ i ]
			SortedCandidates[ i ] = {
				iteration = Result.Iteration,
				cost = Result.Cost,
				costDelta = Result.Cost - BestCost,
				similarity = Result.Similarity,
				probabilityDistance = Result.EloPrediction and Result.EloPrediction.ProbabilityDistance,
				withinPredictionCostCap = Result.Cost <= BestCost + PredictionCostDelta,
				withinVarietyCostCap = Result.Cost <= BestCost + Delta
			}
		end
		local TotalElapsedMS = ( WallTime() - OptimiserStartedAt ) * 1000
		local AuditElapsedMS = ( AuditState.WriteSeconds - AuditSecondsAtStart ) * 1000
		Print( "[ShuffleTiming] %.3f ms through selection, %.3f ms audit writes, %d/%d unique rosters.",
			TotalElapsedMS, AuditElapsedMS, UniqueRosterCount, NumIterations )
		local NewPlayerSplit = GetNewPlayerSplit( NewPlayerGroup, Chosen.TeamMembers )
		if NewPlayerGroup then
			Print( "[ShuffleNewPlayers] %d under %s: chosen split %d-%d.", #NewPlayerGroup.Players,
				tostring( Config.NewPlayers.EloThreshold ), NewPlayerSplit[ 1 ], NewPlayerSplit[ 2 ] )
		end
		WriteAuditEvent( OwnerPlugin, self, "candidate_selected", {
			selectionReason = SelectionReason,
			chosenIteration = Chosen.Iteration,
			minimumCostIteration = BestResult.Iteration,
			minimumCost = BestCost,
			predictionCostDelta = PredictionCostDelta,
			varietyCostDelta = Delta,
			similarityThreshold = Threshold,
			candidatesByCost = SortedCandidates,
			chosenPrediction = Chosen.EloPrediction,
			costPaidAboveMinimum = Chosen.Cost - BestCost,
			newPlayerSplit = NewPlayerSplit,
			totalElapsedMilliseconds = TotalElapsedMS,
			auditWriteElapsedMilliseconds = AuditElapsedMS,
			nonAuditWriteElapsedMilliseconds = Max( 0, TotalElapsedMS - AuditElapsedMS ),
			uniqueRosterCount = UniqueRosterCount,
			timingClock = "Shared.GetSystemTimeReal",
			rankBasis = "seated_commander_elo_otherwise_field_elo",
			chosenTeams = SnapshotTeams( OwnerPlugin, self, Chosen.TeamMembers, RankFunc )
		} )

		for TeamNumber = 1, 2 do
			TeamMembers[ TeamNumber ] = Chosen.TeamMembers[ TeamNumber ]
			TeamSkills[ TeamNumber ] = Chosen.TeamSkills[ TeamNumber ]
		end

		self.Logger:IfDebugEnabled( DebugLogTeamMembers, self, TeamMembers )

		local BeforeHappiness = SnapshotTeams( OwnerPlugin, self, TeamMembers, RankFunc )
		local BeforePrediction, BeforeReason = ComputeEloPrediction( OwnerPlugin, self, TeamMembers, Config )
		local HappinessChanged, HappinessValue = self:OptimiseHappiness( TeamMembers )
		local AfterPrediction, AfterReason = ComputeEloPrediction( OwnerPlugin, self, TeamMembers, Config )
		self.MNGASelectedTeams = SnapshotTeams( OwnerPlugin, self, TeamMembers, RankFunc )
		WriteAuditEvent( OwnerPlugin, self, "post_happiness", {
			changed = HappinessChanged == true,
			result = type( HappinessValue ) == "number" and HappinessValue or nil,
			beforeTeams = BeforeHappiness,
			afterTeams = SnapshotTeams( OwnerPlugin, self, TeamMembers, RankFunc ),
			beforePrediction = BeforePrediction,
			beforePredictionReason = BeforeReason,
			afterPrediction = AfterPrediction,
			afterPredictionReason = AfterReason
		} )
		if HappinessChanged then
			self.Logger:IfDebugEnabled( DebugLogTeamMembers, self, TeamMembers )
		end
	end

	function VRPlugin:OptimiseTeams( TeamMembers, RankFunc, TeamSkills )
		if self.MNGAVoteRandomEnhanceOptimiseTeamsFailed then
			WriteAuditEvent( OwnerPlugin, self, "optimiser_fallback", {
				reason = "previous_enhanced_optimiser_failure",
				teamsBeforeFallback = SnapshotTeams( OwnerPlugin, self, TeamMembers, RankFunc )
			} )
			RemoveEnemyGroups( TeamMembers )
			return self.MNGAVoteRandomEnhanceOriginalOptimiseTeams( self, TeamMembers, RankFunc, TeamSkills )
		end

		local OK, Err = pcall( OptimiseTeamsEnhanced, self, TeamMembers, RankFunc, TeamSkills )
		if OK then return end

		self.MNGAVoteRandomEnhanceOptimiseTeamsFailed = true
		self.MNGASelectedTeams = nil
		self.MNGAVoteRandomEnhanceOptimiseTeamsPatched = false
		RemoveEnemyGroups( TeamMembers )
		WriteAuditEvent( OwnerPlugin, self, "optimiser_fallback", {
			reason = "enhanced_optimiser_error",
			error = tostring( Err ),
			teamsBeforeFallback = SnapshotTeams( OwnerPlugin, self, TeamMembers, RankFunc )
		} )
		return self.MNGAVoteRandomEnhanceOriginalOptimiseTeams( self, TeamMembers, RankFunc, TeamSkills )
	end

	VRPlugin.MNGAVoteRandomEnhanceOptimiseTeamsPatched = true

	PatchState.Patches[ #PatchState.Patches + 1 ] = "OptimiseTeams conservative variety + streak + enemy groups"
end

local function RestorePatches( VRPlugin )
	if not VRPlugin then return end

	if VRPlugin.MNGAVoteRandomEnhanceOriginalApplyAutoShuffle then
		VRPlugin.ApplyAutoShuffle = VRPlugin.MNGAVoteRandomEnhanceOriginalApplyAutoShuffle
		VRPlugin.MNGAVoteRandomEnhanceOriginalApplyAutoShuffle = nil
	end
	if VRPlugin.MNGAVoteRandomEnhanceOriginalGetTargetsForSorting then
		VRPlugin.GetTargetsForSorting = VRPlugin.MNGAVoteRandomEnhanceOriginalGetTargetsForSorting
		VRPlugin.MNGAVoteRandomEnhanceOriginalGetTargetsForSorting = nil
	end
	if VRPlugin.MNGAVoteRandomEnhanceOriginalOptimiseHappiness then
		VRPlugin.OptimiseHappiness = VRPlugin.MNGAVoteRandomEnhanceOriginalOptimiseHappiness
		VRPlugin.MNGAVoteRandomEnhanceOriginalOptimiseHappiness = nil
	end
	if VRPlugin.MNGAVoteRandomEnhanceOriginalShuffleTeams then
		VRPlugin.ShuffleTeams = VRPlugin.MNGAVoteRandomEnhanceOriginalShuffleTeams
		VRPlugin.MNGAVoteRandomEnhanceOriginalShuffleTeams = nil
	end
	if VRPlugin.MNGAVoteRandomEnhanceOriginalOptimiseTeams then
		VRPlugin.OptimiseTeams = VRPlugin.MNGAVoteRandomEnhanceOriginalOptimiseTeams
		VRPlugin.MNGAVoteRandomEnhanceOriginalOptimiseTeams = nil
	end
	if VRPlugin.MNGAVoteRandomEnhanceOriginalMakeNewFriendGroup then
		VRPlugin.MakeNewFriendGroup = VRPlugin.MNGAVoteRandomEnhanceOriginalMakeNewFriendGroup
		VRPlugin.MNGAVoteRandomEnhanceOriginalMakeNewFriendGroup = nil
	end
	if VRPlugin.MNGAVoteRandomEnhanceOriginalAddClientToFriendGroup then
		VRPlugin.AddClientToFriendGroup = VRPlugin.MNGAVoteRandomEnhanceOriginalAddClientToFriendGroup
		VRPlugin.MNGAVoteRandomEnhanceOriginalAddClientToFriendGroup = nil
	end

	VRPlugin.MNGAVoteRandomEnhancePatched = nil
	VRPlugin.MNGAVoteRandomEnhanceOptimiseTeamsPatched = nil
	VRPlugin.MNGAVoteRandomEnhanceOptimiseTeamsFailed = nil
	VRPlugin.MNGAEloPredictionReady = nil
	VRPlugin.MNGAEloPredictionReason = nil
	VRPlugin.MNGAAuditShuffleID = nil
	VRPlugin.MNGASelectedTeams = nil
	VRPlugin.MNGASelectedRosterValid = nil
end

local function ApplyPatches( OwnerPlugin, VRPlugin )
	if not VRPlugin or VRPlugin.MNGAVoteRandomEnhancePatched then return end

	local Config = GetConfig( OwnerPlugin )
	local ExpectedVersion = ( Config.Compatibility or {} ).ExpectedVoteRandomVersion or ExpectedVoteRandomVersion
	if not Config.Enabled then
		if OwnerPlugin.InstallVoteRandomAutoShufflePatch then
			OwnerPlugin:InstallVoteRandomAutoShufflePatch()
		end
		return
	end

	PatchState.AppliedCount = PatchState.AppliedCount + 1
	PatchState.LastVersion = VRPlugin.Version
	PatchState.VersionMatches = VRPlugin.Version == ExpectedVersion
	PatchState.Patches = {}


	PatchApplyAutoShuffle( OwnerPlugin, VRPlugin )
	PatchGetTargetsForSorting( OwnerPlugin, VRPlugin )
	PatchOptimiseHappiness( VRPlugin )
	PatchShuffleTeams( OwnerPlugin, VRPlugin )
	PatchFriendGroupExclusivity( OwnerPlugin, VRPlugin )

	if PatchState.VersionMatches then
		PatchOptimiseTeams( OwnerPlugin, VRPlugin )
	else
	end

	VRPlugin.MNGAVoteRandomEnhancePatched = true
	PatchState.PatchedPlugins[ VRPlugin ] = true
end

local function NotifyOrPrint( Client, Format, ... )
	local Message = StringFormat( Format, ... )
	if Client then
		Shine:NotifyColour( Client, 255, 200, 100, Message )
	end
end

local function FindConnectedClientBySteamID( SteamID )
	local Clients = Shine.GetAllClients and Shine.GetAllClients() or {}
	for i = 1, #Clients do
		local Candidate = Clients[ i ]
		if Candidate.GetUserId and Candidate:GetUserId() == SteamID then
			return Candidate
		end
	end
end

local function SetEnemyGroupTarget( Plugin, Client, TargetSteamID, ShouldAdd, Source )
	if not Client or not Client.GetUserId then return false, "invalid_client" end
	local OwnerID = Client:GetUserId()
	TargetSteamID = tonumber( TargetSteamID )
	if not OwnerID or not TargetSteamID or TargetSteamID <= 0 then return false, "invalid_target" end
	if OwnerID == TargetSteamID then return false, "self" end

	local Config = GetConfig( Plugin )
	local EnemyConfig = Config.EnemyGroups or {}
	if not EnemyConfig.Enabled then return false, "disabled" end
	local VoteRandom = Shine.Plugins and Shine.Plugins[ "voterandom" ]
	if VoteRandom and IsSameFriendGroup( VoteRandom, OwnerID, TargetSteamID ) then
		return false, "friend_group"
	end
	local TargetClient = FindConnectedClientBySteamID( TargetSteamID )
	if not TargetClient or ( TargetClient.GetIsVirtual and TargetClient:GetIsVirtual() ) then
		return false, "not_connected"
	end

	local Key = tostring( OwnerID )
	local List = EnemyGroups[ Key ] or {}
	local ExistingIndex
	for i = 1, #List do
		if tonumber( List[ i ] ) == TargetSteamID then
			ExistingIndex = i
			break
		end
	end

	if ShouldAdd then
		if ExistingIndex then return false, "already_added" end
		local MaxGroupSize = Max( 1, tonumber( EnemyConfig.MaxEnemyGroupSize ) or 1 )
		if #List >= MaxGroupSize then
			-- A target who left (e.g. during a map change) must not hold the slot.
			PruneDisconnectedEnemyGroups( Plugin, OwnerID, "add slot check" )
			List = EnemyGroups[ Key ] or {}
		end
		if #List >= MaxGroupSize then return false, "full" end
		List[ #List + 1 ] = TargetSteamID
		EnemyGroups[ Key ] = List
	else
		if not ExistingIndex then return false, "not_added" end
		table.remove( List, ExistingIndex )
		if #List == 0 then
			EnemyGroups[ Key ] = nil
		else
			EnemyGroups[ Key ] = List
		end
	end

	SendEnemyGroupState( Plugin, Client, TargetSteamID, ShouldAdd )
	WriteEnemyGroupAudit( Plugin, ShouldAdd and "enemy_group_added" or "enemy_group_removed", OwnerID, TargetSteamID, Source )
	return true
end

local function RemoveEnemyRelationsForFriendPair( Plugin, FirstID, SecondID )
	local Removed = {}
	local Pairs = { { FirstID, SecondID }, { SecondID, FirstID } }
	for i = 1, #Pairs do
		local OwnerID, TargetID = Pairs[ i ][ 1 ], Pairs[ i ][ 2 ]
		local List = EnemyGroups[ tostring( OwnerID ) ]
		if List then
			for j = #List, 1, -1 do
				if tonumber( List[ j ] ) == TargetID then
					table.remove( List, j )
					Removed[ #Removed + 1 ] = { OwnerID = OwnerID, TargetID = TargetID }
				end
			end
			if #List == 0 then EnemyGroups[ tostring( OwnerID ) ] = nil end
		end
	end
	if #Removed == 0 then return end

	for i = 1, #Removed do
		local Relation = Removed[ i ]
		local OwnerClient = FindConnectedClientBySteamID( Relation.OwnerID )
		if OwnerClient then SendEnemyGroupState( Plugin, OwnerClient, Relation.TargetID, false ) end
		WriteEnemyGroupAudit( Plugin, "enemy_group_removed_for_friend_group",
			Relation.OwnerID, Relation.TargetID, "friend_group" )
	end
end

PatchFriendGroupExclusivity = function( OwnerPlugin, VRPlugin )
	if VRPlugin.MNGAVoteRandomEnhanceOriginalMakeNewFriendGroup
		or type( VRPlugin.MakeNewFriendGroup ) ~= "function"
		or type( VRPlugin.AddClientToFriendGroup ) ~= "function" then return end

	VRPlugin.MNGAVoteRandomEnhanceOriginalMakeNewFriendGroup = VRPlugin.MakeNewFriendGroup
	VRPlugin.MNGAVoteRandomEnhanceOriginalAddClientToFriendGroup = VRPlugin.AddClientToFriendGroup

	function VRPlugin:MakeNewFriendGroup( Leader, Members, ... )
		local LeaderID = Leader and Leader.GetUserId and Leader:GetUserId()
		for i = 1, #( Members or {} ) do
			local Member = Members[ i ]
			local MemberID = Member and Member.GetUserId and Member:GetUserId()
			if LeaderID and MemberID and LeaderID ~= MemberID then
				RemoveEnemyRelationsForFriendPair( OwnerPlugin, LeaderID, MemberID )
			end
		end
		return self.MNGAVoteRandomEnhanceOriginalMakeNewFriendGroup( self, Leader, Members, ... )
	end

	function VRPlugin:AddClientToFriendGroup( Group, Client, ... )
		local ClientID = Client and Client.GetUserId and Client:GetUserId()
		for i = 1, #( Group and Group.Clients or {} ) do
			local Member = Group.Clients[ i ]
			local MemberID = Member and Member.GetUserId and Member:GetUserId()
			if ClientID and MemberID and ClientID ~= MemberID then
				RemoveEnemyRelationsForFriendPair( OwnerPlugin, ClientID, MemberID )
			end
		end
		return self.MNGAVoteRandomEnhanceOriginalAddClientToFriendGroup( self, Group, Client, ... )
	end

	PatchState.Patches[ #PatchState.Patches + 1 ] = "Friend groups clear conflicting enemy relations"
end

function Plugin:ReceiveEnemyGroupAction( Client, Data )
	if type( Data ) ~= "table" then return end
	local ShouldAdd = Data.Action == 1
	if not ShouldAdd and Data.Action ~= 2 then
		return
	end

	local Changed, Reason = SetEnemyGroupTarget( self, Client, Data.TargetSteamID, ShouldAdd, "scoreboard" )
	if Changed then return end

	local Messages = {
		self = "You cannot add yourself to your enemy group.",
		disabled = "Enemy groups are disabled.",
		not_connected = "That player is no longer connected.",
		already_added = "That player is already in your enemy group.",
		not_added = "That player is not in your enemy group.",
		full = StringFormat( "Enemy group is full (%s max). Remove your current enemy first.",
			tostring( ( GetConfig( self ).EnemyGroups or {} ).MaxEnemyGroupSize or 1 ) ),
		friend_group = "Remove this player from your friend group before adding them as an enemy.",
		invalid_target = "Invalid enemy-group target."
	}
	Shine:NotifyColour( Client, 255, 80, 80, Messages[ Reason ] or "Enemy group action failed." )
end

function Plugin:ReceiveEnemyGroupRequestSync( Client )
	SyncEnemyGroupState( self, Client )
end

local function RegisterCommands( self )
	if self.MNGAVoteRandomEnhanceCommandsRegistered then return end
	self.MNGAVoteRandomEnhanceCommandsRegistered = true

	local function Status( Client )
		local Config = GetConfig( self )
		-- Keep this at 7 chat lines or fewer: the chat area only shows the newest ~10.
		-- Patch names go to the caller's console instead.
		NotifyOrPrint( Client, "status: installed=%s appliedCount=%d version=%s match=%s patches=%d (names in console)",
			tostring( PatchState.Installed ), PatchState.AppliedCount,
			tostring( PatchState.LastVersion ), tostring( PatchState.VersionMatches ), #PatchState.Patches )
		local NewPlayers = Config.NewPlayers or {}
		NotifyOrPrint( Client, "config: variety=%s delta=%s streaks=%s enemy=%s enemyWeight=%s xp=%s offset=%s newPlayers=%s<%s w=%s",
			tostring( Config.Variety.SelectionEnabled ), tostring( Config.Variety.MaxCostDeltaForVariety ),
			tostring( Config.Streaks.Enabled ), tostring( Config.EnemyGroups.Enabled ),
			tostring( Config.EnemyGroups.Weighting ), tostring( Config.XPWeighting.Enabled ),
			tostring( Config.OffsetDampening.Enabled ), tostring( NewPlayers.Enabled ),
			tostring( NewPlayers.EloThreshold ), tostring( NewPlayers.Weighting ) )
		local Prediction = Config.EloPrediction or {}
		NotifyOrPrint( Client, "elo model: enabled=%s version=%s beta=%s scale=%s bias=%s stockCostDelta=%s",
			tostring( Prediction.Enabled ), tostring( Prediction.ModelVersion ),
			tostring( Prediction.CommanderPredictionWeight ), tostring( Prediction.LogitScale ),
			 tostring( Prediction.MarineWinBiasLogit ), tostring( Prediction.MaxStockCostDelta ) )
		local Optimiser = Config.Optimiser or {}
		local Safety = Optimiser.CostSafety or {}
		NotifyOrPrint( Client, "optimizer: enabled=%s starts=%s maxStarts=%s finiteCost=%s exponentCap=%s maximumCost=%s",
			tostring( Optimiser.Enabled ), tostring( Optimiser.Starts ), tostring( Optimiser.MaximumStarts ),
			tostring( Safety.Enabled ), tostring( Safety.ExponentCap ), tostring( Safety.MaximumFiniteCost ) )
		NotifyOrPrint( Client, "rating: source=player_skill_fields definitive=true implementation=%s schema=%s",
			PatchImplementationVersion, tostring( AuditSchemaVersion ) )
		local Audit = Config.AuditLog or {}
		NotifyOrPrint( Client, "audit: enabled=%s path=%s dropped=%d lastError=%s",
			tostring( Audit.Enabled ), tostring( AuditState.Path or "not opened" ),
			AuditState.DroppedEvents, tostring( AuditState.LastError ) )
		for i = 1, #PatchState.Patches do
			Shine:AdminPrint( Client, "[vre_status] patch[%d]=%s", true, i, PatchState.Patches[ i ] )
		end
		local Supporters = Config.Supporters or {}
		local Bonus, EnemyWeights = Supporters.PreferenceBonus or {}, Supporters.EnemyWeighting or {}
		NotifyOrPrint( Client, "supporters: enabled=%s prefBonus=%s/%s/%s enemyWeight=%s/%s/%s yourTier=%d",
			tostring( Supporters.Enabled ), tostring( Bonus[ 1 ] ), tostring( Bonus[ 2 ] ), tostring( Bonus[ 3 ] ),
			tostring( EnemyWeights[ 1 ] ), tostring( EnemyWeights[ 2 ] ), tostring( EnemyWeights[ 3 ] ),
			( GetSupporterTier( Supporters, Client ) ) )
	end

	local StatusCommand = self:BindCommand( "sh_vre_status", nil, Status, true )
	StatusCommand:Help( "Prints MNGA VoteRandomEnhance patch status." )

	-- Chat shows only the newest ~10 lines: chat gets a count plus the longest
	-- streaks (6 lines max); the full list goes to the caller's console.
	local MaxStreakChatLines = 5
	local function TeamStreaks( Client )
		local Rows = {}
		local Clients = Shine.GetAllClients()
		for i = 1, #Clients do
			local ConnectedClient = Clients[ i ]
			local SteamID = ConnectedClient.GetUserId and ConnectedClient:GetUserId()
			local Entry = SteamID and UnluckyStreaks[ SteamID ]
			if Entry then
				local Player = ConnectedClient.GetControllingPlayer and ConnectedClient:GetControllingPlayer()
				local Name = Player and Player.GetName and Player:GetName() or tostring( SteamID )
				Rows[ #Rows + 1 ] = {
					Streak = Entry.Streak or 0,
					Text = StringFormat( "%s: wants team %s denied=%d lastTeam=%s",
						Name, tostring( Entry.Pref ), Entry.Streak or 0, tostring( LastCommittedTeams[ SteamID ] ) )
				}
			end
		end

		if #Rows == 0 then
			NotifyOrPrint( Client, "unlucky streaks: none for connected players" )
			return
		end

		TableSort( Rows, function( A, B ) return A.Streak > B.Streak end )
		local Shown = math.min( #Rows, MaxStreakChatLines )
		NotifyOrPrint( Client, "unlucky streaks: %d connected player(s), longest %d shown%s", #Rows, Shown,
			#Rows > Shown and " (full list in console)" or "" )
		for i = 1, Shown do
			NotifyOrPrint( Client, "%s", Rows[ i ].Text )
		end
		if #Rows > Shown then
			for i = 1, #Rows do
				Shine:AdminPrint( Client, "[teamstreaks] %s", true, Rows[ i ].Text )
			end
		end
	end

	local StreakCommand = self:BindCommand( "sh_teamstreaks", nil, TeamStreaks, true )
	StreakCommand:Help( "Prints VoteRandomEnhance denied-preference streaks." )

	local function ListEnemyGroup( Client )
		if not Client then return end
		local SteamID = Client:GetUserId()
		local List = EnemyGroups[ tostring( SteamID ) ] or {}
		if #List == 0 then
			Shine:NotifyColour( Client, 255, 200, 100, "Your enemy group is empty." )
			return
		end
		Shine:NotifyColour( Client, 255, 200, 100, StringFormat( "Your enemy group: %s", table.concat( List, ", " ) ) )
	end

	local ListCommand = self:BindCommand( "sh_enemygroup_list", "enemygroup", ListEnemyGroup, true )
	ListCommand:Help( "Lists your VoteRandom enemy group." )

	local function AddEnemy( Client, Target )
		if not Client or not Target then return end
		local TargetID = Target:GetUserId()
		local Changed, Reason = SetEnemyGroupTarget( self, Client, TargetID, true, "command" )
		if Changed then
			return
		elseif Reason == "full" then
			Shine:NotifyColour( Client, 255, 80, 80, StringFormat( "Enemy group is full (%s max). Remove your current enemy first.",
				tostring( ( GetConfig( self ).EnemyGroups or {} ).MaxEnemyGroupSize or 1 ) ) )
		elseif Reason == "self" then
			Shine:NotifyColour( Client, 255, 80, 80, "You cannot add yourself to your enemy group." )
		else
			Shine:NotifyColour( Client, 255, 200, 100, "Enemy group was not changed." )
		end
	end

	local AddCommand = self:BindCommand( "sh_enemygroup_add", "enemyadd", AddEnemy, true )
	AddCommand:AddParam{ Type = "client", IgnoreCanTarget = true }
	AddCommand:Help( "Adds a connected player to your VoteRandom enemy group." )

	local function RemoveEnemy( Client, Target )
		if not Client or not Target then return end
		local TargetID = Target:GetUserId()
		SetEnemyGroupTarget( self, Client, TargetID, false, "command" )
	end

	local RemoveCommand = self:BindCommand( "sh_enemygroup_remove", "enemyremove", RemoveEnemy, true )
	RemoveCommand:AddParam{ Type = "client", IgnoreCanTarget = true }
	RemoveCommand:Help( "Removes a connected player from your VoteRandom enemy group." )

	local function ClearEnemyGroup( Client )
		if not Client then return end
		local OwnerID = Client:GetUserId()
		EnemyGroups[ tostring( OwnerID ) ] = nil
		SendEnemyGroupState( self, Client, 0, false )
		WriteEnemyGroupAudit( self, "enemy_group_cleared", OwnerID, nil, "command" )
		Shine:NotifyColour( Client, 255, 200, 100, "Enemy group cleared." )
	end

	local ClearCommand = self:BindCommand( "sh_enemygroup_clear", "enemyclear", ClearEnemyGroup, true )
	ClearCommand:Help( "Clears your VoteRandom enemy group." )
end

local function MigrateVoteRandomEnhanceConfig( self )
	self.Config = self.Config or {}
	local Config = self.Config.VoteRandomEnhance
	if type( Config ) ~= "table" then
		Config = {}
		self.Config.VoteRandomEnhance = Config
	end
	local Changed = false
	Config.Optimiser = type( Config.Optimiser ) == "table" and Config.Optimiser or {}
	if Config.Optimiser.Starts == nil and type( Config.Variety ) == "table" and Config.Variety.MinIterations ~= nil then
		local LegacyStarts = tonumber( Config.Variety.MinIterations )
		-- Five was the old source default, so migrate that known default to the
		-- new ten-start policy while preserving genuinely customised values.
		Config.Optimiser.Starts = LegacyStarts == 5 and 10 or LegacyStarts or 10
		Changed = true
	end
	Config.AutoShuffle = type( Config.AutoShuffle ) == "table" and Config.AutoShuffle or {}
	if Config.AutoShuffle.MinimumHumans == nil and self.Config.AutoShuffleAtRoundStartPlayerMin ~= nil then
		Config.AutoShuffle.MinimumHumans = tonumber( self.Config.AutoShuffleAtRoundStartPlayerMin ) or 14
		Changed = true
	end
	Config.Streaks = type( Config.Streaks ) == "table" and Config.Streaks or {}
	if Config.Streaks.GraceRounds == 2 and Config.Streaks.WeightScale == 1 then
		-- v5 source default; v6 is grace 1 / scale 3 (shuffle_implementation.md §14).
		Config.Streaks.GraceRounds = 1
		Config.Streaks.WeightScale = 3
		Changed = true
	end
	Config.AuditLog = type( Config.AuditLog ) == "table" and Config.AuditLog or {}
	if Config.AuditLog.FilePath == nil or Config.AuditLog.FilePath == ""
		or Config.AuditLog.FilePath == "config://shine/logs/shuffle3.txt"
		or Config.AuditLog.FilePath == "config://shine/logs/shuffle4.txt"
		or Config.AuditLog.FilePath == "config://shine/logs/shuffle4"
		or Config.AuditLog.FilePath == "config://shine/logs/shuffle4/"
		or Config.AuditLog.FilePath == "config://shine/logs/shuffle5"
		or Config.AuditLog.FilePath == "config://shine/logs/shuffle5/" then
		Config.AuditLog.FilePath = "config://shine/logs/shuffle6"
		Changed = true
	end
	if Changed and type( self.SaveConfig ) == "function" then self:SaveConfig() end
end

function Plugin:InstallVoteRandomEnhancePatch()
	MigrateVoteRandomEnhanceConfig( self )
	if PatchState.Installed then
		local VoteRandom = Shine.Plugins and Shine.Plugins[ "voterandom" ]
		if VoteRandom then ApplyPatches( self, VoteRandom ) end
		return GetConfig( self ).Enabled
	end

	if not GetConfig( self ).Enabled then
		if self.InstallVoteRandomAutoShufflePatch then
			self:InstallVoteRandomAutoShufflePatch()
		end
		return false
	end

	PatchState.Installed = true
	ResetAuditState()
	WriteAuditEvent( self, Shine.Plugins and Shine.Plugins[ "voterandom" ], "audit_session_started", {
		implementationVersion = PatchImplementationVersion,
		auditSchemaVersion = AuditSchemaVersion,
		expectedVoteRandomVersion = ( GetConfig( self ).Compatibility or {} ).ExpectedVoteRandomVersion,
		ratingSource = "player_skill_fields",
		optimiserConfig = GetConfig( self ).Optimiser,
		auditConfig = GetConfig( self ).AuditLog,
		predictionConfig = GetConfig( self ).EloPrediction
	}, false )
	LoadEnemyGroups( self )
	LoadStreakHistory()
	RegisterCommands( self )
	Shine.Hook.Remove( "ClientConnect", EnemyGroupClientConnectHook )
	Shine.Hook.Add( "ClientConnect", EnemyGroupClientConnectHook, function( Client )
		SyncEnemyGroupState( self, Client )
	end )
	Shine.Hook.Remove( "ClientDisconnect", EnemyGroupClientDisconnectHook )
	Shine.Hook.Add( "ClientDisconnect", EnemyGroupClientDisconnectHook, function( Client )
		if not Client or ( Client.GetIsVirtual and Client:GetIsVirtual() ) then return end
		RemoveDisconnectedEnemyPlayer( self, Client.GetUserId and Client:GetUserId() )
	end )
	Shine.Hook.Remove( "MapChange", EnemyGroupMapChangeHook )
	Shine.Hook.Add( "MapChange", EnemyGroupMapChangeHook, function()
		SaveEnemyGroups()
		Print( "[enemygroup] Saved enemy groups for map change." )
	end )
	ScheduleEnemyGroupRestorePrune( self )
	local ConnectedClients = Shine.GetAllClients and Shine.GetAllClients() or {}
	for i = 1, #ConnectedClients do
		SyncEnemyGroupState( self, ConnectedClients[ i ] )
	end

	Shine.Hook.Remove( "OnPluginLoad", PatchHookName )
	Shine.Hook.Add( "OnPluginLoad", PatchHookName, function( Name, LoadedPlugin )
		if Name ~= "voterandom" then return end
		ApplyPatches( self, LoadedPlugin )
	end )

	local VoteRandom = Shine.Plugins and Shine.Plugins[ "voterandom" ]
	if VoteRandom then
		ApplyPatches( self, VoteRandom )
	end

	return true
end

function Plugin:CleanupVoteRandomEnhancePatch()
	Shine.Hook.Remove( "ClientConnect", EnemyGroupClientConnectHook )
	Shine.Hook.Remove( "ClientDisconnect", EnemyGroupClientDisconnectHook )
	Shine.Hook.Remove( "MapChange", EnemyGroupMapChangeHook )
	Shine.Timer.Destroy( EnemyGroupRestoreTimerName )
	Shine.Hook.Remove( "OnPluginLoad", PatchHookName )
	WriteAuditEvent( self, Shine.Plugins and Shine.Plugins[ "voterandom" ], "audit_session_ended", {
		droppedEvents = AuditState.DroppedEvents,
		lastError = AuditState.LastError
	}, false )
	for VRPlugin in pairs( PatchState.PatchedPlugins ) do
		RestorePatches( VRPlugin )
		PatchState.PatchedPlugins[ VRPlugin ] = nil
	end
	PatchState.Installed = false
	PatchState.Patches = {}
	StagedShuffle = nil
	StagedAudit = nil
	ActiveAuditRound = nil
	CloseAuditLog()
	self.MNGAVoteRandomEnhanceCommandsRegistered = nil
end
