--[[
	Commbans client.
]]

local Plugin = ...

Plugin.AdminTab = "Comm Restricts"

Plugin.BanCommand = "sh_commrestrictid"
Plugin.UnbanCommand = "sh_uncommrestrict"

Plugin.AdminMenuIcon = Shine.GUI.Icons.Ionicons.Thumbsdown

do
	local RichTextFormat = require "shine/lib/gui/richtext/format"

	local function GetColourForName( Values )
		return RichTextFormat.GetColourForPlayer( Values.TargetName )
	end

	Plugin.RichTextMessageOptions = {
		PLAYER_RESTRICTED = {
			Colours = {
				TargetName = GetColourForName,
				Duration = RichTextFormat.Colours.LightBlue,
				Reason = RichTextFormat.Colours.LightRed
			}
		},
		PLAYER_UNRESTRICTED = {
			Colours = {
				TargetName = GetColourForName
			}
		}
	}
end

function Plugin:Initialise()
	self:SetupAdminMenu()

	self.Enabled = true

	return true
end
