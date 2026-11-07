-- Vanilla expires Defend after ten quiet seconds even before the bot arrives.
-- Keep the approach alive; once in range, retain vanilla quiet-time completion.
if Server then
    local function UpdateDefendApproach(player)
        if not player:isa("Alien") or not player:GetIsAlive() then return end
        local client = player:GetClient()
        if not client or not client:GetIsVirtual() then return end
        local order = player:GetCurrentOrder()
        if not order or order:GetType() ~= kTechId.Defend then return end
        local target = Shared.GetEntity(order:GetParam())
        if target and HasMixin(target, "Live") and target:GetIsAlive()
            and target:GetTeamNumber() == player:GetTeamNumber() then
            order:SetLocation(target:GetOrigin())
            if (player:GetOrigin() - target:GetOrigin()):GetLengthSquared() >= 25 then
                order.orderTime = Shared.GetTime()
            end
        end
    end

    local oldOnUpdate = OrdersMixin.OnUpdate
    function OrdersMixin:OnUpdate(deltaTime)
        UpdateDefendApproach(self)
        return oldOnUpdate(self, deltaTime)
    end

    local oldOnProcessMove = OrdersMixin.OnProcessMove
    function OrdersMixin:OnProcessMove(input)
        UpdateDefendApproach(self)
        return oldOnProcessMove(self, input)
    end
end
