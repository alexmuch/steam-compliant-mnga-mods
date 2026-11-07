-- ======= mnga_administration ===================================================
--
-- lua\mnga_administration\VotingCommBanPlayer.lua
--
--    Adds a "Vote to Comm-Ban" option to the base NS2 start-vote menu (alongside
--    Vote Kick Player, Vote Gag Player, Change Map, etc). On success the target
--    is banned from commanding via the Shine commbans plugin for a configurable
--    duration (defaults to the commbans plugin's DefaultBanTime, in minutes).
--
--    Threshold mirrors VoteKickPlayer / VoteGagPlayer: default majority of
--    voting players plus the extra check requiring at least 3 real players and
--    2 yes votes.
--
-- ==============================================================================

local StringFormat = string.format

local kExecuteVoteDelay = 3

-- Duration (minutes) applied when no DefaultBanTime is available from config.
-- Zero means permanent.
local kFallbackBanMinutes = 60

RegisterVoteType("VoteCommBanPlayer", { commban_client = "integer" })

if Client then

    local function SetupCommBanPlayerVote(voteMenu)

        -- Only show the option outside of Thunderdome (same guard as VoteGagPlayer).
        if GetStartVoteAllowedForThunderdome("VoteCommBanPlayer") then

            local function GetPlayerList()

                local playerList = Scoreboard_GetPlayerList()
                local menuItems = {}
                for p = 1, #playerList do

                    local name = Scoreboard_GetPlayerData(Client.GetLocalClientIndex(), "Name")
                    -- Exclude the local player and bots (SteamId == 0).
                    local steamId = Scoreboard_GetPlayerRecord(playerList[p].client_index).SteamId
                    if playerList[p].name ~= name and steamId ~= 0 then
                        table.insert(menuItems, {
                            text = playerList[p].name,
                            extraData = { commban_client = playerList[p].client_index }
                        })
                    end

                end
                return menuItems

            end

            local function StartCommBanPlayerVote(data)
                AttemptToStartVote("VoteCommBanPlayer", { commban_client = data.commban_client })
            end

            voteMenu:AddMainMenuOption("Comm-Ban Player...", GetPlayerList, StartCommBanPlayerVote)
        end

        -- Translates the networked data into the question shown to voters.
        local function GetVoteCommBanPlayerQuery(data)
            return "Vote to Comm-Ban " .. Scoreboard_GetPlayerName(data.commban_client) .. " (1 hour)?"
        end
        AddVoteStartListener("VoteCommBanPlayer", GetVoteCommBanPlayerQuery)

    end
    AddVoteSetupCallback(SetupCommBanPlayerVote)

end

if Server then

    -- Mirror VoteKickPlayer / VoteGagPlayer extra pass check so the threshold aligns.
    local function OnCommBanPlayerAdditionVotePassedCheck(numRealPlayers, yes, no)
        return numRealPlayers >= 3 and yes >= 2
    end

    local function OnCommBanPlayerVoteSuccessful(data)

        local client = Server.GetClientById(data.commban_client)
        -- client may be nil if the target disconnected before the vote completed.
        if not client then
            Print("VoteCommBanPlayer: target client %s no longer present, nothing to comm-ban", tostring(data.commban_client))
            return
        end

        local userId = client:GetUserId()

        -- Guard against Shine being absent.
        if not Shine then
            Print("VoteCommBanPlayer: Shine not available, cannot comm-ban %s", tostring(userId))
            return
        end

        local enabled, commbans = Shine:IsExtensionEnabled("commbans")
        if not (enabled and commbans) then
            Print("VoteCommBanPlayer: commbans plugin unavailable, cannot comm-ban %s", tostring(userId))
            return
        end

        -- Resolve ban duration: prefer the plugin's configured default, fall back
        -- to kFallbackBanMinutes. A value of 0 means permanent.
        local banMinutes = (commbans.Config and commbans.Config.DefaultBanTime) or kFallbackBanMinutes

        local player  = client:GetControllingPlayer()
        local name    = player and player:GetName() or "<unknown>"
        local steamId = tostring(userId)

        -- AddBan() is inherited from Shine's ban extension. It persists the
        -- record and updates its network and configured web-sync state.
        if commbans.AddBan then
            -- AddBan() takes duration in seconds, unlike the vote configuration.
            local durationSeconds = banMinutes == 0 and 0 or banMinutes * 60
            local added, err = commbans:AddBan(
                steamId,
                name,
                durationSeconds,
                "Player Vote",
                0,
                "Player vote comm-ban"
            )
            if not added then
                Print("VoteCommBanPlayer: failed to persist comm-ban for %s [%s]: %s",
                    name, steamId, tostring(err))
                return
            end
        else
            -- Fallback: write directly into the ban table the same way the
            -- plugin itself would via its ban module.
            local Time = os.time
            local unbanTime = banMinutes == 0 and 0 or (Time() + banMinutes * 60)

            commbans.Config.Banned[steamId] = {
                Name      = name,
                UnbanTime = unbanTime,
                Reason    = "Player vote comm-ban",
                BannedBy  = "Player Vote"
            }
            commbans:SaveConfig()

            Print("VoteCommBanPlayer: comm-banned %s [%s] via direct config write (duration: %s min)",
                name, steamId, banMinutes == 0 and "permanent" or tostring(banMinutes))
        end

        -- A successfully banned active commander must be ejected immediately.
        if player and player:isa("Commander") then
            player:Eject()
        end

        Print("VoteCommBanPlayer: comm-banned %s [%s] for %s minute(s) by player vote",
            name, steamId, banMinutes == 0 and "permanent" or tostring(banMinutes))

        -- Announce to all connected clients so the outcome is visible.
        local durationStr = banMinutes == 0
            and "permanently"
            or StringFormat("for %d minute(s)", banMinutes)

        -- Orange accent matching the commbans plugin's NotifyPrefixColour {255, 50, 0}.
        MNGA_NotifyNames(Shine.GetAllClients(), 255, 50, 0,
            "%s was comm-banned by player vote %s.", MNGA_Name(userId, name), durationStr)

    end

    SetVoteSuccessfulCallback(
        "VoteCommBanPlayer",
        kExecuteVoteDelay,
        OnCommBanPlayerVoteSuccessful,
        OnCommBanPlayerAdditionVotePassedCheck
    )

end
