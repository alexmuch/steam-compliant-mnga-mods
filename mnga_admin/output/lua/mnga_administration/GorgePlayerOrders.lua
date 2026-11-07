-- Gorge uses construct for unbuilt friendly structures and heal for built ones.
if Server then
    function Gorge:OnOverrideOrder(order)
        local kind = order:GetType()
        if kind ~= kTechId.Default and kind ~= kTechId.Construct and kind ~= kTechId.Heal then return end
        local target = Shared.GetEntity(order:GetParam())
        if GetOrderTargetIsConstructTarget(order, self:GetTeamNumber()) then
            order:SetType(kTechId.Construct)
        elseif target and HasMixin(target, "Construct") and target:GetIsBuilt()
            and target:GetTeamNumber() == self:GetTeamNumber() then
            order:SetType(kTechId.Heal)
        elseif GetOrderTargetIsHealTarget(order, self:GetTeamNumber())
            or ((kind == kTechId.Construct or kind == kTechId.Heal) and target
                and HasMixin(target, "Live") and target:GetTeamNumber() == self:GetTeamNumber()) then
            order:SetType(kTechId.Heal)
        else
            Alien.OnOverrideOrder(self, order)
        end
    end
end
