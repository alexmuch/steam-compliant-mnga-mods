local Plugin = ...

local SGUI = Shine.GUI
local Date = os.date
local Format = string.format

function Plugin:Initialise()
	self:SetupAdminMenu()
	self.Enabled = true
	return true
end

local function ExpiryText( Expires )
	return Expires == 0 and "Never" or Date( "%Y-%m-%d %H:%M", Expires )
end

function Plugin:OpenAddWindow( IsGameGag, SteamID )
	local Units = SGUI.Layout.Units
	local Scaled = Units.HighResScaled
	local Spacing = Units.Spacing
	local Percent = Units.Percentage
	local Font = { Family = "kAgencyFB", Size = Scaled( 27 ) }
	local Modal = SGUI:Create( "Modal" )
	Modal.TitleBarHeight = Scaled( 28 )
	Modal:AddTitleBar( self:GetPhrase( IsGameGag and "ADD_GAME_GAG" or "ADD_GAG" ), Font )
	local Elements = SGUI:BuildTree( {
		Parent = Modal,
		{ Class = "Label", Props = { Text = "NS2ID:", AutoFont = Font } },
		{ Class = "Horizontal", Type = "Layout", Props = {
			AutoSize = Units.UnitVector( Percent.ONE_HUNDRED, Scaled( 32 ) ), Fill = false,
			Margin = Spacing( 0, Scaled( 4 ), 0, Scaled( 5 ) )
		}, Children = {
			{ ID = "ID", Class = "TextEntry", Props = {
				Fill = true, AutoFont = Font, Numeric = true, Text = SteamID, StyleName = "InputGroupStart"
			} },
			{ ID = "Players", Class = "Button", Props = {
				AutoFont = { Family = "Ionicons", Size = Scaled( 29 ) },
				AutoSize = Units.UnitVector( Scaled( 32 ), Scaled( 32 ) ),
				Text = SGUI.Icons.Ionicons.ArrowDownB, Tooltip = self:GetPhrase( "SELECT_PLAYER" ),
				StyleName = "InputGroupEnd"
			} }
		} },
		{ Class = "Label", Props = { Text = self:GetPhrase( "DURATION" ), AutoFont = Font } },
		{ ID = "Duration", Class = "TextEntry", Props = {
			AutoFont = Font, AutoSize = Units.UnitVector( Percent.ONE_HUNDRED, Scaled( 32 ) ),
			Text = "30m", Margin = Spacing( 0, Scaled( 4 ), 0, Scaled( 5 ) )
		} },
		{ Class = "Label", Props = { Text = self:GetPhrase( "REASON" ), AutoFont = Font } },
		{ ID = "Reason", Class = "TextEntry", Props = {
			AutoFont = Font, AutoSize = Units.UnitVector( Percent.ONE_HUNDRED, Scaled( 32 ) ),
			Text = "No reason given.", Margin = Spacing( 0, Scaled( 4 ), 0, Scaled( 8 ) )
		} },
		{ ID = "Confirm", Class = "Button", Props = {
			AutoFont = Font, Text = self:GetPhrase( IsGameGag and "ADD_GAME_GAG" or "ADD_GAG" ),
			StyleName = "SuccessButton", AutoSize = Units.UnitVector( Percent.ONE_HUNDRED, Scaled( 36 ) )
		} }
	} )
	Modal.Layout:SetPadding( Spacing( Scaled( 16 ), Scaled( 4 ), Scaled( 16 ), Scaled( 8 ) ) )
	Modal:SetSize( Vector2( Scaled( 440 ):GetValue(), Modal:GetContentSizeForAxis( 2 ) ) )
	local Window = Shine.AdminMenu.Window
	Modal:SetPos( Window:GetScreenPos() + Window:GetSize() * 0.5 - Modal:GetSize() * 0.5 )
	Modal:SetDraggable( true )
	Modal:PopUp( Window )
	Shine.AdminMenu:AttachModal( Modal )

	Elements.Players:SetOpenMenuOnClick( function( Button )
		return {
			MenuPos = Vector2( -Elements.ID:GetSize().x, Button:GetSize().y ),
			Size = Vector2( Elements.ID:GetSize().x + Button:GetSize().x, Scaled( 28 ):GetValue() ),
			Populate = function( Menu )
				Menu:SetMaxVisibleButtons( 12 )
				for _, Ent in ientitylist( Shared.GetEntitiesWithClassname( "PlayerInfoEntity" ) ) do
					local ID = tostring( Ent.steamId )
					Menu:AddButton( Ent.playerName, function()
						if SGUI.IsValid( Elements.ID ) then Elements.ID:SetText( ID ) end
						Menu:Destroy()
					end ):SetAutoFont( Font )
				end
			end
		}
	end )

	function Elements.Confirm.DoClick()
		local ID = Elements.ID:GetText()
		local Duration = Elements.Duration:GetText()
		if ID == "" or Duration == "" then return end
		Shine.AdminMenu:RunCommand( IsGameGag and "sh_gaggameid" or "sh_gagid",
			Format( "%s %s %s", ID, Duration, Elements.Reason:GetText() ) )
		Modal:Close()
	end
	Elements.ID:RequestFocus()
end

function Plugin:SetupAdminMenu()
	local Units = SGUI.Layout.Units
	local Scaled = Units.HighResScaled
	local Spacing = Units.Spacing
	local Percent = Units.Percentage
	local Auto = Units.Auto
	self:AddAdminMenuTab( self:GetPhrase( "GAGS" ), {
		Icon = SGUI.Icons.Ionicons.MicOff or SGUI.Icons.Ionicons.VolumeMute,
		OnInit = function( Panel, Data )
			self.GagMenuOpen = true
			local Layout = SGUI.Layout:CreateLayout( "Vertical", {
				Padding = Spacing( Scaled( 16 ), Scaled( 32 ), Scaled( 16 ), Scaled( 16 ) )
			} )
			local Font, Scale = SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 )
			local Search = SGUI:Create( "TextEntry", Panel )
			Search:SetFontScale( Font, Scale )
			Search:SetAutoSize( Units.UnitVector( Percent.ONE_HUNDRED, Scaled( 32 ) ) )
			Search:SetPlaceholderText( self:GetPhrase( "SEARCH_HINT" ) )
			Search:SetMargin( Spacing( 0, 0, 0, Scaled( 16 ) ) )
			Layout:AddElement( Search )

			local List = SGUI:Create( "List", Panel )
			List:SetColumns( self:GetPhrase( "PLAYER" ), self:GetPhrase( "TYPE" ),
				self:GetPhrase( "GAGGED_BY" ), self:GetPhrase( "EXPIRY" ) )
			List:SetSpacing( 0.28, 0.15, 0.27, 0.3 )
			List:SetFill( true )
			List:SetSortedExternally( true )
			Shine.AdminMenu.SetupListWithScaling( List )
			Layout:AddElement( List )
			self.GagList = List

			Data = Data or { Page = 1, MaxResults = 15, SortColumn = 4, SortAscending = true, Filter = "" }
			self.CurrentPage = Data
			function Search.OnTextChanged()
				self.SearchTimer = self.SearchTimer or self:SimpleTimer( 0.3, function()
					self.SearchTimer = nil
					if not SGUI.IsValid( Search ) then return end
					Data.Page, Data.Filter = 1, Search:GetText()
					self:RequestGagPage( Data )
				end )
				self.SearchTimer:Debounce()
			end
			function List.HandleExternalSorting( _, Column, Descending )
				Data.SortColumn = Column
				Data.SortAscending = not Descending
				self:RequestGagPage( Data )
				return true
			end

			local Controls = SGUI.Layout:CreateLayout( "Horizontal", {
				Margin = Spacing( 0, Scaled( 16 ), 0, 0 ), Fill = false
			} )
			local PageButtonSize = Units.UnitVector(
				Units.Max( Scaled( 32 ), Auto.INSTANCE + Scaled( 8 ) ),
				Percent.ONE_HUNDRED
			)
			local Navigation = SGUI.Layout:CreateLayout( "Horizontal", {
				Fill = false,
				Alignment = SGUI.LayoutAlignment.CENTRE,
				AutoSize = Units.UnitVector( Auto.INSTANCE, Percent.ONE_HUNDRED )
			} )
			local Back = SGUI:Create( "Button", Panel )
			Back:SetIcon( SGUI.Icons.Ionicons.ArrowLeftB )
			Back:SetAutoSize( PageButtonSize )
			Back:SetAlignment( SGUI.LayoutAlignment.CENTRE )
			function Back.DoClick() Data.Page = Data.Page - 1 self:RequestGagPage( Data ) end
			Navigation:AddElement( Back )
			local Page = SGUI:Create( "Label", Panel )
			Page:SetFontScale( Font, Scale )
			Page:SetText( "1 / 1" )
			Page:SetAlignment( SGUI.LayoutAlignment.CENTRE )
			Page:SetCrossAxisAlignment( SGUI.LayoutAlignment.CENTRE )
			Page:SetMargin( Spacing( Scaled( 12 ), 0, Scaled( 12 ), 0 ) )
			Navigation:AddElement( Page )
			local Forward = SGUI:Create( "Button", Panel )
			Forward:SetIcon( SGUI.Icons.Ionicons.ArrowRightB )
			Forward:SetAutoSize( PageButtonSize )
			Forward:SetAlignment( SGUI.LayoutAlignment.CENTRE )
			function Forward.DoClick() Data.Page = Data.Page + 1 self:RequestGagPage( Data ) end
			Navigation:AddElement( Forward )
			Controls:AddElement( Navigation )

			local Actions = SGUI.Layout:CreateLayout( "Horizontal", {
				Fill = false,
				Alignment = SGUI.LayoutAlignment.MAX,
				AutoSize = Units.UnitVector( Auto.INSTANCE, Percent.ONE_HUNDRED )
			} )
			local function AddButton( Text, Icon, Callback, Style )
				local Button = SGUI:Create( "Button", Panel )
				Button:SetText( Text ) Button:SetFontScale( Font, Scale ) Button:SetIcon( Icon )
				if Style then Button:SetStyleName( Style ) end
				Button.DoClick = Callback return Button
			end
			local Ungag = AddButton( self:GetPhrase( "UNGAG" ), SGUI.Icons.Ionicons.TrashB, function()
				local Row = List:GetSelectedRow()
				if Row and Row.GagData then Shine.AdminMenu:RunCommand( "sh_ungagid", Row.GagData.ID ) end
			end, "DangerButton" )
			Ungag:SetEnabled( false )
			Controls:AddElement( Ungag )
			local AddGag = AddButton( self:GetPhrase( "ADD_GAG" ), SGUI.Icons.Ionicons.Plus,
				function() self:OpenAddWindow( false ) end )
			Actions:AddElement( AddGag )
			local AddGameGag = AddButton( self:GetPhrase( "ADD_GAME_GAG" ), SGUI.Icons.Ionicons.Plus,
				function() self:OpenAddWindow( true ) end )
			Actions:AddElement( AddGameGag )
			local ActionButtonWidth = Units.Max(
				Scaled( 128 ),
				Auto( Ungag ) + Scaled( 16 ),
				Auto( AddGag ) + Scaled( 16 ),
				Auto( AddGameGag ) + Scaled( 16 )
			)
			local ActionButtonSize = Units.UnitVector( ActionButtonWidth, Percent.ONE_HUNDRED )
			Ungag:SetAutoSize( ActionButtonSize )
			AddGag:SetAutoSize( ActionButtonSize )
			AddGameGag:SetAutoSize( ActionButtonSize )
			Controls:AddElement( Actions )
			local ButtonHeight = Units.Max( Auto( AddGameGag ), Auto( Forward ) ) + Scaled( 8 )
			Controls:SetAutoSize( Units.UnitVector( Percent.ONE_HUNDRED, ButtonHeight ) )
			function List:OnRowSelected() Ungag:SetEnabled( true ) end
			function List:OnRowDeselected() Ungag:SetEnabled( false ) end
			Layout:AddElement( Controls )
			Panel:SetLayout( Layout ) Panel:InvalidateLayout( true )
			self.PageBack, self.PageForward, self.PageLabel = Back, Forward, Page
			self:RequestGagPage( Data )
		end,
		OnCleanup = function()
			self.GagList, self.PageBack, self.PageForward, self.PageLabel = nil, nil, nil, nil
			self.GagMenuOpen = false
			return self.CurrentPage
		end
	} )
end

function Plugin:RequestGagPage( Data )
	self:SendNetworkMessage( "RequestGagPage", Data, true )
end

function Plugin:ReceiveGagData( Data )
	if not SGUI.IsValid( self.GagList ) then return end
	local Row = self.GagList:AddRow( Format( "%s [%s]", Data.Name, Data.ID ),
		self:GetPhrase( Data.GagType == 2 and "GAME_GAG" or "GAG" ),
		Format( "%s [%s]", Data.GaggedBy, Data.GaggerID ), ExpiryText( Data.Expires ) )
	Row:SetTooltip( Format( "Issued: %s\nDuration: %s\nReason: %s",
		Date( "%Y-%m-%d %H:%M", Data.Issued ),
		Data.Duration == 0 and "Permanent" or string.TimeToString( Data.Duration ), Data.Reason ) )
	Row.GagData = Data
end

function Plugin:ReceiveGagPage( Data )
	Shared.Message( string.format( "[MNGAGags] Client got page %s/%s, %s rows, list valid: %s",
		tostring( Data.Page ), tostring( Data.NumPages ), tostring( Data.TotalNumResults ), tostring( SGUI.IsValid( self.GagList ) ) ) )
	if not SGUI.IsValid( self.GagList ) then return end
	self.GagList:Clear()
	self.CurrentPage.Page = Data.Page
	self.PageLabel:SetText( Format( "%d / %d", Data.Page, Data.NumPages ) )
	self.PageLabel:SetTooltip( Format( "%d gags", Data.TotalNumResults ) )
	self.PageBack:SetEnabled( Data.Page > 1 )
	self.PageForward:SetEnabled( Data.Page < Data.NumPages )
end

function Plugin:ReceiveGagDataChanged()
	if self.GagMenuOpen and self.CurrentPage then self:RequestGagPage( self.CurrentPage ) end
end
