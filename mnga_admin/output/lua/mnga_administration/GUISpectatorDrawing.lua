class "GUISpectatorDrawing" ( GUIScript )

local SLOT_COUNT = 4
-- Map changes destroy the client VM/cache. A one-day lifetime avoids marks
-- silently expiring during unusually long map sessions without per-frame redraw.
local LINE_LIFETIME = 86400
local BUTTON_HEIGHT = 28
local BUTTON_GAP = 4
local BUTTON_WIDTH = 145
local RECEIVE_WIDTH = 125
local BUTTON_Y = 8
local BUTTON_RIGHT_MARGIN = 12
local BACKGROUND_ALPHA = 0.82
local MAX_PENDING_PREDICTIONS = 128
-- Spectator camera-mode changes can clear native debug lines after the GUI has
-- updated. Rebuild shortly afterwards from the local cache, with no server
-- replay, once the new camera has settled.
local CAMERA_MODE_REBUILD_DELAY = 0.3
-- Shared.DebugLine has no width parameter. Additional parallel lines emulate
-- thickness without increasing the number or size of network messages.
local THICK_LINE_SPACING = 0.012

local SlotColours = {
	Color( 1, 1, 1, 1 ),
	Color( 0.32, 0.62, 1, 1 ),
	Color( 0.42, 1, 0.5, 1 ),
	Color( 1, 0.72, 0.3, 1 )
}

local function GetPlugin()
	return Shine and Shine.Plugins and Shine.Plugins.mngaadministration
end

local function GetLocalPlayer()
	return Client.GetLocalPlayer and Client.GetLocalPlayer()
end

local function IsLocalSpectator()
	-- In first-person spectate, the local player entity can temporarily expose
	-- the followed player's playing-team number. The local client's assigned
	-- team remains the authoritative spectator-session identity throughout the
	-- camera transition, so using it prevents destruction of the drawing cache.
	if Client.GetLocalClientTeamNumber then
		return Client.GetLocalClientTeamNumber() == kSpectatorIndex
	end
	local Player = GetLocalPlayer()
	return Player and Player:GetTeamNumber() == kSpectatorIndex
end

local function GetLocalUserId()
	return Client.GetSteamId and Client.GetSteamId() or 0
end

local function SetTextItemFont( Item )
	Item:SetFontName( Fonts.kAgencyFB_Small )
	Item:SetTextAlignmentX( GUIItem.Align_Center )
	Item:SetTextAlignmentY( GUIItem.Align_Center )
	Item:SetColor( Color( 1, 1, 1, 1 ) )
	GUIMakeFontScale( Item )
end

function GUISpectatorDrawing:Initialize()
	self.Enabled = false
	self.SampleRateHz = 12
	self.LocalSampleRateHz = 24
	self.StrokeThickness = 3
	self.MaxPointsPerStroke = 64
	self.MaximumTraceDistance = 1000
	self.DrawingPlaneHeight = 0
	self.ReceiveEnabled = false
	self.Synchronizing = false
	self.InsightVisible = true
	self.LocalOwnerSlot = nil
	self.IsDrawing = false
	self.LastLocalWorldPoint = nil
	self.LastNetworkWorldPoint = nil
	self.LatestWorldPoint = nil
	self.LastLocalSampleTime = 0
	self.LastNetworkSampleTime = 0
	self.ClientSequence = 0
	self.Stroke = 0
	self.StrokePoints = 0
	self.Slots = {}
	self.Segments = {}
	self.SeenSegments = {}
	self.ChannelEpochs = {}
	self.Buttons = {}
	self.PredictedSegments = {}
	self.PredictionOrder = {}
	self.LastSpectatorMode = nil
	self.PendingCameraModeRebuildTime = nil

	for Slot = 1, SLOT_COUNT do
		self.Slots[ Slot ] = { OwnerId = 0, OwnerName = "" }
		self.Segments[ Slot ] = {}
		self.SeenSegments[ Slot ] = {}
		self.ChannelEpochs[ Slot ] = 0
	end

	self:CreateControls()
	self:UpdateControlState()
	Print( "[spectator_draw] GUISpectatorDrawing initialised." )
end

function GUISpectatorDrawing:CreateButton( Width, Colour )
	local Background = GUIManager:CreateGraphicItem()
	Background:SetSize( Vector( Width, BUTTON_HEIGHT, 0 ) )
	Background:SetColor( Color( Colour.r * 0.38, Colour.g * 0.38, Colour.b * 0.38, BACKGROUND_ALPHA ) )
	Background:SetLayer( kGUILayerPlayerHUDForeground4 )

	local Text = GUIManager:CreateTextItem()
	Text:SetSize( Vector( Width, BUTTON_HEIGHT, 0 ) )
	Text:SetPosition( Vector( Width * 0.5, BUTTON_HEIGHT * 0.5, 0 ) )
	SetTextItemFont( Text )
	Background:AddChild( Text )

	return { Background = Background, Text = Text, Width = Width, Colour = Colour }
end

function GUISpectatorDrawing:CreateControls()
	local ScreenWidth = Client.GetScreenWidth()
	local AvailableWidth = ScreenWidth - BUTTON_RIGHT_MARGIN - RECEIVE_WIDTH - BUTTON_GAP * SLOT_COUNT
	local SlotButtonWidth = math.max( 90, math.min( BUTTON_WIDTH, AvailableWidth / SLOT_COUNT ) )
	local TotalWidth = SlotButtonWidth * SLOT_COUNT + RECEIVE_WIDTH + BUTTON_GAP * SLOT_COUNT
	local X = ScreenWidth - BUTTON_RIGHT_MARGIN - TotalWidth
	for Slot = 1, SLOT_COUNT do
		local Button = self:CreateButton( SlotButtonWidth, SlotColours[ Slot ] )
		Button.Background:SetPosition( Vector( X, BUTTON_Y, 0 ) )
		Button.Slot = Slot
		self.Buttons[ #self.Buttons + 1 ] = Button
		X = X + SlotButtonWidth + BUTTON_GAP
	end

	local Receive = self:CreateButton( RECEIVE_WIDTH, Color( 0.45, 0.45, 0.45, 1 ) )
	Receive.Background:SetPosition( Vector( X, BUTTON_Y, 0 ) )
	Receive.IsReceive = true
	self.Buttons[ #self.Buttons + 1 ] = Receive
	self.ReceiveButton = Receive
end

function GUISpectatorDrawing:DestroyControls()
	for i = 1, #self.Buttons do
		GUI.DestroyItem( self.Buttons[ i ].Background )
	end
	self.Buttons = {}
	self.ReceiveButton = nil
end

function GUISpectatorDrawing:Uninitialize()
	self:ClearAllDrawing()
	self:DestroyControls()
	Print( "[spectator_draw] GUISpectatorDrawing uninitialised." )
end

function GUISpectatorDrawing:OnResolutionChanged()
	self:DestroyControls()
	self:CreateControls()
	self:UpdateControlState()
end

function GUISpectatorDrawing:SetInsightVisible( Visible )
	if self.InsightVisible == Visible then return end
	self.InsightVisible = Visible
	self:UpdateControlState()
	if Visible and self.ReceiveEnabled and IsLocalSpectator() then
		self:RebuildWorldLines()
	else
		Shared.ClearDebugLines()
	end
end

function GUISpectatorDrawing:ApplyServerConfig( Data )
	local PreviousThickness = self.StrokeThickness
	self.Enabled = Data.Enabled
	self.SampleRateHz = Data.SampleRateHz
	self.LocalSampleRateHz = Data.LocalSampleRateHz
	self.StrokeThickness = Data.StrokeThickness
	self.MaxPointsPerStroke = Data.MaxPointsPerStroke
	self.MaximumTraceDistance = Data.MaximumTraceDistance
	self.DrawingPlaneHeight = Data.DrawingPlaneHeight
	if not Data.Enabled then
		self.ReceiveEnabled = false
		self.Synchronizing = false
		self.LocalOwnerSlot = nil
		self:ClearDrawingCache()
	end
	if Data.Enabled and PreviousThickness ~= self.StrokeThickness and self:GetSegmentCount() > 0 then
		self:RebuildWorldLines()
	end
	self:UpdateControlState()
	Print( "%s", string.format( "[spectator_draw] config received enabled=%s networkSampleRate=%d localSampleRate=%d strokeThickness=%d maxPoints=%d traceDistance=%d planeY=%d",
		tostring( self.Enabled ), self.SampleRateHz, self.LocalSampleRateHz, self.StrokeThickness,
		self.MaxPointsPerStroke, self.MaximumTraceDistance, self.DrawingPlaneHeight ) )
end

function GUISpectatorDrawing:ApplySlotState( Data )
	local PreviousLocalSlot = self.LocalOwnerSlot
	local Slot = self.Slots[ Data.Slot ]
	Slot.OwnerId = Data.OwnerId
	Slot.OwnerName = Data.OwnerName
	self.LocalOwnerSlot = nil
	local LocalId = GetLocalUserId()
	for SlotIndex = 1, SLOT_COUNT do
		if self.Slots[ SlotIndex ].OwnerId ~= 0 and self.Slots[ SlotIndex ].OwnerId == LocalId then
			self.LocalOwnerSlot = SlotIndex
			-- The server makes ownership imply Receive. Reflect that immediately
			-- so an early live echo cannot be discarded before the reliable
			-- receive-state acknowledgement arrives.
			self.ReceiveEnabled = true
			break
		end
	end
	if PreviousLocalSlot ~= self.LocalOwnerSlot then
		self.IsDrawing = false
		self:ResetSamplingState()
	end
	self:UpdateControlState()
end

function GUISpectatorDrawing:ApplyReceiveState( Data )
	local WasEnabled = self.ReceiveEnabled
	self.ReceiveEnabled = Data.Enabled
	self.Synchronizing = Data.Synchronizing
	if WasEnabled and not Data.Enabled then
		self:ClearAllDrawing()
	elseif not WasEnabled and Data.Enabled and not Data.Synchronizing then
		-- A fully cached resume has no replay queue. SnapshotEnd arrives before
		-- this acknowledgement, so rebuild once Receive becomes active.
		self:RebuildWorldLines()
	end
	self:UpdateControlState()
end

function GUISpectatorDrawing:BeginSnapshot( SegmentCount )
	self.Synchronizing = SegmentCount > 0
	-- Retain authoritative cache across Receive toggles. The following channel
	-- manifests prune stale epochs/generations before missing batches replay.
	self:ClearAllDrawing()
	self:UpdateControlState()
end

function GUISpectatorDrawing:ApplySnapshotChannel( Data )
	local ValidGenerations = {
		[ Data.Generation1 ] = Data.Generation1 ~= 0,
		[ Data.Generation2 ] = Data.Generation2 ~= 0,
		[ Data.Generation3 ] = Data.Generation3 ~= 0
	}
	local Kept = {}
	local Seen = {}
	for i = 1, #self.Segments[ Data.Slot ] do
		local Segment = self.Segments[ Data.Slot ][ i ]
		if Segment.Epoch == Data.Epoch and ValidGenerations[ Segment.Generation ] then
			Kept[ #Kept + 1 ] = Segment
			Seen[ self:GetSegmentKey( Segment ) ] = true
		end
	end
	self.ChannelEpochs[ Data.Slot ] = Data.Epoch
	self.Segments[ Data.Slot ] = Kept
	self.SeenSegments[ Data.Slot ] = Seen
end

function GUISpectatorDrawing:EndSnapshot()
	self.Synchronizing = false
	self:RebuildWorldLines()
	self:UpdateControlState()
end

function GUISpectatorDrawing:GetSegmentKey( Data )
	return string.format( "%d:%d:%d", Data.Epoch, Data.Generation, Data.Sequence )
end

function GUISpectatorDrawing:DrawWorldSegment( Segment )
	if not self.ReceiveEnabled or not self.InsightVisible or not IsLocalSpectator() then return end
	local Colour = SlotColours[ Segment.Slot ]
	Shared.DebugColor( Colour.r, Colour.g, Colour.b, Colour.a )

	local Difference = Segment.EndPoint - Segment.StartPoint
	local Length = Difference:GetLength()
	if Length <= 0 or self.StrokeThickness <= 1 then
		Shared.DebugLine( Segment.StartPoint, Segment.EndPoint, LINE_LIFETIME )
		return
	end

	Difference:Scale( 1 / Length )
	local Reference = math.abs( Difference.y ) < 0.9 and Vector( 0, 1, 0 ) or Vector( 1, 0, 0 )
	local Side = Difference:CrossProduct( Reference )
	Side:Normalize()
	local Centre = ( self.StrokeThickness + 1 ) * 0.5
	for LineIndex = 1, self.StrokeThickness do
		local Offset = Side * ( ( LineIndex - Centre ) * THICK_LINE_SPACING )
		Shared.DebugLine( Segment.StartPoint + Offset, Segment.EndPoint + Offset, LINE_LIFETIME )
	end
end

function GUISpectatorDrawing:GetPredictionKey( Slot, ClientSequence )
	return string.format( "%d:%d", Slot, ClientSequence )
end

function GUISpectatorDrawing:AddPredictedSegment( Segment, DrawImmediately )
	local Key = self:GetPredictionKey( Segment.Slot, Segment.ClientSequence )
	self.PredictedSegments[ Key ] = Segment
	self.PredictionOrder[ #self.PredictionOrder + 1 ] = Key
	if #self.PredictionOrder > MAX_PENDING_PREDICTIONS then
		local OldestKey = table.remove( self.PredictionOrder, 1 )
		self.PredictedSegments[ OldestKey ] = nil
	end
	if DrawImmediately ~= false then
		self:DrawWorldSegment( Segment )
	end
end

function GUISpectatorDrawing:ConsumePredictedSegment( Segment )
	local Key = self:GetPredictionKey( Segment.Slot, Segment.ClientSequence )
	local Predicted = self.PredictedSegments[ Key ]
	if not Predicted then return false end

	-- Slot/client sequence identifies the normal echo. Comparing endpoints also
	-- prevents a stale dropped prediction from matching a later slot owner.
	if ( Predicted.StartPoint - Segment.StartPoint ):GetLength() > 0.02
		or ( Predicted.EndPoint - Segment.EndPoint ):GetLength() > 0.02 then
		return false
	end
	self.PredictedSegments[ Key ] = nil
	return true
end

function GUISpectatorDrawing:ClearPredictedSegments()
	self.PredictedSegments = {}
	self.PredictionOrder = {}
end

function GUISpectatorDrawing:AddAuthoritativeSegment( Data )
	if not self.ReceiveEnabled then return end
	if Data.Epoch < self.ChannelEpochs[ Data.Slot ] then return end
	if Data.Epoch > self.ChannelEpochs[ Data.Slot ] then
		local HadCachedSegments = #self.Segments[ Data.Slot ] > 0
		self.ChannelEpochs[ Data.Slot ] = Data.Epoch
		self.Segments[ Data.Slot ] = {}
		self.SeenSegments[ Data.Slot ] = {}
		-- The first live segment commonly advances a fresh client's channel from
		-- epoch zero. Avoid rebuilding an empty cache there, as that would erase
		-- the caster's finer local preview just before echo reconciliation.
		if HadCachedSegments then
			self:RebuildWorldLines()
		end
	end

	local Key = self:GetSegmentKey( Data )
	if self.SeenSegments[ Data.Slot ][ Key ] then return end
	self.SeenSegments[ Data.Slot ][ Key ] = true
	self.Segments[ Data.Slot ][ #self.Segments[ Data.Slot ] + 1 ] = Data
	if not self:ConsumePredictedSegment( Data ) and not self.Synchronizing then
		self:DrawWorldSegment( Data )
	end
end

function GUISpectatorDrawing:SendResumeState()
	local Plugin = GetPlugin()
	for Slot = 1, SLOT_COUNT do
		local Batches = {}
		for i = 1, #self.Segments[ Slot ] do
			local Segment = self.Segments[ Slot ][ i ]
			local Batch = Batches[ Segment.Generation ]
			if not Batch then
				Batch = { Count = 0, LastSequence = 0 }
				Batches[ Segment.Generation ] = Batch
			end
			Batch.Count = Batch.Count + 1
			Batch.LastSequence = math.max( Batch.LastSequence, Segment.Sequence )
		end
		for Generation, Batch in pairs( Batches ) do
			Plugin:SendNetworkMessage( "SpecDrawResumeBatch", {
				Slot = Slot,
				Epoch = self.ChannelEpochs[ Slot ],
				Generation = Generation,
				SegmentCount = Batch.Count,
				LastSequence = Batch.LastSequence
			}, true )
		end
	end
end

function GUISpectatorDrawing:DropBatch( Data )
	if Data.Epoch < self.ChannelEpochs[ Data.Slot ] then return end
	local Kept = {}
	local Seen = {}
	local Removed = 0
	for i = 1, #self.Segments[ Data.Slot ] do
		local Segment = self.Segments[ Data.Slot ][ i ]
		if Segment.Epoch == Data.Epoch and Segment.Generation == Data.Generation then
			Removed = Removed + 1
		else
			Kept[ #Kept + 1 ] = Segment
			Seen[ self:GetSegmentKey( Segment ) ] = true
		end
	end
	self.Segments[ Data.Slot ] = Kept
	self.SeenSegments[ Data.Slot ] = Seen
	self:RebuildWorldLines()
	Print( "%s", string.format( "[spectator_draw] batch removed slot=%d generation=%d segments=%d",
		Data.Slot, Data.Generation, Removed ) )
end

function GUISpectatorDrawing:ClearChannel( Data )
	if Data.Epoch < self.ChannelEpochs[ Data.Slot ] then return end
	self.ChannelEpochs[ Data.Slot ] = Data.Epoch
	self.Segments[ Data.Slot ] = {}
	self.SeenSegments[ Data.Slot ] = {}
	self:RebuildWorldLines()
	Print( "%s", string.format( "[spectator_draw] channel cleared slot=%d epoch=%d", Data.Slot, Data.Epoch ) )
end

function GUISpectatorDrawing:GetSegmentCount()
	local Count = 0
	for Slot = 1, SLOT_COUNT do Count = Count + #self.Segments[ Slot ] end
	return Count
end

function GUISpectatorDrawing:ClearAllDrawing()
	self:ClearPredictedSegments()
	Shared.ClearDebugLines()
end

function GUISpectatorDrawing:ClearDrawingCache()
	for Slot = 1, SLOT_COUNT do
		self.Segments[ Slot ] = {}
		self.SeenSegments[ Slot ] = {}
		self.ChannelEpochs[ Slot ] = 0
	end
	self:ClearAllDrawing()
	Print( "[spectator_draw] local shared drawing cache cleared." )
end

function GUISpectatorDrawing:RebuildWorldLines()
	-- A rebuild removes unacknowledged predicted primitives. Their eventual
	-- authoritative echoes therefore need to render normally again.
	self:ClearPredictedSegments()
	Shared.ClearDebugLines()
	if not self.ReceiveEnabled or not self.InsightVisible or not IsLocalSpectator() then return end
	for Slot = 1, SLOT_COUNT do
		for i = 1, #self.Segments[ Slot ] do
			self:DrawWorldSegment( self.Segments[ Slot ][ i ] )
		end
	end
end

function GUISpectatorDrawing:GetControlsVisible()
	return self.Enabled and self.InsightVisible and IsLocalSpectator()
end

function GUISpectatorDrawing:UpdateControlState()
	local Visible = self:GetControlsVisible()
	local LocalId = GetLocalUserId()
	for Slot = 1, SLOT_COUNT do
		local Button = self.Buttons[ Slot ]
		if Button then
			Button.Background:SetIsVisible( Visible )
			local State = self.Slots[ Slot ]
			local Label = State.OwnerId == 0 and string.format( "%d: available", Slot ) or State.OwnerName
			if State.OwnerId == LocalId and State.OwnerId ~= 0 then Label = Label .. " [ON]" end
			Button.Text:SetText( Label )
			local Colour = Button.Colour
			local Brightness = State.OwnerId == 0 and 0.28 or ( State.OwnerId == LocalId and 0.72 or 0.48 )
			Button.Background:SetColor( Color( Colour.r * Brightness, Colour.g * Brightness,
				Colour.b * Brightness, BACKGROUND_ALPHA ) )
		end
	end
	if self.ReceiveButton then
		self.ReceiveButton.Background:SetIsVisible( Visible )
		local Label = self.Synchronizing and "Receive: syncing" or
			( self.ReceiveEnabled and "Receive: ON" or "Receive: off" )
		self.ReceiveButton.Text:SetText( Label )
		self.ReceiveButton.Background:SetColor( self.ReceiveEnabled and Color( 0.18, 0.55, 0.58, BACKGROUND_ALPHA )
			or Color( 0.18, 0.18, 0.18, BACKGROUND_ALPHA ) )
	end
end

function GUISpectatorDrawing:HandleButtonClick()
	if not self:GetControlsVisible() then return false end
	local MouseX, MouseY = Client.GetCursorPosScreen()
	for Slot = 1, SLOT_COUNT do
		local Button = self.Buttons[ Slot ]
		if GUIItemContainsPoint( Button.Background, MouseX, MouseY ) then
			local State = self.Slots[ Slot ]
			local IsOwner = State.OwnerId ~= 0 and State.OwnerId == GetLocalUserId()
			if State.OwnerId == 0 or IsOwner then
				GetPlugin():SendNetworkMessage( "SpecDrawRequestSlot", {
					Slot = Slot,
					Claim = not IsOwner
				}, true )
			end
			return true
		end
	end
	if GUIItemContainsPoint( self.ReceiveButton.Background, MouseX, MouseY ) then
		if not self.LocalOwnerSlot then
			if not self.ReceiveEnabled then self:SendResumeState() end
			GetPlugin():SendNetworkMessage( "SpecDrawRequestReceive", {
				Enabled = not self.ReceiveEnabled
			}, true )
		end
		return true
	end
	return false
end

function GUISpectatorDrawing:SendKeyEvent( Key, Down )
	if Key == InputKey.MouseButton0 and Down and self:HandleButtonClick() then return true end
	if not self:GetControlsVisible() then
		self.IsDrawing = false
		self:ResetSamplingState()
		return false
	end

	if Down and GetIsBinding( Key, "Reload" ) and self.LocalOwnerSlot then
		GetPlugin():SendNetworkMessage( "SpecDrawRequestClear", { Slot = self.LocalOwnerSlot }, true )
		Print( "%s", string.format( "[spectator_draw] clear requested slot=%d", self.LocalOwnerSlot ) )
		return true
	end

	if GetIsBinding( Key, "SecondaryAttack" ) then
		if Down and self.LocalOwnerSlot then
			self.IsDrawing = true
			self:ResetSamplingState()
			self.Stroke = ( self.Stroke + 1 ) % 65536
			self.StrokePoints = 0
			return true
		end
		if self.IsDrawing and self.LocalOwnerSlot then
			-- Preserve the final locally sampled point for short strokes that end
			-- between regular network ticks.
			self:SubmitLatestNetworkSegment()
		end
		self.IsDrawing = false
		self:ResetSamplingState()
		return self.LocalOwnerSlot ~= nil
	end
	return false
end

function GUISpectatorDrawing:ResetSamplingState()
	self.LastLocalWorldPoint = nil
	self.LastNetworkWorldPoint = nil
	self.LatestWorldPoint = nil
	self.LastLocalSampleTime = 0
	self.LastNetworkSampleTime = 0
end

function GUISpectatorDrawing:TraceCursorToWorld()
	local Player = GetLocalPlayer()
	if not Player then return nil end
	local X, Y = Client.GetCursorPosScreen()
	local Direction = Client.CreatePickingRayXY( X, Y )
	local StartPoint = Player:GetEyePos()
	-- Flat drawing: NS2's Y axis is vertical. Intersect the cursor
	-- ray directly with one horizontal world plane instead of tracing geometry;
	-- this prevents walls and floors from bending a stroke across their surfaces.
	if math.abs( Direction.y ) < 0.0001 then return nil end
	local Distance = ( self.DrawingPlaneHeight - StartPoint.y ) / Direction.y
	if Distance < 0 or Distance > self.MaximumTraceDistance then return nil end
	return StartPoint + Direction * Distance
end

function GUISpectatorDrawing:SampleLocalDrawing()
	local Point = self:TraceCursorToWorld()
	if not Point then
		self.LastLocalWorldPoint = nil
		self.LastNetworkWorldPoint = nil
		self.LatestWorldPoint = nil
		return
	end
	if not self.LastLocalWorldPoint then
		self.LastLocalWorldPoint = Point
		self.LastNetworkWorldPoint = Point
		self.LatestWorldPoint = Point
		self.StrokePoints = 1
		return
	end
	if Point == self.LastLocalWorldPoint then return end

	-- This is a local-only preview segment. It is deliberately not retained in
	-- authoritative history; the lower-rate network chord covers the same path
	-- for other receivers and after any local cache rebuild.
	self:DrawWorldSegment( {
		Slot = self.LocalOwnerSlot,
		StartPoint = self.LastLocalWorldPoint,
		EndPoint = Point
	} )
	self.LastLocalWorldPoint = Point
	self.LatestWorldPoint = Point
end

function GUISpectatorDrawing:SubmitLatestNetworkSegment()
	if not self.LastNetworkWorldPoint or not self.LatestWorldPoint
		or self.LatestWorldPoint == self.LastNetworkWorldPoint then return end

	if self.StrokePoints >= self.MaxPointsPerStroke then
		self.Stroke = ( self.Stroke + 1 ) % 65536
		self.StrokePoints = 1
	end
	self.ClientSequence = ( self.ClientSequence + 1 ) % 2147483647
	local Segment = {
		Slot = self.LocalOwnerSlot,
		Stroke = self.Stroke,
		ClientSequence = self.ClientSequence,
		StartPoint = self.LastNetworkWorldPoint,
		EndPoint = self.LatestWorldPoint
	}
	-- The high-rate local preview already covers this chord. Track the submit so
	-- its authoritative echo is cached without drawing a duplicate over it.
	self:AddPredictedSegment( Segment, false )
	GetPlugin():SendNetworkMessage( "SpecDrawSubmitSegment", Segment, false )
	self.LastNetworkWorldPoint = self.LatestWorldPoint
	self.StrokePoints = self.StrokePoints + 1
end

function GUISpectatorDrawing:Update()
	local Spectator = IsLocalSpectator()
	if self.WasSpectator and not Spectator then
		self.IsDrawing = false
		self:ResetSamplingState()
		self.ReceiveEnabled = false
		self.LocalOwnerSlot = nil
		self:ClearDrawingCache()
		self:UpdateControlState()
		Print( "[spectator_draw] local player left spectator; local drawing state cleared." )
	elseif self.WasSpectator ~= Spectator then
		self:UpdateControlState()
		if Spectator then GetPlugin():SendNetworkMessage( "SpecDrawRequestState", {}, true ) end
	end
	self.WasSpectator = Spectator

	local Player = GetLocalPlayer()
	local SpectatorMode = Spectator and Player.GetSpectatorModeType
		and Player:GetSpectatorModeType() or nil
	if SpectatorMode ~= self.LastSpectatorMode then
		if self.LastSpectatorMode ~= nil and SpectatorMode ~= nil then
			self.PendingCameraModeRebuildTime = Shared.GetTime() + CAMERA_MODE_REBUILD_DELAY
		end
		self.LastSpectatorMode = SpectatorMode
	end

	if self.PendingCameraModeRebuildTime
		and Shared.GetTime() >= self.PendingCameraModeRebuildTime then
		self.PendingCameraModeRebuildTime = nil
		self:RebuildWorldLines()
	end

	if not self.IsDrawing or not self.LocalOwnerSlot then return end
	local Now = Shared.GetTime()
	if Now - self.LastLocalSampleTime >= 1 / self.LocalSampleRateHz then
		self.LastLocalSampleTime = Now
		self:SampleLocalDrawing()
	end
	if Now - self.LastNetworkSampleTime >= 1 / self.SampleRateHz then
		self.LastNetworkSampleTime = Now
		self:SubmitLatestNetworkSegment()
	end
end
