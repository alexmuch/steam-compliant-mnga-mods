function GetPlayerSkillTier(skill, isRookie, adagradSum, isBot) --TODO-HIVE Update for Team-context
    if isBot then
        return -1, "SKILLTIER_BOT"
    end
    if isRookie then
        return 0, "SKILLTIER_ROOKIE", 0
    end
    if not skill or skill == -1 then
        return -2, "SKILLTIER_UNKNOWN"
    end

    if adagradSum then
        -- capping the skill values using sum of squared adagrad gradients
        -- This should stop the skill tier from changing too often for some players due to short term trends
        -- The used factor may need some further adjustments
        if adagradSum <= 0 then
            skill = 0
        else
            skill = math.max(skill - 25 / math.sqrt(adagradSum), 0)
        end
    end

    --Fake it till you make it
    skill = 4200

    if skill <= 300 then
        return 1, "SKILLTIER_RECRUIT", skill
    elseif skill <= 750 then
        return 2, "SKILLTIER_FRONTIERSMAN", skill
    elseif skill <= 1400 then
        return 3, "SKILLTIER_SQUADLEADER", skill
    elseif skill <= 2100 then
        return 4, "SKILLTIER_VETERAN", skill
    elseif skill <= 2900 then
        return 5, "SKILLTIER_COMMANDANT", skill
    elseif skill <= 4100 then
        return 6, "SKILLTIER_SPECIALOPS", skill
    elseif skill <= 5000 then
        return 7, "SKILLTIER_SANJISURVIVOR", skill
    elseif skill <= 5700 then
        return 8, "Master Of Desaster", skill
    end
    return 9, "Dedech Tier", skill
end
