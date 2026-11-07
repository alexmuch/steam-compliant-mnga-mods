local function AliasedRecordsDuring(callback, ...)
    local oldGetAllScores = ScoreboardUI_GetAllScores
    ScoreboardUI_GetAllScores = function() return SSB_GetAliasedScoreRecords(oldGetAllScores()) end
    local args = { ... }
    local results = { xpcall(function() return callback(unpack(args)) end, debug.traceback) }
    ScoreboardUI_GetAllScores = oldGetAllScores
    if not results[1] then error(results[2]) end
    return unpack(results, 2)
end

if GUIVoiceChat and GUIVoiceChat.Update and not SSBPlayerAliasVoiceWrapped then
    SSBPlayerAliasVoiceWrapped = true
    local oldUpdate = GUIVoiceChat.Update
    function GUIVoiceChat:Update(deltaTime)
        return AliasedRecordsDuring(oldUpdate, self, deltaTime)
    end
end

if GUIInsight_PlayerFrames and GUIInsight_PlayerFrames.UpdatePlayer and not SSBPlayerAliasInsightWrapped then
    SSBPlayerAliasInsightWrapped = true
    local oldUpdatePlayer = GUIInsight_PlayerFrames.UpdatePlayer
    function GUIInsight_PlayerFrames:UpdatePlayer(player, record, team, yPosition, isMouseOver)
        local records = SSB_GetAliasedScoreRecords({ record })
        return oldUpdatePlayer(self, player, records[1], team, yPosition, isMouseOver)
    end
end

if GUIMinimap and GUIMinimap.DrawMinimapName and not SSBPlayerAliasMinimapWrapped then
    SSBPlayerAliasMinimapWrapped = true
    local oldDrawMinimapName = GUIMinimap.DrawMinimapName
    function GUIMinimap:DrawMinimapName(item, blipTeam, clientIndex, isParasited)
        local oldGetRecord = Scoreboard_GetPlayerRecord
        Scoreboard_GetPlayerRecord = function(index)
            local record = oldGetRecord(index)
            if index ~= clientIndex or not record then return record end
            return SSB_GetAliasedScoreRecords({ record })[1]
        end
        local results = { xpcall(function()
            return oldDrawMinimapName(self, item, blipTeam, clientIndex, isParasited)
        end, debug.traceback) }
        Scoreboard_GetPlayerRecord = oldGetRecord
        if not results[1] then error(results[2]) end
        return unpack(results, 2)
    end
end
