-- Raise the Lua-side gamma ceiling before vanilla Render.lua defines its
-- synchronization and console-command handlers.

local kExtendedGammaMaximum = 7

Client.MaxRenderGamma = kExtendedGammaMaximum

local savedGamma = Client.GetOptionFloat(
    "graphics/display/gamma",
    Client.DefaultRenderGammaAdjustment
)

if savedGamma > kExtendedGammaMaximum then
    Client.SetOptionFloat("graphics/display/gamma", kExtendedGammaMaximum)
end
