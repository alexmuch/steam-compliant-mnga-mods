-- ======= mnga_administration ===================================================
--
-- lua\mnga_administration\VotingMoveToSpecPlayer.lua
--
--    Adds a "Vote to Send to Shadow-Realm" option to the base NS2 start-vote menu.
--    On success the target player is forced onto the spectator team.
--
--    Threshold mirrors VoteKickPlayer / VoteGagPlayer: default majority of
--    voting players plus the extra check requiring at least 3 real players and
--    2 yes votes.
--
-- ==============================================================================

local kExecuteVoteDelay = 3
local kShadowRealmRestrictionDuration = 10 * 60
local kShadowRealmQueueThreshold = 6

RegisterVoteType("VoteMoveToSpecPlayer", { spec_client = "integer" })

if Client then

    local function SetupMoveToSpecPlayerVote(voteMenu)

        if GetStartVoteAllowedForThunderdome("VoteMoveToSpecPlayer") then

            local function GetPlayerList()

                local playerList = Scoreboard_GetPlayerList()
                local menuItems = { }
                local localClientIndex = Client.GetLocalClientIndex()
                local missingRecords = 0
                local botRecords = 0
                local spectatorRecords = 0
                local localPlayerRecords = 0
                for p = 1, #playerList do

                    local record = Scoreboard_GetPlayerRecord(playerList[p].client_index)

                    -- EntityTeamNumber is the authoritative replicated team. Do not use
                    -- IsSpectator here: it can remain set while a player is on a playing
                    -- team, which made valid targets disappear from this menu.
                    if not record then
                        missingRecords = missingRecords + 1
                    elseif playerList[p].client_index == localClientIndex then
                        localPlayerRecords = localPlayerRecords + 1
                    elseif record.SteamId == 0 then
                        botRecords = botRecords + 1
                    elseif record.EntityTeamNumber == kSpectatorIndex then
                        spectatorRecords = spectatorRecords + 1
                    else
                        table.insert(menuItems, {
                            text = playerList[p].name,
                            extraData = { spec_client = playerList[p].client_index }
                        })
                    end

                end

                Print(
                    "[shadow-realm] target menu: scoreboard=%s eligible=%s local=%s bots=%s spectators=%s missing=%s",
                    tostring(#playerList),
                    tostring(#menuItems),
                    tostring(localPlayerRecords),
                    tostring(botRecords),
                    tostring(spectatorRecords),
                    tostring(missingRecords)
                )
                return menuItems

            end

            local function StartMoveToSpecPlayerVote(data)
                AttemptToStartVote("VoteMoveToSpecPlayer", { spec_client = data.spec_client })
            end

            voteMenu:AddMainMenuOption("Send Player to Shadow-Realm... (spectate)", GetPlayerList, StartMoveToSpecPlayerVote)
        end

        -- Translates the networked data into the question shown to voters.
        local function GetVoteMoveToSpecPlayerQuery(data)
            return "Vote to send " .. Scoreboard_GetPlayerName(data.spec_client) .. " to shadow-realm?"
        end
        AddVoteStartListener("VoteMoveToSpecPlayer", GetVoteMoveToSpecPlayerQuery)

    end
    AddVoteSetupCallback(SetupMoveToSpecPlayerVote)

end

if Server then

    -- Mirror VoteKickPlayer / VoteGagPlayer extra pass check so the threshold aligns.
    local function OnMoveToSpecPlayerAdditionVotePassedCheck(numRealPlayers, yes, no)
        return numRealPlayers >= 3 and yes >= 2
    end

    local function OnMoveToSpecPlayerVoteSuccessful(data)

        Print("VoteMoveToSpecPlayer: vote passed for client %s", tostring(data.spec_client))

        local client = Server.GetClientById(data.spec_client)
        -- client may be nil if the target disconnected before the vote completed.
        if not client then
            Print("VoteMoveToSpecPlayer: target client %s no longer present, nothing to move", tostring(data.spec_client))
            return
        end

        local player = client:GetControllingPlayer()
        if not player then
            Print("VoteMoveToSpecPlayer: client %s has no controlling player", tostring(data.spec_client))
            return
        end

        local name = player:GetName()
        local oldTeamNumber = player:GetTeamNumber()
        local oldTeamName = Shine and Shine:GetTeamName(oldTeamNumber, true) or tostring(oldTeamNumber)

        -- The Player team is authoritative. Client:GetIsSpectator() can be stale
        -- under queue/scoreboard integrations, and previously caused this callback
        -- to return even though the target was still playing.
        if oldTeamNumber == kSpectatorIndex then
            Print("VoteMoveToSpecPlayer: %s [%s] is already spectator", name, tostring(client:GetUserId()))
            return
        end

        local gamerules = GetGamerules()
        if not gamerules then
            Print("VoteMoveToSpecPlayer: no gamerules available; cannot move %s [%s]", name, tostring(client:GetUserId()))
            return
        end

        local queuePlugin = Shine and Shine.Plugins and Shine.Plugins[ "mngareadyroomqueue" ]
        local queueCount = queuePlugin and queuePlugin.Enabled
            and queuePlugin.GetQueueCount and queuePlugin:GetQueueCount() or nil

        -- The fourth argument is ShineForce. This is a completed player vote, so
        -- queue/team-management JoinTeam hooks must not veto the forced transfer.
        local success, newPlayer = gamerules:JoinTeam(player, kSpectatorIndex, true, true)

        Print(
            "VoteMoveToSpecPlayer: JoinTeam(%s [%s], spectator, force=true, shineForce=true) success=%s oldTeam=%s newTeam=%s",
            name,
            tostring(client:GetUserId()),
            tostring(success),
            tostring(oldTeamNumber),
            tostring(newPlayer and newPlayer:GetTeamNumber())
        )

        if not success or not newPlayer or newPlayer:GetTeamNumber() ~= kSpectatorIndex then
            Print("VoteMoveToSpecPlayer: transfer verification failed for %s [%s]", name, tostring(client:GetUserId()))
            return
        end

        if queueCount ~= nil and queueCount < kShadowRealmQueueThreshold then
            local restricted = queuePlugin.AddShadowRealmRestriction
                and queuePlugin:AddShadowRealmRestriction( client:GetUserId(), kShadowRealmRestrictionDuration )
            Print(
                "[shadow-realm] restriction: steam_id=%s queue=%s threshold=%s duration=%s registered=%s",
                tostring(client:GetUserId()),
                tostring(queueCount),
                tostring(kShadowRealmQueueThreshold),
                tostring(kShadowRealmRestrictionDuration),
                tostring(restricted)
            )
        elseif queueCount == nil then
            Print("[shadow-realm] restriction: queue plugin unavailable; spectator transfer remains in effect")
        else
            Print(
                "[shadow-realm] restriction: steam_id=%s queue=%s threshold=%s registered=false reason=queue_threshold",
                tostring(client:GetUserId()),
                tostring(queueCount),
                tostring(kShadowRealmQueueThreshold)
            )
        end

        if Shine then
            MNGA_NotifyNames(Shine.GetAllClients(), 255, 112, 77,
                "%s (%s) was sent to the shadow-realm by player vote.", MNGA_Name(client:GetUserId(), name), oldTeamName)
        else
            Print("VoteMoveToSpecPlayer: Shine not available, skipping notification")
        end

    end

    SetVoteSuccessfulCallback(
        "VoteMoveToSpecPlayer",
        kExecuteVoteDelay,
        OnMoveToSpecPlayerVoteSuccessful,
        OnMoveToSpecPlayerAdditionVotePassedCheck
    )

end
