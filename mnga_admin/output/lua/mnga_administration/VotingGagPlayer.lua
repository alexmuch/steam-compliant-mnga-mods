-- ======= mnga_administration ===================================================
--
-- lua\mnga_administration\VotingGagPlayer.lua
--
--    Adds a "Vote to gag" option to the base NS2 start-vote menu (alongside
--    Vote Kick Player, Change Map, etc). On success the target is gagged via
--    Shine's basecommands plugin until the next map change.
--
--    Threshold mirrors VoteKickPlayer: default majority of voting players plus
--    the extra check requiring at least 3 real players and 2 yes votes.
--
-- ==============================================================================

local kExecuteVoteDelay = 3

RegisterVoteType("VoteGagPlayer", { gag_client = "integer" })

if Client then

    local function SetupGagPlayerVote(voteMenu)

        if GetStartVoteAllowedForThunderdome("VoteGagPlayer") then

            local function GetPlayerList()

                local playerList = Scoreboard_GetPlayerList()
                local menuItems = { }
                for p = 1, #playerList do

                    local name = Scoreboard_GetPlayerData(Client.GetLocalClientIndex(), "Name")
                    -- Don't add the local player to the list, and exclude bots.
                    local steamId = Scoreboard_GetPlayerRecord(playerList[p].client_index).SteamId
                    if playerList[p].name ~= name and steamId ~= 0 then
                        table.insert(menuItems, { text = playerList[p].name, extraData = { gag_client = playerList[p].client_index } })
                    end

                end
                return menuItems

            end

            local function StartGagPlayerVote(data)
                AttemptToStartVote("VoteGagPlayer", { gag_client = data.gag_client })
            end

            voteMenu:AddMainMenuOption("Gag Player...", GetPlayerList, StartGagPlayerVote)
        end

        -- Translates the networked data into the question shown to voters.
        local function GetVoteGagPlayerQuery(data)
            return "Vote to Gag " .. Scoreboard_GetPlayerName(data.gag_client) .. " (until map change)?"
        end
        AddVoteStartListener("VoteGagPlayer", GetVoteGagPlayerQuery)

    end
    AddVoteSetupCallback(SetupGagPlayerVote)

end

if Server then

    -- Mirror VoteKickPlayer's extra pass check so the threshold aligns.
    local function OnGagPlayerAdditionVotePassedCheck(numRealPlayers, yes, no)
        return numRealPlayers >= 3 and yes >= 2
    end

    local function OnGagPlayerVoteSuccessful(data)

        local client = Server.GetClientById(data.gag_client)
        -- client may be nil if the target disconnected before the vote completed.
        if not client then
            Print("VoteGagPlayer: target client %s no longer present, nothing to gag", tostring(data.gag_client))
            return
        end

        local userId = client:GetUserId()

        -- Guard against Shine being absent. In practice this mod is a Shine
        -- plugin so Shine is always present by the time a vote completes, but a
        -- nil deref here would error out of the vote update loop, so be safe.
        if not Shine then
            Print("VoteGagPlayer: Shine not available, cannot gag %s", tostring(userId))
            return
        end

        local enabled, basecommands = Shine:IsExtensionEnabled("basecommands")
        if not (enabled and basecommands and basecommands.Gagged) then
            Print("VoteGagPlayer: basecommands plugin unavailable, cannot gag %s", tostring(userId))
            return
        end

        -- true (rather than an expiry time) gags until the next map change, as
        -- the runtime Gagged table is rebuilt from config on map load.
        basecommands.Gagged[userId] = true

        local player = client:GetControllingPlayer()
        local name = player and player:GetName() or "<unknown>"
        Print("VoteGagPlayer: gagged %s [%s] until next map change", name, tostring(userId))

        -- Announce to everyone so players see the vote took effect.
        MNGA_NotifyNames(Shine.GetAllClients(), 255, 112, 77,
            "%s was gagged by player vote until the next map change.", MNGA_Name(userId, name))

    end
    SetVoteSuccessfulCallback("VoteGagPlayer", kExecuteVoteDelay, OnGagPlayerVoteSuccessful, OnGagPlayerAdditionVotePassedCheck)

end
