-- Vanilla GetClosestEntrancesBetweenTunnels builds sparse { ExitA, ExitB }
-- arrays and iterates them with ipairs. If ExitA has disappeared while ExitB
-- remains during tunnel collapse, ipairs visits nothing and the caller indexes
-- a nil toTunnelExit. The same dereference occurs once both destination exits
-- disappear. Handle only those transient shapes here and leave every normal
-- call on the vanilla implementation.
if Server and GetTunnelDistanceForAlien and not gMNGAAlienTunnelDistanceFixInstalled then

local OldGetTunnelDistanceForAlien = GetTunnelDistanceForAlien
local LastDiagnosticTime = -math.huge

local function GetDestinationPosition( Destination )
    if Destination:isa( "Vector" ) then
        return Destination
    elseif Destination:isa( "Entity" ) then
        return Destination:GetOrigin()
    end
end

local function GetInternalPosition( Tunnel, Exit )
    local ExitA = Tunnel:GetExitA()
    if ExitA and ExitA:GetId() == Exit:GetId() then
        return Tunnel:GetExitAPosition()
    end

    local ExitB = Tunnel:GetExitB()
    if ExitB and ExitB:GetId() == Exit:GetId() then
        return Tunnel:GetExitBPosition()
    end
end

local function TryGetSparseExitDistance( Alien, Destination )
    local AlienTunnel = Alien.currentTunnelId
        and Alien.currentTunnelId ~= Entity.invalidId
        and Shared.GetEntity( Alien.currentTunnelId ) or nil
    local DestinationPosition = GetDestinationPosition( Destination )
    local DestinationTunnel = DestinationPosition and GetTunnelForPos( DestinationPosition ) or nil

    if not AlienTunnel or not DestinationTunnel
        or AlienTunnel:GetId() == DestinationTunnel:GetId() then
        return nil
    end

    local FromA, FromB = AlienTunnel:GetExitA(), AlienTunnel:GetExitB()
    local ToA, ToB = DestinationTunnel:GetExitA(), DestinationTunnel:GetExitB()

    -- The vanilla ipairs bug only exists when slot A is empty but slot B is
    -- populated. Do not replace the ordinary path-selection behavior.
    if not ( ( not FromA and FromB ) or not ToA ) then
        return nil
    end

    local FromExits = { FromA, FromB }
    local ToExits = { ToA, ToB }
    local BestFromExit, BestFromPosition, BestToExit, BestDistance

    for FromIndex = 1, 2 do
        local FromExit = FromExits[ FromIndex ]
        if FromExit then
            local FromPosition = GetInternalPosition( AlienTunnel, FromExit )
            for ToIndex = 1, 2 do
                local ToExit = ToExits[ ToIndex ]
                if ToExit and FromPosition then
                    local Distance = GetBotWalkDistance( FromExit, ToExit )
                    if not BestDistance or Distance < BestDistance then
                        BestFromExit = FromExit
                        BestFromPosition = FromPosition
                        BestToExit = ToExit
                        BestDistance = Distance
                    end
                end
            end
        end
    end

    -- A destination tunnel may lose both entrances one update later. It is no
    -- longer enterable, so choose the current-tunnel exit with the shortest
    -- world path to the original destination instead of asking vanilla to
    -- dereference a nonexistent destination entrance.
    if not ToA and not ToB then
        for FromIndex = 1, 2 do
            local FromExit = FromExits[ FromIndex ]
            local FromPosition = FromExit and GetInternalPosition( AlienTunnel, FromExit ) or nil
            if FromPosition then
                local Distance = GetBotWalkDistance( FromExit, DestinationPosition )
                if not BestDistance or Distance < BestDistance then
                    BestFromExit = FromExit
                    BestFromPosition = FromPosition
                    BestDistance = Distance
                end
            end
        end
    end

    if not BestFromExit or ( ( ToA or ToB ) and not BestToExit ) then
        return nil
    end

    local Now = Shared.GetTime()
    if Now - LastDiagnosticTime >= 5 then
        LastDiagnosticTime = Now
        Print( "%s", string.format(
            "[mngabots] recovered sparse tunnel exits alien=%s fromA=%s fromB=%s toA=%s toB=%s",
            tostring( Alien:GetId() ), tostring( FromA ~= nil ), tostring( FromB ~= nil ),
            tostring( ToA ~= nil ), tostring( ToB ~= nil ) ) )
    end

    local TravelDistance = Alien:GetOrigin():GetDistance( BestFromPosition ) + BestDistance
    return kTunnelDistanceResult.WrongTunnel, TravelDistance, BestFromPosition, nil
end

function GetTunnelDistanceForAlien( Alien, Destination, DestinationLocationHint )
    local Result, Distance, GoalPosition, Entrance = TryGetSparseExitDistance( Alien, Destination )
    if Result then
        return Result, Distance, GoalPosition, Entrance
    end
    return OldGetTunnelDistanceForAlien( Alien, Destination, DestinationLocationHint )
end

gMNGAAlienTunnelDistanceFixInstalled = true
Print( "[mngabots] sparse alien tunnel-exit crash fix installed" )

end
