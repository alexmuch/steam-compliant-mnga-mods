Script.Load("lua/mnga_administration/Globals.lua")

local VanillaGetPlayerSkillTier = GetPlayerSkillTier
local VanillaGetSkillTierDescription = GetSkillTierDescription

function GetPlayerSkillTier(skill, isRookie, adagradSum, isBot)

    if MNGA_GetSkillTierForSkill then
        return MNGA_GetSkillTierForSkill(skill, isRookie, adagradSum, isBot)
    end

    return VanillaGetPlayerSkillTier(skill, isRookie, adagradSum, isBot)

end

function GetSkillTierDescription(tier)

    if MNGA_GetSkillTierDescription then
        return MNGA_GetSkillTierDescription(tier)
    end

    return VanillaGetSkillTierDescription(tier)

end
