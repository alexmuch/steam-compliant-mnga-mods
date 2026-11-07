-- ======= Copyright (c) 2003-2016, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua/TeamInfo.lua
--
-- TeamInfo is used to sync information about a team to clients.
-- A client on team 1 or 2 will only receive team info regarding their
-- own team while a client on the kSpectatorIndex team will receive both
-- teams info.
--
-- Created by Brian Cronin (brianc@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================
Script.Load("lua/TeamMixin.lua")

class 'TeamInfo' (Entity)

TeamInfo.kMapName = "TeamInfo"

TeamInfo.kTechTreeUpdateInterval = 1

-- max 100 tres/min, max 1000 minute game; should be enough 
kMaxTotalTeamResources = 100000
kMaxTotalPersonalResources = 100000

local networkVars =
{
    teamResources =  "float (0 to " .. kMaxTeamResources .. " by 0.1 [ 4 ])",
    totalTeamResources = "float (0 to " .. kMaxTotalTeamResources .. " by 1 [ 1 ])",
    personalResources = "float (0 to " .. kMaxTotalPersonalResources .. " by 0.1) [ 4 ]",
    numResourceTowers = "integer (0 to 99)",
    numCapturedResPoints = "integer (0 to 99)",
    latestResearchId = "integer",
    numCapturedTechPoint = "integer (0 to 99)",
    lastCommIsBot = "boolean",
    techActiveMask = "integer",
    techOwnedMask = "integer",
    playerCount = "integer (0 to " .. kMaxPlayers - 1 .. ")",
    spawnQueueTotal = "integer (0 to 64)",  --max val should be ref'd from somewhere
    supplyUsed = "integer (0 to " .. 10 * kSupplyPerTechpoint .. ")",
    kills = "integer (0 to 9999)",
    -- MNGA marine top bar: completed, living ARCs. Kept on TeamInfo so this
    -- composes with the existing multi-ping replacement instead of requiring
    -- a second full MarineTeamInfo replacement.
    numARCs = "integer (0 to 31)"
}

-- MNGA multi-ping: number of simultaneous ping slots per team.
-- Must be identical in both VMs (this file loads in both); netvars are load-time frozen.
kMultiPingCount = 10

-- field names precomputed once so the per-frame GUI loops don't concat strings
local kPingTimeVars = {}
local kPingPositionVars = {}
local kPingClientVars = {}
local kPingTierVars = {}
local kPingCommanderVars = {}

for i = 1, kMultiPingCount do
    kPingTimeVars[i] = "pingTime" .. i
    kPingPositionVars[i] = "pingPosition" .. i
    kPingClientVars[i] = "pingClient" .. i
    kPingTierVars[i] = "pingTier" .. i
    kPingCommanderVars[i] = "pingIsCommander" .. i
    networkVars[kPingTimeVars[i]] = "time"
    networkVars[kPingPositionVars[i]] = "vector"
    -- owner's client id (client:GetId()); same key ChatUI_GetClientMuted uses.
    -- "entityid" matches the type of the clientIndex netvar in Player.lua.
    -- The pinger's NAME is NOT networked here: it is derived client-side from
    -- this client index via the scoreboard (see GetPingName). Networking 10
    -- "string (64)" fields on TeamInfo -- which is relevant to the whole team
    -- at infinite distance -- was the dominant per-tick server networking cost.
    networkVars[kPingClientVars[i]] = "entityid"
    -- MNGA extends skill tiers through tier 9. This range must include every
    -- value produced by PlayingTeamMultiPing or clients cannot receive the
    -- correct tier/color for high-skill ping owners.
    networkVars[kPingTierVars[i]] = "integer (0 to 9)"
    -- whether this slot is a commander ping, captured at ping time (owner id
    -- -1). Lets GetPingName show the literal "Commander" label robustly --
    -- deriving it from the live scoreboard IsCommander flag would flip the
    -- label to the player's name the instant they leave the chair/hive while
    -- the ping is still on screen. A boolean is ~1 bit, unlike the dropped
    -- "string (64)" name fields, so the perf cost is negligible.
    networkVars[kPingCommanderVars[i]] = "boolean"
end

-- MNGA contextual ping: highlighted target slots (see ContextPingShared.lua).
-- Same owner/tier/commander scheme as the ping slots above; the pinger name is
-- derived client-side from markClient via the scoreboard (GetMarkName).
Script.Load("lua/mnga_administration/ContextPingShared.lua")

local kMarkTargetVars = {}
local kMarkTimeVars = {}
local kMarkClientVars = {}
local kMarkTierVars = {}
local kMarkCommanderVars = {}

for i = 1, kContextMarkCount do
    kMarkTargetVars[i] = "markTarget" .. i
    kMarkTimeVars[i] = "markTime" .. i
    kMarkClientVars[i] = "markClient" .. i
    kMarkTierVars[i] = "markTier" .. i
    kMarkCommanderVars[i] = "markIsCommander" .. i
    networkVars[kMarkTargetVars[i]] = "entityid"
    networkVars[kMarkTimeVars[i]] = "time"
    networkVars[kMarkClientVars[i]] = "entityid"
    networkVars[kMarkTierVars[i]] = "integer (0 to 9)"
    networkVars[kMarkCommanderVars[i]] = "boolean"
end

AddMixinNetworkVars(TeamMixin, networkVars)

-- Relevant techs must be ordered with children techs coming after their parents
TeamInfo.kRelevantTechIdsMarine =
{

    kTechId.ShotgunTech,
    --kTechId.HeavyMachineGunTech,
    kTechId.MinesTech,
    kTechId.WelderTech,
    kTechId.GrenadeTech,
    
    kTechId.AdvancedArmory,
    kTechId.AdvancedArmoryUpgrade,
    kTechId.AdvancedWeaponry,

    kTechId.Weapons1,
    kTechId.Weapons2,
    kTechId.Weapons3,
    kTechId.Armor1,
    kTechId.Armor2,
    kTechId.Armor3,

    kTechId.PrototypeLab,
    kTechId.JetpackTech,
    kTechId.ExosuitTech,
    kTechId.DualMinigunTech,

    kTechId.ARCRoboticsFactory,
    kTechId.UpgradeRoboticsFactory,
    kTechId.MACEMPTech,
    kTechId.MACSpeedTech,
    
    kTechId.Observatory,
    kTechId.PhaseTech,

    kTechId.AdvancedMarineSupport,
}

TeamInfo.kRelevantTechIdsAlien =
{

    kTechId.CragHive,
    kTechId.UpgradeToCragHive,
    kTechId.Shell,
    kTechId.TwoShells,
    kTechId.ThreeShells,
    
    kTechId.ShadeHive,
    kTechId.UpgradeToShadeHive,
    kTechId.Veil,
    kTechId.TwoVeils,
    kTechId.ThreeVeils,
    
    kTechId.ShiftHive,
    kTechId.UpgradeToShiftHive,
    kTechId.Spur,
    kTechId.TwoSpurs,
    kTechId.ThreeSpurs,
    
    kTechId.ResearchBioMassOne,
    kTechId.ResearchBioMassTwo,
    kTechId.ResearchBioMassThree,

    kTechId.Leap,
    kTechId.Xenocide,
    kTechId.BileBomb,
    kTechId.WebTech,
    kTechId.Umbra,
    kTechId.Spores,
    kTechId.MetabolizeEnergy,
    kTechId.MetabolizeHealth,
    kTechId.Stab,
    kTechId.Charge,
    kTechId.BoneShield,
    kTechId.Stomp,
    
}

local function CreateRelevantIdMaskMarine()

    local t = {}

    for i, techId in ipairs(TeamInfo.kRelevantTechIdsMarine) do

        local s = EnumToString(kTechId, techId)
        t[i] = s

    end

    
    TeamInfo.kRelevantIdMaskMarine = CreateBitMask(t)

end

local function CreateRelevantIdMaskAlien()

    local t = {}

    for i,techId in ipairs(TeamInfo.kRelevantTechIdsAlien) do

        local s = EnumToString(kTechId, techId)
        t[i] = s

    end


    TeamInfo.kRelevantIdMaskAlien = CreateBitMask(t)

end

function TeamInfo:OnCreate()

    Entity.OnCreate(self)
    
    CreateRelevantIdMaskMarine()
    CreateRelevantIdMaskAlien()
    
    if Server then
    
        self:SetUpdates(true, kRealTimeUpdateRate)
        
		self:Reset()
        
    end
    
    InitMixin(self, TeamMixin)
    
end

if Server then

    function TeamInfo:Reset()
    
        self.teamResources = 0
        self.personalResources = 0
        self.numResourceTowers = 0
        self.latestResearchId = 0
        self.researchDisplayTime = 0
        self.lastTechPriority = 0
        for i = 1, kMultiPingCount do
            self[kPingTimeVars[i]] = 0
            self[kPingPositionVars[i]] = Vector(0,0,0)
            self[kPingClientVars[i]] = -1
            self[kPingTierVars[i]] = 0
            self[kPingCommanderVars[i]] = false
        end
        for i = 1, kContextMarkCount do
            self[kMarkTargetVars[i]] = Entity.invalidId
            self[kMarkTimeVars[i]] = 0
            self[kMarkClientVars[i]] = -1
            self[kMarkTierVars[i]] = 0
            self[kMarkCommanderVars[i]] = false
        end
        self.contextMarksVersionCopied = nil
        self.lastCommIsBot = false
        self.lastCommLoginTime = 0
        self.totalTeamResources = 0
        self.techActiveMask = 0
        self.techOwnedMask = 0
        self.playerCount = 0
        self.spawnQueueTotal = 0
        self.workerCount = 0
        self.kills = 0
        self.supplyUsed = 0
        self.numARCs = 0
        self.nextARCCountUpdate = 0
        self.userTrackersDirty = true
    
    end
    
end

if Client then
    
    function TeamInfo:OnInitialized()
        
        Entity.OnInitialized(self)
        
        -- Hook up some callbacks for the GUI system.
        -- (These respect relevancy because they will only receive updates for TeamInfo that are
        -- relevant to the current player, eg both if player is spectating.)
        
        -- Notify GUI system when a team's resources change.
        self:AddFieldWatcher("teamResources",
            function(self2)
                local teamNumber = self2:GetTeamNumber()
                local eventName = string.format("OnTeam%dResourcesChanged", teamNumber)
                GetGlobalEventDispatcher():FireEvent(eventName, self2.teamResources)
                return true -- preserve field watcher
            end)
        
        -- Notify GUI system when a team's RT-count changes.
        self:AddFieldWatcher("numResourceTowers",
            function(self2)
                local teamNumber = self2:GetTeamNumber()
                local eventName = string.format("OnTeam%dResourceTowerCountChanged", teamNumber)
                GetGlobalEventDispatcher():FireEvent(eventName, self2.numResourceTowers)
                return true -- preserve field watcher
            end)
    
        -- Notify GUI system when a team's consumed supply changes.
        self:AddFieldWatcher("supplyUsed",
        function(self2)
            local teamNumber = self2:GetTeamNumber()
            local eventName = string.format("OnTeam%dSupplyUsedChanged", teamNumber)
            GetGlobalEventDispatcher():FireEvent(eventName, self2.supplyUsed)
            return true -- preserve field watcher
        end)
    
        -- Notify GUI system when a team's count of respawning players changes.
        self:AddFieldWatcher("spawnQueueTotal",
        function(self2)
            local teamNumber = self2:GetTeamNumber()
            local eventName = string.format("OnTeam%dSpawnQueueTotalChanged", teamNumber)
            GetGlobalEventDispatcher():FireEvent(eventName, self2.spawnQueueTotal)
            return true -- preserve field watcher
        end)

        -- Only MarineTeamInfo will produce a non-zero value. This mirrors the
        -- existing marine-only infantry portal event used by the top bar.
        self:AddFieldWatcher("numARCs",
        function(self2)
            if self2:GetTeamNumber() == kTeam1Index then
                GetGlobalEventDispatcher():FireEvent("OnARCCountChanged", self2.numARCs)
            end
            return true
        end)
        
        -- Fire an event signifying that a new TeamInfo has just been initialized.
        GetGlobalEventDispatcher():FireEvent("OnTeamInfoInitialized", self)
        
    end
    
end

function TeamInfo:GetSpawnQueueTotal()
    return self.spawnQueueTotal
end

function TeamInfo:UpdateInfo()

    if self.team then
    
        self:SetTeamNumber(self.team:GetTeamNumber())
        self.teamResources = self.team:GetTeamResources()
        self.playerCount = Clamp(self.team:GetNumPlayers(), 0, 31)
        self.totalTeamResources = self.team:GetTotalTeamResources()
        self.personalResources = 0
        for index, player in ipairs(self.team:GetPlayers()) do
            self.personalResources = self.personalResources + player:GetResources()
        end
        
        local rtCount = 0
        local rtActiveCount = 0
        local rts = GetEntitiesForTeam("ResourceTower", self:GetTeamNumber())
        for index, rt in ipairs(rts) do
        
            if rt:GetIsAlive() then
                rtCount = rtCount + 1
                if rt:GetIsCollecting() then
                    rtActiveCount = rtActiveCount + 1
                end
            end
            
        end
        
        self.numCapturedResPoints = rtCount
        self.numResourceTowers = rtActiveCount
        self.kills = self.team:GetKills()
        
        if Server then
        
            if self.lastTechTreeUpdate == nil or (Shared.GetTime() > (self.lastTechTreeUpdate + TeamInfo.kTechTreeUpdateInterval)) then
                if not GetGamerules():GetGameStarted() then
                    self.techActiveMask = 0
                    self.techOwnedMask = 0
                else
                    self:UpdateTechTreeInfo(self.team:GetTechTree())    
                end
            end
        
            if self.latestResearchId ~= 0 and self.researchDisplayTime < Shared.GetTime() then
            
                self.latestResearchId = 0
                self.researchDisplayTime = 0
                self.lastTechPriority = 0
                
            end
            
            local team = self:GetTeam()
            self.numCapturedTechPoint = team:GetNumCapturedTechPoints()
            
            local pings = team.GetPlayerPings and team:GetPlayerPings()
            if pings then
                for i = 1, kMultiPingCount do
                    local ping = pings[i]
                    if ping then
                        self[kPingTimeVars[i]] = ping.time
                        self[kPingPositionVars[i]] = ping.position
                        self[kPingClientVars[i]] = ping.clientIndex
                        self[kPingTierVars[i]] = ping.skillTier
                        self[kPingCommanderVars[i]] = ping.isCommander == true
                    end
                end
            end

            -- contextual ping marks; PruneContextMarks drops dead/missing
            -- targets. The netvars are only rewritten when a mark changed.
            local marks = team.GetContextMarks and team:GetContextMarks()
            if marks then
                team:PruneContextMarks()
                local version = team:GetContextMarksVersion()
                if version ~= self.contextMarksVersionCopied then
                    self.contextMarksVersionCopied = version
                    for i = 1, kContextMarkCount do
                        local mark = marks[i]
                        if mark then
                            self[kMarkTargetVars[i]] = mark.targetId
                            self[kMarkTimeVars[i]] = mark.time
                            self[kMarkClientVars[i]] = mark.clientIndex
                            self[kMarkTierVars[i]] = mark.skillTier
                            self[kMarkCommanderVars[i]] = mark.isCommander == true
                        end
                    end
                end
            end
            
            self.supplyUsed = team:GetSupplyUsed()
            
            self.spawnQueueTotal = team:GetTotalInRespawnQueue()

            if self:GetTeamNumber() == kTeam1Index and
                    Shared.GetTime() >= self.nextARCCountUpdate then
                local arcCount = 0
                local arcs = GetEntitiesForTeam("ARC", kTeam1Index)
                for i = 1, #arcs do
                    local arc = arcs[i]
                    -- ARCs are manufactured units and do not use ConstructMixin;
                    -- the ARC entity is created only when manufacture completes.
                    if arc:GetIsAlive() then
                        arcCount = arcCount + 1
                    end
                end

                arcCount = math.min(arcCount, 31)
                if arcCount ~= self.numARCs then
                    self.numARCs = arcCount
                end
                self.nextARCCountUpdate = Shared.GetTime() + 1
            end

            if self.userTrackersDirty then
                self:UpdateUserTrackers()
                self.userTrackersDirty = false
            end
            
        end
        
    end
    
end

function TeamInfo:SetUserTrackersDirty()
    self.userTrackersDirty = true
end

function TeamInfo:UpdateUserTrackers()
    -- for others to override.
end

function TeamInfo:GetRelevantTech()
    if self:GetTeamType() == kMarineTeamType then
        return TeamInfo.kRelevantIdMaskMarine, TeamInfo.kRelevantTechIdsMarine
    else
        return TeamInfo.kRelevantIdMaskAlien, TeamInfo.kRelevantTechIdsAlien
    end
end

function TeamInfo:GetSupplyUsed()
    return self.supplyUsed
end

function TeamInfo:GetNumWorkers()
    return self.workerCount
end

function TeamInfo:GetPingCount()
    return kMultiPingCount
end

-- Slot with the most recent ping; used by the no-slot compat getters below.
-- Player:UpdateCommanderPingSound relies on no-arg GetPingTime() increasing
-- whenever ANY new ping arrives, which this provides.
function TeamInfo:GetLatestPingSlot()

    local bestSlot = 1
    local bestTime = -1
    for i = 1, kMultiPingCount do
        local t = self[kPingTimeVars[i]] or 0
        if t > bestTime then
            bestTime = t
            bestSlot = i
        end
    end
    return bestSlot

end

function TeamInfo:GetPingTime(slot)
    slot = slot or self:GetLatestPingSlot()
    return self[kPingTimeVars[slot]] or 0
end

function TeamInfo:GetPingPosition(slot)
    slot = slot or self:GetLatestPingSlot()
    return self[kPingPositionVars[slot]] or Vector(0,0,0)
end

-- The pinger name is NOT a netvar; derive it client-side from the networked
-- owner client index via the scoreboard (NS2 already replicates every player's
-- name there, keyed by the same client index). This is why the 10 "string (64)"
-- ping-name netvars could be dropped. Returns "" on the server / when the
-- scoreboard record isn't available yet (the GUI tolerates an empty name).
function TeamInfo:GetPingName(slot)
    slot = slot or self:GetLatestPingSlot()
    -- Commander pings kept the literal "Commander" label in the
    -- networked-string version. The flag is captured at ping time, so the label
    -- is stable for the ping's whole lifetime even if the commander leaves the
    -- chair/hive while it is still on screen.
    if self[kPingCommanderVars[slot]] then
        return "Commander"
    end
    local clientIndex = self[kPingClientVars[slot]] or -1
    if clientIndex > 0 and Scoreboard_GetPlayerRecord then
        local record = Scoreboard_GetPlayerRecord(clientIndex)
        if record then
            return record.Name or ""
        end
    end
    return ""
end

function TeamInfo:GetPingOwnerClientIndex(slot)
    slot = slot or self:GetLatestPingSlot()
    return self[kPingClientVars[slot]] or -1
end

function TeamInfo:GetPingOwnerTier(slot)
    slot = slot or self:GetLatestPingSlot()
    return self[kPingTierVars[slot]] or 0
end

function TeamInfo:GetMarkCount()
    return kContextMarkCount
end

function TeamInfo:GetMarkTarget(slot)
    return self[kMarkTargetVars[slot]] or Entity.invalidId
end

function TeamInfo:GetMarkTime(slot)
    return self[kMarkTimeVars[slot]] or 0
end

function TeamInfo:GetMarkOwnerClientIndex(slot)
    return self[kMarkClientVars[slot]] or -1
end

function TeamInfo:GetMarkOwnerTier(slot)
    return self[kMarkTierVars[slot]] or 0
end

-- Same derivation as GetPingName: "Commander" for commander marks, otherwise
-- the scoreboard name for the owner's client index.
function TeamInfo:GetMarkName(slot)
    if self[kMarkCommanderVars[slot]] then
        return "Commander"
    end
    local clientIndex = self[kMarkClientVars[slot]] or -1
    if clientIndex > 0 and Scoreboard_GetPlayerRecord then
        local record = Scoreboard_GetPlayerRecord(clientIndex)
        if record then
            return record.Name or ""
        end
    end
    return ""
end

function TeamInfo:GetCommanderPingName()
    return self:GetPingName()
end

function TeamInfo:GetLastCommIsBot()
    return self.lastCommIsBot
end

function TeamInfo:SetWatchTeam(team)

    self.team = team
    self:SetTeamNumber(team:GetTeamNumber())
    self:UpdateInfo()
    self:UpdateRelevancy()
    
end

function TeamInfo:GetNumCapturedResPoints()
    return self.numCapturedResPoints
end

function TeamInfo:OnCommanderLogin( commanderPlayer, forced )

    self.lastCommIsBot = commanderPlayer:GetIsVirtual()
	if forced or GetGamerules():GetGameState() > kGameState.PreGame then
		if self.lastCommLoginTime == 0 then
			commanderPlayer:SetResources(0)
		end
		self.lastCommLoginTime = Shared.GetTime()
	end
end

function TeamInfo:GetTeamResources()
    return self.teamResources
end

function TeamInfo:GetPersonalResources()
    return self.personalResources
end

function TeamInfo:GetNumResourceTowers()
    return self.numResourceTowers
end

function TeamInfo:GetKills()
    return self.kills
end

function TeamInfo:UpdateRelevancy()

    self:SetRelevancyDistance(Math.infinity)
    
    local mask = 0
    
    if self:GetTeamNumber() == kTeam1Index then
        mask = kRelevantToTeam1
    elseif self:GetTeamNumber() == kTeam2Index then
        mask = kRelevantToTeam2
    end
        
    self:SetExcludeRelevancyMask(mask)

end

function TeamInfo:OnUpdate(deltaTime)
    self:UpdateInfo()
end

function TeamInfo:SetLatestResearchedTech(researchId, displayTime, techPriority)
    
    if techPriority >= self.lastTechPriority then
    
        self.latestResearchId = researchId
        self.researchDisplayTime = displayTime
        self.lastTechPriority = techPriority
        
    end
    
end

function TeamInfo:UpdateTechTreeInfo(techTree)

    if not techTree then return end

    local relevantIdMask, relevantTechIds = self:GetRelevantTech()
    for i,techId in ipairs(relevantTechIds) do

        local techNode = techTree:GetTechNode(techId)

        if techNode and relevantIdMask then

            self:UpdateBitmasks(techId, techNode)

        end

    end
    
    self.lastTechTreeUpdate = Shared.GetTime()

end

function TeamInfo:GetNumCapturedTechPoints()
    return self.numCapturedTechPoint
end

function TeamInfo:GetLatestResearchedTech()
    return self.latestResearchId
end

function TeamInfo:GetTotalTeamResources()
    return self.totalTeamResources
end

function TeamInfo:GetTeamTechTreeInfo()
    return self.techActiveMask, self.techOwnedMask
end

--[[
A - Active
O - Owned
-----
A O |
-----
0 0 | None
1 0 | Researching
0 1 | Lost
1 1 | Researched
-----]]

function TeamInfo:UpdateBitmasks(techId, techNode)

    local relevantIdMask, relevantTechIds = self:GetRelevantTech()

    local techIdString = EnumToString(kTechId, techId)
    local mask = relevantIdMask[techIdString]
    
    -- Tech researching or researched
    if (techNode:GetResearching() and not techNode:GetResearched()) or techNode:GetHasTech() then
        self.techActiveMask = bit.bor(self.techActiveMask, mask)
    else
        self.techActiveMask = bit.band(self.techActiveMask, bit.bnot(mask))
    end
    
    -- Tech has been owned at some point
    if techNode:GetHasTech() then
        self.techOwnedMask = bit.bor(self.techOwnedMask, mask)
    end
    
    -- Hide prerequisite techs when this tech has been researched
    if techNode:GetResearched() or (techNode:GetIsSpecial() and techNode:GetHasTech()) then
        local preq1 = techNode:GetPrereq1()
        local preq2 = techNode:GetPrereq2()
        if preq1 ~= nil then
            local msk = relevantIdMask[EnumToString(kTechId, preq1)]
            if msk then
                self.techActiveMask = bit.band(self.techActiveMask, bit.bnot(msk))
                self.techOwnedMask = bit.band(self.techOwnedMask, bit.bnot(msk))
            end
        end
        if preq2 ~= nil then
            local msk = relevantIdMask[EnumToString(kTechId, preq2)]
            if msk then
                self.techActiveMask = bit.band(self.techActiveMask, bit.bnot(msk))
                self.techOwnedMask = bit.band(self.techOwnedMask, bit.bnot(msk))
            end
        end
    end

end

function TeamInfo:GetPlayerCount()
    return self.playerCount
end

Shared.LinkClassToMap("TeamInfo", TeamInfo.kMapName, networkVars)

function TeamInfo_GetUserTrackerNetvarName(weaponMapName)
    local id = string.gsub(weaponMapName, "+", "plus")
    return string.format("num%sUsers", id)
end

function TeamInfo_SetUserTrackersDirty(teamIndex)

    if not Server then return end

    assert(teamIndex)

    -- kTeam1Index
    -- kTeam2Index
    local teamInfoEnt = GetTeamInfoEntity(teamIndex)
    if teamInfoEnt then
        teamInfoEnt:SetUserTrackersDirty()
    end

end
