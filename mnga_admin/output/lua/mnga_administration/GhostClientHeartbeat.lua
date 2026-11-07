-- Ghost client heartbeat (.claude/docs/ghost-connector.md).
-- A client the engine keeps across a map change but which never re-registers
-- with Lua still holds an engine player slot while having no Lua Client (no
-- kick, no queue handling). Every 30 s print the engine and Lua slot counts plus
-- every Lua-visible human IP; ns2py/ns2dropghost tails this line from the host.
-- Server.GetNumClientsTotal counts humans only (vanilla
-- NS2Gamerules:GetNumPlayersConnecting subtracts no bots from it), so
-- (engine_total - engine_spec) - (lua_humans - lua_spec) = hidden player slots.
-- Read-only.
if not Server then return end

local kInterval = 30
local kTimerName = "MNGAGhostClientHeartbeat"

local function SafeServerNumber(name)
    local callback = Server[name]
    if type(callback) ~= "function" then return -1 end
    local ok, value = pcall(callback)
    if not ok then return -1 end
    return tonumber(value) or -1
end

local function Beat()
    local luaHumans, luaSpec, luaBots = 0, 0, 0
    local ips = {}
    local clients, numClients = Shine.GetAllClients()
    for i = 1, numClients or 0 do
        local client = clients[i]
        if client:GetIsVirtual() then
            luaBots = luaBots + 1
        else
            luaHumans = luaHumans + 1
            if client:GetIsSpectator() then
                luaSpec = luaSpec + 1
            end
            ips[#ips + 1] = IPAddressToString(Server.GetClientAddress(client))
        end
    end

    local engineTotal = SafeServerNumber("GetNumClientsTotal")
    local engineSpec = SafeServerNumber("GetNumSpectators")
    local hidden = (engineTotal - engineSpec) - (luaHumans - luaSpec)

    Print("%s", string.format(
        "[ghostclient] engine_total=%s engine_spec=%s max=%s lua_humans=%s lua_spec=%s lua_bots=%s hidden_player_slots=%s maptime=%s ips=%s",
        tostring(engineTotal), tostring(engineSpec), tostring(SafeServerNumber("GetMaxPlayers")),
        tostring(luaHumans), tostring(luaSpec), tostring(luaBots), tostring(hidden),
        tostring(math.floor(Shared.GetTime())), table.concat(ips, ",")))
end

-- Shine is not loaded when mod entry files run; start the timer once the map is up.
Event.Hook("MapPostLoad", function()
    if not (Shine and Shine.Timer and Shine.GetAllClients) then
        Print("[ghostclient] Shine missing, heartbeat disabled")
        return
    end
    Shine.Timer.Create(kTimerName, kInterval, -1, function()
        local ok, err = pcall(Beat)
        if not ok then
            Print("%s", "[ghostclient] heartbeat error: " .. tostring(err))
        end
    end)
    Print("%s", "[ghostclient] heartbeat started interval=" .. kInterval)
end)
