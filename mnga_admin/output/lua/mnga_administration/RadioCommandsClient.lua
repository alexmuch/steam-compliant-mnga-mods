Script.Load( "lua/mnga_administration/RadioCommandsRegistry.lua" )

local kErrorHexColor = 0xFF3030
local kErrorColor = Color( 1, 0.12, 0.08, 1 )

local function GetChatMessages()
    return debug.getupvaluex( ChatUI_GetMessages, "chatMessages" )
end

local function AddChatRow( NameColor, Name, TextColor, Text, IsCommander )
    local Messages = GetChatMessages()
    if not Messages then return false end
    table.insert( Messages, NameColor )
    table.insert( Messages, Name )
    table.insert( Messages, TextColor )
    table.insert( Messages, Text )
    table.insert( Messages, IsCommander == true )
    table.insert( Messages, false )
    table.insert( Messages, 0 )
    table.insert( Messages, 0 )
    return true
end

local function OnRadioDelivery( Message )
    local Command = MNGA_RADIO.GetCommand( Message.CommandID )
    if not Command then return end
    if SSB_GetClientCallsMuted and SSB_GetClientCallsMuted( Message.SenderClientIndex ) then
        return
    end

    local Text, Sound = MNGA_RADIO.GetResolvedCommand( Command, Message.TeamNumber )
    if Message.ReportText ~= "" then Text = Message.ReportText end
    local LocationText = Message.LocationID > 0 and string.format( "(Team, %s) ", Shared.GetString( Message.LocationID ) ) or "(Team) "
    local Prefix = string.format( "%s%s: ", Message.SenderName, LocationText )
    local Player = Client.GetLocalPlayer()
    if Message.ShowText then
        local Added = AddChatRow( GetColorForTeamNumber( Message.TeamNumber ), Prefix,
            kChatTextColor[ Message.TeamType ], Text, false )
        if Added and Player then StartSoundEffect( Player:GetChatSound() ) end
        Shared.Message( string.format( "Chat Team %d - %s: %s", Message.TeamNumber, Message.SenderName, Text ) )
    end
    if Message.PlaySound then
        -- Custom radiovoice bank events bypass Client.SetSoundVolume, so apply
        -- both persisted option levels explicitly at the event instance.
        local SoundVolume = Clamp( Client.GetOptionInteger( "soundVolume", 90 ), 0, 100 ) / 100
        local RadioVolume = Clamp( Client.GetOptionInteger( MNGA_RADIO.VolumeOptionPath,
            MNGA_RADIO.DefaultVolume ), 0, 100 ) / 100
        local Volume = SoundVolume * RadioVolume
        if Message.PositionalSound then
            StartSoundEffectAtOrigin( Sound, Message.SoundOrigin, Volume )
        else
            StartSoundEffect( Sound, Volume )
        end
    end
end

local function OnRadioFeedback( Message )
    local Text = Message.Reason == MNGA_RADIO.FeedbackSpam
        and "30 second cooldown for spamming" or "Wait longer before sending"
    AddChatRow( kErrorHexColor, "", kErrorColor, Text, false )
end

Client.HookNetworkMessage( "MNGARadioDelivery", OnRadioDelivery )
Client.HookNetworkMessage( "MNGARadioFeedback", OnRadioFeedback )
