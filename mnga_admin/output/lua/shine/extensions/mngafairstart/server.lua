local Plugin = ...

local StringFormat = string.format
local Lower = string.lower

local function GetLocationName( Entity )
	if not Entity then return "" end

	if Entity.GetLocationName then
		return Entity:GetLocationName() or ""
	end

	local Location = GetLocationForPoint( Entity:GetOrigin() )
	return Location and Location:GetName() or ""
end

local function GetMapEnabled( Config )
	local MapName = Lower( Shared.GetMapName() or "" )
	local Maps = Config.Maps
	if not Maps or Maps[ MapName ] == nil then return true end
	return Maps[ MapName ] == true
end

local function GetIsNS20KMode()
	return type( NS20KIsEnabled ) == "function"
		and NS20KIsEnabled( "CommanderlessStart" ) == true
end

local function GetIsVanillaPotentialAlienSpawn( TechPoint )
	if not TechPoint or not TechPoint.GetTeamNumberAllowed then return false end

	local AllowedTeam = TechPoint:GetTeamNumberAllowed()
	return AllowedTeam == 0 or AllowedTeam == kTeam2Index
end

local function AddCandidateTechPoint( Candidates, CandidateSet, TechPoint )
	if not TechPoint or not TechPoint.GetId then return false end

	local ID = TechPoint:GetId()
	if CandidateSet[ ID ] then return false end

	CandidateSet[ ID ] = true
	Candidates[ #Candidates + 1 ] = TechPoint
	return true
end

local function BuildTechPointLookup()
	local Lookup = {}

	for _, TechPoint in ientitylist( Shared.GetEntitiesWithClassname( "TechPoint" ) ) do
		Lookup[ Lower( GetLocationName( TechPoint ) ) ] = TechPoint
	end

	return Lookup
end

local function BuildNameList( TechPoints )
	local Names = {}

	for i = 1, #TechPoints do
		Names[ i ] = GetLocationName( TechPoints[ i ] )
	end

	return table.concat( Names, ", " )
end

local function GetCustomSpawnsCandidateTechPoints( self, MarineStart )
	local CustomSpawns = Shine.Plugins and Shine.Plugins.customspawns
	if not CustomSpawns or not CustomSpawns.Spawns or not MarineStart then
		return nil
	end

	local MarineStartName = Lower( GetLocationName( MarineStart ) )
	local MarineSpawnEntry = CustomSpawns.Spawns[ MarineStartName ]
	local EnemySpawns = MarineSpawnEntry and MarineSpawnEntry.enemyspawns
	if not EnemySpawns or #EnemySpawns == 0 then
		self:DebugPrint( "customspawns has no enemyspawns for marine start %s", MarineStartName )
		return nil
	end

	local TechPointLookup = BuildTechPointLookup()
	local Candidates = {}
	local CandidateSet = {}

	for i = 1, #EnemySpawns do
		local EnemySpawnName = Lower( EnemySpawns[ i ] )
		local TechPoint = CustomSpawns.Spawns[ EnemySpawnName ] or TechPointLookup[ EnemySpawnName ]
		if not AddCandidateTechPoint( Candidates, CandidateSet, TechPoint ) then
			self:DebugPrint( "customspawns candidate %s did not resolve to a unique tech point", EnemySpawnName )
		end
	end

	return Candidates, "customspawns"
end

local function GetVanillaOverrideCandidateTechPoints( self, MarineStart )
	if not MarineStart or not Server or not Server.spawnSelectionOverrides then
		return nil
	end

	local SpawnOverrides = Server.spawnSelectionOverrides
	if #SpawnOverrides == 0 then return nil end

	local MarineStartName = Lower( GetLocationName( MarineStart ) )
	local TechPointLookup = BuildTechPointLookup()
	local Candidates = {}
	local CandidateSet = {}

	for i = 1, #SpawnOverrides do
		local SpawnPair = SpawnOverrides[ i ]
		if SpawnPair and SpawnPair.marineSpawn == MarineStartName then
			local AlienSpawnName = SpawnPair.alienSpawn
			if not AddCandidateTechPoint( Candidates, CandidateSet, TechPointLookup[ AlienSpawnName ] ) then
				self:DebugPrint( "vanilla override candidate %s did not resolve to a unique tech point", tostring( AlienSpawnName ) )
			end
		end
	end

	if #Candidates == 0 then
		self:DebugPrint( "vanilla spawnSelectionOverrides has no alien spawns for marine start %s", MarineStartName )
		return nil
	end

	return Candidates, "vanilla_overrides"
end

local function GetConfiguredPairCandidateTechPoints( self, MarineStart )
	if not MarineStart then return nil end

	local SpawnPairs = self.Config and self.Config.SpawnPairs
	local MapPairs = SpawnPairs and SpawnPairs[ Lower( Shared.GetMapName() or "" ) ]
	if not MapPairs then return nil end

	local MarineStartName = Lower( GetLocationName( MarineStart ) )
	local EnemySpawns = MapPairs[ MarineStartName ]
	if not EnemySpawns or #EnemySpawns == 0 then
		self:DebugPrint( "SpawnPairs has no enemyspawns for marine start %s", MarineStartName )
		return nil
	end

	local TechPointLookup = BuildTechPointLookup()
	local Candidates = {}
	local CandidateSet = {}

	for i = 1, #EnemySpawns do
		local EnemySpawnName = Lower( EnemySpawns[ i ] )
		if not AddCandidateTechPoint( Candidates, CandidateSet, TechPointLookup[ EnemySpawnName ] ) then
			self:DebugPrint( "SpawnPairs candidate %s did not resolve to a unique tech point", EnemySpawnName )
		end
	end

	return Candidates, "spawnpairs"
end

local function GetFallbackCandidateTechPoints()
	local Candidates = {}
	local CandidateSet = {}

	for _, TechPoint in ientitylist( Shared.GetEntitiesWithClassname( "TechPoint" ) ) do
		if GetIsVanillaPotentialAlienSpawn( TechPoint ) then
			AddCandidateTechPoint( Candidates, CandidateSet, TechPoint )
		end
	end

	return Candidates, "fallback"
end

local function GetCandidateTechPoints( self, Gamerules )
	local MarineTeam = Gamerules and Gamerules.GetTeam and Gamerules:GetTeam( kTeam1Index )
	local AlienTeam = Gamerules and Gamerules.GetTeam and Gamerules:GetTeam( kTeam2Index )
	local MarineStart = MarineTeam and MarineTeam.GetInitialTechPoint and MarineTeam:GetInitialTechPoint()
	local AlienStart = AlienTeam and AlienTeam.GetInitialTechPoint and AlienTeam:GetInitialTechPoint()

	local Candidates, Source = GetCustomSpawnsCandidateTechPoints( self, MarineStart )
	if not Candidates or #Candidates == 0 then
		Candidates, Source = GetVanillaOverrideCandidateTechPoints( self, MarineStart )
	end
	if not Candidates or #Candidates == 0 then
		Candidates, Source = GetConfiguredPairCandidateTechPoints( self, MarineStart )
	end
	if not Candidates or #Candidates == 0 then
		Candidates, Source = GetFallbackCandidateTechPoints()
	end

	self:DebugPrint( "marine start=%s, alien start=%s, candidate source=%s, candidates=%s",
		GetLocationName( MarineStart ), GetLocationName( AlienStart ), Source, BuildNameList( Candidates ) )

	return Candidates, Source
end

local function GetExistingAttachedEntity( AttachPoint )
	if not AttachPoint or not AttachPoint.GetAttached then return nil end
	return AttachPoint:GetAttached()
end

local function GetShouldDestroyCandidateRoomPower( Config )
	if Config.DestroyCandidateRoomPower == nil then return true end
	return Config.DestroyCandidateRoomPower == true
end

local function ApplyFairStart( self, AlienTeam )
	-- NS20K owns the complete commanderless opening. Do not alter Tech Point
	-- room power while that mode is active.
	if GetIsNS20KMode() then
		if not self.NS20KSuppressionLogged then
			self.NS20KSuppressionLogged = true
			Print( "[mngafairstart] disabled for NS20K mode" )
		end
		return
	end

	if not self.Config.Enabled then
		self:DebugPrint( "disabled by config" )
		return
	end

	if not GetMapEnabled( self.Config ) then
		self:DebugPrint( "disabled for map %s", Shared.GetMapName() )
		return
	end

	-- Vanilla destroys power only at the real alien start, which reveals it.
	-- Destroy power at every other possible alien start for this marine start.
	local DestroyPower = GetShouldDestroyCandidateRoomPower( self.Config )
	local PowerCount = 0
	local EligibleCount = 0
	local SkippedCount = 0
	local Gamerules = GetGamerules()
	local CandidateTechPoints, CandidateSource = GetCandidateTechPoints( self, Gamerules )

	for i = 1, #CandidateTechPoints do
		local TechPoint = CandidateTechPoints[ i ]
		local LocationName = GetLocationName( TechPoint )
		EligibleCount = EligibleCount + 1

		local Attached = GetExistingAttachedEntity( TechPoint )
		if Attached then
			SkippedCount = SkippedCount + 1
			self:DebugPrint( "skipped candidate %s: occupied by %s", LocationName, Attached:GetClassName() )
		elseif DestroyPower then
			DestroyPowerForLocation( LocationName, true )
			PowerCount = PowerCount + 1
			self:DebugPrint( "destroyed power at candidate room %s", LocationName )
		end
	end

	Print( "%s", StringFormat(
		"[mngafairstart] Round start: source=%s, eligible alien spawns=%d, skipped occupied=%d, power destroyed=%d",
		CandidateSource, EligibleCount, SkippedCount, PowerCount
	) )
end

function Plugin:DebugPrint( Message, ... )
	if not self.Config or not self.Config.Debug then return end
	Print( "%s", StringFormat( "[mngafairstart] " .. Message, ... ) )
end

function Plugin:InstallAlienTeamPatch()
	if self.OldAlienTeamOnResetComplete then return end

	self.OldAlienTeamOnResetComplete = AlienTeam.OnResetComplete

	local PluginRef = self
	local OldAlienTeamOnResetComplete = self.OldAlienTeamOnResetComplete

	local function FairStartAlienTeamOnResetComplete( Team )
		OldAlienTeamOnResetComplete( Team )
		ApplyFairStart( PluginRef, Team )
	end

	self.FairStartAlienTeamOnResetComplete = FairStartAlienTeamOnResetComplete

	AlienTeam.OnResetComplete = FairStartAlienTeamOnResetComplete

	Print( "[mngafairstart] AlienTeam OnResetComplete patch installed" )
end

function Plugin:Initialise()
	self:InstallAlienTeamPatch()

	self.Enabled = true
	return true
end

function Plugin:Cleanup()
	if self.OldAlienTeamOnResetComplete and AlienTeam.OnResetComplete == self.FairStartAlienTeamOnResetComplete then
		AlienTeam.OnResetComplete = self.OldAlienTeamOnResetComplete
	end

	self.OldAlienTeamOnResetComplete = nil
	self.FairStartAlienTeamOnResetComplete = nil
	self.NS20KSuppressionLogged = nil

	self.BaseClass.Cleanup( self )
	self.Enabled = false
end

return Plugin
