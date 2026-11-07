-- =============================================================================
--
-- lua/shimizuscoreboard/Scoreboard.lua
--
-- Decorates vanilla scoreboard records through Shine's existing scoreboard
-- indexing pass. Vanilla continues to own its cache, sorting, and query APIs.
--
-- =============================================================================

local function LogCompatibilityError(message)
    if SSBScoreboardPostPatchCompatibilityErrorLogged then return end
    SSBScoreboardPostPatchCompatibilityErrorLogged = true
    Print("[SSB] COMPATIBILITY ERROR: %s; scoreboard data post patch was not installed", message)
end

if type(Scoreboard_ReloadPlayerData) ~= "function"
        or type(Scoreboard_GetPlayerRecord) ~= "function"
        or type(Scoreboard_Sort) ~= "function" then
    LogCompatibilityError("required vanilla Scoreboard globals are unavailable")
    return
end

if not Shine or not Shine.Hook or type(Shine.Hook.Add) ~= "function"
        or type(Shine.GetScoreboardEntryByClientID) ~= "function"
        or Shine.Hook.MAX_PRIORITY == nil then
    LogCompatibilityError("required Shine.Hook scoreboard pipeline is unavailable")
    return
end

local kLastMarineCommanderInfo
local kLastAlienCommanderInfo

local thunderdomeEnabled = false

local function GetPlayerSkillFields(pie, tdEnabled)
    local fieldSkill = tdEnabled and pie.playerTDSkill or pie.playerSkill
    local fieldOffset = (tdEnabled and pie.playerTDSkillOffset or pie.playerSkillOffset) or 0
    local commanderSkill = tdEnabled and pie.playerTDCommSkill or pie.playerCommSkill
    if not commanderSkill or commanderSkill < 0 then commanderSkill = fieldSkill end
    local commanderOffset = (tdEnabled and pie.playerTDCommSkillOffset or pie.playerCommSkillOffset) or 0
    return fieldSkill, fieldOffset, commanderSkill, commanderOffset
end

local function UpdateLastCommanderInfo(playerRecord)
    if not playerRecord.IsCommander then return end

    local playerEnt = Shared.GetEntity(playerRecord.EntityId)
    if not playerEnt then return end

    local commanderTeam = playerEnt:GetTeamType()
    local commanderInfo
    if commanderTeam == kMarineTeamType then
        commanderInfo = kLastMarineCommanderInfo
        if not commanderInfo then
            commanderInfo = {}
            kLastMarineCommanderInfo = commanderInfo
        end
    elseif commanderTeam == kAlienTeamType then
        commanderInfo = kLastAlienCommanderInfo
        if not commanderInfo then
            commanderInfo = {}
            kLastAlienCommanderInfo = commanderInfo
        end
    else
        return
    end

    commanderInfo.CallingCard = playerRecord.CallingCard
    commanderInfo.Name = playerRecord.Name
    commanderInfo.SteamId32 = playerRecord.SteamId
    commanderInfo.Skill = playerRecord.commSkill
    commanderInfo.AdagradSum = playerRecord.CommAdagradSum
    commanderInfo.Rookie = playerRecord.IsRookie
end

local function DecorateScoreboardEntry(playerRecord, pie)
    local tdEnabled = thunderdomeEnabled

    -- Name is the client-facing presentation field used throughout vanilla UI.
    -- Preserve the authoritative value separately for context menus and callers
    -- that still identify a record using a server-supplied name string.
    if SSB_ApplyPlayerAliasToRecord then
        SSB_ApplyPlayerAliasToRecord(playerRecord, pie.steamId, pie.playerName, "reload")
    else
        playerRecord.RealName = pie.playerName or playerRecord.Name
    end

    -- Bot commander snapshots can overlap a human commander during chair
    -- transitions. SSB intentionally presents commander continuity only for
    -- humans, so exclude Steam ID 0 at the record boundary.
    playerRecord.IsCommander = pie.isCommander and pie.steamId > 0

    -- The scoreboard's Ready Room section also contains true spectators. Queue
    -- positions only describe people still assigned to spectator, not a player
    -- who has already been promoted to Ready Room while a queued snapshot is
    -- in flight.
    local queuePosition = pie.teamNumber == kSpectatorIndex
        and MNGAReadyRoomQueuePositions and MNGAReadyRoomQueuePositions[pie.steamId]
    if queuePosition then
        playerRecord.Status = string.format("Queue: %d", queuePosition)
    end

    local baseSkill, skillOffset, baseCommSkill, commSkillOffset = GetPlayerSkillFields(pie, tdEnabled)
    playerRecord.playerSkill = baseSkill
    playerRecord.playerCommSkill = baseCommSkill
    playerRecord.marineSkill = baseSkill and baseSkill + skillOffset or -1
    playerRecord.marineCommSkill = baseCommSkill and baseCommSkill + commSkillOffset or -1
    playerRecord.alienSkill = baseSkill and baseSkill - skillOffset or -1
    playerRecord.alienCommSkill = baseCommSkill and baseCommSkill - commSkillOffset or -1

    if pie.teamNumber == kTeam1Index then
        playerRecord.Skill = playerRecord.marineSkill
        playerRecord.commSkill = playerRecord.marineCommSkill
    elseif pie.teamNumber == kTeam2Index then
        playerRecord.Skill = playerRecord.alienSkill
        playerRecord.commSkill = playerRecord.alienCommSkill
    else
        -- FIXME This is a bit wonky in TD context, as in RR would be, odd...to not use assigned team. BLEH
        playerRecord.Skill = tdEnabled and pie.playerTDSkill or pie.playerSkill
        playerRecord.commSkill = baseCommSkill
    end

    playerRecord.CommanderSkill = playerRecord.commSkill
    playerRecord.CommanderAdagradSum = tdEnabled and pie.playerTDCommAdagrad or pie.commAdagradSum
    playerRecord.CommAdagradSum = tdEnabled and pie.playerTDCommAdagrad or pie.commAdagradSum

    UpdateLastCommanderInfo(playerRecord)
end

-- For Death Messages. These deliberately override vanilla's getters so bot
-- snapshots from vanilla can never replace SSB's retained human snapshots.
function Scoreboard_GetLastMarineCommanderInfo()
    return kLastMarineCommanderInfo
end

function Scoreboard_GetLastAlienCommanderInfo()
    return kLastAlienCommanderInfo
end

-- Scoreboard_GetPlayerRecord owns vanilla's normal 0.5-second reload check.
-- Mirroring only the local human commander boolean keeps chair transitions on
-- the GUI's 0.10-second refresh cadence without increasing global reloads.
function Scoreboard_SyncLocalCommanderState()
    local player = Client.GetLocalPlayer()
    if not player then return false end

    local clientIndex = player:GetClientIndex()
    local playerRecord = Scoreboard_GetPlayerRecord(clientIndex)
    if not playerRecord or not playerRecord.SteamId or playerRecord.SteamId <= 0 then
        return false
    end

    local isCommander = player:GetIsCommander() and true or false
    if playerRecord.IsCommander == isCommander then
        return false
    end

    playerRecord.IsCommander = isCommander
    Scoreboard_Sort()
    return true
end

Shine.Hook.Add("PostScoreboardReload", "SSBScoreboardReloadBegin", function()
    thunderdomeEnabled = Shared.GetThunderdomeEnabled()
end, Shine.Hook.MAX_PRIORITY)

Shine.Hook.Add("OnScoreboardEntryReload", "SSBDecorateScoreboardEntry", DecorateScoreboardEntry,
    Shine.Hook.MAX_PRIORITY)

-- Some engine-owned incremental updates mutate the cached records without a
-- Lua setter that can be wrapped. Make the public read boundaries idempotently
-- enforce presentation names so every cache consumer sees the SteamID alias.
local OldScoreboardGetPlayerRecord = Scoreboard_GetPlayerRecord
function Scoreboard_GetPlayerRecord(clientIndex)
    local record = OldScoreboardGetPlayerRecord(clientIndex)
    if record and SSB_EnsurePlayerAliasOnRecord then
        SSB_EnsurePlayerAliasOnRecord(record, "record-read")
    end
    return record
end

local function DecorateScoreList(scores)
    if type(scores) ~= "table" or not SSB_EnsurePlayerAliasOnRecord then return scores end
    for i = 1, #scores do
        SSB_EnsurePlayerAliasOnRecord(scores[i], "list-read")
    end
    return scores
end

local function WrapScoreListGetter(name)
    local oldGetter = _G[name]
    if type(oldGetter) ~= "function" then return end
    _G[name] = function(...)
        return DecorateScoreList(oldGetter(...))
    end
end

WrapScoreListGetter("ScoreboardUI_GetAllScores")
WrapScoreListGetter("ScoreboardUI_GetBlueScores")
WrapScoreListGetter("ScoreboardUI_GetRedScores")
WrapScoreListGetter("ScoreboardUI_GetSpectatorScores")

-- Vanilla builds its name index after OnScoreboardEntryReload, so it naturally
-- indexes display names. Retain compatibility for server-authored real names.
local OldScoreboardGetPlayerRecordByName = Scoreboard_GetPlayerRecordByName
function Scoreboard_GetPlayerRecordByName(playerName)
    local record = OldScoreboardGetPlayerRecordByName(playerName)
    if record or type(playerName) ~= "string" then return record end
    local scores = ScoreboardUI_GetAllScores()
    for i = 1, #scores do
        if scores[i].RealName == playerName then return scores[i] end
    end
end
