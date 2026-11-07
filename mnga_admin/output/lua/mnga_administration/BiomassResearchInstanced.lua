-- Post-hook on lua/TechTree.lua (shared).
-- Biomass research shows in the field players' left-side research list
-- (Hud/GUIEvent). Vanilla only lists kTechType.Research nodes or "instanced"
-- tech; ResearchBioMass* are Upgrade nodes and several hives can research the
-- same id at once, so they are marked instanced like the hive-type upgrades.
-- Vanilla then tracks progress per hive (TechNode.instances), sends
-- TechNodeInstance messages and the client adds one list entry per hive.
-- The list title gets the hive level the research reaches ("BIOMASS 2").
-- See .claude/docs/biomass-research-list.md.

local kBiomassResearchTargetLevel =
{
    [kTechId.ResearchBioMassOne] = 2,
    [kTechId.ResearchBioMassTwo] = 3,
    [kTechId.ResearchBioMassThree] = 4,
    [kTechId.ResearchBioMassFour] = 5,
}

function MNGAGetBiomassResearchTargetLevel(techId)
    return kBiomassResearchTargetLevel[techId]
end

local oldGetTechIdIsInstanced = GetTechIdIsInstanced
function GetTechIdIsInstanced(techId)

    if kBiomassResearchTargetLevel[techId] then
        return true
    end
    return oldGetTechIdIsInstanced(techId)

end

-- GUINotificationItem reads kTechDataResearchName for the title; biomass has
-- none (vanilla would log a warning and show the enum name).
local function AddBiomassResearchNames(techData)

    for _, entry in ipairs(techData) do
        if kBiomassResearchTargetLevel[entry[kTechDataId]] and not entry[kTechDataResearchName] then
            entry[kTechDataResearchName] = "BIOMASS"
        end
    end

end

local oldBuildTechData = BuildTechData
if oldBuildTechData then

    function BuildTechData()

        local techData = oldBuildTechData()
        AddBiomassResearchNames(techData)
        return techData

    end

end

-- Already built by an earlier lookup: the cache holds the same entry tables.
if kTechData then
    AddBiomassResearchNames(kTechData)
end
