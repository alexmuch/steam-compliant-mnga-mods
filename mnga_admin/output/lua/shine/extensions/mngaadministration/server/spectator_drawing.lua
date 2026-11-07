local Plugin = ...
local Shine = Shine
local StringFormat = string.format
local Min = math.min
local Max = math.max
local Floor = math.floor

local THINK_HOOK = "MNGAAdministrationSpectatorDrawingReplay"
local IDLE_TIMER = "MNGAAdministrationSpectatorDrawingIdle"
local SLOT_COUNT = 4
local HISTORY_BATCH_COUNT = 3
local MAX_NETWORK_SEGMENTS = 2400

local function Clamp( Value, Minimum, Maximum )
	Value = tonumber( Value ) or Minimum
	return Min( Maximum, Max( Minimum, Value ) )
end

local function GetPlayer( Client )
	return Client and Client:GetControllingPlayer()
end

local function IsSpectator( Client )
	local Player = GetPlayer( Client )
	return Player and Player:GetTeamNumber() == kSpectatorIndex
end

local function GetName( Client )
	local Player = GetPlayer( Client )
	return Player and Player:GetName() or "<unknown>"
end

local function IsFiniteNumber( Value )
	return type( Value ) == "number" and Value == Value
		and Value > -math.huge and Value < math.huge
end

local function IsValidVector( Value )
	return Value and IsFiniteNumber( Value.x ) and IsFiniteNumber( Value.y )
		and IsFiniteNumber( Value.z ) and math.abs( Value.x ) < 10000
		and math.abs( Value.y ) < 10000 and math.abs( Value.z ) < 10000
end

function Plugin:SpecDrawLog( Message, ... )
	local Config = self.SpectatorDrawingConfig
	if not Config or not Config.Debug then return end
	Print( "%s", StringFormat( "[spectator_draw] " .. Message, ... ) )
end

function Plugin:GetSpectatorDrawingClients()
	local Result = {}
	local Clients = Shine.GetAllClients()
	for i = 1, #Clients do
		local Client = Clients[ i ]
		if Client and not Client:GetIsVirtual() and IsSpectator( Client ) then
			Result[ #Result + 1 ] = Client
		end
	end
	return Result
end

function Plugin:AddSpectatorDrawingReceiver( Client )
	if self.SpectatorDrawingReceivers[ Client ] then return false end

	local ReceiverList = self.SpectatorDrawingReceiverList
	self.SpectatorDrawingReceivers[ Client ] = true
	ReceiverList[ #ReceiverList + 1 ] = Client
	self.SpectatorDrawingReceiverIndices[ Client ] = #ReceiverList
	self:SpecDrawLog( "receiver added id=%s receivers=%d", Client:GetUserId(), #ReceiverList )
	return true
end

function Plugin:RemoveSpectatorDrawingReceiver( Client, Reason )
	if not self.SpectatorDrawingReceivers[ Client ] then
		self.SpectatorDrawingReplayQueues[ Client ] = nil
		self:UpdateSpectatorDrawingReplayHook()
		return false
	end

	self.SpectatorDrawingReceivers[ Client ] = nil
	self.SpectatorDrawingReplayQueues[ Client ] = nil
	local ReceiverList = self.SpectatorDrawingReceiverList
	local ReceiverIndices = self.SpectatorDrawingReceiverIndices
	local Index = ReceiverIndices[ Client ]
	if not Index then
		self:SpecDrawLog( "receiver cache repaired after missing index reason=%s", tostring( Reason or "unknown" ) )
		self:UpdateSpectatorDrawingReplayHook()
		return true
	end
	local LastIndex = #ReceiverList
	local LastClient = ReceiverList[ LastIndex ]
	if Index and Index ~= LastIndex then
		ReceiverList[ Index ] = LastClient
		ReceiverIndices[ LastClient ] = Index
	end
	ReceiverList[ LastIndex ] = nil
	ReceiverIndices[ Client ] = nil
	local UserID = Client and Client.GetUserId and Client:GetUserId() or "invalid"
	self:SpecDrawLog( "receiver removed id=%s reason=%s receivers=%d", tostring( UserID ),
		tostring( Reason or "unknown" ), #ReceiverList )
	self:UpdateSpectatorDrawingReplayHook()
	return true
end

function Plugin:GetSpectatorDrawingReceiverList()
	return self.SpectatorDrawingReceiverList
end

function Plugin:PruneSpectatorDrawingReceivers()
	local ReceiverList = self.SpectatorDrawingReceiverList
	for Index = #ReceiverList, 1, -1 do
		local Client = ReceiverList[ Index ]
		if not Shine:IsValidClient( Client ) or not IsSpectator( Client ) then
			self:RemoveSpectatorDrawingReceiver( Client, "periodic validation" )
		end
	end
end

function Plugin:UpdateSpectatorDrawingReplayHook()
	local ShouldRun = next( self.SpectatorDrawingReplayQueues ) ~= nil
	if ShouldRun == self.SpectatorDrawingReplayHookActive then return end

	self.SpectatorDrawingReplayHookActive = ShouldRun
	Shine.Hook.Remove( "Think", THINK_HOOK )
	if ShouldRun then
		Shine.Hook.Add( "Think", THINK_HOOK, function() self:ProcessSpectatorDrawingReplay() end )
		Print( "[spectator_draw] replay scheduler activated for queued history." )
	else
		Print( "[spectator_draw] replay scheduler stopped; no history queues remain." )
	end
end

function Plugin:SendSpectatorDrawingConfig( Client )
	local Config = self.SpectatorDrawingConfig
	self:SendNetworkMessage( Client, "SpecDrawConfig", {
		Enabled = Config.Enabled,
		SampleRateHz = Config.SampleRateHz,
		LocalSampleRateHz = Config.LocalSampleRateHz,
		StrokeThickness = Config.StrokeThickness,
		MaxPointsPerStroke = Config.MaxPointsPerStroke,
		MaximumTraceDistance = Config.MaximumTraceDistance,
		DrawingPlaneHeight = self.SpectatorDrawingResolvedPlaneHeight
	}, true )
end

function Plugin:BroadcastSpectatorDrawingSlot( SlotIndex, Target )
	local Slot = self.SpectatorDrawingSlots[ SlotIndex ]
	local Owner = Slot.Owner
	self:SendNetworkMessage( Target or self:GetSpectatorDrawingClients(), "SpecDrawSlotState", {
		Slot = SlotIndex,
		OwnerId = Owner and Owner:GetUserId() or 0,
		OwnerName = Owner and string.sub( GetName( Owner ), 1, 32 ) or ""
	}, true )
end

function Plugin:SendSpectatorDrawingState( Client )
	if not Client or not IsSpectator( Client ) then return end
	self:SendSpectatorDrawingConfig( Client )
	for Slot = 1, SLOT_COUNT do
		self:BroadcastSpectatorDrawingSlot( Slot, Client )
	end
	self:SendNetworkMessage( Client, "SpecDrawReceiveState", {
		Enabled = self.SpectatorDrawingReceivers[ Client ] == true,
		Synchronizing = self.SpectatorDrawingReplayQueues[ Client ] ~= nil
	}, true )
end

function Plugin:ReceiveSpecDrawRequestState( Client )
	if IsSpectator( Client ) and self.SpectatorDrawingConfig.Enabled
		and self.SpectatorDrawingReceivePreferences[ Client ] == nil then
		self:SetSpectatorDrawingReceive( Client, true, "spectator default" )
	end
	self:SendSpectatorDrawingState( Client )
end

function Plugin:GetSpectatorDrawingOwnerSlot( Client )
	for Slot = 1, SLOT_COUNT do
		if self.SpectatorDrawingSlots[ Slot ].Owner == Client then return Slot end
	end
end

function Plugin:IsSpectatorDrawingBanned( Client )
	return Client and self.SpectatorDrawingConfig.BannedUsers[ tostring( Client:GetUserId() ) ] ~= nil
end

function Plugin:ReleaseSpectatorDrawingSlot( Client, Reason )
	local SlotIndex = self:GetSpectatorDrawingOwnerSlot( Client )
	if not SlotIndex then return false end

	local Slot = self.SpectatorDrawingSlots[ SlotIndex ]
	Slot.Owner = nil
	Slot.CurrentStroke = nil
	Slot.CurrentStrokeSegments = 0
	Slot.LastClientSequence = nil
	Slot.LastAcceptedTime = nil
	Slot.LastDrawTime = nil
	self:BroadcastSpectatorDrawingSlot( SlotIndex )
	self:SpecDrawLog( "slot released slot=%d id=%s name=%s reason=%s", SlotIndex,
		tostring( Client:GetUserId() ), GetName( Client ), tostring( Reason or "request" ) )
	return true
end

function Plugin:ReceiveSpecDrawRequestSlot( Client, Data )
	if not self.SpectatorDrawingConfig.Enabled or not IsSpectator( Client ) then
		self:SpecDrawLog( "slot request rejected: not enabled/spectator id=%s", Client and Client:GetUserId() or "nil" )
		return
	end

	local SlotIndex = Data.Slot
	local Slot = self.SpectatorDrawingSlots[ SlotIndex ]
	if not Data.Claim then
		if Slot.Owner == Client then self:ReleaseSpectatorDrawingSlot( Client, "owner click" ) end
		return
	end

	if self:IsSpectatorDrawingBanned( Client ) then
		self:SpecDrawLog( "claim rejected: drawing-banned id=%s name=%s", Client:GetUserId(), GetName( Client ) )
		return
	end
	if Slot.Owner or self:GetSpectatorDrawingOwnerSlot( Client ) then
		self:SpecDrawLog( "claim rejected: occupied/already owns id=%s requestedSlot=%d", Client:GetUserId(), SlotIndex )
		return
	end

	Slot.Owner = Client
	Slot.CurrentStroke = nil
	Slot.CurrentStrokeSegments = 0
	Slot.LastClientSequence = nil
	Slot.LastAcceptedTime = nil
	Slot.LastDrawTime = Shared.GetTime()
	self:BroadcastSpectatorDrawingSlot( SlotIndex )
	if not self.SpectatorDrawingReceivers[ Client ] then
		self:SetSpectatorDrawingReceive( Client, true, "slot claim" )
	end
	self:SpecDrawLog( "slot claimed slot=%d id=%s name=%s", SlotIndex, Client:GetUserId(), GetName( Client ) )
end

function Plugin:ReceiveSpecDrawResumeBatch( Client, Data )
	if not self.SpectatorDrawingConfig.Enabled or not IsSpectator( Client )
		or self.SpectatorDrawingReceivers[ Client ] then return end
	local Resume = self.SpectatorDrawingResumeState[ Client ]
	if not Resume then
		Resume = {}
		self.SpectatorDrawingResumeState[ Client ] = Resume
	end
	local SlotResume = Resume[ Data.Slot ]
	if not SlotResume then
		SlotResume = { Count = 0 }
		Resume[ Data.Slot ] = SlotResume
	end
	if not SlotResume[ Data.Generation ] then
		if SlotResume.Count >= HISTORY_BATCH_COUNT then return end
		SlotResume.Count = SlotResume.Count + 1
	end
	SlotResume[ Data.Generation ] = {
		Epoch = Data.Epoch,
		SegmentCount = Data.SegmentCount,
		LastSequence = Data.LastSequence
	}
end

function Plugin:BuildSpectatorDrawingSnapshot( Client )
	local Queue = {}
	local Channels = {}
	local Resume = self.SpectatorDrawingResumeState[ Client ] or {}
	local Skipped = 0
	for SlotIndex = 1, SLOT_COUNT do
		local Slot = self.SpectatorDrawingSlots[ SlotIndex ]
		local Generations = { 0, 0, 0 }
		for BatchIndex = 1, #Slot.Batches do
			local Batch = Slot.Batches[ BatchIndex ]
			Generations[ BatchIndex ] = Batch.Generation
			local Segments = Batch.Segments
			local Summary = Resume[ SlotIndex ] and Resume[ SlotIndex ][ Batch.Generation ]
			local LastSequence = #Segments > 0 and Segments[ #Segments ].Sequence or 0
			local Complete = Summary and Summary.Epoch == Slot.Epoch
				and Summary.SegmentCount == #Segments and Summary.LastSequence == LastSequence
			if Complete then
				Skipped = Skipped + #Segments
			else
				for SegmentIndex = 1, #Segments do
					Queue[ #Queue + 1 ] = Segments[ SegmentIndex ]
				end
			end
		end
		Channels[ #Channels + 1 ] = {
			Slot = SlotIndex,
			Epoch = Slot.Epoch,
			Generation1 = Generations[ 1 ],
			Generation2 = Generations[ 2 ],
			Generation3 = Generations[ 3 ]
		}
	end
	self.SpectatorDrawingResumeState[ Client ] = nil

	self.SpectatorDrawingReplayQueues[ Client ] = #Queue > 0 and {
		Segments = Queue,
		Index = 1,
		Credit = 0,
		LastTime = Shared.GetTime()
	} or nil
	self:UpdateSpectatorDrawingReplayHook()
	self:SendNetworkMessage( Client, "SpecDrawSnapshotBegin", { SegmentCount = #Queue }, true )
	for i = 1, #Channels do
		self:SendNetworkMessage( Client, "SpecDrawSnapshotChannel", Channels[ i ], true )
	end
	if #Queue == 0 then
		self:SendNetworkMessage( Client, "SpecDrawSnapshotEnd", {}, true )
	end
	self:SendNetworkMessage( Client, "SpecDrawReceiveState", {
		Enabled = true,
		Synchronizing = #Queue > 0
	}, true )
	self:SpecDrawLog( "history snapshot queued id=%s replaySegments=%d cachedSegments=%d",
		Client:GetUserId(), #Queue, Skipped )
end

function Plugin:SetSpectatorDrawingReceive( Client, Enabled, Reason )
	if Enabled then
		if not self.SpectatorDrawingConfig.Enabled or not IsSpectator( Client ) then return false end
		self.SpectatorDrawingReceivePreferences[ Client ] = true
		self:AddSpectatorDrawingReceiver( Client )
		self:BuildSpectatorDrawingSnapshot( Client )
	else
		if self:GetSpectatorDrawingOwnerSlot( Client ) then
			self:SendNetworkMessage( Client, "SpecDrawReceiveState", {
				Enabled = true,
				Synchronizing = self.SpectatorDrawingReplayQueues[ Client ] ~= nil
			}, true )
			return false
		end
		self:RemoveSpectatorDrawingReceiver( Client, Reason or "disabled" )
		self.SpectatorDrawingReceivePreferences[ Client ] = false
		self.SpectatorDrawingResumeState[ Client ] = nil
		self:SendNetworkMessage( Client, "SpecDrawReceiveState", {
			Enabled = false,
			Synchronizing = false
		}, true )
	end
	return true
end

function Plugin:ReceiveSpecDrawRequestReceive( Client, Data )
	self:SetSpectatorDrawingReceive( Client, Data.Enabled, "button" )
end

function Plugin:RemoveSpectatorDrawingReplaySegments( Predicate )
	for Client, Queue in pairs( self.SpectatorDrawingReplayQueues ) do
		local Kept = {}
		for Index = Queue.Index, #Queue.Segments do
			local Segment = Queue.Segments[ Index ]
			if not Predicate( Segment ) then Kept[ #Kept + 1 ] = Segment end
		end
		Queue.Segments = Kept
		Queue.Index = 1
		self:SpecDrawLog( "history replay pruned id=%s remaining=%d", Client:GetUserId(), #Kept )
	end
end

function Plugin:RotateSpectatorDrawingBatch( SlotIndex )
	local Slot = self.SpectatorDrawingSlots[ SlotIndex ]
	if #Slot.Batches == HISTORY_BATCH_COUNT then
		local Dropped = table.remove( Slot.Batches, 1 )
		self:RemoveSpectatorDrawingReplaySegments( function( Segment )
			return Segment.Slot == SlotIndex and Segment.Epoch == Slot.Epoch
				and Segment.Generation == Dropped.Generation
		end )
		local Receivers = self:GetSpectatorDrawingReceiverList()
		self:SendNetworkMessage( Receivers, "SpecDrawBatchDrop", {
			Slot = SlotIndex,
			Epoch = Slot.Epoch,
			Generation = Dropped.Generation
		}, true )
		self:SpecDrawLog( "oldest batch dropped slot=%d generation=%d segments=%d", SlotIndex,
			Dropped.Generation, #Dropped.Segments )
	end
	Slot.NextGeneration = Slot.NextGeneration + 1
	Slot.Batches[ #Slot.Batches + 1 ] = {
		Generation = Slot.NextGeneration,
		Segments = {}
	}
	return Slot.Batches[ #Slot.Batches ]
end

function Plugin:ReceiveSpecDrawSubmitSegment( Client, Data )
	local Config = self.SpectatorDrawingConfig
	local Slot = self.SpectatorDrawingSlots[ Data.Slot ]
	if not Config.Enabled or not Slot or Slot.Owner ~= Client or not IsSpectator( Client )
		or self:IsSpectatorDrawingBanned( Client ) then
		self:SpecDrawLog( "segment rejected: authority id=%s slot=%s", Client and Client:GetUserId() or "nil", tostring( Data.Slot ) )
		return
	end
	if not IsValidVector( Data.StartPoint ) or not IsValidVector( Data.EndPoint ) then
		self:SpecDrawLog( "segment rejected: invalid coordinates id=%s", Client:GetUserId() )
		return
	end

	local Difference = Data.EndPoint - Data.StartPoint
	local Length = Difference:GetLength()
	if Length < Config.MinimumPointDistance then return end
	if Length > Config.MaximumSegmentLength then
		self:SpecDrawLog( "segment rejected: length=%.3f max=%.3f id=%s", Length,
			Config.MaximumSegmentLength, Client:GetUserId() )
		return
	end

	local Now = Shared.GetTime()
	local MinimumInterval = 0.75 / Config.SampleRateHz
	if Slot.LastAcceptedTime and Now - Slot.LastAcceptedTime < MinimumInterval then
		return
	end
	if Slot.LastClientSequence and Data.ClientSequence <= Slot.LastClientSequence then
		return
	end

	local Batch = Slot.Batches[ #Slot.Batches ]
	if Slot.CurrentStroke ~= Data.Stroke then
		local ReservedSegments = Config.MaxPointsPerStroke - 1
		if #Batch.Segments > 0 and #Batch.Segments + ReservedSegments > self.SpectatorDrawingBatchCapacity then
			Batch = self:RotateSpectatorDrawingBatch( Data.Slot )
		end
		Slot.CurrentStroke = Data.Stroke
		Slot.CurrentStrokeSegments = 0
	end
	if Slot.CurrentStrokeSegments >= Config.MaxPointsPerStroke - 1 then
		self:SpecDrawLog( "segment rejected: stroke cap id=%s stroke=%d", Client:GetUserId(), Data.Stroke )
		return
	end
	if #Batch.Segments >= self.SpectatorDrawingBatchCapacity then
		-- Defensive fallback for a malformed/overlong held stroke. The normal
		-- client chunks before this path, preserving stroke/batch boundaries.
		self:SpecDrawLog( "segment rejected: active batch full slot=%d stroke=%d", Data.Slot, Data.Stroke )
		return
	end

	Slot.Sequence = Slot.Sequence + 1
	local Message = {
		Slot = Data.Slot,
		Epoch = Slot.Epoch,
		Generation = Batch.Generation,
		Sequence = Slot.Sequence,
		Stroke = Data.Stroke,
		ClientSequence = Data.ClientSequence,
		StartPoint = Data.StartPoint,
		EndPoint = Data.EndPoint
	}
	Batch.Segments[ #Batch.Segments + 1 ] = Message
	Slot.CurrentStrokeSegments = Slot.CurrentStrokeSegments + 1
	Slot.LastClientSequence = Data.ClientSequence
	Slot.LastAcceptedTime = Now
	Slot.LastDrawTime = Now

	self:SendNetworkMessage( self:GetSpectatorDrawingReceiverList(), "SpecDrawSegment", Message, false )
	if Config.DebugSegments then
		self:SpecDrawLog( "segment accepted slot=%d generation=%d sequence=%d", Data.Slot,
			Batch.Generation, Slot.Sequence )
	end
end

function Plugin:ClearSpectatorDrawingChannel( SlotIndex, Reason )
	local Slot = self.SpectatorDrawingSlots[ SlotIndex ]
	Slot.Epoch = Slot.Epoch + 1
	self:RemoveSpectatorDrawingReplaySegments( function( Segment )
		return Segment.Slot == SlotIndex and Segment.Epoch < Slot.Epoch
	end )
	Slot.Sequence = 0
	Slot.NextGeneration = Slot.NextGeneration + 1
	Slot.Batches = { { Generation = Slot.NextGeneration, Segments = {} } }
	Slot.CurrentStroke = nil
	Slot.CurrentStrokeSegments = 0
	Slot.LastClientSequence = nil
	self:SendNetworkMessage( self:GetSpectatorDrawingReceiverList(), "SpecDrawChannelClear", {
		Slot = SlotIndex,
		Epoch = Slot.Epoch
	}, true )
	self:SpecDrawLog( "channel cleared slot=%d epoch=%d reason=%s", SlotIndex, Slot.Epoch, tostring( Reason ) )
end

function Plugin:ReceiveSpecDrawRequestClear( Client, Data )
	local Slot = self.SpectatorDrawingSlots[ Data.Slot ]
	if Slot and Slot.Owner == Client and IsSpectator( Client ) then
		self:ClearSpectatorDrawingChannel( Data.Slot, "owner reload" )
	end
end

function Plugin:ProcessSpectatorDrawingReplay()
	local Now = Shared.GetTime()
	local Rate = self.SpectatorDrawingConfig.HistoryReplayRate
	for Client, Queue in pairs( self.SpectatorDrawingReplayQueues ) do
		if not Shine:IsValidClient( Client ) or not IsSpectator( Client )
			or not self.SpectatorDrawingReceivers[ Client ] then
			self.SpectatorDrawingReplayQueues[ Client ] = nil
		else
			local Delta = Min( Now - Queue.LastTime, 0.25 )
			Queue.LastTime = Now
			Queue.Credit = Min( Rate * 0.5, Queue.Credit + Delta * Rate )
			local Count = Floor( Queue.Credit )
			while Count > 0 and Queue.Index <= #Queue.Segments do
				self:SendNetworkMessage( Client, "SpecDrawSegment", Queue.Segments[ Queue.Index ], true )
				Queue.Index = Queue.Index + 1
				Queue.Credit = Queue.Credit - 1
				Count = Count - 1
			end
			if Queue.Index > #Queue.Segments then
				self.SpectatorDrawingReplayQueues[ Client ] = nil
				self:SendNetworkMessage( Client, "SpecDrawSnapshotEnd", {}, true )
				self:SendNetworkMessage( Client, "SpecDrawReceiveState", {
					Enabled = true,
					Synchronizing = false
				}, true )
				self:SpecDrawLog( "history snapshot complete id=%s segments=%d", Client:GetUserId(), #Queue.Segments )
			end
		end
	end
	self:UpdateSpectatorDrawingReplayHook()
end

function Plugin:CheckSpectatorDrawingIdleState()
	self:PruneSpectatorDrawingReceivers()
	local Now = Shared.GetTime()
	for SlotIndex = 1, SLOT_COUNT do
		local Slot = self.SpectatorDrawingSlots[ SlotIndex ]
		if Slot.Owner and Slot.LastDrawTime
			and Now - Slot.LastDrawTime >= self.SpectatorDrawingConfig.SlotIdleTimeout then
			self:ReleaseSpectatorDrawingSlot( Slot.Owner, "drawing idle timeout" )
		end
	end
end

function Plugin:HandleSpectatorDrawingClientDisconnect( Client )
	self:ReleaseSpectatorDrawingSlot( Client, "disconnect" )
	self:RemoveSpectatorDrawingReceiver( Client, "disconnect" )
	self.SpectatorDrawingResumeState[ Client ] = nil
	self.SpectatorDrawingReceivePreferences[ Client ] = nil
	self:UpdateSpectatorDrawingReplayHook()
end

function Plugin:HandleSpectatorDrawingPostJoinTeam( Client, NewTeam )
	if not Client or Client:GetIsVirtual() then return end
	if NewTeam == kSpectatorIndex then
		self.SpectatorDrawingReceivePreferences[ Client ] = nil
		if self.SpectatorDrawingConfig.Enabled then
			self:SetSpectatorDrawingReceive( Client, true, "entered spectator team" )
		end
		self:SendSpectatorDrawingState( Client )
		return
	end
	self:ReleaseSpectatorDrawingSlot( Client, "left spectator team" )
	self.SpectatorDrawingReceivePreferences[ Client ] = nil
	if self.SpectatorDrawingReceivers[ Client ] then
		self:RemoveSpectatorDrawingReceiver( Client, "left spectator team" )
		self.SpectatorDrawingResumeState[ Client ] = nil
		self:SendNetworkMessage( Client, "SpecDrawReceiveState", {
			Enabled = false,
			Synchronizing = false
		}, true )
	end
	self:UpdateSpectatorDrawingReplayHook()
end

function Plugin:CreateSpectatorDrawingCommands()
	local function HasModerationAccess( Client )
		return not Client or Shine:HasAccess( Client, "mnga.spectatordraw.moderate" )
	end
	local function RejectAccess( Client )
		if Client then Shine:NotifyColour( Client, 255, 80, 80, "You cannot moderate spectator drawing." ) end
	end

	local Evict = self:BindCommand( "sh_specdraw_evict", nil, function( Client, Target )
		if not HasModerationAccess( Client ) then RejectAccess( Client ) return end
		local Released = self:ReleaseSpectatorDrawingSlot( Target, "admin eviction" )
		Shine:AdminPrint( Client, Released and "Released %s's spectator drawing slot."
			or "%s does not own a spectator drawing slot.", true, GetName( Target ) )
	end, true )
	Evict:AddParam{ Type = "client", IgnoreCanTarget = true }
	Evict:Help( "Releases a spectator drawing slot without clearing its colour." )

	local Ban = self:BindCommand( "sh_specdraw_ban", nil, function( Client, Target )
		if not HasModerationAccess( Client ) then RejectAccess( Client ) return end
		local ID = tostring( Target:GetUserId() )
		self.SpectatorDrawingConfig.BannedUsers[ ID ] = { Name = GetName( Target ) }
		self:SaveConfig()
		self:ReleaseSpectatorDrawingSlot( Target, "drawing ban" )
		Shine:AdminPrint( Client, "Banned %s from spectator drawing (receiving remains allowed).", true, GetName( Target ) )
		self:SpecDrawLog( "drawing ban persisted id=%s name=%s", ID, GetName( Target ) )
	end, true )
	Ban:AddParam{ Type = "client", IgnoreCanTarget = true }
	Ban:Help( "Persistently bans a player from claiming spectator drawing slots." )

	local Unban = self:BindCommand( "sh_specdraw_unban", nil, function( Client, TargetText )
		if not HasModerationAccess( Client ) then RejectAccess( Client ) return end
		local ID = tostring( TargetText or "" )
		local Target = Shine.GetClientByName and Shine.GetClientByName( ID )
		if Target then ID = tostring( Target:GetUserId() ) end
		if not self.SpectatorDrawingConfig.BannedUsers[ ID ] then
			Shine:AdminPrint( Client, "No spectator drawing ban exists for %s.", true, ID )
			return
		end
		self.SpectatorDrawingConfig.BannedUsers[ ID ] = nil
		self:SaveConfig()
		Shine:AdminPrint( Client, "Removed spectator drawing ban for %s.", true, ID )
		self:SpecDrawLog( "drawing ban removed id=%s", ID )
	end, true )
	Unban:AddParam{ Type = "string", TakeRestOfLine = true }
	Unban:Help( "Removes a spectator drawing ban by connected name or NS2 Steam ID." )
end

function Plugin:ResolveSpectatorDrawingPlaneHeight( Config )
	local MapName = Shared.GetMapName and Shared.GetMapName() or "unknown"
	local Override = tonumber( Config.DrawingPlaneHeightOverrides[ MapName ] )
	local ReferenceHeight
	local Source

	if Override then
		ReferenceHeight = Clamp( Override, -1000, 1000 )
		Source = "map override"
	else
		local Heights = {}
		for _, TechPoint in ientitylist( Shared.GetEntitiesWithClassname( "TechPoint" ) ) do
			local Origin = TechPoint:GetOrigin()
			if Origin and IsFiniteNumber( Origin.y ) then
				Heights[ #Heights + 1 ] = Origin.y
			end
		end
		table.sort( Heights )
		local Count = #Heights
		if Count > 0 then
			local Middle = Floor( ( Count + 1 ) * 0.5 )
			ReferenceHeight = Count % 2 == 1 and Heights[ Middle ]
				or ( Heights[ Middle ] + Heights[ Middle + 1 ] ) * 0.5
			Source = StringFormat( "tech-point median (%d points)", Count )
		else
			ReferenceHeight = Config.DrawingPlaneHeight
			Source = "legacy fallback"
		end
	end

	local ResolvedHeight = Floor( Clamp( ReferenceHeight + Config.DrawingPlaneHeightOffset, -1000, 1000 ) )
	Print( "%s", StringFormat(
		"[spectator_draw] drawing plane resolved map=%s source=%s reference=%.2f offset=%.2f resolved=%d",
		MapName, Source, ReferenceHeight, Config.DrawingPlaneHeightOffset, ResolvedHeight ) )
	return ResolvedHeight
end

function Plugin:InitialiseSpectatorDrawing()
	local Config = self.Config.SpectatorDrawing or {}
	Config.Enabled = Config.Enabled ~= false
	Config.Debug = Config.Debug ~= false
	Config.DebugSegments = Config.DebugSegments == true
	Config.SampleRateHz = Floor( Clamp( Config.SampleRateHz, 2, 30 ) )
	Config.LocalSampleRateHz = Floor( Clamp( Config.LocalSampleRateHz or 24, 2, 60 ) )
	Config.StrokeThickness = Floor( Clamp( Config.StrokeThickness or 3, 1, 7 ) )
	Config.MaxSegmentsPerChannel = Floor( Clamp( Config.MaxSegmentsPerChannel, 30, MAX_NETWORK_SEGMENTS ) )
	Config.HistoryBatchCount = HISTORY_BATCH_COUNT
	Config.MaxPointsPerStroke = Floor( Clamp( Config.MaxPointsPerStroke, 2, 512 ) )
	Config.MinimumPointDistance = Clamp( Config.MinimumPointDistance, 0.001, 2 )
	Config.MaximumSegmentLength = Clamp( Config.MaximumSegmentLength, 0.1, 100 )
	Config.MaximumTraceDistance = Floor( Clamp( Config.MaximumTraceDistance, 10, 2000 ) )
	Config.DrawingPlaneHeight = Floor( Clamp( Config.DrawingPlaneHeight or 0, -1000, 1000 ) )
	Config.DrawingPlaneHeightOffset = Clamp( Config.DrawingPlaneHeightOffset or 0, -1000, 1000 )
	Config.DrawingPlaneHeightOverrides = Config.DrawingPlaneHeightOverrides or {}
	Config.HistoryReplayRate = Clamp( Config.HistoryReplayRate, 10, 1000 )
	Config.SlotIdleTimeout = Clamp( Config.SlotIdleTimeout or 60, 10, 3600 )
	Config.BannedUsers = Config.BannedUsers or {}
	self.Config.SpectatorDrawing = Config
	self.SpectatorDrawingConfig = Config
	self.SpectatorDrawingResolvedPlaneHeight = self:ResolveSpectatorDrawingPlaneHeight( Config )
	self.SpectatorDrawingBatchCapacity = Max( 1, Floor( Config.MaxSegmentsPerChannel / HISTORY_BATCH_COUNT ) )
	Config.MaxPointsPerStroke = Min( Config.MaxPointsPerStroke, self.SpectatorDrawingBatchCapacity + 1 )

	self.SpectatorDrawingReceivers = {}
	self.SpectatorDrawingReceiverList = {}
	self.SpectatorDrawingReceiverIndices = {}
	self.SpectatorDrawingReplayQueues = {}
	self.SpectatorDrawingReplayHookActive = false
	self.SpectatorDrawingResumeState = {}
	self.SpectatorDrawingReceivePreferences = {}
	self.SpectatorDrawingSlots = {}
	for Slot = 1, SLOT_COUNT do
		self.SpectatorDrawingSlots[ Slot ] = {
			Owner = nil,
			Epoch = 1,
			Sequence = 0,
			NextGeneration = 1,
			Batches = { { Generation = 1, Segments = {} } }
		}
	end

	Shine.Hook.Remove( "Think", THINK_HOOK )
	self:DestroyTimer( IDLE_TIMER )
	if Config.Enabled then
		self:CreateTimer( IDLE_TIMER, 1, -1, function() self:CheckSpectatorDrawingIdleState() end )
	end
	self:CreateSpectatorDrawingCommands()
	Print( "%s", StringFormat( "[spectator_draw] scheduler initialised enabled=%s replay=on-demand idleCheck=1.0s receiverCache=event-driven",
		tostring( Config.Enabled ) ) )
	self:SpecDrawLog( "initialised enabled=%s networkSampleRate=%d localSampleRate=%d strokeThickness=%d maxSegments=%d batchCapacity=%d maxPointsPerStroke=%d replayRate=%d",
		tostring( Config.Enabled ), Config.SampleRateHz, Config.LocalSampleRateHz, Config.StrokeThickness, Config.MaxSegmentsPerChannel,
		self.SpectatorDrawingBatchCapacity, Config.MaxPointsPerStroke, Config.HistoryReplayRate )
end

function Plugin:CleanupSpectatorDrawing()
	Shine.Hook.Remove( "Think", THINK_HOOK )
	self:DestroyTimer( IDLE_TIMER )
	self.SpectatorDrawingReceivers = {}
	self.SpectatorDrawingReceiverList = {}
	self.SpectatorDrawingReceiverIndices = {}
	self.SpectatorDrawingReplayQueues = {}
	self.SpectatorDrawingReplayHookActive = false
	self.SpectatorDrawingResumeState = {}
	self.SpectatorDrawingReceivePreferences = {}
	self.SpectatorDrawingSlots = {}
	Print( "[spectator_draw] server cleanup complete." )
end
