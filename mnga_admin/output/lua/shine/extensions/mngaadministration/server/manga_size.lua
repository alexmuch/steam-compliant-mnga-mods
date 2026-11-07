local Plugin = ...
local StringFormat = string.format

function Plugin:InitialiseMangaSize()
	local Command = self:BindCommand( "sh_mangasize", "mangasize", function( Client, Size )
		if not Client then return end
		Size = math.max( 30, math.min( 120, math.floor( Size ) ) )
		self:SendNetworkMessage( Client, "MangaSizeState", { Size = Size }, true )
		Print( "%s", StringFormat( "[MangaSize] Sent local preference update steamid=%s size=%d",
			tostring( Client:GetUserId() ), Size ) )
	end, true )
	Command:AddParam{ Type = "number", Min = 30, Max = 120, Round = true,
		Error = "Usage: !mangasize <30-120>", Help = "UI size percent" }
	Command:Help( "Sets the Poker UI size." )
	Print( "[MangaSize] Registered !mangasize client-persisted mini-game size command." )
end

function Plugin:CleanupMangaSize()
end
