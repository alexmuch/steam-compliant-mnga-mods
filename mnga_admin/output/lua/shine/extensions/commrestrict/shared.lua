--[[
	Shine commander bans plugin.
]]

local Plugin = Shine.Plugin( ... )

Plugin.NotifyPrefixColour = {
	255, 50, 0
}

function Plugin:SetupDataTable()
	self.__Inherit.SetupDataTable( self )
	self:AddTranslatedNotify( "RESTRICTED_WARNING", {
		Duration = "integer"
	} )
	self:AddTranslatedMessage( "PLAYER_UNRESTRICTED", {
		TargetName = self:GetNameNetworkField()
	} )
end

local Options = {
	Base = "ban",
	BlacklistKeys = {
		CheckConnectionAllowed = true,
		ClientConnect = true,
		OnWebConfigLoaded = true,
		BanNetworkData = true,
		BanNetworkedClients = true,
		BanList = true,
		Rows = true,
		BanData = true,
		SaveConfig = true
	}
}

return Plugin, Options
