Script.Load( "lua/mnga_administration/RadioCommandsRegistry.lua" )

Shared.RegisterNetworkMessage( "MNGARadioRequest", {
    CommandID = "string (" .. MNGA_RADIO.MaxCommandIDLength .. ")"
} )

Shared.RegisterNetworkMessage( "MNGARadioDelivery", {
    CommandID = "string (" .. MNGA_RADIO.MaxCommandIDLength .. ")",
    SenderClientIndex = "integer (0 to 255)",
    SenderName = string.format( "string (%d)", kMaxNameLength * 4 ),
    ReportText = string.format( "string (%d)", kMaxNameLength * 4 + 64 ),
    LocationID = "integer (-1 to 1000)",
    TeamNumber = "integer (0 to 2)",
    TeamType = "integer (0 to 2)",
    PlaySound = "boolean",
    ShowText = "boolean",
    PositionalSound = "boolean",
    SoundOrigin = "vector"
} )

Shared.RegisterNetworkMessage( "MNGARadioFeedback", {
    Reason = "integer (1 to 2)"
} )

-- Commander order click feedback; index into MNGAPlayerOrderSounds.suffixes.
Shared.RegisterNetworkMessage( "MNGAOrderVoice", {
    Index = "integer (1 to 5)"
} )
