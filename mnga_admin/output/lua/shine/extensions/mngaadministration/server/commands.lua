local Plugin = ...
local Shine = Shine
local StringFormat = string.format
local Random = math.random

local kSlapHorizontalMin = 4
local kSlapHorizontalMax = 10
local kSlapVerticalMin = 6
local kSlapVerticalMax = 12

local function GetEligiblePlayingPlayer( Target )
	local Player = Target and Target:GetControllingPlayer()
	if not Player or not Player.GetTeamNumber or not Player.GetIsAlive then
		return nil, "Target has no controllable player."
	end

	local TeamNumber = Player:GetTeamNumber()
	if TeamNumber ~= kTeam1Index and TeamNumber ~= kTeam2Index then
		return nil, "Target must be on the Marine or Alien team."
	end
	if not Player:GetIsAlive() then
		return nil, "Target must be alive."
	end
	if Player:isa( "Commander" ) then
		return nil, "Target must leave the command structure first."
	end

	return Player, nil
end

local function NotifyAdminCommandError( Client, Message )
	Shine:NotifyCommandError( Client, Message, true )
end

local function AnnounceAdminRecoveryCommand( Client, Message, ... )
	-- Pass target names as MNGA_Name() so viewers see their SSB aliases.
	MNGA_NotifyNames( nil, 255, 200, 100, "%s has " .. Message, MNGA_Name( Client ), ... )
end

local function GetRandomSignedMagnitude( Minimum, Maximum )
	local Magnitude = Minimum + Random() * ( Maximum - Minimum )
	return Random() < 0.5 and -Magnitude or Magnitude
end

local function FindAdminUnstuckDestination( Player, Structure )
	local TechID = Player:GetTechId()
	local Extents = LookupTechData( TechID, kTechDataMaxExtents )
	if not Extents then return nil end

	local Height, Radius = GetTraceCapsuleFromExtents( Extents )
	local Origin = Structure.GetDefaultEntryOrigin and Structure:GetDefaultEntryOrigin()
		or Structure:GetOrigin()

	for i = 1, 10 do
		local Destination = GetRandomSpawnForCapsule(
			Height, Radius, Origin, 0.5, 6, EntityFilterAll()
		)
		if Destination then return Destination end
	end

	return nil
end

function Plugin:CreateCommands()
	-- No rate-trial module, timer or gameplay hook is loaded at plugin startup.
	local function RateTrial( Client, Action, Tick, Move, Send, Seconds )
		if not self.MNGARateTrialCommand then
			Shine.LoadPluginFile( self:GetName(), "server/rate_trial.lua", self )
		end
		self:MNGARateTrialCommand( Action, Tick, Move, Send, Seconds )
	end
	local RateTrialCommand = self:BindCommand( "sh_mngarates", nil, RateTrial )
	RateTrialCommand:AddParam{ Type = "string", Optional = true, Default = "status" }
	-- Parse these strictly in the module. Shine's optional number parser turns
	-- malformed input into nil, which would otherwise select the default rates.
	RateTrialCommand:AddParam{ Type = "string", Optional = true, MaxLength = 24, Help = "target tickrate (30-60)" }
	RateTrialCommand:AddParam{ Type = "string", Optional = true, MaxLength = 24, Help = "target moverate (26-52)" }
	RateTrialCommand:AddParam{ Type = "string", Optional = true, MaxLength = 24, Help = "target sendrate (20-40)" }
	RateTrialCommand:AddParam{ Type = "string", Optional = true, MaxLength = 24, Help = "seconds per window (60-600, default 300)" }
	RateTrialCommand:Help( "status | start [tick move send [seconds]] | stop. Default 36/32/24; transient, auto-restored." )

	local function AdminUnstuck( Client, Target )
		local Player, Error = GetEligiblePlayingPlayer( Target )
		if not Player then
			NotifyAdminCommandError( Client, Error )
			return
		end

		local TeamNumber = Player:GetTeamNumber()
		local StructureClass = TeamNumber == kTeam1Index and "CommandStation" or "Hive"
		local Structures = GetEntitiesForTeam( StructureClass, TeamNumber )

		for i = 1, #Structures do
			local Structure = Structures[ i ]
			if Structure:GetIsAlive() and Structure:GetIsBuilt() then
				local Destination = FindAdminUnstuckDestination( Player, Structure )
				if Destination then
					SpawnPlayerAtPoint( Player, Destination )
					Player:SetVelocity( Vector( 0, 0, 0 ) )
					Shine:AdminPrint( Client, "Moved %s near a team %s.", true,
						Player:GetName(), StructureClass )
					AnnounceAdminRecoveryCommand( Client, "unstuck %s to %s.",
						MNGA_Name( Player ), StructureClass == "Hive" and "Hive" or "Command Station" )
					return
				end
			end
		end

		local Message = StringFormat( "No safe destination near a built, living %s was found.",
			StructureClass )
		NotifyAdminCommandError( Client, Message )
	end
	local AdminUnstuckCommand = self:BindCommand( "sh_adminunstuck", nil, AdminUnstuck )
	AdminUnstuckCommand:AddParam{ Type = "client" }
	AdminUnstuckCommand:Help( "Moves a living Marine or Alien near a team command structure." )

	local function Slay( Client, Target )
		local Player, Error = GetEligiblePlayingPlayer( Target )
		if not Player then
			NotifyAdminCommandError( Client, Error )
			return
		end

		Player:Kill( nil, nil, Player:GetOrigin() )
		Shine:AdminPrint( Client, "Slayed %s.", true, Player:GetName() )
		AnnounceAdminRecoveryCommand( Client, "slain %s.", MNGA_Name( Player ) )
	end
	local SlayCommand = self:BindCommand( "sh_slay", nil, Slay )
	SlayCommand:AddParam{ Type = "client" }
	SlayCommand:Help( "Kills a living player on the Marine or Alien team." )

	local function Slap( Client, Target, Damage )
		local Player, Error = GetEligiblePlayingPlayer( Target )
		if not Player then
			NotifyAdminCommandError( Client, Error )
			return
		end

		-- Be defensive here even though the command parameter declares a default. This
		-- also keeps direct/internal calls to the handler consistent with sh_slap.
		Damage = Damage or 1

		local Velocity = Vector(
			GetRandomSignedMagnitude( kSlapHorizontalMin, kSlapHorizontalMax ),
			kSlapVerticalMin + Random() * ( kSlapVerticalMax - kSlapVerticalMin ),
			GetRandomSignedMagnitude( kSlapHorizontalMin, kSlapHorizontalMax )
		)
		if Player.DisableGroundMove then
			-- SetVelocity alone does not launch a grounded player: GroundMoveMixin can
			-- consume the Y component on the next movement update. This is the same
			-- airborne transition used by NS2's jump/forced-launch paths.
			Player:DisableGroundMove( 0.1 )
		else
			Player.onGround = false
		end
		Player:SetVelocity( Velocity )

		if Damage > 0 then
			local AppliedDamage, ArmourUsed, HealthUsed = GetDamageByType(
				Player, Player, Player, Damage, kDamageType.Normal, Player:GetOrigin()
			)
			-- Normal damage rules expect a non-nil doer (weapon upgrade processing
			-- dereferences it), so use the target as the synthetic slap source.
			Player:TakeDamage( AppliedDamage, Player, Player, Player:GetOrigin(), Velocity,
				ArmourUsed, HealthUsed, kDamageType.Normal )
		end

		Shine:AdminPrint( Client, "Slapped %s for %d damage.", true, Player:GetName(), Damage )
		AnnounceAdminRecoveryCommand( Client, "slapped %s for %d damage.", MNGA_Name( Player ), Damage )
	end
	local SlapCommand = self:BindCommand( "sh_slap", nil, Slap )
	SlapCommand:AddParam{ Type = "client" }
	SlapCommand:AddParam{ Type = "number", Min = 0, Max = 1000, Round = true,
		Optional = true, Default = 1, Help = "damage" }
	SlapCommand:Help( "Damages and launches a living Marine or Alien; damage defaults to 1." )

	local function BotDifficulty( Client, ProfileName )
		ProfileName = string.lower( tostring( ProfileName or "" ) )
		if not self:ApplyBotDifficultyProfile( ProfileName, self:GetClientInfo( Client, true ) ) then
			Shine:NotifyCommandError( Client, "Unknown bot difficulty profile '%s'. Use easy, normal, or hard.",
				true, ProfileName )
			return
		end
		Shine:AdminPrint( Client, "Bot difficulty is now %s for this map.", true, ProfileName )
	end
	local DifficultyCommand = self:BindCommand( "sh_botdifficulty", nil, BotDifficulty )
	DifficultyCommand:AddParam{ Type = "string", Error = "Please specify easy, normal, or hard." }
	DifficultyCommand:Help( "Applies an easy, normal, or hard bot difficulty profile for this map." )

	local function BotDifficultyStatus( Client )
		local Tuning = self.ActiveBotTuning or {}
		local Gamerules = GetGamerules()
		local Controller = Gamerules and Gamerules.botTeamController
		local Target = self.BotTarget and self.BotTarget.MaxBots
			or Controller and ( Controller.mngaVanillaMaxBots or Controller.MaxBots ) or 0
		Shine:AdminPrint( Client,
			"Bot mode=%s profile=%s configured=%s target=%s interval=%s timer=%s pending=%s tier=%s cap=%s miss=%.2f acquisition=%.2f skulkChance=%.2f skulkInterval=%.2f.",
			true, tostring( self.BotMode ), tostring( self.ActiveBotDifficultyProfile ),
			tostring( self.ConfiguredBotDifficultyProfile ), tostring( Target ),
			tostring( botAdjustmentInterval ), tostring( self.BotAdjustTimerRunning == true ),
			tostring( self.BotReconcilePending == true ), tostring( Tuning.AimTier ), tostring( Tuning.AccuracyCap ),
			Tuning.MarineMissOffsetMultiplier or 0, Tuning.TargetAcquisitionDelay or 0,
			Tuning.SkulkBiteAttemptChance or 0, Tuning.SkulkBiteDecisionInterval or 0 )
		Shine:AdminPrint( Client,
			"Bot Skulk tuning targetRange=%.1f biteGate=%.1f removeJump=%s forceForward=%s.",
			true, Tuning.SkulkTargetRange or 0, Tuning.SkulkBiteGateRange or 0,
			tostring( Tuning.SkulkRemoveJump ), tostring( Tuning.SkulkForceForward ) )
	end
	local StatusCommand = self:BindCommand( "sh_botdifficulty_status", nil, BotDifficultyStatus )
	StatusCommand:Help( "Shows the active bot mode, target, and difficulty values." )

	local function ResetBotDifficulty( Client )
		self:ApplyBotDifficultyProfile( self.ConfiguredBotDifficultyProfile, "admin reset" )
		Shine:AdminPrint( Client, "Bot difficulty reset to configured profile %s.",
			true, self.ConfiguredBotDifficultyProfile )
	end
	local ResetCommand = self:BindCommand( "sh_botdifficulty_reset", nil, ResetBotDifficulty )
	ResetCommand:Help( "Resets bot difficulty to the configured map default." )

	local function ShowXP( Client )
		if not Client then return end
		self:ShowXP( Client )
	end
	-- Keep a second, deliberately uncommon chat alias as a diagnostic. If !xp
	-- disappears while !xp2 remains, another extension has overwritten or
	-- removed only the common "xp" alias. If both disappear, investigate this
	-- plugin being unloaded/reloaded instead.
	local XPCommand = self:BindCommand( "sh_xp", { "xp", "xp2" }, ShowXP, true )
	XPCommand:Help( "Shows xp." )
	
	-- As with !xp2 above, !discord2 distinguishes a collision on the common
	-- alias from the whole mngaadministration command set being cleaned up.
	local discordCommand = self:BindCommand( "sh_discord", { "discord", "discord2" },
        function( client )
            Shine:NotifyDualColour(
                client,
                0, 200, 255, "Discord: ",
                255, 255, 255, "https://tinyurl.com/ns2manga . That is tinyurl + ns2 + manga. "
            )
        end
		, true)
	discordCommand:Help( "Shows discord link - https://discord.gg/W6SsuX6k88 or https://tinyurl.com/ns2manga." )
	Print( "[mnga_commands] Registered XP aliases !xp/!xp2 and Discord aliases !discord/!discord2." )

	local rulesCommand = self:BindCommand( "sh_rules", { "rules", "rule" },
        function( client )
            local RulesLines = self.Config.rulesLines
            if #RulesLines > 0 then
                -- NotifyColour with no client would broadcast to everyone.
                if not client then return end
                for i = 1, #RulesLines do
                    Shine:NotifyColour( client, 255, 255, 255, RulesLines[ i ] )
                end
                return
            end

            Shine:NotifyDualColour(
                client,
                0, 200, 0, "More info: !discord ",
                0, 200, 255, "Rules: Don't troll the server (smurf, providing hidden info, ...). ",
                255, 255, 255, " Disallowed gameplay action (6 arcs, completely hidden structures)"
            )
        end
		, true)
	rulesCommand:Help( "Shows server rules" )

	-- Toggle anti dog-pile vote hiding. With no argument it flips the current
	-- state; pass true/false to set it explicitly. Resets to the config default
	-- on every map change (the plugin reloads), so it is set per-map.
	local function HideVotes( Client, Enable )
		self.HideMapVoteCounts = Enable
		Print( "%s", StringFormat( " >;> HIDEVOTES | %s | set to %s by %s",
			Shared.GetTime(), tostring( Enable ), self:GetClientInfo( Client, true ) ) )
		Shine:AdminPrint( Client, "Map vote counts are now %s.",
			true, Enable and "HIDDEN" or "VISIBLE" )
	end
	local HideVotesCommand = self:BindCommand( "sh_hidevotes", "hidevotes", HideVotes, false, true )
	HideVotesCommand:AddParam{ Type = "boolean", Optional = true,
		Default = function() return not self.HideMapVoteCounts end }
	HideVotesCommand:Help( "Hides live map vote tallies to prevent dog-piling. Omit the argument to toggle." )

	-- Resolves a !skipq target like Shine:GetClient (IDs, Steam IDs, names), but
	-- an ambiguous name is rejected instead of silently taking the leftmost match.
	-- Returns the client, or nil plus the list of matching names.
	local function FindSkipTarget( String )
		local Number = Shine.CoerceToID( String )
		if Number then
			local Target = Shine.GetClientByNS2ID( Number ) or Shine.GetClientByID( Number )
			return Target, {}
		end
		local SteamTarget = Shine:GetClientBySteamID( String )
		if SteamTarget then return SteamTarget, {} end

		local Search = String:lower()
		local Exact, Partial, Names = {}, {}, {}
		for Client in Shine.IterateClients() do
			local Player = Client:GetControllingPlayer()
			if Player then
				local Name = Player:GetName()
				local Lower = Name:lower()
				if Lower == Search then
					Exact[ #Exact + 1 ] = Client
				elseif Lower:find( Search, 1, true ) then
					Partial[ #Partial + 1 ] = Client
					Names[ #Names + 1 ] = Name
				end
			end
		end
		if #Exact == 1 then return Exact[ 1 ], {} end
		if #Exact > 1 then
			-- Names are unique ignoring case in practice, but list them all if not.
			Names = {}
			for i = 1, #Exact do Names[ i ] = Shine.GetClientName( Exact[ i ] ) end
			return nil, Names
		end
		if #Partial == 1 then return Partial[ 1 ], {} end
		return nil, Names
	end

	-- Skip-queue policy is owned by mngareadyroomqueue. An optional player
	-- argument spends the caller's supporter (donation) token on that player.
	local function SkipqueuePlayer( Client, TargetString )
		if not Client then return end
		local rrqueue = Shine.Plugins and Shine.Plugins[ "mngareadyroomqueue" ]
		if not ( rrqueue and rrqueue.Skipqueue ) then return end

		TargetString = ( TargetString or "" ):match( "^%s*(.-)%s*$" )
		if TargetString == "" then
			rrqueue:Skipqueue( Client )
			return
		end

		local Target, Matches = FindSkipTarget( TargetString )
		Print( "%s", StringFormat( "[skipqueue] target lookup by %s query='%s' result=%s matches=%d",
			self:GetClientInfo( Client, true ), TargetString,
			Target and self:GetClientInfo( Target, true ) or "none", #Matches ) )
		if not Target then
			if #Matches > 1 then
				Shine:NotifyColour( Client, 255, 80, 80, StringFormat(
					"Multiple players match '%s': %s. Be more specific.",
					TargetString, table.concat( Matches, ", " ) ) )
			else
				Shine:NotifyColour( Client, 255, 80, 80, StringFormat(
					"No player matching '%s' was found.", TargetString ) )
			end
			return
		end

		if Target == Client then
			rrqueue:Skipqueue( Client )
		else
			rrqueue:Skipqueue( Client, Target )
		end
	end
	local SkipqueueCmd = self:BindCommand( "sh_skipqueue", "skipq", SkipqueuePlayer, true )
	SkipqueueCmd:AddParam{ Type = "string", Optional = true, TakeRestOfLine = true, Default = "",
		Help = "player" }
	SkipqueueCmd:Help( "Use a supporter or seeding token to skip queue. Give a player to spend a supporter token on them." )

	-- Swap spectator <-> player through the owned queue transaction API.
	local function SwapPlayerCmd( Client, SpecTarget, PlayerTarget )
		local rrqueue = Shine.Plugins and Shine.Plugins[ "mngareadyroomqueue" ]
		if rrqueue and rrqueue.SwapPlayer then
			rrqueue:SwapPlayer( Client, SpecTarget, PlayerTarget )
		end
	end
	local SwapCmd = self:BindCommand( "sh_swap", "swapplayer", SwapPlayerCmd )
	SwapCmd:AddParam{ Type = "client", IgnoreCanTarget = true }
	SwapCmd:AddParam{ Type = "client", IgnoreCanTarget = true }
	SwapCmd:Help( "Swaps a spectator with a playing player. First target is spectator, second is player." )

	-- Third person toggle (M menu button). Only flips between 0 and our distance so an
	-- emote's orbit camera or death camera is never overwritten.
	local function ThirdPerson( Client )
		if not Client then return end
		local Player = Client:GetControllingPlayer()
		local Gamerules = GetGamerules()
		local GameState = Gamerules and Gamerules:GetGameState()
		local Reason = self.GetThirdPersonBlockReason( Player, GameState )
		if Reason then
			Shine:NotifyCommandError( Client, Reason )
			return
		end

		local Distance = Player:GetCameraDistance()
		if Distance == self.ThirdPersonDistance then
			Player:SetIsThirdPerson( 0 )
		elseif Distance == 0 then
			Player:SetIsThirdPerson( self.ThirdPersonDistance )
		else
			Shine:NotifyCommandError( Client, "Camera is busy (emote?)." )
		end
	end
	local ThirdPersonCmd = self:BindCommand( "sh_thirdperson", "thirdperson", ThirdPerson, true )
	ThirdPersonCmd:Help( "Toggles third person camera in the ready room or before the round starts." )

end


