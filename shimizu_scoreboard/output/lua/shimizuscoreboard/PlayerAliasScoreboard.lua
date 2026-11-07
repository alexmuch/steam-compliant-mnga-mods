-- Apply aliases only to the public display getter. Scoreboard records retain
-- their real names for indexing, local-player checks, and menu identification.
local oldScoreboardGetPlayerData = Scoreboard_GetPlayerData
function Scoreboard_GetPlayerData(clientIndex, dataType)
    local value = oldScoreboardGetPlayerData(clientIndex, dataType)
    if dataType == "Name" then return SSB_GetPlayerDisplayName(clientIndex, value) end
    return value
end
