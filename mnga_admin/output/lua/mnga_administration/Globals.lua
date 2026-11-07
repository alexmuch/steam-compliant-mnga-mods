kNNSLB_DEBUG_LOG = false
kNNSLB_INSERT_OWN_ID = false -- Sanity check to make sure badge info works (client side)

kMNGASkillTierConfig = kMNGASkillTierConfig or {
    UseAdagradSkillCap = false,

    -- MNGA uses custom tier 5/6 boundaries. Tier 7 covers the gap before the
    -- custom MNGA tier 8/9 emblems.
    Tiers = {
        [1] = { MaxSkill = 300,  Name = "SKILLTIER_RECRUIT" },
        [2] = { MaxSkill = 750,  Name = "SKILLTIER_FRONTIERSMAN" },
        [3] = { MaxSkill = 1400, Name = "SKILLTIER_SQUADLEADER" },
        [4] = { MaxSkill = 2100, Name = "SKILLTIER_VETERAN" },
        [5] = { MaxSkill = 2999, Name = "SKILLTIER_COMMANDANT" },
        [6] = { MaxSkill = 3999, Name = "SKILLTIER_SPECIALOPS" },
        [7] = { MaxSkill = 4999, Name = "SKILLTIER_SANJISURVIVOR" },
        [8] = { MaxSkill = 5999, Name = "Alterra Field Marshal" },
        [9] = { Name = "LEGEND" },
    },

    PingColors = {
        [1] = Color(0xE8/255, 0xBA/255, 0xC6/255, 1),
        [2] = Color(0x98/255, 0x7B/255, 0x61/255, 1),
        [3] = Color(0xDB/255, 0xEF/255, 0xF4/255, 1),
        [4] = Color(0xFF/255, 0xF5/255, 0x91/255, 1),
        [5] = Color(0x70/255, 0xC1/255, 0xF3/255, 1),
        [6] = Color(0x83/255, 0x49/255, 0xE9/255, 1),
        [7] = Color(0xF2/255, 0x2B/255, 0x2F/255, 1),
        [8] = Color(0xF2/255, 0x2B/255, 0x2F/255, 1),
        [9] = Color(0xF2/255, 0x2B/255, 0x2F/255, 1),
    }
}

Print("[MNGASkillTier] Loaded skill tiers: tier 5 <= 2999, tier 6 = 3000-3999, tier 7 >= 4000")

function MNGA_GetSkillTierConfig()
    return kMNGASkillTierConfig
end

function MNGA_GetSkillTierForSkill(skill, isRookie, adagradSum, isBot)

    if isBot then return -1, "SKILLTIER_BOT" end
    if not skill or skill == -1 then return -2, "SKILLTIER_UNKNOWN" end
    if isRookie and skill <= 300 then return 0, "SKILLTIER_ROOKIE", 0 end

    local config = MNGA_GetSkillTierConfig()

    if config and config.UseAdagradSkillCap and adagradSum then
        if adagradSum <= 0 then
            skill = 0
        else
            skill = math.max(skill - 25 / math.sqrt(adagradSum), 0)
        end
    end

    local tiers = config and config.Tiers
    if not tiers then return 7, "SKILLTIER_SANJISURVIVOR", skill end

    local lastTier, lastName = 7, "SKILLTIER_SANJISURVIVOR"
    for tier = 1, #tiers do
        local tierConfig = tiers[tier]
        if tierConfig then
            lastTier = tier
            lastName = tierConfig.Name or lastName
            if not tierConfig.MaxSkill or skill <= tierConfig.MaxSkill then
                return tier, lastName, skill
            end
        end
    end

    return lastTier, lastName, skill

end

function MNGA_GetSkillTierDescription(tier)

    if tier == -1 then return "SKILLTIER_BOT" end
    if tier == 0 then return "SKILLTIER_ROOKIE" end

    local config = MNGA_GetSkillTierConfig()
    local tierConfig = config and config.Tiers and config.Tiers[tier]
    if tierConfig and tierConfig.Name then
        return tierConfig.Name
    end

    return "SKILLTIER_UNKNOWN"

end

function MNGA_GetSkillTierColor(tier)

    local config = MNGA_GetSkillTierConfig()
    return config and config.PingColors and config.PingColors[tier]

end

kNNSLPlacementRankKey = enum (
{
    "placement-1",
    "placement-2",
    "placement-3",
})

function NNSL_DebugLog(formatStr, ...)

    if not kNNSLB_DEBUG_LOG then return end
    formatStr = string.format("[NNSLBadges] %s", formatStr)

    Log(formatStr, ...)

end
