local Plugin = ...
local Shine = Shine
local StringFormat = string.format

local xpdata = {}

local function GetCentralURL( self, Path )
	local BaseURL = tostring( self.Config.xpCentralURL or "http://127.0.0.1:25386" )
	return BaseURL:gsub( "/+$", "" )..Path
end

local function GetCentralAuth( self )
	return {
		server_id = tostring( self.Config.xpServerID or "" ),
		secret = tostring( self.Config.xpSharedSecret or "" )
	}
end

function Plugin:GetXPLevel( SteamID )
	local Data = xpdata[ tonumber( SteamID ) ]
	return Data and tonumber( Data.level ) or 0
end

function Plugin:GetUserStats( steamids ) 
	-- request stats to cache
	local function OnSuccess( response )

		if not GetGamerules or not GetGamerules() then return end
		if not response or response == "" then
			return
		end
		
		local data = json.decode(response, 1, nil)
		if not data then
			Print("%s", StringFormat(" >;> ERROR | %s | failed to decode stats response", Shared.GetTime()))
			return
		end
		-- Print(StringFormat(" >;> POST getuserstats http | %s | query %s", Shared.GetTime(), table.concat(steamids, ",")))
		for i, player in pairs(data) do
			local steamid = tonumber(player['steamid'])
			if steamid then
				xpdata[steamid] = {
					xp=player.xp,
					commxp=player.commxp,
					level=player.level,
					nextlevel=player.nextlevel,
					seedingtokens=player.seedingtokens,
					donationtokens=player.donationtokens,
					winstreak=player.winstreak
				}
			end
		end
		-- Print(StringFormat(" >;> POST POST getuserstats http | %s | query %s", Shared.GetTime(), table.concat(steamids, ",")))
	end
	
	local function OnTimeout()
		Print( "%s", StringFormat(" >;> ERROR | %s | request for stats timed out %s", Shared.GetTime(), table.concat(steamids, ", ") ))
		
		for _, steamid in ipairs(steamids) do
			xpdata[steamid] = {
				xp=0, commxp=0, level=0, nextlevel=200, seedingtokens=0, donationtokens=0
			}
		end
	end
	
	-- Print(StringFormat( " >;> PRE getuserstats http | %s | query %s", Shared.GetTime(),table.concat(steamids, ",") ) )
	local Params = GetCentralAuth( self )
	Params.steamids = table.concat( steamids, "," )
	Shine.TimedHTTPRequest( GetCentralURL( self, "/stats" ), "POST", Params, OnSuccess, OnTimeout, 2 )

end

function Plugin:ProcessNoti()
	local Clients, Count = Shine.GetAllClients()
	local SteamIDs = {}
	for i = 1, Count do
		local Client = Clients[ i ]
		if Client and not Client:GetIsVirtual() then
			SteamIDs[ #SteamIDs + 1 ] = Client:GetUserId()
		end
	end
	if #SteamIDs == 0 then return end
	
    local function OnSuccess( response )

		if not GetGamerules or not GetGamerules() then return end
        if not response or response == "" then
            return
        end

		local obj, pos, err = json.decode(response)
		-- Print("[NOTIFICATION] Raw response: " .. tostring(response))
        if not obj or type( obj ) ~= "table" then
            Print( "[NOTIFICATION] Invalid notification payload" )
            return
        end

		local RefreshIDs = {}
		local SeenRefreshIDs = {}
		for i = 1, #obj do

            local notif = obj[ i ]

			local message
			
			local steamid = tonumber(notif.steamid)
			
			if notif.event == 'lvlup' then

				message = string.format(
					"Level up! You are now level %s! Type !xp for more information.",
					tostring( notif.levelup )
				)
			elseif notif.event == 'seedxp' then

				message = string.format(
					"XP awarded for seeding: +%d XP",
					notif.xp
				)
			elseif notif.event == 'xp' then

				message = string.format(
					"XP awarded: +%d XP",
					notif.xp
				)
			elseif notif.event == 'commxp' then

				message = string.format(
					"Comm XP awarded: +%d Commander XP",
					notif.commxp
				)
			elseif notif.event == 'seedtoken' then
			
				message = string.format(
					"You have been awarded a seeding token! (sh_skipqueue in console or !skipqueue in chat)"
				)
			elseif notif.event == 'usedtoken' then
				-- Cache is refreshed authoritatively below.
			elseif notif.event == 'hatunlock' then
				-- Central saw this XP award cross a hat threshold; the mngahats plugin (shimizushine) announces it.
				for _, c in ipairs( Shine.GetAllClients() ) do
					if c:GetUserId() == steamid then
						Print( "%s", StringFormat( "[mnga_xp] hat unlock steamid=%s item=%s",
							tostring( steamid ), tostring( notif.item_key ) ) )
						Shine.Hook.Call( "OnMNGAHatUnlocked", c, tostring( notif.item_key or "" ) )
						break
					end
				end
			else

				message = "Unknown notification received"

			end
			
			if message then
				-- this doesn't work, steamid ns2id whatever
				-- local client = Shine:GetClientByNS2ID( steamid )
				-- so we just iterate all clients
				local targetID = steamid  
				local client = nil
				for _, c in ipairs( Shine.GetAllClients() ) do
					if c:GetUserId() == targetID then
						client = c
						break
					end
				end
				if client then
					if notif.event == "seedxp" then
						self:SendNetworkMessage( client, "SilentSeedingXPNotification", {
							Message = message
						}, true )
						Print( "%s", StringFormat(
							"[mnga_xp] Sent silent seeding XP notification steamid=%s xp=%s",
							tostring( steamid ),
							tostring( notif.xp )
						) )
					else
						Shine:NotifyColour(
							client,
							255, 112, 77,
							message
						)
					end
				end
			end
			if steamid and not SeenRefreshIDs[ steamid ] then
				SeenRefreshIDs[ steamid ] = true
				RefreshIDs[ #RefreshIDs + 1 ] = steamid
			end

			-- Optional: log receipt
			-- Print(
				-- "[XP NOTI] steamid=%s event=%s xp=%s",
				-- tostring( notif.steamid ),
				-- tostring( notif.event ),
				-- tostring( notif.xp )
			-- )

		end
		if #RefreshIDs > 0 then
			self:GetUserStats( RefreshIDs )
		end

    end


    local function OnTimeout()
        Print( ">;> ERROR | %s | [NOTIFICATION] Notification request timed out",Shared.GetTime() )
    end
	
	local Params = GetCentralAuth( self )
	Params.steamids = table.concat( SteamIDs, "," )
	Shine.TimedHTTPRequest( GetCentralURL( self, "/notifications/pending" ), "POST", Params, OnSuccess,
		OnTimeout, 2 )
end


function Plugin:ShowXP( Client )
	if not Shine:IsValidClient( Client ) then print( "Invalid client" ) return false end
	
	local steamid = Client:GetUserId()
	local xp = (xpdata[steamid] and xpdata[steamid].xp) or 0
	local level = (xpdata[steamid] and xpdata[steamid].level) or 0
	local commxp = (xpdata[steamid] and xpdata[steamid].commxp) or 0
	local seedingtokens = (xpdata[steamid] and xpdata[steamid].seedingtokens) or 0
	local donationtokens = (xpdata[steamid] and xpdata[steamid].donationtokens) or 0
	local message = StringFormat('Level: %s , Current XP: %s. Comm XP: %s. Seeding tokens: %s. Supporter tokens: %s', level, xp, commxp, seedingtokens, donationtokens)
	Shine:NotifyColour(
				Client,
				255, 112, 77,
				message
	)
	-- local Player = Client:GetControllingPlayer()
	-- local PlayerName = Player and Player:GetName() or "Console"
	-- Shine:Notify( Client, "(XP)", PlayerName, message )
end


function Plugin:UseSeedingToken( Client )
	if not Shine:IsValidClient( Client ) then print( "Invalid client" ) return false end
	
	local steamid = Client:GetUserId()
	local seedingtokens = (xpdata[steamid] and xpdata[steamid].seedingtokens) or 0
	local message
	if seedingtokens > 0 then
		message = 'You have a token, but skip functionality is not yet implemented, stay tuned!'
		Print("%s", StringFormat( " >;> SEEDTOKENUSE | %s | %s", Shared.GetTime() , self:GetClientInfo( Client, true ) ) )
	else
		message = 'You do not have a seeding token. Seed server to earn tokens!'
	end
	Shine:NotifyColour(
				Client,
				255, 112, 77,
				message
	)
end

