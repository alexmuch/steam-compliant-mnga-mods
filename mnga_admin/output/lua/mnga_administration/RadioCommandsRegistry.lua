MNGA_RADIO = MNGA_RADIO or {}

MNGA_RADIO.BindingName = "RadioCommands"
MNGA_RADIO.VolumeOptionPath = "mnga/radioVolume"
MNGA_RADIO.DefaultVolume = 20
MNGA_RADIO.PersonalAudibleDistance = 30
MNGA_RADIO.ContextPingLocalDistance = 25
MNGA_RADIO.Cooldown = 3
MNGA_RADIO.SpamWindow = 12
MNGA_RADIO.SpamCommandCount = 3
MNGA_RADIO.SpamCooldown = 30
MNGA_RADIO.MaxCommandIDLength = 32
MNGA_RADIO.MaxSoundNameLength = 48
MNGA_RADIO.MaxLabelLength = 64
MNGA_RADIO.FeedbackWait = 1
MNGA_RADIO.FeedbackSpam = 2

local function Command( ID, Label, MarineSound, AlienSound, AlienText, ReportLifeform )
    return { ID = ID, Label = Label, MarineText = Label, AlienText = AlienText or Label,
        ReportLifeform = ReportLifeform,
        MarineSound = MarineSound,
        AlienSound = AlienSound or string.gsub( MarineSound, "^marine_", "alien_" ) }
end

local function MarineOnlyCommand( ID, Label, Sound, Lifeform )
    local Entry = Command( ID, Label, Sound, Sound )
    Entry.MarineOnly = true
    Entry.ReportLifeform = Lifeform
    return Entry
end

local function SlotCommand( Slot, ... )
    local Entry = Command( ... )
    Entry.Slot = Slot
    return Entry
end

local function VanillaRequest( ID, MarineLabel, AlienLabel, MarineVoiceID, AlienVoiceID )
    return {
        ID = ID,
        Label = MarineLabel,
        MarineText = MarineLabel,
        AlienText = AlienLabel or MarineLabel,
        VanillaVoiceID = {
            Marine = MarineVoiceID,
            Alien = AlienVoiceID or MarineVoiceID
        }
    }
end

MNGA_RADIO.Menu = {
    Label = "RADIO",
    Children = {
        { Label = "1 - Personal", TeamAudio = false, Children = {
            Command( "follow_me", "Follow me", "marine_followme" ),
            Command( "cover_me", "Cover me", "marine_coverme" ),
            Command( "take_point", "You take the point", "marine_youtakethepoint" ),
            Command( "weld_heal_me", "Weld me", "marine_weldme", "alien_healme", "Heal me" )
        } },
        { Label = "2 - Group", TeamAudio = true, Children = {
            Command( "go", "Go!", "marine_gogogo" ),
            Command( "fall_back", "Fall back", "marine_fallback" ),
            Command( "group_up", "Group up", "marine_groupup" ),
            Command( "hold_position", "Hold this position", "marine_holdthisposition" ),
            Command( "rotate", "Rotate to next location", "marine_rotatetonextlocation" ),
            Command( "need_assistance", "Need assistance", "marine_needassistance" )
        } },
        { Label = "3 - Objective", TeamAudio = true, Children = {
            Command( "structure_support", "Structure needs welding", "marine_structureneedswelding", "alien_structureneedshealing", "Structure needs healing" ),
            Command( "defend_gate", "Defend the gates", "marine_defendgates", "alien_defendthetunnel", "Defend the tunnel" ),
            Command( "rt_low", "RT is low", "marine_rtislow" ),
            Command( "focus", "Focus lifeform!", "marine_focuslifeform", "alien_focusgl", "Focus GL!" ),
            Command( "shoot_tunnel", "Shoot the tunnel!", "marine_shootthetunnel", "alien_bitethegate", "Bite the gate!" ),
            Command( "shoot_hive", "Shoot the hive!", "marine_shootthehive", "alien_bitethechair", "Bite the chair!" ),
            Command( "defend_main", "Defend marine main!", "marine_theyrecomingforbase", "alien_defendthehive", "Defend the hive!" ),
            Command( "drop_gate", "Drop a gate on me", "marine_dropagateonme", "alien_gatheronme", "Gather on me for a rush" )
        } },
        { Label = "4 - Responses / Reports", TeamAudio = true, Children = {
            Command( "affirmative", "Affirmative", "marine_affirmative" ),
            Command( "enemy_nearby", "Enemy nearby", "marine_enemynearby" ),
            Command( "negative", "Negative", "marine_negative" ),
            Command( "rt_under_attack", "RT under attack", "marine_rtunderattack" ),
            Command( "incoming", "Xenoform ball detected!", "marine_xenoformballdetected", "alien_pushincoming", "Push incoming!" ),
            SlotCommand( 9, "get_out", "Get out of there, it's gonna blow!", "marine_getoutofthere" )
        } },
        { Label = "5 - Team-Specific Responses / Reports", TeamAudio = true, Children = {
            Command( "gorge_down", "Gorge down", "marine_gorgeslaughtered", "alien_structureneedscysting", "Structure needs cysting", "Gorge" ),
            Command( "lerk_down", "Lerk down", "marine_lerkdown", "alien_sneakymarine", "Sneaky marine found", "Lerk" ),
            Command( "fade_down", "Fade down", "marine_fadeneutralized", "alien_bitethepower", "Bite the power", "Fade" ),
            MarineOnlyCommand( "onos_down", "Onos down", "marine_onoseliminated", "Onos" )
        } },
        { Label = "6 - Commander Request", Children = {
            VanillaRequest( "request_health", "Request Medpack", "Request Healing",
                "MarineRequestMedpack", "AlienRequestHealing" ),
            VanillaRequest( "request_ammo", "Request Ammo", "Request Enzyme",
                "MarineRequestAmmo", "AlienRequestDrifter" ),
            VanillaRequest( "request_order", "Request Order", "Request Order",
                "MarineRequestOrder", "AlienRequestHarvester" )
        } },
        { Label = "7 - Misc", TeamAudio = true, Children = {
            Command( "terrorists_win", "Terrorists win", "twin", "twin" ),
            Command( "counter_terrorists_win", "Counter-terrorists win", "ctwin", "ctwin" )
        } }
    }
}

-- Contextual ping voicelines (ContextPingShared.lua / ContextPingServer.lua).
-- Hidden: never shown in the radio menu and rejected from MNGARadioRequest;
-- delivered only by the server through MNGA_RADIO.DeliverContextPing. Each
-- entry is team-specific, so both team variants point at the same event.
-- Several entries share one event (all alien marine focuses except GL use
-- alien_focusmarine; every pickup uses marine_pickthatup); the chat text
-- stays specific because the server sends it as ReportText.
-- LocalAudio: the voice plays only for teammates within ContextPingLocalDistance
-- of the pinger or the target (commanders always hear it); text stays team-wide.
local function ContextPingCommand( ID, Label, Sound, LocalAudio )
    local Entry = Command( ID, Label, Sound, Sound )
    Entry.ContextPing = true
    Entry.LocalAudio = LocalAudio == true
    return Entry
end

MNGA_RADIO.ContextPingMenu = {
    Label = "CONTEXT PING",
    TeamAudio = true,
    Children = {
        { Label = "Focus", Children = {
            ContextPingCommand( "cp_focus_lifeform", "Focus Lifeform!", "marine_focuslifeform", true ),
            ContextPingCommand( "cp_focus_flamer", "Focus Flamer!", "alien_focusmarine", true ),
            ContextPingCommand( "cp_focus_gl", "Focus GL!", "alien_focusgl", true ),
            ContextPingCommand( "cp_focus_exo", "Focus Exo!", "alien_focusmarine", true ),
            ContextPingCommand( "cp_focus_marine", "Focus Marine!", "alien_focusmarine", true )
        } },
        { Label = "Structures", Children = {
            ContextPingCommand( "cp_shoot_hive", "Shoot the hive!", "marine_shootthehive" ),
            ContextPingCommand( "cp_shoot_tunnel", "Shoot the tunnel!", "marine_shootthetunnel", true ),
            ContextPingCommand( "cp_marine_focus_this", "Focus this!", "marine_focusstructure", true ),
            ContextPingCommand( "cp_bite_chair", "Bite the chair!", "alien_bitethechair" ),
            ContextPingCommand( "cp_bite_gate", "Bite the gate!", "alien_bitethegate", true ),
            ContextPingCommand( "cp_bite_power", "Bite the power!", "alien_bitethepower", true ),
            ContextPingCommand( "cp_alien_focus_this", "Focus this!", "alien_focusstructure", true ),
            ContextPingCommand( "cp_marine_defend_this", "Defend this!", "marine_defendstructure" ),
            ContextPingCommand( "cp_alien_defend_this", "Defend this!", "alien_defendstructure" )
        } },
        { Label = "Structures 2", Children = {
            ContextPingCommand( "cp_defend_hive", "Defend the hive!", "alien_defendthehive" ),
            ContextPingCommand( "cp_defend_tunnel", "Defend the tunnel", "alien_defendthetunnel" )
        } },
        { Label = "Pickups", Children = {
            ContextPingCommand( "cp_pickup_rifle", "Pick up Rifle", "marine_pickthatup" ),
            ContextPingCommand( "cp_pickup_shotgun", "Pick up Shotgun", "marine_pickthatup" ),
            ContextPingCommand( "cp_pickup_flamethrower", "Pick up Flamethrower", "marine_pickthatup" ),
            ContextPingCommand( "cp_pickup_gl", "Pick up Grenade Launcher", "marine_pickthatup" ),
            ContextPingCommand( "cp_pickup_hmg", "Pick up HMG", "marine_pickthatup" ),
            ContextPingCommand( "cp_pickup_pistol", "Pick up Pistol", "marine_pickthatup" ),
            ContextPingCommand( "cp_pickup_welder", "Pick up Welder", "marine_pickthatup" ),
            ContextPingCommand( "cp_pickup_mines", "Pick up Mines", "marine_pickthatup" ),
            ContextPingCommand( "cp_pickup_jetpack", "Pick up Jetpack", "marine_pickthatup" )
        } },
        { Label = "Pickups 2", Children = {
            ContextPingCommand( "cp_pickup_exo", "Pick up Exosuit", "marine_pickthatup" ),
            ContextPingCommand( "cp_pickup_weapon", "Pick up weapon", "marine_pickthatup" )
        } }
    }
}

local CommandsByID = {}

local function IsNonEmptyString( Value, MaxLength )
    return type( Value ) == "string" and Value ~= "" and #Value <= MaxLength
end

local function ValidateNode( Node, SeenTables, TeamAudio )
    if type( Node ) ~= "table" or SeenTables[ Node ] then
        return false
    end
    SeenTables[ Node ] = true
    if not IsNonEmptyString( Node.Label, MNGA_RADIO.MaxLabelLength ) then
        return false
    end
    if Node.Children then
        if Node.ID or #Node.Children < 1 or #Node.Children > 9 then
            return false
        end
        local ChildTeamAudio = Node.TeamAudio
        if ChildTeamAudio == nil then ChildTeamAudio = TeamAudio end
        local Slots = {}
        for Index = 1, #Node.Children do
            local Child = Node.Children[ Index ]
            local Slot = Child.Slot or Index
            if type( Slot ) ~= "number" or Slot < 1 or Slot > 9 or Slot % 1 ~= 0 or Slots[ Slot ] then return false end
            Slots[ Slot ] = true
            if not ValidateNode( Child, SeenTables, ChildTeamAudio ) then return false end
        end
        return true
    end
    if not IsNonEmptyString( Node.ID, MNGA_RADIO.MaxCommandIDLength ) or not string.match( Node.ID, "^[%w_]+$" ) then
        return false
    end
    if CommandsByID[ Node.ID ] then
        return false
    end
    if Node.VanillaVoiceID then
        if type( Node.VanillaVoiceID ) ~= "table"
        or not IsNonEmptyString( Node.MarineText, MNGA_RADIO.MaxLabelLength )
        or not IsNonEmptyString( Node.AlienText, MNGA_RADIO.MaxLabelLength )
        or not IsNonEmptyString( Node.VanillaVoiceID.Marine, MNGA_RADIO.MaxCommandIDLength )
        or not IsNonEmptyString( Node.VanillaVoiceID.Alien, MNGA_RADIO.MaxCommandIDLength ) then
            return false
        end
        CommandsByID[ Node.ID ] = Node
        return true
    end
    if not IsNonEmptyString( Node.MarineText, MNGA_RADIO.MaxLabelLength )
    or not IsNonEmptyString( Node.AlienText, MNGA_RADIO.MaxLabelLength )
    or not IsNonEmptyString( Node.MarineSound, MNGA_RADIO.MaxSoundNameLength )
    or not IsNonEmptyString( Node.AlienSound, MNGA_RADIO.MaxSoundNameLength ) then
        return false
    end
    Node.TeamAudio = TeamAudio == true
    Node.MarineAsset = PrecacheAsset( "sound/radiovoice.fev/radiovoice/" .. Node.MarineSound )
    Node.AlienAsset = PrecacheAsset( "sound/radiovoice.fev/radiovoice/" .. Node.AlienSound )
    CommandsByID[ Node.ID ] = Node
    return true
end

function MNGA_RADIO.RebuildRegistry()
    CommandsByID = {}
    local Valid = ValidateNode( MNGA_RADIO.Menu, {}, false )
    MNGA_RADIO.RegistryValid = Valid
    -- validated separately so a contextual-ping registry error cannot disable
    -- the radio menu (and vice versa)
    MNGA_RADIO.ContextPingRegistryValid = ValidateNode( MNGA_RADIO.ContextPingMenu, {}, true )
    if not MNGA_RADIO.ContextPingRegistryValid then
        Print( "[ContextPing] ERROR: contextual ping radio registry failed validation" )
    end
    return Valid
end

function MNGA_RADIO.GetResolvedLabel( Command, TeamNumber )
    if not Command then return nil end
    if TeamNumber == kTeam2Index then return Command.AlienText end
    return Command.MarineText
end

function MNGA_RADIO.GetCommand( ID ) return CommandsByID[ ID ] end

function MNGA_RADIO.GetResolvedCommand( Command, TeamNumber )
    if not Command then return nil, nil end
    if TeamNumber == kTeam2Index then return Command.AlienText, Command.AlienAsset end
    return Command.MarineText, Command.MarineAsset
end

function MNGA_RADIO.IsEligibleTeam( TeamNumber )
    return TeamNumber == kTeam1Index or TeamNumber == kTeam2Index
end

MNGA_RADIO.RebuildRegistry()
