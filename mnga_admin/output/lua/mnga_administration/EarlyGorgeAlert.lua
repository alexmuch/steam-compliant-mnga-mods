-- Early gorge alert: during the first minute of a round, tell the alien team
-- whenever a player starts evolving to gorge, with the team's gorge count
-- (gorges + embryos gestating into gorge). Post hook of lua/Embryo.lua:
-- betteregg replaces Alien:ProcessBuyAction outright, but every evolve path
-- (vanilla and betteregg) ends in Embryo:SetGestationData on the new embryo.
-- Also, at any time during a started round, "X has gone lerk/fade/onos"
-- (no count) for every higher-lifeform evolve.
if not Server then return end

local kEarlyGorgeAlertWindow = 60

local kLifeformAlertNames

local function CountTeamGorges(teamNumber)
    local team = GetGamerules():GetTeam(teamNumber)
    if not team then return 0 end
    local count = 0
    for _, player in ipairs(team:GetPlayers()) do
        if player:isa("Gorge") or (player:isa("Embryo") and player.gestationTypeTechId == kTechId.Gorge) then
            count = count + 1
        end
    end
    return count
end

local function GetAlienTeamClients(teamNumber)
    local team = GetGamerules():GetTeam(teamNumber)
    if not team or not Shine then return nil end
    local clients = {}
    for _, player in ipairs(team:GetPlayers()) do
        local client = player:GetClient()
        if client and not client:GetIsVirtual() then
            clients[#clients + 1] = client
        end
    end
    if #clients == 0 then return nil end
    return clients
end

local oldSetGestationData = Embryo.SetGestationData
function Embryo:SetGestationData(techIds, previousTechId, healthScalar, armorScalar)

    oldSetGestationData(self, techIds, previousTechId, healthScalar, armorScalar)

    local techId = self.gestationTypeTechId
    if previousTechId == techId then return end

    local gamerules = GetGamerules()
    if not gamerules or not gamerules:GetGameStarted() then return end

    kLifeformAlertNames = kLifeformAlertNames or {
        [kTechId.Lerk] = "lerk",
        [kTechId.Fade] = "fade",
        [kTechId.Onos] = "onos",
    }

    local teamNumber = self:GetTeamNumber()
    local lifeformName = kLifeformAlertNames[techId]
    if lifeformName then
        local clients = GetAlienTeamClients(teamNumber)
        if clients then
            MNGA_NotifyNames(clients, 255, 255, 0, "%s has gone " .. lifeformName, MNGA_Name(self))
        end
        return
    end

    if techId ~= kTechId.Gorge then return end
    if Shared.GetTime() - gamerules:GetGameStartTime() > kEarlyGorgeAlertWindow then return end

    local clients = GetAlienTeamClients(teamNumber)
    if clients then
        MNGA_NotifyNames(clients, 255, 255, 0, "%s has gone gorge (gorge count: %d)", MNGA_Name(self), CountTeamGorges(teamNumber))
    end

end
