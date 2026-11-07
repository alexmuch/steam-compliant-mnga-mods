local Plugin = ...

function Plugin:InitialiseMangaOpacity()
	local Command = self:BindCommand( "sh_mangaopacity", "mangaopacity", function( Client, Opacity )
		if not Client then return end
		Opacity = math.max( 30, math.min( 100, math.floor( Opacity ) ) )
		self:SendNetworkMessage( Client, "MangaOpacityState", { Opacity = Opacity }, true )
	end, true )
	Command:AddParam{ Type = "number", Min = 30, Max = 100, Round = true,
		Error = "Usage: !mangaopacity <30-100>", Help = "UI opacity percent" }
	Command:Help( "Sets the shared Poker and Match3 window opacity." )
end

function Plugin:CleanupMangaOpacity()
end
