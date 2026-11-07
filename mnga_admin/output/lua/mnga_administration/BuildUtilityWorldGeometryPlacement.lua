-- Apply Infantry Portal-style placement clearance to Arms Labs and Observatories.
--
-- Infantry Portal placement has two relevant checks: a marine-sized clearance
-- box at the structure origin and a special no_ip surface test. Reuse both
-- without copying its Command Station proximity, attachment, or count rules.

local kCheckedTechIds = {
    [kTechId.ArmsLab] = true,
    [kTechId.Observatory] = true,
}

-- Slightly wider than the Infantry Portal's Player.kXZExtents (0.35) so these
-- structures cannot be tucked as deeply into nearby world geometry.
local kWorldGeometryClearanceXZExtents = 0.5

local originalGetIsBuildLegal = GetIsBuildLegal

local function GetMarineBuildTechNode(techId, player)
    if not kCheckedTechIds[techId]
            or not player
            or not player.GetTeamNumber
            or player:GetTeamNumber() ~= kMarineTeamType then
        return nil
    end

    local techTree
    if Client then
        techTree = GetTechTree()
    elseif player.GetTechTree then
        techTree = player:GetTechTree()
    end

    local techNode = techTree and techTree:GetTechNode(techId) or nil
    return techNode and techNode:GetIsBuild() and techNode or nil
end

-- This is the non-proximity part of InfantryPortal.GetCommandStationIsBuilt.
local function GetHasInfantryPortalPlacementRoom(position)
    local extents = Vector(
        kWorldGeometryClearanceXZExtents,
        Player.kYExtents,
        kWorldGeometryClearanceXZExtents
    )
    local center = position + Vector(0, 0.1 + Player.kYExtents, 0)

    return GetHasRoomForCapsule(
        extents,
        center,
        CollisionRep.Default,
        PhysicsMask.AllButPCsAndRagdolls
    )
end

-- Exact equivalent of BuildUtility.CheckValidIPPlacement.
local function GetHasInfantryPortalPlacementSurface(position, extents)
    local groundTrace = Shared.TraceBox(
        extents,
        position - Vector(0, 0.3, 0),
        position - Vector(0, 3, 0),
        CollisionRep.Default,
        PhysicsMask.AllButPCs,
        EntityFilterAll()
    )

    if groundTrace.fraction == 1 then
        local traceStart = position + Vector(0, 0.3, 0)
        local surfaceTrace = Shared.TraceRay(
            traceStart,
            traceStart - Vector(0, 0.4, 0),
            CollisionRep.Default,
            PhysicsMask.AllButPCs,
            EntityFilterAll()
        )

        return surfaceTrace.surface ~= "no_ip"
    end

    return true
end

function GetIsBuildLegal(techId, position, angle, snapRadius, player, ignoreEntity, ignoreChecks)
    local legalBuild, legalPosition, attachEntity, errorString = originalGetIsBuildLegal(
        techId,
        position,
        angle,
        snapRadius,
        player,
        ignoreEntity,
        ignoreChecks
    )

    if not legalBuild or not GetMarineBuildTechNode(techId, player) then
        return legalBuild, legalPosition, attachEntity, errorString
    end

    if not GetHasInfantryPortalPlacementRoom(legalPosition) then
        return false, legalPosition, attachEntity, "COMMANDERERROR_INVALID_PLACEMENT"
    end

    if not GetHasInfantryPortalPlacementSurface(legalPosition, GetExtents(techId)) then
        return false, legalPosition, attachEntity, "COMMANDERERROR_INVALID_PLACEMENT"
    end

    return legalBuild, legalPosition, attachEntity, errorString
end
