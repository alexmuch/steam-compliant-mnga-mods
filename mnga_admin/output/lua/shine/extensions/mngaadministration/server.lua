local Plugin, PluginName = ...
local Shine = Shine
local StringFormat = string.format

PluginName = PluginName or Plugin:GetName()

Shine.LoadPluginFile( PluginName, "server/xp.lua", Plugin )
Shine.LoadPluginFile( PluginName, "server/seeding.lua", Plugin )
Shine.LoadPluginFile( PluginName, "server/commands.lua", Plugin )
Shine.LoadPluginFile( PluginName, "server/player_events.lua", Plugin )
Shine.LoadPluginFile( PluginName, "server/round_stats.lua", Plugin )
Shine.LoadPluginFile( PluginName, "server/round_start_base_afk.lua", Plugin )
Shine.LoadPluginFile( PluginName, "server/queue_promotion_timeout.lua", Plugin )
Shine.LoadPluginFile( PluginName, "server/shared_bans.lua", Plugin )
Shine.LoadPluginFile( PluginName, "server/voterandom_enhance.lua", Plugin )
Shine.LoadPluginFile( PluginName, "server/integrations.lua", Plugin )
Shine.LoadPluginFile( PluginName, "server/spectator_chat.lua", Plugin )
Shine.LoadPluginFile( PluginName, "server/spectator_drawing.lua", Plugin )
Shine.LoadPluginFile( PluginName, "server/manga_volume.lua", Plugin )
Shine.LoadPluginFile( PluginName, "server/manga_size.lua", Plugin )
Shine.LoadPluginFile( PluginName, "server/manga_opacity.lua", Plugin )
Shine.LoadPluginFile( PluginName, "server/blocked_minigames.lua", Plugin )

local function ApplyConfig( self )
	gMNGAAdministrationPlugin = self
	self.MNGABotsDebug = self.Config.mngaBotsDebug == true
	local RequestedMode = string.lower( tostring( self.Config.botMode or "manga" ) )
	if RequestedMode ~= "manga" and RequestedMode ~= "vanilla" then
		Print( "[mngabots] invalid botMode=%s; falling back to manga", tostring( RequestedMode ) )
		RequestedMode = "manga"
	end
	self.BotMode = RequestedMode
	gMNGABotMode = RequestedMode
	gMNGAAdministrationPlugin = self
	self.VanillaMaxBots = math.max( 0, math.floor( tonumber( self.Config.vanillaMaxBots ) or 26 ) )
	self.BotDifficultyProfiles = self.Config.botDifficultyProfiles or {}
	self.ConfiguredBotDifficultyProfile = string.lower( tostring( self.Config.botDifficultyProfile or "easy" ) )

	seedingGameThreshold = self.Config.seedingGameThreshold
	smallGameThreshold = self.Config.smallGameThreshold

	autoStartThreshold = self.Config.autoStartThreshold

	seedingMaxBotCount = self.Config.seedingMaxBotCount
	smallGameMaxBotCount = self.Config.smallGameMaxBotCount
	standardMaxBotCount = self.Config.standardMaxBotCount
	botAdjustmentInterval = self.Config.botAdjustmentInterval or 2
	criticalBotThreshold = self.Config.criticalBotThreshold
	inProgressGraceTime = self.Config.inProgressGraceTime
	alientopupres = self.Config.alientopupres
	seededMarineTeamStartResources = self.Config.seededMarineTeamStartResources or 150
	seededAlienTeamStartResources = self.Config.seededAlienTeamStartResources or 160
	seededInstantBuildDuration = self.Config.seededInstantBuildDuration or 50
	seededHumanStartResources = self.Config.seededHumanStartResources or 100
	seededBotStartResources = self.Config.seededBotStartResources or 50
	humanTickResources = self.Config.humanTickResources or 10
	xpsystem = self.Config.xpsystem

	readdComBot = self.Config.readdComBot
	commBotHumanThreshold = self.Config.commBotHumanThreshold or 10

	self.HideMapVoteCounts = self.Config.hideMapVoteCounts
	if self.ApplySpectatorAllChatLimitConfig then
		self:ApplySpectatorAllChatLimitConfig()
	end

	Print(
		"[mngabots] config botMode=%s vanillaMaxBots=%s difficulty=%s seeding=%s small=%s standard=%s lowUp=%s lowDown=%s offUp=%s mediumDown=%s interval=%s commThreshold=%s marineTeamStartRes=%s alienTeamStartRes=%s instantBuildDuration=%s humanStartRes=%s botStartRes=%s humanTickRes=%s",
		tostring( self.BotMode ), tostring( self.VanillaMaxBots ), tostring( self.ConfiguredBotDifficultyProfile ),
		tostring( seedingMaxBotCount ), tostring( smallGameMaxBotCount ), tostring( standardMaxBotCount ),
		tostring( ( seedingGameThreshold or 14 ) + 1 ), tostring( ( seedingGameThreshold or 14 ) - 1 ),
		tostring( ( smallGameThreshold or 18 ) + 1 ), tostring( ( smallGameThreshold or 18 ) - 1 ),
		tostring( botAdjustmentInterval ),
		tostring( commBotHumanThreshold ),
		tostring( seededMarineTeamStartResources ), tostring( seededAlienTeamStartResources ),
		tostring( seededInstantBuildDuration ),
		tostring( seededHumanStartResources ), tostring( seededBotStartResources ),
		tostring( humanTickResources )
	)
end

function Plugin:ApplyBotDifficultyProfile( ProfileName, Reason )
	ProfileName = string.lower( tostring( ProfileName or "" ) )
	local Profile = self.BotDifficultyProfiles and self.BotDifficultyProfiles[ ProfileName ]
	if not Profile then return false end

	local Sanitized = {
		AimTier = math.max( 1, math.min( 7, math.floor( tonumber( Profile.AimTier ) or 1 ) ) ),
		AccuracyCap = math.max( 0, math.min( 100, tonumber( Profile.AccuracyCap ) or 15 ) ),
		MarineMissOffsetMultiplier = math.max( 1, tonumber( Profile.MarineMissOffsetMultiplier ) or 2 ),
		TargetAcquisitionDelay = math.max( 0, tonumber( Profile.TargetAcquisitionDelay ) or 1 ),
		SkulkTargetRange = math.max( 0, tonumber( Profile.SkulkTargetRange ) or 25 ),
		SkulkBiteGateRange = math.max( 0, tonumber( Profile.SkulkBiteGateRange ) or 1.5 ),
		SkulkBiteAttemptChance = math.max( 0, math.min( 1, tonumber( Profile.SkulkBiteAttemptChance ) or 0.5 ) ),
		SkulkBiteDecisionInterval = math.max( 0, tonumber( Profile.SkulkBiteDecisionInterval ) or 0.65 ),
		SkulkRemoveJump = Profile.SkulkRemoveJump ~= false,
		SkulkForceForward = Profile.SkulkForceForward ~= false
	}

	self.ActiveBotDifficultyProfile = ProfileName
	self.ActiveBotTuning = Sanitized
	gMNGABotTuning = Sanitized
	gSkillTierOverride = Sanitized.AimTier
	Print(
		"[mngabots] difficulty profile=%s reason=%s tier=%d cap=%.1f missMultiplier=%.2f acquisition=%.2f skulkRange=%.1f biteGate=%.1f biteChance=%.2f biteInterval=%.2f removeJump=%s forceForward=%s",
		ProfileName, tostring( Reason or "unspecified" ), Sanitized.AimTier, Sanitized.AccuracyCap,
		Sanitized.MarineMissOffsetMultiplier, Sanitized.TargetAcquisitionDelay,
		Sanitized.SkulkTargetRange, Sanitized.SkulkBiteGateRange,
		Sanitized.SkulkBiteAttemptChance, Sanitized.SkulkBiteDecisionInterval,
		 tostring( Sanitized.SkulkRemoveJump ), tostring( Sanitized.SkulkForceForward ) )
	return true
end

function Plugin:Initialise()
	self.Enabled = true
	self:CreateCommands()
	ApplyConfig( self )
	if not self:ApplyBotDifficultyProfile( self.ConfiguredBotDifficultyProfile, "plugin initialise" ) then
		Print( "[mngabots] configured difficulty profile '%s' missing; falling back to easy",
			tostring( self.ConfiguredBotDifficultyProfile ) )
		self.ConfiguredBotDifficultyProfile = "easy"
		self:ApplyBotDifficultyProfile( "easy", "missing configured profile fallback" )
	end
	self:InstallVoteSurrenderLastVotePatch()
	self:InstallBaseCommandsStopVotePatch()
	self:InstallVoteRandomEnhancePatch()
	self:InitialiseSpectatorDrawing()
	self:InitialiseMangaVolume()
	self:InitialiseMangaSize()
	self:InitialiseMangaOpacity()
	self:InitialiseBlockedMinigames()
	self:InitialiseSharedBans()
	if self.InstallPregameCountdownAttentionPatch then
		self:InstallPregameCountdownAttentionPatch()
	else
		Print( "[mngaadministration] PregameCountdownAttention patch not found; skipping install." )
	end

	return true
end

function Plugin:Cleanup()
	if self.CleanupMNGARateTrial then
		self:CleanupMNGARateTrial()
	end
	if gMNGAAdministrationPlugin == self then
		gMNGAAdministrationPlugin = nil
	end
	if self.CleanupVoteRandomEnhancePatch then
		self:CleanupVoteRandomEnhancePatch()
	end
	if self.CleanupSpectatorDrawing then
		self:CleanupSpectatorDrawing()
	end
	self:CleanupMangaVolume()
	self:CleanupMangaSize()
	self:CleanupMangaOpacity()
	self:CleanupBlockedMinigames()
	self:CleanupSharedBans()
	Shine.Hook.Remove( "OnPluginLoad", self.VoteRandomAutoShufflePatchHook or "MNGAAdministrationVoteRandomAutoShufflePatch" )
	Shine.Hook.Remove( "OnPluginLoad", self.VoteSurrenderLastVotePatchHook or "MNGAAdministrationVoteSurrenderLastVotePatch" )
	Shine.Hook.Remove( "OnPluginLoad", self.BaseCommandsStopVotePatchHook or "MNGAAdministrationBaseCommandsStopVotePatch" )
	Shine.Hook.Remove( "OnPluginLoad", self.PregameCountdownAttentionPatchHook or "MNGAAdministrationPregameCountdownAttentionPatch" )
	Shine.Timer.Destroy( "mnga_tick" )
	Shine.Timer.Destroy( "mnga_bot_adjust" )
	Shine.Timer.Destroy( "mnga_bot_reconcile" )
	Shine.Timer.Destroy( "mnga_bot_force_join" )
	Shine.Timer.Destroy( "mnga_mapvote_results_postload" )
	self:StopRoundStartBaseAFKCheck()
	self:ClearQueuePromotionTimeouts( "plugin cleanup" )
	if self.CleanupSpectatorAllChatLimit then
		self:CleanupSpectatorAllChatLimit()
	end
	self.BaseClass.Cleanup( self )
end

return Plugin
