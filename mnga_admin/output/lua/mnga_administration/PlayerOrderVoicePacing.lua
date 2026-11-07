-- GUIWaypoints owns the player-facing order callbacks. Keep its marker updates
-- intact while limiting the voice events shared by all order types.
if Client then
    Script.Load("lua/mnga_administration/PlayerOrderSounds.lua")
    -- Vanilla marine Defend/Construct/Repair callbacks stay untouched; Move is
    -- replaced only to apply its volume.
    local orderSounds = {
        MarineOrder_OnOrderAttack = MNGAPlayerOrderSounds.marine.Attack,
        MarineOrder_OnOrderMove = MNGAPlayerOrderSounds.marine.Move
    }
    for suffix, sound in pairs(MNGAPlayerOrderSounds.alien) do
        orderSounds["AlienOrder_OnOrder" .. suffix] = sound
    end
    local function CreateOrderSoundCallback(name, sound)
        return function()
            local player = Client.GetLocalPlayer()
            if player and not player:isa("Commander")
                and (name ~= "AlienOrder_OnOrderConstruct" and name ~= "AlienOrder_OnOrderRepair"
                    or player:isa("Gorge")) then
                local volume = MNGAPlayerOrderSounds.GetVolume(sound)
                -- Radiovoice events are played 2D like radio calls.
                if MNGAPlayerOrderSounds.IsRadioBank(sound) then
                    StartSoundEffect(sound, volume)
                else
                    StartSoundEffectOnEntity(sound, player, volume)
                end
            end
        end
    end
    for name, sound in pairs(orderSounds) do
        _G[name] = CreateOrderSoundCallback(name, sound)
    end

    -- Commander click feedback: 2D at the per-event volume (see CommanderPlayerOrderPacing).
    local function OnOrderVoice(message)
        local player = Client.GetLocalPlayer()
        local suffix = MNGAPlayerOrderSounds.suffixes[message.Index]
        if not player or not suffix then return end
        local set = player:GetTeamNumber() == kAlienTeamType and MNGAPlayerOrderSounds.alien
            or player:GetTeamNumber() == kMarineTeamType and MNGAPlayerOrderSounds.marine
        local sound = set and set[suffix]
        if sound then
            StartSoundEffect(sound, MNGAPlayerOrderSounds.GetVolume(sound))
        end
    end
    Client.HookNetworkMessage("MNGAOrderVoice", OnOrderVoice)

    -- Trolling guard: a player who used SSB "Mute Calls" on their commander
    -- hears no order voicelines. SSB is a separate mod; without it nothing is
    -- suppressed. Runs only when an order voice would play.
    local function IsCommanderMuted(player)
        if not SSB_GetHasClientCallsMuted or not SSB_GetHasClientCallsMuted() then
            return false
        end
        local commanders = GetEntitiesForTeam("Commander", player:GetTeamNumber())
        for i = 1, #commanders do
            local index = commanders[i]:GetClientIndex()
            if index and index > 0 and SSB_GetClientCallsMuted(index) then
                return true
            end
        end
        return false
    end

    local lastVoiceTime = -math.huge
    local interval = 4
    local names = {
        "MarineOrder_OnOrderAttack", "MarineOrder_OnOrderMove",
        "MarineOrder_OnOrderDefend", "MarineOrder_OnOrderConstruct",
        "MarineOrder_OnOrderRepair", "AlienOrder_OnOrderAttack",
        "AlienOrder_OnOrderMove", "AlienOrder_OnOrderDefend",
        "AlienOrder_OnOrderConstruct",
        "AlienOrder_OnOrderRepair"
    }
    for _, name in ipairs(names) do
        local original = _G[name]
        if original then
            _G[name] = function(...)
                local player = Client.GetLocalPlayer()
                if player and not player:isa("Commander") and IsCommanderMuted(player) then
                    return
                end
                local now = Shared.GetTime()
                if now - lastVoiceTime >= interval then
                    lastVoiceTime = now
                    return original(...)
                end
            end
        end
    end

    -- Vanilla's file-local waypoint sound timer starts when this script loads
    -- and suppresses callbacks within one second of its last allowed sound.
    -- Catch order changes skipped by that timer, including early first orders.
    local oldUpdate = GUIWaypoints.Update
    function GUIWaypoints:Update(deltaTime)
        local previousId = self.lastOrderId
        local previousType = self.lastOrderType
        oldUpdate(self, deltaTime)
        if self.lastOrderId and
            (previousId ~= self.lastOrderId or previousType ~= self.lastOrderType) then
            local prefix = self.marineWaypointLoaded and "MarineOrder_OnOrder" or "AlienOrder_OnOrder"
            local suffix = MNGAPlayerOrderSounds.GetSuffix(self.lastOrderType)
            local callback = suffix and _G[prefix .. suffix]
            if callback then callback() end
        end
    end
end
