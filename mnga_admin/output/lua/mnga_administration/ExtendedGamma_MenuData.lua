local kExtendedGammaMaximum = 7

local function FindConfigByName(config, wantedName)
    if type(config) ~= "table" then
        return nil
    end

    if config.name == wantedName then
        return config
    end

    if config.children then
        for i = 1, #config.children do
            local result = FindConfigByName(config.children[i], wantedName)
            if result then
                return result
            end
        end
    end

    return nil
end

local graphicsConfig = MenuData
    and MenuData.Config
    and MenuData.Config.OptionsMenu
    and MenuData.Config.OptionsMenu.Graphics
local gammaConfig = FindConfigByName(graphicsConfig, "gamma")

if gammaConfig and gammaConfig.params then
    gammaConfig.params.maxValue = kExtendedGammaMaximum

    gammaConfig.params.immediateUpdate = function(self)
        local value = self:GetValue()
        Client.SetRenderGammaAdjustment(value)
    end
end
