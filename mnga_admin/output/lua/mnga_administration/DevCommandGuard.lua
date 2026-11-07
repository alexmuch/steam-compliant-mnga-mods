-- Vanilla hooks these server console commands with no usable permission check.
-- bot_setupdev and bv_percep run "tests 1" and "cheats 1" as the server, and !
-- runs any text as Lua once cheats are on. devtrace runs "dev 1" and "dev 0" as
-- the server once cheats are on. The sh_admindebug commands are vanilla debug
-- commands any player could run: bot file reloads, bot spawn setup, bot lifeform
-- locks with a chat broadcast, perf and cyst log toggles, and log dumps.
-- sh_admindebug is our own permission, granted through Shine groups. Wrap
-- Event.Hook before the commands register, because a second hook could not stop
-- the vanilla one from running.
-- See cheats-bypass-review.md.
if not Server or gMNGADevCommandGuard then return end
gMNGADevCommandGuard = true

-- Shine permission that allows a player to run the command, false for none.
local kGuardedCommands = {
    ["Console_bot_setupdev"] = "sh_cheats",
    ["Console_bv_percep"] = "sh_cheats",
    ["Console_!"] = false,
    ["Console_devtrace"] = "sh_admindebug",
    ["Console_trace"] = "sh_admindebug",
    ["Console_bot_hotload"] = "sh_admindebug",
    ["Console_locgraph_place"] = "sh_admindebug",
    ["Console_bot_lockevolve"] = "sh_admindebug",
    ["Console_perfmon"] = "sh_admindebug",
    ["Console_perfdbg"] = "sh_admindebug",
    ["Console_cchain_debug"] = "sh_admindebug",
    ["Console_td_dumprules"] = "sh_admindebug",
    ["Console_shimizuspecdiag"] = "sh_admindebug",
    ["Console_shimizuspecdiagreset"] = "sh_admindebug",
}
local kMaxLoggedTextLength = 200
-- One chat line per player and command in this window. The 344 hotfix adds a
-- second wrapped handler, so one attempt would otherwise post twice, and a
-- player spamming the command would flood chat.
local kAnnounceCooldown = 10
local lastAnnounceTimes = {}

local function CanRun(client, permission)
    if not client or client:GetIsLocalClient() then return true end
    return permission and Shine ~= nil and Shine:HasAccess(client, permission) or false
end

local function LogAttempt(client, command, verdict, text)
    local player = client and client:GetControllingPlayer()
    Print("%s", string.format("[devcmdguard] %s command=%s steamid=%s name=%s team=%s cheats=%s tests=%s dev=%s text=%s",
        verdict,
        command,
        tostring(client and client:GetUserId() or "console"),
        tostring(player and player:GetName() or "?"),
        tostring(player and player:GetTeamNumber() or "?"),
        tostring(Shared.GetCheatsEnabled()),
        tostring(Shared.GetTestsEnabled()),
        tostring(Shared.GetDevMode()),
        tostring(text or "")))
end

-- Tells everyone in chat that a player tried a blocked command. Arguments are
-- left out, so a player cannot use the attempt to post their own text.
local function AnnounceBlocked(client, command)
    if not client or not MNGA_NotifyNames or not MNGA_Name then return end
    local key = tostring(client:GetUserId()) .. command
    local now = Shared.GetTime()
    if lastAnnounceTimes[key] and now - lastAnnounceTimes[key] < kAnnounceCooldown then return end
    lastAnnounceTimes[key] = now
    local commandName = command:gsub("^Console_", "")
    MNGA_NotifyNames(nil, 255, 80, 80, "[Guard] %s tried to run the blocked command '%s'.",
        MNGA_Name(client), commandName)
end

local VanillaEventHook = Event.Hook
Event.Hook = function(name, callback, ...)
    local permission = kGuardedCommands[name]
    if permission == nil then
        return VanillaEventHook(name, callback, ...)
    end

    return VanillaEventHook(name, function(client, ...)
        local allowed = CanRun(client, permission)
        local text = table.concat({ ... }, " "):sub(1, kMaxLoggedTextLength)
        LogAttempt(client, name, allowed and "allowed" or "blocked", text)
        if allowed then
            return callback(client, ...)
        end
        AnnounceBlocked(client, name)
        -- Workshop 344 hotfix (3558697165) arms gUWEHotfixConsoleBlock before these
        -- commands and clears it in a handler that registers after this wrap, so a
        -- block here would also skip the clear and leave cheats/tests/dev sets and
        -- loadstring refused server-wide. Nothing ran, so clearing it is safe.
        if gUWEHotfixConsoleBlock then
            gUWEHotfixConsoleBlock = false
        end
    end, ...)
end

-- Vanilla logs neither command, and bot_setupdev is not a proven route to cheats.
-- Log-only: a second hook leaves vanilla behaviour alone. steamid=console on
-- autobuild means the server issued it, as bot_setupdev does. The client-side
-- dbg_locgates sends "tests 1", "spectate" and "nav_debug" to the server; if
-- nav_debug reaches Lua here, the steamid shows who ran it. No line proves
-- nothing, because the engine may handle nav_debug before Lua sees it.
for _, command in ipairs({ "Console_autobuild", "Console_endgame", "Console_nav_debug" }) do
    VanillaEventHook(command, function(client)
        LogAttempt(client, command, "seen")
    end)
end
