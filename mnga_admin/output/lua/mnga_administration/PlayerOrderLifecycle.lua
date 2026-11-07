if Server then
    local oldOnEntityChange = NS2Gamerules.OnEntityChange
    function NS2Gamerules:OnEntityChange(oldId, newId)
        if MNGAPlayerOrderPacing then
            MNGAPlayerOrderPacing.OnEntityChange(oldId, newId)
        end
        return oldOnEntityChange(self, oldId, newId)
    end

    local oldResetGame = NS2Gamerules.ResetGame
    function NS2Gamerules:ResetGame(...)
        if MNGAPlayerOrderPacing then MNGAPlayerOrderPacing.Reset() end
        return oldResetGame(self, ...)
    end

    local oldOnDestroy = NS2Gamerules.OnDestroy
    function NS2Gamerules:OnDestroy(...)
        if MNGAPlayerOrderPacing then MNGAPlayerOrderPacing.Reset() end
        return oldOnDestroy(self, ...)
    end
end
