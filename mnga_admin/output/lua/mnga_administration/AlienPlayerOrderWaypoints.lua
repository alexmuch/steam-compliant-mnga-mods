if Client then
    local function GetAlienPlayerOrder()
        local player = Client.GetLocalPlayer()
        if player and player:isa("Alien") and HasMixin(player, "Orders") then
            return player:GetCurrentOrder(), player
        end
    end

    -- The final waypoint already handles Order entities, projection, tunnels,
    -- transitions and visibility settings. Change only its alien target selector.
    local getPheromone, owner, index = debug.getupvaluex(
        PlayerUI_GetFinalWaypointInScreenspace, "GetMostRelevantPheromone")
    if type(getPheromone) == "function" and owner and index then
        debug.setupvalue(owner, index, function(origin)
            local order = GetAlienPlayerOrder()
            if order then
                return order
            end
            return getPheromone(origin)
        end)
    else
        Print("[AlienOrders] ERROR: alien waypoint selector upvalue missing")
    end

    -- The vanilla path function shares the selector upvalue, but its alien
    -- branch uses GetOrigin (the order's start), not GetLocation (its destination).
    -- Handle direct orders here; leave pheromones and all other players vanilla.
    local oldGetOrderPath = PlayerUI_GetOrderPath
    function PlayerUI_GetOrderPath()
        local order, player = GetAlienPlayerOrder()
        if not order then return oldGetOrderPath() end
        if Client.kWayPointsEnabled and (Client.kHintsEnabled
            or not PlayerUI_GetTypeAutoOrderOrPheromone(order:GetType())) then
            local points = PointArray()
            if Pathing.GetPathPoints(player:GetOrigin(), order:GetLocation(), points) then
                return points
            end
        end
        return nil
    end
end
