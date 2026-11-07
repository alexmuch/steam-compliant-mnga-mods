local JSON = require "shine/lib/json"

local Plugin = Shine.Plugin( ... )

Plugin.HasConfig = true
Plugin.PrintName = "mngaadministration"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.CheckConfigRecursively = true
Plugin.ConfigName = "mngaadministration.json"
Plugin.DefaultState = false

Plugin.DefaultConfig = {
	-- seeding system
	-- Opt-in diagnostics for the bot-management system.
	mngaBotsDebug = false,
	botMode = "manga",
	vanillaMaxBots = 26,
	botDifficultyProfile = "easy",
	botDifficultyProfiles = {
		easy = {
			AimTier = 1, AccuracyCap = 15, MarineMissOffsetMultiplier = 2,
			TargetAcquisitionDelay = 1,
			SkulkTargetRange = 25, SkulkBiteGateRange = 1.5,
			SkulkBiteAttemptChance = 0.5, SkulkBiteDecisionInterval = 0.65,
			SkulkRemoveJump = true, SkulkForceForward = true
		},
		normal = {
			AimTier = 3, AccuracyCap = 25, MarineMissOffsetMultiplier = 1.5,
			TargetAcquisitionDelay = 0.6,
			SkulkTargetRange = 25, SkulkBiteGateRange = 1.5,
			SkulkBiteAttemptChance = 0.7, SkulkBiteDecisionInterval = 0.4,
			SkulkRemoveJump = true, SkulkForceForward = true
		},
		hard = {
			AimTier = 5, AccuracyCap = 35, MarineMissOffsetMultiplier = 1.2,
			TargetAcquisitionDelay = 0.3,
			SkulkTargetRange = 25, SkulkBiteGateRange = 1.5,
			SkulkBiteAttemptChance = 0.85, SkulkBiteDecisionInterval = 0.2,
			SkulkRemoveJump = true, SkulkForceForward = true
		}
	},
	seedingGameThreshold = 14,
	smallGameThreshold = 18,

	autoStartThreshold = 14,
	AutoShuffleAtRoundStartPlayerMin = 14,

	seedingMaxBotCount = 26,
	smallGameMaxBotCount = 20,
	standardMaxBotCount = 4,

	-- Field-bot hysteresis is derived from seedingGameThreshold and
	-- smallGameThreshold with a one-player buffer around each boundary.
	botAdjustmentInterval = 0.5,

	-- Legacy knobs kept for config compatibility. Field bots are now always
	-- drain-only once the game reaches Started; leavers do not trigger refills.
	criticalBotThreshold = 8,
	inProgressGraceTime = 35,

	alientopupres = 100,
	-- Team resource banks assigned when a low-population seeded round starts.
	seededMarineTeamStartResources = 150,
	seededAlienTeamStartResources = 160,
	-- Seconds that seeded starts retain instant construction after countdown begins.
	seededInstantBuildDuration = 50,
	seededHumanStartResources = 100,
	seededBotStartResources = 50,
	humanTickResources = 10,

	readdComBot = true,
	commBotHumanThreshold = 10,
	-- xpsystem
	xpsystem = false,
	xpCentralURL = "http://127.0.0.1:25386",
	xpServerID = "manga-primary",
	xpSharedSecret = "",

	-- Chat lines for !rules. Empty shows the built-in MaNGA rules.
	rulesLines = {},

	-- When true, the map vote hides live vote tallies (both the menu tile
	-- counts and the chat "(N votes for this, M total)" text) and instead just
	-- announces that a player has voted. Stops players from dog-piling whichever
	-- map is currently winning. Toggle at runtime with sh_hidevotes.
	hideMapVoteCounts = false,

	SpectatorAllChatLimit = {
		Enabled = true,
		AllowedQueuedSpectators = 5,
		AdminBypassPermission = "mnga.spectatorchat.bypass",
		NotifyCooldown = 10
	},

	SpectatorDrawing = {
		Enabled = true,
		Debug = false,
		DebugSegments = false,
		SampleRateHz = 12,
		LocalSampleRateHz = 24,
		StrokeThickness = 1,
		MaxSegmentsPerChannel = 600,
		HistoryBatchCount = 3,
		MaxPointsPerStroke = 64,
		MinimumPointDistance = 0.05,
		MaximumSegmentLength = 20,
		MaximumTraceDistance = 1000,
		-- Project cursor rays onto one horizontal NS2 world plane.
		-- NS2 uses Y as its vertical axis. The legacy absolute height is now
		-- only the fallback when a map has no Tech Points.
		DrawingPlaneHeight = 0,
		DrawingPlaneHeightOffset = 0,
		DrawingPlaneHeightOverrides = Shine.IgnoreWhenChecking( JSON.Object() ),
		HistoryReplayRate = 90,
		SlotIdleTimeout = 60,
		BannedUsers = Shine.IgnoreWhenChecking( JSON.Object() )
	},

	QueuePromotionTimeout = {
		Enabled = true,
		Timeout = 20
	},

	RoundStartBaseAFK = {
		Enabled = true,
		Debug = false,
		CheckTime = 40,
		TrackInterval = 1
	},

	SharedBans = {
		-- Shounen only: exact-IP ban correlation on top of stock Shine web bans. Keep off on MaNGA.
		Enabled = false,
		-- Crash test only, leave off: sends one request during map load, which can crash the server.
		LoadHTTPProbe = false
	},

	VoteRandomEnhance = {
		Enabled = true,
		Debug = true,
		Compatibility = {
			ExpectedVoteRandomVersion = "2.12",
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
		AuditLog = {
			-- File-only trace of shuffle candidates, predictions and outcomes.
			-- Each map load creates one fresh file under this directory.
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
			-- Personal social-cost budget before dividing by the owner's current
			-- friend-group size (including the owner).
			Weighting = 50
		},

		-- Donator shuffle priority (.claude/docs/shuffle_implementation.md §5.8).
		-- Tier = highest TierGroups entry reached through the user's group InheritsFrom chain.
		Supporters = {
			Enabled = true,
			TierGroups = {
				[ "Server Supporter" ] = 1,
				[ "Server Supporter 2" ] = 2,
				[ "Server Supporter 3" ] = 3
			},
			-- Added to the stated-preference weight (normal ~3; a twice-denied streak is 24).
			PreferenceBonus = { 5, 10, 15 },
			-- Replaces EnemyGroups.Weighting for groups the supporter owns (still / friend-group size).
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
			-- Keep these values in lock-step with ns2py/nselo2/config_nselo2.json.
			-- The service stores the model version/parameters with every round.
			Enabled = true,
			ModelVersion = "field_commander_logit_v3",
			CutoverDate = "2026-07-14",
			LogitScale = 400,
			MarineWinBiasLogit = 0,
			CommanderPredictionWeight = 0.1,
			MaxStockCostDelta = 5,
			SimilarityTieBreak = true
		}
	},

	-- Steam ID string -> { Name, UnbanTime, Reason }. Used by the vanilla
	-- vote-call-ban vote to persist one-hour vote-start restrictions across
	-- map changes.
	VoteCallBanned = Shine.IgnoreWhenChecking( JSON.Object() )
}

function Plugin:SetupDataTable()
	-- One client-persisted volume preference shared by MNGA mini-games.
	self:AddNetworkMessage( "MangaVolumeState", {
		Volume = "integer (0 to 100)"
	}, "Client" )
	self:AddNetworkMessage( "MangaSizeState", {
		Size = "integer (30 to 120)"
	}, "Client" )
	self:AddNetworkMessage( "MangaOpacityState", {
		Opacity = "integer (30 to 100)"
	}, "Client" )

	-- Enemy groups are owned by the server, but the scoreboard needs the local
	-- player's one-entry state to render its action and red row safely.
	self:AddNetworkMessage( "EnemyGroupAction", {
		TargetSteamID = "integer",
		Action = "integer (1 to 2)"
	}, "Server" )
	self:AddNetworkMessage( "EnemyGroupRequestSync", {}, "Server" )
	self:AddNetworkMessage( "EnemyGroupState", {
		TargetSteamID = "integer",
		IsEnemy = "boolean"
	}, "Client" )

	self:AddNetworkMessage( "PregameCountdownAttention", {
		Duration = "integer"
	}, "Client" )
	self:AddNetworkMessage( "QueuePromotionAttention", {}, "Client" )
	self:AddNetworkMessage( "SilentSeedingXPNotification", {
		Message = "string (128)"
	}, "Client" )

	-- Shared spectator world drawing. Live segments are deliberately compact;
	-- the server supplies authoritative epochs/generations for retained history.
	self:AddNetworkMessage( "SpecDrawRequestState", {}, "Server" )
	self:AddNetworkMessage( "SpecDrawRequestSlot", {
		Slot = "integer (1 to 4)",
		Claim = "boolean"
	}, "Server" )
	self:AddNetworkMessage( "SpecDrawRequestReceive", {
		Enabled = "boolean"
	}, "Server" )
	self:AddNetworkMessage( "SpecDrawResumeBatch", {
		Slot = "integer (1 to 4)",
		Epoch = "integer (0 to 2147483647)",
		Generation = "integer (1 to 2147483647)",
		SegmentCount = "integer (0 to 2400)",
		LastSequence = "integer (0 to 2147483647)"
	}, "Server" )
	self:AddNetworkMessage( "SpecDrawSubmitSegment", {
		Slot = "integer (1 to 4)",
		Stroke = "integer (0 to 65535)",
		ClientSequence = "integer (0 to 2147483647)",
		StartPoint = "vector",
		EndPoint = "vector"
	}, "Server" )
	self:AddNetworkMessage( "SpecDrawRequestClear", {
		Slot = "integer (1 to 4)"
	}, "Server" )

	self:AddNetworkMessage( "SpecDrawConfig", {
		Enabled = "boolean",
		SampleRateHz = "integer (2 to 30)",
		LocalSampleRateHz = "integer (2 to 60)",
		StrokeThickness = "integer (1 to 7)",
		MaxPointsPerStroke = "integer (2 to 512)",
		MaximumTraceDistance = "integer (10 to 2000)",
		DrawingPlaneHeight = "integer (-1000 to 1000)"
	}, "Client" )
	self:AddNetworkMessage( "SpecDrawSlotState", {
		Slot = "integer (1 to 4)",
		OwnerId = "integer",
		OwnerName = "string (32)"
	}, "Client" )
	self:AddNetworkMessage( "SpecDrawReceiveState", {
		Enabled = "boolean",
		Synchronizing = "boolean"
	}, "Client" )
	self:AddNetworkMessage( "SpecDrawSnapshotBegin", {
		SegmentCount = "integer (0 to 9600)"
	}, "Client" )
	self:AddNetworkMessage( "SpecDrawSnapshotChannel", {
		Slot = "integer (1 to 4)",
		Epoch = "integer (1 to 2147483647)",
		Generation1 = "integer (0 to 2147483647)",
		Generation2 = "integer (0 to 2147483647)",
		Generation3 = "integer (0 to 2147483647)"
	}, "Client" )
	self:AddNetworkMessage( "SpecDrawSnapshotEnd", {}, "Client" )
	self:AddNetworkMessage( "SpecDrawSegment", {
		Slot = "integer (1 to 4)",
		Epoch = "integer (1 to 2147483647)",
		Generation = "integer (1 to 2147483647)",
		Sequence = "integer (1 to 2147483647)",
		Stroke = "integer (0 to 65535)",
		ClientSequence = "integer (0 to 2147483647)",
		StartPoint = "vector",
		EndPoint = "vector"
	}, "Client" )
	self:AddNetworkMessage( "SpecDrawBatchDrop", {
		Slot = "integer (1 to 4)",
		Epoch = "integer (1 to 2147483647)",
		Generation = "integer (1 to 2147483647)"
	}, "Client" )
	self:AddNetworkMessage( "SpecDrawChannelClear", {
		Slot = "integer (1 to 4)",
		Epoch = "integer (1 to 2147483647)"
	}, "Client" )
end

-- M-menu third person toggle (vanilla "thirdperson" needs sv_cheats). Allowed for living
-- ready-room players at any time, and for living team players before the round. Round start
-- needs no cleanup: ResetGame -> Player:Reset() zeroes cameraDistance before respawning teams.
Plugin.ThirdPersonDistance = 3

function Plugin.GetThirdPersonBlockReason( Player, GameState )
	if not Player or not HasMixin( Player, "CameraHolder" ) then return "No player." end
	if Player:isa( "Spectator" ) or Player:isa( "Commander" ) or Player:isa( "Embryo" )
	or Player:isa( "ReadyRoomEmbryo" ) then
		return "Third person is not available right now."
	end
	if not Player:GetIsAlive() then return "You must be alive." end

	local Team = Player:GetTeamNumber()
	if Team == kTeamReadyRoom then return nil end
	if ( Team == kTeam1Index or Team == kTeam2Index ) and ( GameState == kGameState.NotStarted
	or GameState == kGameState.WarmUp or GameState == kGameState.PreGame ) then
		return nil
	end
	return "Third person only works in the ready room or before the round starts."
end

return Plugin
