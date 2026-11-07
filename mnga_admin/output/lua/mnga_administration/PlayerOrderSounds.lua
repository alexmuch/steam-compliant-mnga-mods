-- Shared order voice table: recipient callbacks (client) and commander click
-- feedback (server) pick the same event for a resolved order type.
if MNGAPlayerOrderSounds then return end

MNGAPlayerOrderSounds = {
    alien = {
        -- Operator-made radiovoice bank events.
        Move = PrecacheAsset("sound/radiovoice.fev/radiovoice/alien_proceedtowaypoint"),
        Attack = PrecacheAsset("sound/radiovoice.fev/radiovoice/alien_attacktargetatwaypoint"),
        Defend = PrecacheAsset("sound/radiovoice.fev/radiovoice/alien_defendtargetatwaypoint"),
        Construct = PrecacheAsset("sound/radiovoice.fev/radiovoice/alien_buildstructurewaypoint"),
        Repair = PrecacheAsset("sound/radiovoice.fev/radiovoice/alien_healtargetwaypoint")
    },
    marine = {
        -- Attack = PrecacheAsset("sound/NS2_manga.fev/marine/voiceovers/commander/attack"),
        Attack = PrecacheAsset("sound/NS2.fev/marine/voiceovers/move"),
        -- The rest mirror vanilla kTechDataOrderSound for marine orders.
        Move = PrecacheAsset("sound/NS2.fev/marine/voiceovers/move"),
        Defend = PrecacheAsset("sound/NS2.fev/marine/voiceovers/commander/defend"),
        Construct = PrecacheAsset("sound/NS2.fev/marine/voiceovers/commander/build"),
        Repair = PrecacheAsset("sound/NS2.fev/marine/structures/mac/weld")
    }
}

-- Per-event volume. The marine move line is mixed louder than the commander
-- radio lines; it also stands in for Attack, so key by event, not order type.
local kVolumes = {
    [PrecacheAsset("sound/NS2.fev/marine/voiceovers/move")] = 0.6
}

-- Network index of each suffix for MNGAOrderVoice.
MNGAPlayerOrderSounds.suffixes = { "Move", "Attack", "Defend", "Construct", "Repair" }

-- Radiovoice clips are mastered hot (0 dB events, ~-17 dBFS RMS); radio calls
-- play them at the 20% default Radio Volume. Orders use that same fixed level,
-- independent of the slider, so muting radio calls keeps order voices.
local kRadioBankScale = 0.2

-- Custom radiovoice bank events bypass Client.SetSoundVolume (see
-- radio-commands.md), so they apply the persisted Sound Volume themselves.
function MNGAPlayerOrderSounds.IsRadioBank(sound)
    return string.find(sound, "sound/radiovoice.fev/", 1, true) == 1
end

function MNGAPlayerOrderSounds.GetVolume(sound)
    local volume = kVolumes[sound] or 1
    if Client and MNGAPlayerOrderSounds.IsRadioBank(sound) then
        volume = volume * kRadioBankScale
            * Clamp(Client.GetOptionInteger("soundVolume", 90), 0, 100) / 100
    end
    return volume
end

function MNGAPlayerOrderSounds.GetSuffix(kind)
    if kind == kTechId.Attack then return "Attack"
    elseif kind == kTechId.Move then return "Move"
    elseif kind == kTechId.Construct or kind == kTechId.AutoConstruct then return "Construct"
    elseif kind == kTechId.Defend then return "Defend"
    elseif kind == kTechId.Weld or kind == kTechId.AutoWeld
        or kind == kTechId.Heal or kind == kTechId.AutoHeal then return "Repair" end
end

function MNGAPlayerOrderSounds.Get(teamNumber, kind)
    local suffix = MNGAPlayerOrderSounds.GetSuffix(kind)
    local set = teamNumber == kAlienTeamType and MNGAPlayerOrderSounds.alien
        or teamNumber == kMarineTeamType and MNGAPlayerOrderSounds.marine
    return suffix and set and set[suffix], suffix
end
