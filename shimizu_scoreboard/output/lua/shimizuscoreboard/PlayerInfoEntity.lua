-- Extend vanilla's fixed tactical bit mask with two reserved Exo-armament bits.
-- Ordinary decoding remains owned by vanilla; if its tracked sequence changes,
-- only the Exo decoration is disabled.
local vanillaGetTechIdsFromBitMask = GetTechIdsFromBitMask
local vanillaPlayerInfoEntityUpdateScore = PlayerInfoEntity.UpdateScore
local expectedVanillaTech = {
    kTechId.Jetpack, kTechId.Welder, kTechId.ClusterGrenade,
    kTechId.PulseGrenade, kTechId.GasGrenade, kTechId.Mine,
    kTechId.Vampirism, kTechId.Carapace, kTechId.Regeneration,
    kTechId.Aura, kTechId.Focus, kTechId.Camouflage,
    kTechId.Celerity, kTechId.Adrenaline, kTechId.Crush, kTechId.Parasite
}
local kMinigunExoBit = 65536 -- bit 17; vanilla owns bits 1-16.
local kRailgunExoBit = 131072 -- bit 18.
local exoArmamentEnabled = true
local decodeCache = {}

local function ValidateVanillaTechSequence()
    if not debug.getupvaluex then return false, "debug.getupvaluex unavailable" end
    local vanillaTech = debug.getupvaluex(vanillaGetTechIdsFromBitMask, "techUpgradesTable")
    if type(vanillaTech) ~= "table" then return false, "vanilla tech table unavailable" end
    if #vanillaTech ~= #expectedVanillaTech then
        return false, string.format("vanilla tracked count changed (%d expected %d)",
            #vanillaTech, #expectedVanillaTech)
    end
    for i = 1, #expectedVanillaTech do
        if vanillaTech[i] ~= expectedVanillaTech[i] then
            return false, string.format("vanilla tracked tech changed at position %d", i)
        end
    end
    local mask = CreateBitMask(vanillaTech)
    for _, techId in ipairs(vanillaTech) do
        if mask[techId] == kMinigunExoBit or mask[techId] == kRailgunExoBit then
            return false, "reserved Exo bit collision"
        end
    end
    return true
end

local valid, validationError = ValidateVanillaTechSequence()
if not valid then
    exoArmamentEnabled = false
    Print("[SSB] COMPATIBILITY ERROR: Exo armament decoration disabled: %s", validationError)
end

function GetTechIdsFromBitMask(techMask)
    PROFILE("GetTechIdsFromBitMask")
    techMask = techMask or 0
    local cached = decodeCache[techMask]
    if cached then
        return cached
    end
    local techIds = vanillaGetTechIdsFromBitMask(techMask)
    if exoArmamentEnabled then
        if bit.band(techMask, kMinigunExoBit) > 0 then techIds[#techIds + 1] = kTechId.DualMinigunExosuit end
        if bit.band(techMask, kRailgunExoBit) > 0 then techIds[#techIds + 1] = kTechId.DualRailgunExosuit end
    end
    decodeCache[techMask] = techIds
    return techIds
end

function PlayerInfoEntity:UpdateScore()
    local result = vanillaPlayerInfoEntityUpdateScore(self)
    if Server and exoArmamentEnabled then
        local scorePlayer = Shared.GetEntity(self.playerId)
        if scorePlayer and self.currentTech and scorePlayer:isa("Exo") then
            if scorePlayer:GetHasMinigun() then
                self.currentTech = bit.bor(self.currentTech, kMinigunExoBit)
            elseif scorePlayer:GetHasRailgun() then
                self.currentTech = bit.bor(self.currentTech, kRailgunExoBit)
            end
        end
    end
    return result
end
