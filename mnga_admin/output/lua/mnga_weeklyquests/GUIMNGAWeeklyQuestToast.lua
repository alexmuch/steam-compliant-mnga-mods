--[[
	MNGA Weekly Quests - MMO-style "Quest Complete!" toast (top center).

	Created on demand by the Shine plugin and destroyed once its queue drains,
	so the per-frame Update only exists for a few seconds per completion.
]]

class "GUIMNGAWeeklyQuestToast" ( GUIScript )

local kFadeIn = 0.3
local kHold = 3.6
local kFadeOut = 0.9
local kDuration = kFadeIn + kHold + kFadeOut

local kBandWidth = 640
local kBandHeight = 92
local kVerticalPosition = 0.2

local kTitleFont = Fonts.kAgencyFB_Large_Bold
local kFont = Fonts.kAgencyFB_Large
local kFontPixelSize = 41

-- Explicit scale on a fixed font; GUIMakeFontScale compounds on relayout.
local function SetTextSize( Item, Pixels )
	local Scale = GUIScale( Pixels ) / kFontPixelSize
	Item:SetScale( Vector( Scale, Scale, 0 ) )
end

local kBandColor = Color( 0.06, 0.045, 0.03, 0.78 )
local kLineColor = Color( 0.78, 0.6, 0.28, 0.95 )
local kTitleColor = Color( 1, 0.82, 0.38, 1 )
local kTextColor = Color( 0.95, 0.92, 0.85, 1 )

function GUIMNGAWeeklyQuestToast:Initialize()
	self.queue = {}
	self.current = nil

	self.band = GUIManager:CreateGraphicItem()
	self.band:SetAnchor( GUIItem.Middle, GUIItem.Top )
	self.band:SetLayer( kGUILayerPlayerHUDForeground4 )

	self.topLine = GUIManager:CreateGraphicItem()
	self.topLine:SetAnchor( GUIItem.Left, GUIItem.Top )
	self.band:AddChild( self.topLine )

	self.bottomLine = GUIManager:CreateGraphicItem()
	self.bottomLine:SetAnchor( GUIItem.Left, GUIItem.Top )
	self.band:AddChild( self.bottomLine )

	self.title = GUIManager:CreateTextItem()
	self.title:SetAnchor( GUIItem.Middle, GUIItem.Top )
	self.title:SetTextAlignmentX( GUIItem.Align_Center )
	self.title:SetFontName( kTitleFont )
	self.band:AddChild( self.title )

	self.text = GUIManager:CreateTextItem()
	self.text:SetAnchor( GUIItem.Middle, GUIItem.Top )
	self.text:SetTextAlignmentX( GUIItem.Align_Center )
	self.text:SetFontName( kFont )
	self.band:AddChild( self.text )

	self:Layout()
	self:ApplyAlpha( 0 )
end

function GUIMNGAWeeklyQuestToast:Uninitialize()
	if self.band then
		GUI.DestroyItem( self.band )
		self.band = nil
	end
end

function GUIMNGAWeeklyQuestToast:OnResolutionChanged()
	self:Layout()
end

function GUIMNGAWeeklyQuestToast:Layout()
	local Scale = GUIScale( 1 )
	local Width = kBandWidth * Scale
	local Height = kBandHeight * Scale
	local LineHeight = math.max( 1, 2 * Scale )

	self.band:SetSize( Vector( Width, Height, 0 ) )
	self.band:SetPosition( Vector( -Width * 0.5, Client.GetScreenHeight() * kVerticalPosition, 0 ) )
	self.topLine:SetSize( Vector( Width, LineHeight, 0 ) )
	self.bottomLine:SetSize( Vector( Width, LineHeight, 0 ) )
	self.bottomLine:SetPosition( Vector( 0, Height - LineHeight, 0 ) )

	SetTextSize( self.title, 41 )
	self.title:SetPosition( Vector( 0, 8 * Scale, 0 ) )
	SetTextSize( self.text, 30 )
	self.text:SetPosition( Vector( 0, 52 * Scale, 0 ) )
end

local function WithAlpha( Base, Alpha )
	return Color( Base.r, Base.g, Base.b, Base.a * Alpha )
end

function GUIMNGAWeeklyQuestToast:ApplyAlpha( Alpha )
	self.band:SetColor( WithAlpha( kBandColor, Alpha ) )
	self.topLine:SetColor( WithAlpha( kLineColor, Alpha ) )
	self.bottomLine:SetColor( WithAlpha( kLineColor, Alpha ) )
	self.title:SetColor( WithAlpha( kTitleColor, Alpha ) )
	self.text:SetColor( WithAlpha( kTextColor, Alpha ) )
end

function GUIMNGAWeeklyQuestToast:Push( Title, Text )
	self.queue[ #self.queue + 1 ] = { Title = Title, Text = Text }
end

function GUIMNGAWeeklyQuestToast:GetIsFinished()
	return self.current == nil and #self.queue == 0
end

function GUIMNGAWeeklyQuestToast:Update( DeltaTime )
	local Now = Shared.GetTime()
	if not self.current then
		local Next = table.remove( self.queue, 1 )
		if not Next then return end
		self.current = Next
		self.current.StartTime = Now
		self.title:SetText( Next.Title )
		self.text:SetText( Next.Text )
	end

	local Elapsed = Now - self.current.StartTime
	if Elapsed >= kDuration then
		self.current = nil
		self:ApplyAlpha( 0 )
		return
	end

	local Alpha = 1
	if Elapsed < kFadeIn then
		Alpha = Elapsed / kFadeIn
	elseif Elapsed > kFadeIn + kHold then
		Alpha = 1 - ( Elapsed - kFadeIn - kHold ) / kFadeOut
	end
	self:ApplyAlpha( Clamp( Alpha, 0, 1 ) )
end
