-- Completed commander-created lifeform eggs use their contained lifeform's map
-- icon. Eggs still researching deliberately remain ordinary Egg blips.

local kCompletedLifeformEggBlipTypes =
{
    [kTechId.GorgeEgg] = kMinimapBlipType.Gorge,
    [kTechId.LerkEgg] = kMinimapBlipType.Lerk,
    [kTechId.FadeEgg] = kMinimapBlipType.Fade,
    [kTechId.OnosEgg] = kMinimapBlipType.Onos,
}

function Egg:GetMapBlipType()
    return kCompletedLifeformEggBlipTypes[self:GetTechId()] or kMinimapBlipType.Egg
end

if Server then

    local oldEggOnResearchComplete = Egg.OnResearchComplete
    function Egg:OnResearchComplete(techId)
        local result = oldEggOnResearchComplete(self, techId)
        local blipType = kCompletedLifeformEggBlipTypes[self:GetTechId()]

        if blipType then
            -- TechMixin does not mark MapBlipMixin dirty when the tech id changes.
            self:MarkBlipDirty()
            Print("[LifeformEggMap] completed entity=%s tech=%s blip=%s",
                tostring(self:GetId()),
                EnumToString(kTechId, self:GetTechId()),
                EnumToString(kMinimapBlipType, blipType))
        end

        return result
    end

end
