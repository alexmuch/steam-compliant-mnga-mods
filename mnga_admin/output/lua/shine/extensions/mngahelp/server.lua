--[[
	MNGA Help - server. Only binds the chat commands; no hooks or per-tick work.
]]

local Plugin = ...

function Plugin:Initialise()
	self:CreateCommands()
	self.Enabled = true
	return true
end

function Plugin:CreateCommands()
	local Command = self:BindCommand( "sh_mngahelp", { "help", "command", "commands" }, function( Client )
		if not Client then return end
		self:SendNetworkMessage( Client, "OpenHelp", {}, true )
	end, true )
	Command:Help( "Opens the server help window listing player commands and mod options." )
end
