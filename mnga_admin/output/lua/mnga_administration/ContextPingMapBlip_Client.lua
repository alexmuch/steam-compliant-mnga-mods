-- MNGA contextual ping: marked targets show a bright red minimap/map blip for
-- the pinging team. Post-hook on lua/MapBlip.lua.
--
-- Enemy blips are only network-relevant while the owner is sighted
-- (MapBlip:UpdateRelevancy), so an alien-pinged marine is red on the map only
-- while aliens can see it. Colour is decided entirely client-side.

if Client and not Predict then

    -- Same red<->white pulse as the vanilla under-attack blip (MinimapMappableMixin.PulseRed).

    local oldGetMapBlipColor = MapBlip.GetMapBlipColor

    local function GetMapBlipColor(self, minimap, item)
        local color = oldGetMapBlipColor(self, minimap, item)
        if MNGA_ContextPing_IsTargetMarked and MNGA_ContextPing_IsTargetMarked(self.ownerEntityId) then
            local anim = (math.cos(Shared.GetTime() * 10) + 1) * 0.5
            -- Must be a NEW Color each call: UpdateMinimapItem only calls SetColor when
            -- the returned object differs from item.prevBlipColor (a reused, mutated
            -- table compares equal to itself, so the colour would almost never apply).
            return Color(1, anim, anim, 1)
        end
        return color
    end

    -- Static blips are only refreshed every ~0.5s, which aliases the 10 rad/s pulse
    -- (red-pink-white-red-white-pink). Vanilla avoids this by giving in-combat blips
    -- the Medium rate (0.05s); marked blips get the same.
    local oldUpdateActivity = MapBlip.UpdateMinimapActivity

    local function UpdateMinimapActivity(self, minimap, item)
        local activity = oldUpdateActivity(self, minimap, item)
        if activity and MNGA_ContextPing_IsTargetMarked and MNGA_ContextPing_IsTargetMarked(self.ownerEntityId)
                and self.combatActivity then
            return self.combatActivity
        end
        return activity
    end

    -- Derived classes copied the method when they were declared (earlier in
    -- MapBlip.lua), so replace it wherever it is still the original.
    -- (Class_ReplaceMethod is not available yet when MapBlip.lua loads.)
    for _, className in ipairs({ "MapBlip", "PlayerMapBlip", "ScanMapBlip" }) do
        local cls = _G[className]
        if cls and cls.GetMapBlipColor == oldGetMapBlipColor then
            cls.GetMapBlipColor = GetMapBlipColor
        end
        if cls and cls.UpdateMinimapActivity == oldUpdateActivity then
            cls.UpdateMinimapActivity = UpdateMinimapActivity
        end
    end

end
