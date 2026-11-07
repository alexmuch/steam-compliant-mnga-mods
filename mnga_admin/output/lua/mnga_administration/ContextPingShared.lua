-- MNGA contextual ping: shared constants, target eligibility, target picking and
-- classification. Loaded in every VM that needs it (Script.Load is idempotent:
-- this file only defines constants and functions).
--
-- See .claude/docs/contextual-ping.md.

-- Master switch. false = every ping is the plain location ping (pre-contextual behaviour).
kMNGAContextPingEnabled = true

-- Viewer presentation. Alien viewers get the world glow
-- (ContextPingHighlight_Client.lua). Marine viewers get the commander
-- attack-order style target icon instead (ContextPingTargetIcon_Client.lua);
-- the marine glow felt like an unfair advantage.
kMNGAContextPingMarineIcon = true
-- true = enemy target icons only while the target is sighted. false = while
-- the target is network relevant (through walls).
kMNGAContextPingIconRequireSighted = true
-- Icon opacity at the crosshair; it rises to 1 at kFadeRadius px away.
-- (Vanilla waypoints fade to ~0; kept visible for coordination.)
kMNGAContextPingIconMinAlpha = 0.5

-- Simultaneous highlighted targets per team. Netvars are frozen at load time,
-- so this must be identical in both VMs (TeamInfoMultiPing.lua uses it).
kContextMarkCount = 8
kContextMarkDuration = 6

kContextPingRange = 40
local kAssistRadius = 0.3          -- capsule "aim assist" radius for entity picks
local kPickupAssistRange = 1.5     -- dropped item search radius around the location ping point

kContextPingKind =
{
    Lifeform = 1,           -- marine pings Gorge/Lerk/Fade/Onos
    EnemyPlayer = 2,        -- alien pings a marine/exo
    EnemyStructure = 3,
    FriendlyStructure = 4,
    Pickup = 5,             -- marine pings a dropped weapon/jetpack/exosuit
}

local kLifeforms = { "Gorge", "Lerk", "Fade", "Onos" }

-- Non-constructed units that still count as structure targets. Everything
-- built (Hive, CC, Tunnel, Hydra, Sentry, PowerPoint...) has ConstructMixin.
-- NOTE: MapBlipMixin can NOT be used for this: most structures only init it
-- in the Server VM, so a client-side check would reject them.
local kUnitClasses = { "ARC", "MAC", "Drifter", "DrifterEgg", "Egg", "Hallucination" }

local function IsStructureOrUnit(target)
    if HasMixin(target, "Construct") then
        return true
    end
    for i = 1, #kUnitClasses do
        if target:isa(kUnitClasses[i]) then
            return true
        end
    end
    return false
end

-- class, radio command id, display name. First match wins.
local kPickups =
{
    { "Rifle", "cp_pickup_rifle", "Rifle" },
    { "Shotgun", "cp_pickup_shotgun", "Shotgun" },
    { "Flamethrower", "cp_pickup_flamethrower", "Flamethrower" },
    { "GrenadeLauncher", "cp_pickup_gl", "Grenade Launcher" },
    { "HeavyMachineGun", "cp_pickup_hmg", "HMG" },
    { "Pistol", "cp_pickup_pistol", "Pistol" },
    { "Welder", "cp_pickup_welder", "Welder" },
    { "LayMines", "cp_pickup_mines", "Mines" },
    { "Jetpack", "cp_pickup_jetpack", "Jetpack" },
    { "Exosuit", "cp_pickup_exo", "Exosuit" },
}

-- Tier category used for highlight colour and refresh precedence.
-- 1 = unknown/rookie/bot/tier 1-4, 2 = tier 5, 3 = tier 6, 4 = tier 7+.
function MNGA_ContextPing_GetTierCategory(tier)
    tier = tier or 0
    if tier >= 7 then
        return 4
    elseif tier == 6 then
        return 3
    elseif tier == 5 then
        return 2
    end
    return 1
end

local function IsDroppedItem(target)
    if target:isa("Weapon") then
        return target.GetWeaponWorldState ~= nil and target:GetWeaponWorldState() == true
    end
    return target:isa("Jetpack") or target:isa("Exosuit")
end

-- Cheap eligibility check (also used inside physics trace filters, so no
-- string building). Returns a kContextPingKind value or nil (= location ping).
function MNGA_ContextPing_GetKind(pinger, target)

    if not pinger or not target or target == pinger then
        return nil
    end

    local pingerTeam = pinger:GetTeamNumber()
    if pingerTeam ~= kTeam1Index and pingerTeam ~= kTeam2Index then
        return nil
    end

    -- Dropped items: only marines who can actually pick things up.
    if pingerTeam == kTeam1Index and pinger:isa("Marine") and IsDroppedItem(target) then
        return kContextPingKind.Pickup
    end

    if not HasMixin(target, "Live") or not target:GetIsAlive() then
        return nil
    end

    local targetTeam = target:GetTeamNumber()
    local enemyTeam = GetEnemyTeamNumber(pingerTeam)

    if target:isa("Player") then

        if targetTeam ~= enemyTeam then
            return nil
        end

        if pingerTeam == kTeam1Index then
            -- player hallucinations subclass the real lifeform classes, so they
            -- are treated exactly like the real thing (no information leak)
            for i = 1, #kLifeforms do
                if target:isa(kLifeforms[i]) then
                    return kContextPingKind.Lifeform
                end
            end
            return nil -- Skulk, Embryo -> location ping
        end

        -- JetpackMarine isa Marine
        if target:isa("Marine") or target:isa("Exo") then
            return kContextPingKind.EnemyPlayer
        end
        return nil

    end

    -- Cysts are never ping targets: the ray/capsule passes through them to
    -- whatever is behind, or falls back to the location ping.
    if target:isa("Cyst") then
        return nil
    end

    -- structures and AI units (same answer in client and server VMs)
    if not IsStructureOrUnit(target) then
        return nil
    end

    if HasMixin(target, "GhostStructure") and target:GetIsGhostStructure() then
        return nil
    end

    if target:isa("PowerPoint") then
        if target:GetPowerState() == PowerPoint.kPowerState.unsocketed or not target:GetIsBuilt() then
            return nil
        end
    end

    if targetTeam == pingerTeam then
        return kContextPingKind.FriendlyStructure
    elseif targetTeam == enemyTeam then
        return kContextPingKind.EnemyStructure
    end

    return nil

end

-- True if this kind creates a 5s highlight mark (everything except pickups).
function MNGA_ContextPing_IsMarkKind(kind)
    return kind ~= nil and kind ~= kContextPingKind.Pickup
end

-- Localized structure name. The server may not have resolved locale strings,
-- so fall back to prettifying the key ("ADVANCED_ARMORY" -> "Advanced Armory").
function MNGA_ContextPing_GetTechName(techId)

    local key = LookupTechData(techId, kTechDataDisplayName)
    if type(key) == "string" and key ~= "" then

        if Locale and Locale.ResolveString then
            local resolved = Locale.ResolveString(key)
            if type(resolved) == "string" and resolved ~= "" and resolved ~= key then
                return resolved
            end
        end

        local pretty = string.lower(string.gsub(key, "_", " "))
        pretty = string.gsub(pretty, "(%a)([%w']*)", function(first, rest) return string.upper(first) .. rest end)
        return pretty

    end

    return EnumToString(kTechId, techId) or "this"

end

local function GetStructureTechId(target)
    -- non-player hallucinations (hallucinated hive, whip, drifter...) emulate
    -- another tech; never reveal that they are hallucinations
    if target:isa("Hallucination") and target.assignedTechId then
        return target.assignedTechId
    end
    return target:GetTechId()
end

local function GetPlayerName(target)
    return target.GetName and target:GetName() or ""
end

-- Full classification (server: builds the radio command id and chat text).
-- Returns { kind = kContextPingKind, commandId = string, text = string } or nil.
function MNGA_ContextPing_Classify(pinger, target)

    local kind = MNGA_ContextPing_GetKind(pinger, target)
    if not kind then
        return nil
    end

    local pingerTeam = pinger:GetTeamNumber()

    if kind == kContextPingKind.Pickup then
        for i = 1, #kPickups do
            local entry = kPickups[i]
            if target:isa(entry[1]) then
                return { kind = kind, commandId = entry[2], text = "Pick up " .. entry[3] }
            end
        end
        return { kind = kind, commandId = "cp_pickup_weapon", text = "Pick up " .. target:GetClassName() }
    end

    if kind == kContextPingKind.Lifeform then
        local lifeform = "Alien"
        for i = 1, #kLifeforms do
            if target:isa(kLifeforms[i]) then
                lifeform = kLifeforms[i]
                break
            end
        end
        return { kind = kind, commandId = "cp_focus_lifeform",
                 text = string.format("Focus %s! (%s)", lifeform, GetPlayerName(target)) }
    end

    if kind == kContextPingKind.EnemyPlayer then
        local commandId, label = "cp_focus_marine", "Focus Marine!"
        if target:isa("Exo") then
            commandId, label = "cp_focus_exo", "Focus Exo!"
        else
            local weapon = target.GetActiveWeapon and target:GetActiveWeapon()
            if weapon and weapon:isa("Flamethrower") then
                commandId, label = "cp_focus_flamer", "Focus Flamer!"
            elseif weapon and weapon:isa("GrenadeLauncher") then
                commandId, label = "cp_focus_gl", "Focus GL!"
            end
        end
        return { kind = kind, commandId = commandId, text = string.format("%s (%s)", label, GetPlayerName(target)) }
    end

    local techId = GetStructureTechId(target)
    local name = MNGA_ContextPing_GetTechName(techId)

    if kind == kContextPingKind.EnemyStructure then

        if pingerTeam == kTeam1Index then
            if target:isa("Hive") or techId == kTechId.Hive then
                return { kind = kind, commandId = "cp_shoot_hive", text = "Shoot the hive!" }
            elseif target:isa("TunnelEntrance") then
                return { kind = kind, commandId = "cp_shoot_tunnel", text = "Shoot the tunnel!" }
            end
            return { kind = kind, commandId = "cp_marine_focus_this", text = "Focus " .. name }
        end

        if target:isa("CommandStation") or techId == kTechId.CommandStation then
            return { kind = kind, commandId = "cp_bite_chair", text = "Bite the chair!" }
        elseif target:isa("PhaseGate") or techId == kTechId.PhaseGate then
            return { kind = kind, commandId = "cp_bite_gate", text = "Bite the gate!" }
        elseif target:isa("PowerPoint") then
            return { kind = kind, commandId = "cp_bite_power", text = "Bite the power!" }
        end
        return { kind = kind, commandId = "cp_alien_focus_this", text = "Focus " .. name }

    end

    -- friendly structure
    if pingerTeam == kTeam1Index then
        return { kind = kind, commandId = "cp_marine_defend_this", text = "Defend " .. name }
    end
    if target:isa("Hive") or techId == kTechId.Hive then
        return { kind = kind, commandId = "cp_defend_hive", text = "Defend the hive!" }
    elseif target:isa("TunnelEntrance") then
        return { kind = kind, commandId = "cp_defend_tunnel", text = "Defend the tunnel" }
    end
    return { kind = kind, commandId = "cp_alien_defend_this", text = "Defend " .. name }

end

-- Picks the entity the player is pinging (or nil). Used by the client to send
-- a lag-free hint and by the server as the fallback (e.g. bots, missing hint).
function MNGA_ContextPing_PickTarget(player)

    local eye = player:GetEyePos()
    local dir = player:GetViewCoords().zAxis
    local endPoint = eye + dir * kContextPingRange

    -- 1. exact hit on hitboxes (same rep/mask as the crosshair target trace)
    local trace = Shared.TraceRay(eye, endPoint, CollisionRep.Damage, PhysicsMask.Bullets, EntityFilterOne(player))
    if trace.entity and MNGA_ContextPing_GetKind(player, trace.entity) then
        return trace.entity
    end

    -- 2. near miss: thin capsule that only collides with eligible targets
    -- (world geometry still blocks it)
    local filter = function(ent)
        return ent == player or not MNGA_ContextPing_GetKind(player, ent)
    end
    local capsule = Shared.TraceCapsule(eye, endPoint, kAssistRadius, 0, CollisionRep.Damage, PhysicsMask.Bullets, filter)
    if capsule.entity and MNGA_ContextPing_GetKind(player, capsule.entity) then
        return capsule.entity
    end

    -- 3. dropped items near the point the location ping would use
    if player:GetTeamNumber() == kTeam1Index and player:isa("Marine") then

        local locTrace = Shared.TraceRay(eye, endPoint, CollisionRep.Default, PhysicsMask.Bullets, EntityFilterOne(player))
        local best, bestDistSq
        local pickupables = GetEntitiesWithMixinWithinRange("Pickupable", locTrace.endPoint, kPickupAssistRange)
        for i = 1, #pickupables do
            local ent = pickupables[i]
            if MNGA_ContextPing_GetKind(player, ent) == kContextPingKind.Pickup then
                local distSq = (ent:GetOrigin() - locTrace.endPoint):GetLengthSquared()
                if not bestDistSq or distSq < bestDistSq then
                    best, bestDistSq = ent, distSq
                end
            end
        end
        if best then
            return best
        end

    end

    return nil

end
