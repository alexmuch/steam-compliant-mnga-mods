-- Hydra and Bile Bomb entities are not valid Drifter construction targets.
-- Vanilla Drifter task selection accepts any unfinished friendly entity with
-- ConstructMixin, so reject these tech IDs at the common order override used
-- by autonomous and commander-issued orders. Also chains Drifters along
-- unbuilt cysts after they finish growing one.

local oldDrifterOnOverrideOrder = Drifter.OnOverrideOrder

-- After a Drifter finishes growing a cyst, it looks this far for the next
-- unbuilt cyst so it can follow a cyst chain (31 m link range + 2 m margin).
local kDrifterCystChainRange = 33

local kInvalidDrifterGrowTechIds =
{
    [kTechId.Hydra] = true,
    [kTechId.BileBomb] = true,
}

local function GetOrderTarget(order)
    local targetId = order:GetParam()
    if targetId and targetId ~= Entity.invalidId then
        return Shared.GetEntity(targetId)
    end
end

local function IsBeingGrownByAnotherDrifter(self, target)
    if target.hasDrifterEnzyme then
        return true
    end

    for _, drifter in ipairs(GetEntitiesForTeam("Drifter", target:GetTeamNumber())) do
        if self ~= drifter then
            local order = drifter:GetCurrentOrder()
            if order and order:GetType() == kTechId.Grow and GetOrderTarget(order) == target then
                return true
            end
        end
    end

    return false
end

local function FindNextChainCyst(self)
    local origin = self:GetOrigin()
    local cysts = GetEntitiesForTeamWithinRange("Cyst", self:GetTeamNumber(), origin, kDrifterCystChainRange)

    local best, bestDistSq
    for _, cyst in ipairs(cysts) do
        if not cyst:GetIsBuilt()
                and cyst:GetIsAlive()
                and cyst:GetCanAutoBuild()
                and not IsBeingGrownByAnotherDrifter(self, cyst) then
            local distSq = (cyst:GetOrigin() - origin):GetLengthSquared()
            if not bestDistSq or distSq < bestDistSq then
                best, bestDistSq = cyst, distSq
            end
        end
    end

    return best
end

function Drifter:OnOverrideOrder(order)
    oldDrifterOnOverrideOrder(self, order)

    if order:GetType() ~= kTechId.Grow then
        return
    end

    local target = GetOrderTarget(order)
    local targetTechId = target and target.GetTechId and target:GetTechId()
    if not kInvalidDrifterGrowTechIds[targetTechId] then
        return
    end

    -- Keep the order valid while preventing an approach to the rejected target.
    -- A zero-distance Move completes normally, allowing autonomous task scans
    -- to continue instead of leaving the Drifter stuck on a permanent order.
    order:SetType(kTechId.Move)
    order.orderParam = Entity.invalidId
    order:SetLocation(self:GetOrigin())
end

if Server then
    local oldDrifterProcessGrowOrder = Drifter.ProcessGrowOrder

    -- Event-style hook: only does work on the update where a Grow order on a
    -- cyst ends because the cyst became built.
    function Drifter:ProcessGrowOrder(moveSpeed, deltaTime)
        local order = self:GetCurrentOrder()
        local target = order and GetOrderTarget(order)

        oldDrifterProcessGrowOrder(self, moveSpeed, deltaTime)

        if not target or not target:isa("Cyst") or not target:GetIsBuilt() then
            return
        end

        -- Respect any queued commander orders.
        if self:GetHasOrder() or not GetIsUnitActive(self) then
            return
        end

        local nextCyst = FindNextChainCyst(self)
        if nextCyst then
            self:GiveOrder(kTechId.Grow, nextCyst:GetId(), nextCyst:GetOrigin(), nil, false, false)
        end
    end
end
