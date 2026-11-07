local JSON = require "shine/lib/json"

local Plugin = Shine.Plugin( ... )

Plugin.Version = "1.0"
Plugin.HasConfig = true
Plugin.ConfigName = "MNGAGags.json"
Plugin.PrintName = "MNGA Gags"
Plugin.DefaultState = true
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.DefaultConfig = {
	Gagged = JSON.Object(),
	GameGagged = JSON.Object(),
	DefaultGagTime = 1800
}

Plugin.SortColumn = table.AsEnum( {
	"NAME", "TYPE", "GAGGED_BY", "EXPIRY"
}, function( Index ) return Index end )

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "GagData", {
		ID = "string (32)",
		Name = self:GetNameNetworkField(),
		GagType = "integer (1 to 2)",
		Duration = "integer",
		Expires = "integer",
		GaggedBy = self:GetNameNetworkField(),
		GaggerID = "integer",
		Reason = "string (128)",
		Issued = "integer"
	}, "Client" )
	self:AddNetworkMessage( "RequestGagPage", {
		Page = "integer",
		MaxResults = "integer",
		Filter = "string (128)",
		SortColumn = "integer (1 to 4)",
		SortAscending = "boolean"
	}, "Server" )
	self:AddNetworkMessage( "GagPage", {
		Page = "integer",
		NumPages = "integer",
		MaxResults = "integer",
		TotalNumResults = "integer"
	}, "Client" )
	self:AddNetworkMessage( "GagDataChanged", {}, "Client" )
end

return Plugin
