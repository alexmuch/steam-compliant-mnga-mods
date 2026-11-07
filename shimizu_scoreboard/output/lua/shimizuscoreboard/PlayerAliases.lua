-- Client-local player aliases keyed by NS2/Steam ID.

local kAliasFile = "config://shine/SSBPlayerAliases.json"
local kMaxAliasLength = 25
local aliases = {}
local aliasesLoaded = false
local kActivityPrefixes = { "<poke> ", "<M3> " }

local function NormaliseSteamID(steamId)
    steamId = tonumber(steamId)
    return steamId and steamId > 0 and tostring(math.floor(steamId)) or nil
end

local function Trim(value)
    return string.gsub(string.gsub(value, "^%s+", ""), "%s+$", "")
end

local function LoadAliases()
    if aliasesLoaded or not Shine or not Shine.LoadJSONFile then return false end
    aliasesLoaded = true
    local data = Shine.LoadJSONFile(kAliasFile)
    if not data then return end
    if type(data) ~= "table" or data.Version ~= 1 or type(data.Aliases) ~= "table" then
        Print("[SSBAlias] Ignored invalid alias file")
        return false
    end
    local count = 0
    for steamId, alias in pairs(data.Aliases) do
        local key = NormaliseSteamID(steamId)
        if key and type(alias) == "string" and alias ~= "" and not string.find(alias, "%c") then
            aliases[key] = string.UTF8Sub(alias, 1, kMaxAliasLength)
            count = count + 1
        end
    end
    if count > 0 then Print("[SSBAlias] Loaded %d persisted alias(es)", count) end
    return true
end

local function SaveAliases()
    local ok, err = Shine.SaveJSONFile({ Version = 1, Aliases = aliases }, kAliasFile, { indent = true })
    if not ok then Print("[SSBAlias] Failed to save aliases: %s", ToString(err)) end
    return ok
end

function SSB_GetPlayerAlias(steamId)
    LoadAliases()
    local key = NormaliseSteamID(steamId)
    return key and aliases[key] or nil
end

function SSB_GetPlayerDisplayNameBySteamId(steamId, fallbackName)
    return SSB_GetPlayerAlias(steamId) or fallbackName
end

local function SplitActivityPrefix(name)
    if type(name) ~= "string" then return "", name end
    local combinedPrefix = ""
    for _ = 1, #kActivityPrefixes do
        local matched = false
        for i = 1, #kActivityPrefixes do
            local prefix = kActivityPrefixes[i]
            if string.sub(name, 1, #prefix) == prefix then
                combinedPrefix = combinedPrefix .. prefix
                name = string.sub(name, #prefix + 1)
                matched = true
                break
            end
        end
        if not matched then break end
    end
    return combinedPrefix, name
end

function SSB_ApplyPlayerAliasToRecord(record, steamId, realName, source)
    if type(record) ~= "table" then return record end
    local prefix, baseName = SplitActivityPrefix(realName or record.RealName or record.Name)
    -- A presentation-boundary pass may see the value previously produced by
    -- this function. Keep the authoritative name in that case rather than
    -- accidentally promoting the alias into RealName.
    if record.AliasName and baseName == record.AliasName and record.RealName then
        baseName = record.RealName
    end
    record.RealName = baseName
    record.AliasName = SSB_GetPlayerDisplayNameBySteamId(steamId or record.SteamId, baseName)
    record.Name = prefix .. record.AliasName
    record.SSBAliasSteamId = steamId or record.SteamId
    record.SSBAliasOutputName = record.Name
    return record
end

function SSB_EnsurePlayerAliasOnRecord(record, source)
    if type(record) ~= "table" or not record.SteamId or record.SteamId <= 0 then return record end
    if record.SSBAliasSteamId == record.SteamId and record.SSBAliasOutputName == record.Name then
        return record
    end
    return SSB_ApplyPlayerAliasToRecord(record, record.SteamId, record.Name, source)
end

function SSB_GetPlayerDisplayName(clientIndex, fallbackName)
    local record = Scoreboard_GetPlayerRecord and Scoreboard_GetPlayerRecord(clientIndex)
    local steamId = record and record.SteamId
    if not steamId and GetSteamIdForClientIndex then steamId = GetSteamIdForClientIndex(clientIndex) end
    return SSB_GetPlayerDisplayNameBySteamId(steamId, fallbackName or (record and record.Name))
end

function SSB_GetPlayerDisplayNameByRealName(realName)
    if type(realName) ~= "string" or not ScoreboardUI_GetAllScores then return realName end
    local records = ScoreboardUI_GetAllScores()
    local displayName
    for i = 1, #records do
        local record = records[i]
        if record.RealName == realName then
            -- Never guess when another mod/server presents duplicate names.
            local recordDisplayName = record.AliasName or record.Name
            if displayName and displayName ~= recordDisplayName then return realName end
            displayName = recordDisplayName
        end
    end
    return displayName or realName
end

local function IsWordByte(byte)
    return byte and (byte >= 128 or byte == 95 or byte >= 48 and byte <= 57 or
        byte >= 65 and byte <= 90 or byte >= 97 and byte <= 122)
end

local function ReplaceWholeName(text, realName, displayName)
    if realName == "" or realName == displayName then return text end
    local output = {}
    local cursor = 1
    local searchFrom = 1
    local realLength = #realName
    local requireLeftBoundary = IsWordByte(string.byte(realName, 1))
    local requireRightBoundary = IsWordByte(string.byte(realName, realLength))

    while true do
        local first, last = string.find(text, realName, searchFrom, true)
        if not first then break end
        local leftMatches = not requireLeftBoundary or first == 1 or not IsWordByte(string.byte(text, first - 1))
        local rightMatches = not requireRightBoundary or last == #text or not IsWordByte(string.byte(text, last + 1))
        if leftMatches and rightMatches then
            output[#output + 1] = string.sub(text, cursor, first - 1)
            output[#output + 1] = displayName
            cursor = last + 1
        end
        searchFrom = last + 1
    end

    if cursor == 1 then return text end
    output[#output + 1] = string.sub(text, cursor)
    return table.concat(output)
end

-- Text search can't tell a name from ordinary text, so skip names that would
-- match it: a player called "0" replaced every standalone 0 in system lines.
-- Needs 3+ bytes and a letter (any non-ASCII byte counts, so CJK names pass).
local function IsSearchableName(name)
    return #name >= 3 and string.find(name, "[%a\128-\255]") ~= nil
end

-- Presentation-only fallback for UI strings whose network message supplies a
-- name but no Steam ID (notably vanilla concede/eject broadcasts). MNGA's own
-- messages send Steam IDs instead (MNGA_NotifyNames) and never come through here.
function SSB_ApplyPlayerAliasesToText(text)
    if type(text) ~= "string" or not ScoreboardUI_GetAllScores then return text end
    local records = ScoreboardUI_GetAllScores()
    local replacements = {}
    local names = {}
    for i = 1, #records do
        local record = records[i]
        local displayName = record.AliasName or record.Name
        if record.RealName and displayName and record.RealName ~= displayName
                and IsSearchableName(record.RealName) then
            local previous = names[record.RealName]
            if previous == nil then
                names[record.RealName] = displayName
            elseif previous ~= displayName then
                names[record.RealName] = false
            end
        end
    end
    for realName, displayName in pairs(names) do
        if displayName then replacements[#replacements + 1] = { realName, displayName } end
    end
    table.sort(replacements, function(a, b) return #a[1] > #b[1] end)
    for i = 1, #replacements do
        text = ReplaceWholeName(text, replacements[i][1], replacements[i][2])
    end
    return text
end

function SSB_SetPlayerAlias(steamId, value)
    LoadAliases()
    local key = NormaliseSteamID(steamId)
    if not key then return false, "Invalid player ID." end
    if type(value) ~= "string" then return false, "Alias must be text." end
    value = Trim(value)
    if string.find(value, "%c") then return false, "Alias cannot contain control characters." end
    if string.UTF8Length(value) > kMaxAliasLength then
        return false, string.format("Alias must be %d characters or fewer.", kMaxAliasLength)
    end
    local previous = aliases[key]
    aliases[key] = value ~= "" and value or nil
    if not SaveAliases() then
        aliases[key] = previous
        return false, "Could not save the alias file."
    end
    if Scoreboard_ReloadPlayerData then Scoreboard_ReloadPlayerData() end
    return true
end

LoadAliases()

-- Improved Chat consumes this public presentation event. Mutating its display
-- DTO is intentionally separate from the engine network callback and payload.
if Shine and Shine.Hook and Shine.Hook.Add then
    Shine.Hook.Add("OnChatMessageReceived", "SSBAliasChatPresentation", function(data)
        if data.SteamID and data.SteamID > 0 then
            data.Name = SSB_GetPlayerDisplayNameBySteamId(data.SteamID, data.Name)
        end
    end, Shine.Hook.MAX_PRIORITY)
end
