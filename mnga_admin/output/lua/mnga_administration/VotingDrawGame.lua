-- Automated vote to end the current round as a draw.

local kExecuteVoteDelay = 2

RegisterVoteType("VoteDrawGame", { })

if Client then

    local function SetupDrawGameVote(voteMenu)

        local function GetVoteDrawGameQuery(data)
            return "End this match as a draw?"
        end
        AddVoteStartListener("VoteDrawGame", GetVoteDrawGameQuery)

    end
    AddVoteSetupCallback(SetupDrawGameVote)

end

if Server then

    local function OnDrawGameVoteSuccessful(data)
        local gameRules = GetGamerules()
        if gameRules and gameRules:GetGameStarted() then
            Print("[auto_draw_vote] Draw vote passed; ending the match as a draw.")
            gameRules:DrawGame()
        else
            Print("[auto_draw_vote] Draw vote passed, but no active game was found.")
        end
    end

    SetVoteSuccessfulCallback("VoteDrawGame", kExecuteVoteDelay, OnDrawGameVoteSuccessful)

end
