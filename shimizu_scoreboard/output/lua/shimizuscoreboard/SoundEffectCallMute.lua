if Client then
    local callSoundAssetIndices

    local function BuildCallSoundAssetIndices()
        local indices = {}
        if not GetVoiceSoundData or not debug.getupvaluex then return nil end
        local soundData = debug.getupvaluex(GetVoiceSoundData, "kSoundData")
        if not soundData then return nil end
        for _, data in pairs(soundData) do
            if data.Sound then
                local index = Shared.GetSoundIndex(data.Sound)
                if index ~= 0 then indices[index] = true end
            end
            if data.SoundFemale then
                local index = Shared.GetSoundIndex(data.SoundFemale)
                if index ~= 0 then indices[index] = true end
            end
        end
        return indices
    end

    local function GetShouldSuppressCall(self)
        if not SSB_GetHasClientCallsMuted or not SSB_GetHasClientCallsMuted() then return false end
        callSoundAssetIndices = callSoundAssetIndices or BuildCallSoundAssetIndices()
        if not callSoundAssetIndices or not callSoundAssetIndices[self.assetIndex] then return false end
        local parent = self:GetParent()
        return parent and parent.GetClientIndex and SSB_GetClientCallsMuted(parent:GetClientIndex())
    end

    local function StopSuppressedCall(self)
        if self.soundEffectInstance then
            self.soundEffectInstance:Stop()
            Client.DestroySoundEffect(self.soundEffectInstance)
            self.soundEffectInstance = nil
        end
        self.clientAssetIndex = self.assetIndex
        self.clientPlaying = self.playing
        self.clientStartTime = self.startTime
    end

    local VanillaOnUpdate = SoundEffect.OnUpdate
    function SoundEffect:OnUpdate(deltaTime)
        if GetShouldSuppressCall(self) then StopSuppressedCall(self); return end
        return VanillaOnUpdate(self, deltaTime)
    end

    local VanillaOnProcessMove = SoundEffect.OnProcessMove
    function SoundEffect:OnProcessMove()
        if GetShouldSuppressCall(self) then StopSuppressedCall(self); return end
        return VanillaOnProcessMove(self)
    end

    local VanillaOnProcessSpectate = SoundEffect.OnProcessSpectate
    function SoundEffect:OnProcessSpectate()
        if GetShouldSuppressCall(self) then StopSuppressedCall(self); return end
        return VanillaOnProcessSpectate(self)
    end

    Print("[SSBCallMute] Installed replicated call-sound suppression")
end
