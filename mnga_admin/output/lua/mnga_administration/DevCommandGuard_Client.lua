-- Vanilla client debug commands with no permission check. dbg_locgates runs
-- "tests 1", "spectate" and "nav_debug", then draws location gates every 0.15 s
-- until map change. bot_test* run "tests 1"/"cheats 1", "spectate" and bot
-- commands. Gate the command itself, so typing it, a bind someone handed out and
-- a server-sent Shine_Command are all blocked the same way. Wrap Event.Hook
-- before the commands register, because a second hook could not stop the vanilla
-- one from running. See cheats-bypass-review.md.
if not Client or gMNGADevCommandGuardClient then return end
gMNGADevCommandGuardClient = true

local kGuardedCommands = {
    ["Console_dbg_locgates"] = true,
    ["Console_bot_test"] = true,
    ["Console_bot_test_comm"] = true,
    ["Console_bot_test_lf"] = true,
}
local kMaxLoggedTextLength = 200

-- Listen-server host, or a server that already has cheats, tests or dev mode on.
local function CanRun()
    if Shared.GetCheatsEnabled() or Shared.GetTestsEnabled() or Shared.GetDevMode() then
        return true
    end
    local gameInfo = GetGameInfoEntity and GetGameInfoEntity()
    return gameInfo ~= nil and not gameInfo:GetIsDedicated()
end

local VanillaEventHook = Event.Hook
Event.Hook = function(name, callback, ...)
    if not kGuardedCommands[name] then
        return VanillaEventHook(name, callback, ...)
    end

    return VanillaEventHook(name, function(...)
        local allowed = CanRun()
        local text = table.concat({ ... }, " "):sub(1, kMaxLoggedTextLength)
        Print("%s", string.format("[devcmdguard] %s client command=%s cheats=%s tests=%s dev=%s text=%s",
            allowed and "allowed" or "blocked",
            name,
            tostring(Shared.GetCheatsEnabled()),
            tostring(Shared.GetTestsEnabled()),
            tostring(Shared.GetDevMode()),
            text))
        if allowed then
            return callback(...)
        end
    end, ...)
end
