Script.Load( "lua/mnga_administration/RadioCommandsRegistry.lua" )
Script.Load( "lua/BindingsDialog.lua" )

class "GUIRadioCommands" ( GUIScript )

local kPanelWidth = 360
local kHeaderHeight = 42
local kRowHeight = 38
local kPanelPadding = 14
local kScreenMargin = 28
local kVerticalScreenOffset = 0.15
local kFont = Fonts.kAgencyFB_Small
local kNumberKeys = {
    [ InputKey.Num1 ] = 1,
    [ InputKey.Num2 ] = 2,
    [ InputKey.Num3 ] = 3,
    [ InputKey.Num4 ] = 4,
    [ InputKey.Num5 ] = 5,
    [ InputKey.Num6 ] = 6,
    [ InputKey.Num7 ] = 7,
    [ InputKey.Num8 ] = 8,
    [ InputKey.Num9 ] = 9
}

local function GetLocalRadioTeam()
    local Player = Client.GetLocalPlayer()
    local ClientTeamNumber = Client.GetLocalClientTeamNumber and Client.GetLocalClientTeamNumber()
    if ClientTeamNumber == kSpectatorIndex then return ClientTeamNumber end
    if MNGA_RADIO.IsEligibleTeam( ClientTeamNumber ) then return ClientTeamNumber end
    return Player and Player:GetTeamNumber() or ClientTeamNumber
end

local function GetCanOpen()
    local Player = Client.GetLocalPlayer()
    local TeamNumber = GetLocalRadioTeam()
    return Player ~= nil
        and MNGA_RADIO.IsEligibleTeam( TeamNumber )
        and not ChatUI_EnteringChatMessage()
        and not GetIsTextBeingEntered()
        and not MainMenu_GetIsOpened()
end

function GUIRadioCommands:Initialize()
    self.visible = false
    self.nodeStack = { MNGA_RADIO.Menu }
    self.rowItems = {}
    self:CreateItems()
    self:SetVisible( false )
end

function GUIRadioCommands:CreateItems()
    self.background = GetGUIManager():CreateGraphicItem()
    self.background:SetAnchor( GUIItem.Left, GUIItem.Center )
    self.background:SetColor( Color( 0, 0, 0, 0 ) )
    self.background:SetLayer( kGUILayerPlayerHUDForeground1 )

    self.header = GetGUIManager():CreateTextItem()
    self.header:SetAnchor( GUIItem.Left, GUIItem.Top )
    self.header:SetFontName( kFont )
    self.header:SetColor( Color( 0.35, 0.9, 1, 1 ) )
    self.background:AddChild( self.header )

    self.closeItem = GetGUIManager():CreateTextItem()
    self.closeItem:SetAnchor( GUIItem.Left, GUIItem.Top )
    self.closeItem:SetFontName( kFont )
    self.closeItem:SetColor( Color( 0.65, 0.7, 0.72, 1 ) )
    self.closeItem:SetText( "[0] Close Menu" )
    self.background:AddChild( self.closeItem )

    for Index = 1, 9 do
        local Row = GetGUIManager():CreateTextItem()
        Row:SetAnchor( GUIItem.Left, GUIItem.Top )
        Row:SetFontName( kFont )
        Row:SetColor( Color( 1, 1, 1, 1 ) )
        self.background:AddChild( Row )
        self.rowItems[ Index ] = Row
    end

    self:UpdateScaleAndLayout()
    self:Refresh()
end

function GUIRadioCommands:UpdateScaleAndLayout()
    local Scale = GUIScale( 1 )
    local Width = kPanelWidth * Scale
    local Height = ( kHeaderHeight + kPanelPadding * 2 + kRowHeight * 9 + 30 ) * Scale
    self.background:SetSize( Vector( Width, Height, 0 ) )
    self.background:SetPosition( Vector( kScreenMargin * Scale,
        -Height * 0.5 + Client.GetScreenHeight() * kVerticalScreenOffset, 0 ) )

    local TextScale = Vector( Scale, Scale, Scale )
    self.header:SetScale( TextScale )
    self.header:SetPosition( Vector( kPanelPadding * Scale, kPanelPadding * Scale, 0 ) )
    GUIMakeFontScale( self.header )

    self.closeItem:SetScale( TextScale )
    local VisibleCount = self.visibleSlotCount or 0
    self.closeItem:SetPosition( Vector( kPanelPadding * Scale,
        ( kPanelPadding + kHeaderHeight + ( VisibleCount + 1 ) * kRowHeight ) * Scale, 0 ) )
    GUIMakeFontScale( self.closeItem )

    for Index = 1, 9 do
        local Row = self.rowItems[ Index ]
        Row:SetScale( TextScale )
        Row:SetPosition( Vector(
            kPanelPadding * Scale,
            ( kPanelPadding + kHeaderHeight + ( Index - 1 ) * kRowHeight ) * Scale,
            0
        ) )
        GUIMakeFontScale( Row )
    end
end

function GUIRadioCommands:OnResolutionChanged()
    self:UpdateScaleAndLayout()
end

function GUIRadioCommands:GetCurrentNode()
    return self.nodeStack[ #self.nodeStack ]
end

function GUIRadioCommands:GetBreadcrumb()
    local Labels = {}
    for Index = 1, #self.nodeStack do
        Labels[ Index ] = self.nodeStack[ Index ].Label
    end
    return table.concat( Labels, " > " )
end

function GUIRadioCommands:Refresh()
    local Node = self:GetCurrentNode()
    self.visibleChildren = {}
    self.visibleSlotCount = 0
    for Index = 1, #( Node.Children or {} ) do
        local Child = Node.Children[ Index ]
        if not Child.MarineOnly or self.openTeamNumber == kTeam1Index then
            local Slot = Child.Slot or Index
            self.visibleChildren[ Slot ] = Child
            self.visibleSlotCount = math.max( self.visibleSlotCount, Slot )
        end
    end
    self.header:SetText( self:GetBreadcrumb() )

    for Index = 1, 9 do
        local Child = self.visibleChildren[ Index ]
        local Text = ""
        if Child then
            if Child.Children then
                Text = Child.Label .. "  >"
            else
                local Label = MNGA_RADIO.GetResolvedLabel( Child,
                    self.openTeamNumber or GetLocalRadioTeam() )
                Text = string.format( "[%d]  %s", Index, Label )
            end
        end
        self.rowItems[ Index ]:SetText( Text )
    end
    local Scale = GUIScale( 1 )
    self.closeItem:SetPosition( Vector( kPanelPadding * Scale,
        ( kPanelPadding + kHeaderHeight + ( self.visibleSlotCount + 1 ) * kRowHeight ) * Scale, 0 ) )
end

function GUIRadioCommands:SetVisible( Visible )
    self.visible = Visible
    if self.background then
        self.background:SetIsVisible( Visible )
    end
end

function GUIRadioCommands:Open()
    if not GetCanOpen() then
        return
    end

    self.openTeamNumber = GetLocalRadioTeam()
    self.nodeStack = { MNGA_RADIO.Menu }
    self:Refresh()
    self:SetVisible( true )
end

function GUIRadioCommands:Close()
    if not self.visible then return end
    self:SetVisible( false )
    self.openTeamNumber = nil
    self.nodeStack = { MNGA_RADIO.Menu }
end

function GUIRadioCommands:GoBack()
    self:Close( "zero" )
end

function GUIRadioCommands:Select( Index )
    local Child = self.visibleChildren[ Index ]
    if not Child then return end

    if Child.Children then
        table.insert( self.nodeStack, Child )
        self:Refresh()
        return
    end

    if Child.VanillaVoiceID then
        local TeamKey = self.openTeamNumber == kTeam2Index and "Alien" or "Marine"
        local VoiceID = kVoiceId and kVoiceId[ Child.VanillaVoiceID[ TeamKey ] ]
        local SendVanillaRequest = GUIRequestMenu and GUIRequestMenu.SendKeyEvent
            and debug.getupvaluex( GUIRequestMenu.SendKeyEvent, "SendRequest" )
        if VoiceID and SendVanillaRequest then
            SendVanillaRequest( VoiceID )
        end
    else
        Client.SendNetworkMessage( "MNGARadioRequest", { CommandID = Child.ID }, true )
    end
    self:Close( "command-selected" )
end

function GUIRadioCommands:SendKeyEvent( Key, Down )
    if not Down then
        return self.visible and ( kNumberKeys[ Key ] ~= nil or Key == InputKey.Num0
            or Key == InputKey.Escape or GetIsBinding( Key, MNGA_RADIO.BindingName ) )
    end

    -- Menu digits take priority over the radio binding while open, so a radio key bound to 1-9
    -- still reaches that slot.
    local Index = kNumberKeys[ Key ]
    if self.visible and Index then
        self:Select( Index )
        return true
    end

    if GetIsBinding( Key, MNGA_RADIO.BindingName ) then
        if self.visible then
            self:Close( "binding" )
        else
            self:Open()
        end
        return true
    end

    if not self.visible then return false end

    if Key == InputKey.Escape then
        self:Close( "escape" )
        return true
    end

    if Key == InputKey.Num0 then
        self:GoBack()
        return true
    end

    return false
end

function GUIRadioCommands:Update()
    if self.visible then
        local CurrentTeamNumber = GetLocalRadioTeam()
        if not GetCanOpen() then
            self:Close( "player-state-changed" )
        elseif CurrentTeamNumber ~= self.openTeamNumber then
            self:Close( "team-changed" )
        end
    end
end

function GUIRadioCommands:Uninitialize()
    self:SetVisible( false )
    if self.background then
        GUI.DestroyItem( self.background )
        self.background = nil
    end
    self.rowItems = {}
end
