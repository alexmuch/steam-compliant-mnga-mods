-- Commander cooldowns live in separate file-local tables in the server VM and
-- each client VM. A newly-created Commander therefore needs the server's live
-- entries replayed after player replacement has completed. Use vanilla's
-- AbilityResult path so its button dial and every other client consumer agree.
local OriginalOnProcessMove = Commander.OnProcessMove

function Commander:OnProcessMove(input)
    OriginalOnProcessMove(self, input)

    if not Server or self.mngaCooldownHandoffComplete then
        return
    end

    self.mngaCooldownHandoffComplete = true

    local now = Shared.GetTime()
    local replayed = 0

    for techId = 1, kTechId.Max - 1 do
        local cooldownDuration = LookupTechData(techId, kTechDataCooldown, 0)
        if cooldownDuration > 0 then
            local cooldownFraction = self:GetCooldownFraction(techId)
            if cooldownFraction > 0 then
                local castTime = now - (1 - cooldownFraction) * cooldownDuration
                local message = BuildAbilityResultMessage(techId, true, castTime)
                Server.SendNetworkMessage(self, "AbilityResult", message, false)
                replayed = replayed + 1

                Print("[CommanderCooldownHandoff] Replayed techId=%s fraction=%.4f duration=%.2f castTime=%.3f team=%s",
                    tostring(techId), cooldownFraction, cooldownDuration, castTime, tostring(self:GetTeamNumber()))
            end
        end
    end

    Print("[CommanderCooldownHandoff] Initial cooldown replay complete commanderId=%s team=%s replayed=%s",
        tostring(self:GetId()), tostring(self:GetTeamNumber()), tostring(replayed))
end
