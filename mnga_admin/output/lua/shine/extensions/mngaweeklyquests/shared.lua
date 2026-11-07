--[[
	MNGA Weekly Quests.

	Fun, standalone quest log nudging players towards server-specific features.
	Progress is tracked entirely client-side (config://mngaWeeklyQuests.json).
	The server only relays reward claims to the central Flask API, which pays
	each quest reward at most once per steamid per week.

	Week index (shared with Flask): floor((unix_utc - 345600) / 604800).
	345600 = Monday 1970-01-05 00:00 UTC, so weeks reset Monday 00:00 UTC.
]]

local Plugin = Shine.Plugin( ... )

Plugin.Version = "1.0"
Plugin.PrintName = "MNGA Weekly Quests"
Plugin.HasConfig = true
Plugin.ConfigName = "MNGAWeeklyQuests.json"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.DefaultState = true

Plugin.DefaultConfig = {
	-- Pretend Flask accepted every claim. Always on for listen servers.
	FakeClaims = false,
	ClaimTimeout = 5,
	MaxClaimsPerMap = 32,
	EnableDebugLogs = false
}

-- Stable quest ids; ns2py/ns2xp keeps the same id list (1..8).
-- Titles are display-only (quest 5 is intentionally misleading).
Plugin.Quests = {
	{ Id = 1, Title = "Ping 3 Onos or Exosuits", Goal = 3 },
	{ Id = 2, Title = "Use any radio command 5 times", Goal = 5 },
	{ Id = 3, Title = "Volunteer as tribute or cancel one", Goal = 1 },
	{ Id = 4, Title = "Use quick bind 5 times", Goal = 5 },
	-- Tracks 10 strokes internally but displays as 0/1 (DisplayGoal).
	{ Id = 5, Title = "Draw a cat in spectator", Goal = 10, DisplayGoal = 1 },
	{ Id = 6, Title = "Add a player to your enemy group", Goal = 1 },
	{ Id = 7, Title = "Spectate a commander for 1 minute", Goal = 60 },
	{ Id = 8, Title = "Emote 5 times", Goal = 5 }
}
Plugin.QuestById = {}
for i = 1, #Plugin.Quests do
	Plugin.QuestById[ Plugin.Quests[ i ].Id ] = Plugin.Quests[ i ]
end

Plugin.AllQuestsId = 0
Plugin.QuestReward = 25000
Plugin.AllQuestsReward = 200000

Plugin.ClaimStatus = {
	Ok = 1,
	Already = 2,
	Retry = 3,
	Denied = 4
}

local kWeekEpochOffset = 345600
local kWeekSeconds = 604800
Plugin.WeekSeconds = kWeekSeconds

function Plugin.GetWeekIndex( UnixTime )
	return math.floor( ( UnixTime - kWeekEpochOffset ) / kWeekSeconds )
end

function Plugin.GetWeekResetTime( Week )
	return ( Week + 1 ) * kWeekSeconds + kWeekEpochOffset
end

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "Claim", {
		QuestId = "integer (0 to 15)",
		Week = "integer"
	}, "Server" )
	self:AddNetworkMessage( "ClaimResult", {
		QuestId = "integer (0 to 15)",
		Week = "integer",
		Status = "integer (0 to 7)",
		Amount = "integer"
	}, "Client" )
end

return Plugin
