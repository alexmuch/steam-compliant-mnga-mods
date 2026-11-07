-- Marine bot commanders can repeatedly queue MACs from Robotics Factories.
-- Keep the base action's MAC-management pass, but make its build choice
-- permanently ineligible and guard its perform callback as a second layer.

if not Server then
    return
end

local kMACActionName = "BuildAndManageMACs"
local numWrappedActions = 0

local function WrapActionEvaluator(actionEvaluator)
    return function(bot, brain, com)
        local action = actionEvaluator(bot, brain, com)

        if action and action.name == kMACActionName then
            action.weight = 0
            action.perform = function()
                Print("[MarineCommanderNoMACs] Blocked a marine bot commander MAC build attempt")
            end
        end

        return action
    end
end

for index, actionEvaluator in ipairs(kMarineComBrainActions or {}) do
    kMarineComBrainActions[index] = WrapActionEvaluator(actionEvaluator)
    numWrappedActions = numWrappedActions + 1
end

Print("%s", string.format("[MarineCommanderNoMACs] Installed MAC build guard across %d commander actions", numWrappedActions))
