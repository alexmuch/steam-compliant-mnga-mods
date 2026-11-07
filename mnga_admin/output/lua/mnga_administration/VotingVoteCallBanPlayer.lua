-- ======= mnga_administration ===================================================
--
-- lua\mnga_administration\VotingVoteCallBanPlayer.lua
--
--    Adds a "Vote to Vote-Call-Ban" option to the base NS2 start-vote menu.
--    On success the target is banned from starting/calling votes for one hour.
--    They can still vote yes/no in votes started by other players.
--
-- ==============================================================================

local kExecuteVoteDelay = 3
local kVoteCallBanMinutes = 60

RegisterVoteType("VoteVoteCallBanPlayer", { voteban_client = "integer" })

if Client then

    local function SetupVoteCallBanPlayerVote(voteMenu)

        if GetStartVoteAllowedForThunderdome("VoteVoteCallBanPlayer") then

            local function GetPlayerList()

                local playerList = Scoreboard_GetPlayerList()
                local menuItems = {}
                for p = 1, #playerList do

                    local localName = Scoreboard_GetPlayerData(Client.GetLocalClientIndex(), "Name")
                    local record = Scoreboard_GetPlayerRecord(playerList[p].client_index)

                    -- Exclude the local player and bots.
                    if record and playerList[p].name ~= localName and record.SteamId ~= 0 then
                        table.insert(menuItems, {
                            text = playerList[p].name,
                            extraData = { voteban_client = playerList[p].client_index }
                        })
                    end

                end
                return menuItems

            end

            local function StartVoteCallBanPlayerVote(data)
                AttemptToStartVote("VoteVoteCallBanPlayer", { voteban_client = data.voteban_client })
            end

            voteMenu:AddMainMenuOption("Ban player from starting a vote", GetPlayerList, StartVoteCallBanPlayerVote)
        end

        local function GetVoteCallBanPlayerQuery(data)
            return "Vote to ban " .. Scoreboard_GetPlayerName(data.voteban_client) .. " from calling votes for 1 hour?"
        end
        AddVoteStartListener("VoteVoteCallBanPlayer", GetVoteCallBanPlayerQuery)

    end
    AddVoteSetupCallback(SetupVoteCallBanPlayerVote)

end

if Server then

    local function OnVoteCallBanPlayerAdditionVotePassedCheck(numRealPlayers, yes, no)
        return numRealPlayers >= 3 and yes >= 2
    end

    local function OnVoteCallBanPlayerVoteSuccessful(data)

        Print("VoteVoteCallBanPlayer: vote passed for client %s", tostring(data.voteban_client))

        local client = Server.GetClientById(data.voteban_client)
        if not client then
            Print("VoteVoteCallBanPlayer: target client %s no longer present, nothing to ban", tostring(data.voteban_client))
            return
        end

        if not AddVoteCallBan then
            Print("VoteVoteCallBanPlayer: AddVoteCallBan missing, cannot vote-call-ban %s", tostring(client:GetUserId()))
            return
        end

        local player = client:GetControllingPlayer()
        local name = player and player:GetName() or "<unknown>"

        if not AddVoteCallBan(client, kVoteCallBanMinutes, "Player vote vote-call-ban") then
            Print("VoteVoteCallBanPlayer: failed to vote-call-ban %s [%s]", name, tostring(client:GetUserId()))
            return
        end

        if Shine then
            MNGA_NotifyNames(Shine.GetAllClients(), 255, 112, 77,
                "%s was banned from calling votes for 1 hour by player vote.", MNGA_Name(client:GetUserId(), name))
        else
            Print("VoteVoteCallBanPlayer: Shine not available, skipping notification")
        end

    end

    SetVoteSuccessfulCallback(
        "VoteVoteCallBanPlayer",
        kExecuteVoteDelay,
        OnVoteCallBanPlayerVoteSuccessful,
        OnVoteCallBanPlayerAdditionVotePassedCheck
    )

end
