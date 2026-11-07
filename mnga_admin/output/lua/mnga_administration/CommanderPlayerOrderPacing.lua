-- Gamerules owns the timers: authenticated orders survive commander logout.
if Server then
    local kMarkerInterval = 1
    local states = {}
    local oldOrderEntities = Commander.OrderEntities
    -- This is a vanilla closure upvalue, not a global function.
    local prePlaceBuildings = debug.getupvaluex(oldOrderEntities, "Commander_PrePlaceBuildings")
    if type(prePlaceBuildings) ~= "function" then
        Print("[AlienOrders] WARNING: vanilla selection spread helper missing; orders use the clicked point")
    end
    MNGAPlayerOrderPacing = {}

    local function ReportInvalid(order)
        local click = order.click
        local sender = Shared.GetEntity(click.senderId)
        if not click.reported and sender == click.sender and sender:isa("Commander")
            and sender:GetClient() == click.client and sender:GetTeamNumber() == order.teamNumber then
            click.reported = true
            sender:TriggerInvalidSound()
        end
    end

    local kCommanderVoiceInterval = 2
    Script.Load("lua/mnga_administration/PlayerOrderSounds.lua")

    -- Commander click feedback: once per original click, on its first applied
    -- player order, using the type that recipient actually received.
    local function PlayCommanderVoice(order, kind)
        local click = order.click
        if click.voiced then return end
        click.voiced = true
        local sender = Shared.GetEntity(click.senderId)
        if sender ~= click.sender or not sender:isa("Commander")
            or sender:GetClient() ~= click.client or sender:GetTeamNumber() ~= order.teamNumber then
            return
        end
        local now = Shared.GetTime()
        if sender.mngaLastOrderVoice and now - sender.mngaLastOrderVoice < kCommanderVoiceInterval then
            return
        end
        local sound, suffix = MNGAPlayerOrderSounds.Get(order.teamNumber, kind)
        if not sound then return end
        sender.mngaLastOrderVoice = now
        -- The commander order voice events (marine move/defend/build) are 2D FMOD
        -- events. A parented SoundEffect entity made the client push 3D attributes
        -- to them every frame ("2d sound ... meant for 3d" spam), and
        -- Server.PlayPrivateSound ignores volume. Tell the commander's client
        -- instead; it plays the event 2D at the per-event volume.
        local index
        for i, name in ipairs(MNGAPlayerOrderSounds.suffixes) do
            if name == suffix then index = i break end
        end
        if index then
            Server.SendNetworkMessage(click.client, "MNGAOrderVoice", { Index = index }, true)
        end
    end

    local function GetRecipient(state)
        local player = Shared.GetEntity(state.playerId)
        if player == state.player and not player:GetIsDestroyed() and player:isa("Player")
            and HasMixin(player, "Orders") and player:GetIsAlive()
            and player:GetTeam() == state.team and GetGamerules() == state.rules then
            return player
        end
    end

    local function Apply(player, order)
        if order.targetInvalid then return false end
        if player:isa("Alien") and (order.techId == kTechId.Defend
            or order.techId == kTechId.Construct or order.techId == kTechId.Heal) then
            local target = Shared.GetEntity(order.targetId)
            if not target or not HasMixin(target, "Live") or not target:GetIsAlive()
                or target:GetTeamNumber() ~= player:GetTeamNumber() then
                return false
            end
        end
        if order.target then
            local target = Shared.GetEntity(order.targetId)
            if target ~= order.target or target:GetIsDestroyed()
                or (target.GetTeamNumber and target:GetTeamNumber() ~= order.targetTeam) then
                return false
            end
        end
        local given = player:GiveOrder(order.techId, order.targetId, order.origin, order.orientation,
            not order.shiftDown, false)
        return given ~= kTechId.None and given
    end

    function MNGAPlayerOrderPacing.Reset()
        states = {}
    end

    function MNGAPlayerOrderPacing.OnEntityChange(oldId, newId)
        if not oldId or oldId == Entity.invalidId then return end
        if states[oldId] then
            states[oldId] = nil
        end
        local replacement = newId and Shared.GetEntity(newId)
        for _, state in pairs(states) do
            for _, order in ipairs(state.pending) do
                if order.techId ~= kTechId.Build and order.targetId == oldId then
                    if replacement and replacement.GetTeamNumber
                        and replacement:GetTeamNumber() == order.targetTeam then
                        order.targetId = newId
                        order.target = replacement
                    else
                        order.targetInvalid = true
                        order.target = nil
                    end
                end
            end
        end
    end

    local Schedule
    Schedule = function(state)
        if state.scheduled then return end
        state.scheduled = true
        state.rules:AddTimedCallback(function()
            state.scheduled = false
            if states[state.playerId] ~= state then return false end
            local player = GetRecipient(state)
            if not player then
                states[state.playerId] = nil
                return false
            end
            local now = Shared.GetTime()
            local due = state.nextTime
            if #state.pending > 0 then
                due = math.max(due, (player.timeLastOrder or -math.huge) + OrdersMixin.kOrderDelay)
            end
            if now < due then
                state.nextTime = due
                Schedule(state)
                return false
            end
            local order = table.remove(state.pending, 1)
            if not order then
                states[state.playerId] = nil
                return false
            end
            local given = Apply(player, order)
            if given then
                PlayCommanderVoice(order, given)
            else
                ReportInvalid(order)
            end
            state.nextTime = now + kMarkerInterval
            Schedule(state)
            return false
        end, math.max(0.01, state.nextTime - Shared.GetTime()), false)
    end

    local function Queue(team, player, order)
        local playerId = player:GetId()
        local state = states[playerId]
        local now = Shared.GetTime()
        if state and not GetRecipient(state) then
            states[playerId] = nil
            state = nil
        end
        if not state then
            state = { team = team, player = player, playerId = playerId,
                rules = GetGamerules(), nextTime = 0, pending = {} }
            if not GetRecipient(state) then return false end
            states[playerId] = state
        end
        if now >= state.nextTime and #state.pending == 0 then
            local given = Apply(player, order)
            if not given then
                states[playerId] = nil
                return false
            end
            PlayCommanderVoice(order, given)
            state.nextTime = now + kMarkerInterval
        else
            if not order.shiftDown then
                state.pending = {}
            elseif #state.pending >= OrdersMixin.kMaxOrdersPerUnit then
                return false
            end
            table.insert(state.pending, order)
        end
        Schedule(state)
        return true
    end

    -- The server pick trace hits entities the commander's client never
    -- received. Keep the pick ray so a hit on an unknown enemy can be traced
    -- again as if that entity did not exist.
    local oldProcessTechTreeAction = Commander.ProcessTechTreeAction
    function Commander:ProcessTechTreeAction(techId, pickVec, orientation, worldCoordsSpecified, targetId, shiftDown)
        self.mngaOrderPickVec = pickVec
        self.mngaOrderPickWorld = worldCoordsSpecified
        local success = oldProcessTechTreeAction(self, techId, pickVec, orientation,
            worldCoordsSpecified, targetId, shiftDown)
        self.mngaOrderPickVec = nil
        self.mngaOrderPickWorld = nil
        return success
    end

    local function FilterUnknownTargets(self, trace, targetId)
        if not MNGAGetOrderTargetKnown then return trace, targetId end
        if targetId and targetId ~= Entity.invalidId
            and not MNGAGetOrderTargetKnown(self, Shared.GetEntity(targetId)) then
            targetId = Entity.invalidId
        end
        local hit = trace.entity
        if hit and not MNGAGetOrderTargetKnown(self, hit) then
            local pickVec = self.mngaOrderPickVec
            if pickVec then
                local commander = self
                trace = GetCommanderPickTarget(self, pickVec, self.mngaOrderPickWorld, false,
                    function(entity)
                        return entity == commander or not MNGAGetOrderTargetKnown(commander, entity)
                    end)
            else
                trace = { fraction = trace.fraction, endPoint = trace.endPoint, normal = trace.normal }
            end
        end
        return trace, targetId
    end

    function Commander:OrderEntities(orderTechId, trace, orientation, targetId, shiftDown)
        if not trace then return end
        trace, targetId = FilterUnknownTargets(self, trace, targetId)
        if trace.fraction >= 1 then
            return oldOrderEntities(self, orderTechId, trace, orientation, targetId, shiftDown)
        end

        local selection = self:GetSelection()
        local hasPlayer = false
        for _, entity in ipairs(selection) do
            if entity:isa("Player") then hasPlayer = true break end
        end
        if not hasPlayer then
            return oldOrderEntities(self, orderTechId, trace, orientation, targetId, shiftDown)
        end

        local resolvedTargetId = targetId or Entity.invalidId
        if resolvedTargetId == Entity.invalidId and trace.entity then
            resolvedTargetId = trace.entity:GetId()
        end

        local click = { sender = self, senderId = self:GetId(), client = self:GetClient() }
        local target = resolvedTargetId ~= Entity.invalidId and Shared.GetEntity(resolvedTargetId) or nil
        local invalid = false
        local orderTechIdGiven = orderTechId
        local origins = { trace.endPoint }
        if #selection > 1 then
            if type(prePlaceBuildings) == "function" then
                origins = prePlaceBuildings(trace.endPoint, math.min(15, #selection))
            end
        end
        local team = self:GetTeam()
        for tableIndex, entity in ipairs(selection) do
            local origin = origins and #origins > 0
                and origins[(tableIndex % #origins) + 1]
                or trace.endPoint
            local isPlayerRecipient = entity:isa("Player")
                and entity:GetTeamNumber() == self:GetTeamNumber() and HasMixin(entity, "Orders")
            if isPlayerRecipient and orderTechId == kTechId.Attack
                and resolvedTargetId == Entity.invalidId then
                -- Vanilla OrdersMixin drops a targetless player Attack on its
                -- next update. Reject it up front: no marker, voice, or queue change.
                invalid = true
            elseif isPlayerRecipient then
                local accepted = Queue(team, entity, {
                    techId = orderTechId, targetId = resolvedTargetId,
                    origin = Vector(origin), orientation = orientation,
                    click = click, target = orderTechId ~= kTechId.Build and target or nil,
                    targetTeam = target and target.GetTeamNumber and target:GetTeamNumber() or nil,
                    targetInvalid = orderTechId ~= kTechId.Build
                        and resolvedTargetId ~= Entity.invalidId and not target,
                    shiftDown = shiftDown, teamNumber = self:GetTeamNumber()
                })
                if not accepted then invalid = true end
            elseif HasMixin(entity, "Orders") then
                local given = entity:GiveOrder(orderTechId, resolvedTargetId, origin,
                    orientation, not shiftDown, false)
                if given == kTechId.None then invalid = true end
            else
                invalid = true
            end
        end


        self:OnOrderEntities(orderTechIdGiven, selection)

        if invalid then
            click.reported = true
            self:TriggerInvalidSound()
        end
    end
end
