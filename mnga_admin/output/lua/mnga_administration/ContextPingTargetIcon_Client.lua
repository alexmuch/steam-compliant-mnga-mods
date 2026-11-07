-- MNGA contextual ping: marine-side target icon. Post-hook on
-- lua/Player_Client.lua (client VM only).
--
-- Marine viewers do not get the world glow (it felt like an unfair advantage).
-- Instead every active mark shows the same screen-space icon the marine
-- commander's attack order shows on its target (GUIWaypoints final waypoint:
-- ui/buildmenu.dds order icon, distance scaling, bounce, crosshair fade (to
-- kMNGAContextPingIconMinAlpha, not 0) and the off-screen edge arrow), tinted
-- with the pinger's tier category colour.
-- Enemy targets use the Attack icon, friendly structures the Defend icon.
-- Up to kContextMarkCount icons at once; marks come from
-- MNGA_ContextPing_GetActiveMarks (ContextPingHighlight_Client.lua).
--
-- See .claude/docs/contextual-ping.md.

if not Client or Predict then
    return
end

Script.Load("lua/mnga_administration/ContextPingShared.lua")

local kIconTexture = "ui/buildmenu.dds"
local kArrowTexture = PrecacheAsset("ui/marinewaypoint_arrow.dds")

-- Values copied from GUIWaypoints / PlayerUI_GetFinalWaypointInScreenspace.
local kIconSize = 128               -- GUIScale'd, times the distance scale
local kHeightOffset = 1.5           -- field players: icon 1.5m above the origin
local kMaxScaleDistance = 25
local kMinScale = 0.5
local kCommanderScale = 0.3
local kScreenBorder = 0.18          -- off-screen clamp border (fraction of screen)
local kArrowSize = 24
local kArrowDistance = 80
local kFadeRadius = 400             -- icon is at kMNGAContextPingIconMinAlpha at the crosshair, opaque 400px away
local kTextOffset = 30
local kBounceSpeed = 3
local kBounceHeight = 10

local items = {}                    -- pool, one entry per visible icon
local screenWidth, screenHeight
local metersText

local function DestroyItems()
    for i = #items, 1, -1 do
        GUI.DestroyItem(items[i].icon) -- children are destroyed with the parent
        items[i] = nil
    end
end

local function CreateItem()

    local icon = GUI.CreateItem()
    icon:SetTexture(kIconTexture)
    icon:SetBlendTechnique(GUIItem.Add)
    icon:SetLayer(kGUILayerPlayerHUDBackground)
    icon:SetIsVisible(false)

    local arrow = GUI.CreateItem()
    arrow:SetAnchor(GUIItem.Middle, GUIItem.Center)
    arrow:SetTexture(kArrowTexture)
    arrow:SetIsVisible(false)
    icon:AddChild(arrow)

    local text = GUI.CreateItem()
    text:SetOptionFlag(GUIItem.ManageRender)
    text:SetAnchor(GUIItem.Middle, GUIItem.Bottom)
    text:SetTextAlignmentX(GUIItem.Align_Center)
    text:SetTextAlignmentY(GUIItem.Align_Min)
    text:SetFontName(Fonts.kAgencyFB_Small)
    text:SetScale(GetScaledVector())
    GUIMakeFontScale(text)
    text:SetInheritsParentAlpha(true)
    icon:AddChild(text)

    return { icon = icon, arrow = arrow, text = text }

end

local function GetItem(index)
    local item = items[index]
    if not item then
        item = CreateItem()
        items[index] = item
    end
    return item
end

-- Returns x, y, scale, showArrow, dist or nil when the icon is not drawn.
local function GetScreenPlacement(isCommander, eye, forward, worldPoint)

    local toTarget = worldPoint - eye
    local dist = toTarget:GetLength()
    local screenPos = Client.WorldToScreen(worldPoint)

    local w, h = screenWidth, screenHeight
    local border = isCommander and 0 or kScreenBorder
    local minX, maxX = w * border, w * (1 - border)
    local minY, maxY = h * border, h * (1 - border)

    local inFront
    if isCommander then
        inFront = toTarget:DotProduct(forward) > 0
    else
        inFront = Math.DotProduct(GetNormalizedVectorXZ(toTarget), GetNormalizedVectorXZ(forward)) >= 0
    end

    local scale = isCommander and kCommanderScale or math.max(kMinScale, 1 - dist / kMaxScaleDistance)

    if inFront and screenPos.x >= minX and screenPos.x <= maxX and screenPos.y >= minY and screenPos.y <= maxY then
        local bounce = math.sin(Shared.GetTime() * kBounceSpeed) * kBounceHeight * scale
        return screenPos.x, screenPos.y + bounce, scale, false, dist
    end

    -- the commander has the minimap; no edge clamp in the top-down view
    if isCommander then
        return nil
    end

    -- off screen: vanilla compass method
    local eyeForwardPos = eye + forward * 5
    local dir = worldPoint - eyeForwardPos
    dir:Normalize()
    local middle = Vector(w / 2, h / 2, 0)
    local screenDir = Client.WorldToScreen(eyeForwardPos + dir) - middle
    screenDir:Normalize()
    local finalPos = middle + Vector(screenDir.x * (w / 2), screenDir.y * (h / 2), 0)

    local showArrow = finalPos.x < minX or finalPos.x > maxX or finalPos.y < minY or finalPos.y > maxY
    return Clamp(finalPos.x, minX, maxX), Clamp(finalPos.y, minY, maxY), scale, showArrow, dist

end

local function UpdateTargetIcons()

    local used = 0

    local marks = MNGA_ContextPing_GetActiveMarks and MNGA_ContextPing_GetActiveMarks()
    local player = Client.GetLocalPlayer()

    if marks and #marks > 0 and kMNGAContextPingMarineIcon and player and player:GetTeamNumber() == kTeam1Index then

        local w, h = Client.GetScreenWidth(), Client.GetScreenHeight()
        if w ~= screenWidth or h ~= screenHeight then
            DestroyItems()
            screenWidth, screenHeight = w, h
        end
        metersText = metersText or Locale.ResolveString("METERS")

        local isCommander = player:isa("Commander")
        local viewCoords = player:GetCameraViewCoords()
        local eye, forward = viewCoords.origin, viewCoords.zAxis
        local center = Vector(w / 2, h / 2, 0)
        local showText = not isCommander and Client.GetHudDetail() == kHUDMode.Full

        for i = 1, #marks do

            local mark = marks[i]
            local ent = Shared.GetEntity(mark.targetId)
            local enemy = ent and ent:GetTeamNumber() ~= kTeam1Index
            local show = ent ~= nil
            if show and enemy and kMNGAContextPingIconRequireSighted and HasMixin(ent, "LOS") then
                show = ent:GetIsSighted()
            end

            if show then

                local worldPoint = ent:GetOrigin()
                if not isCommander then
                    worldPoint = worldPoint + Vector(0, kHeightOffset, 0)
                end

                local x, y, scale, showArrow, dist = GetScreenPlacement(isCommander, eye, forward, worldPoint)
                if x then

                    used = used + 1
                    local item = GetItem(used)
                    local size = GUIScale(kIconSize) * scale

                    local alpha = 1
                    if not isCommander then
                        local fade = math.min(1, (Vector(x, y, 0) - center):GetLength() / GUIScale(kFadeRadius))
                        alpha = kMNGAContextPingIconMinAlpha + (1 - kMNGAContextPingIconMinAlpha) * fade
                    end
                    local color = MNGA_ContextPing_GetCategoryColor(MNGA_ContextPing_GetTierCategory(mark.tier))

                    local techId = enemy and kTechId.Attack or kTechId.Defend
                    if item.techId ~= techId then
                        item.techId = techId
                        item.icon:SetTexturePixelCoordinates(GUIUnpackCoords(GetTextureCoordinatesForIcon(techId)))
                    end

                    item.icon:SetSize(Vector(size, size, 0))
                    item.icon:SetPosition(Vector(x - size / 2, y - size / 2, 0))
                    item.icon:SetColor(Color(color.r, color.g, color.b, alpha))
                    item.icon:SetIsVisible(true)

                    if showArrow then
                        local direction = Vector(x, y, 0) - center
                        direction:Normalize()
                        local arrowSize = GUIScale(kArrowSize)
                        item.arrow:SetSize(Vector(arrowSize, arrowSize, 0))
                        item.arrow:SetPosition(Vector(-arrowSize / 2, -arrowSize / 2, 0) + direction * GUIScale(kArrowDistance))
                        item.arrow:SetRotation(Vector(0, 0, math.atan2(direction.x, direction.y)))
                        item.arrow:SetColor(Color(color.r, color.g, color.b, 1))
                    end
                    item.arrow:SetIsVisible(showArrow)

                    item.text:SetIsVisible(showText)
                    if showText then
                        item.text:SetPosition(Vector(0, GUIScale(kTextOffset), 0))
                        item.text:SetText(string.format("%d %s", math.floor(dist), metersText))
                    end

                end

            end

        end

    end

    for i = used + 1, #items do
        items[i].icon:SetIsVisible(false)
    end

end

Event.Hook("UpdateRender", UpdateTargetIcons)
