local Plugin = ...
local StringFormat = string.format

function Plugin:InitialiseMangaVolume()
	local Command = self:BindCommand( "sh_mangavolume", "mangavolume", function( Client, Volume )
		if not Client then return end
		Volume = math.max( 0, math.min( 100, math.floor( Volume ) ) )
		self:SendNetworkMessage( Client, "MangaVolumeState", { Volume = Volume }, true )
		Print( "%s", StringFormat( "[MangaVolume] Sent local preference update steamid=%s volume=%d",
			tostring( Client:GetUserId() ), Volume ) )
	end, true )
	Command:AddParam{ Type = "number", Min = 0, Max = 100, Round = true,
		Error = "Usage: !mangavolume <0-100>", Help = "volume percent" }
	Command:Help( "Sets the Poker sound volume." )
	Print( "[MangaVolume] Registered !mangavolume client-persisted mini-game volume command." )
end

function Plugin:CleanupMangaVolume()
end
