-- Server-only, narrowly scoped override for marine weapon drops beside Armories.
-- Set MNGAWeaponDropPhysics.Enabled to false for immediate vanilla delegation.

if not Server or not Weapon then
    return
end

MNGAWeaponDropPhysics = MNGAWeaponDropPhysics or {}
if MNGAWeaponDropPhysics.Enabled == nil then
    MNGAWeaponDropPhysics.Enabled = true
end

if MNGAWeaponDropPhysics.HookInstalled then
    return
end

local kGentleImpulseScalar = 0.25
local kGentleAngularVelocity = Vector(0.5, 0.125, 0.125)
local kPerformExpirationCheckAfterDelay = 1.00
local VanillaDropped = Weapon.Dropped

MNGAWeaponDropPhysics.HookInstalled = true
MNGAWeaponDropPhysics.VanillaDropped = VanillaDropped

local function FindActiveFriendlyArmory(weapon, origin)
    -- This is deliberately the only spatial query in the hook. Team scoping
    -- naturally excludes enemy Armories, and the engine bounds it to 4 metres.
    local armories = GetEntitiesForTeamWithinRange(
        "Armory", weapon:GetTeamNumber(), origin, kArmoryDroppedWeaponAttachRange)

    for _, armory in ipairs(armories) do
        if GetIsUnitActive(armory) then
            return armory
        end
    end

    return nil
end

function Weapon:Dropped(prevOwner)
    if not MNGAWeaponDropPhysics.Enabled then
        return VanillaDropped(self, prevOwner)
    end

    local origin = self:GetOrigin()
    local activeArmory = FindActiveFriendlyArmory(self, origin)
    if not activeArmory then
        return VanillaDropped(self, prevOwner)
    end

    local gentleImpulse = kMarineWeaponTossImpulse * kGentleImpulseScalar

    -- Preserve Weapon_Server.lua's vanilla drop setup exactly, changing only
    -- the one-shot impulse and angular velocity in this Armory-only branch.
    self.prevOwnerId = prevOwner:GetId()
    self:SetWeaponWorldState(true)

    if self.physicsModel then
        local viewCoords = prevOwner:GetViewCoords()
        self.physicsModel:AddImpulse(self:GetOrigin(), viewCoords.zAxis * gentleImpulse)
        self.physicsModel:SetAngularVelocity(kGentleAngularVelocity)
    end

    self.weaponExpirationCheckTime = Shared.GetTime() + kPerformExpirationCheckAfterDelay
end
