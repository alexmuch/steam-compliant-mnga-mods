-- Fixed skulk auto-upgrades. Post-hook on lua/Egg.lua.
-- Vanilla Egg:PickUpgrades gives a respawning alien one random upgrade per
-- chamber (Shell/Spur/Veil) it has no remembered pick for. Narrow each
-- chamber's auto-pick list to a single fixed upgrade so table.random always
-- returns it. Remembered picks (lastUpgradeList) still take priority.
-- A fixed pick is only used when the chamber offers it (kUpgrades[upgrade]
-- maps back to the chamber). CBM FINAL VERSION has no Carapace: forcing it
-- put Carapace in lastUpgradeList and the next PickUpgrades threw
-- "table index is nil" at picked[kUpgrades[techId]].

local kFixedUpgrades =
{
    [kTechId.Shell] = kTechId.Carapace,
    [kTechId.Spur] = kTechId.Celerity,
    [kTechId.Veil] = kTechId.Aura,
}

local oldBuildUpgradeStructureTable = Egg.BuildUpgradeStructureTable
function Egg.BuildUpgradeStructureTable()
    oldBuildUpgradeStructureTable()

    local kUpgrades = Egg.kUpgrades
    for structureId, upgradeId in pairs(kFixedUpgrades) do
        if kUpgrades[structureId] and kUpgrades[upgradeId] == structureId then
            kUpgrades[structureId] = { upgradeId }
        else
            Shared.Message(string.format("[eggfixed] %s not offered by %s, keeping its random pick",
                EnumToString(kTechId, upgradeId), EnumToString(kTechId, structureId)))
        end
    end
end
