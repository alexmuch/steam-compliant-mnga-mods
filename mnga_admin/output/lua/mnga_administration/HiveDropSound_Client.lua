-- Team-wide hive drop sound (.claude/docs/hive-drop-sound.md): play the far
-- copy of hive_spawn. It is a 3D FMOD event, so parent it to the local player
-- (3D, follows the listener) rather than playing it 2D.

if not Client or MNGAHiveDropSoundClientInstalled then return end
MNGAHiveDropSoundClientInstalled = true

local function OnHiveDropSound(message)
    local player = Client.GetLocalPlayer()
    if not player then return end
    Shared.PlaySound(player, MNGA_HIVE_DROP_SOUND.Sound, MNGA_HIVE_DROP_SOUND.Volume)
end

Client.HookNetworkMessage("MNGAHiveDropSound", OnHiveDropSound)
