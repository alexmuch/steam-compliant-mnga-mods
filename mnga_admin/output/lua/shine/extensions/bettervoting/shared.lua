local JSON = require "shine/lib/json"

local Plugin = Shine.Plugin( ... )

Plugin.Version = "1.0.0"
Plugin.PrintName = "Better Voting"
Plugin.HasConfig = true
Plugin.ConfigName = "BetterVoting.json"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.CheckConfigRecursively = true
Plugin.DefaultState = false

Plugin.DefaultConfig = {
    Debug = true,
    SnapshotLifetime = 300,
    TestVote = {
        Enabled = true,
        Duration = 20
    },
    ShadowRealm = {
        Enabled = true,
        Duration = 20,
        YesFraction = 0.60,
        MinimumElectorate = 3,
        AttemptsPerTeam = 1
    },
    Snapshot = Shine.IgnoreWhenChecking( JSON.Object() )
}

function Plugin:SetupDataTable()
    -- Spark's reliable string-message path is proven up to 1024 bytes in the
    -- shipped mods, but oversized 4096-byte schema fields can crash the engine
    -- without a Lua error during initial sync. Split JSON into safe chunks.
    self:AddNetworkMessage( "StateChunk", {
        Channel = "integer (1 to 2)",
        TransferID = "integer (0 to 2147483647)",
        Part = "integer (1 to 32)",
        Parts = "integer (1 to 32)",
        Data = "string (900)"
    }, "Client" )
    self:AddNetworkMessage( "CastVote", {
        VoteID = "integer (0 to 2147483647)",
        Option = "integer (1 to 9)"
    }, "Server" )
    self:AddNetworkMessage( "StartShadowVote", {
        TargetID = "string (24)"
    }, "Server" )
    self:AddNetworkMessage( "RequestSync", {}, "Server" )
end

return Plugin
