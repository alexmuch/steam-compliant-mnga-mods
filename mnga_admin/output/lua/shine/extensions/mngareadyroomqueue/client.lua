local Plugin = ...

-- Reset on every script/plugin load. The server revision restarts from zero
-- when the extension is reloaded on the same map, so retaining these globals
-- would make the client reject the replacement extension's snapshots.
MNGAReadyRoomQueuePositions = {}
MNGAReadyRoomQueueRevision = 0

function Plugin:ReceiveQueueSnapshotReset( Data )
	if Data.Revision < MNGAReadyRoomQueueRevision then return end
	MNGAReadyRoomQueueRevision = Data.Revision
	MNGAReadyRoomQueuePositions = {}
	if Scoreboard_ReloadPlayerData then Scoreboard_ReloadPlayerData() end
end

function Plugin:ReceiveQueueStatus( Data )
	if Data.Revision < MNGAReadyRoomQueueRevision then return end
	if Data.Revision > MNGAReadyRoomQueueRevision then
		MNGAReadyRoomQueueRevision = Data.Revision
		MNGAReadyRoomQueuePositions = {}
	end
	MNGAReadyRoomQueuePositions[ tonumber( Data.SteamID ) ] = Data.Position
	if Scoreboard_ReloadPlayerData then Scoreboard_ReloadPlayerData() end
end

function Plugin:ReceiveQueueLeft()
	self:Notify( "A player slot is ready. You were moved to the Ready Room." )
	Client.WindowNeedsAttention()
end

return Plugin
