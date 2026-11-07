-- Name-aware Shine chat (.claude/docs/player-alias-coverage.md). Player names
-- travel beside the text (Steam ID + real name per slot) instead of inside it,
-- so each client can show its own SSB alias without searching the text.
--
-- Server usage, same shape as Shine:NotifyColour / NotifyDualColour with a
-- format string; wrap each player name argument in MNGA_Name():
--   MNGA_NotifyNames( Target, R, G, B, "%s was gagged.", MNGA_Name( Player ) )
--   MNGA_NotifyNamesDual( Target, RP, GP, BP, "[READY]", R, G, B, Format, ... )
-- Target is anything Shine:ApplyNetworkMessage takes (nil = everyone).

MNGA_NAME_NOTIFY_SLOTS = 4

local kNameField = string.format( "string (%d)", kMaxNameLength * 4 + 1 )
local kMessage = {
    RP = "integer (0 to 255)", GP = "integer (0 to 255)", BP = "integer (0 to 255)",
    Prefix = "string (64)",
    R = "integer (0 to 255)", G = "integer (0 to 255)", B = "integer (0 to 255)",
    Template = string.format( "string (%d)", kMaxChatLength * 4 + 1 )
}
for i = 1, MNGA_NAME_NOTIFY_SLOTS do
    kMessage[ "SteamID" .. i ] = "integer"
    kMessage[ "Name" .. i ] = kNameField
end
Shared.RegisterNetworkMessage( "MNGANameNotify", kMessage )

if not Server then return end

local StringFormat = string.format
local StringChar = string.char
local Gsub = string.gsub

-- Placeholder bytes \1..\4 mark name slots in Template. Strip them from every
-- other argument so stray control bytes can never address a slot.
local kPlaceholderPattern = "[\1-\4]"

local NameMarker = {}
NameMarker.__index = NameMarker

local function ResolveNameSource( Source )
    -- nil = server console, matching Shine.GetClientName( nil ).
    if Source == nil then return 0, "Console" end
    if type( Source ) ~= "table" and type( Source ) ~= "userdata" then return 0, tostring( Source ) end
    local Client, Player
    if Source.GetUserId then
        Client = Source
        Player = Client:GetControllingPlayer()
    else
        Player = Source
        Client = Player.GetClient and Player:GetClient()
    end
    local Name = Player and Player.GetName and Player:GetName()
        or ( Client and Shine.GetClientName( Client ) ) or "Unknown"
    local SteamID = Client and Client:GetUserId() or 0
    return SteamID, Name
end

-- Source: a Client, a Player, or (SteamID, Name) for players who already left.
function MNGA_Name( Source, Name )
    local SteamID
    if Name ~= nil then
        SteamID, Name = tonumber( Source ) or 0, tostring( Name )
    else
        SteamID, Name = ResolveNameSource( Source )
    end
    return setmetatable( { SteamID = SteamID, Name = Name }, NameMarker )
end

function MNGA_NotifyNamesDual( Target, RP, GP, BP, Prefix, R, G, B, Format, ... )
    local Args = { ... }
    local Message = {
        RP = RP, GP = GP, BP = BP, Prefix = Prefix or "",
        R = R, G = G, B = B
    }
    local Slot = 0
    for i = 1, select( "#", ... ) do
        local Arg = Args[ i ]
        if getmetatable( Arg ) == NameMarker then
            if Slot < MNGA_NAME_NOTIFY_SLOTS then
                Slot = Slot + 1
                Message[ "SteamID" .. Slot ] = Arg.SteamID
                Message[ "Name" .. Slot ] = Gsub( Arg.Name, kPlaceholderPattern, "" )
                Args[ i ] = StringChar( Slot )
            else
                -- Out of slots: fall back to the real name in the text.
                Args[ i ] = Gsub( Arg.Name, kPlaceholderPattern, "" )
            end
        elseif type( Arg ) == "string" then
            Args[ i ] = Gsub( Arg, kPlaceholderPattern, "" )
        end
    end
    for i = Slot + 1, MNGA_NAME_NOTIFY_SLOTS do
        Message[ "SteamID" .. i ] = 0
        Message[ "Name" .. i ] = ""
    end

    local Template = StringFormat( Gsub( Format, kPlaceholderPattern, "" ), unpack( Args, 1, select( "#", ... ) ) )
    -- Byte cap of the Template field; cut on a UTF-8 boundary like Shine does.
    local MaxBytes = kMaxChatLength * 4
    if #Template > MaxBytes then
        local Cut = MaxBytes
        while Cut > 0 and string.byte( Template, Cut + 1 ) and string.byte( Template, Cut + 1 ) >= 128
            and string.byte( Template, Cut + 1 ) < 192 do
            Cut = Cut - 1
        end
        Template = string.sub( Template, 1, Cut )
    end
    Message.Template = Template

    Print( "[namenotify] slots=%s template=%s", tostring( Slot ), ( Gsub( Template, kPlaceholderPattern, "{}" ) ) )
    Shine:ApplyNetworkMessage( Target, "MNGANameNotify", Message, true )
end

function MNGA_NotifyNames( Target, R, G, B, Format, ... )
    MNGA_NotifyNamesDual( Target, 0, 0, 0, "", R, G, B, Format, ... )
end
