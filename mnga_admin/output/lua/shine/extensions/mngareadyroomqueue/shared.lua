local Plugin = Shine.Plugin( ... )

Plugin.Version = "0.4.2-spectator-first-human-threshold"
Plugin.PrintName = "MNGA Ready Room Queue"
Plugin.NotifyPrefixColour = {
	255, 160, 0
}
Plugin.HasConfig = true
Plugin.ConfigName = "mngareadyroomqueue.json"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.CheckConfigRecursively = true
Plugin.DefaultState = false

Plugin.DefaultConfig = {
	OperatingMode = "authoritative",
	ProcessInterval = 0.5,
	PlayerSlotLimit = 20,
	ConnectionReservation = "enforce", -- disabled, shadow, enforce
	-- Opt-in mode. Fresh arrivals load as spectators when at least 15 other
	-- humans are connected; eligible arrivals confirming within 120 seconds
	-- use the existing queue processor.
	SpectatorFirst = false,
	RestoreQueueAfterMapchange = true,
	QueueHistoryLifeTime = 300,
	QueuePositionMaxReservationTime = 300,
	VIPPlayers = {
		Enabled = false,
		PermissionString = "sh_vip"
	},
	Debug = false,
	-- High-volume player-slot accounting diagnostics. Enable only for a
	-- bounded investigation; production keeps the essential events below.
	CapacityDebug = false,
	CapacitySampleInterval = 5,
	CapacityEventCooldown = 5,
	CapacityDetailCooldown = 10,
	-- Bounded validation of restored queue claims. This records at most two
	-- lines per restored Steam ID.
	HistoryClaimShadowDebug = false,
	-- Behaviour-neutral evidence collection for the owned spectator-first
	-- admission mode, including open-slot/empty-queue arrivals. Handoff intent
	-- is frozen at the admission check; full-server arrivals remain viewers.
	-- This never changes connection or queue decisions.
	SpectatorFirstShadow = false,
	SpectatorFirstShadowLifetime = 180,
	-- Extremely noisy per-tick diagnostics. Keep this off even when Debug is
	-- temporarily enabled for queue lifecycle/event logging.
	VerboseDebug = false
}

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "QueueSnapshotReset", { Revision = "integer" }, "Client" )
	self:AddNetworkMessage( "QueueStatus", {
		Revision = "integer",
		SteamID = "string (16)",
		Position = "integer"
	}, "Client" )
	self:AddNetworkMessage( "QueueLeft", {}, "Client" )
end

return Plugin
