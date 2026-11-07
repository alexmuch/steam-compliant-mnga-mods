--[[
	MNGA Weekly Quests - server.

	No hooks, no per-tick work. The only job is relaying reward claims from the
	client to the central Flask API (POST /quests/claim) using the trusted
	Client:GetUserId(), then relaying the result back.
]]

local Plugin = ...
local Shine = Shine
local StringFormat = string.format

local Status = Plugin.ClaimStatus
local StatusByName = {
	ok = Status.Ok,
	already = Status.Already,
	retry = Status.Retry,
	denied = Status.Denied
}

function Plugin:Log( Message, ... )
	if not self.Config.EnableDebugLogs then return end
	Print( "%s", "[weeklyquests] "..StringFormat( Message, ... ) )
end

function Plugin:Initialise()
	self.ClaimCounts = {}
	self.Enabled = true
	self:Log( "server initialised (fake claims: %s)", tostring( self:UseFakeClaims() ) )
	return true
end

function Plugin:ClientDisconnect( Client )
	self.ClaimCounts[ Client ] = nil
end

function Plugin:UseFakeClaims()
	if self.Config.FakeClaims then return true end
	return Server.IsDedicated and not Server.IsDedicated()
end

-- Reuse the central API credentials already configured for mngaadministration
-- so the shared secret lives in one place.
function Plugin:GetCentralSettings()
	local Admin = Shine.Plugins and Shine.Plugins.mngaadministration
	local Config = Admin and Admin.Config
	if not Config then return nil end
	local BaseURL = tostring( Config.xpCentralURL or "" ):gsub( "/+$", "" )
	if BaseURL == "" then return nil end
	return BaseURL, tostring( Config.xpServerID or "" ), tostring( Config.xpSharedSecret or "" )
end

function Plugin:SendClaimResult( Client, QuestId, Week, ResultStatus, Amount )
	if not Shine:IsValidClient( Client ) then return end
	self:SendNetworkMessage( Client, "ClaimResult", {
		QuestId = QuestId,
		Week = Week,
		Status = ResultStatus,
		Amount = Amount or 0
	}, true )
end

function Plugin:GetRewardForQuest( QuestId )
	return QuestId == self.AllQuestsId and self.AllQuestsReward or self.QuestReward
end

function Plugin:ReceiveClaim( Client, Data )
	if not Client or Client:GetIsVirtual() then return end

	local QuestId = tonumber( Data.QuestId )
	local Week = tonumber( Data.Week )
	if not QuestId or not Week then return end
	if QuestId ~= self.AllQuestsId and not self.QuestById[ QuestId ] then return end

	local SteamID = Client:GetUserId()
	if not SteamID or SteamID == 0 then return end

	local Count = ( self.ClaimCounts[ Client ] or 0 ) + 1
	self.ClaimCounts[ Client ] = Count
	if Count > self.Config.MaxClaimsPerMap then
		self:Log( "claim cap reached steamid=%s quest=%d", tostring( SteamID ), QuestId )
		self:SendClaimResult( Client, QuestId, Week, Status.Retry, 0 )
		return
	end

	self:Log( "claim received steamid=%s quest=%d week=%d", tostring( SteamID ), QuestId, Week )

	if self:UseFakeClaims() then
		local Amount = self:GetRewardForQuest( QuestId )
		self:Log( "fake claim ok steamid=%s quest=%d amount=%d", tostring( SteamID ), QuestId, Amount )
		self:SendClaimResult( Client, QuestId, Week, Status.Ok, Amount )
		return
	end

	local BaseURL, ServerID, Secret = self:GetCentralSettings()
	if not BaseURL then
		Print( "[weeklyquests] no central API config (mngaadministration missing); claim left pending" )
		self:SendClaimResult( Client, QuestId, Week, Status.Retry, 0 )
		return
	end

	local function OnSuccess( Response )
		local Decoded = Response and Response ~= "" and json.decode( Response, 1, nil )
		local ResultStatus = type( Decoded ) == "table" and StatusByName[ tostring( Decoded.status ) ]
			or Status.Retry
		local Amount = type( Decoded ) == "table" and tonumber( Decoded.amount ) or 0
		self:Log( "claim result steamid=%s quest=%d status=%s amount=%d",
			tostring( SteamID ), QuestId, tostring( type( Decoded ) == "table" and Decoded.status ), Amount )
		self:SendClaimResult( Client, QuestId, Week, ResultStatus, Amount )
	end

	local function OnTimeout()
		self:Log( "claim timeout steamid=%s quest=%d", tostring( SteamID ), QuestId )
		self:SendClaimResult( Client, QuestId, Week, Status.Retry, 0 )
	end

	local Player = Client:GetControllingPlayer()
	local PlayerName = Player and Player.GetName and Player:GetName() or ""

	Shine.TimedHTTPRequest( BaseURL.."/quests/claim", "POST", {
		steamid = tostring( SteamID ),
		playername = PlayerName,
		server_id = ServerID,
		secret = Secret,
		quest_id = tostring( QuestId ),
		week = tostring( Week )
	}, OnSuccess, OnTimeout, self.Config.ClaimTimeout )
end
