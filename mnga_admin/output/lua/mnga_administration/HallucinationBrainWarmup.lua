-- Server-side warm-up for the full bot brains used by player hallucinations.
-- One lifeform is warmed at a time so the intentional cold-start work is
-- spread across pre-round frames instead of landing on the first live cast.

if not Server then return end

local kWarmupDelay = 60
local kWarmupDurationPerLifeform = 0.75
local kWarmupGap = 0.1
local kWarmupTimeout = 3

local kWarmupClasses =
{
    { Name = "Skulk", GetMapName = function() return SkulkHallucination.kMapName end },
    { Name = "Gorge", GetMapName = function() return GorgeHallucination.kMapName end },
    { Name = "Lerk", GetMapName = function() return LerkHallucination.kMapName end },
    { Name = "Fade", GetMapName = function() return FadeHallucination.kMapName end },
    { Name = "Onos", GetMapName = function() return OnosHallucination.kMapName end }
}

local WarmupState =
{
    Pending = false,
    Complete = false,
    Index = 1,
    NextActionTime = 0,
    ActiveEntity = nil,
    ActiveName = nil,
    ActiveStartTime = 0,
    BrainReadyTime = nil
}

local function GetWarmupOrigin()
    local Hives = GetEntitiesForTeam("Hive", kAlienTeamType)
    if Hives[1] then
        return Hives[1]:GetOrigin() + Vector(0, 0.5, 0)
    end

    local TechPoints = GetEntities("TechPoint")
    if TechPoints[1] then
        return TechPoints[1]:GetOrigin() + Vector(0, 0.5, 0)
    end

    return nil
end

local function DestroyActiveWarmup(Reason)
    local Entity = WarmupState.ActiveEntity
    if Entity and IsValid(Entity) then
        if Entity.brain and Entity.brain.OnDestroy then
            Entity.brain:OnDestroy()
        end
        DestroyEntity(Entity)
    end


    WarmupState.ActiveEntity = nil
    WarmupState.ActiveName = nil
    WarmupState.ActiveStartTime = 0
    WarmupState.BrainReadyTime = nil
end

local function AbortWarmup(Reason)
    if WarmupState.ActiveEntity then
        DestroyActiveWarmup(Reason)
    end

    WarmupState.Pending = false
end

local function StartNextWarmup(CurrentTime)
    local Entry = kWarmupClasses[WarmupState.Index]
    if not Entry then
        WarmupState.Pending = false
        WarmupState.Complete = true
        return
    end

    local Origin = GetWarmupOrigin()
    if not Origin then
        WarmupState.NextActionTime = CurrentTime + 0.25
        return
    end

    local Entity = CreateEntity(Entry.GetMapName(), Origin, kAlienTeamType)

    if not Entity then
        AbortWarmup("create_failed_" .. Entry.Name)
        return
    end

    Entity.mngaHallucinationWarmup = true
    WarmupState.ActiveEntity = Entity
    WarmupState.ActiveName = Entry.Name
    WarmupState.ActiveStartTime = CurrentTime
    WarmupState.BrainReadyTime = nil

end

local function UpdateWarmup()
    if not WarmupState.Pending or WarmupState.Complete then return end

    local Gamerules = GetGamerules and GetGamerules()
    if not Gamerules then return end

    if Gamerules:GetGameState() >= kGameState.Countdown then
        AbortWarmup("game_entered_countdown")
        return
    end

    local CurrentTime = Shared.GetTime()
    local Entity = WarmupState.ActiveEntity
    if Entity then
        if not IsValid(Entity) then
            AbortWarmup("entity_destroyed_early_" .. tostring(WarmupState.ActiveName))
            return
        end

        if Entity.brain and not WarmupState.BrainReadyTime then
            WarmupState.BrainReadyTime = CurrentTime
        end

        if WarmupState.BrainReadyTime
            and CurrentTime - WarmupState.BrainReadyTime >= kWarmupDurationPerLifeform then
            DestroyActiveWarmup("warmed")
            WarmupState.Index = WarmupState.Index + 1
            WarmupState.NextActionTime = CurrentTime + kWarmupGap
        elseif CurrentTime - WarmupState.ActiveStartTime >= kWarmupTimeout then
            AbortWarmup("brain_timeout_" .. tostring(WarmupState.ActiveName))
        end
        return
    end

    if CurrentTime >= WarmupState.NextActionTime then
        StartNextWarmup(CurrentTime)
    end
end

Event.Hook("MapPostLoad", function()
    WarmupState.Pending = true
    WarmupState.Complete = false
    WarmupState.Index = 1
    WarmupState.NextActionTime = Shared.GetTime() + kWarmupDelay
end)

Event.Hook("UpdateServer", UpdateWarmup)
