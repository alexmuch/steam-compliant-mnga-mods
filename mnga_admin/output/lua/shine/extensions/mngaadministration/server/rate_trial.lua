-- Loaded only by sh_mngarates. No hooks/timers are installed until start.
-- All source_confirmed_gen* packages are immutable; this file only changes
-- transient native settings and observes existing native performance records.
local Plugin = ...
local build = "mnga-rate-trial-20260925-v1"
local expectedGen6 = "vanillaopt-gen6-cd4d1ed44068a5e7"

-- Retain restoration ownership across a plugin reload in the same map VM.
if MNGARateTrial then
    function Plugin:MNGARateTrialCommand(...) MNGARateTrial.Dispatch(...) end
    function Plugin:CleanupMNGARateTrial() MNGARateTrial.Cleanup() end
    return
end
local R = { run = 0, session = tostring(Shared.GetSystemTimeReal()) }
local clock = Shared.GetSystemTimeReal
local active, pending, restore
local updateHook, mapHook, updateAttached, mapAttached
local lastStamp, lastFresh, nextPoll
local optionalReported = {}
local baseline = { tick = 30, move = 26, send = 20, interp = 100 }
local function Log(format, ...)
    Print("[mnga_rates] build=%s session=%s run=%d %s", build, R.session, R.run, string.format(format, ...))
end
local function Finite(x)
    return type(x) == "number" and x == x and x > -math.huge and x < math.huge
end
local metrics = {
    { "stamp", "GetTimestamp" }, { "duration", "GetDurationMs" },
    { "tick", "GetTickrate" }, { "move", "GetMoverate" }, { "send", "GetSendrate" },
    { "interp", "GetInterpMs" }, { "interval", "GetUpdateIntervalMs" },
    { "idle", "GetTimeSpentIdling" }, { "movesMs", "GetTimeSpentOnMoves" },
    { "entitiesMs", "GetTimeSpentOnUpdate" }, { "moves", "GetMovesProcessed" },
    { "updates", "GetNumEntitiesUpdated" }, { "entities", "GetEntityCount" },
    { "iwarn", "GetNumInterpWarns" }, { "ifail", "GetNumInterpFails" }
}
local function ReadPerf()
    local p = Shared.GetServerPerformanceData()
    local row = {}
    for i = 1, #metrics do
        local key, name = metrics[i][1], metrics[i][2]
        assert(type(p[name]) == "function", "missing_metric_"..name)
        local value = p[name](p)
        assert(Finite(value), "invalid_metric_"..name)
        row[key] = value
    end
    local fn = p.GetIncompleteCount
    local ok, value = false, nil
    if type(fn) == "function" then ok, value = pcall(fn, p) end
    row.incomplete = ok and Finite(value) and value or "unavailable"
    if row.incomplete == "unavailable" and not optionalReported.incomplete then
        optionalReported.incomplete = true
        Log("metric_unavailable name=GetIncompleteCount required=false")
    end
    return row
end
local function Same(a, b)
    return a.tick == b.tick and a.move == b.move and a.send == b.send and a.interp == b.interp
end
local function Plan(tick, move, send, seconds)
    if tick == nil and move == nil and send == nil then tick, move, send = 36, 32, 24 end
    tick, move, send = tonumber(tick), tonumber(move), tonumber(send)
    seconds = seconds == nil and 300 or tonumber(seconds)
    for _, value in pairs({ tick = tick or false, move = move or false, send = send or false, seconds = seconds or false }) do
        if not Finite(value) or value % 1 ~= 0 then return nil, "supply_all_three_integer_rates_and_optional_integer_seconds" end
    end
    if tick < 30 or tick > 60 or move < 26 or move > 52 or send < 20 or send > 40 then
        return nil, "bounds_tick30_to60_move26_to52_send20_to40"
    end
    if tick < move or move < send then return nil, "require_tick_greater_or_equal_move_greater_or_equal_send" end
    if seconds < 60 or seconds > 600 then return nil, "seconds_per_window_60_to600" end
    if tick == 30 and move == 26 and send == 20 then return nil, "target_equals_baseline" end
    local plan = { { label = "baseline_before", tick = 30, move = 26, send = 20, interp = 100, seconds = seconds } }
    local function Add(label, t, m, s)
        local point = { label = label, tick = t, move = m, send = s, interp = 100, seconds = seconds }
        if not Same(point, plan[#plan]) then plan[#plan + 1] = point end
    end
    Add("tick_only", tick, 26, 20)
    Add("tick_move", tick, move, 20)
    Add("tick_move_send", tick, move, send)
    Add("baseline_after", 30, 26, 20)
    return plan, "ok"
end
local function Gen6Ready()
    if not Server.IsDedicated() or not jit or jit.os ~= "Linux" then
        return false, "linux_dedicated_required"
    end
    if NS2RateQ or SO2Perf or SO2Runtime or SO2PoseRuntime or SO2LocalLab or NO1 or NO1Hotpaths then
        return false, "unmount_experiment_packages_use_production_gen6"
    end
    if VanillaOptGen6Build ~= expectedGen6 then return false, "production_gen6_identity_missing" end
    local g, p = VanillaOptGen5, VanillaOptGen6Pose
    if not g or not g.sort or not g.flame then return false, "gen5_lanes_not_active" end
    if not p or not p.active or p.phase ~= "direct" then
        return false, "gen6_not_direct_wait_for_startup_audit_then_retry_status"
    end
    return true, "ok"
end
local function Population()
    local humans, bots, spectators = 0, 0, 0
    local clients = Shine.GetAllClients()
    for i = 1, #clients do
        local client = clients[i]
        if client:GetIsVirtual() then bots = bots + 1
        else
            humans = humans + 1
            local player = client:GetControllingPlayer()
            if player and player:GetTeamNumber() == kSpectatorIndex then spectators = spectators + 1 end
        end
    end
    return humans, bots, spectators
end
local function LogPerf(p, phase)
    local h, b, s = Population()
    local rules = GetGamerules()
    Log("perf phase=%s label=%s stamp=%.6f duration_ms=%s tick=%s move=%s send=%s interp_ms=%s interval_ms=%s idle_ms=%s moves_ms=%s entities_ms=%s moves=%s updates=%s entities=%s iwarn=%s ifail=%s incomplete=%s humans=%d bots=%d human_spectators=%d game_started=%s",
        phase, active and active.target.label or "idle", p.stamp, tostring(p.duration),
        tostring(p.tick), tostring(p.move), tostring(p.send), tostring(p.interp), tostring(p.interval),
        tostring(p.idle), tostring(p.movesMs), tostring(p.entitiesMs), tostring(p.moves),
        tostring(p.updates), tostring(p.entities), tostring(p.iwarn), tostring(p.ifail),
        tostring(p.incomplete), h, b, s, tostring(rules and rules:GetGameStarted()))
end
local function Detach()
    if updateAttached then
        Event.RemoveHook("UpdateServer", updateHook)
        updateAttached = false
    end
    if mapAttached then
        Event.RemoveHook("MapPreLoad", mapHook)
        mapAttached = false
    end
    Log("monitor_detached idle_polling=0")
end
local function Issue(target, restoring, attempt)
    -- Record ownership BEFORE the first write, so a partial command failure
    -- still has a restoration deadline and cannot strand an untracked trial.
    pending = { target = target, restoring = restoring, requested = Shared.GetTime(),
        deadline = clock() + 10, attempt = attempt or 1 }
    if target.tick > baseline.tick then Shared.ConsoleCommand("tickrate "..target.tick) end
    Shared.ConsoleCommand("sendrate 20")
    Shared.ConsoleCommand("mr "..target.move)
    Shared.ConsoleCommand("sendrate "..target.send)
    Shared.ConsoleCommand("tickrate "..target.tick)
    Log("rates_requested tick=%d move=%d send=%d interp_untouched_ms=%d restoring=%s attempt=%d",
        target.tick, target.move, target.send, target.interp, tostring(restoring), pending.attempt)
end
local function Summary(reason)
    if not active or active.summaryPrinted then return end
    active.summaryPrinted = true
    Log("window_end label=%s reason=%s samples=%d duration_ms=%.0f idle_ms=%.0f moves_ms=%.0f entities_ms=%.0f moves=%.0f updates=%.0f iwarn=%.0f ifail=%.0f",
        active.target.label, reason, active.samples, active.duration, active.idle, active.movesMs,
        active.entitiesMs, active.moves, active.updates, active.iwarn, active.ifail)
end
local function Stop(reason)
    Summary(reason)
    active = nil
    R.lastReason = reason
    if restore then
        if not pending or not pending.restoring then Issue(restore, true) end
    else
        pending = nil
        Detach()
    end
    Log("stopped reason=%s restoration_pending=%s", reason, tostring(restore ~= nil))
end
local function Advance()
    if active.index > 0 then
        if active.duration < active.target.seconds * 800 then
            Stop("insufficient_complete_native_coverage"); return
        end
        Summary("complete")
    end
    active.index = active.index + 1
    local target = active.points[active.index]
    if not target then
        Log("sequence_complete qualification=operator_review_required ifail_total=%.0f", active.totalFails)
        Stop("sequence_complete"); return
    end
    active.target = target
    active.phase = "verify"
    active.summaryPrinted = false
    active.samples, active.duration, active.idle, active.movesMs, active.entitiesMs = 0, 0, 0, 0, 0
    active.moves, active.updates, active.iwarn, active.ifail = 0, 0, 0, 0
    active.tickBad, active.idleBad = 0, 0
    Issue(target, false)
end
local function Tick()
    local now = clock()
    if active and now > active.deadline then Stop("sequence_watchdog") end
    if pending and now > pending.deadline then
        if not pending.restoring then Stop("rate_verification_timeout")
        elseif pending.attempt < 3 then Issue(restore, true, pending.attempt + 1)
        else
            Log("RESTORE_FAILED tick=30 move=26 send=20 interp_expected_ms=100 action=sh_mngarates_stop_or_native_rollback")
            pending = nil -- Keep restore latched; start remains blocked, stop retries.
            Detach()
            return
        end
    end
    if now < (nextPoll or 0) then return end
    nextPoll = now + 0.5
    local p = ReadPerf()
    if p.duration > 0 and p.stamp ~= lastStamp then
        lastStamp, lastFresh = p.stamp, now
        local start = p.stamp - p.duration / 1000
        if pending and start >= pending.requested and Same(p, pending.target) then
            if pending.restoring then
                Log("restored_verified tick=%d move=%d send=%d interp_ms=%d", p.tick, p.move, p.send, p.interp)
                restore, pending = nil, nil
                Detach()
                return
            end
            pending = nil
            active.phase, active.due = "warm", now + 5
            Log("rates_verified label=%s tick=%d move=%d send=%d", active.target.label, p.tick, p.move, p.send)
        end
        if active then
            local ready, reason = Gen6Ready()
            if not ready then Stop(reason); return end
            local complete = active.phase == "measure" and start >= active.measureStart
            LogPerf(p, complete and "measure" or active.phase == "measure" and "boundary" or active.phase)
            if not pending and not Same(p, active.target) then Stop("rates_or_interp_changed"); return end
            if complete then
                active.samples = active.samples + 1
                for _, key in ipairs({ "duration", "idle", "movesMs", "entitiesMs", "moves", "updates", "iwarn", "ifail" }) do
                    active[key] = active[key] + p[key]
                end
                active.totalFails = active.totalFails + p.ifail
                active.tickBad = p.interval > 1000 / active.target.tick / 0.85 and active.tickBad + 1 or 0
                active.idleBad = p.idle / p.duration < 0.10 and active.idleBad + 1 or 0
                if p.ifail > 0 then
                    -- A many-client aggregate is not comparable to the private
                    -- one-human ifail streak. Retain counts; do not invent a
                    -- universal multiplayer failure threshold from that rule.
                    Log("interp_event label=%s count=%.0f total=%.0f policy=record_operator_review", active.target.label, p.ifail, active.totalFails)
                end
                if active.tickBad >= 3 then Stop("three_tick_interval_samples"); return end
                if active.idleBad >= 3 then Stop("three_idle_below_10pct_samples"); return end
            end
        end
    elseif active and now - lastFresh > 5 then Stop("stale_performance_data"); return end
    if active and not pending then
        if active.phase == "warm" and now >= active.due then
            active.phase, active.measureStart = "measure", Shared.GetTime()
            active.due = now + active.target.seconds
            Log("window_begin label=%s seconds=%d", active.target.label, active.target.seconds)
        elseif active.phase == "measure" and now >= active.due then Advance() end
    end
end
updateHook = function()
    local ok, err = pcall(Tick)
    if not ok then
        -- Do not restart the restore deadline on each failed telemetry read.
        if not R.reportedError then Log("runner_error=%s", tostring(err)); R.reportedError = true end
        if active or restore and not pending then
            local stopped, stopError = pcall(Stop, "runner_error")
            if not stopped then Log("restore_request_error=%s", tostring(stopError)) end
        end
    end
end
mapHook = function()
    if active or restore then
        local ok, err = pcall(Stop, "map_preload")
        Log("map_change_restore_requested=%s verified=false check_native_baseline_on_new_map=1 detail=%s", tostring(ok), tostring(err))
        -- The old VM cannot verify new-map telemetry. Never report a pass here.
        active, pending = nil, nil
        Detach()
    end
end
local function Attach()
    if not updateAttached then Event.Hook("UpdateServer", updateHook); updateAttached = true end
    if not mapAttached then Event.Hook("MapPreLoad", mapHook); mapAttached = true end
end
local function Preflight()
    if type(clock) ~= "function" or type(Event.RemoveHook) ~= "function" then
        return nil, "clock_or_detach_api_unavailable"
    end
    local ready, reason = Gen6Ready()
    if not ready then return nil, reason end
    local ok, p = pcall(ReadPerf)
    if not ok then return nil, tostring(p) end
    local age = Shared.GetTime() - p.stamp
    if p.duration <= 0 or age < -0.1 or age >= 5 then return nil, "fresh_native_telemetry_required" end
    if not Same(p, baseline) then return nil, "baseline_must_be_30_26_20_interp100" end
    return p, "ok"
end
function R.Command(action, tick, move, send, seconds)
    action = string.lower(tostring(action or "status"))
    if action ~= "start" and (tick ~= nil or move ~= nil or send ~= nil or seconds ~= nil) then
        Log("rejected=rate_parameters_only_valid_with_start"); return
    end
    if action == "status" then
        local p, reason = Preflight()
        Log("status start_ready=%s reason=%s active=%s restoration_pending=%s monitor_attached=%s last_reason=%s",
            tostring(p ~= nil and not active and not restore and not pending), reason,
            tostring(active ~= nil), tostring(restore ~= nil), tostring(updateAttached == true), tostring(R.lastReason))
        local ok, current = pcall(ReadPerf)
        if ok then LogPerf(current, "status") else Log("telemetry_error=%s", tostring(current)) end
        Shared.ConsoleCommand("bwlimit")
    elseif action == "start" then
        if active or pending or restore then Log("rejected=busy_or_restore_pending use=sh_mngarates_stop"); return end
        local points, planReason = Plan(tick, move, send, seconds)
        if not points then Log("start_rejected reason=%s rates_untouched=1", planReason); return end
        local p, reason = Preflight()
        if not p then Log("start_rejected reason=%s rates_untouched=1", reason); return end
        local ok, err = pcall(Attach)
        if not ok then Detach(); Log("start_rejected hook_install=%s rates_untouched=1", tostring(err)); return end
        R.run = R.run + 1
        R.reportedError = false
        restore = { tick = p.tick, move = p.move, send = p.send, interp = p.interp }
        lastStamp, lastFresh, nextPoll = p.stamp, clock(), nil
        local totalSeconds = #points * points[1].seconds
        active = { points = points, index = 0, target = points[1], samples = 0, duration = 0, idle = 0,
            movesMs = 0, entitiesMs = 0, moves = 0, updates = 0, iwarn = 0, ifail = 0,
            totalFails = 0, deadline = clock() + totalSeconds + 180 }
        local target = points[#points - 1]
        Log("sequence_started windows=%d seconds_per_window=%d measured_seconds=%d target_tick=%d target_move=%d target_send=%d interp_bw_held=1 persistence=none joins=allowed",
            #points, points[1].seconds, totalSeconds, target.tick, target.move, target.send)
        for i = 1, #points do
            local point = points[i]
            Log("plan index=%d label=%s tick=%d move=%d send=%d seconds=%d", i, point.label, point.tick, point.move, point.send, point.seconds)
        end
        Log("stop_policy tick_below_85pct=3_records idle_below_10pct=3_records interp=record_manual_review")
        local started, startError = pcall(Advance)
        if not started then
            Log("start_error=%s", tostring(startError))
            local stopped, stopError = pcall(Stop, "start_error")
            if not stopped then Log("restore_request_error=%s", tostring(stopError)) end
        end
    elseif action == "stop" then
        if restore then
            Attach()
            pending = nil -- Explicit retry after RESTORE_FAILED, with a new deadline.
        end
        Stop("operator")
    else Log("usage=sh_mngarates_status_or_start_[tick_move_send_[seconds_per_window]]_or_stop") end
end
function R.Cleanup()
    if active or restore then
        -- The standalone active hook remains only until baseline is verified.
        local ok, err = pcall(function() Attach(); Stop("plugin_cleanup") end)
        if not ok then Log("cleanup_restore_error=%s", tostring(err)) end
    end
end
function R.Dispatch(...)
    local ok, err = pcall(R.Command, ...)
    if not ok then
        Log("command_error=%s", tostring(err))
        if active or restore then
            local stopped, stopError = pcall(Stop, "command_error")
            if not stopped then Log("restore_request_error=%s", tostring(stopError)) end
        end
    end
end
MNGARateTrial = R
function Plugin:MNGARateTrialCommand(...) R.Dispatch(...) end
function Plugin:CleanupMNGARateTrial() R.Cleanup() end
Log("module_loaded hooks_attached=0 activation=explicit_command production_gen6_unchanged=1")
