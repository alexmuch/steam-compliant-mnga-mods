local Plugin = ...
local Shine = Shine
local StringFormat = string.format
local defaultMaps = {"co_core", "co_sava", "co_pulse", "co_angst"};

local function isDefaultMap()
  -- Any combat map counts as the empty-server map
  return string.sub(Shared.GetMapName() or "", 1, 3) == "co_";
end

local function getDefaultMap()
  return table.random(defaultMaps);
end

local function MakeTechEnt( techPoint, mapName, rightOffset, forwardOffset, teamType )
	local origin = techPoint:GetOrigin()
	local right = techPoint:GetCoords().xAxis
	local forward = techPoint:GetCoords().zAxis
	local position = origin + right * rightOffset + forward * forwardOffset

	local newEnt = CreateEntity( mapName, position, teamType)
	if HasMixin( newEnt, "Construct" ) then
		SetRandomOrientation( newEnt )
		newEnt:SetConstructionComplete() 
	end

	if HasMixin( newEnt, "Live" ) then
		newEnt:SetIsAlive(true)
	end

end

local function SpawnBuildings( team )
	local teamNr = team:GetTeamNumber()
	local techPoint = team:GetInitialTechPoint()

	if team:GetTeamType() == kAlienTeamType then
		MakeTechEnt( techPoint, Crag.kMapName, 3.5, 2, teamNr )
		-- MakeTechEnt( techPoint, Shade.kMapName, -3.5, 2, teamNr )
	else
		-- MakeTechEnt(techPoint, MAC.kMapName, 3.5, 2, teamNr)
		MakeTechEnt(techPoint, InfantryPortal.kMapName, 3.5, 2, teamNr)
		MakeTechEnt(techPoint, Armory.kMapName, 3.5, -2, teamNr)
		-- MakeTechEnt(techPoint, ArmsLab.kMapName, -3.5, 2, teamNr)
		MakeTechEnt(techPoint, PrototypeLab.kMapName, -3.5, -2, teamNr)
	end
end

local function IsPlayingTeam( TeamNumber )
	return TeamNumber == kTeam1Index or TeamNumber == kTeam2Index
end

local function DisableBaseBotController( BotController )
	if not BotController then return end
	if gMNGABotMode == "vanilla" then
		BotController.updateLock = 999
		return
	end

	-- Keep vanilla BotTeamController from reacting to JoinTeam/disconnect and
	-- doing bulk back-fill/removal. MaxBots=0 makes vanilla purge bots during
	-- JoinTeam/state updates, so keep a high target and hold its update lock.
	BotController.MaxBots = 64
	BotController.updateLock = 999
end

local function GetBotCountsForTeam( BotController, TeamNumber )
	if not BotController then return 0, 0 end

	local Humans, Bots = BotController:GetPlayerNumbersForTeam( TeamNumber )
	return Humans or 0, Bots or 0
end

local function IsRealPlayer( Player )
	return Player and Player.GetIsVirtual and not Player:GetIsVirtual()
end

-- NS20K deliberately owns the complete commanderless round-start sequence.
-- Test this dynamically rather than at file load so mod/Shine load order cannot
-- make the integration depend on which package initialised first.
local function IsNS20KStartOwner()
	return type( NS20KIsEnabled ) == "function"
		and NS20KIsEnabled( "CommanderlessStart" ) == true
end

-- NS2 Combat v2 (sourcecombatv2) repurposes personal resources as upgrade points and
-- runs its own round start, so the MNGA seeded start, commander bots and the per-tick
-- resource drip must never run there. The combat mod sets gCombatModeActive in its
-- FileHooks, before any game file or plugin loads. Field-bot management is kept.
function Plugin:UseCombatStartOwner()
	local Enabled = gCombatModeActive == true
	if Enabled and not self.CombatStartHandoffLogged then
		self.CombatStartHandoffLogged = true
		Print( "[mngabots] combat mode active: field-bot management retained; commander bots, seeded start and resource grants disabled" )
	end
	return Enabled
end

-- NS2 Combat v2 fills bots itself with the plain vanilla BotTeamController (Combat.json ModBotsPerTeam), so
-- every MNGA bot-controller path (fill timer, update lock, sv_maxbots, round-end hard-off) stands down there.
function Plugin:CombatOwnsBots()
	local Enabled = gCombatModeActive == true
	if Enabled and not self.CombatBotsHandoffLogged then
		self.CombatBotsHandoffLogged = true
		Print( "[mngabots] combat mode active: bot management handed to the combat mod (vanilla controller)" )
	end
	return Enabled
end

function Plugin:UseNS20KStartOwner()
	local Enabled = IsNS20KStartOwner()
	if Enabled and not self.NS20KStartHandoffLogged then
		self.NS20KStartHandoffLogged = true
		Print( "[mngabots] NS20K start handoff active: field-bot management retained; commander bots and MNGA seeded start disabled" )
	end
	return Enabled
end

function Plugin:CountNonSpectatingHumans()
	local Clients, Count = Shine.GetAllClients()
	local Humans = 0

	for i = 1, Count do
		local Client = Clients[ i ]
		if Client and not Client:GetIsVirtual()
		and ( not Client.GetIsSpectator or not Client:GetIsSpectator() ) then
			Humans = Humans + 1
		end
	end

	return Humans
end

function Plugin:GetPopulationHumanCount()
	return self:CountNonSpectatingHumans()
end

function Plugin:GrantHumanTickResources( Reason )
	if self:UseCombatStartOwner() then return end
	local Amount = tonumber( humanTickResources ) or 0
	if Amount <= 0 then return end

	local HumanCount = self:GetPopulationHumanCount()
	local SeedingThreshold = seedingGameThreshold or 14
	if HumanCount >= SeedingThreshold then
		return
	end

	local Players = GetEntities( "Player" )
	for i = 1, #Players do
		local Player = Players[ i ]
		if IsRealPlayer( Player ) and Player.GetResources and Player.SetResources then
			Player:SetResources( Player:GetResources() + Amount )
		end
	end
end

function Plugin:SetSeededStartResources()
	if self:UseCombatStartOwner() then return end
	local HumanResources = tonumber( seededHumanStartResources ) or 100
	local BotResources = tonumber( seededBotStartResources ) or 50
	local Humans = 0
	local Bots = 0

	local Players = GetEntities( "Player" )
	for i = 1, #Players do
		local Player = Players[ i ]
		if Player and Player.SetResources then
			if IsRealPlayer( Player ) then
				Player:SetResources( HumanResources )
				Humans = Humans + 1
			else
				Player:SetResources( BotResources )
				Bots = Bots + 1
			end
		end
	end

	Print( "%s", StringFormat( "[mngabots] seeded start pres humans=%d humanRes=%s bots=%d botRes=%s",
		Humans, tostring( HumanResources ), Bots, tostring( BotResources ) ) )
end

function Plugin:ForcePendingBotsToTeams()
	local Gamerules = GetGamerules()
	if not Gamerules or not gServerBots then return end

	for _, Bot in ipairs( gServerBots ) do
		if Bot and Bot.team and IsPlayingTeam( Bot.team ) then
			local Player = Bot.GetPlayer and Bot:GetPlayer()
			if Player and Player.GetTeamNumber and Player:GetTeamNumber() == kTeamReadyRoom then
				Gamerules:JoinTeam( Player, Bot.team, true )
			end
		end
	end
end

function Plugin:ScheduleBotForceJoin()
	if self:CombatOwnsBots() then return end
	if self.BotForceJoinPending then return end

	self.BotForceJoinPending = true
	Shine.Timer.Destroy( "mnga_bot_force_join" )
	Shine.Timer.Create( "mnga_bot_force_join", 0.5, 1, function()
		self.BotForceJoinPending = false
		if not self.Enabled then return end

		local Gamerules = GetGamerules()
		DisableBaseBotController( Gamerules and Gamerules.botTeamController )
		self:ForcePendingBotsToTeams()
	end )
end

function Plugin:ScheduleBotReconcile( Reason, Delay )
	if self:CombatOwnsBots() then return end
	if not self.BotManagementReady then
		return
	end

	if self.BotReconcilePending then return end

	self.BotReconcilePending = true
	Shine.Timer.Destroy( "mnga_bot_reconcile" )
	Shine.Timer.Create( "mnga_bot_reconcile", Delay or 1, 1, function()
		self.BotReconcilePending = false
		if not self.Enabled then return end

		local Gamerules = GetGamerules()
		if Gamerules then
			self:AdjustBots( Gamerules, Reason )
		end
	end )
end

function Plugin:StartBotAdjustTimer()
	if self.BotAdjustTimerRunning then return end

	local Interval = tonumber( botAdjustmentInterval ) or 2
	if Interval < 0.5 then Interval = 0.5 end

	self.BotAdjustTimerRunning = true
	Shine.Timer.Destroy( "mnga_bot_adjust" )
	Shine.Timer.Create( "mnga_bot_adjust", Interval, -1, function()
		if not self.Enabled then return end

		local Gamerules = GetGamerules()
		if Gamerules then
			self:RunBotAdjustment( Gamerules )
		end
	end )
end

function Plugin:StopBotAdjustTimer()
	if not self.BotAdjustTimerRunning then return end

	self.BotAdjustTimerRunning = false
	Shine.Timer.Destroy( "mnga_bot_adjust" )
end

function Plugin:SetBotControllerHardOff( Gamerules, Reason )
	local HardOffReason = tostring( Reason or "unspecified" )
	self.BotTarget = {
		MaxBots = 0,
		DrainOnly = true,
		Mode = "off"
	}
	self.BotPopulationMode = "off"
	self.BotNextAddTeam = nil

	self:StopBotAdjustTimer()
	Shine.Timer.Destroy( "mnga_bot_reconcile" )
	Shine.Timer.Destroy( "mnga_bot_force_join" )
	self.BotReconcilePending = false
	self.BotForceJoinPending = false

	local BotController = Gamerules and Gamerules.botTeamController
	if not BotController then return end

	self.BotControllerHardOffInProgress = true
	BotController.updateLock = 0
	if Gamerules.SetMaxBots then
		Gamerules:SetMaxBots( 0, false )
	elseif BotController.SetMaxBots then
		BotController:SetMaxBots( 0, false )
	else
		BotController.MaxBots = 0
	end

	BotController.MaxBots = 0
	BotController.addCommander1 = false
	BotController.addCommander2 = false
	self.BotControllerHardOffInProgress = false

	-- AdjustBots also runs on the 30-second population tick. Keep enforcing the
	-- hard-off state, but only log when entering it or when its reason changes.
	if not self.BotControllerHardOffActive or self.BotControllerHardOffReason ~= HardOffReason then
		Print( "%s", StringFormat( "[mngabots] maxbots hard-off reason=%s", HardOffReason ) )
	end
	self.BotControllerHardOffActive = true
	self.BotControllerHardOffReason = HardOffReason
end

function Plugin:GetBotPopulationMode( HumanCount, PlayingHumans )
	if PlayingHumans <= 0 or HumanCount <= 0 then
		if self.BotPopulationMode ~= "off" then
			Print( "%s", StringFormat( "[mngabots] mode change old=%s new=off humans=%d playingHumans=%d",
				tostring( self.BotPopulationMode or "nil" ), HumanCount, PlayingHumans ) )
		end
		self.BotPopulationMode = "off"
		return "off"
	end

	local LowThreshold = seedingGameThreshold or 14
	local SmallThreshold = smallGameThreshold or 18

	local LowExit = LowThreshold + 1
	local LowReentry = LowThreshold - 1
	local OffEnter = SmallThreshold + 1
	local MediumReentry = SmallThreshold - 1

	local Mode = self.BotPopulationMode or "off"

	if Mode == "low" then
		if HumanCount >= LowExit then
			Mode = "medium"
		end
	elseif Mode == "medium" then
		if HumanCount <= LowReentry then
			Mode = "low"
		elseif HumanCount >= OffEnter then
			Mode = "off"
		end
	else
		if HumanCount <= LowThreshold then
			Mode = "low"
		elseif HumanCount <= MediumReentry then
			Mode = "medium"
		else
			Mode = "off"
		end
	end

	if self.BotPopulationMode ~= Mode then
		Print( "%s", StringFormat( "[mngabots] mode change old=%s new=%s humans=%d playingHumans=%d",
			tostring( self.BotPopulationMode or "nil" ), Mode, HumanCount, PlayingHumans ) )
	end

	self.BotPopulationMode = Mode
	return Mode
end

function Plugin:GetTargetMaxBotsForMode( Mode )
	if Mode == "low" then
		return seedingMaxBotCount or 26
	end

	if Mode == "medium" then
		return smallGameMaxBotCount or 20
	end

	return 0
end

function Plugin:AddOneFieldBot( TeamNumber )
	if not OnConsoleAddBots then return false end

	Print( "%s", StringFormat( "[mngabots] progressive add team=%d mode=%s target=%s",
		TeamNumber, tostring( self.BotMode ), tostring( self.BotTarget and self.BotTarget.MaxBots ) ) )
	OnConsoleAddBots( nil, 1, TeamNumber )
	self:ScheduleBotForceJoin()
	return true
end

function Plugin:RemoveOneBot( TeamNumber )
	if not OnConsoleRemoveBots then return false end

	Print( "%s", StringFormat( "[mngabots] progressive remove team=%d mode=%s target=%s",
		TeamNumber, tostring( self.BotMode ), tostring( self.BotTarget and self.BotTarget.MaxBots ) ) )
	OnConsoleRemoveBots( nil, 1, TeamNumber )
	return true
end

function Plugin:RemoveAllManagedBots( Reason )
	if not OnConsoleRemoveBots then return false end

	local BotCount = gServerBots and #gServerBots or 0
	if BotCount <= 0 then return false end

	Print( "%s", StringFormat( "[mngabots] remove all bots count=%d reason=%s",
		BotCount, tostring( Reason or "unspecified" ) ) )
	OnConsoleRemoveBots( nil, BotCount )
	return true
end

function Plugin:RunBotAdjustment( Gamerules )
	if self:CombatOwnsBots() then
		self:StopBotAdjustTimer()
		return
	end
	local BotController = Gamerules and Gamerules.botTeamController
	if not BotController then return end

	DisableBaseBotController( BotController )

	if not OnConsoleAddBots or not OnConsoleRemoveBots then
		return
	end

	local Target = self.BotTarget
	if not Target then
		self:StopBotAdjustTimer()
		return
	end

	local H1, B1 = GetBotCountsForTeam( BotController, kTeam1Index )
	local H2, B2 = GetBotCountsForTeam( BotController, kTeam2Index )
	local CurrentBots = B1 + B2

	local TargetTeamSize = math.floor( ( Target.MaxBots or 0 ) / 2 )
	local Desired1 = math.max( 0, TargetTeamSize - H1 )
	local Desired2 = math.max( 0, TargetTeamSize - H2 )

	if Target.DrainOnly then
		Desired1 = math.min( Desired1, B1 )
		Desired2 = math.min( Desired2, B2 )
	end

	if ( Target.MaxBots or 0 ) <= 0 then
		Desired1 = 0
		Desired2 = 0
	end

	local Excess1 = B1 - Desired1
	local Excess2 = B2 - Desired2
	if Excess1 > 0 or Excess2 > 0 then
		if Excess1 >= Excess2 then
			self:RemoveOneBot( kTeam1Index )
		else
			self:RemoveOneBot( kTeam2Index )
		end
		DisableBaseBotController( BotController )
		return
	end

	if not Target.DrainOnly then
		local Deficit1 = Desired1 - B1
		local Deficit2 = Desired2 - B2
		if Deficit1 > 0 or Deficit2 > 0 then
			local TeamNumber
			if Deficit1 == Deficit2 then
				TeamNumber = self.BotNextAddTeam == kTeam2Index and kTeam2Index or kTeam1Index
				self.BotNextAddTeam = TeamNumber == kTeam1Index and kTeam2Index or kTeam1Index
			elseif Deficit1 > Deficit2 then
				TeamNumber = kTeam1Index
			else
				TeamNumber = kTeam2Index
			end

			self:AddOneFieldBot( TeamNumber )
			DisableBaseBotController( BotController )
			return
		end
	end

	if CurrentBots == 0 and ( Target.MaxBots or 0 ) <= 0 then
		self:StopBotAdjustTimer()
	end

	self:TryAutoStartSeeding( Gamerules, "bot adjustment filled" )
end

function Plugin:GetBotFillStatus( BotController, Target )
	if not BotController or not Target then return true, 0, 0 end

	local H1, B1 = GetBotCountsForTeam( BotController, kTeam1Index )
	local H2, B2 = GetBotCountsForTeam( BotController, kTeam2Index )
	local TargetTeamSize = math.floor( ( Target.MaxBots or 0 ) / 2 )

	local Desired1 = math.max( 0, TargetTeamSize - H1 )
	local Desired2 = math.max( 0, TargetTeamSize - H2 )
	local DesiredTotal = Desired1 + Desired2
	local CurrentTotal = B1 + B2

	return CurrentTotal >= DesiredTotal, CurrentTotal, DesiredTotal
end

function Plugin:TryAutoStartSeeding( Gamerules, Reason )
	-- Keep population management running, but do not ResetGame, enter Countdown,
	-- override resources, enable autobuild, or inject starting structures. NS20K
	-- decides if and when the game starts and owns all associated initial state.
	if self:UseNS20KStartOwner() then return false end
	if self:UseCombatStartOwner() then return false end
	-- Vanilla mode auto-starts too (comm bots + countdown) but skips the seeded setup below.
	if self.BotMode ~= "manga" and self.BotMode ~= "vanilla" then return false end
	if not Gamerules then return false end

	local GameInfo = GetGameInfoEntity()
	if not GameInfo or GameInfo.state >= kGameState.Countdown then
		return false
	end

	local PlayingHumans = self:CountTeamPlayers( true )
	local HumanCount = self:GetPopulationHumanCount()
	if PlayingHumans < 1 or HumanCount > autoStartThreshold then
		return false
	end

	local Filled, CurrentBots, DesiredBots = self:GetBotFillStatus(
		Gamerules.botTeamController, self.BotTarget )
	if not Filled then
		return false
	end

	Print( "%s", StringFormat(
		"[mngabots] autostarting %s game reason=%s bots=%d/%d humans=%d threshold=%s",
		self.BotMode == "vanilla" and "vanilla" or "seeded",
		tostring( Reason or "unspecified" ), CurrentBots, DesiredBots,
		HumanCount, tostring( autoStartThreshold )
	) )

	-- Add comm bots when there's players.
	self:AddCommanderBots( Gamerules, true )
	Gamerules:ResetGame()
	Gamerules:SetGameState( kGameState.Countdown )
	Gamerules.countdownTime = kCountDownLength
	Gamerules.lastCountdownPlayed = nil
	if self.BotMode == "vanilla" then
		Print( "[mngabots] vanilla autostart: no seeded res/autobuild/buildings" )
		return true
	end
	-- Constrain seeded team banks so the alien bot commander does not drop 3 hives.
	local MarineTeamResources = tonumber( seededMarineTeamStartResources ) or 150
	local AlienTeamResources = tonumber( seededAlienTeamStartResources ) or 160
	GetGamerules():GetTeam1():SetTeamResources( MarineTeamResources )
	GetGamerules():GetTeam2():SetTeamResources( AlienTeamResources )
	Print( "%s", StringFormat( "[mngabots] seeded start team res marines=%s aliens=%s",
		tostring( MarineTeamResources ), tostring( AlienTeamResources ) ) )
	local InstantBuildDuration = math.max( 0, tonumber( seededInstantBuildDuration ) or 50 )
	GetGamerules():SetAutobuild(true)
	Print( "%s", StringFormat( "[mngabots] seeded start instant build duration=%s",
		tostring( InstantBuildDuration ) ) )
	self:SetSeededStartResources()
	-- alien comm drops fourth hive at 44 secs (+5 for countdown)
	Shine.Timer.Simple( InstantBuildDuration, function( Timer )
		GetGamerules():SetAutobuild(false)
		-- GetGamerules():GetTeam1():SetTeamResources(200)
		if GetGamerules():GetTeam2():GetTeamResources() < alientopupres then
			GetGamerules():GetTeam2():SetTeamResources(alientopupres)
		end
		-- code does not work
		-- Give maturity to all structures on alien team.
		-- for index, ent in ipairs(GetEntitiesWithMixinForTeam("Maturity",2)) do
			-- ent:SetMature()
		-- end
	end );
	-- marine comm is incompetent, spawn ip
	SpawnBuildings(GetGamerules():GetTeam1())
	SpawnBuildings(GetGamerules():GetTeam2())

	return true
end

function Plugin:MapPostLoad()
  local this = self;
  self.BotManagementReady = false

	if self.BotMode == "vanilla" and not self:CombatOwnsBots() then
		self.BotManagementReady = true
		local Gamerules = GetGamerules()
		if Gamerules and Gamerules.SetMaxBots then
			Print( "%s", StringFormat( "[mngabots] applying map-load vanillaMaxBots=%d", self.VanillaMaxBots or 26 ) )
			Gamerules:SetMaxBots( self.VanillaMaxBots or 26, false )
		end
	end

  Shine.Timer.Destroy( "mnga_mapvote_results_postload" )
  Shine.Timer.Create( "mnga_mapvote_results_postload", 30, 1, function()
	if this.ShowPreviousMapVoteResults then
		this:ShowPreviousMapVoteResults()
	else
		Print( "[mngamapvote] ERROR | ShowPreviousMapVoteResults missing; post-load vote results disabled." )
	end
  end )
  
  -- for log reseting purposes just in case
  Print("%s", StringFormat( " >;> MAPCHANGE | %s | %d players", Shared.GetTime(), Shine.GetHumanPlayerCount() ) )
	
  if xpsystem then 
	  Shine.Timer.Simple(15, function()
		Print("%s", StringFormat( " >;> POST MAPCHANGE | %s | query %d players", Shared.GetTime(), Shine.GetHumanPlayerCount() ) )
		  local Clients, Count = Shine.GetAllClients()
		  local steamids = {}
		  for i = 1, Count do
			local client = Clients[i]

			table.insert(
				steamids,
				client:GetUserId()
			)
		  end
		  this:GetUserStats( steamids )
	  end);
  end
  
	Shine.Timer.Simple(100, function(Timer) -- delay game auto start
		self.BotManagementReady = true
		if self.BotMode == "vanilla" and not self:CombatOwnsBots() then
			local Gamerules = GetGamerules()
			local Controller = Gamerules and Gamerules.botTeamController
			if Controller and Controller.mngaVanillaMaxBots == nil and Gamerules.SetMaxBots then
				Print( "%s", StringFormat( "[mngabots] applying delayed map-load vanillaMaxBots=%d", self.VanillaMaxBots or 26 ) )
				Gamerules:SetMaxBots( self.VanillaMaxBots or 26, false )
			end
		end

		Shine.Timer.Create("mnga_tick", 1 * 30, -1, function(Timer)
			
			local gameInfo = GetGameInfoEntity();
		    -- check for messages
			-- Print(StringFormat("xpsystem 2 %s",xpsystem))
		    if xpsystem then self:ProcessNoti() end;
			
			local Gamerules = GetGamerules()
			if not Gamerules then return end

			local PlayingHumans = this:CountTeamPlayers(true)
			this:GrantHumanTickResources( "mnga_tick" )
			this:AdjustBots( Gamerules, "mnga_tick" )

			if PlayingHumans >= 1 then
			  -- only runs if seeding mode; helper waits for field bot fill.
			  this:TryAutoStartSeeding( Gamerules, "mnga_tick" )
			end

			-- Changelevel if no players back to seeding map
			if (this.BotMode == "manga" and Shine.GetHumanPlayerCount() == 0 and not isDefaultMap()) then
			  -- Change map to a random combat map when no players
			  Shared.ConsoleCommand("sh_changelevel " .. getDefaultMap());
			end
		end);
    end);
  
end

function Plugin:AdjustBots( Gamerules, Reason )
	if self:CombatOwnsBots() then return end
	local BotController = Gamerules.botTeamController

	if not BotController then
		return
	end

	if not OnConsoleAddBots or not OnConsoleRemoveBots then
		return
	end

	DisableBaseBotController( BotController )

	-- Don't fill while the round is over. Keep the controller disabled and let
	-- the immediate purge remove any remaining bots.
	local gameInfo = GetGameInfoEntity()

	local humanCount = self:GetPopulationHumanCount()
	local playingHumans = self:CountTeamPlayers( true )
	local mode
	local maxBots
	if self.BotMode == "vanilla" then
		mode = "vanilla"
		maxBots = tonumber( BotController.mngaVanillaMaxBots ) or tonumber( BotController.MaxBots ) or self.VanillaMaxBots or 26
	else
		mode = self:GetBotPopulationMode( humanCount, playingHumans )
		maxBots = self:GetTargetMaxBotsForMode( mode )
	end
	local roundOver = gameInfo and gameInfo.state >= kGameState.Team1Won

	if roundOver or playingHumans <= 0 then
		if self.BotMode == "vanilla" then
			self.BotTarget = nil
			self:StopBotAdjustTimer()
			self:RemoveAllManagedBots( roundOver and "round over" or "no playing humans" )
			return
		end
		self:SetBotControllerHardOff( Gamerules, roundOver and "round over" or "no playing humans" )
		self:RemoveAllManagedBots( roundOver and "round over" or "no playing humans" )
		return
	end

	self.BotControllerHardOffActive = false
	self.BotControllerHardOffReason = nil

	-- Started rounds above the seeding band are drain-only. Low-pop seeded
	-- rounds may keep filling after start so the gradual add pacing does not
	-- race the countdown.
	local drainOnly = self.BotMode ~= "vanilla" and gameInfo
		and gameInfo.state == kGameState.Started
		and humanCount > ( seedingGameThreshold or 14 )

	self.BotTarget = {
		MaxBots = maxBots,
		DrainOnly = drainOnly,
		Mode = mode
	}

	self:StartBotAdjustTimer()
	self:RunBotAdjustment( Gamerules )
end

	-- Commander bot population gating uses non-spectating humans.
function Plugin:AddCommanderBotIfNeeded( Gamerules, BotController, TeamNumber )
	if self:UseNS20KStartOwner() then return false end
	if self:UseCombatStartOwner() then return false end
	if not BotController:GetTeamHasCommander( TeamNumber ) then
		DisableBaseBotController( BotController )
		Print( "%s", StringFormat( "[mngabots] add commander bot team=%d humans=%d",
			TeamNumber, self:GetPopulationHumanCount() ) )
		OnConsoleAddBots( nil, 1, TeamNumber, "com" )
		if self.ScheduleBotForceJoin then
			self:ScheduleBotForceJoin()
		end
		Gamerules.removeCommanderBots = true
	end
end


function Plugin:AddCommanderBots( Gamerules, IgnoreHumanThreshold )
	if self:UseNS20KStartOwner() then return false end
	if self:UseCombatStartOwner() then return false end
	local BotController = Gamerules.botTeamController

	if not BotController or not BotController.GetTeamHasCommander then
		return
	end

	if not OnConsoleAddBots then
		return
	end

	local PlayingHumans = self:CountTeamPlayers( true )
	local ServerHumans = self:GetPopulationHumanCount()
	if not IgnoreHumanThreshold and ( PlayingHumans < 1 or ServerHumans > commBotHumanThreshold ) then
		return
	end

	DisableBaseBotController( BotController )

	self:AddCommanderBotIfNeeded(Gamerules, BotController, kTeam1Index);
	self:AddCommanderBotIfNeeded(Gamerules, BotController, kTeam2Index);
end

function Plugin:CountTeamPlayers(excludeBots)
  return self:CountMarinePlayers(excludeBots) + self:CountAlienPlayers(excludeBots);
end

function Plugin:CountMarinePlayers(excludeBots)
  return self:GetTeamPlayerCount(kTeam1Index, excludeBots);
end

function Plugin:CountAlienPlayers(excludeBots)
  return self:GetTeamPlayerCount(kTeam2Index, excludeBots);
end

function Plugin:GetTeamPlayerCount(teamIndex, excludeBots)
	local Players = GetEntitiesForTeam("Player", teamIndex);

	local count = #Players;

  if (excludeBots) then
    for i = 1, #Players do
      local Player = Players[i];
      if Player and Player:GetIsVirtual() then
        count = count - 1;
      end
    end
  end

	return count;
end
