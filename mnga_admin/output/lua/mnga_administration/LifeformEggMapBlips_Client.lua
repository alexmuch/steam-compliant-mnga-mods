-- The server uses lifeform blip types for completed eggs so aliens see their
-- contents. Conceal that distinction from marine map and minimap presentation.

if Client then

    local kLifeformBlipTypes =
    {
        [kMinimapBlipType.Gorge] = true,
        [kMinimapBlipType.Lerk] = true,
        [kMinimapBlipType.Fade] = true,
        [kMinimapBlipType.Onos] = true,
    }

    local oldMapBlipGetMapBlipType = MapBlip.GetMapBlipType
    function MapBlip:GetMapBlipType()
        local blipType = oldMapBlipGetMapBlipType(self)
        local player = Client.GetLocalPlayer()

        if player and player:GetTeamNumber() == kMarineTeamType and kLifeformBlipTypes[blipType] then
            local owner = Shared.GetEntity(self:GetOwnerEntityId())
            if owner and owner:isa("Egg") then
                return kMinimapBlipType.Egg
            elseif not owner and not self:isa("PlayerMapBlip") then
                -- Network creation order can briefly make a blip available before
                -- its owner. Do not expose a lifeform silhouette in that window.
                return kMinimapBlipType.Egg
            end
        end

        return blipType
    end

end
