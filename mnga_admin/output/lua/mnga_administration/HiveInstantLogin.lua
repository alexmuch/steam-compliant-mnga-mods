-- Vanilla CommandStructure:OnUse requires self.loginAllowed, which is only set by
-- the model's "opened" animation tag. A freshly built hive shows the enter prompt
-- (GetIsBuilt) several seconds before that tag fires, so use silently fails.
-- Aliens log in to hives instantly anyway, so open the gate once the hive is built.

function Hive:OnUse(player, elapsedTime, useSuccessTable)

    if self:GetIsBuilt() and not self.occupied then
        self.loginAllowed = true
    end

    CommandStructure.OnUse(self, player, elapsedTime, useSuccessTable)

end
