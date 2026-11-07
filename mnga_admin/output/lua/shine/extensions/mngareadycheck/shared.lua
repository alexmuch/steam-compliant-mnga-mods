--[[
	MNGA Ready Check (.claude/docs/ready-check.md).

	CS-style "ready up" before a full-server round starts. When both commanders
	are in their chairs and more players want to play than there are field
	slots, the start is held: first both commanders ready, then slot holders
	(Teams + Ready Room) and queued spectators ready up; after PoolWindow,
	ready queued spectators replace unready slot holders in queue order; after
	OpenWindow an "under-full start" vote runs. A commander leaving the chair
	cancels the check. After an all-ready start, leaving within LeaveBanWindow
	bans the player from the queue for LeaveBanDuration.

	All durations are config values so they can be tuned after live use.
]]

local Plugin = Shine.Plugin( ... )

Plugin.Version = "0.1"
Plugin.PrintName = "Ready Check"
Plugin.NotifyPrefixColour = {
	80, 220, 120
}
Plugin.HasConfig = true
Plugin.ConfigName = "mngareadycheck.json"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.DefaultState = false

Plugin.DefaultConfig = {
	-- Master switch. false = Shine pregame starts games exactly as before.
	-- Live: sh_readycheck_enabled false (applies immediately and saves this).
	ReadyCheckEnabled = true,
	-- Safety net: the longest a check may hold the start (seconds, counted from
	-- both commanders sitting down). After it, the game starts through normal
	-- pregame. 0 = no limit (strictly wait for players/vote).
	MaxHoldTime = 300,
	-- Field players (commanders excluded) that make a full game. The check only
	-- activates when slot holders + connected queued spectators exceed this.
	TargetPlayers = 18,
	-- Seconds both commanders get to ready before anyone else. An unready
	-- commander is then removed from the chair (cancelling the check so
	-- someone else can command). 0 = wait for the commanders indefinitely.
	CommanderReadyWindow = 60,
	-- Seconds slot holders get before ready queued spectators may take slots.
	PoolWindow = 30,
	-- Seconds the slots stay open to ready queued spectators before the vote.
	OpenWindow = 60,
	-- Seconds before PoolWindow ends that unready slot holders get a chat
	-- reminder (no flash: one taskbar flash per round). 0 disables it.
	WarnBeforePoolEnd = 10,
	-- Under-full start vote.
	VoteEnabled = true,
	-- Seconds players have to vote.
	VoteDuration = 20,
	-- Seconds between the vote passing and the game starting.
	VoteExecuteDelay = 1,
	-- Seconds to keep retrying the vote start (another vote or the vote
	-- cooldown can block it) before giving up and waiting.
	VoteStartTimeout = 60,
	-- Seconds between server ticks while a check runs (phase timers, swaps,
	-- client state). Has no cost when no check is running.
	TickInterval = 1,
	-- Minimum seconds between one player's ready requests.
	ReadyRateLimit = 0.5,
	-- "countdown": go straight to the vanilla 6s countdown after the check.
	-- "pregame": hand back to Shine pregame's normal "game starts soon" wait.
	ReleaseMode = "countdown",
	-- After an all-ready start (not a vote start), players on a team at round
	-- start who disconnect or leave their team within LeaveBanWindow seconds
	-- cannot queue for LeaveBanDuration seconds. Lift with sh_readycheck_unban.
	LeaveBanEnabled = true,
	LeaveBanWindow = 60,
	LeaveBanDuration = 1800,
	-- Testing only: let bot commanders activate the check (they count as ready).
	AllowBotCommanders = false,
	-- Testing only: skip the "more candidates than TargetPlayers" requirement so
	-- a solo local test activates the check.
	TestAlwaysActivate = false,
	Debug = true
}

Plugin.Phase = {
	Idle = 0,
	Commanders = 1,
	Pool = 2,
	Open = 3,
	Vote = 4,
	Waiting = 5
}

-- Pool/Open timer speed while the panel count is green on x+y (ready slot
-- holders + ready queued spectators >= TargetPlayers). Server and client both
-- derive it from the ReadyCheckState counts, so it is not networked.
Plugin.GreenTimerRate = 2

function Plugin:GetPhaseTimerRate( PhaseValue, ReadyCount, QueueReady, Needed )
	if ( PhaseValue == self.Phase.Pool or PhaseValue == self.Phase.Open )
		and ReadyCount + QueueReady >= Needed then
		return self.GreenTimerRate
	end
	return 1
end

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "ReadyCheckState", {
		Phase = "integer (0 to 7)",
		TimeLeft = "integer (0 to 4095)",
		ReadyCount = "integer (0 to 255)",
		Needed = "integer (0 to 255)",
		NotReady = "integer (0 to 255)",
		QueueReady = "integer (0 to 255)",
		Eligible = "boolean",
		IsReady = "boolean",
		-- Field slot holder (Teams/Ready Room, not commander): may use the
		-- "go to spectator" button.
		CanSpectate = "boolean",
		VotePending = "boolean"
	}, "Client" )
	self:AddNetworkMessage( "ReadyFlag", { SteamID = "string (16)", Ready = "boolean" }, "Client" )
	self:AddNetworkMessage( "ReadyFlagsReset", {}, "Client" )
	self:AddNetworkMessage( "ReadyCheckAttention", {}, "Client" )

	self:AddNetworkMessage( "RequestReady", {}, "Server" )
	self:AddNetworkMessage( "RequestSpectate", {}, "Server" )
	self:AddNetworkMessage( "RequestReadyCheckSnapshot", {}, "Server" )
end

return Plugin
