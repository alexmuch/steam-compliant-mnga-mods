-- Prevent marine structure blueprints from overlapping PowerPoints.
--
-- PowerPoint collision does not reliably participate in vanilla's stacking
-- result. Keep vanilla validation intact, then compare the proposed structure's
-- oriented model bounds with nearby PowerPoint model bounds directly.

local kOverlapBoundsScale = 0.5
local kClientPlacementSafetyMargin = 0.075
local kMaxStructureOverlapRadius = 2

local originalGetIsBuildLegal = GetIsBuildLegal
local techBoundsCache = {}

local function GetMarineBuildTechNode(techId, player)
    if not player or not player.GetTeamNumber or player:GetTeamNumber() ~= kMarineTeamType then
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

local function GetSymmetricBounds(extents)
    return Vector(-extents.x, -extents.y, -extents.z), Vector(extents.x, extents.y, extents.z)
end

local function GetTechBounds(techId)
    local cached = techBoundsCache[techId]
    if cached then
        return cached.min, cached.max
    end

    local minBounds
    local maxBounds
    local modelName = LookupTechData(techId, kTechDataModel, nil)
    local modelIndex = modelName and Shared.GetModelIndex(modelName) or nil
    local model = modelIndex and Shared.GetModel(modelIndex) or nil

    if model then
        minBounds, maxBounds = model:GetExtents()
    end

    if not minBounds or not maxBounds then
        minBounds, maxBounds = GetSymmetricBounds(GetExtents(techId))
    end

    cached = { min = Vector(minBounds), max = Vector(maxBounds) }
    techBoundsCache[techId] = cached
    return cached.min, cached.max
end

local function GetPowerPointBounds(powerPoint)
    local minBounds, maxBounds = powerPoint:GetModelExtents()
    if not minBounds or not maxBounds then
        minBounds, maxBounds = GetSymmetricBounds(powerPoint:GetExtents())
    end

    return minBounds, maxBounds
end

local function GetHorizontalAxis(axis, fallback)
    local horizontal = Vector(axis.x, 0, axis.z)
    if horizontal:GetLengthSquared() < 0.0001 then
        return fallback
    end

    horizontal:Normalize()
    return horizontal
end

local function GetOrientedBounds(origin, xAxis, yAxis, zAxis, minBounds, maxBounds)
    local localCenter = (minBounds + maxBounds) * 0.5
    local halfSize = (maxBounds - minBounds) * 0.5 * kOverlapBoundsScale
    local center = origin + xAxis * localCenter.x + yAxis * localCenter.y + zAxis * localCenter.z

    return {
        center = center,
        xAxis = GetHorizontalAxis(xAxis, Vector(1, 0, 0)),
        zAxis = GetHorizontalAxis(zAxis, Vector(0, 0, 1)),
        halfX = halfSize.x,
        halfZ = halfSize.z,
        minY = center.y - math.abs(xAxis.y) * halfSize.x - math.abs(yAxis.y) * halfSize.y - math.abs(zAxis.y) * halfSize.z,
        maxY = center.y + math.abs(xAxis.y) * halfSize.x + math.abs(yAxis.y) * halfSize.y + math.abs(zAxis.y) * halfSize.z,
    }
end

local function GetRotationIndependentStructureBounds(origin, minBounds, maxBounds)
    local localCenter = (minBounds + maxBounds) * 0.5
    local halfSize = (maxBounds - minBounds) * 0.5 * kOverlapBoundsScale
    local centerOffsetRadius = math.sqrt(localCenter.x * localCenter.x + localCenter.z * localCenter.z)
    local modelRadius = centerOffsetRadius + math.sqrt(halfSize.x * halfSize.x + halfSize.z * halfSize.z)
    local clientSafetyMargin = Client and kClientPlacementSafetyMargin or 0

    return {
        center = origin + Vector(0, localCenter.y, 0),
        radius = math.min(modelRadius, kMaxStructureOverlapRadius) + clientSafetyMargin,
        minY = origin.y + localCenter.y - halfSize.y,
        maxY = origin.y + localCenter.y + halfSize.y,
    }
end

local function StructureCircleOverlapsPowerPointBox(structureBounds, powerBounds)
    if structureBounds.maxY < powerBounds.minY or powerBounds.maxY < structureBounds.minY then
        return false
    end

    local centerDelta = powerBounds.center - structureBounds.center
    local distanceX = math.max(math.abs(Math.DotProduct(centerDelta, powerBounds.xAxis)) - powerBounds.halfX, 0)
    local distanceZ = math.max(math.abs(Math.DotProduct(centerDelta, powerBounds.zAxis)) - powerBounds.halfZ, 0)
    return distanceX * distanceX + distanceZ * distanceZ <= structureBounds.radius * structureBounds.radius
end

local function HasPowerPointOverlap(techId, position)
    local minBounds, maxBounds = GetTechBounds(techId)
    local structureBounds = GetRotationIndependentStructureBounds(position, minBounds, maxBounds)
    local searchRadius = structureBounds.radius + 3

    for _, powerPoint in ipairs(GetEntitiesWithinRange("PowerPoint", position, searchRadius)) do
        local powerMin, powerMax = GetPowerPointBounds(powerPoint)
        local coords = powerPoint:GetCoords()
        local powerBounds = GetOrientedBounds(
            coords.origin,
            coords.xAxis,
            coords.yAxis,
            coords.zAxis,
            powerMin,
            powerMax
        )

        if StructureCircleOverlapsPowerPointBox(structureBounds, powerBounds) then
            return true
        end
    end

    return false
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

    if HasPowerPointOverlap(techId, legalPosition) then
        return false, legalPosition, attachEntity, "COMMANDERERROR_CANT_BUILD_ON_TOP"
    end

    return legalBuild, legalPosition, attachEntity, errorString
end
