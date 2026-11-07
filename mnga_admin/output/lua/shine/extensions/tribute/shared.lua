local Plugin = Shine.Plugin( ... )

Plugin.Version = "1.0"
Plugin.PrintName = "Tribute"
Plugin.HasConfig = true
Plugin.ConfigName = "Tribute.json"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.DefaultState = false

Plugin.DefaultConfig = {
	EnableDebugLogs = true
}

return Plugin
