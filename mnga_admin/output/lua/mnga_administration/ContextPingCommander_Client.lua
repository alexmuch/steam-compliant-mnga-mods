-- MNGA contextual ping: commander world-click pings. Post-hook on
-- lua/Commander_Client.lua.
--
-- The vanilla world ping traces with EntityFilterAll() and only sends the
-- floor position. Here we also pick the Selectable entity under the cursor
-- (same loop as Commander:GetUnitUnderCursor, but without the
-- "marinecommselect" gate) and, if it is a contextual target, send
-- MNGACommanderContextPing instead. Minimap-click pings stay location-only.
--
-- The Selectable ray does not hit player models from the commander view
-- (structures work, players never did), so eligible players are also picked
-- in screen space: the closest one whose engagement point or origin projects
-- within kPlayerPickRadius pixels of the cursor. A player under the cursor
-- wins over a structure behind it.

if Client and not Predict then

    Script.Load("lua/mnga_administration/ContextPingShared.lua")

    local function GetSelectableUnderCursor(player, pickVec)

        local origin = player:GetOrigin()
        for _ = 1, 25 do
            local trace = Shared.TraceRay(origin, origin + pickVec * 1000, CollisionRep.Select, PhysicsMask.CommanderSelect, EntityFilterAllButMixin("Selectable"))
            if trace.fraction == 1 then
                return nil
            elseif trace.entity then
                return trace.entity
            end
            origin = trace.endPoint + pickVec * 0.1
        end
        return nil

    end

    local kPlayerPickRadius = 40    -- GUIScale'd pixels around the cursor

    local function GetScreenDistanceSq(x, y, point, camOrigin, camForward)
        if (point - camOrigin):DotProduct(camForward) <= 0 then
            return nil
        end
        local screen = Client.WorldToScreen(point)
        local dx, dy = screen.x - x, screen.y - y
        return dx * dx + dy * dy
    end

    local function GetPlayerNearCursor(player, x, y)

        local viewCoords = player:GetCameraViewCoords()
        local camOrigin, camForward = viewCoords.origin, viewCoords.zAxis
        local radius = GUIScale(kPlayerPickRadius)
        local best, bestDistSq = nil, radius * radius
        local playerTeam = player:GetTeamNumber()

        for _, target in ientitylist(Shared.GetEntitiesWithClassname("Player")) do

            local kind = MNGA_ContextPing_GetKind(player, target)
            -- the server only accepts sighted enemies from commanders
            if MNGA_ContextPing_IsMarkKind(kind) and (target:GetTeamNumber() == playerTeam
                    or not HasMixin(target, "LOS") or target:GetIsSighted()) then

                local engagement = target.GetEngagementPoint and target:GetEngagementPoint() or target:GetOrigin()
                local d1 = GetScreenDistanceSq(x, y, engagement, camOrigin, camForward)
                local d2 = GetScreenDistanceSq(x, y, target:GetOrigin(), camOrigin, camForward)
                local distSq = d1 and d2 and math.min(d1, d2) or d1 or d2
                if distSq and distSq <= bestDistSq then
                    best, bestDistSq = target, distSq
                end

            end

        end

        return best

    end

    local oldTriggerPingInWorld = CommanderUI_TriggerPingInWorld
    function CommanderUI_TriggerPingInWorld(x, y)

        local player = Client.GetLocalPlayer()
        if not kMNGAContextPingEnabled or not player then
            return oldTriggerPingInWorld(x, y)
        end

        local pickVec = Client.CreatePickingRayXY(x, y)

        -- floor position, exactly as vanilla
        local trace = Shared.TraceRay(player:GetOrigin(), player:GetOrigin() + pickVec * 1000, CollisionRep.Select, PhysicsMask.CommanderSelect, EntityFilterAll())
        if trace.fraction == 1 then
            return
        end

        local rayTarget = GetSelectableUnderCursor(player, pickVec)
        local target = rayTarget
        if not (target and target:isa("Player")) then
            target = GetPlayerNearCursor(player, x, y) or rayTarget
        end
        local kind = target and MNGA_ContextPing_GetKind(player, target)

        if MNGA_ContextPing_IsMarkKind(kind) then
            Client.SendNetworkMessage("MNGACommanderContextPing", { position = trace.endPoint, targetId = target:GetId() }, true)
        else
            Client.SendNetworkMessage("CommanderPing", BuildCommanderPingMessage(trace.endPoint), true)
        end

    end

end
