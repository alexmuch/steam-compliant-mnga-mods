-- MNGA contextual ping: client side mark cache + world highlight (alien viewers).
-- Post-hook on lua/Player_Client.lua (client VM only).
--
-- Marks come from the local team's TeamInfo (TeamInfoMultiPing.lua). While a
-- mark is active, alien viewers see its target (and its child models, e.g. held weapons) gets an
-- additive glow material (cinematics/vfx_materials/mnga_contextping_highlight):
-- a thick fresnel rim in the pinger's ping colour. It is part of the model's
-- own rendering, so walls hide it (unlike EquipmentOutline/HiveVision, which
-- draw through geometry). Marines pinged by aliens glow ping-red and only
-- while sighted by aliens. Marine viewers get the target icon instead
-- (ContextPingTargetIcon_Client.lua).
--
-- See .claude/docs/contextual-ping.md.

if not Client or Predict then
    return
end

Script.Load("lua/mnga_administration/ContextPingShared.lua")

-- ---------------------------------------------------------------------------
-- Active mark cache (rebuilt at most once per frame). Also used by
-- ContextPingMapBlip_Client.lua (red blips) and GUIMinimapMultiPing.lua (names).
-- ---------------------------------------------------------------------------

local cacheTime = -1
local cacheMarks = {}       -- array of { slot, targetId, tier, time }
local cacheByTarget = {}    -- targetId -> mark
local cacheTeamInfo

local function GetLocalTeamInfo(player)
    local teamNumber = player:GetTeamNumber()
    if teamNumber ~= kTeam1Index and teamNumber ~= kTeam2Index then
        return nil
    end
    local teamInfos = GetEntitiesForTeam("TeamInfo", teamNumber)
    return teamInfos[1]
end

-- Returns marks (array), marksByTargetId, teamInfo. Do not modify the tables.
function MNGA_ContextPing_GetActiveMarks()

    local now = Shared.GetTime()
    if now == cacheTime then
        return cacheMarks, cacheByTarget, cacheTeamInfo
    end
    cacheTime = now

    for i = #cacheMarks, 1, -1 do
        cacheMarks[i] = nil
    end
    for targetId in pairs(cacheByTarget) do
        cacheByTarget[targetId] = nil
    end
    cacheTeamInfo = nil

    local player = Client.GetLocalPlayer()
    local teamInfo = player and GetLocalTeamInfo(player)
    if not teamInfo or not teamInfo.GetMarkCount then
        return cacheMarks, cacheByTarget, nil
    end
    cacheTeamInfo = teamInfo

    for slot = 1, teamInfo:GetMarkCount() do
        local targetId = teamInfo:GetMarkTarget(slot)
        local markTime = teamInfo:GetMarkTime(slot)
        if targetId ~= Entity.invalidId and markTime > 0 and now - markTime < kContextMarkDuration then
            local mark = { slot = slot, targetId = targetId, tier = teamInfo:GetMarkOwnerTier(slot), time = markTime }
            cacheMarks[#cacheMarks + 1] = mark
            cacheByTarget[targetId] = mark
        end
    end

    return cacheMarks, cacheByTarget, teamInfo

end

function MNGA_ContextPing_IsTargetMarked(entityId)
    if not entityId or entityId == Entity.invalidId then
        return false
    end
    local marks, byTarget = MNGA_ContextPing_GetActiveMarks()
    return #marks > 0 and byTarget[entityId] ~= nil
end

-- ---------------------------------------------------------------------------
-- World highlight
-- ---------------------------------------------------------------------------

local kHighlightMaterial = PrecacheAsset("cinematics/vfx_materials/mnga_contextping_highlight.material")

-- Shader tuning (sent to the material on creation; see the .surface_shader).
-- rimPower: higher = rim hugs the silhouette edge more tightly (lower = thicker,
-- spreads over the body). rimStrength = rim brightness. fillStrength = whole-body
-- tint (0 = edges only). pulse* = extra brightness right after a (re)ping.
-- Parasite-like whole-body glow.
local kHighlightProfile = { rimPower = 1.25, rimStrength = 4.0, fillStrength = 0.1, pulseStrength = 1.5, pulseDuration = 0.75 }

-- Category 1 (unknown/bot/tier 1-4) stays green; categories 2-4 use the
-- MNGA ping colours of tiers 5, 6 and 7 (blue, purple, red).
local kCategoryOneColor = Color(0.2, 1, 0.2, 1)
local kFallbackCategoryColors = { [2] = Color(0x70/255, 0xC1/255, 0xF3/255, 1), [3] = Color(0x83/255, 0x49/255, 0xE9/255, 1), [4] = Color(0xF2/255, 0x2B/255, 0x2F/255, 1) }
local kCategoryTier = { [2] = 5, [3] = 6, [4] = 7 }

local function GetCategoryColor(category)
    if category <= 1 then
        return kCategoryOneColor
    end
    return (MNGA_GetSkillTierColor and MNGA_GetSkillTierColor(kCategoryTier[category])) or kFallbackCategoryColors[category]
end

-- also used by the marine target icon (ContextPingTargetIcon_Client.lua)
MNGA_ContextPing_GetCategoryColor = GetCategoryColor

-- alien-pinged marines: always ping red
local function GetEnemyPlayerColor()
    return GetCategoryColor(4)
end

-- targetId -> { material, color, startTime, attached = { [entityId] = model }, seen = {} }
local highlights = {}

local function DetachStale(state, all)
    for entityId, model in pairs(state.attached) do
        if all or not state.seen[entityId] then
            -- only touch the model if the entity still owns it; a replaced or
            -- destroyed model took the material with it
            local ent = Shared.GetEntity(entityId)
            if ent and ent._renderModel == model then
                model:RemoveMaterial(state.material)
            end
            state.attached[entityId] = nil
        end
    end
end

local function AttachTree(state, ent)
    if HasMixin(ent, "Model") then
        local model = ent._renderModel
        if model and model:GetZone() ~= RenderScene.Zone_ViewModel then
            local entityId = ent:GetId()
            if state.attached[entityId] ~= model then
                model:AddMaterial(state.material)
                state.attached[entityId] = model
            end
            state.seen[entityId] = true
        end
    end
    for i = 1, ent:GetNumChildren() do
        AttachTree(state, ent:GetChildAtIndex(i - 1))
    end
end

local function SetMaterialColor(state, color)
    state.color = color
    state.material:SetParameter("glowColor", Vector(color.r, color.g, color.b))
end

local function CreateHighlight(color, startTime)
    local profile = kHighlightProfile
    local material = Client.CreateRenderMaterial()
    material:SetMaterial(kHighlightMaterial)
    material:SetParameter("rimPower", profile.rimPower)
    material:SetParameter("rimStrength", profile.rimStrength)
    material:SetParameter("fillStrength", profile.fillStrength)
    material:SetParameter("pulseStrength", profile.pulseStrength)
    material:SetParameter("pulseDuration", profile.pulseDuration)
    material:SetParameter("startTime", startTime)
    local state = { material = material, startTime = startTime, attached = {}, seen = {} }
    SetMaterialColor(state, color)
    return state
end

local function DestroyHighlight(targetId)
    local state = highlights[targetId]
    if state then
        DetachStale(state, true)
        Client.DestroyRenderMaterial(state.material)
        highlights[targetId] = nil
    end
end

local desired = {}

local function UpdateHighlights()

    local marks = MNGA_ContextPing_GetActiveMarks()
    if #marks == 0 and next(highlights) == nil then
        return
    end

    local player = Client.GetLocalPlayer()
    local validViewer = player and player:GetTeamNumber() == kTeam2Index

    for targetId in pairs(desired) do
        desired[targetId] = nil
    end

    if validViewer then

        for i = 1, #marks do

            local mark = marks[i]
            local ent = Shared.GetEntity(mark.targetId)
            if ent then

                local show = true
                local color
                if ent:isa("Player") and ent:GetTeamNumber() ~= kTeam2Index then
                    -- alien-pinged marine: only while aliens can see it
                    show = not HasMixin(ent, "LOS") or ent:GetIsSighted()
                    color = GetEnemyPlayerColor()
                else
                    color = GetCategoryColor(MNGA_ContextPing_GetTierCategory(mark.tier))
                end

                if show then

                    desired[mark.targetId] = true

                    local state = highlights[mark.targetId]
                    if not state then
                        state = CreateHighlight(color, mark.time)
                        highlights[mark.targetId] = state
                    else
                        if state.color ~= color then
                            SetMaterialColor(state, color)
                        end
                        if state.startTime ~= mark.time then
                            -- refreshed mark: replay the brightness pulse
                            state.startTime = mark.time
                            state.material:SetParameter("startTime", mark.time)
                        end
                    end

                    -- follow model changes and children (weapons) every frame
                    for entityId in pairs(state.seen) do
                        state.seen[entityId] = nil
                    end
                    AttachTree(state, ent)
                    DetachStale(state, false)

                end

            end

        end

    end

    for targetId in pairs(highlights) do
        if not desired[targetId] then
            DestroyHighlight(targetId)
        end
    end

end

Event.Hook("UpdateRender", UpdateHighlights)

