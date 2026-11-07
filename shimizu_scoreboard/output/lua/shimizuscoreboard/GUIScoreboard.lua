-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\GUIScoreboard.lua
--
-- Created by: Brian Cronin (brianc@unknownworlds.com)
--
-- Manages the player scoreboard (scores, pings, etc).
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================
if not GUIScoreboard then
    if not SSBGUIScoreboardPostPatchCompatibilityErrorLogged then
        SSBGUIScoreboardPostPatchCompatibilityErrorLogged = true
        Print("[SSB] COMPATIBILITY ERROR: vanilla GUIScoreboard class is unavailable; GUI post patch was not installed")
    end
    return
end

local scoreboardIntegrations = {}

function SSB_RegisterScoreboardIntegration(name, integration)
    if type(name) ~= "string" or type(integration) ~= "table" then return false end
    scoreboardIntegrations[name] = integration
    Print("[SSB] Registered optional scoreboard integration: %s", name)
    return true
end

function SSB_UnregisterScoreboardIntegration(name)
    scoreboardIntegrations[name] = nil
end

local function NotifyScoreboardIntegrations(method, scoreboard, value)
    for name, integration in pairs(scoreboardIntegrations) do
        local callback = integration[method]
        if callback then
            local ok, err = xpcall(function() callback(scoreboard, value) end, debug.traceback)
            if not ok then Print("[SSB] Integration %s %s failed: %s", name, method, ToString(err)) end
        end
    end
end

-- Horizontal size for the game time background is irrelevant as it will be expanded to SB width
GUIScoreboard.kGameTimeBackgroundSize = Vector(640, GUIScale(32), 0)
GUIScoreboard.kClickForMouseBackgroundSize = Vector(GUIScale(200), GUIScale(32), 0)
GUIScoreboard.kClickForMouseText = Locale.ResolveString("SB_CLICK_FOR_MOUSE")

GUIScoreboard.kFavoriteIconSize = Vector(26, 26, 0)
GUIScoreboard.kFavoriteTexture = PrecacheAsset("ui/menu/favorite.dds")
GUIScoreboard.kNotFavoriteTexture = PrecacheAsset("ui/menu/nonfavorite.dds")

GUIScoreboard.kBlockedIconSize = Vector(26, 26, 0)
GUIScoreboard.kBlockedTexture = PrecacheAsset("ui/menu/blocked.dds")
GUIScoreboard.kNotBlockedTexture = PrecacheAsset("ui/menu/notblocked.dds")

GUIScoreboard.kSlidebarSize = Vector(7.5, 25, 0)
GUIScoreboard.kBgColor = Color(0, 0, 0, 0.5)
GUIScoreboard.kBgMaxYSpace = Client.GetScreenHeight() - ((GUIScoreboard.kClickForMouseBackgroundSize.y + 5) + (GUIScoreboard.kGameTimeBackgroundSize.y + 6) + 20)

local kIconSize = Vector(40, 40, 0)
local kIconOffset = Vector(-15, -10, 0)

-- Shared constants.
GUIScoreboard.kTeamInfoFontName = Fonts.kArial_15
GUIScoreboard.kTeamSmallFont = ReadOnly {
    family = "Arial",
    size = 10
}
GUIScoreboard.kTeamSmallBoldFont = ReadOnly {
    family = "Arial",
    size = 11
}
GUIScoreboard.kTeamLargeFont = ReadOnly {
    family = "Arial",
    size = 12
}
GUIScoreboard.kTeamLargeBoldFont = ReadOnly {
    family = "Arial",
    size = 13
}
GUIScoreboard.kPlayerStatsFontName = Fonts.kArial_15
GUIScoreboard.kPlayerStatsFontNameBold = Fonts.kInsight
-- GUIScoreboard.kPlayerStatsFontName = Fonts.kInsight
GUIScoreboard.kTeamNameFontName = Fonts.kArial_17
-- GUIScoreboard.kTeamNameFontName = Fonts.kInsight
GUIScoreboard.kGameTimeFontName = Fonts.kArial_17
GUIScoreboard.kTeamNameFontName = Fonts.kArial_17
GUIScoreboard.kTeamNameFontName = Fonts.kInsight
GUIScoreboard.kClickForMouseFontName = Fonts.kArial_17
-- GUIScoreboard.kClickForMouseFontName = Fonts.kInsight

GUIScoreboard.kLowPingThreshold = 100
GUIScoreboard.kLowPingColor = Color(0, 1, 0, 1)
GUIScoreboard.kMedPingThreshold = 249
GUIScoreboard.kMedPingColor = Color(1, 1, 0, 1)
GUIScoreboard.kHighPingThreshold = 499
GUIScoreboard.kHighPingColor = Color(1, 0.5, 0, 1)
GUIScoreboard.kInsanePingColor = Color(1, 0, 0, 1)
GUIScoreboard.kVoiceMuteColor = Color(1, 1, 1, 1)
GUIScoreboard.kVoiceDefaultColor = Color(1, 1, 1, 0.5)
GUIScoreboard.kHighPresThreshold = 55
GUIScoreboard.kHighPresColor = Color(1, 1, 0, 1)
GUIScoreboard.kVeryHighPresThreshold = 75
GUIScoreboard.kVeryHighPresColor = Color(1, 0.5, 0, 1)
GUIScoreboard.kMaxPresThreshold = 100
GUIScoreboard.kMaxPresColor = Color(1, 0, 0, 1)

-- Team constants.
GUIScoreboard.kTeamBackgroundYOffset = 50
GUIScoreboard.kTeamNameFontSize = 26
GUIScoreboard.kTeamInfoFontSize = 16
GUIScoreboard.kTeamItemWidth = 600
GUIScoreboard.kTeamItemHeight = GUIScoreboard.kTeamNameFontSize + GUIScoreboard.kTeamInfoFontSize + 8
GUIScoreboard.kTeamSpacing = 32
GUIScoreboard.kTeamScoreColumnStartX = 200
GUIScoreboard.kTeamColumnSpacingX = ConditionalValue(Client.GetScreenWidth() < 1280, 30, 40)

-- Player constants.
GUIScoreboard.kPlayerStatsFontSize = 16
GUIScoreboard.kPlayerItemWidthBuffer = 10
GUIScoreboard.kPlayerItemWidth = 275
GUIScoreboard.kPlayerItemHeight = 32
GUIScoreboard.kPlayerSpacing = 4

local kPlayerItemLeftMargin = 10
local kPlayerNumberWidth = 20
local kPlayerVoiceChatIconSize = 20
local kPlayerBadgeIconSize = 20
local kPlayerBadgeRightPadding = 4

local kPlayerSkillIconSize = Vector(62, 20, 0)
local kPlayerSkillIconTexture = PrecacheAsset("ui/ShimizuScoreboard/skill_tier_icons.dds")
local kPlayerCommanderSkillIconTexture = PrecacheAsset("ui/ShimizuScoreboard/comm_skill_tier_icons.dds")
local kPlayerSkillIconSizeOverride = Vector(58, 20, 0) -- slightly smaller so it doesn't overlap.
local kLifeformIconSize = 20
local kLifeformAtlas1 = PrecacheAsset("ui/ShimizuScoreboard/shimizu_lifeform_selector1.dds")
local kLifeformAtlas2 = PrecacheAsset("ui/ShimizuScoreboard/shimizu_lifeform_selector2.dds")
local kLifeformNames = { "Gorge", "Lerk", "Fade", "Onos" }
local kLifeformAtlasIndex = { Gorge = 0, Lerk = 1, Fade = 2, Onos = 3 }

local kPlayerCommIconSize = Vector(15, 15, 0)
local kPlayerCommIconTexture = PrecacheAsset("ui/badges/commander.dds")
local kPlayerCommIconsTexture = PrecacheAsset("ui/ShimizuScoreboard/ComSkillBadges.dds")
local lastComm = {}
local lastCommLastSeen = {}
local commanderVisibilityState = {}
local isPreGame = false
local commanderTrackingActive = true
local lastCommanderGameState
local localPlayerIsSpectator = false
local localPlayerSteamID = 0

-- Bots all have Steam ID 0, so use their client index to give commander
-- tracking a stable, truthy identity that cannot collide with another bot.
local function GetCommanderIdentity(steamId, clientIndex)
    if steamId and steamId > 0 then
        return steamId
    elseif clientIndex ~= nil then
        return string.format("bot:%s", ToString(clientIndex))
    end
    return nil
end

local function GetIsTerminalGameState(gameState)
    return gameState == kGameState.Team1Won or
        gameState == kGameState.Team2Won or
        gameState == kGameState.Draw
end

local function UpdateCommanderRoundState(gameState)
    commanderTrackingActive = not GetIsTerminalGameState(gameState)
    if commanderTrackingActive or gameState == lastCommanderGameState then
        lastCommanderGameState = gameState
        return
    end

    lastComm[kMarineTeamType] = nil
    lastComm[kAlienTeamType] = nil
    lastCommLastSeen[kMarineTeamType] = nil
    lastCommLastSeen[kAlienTeamType] = nil
    lastCommanderGameState = gameState
end
local kBuildmenuTexture = PrecacheAsset("ui/buildmenu.dds")
local kHudElementsTexture = PrecacheAsset("ui/hud_elements.dds")
local kSteamfriendTexture = PrecacheAsset("ui/steamfriend.dds")
local kLowVoiceTexture = PrecacheAsset("ui/ShimizuScoreboard/voice0.dds")
local kLowVoiceTooltip = "Low voice volume"
-- Pregame ready-check flag from the MNGA mngareadycheck extension
-- (.claude/docs/ready-check.md). Only shown while the game has not started.
local kReadyTexture = PrecacheAsset("ui/ShimizuScoreboard/gameready.dds")
local kReadyTooltip = "Ready"
local kAlienUpgradesTexture = PrecacheAsset("ui/ShimizuScoreboard/AlienUpgrades.dds")
local kMarineEquipTexture = PrecacheAsset("ui/ShimizuScoreboard/MarineEquip.dds")
local function RGBAtoColor(r, g, b, a)
    return Color(r / 255, g / 255, b / 255, a)
end

local playerStatsTable = {}
local kStatsRetryInterval = 15
local globalFetchTime = -kStatsRetryInterval
local statsRequestGeneration = 0
local statsRosterSignature = ""
local fetchUrl = "https://ns2stats.ns2manga.com/api/players/stats?player_ids=%s"
local playerHwid = nil

local function NormalizeSelectorLifeform(value)
    value = type(value) == "string" and string.lower(value) or nil
    if value == "gorge" then return "Gorge" end
    if value == "lerk" then return "Lerk" end
    if value == "fade" then return "Fade" end
    if value == "onos" then return "Onos" end
    return nil
end

local function GetLifeformViewerEligible()
    local player = Client.GetLocalPlayer()
    local teamNumber = player and player:GetTeamNumber()
    return teamNumber == kTeam2Index or teamNumber == kSpectatorIndex
end

local lastScoreboardVisState = false

local kSteamProfileURL = "http://steamcommunity.com/profiles/"
local kNS2StatsProfileURL = "https://ns2stats.ns2manga.com/player/%s"
local kSpectatorScoreboardFilterMinHumans = 26
local lastSpectatorFilterActive
local lastSpectatorRowsHidden
local kMinTruncatedNameLength = 8
local kGUIdata = {}

local guiThrottleInterval = 0.6
local guiThrottleTime = {}
local kVisibleUpdateInterval = 0.10
local kMouseUpdateInterval = 0.01
local kHiddenUpdateInterval = 0.20
local perfCounters = { outer = 0, teamQueries = 0, layouts = 0, skillChanged = 0, skillSkipped = 0,
    tacticalChanged = 0, tacticalSkipped = 0, statsChanged = 0, statsSkipped = 0,
    commanderChanged = 0, commanderSkipped = 0, interactionTicks = 0, dataRefreshes = 0,
    identityChanged = 0, identitySkipped = 0, muteChanged = 0, muteSkipped = 0,
    backgroundChanged = 0, backgroundSkipped = 0, teamChanged = 0, teamSkipped = 0 }

-- Dirty domains are checked on every scheduled data pass. Keep their last
-- inputs as reusable arrays so unchanged rows do not allocate formatted key
-- strings and temporary concat tables ten times per second.
local function DirtyValuesChanged(owner, cacheName, ...)
    local valueCount = select("#", ...)
    local cached = owner[cacheName]
    local changed = not cached or cached.n ~= valueCount
    if not changed then
        for i = 1, valueCount do
            if cached[i] ~= select(i, ...) then
                changed = true
                break
            end
        end
    end
    if changed then
        cached = cached or {}
        cached.n = valueCount
        for i = 1, valueCount do
            cached[i] = select(i, ...)
        end
        owner[cacheName] = cached
    end
    return changed
end

local function DirtyListChanged(owner, cacheName, values)
    local cached = owner[cacheName]
    local valueCount = #values
    local changed = not cached or cached.n ~= valueCount
    if not changed then
        for i = 1, valueCount do
            if cached[i] ~= values[i] then
                changed = true
                break
            end
        end
    end
    if changed then
        cached = cached or {}
        cached.n = valueCount
        for i = 1, valueCount do cached[i] = values[i] end
        owner[cacheName] = cached
    end
    return changed
end

-- Color constants.
GUIScoreboard.kBlueColor = ColorIntToColor(kMarineTeamColor)
GUIScoreboard.kBlueHighlightColor = Color(0.30, 0.69, 1, 1)
GUIScoreboard.kRedColor = kRedColor
-- ColorIntToColor(kAlienTeamColor)
GUIScoreboard.kRedHighlightColor = Color(1, 0.79, 0.23, 1)
GUIScoreboard.kSpectatorColor = ColorIntToColor(kNeutralTeamColor)
GUIScoreboard.kSpectatorHighlightColor = Color(0.8, 0.8, 0.8, 1)

GUIScoreboard.kCommanderFontColor = Color(1, 1, 0, 1)
GUIScoreboard.kWhiteColor = Color(1, 1, 1, 1)
local kDeadColor = Color(1, 0, 0, 1)

local kMutedTextTexture = PrecacheAsset("ui/sb-text-muted.dds")
local kMutedVoiceTexture = PrecacheAsset("ui/sb-voice-muted.dds")
local kMutedCallTexture = PrecacheAsset("ui/ShimizuScoreboard/mutecall.dds")
local kTeamVoiceUnmutedTexture = PrecacheAsset("ui/speaker.dds")
local kTeamVoiceMutedTexture = PrecacheAsset("ui/sb-voice-muted.dds")
local kTeamVoiceIconSize = 22
local kTeamVoiceIconSafetyGap = 25

local function IsLocalClientSpectator()
    -- First-person spectating makes Client.GetLocalPlayer() return the followed
    -- player. The client's assigned team remains spectator and is authoritative
    -- for spectator-only controls throughout camera-mode changes.
    if Client.GetLocalClientTeamNumber then
        return Client.GetLocalClientTeamNumber() == kSpectatorIndex
    end
    local player = Client.GetLocalPlayer()
    return player and player:GetTeamNumber() == kSpectatorIndex
end

local function dump(o)
    if type(o) == "table" then
        local s = "{ "
        for k, v in pairs(o) do
            if type(k) ~= "number" then
                k = '"' .. k .. '"'
            end
            s = s .. "[" .. k .. "] = " .. dump(v) .. ","
        end
        return s .. "} "
    else
        return tostring(o)
    end
end

-- Round function implementation with round up and decimal
local function round(number, decimals)
    PROFILE("round")
    if number and IsNumber(number) then
        if decimals > 0 then
            decimals = 10 ^ decimals
            number = number * decimals
            number = number % 1 >= 0.5 and math.ceil(number) or math.floor(number)
            number = number / decimals
        else
            number = number % 1 >= 0.5 and math.ceil(number) or math.floor(number)
        end

        return tostring(number)
    else
        return "NaN"
    end
end

local function humanNumber(number)
    PROFILE("humanNumber")
    if number and IsNumber(number) then
        if number > 1000000 then
            number = number / 10000
            number = number % 1 >= 0.5 and math.ceil(number) or math.floor(number)
            number = number / 100
            number = tostring(number) .. "m"
        elseif number > 1000 then
            number = number / 100
            number = number % 1 >= 0.5 and math.ceil(number) or math.floor(number)
            number = number / 10
            number = tostring(number) .. "k"
        end

        return tostring(number)
    else
        return "NaN"
    end
end

local function myPrint(string)
    if Client.GetSteamId() == 74660439 or Client.GetSteamId() == 77470693 then
        HPrint(string)
    end
end

local function fetchPlayerStats(fetchTable)
    PROFILE("fetchPlayerStats")

    if not fetchTable or #fetchTable == 0 then return end

    local rosterIds, rosterLookup = {}, {}
    for _, user in ipairs(fetchTable) do
        user = tonumber(user)
        if user and user > 0 and not rosterLookup[user] then
            rosterLookup[user] = true
            rosterIds[#rosterIds + 1] = user
        end
    end
    local signatureParts = {}
    for i = 1, #rosterIds do signatureParts[i] = tostring(rosterIds[i]) end
    local signature = table.concat(signatureParts, ",")
    if signature ~= statsRosterSignature then
        statsRosterSignature = signature
        statsRequestGeneration = statsRequestGeneration + 1
        globalFetchTime = -kStatsRetryInterval
    end
    if globalFetchTime + kStatsRetryInterval > Shared.GetTime() then return end

    local requested, requestedLookup = {}, {}
    for _, user in ipairs(rosterIds) do
        local cached = user and playerStatsTable[user]
        if user and user > 0 and not requestedLookup[user] and
                (not cached or cached.state == "failed" or
                    (cached.state == "pending" and cached.generation ~= statsRequestGeneration)) then
            requestedLookup[user] = true
            requested[#requested + 1] = user
        end
    end
    if #requested == 0 then return end

    globalFetchTime = Shared.GetTime()
    statsRequestGeneration = statsRequestGeneration + 1
    local generation = statsRequestGeneration
    local idStrings = {}
    for i = 1, #requested do
        idStrings[i] = tostring(requested[i])
        playerStatsTable[requested[i]] = { state = "pending", generation = generation }
    end
    Shared.SendHTTPRequest(string.format(fetchUrl, table.concat(idStrings, ",")), "GET", {}, function(data)
        if generation ~= statsRequestGeneration then
            Print("[SSBPerf] Ignored stale NS2Stats callback generation=%d current=%d",
                generation, statsRequestGeneration)
            return
        end

        local ok, decoded = pcall(json.decode, data or "")
        if not ok or type(decoded) ~= "table" then
            for i = 1, #requested do playerStatsTable[requested[i]] = { state = "failed" } end
            Print("[SSB] NS2Stats batch generation=%d returned malformed data", generation)
            return
        end

        local resolved = {}
        local resolvedCount = 0
        for _, value in ipairs(decoded) do
            local steamId = type(value) == "table" and tonumber(value.steam_id)
            if steamId and requestedLookup[steamId] and
                    (value.marine_kdr == nil or IsNumber(value.marine_kdr)) and
                    (value.alien_kdr == nil or IsNumber(value.alien_kdr)) and
                    (value.marine_accuracy == nil or IsNumber(value.marine_accuracy)) and
                    (value.alien_accuracy == nil or IsNumber(value.alien_accuracy)) then
                local normalizedLifeform = NormalizeSelectorLifeform(value.main_lifeform)
                if value.main_lifeform ~= nil and not normalizedLifeform then
                    Print("[SSBLifeform] Invalid API main_lifeform steamId=%s value=%s; defaulting to Onos",
                        ToString(steamId), ToString(value.main_lifeform))
                end
                value.main_lifeform = normalizedLifeform
                local hasMetrics = IsNumber(value.marine_kdr) or IsNumber(value.alien_kdr) or
                    IsNumber(value.marine_accuracy) or IsNumber(value.alien_accuracy)
                value.state = hasMetrics and "ready" or "missing"
                playerStatsTable[steamId] = value
                resolved[steamId] = true
                resolvedCount = resolvedCount + 1
            end
        end
        for i = 1, #requested do
            local steamId = requested[i]
            if not resolved[steamId] then playerStatsTable[steamId] = { state = "missing" } end
        end
    end)
end

local function getPlayerStats(steamId)
    if not steamId then
        return nil
    end

    return playerStatsTable[steamId]
end

local function GetSpectatorScoreboardViewMode()
    if SSB_GetSpectatorScoreboardViewMode then return SSB_GetSpectatorScoreboardViewMode() end
    return "USE_SERVER_SETTINGS"
end

local function GetScoreboardHumanCount()
    local count = 0
    for _, record in ipairs(ScoreboardUI_GetAllScores()) do
        if record.SteamId and record.SteamId ~= 0 then count = count + 1 end
    end
    return count
end

-- Spectator section order (.claude/docs/ready-check.md): Ready Room players,
-- then queued spectators by queue position (#1 on top), then non-queued
-- spectators. Ties keep vanilla's ClientIndex-descending order. The records
-- table is rebuilt on every call, so sorting it in place is safe.
local function GetSpectatorSectionRank(record)
    if record.EntityTeamNumber == kSpectatorIndex then
        local queuePositions = MNGAReadyRoomQueuePositions
        local position = queuePositions and queuePositions[tonumber(record.SteamId)]
        if position then return 2, position end
        return 3, 0
    end
    return 1, 0
end

local function CompareSpectatorSectionRecords(a, b)
    local rankA, positionA = GetSpectatorSectionRank(a)
    local rankB, positionB = GetSpectatorSectionRank(b)
    if rankA ~= rankB then return rankA < rankB end
    if positionA ~= positionB then return positionA < positionB end
    return (a.ClientIndex or 0) > (b.ClientIndex or 0)
end

-- Ready Room header counts, taken from the full section before the spectator
-- row filter so hidden spectators are still counted.
local ssbSectionReadyRoomCount, ssbSectionQueueCount, ssbSectionSpectatorCount = 0, 0, 0

local function SSB_GetSpectatorSectionScores()
    local records = ScoreboardUI_GetSpectatorScores()
    if #records > 1 then
        table.sort(records, CompareSpectatorSectionRecords)
    end
    local numReadyRoom, numQueue, numSpectators = 0, 0, 0
    for i = 1, #records do
        local rank = GetSpectatorSectionRank(records[i])
        if rank == 1 then numReadyRoom = numReadyRoom + 1
        elseif rank == 2 then numQueue = numQueue + 1
        else numSpectators = numSpectators + 1 end
    end
    ssbSectionReadyRoomCount, ssbSectionQueueCount, ssbSectionSpectatorCount = numReadyRoom, numQueue, numSpectators
    local active = GetScoreboardHumanCount() >= kSpectatorScoreboardFilterMinHumans
    if active ~= lastSpectatorFilterActive then lastSpectatorFilterActive = active end
    local localPlayer = Client.GetLocalPlayer()
    if not active or GetSpectatorScoreboardViewMode() == "ALWAYS_SHOW_ALL" or
            (localPlayer and localPlayer:GetTeamNumber() == kSpectatorIndex) then
        return records
    end
    local visible, hidden = {}, 0
    for i = 1, #records do
        if records[i].IsSpectator then hidden = hidden + 1 else visible[#visible + 1] = records[i] end
    end
    if hidden ~= lastSpectatorRowsHidden then
        Print("[SSB] Hiding %d spectator row(s); retaining %d Ready Room row(s)", hidden, #visible)
        lastSpectatorRowsHidden = hidden
    end
    return visible
end

function GUIScoreboard:OnResolutionChanged(_, _, newX, _)
    PROFILE("GUIScoreboard:OnResolutionChanged")
    GUIScoreboard.screenWidth = newX

    GUIScoreboard.kTeamColumnSpacingX = ConditionalValue(GUIScoreboard.screenWidth < 1280, 30, 40)

    -- Horizontal size for the game time background is irrelevant as it will be expanded to SB width
    GUIScoreboard.kGameTimeBackgroundSize = Vector(640, GUIScale(32), 0)
    GUIScoreboard.kClickForMouseBackgroundSize = Vector(GUIScale(200), GUIScale(32), 0)

    GUIScoreboard.kBgMaxYSpace = Client.GetScreenHeight() - ((GUIScoreboard.kClickForMouseBackgroundSize.y + 5) + (GUIScoreboard.kGameTimeBackgroundSize.y + 6) + 20)

    self:Uninitialize()
    self:Initialize()
end

function GUIScoreboard:GetTeamItemWidth()
    PROFILE("GUIScoreboard:GetTeamItemWidth")
    if GUIScoreboard.screenWidth < 1280 then
        return 608 -- 640 * 0.95
    else
        return math.min(800, GUIScoreboard.screenWidth / 2 * 0.95)
    end
end

local function CreateTeamBackground(self, teamNumber)
    PROFILE("CreateTeamBackground")
    local color
    local teamItem = GUIManager:CreateGraphicItem()
    teamItem:SetStencilFunc(GUIItem.NotEqual)

    -- Background
    local isPlayingTeam = teamNumber ~= kTeamReadyRoom
    teamItem:SetSize(Vector(self:GetTeamItemWidth(), GUIScoreboard.kTeamItemHeight, 0) * GUIScoreboard.kScalingFactor)
    if teamNumber == kTeamReadyRoom then
        color = GUIScoreboard.kSpectatorColor
        teamItem:SetAnchor(GUIItem.Middle, GUIItem.Top)
    elseif teamNumber == kTeam1Index then
        color = GUIScoreboard.kBlueColor
        teamItem:SetAnchor(GUIItem.Middle, GUIItem.Top)
    elseif teamNumber == kTeam2Index then
        color = GUIScoreboard.kRedColor
        teamItem:SetAnchor(GUIItem.Middle, GUIItem.Top)
    end

    teamItem:SetColor(Color(0, 0, 0, 0.75))
    teamItem:SetIsVisible(false)
    teamItem:SetLayer(kGUILayerScoreboard)

    -- Team name text item.
    local teamNameItem = GUIManager:CreateTextItem()
    teamNameItem:SetFont(GUIScoreboard.kTeamLargeBoldFont)
    teamNameItem:SetFontIsBold(true)

    GUIMakeFontScale(teamNameItem)
    teamNameItem:SetAnchor(GUIItem.Left, GUIItem.Top)
    teamNameItem:SetTextAlignmentX(GUIItem.Align_Min)
    teamNameItem:SetTextAlignmentY(GUIItem.Align_Min)
    if not isPlayingTeam then
        teamNameItem:SetPosition(Vector(10, 5, 0) * GUIScoreboard.kScalingFactor)
    else
        teamNameItem:SetPosition(Vector(10 + kPlayerSkillIconSize.x, 5, 0) * GUIScoreboard.kScalingFactor)
    end
    teamNameItem:SetColor(color)
    teamNameItem:SetStencilFunc(GUIItem.NotEqual)
    teamItem:AddChild(teamNameItem)

    local teamSkillItem = GUIManager:CreateGraphicItem()
    teamSkillItem:SetAnchor(GUIItem.Left, GUIItem.Top)
    teamSkillItem:SetPosition(Vector(10, 5, 0) * GUIScoreboard.kScalingFactor)
    teamSkillItem:SetSize(kPlayerSkillIconSize * GUIScoreboard.kScalingFactor)
    teamSkillItem:SetStencilFunc(GUIItem.NotEqual)
    teamSkillItem:SetTexture(kPlayerSkillIconTexture)
    teamSkillItem:SetTexturePixelCoordinates(0, 0, 100, 31)
    teamSkillItem:SetIsVisible(false)
    teamItem:AddChild(teamSkillItem)

    local playerDataRowY = 10
    local currentColumnX = ConditionalValue(GUIScoreboard.screenWidth < 1280, GUIScoreboard.kPlayerItemWidth, self:GetTeamItemWidth() - GUIScoreboard.kTeamColumnSpacingX * 10)

    -- Add team info items (team resources etc).
    local teamInfoItems = {}
    teamInfoItems["teamRes"] = GUIManager:CreateTextItem()
    teamInfoItems["teamRes"]:SetFont(GUIScoreboard.kTeamSmallBoldFont)
    GUIMakeFontScale(teamInfoItems["teamRes"])
    teamInfoItems["teamRes"]:SetAnchor(GUIItem.Left, GUIItem.Top)
    teamInfoItems["teamRes"]:SetTextAlignmentX(GUIItem.Align_Min)
    teamInfoItems["teamRes"]:SetTextAlignmentY(GUIItem.Align_Min)
    teamInfoItems["teamRes"]:SetPosition(Vector(12, GUIScoreboard.kTeamNameFontSize + 7, 0) * GUIScoreboard.kScalingFactor)
    teamInfoItems["teamRes"]:SetColor(color)
    teamInfoItems["teamRes"]:SetStencilFunc(GUIItem.NotEqual)
    teamItem:AddChild(teamInfoItems["teamRes"])

    teamInfoItems["teamCommIcon"] = GUIManager:CreateGraphicItem()
    teamInfoItems["teamCommIcon"]:SetSize(Vector(kPlayerBadgeIconSize, kPlayerBadgeIconSize, 0))
    teamInfoItems["teamCommIcon"]:SetAnchor(GUIItem.Right, GUIItem.Top)
    teamInfoItems["teamCommIcon"]:SetPosition(Vector(-12 - kPlayerBadgeIconSize, playerDataRowY, 0) * GUIScoreboard.kScalingFactor)
    teamInfoItems["teamCommIcon"]:SetTexture(kPlayerCommIconTexture)
    teamInfoItems["teamCommIcon"]:SetIsVisible(isPlayingTeam)
    teamItem:AddChild(teamInfoItems["teamCommIcon"])

    -- Add team commander
    teamInfoItems["teamComm"] = GUIManager:CreateTextItem()
    teamInfoItems["teamComm"]:SetFont(GUIScoreboard.kTeamLargeBoldFont)
    GUIMakeFontScale(teamInfoItems["teamComm"])
    teamInfoItems["teamComm"]:SetAnchor(GUIItem.Right, GUIItem.Top)
    teamInfoItems["teamComm"]:SetTextAlignmentX(GUIItem.Align_Max)
    teamInfoItems["teamComm"]:SetTextAlignmentY(GUIItem.Align_Min)
    teamInfoItems["teamComm"]:SetPosition(Vector(-12 - kPlayerBadgeIconSize - 4, playerDataRowY, 0) * GUIScoreboard.kScalingFactor)
    teamInfoItems["teamComm"]:SetText(Locale.ResolveString("NO_COMMANDER"))
    teamInfoItems["teamComm"]:SetColor(color)
    teamInfoItems["teamComm"]:SetStencilFunc(GUIItem.NotEqual)
    teamInfoItems["teamComm"]:SetIsVisible(isPlayingTeam)
    teamItem:AddChild(teamInfoItems["teamComm"])

    -- Status text item.
    local statusItem = GUIManager:CreateTextItem()
    statusItem:SetFont(GUIScoreboard.kTeamSmallBoldFont)
    GUIMakeFontScale(statusItem)
    statusItem:SetAnchor(GUIItem.Left, GUIItem.Top)
    statusItem:SetTextAlignmentX(GUIItem.Align_Min)
    statusItem:SetTextAlignmentY(GUIItem.Align_Min)
    statusItem:SetPosition(Vector(currentColumnX + 60, GUIScoreboard.kTeamNameFontSize + 7, 0) * GUIScoreboard.kScalingFactor)
    statusItem:SetColor(color)
    statusItem:SetText("")
    statusItem:SetStencilFunc(GUIItem.NotEqual)
    teamItem:AddChild(statusItem)

    currentColumnX = currentColumnX + GUIScoreboard.kTeamColumnSpacingX * 2 + 33

    -- Score text item.
    local scoreItem = GUIManager:CreateTextItem()
    scoreItem:SetFont(GUIScoreboard.kTeamSmallBoldFont)
    GUIMakeFontScale(scoreItem)
    scoreItem:SetAnchor(GUIItem.Left, GUIItem.Top)
    scoreItem:SetTextAlignmentX(GUIItem.Align_Center)
    scoreItem:SetTextAlignmentY(GUIItem.Align_Min)
    scoreItem:SetPosition(Vector(currentColumnX + 42.5, GUIScoreboard.kTeamNameFontSize + 7, 0) * GUIScoreboard.kScalingFactor)
    scoreItem:SetColor(color)
    scoreItem:SetText(Locale.ResolveString("SB_SCORE"))
    scoreItem:SetStencilFunc(GUIItem.NotEqual)
    scoreItem:SetIsVisible(isPlayingTeam)
    teamItem:AddChild(scoreItem)

    currentColumnX = currentColumnX + GUIScoreboard.kTeamColumnSpacingX + 40

    -- Kill text item.
    local killsItem = GUIManager:CreateTextItem()
    killsItem:SetFont(GUIScoreboard.kTeamSmallBoldFont)
    GUIMakeFontScale(killsItem)
    killsItem:SetAnchor(GUIItem.Left, GUIItem.Top)
    killsItem:SetTextAlignmentX(GUIItem.Align_Center)
    killsItem:SetTextAlignmentY(GUIItem.Align_Min)
    killsItem:SetPosition(Vector(currentColumnX, GUIScoreboard.kTeamNameFontSize + 7, 0) * GUIScoreboard.kScalingFactor)
    killsItem:SetColor(color)
    killsItem:SetText(Locale.ResolveString("SB_KILLS"))
    killsItem:SetStencilFunc(GUIItem.NotEqual)
    killsItem:SetIsVisible(isPlayingTeam)
    teamItem:AddChild(killsItem)

    currentColumnX = currentColumnX + GUIScoreboard.kTeamColumnSpacingX

    -- Assist text item.
    local assistsItem = GUIManager:CreateTextItem()
    assistsItem:SetFont(GUIScoreboard.kTeamSmallBoldFont)
    GUIMakeFontScale(assistsItem)
    assistsItem:SetAnchor(GUIItem.Left, GUIItem.Top)
    assistsItem:SetTextAlignmentX(GUIItem.Align_Center)
    assistsItem:SetTextAlignmentY(GUIItem.Align_Min)
    assistsItem:SetPosition(Vector(currentColumnX, GUIScoreboard.kTeamNameFontSize + 7, 0) * GUIScoreboard.kScalingFactor)
    assistsItem:SetColor(color)
    assistsItem:SetText(Locale.ResolveString("SB_ASSISTS"))
    assistsItem:SetStencilFunc(GUIItem.NotEqual)
    assistsItem:SetIsVisible(isPlayingTeam)
    teamItem:AddChild(assistsItem)

    currentColumnX = currentColumnX + GUIScoreboard.kTeamColumnSpacingX

    -- Deaths text item.
    local deathsItem = GUIManager:CreateTextItem()
    deathsItem:SetFont(GUIScoreboard.kTeamSmallBoldFont)
    GUIMakeFontScale(deathsItem)
    deathsItem:SetAnchor(GUIItem.Left, GUIItem.Top)
    deathsItem:SetTextAlignmentX(GUIItem.Align_Center)
    deathsItem:SetTextAlignmentY(GUIItem.Align_Min)
    deathsItem:SetPosition(Vector(currentColumnX, GUIScoreboard.kTeamNameFontSize + 7, 0) * GUIScoreboard.kScalingFactor)
    deathsItem:SetColor(color)
    deathsItem:SetText(Locale.ResolveString("SB_DEATHS"))
    deathsItem:SetStencilFunc(GUIItem.NotEqual)
    deathsItem:SetIsVisible(isPlayingTeam)
    teamItem:AddChild(deathsItem)

    currentColumnX = currentColumnX + GUIScoreboard.kTeamColumnSpacingX

    -- Resources text item.
    local resItem = GUIManager:CreateGraphicItem()
    resItem:SetPosition((Vector(currentColumnX, GUIScoreboard.kTeamNameFontSize + 7, 0) + kIconOffset) * GUIScoreboard.kScalingFactor)
    resItem:SetTexture(kBuildmenuTexture)
    resItem:SetTexturePixelCoordinates(GUIUnpackCoords(GetTextureCoordinatesForIcon(kTechId.CollectResources)))
    resItem:SetSize(kIconSize * GUIScoreboard.kScalingFactor)
    resItem:SetStencilFunc(GUIItem.NotEqual)
    resItem:SetIsVisible(isPlayingTeam)
    teamItem:AddChild(resItem)

    currentColumnX = currentColumnX + GUIScoreboard.kTeamColumnSpacingX

    -- Ping text item.
    local pingItem = GUIManager:CreateTextItem()
    pingItem:SetFont(GUIScoreboard.kTeamSmallBoldFont)
    GUIMakeFontScale(pingItem)
    pingItem:SetAnchor(GUIItem.Left, GUIItem.Top)
    pingItem:SetTextAlignmentX(GUIItem.Align_Min)
    pingItem:SetTextAlignmentY(GUIItem.Align_Min)
    pingItem:SetPosition(Vector(currentColumnX, GUIScoreboard.kTeamNameFontSize + 7, 0) * GUIScoreboard.kScalingFactor)
    pingItem:SetColor(color)
    pingItem:SetText(Locale.ResolveString("SB_PING"))
    pingItem:SetStencilFunc(GUIItem.NotEqual)
    teamItem:AddChild(pingItem)

    local teamVoiceMute
    if teamNumber == kTeam1Index or teamNumber == kTeam2Index then
        teamVoiceMute = GUIManager:CreateGraphicItem()
        teamVoiceMute:SetAnchor(GUIItem.Left, GUIItem.Top)
        teamVoiceMute:SetSize(Vector(kTeamVoiceIconSize, kTeamVoiceIconSize, 0) * GUIScoreboard.kScalingFactor)
        teamVoiceMute:SetColor(Color(1, 1, 1, 0.9))
        teamVoiceMute:SetStencilFunc(GUIItem.NotEqual)
        teamVoiceMute:SetIsVisible(false)
        teamItem:AddChild(teamVoiceMute)
    end

    return {
        Background = teamItem,
        TeamName = teamNameItem,
        TeamInfo = teamInfoItems,
        TeamSkill = teamSkillItem,
        TeamVoiceMute = teamVoiceMute
    }
end

local kFavoriteMouseOverColor = Color(1, 1, 0, 1)
local kFavoriteColor = Color(1, 1, 1, 0.9)

local kBlockedMouseOverColor = Color(1, 1, 0, 1)
local kBlockedColor = Color(1, 1, 1, 0.9)

-- Forward-declared so every teardown path can release mouse ownership before
-- destroying the GUI objects used by mouse mode.
local SetMouseVisible

function GUIScoreboard:Initialize()
    PROFILE("GUIScoreboard:Initialize")

    self.updateInterval = kVisibleUpdateInterval

    kGUIdata.contentXSize = 0
    kGUIdata.contentYSize = 0

    self.visible = false
    self.ssbNextDataRefresh = 0
    self.ssbForceDataRefresh = true
    self.ssbHoveredPlayerItem = nil
    self.ssbLifeformSyncEligible = false

    localPlayerSteamID = Client:GetSteamId()

    guiThrottleTime[kMarineTeamType] = 0
    guiThrottleTime[kAlienTeamType] = 0
    lastComm[kMarineTeamType] = nil
    lastComm[kAlienTeamType] = nil
    lastCommLastSeen[kMarineTeamType] = nil
    lastCommLastSeen[kAlienTeamType] = nil
    commanderTrackingActive = true
    lastCommanderGameState = nil

    self.teams = {}
    self.reusePlayerItems = {}
    self.slidePercentage = -1
    GUIScoreboard.screenWidth = Client.GetScreenWidth()
    GUIScoreboard.screenHeight = Client.GetScreenHeight()
    GUIScoreboard.kScalingFactor = ConditionalValue(GUIScoreboard.screenHeight > 1280, GUIScale(1), 1)
    self.centerOnPlayer = true -- For modding

    self.scoreboardBackground = GUIManager:CreateGraphicItem()
    self.scoreboardBackground:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.scoreboardBackground:SetLayer(kGUILayerScoreboard)
    self.scoreboardBackground:SetColor(GUIScoreboard.kBgColor)
    self.scoreboardBackground:SetIsVisible(false)

    self.background = GUIManager:CreateGraphicItem()
    self.background:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.background:SetLayer(kGUILayerScoreboard)
    self.background:SetColor(GUIScoreboard.kBgColor)
    self.background:SetIsVisible(false)

    self.backgroundStencil = GUIManager:CreateGraphicItem()
    self.backgroundStencil:SetIsStencil(true)
    self.backgroundStencil:SetClearsStencilBuffer(true)
    self.scoreboardBackground:AddChild(self.backgroundStencil)

    self.slidebar = GUIManager:CreateGraphicItem()
    self.slidebar:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.slidebar:SetSize(GUIScoreboard.kSlidebarSize * GUIScoreboard.kScalingFactor)
    self.slidebar:SetLayer(kGUILayerScoreboard)
    self.slidebar:SetColor(Color(1, 1, 1, 1))
    self.slidebar:SetIsVisible(true)

    self.slidebarBg = GUIManager:CreateGraphicItem()
    self.slidebarBg:SetAnchor(GUIItem.Right, GUIItem.Top)
    self.slidebarBg:SetSize(Vector(GUIScoreboard.kSlidebarSize.x * GUIScoreboard.kScalingFactor, GUIScoreboard.kBgMaxYSpace - 20, 0))
    self.slidebarBg:SetPosition(Vector(-12.5 * GUIScoreboard.kScalingFactor, 10, 0))
    self.slidebarBg:SetLayer(kGUILayerScoreboard)
    self.slidebarBg:SetColor(Color(0.25, 0.25, 0.25, 1))
    self.slidebarBg:SetIsVisible(false)
    self.slidebarBg:AddChild(self.slidebar)
    self.scoreboardBackground:AddChild(self.slidebarBg)

    self.gameTimeBackground = GUIManager:CreateGraphicItem()
    self.gameTimeBackground:SetSize(GUIScoreboard.kGameTimeBackgroundSize)
    self.gameTimeBackground:SetAnchor(GUIItem.Middle, GUIItem.Top)
    self.gameTimeBackground:SetPosition(Vector(-GUIScoreboard.kGameTimeBackgroundSize.x / 2, 10, 0))
    self.gameTimeBackground:SetIsVisible(false)
    self.gameTimeBackground:SetColor(Color(0, 0, 0, 0.5))
    self.gameTimeBackground:SetLayer(kGUILayerScoreboard)

    self.gameTime = GUIManager:CreateTextItem()
    self.gameTime:SetFontName(GUIScoreboard.kGameTimeFontName)
    self.gameTime:SetScale(GetScaledVector())
    GUIMakeFontScale(self.gameTime)
    self.gameTime:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.gameTime:SetTextAlignmentX(GUIItem.Align_Center)
    self.gameTime:SetTextAlignmentY(GUIItem.Align_Center)
    self.gameTime:SetColor(Color(1, 1, 1, 1))
    self.gameTime:SetText("")
    self.gameTimeBackground:AddChild(self.gameTime)

    self.serverAddress = Client.GetConnectedServerAddress()

    self.favoriteButton = GUIManager:CreateGraphicItem()
    self.favoriteButton:SetSize(GUIScale(self.kFavoriteIconSize))
    self.favoriteButton.isServerFavorite = GetServerIsFavorite(self.serverAddress)
    self.favoriteButton:SetTexture(self.favoriteButton.isServerFavorite and self.kFavoriteTexture or self.kNotFavoriteTexture)
    self.favoriteButton:SetColor(kFavoriteColor)
    self.favoriteButton:SetAnchor(GUIItem.Middle, GUIItem.Top)
    self.gameTimeBackground:AddChild(self.favoriteButton)

    self.blockedButton = GUIManager:CreateGraphicItem()
    self.blockedButton:SetSize(GUIScale(self.kBlockedIconSize))
    self.blockedButton.isServerBlocked = GetServerIsBlocked(self.serverAddress)
    self.blockedButton:SetTexture(self.blockedButton.isServerBlocked and self.kBlockedTexture or self.kNotBlockedTexture)
    self.blockedButton:SetColor(kFavoriteColor)
    self.blockedButton:SetAnchor(GUIItem.Middle, GUIItem.Top)
    self.gameTimeBackground:AddChild(self.blockedButton)

    -- Teams table format: Team GUIItems, color, player GUIItem list, get scores function.
    -- Spectator team.
    table.insert(self.teams, {
        GUIs = CreateTeamBackground(self, kTeamReadyRoom),
        TeamName = ScoreboardUI_GetSpectatorTeamName(),
        Color = GUIScoreboard.kSpectatorColor,
        PlayerList = {},
        HighlightColor = GUIScoreboard.kSpectatorHighlightColor,
        GetScores = SSB_GetSpectatorSectionScores,
        TeamNumber = kTeamReadyRoom
    })

    -- Blue team.
    table.insert(self.teams, {
        GUIs = CreateTeamBackground(self, kTeam1Index),
        TeamName = ScoreboardUI_GetBlueTeamName(),
        Color = GUIScoreboard.kBlueColor,
        PlayerList = {},
        HighlightColor = GUIScoreboard.kBlueHighlightColor,
        GetScores = ScoreboardUI_GetBlueScores,
        TeamNumber = kTeam1Index
    })

    -- Red team.
    table.insert(self.teams, {
        GUIs = CreateTeamBackground(self, kTeam2Index),
        TeamName = ScoreboardUI_GetRedTeamName(),
        Color = GUIScoreboard.kRedColor,
        PlayerList = {},
        HighlightColor = GUIScoreboard.kRedHighlightColor,
        GetScores = ScoreboardUI_GetRedScores,
        TeamNumber = kTeam2Index
    })

    self.background:AddChild(self.teams[1].GUIs.Background)
    self.background:AddChild(self.teams[2].GUIs.Background)
    self.background:AddChild(self.teams[3].GUIs.Background)

    -- Add team topBar
    self.playerHighlightItem = GUIManager:CreateGraphicItem()
    self.playerHighlightItem:SetSize(Vector(self:GetTeamItemWidth() - (GUIScoreboard.kPlayerItemWidthBuffer * 2), GUIScoreboard.kPlayerItemHeight, 0) * GUIScoreboard.kScalingFactor)
    self.playerHighlightItem:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.playerHighlightItem:SetColor(Color(1, 1, 1, 1))
    self.playerHighlightItem:SetTexture(kHudElementsTexture)
    self.playerHighlightItem:SetTextureCoordinates(0, 0.16, 0.558, 0.32)
    self.playerHighlightItem:SetStencilFunc(GUIItem.NotEqual)
    self.playerHighlightItem:SetIsVisible(false)

    self.clickForMouseBackground = GUIManager:CreateGraphicItem()
    self.clickForMouseBackground:SetSize(GUIScoreboard.kClickForMouseBackgroundSize)
    self.clickForMouseBackground:SetPosition(Vector(-GUIScoreboard.kClickForMouseBackgroundSize.x / 2, -GUIScoreboard.kClickForMouseBackgroundSize.y - 5, 0))
    self.clickForMouseBackground:SetAnchor(GUIItem.Middle, GUIItem.Bottom)
    self.clickForMouseBackground:SetIsVisible(false)

    self.clickForMouseIndicator = GUIManager:CreateTextItem()
    self.clickForMouseIndicator:SetFontName(GUIScoreboard.kClickForMouseFontName)
    self.clickForMouseIndicator:SetScale(GetScaledVector())
    GUIMakeFontScale(self.clickForMouseIndicator)
    self.clickForMouseIndicator:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.clickForMouseIndicator:SetTextAlignmentX(GUIItem.Align_Center)
    self.clickForMouseIndicator:SetTextAlignmentY(GUIItem.Align_Center)
    self.clickForMouseIndicator:SetColor(Color(0, 0, 0, 1))
    self.clickForMouseIndicator:SetText(GUIScoreboard.kClickForMouseText)
    self.clickForMouseBackground:AddChild(self.clickForMouseIndicator)

    self.mousePressed = {
        LMB = {
            Down = nil
        },
        RMB = {
            Down = nil
        }
    }
    self.badgeNameTooltip = GetGUIManager():CreateGUIScriptSingle("menu/GUIHoverTooltip")
    -- This tooltip is owned by cursor hover state, not by a display timer.
    -- Without toggle mode, GUIHoverTooltip:Show() sets an immediately-expired
    -- targetTime and its update hides the tooltip before the next interaction
    -- pass shows it again.
    self.badgeNameTooltip:SetToggle(true)
    -- GUIHoverTooltip defaults to kUpdateIntervalLow after its fade animation
    -- ends, which makes a cursor-anchored tooltip visibly trail the mouse.
    -- Keep this scoreboard-owned tooltip at a true 100 Hz even when idle.
    self.badgeNameTooltip.noItemsUpdateInterval = kMouseUpdateInterval
    self.badgeNameTooltip.updateInterval = kMouseUpdateInterval

    self.hoverMenu = GetGUIManager():CreateGUIScriptSingle("GUIHoverMenu")
    self.hoverMenu:Hide()

    self.hoverPlayerClientIndex = 0
    self.ssbHoverTooltipText = nil
    self.ssbHoverTooltipSteamId = nil

    self.mouseVisible = false
    self.ssbMouseBackend = nil
    self.ssbMouseController = nil

    self.hiddenOverride = HelpScreen_GetHelpScreen():GetIsBeingDisplayed() -- if true, forces scoreboard to be hidden
end

function GUIScoreboard:Uninitialize()
    PROFILE("GUIScoreboard:Uninitialize")
    if self.mouseVisible then
        Print("%s", string.format(
            "[SSBMouse] uninitialize with active ownership backend=%s mouse_before=%d registered=%s",
            tostring(self.ssbMouseBackend),
            self.ssbMouseController and self.ssbMouseController.MouseObjects or -1,
            tostring(self.ssbMouseController and self.ssbMouseController.MouseEnabledControls[self] == true)))
        SetMouseVisible(self, false)
    end

    for _, team in ipairs(self.teams) do
        GUI.DestroyItem(team["GUIs"]["Background"])
    end
    self.teams = {}

    for _, playerItem in ipairs(self.reusePlayerItems) do
        GUI.DestroyItem(playerItem["Background"])
    end
    self.reusePlayerItems = {}

    GUI.DestroyItem(self.clickForMouseIndicator)
    self.clickForMouseIndicator = nil
    GUI.DestroyItem(self.clickForMouseBackground)
    self.clickForMouseBackground = nil

    GUI.DestroyItem(self.gameTime)
    self.gameTime = nil
    GUI.DestroyItem(self.favoriteButton)
    self.favoriteButton = nil
    GUI.DestroyItem(self.blockedButton)
    self.blockedButton = nil
    GUI.DestroyItem(self.gameTimeBackground)
    self.gameTimeBackground = nil

    GUI.DestroyItem(self.scoreboardBackground)
    self.scoreboardBackground = nil

    GUI.DestroyItem(self.background)
    self.background = nil

    GUI.DestroyItem(self.playerHighlightItem)
    self.playerHighlightItem = nil

    lastComm = {}

    kGUIdata.contentXSize = 0
    kGUIdata.contentYSize = 0
end

local function UpdateLifeformSyncEligibility(self, reason)
    local eligible = GetLifeformViewerEligible()
    if eligible and not self.ssbLifeformSyncEligible and SSB_RequestLifeformSelectionSync then
        SSB_RequestLifeformSelectionSync(reason or "viewer_became_eligible")
    elseif self.ssbLifeformSyncEligible and not eligible then
        Print("[SSBLifeform] Local viewer became ineligible; hiding selector icons")
    end
    self.ssbLifeformSyncEligible = eligible
end

SetMouseVisible = function(self, setVisible)
    PROFILE("GUIScoreboard:SetMouseVisible")
    if self.mouseVisible == setVisible then
        return
    end

    if setVisible then
        local shineGUI = Shine and Shine.GUI
        if shineGUI and shineGUI.EnableMouse then
            self.ssbMouseBackend = "SGUI"
            self.ssbMouseController = shineGUI
            self.ssbMouseController:EnableMouse(true, self)
        else
            self.ssbMouseBackend = "MouseTracker"
            self.ssbMouseController = nil
            MouseTracker_SetIsVisible(true, "ui/Cursor_MenuDefault.dds", true)
        end

        self.mouseVisible = true
        self.updateInterval = kMouseUpdateInterval
        if self.clickForMouseBackground then
            self.clickForMouseBackground:SetIsVisible(false)
        end
        return
    end

    local backend = self.ssbMouseBackend
    if backend == "SGUI" and self.ssbMouseController then
        local controller = self.ssbMouseController
        self.ssbMouseController:EnableMouse(false, self)
    elseif backend == "MouseTracker" then
        MouseTracker_SetIsVisible(false)
    end

    self.mouseVisible = false
    self.updateInterval = self.visible and kVisibleUpdateInterval or kHiddenUpdateInterval
    self.ssbMouseBackend = nil
    self.ssbMouseController = nil
end

local function HandleSlidebarClicked(self, _, mouseY)
    PROFILE("GUIScoreboard:HandleSlidebarClicked")
    if self.slidebarBg:GetIsVisible() and self.isDragging then
        local topPos = (GUIScoreboard.kGameTimeBackgroundSize.y + 6) + 19
        local bottomPos = Client.GetScreenHeight() - (GUIScoreboard.kClickForMouseBackgroundSize.y + 5) - 19
        mouseY = Clamp(mouseY, topPos, bottomPos)
        self.slidePercentage = (mouseY - topPos) / (bottomPos - topPos) * 100
    end
end

local function GetIsVisibleTeam(teamNumber)
    PROFILE("GUIScoreboard:GetIsVisibleTeam")

    -- Check what we can without extra processing
    if localPlayerIsSpectator or teamNumber == kTeamReadyRoom then
        return true
    end

    local localPlayer = Client.GetLocalPlayer()
    if localPlayer then
        local localPlayerTeamNum = localPlayer:GetTeamNumber()
        -- Can see secret information if the player is on the team or is a spectator.
        if localPlayerTeamNum == teamNumber or localPlayerTeamNum == kSpectatorIndex then
            return true
        end
    end

    -- Allow seeing who is commander during pre-game
    if isPreGame then
        return true
    end

    return false
end

function GUIScoreboard:Update_topBarMode()
    PROFILE("GUIScoreboard:Update_topBarMode")

    local topBar = nil
    local vis = self.visible and not self.hiddenOverride
    -- Yes, a bit janky but each "mode" needs different handling
    if PlayerUI_GetIsSpecating() then
        topBar = GetGUIManager():GetGUIScriptSingle("GUIInsight_TopBar")

        if topBar then
            topBar:SetIsVisible(not vis)
        end
    else
        topBar = ClientUI.GetScript("Hud2/topBar/GUIHudTopBarForLocalTeam") -- ToDo: create object for this script at initialization, then get it here

        if topBar then
            topBar:SetIsHiddenOverride(vis)
        end
    end
end

-- Current commander/last-commander info
function GUIScoreboard:Update_TeamsInfo() -- ToDo: Why does this function get all scores etc?
    PROFILE("GUIScoreboard:Update_TeamsInfo")

    local vis = self.visible and not self.hiddenOverride
    local teamGUISize = {}
    local fetchTable = {}
    local now = Shared.GetTime()
    local identityTeams = {}
    local commanderCandidates = {}

    -- PlayerInfoEntity can disappear briefly while a player exits a command
    -- structure. Build one roster-wide snapshot before touching lastComm so a
    -- temporary missing row and overlapping bot/human commander flags cannot
    -- make row iteration order decide commander ownership.
    for _, team in ipairs(self.teams) do
        local scores = team.CurrentScores or team["GetScores"]()
        team.CurrentScores = scores
        for _, player in pairs(scores) do
            local steamId = player and player.SteamId
            if not steamId and player and player.ClientIndex then
                steamId = GetSteamIdForClientIndex(player.ClientIndex)
            end
            local identity = player and GetCommanderIdentity(steamId, player.ClientIndex)
            if identity then
                identityTeams[identity] = team.TeamNumber
                if player.IsCommander and steamId and steamId > 0 and
                        team.TeamNumber ~= kTeamReadyRoom then
                    commanderCandidates[team.TeamNumber] = {
                        identity = identity,
                        name = player.Name,
                        clientIndex = player.ClientIndex,
                        steamId = steamId
                    }
                end
            end
        end
    end

    for _, teamNumber in ipairs({ kMarineTeamType, kAlienTeamType }) do
        local remembered = lastComm[teamNumber]
        local candidate = commanderTrackingActive and commanderCandidates[teamNumber] or nil
        if candidate and remembered ~= candidate.identity then
            lastComm[teamNumber] = candidate.identity
            lastCommLastSeen[teamNumber] = now
        elseif remembered then
            local observedTeam = identityTeams[remembered]
            if observedTeam == teamNumber then
                lastCommLastSeen[teamNumber] = now
            elseif observedTeam ~= nil then
                lastComm[teamNumber] = nil
                lastCommLastSeen[teamNumber] = nil
            elseif now - (lastCommLastSeen[teamNumber] or now) >= 5 then
                lastComm[teamNumber] = nil
                lastCommLastSeen[teamNumber] = nil
            end
        end
    end

    for index, team in ipairs(self.teams) do
        -- Update coms info
        local scores = team.CurrentScores or team["GetScores"]()
        team.CurrentScores = scores
        for _, player in pairs(scores) do
            local steamId = player and player.SteamId
            if not steamId and player and player.ClientIndex then
                steamId = GetSteamIdForClientIndex(player.ClientIndex)
            end
            if steamId then
                if vis and steamId > 0 then table.insert(fetchTable, steamId) end
            end
        end

        -- Update connecting players info
        local numPlayers = table.icount(scores)
        if team.TeamNumber == 0 and numPlayers == 0 and PlayerUI_GetNumConnectingPlayers() > 0 then
            numPlayers = PlayerUI_GetNumConnectingPlayers()
        end

        if vis then -- The heavy parts, updates each player line
            self:UpdateTeam(team, scores)
            if numPlayers > 0 then
                if teamGUISize[team.TeamNumber] == nil then
                    teamGUISize[team.TeamNumber] = {}
                end
                teamGUISize[team.TeamNumber] = self.teams[index].GUIs.Background:GetSize().y
            end
        end

        -- Update self
        if team.TeamNumber == kTeamReadyRoom and numPlayers <= 0 then
            localPlayerIsSpectator = false
        end
    end

    return fetchTable, teamGUISize
end

function GUIScoreboard:Update_GUIElements(deltaTime, contentXSize, contentYSize)
    PROFILE("GUIScoreboard:Update_GUIElements")

    local sizeChanged = false
    if contentXSize ~= kGUIdata.contentXSize or contentYSize ~= kGUIdata.contentYSize then
        kGUIdata.contentXSize = contentXSize
        kGUIdata.contentYSize = contentYSize
        sizeChanged = true
    end

    local displaySpace = Client.GetScreenHeight() - ((GUIScoreboard.kClickForMouseBackgroundSize.y + 5) + (GUIScoreboard.kGameTimeBackgroundSize.y + 6) + 20)

    -- Update game time and server name
    local mapName = Shared.GetMapName()
    local serverName = Client.GetServerIsHidden() and "Hidden" or Client.GetConnectedServerName()

    local gameTime = PlayerUI_GetGameLengthTime()
    local minutes = math.floor(gameTime / 60)
    local seconds = math.floor(gameTime - minutes * 60)

    local gInfo = GetGameInfoEntity()
    local serverPopulation = gInfo and gInfo:GetNumClientsTotal() or 0
    if not gInfo and deltaTime == 0 then
        HPrint("[SSB] Scoreboard opened before GameInfoEntity was available; using population 0")
    end
    local serverPopulationText = serverPopulation == 1 and tostring(serverPopulation) .. " " .. string.lower(Locale.ResolveString("PLAYER")) or tostring(serverPopulation) .. " " .. string.lower(Locale.ResolveString("PLAYERS"))
    local gameTimeText = serverName .. " | " .. serverPopulationText .. " | " .. mapName .. string.format(" - %d:%02d", minutes, seconds)

    if self.ssbGameTimeText ~= gameTimeText then
        self.ssbGameTimeText = gameTimeText
        self.gameTime:SetText(gameTimeText)
        local width = self.gameTime:GetTextWidth(gameTimeText) / 2 + (self.kBlockedIconSize.x + GUIScale(30))
        local widthFavoriteButton = width + (self.kFavoriteIconSize.x + GUIScale(10))
        self.blockedButton:SetPosition(Vector(-width, GUIScale(4), 0))
        self.favoriteButton:SetPosition(Vector(-widthFavoriteButton, GUIScale(4), 0))
    end

    -- Update the favorite button when the scoreboard opens (dt == 0)
    if deltaTime == 0 then
        self.favoriteButton.isServerFavorite = GetServerIsFavorite(self.serverAddress)
        self.favoriteButton:SetTexture(self.favoriteButton.isServerFavorite and self.kFavoriteTexture or self.kNotFavoriteTexture)

        self.blockedButton.isServerBlocked = GetServerIsBlocked(self.serverAddress)
        self.blockedButton:SetTexture(self.blockedButton.isServerBlocked and self.kBlockedTexture or self.kNotBlockedTexture)
    end

    -- Fetch slide bars and display space
    local sliderPos = (self.slidePercentage * self.slidebarBg:GetSize().y / 100)
    if sliderPos < self.slidebar:GetSize().y / 2 then
        sliderPos = 0
    end
    if sliderPos > self.slidebarBg:GetSize().y - self.slidebar:GetSize().y then
        sliderPos = self.slidebarBg:GetSize().y - self.slidebar:GetSize().y
    end

    local showSlidebar = contentYSize > displaySpace
    self.slidebar:SetPosition(Vector(0, sliderPos, 0))
    self.slidebarBg:SetIsVisible(showSlidebar)

    if self.slidePercentage == -1 then
        self.slidePercentage = 0
        local localPlayer = Client.GetLocalPlayer()
        local teamNumber = localPlayer and localPlayer:GetTeamNumber() or kSpectatorIndex
        if showSlidebar and teamNumber ~= kSpectatorIndex and self.centerOnPlayer then
            local player = self.playerHighlightItem:GetParent()
            if player then
                local playerItem = player:GetPosition().y
                local teamItem = player:GetParent() and player:GetParent():GetPosition().y or 0
                local playerPos = playerItem + teamItem + GUIScoreboard.kPlayerItemHeight
                if playerPos > displaySpace then
                    self.slidePercentage = math.max(0, math.min((playerPos / contentYSize * 100), 100))
                end
            else
                HPrint("[SSB] Skipped initial scoreboard centering because the local-player row was unavailable")
            end
        end
    end

    -- Sets game time and background stuff
    if sizeChanged then
        local gameTimeBgYSize = self.gameTimeBackground:GetSize().y
        local gameTimeBgYPos = self.gameTimeBackground:GetPosition().y
        self.gameTimeBackground:SetSize(Vector(contentXSize, gameTimeBgYSize, 0))
        self.gameTimeBackground:SetPosition(Vector(-contentXSize / 2, gameTimeBgYPos, 0))

        local ySize = math.min(displaySpace, contentYSize)
        self.backgroundStencil:SetSize(Vector(contentXSize, ySize - 20, 0))
        self.backgroundStencil:SetPosition(Vector(0, 10, 0))

        self.scoreboardBackground:SetSize(Vector(contentXSize, ySize, 0))
        self.scoreboardBackground:SetPosition(Vector(-contentXSize / 2, -ySize / 2, 0))
    end

    -- Sliding changes independently of content dimensions, so update the
    -- content position even when the cached size remains unchanged.
    local ySize = math.min(displaySpace, contentYSize)
    local slideOffset = -(self.slidePercentage * contentYSize / 100) + (self.slidePercentage * self.slidebarBg:GetSize().y / 100)
    self.background:SetPosition(Vector(0, 10 + (-ySize / 2 + slideOffset), 0))

    self.scoreboardBackground:SetColor(ConditionalValue(showSlidebar, GUIScoreboard.kBgColor, Color(0, 0, 0, 0)))

    if not self.mouseVisible then
        -- Click for mouse only visible when not a commander and when the scoreboard is visible.
        local backgroundColor = PlayerUI_GetTeamColor()
        backgroundColor.a = 0.8
        self.clickForMouseBackground:SetColor(backgroundColor)
    end
end

function GUIScoreboard:Update_toNewSizes(teamGUISize)
    PROFILE("GUIScoreboard:Update_toNewSizes")

    local layoutKey = string.format("%s:%s:%s:%s:%s", ToString(GUIScoreboard.screenWidth),
        ToString(GUIScoreboard.screenHeight), ToString(teamGUISize[0]),
        ToString(teamGUISize[1]), ToString(teamGUISize[2]))
    if self.ssbLayoutKey == layoutKey and self.ssbContentXSize and self.ssbContentYSize then
        return self.ssbContentXSize, self.ssbContentYSize
    end
    self.ssbLayoutKey = layoutKey
    perfCounters.layouts = perfCounters.layouts + 1

    -- Get sizes for everything so we can reposition correctly
    local contentYSize = 0
    local teamItemWidth = self:GetTeamItemWidth() * GUIScoreboard.kScalingFactor
    local teamItemVerticalFormat = teamItemWidth * 2 > GUIScoreboard.screenWidth
    local contentXOffset = (GUIScoreboard.screenWidth - teamItemWidth * 2) / 2
    local contentXExtraOffset = ConditionalValue(GUIScoreboard.screenWidth > 1900, contentXOffset * 0.33, 15 * GUIScoreboard.kScalingFactor)
    local contentXSize = teamItemWidth + contentXExtraOffset * 2
    local contentYSpacing = 20 * GUIScoreboard.kScalingFactor

    if teamGUISize[1] then
        -- If it doesn't fit horizontally or there is only one team put it below
        if teamItemVerticalFormat or not teamGUISize[2] then
            self.teams[2].GUIs.Background:SetPosition(Vector(-teamItemWidth / 2, contentYSize, 0))
            contentYSize = contentYSize + teamGUISize[1] + contentYSpacing
        else
            self.teams[2].GUIs.Background:SetPosition(Vector(-teamItemWidth - contentXOffset / 2 + contentXExtraOffset, contentYSize, 0))
        end
    end
    if teamGUISize[2] then
        -- If it doesn't fit horizontally or there is only one team put it below
        if teamItemVerticalFormat or not teamGUISize[1] then
            self.teams[3].GUIs.Background:SetPosition(Vector(-teamItemWidth / 2, contentYSize, 0))
            contentYSize = contentYSize + teamGUISize[2] + contentYSpacing
        else
            self.teams[3].GUIs.Background:SetPosition(Vector(contentXOffset / 2 - contentXExtraOffset, contentYSize, 0))
        end
    end

    -- If both teams fit horizontally then take only the biggest size
    if teamGUISize[1] and teamGUISize[2] and not teamItemVerticalFormat then
        contentYSize = math.max(teamGUISize[1], teamGUISize[2]) + contentYSpacing * 2
        contentXSize = teamItemWidth * 2 + contentXOffset
    end
    if teamGUISize[0] then
        self.teams[1].GUIs.Background:SetPosition(Vector(-teamItemWidth / 2, contentYSize, 0))
        contentYSize = contentYSize + teamGUISize[0] + contentYSpacing
    end

    local displaySpace = Client.GetScreenHeight() - ((GUIScoreboard.kClickForMouseBackgroundSize.y + 5) + (GUIScoreboard.kGameTimeBackgroundSize.y + 6) + 20)
    local showSlidebar = contentYSize > displaySpace

    self.ssbContentXSize, self.ssbContentYSize = contentXSize, contentYSize
    return contentXSize, contentYSize
end

function GUIScoreboard:Update_SetMainVisibles()
    PROFILE("GUIScoreboard:Update_SetMainVisibles")

    -- Show all the elements the frame after sorting them
    -- so it doesn't appear to shift when we open
    local vis = self.visible and not self.hiddenOverride
    local displayScoreboard = vis and self.slidePercentage > -1 and not self.hiddenOverride
    local isACommander = PlayerUI_IsACommander()

    self.clickForMouseBackground:SetIsVisible(vis and not MouseTracker_GetIsVisible() and not isACommander)
    self.gameTimeBackground:SetIsVisible(displayScoreboard)
    self.gameTime:SetIsVisible(displayScoreboard)
    self.background:SetIsVisible(displayScoreboard)
    self.scoreboardBackground:SetIsVisible(displayScoreboard)

    ---

    if lastScoreboardVisState ~= displayScoreboard then
        lastScoreboardVisState = displayScoreboard
        if vis == false then
            self.updateInterval = kHiddenUpdateInterval
            self.badgeNameTooltip:Hide(0)
        end
    end

    if self.hoverPlayerClientIndex == 0 then
        local containsPoint = GUIItemContainsPoint(self.scoreboardBackground, Client.GetCursorPosScreen())
        if containsPoint then
            self.badgeNameTooltip:Hide(0)
        end
    end

    ---

    if not vis then
        SetMouseVisible(self, false)
        self.slidePercentage = -1
    end

    ---

    if self.hoverMenu.background:GetIsVisible() then
        if not vis then
            self.hoverMenu:Hide()
        end
    elseif not vis then
        -- The lightweight interaction pass owns hover state while visible.
        -- Clearing it from the slower data/presentation pass creates a race
        -- where row clicks intermittently observe client index zero.
        self.hoverPlayerClientIndex = 0
    end

    ---

    for index, team in ipairs(self.teams) do
        local scores = vis and (team.CurrentScores or team["GetScores"]()) or {}
        local numPlayers = table.icount(scores)
        team["GUIs"]["Background"]:SetIsVisible(vis and (numPlayers > 0))
    end

    --

end

function GUIScoreboard:Update(deltaTime)
    PROFILE("GUIScoreboard:Update")

    local vis = self.visible and not self.hiddenOverride
    perfCounters.outer = perfCounters.outer + 1

    if not vis then
        self:Update_SetMainVisibles()
        self:Update_topBarMode()
        return
    end

    self:UpdateMouseInteraction()

    local now = Shared.GetTime()
    local dataRefreshDue = deltaTime == 0 or self.ssbForceDataRefresh or now >= self.ssbNextDataRefresh
    if not dataRefreshDue then
        return
    end
    self.ssbForceDataRefresh = false
    self.ssbNextDataRefresh = now + kVisibleUpdateInterval
    perfCounters.dataRefreshes = perfCounters.dataRefreshes + 1
    UpdateLifeformSyncEligibility(self)

    local gInfo = GetGameInfoEntity()
    local gameState = gInfo and gInfo:GetState()
    isPreGame = (gameState and gameState <= kGameState.PreGame) or false
    if gameState then
        UpdateCommanderRoundState(gameState)
    end

    -- Bypass the vanilla 0.5-second record delay for the local chair state;
    -- every other player field retains the normal cache interval.
    Scoreboard_SyncLocalCommanderState()

    for _, team in ipairs(self.teams) do
        team.CurrentScores = team["GetScores"]()
        perfCounters.teamQueries = perfCounters.teamQueries + 1
    end

    self:Update_SetMainVisibles()

    local fetchTable, teamGUISize = self:Update_TeamsInfo()
    local contentXSize, contentYSize = self:Update_toNewSizes(teamGUISize)

    self:Update_topBarMode()

    fetchPlayerStats(fetchTable)

    self:Update_GUIElements(deltaTime, contentXSize, contentYSize)
    if self.ssbPendingMenuIntegration and self.hoverMenu.background:GetIsVisible() then
        NotifyScoreboardIntegrations("OnMenuOpened", self, self.ssbPendingMenuIntegration)
        self.ssbPendingMenuIntegration = nil
    end

end

local function SetPlayerItemBadges(item, badgeTextures)
    PROFILE("GUIScoreboard:SetPlayerItemBadges")

    assert(#badgeTextures <= #item.BadgeItems)

    local offset = 0

    for i = 1, #item.BadgeItems do
        if badgeTextures[i] ~= nil then
            item.BadgeItems[i]:SetTexture(badgeTextures[i])
            item.BadgeItems[i]:SetIsVisible(true)
        else
            item.BadgeItems[i]:SetIsVisible(false)
        end
    end

    -- now adjust the position of the player name
    local numBadgesShown = math.min(#badgeTextures, #item.BadgeItems)

    offset = numBadgesShown * (kPlayerBadgeIconSize + kPlayerBadgeRightPadding) * GUIScoreboard.kScalingFactor

    return offset
end

local function GetCountByStatus(team, status, partof)
    PROFILE("GUIScoreboard:GetCountByStatus")

    local count = 0
    for index, item in ipairs(team) do
        if partof and string.find(item["Status"], status) then
            count = count + 1
        elseif status == item["Status"] then
            count = count + 1
        end
    end
    return count
end

function GUIScoreboard:UpdateTeam_CommanderName(playerObject, teamObject)
    PROFILE("GUIScoreboard:UpdateTeam_CommanderName")

    -- Commander identity is secret information. The raw commander cache is
    -- intentionally maintained for both teams, but it must only be presented
    -- when vanilla's team-visibility rule permits it.
    if playerObject.isLastComm or playerObject.isCommander then
        teamObject.commRage = false -- Check for Commander Rage quit
        teamObject.teamInfoGUIItem["teamComm"]:SetText(playerObject.playerName)
    end

    if teamObject.isVisibleTeam and not playerObject.isDead and playerObject.teamNumber == kTeam1Index then
        if table.icontains(playerObject.currentTech, kTechId.Jetpack) then
            if playerObject.playerStatus ~= "" and playerObject.playerStatus ~= " " then
                playerObject.playerStatus = string.format("%s/%s", playerObject.playerStatus, Locale.ResolveString("STATUS_JETPACK"))
            else
                playerObject.playerStatus = Locale.ResolveString("STATUS_JETPACK")
            end
        end
        if table.icontains(playerObject.currentTech, kTechId.DualMinigunExosuit) then
            if playerObject.playerStatus ~= "" and playerObject.playerStatus ~= " " then
                playerObject.playerStatus = string.format("%s-%s", playerObject.playerStatus, "Mini")
            else
                playerObject.playerStatus = Locale.ResolveString("HELP_SCREEN_EXO_MINIGUN")
            end
        elseif table.icontains(playerObject.currentTech, kTechId.DualRailgunExosuit) then
            if playerObject.playerStatus ~= "" and playerObject.playerStatus ~= " " then
                playerObject.playerStatus = string.format("%s-%s", playerObject.playerStatus, "Rail")
            else
                playerObject.playerStatus = Locale.ResolveString("HELP_SCREEN_EXO_RAILGUN")
            end
        end
    end

    if (playerObject.isCommander or (playerObject.isLastComm and not playerObject.isBot)) and teamObject.isPlayingTeam then
        if playerObject.comSkillTier > 0 then
            playerObject.playerGUIItem.CommIcon:SetTexturePixelCoordinates(0, (playerObject.comSkillTier + 1) * 32, 32, (playerObject.comSkillTier + 2) * 32)
        else
            playerObject.playerGUIItem.CommIcon:SetTexturePixelCoordinates(0, 0, 32, 32)
        end
        playerObject.playerGUIItem.CommIcon:SetIsVisible(true)
    else
        playerObject.playerGUIItem.CommIcon:SetIsVisible(false)
    end

    playerObject.playerGUIItem["Status"]:SetText(playerObject.playerStatus)
end

function GUIScoreboard:UpdateTeam_UpgradesIcons(playerObject, teamObject)
    PROFILE("GUIScoreboard:UpdateTeam_UpgradesIcons")

    -- Upgrade Icons handle
    -- -- Marines
    local showTech = (teamObject.isVisibleTeam and not playerObject.isDead and playerObject.teamNumber == kTeam1Index)
    if showTech and table.icontains(playerObject.currentTech, kTechId.Welder) then
        playerObject.playerGUIItem.UpgradeIcons["marineWelder"]:SetIsVisible(true)
    else
        playerObject.playerGUIItem.UpgradeIcons["marineWelder"]:SetIsVisible(false)
    end
    playerObject.playerGUIItem.UpgradeIcons["marineGrenadeCluster"]:SetIsVisible(
        showTech and table.icontains(playerObject.currentTech, kTechId.ClusterGrenade))
    playerObject.playerGUIItem.UpgradeIcons["marineGrenadeGas"]:SetIsVisible(
        showTech and table.icontains(playerObject.currentTech, kTechId.GasGrenade))
    playerObject.playerGUIItem.UpgradeIcons["marineGrenadePulse"]:SetIsVisible(
        showTech and table.icontains(playerObject.currentTech, kTechId.PulseGrenade))
    if showTech and table.icontains(playerObject.currentTech, kTechId.Mine) then
        playerObject.playerGUIItem.UpgradeIcons["marineMine"]:SetIsVisible(true)
    else
        playerObject.playerGUIItem.UpgradeIcons["marineMine"]:SetIsVisible(false)
    end

    -- -- Aliens
    local showTech = (teamObject.isVisibleTeam and not playerObject.isDead and playerObject.teamNumber == kTeam2Index)
    if showTech and (table.icontains(playerObject.currentTech, kTechId.Regeneration) or table.icontains(playerObject.currentTech, kTechId.Carapace) or table.icontains(playerObject.currentTech, kTechId.Vampirism)) then
        playerObject.playerGUIItem.UpgradeIcons["alienShell"]:SetIsVisible(true)
        if table.icontains(playerObject.currentTech, kTechId.Regeneration) then
            playerObject.playerGUIItem.UpgradeIcons["alienShell"]:SetTexture(kAlienUpgradesTexture)
            playerObject.playerGUIItem.UpgradeIcons["alienShell"]:SetTexturePixelCoordinates(GUIUnpackCoords({113 * 0, 114 * 0, 113 * 1, 114 * 1}))
        elseif table.icontains(playerObject.currentTech, kTechId.Carapace) then
            playerObject.playerGUIItem.UpgradeIcons["alienShell"]:SetTexture(kAlienUpgradesTexture)
            playerObject.playerGUIItem.UpgradeIcons["alienShell"]:SetTexturePixelCoordinates(GUIUnpackCoords({113 * 1, 114 * 0, 113 * 2, 114 * 1}))
        elseif table.icontains(playerObject.currentTech, kTechId.Vampirism) then
            playerObject.playerGUIItem.UpgradeIcons["alienShell"]:SetTexture(kAlienUpgradesTexture)
            playerObject.playerGUIItem.UpgradeIcons["alienShell"]:SetTexturePixelCoordinates(GUIUnpackCoords({113 * 2, 114 * 0, 113 * 3, 114 * 1}))
        end
    else
        playerObject.playerGUIItem.UpgradeIcons["alienShell"]:SetIsVisible(false)
    end

    if showTech and (table.icontains(playerObject.currentTech, kTechId.Camouflage) or table.icontains(playerObject.currentTech, kTechId.Focus) or table.icontains(playerObject.currentTech, kTechId.Aura)) then
        playerObject.playerGUIItem.UpgradeIcons["alienVeil"]:SetIsVisible(true)
        if table.icontains(playerObject.currentTech, kTechId.Camouflage) then
            playerObject.playerGUIItem.UpgradeIcons["alienVeil"]:SetTexturePixelCoordinates(GUIUnpackCoords({113 * 0, 114 * 1, 113 * 1, 114 * 2}))
        elseif table.icontains(playerObject.currentTech, kTechId.Focus) then
            playerObject.playerGUIItem.UpgradeIcons["alienVeil"]:SetTexturePixelCoordinates(GUIUnpackCoords({113 * 1, 114 * 1, 113 * 2, 114 * 2}))
        elseif table.icontains(playerObject.currentTech, kTechId.Aura) then
            playerObject.playerGUIItem.UpgradeIcons["alienVeil"]:SetTexturePixelCoordinates(GUIUnpackCoords({113 * 2, 114 * 1, 113 * 3, 114 * 2}))
        end
    else
        playerObject.playerGUIItem.UpgradeIcons["alienVeil"]:SetIsVisible(false)
    end
    if showTech and (table.icontains(playerObject.currentTech, kTechId.Adrenaline) or table.icontains(playerObject.currentTech, kTechId.Celerity) or table.icontains(playerObject.currentTech, kTechId.Crush)) then
        playerObject.playerGUIItem.UpgradeIcons["alienSpur"]:SetIsVisible(true)
        if table.icontains(playerObject.currentTech, kTechId.Adrenaline) then
            playerObject.playerGUIItem.UpgradeIcons["alienSpur"]:SetTexturePixelCoordinates(GUIUnpackCoords({113 * 0, 114 * 2, 113 * 1, 114 * 3}))
        elseif table.icontains(playerObject.currentTech, kTechId.Celerity) then
            playerObject.playerGUIItem.UpgradeIcons["alienSpur"]:SetTexturePixelCoordinates(GUIUnpackCoords({113 * 1, 114 * 2, 113 * 2, 114 * 3}))
        elseif table.icontains(playerObject.currentTech, kTechId.Crush) then
            playerObject.playerGUIItem.UpgradeIcons["alienSpur"]:SetTexturePixelCoordinates(GUIUnpackCoords({113 * 2, 114 * 2, 113 * 3, 114 * 3}))
        end
    else
        playerObject.playerGUIItem.UpgradeIcons["alienSpur"]:SetIsVisible(false)
    end
end

function GUIScoreboard:UpdateTeam_HighlightCurrentPlayer(playerObject, teamObject)
    PROFILE("GUIScoreboard:UpdateTeam_HighlightCurrentPlayer")

    -- Handle local player highlight
    if ScoreboardUI_IsPlayerLocal(playerObject["playerName"]) then
        if self.playerHighlightItem:GetParent() ~= playerObject.playerGUIItem["Background"] then
            if self.playerHighlightItem:GetParent() ~= nil then
                self.playerHighlightItem:GetParent():RemoveChild(self.playerHighlightItem)
            end
            playerObject.playerGUIItem["Background"]:AddChild(self.playerHighlightItem)
            self.playerHighlightItem:SetIsVisible(true)
            self.playerHighlightItem:SetColor(teamObject.localPlayerHighlightColor)
        end
    end
end

function GUIScoreboard:UpdateTeam_PlayersPlaceAndName(playerObject, badgeTextures, badgeNames)
    PROFILE("GUIScoreboard:UpdateTeam_PlayersPlaceAndName")

    -- New scoreboard positioning
    local numberSize = 0
    if playerObject.playerGUIItem["Number"]:GetIsVisible() then
        numberSize = kPlayerNumberWidth
    end

    local statusPos = ConditionalValue(GUIScoreboard.screenWidth < 1280, GUIScoreboard.kPlayerItemWidth + 30, (self:GetTeamItemWidth() - GUIScoreboard.kTeamColumnSpacingX * 10) + 60)
    local playerStatus = playerObject.playerGUIItem["Status"]:GetText()

    local isQueueStatus = string.match(playerStatus or "", "^Queue: %d+$") ~= nil
    if playerStatus == "-" or (not isQueueStatus and playerStatus ~= Locale.ResolveString("STATUS_SPECTATOR") and playerObject["teamNumber"] ~= kTeam1Index and playerObject["teamNumber"] ~= kTeam2Index) then
        playerObject.playerGUIItem["Status"]:SetText("")
        statusPos = statusPos + GUIScoreboard.kTeamColumnSpacingX * ConditionalValue(GUIScoreboard.screenWidth < 1280, 2.75, 1.75)
    end

    badgeTextures = badgeTextures or Badges_GetBadgeTextures(playerObject["clientIndex"], "scoreboard")
    playerObject.playerGUIItem.SSBBadgeNames = badgeNames
    SetPlayerItemBadges(playerObject.playerGUIItem, badgeTextures)

    -- Badges sit right of the name: [number] name [badges] ... [icons][tier].
    local badgeItems = playerObject.playerGUIItem["BadgeItems"]
    local numBadges = math.min(#badgeTextures, #badgeItems)
    local nameItem = playerObject.playerGUIItem["Name"]
    local nameX = (numberSize + kPlayerItemLeftMargin) * GUIScoreboard.kScalingFactor
    nameItem:SetPosition(Vector(nameX, 0, 0))

    -- Status icons stack leftwards from the tier emblem; pos ends as the
    -- leftmost visible icon, which is the right wall for name + badges.
    local pos = playerObject.playerGUIItem.SkillIcon:GetPosition().x
    for _, icon in ipairs(playerObject.playerGUIItem["IconTable"]) do
        if icon:GetIsVisible() then
            local iconSize = icon:GetSize()
            pos = pos - iconSize.x
            icon:SetPosition(Vector(pos, (-iconSize.y / 2), 0))
        end
    end

    local gap = kPlayerBadgeRightPadding * GUIScoreboard.kScalingFactor
    local badgeStep = (kPlayerBadgeIconSize + kPlayerBadgeRightPadding) * GUIScoreboard.kScalingFactor

    local finalName = nameItem:GetText()
    -- GUIMakeFontScale swaps to a larger font and shrinks the item scale at high res,
    -- so drawn width is GetTextWidth * item scale, not * kScalingFactor.
    local textScale = nameItem:GetScale().x
    local finalNameWidth = nameItem:GetTextWidth(finalName) * textScale
    local dotsWidth = nameItem:GetTextWidth("...") * textScale

    -- Shorten the name first; the minimum truncated length also includes the "..."
    while nameX + finalNameWidth + gap + numBadges * badgeStep > pos and string.UTF8Length(finalName) > kMinTruncatedNameLength do
        finalName = string.UTF8Sub(finalName, 1, string.UTF8Length(finalName) - 1)
        finalNameWidth = (nameItem:GetTextWidth(finalName) * textScale) + dotsWidth
        nameItem:SetText(finalName .. "...")
    end

    -- Name is at its minimum and the row still overflows: drop badges from the end.
    local shownBadges = numBadges
    while shownBadges > 0 and nameX + finalNameWidth + gap + shownBadges * badgeStep > pos do
        shownBadges = shownBadges - 1
    end

    local badgeX = nameX + finalNameWidth + gap
    for i = 1, #badgeItems do
        if i <= shownBadges then
            badgeItems[i]:SetPosition(Vector(badgeX + (i - 1) * badgeStep, -kPlayerBadgeIconSize / 2 * GUIScoreboard.kScalingFactor, 0))
        else
            badgeItems[i]:SetIsVisible(false)
        end
    end
end

local loggedCommanderInsigniaSkips = {}

local function UpdateCommanderInsignia(playerObject)
    local insignia = playerObject.playerGUIItem.CommInsignia
    if not insignia then return end
    local special = CheckForSpecialBadgeRecipient(playerObject.steamId)
    if playerObject.isBot or not playerObject.hasCommanderSkill or special then
        insignia:SetIsVisible(false)
        if special and playerObject.steamId and not loggedCommanderInsigniaSkips[playerObject.steamId] then
            loggedCommanderInsigniaSkips[playerObject.steamId] = true
            Print("[SSB] Commander insignia hidden for special badge recipient steamId=%s",
                ToString(playerObject.steamId))
        end
        return
    end
    local iconIndex = playerObject.comSkillTier + 2
    insignia:SetPosition(playerObject.playerGUIItem.SkillIcon:GetPosition())
    insignia:SetSize(playerObject.playerGUIItem.SkillIcon:GetSize())
    insignia:SetTexture(kPlayerCommanderSkillIconTexture)
    insignia:SetTexturePixelCoordinates(0, iconIndex * 32, 100, (iconIndex + 1) * 32 - 1)
    insignia:SetIsVisible(true)
end

function GUIScoreboard:UpdateTeam_SkillIcons(playerObject)
    PROFILE("GUIScoreboard:UpdateTeam_SkillIcons")

    -- Set player skill icon
    local skillIconOverrideSettings = CheckForSpecialBadgeRecipient(playerObject.steamId)
    if skillIconOverrideSettings then
        -- User has a special skill-tier icon tied to their steam Id.

        -- Reset the skill icon's texture coordinates to the default normalized coordinates (0, 0), (1, 1).
        -- The shader depends on them being this way.
        playerObject.playerGUIItem.SkillIcon:SetTextureCoordinates(0, 0, 1, 1)

        -- Change the skill icon's shader to the one that will animate.
        playerObject.playerGUIItem.SkillIcon:SetShader(skillIconOverrideSettings.shader)
        playerObject.playerGUIItem.SkillIcon:SetTexture(skillIconOverrideSettings.tex)
        playerObject.playerGUIItem.SkillIcon:SetFloatParameter("frameCount", skillIconOverrideSettings.frameCount)

        -- Change the size so it doesn't touch the weapon name text.
        playerObject.playerGUIItem.SkillIcon:SetSize(kPlayerSkillIconSizeOverride * GUIScoreboard.kScalingFactor)

        -- Change the tooltip of the skill icon.
        playerObject.playerGUIItem.SkillIcon.tooltipText = skillIconOverrideSettings.tooltip
    else
        -- User has no special skill-tier icon.

        -- Reset the shader and texture back to the default one.
        playerObject.playerGUIItem.SkillIcon:SetShader("shaders/GUIBasic.surface_shader")
        playerObject.playerGUIItem.SkillIcon:SetTexture(kPlayerSkillIconTexture)
        playerObject.playerGUIItem.SkillIcon:SetSize(kPlayerSkillIconSize * GUIScoreboard.kScalingFactor)

        playerObject.playerGUIItem.SkillIcon.tooltipText = string.format(Locale.ResolveString("SKILLTIER_TOOLTIP"), Locale.ResolveString(playerObject.playerSkillTierName), playerObject.playerSkillTier)

        local iconIndex = playerObject.playerSkillTier + 2
        playerObject.playerGUIItem.SkillIcon:SetTexturePixelCoordinates(0, iconIndex * 32, 100, (iconIndex + 1) * 32 - 1)
    end

    if playerObject["isBot"] then
        playerObject.playerGUIItem.SkillIcon.tooltipText = "NS2 Bot"
    else
        playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. string.format("\nSkill: %.0f", (playerObject.playerSkill))
        if playerObject.isSpectator or playerObject["isMarine"] or isPreGame then
            playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. "\nMarine: " .. tostring(playerObject.marineSkill)
        end
        if playerObject.isSpectator or playerObject["isAlien"] or isPreGame then
            playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. "\nAlien: " .. tostring(playerObject.alienSkill)
        end
        playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. "\n"
        if playerObject.isSpectator or playerObject.isLastComm or isPreGame then
            playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. "\nCom Tier: " .. Locale.ResolveString(playerObject.comSkillTierName) .. " (" .. tostring(playerObject.comSkillTier) .. ")"
        end
        if playerObject.isSpectator or playerObject.isLastComm or isPreGame then
            playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. string.format("\nCom Skill: %.0f", (playerObject.playerCommSkill))
        end
        if playerObject.isSpectator or (playerObject.isLastComm and playerObject["isMarine"]) or isPreGame then
            playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. "\nMarine: " .. tostring(playerObject.marineCommSkill)
        end
        if playerObject.isSpectator or (playerObject.isLastComm and playerObject["isAlien"]) or isPreGame then
            playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. "\nAlien: " .. tostring(playerObject.alienCommSkill)
        end
        if playerObject.isSpectator or playerObject.isLastComm or isPreGame then
            playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. "\n"
        end
    end

    local stats = playerObject["playerTooltipData"]
    if not playerObject["isBot"] and (not stats or stats.state == "pending") then
        playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. "\nRequesting NS2Stats data..."
    elseif not playerObject["isBot"] and stats and (stats.state == "missing" or stats.state == "failed") then
        playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. "\nNo NS2Stats data!"
    elseif not playerObject["isBot"] and stats and stats.state == "ready" then
        playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. "\nKDR:"
        if (playerObject["isSpectator"] or playerObject["isMarine"] or isPreGame) and IsNumber(stats.marine_kdr) then
            playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. " M " .. string.format("%.2f", stats.marine_kdr)
        end
        if (playerObject["isSpectator"] or playerObject["isAlien"] or isPreGame) and IsNumber(stats.alien_kdr) then
            playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. " A " .. string.format("%.2f", stats.alien_kdr)
        end
        playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. "\nAccuracy:"
        if (playerObject["isSpectator"] or playerObject["isMarine"] or isPreGame) and IsNumber(stats.marine_accuracy) then
            playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. " M " .. tostring(round(stats.marine_accuracy, 0))
        end
        if (playerObject["isSpectator"] or playerObject["isAlien"] or isPreGame) and IsNumber(stats.alien_accuracy) then
            playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. " A " .. tostring(round(stats.alien_accuracy, 0))
        end
        playerObject.playerGUIItem.SkillIcon.tooltipText = playerObject.playerGUIItem.SkillIcon.tooltipText .. "\nProvided by MaNGA NS2 Stats"
        stats.toolTip = playerObject.playerGUIItem.SkillIcon.tooltipText
    end
    UpdateCommanderInsignia(playerObject)
end

function GUIScoreboard:UpdateTeam_StatsValues(playerObject, teamObject)
    PROFILE("GUIScoreboard:UpdateTeam_StatsValues")

    local resourcesStr = ConditionalValue(teamObject["isVisibleTeam"], tostring(math.floor(playerObject["resources"] * 10) / 10), "-")

    local deadString = Locale.ResolveString("STATUS_DEAD")

    local score = tostring(playerObject["score"])
    if (playerObject["isCommander"] or (playerObject["isLastComm"] and not playerObject["isBot"])) and teamObject["isPlayingTeam"] then
        score = "*"
    end

    if teamObject["isPlayingTeam"] then
        playerObject.playerGUIItem["Score"]:SetText(score)
        playerObject.playerGUIItem["Kills"]:SetText(tostring(playerObject["kills"]))
        playerObject.playerGUIItem["Assists"]:SetText(tostring(playerObject["assists"]))
        playerObject.playerGUIItem["Deaths"]:SetText(tostring(playerObject["deaths"]))
        playerObject.playerGUIItem["Resources"]:SetText(resourcesStr)
    end
    -- player["Status"]:SetText(playerStatus)
    playerObject.playerGUIItem["Ping"]:SetText(tostring(playerObject["ping"]))

    playerObject.playerGUIItem["Score"]:SetIsVisible(teamObject["isPlayingTeam"])
    playerObject.playerGUIItem["Kills"]:SetIsVisible(teamObject["isPlayingTeam"])
    playerObject.playerGUIItem["Assists"]:SetIsVisible(teamObject["isPlayingTeam"])
    playerObject.playerGUIItem["Deaths"]:SetIsVisible(teamObject["isPlayingTeam"])
    playerObject.playerGUIItem["Resources"]:SetIsVisible(teamObject["isPlayingTeam"])

    local white = GUIScoreboard.kWhiteColor
    local baseColor, nameColor, statusColor = white, white, white

    if playerObject["isDead"] and teamObject["isVisibleTeam"] then
        nameColor, statusColor = kDeadColor, kDeadColor
    end

    playerObject.playerGUIItem["Score"]:SetColor(baseColor)
    playerObject.playerGUIItem["Kills"]:SetColor(baseColor)
    playerObject.playerGUIItem["Assists"]:SetColor(baseColor)
    playerObject.playerGUIItem["Deaths"]:SetColor(baseColor)
    playerObject.playerGUIItem["Status"]:SetColor(statusColor)

    playerObject.playerGUIItem["Name"]:SetColor(nameColor)

    -- resource color
    if resourcesStr then
        local resourcesNumber = tonumber(resourcesStr)
        if resourcesNumber == nil then -- necessary at gamestart with bots
            resourcesNumber = 0
        end
        if resourcesNumber < GUIScoreboard.kHighPresThreshold then
            playerObject.playerGUIItem["Resources"]:SetColor(baseColor)
        elseif resourcesNumber >= GUIScoreboard.kMaxPresThreshold then
            playerObject.playerGUIItem["Resources"]:SetColor(GUIScoreboard.kMaxPresColor)
        elseif resourcesNumber >= GUIScoreboard.kVeryHighPresThreshold then
            playerObject.playerGUIItem["Resources"]:SetColor(GUIScoreboard.kVeryHighPresColor)
        else
            playerObject.playerGUIItem["Resources"]:SetColor(GUIScoreboard.kHighPresColor)
        end
    else
        playerObject.playerGUIItem["Resources"]:SetColor(baseColor)
    end

    if playerObject["ping"] < GUIScoreboard.kLowPingThreshold then
        playerObject.playerGUIItem["Ping"]:SetColor(GUIScoreboard.kLowPingColor)
    elseif playerObject["ping"] < GUIScoreboard.kMedPingThreshold then
        playerObject.playerGUIItem["Ping"]:SetColor(GUIScoreboard.kMedPingColor)
    elseif playerObject["ping"] < GUIScoreboard.kHighPingThreshold then
        playerObject.playerGUIItem["Ping"]:SetColor(GUIScoreboard.kHighPingColor)
    else
        playerObject.playerGUIItem["Ping"]:SetColor(GUIScoreboard.kInsanePingColor)
    end

end

function GUIScoreboard:UpdateTeam_BackgroundColor(playerObject, teamObject)
    PROFILE("GUIScoreboard:UpdateTeam_BackgroundColor")

    local color = Color(0.5, 0.5, 0.5, 1)
    if playerObject["isCommander"] or (playerObject["isLastComm"] and not playerObject["isBot"]) then
        color = GUIScoreboard.kCommanderFontColor * 0.8
    else
        color = teamObject["teamColor"] * 0.8
    end

    local item = playerObject.playerGUIItem
    item.SSBClientIndex = playerObject.clientIndex
    item.SSBSteamId = playerObject.steamId
    -- Tooltips use actual entity-team spectator status, not the combined
    -- Ready Room/spectator presentation section.
    item.SSBIsSpectator = playerObject.isQueueSpectator
    item.SSBBaseBackgroundColor = ConditionalValue(playerObject.isCommander,
        playerObject.commanderColor, teamObject.teamColor)
    item.SSBHoverBackgroundColor = color
    local backgroundKey = string.format("%s:%s:%s", ToString(playerObject.isCommander),
        ToString(playerObject.isLastComm), ToString(teamObject.teamNumber))
    if item.SSBBackgroundKey ~= backgroundKey then
        item.SSBBackgroundKey = backgroundKey
        item.Background:SetColor(item.SSBBaseBackgroundColor)
        perfCounters.backgroundChanged = perfCounters.backgroundChanged + 1
    else
        perfCounters.backgroundSkipped = perfCounters.backgroundSkipped + 1
    end
end
local function GetHoverSkillTooltip(item)
    local skillIcon = item.SkillIcon
    local description = skillIcon.SSBCanonicalTooltipText or skillIcon.tooltipText
    return SSB_AppendEnhancedTooltip and
        SSB_AppendEnhancedTooltip(description, item.SSBSteamId, item.SSBIsSpectator) or description
end

function GUIScoreboard:UpdateMouseInteraction()
    PROFILE("GUIScoreboard:UpdateMouseInteraction")
    perfCounters.interactionTicks = perfCounters.interactionTicks + 1

    -- Another UI must not anonymously decrement SGUI's global ownership, but
    -- recover safely if legacy code does so during map-load startup. Rebuild
    -- both SGUI bookkeeping and its cursor entry when the count was erased;
    -- never leave a raw MouseTracker push that SGUI cannot later release.
    if self.mouseVisible and not MouseTracker_GetIsVisible() then
        local controller = self.ssbMouseController
        local mouseObjects = controller and controller.MouseObjects or -1
        if self.ssbMouseBackend == "SGUI" and controller and mouseObjects <= 0 then
            -- The stale identity would make EnableMouse(true, self) a no-op.
            controller.MouseEnabledControls[self] = nil
            controller:EnableMouse(true, self)
            Print("%s", string.format(
                "[SSBMouse] recovered missing cursor by rebuilding SGUI registration mouse_before=%d mouse_after=%d",
                mouseObjects, controller.MouseObjects or 0))
        elseif self.ssbMouseBackend == "SGUI" and controller then
            -- SGUI still has logical owners, so restore its one shared
            -- underlying cursor entry. The final SGUI owner will pop it.
            MouseTracker_SetIsVisible(true, "ui/Cursor_MenuDefault.dds", true)
            Print("%s", string.format(
                "[SSBMouse] recovered missing cursor under active SGUI ownership mouse_objects=%d",
                mouseObjects))
        else
            MouseTracker_SetIsVisible(true, "ui/Cursor_MenuDefault.dds", true)
            Print("[SSBMouse] recovered missing cursor through MouseTracker fallback")
        end
    end

    local mouseX, mouseY = Client.GetCursorPosScreen()
    if self.badgeNameTooltip:GetShown() and
            not GUIItemContainsPoint(self.scoreboardBackground, mouseX, mouseY) then
        self.badgeNameTooltip:Hide()
    end
    if self.mousePressed["LMB"]["Down"] and self.isDragging then
        HandleSlidebarClicked(self, mouseX, mouseY)
        if self.ssbContentYSize then
            local displaySpace = Client.GetScreenHeight() - ((GUIScoreboard.kClickForMouseBackgroundSize.y + 5) +
                (GUIScoreboard.kGameTimeBackgroundSize.y + 6) + 20)
            local ySize = math.min(displaySpace, self.ssbContentYSize)
            local slideOffset = -(self.slidePercentage * self.ssbContentYSize / 100) +
                (self.slidePercentage * self.slidebarBg:GetSize().y / 100)
            self.background:SetPosition(Vector(0, 10 + (-ySize / 2 + slideOffset), 0))
        end
    end

    -- Cursor availability and SSB cursor ownership are deliberately separate.
    -- Commander/overhead spectator modes already provide a MouseTracker cursor
    -- that must support scoreboard hover without SSB acquiring or releasing it.
    if not MouseTracker_GetIsVisible() or self.hoverMenu.background:GetIsVisible() or MainMenu_GetIsOpened() then
        return
    end

    local hoveredItem
    local hoverTooltipText
    local hoverTooltipSteamId
    local canHighlight = true
    for _, team in ipairs(self.teams) do
        for _, item in ipairs(team.PlayerList) do
            if item.Background:GetIsVisible() and GUIItemContainsPoint(item.Background, mouseX, mouseY) then
                hoveredItem = item
                for _, icon in ipairs(item.IconTable) do
                    if icon.SSBTooltipText and icon:GetIsVisible() and GUIItemContainsPoint(icon, mouseX, mouseY) then
                        hoverTooltipText = icon.SSBTooltipText
                        hoverTooltipSteamId = item.SSBSteamId
                    end
                    if icon:GetIsVisible() and GUIItemContainsPoint(icon, mouseX, mouseY) and not icon.allowHighlight then
                        canHighlight = false
                        break
                    end
                end
                for i = 1, #item.BadgeItems do
                    local badgeItem = item.BadgeItems[i]
                    if badgeItem:GetIsVisible() and GUIItemContainsPoint(badgeItem, mouseX, mouseY) then
                        local badgeNames = item.SSBBadgeNames or {}
                        hoverTooltipText = GetBadgeFormalName(ToString(badgeNames[i]))
                        hoverTooltipSteamId = item.SSBSteamId
                        break
                    end
                end
                if item.SkillIcon:GetIsVisible() and GUIItemContainsPoint(item.SkillIcon, mouseX, mouseY) then
                    hoverTooltipText = GetHoverSkillTooltip(item)
                    hoverTooltipSteamId = item.SSBSteamId
                end
                break
            end
        end
        if hoveredItem then break end
    end

    local hoverChanged = self.ssbHoveredPlayerItem ~= hoveredItem or
        self.ssbHoveredCanHighlight ~= canHighlight
    if hoverChanged then
        if self.ssbHoveredPlayerItem and self.ssbHoveredPlayerItem.SSBBaseBackgroundColor then
            self.ssbHoveredPlayerItem.Background:SetColor(self.ssbHoveredPlayerItem.SSBBaseBackgroundColor)
        end
        self.ssbHoveredPlayerItem = hoveredItem
        self.ssbHoveredCanHighlight = canHighlight
    end
    if hoveredItem and canHighlight then
        self.hoverPlayerClientIndex = hoveredItem.SSBClientIndex or 0
        if hoverChanged then hoveredItem.Background:SetColor(hoveredItem.SSBHoverBackgroundColor) end
    else
        self.hoverPlayerClientIndex = 0
    end
    if hoverTooltipText then
        if self.ssbHoverTooltipText ~= hoverTooltipText then
            self.badgeNameTooltip:SetText(hoverTooltipText)
            self.ssbHoverTooltipText = hoverTooltipText
        end
        if not self.badgeNameTooltip:GetShown() then self.badgeNameTooltip:Show() end
        self.ssbHoverTooltipSteamId = hoverTooltipSteamId
    elseif self.badgeNameTooltip:GetShown() then
        self.badgeNameTooltip:Hide()
        self.ssbHoverTooltipText = nil
        self.ssbHoverTooltipSteamId = nil
    end

    self.favoriteButton:SetColor(GUIItemContainsPoint(self.favoriteButton, mouseX, mouseY) and
        kFavoriteMouseOverColor or kFavoriteColor)
    self.blockedButton:SetColor(GUIItemContainsPoint(self.blockedButton, mouseX, mouseY) and
        kBlockedMouseOverColor or kBlockedColor)
end

local function UpdateTeamVoiceControl(updateTeam)
    local icon = updateTeam.GUIs.TeamVoiceMute
    local teamName = updateTeam.GUIs.TeamName
    if not icon or not teamName then return end
    local muted = SSB_GetTeamVoiceMuted and SSB_GetTeamVoiceMuted(updateTeam.TeamNumber) or false
    local scalingFactor = GUIScoreboard.kScalingFactor
    local teamNamePosition = teamName:GetPosition()
    local teamNameScale = teamName:GetScale()
    local teamNameRight = teamNamePosition.x +
        teamName:GetTextWidth(teamName:GetText()) * teamNameScale.x
    local headerRight = teamNameRight
    local teamSkill = updateTeam.GUIs.TeamSkill
    if teamSkill and teamSkill:GetIsVisible() then
        local position, size = teamSkill:GetPosition(), teamSkill:GetSize()
        headerRight = math.max(headerRight, position.x + size.x)
    end
    local iconX = headerRight + kTeamVoiceIconSafetyGap * scalingFactor
    icon:SetTexture(muted and kTeamVoiceMutedTexture or kTeamVoiceUnmutedTexture)
    icon:SetPosition(Vector(iconX, 8 * scalingFactor, 0))
    icon:SetIsVisible(IsLocalClientSpectator() and
        updateTeam.GUIs.Background:GetIsVisible())
end

local function UpdatePlayerLifeformIcon(playerObject)
    local icon = playerObject.playerGUIItem.LifeformIcon
    if not icon then return end

    local stats = playerObject.playerTooltipData
    local baseline = NormalizeSelectorLifeform(stats and stats.main_lifeform) or "Onos"
    local manual = SSB_GetLifeformSelection and SSB_GetLifeformSelection(playerObject.steamId) or nil
    local normalizedManual = NormalizeSelectorLifeform(manual)
    local hasManualSelection = normalizedManual ~= nil
    local selected = normalizedManual or baseline
    local visible = GetLifeformViewerEligible() and playerObject.isAlien and
        playerObject.steamId and playerObject.steamId > 0
    local atlas = hasManualSelection and kLifeformAtlas2 or kLifeformAtlas1
    local atlasIndex = kLifeformAtlasIndex[selected] or kLifeformAtlasIndex.Onos

    if DirtyValuesChanged(playerObject.playerGUIItem, "SSBLifeformValues",
            playerObject.steamId, playerObject.teamNumber, visible, baseline, selected,
            hasManualSelection, atlas) then
        icon:SetTexture(atlas)
        icon:SetTexturePixelCoordinates(atlasIndex * 64, 0, (atlasIndex + 1) * 64, 64)
        icon:SetIsVisible(visible)
        icon.SSBLifeform = selected
        icon.SSBLifeformBaseline = baseline
        icon.SSBSteamId = playerObject.steamId
    end
end

function GUIScoreboard:UpdateTeam(updateTeam, currentScores)
    PROFILE("GUIScoreboard:UpdateTeam")

    local teamObject = {}
    teamObject.teamGUIItem = updateTeam["GUIs"]["Background"]
    teamObject.teamNameGUIItem = updateTeam["GUIs"]["TeamName"]
    teamObject.teamSkillGUIItem = updateTeam["GUIs"]["TeamSkill"]
    teamObject.teamInfoGUIItem = updateTeam["GUIs"]["TeamInfo"]
    teamObject.teamNameText = Locale.ResolveString(string.format("NAME_TEAM_%s", updateTeam["TeamNumber"]))
    teamObject.teamColor = updateTeam["Color"]
    teamObject.localPlayerHighlightColor = updateTeam["HighlightColor"]
    teamObject.playerList = updateTeam["PlayerList"]
    teamObject.teamScores = currentScores or updateTeam.CurrentScores or updateTeam["GetScores"]()
    teamObject.teamNumber = updateTeam["TeamNumber"]
    teamObject.isPlayingTeam = teamObject.teamNumber ~= kTeamReadyRoom

    -- Determines if the local player can see secret information
    -- for this team.
    teamObject.isVisibleTeam = GetIsVisibleTeam(teamObject.teamNumber)
    teamObject.isSpectator, teamObject.isMarine, teamObject.isAlien = teamObject.teamNumber == kNeutralTeamType, teamObject.teamNumber == kMarineTeamType, teamObject.teamNumber == kAlienTeamType

    -- How many items per player.
    teamObject.numPlayers = table.icount(teamObject.teamScores)

    -- If we are throttline GUI updates
    local throttlePerformUpdates = guiThrottleTime[teamObject.teamNumber] and Shared.GetTime() > guiThrottleTime[teamObject.teamNumber] or false
    if throttlePerformUpdates then
        guiThrottleTime[teamObject.teamNumber] = Shared.GetTime() + guiThrottleInterval
    end

    -- Update the team name text.
    local playersOnTeamText = string.format("%d %s", teamObject.numPlayers, teamObject.numPlayers == 1 and Locale.ResolveString("SB_PLAYER") or Locale.ResolveString("SB_PLAYERS"))
    local teamHeaderText

    if not teamObject.isPlayingTeam then
        -- Ready Room (x Players, y Queue, z Connecting, a Spectators). Players are
        -- Ready Room team entities; Queue/Spectators split true spectators by
        -- whether they hold a player-slot queue position. Counts come from the
        -- unfiltered section, so hidden spectator rows are still counted.
        -- Zero counts are omitted; all-zero falls through to the default header.
        local parts = {}
        if ssbSectionReadyRoomCount > 0 then
            parts[#parts + 1] = string.format("%d %s", ssbSectionReadyRoomCount,
                ssbSectionReadyRoomCount == 1 and Locale.ResolveString("SB_PLAYER") or Locale.ResolveString("SB_PLAYERS"))
        end
        if ssbSectionQueueCount > 0 then parts[#parts + 1] = string.format("%d Queue", ssbSectionQueueCount) end
        local numPlayersConnecting = PlayerUI_GetNumConnectingPlayers()
        if numPlayersConnecting > 0 then
            parts[#parts + 1] = string.format("%d %s", numPlayersConnecting, Locale.ResolveString("SB_CONNECTING"))
        end
        if ssbSectionSpectatorCount > 0 then parts[#parts + 1] = string.format("%d Spectators", ssbSectionSpectatorCount) end
        if #parts > 0 then
            teamHeaderText = string.format("%s (%s)", teamObject.teamNameText, table.concat(parts, ", "))
        end
    end

    if not teamHeaderText then
        teamHeaderText = string.format("%s (%s)", teamObject.teamNameText, playersOnTeamText)
    end
    -- "[muted by v/t]": only on the local player's own playing team during a
    -- started game, and only when either count is non-zero.
    if SSB_GetMutedByCounts and (teamObject.isMarine or teamObject.isAlien) and
            not IsLocalClientSpectator() and teamObject.teamNumber == PlayerUI_GetTeamNumber() then
        local gameInfo = GetGameInfoEntity()
        if gameInfo and gameInfo:GetGameStarted() then
            local mutedByVoice, mutedByText = SSB_GetMutedByCounts()
            if mutedByVoice > 0 or mutedByText > 0 then
                teamHeaderText = string.format("%s [muted by %d/%d]", teamHeaderText, mutedByVoice, mutedByText)
            end
        end
    end
    if SSB_AppendEnhancedTeamSkill then
        teamHeaderText = SSB_AppendEnhancedTeamSkill(teamHeaderText, teamObject.teamNumber)
    end

    local teamResourcesString = ""
    if teamObject.isPlayingTeam then
        teamResourcesString = ConditionalValue(teamObject.isVisibleTeam,
            string.format(Locale.ResolveString("SB_TEAM_RES"), ScoreboardUI_GetTeamResources(teamObject.teamNumber)), "")
    end

    if DirtyValuesChanged(updateTeam, "SSBTeamValues", teamHeaderText, teamResourcesString,
            lastComm[teamObject.teamNumber] ~= nil, teamObject.isPlayingTeam,
            teamObject.isVisibleTeam, teamObject.numPlayers, GUIScoreboard.kScalingFactor) then
        teamObject.teamNameGUIItem:SetText(teamHeaderText)
        if teamObject.isPlayingTeam then
            teamObject.teamInfoGUIItem["teamRes"]:SetText(teamResourcesString)
            local showCommander = teamObject.isVisibleTeam and lastComm[teamObject.teamNumber] ~= nil
            local visibilityKey = string.format("%s:%s:%s", ToString(teamObject.isVisibleTeam),
                ToString(lastComm[teamObject.teamNumber] ~= nil), ToString(showCommander))
            if commanderVisibilityState[teamObject.teamNumber] ~= visibilityKey then
                commanderVisibilityState[teamObject.teamNumber] = visibilityKey
                Print("[SSBCommanderPrivacy] team=%s visible=%s cached=%s displayed=%s",
                    ToString(teamObject.teamNumber), ToString(teamObject.isVisibleTeam),
                    ToString(lastComm[teamObject.teamNumber] ~= nil), ToString(showCommander))
            end
            if showCommander then
                teamObject.teamInfoGUIItem["teamCommIcon"]:SetColor(RGBAtoColor(255, 255, 255, 1))
            else
                teamObject.teamInfoGUIItem["teamComm"]:SetText(Locale.ResolveString("NO_COMMANDER"))
                teamObject.teamInfoGUIItem["teamCommIcon"]:SetColor(RGBAtoColor(255, 50, 50, 1))
            end
        end
        teamObject.teamGUIItem:SetSize(Vector(self:GetTeamItemWidth(), (GUIScoreboard.kTeamItemHeight) +
            ((GUIScoreboard.kPlayerItemHeight + GUIScoreboard.kPlayerSpacing) * teamObject.numPlayers), 0) *
            GUIScoreboard.kScalingFactor)
        perfCounters.teamChanged = perfCounters.teamChanged + 1
    else
        perfCounters.teamSkipped = perfCounters.teamSkipped + 1
    end

    -- Resize the player list if it doesn't match.
    if table.icount(teamObject.playerList) ~= teamObject.numPlayers then
        self:ResizePlayerList(teamObject.playerList, teamObject.numPlayers, teamObject.teamGUIItem)
    end

    local currentY = (GUIScoreboard.kTeamNameFontSize + GUIScoreboard.kTeamInfoFontSize + 10) * GUIScoreboard.kScalingFactor

    local sumPlayerSkill = 0
    local numPlayerSkill = 0

    local numRookies = 0
    local numBots = 0

    local isSpectating = false
    teamObject.commRage = lastComm[teamObject.teamNumber] ~= nil
    for index, player in ipairs(teamObject.playerList) do
        local playerRecord = teamObject.teamScores[index]
        local playerObject = {}
        playerObject.playerGUIItem = player

        playerObject.realPlayerName = playerRecord.RealName or playerRecord["Name"] or "Unknown"
        playerObject.clientIndex = playerRecord["ClientIndex"]
        playerObject.teamNumber = playerRecord["EntityTeamNumber"]
        playerObject.steamId = playerRecord.SteamId
        if not playerObject.steamId then
            playerObject.steamId = GetSteamIdForClientIndex(playerObject.clientIndex)
        end
        playerObject.playerName = playerRecord["Name"] or playerObject.realPlayerName
        playerObject.playerStatus = teamObject.isVisibleTeam and playerRecord["Status"] or "-"
        playerObject.score = playerRecord["Score"] or 0
        playerObject.kills = playerRecord["Kills"] or 0
        playerObject.assists = playerRecord["Assists"] or 0
        playerObject.deaths = playerRecord["Deaths"] or 0
        -- A terminal round has no retained/current commander presentation even
        -- if the final PlayerInfoEntity snapshot still says the player is in
        -- the chair. Tracking resumes from live records in the next round.
        playerObject.isCommander = teamObject.isVisibleTeam and commanderTrackingActive and
            playerObject.steamId and playerObject.steamId > 0 and
            playerRecord["IsCommander"]
        -- Preserve 1.9.4 display behavior: Ready Room and Spectator players
        -- share this section, and every row in it shows both teams' field and
        -- commander skill values. This is presentation state only; use the
        -- record's entity team for gameplay/team decisions.
        playerObject.isSpectator = teamObject.teamNumber == kTeamReadyRoom
        -- The Ready Room section contains true spectators and Ready Room players.
        -- Only the former can have a player-slot queue position.
        playerObject.isQueueSpectator = playerObject.teamNumber == kSpectatorIndex
        local queuePosition = playerObject.isQueueSpectator and SSB_GetQueuePosition
            and SSB_GetQueuePosition(playerObject.steamId)
        if queuePosition then playerObject.playerStatus = string.format("Queue: %d", queuePosition) end
        playerObject.isMarine = playerObject["teamNumber"] == kMarineTeamType
        playerObject.isAlien = playerObject["teamNumber"] == kAlienTeamType
        playerObject.isDead = playerObject.playerStatus == Locale.ResolveString("STATUS_DEAD")
        playerObject.resources = playerRecord["Resources"] or 0
        playerObject.ping = playerRecord["Ping"] or 0

        playerObject.currentPosition = Vector(player["Background"]:GetPosition())
        playerObject.isSteamFriend = playerRecord["IsSteamFriend"]
        playerObject.playerSkill = playerRecord["Skill"] or 0
        playerObject.adagradSum = playerRecord["AdagradSum"] or 0
        playerObject.marineSkill = playerRecord["marineSkill"] or 0
        playerObject.alienSkill = playerRecord["alienSkill"] or 0
        playerObject.playerCommSkill = playerRecord["playerCommSkill"] or 0
        playerObject.hasCommanderSkill = playerRecord["playerCommSkill"] ~= nil and playerRecord["playerCommSkill"] >= 0
        playerObject.marineCommSkill = playerRecord["marineCommSkill"] or 0
        playerObject.alienCommSkill = playerRecord["alienCommSkill"] or 0
        playerObject.CommAdagradSum = playerRecord["CommAdagradSum"] or 0
        playerObject.commanderColor = GUIScoreboard.kCommanderFontColor
        playerObject.currentTechMask = playerRecord["Tech"] or 0
        playerObject.currentTech = GetTechIdsFromBitMask(playerObject.currentTechMask)
        if playerObject.steamId == localPlayerSteamID and playerRecord["IsSpectator"] then
            isSpectating = true
        end

        playerObject.isBot = playerObject.steamId == 0
        playerObject.commanderIdentity = GetCommanderIdentity(playerObject.steamId, playerObject.clientIndex)
        playerObject.isRookie = playerRecord["IsRookie"]
        numRookies = numRookies + (playerObject.isRookie and 1 or 0)
        numBots = numBots + (playerObject.isBot and 1 or 0)

        playerObject.playerTooltipData = (playerObject.steamId and playerObject.steamId > 0 and not playerObject.isBot) and getPlayerStats(playerObject.steamId) or nil

        -- Skills
        playerObject.playerSkillTier, playerObject.playerSkillTierName, playerObject.playerSkillCapped = GetPlayerSkillTier(playerObject.playerSkill, playerObject.isRookie, playerObject.adagradSum, playerObject.isBot)
        if playerObject.playerSkillCapped then
            sumPlayerSkill = sumPlayerSkill + playerObject.playerSkillCapped
            numPlayerSkill = numPlayerSkill + 1
        end

        playerObject.comSkillTier, playerObject.comSkillTierName, playerObject.comSkillCapped = GetPlayerSkillTier(playerObject.playerCommSkill, playerObject.isRookie, playerObject.CommAdagradSum, playerObject.isBot)

        playerObject.isLastComm = teamObject.isVisibleTeam and playerObject.commanderIdentity ~= nil and
            lastComm[teamObject.teamNumber] == playerObject.commanderIdentity

        -- Process the player GUI items
        if DirtyValuesChanged(playerObject.playerGUIItem, "SSBCommanderValues", playerObject.steamId,
                playerObject.playerName, playerObject.playerStatus, playerObject.currentTechMask,
                playerObject.isCommander, playerObject.isLastComm, teamObject.isVisibleTeam,
                playerObject.comSkillTier) then
            self:UpdateTeam_CommanderName(playerObject, teamObject)
            perfCounters.commanderChanged = perfCounters.commanderChanged + 1
        else
            perfCounters.commanderSkipped = perfCounters.commanderSkipped + 1
        end
        if DirtyValuesChanged(playerObject.playerGUIItem, "SSBTacticalValues", playerObject.currentTechMask,
                teamObject.isVisibleTeam, playerObject.isDead, playerObject.teamNumber) then
            self:UpdateTeam_UpgradesIcons(playerObject, teamObject)
            perfCounters.tacticalChanged = perfCounters.tacticalChanged + 1
        else
            perfCounters.tacticalSkipped = perfCounters.tacticalSkipped + 1
        end

        playerObject.currentPosition.y = currentY
        playerObject.playerGUIItem["ClientIndex"] = playerObject.clientIndex

        self:UpdateTeam_HighlightCurrentPlayer(playerObject, teamObject)
        local skillIcon = playerObject.playerGUIItem.SkillIcon
        local stats = playerObject.playerTooltipData
        UpdatePlayerLifeformIcon(playerObject)
        if DirtyValuesChanged(playerObject.playerGUIItem, "SSBSkillValues",
                playerObject.steamId, playerObject.playerSkill, playerObject.marineSkill,
                playerObject.alienSkill, playerObject.playerCommSkill, playerObject.marineCommSkill,
                playerObject.alienCommSkill, playerObject.playerSkillTier, playerObject.comSkillTier,
                playerObject.isSpectator, playerObject.isLastComm, playerObject.isRookie, isPreGame,
                stats and stats.state, stats and stats.marine_kdr, stats and stats.alien_kdr,
                stats and stats.marine_accuracy, stats and stats.alien_accuracy) then
            self:UpdateTeam_SkillIcons(playerObject)
            skillIcon.SSBCanonicalTooltipText = skillIcon.tooltipText
            perfCounters.skillChanged = perfCounters.skillChanged + 1
        else
            perfCounters.skillSkipped = perfCounters.skillSkipped + 1
        end

        -- tooltipText is a public compatibility surface and legacy extensions
        -- may append annotations after UpdateTeam. Keep it at SSB's immutable
        -- base; the hover path is the sole metadata decorator.
        if skillIcon.SSBCanonicalTooltipText and
                skillIcon.tooltipText ~= skillIcon.SSBCanonicalTooltipText then
            skillIcon.tooltipText = skillIcon.SSBCanonicalTooltipText
        end

        if DirtyValuesChanged(playerObject.playerGUIItem, "SSBStatsValues", playerObject.score,
                playerObject.kills, playerObject.assists, playerObject.deaths, playerObject.resources,
                playerObject.ping, playerObject.isDead, playerObject.isCommander,
                playerObject.isLastComm, teamObject.isVisibleTeam, teamObject.teamNumber) then
            self:UpdateTeam_StatsValues(playerObject, teamObject)
            perfCounters.statsChanged = perfCounters.statsChanged + 1
        else
            perfCounters.statsSkipped = perfCounters.statsSkipped + 1
        end
        local voiceMuted = ChatUI_GetClientMuted(playerObject.clientIndex)
        local textMuted = ChatUI_GetSteamIdTextMuted(playerObject.steamId)
        local callMuted = SSB_GetClientCallsMuted and SSB_GetClientCallsMuted(playerObject.clientIndex) or false
        local lowVoice = SSB_GetLowVoice and SSB_GetLowVoice(playerObject.steamId) or false
        local ready = isPreGame and MNGAReadyCheck_IsReady and MNGAReadyCheck_IsReady(playerObject.steamId) or false
        local muteChanged = DirtyValuesChanged(playerObject.playerGUIItem, "SSBMuteValues",
            playerObject.isSteamFriend, voiceMuted, textMuted, callMuted, lowVoice, ready)
        if muteChanged then
            playerObject.playerGUIItem["SteamFriend"]:SetIsVisible(playerObject.isSteamFriend)
            playerObject.playerGUIItem["Voice"]:SetIsVisible(voiceMuted)
            playerObject.playerGUIItem["Text"]:SetIsVisible(textMuted)
            playerObject.playerGUIItem["Call"]:SetIsVisible(callMuted)
            playerObject.playerGUIItem["LowVoice"]:SetIsVisible(lowVoice)
            playerObject.playerGUIItem["Ready"]:SetIsVisible(ready)
            perfCounters.muteChanged = perfCounters.muteChanged + 1
        else
            perfCounters.muteSkipped = perfCounters.muteSkipped + 1
        end

        local badgeTextures, badgeNames = Badges_GetBadgeTextures(playerObject.clientIndex, "scoreboard")
        local identityChanged = DirtyValuesChanged(playerObject.playerGUIItem, "SSBIdentityValues",
            index, playerObject.playerName, playerObject.clientIndex, playerObject.teamNumber,
            playerObject.playerStatus, playerObject.currentTechMask, playerObject.playerSkillTier,
            playerObject.comSkillTier, playerObject.isSteamFriend, voiceMuted, textMuted, callMuted, lowVoice, ready,
            playerObject.playerGUIItem.LifeformIcon:GetIsVisible(),
            GUIScoreboard.screenWidth, GUIScoreboard.kScalingFactor)
        local badgesChanged = DirtyListChanged(playerObject.playerGUIItem, "SSBBadgeTextures", badgeTextures)
        if identityChanged or badgesChanged then
            playerObject.playerGUIItem["Background"]:SetPosition(playerObject.currentPosition)
            playerObject.playerGUIItem["Background"]:SetColor(ConditionalValue(playerObject.isCommander,
                playerObject.commanderColor, teamObject.teamColor))
            playerObject.playerGUIItem["Number"]:SetText(index .. ".")
            playerObject.playerGUIItem["Name"]:SetText(playerObject.playerName)
            self:UpdateTeam_PlayersPlaceAndName(playerObject, badgeTextures, badgeNames)
            perfCounters.identityChanged = perfCounters.identityChanged + 1
        else
            playerObject.playerGUIItem.SSBBadgeNames = badgeNames
            perfCounters.identitySkipped = perfCounters.identitySkipped + 1
        end

        self:UpdateTeam_BackgroundColor(playerObject, teamObject)

        currentY = currentY + (GUIScoreboard.kPlayerItemHeight + GUIScoreboard.kPlayerSpacing) * GUIScoreboard.kScalingFactor
    end

    -- Is spectating handle
    if not teamObject.isPlayingTeam then
        localPlayerIsSpectator = isSpectating
    end

    -- Team skill avg icon
    if teamObject.isPlayingTeam and teamObject.teamSkillGUIItem.sumPlayerSkill ~= sumPlayerSkill then
        if teamObject.numPlayers > 0 then
            teamObject.teamSkillGUIItem.sumPlayerSkill = sumPlayerSkill
            local avgSkill = numPlayerSkill < 1 and 0 or sumPlayerSkill / numPlayerSkill
            avgSkill = (sumPlayerSkill + avgSkill * (teamObject.numPlayers - numPlayerSkill)) / teamObject.numPlayers

            local halfPlayerNum = 0.5 * teamObject.numPlayers
            local skillTier, tierName = GetPlayerSkillTier(avgSkill, numRookies > halfPlayerNum, nil, numBots > halfPlayerNum)
            teamObject.teamSkillGUIItem.tooltipText = string.format(Locale.ResolveString("SKILLTIER_TOOLTIP"), Locale.ResolveString(tierName), skillTier)
            local textureIndex = skillTier + 2
            teamObject.teamSkillGUIItem:SetTexturePixelCoordinates(0, textureIndex * 32, 100, (textureIndex + 1) * 32 - 1)
            teamObject.teamSkillGUIItem:SetIsVisible(true)
        else
            teamObject.teamSkillGUIItem:SetIsVisible(false)
        end
    end

    UpdateTeamVoiceControl(updateTeam)
    NotifyScoreboardIntegrations("OnTeamUpdated", self, updateTeam)
end

function GUIScoreboard:ResizePlayerList(playerList, numPlayers, teamGUIItem)
    PROFILE("GUIScoreboard:ResizePlayerList")
    while table.icount(playerList) > numPlayers do
        teamGUIItem:RemoveChild(playerList[1]["Background"])
        playerList[1]["Background"]:SetIsVisible(false)
        table.insert(self.reusePlayerItems, playerList[1])
        table.remove(playerList, 1)
    end

    while table.icount(playerList) < numPlayers do
        local newPlayerItem = self:CreatePlayerItem()
        table.insert(playerList, newPlayerItem)
        teamGUIItem:AddChild(newPlayerItem["Background"])
        newPlayerItem["Background"]:SetIsVisible(true)
    end
end

function GUIScoreboard:CreatePlayerItem()
    PROFILE("GUIScoreboard:CreatePlayerItem")
    -- Reuse an existing player item if there is one.
    if table.icount(self.reusePlayerItems) > 0 then
        local returnPlayerItem = self.reusePlayerItems[1]
        table.remove(self.reusePlayerItems, 1)
        return returnPlayerItem
    end

    -- Create background.
    local playerItem = GUIManager:CreateGraphicItem()
    playerItem:SetSize(Vector(self:GetTeamItemWidth() - (GUIScoreboard.kPlayerItemWidthBuffer * 2), GUIScoreboard.kPlayerItemHeight, 0) * GUIScoreboard.kScalingFactor)
    playerItem:SetAnchor(GUIItem.Left, GUIItem.Top)
    playerItem:SetPosition(Vector(GUIScoreboard.kPlayerItemWidthBuffer, GUIScoreboard.kPlayerItemHeight / 2, 0) * GUIScoreboard.kScalingFactor)
    playerItem:SetColor(Color(1, 1, 1, 1))
    playerItem:SetTexture(kHudElementsTexture)
    playerItem:SetTextureCoordinates(0, 0, 0.558, 0.16)
    playerItem:SetStencilFunc(GUIItem.NotEqual)

    local playerItemChildX = kPlayerItemLeftMargin

    -- Player number item
    local playerNumber = GUIManager:CreateTextItem()
    playerNumber:SetFontName(GUIScoreboard.kPlayerStatsFontName)
    playerNumber:SetScale(Vector(1, 1, 1) * GUIScoreboard.kScalingFactor)
    GUIMakeFontScale(playerNumber)
    playerNumber:SetAnchor(GUIItem.Left, GUIItem.Center)
    playerNumber:SetTextAlignmentX(GUIItem.Align_Min)
    playerNumber:SetTextAlignmentY(GUIItem.Align_Center)
    playerNumber:SetPosition(Vector(playerItemChildX, 0, 0))
    playerItemChildX = playerItemChildX + kPlayerNumberWidth
    playerNumber:SetColor(Color(0.5, 0.5, 0.5, 1))
    playerNumber:SetStencilFunc(GUIItem.NotEqual)
    playerNumber:SetIsVisible(false)
    playerItem:AddChild(playerNumber)

    -- Player voice icon item.
    local playerVoiceIcon = GUIManager:CreateGraphicItem()
    playerVoiceIcon:SetSize(Vector(kPlayerVoiceChatIconSize, kPlayerVoiceChatIconSize, 0) * GUIScoreboard.kScalingFactor)
    playerVoiceIcon:SetAnchor(GUIItem.Left, GUIItem.Center)
    playerVoiceIcon:SetPosition(Vector(playerItemChildX, -kPlayerVoiceChatIconSize / 2, 0) * GUIScoreboard.kScalingFactor)
    playerItemChildX = playerItemChildX + kPlayerVoiceChatIconSize
    playerVoiceIcon:SetTexture(kMutedVoiceTexture)
    playerVoiceIcon:SetStencilFunc(GUIItem.NotEqual)
    playerVoiceIcon:SetIsVisible(false)
    playerVoiceIcon:SetColor(GUIScoreboard.kVoiceMuteColor)
    playerItem:AddChild(playerVoiceIcon)

    ------------------------------------------
    --  Badge icons
    ------------------------------------------
    local maxBadges = Badges_GetMaxBadges()
    local badgeItems = {}

    -- Player badges
    for _ = 1, maxBadges do
        local playerBadge = GUIManager:CreateGraphicItem()
        playerBadge:SetSize(Vector(kPlayerBadgeIconSize, kPlayerBadgeIconSize, 0) * GUIScoreboard.kScalingFactor)
        playerBadge:SetAnchor(GUIItem.Left, GUIItem.Center)
        playerBadge:SetPosition(Vector(playerItemChildX, -kPlayerBadgeIconSize / 2, 0) * GUIScoreboard.kScalingFactor)
        playerItemChildX = playerItemChildX + kPlayerBadgeIconSize + kPlayerBadgeRightPadding
        playerBadge:SetIsVisible(false)
        playerBadge:SetStencilFunc(GUIItem.NotEqual)
        playerItem:AddChild(playerBadge)
        table.insert(badgeItems, playerBadge)
    end

    -- Player name text item.
    local playerNameItem = GUIManager:CreateTextItem()
    playerNameItem:SetFontName(GUIScoreboard.kPlayerStatsFontName)
    playerNameItem:SetScale(Vector(1, 1, 1) * GUIScoreboard.kScalingFactor)
    GUIMakeFontScale(playerNameItem)
    playerNameItem:SetAnchor(GUIItem.Left, GUIItem.Center)
    playerNameItem:SetTextAlignmentX(GUIItem.Align_Min)
    playerNameItem:SetTextAlignmentY(GUIItem.Align_Center)
    playerNameItem:SetPosition(Vector(playerItemChildX, 0, 0) * GUIScoreboard.kScalingFactor)
    playerNameItem:SetColor(Color(1, 1, 1, 1))
    playerNameItem:SetStencilFunc(GUIItem.NotEqual)
    playerItem:AddChild(playerNameItem)

    local currentColumnX = ConditionalValue(GUIScoreboard.screenWidth < 1280, GUIScoreboard.kPlayerItemWidth, (self:GetTeamItemWidth() - GUIScoreboard.kTeamColumnSpacingX * 10) - 75)

    local playerSkillIcon = GUIManager:CreateGraphicItem()
    playerSkillIcon:SetSize(kPlayerSkillIconSize * GUIScoreboard.kScalingFactor)
    playerSkillIcon:SetAnchor(GUIItem.Left, GUIItem.Center)
    playerSkillIcon:SetPosition(Vector(currentColumnX, -kPlayerBadgeIconSize / 2, 0) * GUIScoreboard.kScalingFactor)
    playerSkillIcon:SetStencilFunc(GUIItem.NotEqual)
    playerSkillIcon:SetTexture(kPlayerSkillIconTexture)
    playerSkillIcon:SetTexturePixelCoordinates(0, 0, 100, 31)
    playerItem:AddChild(playerSkillIcon)

    local lifeformIcon = GUIManager:CreateGraphicItem()
    lifeformIcon:SetSize(Vector(kLifeformIconSize, kLifeformIconSize, 0) * GUIScoreboard.kScalingFactor)
    lifeformIcon:SetAnchor(GUIItem.Left, GUIItem.Center)
    lifeformIcon:SetPosition(Vector(currentColumnX - kLifeformIconSize - 4,
        -kLifeformIconSize / 2, 0) * GUIScoreboard.kScalingFactor)
    lifeformIcon:SetStencilFunc(GUIItem.NotEqual)
    lifeformIcon:SetTexture(kLifeformAtlas1)
    lifeformIcon:SetTexturePixelCoordinates(3 * 64, 0, 4 * 64, 64)
    lifeformIcon:SetIsVisible(false)
    lifeformIcon.allowHighlight = true
    playerItem:AddChild(lifeformIcon)

    local playerCommIcon = GUIManager:CreateGraphicItem()
    playerCommIcon:SetSize(kPlayerCommIconSize * GUIScoreboard.kScalingFactor)
    playerCommIcon:SetAnchor(GUIItem.Left, GUIItem.Top)
    -- playerCommIcon:SetPosition(Vector(kPlayerCommIconSize.x, kPlayerCommIconSize.y / 2, 0) * GUIScoreboard.kScalingFactor)
    playerCommIcon:SetPosition(Vector(-4, -3, 0) * GUIScoreboard.kScalingFactor)
    playerCommIcon:SetStencilFunc(GUIItem.NotEqual)
    playerCommIcon:SetTexture(kPlayerCommIconsTexture)
    playerCommIcon:SetIsVisible(false)
    playerCommIcon:SetTexturePixelCoordinates(0, 0, 32, 32)
    -- playerItem:AddChild(playerCommIcon)
    playerSkillIcon:AddChild(playerCommIcon)

    local playerCommInsignia = GUIManager:CreateGraphicItem()
    playerCommInsignia:SetAnchor(GUIItem.Left, GUIItem.Center)
    playerCommInsignia:SetPosition(playerSkillIcon:GetPosition())
    playerCommInsignia:SetSize(playerSkillIcon:GetSize())
    playerCommInsignia:SetTexture(kPlayerCommanderSkillIconTexture)
    playerCommInsignia:SetStencilFunc(GUIItem.NotEqual)
    playerCommInsignia:SetLayer(3)
    playerCommInsignia:SetIsVisible(false)
    playerItem:AddChild(playerCommInsignia)

    local upgradeIcons = {}
    local startXupgrades = currentColumnX + ConditionalValue(GUIScoreboard.screenWidth < 1280, 30, 60)
    upgradeIcons["marineWelder"] = GUIManager:CreateGraphicItem()
    upgradeIcons["marineWelder"]:SetColor(RGBAtoColor(255, 255, 255, 1))
    upgradeIcons["marineWelder"]:SetSize(Vector(20, 20, 0) * GUIScoreboard.kScalingFactor)
    upgradeIcons["marineWelder"]:SetAnchor(GUIItem.Left, GUIItem.Center)
    upgradeIcons["marineWelder"]:SetPosition(Vector(startXupgrades * GUIScoreboard.kScalingFactor, -(upgradeIcons["marineWelder"]:GetSize().y / 2), 0))
    -- upgradeIcons["marineWelder"]:SetStencilFunc(GUIItem.NotEqual)
    upgradeIcons["marineWelder"]:SetTexture(kMarineEquipTexture)
    upgradeIcons["marineWelder"]:SetTexturePixelCoordinates(GUIUnpackCoords({113, 114 * 0, 227, 114 * 1}))
    upgradeIcons["marineWelder"]:SetIsVisible(false)
    playerItem:AddChild(upgradeIcons["marineWelder"])

    local marineGrenadePosition = Vector((startXupgrades + 20 + 4) * GUIScoreboard.kScalingFactor, 0, 0)
    local marineGrenadeNames = { "Cluster", "Gas", "Pulse" }
    local marineGrenadeRows = { Cluster = 2, Gas = 3, Pulse = 4 }
    for _, grenadeName in ipairs(marineGrenadeNames) do
        local iconName = "marineGrenade" .. grenadeName
        upgradeIcons[iconName] = GUIManager:CreateGraphicItem()
        upgradeIcons[iconName]:SetColor(RGBAtoColor(255, 255, 255, 1))
        upgradeIcons[iconName]:SetSize(Vector(20, 20, 0) * GUIScoreboard.kScalingFactor)
        upgradeIcons[iconName]:SetAnchor(GUIItem.Left, GUIItem.Center)
        upgradeIcons[iconName]:SetPosition(Vector(marineGrenadePosition.x,
            -(upgradeIcons[iconName]:GetSize().y / 2), 0))
        upgradeIcons[iconName]:SetTexture(kMarineEquipTexture)
        local row = marineGrenadeRows[grenadeName]
        upgradeIcons[iconName]:SetTexturePixelCoordinates(GUIUnpackCoords({113, 114 * row, 227, 114 * (row + 1)}))
        upgradeIcons[iconName]:SetIsVisible(false)
        playerItem:AddChild(upgradeIcons[iconName])
    end

    upgradeIcons["marineMine"] = GUIManager:CreateGraphicItem()
    upgradeIcons["marineMine"]:SetColor(RGBAtoColor(255, 255, 255, 1))
    upgradeIcons["marineMine"]:SetSize(Vector(20, 20, 0) * GUIScoreboard.kScalingFactor)
    upgradeIcons["marineMine"]:SetAnchor(GUIItem.Left, GUIItem.Center)
    upgradeIcons["marineMine"]:SetPosition(Vector((startXupgrades + 40 + 8) * GUIScoreboard.kScalingFactor, -(upgradeIcons["marineMine"]:GetSize().y / 2), 0))
    -- upgradeIcons["marineMine"]:SetStencilFunc(GUIItem.NotEqual)
    upgradeIcons["marineMine"]:SetTexture(kMarineEquipTexture)
    upgradeIcons["marineMine"]:SetTexturePixelCoordinates(GUIUnpackCoords({113, 114 * 1, 227, 114 * 2}))
    upgradeIcons["marineMine"]:SetIsVisible(false)
    playerItem:AddChild(upgradeIcons["marineMine"])

    -- Alien upgrades
    upgradeIcons["alienShell"] = GUIManager:CreateGraphicItem()
    upgradeIcons["alienShell"]:SetColor(RGBAtoColor(255, 255, 255, 1))
    upgradeIcons["alienShell"]:SetSize(Vector(20, 20, 0) * GUIScoreboard.kScalingFactor)
    upgradeIcons["alienShell"]:SetAnchor(GUIItem.Left, GUIItem.Center)
    upgradeIcons["alienShell"]:SetPosition(Vector(startXupgrades * GUIScoreboard.kScalingFactor, -(upgradeIcons["alienShell"]:GetSize().y / 2), 0))
    -- upgradeIcons["alienShell"]:SetStencilFunc(GUIItem.NotEqual)
    upgradeIcons["alienShell"]:SetTexture(kAlienUpgradesTexture)
    upgradeIcons["alienShell"]:SetTexturePixelCoordinates(GUIUnpackCoords({113 * 0, 114 * 0, 113 * 1, 114 * 1}))
    upgradeIcons["alienShell"]:SetIsVisible(false)
    playerItem:AddChild(upgradeIcons["alienShell"])

    upgradeIcons["alienVeil"] = GUIManager:CreateGraphicItem()
    upgradeIcons["alienVeil"]:SetColor(RGBAtoColor(255, 255, 255, 1))
    upgradeIcons["alienVeil"]:SetSize(Vector(20, 20, 0) * GUIScoreboard.kScalingFactor)
    upgradeIcons["alienVeil"]:SetAnchor(GUIItem.Left, GUIItem.Center)
    upgradeIcons["alienVeil"]:SetPosition(Vector((startXupgrades + 20 + 4) * GUIScoreboard.kScalingFactor, -(upgradeIcons["alienVeil"]:GetSize().y / 2), 0))
    -- upgradeIcons["alienVeil"]:SetStencilFunc(GUIItem.NotEqual)
    upgradeIcons["alienVeil"]:SetTexture(kAlienUpgradesTexture)
    upgradeIcons["alienVeil"]:SetTexturePixelCoordinates(GUIUnpackCoords({113 * 0, 114 * 1, 113 * 1, 114 * 2}))
    upgradeIcons["alienVeil"]:SetIsVisible(false)
    playerItem:AddChild(upgradeIcons["alienVeil"])

    upgradeIcons["alienSpur"] = GUIManager:CreateGraphicItem()
    upgradeIcons["alienSpur"]:SetColor(RGBAtoColor(255, 255, 255, 1))
    upgradeIcons["alienSpur"]:SetSize(Vector(20, 20, 0) * GUIScoreboard.kScalingFactor)
    upgradeIcons["alienSpur"]:SetAnchor(GUIItem.Left, GUIItem.Center)
    upgradeIcons["alienSpur"]:SetPosition(Vector((startXupgrades + 40 + 8) * GUIScoreboard.kScalingFactor, -(upgradeIcons["alienSpur"]:GetSize().y / 2), 0))
    -- upgradeIcons["alienSpur"]:SetStencilFunc(GUIItem.NotEqual)
    upgradeIcons["alienSpur"]:SetTexture(kAlienUpgradesTexture)
    upgradeIcons["alienSpur"]:SetTexturePixelCoordinates(GUIUnpackCoords({113 * 0, 114 * 2, 113 * 1, 114 * 3}))
    upgradeIcons["alienSpur"]:SetIsVisible(false)
    playerItem:AddChild(upgradeIcons["alienSpur"])

    currentColumnX = currentColumnX + 75
    -- Status text item.
    local statusItem = GUIManager:CreateTextItem()
    statusItem:SetFontName(GUIScoreboard.kPlayerStatsFontName)
    statusItem:SetScale(Vector(1, 1, 1) * GUIScoreboard.kScalingFactor)
    GUIMakeFontScale(statusItem)
    statusItem:SetAnchor(GUIItem.Left, GUIItem.Center)
    statusItem:SetTextAlignmentX(GUIItem.Align_Min)
    statusItem:SetTextAlignmentY(GUIItem.Align_Center)
    statusItem:SetPosition(Vector(currentColumnX + ConditionalValue(GUIScoreboard.screenWidth < 1280, 30, 60), 0, 0) * GUIScoreboard.kScalingFactor)
    statusItem:SetColor(Color(1, 1, 1, 1))
    statusItem:SetStencilFunc(GUIItem.NotEqual)
    playerItem:AddChild(statusItem)

    currentColumnX = currentColumnX + GUIScoreboard.kTeamColumnSpacingX * 2 + 35

    -- Score text item.
    local scoreItem = GUIManager:CreateTextItem()
    scoreItem:SetFontName(GUIScoreboard.kPlayerStatsFontName)
    scoreItem:SetScale(Vector(1, 1, 1) * GUIScoreboard.kScalingFactor)
    GUIMakeFontScale(scoreItem)
    scoreItem:SetAnchor(GUIItem.Left, GUIItem.Center)
    scoreItem:SetTextAlignmentX(GUIItem.Align_Center)
    scoreItem:SetTextAlignmentY(GUIItem.Align_Center)
    scoreItem:SetPosition(Vector(currentColumnX + 30, 0, 0) * GUIScoreboard.kScalingFactor)
    scoreItem:SetColor(Color(1, 1, 1, 1))
    scoreItem:SetStencilFunc(GUIItem.NotEqual)
    playerItem:AddChild(scoreItem)

    currentColumnX = currentColumnX + GUIScoreboard.kTeamColumnSpacingX + 30

    -- Kill text item.
    local killsItem = GUIManager:CreateTextItem()
    killsItem:SetFontName(GUIScoreboard.kPlayerStatsFontName)
    killsItem:SetScale(Vector(1, 1, 1) * GUIScoreboard.kScalingFactor)
    GUIMakeFontScale(killsItem)
    killsItem:SetAnchor(GUIItem.Left, GUIItem.Center)
    killsItem:SetTextAlignmentX(GUIItem.Align_Center)
    killsItem:SetTextAlignmentY(GUIItem.Align_Center)
    killsItem:SetPosition(Vector(currentColumnX, 0, 0) * GUIScoreboard.kScalingFactor)
    killsItem:SetColor(Color(1, 1, 1, 1))
    killsItem:SetStencilFunc(GUIItem.NotEqual)
    playerItem:AddChild(killsItem)

    currentColumnX = currentColumnX + GUIScoreboard.kTeamColumnSpacingX

    -- assists text item.
    local assistsItem = GUIManager:CreateTextItem()
    assistsItem:SetFontName(GUIScoreboard.kPlayerStatsFontName)
    assistsItem:SetScale(Vector(1, 1, 1) * GUIScoreboard.kScalingFactor)
    GUIMakeFontScale(assistsItem)
    assistsItem:SetAnchor(GUIItem.Left, GUIItem.Center)
    assistsItem:SetTextAlignmentX(GUIItem.Align_Center)
    assistsItem:SetTextAlignmentY(GUIItem.Align_Center)
    assistsItem:SetPosition(Vector(currentColumnX, 0, 0) * GUIScoreboard.kScalingFactor)
    assistsItem:SetColor(Color(1, 1, 1, 1))
    assistsItem:SetStencilFunc(GUIItem.NotEqual)
    playerItem:AddChild(assistsItem)

    currentColumnX = currentColumnX + GUIScoreboard.kTeamColumnSpacingX

    -- Deaths text item.
    local deathsItem = GUIManager:CreateTextItem()
    deathsItem:SetFontName(GUIScoreboard.kPlayerStatsFontName)
    deathsItem:SetScale(Vector(1, 1, 1) * GUIScoreboard.kScalingFactor)
    GUIMakeFontScale(deathsItem)
    deathsItem:SetAnchor(GUIItem.Left, GUIItem.Center)
    deathsItem:SetTextAlignmentX(GUIItem.Align_Center)
    deathsItem:SetTextAlignmentY(GUIItem.Align_Center)
    deathsItem:SetPosition(Vector(currentColumnX, 0, 0) * GUIScoreboard.kScalingFactor)
    deathsItem:SetColor(Color(1, 1, 1, 1))
    deathsItem:SetStencilFunc(GUIItem.NotEqual)
    playerItem:AddChild(deathsItem)

    currentColumnX = currentColumnX + GUIScoreboard.kTeamColumnSpacingX

    -- Resources text item.
    local resItem = GUIManager:CreateTextItem()
    resItem:SetFontName(GUIScoreboard.kPlayerStatsFontName)
    resItem:SetScale(Vector(1, 1, 1) * GUIScoreboard.kScalingFactor)
    GUIMakeFontScale(resItem)
    resItem:SetAnchor(GUIItem.Left, GUIItem.Center)
    resItem:SetTextAlignmentX(GUIItem.Align_Center)
    resItem:SetTextAlignmentY(GUIItem.Align_Center)
    resItem:SetPosition(Vector(currentColumnX, 0, 0) * GUIScoreboard.kScalingFactor)
    resItem:SetColor(Color(1, 1, 1, 1))
    resItem:SetStencilFunc(GUIItem.NotEqual)
    playerItem:AddChild(resItem)

    currentColumnX = currentColumnX + GUIScoreboard.kTeamColumnSpacingX

    -- Ping text item.
    local pingItem = GUIManager:CreateTextItem()
    pingItem:SetFontName(GUIScoreboard.kPlayerStatsFontName)
    pingItem:SetScale(Vector(1, 1, 1) * GUIScoreboard.kScalingFactor)
    GUIMakeFontScale(pingItem)
    pingItem:SetAnchor(GUIItem.Left, GUIItem.Center)
    pingItem:SetTextAlignmentX(GUIItem.Align_Min)
    pingItem:SetTextAlignmentY(GUIItem.Align_Center)
    pingItem:SetPosition(Vector(currentColumnX, 0, 0) * GUIScoreboard.kScalingFactor)
    pingItem:SetColor(Color(1, 1, 1, 1))
    pingItem:SetStencilFunc(GUIItem.NotEqual)
    playerItem:AddChild(pingItem)

    local playerTextIcon = GUIManager:CreateGraphicItem()
    playerTextIcon:SetSize(Vector(kPlayerVoiceChatIconSize, kPlayerVoiceChatIconSize, 0) * GUIScoreboard.kScalingFactor)
    playerTextIcon:SetAnchor(GUIItem.Left, GUIItem.Center)
    playerTextIcon:SetTexture(kMutedTextTexture)
    playerTextIcon:SetStencilFunc(GUIItem.NotEqual)
    playerTextIcon:SetIsVisible(false)
    playerTextIcon:SetColor(GUIScoreboard.kVoiceMuteColor)
    playerItem:AddChild(playerTextIcon)

    local playerCallIcon = GUIManager:CreateGraphicItem()
    playerCallIcon:SetSize(Vector(kPlayerVoiceChatIconSize, kPlayerVoiceChatIconSize, 0) * GUIScoreboard.kScalingFactor)
    playerCallIcon:SetAnchor(GUIItem.Left, GUIItem.Center)
    playerCallIcon:SetTexture(kMutedCallTexture)
    playerCallIcon:SetStencilFunc(GUIItem.NotEqual)
    playerCallIcon:SetIsVisible(false)
    playerCallIcon:SetColor(GUIScoreboard.kVoiceMuteColor)
    playerItem:AddChild(playerCallIcon)

    local steamFriendIcon = GUIManager:CreateGraphicItem()
    steamFriendIcon:SetSize(Vector(kPlayerVoiceChatIconSize, kPlayerVoiceChatIconSize, 0) * GUIScoreboard.kScalingFactor)
    steamFriendIcon:SetAnchor(GUIItem.Left, GUIItem.Center)
    steamFriendIcon:SetTexture(kSteamfriendTexture)
    steamFriendIcon:SetStencilFunc(GUIItem.NotEqual)
    steamFriendIcon:SetIsVisible(false)
    steamFriendIcon.allowHighlight = true
    playerItem:AddChild(steamFriendIcon)

    local lowVoiceIcon = GUIManager:CreateGraphicItem()
    lowVoiceIcon:SetSize(Vector(kPlayerVoiceChatIconSize, kPlayerVoiceChatIconSize, 0) * GUIScoreboard.kScalingFactor)
    lowVoiceIcon:SetAnchor(GUIItem.Left, GUIItem.Center)
    lowVoiceIcon:SetTexture(kLowVoiceTexture)
    lowVoiceIcon:SetStencilFunc(GUIItem.NotEqual)
    lowVoiceIcon:SetIsVisible(false)
    lowVoiceIcon.allowHighlight = true
    lowVoiceIcon.SSBTooltipText = kLowVoiceTooltip
    playerItem:AddChild(lowVoiceIcon)

    local readyIcon = GUIManager:CreateGraphicItem()
    readyIcon:SetSize(Vector(kPlayerVoiceChatIconSize, kPlayerVoiceChatIconSize, 0) * GUIScoreboard.kScalingFactor)
    readyIcon:SetAnchor(GUIItem.Left, GUIItem.Center)
    readyIcon:SetTexture(kReadyTexture)
    readyIcon:SetStencilFunc(GUIItem.NotEqual)
    readyIcon:SetIsVisible(false)
    readyIcon.allowHighlight = true
    readyIcon.SSBTooltipText = kReadyTooltip
    playerItem:AddChild(readyIcon)

    -- Let's do a table here to easily handle the highlighting/clicking of icons
    -- It also makes it easy for other mods to add icons afterwards
    local iconTable = {}
    -- Icons are packed leftward from the skill emblem in table order. The
    -- pregame ready flag takes the closest slot, then the lifeform selector,
    -- then the low-voice flag, and ancillary icons sit left of them.
    -- Full order: .claude/docs/ssb-lowvoice-mutedby.md, .claude/docs/ready-check.md
    table.insert(iconTable, readyIcon)
    table.insert(iconTable, lifeformIcon)
    table.insert(iconTable, lowVoiceIcon)
    table.insert(iconTable, steamFriendIcon)
    table.insert(iconTable, playerCallIcon)
    table.insert(iconTable, playerTextIcon)
    table.insert(iconTable, playerVoiceIcon)

    return {
        Background = playerItem,
        Number = playerNumber,
        Name = playerNameItem,
        Voice = playerVoiceIcon,
        Status = statusItem,
        CommIcon = playerCommIcon,
        CommInsignia = playerCommInsignia,
        SkillIcon = playerSkillIcon,
        LifeformIcon = lifeformIcon,
        UpgradeIcons = upgradeIcons,
        Score = scoreItem,
        Kills = killsItem,
        Assists = assistsItem,
        Deaths = deathsItem,
        Resources = resItem,
        Ping = pingItem,
        BadgeItems = badgeItems,
        Text = playerTextIcon,
        Call = playerCallIcon,
        SteamFriend = steamFriendIcon,
        LowVoice = lowVoiceIcon,
        Ready = readyIcon,
        IconTable = iconTable
    }
end

local function HandleLifeformSelectorClicked(self)
    if not MouseTracker_GetIsVisible() or not GetLifeformViewerEligible() then return false end
    local localPlayer = Client.GetLocalPlayer()
    if not localPlayer or localPlayer:GetTeamNumber() ~= kTeam2Index then return false end

    local mouseX, mouseY = Client.GetCursorPosScreen()
    local localSteamId = Client.GetSteamId()
    for _, team in ipairs(self.teams) do
        for _, item in ipairs(team.PlayerList) do
            local icon = item.LifeformIcon
            if icon and icon:GetIsVisible() and tostring(item.SSBSteamId) == tostring(localSteamId) and
                    GUIItemContainsPoint(icon, mouseX, mouseY) then
                local bgColor = GUIScoreboard.kRedColor * 0.1
                bgColor.a = 0.9
                local buttonColor = GUIScoreboard.kRedColor * 0.5
                local highlightColor = GUIScoreboard.kRedColor * 0.75
                local textColor = Color(1, 1, 1, 1)
                self.hoverMenu:ResetButtons()
                self.hoverMenu:SetBackgroundColor(bgColor)
                self.hoverMenu:AddButton("Select preferred lifeform", Color(0, 0, 0, 0),
                    Color(0, 0, 0, 0), textColor)
                for i = 1, #kLifeformNames do
                    local lifeform = kLifeformNames[i]
                    self.hoverMenu:AddButton(lifeform, buttonColor, highlightColor, textColor, function()
                        if SSB_SetLocalLifeformSelection then
                            SSB_SetLocalLifeformSelection(lifeform)
                            self.ssbForceDataRefresh = true
                        end
                    end)
                end
                self.hoverMenu:Show()
                self.badgeNameTooltip:Hide(0)
                self.ssbPendingMenuIntegration = nil
                return true
            end
        end
    end
    return false
end

local function HandlePlayerVoiceClicked(self)
    PROFILE("GUIScoreboard:HandlePlayerVoiceClicked")
    if MouseTracker_GetIsVisible() then
        local mouseX, mouseY = Client.GetCursorPosScreen()
        for t = 1, #self.teams do
            local playerList = self.teams[t]["PlayerList"]
            for p = 1, #playerList do
                local playerItem = playerList[p]
                if GUIItemContainsPoint(playerItem["Voice"], mouseX, mouseY) and playerItem["Voice"]:GetIsVisible() then
                    local clientIndex = playerItem["ClientIndex"]
                    ChatUI_SetClientMuted(clientIndex, not ChatUI_GetClientMuted(clientIndex))
                end
            end
        end
    end
end

local function HandlePlayerCallClicked(self)
    PROFILE("GUIScoreboard:HandlePlayerCallClicked")
    if not MouseTracker_GetIsVisible() or not SSB_SetClientCallsMuted then return end
    local mouseX, mouseY = Client.GetCursorPosScreen()
    for t = 1, #self.teams do
        local playerList = self.teams[t]["PlayerList"]
        for p = 1, #playerList do
            local playerItem = playerList[p]
            if playerItem["Call"]:GetIsVisible() and GUIItemContainsPoint(playerItem["Call"], mouseX, mouseY) then
                local clientIndex = playerItem["ClientIndex"]
                SSB_SetClientCallsMuted(clientIndex, not SSB_GetClientCallsMuted(clientIndex))
            end
        end
    end
end

local function HandlePlayerTextClicked(self)
    PROFILE("GUIScoreboard:HandlePlayerTextClicked")
    if MouseTracker_GetIsVisible() then
        local mouseX, mouseY = Client.GetCursorPosScreen()
        for t = 1, #self.teams do
            local playerList = self.teams[t]["PlayerList"]
            for p = 1, #playerList do
                local playerItem = playerList[p]
                if GUIItemContainsPoint(playerItem["Text"], mouseX, mouseY) and playerItem["Text"]:GetIsVisible() then
                    local clientIndex = playerItem["ClientIndex"]
                    local steamId = GetSteamIdForClientIndex(clientIndex)
                    ChatUI_SetSteamIdTextMuted(steamId, not ChatUI_GetSteamIdTextMuted(steamId))
                end
            end
        end

        if self.favoriteButton and GUIItemContainsPoint(self.favoriteButton, mouseX, mouseY) then
            local serverIsFavorite = not self.favoriteButton.isServerFavorite
            self.favoriteButton:SetTexture(serverIsFavorite and self.kFavoriteTexture or self.kNotFavoriteTexture)
            self.favoriteButton.isServerFavorite = serverIsFavorite
            SetServerIsFavorite({
                address = self.serverAddress
            }, serverIsFavorite)

            if serverIsFavorite then
                self.blockedButton.isServerBlocked = false
                self.blockedButton:SetTexture(self.kNotBlockedTexture)
            end
        elseif self.blockedButton and GUIItemContainsPoint(self.blockedButton, mouseX, mouseY) then
            local serverIsBlocked = not self.blockedButton.isServerBlocked
            self.blockedButton:SetTexture(serverIsBlocked and self.kBlockedTexture or self.kNotBlockedTexture)
            self.blockedButton.isServerBlocked = serverIsBlocked
            SetServerIsBlocked({
                address = self.serverAddress
            }, serverIsBlocked)

            if serverIsBlocked then
                self.favoriteButton.isServerFavorite = false
                self.favoriteButton:SetTexture(self.kNotFavoriteTexture)
            end
        end
    end
end

local function HandleTeamVoiceMuteClicked(self)
    if not IsLocalClientSpectator() or not MouseTracker_GetIsVisible() then
        return false
    end
    local mouseX, mouseY = Client.GetCursorPosScreen()
    for _, team in ipairs(self.teams) do
        local icon = team.GUIs and team.GUIs.TeamVoiceMute
        if icon and icon:GetIsVisible() and GUIItemContainsPoint(icon, mouseX, mouseY) then
            local muted = SSB_GetTeamVoiceMuted(team.TeamNumber)
            Print("[SSBTeamVoiceMute] Clicked team %d; requesting %s", team.TeamNumber,
                muted and "unmuted" or "muted")
            SSB_SetTeamVoiceMuted(team.TeamNumber, not muted)
            return true
        end
    end
    return false
end

function GUIScoreboard:SetIsVisible(state)
    PROFILE("GUIScoreboard:SetIsVisible")
    self.hiddenOverride = not state
    self.ssbForceDataRefresh = state

    -- Don't remove the deltatime parameter we use it to detect if the scoreboard get opened
    self:Update(0)
end

function GUIScoreboard:GetIsVisible()
    return not self.hiddenOverride
end

function GUIScoreboard:SendKeyEvent(key, down)
    PROFILE("GUIScoreboard:SendKeyEvent")

    if ChatUI_EnteringChatMessage() then
        return false
    end

    if GetIsBinding(key, "Scoreboard") then
        local wasVisible = self.visible
        self.visible = down and not self.hiddenOverride
        if not self.visible then
            self.hoverMenu:Hide()
        else
            self.updateInterval = MouseTracker_GetIsVisible() and kMouseUpdateInterval or kVisibleUpdateInterval
            if not wasVisible then
                UpdateLifeformSyncEligibility(self, "scoreboard_open")
            end
            if self.background and not self.background:GetIsVisible() then
                self:Update(0)
            end
        end
    end

    if not self.visible then
        return false
    end

    if down then
        self.ssbForceDataRefresh = true
    end

    -- SGUI may consume the matching mouse-up after SourceSSB acquires mouse
    -- ownership during the activation press. Treat each delivered mouse-down
    -- as a fresh click instead of requiring our legacy pressed-state cache to
    -- have observed that release.
    local leftMouseDown = key == InputKey.MouseButton0 and down
    if leftMouseDown and MouseTracker_GetIsVisible() and
            HandleTeamVoiceMuteClicked(self) then
        return true
    end

    if leftMouseDown and MouseTracker_GetIsVisible() and not MainMenu_GetIsOpened() then
        -- Resolve the row under the cursor on the input event itself. This
        -- keeps menu clicks correct even when an input event lands between
        -- scheduled interaction ticks (notably during map-load GUI startup).
        self:UpdateMouseInteraction()
        if HandleLifeformSelectorClicked(self) then
            self.mousePressed["LMB"]["Down"] = down
            return true
        end
        HandlePlayerTextClicked(self)
        HandlePlayerCallClicked(self)

        local steamId = GetSteamIdForClientIndex(self.hoverPlayerClientIndex) or 0
        if self.hoverMenu.background:GetIsVisible() then
            -- Display the menu for bots if dev mode is on (steamId is 0 but they have a proper clientIndex)
            return false
        elseif steamId ~= 0 or self.hoverPlayerClientIndex ~= 0 and Shared.GetDevMode() then
            local isTextMuted = ChatUI_GetSteamIdTextMuted(steamId)
            local isVoiceMuted = ChatUI_GetClientMuted(self.hoverPlayerClientIndex)
            local function openSteamProf()
                Client.ShowWebpage(string.format("%s[U:1:%s]", kSteamProfileURL, steamId))
            end
            local function openNS2StatsProfile()
                Client.ShowWebpage(string.format(kNS2StatsProfileURL, steamId))
            end
            local function muteText()
                ChatUI_SetSteamIdTextMuted(steamId, not isTextMuted)
            end
            local function muteVoice()
                ChatUI_SetClientMuted(self.hoverPlayerClientIndex, not isVoiceMuted)
            end
            local callsMuted = SSB_GetClientCallsMuted and SSB_GetClientCallsMuted(self.hoverPlayerClientIndex) or false
            local function muteCalls()
                SSB_SetClientCallsMuted(self.hoverPlayerClientIndex, not callsMuted)
            end

            self.hoverMenu:ResetButtons()

            local teamColorBg
            local teamColorHighlight
            local playerRecord = Scoreboard_GetPlayerRecord(self.hoverPlayerClientIndex)
            local playerName = playerRecord and (playerRecord.RealName or playerRecord.Name) or "Unknown"
            local teamNumber = Scoreboard_GetPlayerData(self.hoverPlayerClientIndex, "EntityTeamNumber")
            local isCommander = Scoreboard_GetPlayerData(self.hoverPlayerClientIndex, "IsCommander") and GetIsVisibleTeam(teamNumber)

            local textColor = Color(1, 1, 1, 1)
            local nameBgColor = Color(0, 0, 0, 0)

            if isCommander then
                teamColorBg = GUIScoreboard.kCommanderFontColor
            elseif teamNumber == kMarineTeamType then
                teamColorBg = GUIScoreboard.kBlueColor
            elseif teamNumber == kAlienTeamType then
                teamColorBg = GUIScoreboard.kRedColor
            else
                teamColorBg = GUIScoreboard.kSpectatorColor
            end

            local bgColor = teamColorBg * 0.1
            bgColor.a = 0.9

            teamColorHighlight = teamColorBg * 0.75
            teamColorBg = teamColorBg * 0.5

            self.hoverMenu:SetBackgroundColor(bgColor)
            self.hoverMenu:AddButton(playerName, nameBgColor, nameBgColor, textColor)
            self.hoverMenu:AddButton(Locale.ResolveString("SB_MENU_STEAM_PROFILE"), teamColorBg, teamColorHighlight, textColor, openSteamProf)
            self.hoverMenu:AddButton("NS2 Stats Profile", teamColorBg, teamColorHighlight, textColor, openNS2StatsProfile)

            if Client.GetSteamId() ~= steamId then
                self.hoverMenu:AddSeparator("muteOptions")
                self.hoverMenu:AddButton(ConditionalValue(isVoiceMuted, Locale.ResolveString("SB_MENU_UNMUTE_VOICE"), Locale.ResolveString("SB_MENU_MUTE_VOICE")), teamColorBg, teamColorHighlight, textColor, muteVoice)
                self.hoverMenu:AddButton(ConditionalValue(isTextMuted, Locale.ResolveString("SB_MENU_UNMUTE_TEXT"), Locale.ResolveString("SB_MENU_MUTE_TEXT")), teamColorBg, teamColorHighlight, textColor, muteText)
                self.hoverMenu:AddButton(callsMuted and "Unmute Calls" or "Mute Calls",
                    teamColorBg, teamColorHighlight, textColor, muteCalls)
            end

            self.hoverMenu:Show()
            self.badgeNameTooltip:Hide(0)
            -- Run optional menu integrations on the next update so existing
            -- Shine passive-post actions (notably VoteRandom friends) append first.
            self.ssbPendingMenuIntegration = self.hoverPlayerClientIndex
        end
    end

    if key == InputKey.MouseButton0 then
        self.mousePressed["LMB"]["Down"] = down
        if down then
            local mouseX, mouseY = Client.GetCursorPosScreen()
            self.isDragging = GUIItemContainsPoint(self.slidebarBg, mouseX, mouseY)
            if self.isDragging then self.updateInterval = kMouseUpdateInterval end

            -- Global cursor visibility may belong to Poker, Bejeweled, or
            -- another Shine window. Only our own flag proves that SSB has a
            -- balanced ownership claim.
            if not MouseTracker_GetIsVisible() then
                SetMouseVisible(self, true)
                self.updateInterval = kMouseUpdateInterval
            else
                HandlePlayerVoiceClicked(self)
            end

            return true
        end
        self.isDragging = false
        self.updateInterval = self.mouseVisible and kMouseUpdateInterval or kVisibleUpdateInterval
    end

    if self.slidebarBg:GetIsVisible() then
        if key == InputKey.MouseWheelDown then
            self.slidePercentage = math.min(self.slidePercentage + 5, 100)
            return true
        elseif key == InputKey.MouseWheelUp then
            self.slidePercentage = math.max(self.slidePercentage - 5, 0)
            return true
        elseif key == InputKey.PageDown and down then
            self.slidePercentage = math.min(self.slidePercentage + 10, 100)
            return true
        elseif key == InputKey.PageUp and down then
            self.slidePercentage = math.max(self.slidePercentage - 10, 0)
            return true
        elseif key == InputKey.Home then
            self.slidePercentage = 0
            return true
        elseif key == InputKey.End then
            self.slidePercentage = 100
            return true
        end
    end
end

