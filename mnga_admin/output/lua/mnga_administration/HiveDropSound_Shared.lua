-- Team-wide hive drop sound (.claude/docs/hive-drop-sound.md): shared constants
-- and the server -> far alien "a hive was dropped" message.

MNGA_HIVE_DROP_SOUND = MNGA_HIVE_DROP_SOUND or {
    Sound = PrecacheAsset("sound/NS2.fev/alien/structures/hive_spawn"),
    -- Aliens within this range hear only the vanilla positional sound. Matches
    -- the vanilla SoundEffect relevancy distance (kDefaultMaxAudibleDistance in
    -- core/lua/SoundEffect.lua): beyond it the vanilla sound is never sent.
    NearRange = 50,
    -- Client playback volume for the far copy.
    Volume = 0.25
}

Shared.RegisterNetworkMessage( "MNGAHiveDropSound", {
    hiveId = "entityid"
} )
