local Plugin = ...
local Shine = Shine
local JSON = require "shine/lib/json"

local FilePath = "config://shine/temp/nameguard_snapshot.json"
local TimerName = "nameguard_post_load_validation"
local MapVoteHook = "NameGuardMapVoteStart"
local StringFormat = string.format
local StringUTF8Lower = string.UTF8Lower
local OSTime = os.time
local Random = math.random
local Min = math.min
local Floor = math.floor

local ReplacementNameFormat = "no copying names(%d)"
local MaxReplacementNumber = 200

-- Static Arial 15 advance widths, normalised against the mean advance of
-- A-Z, a-z and 0-9. These are committed calibration data; the server never
-- creates GUI objects or asks a client to measure a name.
local GlyphWidths = {
	[ " " ] = 0.540305, [ "!" ] = 0.405229, [ '"' ] = 0.675381, [ "#" ] = 0.945534,
	[ "$" ] = 0.945534, [ "%" ] = 1.620915, [ "&" ] = 1.215686, [ "'" ] = 0.270153,
	[ "(" ] = 0.540305, [ ")" ] = 0.540305, [ "*" ] = 0.675381, [ "+" ] = 1.080610,
	[ "," ] = 0.540305, [ "-" ] = 0.540305, [ "." ] = 0.540305, [ "/" ] = 0.540305,
	[ "0" ] = 0.945534, [ "1" ] = 0.945534, [ "2" ] = 0.945534, [ "3" ] = 0.945534,
	[ "4" ] = 0.945534, [ "5" ] = 0.945534, [ "6" ] = 0.945534, [ "7" ] = 0.945534,
	[ "8" ] = 0.945534, [ "9" ] = 0.945534, [ ":" ] = 0.540305, [ ";" ] = 0.540305,
	[ "<" ] = 1.080610, [ "=" ] = 1.080610, [ ">" ] = 1.080610, [ "?" ] = 0.945534,
	[ "@" ] = 1.755991, [ "A" ] = 1.215686, [ "B" ] = 1.215686, [ "C" ] = 1.215686,
	[ "D" ] = 1.215686, [ "E" ] = 1.215686, [ "F" ] = 1.080610, [ "G" ] = 1.350763,
	[ "H" ] = 1.215686, [ "I" ] = 0.405229, [ "J" ] = 0.810458, [ "K" ] = 1.215686,
	[ "L" ] = 0.945534, [ "M" ] = 1.485839, [ "N" ] = 1.215686, [ "O" ] = 1.350763,
	[ "P" ] = 1.215686, [ "Q" ] = 1.350763, [ "R" ] = 1.215686, [ "S" ] = 1.215686,
	[ "T" ] = 0.945534, [ "U" ] = 1.215686, [ "V" ] = 1.215686, [ "W" ] = 1.755991,
	[ "X" ] = 0.945534, [ "Y" ] = 1.215686, [ "Z" ] = 0.945534, [ "[" ] = 0.540305,
	[ "\\" ] = 0.540305, [ "]" ] = 0.540305, [ "^" ] = 0.675381, [ "_" ] = 0.945534,
	[ "`" ] = 0.540305, [ "a" ] = 0.945534, [ "b" ] = 0.945534, [ "c" ] = 0.945534,
	[ "d" ] = 0.945534, [ "e" ] = 0.945534, [ "f" ] = 0.405229, [ "g" ] = 0.945534,
	[ "h" ] = 0.945534, [ "i" ] = 0.405229, [ "j" ] = 0.405229, [ "k" ] = 0.945534,
	[ "l" ] = 0.405229, [ "m" ] = 1.485839, [ "n" ] = 0.945534, [ "o" ] = 0.945534,
	[ "p" ] = 0.945534, [ "q" ] = 0.945534, [ "r" ] = 0.540305, [ "s" ] = 0.945534,
	[ "t" ] = 0.540305, [ "u" ] = 0.945534, [ "v" ] = 0.675381, [ "w" ] = 1.215686,
	[ "x" ] = 0.945534, [ "y" ] = 0.945534, [ "z" ] = 0.945534, [ "{" ] = 0.540305,
	[ "|" ] = 0.405229, [ "}" ] = 0.540305, [ "~" ] = 1.080610,
	-- Additional measured-set characters use the requested equivalent Arial 15
	-- advances rather than the conservative unknown-glyph charge.
	[ "§" ] = 1.215686, -- Same visual allowance as S.
	[ "Ä" ] = 1.215686  -- Same visual allowance as A.
}
-- Characters outside calibrated printable ASCII are deliberately charged well
-- above the widest measured ASCII glyph (1.756 units). This is conservative
-- for CJK, emoji, symbols, combining marks and fallback-font rendering.
local UnknownGlyphWidth = 3
-- 20 units, reduced by roughly the measured width of two '%' glyphs (2 * 1.620915).
local MaxVisualNameUnits = 16.7

-- Keep this set intentionally narrow: these glyphs are commonly used as a
-- near-identical lower-case L. Broader leetspeak folding (for example 3 -> e)
-- creates substantially more false-positive ownership collisions.
local ImpersonationConfusables = {
	[ "i" ] = "l",
	[ "1" ] = "l",
	[ "!" ] = "l",
	[ "|" ] = "l"
}

local function GetPlayer( Client )
	return Client and Client.GetControllingPlayer and Client:GetControllingPlayer() or nil
end

function Plugin:CanonicaliseName( Name )
	if type( Name ) ~= "string" then return "" end

	-- This covers Alt+255 (U+00A0) as well as zero-width Unicode characters.
	local Canonical = string.NormaliseUTF8Whitespace( Name, " " )
	Canonical = string.gsub( Canonical, "^%s+", "" )
	Canonical = string.gsub( Canonical, "%s+$", "" )
	Canonical = string.gsub( Canonical, "%s+", " " )
	Canonical = StringUTF8Lower( Canonical )

	local Normalised = {}
	local Length = string.UTF8Length( Canonical )
	for i = 1, Length do
		local Character = string.UTF8Sub( Canonical, i, i )
		Normalised[ i ] = ImpersonationConfusables[ Character ] or Character
	end
	return table.concat( Normalised )
end

function Plugin:IsBlankName( Name )
	return type( Name ) ~= "string" or not string.ContainsNonUTF8Whitespace( Name )
end

function Plugin:GetNameLimits()
	local MaxCharacters = Floor( Min( 25, math.max( 1, self.Config.MaxNameCharacters or 25 ) ) )
	-- Enforce the server policy even when an existing generated config still
	-- contains an older, wider value.
	local MaxWidth = Min( MaxVisualNameUnits,
		math.max( 1, self.Config.MaxVisualNameUnits or MaxVisualNameUnits ) )
	return MaxCharacters, MaxWidth
end

function Plugin:GetVisualNameWidth( Name )
	local Width = 0
	local Length = string.UTF8Length( Name )
	for i = 1, Length do
		local Character = string.UTF8Sub( Name, i, i )
		Width = Width + ( GlyphWidths[ Character ] or UnknownGlyphWidth )
	end
	return Width
end

function Plugin:TruncateName( Name )
	if type( Name ) ~= "string" then return "", 0, 0, "invalid" end

	-- Mirror the cleanup performed by Player:SetName(), because this hook runs
	-- immediately before that method and must evaluate the name it will store.
	local Sanitised = string.gsub( Name, '\"(.*)\"', "%1" )
	Sanitised = string.gsub( Sanitised, "[\a\b\f\n\r\t\v]", "" )

	local MaxCharacters, MaxWidth = self:GetNameLimits()
	local Length = string.UTF8Length( Sanitised )
	local Width = 0
	local Kept = 0
	local Trigger = Length > MaxCharacters and "characters" or nil

	for i = 1, Min( Length, MaxCharacters ) do
		local Character = string.UTF8Sub( Sanitised, i, i )
		local CharacterWidth = GlyphWidths[ Character ] or UnknownGlyphWidth
		if Width + CharacterWidth > MaxWidth then
			Trigger = "visual-width"
			break
		end
		Width = Width + CharacterWidth
		Kept = i
	end

	return string.UTF8Sub( Sanitised, 1, Kept ), Kept, Width, Trigger
end

-- Returns the lowest free "no copying names(x)". A number is taken while a
-- connected human (other than Client) holds it or the snapshot reserves it for
-- another Steam ID, so simultaneous offenders never share a replacement name.
function Plugin:GetReplacementName( Client )
	local SteamID = Client and Client:GetUserId()
	for i = 1, MaxReplacementNumber do
		local Name = StringFormat( ReplacementNameFormat, i )
		local Canonical = self:CanonicaliseName( Name )
		local SnapshotOwner = self:GetSnapshotOwner( Canonical )
		if not self:FindConnectedOwner( Canonical, Client )
		and ( not SnapshotOwner or SnapshotOwner == SteamID ) then
			return Name
		end
	end

	-- Unreachable on a real server; the engine's (1)/(2) suffix still dedups.
	return StringFormat( ReplacementNameFormat, Random( MaxReplacementNumber + 1, 9999 ) )
end

function Plugin:SaveSnapshot( Reason )
	if not self.Snapshot then return end

	self.Snapshot.savedAt = OSTime()
	self.Snapshot.expiresAt = self.Snapshot.savedAt + ( self.Config.SnapshotTTLSeconds or 7200 )
	Shine.SaveJSONFile( self.Snapshot, FilePath, { indent = true } )
end

function Plugin:TakeSnapshot( Reason )
	local Names = JSON.Object()
	local Count = 0
	local Clients, ClientCount = Shine.GetAllClients()

	for i = 1, ClientCount do
		local Client = Clients[ i ]
		if not Client:GetIsVirtual() then
			local Player = GetPlayer( Client )
			local Name = Player and Player:GetName()
			local Canonical = self:CanonicaliseName( Name )
			if Canonical ~= "" then
				Names[ Canonical ] = Client:GetUserId()
				Count = Count + 1
			end
		end
	end

	self.Snapshot = {
		version = 2,
		names = Names,
		count = Count
	}
	self:SaveSnapshot( Reason )
end

function Plugin:LoadSnapshot()
	local Snapshot = Shine.LoadJSONFile( FilePath )
	if not Snapshot then return end

	if type( Snapshot.names ) ~= "table" or type( Snapshot.expiresAt ) ~= "number" then
		return
	end

	if Snapshot.expiresAt < OSTime() then
		return
	end

	-- Snapshots may have been written by the earlier, case-only canonicaliser.
	-- Re-key them on load so a mod update during a map transition retains the
	-- ownership protection. In the unlikely event of a newly-equivalent pair,
	-- retaining either owner is safer than allowing a third client to claim it.
	local NormalisedNames = JSON.Object()
	local Count = 0
	for Name, SteamID in pairs( Snapshot.names ) do
		local Canonical = self:CanonicaliseName( Name )
		if Canonical ~= "" and NormalisedNames[ Canonical ] == nil then
			NormalisedNames[ Canonical ] = SteamID
			Count = Count + 1
		end
	end
	Snapshot.names = NormalisedNames
	Snapshot.count = Count
	Snapshot.version = 2
	Print( "%s", StringFormat( "[nameguard] Loaded and normalised %d snapshot name(s)", Count ) )

	self.Snapshot = Snapshot
end

function Plugin:GetSnapshotOwner( CanonicalName )
	if not self.Snapshot or not self.Snapshot.names then return nil end
	if self.Snapshot.expiresAt and self.Snapshot.expiresAt < OSTime() then
		self.Snapshot = nil
		return nil
	end

	return tonumber( self.Snapshot.names[ CanonicalName ] )
end

function Plugin:FindConnectedOwner( CanonicalName, ExcludedClient )
	local Clients, ClientCount = Shine.GetAllClients()
	for i = 1, ClientCount do
		local Client = Clients[ i ]
		if Client ~= ExcludedClient and not Client:GetIsVirtual() then
			local Player = GetPlayer( Client )
			if Player and self:CanonicaliseName( Player:GetName() ) == CanonicalName then
				return Client
			end
		end
	end
	return nil
end

function Plugin:ForceRename( Client, Reason )
	local Player = GetPlayer( Client )
	if not Player then return false end

	local OldName = Player:GetName()
	local Replacement = self:GetReplacementName( Client )
	Print( "%s", StringFormat( "[nameguard] Force-renaming '%s' (Steam ID %s) to '%s': %s",
		tostring( OldName ), tostring( Client:GetUserId() ), Replacement, tostring( Reason ) ) )
	-- SetName re-enters CheckPlayerName; skip it so "(10)" and above are not
	-- cut by the visual-width limit.
	self.ApplyingReplacement = Replacement
	Player:SetName( Replacement )
	self.ApplyingReplacement = nil
	return true
end

function Plugin:CheckPlayerName( Player, Name )
	if not self.Config.Enabled or not Player then return end
	local Client = Player:GetClient()
	if not Client or Client:GetIsVirtual() then return end
	if Name == self.ApplyingReplacement then return end

	local AdjustedName = self:TruncateName( Name )
	if self:IsBlankName( AdjustedName ) then
		Print( "%s", StringFormat( "[nameguard] Replacing blank/invisible name for Steam ID %s",
			tostring( Client:GetUserId() ) ) )
		return self:GetReplacementName( Client )
	end

	local Canonical = self:CanonicaliseName( AdjustedName )
	local ConnectedOwner = self:FindConnectedOwner( Canonical, Client )
	if ConnectedOwner then
		Print( "%s", StringFormat( "[nameguard] Blocked connected-name impersonation by Steam ID %s; canonical='%s', owner=%s",
			tostring( Client:GetUserId() ), Canonical, tostring( ConnectedOwner:GetUserId() ) ) )
		return self:GetReplacementName( Client )
	end

	local SnapshotOwner = self:GetSnapshotOwner( Canonical )
	if SnapshotOwner and SnapshotOwner ~= Client:GetUserId() then
		Print( "%s", StringFormat( "[nameguard] Blocked snapshot-name impersonation by Steam ID %s; canonical='%s', owner=%s",
			tostring( Client:GetUserId() ), Canonical, tostring( SnapshotOwner ) ) )
		return self:GetReplacementName( Client )
	end

	if AdjustedName ~= Name then
		Print( "%s", StringFormat( "[nameguard] Truncated name for Steam ID %s from '%s' to '%s'",
			tostring( Client:GetUserId() ), tostring( Name ), AdjustedName ) )
		return AdjustedName
	end
end

function Plugin:ClientConfirmConnect( Client )
	if not self.Config.Enabled or not Client or Client:GetIsVirtual() then return end

	-- A connecting player's initial SetName can run before Shine installs its
	-- Player:SetName hook. Re-check on the next tick so initial names receive the
	-- same character/width enforcement as later name changes.
	self:SimpleTimer( 0, function()
		if not Client or not Shine:IsValidClient( Client ) then return end
		local Player = GetPlayer( Client )
		if not Player then return end

		local Name = Player:GetName()
		local Replacement = self:CheckPlayerName( Player, Name )
		if Replacement and Replacement ~= Name then
			Player:SetName( Replacement )
		end
	end )
end

function Plugin:PlayerNameChange( Player, NewName, OldName )
	if not self.Snapshot or not Player then return end
	local Client = Player:GetClient()
	if not Client or Client:GetIsVirtual() then return end

	local SteamID = Client:GetUserId()
	local OldCanonical = self:CanonicaliseName( OldName )
	local NewCanonical = self:CanonicaliseName( NewName )
	if self.Snapshot.names[ OldCanonical ] == SteamID then
		self.Snapshot.names[ OldCanonical ] = nil
		self.Snapshot.count = math.max( 0, ( self.Snapshot.count or 1 ) - 1 )
	end
	if NewCanonical ~= "" then
		if self.Snapshot.names[ NewCanonical ] == nil then
			self.Snapshot.count = ( self.Snapshot.count or 0 ) + 1
		end
		self.Snapshot.names[ NewCanonical ] = SteamID
	end
	self:SaveSnapshot( "name change" )
end

function Plugin:ValidateAllPlayers( Reason )
	if not self.Config.Enabled then return end
	local Clients, ClientCount = Shine.GetAllClients()
	for i = 1, ClientCount do
		local Client = Clients[ i ]
		if not Client:GetIsVirtual() then
			local Player = GetPlayer( Client )
			if Player then
				local Name = Player:GetName()
				local AdjustedName = self:TruncateName( Name )
				local Canonical = self:CanonicaliseName( AdjustedName )
				local SnapshotOwner = self:GetSnapshotOwner( Canonical )
				if self:IsBlankName( AdjustedName ) then
					self:ForceRename( Client, Reason..": blank/invisible" )
				elseif AdjustedName ~= Name then
					Player:SetName( AdjustedName )
				elseif SnapshotOwner and SnapshotOwner ~= Client:GetUserId() then
					self:ForceRename( Client, Reason..": snapshot owner="..SnapshotOwner )
				end
			end
		end
	end

end

function Plugin:HandleMapVoteStarted()
	if self.Config.Enabled then
		self:TakeSnapshot( "map vote started" )
		self.SnapshotTakenForCurrentMap = true
	end
end

function Plugin:MapChange()
	-- Forced cycles/admin map changes may have no map vote. Do not overwrite a
	-- vote-start snapshot: that snapshot is the ownership record for this change.
	if self.Config.Enabled and not self.SnapshotTakenForCurrentMap then
		self:TakeSnapshot( "map change fallback" )
	end
end

function Plugin:MapPostLoad()
	self.SnapshotTakenForCurrentMap = false
	Shine.Timer.Destroy( TimerName )
	local Delay = self.Config.PostLoadValidationDelay or 3
	Shine.Timer.Create( TimerName, Delay, 1, function()
		self:ValidateAllPlayers( "post map load" )
	end )
end

function Plugin:CreateCommands()
	local Rename = self:BindCommand( "sh_nameguard_rename", "ngrename", function( Client, Target, NewName )
		local Player = GetPlayer( Target )
		if not Player then
			Shine:NotifyCommandError( Client, "That client does not currently control a player.", true )
			return
		end

		local OldName = Player:GetName()
		Player:SetName( NewName )
		Shine:AdminPrint( nil, "%s was renamed to '%s' by %s.", true, OldName, Player:GetName(),
			Shine.GetClientInfo( Client ) )
	end )
	Rename:AddParam{ Type = "client", IgnoreCanTarget = true }
	Rename:AddParam{ Type = "string", TakeRestOfLine = true, Help = "new name" }
	Rename:Help( "Renames a player, including an offline-person impersonator." )
end

function Plugin:Initialise()
	self:LoadSnapshot()
	self.SnapshotTakenForCurrentMap = false
	self:CreateCommands()
	-- Map vote creates this event dynamically, so subscribe explicitly rather
	-- than relying on Shine's plugin-method hook discovery at load time.
	Shine.Hook.Add( "OnMapVoteStarted", MapVoteHook, function()
		self:HandleMapVoteStarted()
	end )
	self.Enabled = true
	return true
end

function Plugin:Cleanup()
	Shine.Timer.Destroy( TimerName )
	Shine.Hook.Remove( "OnMapVoteStarted", MapVoteHook )
	self.BaseClass.Cleanup( self )
end

return Plugin
