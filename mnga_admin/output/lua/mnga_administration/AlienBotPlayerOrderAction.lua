-- Shared order evaluator for alien player bot brains. Each brain supplies its
-- own local movement and attack routines so ordered bots retain lifeform AI.
function CreateAlienBotPlayerOrderAction(lifeform, performMove, performAttack)
    return function(bot, brain, player)
        local order = bot:GetPlayerOrder()
        local orderType = order and order:GetType()
        local weight = 0
        local target

        if orderType == kTechId.Move or orderType == kTechId.Attack or orderType == kTechId.Defend then
            if orderType == kTechId.Attack or orderType == kTechId.Defend then
                target = Shared.GetEntity(order:GetParam())
                if not target or not HasMixin(target, "Live") or not target:GetIsAlive()
                    or (orderType == kTechId.Attack and not GetAreEnemies(player, target))
                    or (orderType == kTechId.Defend and target:GetTeamNumber() ~= player:GetTeamNumber()) then
                    target = nil
                end
            end

            if orderType == kTechId.Move or target then
                weight = 100
            end

            -- Leave the brain's normal emergency/retreat decisions available.
            if lifeform == "Skulk" and player:GetHealthScalar() < 0.4
                or lifeform == "Lerk" and (player:GetHealthScalar() < 0.6
                    or player:GetEnergy() / player:GetMaxEnergy() < 0.35)
                or lifeform == "Fade" and brain:GetSenses():Get("retreatThreshold").retreat
                or lifeform == "Onos" and player:GetHealthScalar() < 0.65 then
                weight = 0
            end
        end

        return {
            name = "commander order",
            weight = weight,
            fastUpdate = true,
            perform = function(move)
                local current = bot:GetPlayerOrder()
                if not order or current ~= order then return end
                if orderType == kTechId.Defend and target and not target:GetIsDestroyed()
                    and target:GetIsAlive() and target:GetTeamNumber() == player:GetTeamNumber() then
                    local threat = brain:GetSenses():Get("nearestThreat")
                    local memory = threat and threat.memory
                    local enemy = memory and Shared.GetEntity(memory.entId)
                    if enemy and HasMixin(enemy, "Live") and enemy:GetIsAlive()
                        and GetAreEnemies(player, enemy) and bot:GetBotCanSeeTarget(enemy)
                        and (enemy:GetOrigin() - target:GetOrigin()):GetLengthSquared() <= 100
                        and (player:GetOrigin() - target:GetOrigin()):GetLengthSquared() <= 100 then
                        if lifeform == "Skulk" or lifeform == "Lerk" then
                            performAttack(player:GetEyePos(), enemy, memory.lastSeenPos or enemy:GetOrigin(), bot, brain, move)
                        else
                            performAttack(player:GetEyePos(), enemy, bot, brain, move)
                        end
                    elseif (player:GetOrigin() - target:GetOrigin()):GetLengthSquared() > 9 then
                        bot:GetMotion():SetDesiredViewTarget(nil)
                        performMove(player:GetEyePos(), target:GetOrigin(), bot, brain, move)
                    else
                        bot:GetMotion():SetDesiredMoveTarget(nil)
                        bot:GetMotion():SetDesiredMoveDirection(nil)
                        bot:GetMotion():SetDesiredViewTarget(target:GetOrigin())
                    end
                elseif orderType == kTechId.Attack and target and not target:GetIsDestroyed()
                    and target:GetIsAlive() and GetAreEnemies(player, target) then
                    if lifeform == "Skulk" or lifeform == "Lerk" then
                        performAttack(player:GetEyePos(), target, target:GetOrigin(), bot, brain, move)
                    else
                        performAttack(player:GetEyePos(), target, bot, brain, move)
                    end
                elseif orderType == kTechId.Move then
                    bot:GetMotion():SetDesiredViewTarget(nil)
                    performMove(player:GetEyePos(), order:GetLocation(), bot, brain, move)
                end
            end
        }
    end
end
