local Plugin = ...
local Shine = Shine

local TEAM_MARINE = kTeam1Index
local TEAM_ALIEN = kTeam2Index
local PLAYING_TEAMS = { [ TEAM_MARINE ] = true, [ TEAM_ALIEN ] = true }

local function Now() return Shared.GetTime() end
local function Epoch() return os.time and os.time() or math.floor( Now() ) end
local function SID( Client ) return Client and tostring( Client:GetUserId() ) or nil end
local function IsHuman( Client ) return Client and not Client:GetIsVirtual() end
local function ClampName( Value ) return tostring( Value or "Unknown" ):sub( 1, 32 ) end
local function CountKeys( Value )
    local Count = 0
    for _ in pairs( Value or {} ) do Count = Count + 1 end
    return Count
end

function Plugin:Log( Format, ... )
    if not self.Config.Debug then return end
    Print( "%s", "[bettervoting] " .. string.format( Format, ... ) )
end

function Plugin:RegisterVoteType( Name, Definition )
    assert( type( Name ) == "string" and type( Definition ) == "table" )
    assert( type( Definition.Options ) == "table" and #Definition.Options >= 2 and #Definition.Options <= 9 )
    self.VoteTypes[ Name ] = Definition
    self:Log( "registered type=%s options=%d", Name, #Definition.Options )
end

function Plugin:IsVoteVisibleTo( Vote, Client )
    return not Vote.Definition.IsVisibleTo or Vote.Definition.IsVisibleTo( self, Vote, Client ) ~= false
end

function Plugin:GetClientBySID( SteamID )
    local Clients = Shine.GetAllClients()
    for i = 1, #Clients do
        if IsHuman( Clients[ i ] ) and SID( Clients[ i ] ) == tostring( SteamID ) then return Clients[ i ] end
    end
end

function Plugin:GetConnectedSnapshotMember( SteamID, TeamNumber )
    local Snapshot = self.Snapshot
    local Team = Snapshot and Snapshot.Teams and Snapshot.Teams[ tostring( TeamNumber ) ]
    local Member = Team and Team.Members and Team.Members[ tostring( SteamID ) ]
    local Client = Member and self:GetClientBySID( SteamID )
    return Member, Client
end

function Plugin:SaveSnapshot()
    self.Config.Snapshot = self.Snapshot or JSON.Object()
    self:SaveConfig( true )
end

function Plugin:ClearSnapshot( Reason )
    if not self.Snapshot and not next( self.Config.Snapshot or {} ) then return end
    self:Log( "clearing snapshot reason=%s", tostring( Reason ) )
    self.Snapshot = nil
    self.Config.Snapshot = require( "shine/lib/json" ).Object()
    self:SaveConfig( true )
    self:BroadcastNominationStates()
end

function Plugin:RestoreSnapshot()
    local Stored = self.Config.Snapshot
    if type( Stored ) ~= "table" or not Stored.ExpiresAt then return end
    if tonumber( Stored.ExpiresAt ) <= Epoch() then
        self:ClearSnapshot( "expired during initialise" )
        return
    end
    self.Snapshot = Stored
    self:Log( "restored snapshot round=%s expires=%s", tostring( Stored.RoundID ), tostring( Stored.ExpiresAt ) )
end

function Plugin:StartRoundTracking()
    self.RoundSequence = self.RoundSequence + 1
    self.RoundTracking = { StartedAt = Now(), Members = {}, Commanders = {} }
    for _, Client in ipairs( Shine.GetAllClients() ) do
        if IsHuman( Client ) then
            local Player = Client:GetControllingPlayer()
            local Team = Player and Player:GetTeamNumber()
            if PLAYING_TEAMS[ Team ] then self:BeginParticipation( Client, Team ) end
            if Player and Player:isa( "Commander" ) and PLAYING_TEAMS[ Team ] then
                self:BeginCommand( Client, Team )
            end
        end
    end
    self:ClearSnapshot( "next round countdown" )
    self:Log( "round tracking started sequence=%d", self.RoundSequence )
end

function Plugin:GetRoundMember( Client, TeamNumber )
    if not self.RoundTracking or not IsHuman( Client ) or not PLAYING_TEAMS[ TeamNumber ] then return nil end
    local SteamID = SID( Client )
    self.RoundTracking.Members[ SteamID ] = self.RoundTracking.Members[ SteamID ] or {
        SteamID = SteamID, Name = "Unknown", Teams = {}, CommanderTime = { [ "1" ] = 0, [ "2" ] = 0 }
    }
    local Member = self.RoundTracking.Members[ SteamID ]
    local Player = Client:GetControllingPlayer()
    Member.Name = ClampName( Player and Player:GetName() or Member.Name )
    return Member
end

function Plugin:BeginParticipation( Client, TeamNumber )
    local Member = self:GetRoundMember( Client, TeamNumber )
    if not Member then return end
    local Key = tostring( TeamNumber )
    Member.Teams[ Key ] = Member.Teams[ Key ] or { Time = 0 }
    if not Member.Teams[ Key ].JoinedAt then Member.Teams[ Key ].JoinedAt = Now() end
end

function Plugin:EndParticipation( Client, TeamNumber )
    local Member = self:GetRoundMember( Client, TeamNumber )
    local State = Member and Member.Teams[ tostring( TeamNumber ) ]
    if State and State.JoinedAt then
        State.Time = ( State.Time or 0 ) + math.max( 0, Now() - State.JoinedAt )
        State.JoinedAt = nil
    end
end

function Plugin:BeginCommand( Client, TeamNumber )
    if not self.RoundTracking or not IsHuman( Client ) or not PLAYING_TEAMS[ TeamNumber ] then return end
    local SteamID = SID( Client )
    self:GetRoundMember( Client, TeamNumber )
    self:EndCommandBySID( SteamID )
    self.RoundTracking.Commanders[ SteamID ] = { Team = TeamNumber, StartedAt = Now() }
    self:Log( "commander begin sid=%s team=%d", SteamID, TeamNumber )
end

function Plugin:EndCommandBySID( SteamID )
    local Tracking = self.RoundTracking
    local State = Tracking and Tracking.Commanders[ tostring( SteamID ) ]
    if not State then return end
    local Member = Tracking.Members[ tostring( SteamID ) ]
    if Member then
        local Key = tostring( State.Team )
        Member.CommanderTime[ Key ] = ( Member.CommanderTime[ Key ] or 0 ) + math.max( 0, Now() - State.StartedAt )
    end
    Tracking.Commanders[ tostring( SteamID ) ] = nil
    self:Log( "commander end sid=%s team=%d", tostring( SteamID ), State.Team )
end

function Plugin:FreezeRoundSnapshot()
    local Tracking = self.RoundTracking
    if not Tracking then return end
    for SteamID in pairs( Tracking.Commanders ) do self:EndCommandBySID( SteamID ) end
    for SteamID, Member in pairs( Tracking.Members ) do
        for TeamKey, State in pairs( Member.Teams ) do
            if State.JoinedAt then
                State.Time = ( State.Time or 0 ) + math.max( 0, Now() - State.JoinedAt )
                State.JoinedAt = nil
            end
        end
    end

    local Snapshot = {
        RoundID = string.format( "%s-%d-%d", Shared.GetMapName(), Epoch(), self.RoundSequence ),
        CreatedAt = Epoch(), ExpiresAt = Epoch() + math.max( 30, tonumber( self.Config.SnapshotLifetime ) or 300 ),
        Teams = { [ "1" ] = { Members = {}, Attempts = 0 }, [ "2" ] = { Members = {}, Attempts = 0 } }
    }
    for SteamID, Member in pairs( Tracking.Members ) do
        for TeamNumber = 1, 2 do
            local Key = tostring( TeamNumber )
            local Time = Member.Teams[ Key ] and tonumber( Member.Teams[ Key ].Time ) or 0
            if Time > 0 then
                Snapshot.Teams[ Key ].Members[ SteamID ] = {
                    Name = Member.Name, Time = Time, CommanderTime = tonumber( Member.CommanderTime[ Key ] ) or 0
                }
            end
        end
    end
    for TeamNumber = 1, 2 do
        local Team = Snapshot.Teams[ tostring( TeamNumber ) ]
        local BestID, BestTime
        for SteamID, Member in pairs( Team.Members ) do
            local Time = tonumber( Member.CommanderTime ) or 0
            if Time > 0 and self:GetClientBySID( SteamID ) and
                ( not BestTime or Time > BestTime or ( Time == BestTime and tostring( SteamID ) < tostring( BestID ) ) ) then
                BestID, BestTime = SteamID, Time
            end
        end
        Team.CommanderID = BestID
        self:Log( "snapshot team=%d members=%d commander=%s time=%.2f", TeamNumber,
            CountKeys( Team.Members ), tostring( BestID ), tonumber( BestTime ) or 0 )
    end
    self.Snapshot = Snapshot
    self.RoundTracking = nil
    self:SaveSnapshot()
    self:BroadcastNominationStates()
end

function Plugin:GetShadowTeamForCommander( Client )
    local SteamID = SID( Client )
    if not SteamID or not self.Snapshot or tonumber( self.Snapshot.ExpiresAt ) <= Epoch() then return nil end
    for TeamNumber = 1, 2 do
        local Team = self.Snapshot.Teams[ tostring( TeamNumber ) ]
        if Team and tostring( Team.CommanderID ) == SteamID then return TeamNumber, Team end
    end
end

function Plugin:BuildNominationState( Client )
    local TeamNumber, Team = self:GetShadowTeamForCommander( Client )
    local Result = { Visible = false }
    if not TeamNumber or not self.Config.ShadowRealm.Enabled then return Result end
    local Limit = math.max( 1, tonumber( self.Config.ShadowRealm.AttemptsPerTeam ) or 1 )
    if ( tonumber( Team.Attempts ) or 0 ) >= Limit then return Result end
    Result.Visible, Result.Team, Result.Targets = true, TeamNumber, {}
    for SteamID, Member in pairs( Team.Members or {} ) do
        if SteamID ~= tostring( Team.CommanderID ) then
            local Target = self:GetClientBySID( SteamID )
            local Player = Target and Target:GetControllingPlayer()
            if Player and Player:GetTeamNumber() ~= kSpectatorIndex then
                Result.Targets[ #Result.Targets + 1 ] = { SteamID = SteamID, Name = ClampName( Player:GetName() ) }
            end
        end
    end
    table.sort( Result.Targets, function( A, B ) return A.Name:lower() < B.Name:lower() end )
    return Result
end

function Plugin:SendNominationState( Client )
    if not Client then return end
    self:SendChunkedState( Client, 2, json.encode( self:BuildNominationState( Client ) ) )
end

function Plugin:BroadcastNominationStates()
    for _, Client in ipairs( Shine.GetAllClients() ) do self:SendNominationState( Client ) end
end

function Plugin:GetShadowElectorate( Vote )
    local Team = self.Snapshot and self.Snapshot.Teams[ tostring( Vote.Data.Team ) ]
    local Voters = {}
    for SteamID, Member in pairs( Team and Team.Members or {} ) do
        if SteamID ~= Vote.Data.CommanderID and SteamID ~= Vote.Data.TargetID and self:GetClientBySID( SteamID ) then
            Voters[ SteamID ] = { Name = Member.Name }
        end
    end
    return Voters
end

function Plugin:MakePublicVoteState( Client )
    local Vote = self.ActiveVote
    if not Vote or not self:IsVoteVisibleTo( Vote, Client ) then
        return { Active = false, Revision = self.Revision }
    end
    local ShowTotals = not Vote.Definition.ShowTotals or Vote.Definition.ShowTotals( self, Vote, Client ) ~= false
    local ShowEligibility = not Vote.Definition.ShowEligibility or Vote.Definition.ShowEligibility( self, Vote, Client ) ~= false
    local ShowChoices = Vote.Definition.ShowVoterChoices and Vote.Definition.ShowVoterChoices( self, Vote, Client ) == true
    local ShowTimer = not Vote.Definition.ShowTimer or Vote.Definition.ShowTimer( self, Vote, Client ) ~= false
    local Voters, Totals = {}, {}
    for i = 1, #Vote.Definition.Options do Totals[ i ] = 0 end
    for SteamID, Info in pairs( Vote.Electorate ) do
        local Choice = Vote.Ballots[ SteamID ]
        if Choice then Totals[ Choice ] = Totals[ Choice ] + 1 end
        if ShowEligibility then
            Voters[ #Voters + 1 ] = {
                SteamID = SteamID, Name = Info.Name, Voted = Choice ~= nil,
                Choice = ShowChoices and ( Choice or 0 ) or nil
            }
        end
    end
    table.sort( Voters, function( A, B ) return A.Name:lower() < B.Name:lower() end )
    local LocalID = SID( Client )
    return {
        Active = true, VoteID = Vote.ID, Revision = self.Revision, Type = Vote.Type,
        Question = Vote.Question, Options = Vote.Definition.Options, Totals = ShowTotals and Totals or {},
        Voters = Voters, Eligible = Vote.Electorate[ LocalID ] ~= nil,
        Selected = Vote.Ballots[ LocalID ] or 0,
        EndsAt = ShowTimer and Vote.EndsAt or 0, ServerTime = Now(), ShowTimer = ShowTimer
    }
end

function Plugin:SendVoteState( Client )
    self:SendChunkedState( Client, 1, json.encode( self:MakePublicVoteState( Client ) ) )
end

function Plugin:SendChunkedState( Client, Channel, Payload )
    Payload = tostring( Payload or "{}" )
    local ChunkSize = 900
    local Parts = math.max( 1, math.ceil( #Payload / ChunkSize ) )
    if Parts > 32 then
        self:Log( "refusing oversized state channel=%d bytes=%d parts=%d", Channel, #Payload, Parts )
        return
    end
    self.NextTransferID = ( self.NextTransferID + 1 ) % 2147483647
    for Part = 1, Parts do
        self:SendNetworkMessage( Client, "StateChunk", {
            Channel = Channel, TransferID = self.NextTransferID, Part = Part, Parts = Parts,
            Data = Payload:sub( ( Part - 1 ) * ChunkSize + 1, Part * ChunkSize )
        }, true )
    end
    self:Log( "sent state channel=%d transfer=%d bytes=%d parts=%d sid=%s", Channel,
        self.NextTransferID, #Payload, Parts, tostring( SID( Client ) ) )
end

function Plugin:BroadcastVoteState()
    self.Revision = self.Revision + 1
    for _, Client in ipairs( Shine.GetAllClients() ) do self:SendVoteState( Client ) end
end

function Plugin:StartRegisteredVote( TypeName, Starter, Data )
    local Definition = self.VoteTypes[ TypeName ]
    if self.ActiveVote or not Definition then return false, "Another Better Voting ballot is active." end
    if GetActiveVoteName and GetActiveVoteName() then return false, "A vanilla vote is active." end
    local Allowed, Reason = Definition.CanStart( self, Starter, Data )
    if not Allowed then return false, Reason end
    self.NextVoteID = self.NextVoteID + 1
    local Vote = { ID = self.NextVoteID, Type = TypeName, Definition = Definition, Data = Data,
        Ballots = {}, StartedAt = Now(), EndsAt = Now() + Definition.Duration( self ), Question = Definition.Question( self, Data ) }
    Vote.Electorate = Definition.Electorate( self, Vote )
    local Minimum = Definition.MinimumElectorate( self )
    local Count = 0
    for _ in pairs( Vote.Electorate ) do Count = Count + 1 end
    if Count < Minimum then return false, string.format( "At least %d eligible voters must be connected.", Minimum ) end
    self.ActiveVote = Vote
    Definition.OnStarted( self, Vote )
    self:Log( "started id=%d type=%s electorate=%d target=%s", Vote.ID, TypeName, Count, tostring( Data.TargetID ) )
    self:BroadcastVoteState()
    self:BroadcastNominationStates()
    return true
end

function Plugin:FinishVote( Result, Reason, ConsumeAttempt )
    local Vote = self.ActiveVote
    if not Vote then return end
    self.ActiveVote = nil
    self:Log( "finished id=%d result=%s reason=%s consume=%s", Vote.ID, Result, Reason, tostring( ConsumeAttempt ) )
    if ConsumeAttempt then Vote.Definition.ConsumeAttempt( self, Vote ) end
    if Result == "passed" then Vote.Definition.OnPassed( self, Vote ) end
    if Vote.Definition.OnCompleted then Vote.Definition.OnCompleted( self, Vote, Result, Reason ) end
    local Message = Result == "passed" and Vote.Question .. " Passed." or Vote.Question .. " " .. ( Reason or "Failed." )
    for _, Client in ipairs( Shine.GetAllClients() ) do Shine:NotifyColour( Client, 255, 180, 80, Message ) end
    self:BroadcastVoteState()
    self:BroadcastNominationStates()
end

function Plugin:EvaluateVote( TimedOut )
    local Vote = self.ActiveVote
    if not Vote then return end
    Vote.Electorate = Vote.Definition.Electorate( self, Vote )
    for SteamID in pairs( Vote.Ballots ) do
        if not Vote.Electorate[ SteamID ] then Vote.Ballots[ SteamID ] = nil end
    end
    local Count, Cast, Yes = 0, 0, 0
    for SteamID in pairs( Vote.Electorate ) do
        Count = Count + 1
        if Vote.Ballots[ SteamID ] then Cast = Cast + 1 end
        if Vote.Ballots[ SteamID ] == 1 then Yes = Yes + 1 end
    end
    if Vote.Definition.Evaluate then
        local Result, Reason = Vote.Definition.Evaluate( self, Vote, {
            Electorate = Count, Cast = Cast, Ballots = Vote.Ballots, TimedOut = TimedOut == true
        } )
        if Result then self:FinishVote( Result, Reason, true ) else self:BroadcastVoteState() end
        return
    end
    local Required = math.ceil( Count * Vote.Definition.YesFraction( self ) )
    self:Log( "evaluate id=%d electorate=%d cast=%d yes=%d required=%d", Vote.ID, Count, Cast, Yes, Required )
    if Count < Vote.Definition.MinimumElectorate( self ) then
        self:FinishVote( "failed", "Cancelled: too few eligible voters remain.", true )
    elseif Yes >= Required then
        self:FinishVote( "passed", "Passed.", true )
    elseif Yes + ( Count - Cast ) < Required or Cast == Count then
        self:FinishVote( "failed", "Failed.", true )
    else
        self:BroadcastVoteState()
    end
end

function Plugin:RegisterTestVote()
    self:RegisterVoteType( "test_apples", {
        Options = { "Yes", "No", "Maybe" },
        Duration = function( P ) return math.max( 5, tonumber( P.Config.TestVote.Duration ) or 20 ) end,
        MinimumElectorate = function() return 1 end,
        Question = function() return "Do you like apples?" end,
        CanStart = function( P )
            if not P.Config.TestVote.Enabled then return false, "Test voting is disabled." end
            return true
        end,
        Electorate = function( P )
            local Voters = {}
            for _, Client in ipairs( Shine.GetAllClients() ) do
                if IsHuman( Client ) then
                    local Player = Client:GetControllingPlayer()
                    Voters[ SID( Client ) ] = { Name = ClampName( Player and Player:GetName() ) }
                end
            end
            return Voters
        end,
        IsVisibleTo = function() return true end,
        ShowEligibility = function() return true end,
        ShowVoterChoices = function() return false end,
        ShowTotals = function() return true end,
        ShowTimer = function() return true end,
        OnStarted = function() end,
        ConsumeAttempt = function() end,
        OnPassed = function() end,
        Evaluate = function( P, Vote, State )
            if not State.TimedOut and State.Cast < State.Electorate then return nil end
            return "completed", State.TimedOut and "Completed: time expired." or "Completed: all votes cast."
        end,
        OnCompleted = function( P, Vote )
            local Totals, Highest = {}, -1
            for Index = 1, #Vote.Definition.Options do Totals[ Index ] = 0 end
            for _, Option in pairs( Vote.Ballots ) do
                if Totals[ Option ] then Totals[ Option ] = Totals[ Option ] + 1 end
            end
            for Index = 1, #Totals do Highest = math.max( Highest, Totals[ Index ] ) end
            local Winners = {}
            for Index, Total in ipairs( Totals ) do
                if Total == Highest then Winners[ #Winners + 1 ] = Vote.Definition.Options[ Index ] end
            end
            Print( "%s", string.format( "[bettervoting] TestVote winner=%s votes=%d totals=yes:%d,no:%d,maybe:%d",
                table.concat( Winners, "/" ), Highest, Totals[ 1 ], Totals[ 2 ], Totals[ 3 ] ) )
        end
    } )
end

function Plugin:CreateCommands()
    self:BindCommand( "sh_testvote", "testvote", function( Client )
        if not Client then return end
        local Success, Reason = self:StartRegisteredVote( "test_apples", Client, {} )
        if not Success then Shine:NotifyColour( Client, 255, 100, 100, Reason or "Unable to start test vote." ) end
    end, true ):Help( "Starts the Better Voting apples UI test." )
end

function Plugin:ReceiveCastVote( Client, Data )
    local Vote = self.ActiveVote
    local SteamID = SID( Client )
    if not Vote or Vote.ID ~= Data.VoteID or not Vote.Electorate[ SteamID ] or Vote.Ballots[ SteamID ] then
        self:Log( "rejected ballot sid=%s id=%s option=%s", tostring( SteamID ), tostring( Data.VoteID ), tostring( Data.Option ) )
        return
    end
    if Data.Option < 1 or Data.Option > #Vote.Definition.Options then return end
    Vote.Ballots[ SteamID ] = Data.Option
    self:Log( "accepted ballot sid=%s id=%d option=%d", SteamID, Vote.ID, Data.Option )
    self:EvaluateVote()
end

function Plugin:ReceiveStartShadowVote( Client, Data )
    local Success, Reason = self:StartRegisteredVote( "shadow_realm", Client, { TargetID = tostring( Data.TargetID ) } )
    if not Success then Shine:NotifyColour( Client, 255, 100, 100, Reason or "Unable to start vote." ) end
end

function Plugin:ReceiveRequestSync( Client )
    self:SendVoteState( Client )
    self:SendNominationState( Client )
end

function Plugin:RegisterShadowRealmVote()
    self:RegisterVoteType( "shadow_realm", {
        Options = { "Yes", "No" },
        Duration = function( P ) return math.max( 5, tonumber( P.Config.ShadowRealm.Duration ) or 20 ) end,
        MinimumElectorate = function( P ) return math.max( 1, tonumber( P.Config.ShadowRealm.MinimumElectorate ) or 3 ) end,
        YesFraction = function( P ) return math.max( 0.01, math.min( 1, tonumber( P.Config.ShadowRealm.YesFraction ) or 0.6 ) ) end,
        Question = function( P, Data )
            local Client = P:GetClientBySID( Data.TargetID )
            local Player = Client and Client:GetControllingPlayer()
            return "Send " .. ClampName( Player and Player:GetName() or "Unknown" ) .. " to the shadow realm?"
        end,
        CanStart = function( P, Client, Data )
            if not P.Config.ShadowRealm.Enabled then return false, "Shadow-realm voting is disabled." end
            local TeamNumber, Team = P:GetShadowTeamForCommander( Client )
            if not TeamNumber then return false, "Only the completed round's primary commander may start this vote." end
            local Limit = math.max( 1, tonumber( P.Config.ShadowRealm.AttemptsPerTeam ) or 1 )
            if ( tonumber( Team.Attempts ) or 0 ) >= Limit then return false, "Your team has already used its vote attempt." end
            local TargetID = tostring( Data.TargetID )
            if TargetID == SID( Client ) or not Team.Members[ TargetID ] then return false, "That player was not your eligible teammate." end
            local Target = P:GetClientBySID( TargetID )
            local Player = Target and Target:GetControllingPlayer()
            if not Player or Player:GetTeamNumber() == kSpectatorIndex then return false, "That target is no longer available." end
            Data.Team, Data.CommanderID, Data.TargetName = TeamNumber, SID( Client ), ClampName( Player:GetName() )
            return true
        end,
        Electorate = function( P, Vote ) return P:GetShadowElectorate( Vote ) end,
        OnStarted = function() end,
        IsVisibleTo = function() return true end,
        ShowEligibility = function() return true end,
        ShowVoterChoices = function() return false end,
        ShowTotals = function() return true end,
        ShowTimer = function() return true end,
        ValidateActive = function( P, Vote )
            local Target = P:GetClientBySID( Vote.Data.TargetID )
            local Player = Target and Target:GetControllingPlayer()
            if not Player or Player:GetTeamNumber() == kSpectatorIndex then
                return false, "Cancelled: the nominee is unavailable."
            end
            return true
        end,
        ConsumeAttempt = function( P, Vote )
            local Team = P.Snapshot and P.Snapshot.Teams[ tostring( Vote.Data.Team ) ]
            if Team then Team.Attempts = ( tonumber( Team.Attempts ) or 0 ) + 1; P:SaveSnapshot() end
        end,
        OnPassed = function( P, Vote )
            local Target = P:GetClientBySID( Vote.Data.TargetID )
            local Player = Target and Target:GetControllingPlayer()
            if not Player or Player:GetTeamNumber() == kSpectatorIndex then
                P:Log( "passed target unavailable sid=%s", Vote.Data.TargetID ); return
            end
            local Gamerules = GetGamerules()
            local OldTeam = Player:GetTeamNumber()
            local Success, NewPlayer = Gamerules and Gamerules:JoinTeam( Player, kSpectatorIndex, true, true )
            P:Log( "shadow transfer sid=%s success=%s old=%s new=%s", Vote.Data.TargetID, tostring( Success ),
                tostring( OldTeam ), tostring( NewPlayer and NewPlayer:GetTeamNumber() ) )
        end
    } )
end

function Plugin:Initialise()
    self.VoteTypes, self.NextVoteID, self.NextTransferID, self.Revision, self.RoundSequence = {}, 0, 0, 0, 0
    self:RegisterShadowRealmVote()
    self:RegisterTestVote()
    self:CreateCommands()
    self:RestoreSnapshot()
    Shine.Timer.Create( "bettervoting_tick", 0.25, -1, function()
        if not self.Enabled then return end
        if self.Snapshot and tonumber( self.Snapshot.ExpiresAt ) <= Epoch() then self:ClearSnapshot( "expired" ) end
        if self.ActiveVote then
            local Definition = self.ActiveVote.Definition
            local Valid, InvalidReason = true, nil
            if Definition.ValidateActive then Valid, InvalidReason = Definition.ValidateActive( self, self.ActiveVote ) end
            if not Valid then
                self:FinishVote( "failed", InvalidReason or "Cancelled: vote is no longer valid.", true )
            elseif Now() >= self.ActiveVote.EndsAt then
                if self.ActiveVote.Definition.Evaluate then
                    self:EvaluateVote( true )
                else
                    self:FinishVote( "failed", "Failed: time expired.", true )
                end
            end
        end
    end )
    self.Enabled = true
    self:Log( "initialised" )
    return true
end

function Plugin:SetGameState( Gamerules, State, OldState )
    if State == kGameState.Countdown and OldState ~= kGameState.Countdown then
        if self.ActiveVote then self:FinishVote( "failed", "Cancelled: the next round is starting.", true ) end
        self:StartRoundTracking()
    end
    if State == kGameState.Started and not self.RoundTracking then self:StartRoundTracking() end
end

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam )
    local Client = Player and Shine.GetClientForPlayer( Player )
    if not Client or not self.RoundTracking then return end
    if PLAYING_TEAMS[ OldTeam ] and OldTeam ~= NewTeam then self:EndParticipation( Client, OldTeam ) end
    if PLAYING_TEAMS[ NewTeam ] and OldTeam ~= NewTeam then self:BeginParticipation( Client, NewTeam ) end
end

function Plugin:CommLoginPlayer( Chair, Player )
    local Client = Player and Shine.GetClientForPlayer( Player )
    if Client then self:BeginCommand( Client, Player:GetTeamNumber() ) end
end

function Plugin:CommLogout( Chair )
    local Commander = Chair and Chair:GetCommander()
    local Client = Commander and Shine.GetClientForPlayer( Commander )
    if Client then self:EndCommandBySID( SID( Client ) ) end
end

function Plugin:EndGame() self:FreezeRoundSnapshot() end

function Plugin:ClientConfirmConnect( Client )
    Shine.Timer.Simple( 1, function()
        if self.Enabled and Shine:IsValidClient( Client ) then
            self:SendVoteState( Client ); self:SendNominationState( Client )
            if self.ActiveVote then self:EvaluateVote() end
        end
    end )
end

function Plugin:ClientDisconnect( Client )
    local SteamID = SID( Client )
    self:EndCommandBySID( SteamID )
    if self.RoundTracking then
        local Member = self.RoundTracking.Members[ SteamID ]
        if Member then for TeamKey in pairs( Member.Teams ) do self:EndParticipation( Client, tonumber( TeamKey ) ) end end
    end
    if self.ActiveVote then Shine.Timer.Simple( 0, function() if self.Enabled and self.ActiveVote then self:EvaluateVote() end end ) end
    Shine.Timer.Simple( 0, function() if self.Enabled then self:BroadcastNominationStates() end end )
end

function Plugin:MapChange()
    if self.ActiveVote then
        self:Log( "map change cancelled active id=%d without consuming attempt", self.ActiveVote.ID )
        self.ActiveVote = nil
    end
    if self.Snapshot then self:SaveSnapshot() end
end

function Plugin:Cleanup()
    Shine.Timer.Destroy( "bettervoting_tick" )
    self.ActiveVote = nil
    self.BaseClass.Cleanup( self )
end

return Plugin
