-- Keep the stock vote visible to observers, but do not let an ineligible client
-- create the stock local voted highlight before SendVoteChoice rejects the vote.
local OldSendKeyEvent = GUIVoteMenu.SendKeyEvent

function GUIVoteMenu:SendKeyEvent(key, down)
    if down and GetCurrentVoteId() > 0 and GetCurrentVoteEligibility and GetCurrentVoteEligibility() ~= true then
        if GetIsBinding(key, "VoteYes") or GetIsBinding(key, "VoteNo") then
            return true
        end
    end

    return OldSendKeyEvent(self, key, down)
end
