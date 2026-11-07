-- Keep the research-in-progress list visible while dead / waiting to respawn.
-- See GUIMNGADeadResearch.lua and .claude/docs/dead-research-list.md.
AddClientUIScriptForClass("MarineSpectator", "mnga_administration/GUIMNGADeadResearch")
AddClientUIScriptForClass("AlienSpectator", "mnga_administration/GUIMNGADeadResearch")

local kHandoffWindow = 1.0
local kListScripts =
{
    "mnga_administration/GUIMNGADeadResearch",
    "Hud/Marine/GUIMarineHUD",
    "GUIAlienHUD",
}

local function GetListScriptsSignature()
    local signature = 0
    for i = 1, #kListScripts do
        if ClientUI.GetScript(kListScripts[i]) then
            signature = signature + 2 ^ (i - 1)
        end
    end
    return signature
end

local oldEvaluateUIVisibility = ClientUI.EvaluateUIVisibility
function ClientUI.EvaluateUIVisibility(forPlayer)

    local before = GetListScriptsSignature()
    local wasDead = ClientUI.GetScript(kListScripts[1]) ~= nil

    -- Respawn: the new player's GUINotificationMixin ignores its queue for 2 s
    -- (vanilla F4-rejoin workaround). Coming straight from the dead list the
    -- tech tree is already valid, so skip that delay.
    if wasDead and forPlayer and HasMixin(forPlayer, "GUINotification") then
        forPlayer.timeInitialized = Shared.GetTime() - GUINotificationMixin.kDelayTime - 0.01
    end

    oldEvaluateUIVisibility(forPlayer)

    local after = GetListScriptsSignature()
    if before ~= 0 and after ~= 0 and before ~= after then
        gMNGAResearchHandoffUntil = Shared.GetTime() + kHandoffWindow
    end

end
