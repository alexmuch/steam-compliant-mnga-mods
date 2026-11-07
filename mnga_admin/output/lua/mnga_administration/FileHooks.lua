local kVersion = "0.1.0"
local kName = "mnga_administration"

if Client then
    HPrint(kName .. ", version " .. kVersion)
end

--Hooks

-- Experimental client gamma range. Render.lua reads Client.MaxRenderGamma when
-- synchronizing the saved setting, while MenuData.lua owns the visible slider.
ModLoader.SetupFileHook("lua/Render.lua", "lua/mnga_administration/ExtendedGamma_Render.lua", "pre")
ModLoader.SetupFileHook("lua/menu2/MenuData.lua", "lua/mnga_administration/ExtendedGamma_MenuData.lua", "post")

-- Keep player-selected voice and text mutes until explicitly removed. Load
-- after vanilla Chat.lua and Shine; never replace the chat implementation.
ModLoader.SetupFileHook("lua/NetworkMessages_Client.lua", "lua/mnga_administration/PermanentMutes_Client.lua", "post")

-- Raise the engine-wide UTF-8 player-name cap before network message schemas
-- derive their string sizes from kMaxNameLength.
ModLoader.SetupFileHook("lua/Globals.lua", "lua/mnga_administration/NameLength.lua", "post")

-- Main/Escape menu MNGA information button. GUIMainMenu only exists in the
-- client VM, so this hook is safe to register for both client and server.
ModLoader.SetupFileHook("lua/menu2/GUIMainMenu.lua", "lua/mnga_administration/GUIMainMenu_Post.lua", "post")

-- Client QoL settings and commander-button cooldown countdown numbers.
ModLoader.SetupFileHook("lua/menu2/NavBar/Screens/Options/Mods/ModsMenuData.lua", "lua/mnga_administration/ShimizuQoLModsMenu.lua", "post")
ModLoader.SetupFileHook("lua/GUICommanderButtons.lua", "lua/mnga_administration/GUICommanderCooldownNumbers.lua", "post")

-- Teammate health bars for field players (Shimizu QoL mode/key/scope). Client only.
ModLoader.SetupFileHook("lua/Player_Client.lua", "lua/mnga_administration/TeamHealthBars_Client.lua", "post")
ModLoader.SetupFileHook("lua/BindingsDialog.lua", "lua/mnga_administration/TeamHealthBarsBindings.lua", "post")
ModLoader.SetupFileHook("lua/ClientUI.lua", "lua/mnga_administration/TeamHealthBarsClientUI.lua", "post")
ModLoader.SetupFileHook("lua/GUIUnitStatus.lua", "lua/mnga_administration/TeamHealthBars_GUIUnitStatus.lua", "post")

-- Marine top bar ARC count. TeamInfoMultiPing owns the replicated count;
-- this post-hook loads the marine-only display class after vanilla widgets.
ModLoader.SetupFileHook("lua/Hud2/topBar/GUIHudTopBarObjectClasses.lua", "lua/mnga_administration/GUIHudARCCount.lua", "post")

-- Vanilla only tells the casting commander about an ability cooldown. Mirror
-- active team cooldowns through vanilla AbilityResult on their first move.
ModLoader.SetupFileHook("lua/Commander.lua", "lua/mnga_administration/CommanderCooldownHandoff.lua", "post")

-- Respawning aliens with no remembered chamber pick get a fixed upgrade
-- (Shell: Carapace, Spur: Celerity, Veil: Aura) instead of a random one.
ModLoader.SetupFileHook("lua/Egg.lua", "lua/mnga_administration/EggFixedUpgrades.lua", "post")

-- Player orders: alien support, per-recipient marker pacing, and local voice pacing.
ModLoader.SetupFileHook("lua/PlayingTeam.lua", "lua/mnga_administration/AlienPlayerOrderTechTree.lua", "post")
ModLoader.SetupFileHook("lua/TechTreeButtons.lua", "lua/mnga_administration/AlienPlayerOrderIcons.lua", "post")
ModLoader.SetupFileHook("lua/OrdersMixin.lua", "lua/mnga_administration/AlienBotDefendOrders.lua", "post")
ModLoader.SetupFileHook("lua/Alien.lua", "lua/mnga_administration/AlienPlayerOrders.lua", "post")
-- First-minute "X has gone gorge (gorge count: N)" alert to the alien team.
-- Embryo, not Alien: betteregg replaces Alien:ProcessBuyAction.
ModLoader.SetupFileHook("lua/Embryo.lua", "lua/mnga_administration/EarlyGorgeAlert.lua", "post")
ModLoader.SetupFileHook("lua/Gorge_Server.lua", "lua/mnga_administration/GorgePlayerOrders.lua", "post")
ModLoader.SetupFileHook("lua/Commander_Server.lua", "lua/mnga_administration/CommanderPlayerOrderPacing.lua", "post")
-- Commander order targets: last-seen positions of enemy non-players.
ModLoader.SetupFileHook("lua/LOSMixin.lua", "lua/mnga_administration/LOSOrderMemory.lua", "post")
ModLoader.SetupFileHook("lua/NS2Gamerules.lua", "lua/mnga_administration/PlayerOrderLifecycle.lua", "post")
ModLoader.SetupFileHook("lua/GUIWaypoints.lua", "lua/mnga_administration/PlayerOrderVoicePacing.lua", "post")
ModLoader.SetupFileHook("lua/ServerConfig.lua", "lua/mnga_administration/WaypointsOptionLock_Server.lua", "post")
ModLoader.SetupFileHook("lua/Player_Client.lua", "lua/mnga_administration/AlienPlayerOrderWaypoints.lua", "post")
-- These brain data replacements add an order action beside the original local
-- lifeform movement and attack routines, which post hooks cannot call.
ModLoader.SetupFileHook("lua/bots/SkulkBrain_Data.lua", "lua/mnga_administration/SkulkBrain_DataOrders.lua", "replace")
ModLoader.SetupFileHook("lua/bots/LerkBrain_Data.lua", "lua/mnga_administration/LerkBrain_DataOrders.lua", "replace")
ModLoader.SetupFileHook("lua/bots/FadeBrain_Data.lua", "lua/mnga_administration/FadeBrain_DataOrders.lua", "replace")
ModLoader.SetupFileHook("lua/bots/OnosBrain_Data.lua", "lua/mnga_administration/OnosBrain_DataOrders.lua", "replace")
ModLoader.SetupFileHook("lua/bots/GorgeBrain_Data.lua", "lua/mnga_administration/GorgeBrain_DataOrders.lua", "replace")

-- Custom skill tiers 8/9. The skill icon atlas is ui/skill_tier_icons.dds:
-- 100x32 rows indexed by tier + 2.
ModLoader.SetupFileHook("lua/NS2Utility.lua", "lua/mnga_administration/NS2UtilitySkillTiers.lua", "post")

-- Scoreboard records and live-scoreboard integrations are owned by the
-- standalone Shimizu Scoreboard mod. shimizu (post-round) score screen owns its
-- own NS2Manga profile action and requires no MNGA GUIGameEndStats wrapper.

-- ban vote evading, fix spam voting bug
ModLoader.SetupFileHook("lua/Voting.lua", "lua/mnga_administration/Voting.lua", "replace")
ModLoader.SetupFileHook("lua/VotingKickPlayer.lua", "lua/mnga_administration/VotingKickPlayer.lua", "post")
ModLoader.SetupFileHook("lua/GUIVoteMenu.lua", "lua/mnga_administration/GUIVoteMenuEligibility.lua", "post")

-- Remove spawn damage in pre-game
ModLoader.SetupFileHook("lua/NS2Gamerules.lua", "lua/mnga_administration/NS2Gamerules.lua", "post")

-- Silence bot calls for meds/ammo
ModLoader.SetupFileHook("lua/PlayingTeam.lua", "lua/mnga_administration/PlayingTeamMuteBot.lua", "post")

-- Vanilla bot_setupdev and bv_percep turn cheats on with no permission check, and
-- ! then runs Lua for any player. Pre hooks: the guard must wrap Event.Hook before
-- these files register the commands. Whichever file loads first installs it.
-- NS2ConsoleCommands_Server.lua (devtrace) loads from NS2Gamerules.lua, before both others.
ModLoader.SetupFileHook("lua/NS2ConsoleCommands_Server.lua", "lua/mnga_administration/DevCommandGuard.lua", "pre")
ModLoader.SetupFileHook("lua/bots/BotUtils.lua", "lua/mnga_administration/DevCommandGuard.lua", "pre")
ModLoader.SetupFileHook("lua/ConsoleCommands_Server.lua", "lua/mnga_administration/DevCommandGuard.lua", "pre")
-- The sh_admindebug commands register in these files. Each gets its own pre hook,
-- so load order cannot let one register before the wrap. Repeat installs return early.
ModLoader.SetupFileHook("lua/bots/BotDebug.lua", "lua/mnga_administration/DevCommandGuard.lua", "pre")
ModLoader.SetupFileHook("lua/bots/Bot_Server.lua", "lua/mnga_administration/DevCommandGuard.lua", "pre")
ModLoader.SetupFileHook("lua/bots/LocationGraph.lua", "lua/mnga_administration/DevCommandGuard.lua", "pre")
ModLoader.SetupFileHook("lua/ServerPerformanceData.lua", "lua/mnga_administration/DevCommandGuard.lua", "pre")
ModLoader.SetupFileHook("lua/Cyst.lua", "lua/mnga_administration/DevCommandGuard.lua", "pre")
ModLoader.SetupFileHook("lua/thunderdome/ThunderdomeRules.lua", "lua/mnga_administration/DevCommandGuard.lua", "pre")
ModLoader.SetupFileHook("lua/shimizubetterspectator/Diagnostics.lua", "lua/mnga_administration/DevCommandGuard.lua", "pre")
-- Client debug commands dbg_locgates (Location.lua, loaded from Shared.lua) and
-- bot_test* (GBDMainWindow.lua) have no permission check either. Same pre-hook trick.
ModLoader.SetupFileHook("lua/Location.lua", "lua/mnga_administration/DevCommandGuard_Client.lua", "pre")
ModLoader.SetupFileHook("lua/bots/DebugGUI/GBDMainWindow.lua", "lua/mnga_administration/DevCommandGuard_Client.lua", "pre")

-- Configurable bot difficulty and vanilla progressive bot-controller support.
ModLoader.SetupFileHook("lua/bots/BotAim.lua", "lua/mnga_administration/BotAimTierOverride.lua", "post")
ModLoader.SetupFileHook("lua/bots/PlayerBot_Server.lua", "lua/mnga_administration/SkulkNerf.lua", "post")
ModLoader.SetupFileHook("lua/bots/BotTeamController.lua", "lua/mnga_administration/GradualVanillaBots.lua", "post")
ModLoader.SetupFileHook("lua/bots/CommonAlienActions.lua", "lua/mnga_administration/CommonAlienActionsTunnelFix.lua", "post")

-- Prevent marine bot commanders from selecting the MAC production action.
ModLoader.SetupFileHook("lua/bots/MarineCommanderBrain_Data.lua", "lua/mnga_administration/MarineCommanderNoMACs.lua", "post")

-- Let players enter a freshly built hive immediately instead of waiting for the "opened" animation tag.
ModLoader.SetupFileHook("lua/Hive_Server.lua", "lua/mnga_administration/HiveInstantLogin.lua", "post")

-- Manual weapon pickup needs a fresh Use press after each pickup (stops E-held swap ping-pong).
ModLoader.SetupFileHook("lua/Marine.lua", "lua/mnga_administration/MarineWeaponSwapLatch.lua", "post")

-- Do not let generic Grow-order handling send Drifters to Gorge-only deployables.
ModLoader.SetupFileHook("lua/Drifter.lua", "lua/mnga_administration/DrifterGrowTargetFilter.lua", "post")

-- Show every simultaneous Hive biomass research on its own consecutive biomass
-- icon instead of letting AlienTeam collapse them into one progress value.
ModLoader.SetupFileHook("lua/AlienTeam.lua", "lua/mnga_administration/AlienTeamBiomassDisplay.lua", "post")
ModLoader.SetupFileHook("lua/GUIBioMassDisplay.lua", "lua/mnga_administration/GUIBioMassPartialProgress.lua", "post")

-- Preserve alien LOS/minimap visibility when parasite state moves between an
-- occupied Exo and its dropped Exosuit.
ModLoader.SetupFileHook("lua/ParasiteMixin.lua", "lua/mnga_administration/ParasiteTransferFix.lua", "post")

-- Give completed commander-created lifeform eggs their lifeform icon for aliens,
-- while keeping the ordinary egg icon during research and on marine minimaps.
ModLoader.SetupFileHook("lua/Egg.lua", "lua/mnga_administration/LifeformEggMapBlips.lua", "post")
ModLoader.SetupFileHook("lua/MapBlip.lua", "lua/mnga_administration/LifeformEggMapBlips_Client.lua", "post")

-- Warm the full alien bot-brain paths used by player hallucinations before a
-- round can begin, avoiding the cold first-cast hitch during live play.
ModLoader.SetupFileHook("lua/AlienHallucination.lua", "lua/mnga_administration/HallucinationBrainWarmup.lua", "post")

-- Fix web console spam
ModLoader.SetupFileHook("lua/Weapons/Alien/Web.lua", "lua/mnga_administration/Web.lua", "post")

-- Keep marine weapon drops gentle when they originate beside an active friendly
-- Armory, preventing the vanilla toss from ricocheting outside attach range.
ModLoader.SetupFileHook("lua/Weapons/Weapon_Server.lua", "lua/mnga_administration/WeaponDropArmoryPhysics.lua", "post")

-- Stop commander- and MAC-built marine structures overlapping PowerPoints.
ModLoader.SetupFileHook("lua/BuildUtility.lua", "lua/mnga_administration/BuildUtilityPowerPointPlacement.lua", "post")

-- Stop Arms Labs and Observatories being embedded in static map geometry.
ModLoader.SetupFileHook("lua/BuildUtility.lua", "lua/mnga_administration/BuildUtilityWorldGeometryPlacement.lua", "post")

-- Prevent unbuilt Robotics/ARC Factory blueprints being used as platforms. A filtered
-- grounding trace distinguishes landing on top from normal side contact while
-- constructing the blueprint.
ModLoader.SetupFileHook("lua/RoboticsFactory.lua", "lua/mnga_administration/RoboticsFactoryArcBlueprint.lua", "post")

-- MVP belt
ModLoader.SetupFileHook("lua/NetworkMessages.lua", "lua/mnga_administration/NetworkMessages.lua", "post")
ModLoader.SetupFileHook("lua/NetworkMessages_Client.lua", "lua/mnga_administration/NetworkMessages_Client.lua", "post")
ModLoader.SetupFileHook("lua/SpecialSkillTierRecipients.lua", "lua/mnga_administration/SpecialSkillTierRecipients.lua", "replace")

-- Fix belt bug on deathscreen
ModLoader.SetupFileHook("lua/GUIDeathScreen2.lua", "lua/mnga_administration/GUIDeathScreen2.lua", "post")

-- Individual pings

ModLoader.SetupFileHook("lua/GUIMinimap.lua", "lua/mnga_administration/GUIMinimapMultiPing.lua", "post")
ModLoader.SetupFileHook("lua/GUIPing.lua", "lua/mnga_administration/GUIPingMultiPing.lua", "post")
ModLoader.SetupFileHook("lua/Player_Client.lua", "lua/mnga_administration/Player_ClientMultiPing.lua", "post")
-- CBM FINAL VERSION ships its own TeamInfo.lua (64-bit tech masks); a plain replace would drop it, so use the merged copy.
if GetFileExists("lua/cbmfinal/FileHooks.lua") then
    Shared.Message("[multiping] CBM FINAL VERSION present, using TeamInfoMultiPing_CBM.lua")
    ModLoader.SetupFileHook("lua/TeamInfo.lua", "lua/mnga_administration/TeamInfoMultiPing_CBM.lua", "replace")
else
    ModLoader.SetupFileHook("lua/TeamInfo.lua", "lua/mnga_administration/TeamInfoMultiPing.lua", "replace")
end
ModLoader.SetupFileHook("lua/PlayingTeam.lua", "lua/mnga_administration/PlayingTeamMultiPing.lua", "post")
ModLoader.SetupFileHook("lua/VoiceOver.lua", "lua/mnga_administration/VoiceOverMultiPing.lua", "post")
ModLoader.SetupFileHook("lua/NetworkMessages_Server.lua", "lua/mnga_administration/NetworkMessages_ServerMultiPing.lua", "post")

-- Individual pings: dead players right-click the open map to ping
ModLoader.SetupFileHook("lua/NetworkMessages.lua", "lua/mnga_administration/NetworkMessagesMultiPing.lua", "post")
ModLoader.SetupFileHook("lua/GUIMinimapFrame.lua", "lua/mnga_administration/GUIMinimapFrameMultiPing.lua", "post")
ModLoader.SetupFileHook("lua/GUIFirstPersonSpectate.lua", "lua/mnga_administration/GUIFirstPersonSpectateMultiPing.lua", "post")

-- Numbered radio-command menu. The companion radiovoice FMOD bank supplies all
-- event assets referenced by RadioCommandsRegistry.lua.
ModLoader.SetupFileHook("lua/BindingsDialog.lua", "lua/mnga_administration/RadioCommandsBindings.lua", "post")
ModLoader.SetupFileHook("lua/menu2/NavBar/Screens/Options/Mods/ModsMenuData.lua", "lua/mnga_administration/RadioCommandsModsMenu.lua", "post")
ModLoader.SetupFileHook("lua/ClientUI.lua", "lua/mnga_administration/RadioCommandsClientUI.lua", "post")
-- Research-in-progress list for dead/respawning players (vanilla shows it only while alive).
ModLoader.SetupFileHook("lua/ClientUI.lua", "lua/mnga_administration/DeadResearchClientUI.lua", "post")
-- Vanilla GUIEvent drops an item pushed past the max; keep before DeadResearchHandoff.
ModLoader.SetupFileHook("lua/Hud/GUIEvent.lua", "lua/mnga_administration/ResearchListOverflowFix.lua", "post")
ModLoader.SetupFileHook("lua/Hud/GUIEvent.lua", "lua/mnga_administration/DeadResearchHandoff.lua", "post")
ModLoader.SetupFileHook("lua/Hud/Marine/GUIMarineHUD.lua", "lua/mnga_administration/DeadResearchMarineHUD.lua", "post")
-- Biomass research in the field players' research list: instanced per hive
-- (shared, server + client must agree) and titled with the level it reaches.
ModLoader.SetupFileHook("lua/TechTree.lua", "lua/mnga_administration/BiomassResearchInstanced.lua", "post")
ModLoader.SetupFileHook("lua/Hud/GUIEvent.lua", "lua/mnga_administration/BiomassResearchListLabel.lua", "post")
ModLoader.SetupFileHook("lua/NetworkMessages.lua", "lua/mnga_administration/RadioCommandsNetworkMessages.lua", "post")
ModLoader.SetupFileHook("lua/NetworkMessages_Server.lua", "lua/mnga_administration/RadioCommandsServer.lua", "post")
ModLoader.SetupFileHook("lua/NetworkMessages_Client.lua", "lua/mnga_administration/RadioCommandsClient.lua", "post")
ModLoader.SetupFileHook("lua/NS2Gamerules.lua", "lua/mnga_administration/RadioCommandsRecentKills.lua", "post")

-- Contextual pings (.claude/docs/contextual-ping.md): pinging an enemy/friendly
-- entity highlights it for the team; dropped items get a "Pick up" callout.
-- Marks/netvars live in PlayingTeamMultiPing/TeamInfoMultiPing; network
-- messages and the client ping hint in NetworkMessagesMultiPing; voicelines in
-- RadioCommandsRegistry/RadioCommandsServer.
ModLoader.SetupFileHook("lua/NetworkMessages_Server.lua", "lua/mnga_administration/ContextPingServer.lua", "post")
ModLoader.SetupFileHook("lua/Player_Client.lua", "lua/mnga_administration/ContextPingHighlight_Client.lua", "post")
-- marine viewers: commander attack-order style target icon instead of the glow
ModLoader.SetupFileHook("lua/Player_Client.lua", "lua/mnga_administration/ContextPingTargetIcon_Client.lua", "post")
ModLoader.SetupFileHook("lua/MapBlip.lua", "lua/mnga_administration/ContextPingMapBlip_Client.lua", "post")
ModLoader.SetupFileHook("lua/Commander_Client.lua", "lua/mnga_administration/ContextPingCommander_Client.lua", "post")

-- Muted voice indicator (.claude/docs/muted-voice-indicator.md): while a player
-- you voice-muted is talking, show an anonymous "Muted" voice bar to help avoid
-- crosstalk. Server wraps Player:GetClientMuted (used by vanilla and Shine hear
-- checks) and notifies the listener; toggle in Mods > Shimizu QoL.
ModLoader.SetupFileHook("lua/NetworkMessages.lua", "lua/mnga_administration/MutedVoiceIndicator_Shared.lua", "post")
-- Player_Server.lua (not NS2Gamerules.lua): Shared.lua loads NS2Gamerules
-- before Player.lua, so Player is still nil at NS2Gamerules post-hook time.
ModLoader.SetupFileHook("lua/Player_Server.lua", "lua/mnga_administration/MutedVoiceIndicator_Server.lua", "post")
ModLoader.SetupFileHook("lua/NetworkMessages_Client.lua", "lua/mnga_administration/MutedVoiceIndicator_Client.lua", "post")
ModLoader.SetupFileHook("lua/GUIVoiceChat.lua", "lua/mnga_administration/GUIVoiceChatMutedIndicator.lua", "post")

-- Team-wide hive drop sound (.claude/docs/hive-drop-sound.md): aliens farther
-- than 50 m from a commander-dropped hive hear hive_spawn at quarter volume.
ModLoader.SetupFileHook("lua/NetworkMessages.lua", "lua/mnga_administration/HiveDropSound_Shared.lua", "post")
ModLoader.SetupFileHook("lua/NS2Utility_Server.lua", "lua/mnga_administration/HiveDropSound_Server.lua", "post")
ModLoader.SetupFileHook("lua/NetworkMessages_Client.lua", "lua/mnga_administration/HiveDropSound_Client.lua", "post")

-- Name-aware Shine chat (.claude/docs/player-alias-coverage.md): names travel as
-- Steam ID + real name beside the text so each client shows its SSB alias.
ModLoader.SetupFileHook("lua/NetworkMessages.lua", "lua/mnga_administration/NameNotify_Shared.lua", "post")
ModLoader.SetupFileHook("lua/NetworkMessages_Client.lua", "lua/mnga_administration/NameNotify_Client.lua", "post")

-- Ghost client heartbeat (.claude/docs/ghost-connector.md): every 15 s log engine
-- vs Lua player-slot counts and Lua client IPs for the ns2dropghost host watcher.
if Server then
    Script.Load("lua/mnga_administration/GhostClientHeartbeat.lua")
end
