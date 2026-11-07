local Plugin = ...

-- The Match3 (!m3) and Bejewelled (!bj) mini-games come from separate Workshop
-- mods. Swallow their chat commands silently and disable their console
-- commands so typing either does nothing. Their plugins may load before or
-- after this one and re-bind on reload, so re-apply on every OnPluginLoad.
local BlockedMinigamesHook = "MNGAAdministrationBlockedMinigames"
local BLOCKED_PLUGINS = {
	match3 = "sh_match3",
	bejeweled = "sh_bejewelled"
}

local function ApplyBlock()
	for _, ConCommand in pairs( BLOCKED_PLUGINS ) do
		local Command = Shine:GetCommand( ConCommand )
		if Command then
			Command.Disabled = true
		end
	end

	local NoOpCommand = Shine:GetCommand( "sh_mngablockedminigame" )
	if NoOpCommand then
		Shine.ChatCommands.m3 = NoOpCommand
		Shine.ChatCommands.bj = NoOpCommand
	end
end

function Plugin:InitialiseBlockedMinigames()
	self:BindCommand( "sh_mngablockedminigame", { "m3", "bj" }, function() end, true, true )
		:Help( "Disabled mini-game command; does nothing." )

	Shine.Hook.Remove( "OnPluginLoad", BlockedMinigamesHook )
	Shine.Hook.Add( "OnPluginLoad", BlockedMinigamesHook, function( Name )
		if BLOCKED_PLUGINS[ Name ] then
			ApplyBlock()
		end
	end )

	ApplyBlock()
end

function Plugin:CleanupBlockedMinigames()
	Shine.Hook.Remove( "OnPluginLoad", BlockedMinigamesHook )
end
