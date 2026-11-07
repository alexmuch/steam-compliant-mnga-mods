-- Cancel an ARC Factory blueprint when a friendly player lands or stands on
-- top of it, without interfering with players beside it who are constructing.

if Server then

    local kCandidateRange = 4
    local kCheckInterval = 0.2
    local kTraceRadius = 0.1
    local kTraceStartHeight = 0.15
    local kTraceDepth = 0.35

    -- ClearGhostStructure is vanilla's single full-refund cancellation path.
    -- Reusing it preserves effects, resource messages, and commander-bot state.
    local clearGhostStructure = debug.getupvaluex(
        GhostStructureMixin.OnTakeDamage,
        "ClearGhostStructure"
    )

    if clearGhostStructure then
        local function IsBlueprintUnderPlayer(self, player)
            -- Player origins are at their feet. Restricting this short trace to
            -- the blueprint makes side proximity fail while real support beneath
            -- the player's feet succeeds against the actual physics mesh.
            local footOrigin = player:GetOrigin()
            self.mngaArcBlueprintTraceFilter = self.mngaArcBlueprintTraceFilter
                or EntityFilterOnly(self)
            local trace = Shared.TraceCapsule(
                footOrigin + Vector(0, kTraceStartHeight, 0),
                footOrigin - Vector(0, kTraceDepth, 0),
                kTraceRadius,
                0,
                CollisionRep.Move,
                PhysicsMask.Movement,
                self.mngaArcBlueprintTraceFilter
            )

            return trace.entity == self
        end

        local function CancelIfBlueprintIsUnderPlayer(self, player)
            if self.mngaArcBlueprintCancelInProgress
                    or not self:GetIsGhostStructure()
                    or not player
                    or not player:isa("Player")
                    or not player:GetIsAlive()
                    or not GetAreFriends(self, player) then
                return false
            end

            if not IsBlueprintUnderPlayer(self, player) then
                return false
            end

            self.mngaArcBlueprintCancelInProgress = true
            clearGhostStructure(self)
            return true
        end

        function RoboticsFactory:OnUpdate(deltaTime)
            -- ns20k intentionally permits Marines to stand on player-placed
            -- Robotics Factory blueprints. Vanilla has no OnUpdate here.
            if NS20KIsEnabled and NS20KIsEnabled("MarineConstruction") then
                return
            end
            if self:GetIsGhostStructure() and not self.mngaArcBlueprintCancelInProgress then
                local now = Shared.GetTime()
                if self.mngaArcBlueprintNextTopCheck
                        and now < self.mngaArcBlueprintNextTopCheck then
                    return
                end
                self.mngaArcBlueprintNextTopCheck = now + kCheckInterval

                local players = GetEntitiesForTeamWithinRange(
                    "Player",
                    self:GetTeamNumber(),
                    self:GetOrigin(),
                    kCandidateRange
                )

                for i = 1, #players do
                    local player = players[i]
                    if player:GetIsAlive() then
                        if CancelIfBlueprintIsUnderPlayer(self, player) then
                            return
                        end
                    end
                end
            end

        end

    end

end
