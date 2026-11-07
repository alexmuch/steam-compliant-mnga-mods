-- mngaadministration client: admin menu swap button

local Plugin = ...
local PluginName = Plugin:GetName()
Shine.LoadPluginFile( PluginName, "client/spectator_drawing.lua", Plugin )
Shine.LoadPluginFile( PluginName, "client/spectator_chat.lua", Plugin )
local EnemyGroupScoreboardHookInstalled = false
local EnemyGroupScoreboardHookAttempted = false
local EnemyGroupScoreboardDeferredHook = "MNGAAdministrationEnemyGroupScoreboardDeferredInstall"
local EnemyGroupState = {}
local EnemyGroupRowColour = Colour( 0.82, 0.12, 0.12 )
local MangaVolumeOption = "mngaMiniGameVolume"
local LegacyPokerVolumeOption = "mngaPokerVolume"
local MangaVolume = 100
local MangaSizeOption = "mngaMiniGameUISize"
local MangaSize = 100
local MangaOpacityOption = "mngaMiniGameOpacity"
local MangaOpacity = 100

-- Public client accessor used by MNGA mini-games. NS2 applies its master
-- sound-effects volume after this per-event scale. Reads the option each call
-- (only when a mini-game sound plays) so the Shimizu QoL slider applies live.
function GetMangaVolumeScale()
	MangaVolume = math.max( 0, math.min( 100,
		math.floor( tonumber( Client.GetOptionInteger( MangaVolumeOption, MangaVolume ) ) or 100 ) ) )
	return MangaVolume / 100
end

function GetMangaUIScale()
	return MangaSize / 100
end

function SetMangaUISize( Size, Source )
	local OldSize = MangaSize
	MangaSize = math.max( 30, math.min( 120, math.floor( tonumber( Size ) or 100 ) ) )
	Client.SetOptionInteger( MangaSizeOption, MangaSize )
	Print( "%s", string.format( "[MangaSize] Applied option=%s old=%d size=%d source=%s",
		MangaSizeOption, OldSize, MangaSize, tostring( Source or "local" ) ) )
	if OldSize ~= MangaSize then
		Shine.Hook.Call( "OnMangaUISizeChanged", MangaSize, OldSize, Source or "local" )
	end
	return MangaSize
end

function GetMangaUIOpacity()
	return MangaOpacity / 100
end

function SetMangaUIOpacity( Opacity, Source )
	local OldOpacity = MangaOpacity
	MangaOpacity = math.max( 30, math.min( 100, math.floor( tonumber( Opacity ) or 100 ) ) )
	Client.SetOptionInteger( MangaOpacityOption, MangaOpacity )
	if OldOpacity ~= MangaOpacity then
		Shine.Hook.Call( "OnMangaUIOpacityChanged", MangaOpacity, OldOpacity, Source or "local" )
	end
	return MangaOpacity
end

function Plugin:ReceiveMangaOpacityState( Data )
	local Opacity = SetMangaUIOpacity( Data.Opacity, "!mangaopacity" )
	Shared.Message( string.format( "[MNGA] Mini-game window opacity set to %d%%.", Opacity ) )
end

function Plugin:ReceiveMangaSizeState( Data )
	local Size = SetMangaUISize( Data.Size, "!mangasize" )
	Shared.Message( string.format( "[MNGA] Mini-game UI size set to %d%%.", Size ) )
end

function Plugin:ReceiveMangaVolumeState( Data )
	MangaVolume = math.max( 0, math.min( 100, math.floor( tonumber( Data.Volume ) or 100 ) ) )
	Client.SetOptionInteger( MangaVolumeOption, MangaVolume )
	Shared.Message( string.format( "[MNGA] Mini-game sound volume set to %d%%.", MangaVolume ) )
	Print( "%s", string.format( "[MangaVolume] Applied and persisted option=%s volume=%d",
		MangaVolumeOption, MangaVolume ) )
end

local function IsEnemyGroupGameInProgress()
	local GameInfo = GetGameInfoEntity and GetGameInfoEntity()
	return GameInfo and ( GameInfo:GetCountdownActive() or GameInfo:GetGameStarted() ) or false
end

local function GetScoreboardSteamID( ClientIndex )
	if not Scoreboard_GetPlayerRecord or not ClientIndex or ClientIndex == 0 then return nil end
	local Entry = Scoreboard_GetPlayerRecord( ClientIndex )
	return Entry and tonumber( Entry.SteamId ) or nil
end

function Plugin:InstallEnemyGroupScoreboardHooks()
	if EnemyGroupScoreboardHookInstalled then return true end
	if not SSB_RegisterScoreboardIntegration or not Scoreboard_GetPlayerRecord then
		if not EnemyGroupScoreboardHookAttempted then
			EnemyGroupScoreboardHookAttempted = true
		end
		return false
	end

	SSB_RegisterScoreboardIntegration( "mnga_enemy_groups", {
		OnMenuOpened = function( Scoreboard )
			self:OnMNGAEnemyGroupScoreboardKey( Scoreboard )
		end,
		OnTeamUpdated = function( Scoreboard, Team )
			self:OnMNGAEnemyGroupScoreboardTeam( Scoreboard, Team )
		end
	} )
	EnemyGroupScoreboardHookInstalled = true
	Print( "[mnga_scoreboard] Registered enemy-group actions through the SSB integration API." )
	return true
end

function Plugin:ScheduleEnemyGroupScoreboardHooks()
	-- VoteRandom installs its friend-group scoreboard hook from OnFirstThink.
	-- Delay ours one frame so our action is appended after the friend action,
	-- regardless of extension load order.
	local EarliestInstallTime = ( Shared.GetTime and Shared.GetTime() or 0 ) + 0.1
	Shine.Hook.Remove( "Think", EnemyGroupScoreboardDeferredHook )
	Shine.Hook.Add( "Think", EnemyGroupScoreboardDeferredHook, function()
		if ( Shared.GetTime and Shared.GetTime() or 0 ) < EarliestInstallTime then return end
		if self:InstallEnemyGroupScoreboardHooks() then
			Shine.Hook.Remove( "Think", EnemyGroupScoreboardDeferredHook )
		end
	end )
end

function Plugin:OnMNGAEnemyGroupScoreboardKey( Scoreboard, Key, Down )
	if IsEnemyGroupGameInProgress() then return end
	local VoteRandom = Shine.Plugins and Shine.Plugins[ "voterandom" ]
	if not VoteRandom or not VoteRandom.Enabled then return end

	local HoverMenu = Scoreboard and Scoreboard.hoverMenu
	if not Scoreboard.visible or not HoverMenu or not HoverMenu.background
		or not HoverMenu.background:GetIsVisible() then return end
	local SteamID = GetScoreboardSteamID( Scoreboard.hoverPlayerClientIndex )
	if not SteamID or SteamID == Client.GetSteamId() then return end
	if VoteRandom.FriendGroup and VoteRandom.FriendGroup[ SteamID ] then return end

	local Buttons = HoverMenu.links
	if not Buttons then return end
	local BackgroundColour, HighlightColour, TextColour, EnemyButton
	for i = #Buttons, 1, -1 do
		local Button = Buttons[ i ]
		if Button.IsMNGAEnemyGroupButton then
			EnemyButton = Button.link
			break
		end
		if not BackgroundColour and not Button.isSeparator and Button.link then
			BackgroundColour = Button.bgColor
			HighlightColour = Button.bgHighlightColor
			TextColour = Button.link:GetColor()
		end
	end
	if not EnemyButton and not BackgroundColour then return end

	local IsEnemy = EnemyGroupState[ SteamID ] == true
	local Text = IsEnemy and "Remove from enemy group" or "Add to enemy group"
	if not EnemyButton then
		HoverMenu:AddSeparator( "MNGAEnemyGroupActions" )
		HoverMenu:AddButton( Text, BackgroundColour, HighlightColour, TextColour, function()
			local Action = EnemyGroupState[ SteamID ] and 2 or 1
			self:SendNetworkMessage( "EnemyGroupAction", {
				TargetSteamID = SteamID,
				Action = Action
			}, true )
		end )
		EnemyButton = HoverMenu.links[ #HoverMenu.links ]
		EnemyButton.IsMNGAEnemyGroupButton = true
		HoverMenu:AdjustMenuSize()
	elseif EnemyButton:GetText() ~= Text then
		EnemyButton:SetText( Text )
		HoverMenu:AdjustMenuSize()
	end
end

function Plugin:OnMNGAEnemyGroupScoreboardTeam( Scoreboard, Team )
	if IsEnemyGroupGameInProgress() or not Team or not Team.PlayerList then return end
	for i = 1, #Team.PlayerList do
		local Row = Team.PlayerList[ i ]
		local SteamID = Row and GetScoreboardSteamID( Row.ClientIndex )
		if SteamID and EnemyGroupState[ SteamID ] and Row.Background then
			Row.Background:SetColor( EnemyGroupRowColour )
		end
	end
end

function Plugin:ReceiveEnemyGroupState( Data )
	if type( Data ) ~= "table" then return end
	local SteamID = tonumber( Data.TargetSteamID )
	if SteamID == 0 and Data.IsEnemy == false then
		EnemyGroupState = {}
	elseif SteamID and SteamID > 0 then
		EnemyGroupState[ SteamID ] = Data.IsEnemy == true or nil
	end
	if Scoreboard_ReloadPlayerData then Scoreboard_ReloadPlayerData() end
end

local function TriggerForcedNotificationSound( SoundName, Reason )
	local Notifications = Shine.Plugins and Shine.Plugins[ "mngaforcednotifications" ]
	if not Notifications or not Notifications.Enabled then
		Print( "%s", string.format(
			"[mnganotify] mngaforcednotifications plugin not enabled; sound skipped for %s.",
			tostring( Reason )
		) )
		return
	end

	if type( Notifications.PlayNamedSound ) ~= "function" then
		Print( "%s", string.format(
			"[mnganotify] mngaforcednotifications PlayNamedSound missing; sound skipped for %s.",
			tostring( Reason )
		) )
		return
	end

	Print( "%s", string.format(
		"[mnganotify] requesting mngaforcednotifications %s sound for %s.",
		tostring( SoundName ), tostring( Reason )
	) )
	Notifications:PlayNamedSound( SoundName, Reason )
end

function Plugin:ReceiveSilentSeedingXPNotification( Data )
	-- Shine.AddChatText normally plays the local player's chat sound. Mask the
	-- sound function only for this synchronous call so every other chat and XP
	-- notification retains its normal audio cue.
	local OriginalStartSoundEffect = StartSoundEffect
	if OriginalStartSoundEffect then
		StartSoundEffect = function() end
	end

	local Success, Error = xpcall( function()
		Shine.AddChatText( 0, 0, 0, "", 1, 112 / 255, 77 / 255, Data.Message )
	end, debug.traceback )

	if OriginalStartSoundEffect then
		StartSoundEffect = OriginalStartSoundEffect
	end

	if Success then
		Print( "[mnga_xp] Displayed silent seeding XP notification." )
	else
		Print( "%s", string.format(
			"[mnga_xp] ERROR | Failed to display silent seeding XP notification: %s",
			tostring( Error )
		) )
	end
end

function Plugin:Initialise()
	local LegacyVolume = Client.GetOptionInteger( LegacyPokerVolumeOption, 100 )
	MangaVolume = math.max( 0, math.min( 100,
		Client.GetOptionInteger( MangaVolumeOption, LegacyVolume ) ) )
	Client.SetOptionInteger( MangaVolumeOption, MangaVolume )
	Print( "%s", string.format( "[MangaVolume] Loaded local option=%s volume=%d",
		MangaVolumeOption, MangaVolume ) )
	MangaSize = math.max( 30, math.min( 120,
		Client.GetOptionInteger( MangaSizeOption, 100 ) ) )
	Client.SetOptionInteger( MangaSizeOption, MangaSize )
	Print( "%s", string.format( "[MangaSize] Loaded local option=%s size=%d",
		MangaSizeOption, MangaSize ) )
	MangaOpacity = math.max( 30, math.min( 100,
		Client.GetOptionInteger( MangaOpacityOption, 100 ) ) )
	Client.SetOptionInteger( MangaOpacityOption, MangaOpacity )
	self:BroadcastModuleEvent( "Initialise" )
	self:SetupAdminMenuCommands()
	self:ScheduleEnemyGroupScoreboardHooks()
	self:InitialiseSpectatorDrawing()
	self:InitialiseSpectatorAllChatCooldown()
	-- A client-side request closes the small load-order window where a server
	-- ClientConnect sync could precede this extension's network receiver.
	self:SendNetworkMessage( "EnemyGroupRequestSync", {}, true )
	self.Enabled = true
	return true
end

function Plugin:OnFirstThink()
	self:ScheduleEnemyGroupScoreboardHooks()
end

function Plugin:SetupAdminMenuCommands()
	local Category = "mnga"

	-- Swap Player<->Spec: only offers the "Swap" option in the submenu when
	-- exactly 2 players are selected, one spectating and one on a playing team.
	self:AddAdminMenuCommand( Category, "Swap Player<->Spec", "sh_swap", true, {
		BuildMenuOptions = function( SelectedPlayerRows, MappingFunctions )
			if #SelectedPlayerRows ~= 2 then return {} end

			local row1, row2 = SelectedPlayerRows[ 1 ], SelectedPlayerRows[ 2 ]
			local team1 = row1:GetColumnText( 3 )
			local team2 = row2:GetColumnText( 3 )

			local specRow, playerRow = nil, nil

			if team1 == "Spectate" and team2 ~= "Spectate" and team2 ~= "Ready Room" then
				specRow, playerRow = row1, row2
			elseif team2 == "Spectate" and team1 ~= "Spectate" and team1 ~= "Ready Room" then
				specRow, playerRow = row2, row1
			else
				return {} -- invalid selection, grey out the swap option
			end

			local specArg = MappingFunctions.GetArgFromPlayer(
				specRow:GetColumnText( 2 ), specRow:GetColumnText( 1 ) )
			local playerArg = MappingFunctions.GetArgFromPlayer(
				playerRow:GetColumnText( 2 ), playerRow:GetColumnText( 1 ) )

			return {
				"Swap",
				function()
					Shine.AdminMenu:RunCommand( "sh_swap", specArg, playerArg )
				end
			}
		end
	}, "Select exactly 1 spectator and 1 playing player, then click to swap them." )
end

function Plugin:ReceivePregameCountdownAttention( Data )
	Print( "%s", string.format(
		"[mngapregame] countdown attention received at half-time; duration=%s",
		tostring( Data and Data.Duration )
	) )

	Client.WindowNeedsAttention()
	TriggerForcedNotificationSound( "RoundStarting", "pregame countdown" )
end

function Plugin:ReceiveQueuePromotionAttention()
	Print( "[mnganotify] queue position 1 promoted to ready room; forcing taskbar attention." )
	Client.WindowNeedsAttention()
end

-- "Third Person" button on the Shine vote menu (M) main page, shown only when the server
-- would allow it (same shared check). WrapCallback skips it while the plugin is disabled.
Shine.VoteMenu:EditPage( "Main", Plugin:WrapCallback( function( VoteMenu )
	local GameInfo = GetGameInfoEntity()
	local GameState = GameInfo and GameInfo:GetState()
	local Reason = Plugin.GetThirdPersonBlockReason( Client.GetLocalPlayer(), GameState )
	if Reason then return end

	local Button = VoteMenu:AddSideButton( "Third Person", function()
		Shared.ConsoleCommand( "sh_thirdperson" )
		VoteMenu:ForceHide()
	end )
	Button.Plugin = "mngaadministration"
	Button.DefaultText = "Third Person"
	Button:SetDebugName( "VoteMenuMNGAThirdPersonButton" )
end ) )

function Plugin:Cleanup()
	EnemyGroupState = {}
	if SSB_UnregisterScoreboardIntegration then
		SSB_UnregisterScoreboardIntegration( "mnga_enemy_groups" )
	end
	EnemyGroupScoreboardHookInstalled = false
	Shine.Hook.Remove( "Think", EnemyGroupScoreboardDeferredHook )
	if self.CleanupSpectatorDrawing then
		self:CleanupSpectatorDrawing()
	end
	if self.CleanupSpectatorAllChatCooldown then
		self:CleanupSpectatorAllChatCooldown()
	end
	self.BaseClass.Cleanup( self )
end
