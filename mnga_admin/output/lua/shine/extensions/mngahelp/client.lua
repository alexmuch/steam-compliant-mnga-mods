--[[
	MNGA Help - client.

	Paged help window modelled on the poker help window (!pokerhelp), with a
	neutral palette. Each page is a command column and a description column.
	Both columns are single labels in the same font, so a row whose
	description spans N lines pads its command with N-1 newlines to stay
	aligned. Keep description lines to ~50 characters so they fit the column.
]]

local Plugin = ...
local SGUI = Shine.GUI
local StringFormat = string.format
local StringRep = string.rep

local FONT = "fonts/AgencyFB_large.fnt"
local WINDOW_W, WINDOW_H = 720, 560
local COMMAND_X, DESC_X = 24, 236

local COL_BG = Colour( 0.055, 0.065, 0.085, 0.97 )
local COL_BUTTON = Colour( 0.16, 0.20, 0.27, 1 )
local COL_BUTTON_HOVER = Colour( 0.24, 0.31, 0.42, 1 )
local COL_BUTTON_DISABLED = Colour( 0.13, 0.14, 0.16, 0.92 )
local COL_TEXT = Colour( 0.90, 0.92, 0.95, 1 )
local COL_DIM = Colour( 0.62, 0.67, 0.75, 1 )
local COL_TITLE = Colour( 0.45, 0.75, 1, 1 )
local COL_COMMAND = Colour( 1, 0.82, 0.45, 1 )

local HELP_PAGES = {
	{
		Title = "CHAT COMMANDS",
		Intro = "Type these in chat. Reopen this window with !help.",
		Rows = {
			{ "!xp", "Your level, XP, comm XP and token counts." },
			{ "!discord", "Link to the community Discord." },
			{ "!skipq", "Spend a supporter or seeding token to skip\nthe player-slot queue (spectators only)." },
			{ "!skipq <player>", "Spend a supporter token to skip the queue\nfor a spectating player (name, part of a\nname, or Steam ID)." },
			{ "!rr_dequeue", "Leave the player-slot queue." },
			{ "!tribute m / a", "From spectator, volunteer to command marines\n(m) or aliens (a) while that chair is empty.\nAfter 30s a random player swaps out for you." },
			{ "!tribute info", "Your immunity from the tribute draw." },
			{ "!tribute help", "Full tribute rules and immunity table." },
			{ "!hats", "Pick a hat to wear. Unlock more by levelling\nup, commanding, supporting and achievements." }
		}
	},
	{
		Title = "MINI-GAMES AND SOUNDS",
		Intro = "Mini-games are for spectators and the ready room.",
		Rows = {
			{ "!poker", "Open the Texas Hold'em table. Your weekly\nbank starts from your XP (XP never changes)." },
			{ "!pokerhelp", "Poker rules, timers and weekly scoring." },
			{ "!pokertop", "Your bank, ranked winnings and the top ten." },
			{ "!m3", "Open the Match3 puzzle game." },
			{ "!mangasize 30-120", "Mini-game window size in % (or use - / +)." },
			{ "!mangaopacity 30-100", "Mini-game window opacity in % (or use - / +)." },
			{ "sh_dfn", "Console: toggle MNGA notification sounds\n(connected, queue done, round start, AFK).\nAdd true / false to set it. Chat: !sounds" },
			{ "sh_dfnvolume 0-200", "Console: notification sound volume in %.\nChat: !soundvolume 0-200" }
		}
	},
	{
		Title = "OPTIONS > MODS",
		Intro = "Open Options, then the Mods tab, to set these up:",
		Rows = {
			{ "Quick Bind", "One key per lifeform ability (parasite, babblers,\nhydra, umbra, spores, stab...). Press once to use\nit and return to your previous weapon." },
			{ "Radio Commands", "Bind a key to open the numbered radio menu,\nthen pick with 1-9. Also sets radio volume." },
			{ "Proximity Voice", "Enable it and bind push-to-talk to speak to\nplayers near you. Normal voice is unaffected." },
			{ "AV Studio", "Customise your alien vision." },
			{ "Shimizu QoL", "Commander cooldown numbers, a \"Muted\" bar while\na player you muted is talking, notification\nsounds (same as sh_dfn)." },
			{ "Hats", "Pick your hat, or hide everyone's hats\nfor yourself only." }
		}
	}
}

-- Pre-build the two column strings for every page once.
for _, Page in ipairs( HELP_PAGES ) do
	local Commands, Descriptions = {}, {}
	for _, Row in ipairs( Page.Rows ) do
		local _, ExtraLines = Row[ 2 ]:gsub( "\n", "" )
		Commands[ #Commands + 1 ] = Row[ 1 ] .. StringRep( "\n", ExtraLines )
		Descriptions[ #Descriptions + 1 ] = Row[ 2 ]
	end
	Page.CommandText = table.concat( Commands, "\n" )
	Page.DescriptionText = table.concat( Descriptions, "\n" )
end

local function GetUIScale()
	return GetMangaUIScale and GetMangaUIScale() or 1
end

local function S( X ) return math.floor( GUIScale( X ) * GetUIScale() ) end

-- Same text scaling as poker: fonts tuned at 2560x1600, SGUI fonts are
-- fixed-size so text is scaled separately from the GUIScale-based layout.
local TEXT_REFERENCE_RESOLUTION = 1600

local function GetTextScaleValue()
	local ScreenW, ScreenH = SGUI.GetScreenSize()
	return math.min( ScreenW, ScreenH ) / TEXT_REFERENCE_RESOLUTION * GetUIScale()
end

local function AddLabel( Parent, X, Y, Text, TextColour )
	local Label = SGUI:Create( "Label", Parent )
	Label:SetupFromTable{ Pos = Vector2( S( X ), S( Y ) ), Text = Text or "", TextColour = TextColour or COL_TEXT,
		Font = FONT }
	local Scale = GetTextScaleValue()
	Label:SetTextScale( Vector2( Scale, Scale ) )
	return Label
end

local function AddButton( Parent, X, Y, W, H, Text, Click )
	local Button = SGUI:Create( "Button", Parent )
	Button:SetupFromTable{ Pos = Vector2( S( X ), S( Y ) ), Size = Vector2( S( W ), S( H ) ), Text = Text,
		ActiveCol = COL_BUTTON_HOVER, InactiveCol = COL_BUTTON, TextColour = COL_TEXT,
		Font = FONT, HighlightOnMouseOver = true }
	local Scale = GetTextScaleValue()
	Button:SetTextScale( Vector2( Scale, Scale ) )
	-- Shine's skin can restore its default grey after the first hover; keep
	-- this palette authoritative (same fix as the poker buttons).
	function Button:SetHighlighted( Highlighted )
		self.Highlighted = not not Highlighted
		self:StopFade( self.Background )
		if not self:IsEnabled() then self:SetBackgroundColour( COL_BUTTON_DISABLED ); return end
		self:SetBackgroundColour( Highlighted and COL_BUTTON_HOVER or COL_BUTTON )
	end
	function Button:SetHelpEnabled( Enabled )
		self:SetEnabled( Enabled )
		self:StopFade( self.Background )
		self:SetBackgroundColour( Enabled and COL_BUTTON or COL_BUTTON_DISABLED )
	end
	function Button:DoClick()
		if not self:IsEnabled() then return end
		Click()
	end
	return Button
end

local function ClampWindowPosition( Position, Width, Height, ScreenW, ScreenH )
	if not Position then return Vector2( ( ScreenW - Width ) * 0.5, ( ScreenH - Height ) * 0.5 ) end
	return Vector2( math.max( 0, math.min( ScreenW - Width, Position.x ) ),
		math.max( 0, math.min( ScreenH - Height, Position.y ) ) )
end

function Plugin:Initialise()
	Shine.Hook.Add( "OnMangaUISizeChanged", "MNGAHelpUISize", function()
		Plugin:ApplyUISize()
	end )
	self.Enabled = true
	return true
end

function Plugin:ReceiveOpenHelp()
	if self.Window and self.Window:IsValid() then
		-- Re-typing !help on an open window jumps back to the first page.
		self:SetPage( 1 )
		return
	end
	self:OpenWindow()
end

function Plugin:OpenWindow( Position, Page )
	if self.Window and self.Window:IsValid() then return end
	local W, H = S( WINDOW_W ), S( WINDOW_H )
	local SW, SH = SGUI.GetScreenSize()
	Position = ClampWindowPosition( Position, W, H, SW, SH )

	local Win = SGUI:Create( "Panel" )
	Win:SetupFromTable{ Size = Vector2( W, H ), Pos = Position, Colour = COL_BG, Draggable = true }
	self.Window = Win
	SGUI:EnableMouse( true, Win )

	self.TitleLabel = AddLabel( Win, 14, 12, "", COL_TITLE )
	self.IntroLabel = AddLabel( Win, COMMAND_X, 62, "", COL_DIM )
	self.CommandLabel = AddLabel( Win, COMMAND_X, 104, "", COL_COMMAND )
	self.DescriptionLabel = AddLabel( Win, DESC_X, 104, "", COL_TEXT )
	self.PageLabel = AddLabel( Win, 340, 510, "" )
	self.PrevButton = AddButton( Win, 20, 502, 120, 38, "Previous", function() Plugin:SetPage( Plugin.Page - 1 ) end )
	self.NextButton = AddButton( Win, 580, 502, 120, 38, "Next", function() Plugin:SetPage( Plugin.Page + 1 ) end )
	AddButton( Win, 674, 10, 30, 28, "X", function() Plugin:CloseWindow() end )

	self:SetPage( Page or 1 )
end

function Plugin:SetPage( Page )
	if not ( self.Window and self.Window:IsValid() ) then return end
	self.Page = math.max( 1, math.min( #HELP_PAGES, Page ) )
	local Data = HELP_PAGES[ self.Page ]
	self.TitleLabel:SetText( "SERVER HELP - " .. Data.Title )
	self.IntroLabel:SetText( Data.Intro or "" )
	self.CommandLabel:SetText( Data.CommandText )
	self.DescriptionLabel:SetText( Data.DescriptionText )
	self.PageLabel:SetText( StringFormat( "%d / %d", self.Page, #HELP_PAGES ) )
	self.PrevButton:SetHelpEnabled( self.Page > 1 )
	self.NextButton:SetHelpEnabled( self.Page < #HELP_PAGES )
end

function Plugin:CloseWindow()
	local Window = self.Window
	if not Window then return end
	SGUI:EnableMouse( false, Window )
	if Window:IsValid() then Window:Destroy() end
	self.Window = nil
	self.TitleLabel, self.IntroLabel, self.CommandLabel, self.DescriptionLabel = nil, nil, nil, nil
	self.PageLabel, self.PrevButton, self.NextButton = nil, nil, nil
end

function Plugin:ApplyUISize()
	if not ( self.Window and self.Window:IsValid() ) then return end
	local Position, Page = self.Window:GetPos(), self.Page
	self:CloseWindow()
	self:OpenWindow( Position, Page )
end

function Plugin:Cleanup()
	Shine.Hook.Remove( "OnMangaUISizeChanged", "MNGAHelpUISize" )
	self:CloseWindow()
	self.BaseClass.Cleanup( self )
	self.Enabled = false
end
