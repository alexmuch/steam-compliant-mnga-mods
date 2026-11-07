if Server then

    local kExecuteVoteDelay = 3

    local function OnKickPlayerAdditionVotePassedCheck(numRealPlayers, yes, no)
        return numRealPlayers >= 3 and yes >= 2
    end

    -- Replace the vanilla success callback so the public result identifies the
    -- target's team before the ban/disconnect removes their player entity.
    local function OnKickPlayerVoteSuccessful(data)
        local client = Server.GetClientById(data.kick_client)
        if not client then
            Print("[vote-kick] target client %s no longer present", tostring(data.kick_client))
            return
        end

        local player = client:GetControllingPlayer()
        local name = player and player:GetName() or "Unknown"
        local teamNumber = player and player:GetTeamNumber()
        local teamName = teamNumber and Shine and Shine:GetTeamName(teamNumber, true) or tostring(teamNumber or "Unknown")
        local message = name .. " (" .. teamName .. ") was kicked by player vote."

        Print("[vote-kick] %s", message)
        if Shine then
            MNGA_NotifyNames(nil, 255, 112, 77, "%s (%s) was kicked by player vote.", MNGA_Name(client), teamName)
        end

        local votingsettings = Server.GetConfigSetting("voting")
        local bantime = votingsettings and tonumber(votingsettings.votekick_bantime)
        if bantime and bantime > 0 then
            Shared.ConsoleCommand(string.format("sv_ban %s %s banned by VoteKick", client:GetUserId(), bantime))
        else
            Server.DisconnectClient(client, "You were kicked by a player vote.")
        end
    end

    SetVoteSuccessfulCallback(
        "VoteKickPlayer",
        kExecuteVoteDelay,
        OnKickPlayerVoteSuccessful,
        OnKickPlayerAdditionVotePassedCheck
    )

    -- If the vote target disconnects mid-vote (e.g. via "retry" in console) while
    -- a VoteKickPlayer vote is active against them, apply the ban immediately.
    -- Without this, Server.GetClientById returns nil in OnKickPlayerVoteSuccessful
    -- and the player escapes without being banned.
    local function OnKickTargetDisconnected(client)
        if GetActiveVoteName() == "VoteKickPlayer" then
            local data = GetActiveVoteData()
            if data and data.kick_client == client:GetId() then
                local votingsettings = Server.GetConfigSetting("voting")
                local bantime = votingsettings and tonumber(votingsettings.votekick_bantime)
                if bantime and bantime > 0 then
                    Shared.ConsoleCommand(string.format("sv_ban %s %s banned, don't try to evade votekick", client:GetUserId(), bantime))
                end
            end
        end
    end
    Event.Hook("ClientDisconnect", OnKickTargetDisconnected)

end
