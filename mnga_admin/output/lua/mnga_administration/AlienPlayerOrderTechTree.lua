-- PlayingTeam runs before AlienTeam completes/sorts its tech tree.
if Server then
    local oldInitTechTree = PlayingTeam.InitTechTree
    function PlayingTeam:InitTechTree(...)
        oldInitTechTree(self, ...)
        if self:GetTeamType() == kAlienTeamType then
            for _, techId in ipairs({ kTechId.Defend, kTechId.Heal }) do
                if not self.techTree:GetTechNode(techId) then
                    self.techTree:AddOrder(techId)
                end
            end
        end
    end
end
