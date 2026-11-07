-- Nameplate visibility for field players (doc .claude/docs/team-health-bars.md): the mouse-over
-- nameplate shown Always / while a key is held, on teammates and uncloaked enemies in sight.
-- Sets vanilla's commander-view flag CommHealthBarsToggle plus the aimed-at text on those blips.
-- Client only, no network.

local kModeAlways = 0
local kModeOnPress = 1
local kModeVanilla = 2

local kKindNone = 0
local kKindPlayer = 1
local kKindStructure = 2

MNGA_TeamHealthBars = MNGA_TeamHealthBars or {}
local module = MNGA_TeamHealthBars

local kVanillaRangeSq = 13 * 13

local mode = kModeAlways
local showStructures = true
local held = false
local rangeWidened = false
local plateOpacity = 1

-- While forced bars are active, vanilla's 13 m nearby range (GUIUnitStatus) is raised to
-- 20 m via module.SetWideRange (TeamHealthBars_GUIUnitStatus.lua). Units 13-20 m away
-- that get no forced bar are dropped below, so vanilla status icons still stop at 13 m.
local function UpdateRange()
    local wide = mode == kModeAlways or (mode == kModeOnPress and held)
    if wide ~= rangeWidened then
        rangeWidened = wide
        if module.SetWideRange then
            module.SetWideRange(wide)
        end
    end
end

function module.GetIsRangeWidened()
    return rangeWidened
end

-- Applied by TeamHealthBars_GUIUnitStatus.lua, which reads the getter when it loads.
function module.GetPlateOpacity()
    return plateOpacity
end

function MNGA_TeamHealthBars_SetOpacity(percent)
    plateOpacity = Clamp(percent / 100, 0, 1)
    if module.SetPlateOpacity then
        module.SetPlateOpacity(plateOpacity)
    end
end

function MNGA_TeamHealthBars_Refresh()
    mode = Client.GetOptionInteger("shimizu/teamHealthBarsMode", kModeAlways)
    showStructures = Client.GetOptionInteger("shimizu/teamHealthBarsScope", 1) == 1
    if mode ~= kModeOnPress then
        held = false
    end
    UpdateRange()
    MNGA_TeamHealthBars_SetOpacity(Client.GetOptionInteger("shimizu/nameplateOpacity", 100))
end

function module.GetIsOnPressMode()
    return mode == kModeOnPress
end

function module.GetIsHeld()
    return held
end

function module.SetHeld(isHeld)
    if held ~= isHeld then
        held = isHeld
        UpdateRange()
    end
end

-- Kind is fixed for a unit, so work it out once per fresh state table (vanilla
-- rebuilds the table every 0.2 s and reuses it in between).
local function GetUnitKind(unitState, unit, player)
    if unit:isa("Weapon") then
        return kKindNone
    end
    -- Neutral units (no team) are left to vanilla.
    if not unitState.IsFriend and not GetAreEnemies(player, unit) then
        return kKindNone
    end
    -- Enemy spawn eggs and embryos (gestating players) are left fully to vanilla: forced
    -- plates would make them too easy to snipe. Kind none = vanilla flag and text untouched.
    if not unitState.IsFriend and (unit:isa("Egg") or unit:isa("Embryo")) then
        return kKindNone
    end
    if unitState.IsPlayer then
        return kKindPlayer
    end
    local mapName = unit:GetMapName()
    if (mapName == TechPoint.kMapName or mapName == ResourcePoint.kPointMapName)
        and unit.GetAttached and unit:GetAttached() ~= nil then
        return kKindNone
    end
    return kKindStructure
end

-- Line-of-sight check for forced plates (doc §3.10), same idea as vanilla's marked-enemy
-- check (ClientLOSMixin:UpdateMisc): a few rays per update, oldest results first. Client only.
local kTracesPerUpdate = 2
local kRecheckAge = 0.1   -- re-trace a unit when its result is older than this
local kVisibleHold = 0.2  -- keep a plate this long after the last passing ray (no flicker)
local kCleanupInterval = 5

local lastTraceTime = {}  -- entity id -> time of last ray
local lastPassTime = {}   -- entity id -> time of last ray that reached the unit
local traceBudgetTime = -1
local traceBudget = 0
local nextCleanupTime = 0

-- Players and babblers never block, so a teammate in front does not hide another's plate.
local function IgnoreForSight(entity)
    return entity:isa("Player") or entity:isa("Babbler")
end

local function CleanupSight(now)
    nextCleanupTime = now + kCleanupInterval
    for id, time in pairs(lastTraceTime) do
        if now - time > kCleanupInterval then
            lastTraceTime[id] = nil
            lastPassTime[id] = nil
        end
    end
end

local function GetIsInSight(player, unit, now)
    local id = unit:GetId()
    local tracedAt = lastTraceTime[id]
    if (not tracedAt or now - tracedAt > kRecheckAge) then
        if traceBudgetTime ~= now then
            traceBudgetTime = now
            traceBudget = kTracesPerUpdate
            if now > nextCleanupTime then
                CleanupSight(now)
            end
        end
        if traceBudget > 0 then
            traceBudget = traceBudget - 1
            lastTraceTime[id] = now
            local target = HasMixin(unit, "Target") and unit:GetEngagementPoint() or unit:GetOrigin()
            local trace = Shared.TraceRay(GetEntityEyePos(player), target,
                CollisionRep.Damage, PhysicsMask.Bullets, IgnoreForSight)
            if trace.fraction == 1 or trace.entity == unit then
                lastPassTime[id] = now
            end
        end
    end
    local passedAt = lastPassTime[id]
    return passedAt ~= nil and now - passedAt <= kVisibleHold
end

local originalGetStatusInfoForUnit = PlayerUI_GetStatusInfoForUnit
function PlayerUI_GetStatusInfoForUnit(player, unit)
    local unitState = originalGetStatusInfoForUnit(player, unit)
    if not unitState then
        return unitState
    end

    -- Remember vanilla's values (commander H, blanked text) on each fresh table so turning
    -- ours off restores them.
    local kind = unitState.mngaTeamHPKind
    if kind == nil then
        unitState.mngaTeamHPBase = unitState.CommHealthBarsToggle and true or false
        unitState.mngaTeamHPBaseName = unitState.Name
        unitState.mngaTeamHPBaseAction = unitState.Action
        unitState.mngaTeamHPBaseHint = unitState.Hint
        kind = GetUnitKind(unitState, unit, player)
        unitState.mngaTeamHPKind = kind
        unitState.mngaTeamHPEnemy = not unitState.IsFriend
    end

    local force = false
    if kind ~= kKindNone and (mode == kModeAlways or (mode == kModeOnPress and held)) then
        local teamNumber = player:GetTeamNumber()
        force = (teamNumber == kTeam1Index or teamNumber == kTeam2Index)
            and not player:isa("Commander")
            and (kind == kKindPlayer or showStructures)
        -- Enemies: not cloaked, same test as vanilla visibleToPlayer (Player_Client.lua:501).
        if force and unitState.mngaTeamHPEnemy then
            force = not (HasMixin(unit, "Cloakable") and (unit:GetIsCloaked()
                or (kind == kKindPlayer and unit:GetCloakFraction() > 0.2)))
        end
        -- Models the engine did not draw last frame are out of sight: hide, no ray needed (§3.9).
        if force and unit.GetWasRenderedLastFrame and not unit:GetWasRenderedLastFrame() then
            force = false
        end
        -- Drawn is not enough (culling is coarse): a line-of-sight ray decides (§3.10).
        if force then
            force = GetIsInSight(player, unit, Shared.GetTime())
        end
    end

    -- Keep vanilla's 13 m for everything we don't force (crosshair and marked units keep 20 m).
    -- Not for commanders: vanilla lists every unit for them with no range (their origin is the
    -- overhead camera), so a cutoff here hid all their blips, H bars included.
    if rangeWidened and not force
        and not player:isa("Commander")
        and GetDistanceSquaredToEntity(player, unit) > kVanillaRangeSq
        and unit ~= player:GetCrossHairTarget()
        and not player:GetHasMarkedTarget(unit) then
        return nil
    end

    unitState.CommHealthBarsToggle = unitState.mngaTeamHPBase or force

    -- Vanilla blanks name/action/hint unless aimed at; forced units get the full text.
    if force then
        if unitState.mngaTeamHPName == nil then
            unitState.mngaTeamHPName = unit:GetUnitName(player) or ""
            unitState.mngaTeamHPAction = unit:GetActionName(player) or ""
            unitState.mngaTeamHPHint = unit:GetUnitHint2(player) or ""
        end
        unitState.Name = unitState.mngaTeamHPName
        unitState.Action = unitState.mngaTeamHPAction
        unitState.Hint = unitState.mngaTeamHPHint
    else
        unitState.Name = unitState.mngaTeamHPBaseName
        unitState.Action = unitState.mngaTeamHPBaseAction
        unitState.Hint = unitState.mngaTeamHPBaseHint
    end

    return unitState
end

MNGA_TeamHealthBars_Refresh()
