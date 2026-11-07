local Plugin = ...

local GUI_SCRIPT_NAME = "mnga_administration/GUISpectatorDrawing"
local SETUP_HOOK = "MNGAAdministrationSpectatorDrawingClientSetup"

function Plugin:GetSpectatorDrawingGUI()
	local Manager = GetGUIManager and GetGUIManager()
	return Manager and Manager:GetGUIScriptSingle( GUI_SCRIPT_NAME ) or nil
end

function Plugin:FlushPendingSpectatorDrawingMessages( GUI )
	local Pending = self.PendingSpectatorDrawingMessages
	if not Pending then return end
	self.PendingSpectatorDrawingMessages = nil
	for i = 1, #Pending do
		local Message = Pending[ i ]
		GUI[ Message.Method ]( GUI, unpack( Message.Arguments ) )
	end
	Print( "%s", string.format( "[spectator_draw] applied %d messages queued before GUIScript was ready.", #Pending ) )
end

function Plugin:ApplyOrQueueSpectatorDrawingMessage( Method, ... )
	local GUI = self:EnsureSpectatorDrawingGUI()
	if GUI then
		GUI[ Method ]( GUI, ... )
		return
	end
	self.PendingSpectatorDrawingMessages = self.PendingSpectatorDrawingMessages or {}
	self.PendingSpectatorDrawingMessages[ #self.PendingSpectatorDrawingMessages + 1 ] = {
		Method = Method,
		Arguments = { ... }
	}
end

function Plugin:EnsureSpectatorDrawingGUI()
	local GUI = self:GetSpectatorDrawingGUI()
	if GUI then return GUI end
	local Manager = GetGUIManager and GetGUIManager()
	if not GUIScript or not Manager then
		if not self.SpectatorDrawingWaitingForGUIScript then
			self.SpectatorDrawingWaitingForGUIScript = true
			Print( "[spectator_draw] waiting for NS2 GUIScript/GUIManager before loading drawing GUI." )
		end
		return nil
	end

	-- Shine's client extension is loaded before NS2's legacy GUIScript base
	-- class. Loading this file any earlier raises "Not a valid base class".
	if not GUISpectatorDrawing then
		Script.Load( "lua/mnga_administration/GUISpectatorDrawing.lua" )
	end

	GUI = Manager:CreateGUIScriptSingle( GUI_SCRIPT_NAME )
	if not GUI then return nil end
	self.SpectatorDrawingWaitingForGUIScript = nil
	Print( "[spectator_draw] client GUI created." )
	self:FlushPendingSpectatorDrawingMessages( GUI )
	return GUI
end

function Plugin:InstallSpectatorDrawingPenPatch()
	if self.SpectatorDrawingPenPatched or not GUIInsight_PenTool then return false end

	self.SpectatorDrawingPenOriginalSendKeyEvent = GUIInsight_PenTool.SendKeyEvent
	self.SpectatorDrawingPenOriginalUpdate = GUIInsight_PenTool.Update
	self.SpectatorDrawingPenOriginalSetIsVisible = GUIInsight_PenTool.SetIsVisible

	GUIInsight_PenTool.SendKeyEvent = function() return false end
	GUIInsight_PenTool.Update = function() end
	GUIInsight_PenTool.SetIsVisible = function( Pen, Visible )
		return self.SpectatorDrawingPenOriginalSetIsVisible( Pen, false )
	end
	self.SpectatorDrawingPenPatched = true
	Print( "[spectator_draw] disabled vanilla local screen-space pen tool." )
	return true
end

function Plugin:RestoreSpectatorDrawingPenPatch()
	if not self.SpectatorDrawingPenPatched then return end
	GUIInsight_PenTool.SendKeyEvent = self.SpectatorDrawingPenOriginalSendKeyEvent
	GUIInsight_PenTool.Update = self.SpectatorDrawingPenOriginalUpdate
	GUIInsight_PenTool.SetIsVisible = self.SpectatorDrawingPenOriginalSetIsVisible
	self.SpectatorDrawingPenPatched = nil
	Print( "[spectator_draw] restored vanilla local screen-space pen tool." )
end

function Plugin:InstallSpectatorDrawingVisibilityPatch()
	if self.SpectatorDrawingVisibilityPatched or not GUISpectator or not GUISpectator.SetIsVisible then
		return false
	end

	self.SpectatorDrawingOriginalSetIsVisible = GUISpectator.SetIsVisible
	GUISpectator.SetIsVisible = function( SpectatorGUI, Visible )
		self.SpectatorDrawingOriginalSetIsVisible( SpectatorGUI, Visible )
		local DrawingGUI = self:GetSpectatorDrawingGUI()
		if DrawingGUI then DrawingGUI:SetInsightVisible( Visible ) end
	end
	self.SpectatorDrawingVisibilityPatched = true
	Print( "[spectator_draw] installed Insight visibility bridge." )
	return true
end

function Plugin:TryCompleteSpectatorDrawingSetup()
	local Complete = self.SpectatorDrawingVisibilityPatched
		or self:InstallSpectatorDrawingVisibilityPatch()
	if self.SpectatorDrawingConfigured then
		Complete = self:EnsureSpectatorDrawingGUI() ~= nil and Complete
		if self.SpectatorDrawingServerEnabled then
			Complete = ( self.SpectatorDrawingPenPatched
				or self:InstallSpectatorDrawingPenPatch() ) and Complete
		end
	end
	if not Complete then return false end

	local WasDeferred = self.SpectatorDrawingSetupDeferred
	Shine.Hook.Remove( "Think", SETUP_HOOK )
	self.SpectatorDrawingSetupDeferred = nil
	if WasDeferred then
		Print( "[spectator_draw] deferred client setup complete; setup Think hook removed." )
	end
	return true
end

function Plugin:ScheduleSpectatorDrawingSetup()
	if self.SpectatorDrawingSetupDeferred then return end
	self.SpectatorDrawingSetupDeferred = true
	Shine.Hook.Remove( "Think", SETUP_HOOK )
	Shine.Hook.Add( "Think", SETUP_HOOK, function()
		self:TryCompleteSpectatorDrawingSetup()
	end )
	Print( "[spectator_draw] client setup deferred until required NS2 GUI classes are available." )
end

function Plugin:InitialiseSpectatorDrawing()
	if not self:TryCompleteSpectatorDrawingSetup() then
		self:ScheduleSpectatorDrawingSetup()
	end
	self:SendNetworkMessage( "SpecDrawRequestState", {}, true )
	Print( "[spectator_draw] client module initialised lazily; requesting server state." )
end

function Plugin:ReceiveSpecDrawConfig( Data )
	self.SpectatorDrawingConfigured = true
	self.SpectatorDrawingServerEnabled = Data.Enabled
	if Data.Enabled then
		self:InstallSpectatorDrawingPenPatch()
	else
		self:RestoreSpectatorDrawingPenPatch()
	end
	local GUI = self:EnsureSpectatorDrawingGUI()
	if GUI then
		GUI:ApplyServerConfig( Data )
	else
		self:ApplyOrQueueSpectatorDrawingMessage( "ApplyServerConfig", Data )
	end
	if not self:TryCompleteSpectatorDrawingSetup() then
		self:ScheduleSpectatorDrawingSetup()
	end
end

function Plugin:ReceiveSpecDrawSlotState( Data )
	self:ApplyOrQueueSpectatorDrawingMessage( "ApplySlotState", Data )
end

function Plugin:ReceiveSpecDrawReceiveState( Data )
	self:ApplyOrQueueSpectatorDrawingMessage( "ApplyReceiveState", Data )
end

function Plugin:ReceiveSpecDrawSnapshotBegin( Data )
	self:ApplyOrQueueSpectatorDrawingMessage( "BeginSnapshot", Data.SegmentCount )
end

function Plugin:ReceiveSpecDrawSnapshotChannel( Data )
	self:ApplyOrQueueSpectatorDrawingMessage( "ApplySnapshotChannel", Data )
end

function Plugin:ReceiveSpecDrawSnapshotEnd()
	self:ApplyOrQueueSpectatorDrawingMessage( "EndSnapshot" )
end

function Plugin:ReceiveSpecDrawSegment( Data )
	self:ApplyOrQueueSpectatorDrawingMessage( "AddAuthoritativeSegment", Data )
end

function Plugin:ReceiveSpecDrawBatchDrop( Data )
	self:ApplyOrQueueSpectatorDrawingMessage( "DropBatch", Data )
end

function Plugin:ReceiveSpecDrawChannelClear( Data )
	self:ApplyOrQueueSpectatorDrawingMessage( "ClearChannel", Data )
end

function Plugin:CleanupSpectatorDrawing()
	Shine.Hook.Remove( "Think", SETUP_HOOK )
	self.SpectatorDrawingSetupDeferred = nil
	self.PendingSpectatorDrawingMessages = nil
	local GUI = self:GetSpectatorDrawingGUI()
	if GUI then
		GUI:ClearAllDrawing()
		GetGUIManager():DestroyGUIScriptSingle( GUI_SCRIPT_NAME )
	end

	self:RestoreSpectatorDrawingPenPatch()
	if self.SpectatorDrawingVisibilityPatched then
		GUISpectator.SetIsVisible = self.SpectatorDrawingOriginalSetIsVisible
		self.SpectatorDrawingVisibilityPatched = nil
	end
	Print( "[spectator_draw] client cleanup complete." )
end
