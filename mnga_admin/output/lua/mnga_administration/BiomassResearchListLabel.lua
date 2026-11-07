-- Post-hook on lua/Hud/GUIEvent.lua (GUINotificationItem is loaded by it).
-- Research list title for biomass shows the hive level it reaches
-- ("BIOMASS 2"); every ResearchBioMass* id shares the BIOMASS name.
-- Instancing lives in BiomassResearchInstanced.lua.
-- See .claude/docs/biomass-research-list.md.

local oldInitialize = GUINotificationItem.Initialize
function GUINotificationItem:Initialize()

    oldInitialize(self)

    local level = MNGAGetBiomassResearchTargetLevel and MNGAGetBiomassResearchTargetLevel(self.techId)
    if level and self.techTitle then
        local title = string.format("%s %d", Locale.ResolveString("BIOMASS"), level)
        self.techTitle:SetText(string.UTF8Upper(title))
    end

end
