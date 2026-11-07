local Plugin = Shine.Plugin( ... )

Plugin.Version = "1.2"
Plugin.PrintName = "Name Guard"
Plugin.HasConfig = true
Plugin.ConfigName = "NameGuard.json"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.DefaultState = true

Plugin.DefaultConfig = {
	Enabled = true,
	MaxNameCharacters = 25,
	MaxVisualNameUnits = 16.7,
	SnapshotTTLSeconds = 7200,
	PostLoadValidationDelay = 3
}

return Plugin
