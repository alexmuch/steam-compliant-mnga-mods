-- Server-started vote used by the mngareadycheck Shine extension
-- (.claude/docs/ready-check.md): when the pregame ready check cannot reach a
-- full set of ready players, Teams + Ready Room vote on starting anyway.
-- Clients cannot start it (SetVoteServerOnly); duration and execute delay are
-- applied from the extension's config through MNGAReadyCheckVote_Configure.

local kDefaultExecuteDelay = 1

RegisterVoteType("VoteReadyCheckStart", { ready = "integer", needed = "integer", token = "integer" })

if Client then

    local function SetupReadyCheckStartVote(voteMenu)

        local function GetVoteReadyCheckStartQuery(data)
            return string.format("Start the game with less than full teams? (%d/%d ready)",
                data.ready or 0, data.needed or 0)
        end
        AddVoteStartListener("VoteReadyCheckStart", GetVoteReadyCheckStartQuery)

    end
    AddVoteSetupCallback(SetupReadyCheckStartVote)

end

if Server then

    local function OnReadyCheckStartVoteSuccessful(data)
        local plugin = Shine and Shine.Plugins and Shine.Plugins.mngareadycheck
        Print("[readycheck] under-full start vote passed token=%s plugin=%s",
            tostring(data and data.token), tostring(plugin and plugin.Enabled))
        if plugin and plugin.Enabled and plugin.OnUnderfullVotePassed then
            plugin:OnUnderfullVotePassed(data and data.token)
        end
    end

    local configuredExecuteDelay = kDefaultExecuteDelay

    function MNGAReadyCheckVote_Configure(duration, executeDelay)
        configuredExecuteDelay = math.max(0, tonumber(executeDelay) or kDefaultExecuteDelay)
        SetVoteExpireTimeOverride("VoteReadyCheckStart", duration)
        SetVoteSuccessfulCallback("VoteReadyCheckStart", configuredExecuteDelay, OnReadyCheckStartVoteSuccessful)
        Print("[readycheck] vote configured duration=%s executeDelay=%s", tostring(duration), tostring(configuredExecuteDelay))
    end

    -- Called right before each StartVote: yes votes needed to pass (and no
    -- votes needed to fail), instead of a majority of the whole electorate.
    function MNGAReadyCheckVote_SetRequiredVotes(requiredVotes)
        requiredVotes = math.max(1, math.floor(tonumber(requiredVotes) or 1))
        SetVoteSuccessfulCallback("VoteReadyCheckStart", configuredExecuteDelay, OnReadyCheckStartVoteSuccessful,
            nil, requiredVotes)
        Print("[readycheck] vote required votes=%s", tostring(requiredVotes))
    end

    SetVoteServerOnly("VoteReadyCheckStart", true)
    SetVoteSuccessfulCallback("VoteReadyCheckStart", kDefaultExecuteDelay, OnReadyCheckStartVoteSuccessful)

end
