Script.Load("lua/mnga_administration/Globals.lua")

local kNNSLTournamentNameMessage =
{
    tournamentName = "string(128)",
}
Shared.RegisterNetworkMessage("NNSLTournamentName", kNNSLTournamentNameMessage)

local kNNSLTeamPlacementMessage =
{
    teamPlacement = "integer (1 to 3)",
    teamName = "string (128)",
    playerIds = "string (131)", -- Max 12 people on a team, csv string (12 * 10 digits + n - 1 commas)
}
Shared.RegisterNetworkMessage("NNSLTeamPlacement", kNNSLTeamPlacementMessage)

Log("[NNSLBadges] Network Messages Registered.")
