--[[
	MNGA Weekly Quests - quest log panel (left side, ready room only).

	Dumb view: the Shine plugin owns all state and pushes rows via SetQuests().
	Only redraws on SetQuests() and a slow (30 s) "resets in" refresh.
]]

class "GUIMNGAWeeklyQuests" ( GUIScript )

local kPanelWidth = 390
local kPadding = 16
local kHeaderHeight = 58
local kRowHeight = 30
local kFooterHeight = 60
local kMarkerSize = 10
local kScreenMargin = 24
local kTopOffset = 0.1
local kBorder = 2

-- Fixed font files with an explicit scale (same approach as sourceshimizushine
-- poker). GUIMakeFontScale is not idempotent: re-running it on relayout reads
-- the previously swapped font and compounds the size.
local kTitleFont = Fonts.kAgencyFB_Large_Bold
local kFont = Fonts.kAgencyFB_Large
local kFontPixelSize = 41
local kTitleTextSize = 32
local kSubtitleTextSize = 21
local kRowTextSize = 25
local kFooterTextSize = 21

local function SetTextSize( Item, Pixels )
	local Scale = GUIScale( Pixels ) / kFontPixelSize
	Item:SetScale( Vector( Scale, Scale, 0 ) )
end

local kBorderColor = Color( 0.78, 0.6, 0.28, 0.9 )
local kBackgroundColor = Color( 0.06, 0.045, 0.03, 0.5 )
local kHeaderColor = Color( 0.12, 0.085, 0.045, 0.35 )
local kTitleColor = Color( 1, 0.82, 0.38, 1 )
local kSubtitleColor = Color( 0.78, 0.72, 0.6, 1 )
local kQuestColor = Color( 0.95, 0.92, 0.85, 1 )
local kCounterColor = Color( 1, 0.82, 0.38, 1 )
local kDoneColor = Color( 0.45, 0.82, 0.4, 1 )
local kMarkerFill = Color( 0.1, 0.08, 0.05, 1 )
local kSeparatorColor = Color( 0.78, 0.6, 0.28, 0.45 )
local kFooterColor = Color( 0.86, 0.76, 0.52, 1 )

GUIMNGAWeeklyQuests.updateInterval = 30

local function CreateGraphic( Parent, Color_ )
	local Item = GUIManager:CreateGraphicItem()
	Item:SetAnchor( GUIItem.Left, GUIItem.Top )
	Item:SetColor( Color_ )
	if Parent then Parent:AddChild( Item ) end
	return Item
end

local function CreateText( Parent, Font, Color_ )
	local Item = GUIManager:CreateTextItem()
	Item:SetAnchor( GUIItem.Left, GUIItem.Top )
	Item:SetFontName( Font )
	Item:SetColor( Color_ )
	Parent:AddChild( Item )
	return Item
end

function GUIMNGAWeeklyQuests:Initialize()
	self.quests = {}
	self.rows = {}

	-- Transparent root; the gold frame is four thin edge items so it never
	-- shows through the translucent background.
	self.border = CreateGraphic( nil, Color( 0, 0, 0, 0 ) )
	self.border:SetAnchor( GUIItem.Left, GUIItem.Top )
	self.border:SetLayer( kGUILayerPlayerHUDForeground1 )
	self.edges = {}
	for i = 1, 4 do
		self.edges[ i ] = CreateGraphic( self.border, kBorderColor )
	end

	self.background = CreateGraphic( self.border, kBackgroundColor )
	self.header = CreateGraphic( self.background, kHeaderColor )
	self.headerLine = CreateGraphic( self.background, kBorderColor )
	self.title = CreateText( self.background, kTitleFont, kTitleColor )
	self.title:SetText( "Weekly Quests" )
	self.subtitle = CreateText( self.background, kFont, kSubtitleColor )
	self.subtitle:SetTextAlignmentX( GUIItem.Align_Max )
	self.footerLine = CreateGraphic( self.background, kSeparatorColor )
	self.footer1 = CreateText( self.background, kFont, kFooterColor )
	self.footer1:SetText( "Reward: 25,000 poker credits each" )
	self.footer2 = CreateText( self.background, kFont, kFooterColor )
	self.footer2:SetText( "Complete all: +200,000 poker credits" )

	self:Layout()
end

function GUIMNGAWeeklyQuests:Uninitialize()
	if self.border then
		GUI.DestroyItem( self.border )
		self.border = nil
	end
	self.rows = {}
end

function GUIMNGAWeeklyQuests:OnResolutionChanged()
	self:Layout()
end

function GUIMNGAWeeklyQuests:EnsureRow( Index )
	local Row = self.rows[ Index ]
	if Row then return Row end
	Row = {}
	Row.markerBorder = CreateGraphic( self.background, kBorderColor )
	Row.marker = CreateGraphic( Row.markerBorder, kMarkerFill )
	Row.text = CreateText( self.background, kFont, kQuestColor )
	Row.counter = CreateText( self.background, kFont, kCounterColor )
	Row.counter:SetTextAlignmentX( GUIItem.Align_Max )
	self.rows[ Index ] = Row
	return Row
end

function GUIMNGAWeeklyQuests:Layout()
	local Scale = GUIScale( 1 )
	local Count = #self.quests
	local Width = kPanelWidth * Scale
	local Height = ( kHeaderHeight + kPadding + Count * kRowHeight + kPadding + kFooterHeight ) * Scale
	local B = kBorder * Scale

	self.border:SetSize( Vector( Width + B * 2, Height + B * 2, 0 ) )
	self.border:SetPosition( Vector( kScreenMargin * Scale, Client.GetScreenHeight() * kTopOffset, 0 ) )
	self.background:SetSize( Vector( Width, Height, 0 ) )
	self.background:SetPosition( Vector( B, B, 0 ) )
	local OuterW, OuterH = Width + B * 2, Height + B * 2
	self.edges[ 1 ]:SetSize( Vector( OuterW, B, 0 ) )            -- top
	self.edges[ 1 ]:SetPosition( Vector( 0, 0, 0 ) )
	self.edges[ 2 ]:SetSize( Vector( OuterW, B, 0 ) )            -- bottom
	self.edges[ 2 ]:SetPosition( Vector( 0, OuterH - B, 0 ) )
	self.edges[ 3 ]:SetSize( Vector( B, Height, 0 ) )            -- left
	self.edges[ 3 ]:SetPosition( Vector( 0, B, 0 ) )
	self.edges[ 4 ]:SetSize( Vector( B, Height, 0 ) )            -- right
	self.edges[ 4 ]:SetPosition( Vector( OuterW - B, B, 0 ) )

	self.header:SetSize( Vector( Width, kHeaderHeight * Scale, 0 ) )
	self.headerLine:SetSize( Vector( Width, math.max( 1, Scale ), 0 ) )
	self.headerLine:SetPosition( Vector( 0, kHeaderHeight * Scale, 0 ) )

	SetTextSize( self.title, kTitleTextSize )
	self.title:SetPosition( Vector( kPadding * Scale, 12 * Scale, 0 ) )

	SetTextSize( self.subtitle, kSubtitleTextSize )
	self.subtitle:SetPosition( Vector( Width - kPadding * Scale, 22 * Scale, 0 ) )

	local Y = kHeaderHeight + kPadding
	for i = 1, Count do
		local Row = self:EnsureRow( i )
		local RowY = ( Y + ( i - 1 ) * kRowHeight ) * Scale
		Row.markerBorder:SetSize( Vector( kMarkerSize * Scale, kMarkerSize * Scale, 0 ) )
		Row.markerBorder:SetPosition( Vector( kPadding * Scale, RowY + 7 * Scale, 0 ) )
		Row.marker:SetSize( Vector( ( kMarkerSize - 2 ) * Scale, ( kMarkerSize - 2 ) * Scale, 0 ) )
		Row.marker:SetPosition( Vector( Scale, Scale, 0 ) )
		SetTextSize( Row.text, kRowTextSize )
		Row.text:SetPosition( Vector( ( kPadding + kMarkerSize + 10 ) * Scale, RowY, 0 ) )
		SetTextSize( Row.counter, kRowTextSize )
		Row.counter:SetPosition( Vector( Width - kPadding * Scale, RowY, 0 ) )
	end

	local FooterY = ( Y + Count * kRowHeight + kPadding * 0.5 ) * Scale
	self.footerLine:SetSize( Vector( Width - kPadding * 2 * Scale, math.max( 1, Scale ), 0 ) )
	self.footerLine:SetPosition( Vector( kPadding * Scale, FooterY, 0 ) )
	SetTextSize( self.footer1, kFooterTextSize )
	self.footer1:SetPosition( Vector( kPadding * Scale, FooterY + 8 * Scale, 0 ) )
	SetTextSize( self.footer2, kFooterTextSize )
	self.footer2:SetPosition( Vector( kPadding * Scale, FooterY + 30 * Scale, 0 ) )
end

-- Quests: array of { Title, CounterText, Done }
function GUIMNGAWeeklyQuests:SetQuests( Quests, SubtitleText )
	local Relayout = #Quests ~= #self.quests
	self.quests = Quests
	if Relayout then self:Layout() end

	for i = 1, #Quests do
		local Quest = Quests[ i ]
		local Row = self:EnsureRow( i )
		Row.text:SetText( Quest.Title )
		Row.text:SetColor( Quest.Done and kDoneColor or kQuestColor )
		Row.counter:SetText( Quest.CounterText )
		Row.counter:SetColor( Quest.Done and kDoneColor or kCounterColor )
		Row.marker:SetColor( Quest.Done and kDoneColor or kMarkerFill )
	end
	self:SetSubtitle( SubtitleText )
end

function GUIMNGAWeeklyQuests:SetSubtitle( Text )
	self.subtitle:SetText( Text or "" )
end

function GUIMNGAWeeklyQuests:SetIsVisible( Visible )
	self.border:SetIsVisible( Visible )
end

function GUIMNGAWeeklyQuests:Update( DeltaTime )
	if self.OnSlowUpdate then self.OnSlowUpdate( self ) end
end
