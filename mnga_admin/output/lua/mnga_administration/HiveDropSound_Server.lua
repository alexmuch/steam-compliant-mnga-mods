-- Team-wide hive drop sound (.claude/docs/hive-drop-sound.md): vanilla plays
-- hive_spawn only as a positional world sound. When the commander drops a hive,
-- tell every alien beyond NearRange to play a quieter copy client-side
-- (Server.PlayPrivateSound ignores volume). Runs only on commander drops, never
-- for map-start hives.

if not Server or MNGAHiveDropSoundInstalled then return end
MNGAHiveDropSoundInstalled = true

local oldCreateEntityForCommander = CreateEntityForCommander
function CreateEntityForCommander(techId, position, commander)

    local newEnt = oldCreateEntityForCommander(techId, position, commander)

    if techId == kTechId.Hive and newEnt and newEnt:isa("Hive") then
        local team = newEnt:GetTeam()
        if team and team.ForEachPlayer then
            local origin = newEnt:GetOrigin()
            local nearSq = MNGA_HIVE_DROP_SOUND.NearRange * MNGA_HIVE_DROP_SOUND.NearRange
            local message = { hiveId = newEnt:GetId() }
            team:ForEachPlayer(function(player)
                if player:GetIsVirtual() then return end
                if player:GetOrigin():GetDistanceSquared(origin) > nearSq then
                    Server.SendNetworkMessage(player, "MNGAHiveDropSound", message, true)
                end
            end)
        end
    end

    return newEnt

end
