local Plugin = ...
local SGUI = Shine.GUI

local KEY_OPTIONS = {
    [ InputKey.Num1 ] = 1, [ InputKey.Num2 ] = 2, [ InputKey.Num3 ] = 3,
    [ InputKey.Num4 ] = 4, [ InputKey.Num5 ] = 5, [ InputKey.Num6 ] = 6,
    [ InputKey.Num7 ] = 7, [ InputKey.Num8 ] = 8, [ InputKey.Num9 ] = 9
}
local COL_BG = Colour( 0.025, 0.035, 0.05, 0.96 )
local COL_PANEL = Colour( 0.07, 0.09, 0.13, 0.98 )
local COL_BUTTON = Colour( 0.14, 0.23, 0.34, 1 )
local COL_BUTTON_HOVER = Colour( 0.22, 0.38, 0.53, 1 )
local COL_SELECTED = Colour( 0.18, 0.52, 0.28, 1 )
local COL_TEXT = Colour( 0.94, 0.95, 0.98, 1 )
local COL_MUTED = Colour( 0.63, 0.68, 0.75, 1 )
local COL_GOLD = Colour( 1, 0.72, 0.2, 1 )
local TEXT_REFERENCE_RESOLUTION = 1600

local function S( Value ) return math.floor( GUIScale( Value ) ) end
local function Valid( Element ) return Element and Element:IsValid() end

local function GetTextScaleValue( Multiplier )
    local ScreenW, ScreenH = SGUI.GetScreenSize()
    return math.min( ScreenW, ScreenH ) / TEXT_REFERENCE_RESOLUTION * ( Multiplier or 1 )
end

local function GetTextScale( Multiplier )
    local Scale = GetTextScaleValue( Multiplier )
    return Vector2( Scale, Scale )
end

local function AddLabel( Parent, X, Y, Text, Colour, Font, ScaleMultiplier )
    local Label = SGUI:Create( "Label", Parent )
    Label:SetupFromTable {
        Pos = Vector2( S( X ), S( Y ) ), Text = Text or "", TextColour = Colour or COL_TEXT,
        Font = Font or "fonts/AgencyFB_large.fnt"
    }
    Label:SetTextScale( GetTextScale( ScaleMultiplier ) )
    return Label
end

local function AddButton( Parent, X, Y, W, H, Text, OnClick, Colour, ScaleMultiplier )
    local Button = SGUI:Create( "Button", Parent )
    Button:SetupFromTable {
        Pos = Vector2( S( X ), S( Y ) ), Size = Vector2( S( W ), S( H ) ), Text = Text,
        Colour = Colour or COL_BUTTON, ActiveCol = COL_BUTTON_HOVER,
        DoClick = OnClick
    }
    Button:SetTextScale( GetTextScale( ScaleMultiplier ) )
    return Button
end

function Plugin:DestroyPanel( Name )
    local Panel = self[ Name ]
    if Valid( Panel ) then Panel:Destroy() end
    self[ Name ] = nil
end

function Plugin:RefreshMouse()
    local Enabled = ( Valid( self.VotePanel ) or Valid( self.NominationPanel ) ) and true or false
    if Enabled == self.MouseEnabled then return end

    -- Use one stable identity for the plugin. Calling EnableMouse(false)
    -- without a control decrements SGUI's global count and can release another
    -- UI's ownership (SSB/Poker/Match3) during startup or teardown.
    SGUI:EnableMouse( Enabled, self )
    self.MouseEnabled = Enabled
    Print( "%s", string.format( "[bettervoting] mouse ownership %s mouseObjects=%d",
        Enabled and "acquired" or "released", SGUI.MouseObjects or -1 ) )
end

function Plugin:CastOption( Option )
    local State = self.VoteState
    if not State or not State.Active or not State.Eligible or ( tonumber( State.Selected ) or 0 ) > 0 then return end
    if Option < 1 or Option > #( State.Options or {} ) then return end
    self:SendNetworkMessage( "CastVote", { VoteID = State.VoteID, Option = Option }, true )
    Print( "%s", string.format( "[bettervoting] submitted id=%s option=%s", tostring( State.VoteID ), tostring( Option ) ) )
end

function Plugin:BuildVotePanel()
    self:DestroyPanel( "VotePanel" )
    local State = self.VoteState
    if not State or not State.Active then self:RefreshMouse(); return end

    local Voters = State.Voters or {}
    local OptionRowHeight, VoterRowHeight = 42, 29
    local Height = 165 + math.max( #( State.Options or {} ) * OptionRowHeight, #Voters * VoterRowHeight )
    local Width = 760
    local ScreenW, ScreenH = SGUI.GetScreenSize()
    Print( "%s", string.format( "[bettervoting] building vote UI resolution=%dx%d text_scale=%.3f voters=%d options=%d",
        ScreenW, ScreenH, GetTextScaleValue(), #Voters, #( State.Options or {} ) ) )
    local Panel = SGUI:Create( "Panel" )
    Panel:SetupFromTable { Pos = Vector2( ( ScreenW - S( Width ) ) * 0.5, S( 55 ) ),
        Size = Vector2( S( Width ), S( Height ) ), Colour = COL_BG }
    self.VotePanel = Panel
    self.QuestionLabel = AddLabel( Panel, 16, 10, State.Question or "Vote", COL_GOLD,
        "fonts/AgencyFB_large.fnt", 1.2 )
    if State.ShowTimer ~= false then self.TimerLabel = AddLabel( Panel, Width - 95, 16, "", COL_GOLD,
        "fonts/AgencyFB_large.fnt", 1.1 ) end
    AddLabel( Panel, 16, 58, "Options", COL_MUTED, nil, 1.05 )
    AddLabel( Panel, 392, 58, "Eligible voters", COL_MUTED, nil, 1.05 )

    for Index, Option in ipairs( State.Options or {} ) do
        local HasTotal = State.Totals and State.Totals[ Index ] ~= nil
        local Total = tonumber( HasTotal and State.Totals[ Index ] ) or 0
        local Text = HasTotal and string.format( "%d. %s    %d", Index, tostring( Option ), Total )
            or string.format( "%d. %s", Index, tostring( Option ) )
        local Selected = tonumber( State.Selected ) == Index
        if State.Eligible and ( tonumber( State.Selected ) or 0 ) == 0 then
            AddButton( Panel, 16, 88 + ( Index - 1 ) * OptionRowHeight, 350, 36, Text,
                function() Plugin:CastOption( Index ) end, Selected and COL_SELECTED or COL_BUTTON )
        else
            AddLabel( Panel, 22, 94 + ( Index - 1 ) * OptionRowHeight, Text, Selected and COL_GOLD or COL_TEXT )
        end
    end

    for Index, Voter in ipairs( Voters ) do
        local Status = Voter.Voted and "voted" or "pending"
        if tonumber( Voter.Choice ) and tonumber( Voter.Choice ) > 0 then
            Status = tostring( State.Options[ tonumber( Voter.Choice ) ] or Status )
        end
        AddLabel( Panel, 392, 90 + ( Index - 1 ) * VoterRowHeight,
            string.format( "%s — %s", tostring( Voter.Name ), Status ),
            Voter.Voted and COL_TEXT or COL_MUTED )
    end
    if not State.Eligible then
        AddLabel( Panel, 14, Height - 28, "You can view this vote, but you are not eligible to vote.", COL_MUTED )
    elseif ( tonumber( State.Selected ) or 0 ) > 0 then
        AddLabel( Panel, 14, Height - 28, "Your vote has been recorded.", COL_GOLD )
    else
        AddLabel( Panel, 14, Height - 28, "Click an option or press its number key.", COL_MUTED )
    end
    self:RefreshMouse()
    self:UpdateTimer()
end

function Plugin:BuildNominationPanel()
    self:DestroyPanel( "NominationPanel" )
    local State = self.NominationState
    if not State or not State.Visible or #( State.Targets or {} ) == 0 or ( self.VoteState and self.VoteState.Active ) then
        self:RefreshMouse(); return
    end
    local Width, Height = 430, 94 + #State.Targets * 44
    local ScreenW, ScreenH = SGUI.GetScreenSize()
    Print( "%s", string.format( "[bettervoting] building nomination UI resolution=%dx%d text_scale=%.3f targets=%d",
        ScreenW, ScreenH, GetTextScaleValue(), #State.Targets ) )
    local Panel = SGUI:Create( "Panel" )
    Panel:SetupFromTable { Pos = Vector2( S( 20 ), S( 180 ) ), Size = Vector2( S( Width ), S( Height ) ), Colour = COL_PANEL }
    self.NominationPanel = Panel
    AddLabel( Panel, 14, 10, "COMMANDER SHADOW-REALM VOTE", COL_GOLD, nil, 1.1 )
    AddLabel( Panel, 14, 45, "Nominate one former teammate:", COL_MUTED )
    for Index, Target in ipairs( State.Targets ) do
        AddButton( Panel, 14, 76 + ( Index - 1 ) * 44, Width - 28, 36, Target.Name, function()
            Plugin:SendNetworkMessage( "StartShadowVote", { TargetID = tostring( Target.SteamID ) }, true )
        end )
    end
    self:RefreshMouse()
end

function Plugin:UpdateTimer()
    local State = self.VoteState
    if not State or not State.Active or not self.TimerLabel then return end
    local Remaining = math.max( 0, math.ceil( ( tonumber( State.EndsAt ) or 0 ) -
        ( ( tonumber( State.ServerTime ) or 0 ) + Shared.GetTime() - ( self.StateReceivedAt or Shared.GetTime() ) ) ) )
    self.TimerLabel:SetText( tostring( Remaining ) .. "s" )
end

function Plugin:ApplyVoteStateJSON( Payload )
    local Data = json.decode( Payload, 1, nil )
    if type( Data ) ~= "table" then return end
    self.VoteState, self.StateReceivedAt = Data, Shared.GetTime()
    self:BuildVotePanel()
    self:BuildNominationPanel()
end

function Plugin:ApplyNominationStateJSON( Payload )
    local Data = json.decode( Payload, 1, nil )
    if type( Data ) ~= "table" then return end
    self.NominationState = Data
    self:BuildNominationPanel()
end

function Plugin:ReceiveStateChunk( Message )
    local Key = tostring( Message.Channel ) .. ":" .. tostring( Message.TransferID )
    local Transfer = self.StateTransfers[ Key ]
    if not Transfer or Transfer.Parts ~= Message.Parts then
        Transfer = { Parts = Message.Parts, Received = 0, Chunks = {}, StartedAt = Shared.GetTime() }
        self.StateTransfers[ Key ] = Transfer
    end
    if not Transfer.Chunks[ Message.Part ] then
        Transfer.Chunks[ Message.Part ] = Message.Data
        Transfer.Received = Transfer.Received + 1
    end
    if Transfer.Received < Transfer.Parts then return end
    local Payload = table.concat( Transfer.Chunks )
    self.StateTransfers[ Key ] = nil
    Print( "%s", string.format( "[bettervoting] received state channel=%d transfer=%d bytes=%d parts=%d",
        Message.Channel, Message.TransferID, #Payload, Message.Parts ) )
    if Message.Channel == 1 then self:ApplyVoteStateJSON( Payload ) else self:ApplyNominationStateJSON( Payload ) end
end

function Plugin:Initialise()
    self.StateTransfers = {}
    self.Enabled = true
    Shine.Hook.Add( "PlayerKeyPress", self, function( Key, Down )
        if not Down then return end
        local Option = KEY_OPTIONS[ Key ]
        local State = Plugin.VoteState
        if Option and State and State.Active and State.Eligible and ( tonumber( State.Selected ) or 0 ) == 0 and
            Option <= #( State.Options or {} ) then
            Plugin:CastOption( Option )
            return true
        end
    end )
    Shine.Timer.Create( "bettervoting_client_timer", 0.2, -1, function()
        if not self.Enabled then return end
        self:UpdateTimer()
        local CurrentTime = Shared.GetTime()
        for Key, Transfer in pairs( self.StateTransfers ) do
            if CurrentTime - Transfer.StartedAt > 10 then
                Print( "%s", "[bettervoting] discarded incomplete state transfer " .. Key )
                self.StateTransfers[ Key ] = nil
            end
        end
    end )
    self:SendNetworkMessage( "RequestSync", {}, true )
    Print( "[bettervoting] client initialised" )
    return true
end

function Plugin:Cleanup()
    Shine.Hook.Remove( "PlayerKeyPress", self )
    Shine.Timer.Destroy( "bettervoting_client_timer" )
    self:DestroyPanel( "VotePanel" )
    self:DestroyPanel( "NominationPanel" )
    if self.MouseEnabled then
        SGUI:EnableMouse( false, self )
        self.MouseEnabled = false
        Print( "%s", string.format( "[bettervoting] mouse ownership released during cleanup mouseObjects=%d",
            SGUI.MouseObjects or -1 ) )
    end
    self.BaseClass.Cleanup( self )
end

return Plugin
