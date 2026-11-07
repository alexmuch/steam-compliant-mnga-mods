--[[
	MNGA Help.

	!help / !command / !commands opens a paged, draggable help window that lists
	the server's player commands and the configurable client mods. Unlike chat
	notifications it stays open until closed. All text lives client-side; the
	server only relays the chat command.
]]

local Plugin = Shine.Plugin( ... )

Plugin.Version = "1.0"
Plugin.PrintName = "MNGA Help"
Plugin.HasConfig = false
Plugin.DefaultState = true

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "OpenHelp", {}, "Client" )
end

return Plugin
