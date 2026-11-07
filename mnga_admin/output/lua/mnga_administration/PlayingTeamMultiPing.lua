
-- MNGA multi-ping: per-player ping slots (kMultiPingCount is defined in TeamInfoMultiPing.lua).
-- Each pinger owns at most one active ping; pinging again moves their own ping.
-- The commander uses a dedicated owner id, so their ping only overrides their own.

Script.Load("lua/mnga_administration/Globals.lua")
Script.Load("lua/mnga_administration/ContextPingShared.lua")

local kPingSpamInterval = 3 -- min seconds between pings from the same owner (matches vanilla comm ping gate)
local kCommanderOwnerId = -1

-- Fallback only. The normal path uses MNGA_GetSkillTierForSkill() from Globals.lua
-- so multiping and scoreboard/death screen tiers stay in sync.
-- 0 = unknown (bots / hive data not yet received) -> default color.
local kTierMaxSkill = { 300, 750, 1400, 2100, 2999, 3999, 4999, 5999, 999999 }

local function GetPingSkillTier(player)

    if not player or (player.GetIsVirtual and player:GetIsVirtual()) then
        return 0
    end

    local skill = player.GetPlayerSkill and player:GetPlayerSkill()
    if not skill or skill < 0 then
        return 0
    end

    if MNGA_GetSkillTierForSkill then
        local tier = MNGA_GetSkillTierForSkill(skill, false, nil, false)
        return tier and math.max(tier, 0) or 0
    end

    for tier = 1, #kTierMaxSkill do
        if skill <= kTierMaxSkill[tier] then
            return tier
        end
    end
    return #kTierMaxSkill

end

function PlayingTeam:ResetPlayerPings()

    self.playerPings = {}
    for i = 1, kMultiPingCount do
        self.playerPings[i] = { time = 0, position = Vector(0, 0, 0), name = "", ownerId = 0, clientIndex = -1, skillTier = 0, isCommander = false }
    end
    self.lastPingTimeByOwner = {}

    -- contextual ping highlight marks (TeamInfoMultiPing networks them)
    -- bumped on every mark change; TeamInfo only re-copies the mark netvars
    -- when it differs from the version it last copied
    self.contextMarksVersion = (self.contextMarksVersion or 0) + 1
    self.contextMarks = {}
    for i = 1, kContextMarkCount do
        -- ownerIds: server-only set of everyone who pinged this mark (cooldown refund on target death)
        self.contextMarks[i] = { targetId = Entity.invalidId, targetTeam = 0, time = 0, clientIndex = -1, skillTier = 0, isCommander = false, ownerIds = {} }
    end

    -- Kept for bot AI: bot brains react to commander pings via
    -- PlayingTeam:GetCommanderPingTime/GetCommanderPingPosition (vanilla getters read these fields).
    self.lastCommPingTime = 0
    self.lastCommPingPosition = Vector(0, 0, 0)

    local teamInfo = self.teamInfoEntityId and Shared.GetEntity(self.teamInfoEntityId)
    if teamInfo and teamInfo.UpdateInfo then
        teamInfo:UpdateInfo()
    end

end

function PlayingTeam:Initialize(teamName, teamNumber)

    Team.Initialize(self, teamName, teamNumber)

    self.respawnEntity = nil

    self:OnCreate()

    self.timeSinceLastLOSUpdate = Shared.GetTime()
    self.timeSinceLastRTUpdate = Shared.GetTime()

    self.ejectCommVoteManager = VoteManager()
    self.ejectCommVoteManager:Initialize()
    self.ejectCommVoteManager:SetMinYesVoteNeeded(2)

    self.concedeVoteManager = VoteManager()
    self.concedeVoteManager:Initialize()
    self.concedeVoteManager:SetTeamPercentNeeded(kPercentNeededForVoteConcede)

    -- pings must exist before the TeamInfo entity starts watching us
    self:ResetPlayerPings()

    -- child classes can specify a custom team info class
    local teamInfoMapName = TeamInfo.kMapName
    if self.GetTeamInfoMapName then
        teamInfoMapName = self:GetTeamInfoMapName()
    end

    self.supplyUsed = 0

    local teamInfoEntity = Server.CreateEntity(teamInfoMapName)

    self.teamInfoEntityId = teamInfoEntity:GetId()
    teamInfoEntity:SetWatchTeam(self)

    self.entityTechIds = unique_set()
    self.techIdCount = {}

    self.eventListeners = {}

    self.warmupStructures = {}

    self.brain = nil
end


function PlayingTeam:OnInitialized()
    Team.OnInitialized(self)

    self:InitTechTree()
    self.requiredTechIds = self.techTree:GetRequiredTechIds()
    self.timeOfLastTechTreeUpdate = nil

    self.lastPlayedTeamAlertName = nil
    self.timeOfLastPlayedTeamAlert = nil

    self.timeSinceLastRTUpdate = Shared.GetTime()

    self.teamResources = 0
    self.totalTeamResourcesCollected = 0
    self:AddTeamResources(kPlayingTeamInitialTeamRes)

    self.ejectCommVoteManager:Reset()
    self.concedeVoteManager:Reset()

    self.conceded = false

    self:ResetPlayerPings()

    self.supplyUsed = 0

    InitMixin(self, TeamDeathMessageMixin)

end

-- Returns true if the ping was accepted.
-- pingPlayer (optional) is the pinging player entity; used to derive the
-- owner's client id (for client-side voice-mute filtering) and skill tier.
function PlayingTeam:SetPlayerPing(ownerId, position, name, pingPlayer)

    local now = Shared.GetTime()

    local lastTime = self.lastPingTimeByOwner[ownerId]
    if lastTime and lastTime + kPingSpamInterval > now then
        -- Print("SetPlayerPing: spam-blocked owner %s (%s)", ToString(ownerId), ToString(name))
        return false
    end

    -- pick a slot: reuse the owner's active slot, else an expired one, else evict the oldest
    local slot
    for i = 1, kMultiPingCount do
        local ping = self.playerPings[i]
        if ping.time > 0 and ping.ownerId == ownerId then
            slot = i
            break
        end
    end

    if not slot then
        for i = 1, kMultiPingCount do
            if self.playerPings[i].time + kCommanderPingDuration <= now then
                slot = i
                break
            end
        end
    end

    if not slot then
        slot = 1
        for i = 2, kMultiPingCount do
            if self.playerPings[i].time < self.playerPings[slot].time then
                slot = i
            end
        end
    end

    local pingClient = pingPlayer and Server.GetOwner(pingPlayer)

    local ping = self.playerPings[slot]
    ping.time = now
    ping.position = Vector(position)
    ping.name = name or ""
    ping.ownerId = ownerId
    ping.clientIndex = pingClient and pingClient:GetId() or -1
    ping.skillTier = GetPingSkillTier(pingPlayer)
    Print("[MultiPing] Server ping owner=%s clientIndex=%s slot=%s skillTier=%s",
        ToString(ownerId), ToString(ping.clientIndex), ToString(slot), ToString(ping.skillTier))
    -- captured here so the client can show the literal "Commander" label without
    -- depending on the pinger's live scoreboard IsCommander state (see GetPingName)
    ping.isCommander = ownerId == kCommanderOwnerId

    self.lastPingTimeByOwner[ownerId] = now

    return true

end

-- Compat entry point: commander minimap ping (NetworkMessages_Server),
-- 'ping' console command, and anything else vanilla routes here.
function PlayingTeam:SetCommanderPing(position, name, pingPlayer)

    if self:SetPlayerPing(kCommanderOwnerId, position, name or "Commander", pingPlayer) then
        -- feed the bot AI getters (commander pings only)
        self.lastCommPingTime = Shared.GetTime()
        self.lastCommPingPosition = Vector(position)
    end

end

function PlayingTeam:GetPlayerPings()
    return self.playerPings
end

-- ---------------------------------------------------------------------------
-- MNGA contextual ping marks: a 5s highlight on a target entity for the team.
-- ---------------------------------------------------------------------------

-- refund (target died/vanished while marked): everyone who pinged the mark
-- gets their 30s player ping cooldown back, and their 3s spam gate cleared
-- (that gate only ever limits commanders, who keep it).
local function ClearContextMark(team, mark, refund)

    if refund then
        for ownerId in pairs(mark.ownerIds) do
            if ownerId ~= kCommanderOwnerId then
                if MNGA_ResetPlayerPingCooldown then
                    MNGA_ResetPlayerPingCooldown(ownerId)
                end
                team.lastPingTimeByOwner[ownerId] = nil
            end
        end
    end

    for ownerId in pairs(mark.ownerIds) do
        mark.ownerIds[ownerId] = nil
    end

    mark.targetId = Entity.invalidId
    mark.targetTeam = 0
    mark.time = 0
    mark.clientIndex = -1
    mark.skillTier = 0
    mark.isCommander = false
end

-- Returns "new" (first mark: caller plays voice/text), "refresh" (already
-- marked: silent) or nil (spam-gated). ownerId shares the 3s spam gate with
-- SetPlayerPing; isCommander captures the literal "Commander" label.
function PlayingTeam:SetContextMark(target, pingPlayer, ownerId, isCommander)

    local now = Shared.GetTime()

    local lastTime = self.lastPingTimeByOwner[ownerId]
    if lastTime and lastTime + kPingSpamInterval > now then
        return nil
    end

    local targetId = target:GetId()
    local pingClient = pingPlayer and Server.GetOwner(pingPlayer)
    local clientIndex = pingClient and pingClient:GetId() or -1
    local tier = GetPingSkillTier(pingPlayer)

    self.lastPingTimeByOwner[ownerId] = now

    for i = 1, kContextMarkCount do
        local mark = self.contextMarks[i]
        if mark.targetId == targetId and mark.time + kContextMarkDuration > now then

            mark.time = now
            mark.ownerIds[ownerId] = true
            self.contextMarksVersion = self.contextMarksVersion + 1
            if MNGA_ContextPing_GetTierCategory(tier) > MNGA_ContextPing_GetTierCategory(mark.skillTier) then
                mark.clientIndex = clientIndex
                mark.skillTier = tier
                mark.isCommander = isCommander == true
            end
            return "refresh"

        end
    end

    -- an expired slot, else evict the oldest
    local slot
    for i = 1, kContextMarkCount do
        local mark = self.contextMarks[i]
        if mark.time + kContextMarkDuration <= now then
            slot = i
            break
        end
    end
    if not slot then
        slot = 1
        for i = 2, kContextMarkCount do
            if self.contextMarks[i].time < self.contextMarks[slot].time then
                slot = i
            end
        end
    end

    local mark = self.contextMarks[slot]
    for id in pairs(mark.ownerIds) do
        mark.ownerIds[id] = nil
    end
    mark.ownerIds[ownerId] = true
    mark.targetId = targetId
    mark.targetTeam = target:GetTeamNumber()
    mark.time = now
    mark.clientIndex = clientIndex
    mark.skillTier = tier
    mark.isCommander = isCommander == true
    self.contextMarksVersion = self.contextMarksVersion + 1

    return "new"

end

function PlayingTeam:GetContextMarks()
    return self.contextMarks
end

function PlayingTeam:GetContextMarksVersion()
    return self.contextMarksVersion or 0
end

-- Clears marks whose time ran out or whose target died, vanished or changed
-- team. Called from TeamInfo:UpdateInfo before networking; cheap when idle.
function PlayingTeam:PruneContextMarks()

    if not self.contextMarks then
        return
    end

    local now = Shared.GetTime()
    for i = 1, kContextMarkCount do

        local mark = self.contextMarks[i]
        if mark.targetId ~= Entity.invalidId then

            local clear = mark.time + kContextMarkDuration <= now
            local refund = false
            if not clear then
                -- target gone, dead (spectator replacement has no LiveMixin) or switched team
                local target = Shared.GetEntity(mark.targetId)
                clear = not target or not HasMixin(target, "Live") or not target:GetIsAlive()
                        or target:GetTeamNumber() ~= mark.targetTeam
                refund = clear
            end

            if clear then
                ClearContextMark(self, mark, refund)
                self.contextMarksVersion = self.contextMarksVersion + 1
            end

        end

    end

end

-- Marks follow entity replacement (marine -> exo, lifeform -> embryo, ...).
-- Death replaces the player with a spectator, which PruneContextMarks clears
-- (no LiveMixin / different team).
local oldOnEntityChange = PlayingTeam.OnEntityChange
function PlayingTeam:OnEntityChange(oldId, newId)

    oldOnEntityChange(self, oldId, newId)

    if self.contextMarks then
        for i = 1, kContextMarkCount do
            local mark = self.contextMarks[i]
            if mark.targetId == oldId and mark.targetId ~= Entity.invalidId then
                if newId and newId ~= Entity.invalidId then
                    mark.targetId = newId
                else
                    -- destroyed while marked: refund the pingers
                    ClearContextMark(self, mark, true)
                end
                self.contextMarksVersion = self.contextMarksVersion + 1
            end
        end
    end

end
