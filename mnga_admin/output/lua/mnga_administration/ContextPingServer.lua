-- MNGA contextual ping: server side. Post-hook on NetworkMessages_Server.lua.
-- Player pings arrive through the vanilla "Ping" VoiceMessage, which
-- VoiceOverMultiPing.lua routes to MNGA_ContextPing_TryPlayerPing first.
--
-- See .claude/docs/contextual-ping.md.

Script.Load("lua/mnga_administration/ContextPingShared.lua")

local kHintMaxAge = 1               -- seconds a client hint stays usable
local kHintRangeSlack = 3           -- extra metres over kContextPingRange
local kHintMaxAngleCos = math.cos(math.rad(15))
local kHintMaxRayDistance = 3       -- big structures: target centre may sit off-axis
local kHintLOSSlack = 2.5           -- engagement point may be inside a big model
local kCommanderOwnerId = -1        -- must match PlayingTeamMultiPing.lua

local hintByClient = setmetatable({}, { __mode = "k" })

local function OnContextPingTarget(client, message)
    if not client then
        return
    end
    hintByClient[client] = { targetId = message.targetId, time = Shared.GetTime() }
end

Server.HookNetworkMessage("MNGAContextPingTarget", OnContextPingTarget)

-- Returns hasHint, targetId. A hint with Entity.invalidId means the client saw
-- no contextual target; the server still runs its own pick as a fallback.
local function ConsumeHint(client)
    local hint = client and hintByClient[client]
    if not hint then
        return false
    end
    hintByClient[client] = nil
    if Shared.GetTime() - hint.time > kHintMaxAge then
        return false
    end
    return true, hint.targetId
end

local function GetTargetPoint(target)
    if target.GetEngagementPoint then
        return target:GetEngagementPoint()
    end
    return target:GetOrigin()
end

-- Loose server check of a client-picked target: plausible range, roughly in
-- the view direction and not behind world geometry.
local function ValidateHint(player, target)

    if not MNGA_ContextPing_GetKind(player, target) then
        return false
    end

    local eye = player:GetEyePos()
    local dir = player:GetViewCoords().zAxis
    local targetPoint = GetTargetPoint(target)
    local toTarget = targetPoint - eye
    local distance = toTarget:GetLength()

    if distance > kContextPingRange + kHintRangeSlack then
        return false
    end

    local along = toTarget:DotProduct(dir)
    if along <= 0 then
        return false
    end

    if distance > 0.01 then
        local cosAngle = along / distance
        local rayDistance = (toTarget - dir * along):GetLength()
        if cosAngle < kHintMaxAngleCos and rayDistance > kHintMaxRayDistance then
            return false
        end
    end

    -- world geometry only (EntityFilterAll ignores every entity)
    local trace = Shared.TraceRay(eye, targetPoint, CollisionRep.Default, PhysicsMask.Bullets, EntityFilterAll())
    if trace.fraction < 1 and (trace.endPoint - targetPoint):GetLength() > kHintLOSSlack then
        return false
    end

    return true

end

local function DeliverVoice(player, info, target)
    if MNGA_RADIO and MNGA_RADIO.DeliverContextPing then
        MNGA_RADIO.DeliverContextPing(player, info.commandId, info.text, target)
    else
        Print("[ContextPing] ERROR: MNGA_RADIO.DeliverContextPing missing")
    end
end

-- Called by VoiceOverMultiPing's NewPingInViewDirection after the cooldown
-- check. Returns handled, accepted:
--   handled = false -> caller does the normal location ping
--   accepted        -> caller starts the shared ping cooldown
function MNGA_ContextPing_TryPlayerPing(player, ownerId, team)

    if not kMNGAContextPingEnabled or not team or not team.SetContextMark then
        return false
    end

    local client = Server.GetOwner(player)
    local target
    local source = "server pick"

    local hasHint, hintId = ConsumeHint(client)
    if hasHint then
        local hinted = hintId ~= Entity.invalidId and Shared.GetEntity(hintId)
        if hinted and ValidateHint(player, hinted) then
            target = hinted
            source = "client hint"
        end
    end

    if not target then
        target = MNGA_ContextPing_PickTarget(player)
    end

    local info = target and MNGA_ContextPing_Classify(player, target)
    if not info then
        return false
    end

    Print("[ContextPing] %s pinged %s(%d) via %s kind=%d command=%s",
        player:GetName(), target:GetClassName(), target:GetId(), source, info.kind, info.commandId)

    if info.kind == kContextPingKind.Pickup then

        -- no minimap support for items: location ping on the item + voiceline
        local accepted = team:SetPlayerPing(ownerId, target:GetOrigin(), player:GetName(), player)
        if accepted then
            DeliverVoice(player, info, target)
        end
        return true, accepted

    end

    local result = team:SetContextMark(target, player, ownerId, false)
    if result == "new" then
        DeliverVoice(player, info, target)
    end
    return true, result ~= nil

end

-- Commander world-click ping with the entity under the cursor
-- (ContextPingCommander_Client.lua). Invalid or ineligible targets fall back
-- to the vanilla commander location ping.
local function OnCommanderContextPing(client, message)

    local player = client and client:GetControllingPlayer()
    if not player or not player:isa("Commander") then
        return
    end

    local team = player:GetTeam()
    if not team or not team.SetCommanderPing then
        return
    end

    local target = message.targetId ~= Entity.invalidId and Shared.GetEntity(message.targetId)
    local info = kMNGAContextPingEnabled and target and team.SetContextMark and MNGA_ContextPing_Classify(player, target)

    -- commanders have no line of sight of their own: enemies must be sighted
    if info and target:GetTeamNumber() ~= player:GetTeamNumber()
            and HasMixin(target, "LOS") and not target:GetIsSighted() then
        info = nil
    end

    if info and MNGA_ContextPing_IsMarkKind(info.kind) then

        Print("[ContextPing] commander %s pinged %s(%d) command=%s",
            player:GetName(), target:GetClassName(), target:GetId(), info.commandId)
        local result = team:SetContextMark(target, player, kCommanderOwnerId, true)
        if result == "new" then
            DeliverVoice(player, info, target)
        end
        return

    end

    team:SetCommanderPing(message.position, "Commander", player)

end

Server.HookNetworkMessage("MNGACommanderContextPing", OnCommanderContextPing)
