--[[
	MNGA Weekly Quests - client.

	All progress lives in config://mngaWeeklyQuests.json. Quest triggers wrap
	other mods' globals/class methods: the original always runs first and our
	tracker runs inside pcall afterwards, so a quest bug can never break the
	wrapped feature. Every target is nil-checked; a missing mod just means that
	quest never progresses. Hooks install lazily from OnLocalPlayerChanged.
]]

local Plugin = ...
local Shine = Shine
local StringFormat = string.format
local pcall = pcall

local kStateFile = "config://mngaWeeklyQuests.json"
local kQuestLogOption = "shimizu/showWeeklyQuests"
local kQuestLogScript = "mnga_weeklyquests/GUIMNGAWeeklyQuests"
local kToastScript = "mnga_weeklyquests/GUIMNGAWeeklyQuestToast"
local kClaimRetryInterval = 60
local kCommanderSaveInterval = 10
-- The MMO-style toast is disabled for now (players would likely find it
-- intrusive). The code is kept so it can be re-enabled later.
local kToastEnabled = false

local Quest = {
	PingOnos = 1,
	Radio = 2,
	Tribute = 3,
	QuickBind = 4,
	Draw = 5,
	EnemyGroup = 6,
	CommanderSpectate = 7,
	Emote = 8
}

local Status = Plugin.ClaimStatus

local function Log( Message, ... )
	Print( "%s", "[weeklyquests] "..StringFormat( Message, ... ) )
end

local function FormatCredits( Amount )
	local Text = tostring( math.floor( Amount ) )
	local Formatted = Text:reverse():gsub( "(%d%d%d)", "%1," ):reverse()
	return ( Formatted:gsub( "^,", "" ) )
end

local function IsGameStarted()
	local GameInfo = GetGameInfoEntity and GetGameInfoEntity()
	return GameInfo ~= nil and GameInfo:GetGameStarted()
end

-- Use the local player entity's team. Client.GetLocalClientTeamNumber() is set
-- by a separate network message that can lag behind LocalPlayerChanged, which
-- made the quest log track the previous team.
local function GetLocalTeam()
	local Player = Client.GetLocalPlayer()
	return Player and Player.GetTeamNumber and Player:GetTeamNumber() or nil
end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

function Plugin:NewState( Week )
	local State = { steamid = tostring( self.SteamID ), week = Week, q = {}, allClaimed = false }
	for i = 1, #self.Quests do
		State.q[ tostring( self.Quests[ i ].Id ) ] = { p = 0, d = false, c = false }
	end
	return State
end

function Plugin:LoadState()
	local Week = self.GetWeekIndex( Shared.GetSystemTime() )
	local State
	if GetFileExists( kStateFile ) then
		local File = io.open( kStateFile, "r" )
		if File then
			local Ok, Decoded = pcall( json.decode, File:read( "*all" ) )
			io.close( File )
			if Ok and type( Decoded ) == "table" then State = Decoded end
		end
	end

	if not State or tostring( State.steamid ) ~= tostring( self.SteamID ) or type( State.q ) ~= "table" then
		State = self:NewState( Week )
	end
	-- Fill in any quests added since the file was written.
	for i = 1, #self.Quests do
		local Key = tostring( self.Quests[ i ].Id )
		if type( State.q[ Key ] ) ~= "table" then State.q[ Key ] = { p = 0, d = false, c = false } end
	end
	State.week = tonumber( State.week ) or Week
	self.State = State
	self:EnsureCurrentWeek()
	self:SaveState()
end

function Plugin:SaveState()
	if not self.State then return end
	local File = io.open( kStateFile, "w+" )
	if not File then
		Log( "failed to open %s for writing", kStateFile )
		return
	end
	File:write( json.encode( self.State, { indent = true } ) )
	io.close( File )
end

function Plugin:GetQuestState( QuestId )
	return self.State and self.State.q[ tostring( QuestId ) ]
end

function Plugin:IsQuestDone( QuestId )
	local QuestState = self:GetQuestState( QuestId )
	return QuestState == nil or QuestState.d
end

function Plugin:AreAllQuestsDone()
	if not self.State then return false end
	for i = 1, #self.Quests do
		if not self.State.q[ tostring( self.Quests[ i ].Id ) ].d then return false end
	end
	return true
end

function Plugin:AreAllQuestsClaimed()
	for i = 1, #self.Quests do
		if not self.State.q[ tostring( self.Quests[ i ].Id ) ].c then return false end
	end
	return true
end

-- Weekly reset is purely clock based: no server round trip needed.
function Plugin:EnsureCurrentWeek()
	if not self.State then return false end
	local Week = self.GetWeekIndex( Shared.GetSystemTime() )
	if self.State.week == Week then return false end

	local OldWeek = self.State.week
	-- Last chance for completions that were never acknowledged; Flask keeps a
	-- short grace window for the previous week. Results are only logged.
	for i = 1, #self.Quests do
		local QuestState = self.State.q[ tostring( self.Quests[ i ].Id ) ]
		if QuestState.d and not QuestState.c then
			self:SendNetworkMessage( "Claim", { QuestId = self.Quests[ i ].Id, Week = OldWeek }, true )
		end
	end

	self.State = self:NewState( Week )
	self.PendingClaims = {}
	self.LastPingTargetId = nil
	self:SaveState()
	self:RefreshQuestLog()
	return true
end

-------------------------------------------------------------------------------
-- Progress
-------------------------------------------------------------------------------

function Plugin:AddProgress( QuestId, Amount, DeferSave )
	if not self.State then return end
	self:EnsureCurrentWeek()
	local QuestState = self:GetQuestState( QuestId )
	local Definition = self.QuestById[ QuestId ]
	if not QuestState or not Definition or QuestState.d then return end

	QuestState.p = math.min( Definition.Goal, ( tonumber( QuestState.p ) or 0 ) + ( Amount or 1 ) )

	if QuestState.p >= Definition.Goal then
		self:CompleteQuest( QuestId )
		return
	end
	if not DeferSave then self:SaveState() end
	self:RefreshQuestLog()
end

function Plugin:CompleteQuest( QuestId )
	local QuestState = self:GetQuestState( QuestId )
	local Definition = self.QuestById[ QuestId ]
	if not QuestState or not Definition or QuestState.d then return end

	QuestState.p = Definition.Goal
	QuestState.d = true
	self:SaveState()

	self:ShowToast( "Quest Complete!", Definition.Title )
	-- One chat line per completion, sent once the claim result is known so the
	-- reward can be appended (see ReceiveClaimResult).
	self.AnnouncePending = self.AnnouncePending or {}
	self.AnnouncePending[ QuestId ] = true
	self:SendClaim( QuestId )
	self:RefreshQuestLog()
end

-------------------------------------------------------------------------------
-- Claims
-------------------------------------------------------------------------------

function Plugin:SendClaim( QuestId )
	if not self.State then return end
	self.PendingClaims = self.PendingClaims or {}
	local Now = Shared.GetTime()
	local SentAt = self.PendingClaims[ QuestId ]
	if SentAt and Now < SentAt + kClaimRetryInterval then return end
	self.PendingClaims[ QuestId ] = Now
	self:SendNetworkMessage( "Claim", { QuestId = QuestId, Week = self.State.week }, true )
end

function Plugin:RetryPendingClaims( Force )
	if not self.State then return end
	local Now = Shared.GetTime()
	if not Force and self.LastClaimRetry and Now < self.LastClaimRetry + kClaimRetryInterval then return end
	self.LastClaimRetry = Now

	for i = 1, #self.Quests do
		local Id = self.Quests[ i ].Id
		local QuestState = self.State.q[ tostring( Id ) ]
		if QuestState.d and not QuestState.c then self:SendClaim( Id ) end
	end
	if not self.State.allClaimed and self:AreAllQuestsClaimed() then
		self:SendClaim( self.AllQuestsId )
	end
end

function Plugin:ReceiveClaimResult( Data )
	if not self.State then return end
	local QuestId = Data.QuestId
	local Definition = self.QuestById[ QuestId ]

	if Data.Week ~= self.State.week then
		if Data.Status == Status.Ok and Definition then
			self:AddChat( StringFormat( "Quest reward (last week): %s - +%s poker credits",
				Definition.Title, FormatCredits( Data.Amount ) ) )
		end
		return
	end

	if self.PendingClaims then self.PendingClaims[ QuestId ] = nil end
	local Announce = self.AnnouncePending and self.AnnouncePending[ QuestId ]
	if Announce then self.AnnouncePending[ QuestId ] = nil end

	if Data.Status == Status.Retry then
		if Announce and Definition then
			self:AddChat( StringFormat( "Quest complete: %s - reward pending, will retry later", Definition.Title ) )
		end
		return
	end

	if QuestId == self.AllQuestsId then
		self.State.allClaimed = true
		self:SaveState()
		if Data.Status == Status.Ok then
			local Text = StringFormat( "+%s poker credits", FormatCredits( Data.Amount ) )
			self:ShowToast( "All Weekly Quests Complete!", Text )
			self:AddChat( "All weekly quests complete! "..Text )
		end
		return
	end

	local QuestState = self:GetQuestState( QuestId )
	if not QuestState then return end
	QuestState.c = true
	self:SaveState()

	if Definition then
		local Prefix = Announce and "Quest complete" or "Quest reward"
		if Data.Status == Status.Ok then
			self:AddChat( StringFormat( "%s: %s - +%s poker credits",
				Prefix, Definition.Title, FormatCredits( Data.Amount ) ) )
		elseif Announce then
			self:AddChat( StringFormat( "Quest complete: %s", Definition.Title ) )
		end
	end

	if not self.State.allClaimed and self:AreAllQuestsClaimed() then
		self:SendClaim( self.AllQuestsId )
	end
end

-------------------------------------------------------------------------------
-- Notifications
-------------------------------------------------------------------------------

function Plugin:AddChat( Text )
	if Shine.AddChatText then
		Shine.AddChatText( 255, 200, 90, "[Weekly Quests] ", 1, 0.92, 0.75, Text )
	end
end

function Plugin:EnsureGUIClasses()
	if not GUIScript then return false end
	if not GUIMNGAWeeklyQuests then Script.Load( "lua/mnga_weeklyquests/GUIMNGAWeeklyQuests.lua" ) end
	if not GUIMNGAWeeklyQuestToast then Script.Load( "lua/mnga_weeklyquests/GUIMNGAWeeklyQuestToast.lua" ) end
	return true
end

function Plugin:ShowToast( Title, Text, Force )
	if not kToastEnabled and not Force then return end
	local Manager = GetGUIManager and GetGUIManager()
	if not Manager or not self:EnsureGUIClasses() then return end
	local Toast = Manager:GetGUIScriptSingle( kToastScript ) or Manager:CreateGUIScriptSingle( kToastScript )
	if not Toast then return end
	Toast:Push( Title, Text )

	-- Destroy the toast once its queue drains so it stops updating per frame.
	if not self:TimerExists( "ToastCleanup" ) then
		self:CreateTimer( "ToastCleanup", 1, -1, function( Timer )
			local Mgr = GetGUIManager and GetGUIManager()
			local Script = Mgr and Mgr:GetGUIScriptSingle( kToastScript )
			if not Script or Script:GetIsFinished() then
				if Script then Mgr:DestroyGUIScriptSingle( kToastScript ) end
				Timer:Destroy()
			end
		end )
	end
end

-------------------------------------------------------------------------------
-- Quest log
-------------------------------------------------------------------------------

local function FormatResetIn( Seconds )
	Seconds = math.max( 0, Seconds )
	local Days = math.floor( Seconds / 86400 )
	local Hours = math.floor( ( Seconds % 86400 ) / 3600 )
	local Minutes = math.floor( ( Seconds % 3600 ) / 60 )
	if Days > 0 then return StringFormat( "Resets in %dd %dh", Days, Hours ) end
	if Hours > 0 then return StringFormat( "Resets in %dh %dm", Hours, Minutes ) end
	return StringFormat( "Resets in %dm", Minutes )
end

function Plugin:GetResetText()
	local Week = self.State and self.State.week or self.GetWeekIndex( Shared.GetSystemTime() )
	return FormatResetIn( self.GetWeekResetTime( Week ) - Shared.GetSystemTime() )
end

function Plugin:BuildQuestRows()
	local Rows = {}
	for i = 1, #self.Quests do
		local Definition = self.Quests[ i ]
		local QuestState = self.State.q[ tostring( Definition.Id ) ]
		local Progress = math.floor( tonumber( QuestState.p ) or 0 )
		local Counter = StringFormat( "%d/%d", Progress, Definition.Goal )
		if Definition.DisplayGoal then
			local Shown = QuestState.d and Definition.DisplayGoal or 0
			Counter = StringFormat( "%d/%d", Shown, Definition.DisplayGoal )
		elseif Definition.Id == Quest.CommanderSpectate then
			Counter = StringFormat( "%ds/%ds", Progress, Definition.Goal )
		end
		Rows[ i ] = { Title = Definition.Title, CounterText = Counter, Done = QuestState.d == true }
	end
	return Rows
end

function Plugin:ShouldShowQuestLog()
	if not self.State or not self.QuestLogVisible then return false end
	return GetLocalTeam() == kTeamReadyRoom and not self:AreAllQuestsDone()
end

function Plugin:GetQuestLog()
	local Manager = GetGUIManager and GetGUIManager()
	return Manager and Manager:GetGUIScriptSingle( kQuestLogScript ) or nil
end

function Plugin:UpdateQuestLogVisibility()
	local Manager = GetGUIManager and GetGUIManager()
	if not Manager then return end
	local QuestLog = self:GetQuestLog()

	if not self:ShouldShowQuestLog() then
		if QuestLog then
			Manager:DestroyGUIScriptSingle( kQuestLogScript )
		end
		return
	end

	if not QuestLog then
		if not self:EnsureGUIClasses() then return end
		QuestLog = Manager:CreateGUIScriptSingle( kQuestLogScript )
		if not QuestLog then return end
		QuestLog.OnSlowUpdate = function( Script )
			local Ok, Err = pcall( self.OnQuestLogSlowUpdate, self, Script )
			if not Ok then Log( "quest log update error: %s", tostring( Err ) ) end
		end
	end
	QuestLog:SetQuests( self:BuildQuestRows(), self:GetResetText() )
end

function Plugin:OnQuestLogSlowUpdate( Script )
	if self:EnsureCurrentWeek() then return end
	Script:SetSubtitle( self:GetResetText() )
end

function Plugin:RefreshQuestLog()
	local QuestLog = self:GetQuestLog()
	if QuestLog and self:ShouldShowQuestLog() then
		QuestLog:SetQuests( self:BuildQuestRows(), self:GetResetText() )
	else
		self:UpdateQuestLogVisibility()
	end
end

-------------------------------------------------------------------------------
-- Quest triggers (all wrappers: original first, tracker in pcall)
-------------------------------------------------------------------------------

local function SafeTrack( Func, ... )
	local Ok, Err = pcall( Func, ... )
	if not Ok then Log( "tracker error: %s", tostring( Err ) ) end
end

-- 1. Ping Onos or Exos: the client-side ping hint path (GUIRequestMenu -> BuildVoiceMessage).
function Plugin:TrackVoiceMessage( VoiceId )
	if self:IsQuestDone( Quest.PingOnos ) then return end
	if not kVoiceId or VoiceId ~= kVoiceId.Ping or not IsGameStarted() then return end
	if not MNGA_ContextPing_PickTarget then return end
	local Player = Client.GetLocalPlayer()
	if not Player then return end
	local Target = MNGA_ContextPing_PickTarget( Player )
	if not Target or not ( Target:isa( "Onos" ) or Target:isa( "Exo" ) ) then return end
	local TargetId = Target:GetId()
	if TargetId == self.LastPingTargetId then return end
	self.LastPingTargetId = TargetId
	self:AddProgress( Quest.PingOnos, 1 )
end

function Plugin:InstallPingHook()
	if self.PingHooked or not BuildVoiceMessage then return end
	local Original = BuildVoiceMessage
	self.OriginalBuildVoiceMessage = Original
	BuildVoiceMessage = function( VoiceId, ... )
		local Result = Original( VoiceId, ... )
		if Plugin.Enabled then SafeTrack( Plugin.TrackVoiceMessage, Plugin, VoiceId ) end
		return Result
	end
	self.PingHooked = true
end

-- 2. Radio: manual radio menu selections only (context pings never use Select).
function Plugin:InstallRadioHook()
	if self.RadioHooked or not GUIRadioCommands or not GUIRadioCommands.Select then return end
	local Original = GUIRadioCommands.Select
	GUIRadioCommands.Select = function( Menu, Index, ... )
		local Child = Menu.visibleChildren and Menu.visibleChildren[ Index ]
		local Result = Original( Menu, Index, ... )
		if Plugin.Enabled and Child and not Child.Children and not Plugin:IsQuestDone( Quest.Radio ) then
			SafeTrack( Plugin.AddProgress, Plugin, Quest.Radio, 1 )
		end
		return Result
	end
	self.RadioHooked = true
end

-- 3. Tribute: match the tribute plugin's broadcast with the local name.
-- The server broadcasts the plain Player:GetName(), but the client's GetName() reads the scoreboard,
-- which carries poker/match3 activity prefixes and SSB aliases. Compare against the plain name.
local kActivityPrefixes = { "<poke> ", "<M3> " }

local function StripActivityPrefixes( Name )
	local Stripped = true
	while Stripped do
		Stripped = false
		for i = 1, #kActivityPrefixes do
			local Prefix = kActivityPrefixes[ i ]
			if Name:sub( 1, #Prefix ) == Prefix then
				Name = Name:sub( #Prefix + 1 )
				Stripped = true
			end
		end
	end
	return Name
end

local function GetLocalPlainName( Player )
	local Name
	local Record = Scoreboard_GetPlayerRecord and Player.GetClientIndex
		and Scoreboard_GetPlayerRecord( Player:GetClientIndex() )
	if Record and type( Record.RealName ) == "string" and Record.RealName ~= "" then
		Name = Record.RealName
	elseif Player.GetName then
		Name = Player:GetName()
	end
	if type( Name ) ~= "string" then return nil end
	return StripActivityPrefixes( Name )
end

function Plugin:TrackChatText( Message )
	if self:IsQuestDone( Quest.Tribute ) or type( Message ) ~= "string" then return end
	if not Message:find( "tribute", 1, true ) then return end
	local Player = Client.GetLocalPlayer()
	local Name = Player and GetLocalPlainName( Player )
	if not Name or Name == "" then return end
	if Message:sub( 1, #Name ) ~= Name then
		-- Tribute lines arrive via MNGA_NotifyNames, which shows this viewer's
		-- SSB alias for themselves if they set one.
		local Alias = SSB_GetPlayerAlias and SSB_GetPlayerAlias( Client.GetSteamId() )
		if not Alias or Message:sub( 1, #Alias ) ~= Alias then return end
		Name = Alias
	end
	local Rest = Message:sub( #Name + 1 )
	if Rest:find( "^ has volunteered as tribute" ) or Rest:find( "^ has cancelled tribute by comming" ) then
		self:AddProgress( Quest.Tribute, 1 )
	end
end

function Plugin:InstallTributeHook()
	if self.TributeHooked or not Shine.AddChatText then return end
	local Original = Shine.AddChatText
	Shine.AddChatText = function( RP, GP, BP, Prefix, R, G, B, Message, ... )
		local Result = Original( RP, GP, BP, Prefix, R, G, B, Message, ... )
		if Plugin.Enabled and not Plugin:IsQuestDone( Quest.Tribute ) then
			SafeTrack( Plugin.TrackChatText, Plugin, Message )
		end
		return Result
	end
	self.TributeHooked = true
end

-- 4. Quick bind: optional listener exposed by the shimizuquickbind mod.
function Plugin:InstallQuickBindHook()
	if self.QuickBindHooked or not ShimizuQuickBind then return end
	if ShimizuQuickBind.OnSequenceBegin then
		Log( "quickbind OnSequenceBegin already taken; quest 4 disabled" )
		self.QuickBindHooked = true
		return
	end
	ShimizuQuickBind.OnSequenceBegin = function( Ability )
		if not Plugin.Enabled or Plugin:IsQuestDone( Quest.QuickBind ) or not IsGameStarted() then return end
		SafeTrack( Plugin.AddProgress, Plugin, Quest.QuickBind, 1 )
	end
	self.QuickBindHooked = true
end

-- 5. Spectator drawing: one "line" per finished stroke with at least 2 points.
function Plugin:InstallDrawingHook()
	if self.DrawingHooked or not GUISpectatorDrawing or not GUISpectatorDrawing.SendKeyEvent then return end
	local Original = GUISpectatorDrawing.SendKeyEvent
	GUISpectatorDrawing.SendKeyEvent = function( Drawing, Key, Down, ... )
		local WasDrawing = Drawing.IsDrawing
		local Result = Original( Drawing, Key, Down, ... )
		if WasDrawing and not Drawing.IsDrawing and Plugin.Enabled
			and not Plugin:IsQuestDone( Quest.Draw ) and ( Drawing.StrokePoints or 0 ) >= 2 then
			SafeTrack( Plugin.AddProgress, Plugin, Quest.Draw, 1 )
		end
		return Result
	end
	self.DrawingHooked = true
end

-- 6. Enemy group: remember the add request, count when the server confirms it.
function Plugin:InstallEnemyGroupHook()
	if self.EnemyGroupHooked then return end
	local Admin = Shine.Plugins and Shine.Plugins.mngaadministration
	if not Admin or not Admin.ReceiveEnemyGroupState or not Admin.SendNetworkMessage then return end

	local OriginalSend = Admin.SendNetworkMessage
	Admin.SendNetworkMessage = function( AdminPlugin, Name, Data, ... )
		local Result = OriginalSend( AdminPlugin, Name, Data, ... )
		if Name == "EnemyGroupAction" and type( Data ) == "table" and Data.Action == 1 then
			Plugin.PendingEnemyAdd = tonumber( Data.TargetSteamID )
		end
		return Result
	end

	local OriginalReceive = Admin.ReceiveEnemyGroupState
	Admin.ReceiveEnemyGroupState = function( AdminPlugin, Data, ... )
		local Result = OriginalReceive( AdminPlugin, Data, ... )
		if Plugin.Enabled and Plugin.PendingEnemyAdd and type( Data ) == "table"
			and Data.IsEnemy == true and tonumber( Data.TargetSteamID ) == Plugin.PendingEnemyAdd then
			Plugin.PendingEnemyAdd = nil
			SafeTrack( Plugin.AddProgress, Plugin, Quest.EnemyGroup, 1 )
		end
		return Result
	end
	self.EnemyGroupHooked = true
end

-- 7. Commander spectating: 1 s timer, only while spectating and quest open.
function Plugin:GetSpectatedCommander()
	local Player = Client.GetLocalPlayer()
	if not Player or not Player:isa( "Spectator" ) then return nil end
	local Id = Entity.invalidId
	if Player.GetSpectatorModeType and kSpectatorMode
		and Player:GetSpectatorModeType() == kSpectatorMode.Overhead then
		Id = Player.followId or Entity.invalidId
	elseif Player.GetFollowingPlayerId then
		Id = Player:GetFollowingPlayerId()
	end
	if not Id or Id == Entity.invalidId then return nil end
	local Target = Shared.GetEntity( Id )
	if Target and Target:isa( "Commander" ) then return Target end
	return nil
end

function Plugin:CommanderSpectateTick()
	-- Drawing GUI class is loaded lazily by mngaadministration while spectating.
	if not self.DrawingHooked then self:InstallDrawingHook() end

	if self:IsQuestDone( Quest.CommanderSpectate ) then return end
	if not self:GetSpectatedCommander() then
		if self.UnsavedCommanderSeconds > 0 then
			self.UnsavedCommanderSeconds = 0
			self:SaveState()
		end
		return
	end

	self.UnsavedCommanderSeconds = self.UnsavedCommanderSeconds + 1
	local Save = self.UnsavedCommanderSeconds >= kCommanderSaveInterval
	if Save then self.UnsavedCommanderSeconds = 0 end
	self:AddProgress( Quest.CommanderSpectate, 1, not Save )
end

function Plugin:UpdateSpectatorTimer()
	local Wanted = GetLocalTeam() == kSpectatorIndex
		and ( not self:IsQuestDone( Quest.CommanderSpectate ) or not self.DrawingHooked )
	local Exists = self:TimerExists( "CommanderSpectate" )
	if Wanted and not Exists then
		self.UnsavedCommanderSeconds = 0
		self:CreateTimer( "CommanderSpectate", 1, -1, function()
			SafeTrack( self.CommanderSpectateTick, self )
		end )
	elseif not Wanted and Exists then
		self:DestroyTimer( "CommanderSpectate" )
		if self.UnsavedCommanderSeconds and self.UnsavedCommanderSeconds > 0 then
			self.UnsavedCommanderSeconds = 0
			self:SaveState()
		end
	end
end

-- 8. Emotes: optional listener exposed by sourceshimizushine (MarineEmote.lua). It fires from a client field
-- watcher when the local marine's emote actually starts, so refused requests (cooldown, no permission) don't count.
function Plugin:InstallEmoteHook()
	if self.EmoteHooked or not MNGAMarineEmote then return end
	if MNGAMarineEmote.OnLocalEmoteStart then
		Log( "emote OnLocalEmoteStart already taken; quest 8 disabled" )
		self.EmoteHooked = true
		return
	end
	MNGAMarineEmote.OnLocalEmoteStart = function( EmoteId )
		if not Plugin.Enabled or Plugin:IsQuestDone( Quest.Emote ) then return end
		SafeTrack( Plugin.AddProgress, Plugin, Quest.Emote, 1 )
	end
	self.EmoteHooked = true
end

function Plugin:InstallHooks()
	self:InstallPingHook()
	self:InstallRadioHook()
	self:InstallTributeHook()
	self:InstallQuickBindHook()
	self:InstallDrawingHook()
	self:InstallEnemyGroupHook()
	self:InstallEmoteHook()
end

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------

function Plugin:Initialise()
	self.PendingClaims = {}
	self.UnsavedCommanderSeconds = 0
	self.QuestLogVisible = Client.GetOptionBoolean( kQuestLogOption, true )
	self.Enabled = true

	-- The first LocalPlayerChanged (joining into the ready room) can fire before
	-- this plugin is enabled. Poll briefly until state and GUI are ready.
	self:CreateTimer( "InitialSync", 1, 30, function( Timer )
		if not Client.GetLocalPlayer() then return end
		SafeTrack( self.HandleLocalPlayerChanged, self )
		if self.State and GUIScript then
			Timer:Destroy()
		end
	end )
	return true
end

function Plugin:OnLocalPlayerChanged( Player )
	SafeTrack( self.HandleLocalPlayerChanged, self, Player )
end

function Plugin:HandleLocalPlayerChanged( Player )
	if not self.State then
		self.SteamID = Client.GetSteamId and Client.GetSteamId() or 0
		if not self.SteamID or self.SteamID == 0 then return end
		self:LoadState()
		self:RetryPendingClaims( true )
	end
	self:EnsureCurrentWeek()
	self:InstallHooks()
	self:UpdateQuestLogVisibility()
	self:UpdateSpectatorTimer()
	if GetLocalTeam() == kTeamReadyRoom then self:RetryPendingClaims() end

	-- One delayed re-check in case the new player's team arrives after the event.
	self:CreateTimer( "RecheckVisibility", 0.5, 1, function()
		SafeTrack( self.UpdateQuestLogVisibility, self )
		SafeTrack( self.UpdateSpectatorTimer, self )
	end )
end

-- Called by the Shimizu QoL checkbox with the widget value (on revert it fires before the option is saved).
function MNGA_WeeklyQuests_SetVisible( Visible )
	if not Plugin.Enabled then return end
	Log( "quest log visible option: %s", tostring( Visible ) )
	Plugin.QuestLogVisible = Visible
	SafeTrack( Plugin.UpdateQuestLogVisibility, Plugin )
end

function Plugin:Cleanup()
	local Manager = GetGUIManager and GetGUIManager()
	if Manager then
		if Manager:GetGUIScriptSingle( kQuestLogScript ) then Manager:DestroyGUIScriptSingle( kQuestLogScript ) end
		if Manager:GetGUIScriptSingle( kToastScript ) then Manager:DestroyGUIScriptSingle( kToastScript ) end
	end
	if self.UnsavedCommanderSeconds and self.UnsavedCommanderSeconds > 0 then self:SaveState() end
	-- Wrappers stay installed but no-op while Plugin.Enabled is false.
	self.BaseClass.Cleanup( self )
	self.Enabled = false
end
