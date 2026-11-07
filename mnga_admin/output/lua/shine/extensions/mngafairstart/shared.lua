local Plugin = Shine.Plugin( ... )

Plugin.Version = "1.1.0"
Plugin.HasConfig = true
Plugin.ConfigName = "mngafairstart.json"
Plugin.DefaultState = false
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.DefaultConfig = {
	Enabled = true,
	Debug = true,
	DestroyCandidateRoomPower = true,

	-- Empty means every map. Set a map name to false to disable just that map.
	Maps = {},

	-- Lower-case map/location names. Each key is the actual marine start, and
	-- each value is the possible alien starts for that marine start. This is
	-- only used if vanilla spawn_selection_override data is unavailable.
	SpawnPairs = {}
}

return Plugin
