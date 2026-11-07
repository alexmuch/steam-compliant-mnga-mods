
Log("[NNSLBadges] NNSL SpecialSkillTierRecipients Registered.")

Script.Load("lua/UnorderedSet.lua")

-- Adding NSL skill tier icons.
local kGoldTexture   = PrecacheAsset("ui/badges/mnga_mvp_animated.dds")
local kSilverTexture = PrecacheAsset("ui/badges/mnga_debug_animated.dds")
local kBronzeTexture = PrecacheAsset("ui/badges/mnga_mvp_animated.dds")

-- local kAnimatedShader = PrecacheAsset("ui/badges/nsl_open_tournament_2019_animated.surface_shader")
local kAnimatedShader = PrecacheAsset("ui/badges/mnga_mvp_animated.surface_shader")

local kGoldFrameCount = 32
local kSilverFrameCount = 32
local kBronzeFrameCount = 28

local kGoldTooltip   = "== %s =="
local kSilverTooltip = "== %s =="
local kBronzeTooltip = "== %s =="

local tournamentBadgeData = -- So it'll just update once a map change (when mods are re-loaded / updated)
{
    _empty = true,
    tournamentName = nil,

    -- Team data tables by placement/rank
    [1] = nil,
    [2] = nil,
    [3] = nil,
}


local function UpdateEmptyFlag()

    tournamentBadgeData._empty =
        tournamentBadgeData.tournamentName == nil or
        #tournamentBadgeData <= 0

end

function OnTournamentNameMessage(message)
    tournamentBadgeData.tournamentName = message.tournamentName
    NNSL_DebugLog("Received Tournament Name Message: %s", message)
    UpdateEmptyFlag()
end

function OnTeamPlacementDataMessage(message)

    local rank = message.teamPlacement
    local teamName = message.teamName
    local playerIds = string.Explode(message.playerIds, ",")

    local newData = {}
    newData.teamName = teamName
    newData.playerIds = UnorderedSet()
    for _, playerIdStr in ipairs(playerIds) do
        newData.playerIds:Add(tonumber(playerIdStr))
    end

    if kNNSLB_INSERT_OWN_ID then
        newData.playerIds:Add(Client.GetSteamId())
    end

    NNSL_DebugLog("Received TeamPlacement Message (Rank %s): %s", rank, newData)

    tournamentBadgeData[rank] = newData
    UpdateEmptyFlag()

end

-- Returns either nil (no special recipient), or a table:
--  name        Name to use for "skillTierName" field... not sure where this is actually used, just
--                  dotting my i's and crossing my t's here...
--  shader      Shader to use for this icon.
--  tex         Texture file to use.
--  frameCount (optional) Number of frames in the animation.  Sets a float parameter in the shader named "frameCount".
--  tooltip     Tooltip of the icon for the player found (includes their team name).
--  texCoords (optional)    Normalized texture coordinates to use.
--  texPixCoords (optional) Texture coordinates (in pixels) to use.
function CheckForSpecialBadgeRecipient(steamId)
    
    if steamId == nil then
        return nil
    end

    if not tournamentBadgeData then return nil end
    if tournamentBadgeData._empty then return nil end

    local tournamentName = tournamentBadgeData.tournamentName
    local result
    if tournamentBadgeData[1] and tournamentBadgeData[1].playerIds:Contains(steamId) then
        result =
        {
            name = string.format("%s Gold", tournamentName),
            shader = kAnimatedShader,
            tex = kGoldTexture,
            frameCount = kGoldFrameCount,
            tooltip = string.format(kGoldTooltip, tournamentName),
            texCoords = {0, 0, 1, 1},
        }
    elseif tournamentBadgeData[2] and tournamentBadgeData[2].playerIds:Contains(steamId) then
        result =
        {
            name = string.format("%s Silver", tournamentName),
            shader = kAnimatedShader,
            tex = kSilverTexture,
            frameCount = kSilverFrameCount,
            tooltip = string.format(kSilverTooltip, tournamentName),
            texCoords = {0, 0, 1, 1},
        }
    elseif tournamentBadgeData[3] and tournamentBadgeData[3].playerIds:Contains(steamId) then
        result =
        {
            name = string.format("%s Bronze", tournamentName),
            shader = kAnimatedShader,
            tex = kBronzeTexture,
            frameCount = kBronzeFrameCount,
            tooltip = string.format(kBronzeTooltip, tournamentName),
            texCoords = {0, 0, 1, 1},
        }
    end
    
    return result
    
end
