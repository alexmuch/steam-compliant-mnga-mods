-- Commander order targets must not reveal enemies the team cannot see. Remember
-- where each non-player LOS entity stood when its enemies lost sight of it.
-- Recorded only on the sighted -> unsighted transition: the frequent refresh
-- path costs one field compare and allocates nothing.
if Server then
    local kSeenPositionToleranceSq = 1 * 1

    local oldSetIsSighted = LOSMixin.SetIsSighted
    function LOSMixin:SetIsSighted(sighted, viewer)
        if self.sighted and not sighted and not self:isa("Player") then
            local origin = self:GetOrigin()
            self.mngaSeenX, self.mngaSeenY, self.mngaSeenZ = origin.x, origin.y, origin.z
        end
        return oldSetIsSighted(self, sighted, viewer)
    end

    -- Teleport unsights after the entity already moved; that recorded position
    -- would be the unseen destination.
    local oldOnTeleportEnd = LOSMixin.OnTeleportEnd
    function LOSMixin:OnTeleportEnd(...)
        oldOnTeleportEnd(self, ...)
        self.mngaSeenX = nil
    end

    -- True when the commander's team may target this entity: friendly/neutral,
    -- no LOS tracking, currently sighted, or (non-players) last seen here.
    function MNGAGetOrderTargetKnown(commander, entity)
        if not entity or not HasMixin(entity, "LOS") or not GetAreEnemies(commander, entity) then
            return true
        end
        if entity:GetIsSighted() then return true end
        if entity:isa("Player") or not entity.mngaSeenX then return false end
        local origin = entity:GetOrigin()
        local dx = origin.x - entity.mngaSeenX
        local dy = origin.y - entity.mngaSeenY
        local dz = origin.z - entity.mngaSeenZ
        return dx * dx + dy * dy + dz * dz <= kSeenPositionToleranceSq
    end
end
