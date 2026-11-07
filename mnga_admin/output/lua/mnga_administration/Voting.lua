-- ======= Copyright (c) 2003-2013, Unknown Worlds Entertainment, Inc. All rights reserved. =====
--
-- lua\Voting.lua
--
--    Created by:   Brian Cronin (brianc@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================
local kVoteExpireTime = 20
local kDefaultVoteExecuteTime = 30
local kNextVoteAllowedAfterTime = 50
-- How many seconds must pass before a client can start another vote of a certain type after a failed vote.
local kStartVoteAfterFailureLimit = 5 * 60
local kAutoDrawVoteFirstTime = 60 * 60
local kAutoDrawVoteInterval = 20 * 60
local kAutoDrawVoteRetryLogInterval = 30

Shared.RegisterNetworkMessage("SendVote", { voteId = "integer", choice = "boolean" })
Shared.RegisterNetworkMessage("VoteEligibility", { voteId = "integer", eligible = "boolean" })
kVoteState = enum( { 'InProgress', 'Passed', 'Failed' } )
Shared.RegisterNetworkMessage("VoteResults", { voteId = "integer", yesVotes = "integer (0 to 255)", noVotes = "integer (0 to 255)", requiredVotes = "integer (0 to 255)", state = "enum kVoteState" })
Shared.RegisterNetworkMessage("VoteComplete", { voteId = "integer" })
kVoteCannotStartReason = enum( { 'VoteAllowedToStart', 'VoteInProgress', 'Waiting', 'Spam', 'DisabledByAdmin', 'GameInProgress', 'TooEarly', 'TooLate', 'UnsupportedGamemode', 'ThunderdomeDisallowed', 'Spectator', 'VoteCallBanned' } )
Shared.RegisterNetworkMessage("VoteCannotStart", { reason = "enum kVoteCannotStartReason" })

local kVoteCannotStartReasonStrings = { }
kVoteCannotStartReasonStrings[kVoteCannotStartReason.VoteInProgress] = "VOTE_IN_PROGRESS"
kVoteCannotStartReasonStrings[kVoteCannotStartReason.Waiting] = "VOTE_WAITING"
kVoteCannotStartReasonStrings[kVoteCannotStartReason.Spam] = "VOTE_SPAM"
kVoteCannotStartReasonStrings[kVoteCannotStartReason.GameInProgress] = "VOTE_GAME_IN_PROGRESS"
kVoteCannotStartReasonStrings[kVoteCannotStartReason.DisabledByAdmin] = "VOTE_DISABLED_BY_ADMIN"
kVoteCannotStartReasonStrings[kVoteCannotStartReason.TooEarly] = "VOTE_TOO_EARLY"
kVoteCannotStartReasonStrings[kVoteCannotStartReason.TooLate] = "VOTE_TOO_LATE"
kVoteCannotStartReasonStrings[kVoteCannotStartReason.UnsupportedGamemode] = "VOTE_GAMEMODE_NOT_SUPPORTED"
kVoteCannotStartReasonStrings[kVoteCannotStartReason.ThunderdomeDisallowed] = "VOTE_THUNDERDOME_DISALLOWED"
kVoteCannotStartReasonStrings[kVoteCannotStartReason.Spectator] = "Spectators cannot start votes."
kVoteCannotStartReasonStrings[kVoteCannotStartReason.VoteCallBanned] = "You are temporarily banned from calling votes."

-- to prevent message from being re-hooked when interface is re-created.
local hookedVoteTypes = {}

local kThunderdomeValidVotes
-- Checks if the votename is allowed under Thunderdome. If thunderdome mode is not active, will just return true.
function GetStartVoteAllowedForThunderdome(voteName)

    if not kThunderdomeValidVotes then
        kThunderdomeValidVotes = set
        {
            "VoteThunderdomeRematch",
            "VoteKickPlayer",
            "VoteThunderdomeSkipIntermission",
            "VoteThunderdomeDrawGame",
        }
    end

    if not Shared.GetThunderdomeEnabled() then
        return true
    end

    return kThunderdomeValidVotes[voteName]

end

if Server then

    -- Allow reset between Countdown and kMaxTimeBeforeReset
    function VotingResetGameAllowed()
        local gameRules = GetGamerules()
        return gameRules:GetGameState() == kGameState.Countdown or (gameRules:GetGameStarted() and Shared.GetTime() - gameRules:GetGameStartTime() < kMaxTimeBeforeReset)
    end
    
    local activeVoteName, activeVoteData, activeVoteResults, activeVoteStartedAtTime
    local activeVoteElectorate, activeVoteElectorateSize, activeVoteTeam
    local activeVoteId = 0
    local lastVoteStartAtTime
    local lastTimeVoteResultsSent = 0
    local voteSuccessfulCallbacks = { }
    -- Per-vote overrides (.claude/docs/ready-check.md). Votes named in
    -- serverOnlyVotes can only be started by the server (StartVote with a nil
    -- client); voteExpireTimeOverrides replaces kVoteExpireTime for that vote.
    local serverOnlyVotes = { }
    local voteExpireTimeOverrides = { }

    function SetVoteServerOnly(voteName, serverOnly)
        serverOnlyVotes[voteName] = serverOnly and true or nil
    end

    function SetVoteExpireTimeOverride(voteName, expireTime)
        expireTime = tonumber(expireTime)
        voteExpireTimeOverrides[voteName] = expireTime and expireTime > 0 and expireTime or nil
    end

    local function GetVoteExpireTime(voteName)
        return voteName and voteExpireTimeOverrides[voteName] or kVoteExpireTime
    end
    
    local kMaxStartVoteHistory = 100
    local startVoteHistory = { }

    local kPunitiveVoteTargetFields = {
        VoteKickPlayer = "kick_client",
        VoteGagPlayer = "gag_client",
        VoteCommBanPlayer = "commban_client",
        VoteMoveToSpecPlayer = "spec_client",
        VoteVoteCallBanPlayer = "voteban_client"
    }

    local function GetPlayingTeamNumber(client)
        local player = client and client:GetControllingPlayer()
        local teamNumber = player and player:GetTeamNumber()
        if teamNumber == kTeam1Index or teamNumber == kTeam2Index then
            return teamNumber
        end
        return nil
    end

    local function BuildVoteElectorate(voteName, caller, data)
        local electorate = {}
        local electorateSize = 0
        local electorateTeam
        local targetField = kPunitiveVoteTargetFields[voteName]
        local gamerules = GetGamerules()

        if targetField and caller and gamerules and gamerules:GetGameStarted() then
            local callerTeam = GetPlayingTeamNumber(caller)
            local target = data[targetField] and Server.GetClientById(data[targetField])
            local targetTeam = GetPlayingTeamNumber(target)
            if callerTeam and callerTeam == targetTeam then
                electorateTeam = callerTeam
            end
        end

        local clients = Shine and Shine.GetAllClients and Shine.GetAllClients() or {}
        for i = 1, #clients do
            local candidate = clients[i]
            local isHuman = not candidate:GetIsVirtual()
            local isPlaying = not candidate:GetIsSpectator()
            local onElectorateTeam = not electorateTeam or GetPlayingTeamNumber(candidate) == electorateTeam
            if isHuman and isPlaying and onElectorateTeam then
                electorate[candidate:GetUserId()] = true
                electorateSize = electorateSize + 1
            end
        end

        return electorate, electorateSize, electorateTeam, clients
    end

    local function GetMNGAAdministrationPlugin()
        return Shine and Shine.Plugins and Shine.Plugins.mngaadministration
    end

    local function GetVoteCallBanConfig()
        local plugin = GetMNGAAdministrationPlugin()
        if not plugin or not plugin.Config then
            return nil, plugin
        end

        plugin.Config.VoteCallBanned = plugin.Config.VoteCallBanned or {}
        return plugin.Config.VoteCallBanned, plugin
    end

    local function SaveVoteCallBanConfig(plugin)
        if plugin and plugin.SaveConfig then
            plugin:SaveConfig(true)
        end
    end

    function AddVoteCallBan(client, minutes, reason)
        if not client then
            Print("VoteCallBan: cannot add ban, target client is nil")
            return false
        end

        local banned, plugin = GetVoteCallBanConfig()
        if not banned then
            Print("VoteCallBan: mngaadministration config unavailable, cannot persist ban for %s", tostring(client:GetUserId()))
            return false
        end

        local userId = tostring(client:GetUserId())
        local player = client:GetControllingPlayer()
        local name = player and player:GetName() or "<unknown>"
        local now = os.time()
        local duration = (tonumber(minutes) or 60) * 60

        banned[userId] = {
            Name = name,
            UnbanTime = now + duration,
            Reason = reason or "Player vote vote-call-ban"
        }

        SaveVoteCallBanConfig(plugin)

        Print("VoteCallBan: added %s [%s] until %s (%s seconds)", name, userId, tostring(banned[userId].UnbanTime), tostring(duration))
        return true
    end

    local function GetVoteCallBan(client)
        if not client then
            return nil
        end

        local banned, plugin = GetVoteCallBanConfig()
        if not banned then
            return nil
        end

        local userId = tostring(client:GetUserId())
        local banData = banned[userId]
        if not banData then
            return nil
        end

        local now = os.time()
        local unbanTime = tonumber(banData.UnbanTime) or 0
        if unbanTime == 0 or unbanTime > now then
            return banData
        end

        banned[userId] = nil
        SaveVoteCallBanConfig(plugin)
        Print("VoteCallBan: removed expired ban for %s [%s]", banData.Name or "<unknown>", userId)

        return nil
    end
    
    function GetStartVoteAllowed(voteName, client)

        local BetterVoting = Shine and Shine.Plugins and Shine.Plugins.bettervoting
        if BetterVoting and BetterVoting.Enabled and BetterVoting.ActiveVote then
            return kVoteCannotStartReason.VoteInProgress
        end

        if not GetStartVoteAllowedForThunderdome(voteName) then
            return kVoteCannotStartReason.ThunderdomeDisallowed
        end

        if client and serverOnlyVotes[voteName] then
            Print("[voting] Denying client start of server-only vote '%s' from %s", tostring(voteName), tostring(client:GetUserId()))
            return kVoteCannotStartReason.DisabledByAdmin
        end

        if client then
            local voteCallBan = GetVoteCallBan(client)
            if voteCallBan then
                Print(
                    "VoteCallBan: denying vote start '%s' from %s [%s], expires at %s",
                    tostring(voteName),
                    tostring(voteCallBan.Name or "<unknown>"),
                    tostring(client:GetUserId()),
                    tostring(voteCallBan.UnbanTime)
                )
                return kVoteCannotStartReason.VoteCallBanned
            end
        end

        -- Check that there is no current vote.
        if activeVoteName then    
            return kVoteCannotStartReason.VoteInProgress
        end
        
        -- Check that enough time has passed since the last vote.
        if lastVoteStartAtTime and Shared.GetTime() - lastVoteStartAtTime < kNextVoteAllowedAfterTime then
            return kVoteCannotStartReason.Waiting
        end
        
        -- Check that this client hasn't started a failed vote of this type recently.
        if client then
            for v = #startVoteHistory, 1, -1 do

                local vote = startVoteHistory[v]
                if voteName == vote.type and client:GetUserId() == vote.client_id then

                    if not vote.succeeded and Shared.GetTime() - vote.start_time < kStartVoteAfterFailureLimit then
                        return kVoteCannotStartReason.Spam
                    end

                end

            end

            -- Spectators cannot start votes. sh_customvote is admin-gated by
            -- Shine, so admins may run it from spectate.
            if client:GetIsSpectator() and voteName ~= "ShineCustomVote" then
                return kVoteCannotStartReason.Spectator
            end

        end
        
        local votingSettings = Server.GetConfigSetting("voting")
        if votingSettings and votingSettings[string.lower(voteName)] == false then
            return kVoteCannotStartReason.DisabledByAdmin
        end
        
        if voteName == "VoteResetGame" then
            if not VotingResetGameAllowed() then
                if GetGamerules():GetGameState() < kGameState.Countdown then
                    return kVoteCannotStartReason.TooEarly
                else
                    return kVoteCannotStartReason.TooLate
                end
            end
        end

        if voteName == "VoteAddCommanderBots" then
            if not VotingAddCommanderBotsAllowed() then
                return kVoteCannotStartReason.UnsupportedGamemode
            end
        end
        
        if voteName == "VotingForceEvenTeams" then
            if GetGamerules():GetGameStarted() then
                return kVoteCannotStartReason.GameInProgress
            end
        end
        
        return kVoteCannotStartReason.VoteAllowedToStart
        
    end
    
    function StartVote(voteName, client, data)
        Log("StartVote( '%s', %s, %s )", voteName, client, data)
        data = data or {}
        local voteCanStart = GetStartVoteAllowed(voteName, client)
        if voteCanStart == kVoteCannotStartReason.VoteAllowedToStart then

            local clientId = client and client:GetId() or 0
        
            activeVoteId = activeVoteId + 1
            activeVoteName = voteName
            activeVoteResults = {
                voters = {},
                votes = {}
            }
            local clients
            activeVoteElectorate, activeVoteElectorateSize, activeVoteTeam, clients = BuildVoteElectorate(voteName, client, data)
            activeVoteStartedAtTime = Shared.GetTime()
            lastVoteStartAtTime = activeVoteStartedAtTime
            data.voteId = activeVoteId
            local now = Shared.GetTime()
            data.expireTime = now + GetVoteExpireTime(voteName)
            data.client_index = clientId
            Server.SendNetworkMessage(voteName, data)
            for i = 1, #clients do
                local recipient = clients[i]
                Server.SendNetworkMessage(recipient, "VoteEligibility", {
                    voteId = activeVoteId,
                    eligible = activeVoteElectorate[recipient:GetUserId()] == true
                }, true)
            end
            
            activeVoteData = data
            
            local userId = client and client:GetUserId() or 0
            table.insert(startVoteHistory, { type = voteName, client_id = userId, start_time = now, succeeded = false })
            if #startVoteHistory > kMaxStartVoteHistory then
                local removedVote = table.remove(startVoteHistory, 1)
                Log(
                    "[VotingHistory] Pruned oldest entry at cap=%s type='%s' clientId=%s startTime=%s",
                    kMaxStartVoteHistory,
                    tostring(removedVote and removedVote.type),
                    tostring(removedVote and removedVote.client_id),
                    tostring(removedVote and removedVote.start_time)
                )
            end
            Log("Voting: startVoteHistory length is now %s after starting '%s'", #startVoteHistory, voteName)
            
            Print("%s", "Started Vote: " .. voteName)
            Print("%s", string.format(
                "[voting] Started %s voteId=%s mode=%s team=%s electorate=%s required=%s",
                tostring(voteName),
                tostring(activeVoteId),
                activeVoteTeam and "team" or "global",
                tostring(activeVoteTeam or 0),
                tostring(activeVoteElectorateSize),
                tostring(math.floor(activeVoteElectorateSize / 2) + 1)
            ))

            return true
            
        elseif client then
            Server.SendNetworkMessage(client, "VoteCannotStart", { reason = voteCanStart }, true)
        end

        return false, voteCanStart
        
    end
    
    function HookStartVote(voteName)
        
        local function OnStartVoteReceived(client, message)
            StartVote(voteName, client, message)
        end
        Server.HookNetworkMessage(voteName, OnStartVoteReceived)
        
    end
    
    function RegisterVoteType(voteName, voteData)
        
        assert(voteData.voteId == nil, "voteId field detected while registering a vote type")
        voteData.voteId = "integer"

        assert(voteData.expireTime == nil, "expireTime field detected while registering a vote type")
        voteData.expireTime = "time"

        assert(voteData.client_index == nil, "client_index field detected while registering a vote type")
        voteData.client_index = "integer"

        Shared.RegisterNetworkMessage(voteName, voteData)
        HookStartVote(voteName)
        
    end
    
    function SetVoteSuccessfulCallback(voteName, delayTime, callback, extraCheck, requiredVotes)
    
        local voteSuccessfulCallback = { }
        voteSuccessfulCallback.delayTime = delayTime
        voteSuccessfulCallback.callback = callback
        voteSuccessfulCallback.extraCheck = extraCheck
        voteSuccessfulCallback.requiredVotes = requiredVotes

        voteSuccessfulCallbacks[voteName] = voteSuccessfulCallback
        
    end
    
    local function CountVotes(voteResults)
    
        local yes = 0
        local no = 0
        for i = 1, #voteResults.voters do

            local voter = voteResults.voters[i]
            local choice = voteResults.votes[voter]

            yes = (choice and yes + 1) or yes
            no = (not choice and no + 1) or no
            
        end
        
        return yes, no
        
    end
    
    local lastVoteSent = 0
    
    local function OnSendVote(client, message)
    
        if activeVoteName then
        
            if not activeVoteElectorate or not activeVoteElectorate[client:GetUserId()] then
                Print("%s", string.format(
                    "[voting] Rejected ineligible ballot voteId=%s userId=%s team=%s spectator=%s",
                    tostring(activeVoteId),
                    tostring(client:GetUserId()),
                    tostring(GetPlayingTeamNumber(client) or 0),
                    tostring(client:GetIsSpectator())
                ))
                return
            end

            local votingDone = Shared.GetTime() - activeVoteStartedAtTime >= GetVoteExpireTime(activeVoteName)
            if not votingDone and message.voteId == activeVoteId then
                local clientId = client:GetUserId()
                if not activeVoteResults.votes[clientId] then
                    table.insert(activeVoteResults.voters, clientId)
                end

                activeVoteResults.votes[clientId] = message.choice
                lastVoteSent = Shared.GetTime()
            end
            
        end
        
    end
    Server.HookNetworkMessage("SendVote", OnSendVote)
    
    local function GetNumVotingPlayers()
        return Server.GetNumPlayers() - #gServerBots - Server.GetNumSpectators()
    end
        
    local function GetVotePassed(yesVotes, noVotes, required)
        return yesVotes >= required
    end

    local nextAutoDrawVoteTime
    local autoDrawVoteRoundStartTime
    local lastAutoDrawVoteRetryLogTime = 0

    local function ResetAutoDrawVoteSchedule()
        if nextAutoDrawVoteTime then
            Print("[auto_draw_vote] Resetting automatic draw vote schedule.")
        end

        nextAutoDrawVoteTime = nil
        autoDrawVoteRoundStartTime = nil
        lastAutoDrawVoteRetryLogTime = 0
    end

    local function UpdateAutoDrawVoteSchedule()
        if Shared.GetThunderdomeEnabled() then
            ResetAutoDrawVoteSchedule()
            return
        end

        local gameRules = GetGamerules()
        if not gameRules or not gameRules:GetGameStarted() then
            ResetAutoDrawVoteSchedule()
            return
        end

        local roundStartTime = gameRules:GetGameStartTime()
        if not roundStartTime or roundStartTime <= 0 then
            return
        end

        if autoDrawVoteRoundStartTime ~= roundStartTime then
            autoDrawVoteRoundStartTime = roundStartTime
            nextAutoDrawVoteTime = roundStartTime + kAutoDrawVoteFirstTime
            lastAutoDrawVoteRetryLogTime = 0
            Print("%s", string.format(
                "[auto_draw_vote] Scheduled first automatic draw vote for %.0f seconds into this round.",
                kAutoDrawVoteFirstTime
            ))
        end
    end

    local function TryStartAutoDrawVote()
        UpdateAutoDrawVoteSchedule()

        if not nextAutoDrawVoteTime then
            return
        end

        local now = Shared.GetTime()
        if now < nextAutoDrawVoteTime then
            return
        end

        if activeVoteName then
            if now - lastAutoDrawVoteRetryLogTime >= kAutoDrawVoteRetryLogInterval then
                Print("%s", string.format("[auto_draw_vote] Waiting to start draw vote; '%s' is already active.", tostring(activeVoteName)))
                lastAutoDrawVoteRetryLogTime = now
            end
            return
        end

        if lastVoteStartAtTime and now - lastVoteStartAtTime < kNextVoteAllowedAfterTime then
            if now - lastAutoDrawVoteRetryLogTime >= kAutoDrawVoteRetryLogInterval then
                Print("%s", string.format(
                    "[auto_draw_vote] Waiting to start draw vote; vote cooldown has %.0f seconds remaining.",
                    kNextVoteAllowedAfterTime - (now - lastVoteStartAtTime)
                ))
                lastAutoDrawVoteRetryLogTime = now
            end
            return
        end

        local numVotingPlayers = GetNumVotingPlayers()
        if numVotingPlayers <= 0 then
            if now - lastAutoDrawVoteRetryLogTime >= kAutoDrawVoteRetryLogInterval then
                Print("[auto_draw_vote] Waiting to start draw vote; no eligible non-spectator human players.")
                lastAutoDrawVoteRetryLogTime = now
            end
            return
        end

        local scheduledTime = nextAutoDrawVoteTime
        local started, reason = StartVote("VoteDrawGame", nil, {})
        if not started then
            if now - lastAutoDrawVoteRetryLogTime >= kAutoDrawVoteRetryLogInterval then
                Print("%s", string.format("[auto_draw_vote] StartVote rejected draw vote with reason %s; will retry.", tostring(reason)))
                lastAutoDrawVoteRetryLogTime = now
            end
            return
        end

        repeat
            nextAutoDrawVoteTime = nextAutoDrawVoteTime + kAutoDrawVoteInterval
        until nextAutoDrawVoteTime > now

        Print("%s", string.format(
            "[auto_draw_vote] Started automatic draw vote at %.0f seconds elapsed; scheduled threshold was %.0f seconds; next scheduled at %.0f seconds.",
            now - autoDrawVoteRoundStartTime,
            scheduledTime - autoDrawVoteRoundStartTime,
            nextAutoDrawVoteTime - autoDrawVoteRoundStartTime
        ))

        lastAutoDrawVoteRetryLogTime = 0
    end
    
    local function OnUpdateVoting(dt)

        TryStartAutoDrawVote()
    
        if activeVoteName then

            local voteSuccessfulCallback = voteSuccessfulCallbacks[activeVoteName]
        
            local yes, no = CountVotes(activeVoteResults)
            local required = (voteSuccessfulCallback.requiredVotes or math.floor(activeVoteElectorateSize / 2) + 1)
            local voteSuccessful = GetVotePassed(yes, no, required)
            local voteFailed = no >= required
        
            if Shared.GetTime() - lastTimeVoteResultsSent > 1 then
            
                local voteState = kVoteState.InProgress
                
                local votingDone = Shared.GetTime() - activeVoteStartedAtTime >= GetVoteExpireTime(activeVoteName) or voteSuccessful or voteFailed
                if votingDone then
                    voteState = voteSuccessful and kVoteState.Passed or kVoteState.Failed
                end

                Server.SendNetworkMessage("VoteResults", { voteId = activeVoteId, yesVotes = yes, noVotes = no, state = voteState, requiredVotes = required }, true)
                lastTimeVoteResultsSent = Shared.GetTime()
                
            end

            local delay = (voteSuccessfulCallback and (GetVoteExpireTime(activeVoteName) + voteSuccessfulCallback.delayTime)) or kDefaultVoteExecuteTime
            
            if voteSuccessful then
                delay = lastVoteSent - activeVoteStartedAtTime + voteSuccessfulCallback.delayTime
            end

            if Shared.GetTime() - activeVoteStartedAtTime >= delay then
            
                Server.SendNetworkMessage("VoteComplete", { voteId = activeVoteId }, true)
                
                local yes, no = CountVotes(activeVoteResults)
                local voteSuccessful = GetVotePassed(yes, no, required)

                if voteSuccessful and voteSuccessfulCallback.extraCheck then
                    voteSuccessful = voteSuccessfulCallback.extraCheck(activeVoteElectorateSize, yes, no)
                end

                local historyLen = #startVoteHistory
                if historyLen > 0 then
                    startVoteHistory[historyLen].succeeded = voteSuccessful
                else
                    Log("Voting: startVoteHistory is empty during vote completion for '%s' (activeVoteId=%s, callbacks=%s)", activeVoteName, activeVoteId, voteSuccessfulCallbacks[activeVoteName] ~= nil)
                end
                Print("%s", "Vote Complete: " .. activeVoteName .. ". Successful? " .. (voteSuccessful and "Yes" or "No"))

                if voteSuccessfulCallback and voteSuccessful then
                    voteSuccessfulCallback.callback(activeVoteData)
                end
                
                if Shared.GetThunderdomeEnabled() then
                --McG: One-off Vote-Failed handler, required as votes don't have a on-failure callback mechanism atm
                    if activeVoteName == "VoteThunderdomeRematch" and not voteSuccessful then
                        GetThunderdomeRules():OnVotedRematchFailed()
                    end
                end
                
                activeVoteName = nil
                activeVoteData = nil
                activeVoteResults = nil
                activeVoteStartedAtTime = nil
                activeVoteElectorate = nil
                activeVoteElectorateSize = nil
                activeVoteTeam = nil
                
            end
            
        end
        
    end
    -- Getters used by vote type files (e.g. VotingKickPlayer) to inspect the
    -- active vote from a ClientDisconnect hook without exposing internal state.
    function GetActiveVoteName()
        return activeVoteName
    end

    function GetActiveVoteData()
        return activeVoteData
    end

    -- Ends the active vote as failed without running its callback, if it is
    -- the named vote. Used by the ready check when the check ends while its
    -- under-full vote is still open (.claude/docs/ready-check.md).
    function CancelActiveVote(voteName, reason)
        if not activeVoteName or activeVoteName ~= voteName then return false end
        local yes, no = CountVotes(activeVoteResults)
        Server.SendNetworkMessage("VoteResults", { voteId = activeVoteId, yesVotes = yes, noVotes = no,
            state = kVoteState.Failed, requiredVotes = math.max(yes, 1) }, true)
        Server.SendNetworkMessage("VoteComplete", { voteId = activeVoteId }, true)
        local historyLen = #startVoteHistory
        if historyLen > 0 then
            startVoteHistory[historyLen].succeeded = false
        end
        Print("%s", string.format("[voting] Cancelled %s voteId=%s reason=%s", voteName, tostring(activeVoteId), tostring(reason)))
        activeVoteName = nil
        activeVoteData = nil
        activeVoteResults = nil
        activeVoteStartedAtTime = nil
        activeVoteElectorate = nil
        activeVoteElectorateSize = nil
        activeVoteTeam = nil
        return true
    end

    -- Ends whatever vote is active (admin sh_stopvote). Replaces Shine
    -- basecommands' upvalue hack, which only finds a function from
    -- "@lua/Voting.lua" and never clears our electorate state.
    function StopActiveVote(reason)
        local voteName = activeVoteName
        Print("%s", string.format("[voting] StopActiveVote active=%s voteId=%s reason=%s",
            tostring(voteName), tostring(activeVoteId), tostring(reason)))
        if not voteName then return false end
        return CancelActiveVote(voteName, reason), voteName
    end

    Event.Hook("UpdateServer", OnUpdateVoting)
    
end

if Client then

    local currentVoteQuery
    local currentVoteId = 0
    local currentVoteExpireTime = 0
    local yesVotes = 0
    local noVotes = 0
    local requiredVotes = 0
    local currentVoteEligible
    local pendingVoteEligibility = {}
    local lastVoteResults
    
    function RegisterVoteType(voteName, voteData)
        
        assert(voteData.voteId == nil, "voteId field detected while registering a vote type")
        voteData.voteId = "integer"

        assert(voteData.expireTime == nil, "expireTime field detected while registering a vote type")
        voteData.expireTime = "time"

        assert(voteData.client_index == nil, "client_index field detected while registering a vote type")
        voteData.client_index = "integer"
        
        Shared.RegisterNetworkMessage(voteName, voteData)
        
    end
    
    local voteSetupCallbacks = { }
    function AddVoteSetupCallback(callback)
        table.insert(voteSetupCallbacks, callback)
    end
    
    function AttemptToStartVote(voteName, data)
        Client.SendNetworkMessage(voteName, data, true)
    end
    
    function SendVoteChoice(votedYes)
    
        if currentVoteEligible ~= true then
            return
        end

        if currentVoteId > 0 then
        
            -- Predict the vote locally for the UI.
            if votedYes then
                yesVotes = yesVotes + 1
            else
                noVotes = noVotes + 1
            end
            
            Client.SendNetworkMessage("SendVote", { voteId = currentVoteId, choice = votedYes }, true)
            
        end
        
    end
    
    function GetCurrentVoteId()
        return currentVoteId
    end
    
    function GetCurrentVoteQuery()
        if currentVoteQuery and currentVoteEligible == false then
            return currentVoteQuery .. " (Not eligible)"
        end
        return currentVoteQuery
    end

    function GetCurrentVoteEligibility()
        return currentVoteEligible
    end
    
    function GetCurrentVoteTimeLeft()
        return (math.max(0, currentVoteExpireTime - Shared.GetTime()))
    end
    
    function GetLastVoteResults()
        return lastVoteResults
    end
    
    function AddVoteStartListener(voteName, queryTextGenerator)
        
        if hookedVoteTypes[voteName] then
            return
        end
        
        local function OnVoteStarted(data)
            PROFILE("Voting:OnVoteStarted")
            currentVoteId = data.voteId
            currentVoteExpireTime = data.expireTime
            yesVotes = 0
            noVotes = 0
            requiredVotes = 0
            currentVoteQuery = queryTextGenerator(data)
            -- Fail closed until the server's matching per-client eligibility arrives.
            currentVoteEligible = pendingVoteEligibility[data.voteId]
            pendingVoteEligibility[data.voteId] = nil
            lastVoteResults = nil
            local starterName = data.client_index and data.client_index > 0 and Scoreboard_GetPlayerName(data.client_index) or "Server"
            local message = StringReformat(Locale.ResolveString("VOTE_PLAYER_STARTED_VOTE"), { name = starterName })
            ChatUI_AddSystemMessage(message)
            
        end
        Client.HookNetworkMessage(voteName, OnVoteStarted)
        
        hookedVoteTypes[voteName] = true
        
    end
    
    local function OnVoteResults(message)
        PROFILE("Voting:OnVoteResults")
        if currentVoteId == message.voteId then
        
            -- Use the higher value as we predict the vote for the local player.
            yesVotes = math.max(yesVotes, message.yesVotes)
            noVotes = math.max(noVotes, message.noVotes)
            requiredVotes = math.max(requiredVotes, message.requiredVotes)
            
            if message.state == kVoteState.Passed then
                lastVoteResults = true
            elseif message.state == kVoteState.Failed then
                lastVoteResults = false
            end
            
        end
        
    end
    Client.HookNetworkMessage("VoteResults", OnVoteResults)

    local function OnVoteEligibility(message)
        PROFILE("Voting:OnVoteEligibility")
        if currentVoteId == message.voteId then
            currentVoteEligible = message.eligible
            Print("%s", string.format(
                "[voting] Client eligibility voteId=%s eligible=%s",
                tostring(message.voteId),
                tostring(message.eligible)
            ))
        else
            -- Vote-start and eligibility use separate messages. Retain an early
            -- eligibility message until the matching vote-start callback runs.
            pendingVoteEligibility[message.voteId] = message.eligible
        end
    end
    Client.HookNetworkMessage("VoteEligibility", OnVoteEligibility)
    
    function GetVoteResults()
        return yesVotes, noVotes, requiredVotes
    end
    
    local function OnVoteComplete(message)
        PROFILE("Voting:OnVoteComplete")
        if message.voteId == currentVoteId then
        
            currentVoteQuery = nil
            currentVoteId = 0
            currentVoteExpireTime = 0
            yesVotes = 0
            noVotes = 0
            requiredVotes = 0
            lastVoteResults = nil
            currentVoteEligible = nil
            
        end
        
    end
    Client.HookNetworkMessage("VoteComplete", OnVoteComplete)
    
    local function OnVoteCannotStart(message)
        PROFILE("Voting:OnVoteCannotStart")
        local reasonStr = kVoteCannotStartReasonStrings[message.reason]
        if not reasonStr then return end
        -- MNGA-only reasons are literal text, not locale keys.
        if message.reason == kVoteCannotStartReason.VoteCallBanned
            or message.reason == kVoteCannotStartReason.Spectator then
            ChatUI_AddSystemMessage(reasonStr)
        else
            ChatUI_AddSystemMessage(Locale.ResolveString(reasonStr))
        end
        
    end
    Client.HookNetworkMessage("VoteCannotStart", OnVoteCannotStart)
    
    -- Called after the vote menu is created.
    function OnGUIStartVoteMenuCreated(name, script)
    
        if name ~= "GUIStartVoteMenu" then
            return
        end
        
        -- Setup all the vote types.
        for s = 1, #voteSetupCallbacks do
            voteSetupCallbacks[s](script)
        end
        
    end
    
end

--Load all the Votes
Script.Load("lua/mnga_administration/VotingGagPlayer.lua")
Script.Load("lua/mnga_administration/VotingCommBanPlayer.lua")
-- Register the ordinary player-started Shadow-Realm vote. Better Voting's
-- post-round commander flow is separate and may be disabled, so it is not a
-- replacement for this start-vote menu entry.
Script.Load("lua/mnga_administration/VotingMoveToSpecPlayer.lua")
Script.Load("lua/mnga_administration/VotingVoteCallBanPlayer.lua")
Script.Load("lua/VotingChangeMap.lua")
Script.Load("lua/VotingResetGame.lua")
Script.Load("lua/VotingRandomizeRR.lua")
Script.Load("lua/VotingForceEvenTeams.lua")
Script.Load("lua/VotingAddCommanderBots.lua")
Script.Load("lua/mnga_administration/VotingDrawGame.lua")
Script.Load("lua/mnga_administration/VotingReadyCheckStart.lua")

if Shared.GetThunderdomeEnabled() then
    Script.Load("lua/VotingThunderdomeRematch.lua")
    Script.Load("lua/VotingThunderdomeSkipIntermission.lua")
    Script.Load("lua/VotingThunderdomeDrawGame.lua")
end

-- Register kick last so the high-impact option stays at the bottom of the start-vote menu.
Script.Load("lua/VotingKickPlayer.lua")
