--[[
	MNGA Ready Check - client (.claude/docs/ready-check.md).

	Keeps the ready flags for the scoreboard (MNGAReadyCheck_IsReady, read by
	sourcessb), owns the GUIMNGAReadyCheck script while a check runs, and
	flashes the taskbar (plus the sh_dfn-gated sound) when the server asks.

	One notification per round. The ready-check notification is the taskbar
	flash plus the sh_dfn sound (mngaforcednotifications "RoundStarting",
	played only when the player has sh_dfn on). After it, the countdown's own
	notifications are skipped once: the vanilla flash (Player:OnCountDown ->
	Client.WindowNeedsAttention) and mngaforcednotifications' countdown
	"RoundStarting" sound (its server sends PlaySound at Countdown).
	Exception: if the game window is not focused at the countdown (player
	readied up and alt-tabbed), both countdown notifications go through.
]]

local Plugin = ...
local Shine = Shine

local GUI_SCRIPT = "mnga_administration/GUIMNGAReadyCheck"
local PHASE_IDLE = 0

-- Reset on every load so a reloaded extension cannot leave stale flags.
MNGAReadyCheckFlags = {}

function MNGAReadyCheck_IsReady( SteamID )
	local Flags = MNGAReadyCheckFlags
	return Flags ~= nil and Flags[ tonumber( SteamID ) or 0 ] == true
end

local function Log( Message, ... )
	Shared.Message( "[readycheck] "..string.format( Message, ... ) )
end

local function ReloadScoreboard()
	if Scoreboard_ReloadPlayerData then Scoreboard_ReloadPlayerData() end
end

-- Ready players who alt-tab after the ready check still need the
-- countdown notification, so suppression only applies while focused.
local function IsWindowFocused()
	return Client.GetIsWindowFocused == nil or Client.GetIsWindowFocused()
end

local function GetForcedNotifications()
	local Notifications = Shine.Plugins and Shine.Plugins[ "mngaforcednotifications" ]
	if not Notifications or not Notifications.Enabled then return nil end
	return Notifications
end

local function TriggerForcedNotificationSound( SoundName, Reason )
	local Notifications = GetForcedNotifications()
	if not Notifications or type( Notifications.PlayNamedSound ) ~= "function" then return end
	Notifications:PlayNamedSound( SoundName, Reason )
end

-- Shine dispatches network messages through self[ "Receive"..Name ] at call
-- time, so an instance field overrides mngaforcednotifications' receiver.
-- Installed lazily on the first ready-check notification.
local function InstallCountdownSoundFilter( self )
	local Notifications = GetForcedNotifications()
	if not Notifications or type( Notifications.ReceivePlaySound ) ~= "function" then return end
	if self.FilteredNotifications == Notifications and Notifications.ReceivePlaySound == self.SoundFilter then return end
	local Original = Notifications.ReceivePlaySound
	self.FilteredNotifications = Notifications
	self.OriginalReceivePlaySound = Original
	self.SoundFilter = function( NotificationsSelf, Data )
		if self.SuppressCountdownSound and Data and Data.SoundName == "RoundStarting" then
			self.SuppressCountdownSound = false
			if IsWindowFocused() then return end
		end
		return Original( NotificationsSelf, Data )
	end
	Notifications.ReceivePlaySound = self.SoundFilter
end

local function RemoveCountdownSoundFilter( self )
	local Notifications = self.FilteredNotifications
	if Notifications and Notifications.ReceivePlaySound == self.SoundFilter then
		Notifications.ReceivePlaySound = self.OriginalReceivePlaySound
	end
	self.FilteredNotifications = nil
	self.OriginalReceivePlaySound = nil
	self.SoundFilter = nil
end

-- Wraps Player.OnCountDown (Marine/Alien call Player.OnCountDown(self), so the
-- one wrapper covers them; ReadyRoomPlayer's is already empty). Runs once per
-- round on the local player only.
local function InstallCountdownFlashFilter( self )
	if self.OriginalOnCountDown or not Player or type( Player.OnCountDown ) ~= "function" then return end
	local Original = Player.OnCountDown
	self.OriginalOnCountDown = Original
	Player.OnCountDown = function( PlayerSelf, ... )
		if not self.SuppressCountdownFlash then
			return Original( PlayerSelf, ... )
		end
		self.SuppressCountdownFlash = false
		if not IsWindowFocused() then
			return Original( PlayerSelf, ... )
		end
		local Flash = Client.WindowNeedsAttention
		Client.WindowNeedsAttention = function() end
		local Success, Error = pcall( Original, PlayerSelf, ... )
		Client.WindowNeedsAttention = Flash
		if not Success then
			Log( "ERROR Player.OnCountDown: %s", tostring( Error ) )
		end
	end
end

-- Mouse clicks reach SGUI (poker, match3, chatbox) through NS2's
-- MouseTracker button listeners, which run before GUIManager and Shine's
-- PlayerKeyPress hooks, in an append-only local list. InputHandler calls the
-- global MouseTracker_SendKeyEvent at call time, so wrapping it lets a click
-- on the ready/spectate button (drawn above SGUI) be taken before any
-- listener sees it. Only consumes when HandleKey returns true.
local function InstallMouseClickFilter( self )
	if self.OriginalMouseTrackerSendKeyEvent or type( MouseTracker_SendKeyEvent ) ~= "function" then return end
	local Original = MouseTracker_SendKeyEvent
	self.OriginalMouseTrackerSendKeyEvent = Original
	self.MouseClickFilter = function( Key, Down, ... )
		local GUI = self.GUI
		if Key == InputKey.MouseButton0 and GUI and GUI.HandleKey then
			local Success, Consumed = pcall( GUI.HandleKey, GUI, Key, Down )
			if not Success then
				Log( "ERROR button click handling failed: %s", tostring( Consumed ) )
			elseif Consumed then
				return true
			end
		end
		return Original( Key, Down, ... )
	end
	MouseTracker_SendKeyEvent = self.MouseClickFilter
end

local function RemoveMouseClickFilter( self )
	if self.MouseClickFilter and MouseTracker_SendKeyEvent == self.MouseClickFilter then
		MouseTracker_SendKeyEvent = self.OriginalMouseTrackerSendKeyEvent
	end
	self.MouseClickFilter = nil
	self.OriginalMouseTrackerSendKeyEvent = nil
end

function Plugin:Initialise()
	MNGAReadyCheckFlags = {}
	InstallCountdownFlashFilter( self )
	InstallMouseClickFilter( self )
	self.State = { Phase = PHASE_IDLE }
	-- Load (and precache the texture) now rather than at the first check.
	if not GUIMNGAReadyCheck then
		Script.Load( "lua/"..GUI_SCRIPT..".lua" )
	end
	self:BindCommand( "mnga_ready", function()
		self:RequestReady( "console" )
	end )
	self.Enabled = true
	-- ClientConfirmConnect waits for a keypress, so ask for the current state.
	self:SendNetworkMessage( "RequestReadyCheckSnapshot", {}, true )
	return true
end

function Plugin:RequestReady( Source )
	if not self.State or self.State.Phase == PHASE_IDLE then
		Shared.Message( "[READY] There is no ready check running." )
		return
	end
	self:SendNetworkMessage( "RequestReady", {}, true )
end

function Plugin:RequestSpectate( Source )
	if not self.State or self.State.Phase == PHASE_IDLE then return end
	self:SendNetworkMessage( "RequestSpectate", {}, true )
end

function Plugin:UpdateGUI()
	local Active = self.State.Phase ~= PHASE_IDLE
	if Active and not self.GUI then
		self.GUI = GetGUIManager():CreateGUIScript( GUI_SCRIPT )
		if not self.GUI then Log( "ERROR GUI script could not be created" ) end
	end
	if self.GUI then
		if Active then
			self.GUI:SetState( self.State )
		else
			GetGUIManager():DestroyGUIScript( self.GUI )
			self.GUI = nil
		end
	end
end

function Plugin:ReceiveReadyCheckState( Data )
	self.State = {
		Phase = Data.Phase,
		TimeLeft = Data.TimeLeft,
		TimerRate = self:GetPhaseTimerRate( Data.Phase, Data.ReadyCount, Data.QueueReady, Data.Needed ),
		ReceivedAt = Shared.GetTime(),
		ReadyCount = Data.ReadyCount,
		Needed = Data.Needed,
		NotReady = Data.NotReady,
		QueueReady = Data.QueueReady,
		Eligible = Data.Eligible,
		IsReady = Data.IsReady,
		CanSpectate = Data.CanSpectate,
		VotePending = Data.VotePending
	}
	self:UpdateGUI()
end

function Plugin:ReceiveReadyFlag( Data )
	local SteamID = tonumber( Data.SteamID )
	if not SteamID then return end
	MNGAReadyCheckFlags[ SteamID ] = Data.Ready == true or nil
	ReloadScoreboard()
end

function Plugin:ReceiveReadyFlagsReset()
	MNGAReadyCheckFlags = {}
	ReloadScoreboard()
end

function Plugin:ReceiveReadyCheckAttention()
	Client.WindowNeedsAttention()
	self.SuppressCountdownFlash = true
	self.SuppressCountdownSound = true
	InstallCountdownSoundFilter( self )
	TriggerForcedNotificationSound( "RoundStarting", "ready check" )
end

function Plugin:Cleanup()
	RemoveCountdownSoundFilter( self )
	RemoveMouseClickFilter( self )
	if self.OriginalOnCountDown and Player then
		Player.OnCountDown = self.OriginalOnCountDown
		self.OriginalOnCountDown = nil
	end
	if self.GUI then
		GetGUIManager():DestroyGUIScript( self.GUI )
		self.GUI = nil
	end
	MNGAReadyCheckFlags = {}
	ReloadScoreboard()
	self.BaseClass.Cleanup( self )
end
