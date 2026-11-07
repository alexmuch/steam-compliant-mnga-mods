local kVersion = "2.2.0-development"
local kName = "steam_compliant_shimizu_scoreboard"

if Client then
    HPrint(kName .. ", version " .. kVersion)
end

--Hooks
ModLoader.SetupFileHook("lua/GUIScoreboard.lua", "lua/shimizuscoreboard/GUIScoreboard.lua", "post")
ModLoader.SetupFileHook("lua/menu/GUIHoverTooltip.lua", "lua/shimizuscoreboard/GUIHoverTooltip.lua", "post")
ModLoader.SetupFileHook("lua/PlayerInfoEntity.lua", "lua/shimizuscoreboard/PlayerInfoEntity.lua", "post")
ModLoader.SetupFileHook("lua/Scoreboard.lua", "lua/shimizuscoreboard/Scoreboard.lua", "post")
ModLoader.SetupFileHook("lua/NetworkMessages.lua", "lua/shimizuscoreboard/NetworkMessages.lua", "post")
ModLoader.SetupFileHook("lua/NetworkMessages_Client.lua", "lua/shimizuscoreboard/PlayerAliases.lua", "post")
ModLoader.SetupFileHook("lua/NetworkMessages_Client.lua", "lua/shimizuscoreboard/ChatMute_Client.lua", "post")
ModLoader.SetupFileHook("lua/NetworkMessages_Client.lua", "lua/shimizuscoreboard/NetworkMessages_Client.lua", "post")
ModLoader.SetupFileHook("lua/NetworkMessages_Client.lua", "lua/shimizuscoreboard/LowVoiceMutedBy_Client.lua", "post")
ModLoader.SetupFileHook("lua/NetworkMessages_Client.lua", "lua/shimizuscoreboard/PlayerAliasPresentation.lua", "post")
ModLoader.SetupFileHook("lua/NetworkMessages_Server.lua", "lua/shimizuscoreboard/NetworkMessages_Server.lua", "post")
ModLoader.SetupFileHook("lua/SoundEffect.lua", "lua/shimizuscoreboard/SoundEffectCallMute.lua", "post")
ModLoader.SetupFileHook("lua/Player_Server.lua", "lua/shimizuscoreboard/PlayerServerTeamVoiceMute.lua", "post")
ModLoader.SetupFileHook("lua/NS2Gamerules.lua", "lua/shimizuscoreboard/NS2GamerulesMute.lua", "post")
