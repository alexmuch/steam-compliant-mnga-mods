Script.Load( "lua/mnga_administration/RadioCommandsRegistry.lua" )

local RateStateByClient = setmetatable( {}, { __mode = "k" } )

local function SendFeedback( Client, Reason )
    Server.SendNetworkMessage( Client, "MNGARadioFeedback", { Reason = Reason }, true )
end

local function GetRateState( Client )
    local State = RateStateByClient[ Client ]
    if not State then
        State = { LastSuccess = -math.huge, SuccessTimes = {}, SpamUntil = 0 }
        RateStateByClient[ Client ] = State
    end
    return State
end

local function PruneSuccessTimes( State, Now )
    local FirstValid = 1
    while State.SuccessTimes[ FirstValid ]
    and Now - State.SuccessTimes[ FirstValid ] > MNGA_RADIO.SpamWindow do
        FirstValid = FirstValid + 1
    end
    if FirstValid > 1 then
        local Pruned = {}
        for Index = FirstValid, #State.SuccessTimes do
            Pruned[ #Pruned + 1 ] = State.SuccessTimes[ Index ]
        end
        State.SuccessTimes = Pruned
    end
end

local function CheckRateLimit( Client, Now )
    local State = GetRateState( Client )
    if Now < State.SpamUntil then
        SendFeedback( Client, MNGA_RADIO.FeedbackSpam )
        return nil
    end
    if Now - State.LastSuccess < MNGA_RADIO.Cooldown then
        SendFeedback( Client, MNGA_RADIO.FeedbackWait )
        return nil
    end
    PruneSuccessTimes( State, Now )
    return State
end

local function RecordSuccess( Client, State, Now )
    State.LastSuccess = Now
    State.SuccessTimes[ #State.SuccessTimes + 1 ] = Now
    if #State.SuccessTimes >= MNGA_RADIO.SpamCommandCount then
        State.SpamUntil = Now + MNGA_RADIO.SpamCooldown
        State.SuccessTimes = {}
        SendFeedback( Client, MNGA_RADIO.FeedbackSpam )
    end
end

-- A teammate hears a local-audio line when within MaxDistanceSq of any origin.
-- Commanders always hear it. Dead players are first-person TeamSpectators whose
-- own origin is stale, so use the player they are watching.
local function CanHearLocal( Recipient, RecipientClient, AudibleOrigins, MaxDistanceSq )
    if Recipient:isa( "Commander" ) then
        return true
    end
    local Origin = Recipient:GetOrigin()
    if Recipient:isa( "Spectator" ) then
        local Watched = RecipientClient:GetSpectatingPlayer()
        if Watched then
            Origin = Watched:GetOrigin()
        end
    end
    for Index = 1, #AudibleOrigins do
        if Origin:GetDistanceSquared( AudibleOrigins[ Index ] ) <= MaxDistanceSq then
            return true
        end
    end
    return false
end

-- ReportTextOverride (optional) forces the chat text clients display; used by
-- contextual pings, whose text carries target names.
-- AudibleOrigins (optional) limits team audio to teammates near those points
-- (contextual pings with LocalAudio); text still reaches the whole team.
-- LocationIdOverride (optional) replaces the sender's room in the chat prefix
-- (commander contextual pings name the target's room).
local function Deliver( Sender, Command, Text, ReportTextOverride, AudibleOrigins, LocationIdOverride )
    local TeamNumber = Sender:GetTeamNumber()
    local SenderClient = Sender:GetClient()
    local SenderOrigin = Sender:GetOrigin()
    local Recipients = {}
    local LocalDistanceSq = MNGA_RADIO.ContextPingLocalDistance * MNGA_RADIO.ContextPingLocalDistance

    for _, Recipient in ipairs( GetEntitiesForTeam( "Player", TeamNumber ) ) do
        local RecipientClient = Recipient:GetClient()
        if RecipientClient then
            local PlaySound = Command.TeamAudio
            if PlaySound and AudibleOrigins then
                PlaySound = RecipientClient == SenderClient
                    or CanHearLocal( Recipient, RecipientClient, AudibleOrigins, LocalDistanceSq )
            end
            Recipients[ RecipientClient ] = {
                ShowText = true,
                PlaySound = PlaySound,
                PositionalSound = false
            }
        end
    end

    if not Command.TeamAudio then
        for _, Recipient in ientitylist( Shared.GetEntitiesWithClassname( "Player" ) ) do
            local RecipientClient = Recipient:GetClient()
            if RecipientClient and Recipient:GetOrigin():GetDistance( SenderOrigin ) <= MNGA_RADIO.PersonalAudibleDistance then
                local Delivery = Recipients[ RecipientClient ] or { ShowText = false }
                Delivery.PlaySound = true
                Delivery.PositionalSound = true
                Recipients[ RecipientClient ] = Delivery
            end
        end
    end

    -- A sender always hears their Personal command, even if an unusual player
    -- entity reports an origin outside the normal relevancy calculation.
    if not Command.TeamAudio and SenderClient then
        local SenderDelivery = Recipients[ SenderClient ] or { ShowText = true }
        SenderDelivery.PlaySound = true
        SenderDelivery.PositionalSound = true
        Recipients[ SenderClient ] = SenderDelivery
    end

    for RecipientClient, Delivery in pairs( Recipients ) do
        Server.SendNetworkMessage( RecipientClient, "MNGARadioDelivery", {
            CommandID = Command.ID,
            SenderClientIndex = Sender:GetClientIndex(),
            SenderName = Sender:GetName(),
            ReportText = ReportTextOverride or ( Command.ReportLifeform and TeamNumber == kTeam1Index
                and Text ~= Command.MarineText and Text or "" ),
            LocationID = LocationIdOverride or Sender:GetLocationId(),
            TeamNumber = TeamNumber,
            TeamType = Sender:GetTeamType(),
            PlaySound = Delivery.PlaySound == true,
            ShowText = Delivery.ShowText == true,
            PositionalSound = Delivery.PositionalSound == true,
            SoundOrigin = SenderOrigin
        }, true )
    end
end

local function OnRadioRequest( Client, Message )
    local Player = Client and Client:GetControllingPlayer()
    local TeamNumber = Player and Player:GetTeamNumber()
    if not Player or not MNGA_RADIO.IsEligibleTeam( TeamNumber ) then
        return
    end

    local Command = MNGA_RADIO.GetCommand( Message.CommandID )
    if not MNGA_RADIO.RegistryValid or not Command or Command.VanillaVoiceID
    or Command.ContextPing
    or ( Command.MarineOnly and TeamNumber ~= kTeam1Index ) then
        return
    end

    local Now = Shared.GetTime()
    local State = CheckRateLimit( Client, Now )
    if not State then return end

    local Text = MNGA_RADIO.GetResolvedCommand( Command, TeamNumber )
    if TeamNumber == kTeam1Index and Command.ReportLifeform then
        local Kill = MNGA_RADIO.RecentLifeformKills and MNGA_RADIO.RecentLifeformKills[ Command.ReportLifeform ]
        if Kill and Now - Kill.Time <= 10 and Now >= Kill.Time and Kill.Name ~= "" then
            Text = string.format( "%s (%s)", Text, Kill.Name )
        end
    end
    Deliver( Player, Command, Text )
    Server.AddChatToHistory( Text, Player:GetName(), Client:GetUserId() or 0, TeamNumber, true )
    RecordSuccess( Client, State, Now )
end

-- Contextual ping voiceline + team text (ContextPingServer.lua). Team-wide,
-- non-positional, honours call-mute client-side like any radio delivery. Not
-- subject to the radio rate limiter: the ping cooldown governs it.
local kMaxContextPingTextLength = kMaxNameLength * 4 + 64

-- Target (optional): the pinged entity. For LocalAudio commands the voice is
-- heard within ContextPingLocalDistance of the target, and also of the pinger
-- unless the pinger is a commander (whose origin is the overhead camera).
function MNGA_RADIO.DeliverContextPing( Sender, CommandID, Text, Target )
    local Command = MNGA_RADIO.GetCommand( CommandID )
    if not MNGA_RADIO.ContextPingRegistryValid or not Command or not Command.ContextPing then
        Print( "[ContextPing] delivery skipped, unknown command %s", ToString( CommandID ) )
        return false
    end

    local TeamNumber = Sender:GetTeamNumber()
    Text = Text or MNGA_RADIO.GetResolvedCommand( Command, TeamNumber )
    if #Text > kMaxContextPingTextLength then
        Text = string.sub( Text, 1, kMaxContextPingTextLength )
    end

    local AudibleOrigins
    if Command.LocalAudio then
        AudibleOrigins = {}
        if not Sender:isa( "Commander" ) then
            AudibleOrigins[ #AudibleOrigins + 1 ] = Sender:GetOrigin()
        end
        if Target and Target.GetOrigin then
            AudibleOrigins[ #AudibleOrigins + 1 ] = Target:GetOrigin()
        end
    end

    -- Commanders ping from the overhead camera, so their own room is
    -- meaningless: name the target's room instead (sender's room as fallback).
    local LocationIdOverride
    if Sender:isa( "Commander" ) and Target and Target.GetLocationId then
        local TargetLocationId = Target:GetLocationId()
        if TargetLocationId and TargetLocationId > 0 then
            LocationIdOverride = TargetLocationId
        end
    end

    Deliver( Sender, Command, Text, Text, AudibleOrigins, LocationIdOverride )
    local SenderClient = Sender:GetClient()
    Server.AddChatToHistory( Text, Sender:GetName(), SenderClient and SenderClient:GetUserId() or 0, TeamNumber, true )
    return true
end

local function OnClientDisconnect( Client )
    RateStateByClient[ Client ] = nil
end

Server.HookNetworkMessage( "MNGARadioRequest", OnRadioRequest )
Event.Hook( "ClientDisconnect", OnClientDisconnect )
