-- Ordinary alien players use the same networked order state as marines.
Shared.LinkClassToMap("Alien", nil, OrdersMixin.networkVars)

local oldOnInitialized = Alien.OnInitialized
function Alien:OnInitialized()
    oldOnInitialized(self)
    if not HasMixin(self, "Orders") then
        InitMixin(self, OrdersMixin, { kMoveOrderCompleteDistance = kPlayerMoveOrderCompleteDistance })
    end
end

local alienPlayerButtons = {
    kTechId.Attack, kTechId.Move, kTechId.Defend, kTechId.Construct, kTechId.Heal
}
function Alien:GetTechButtons(techId)
    if techId == kTechId.RootMenu and not self.isHallucination then
        return alienPlayerButtons
    end
end

function Alien:OnOverrideOrder(order)
    -- Mixed lifeforms share one command palette. Gorges perform support work;
    -- other aliens defend the friendly target instead of receiving impossible work.
    if order:GetType() == kTechId.Construct or order:GetType() == kTechId.Heal then
        order:SetType(kTechId.Defend)
        return
    end
    if order:GetType() ~= kTechId.Default then return end
    local target = Shared.GetEntity(order:GetParam())
    if GetOrderTargetIsConstructTarget(order, self:GetTeamNumber())
        or GetOrderTargetIsDefendTarget(order, self:GetTeamNumber()) then
        order:SetType(kTechId.Defend)
    elseif target and GetAreEnemies(target, self) and HasMixin(target, "Live")
        and target:GetIsAlive() and (not HasMixin(target, "LOS") or target:GetIsSighted()) then
        order:SetType(kTechId.Attack)
    else
        order:SetType(kTechId.Move)
    end
end
