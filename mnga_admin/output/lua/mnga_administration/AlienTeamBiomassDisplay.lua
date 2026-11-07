-- Vanilla AlienTeam:UpdateBioMassLevel keeps only the greatest pending Hive
-- biomass fraction and displays it on BioMass(current + 1).  Preserve all of
-- vanilla's authoritative biomass accounting, then repair the display-only
-- TechNode progress values so concurrent Hives occupy consecutive icons.

local kBiomassDisplayTechIds =
{
    kTechId.BioMassOne,
    kTechId.BioMassTwo,
    kTechId.BioMassThree,
    kTechId.BioMassFour,
    kTechId.BioMassFive,
    kTechId.BioMassSix,
    kTechId.BioMassSeven,
    kTechId.BioMassEight,
    kTechId.BioMassNine,
    kTechId.BioMassTen,
    kTechId.BioMassEleven,
    kTechId.BioMassTwelve
}

local baseUpdateBioMassLevel = AlienTeam.UpdateBioMassLevel

local function ComparePendingBiomass(lhs, rhs)
    if lhs.progress == rhs.progress then
        return lhs.entityId < rhs.entityId
    end
    return lhs.progress > rhs.progress
end

local function SetDisplayedProgress(self, techNode, progress)
    if techNode:GetResearchProgress() ~= progress then
        techNode:SetResearchProgress(progress)
        self.techTree:SetTechNodeChanged(
            techNode,
            string.format("researchProgress = %.2f", progress))
    end
end

function AlienTeam:UpdateBioMassLevel()
    baseUpdateBioMassLevel(self)

    if not self.techTree then
        return
    end

    local pendingBiomass = {}
    local hives = GetEntitiesForTeam("Hive", self:GetTeamNumber())

    for _, hive in ipairs(hives) do
        if hive:GetIsAlive() then
            local progress = hive.biomassResearchFraction or 0

            -- Vanilla also previews the base biomass supplied by a Hive that is
            -- still constructing. Keep that behaviour, including when regular
            -- biomass research is happening concurrently on other Hives.
            if not hive:GetIsBuilt() then
                progress = progress + hive:GetBuiltFraction()
            end

            if progress > 0 then
                pendingBiomass[#pendingBiomass + 1] =
                {
                    progress = progress,
                    entityId = hive:GetId()
                }
            end
        end
    end

    table.sort(pendingBiomass, ComparePendingBiomass)

    local firstPendingLevel = self.bioMassLevel + 1
    for level = firstPendingLevel, #kBiomassDisplayTechIds do
        local pendingIndex = level - self.bioMassLevel
        local pending = pendingBiomass[pendingIndex]
        local progress = pending and pending.progress or 0
        local techNode = self.techTree:GetTechNode(kBiomassDisplayTechIds[level])

        if techNode then
            SetDisplayedProgress(self, techNode, progress)
        end
    end
end
