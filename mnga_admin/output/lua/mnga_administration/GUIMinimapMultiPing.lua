
-- MNGA multi-ping: render every active ping slot on the minimap.
-- Slot 1 reuses the vanilla self.commanderPing item; extra items are created in Initialize.

Script.Load("lua/mnga_administration/Globals.lua")
Script.Load("lua/mnga_administration/ContextPingShared.lua")

local kPingLayer = 5 -- must match the local of the same name in GUIMinimap.lua

-- ping name styling on the minimap, matching the player-name map labels
-- (kPlayerNameFontSize/kPlayerNameFontName/kPlayerNameLayer in GUIMinimap.lua)
local kPingNameFontSize = 8
local kPingNameFontName = Fonts.kAgencyFB_Tiny
local kPingNameLayer = 7

-- Fallback colors only. Globals.lua is the shared source for MNGA tiers/colors.
local kTierColors = {
    [1] = Color(0xE8/255, 0xBA/255, 0xC6/255, 1),
    [2] = Color(0x98/255, 0x7B/255, 0x61/255, 1),
    [3] = Color(0xDB/255, 0xEF/255, 0xF4/255, 1),
    [4] = Color(0xFF/255, 0xF5/255, 0x91/255, 1),
    [5] = Color(0x70/255, 0xC1/255, 0xF3/255, 1),
    [6] = Color(0x83/255, 0x49/255, 0xE9/255, 1),
    [7] = Color(0xF2/255, 0x2B/255, 0x2F/255, 1),
    [8] = Color(0xF2/255, 0x2B/255, 0x2F/255, 1),
    [9] = Color(0xF2/255, 0x2B/255, 0x2F/255, 1),
}

-- faux text outline: NS2 GUI has no native stroke, so we draw the name several
-- times in black behind the colored copy, offset 1px in 8 directions
local kPingNameOutlinePx = 1
local kPingNameOutlineDirs = {
    Vector(-1, -1, 0), Vector(0, -1, 0), Vector(1, -1, 0),
    Vector(-1,  0, 0),                   Vector(1,  0, 0),
    Vector(-1,  1, 0), Vector(0,  1, 0), Vector(1,  1, 0),
}

local function ConfigurePingNameItem(item)
    item:SetFontSize(kPingNameFontSize)
    item:SetFontIsBold(false)
    item:SetFontName(kPingNameFontName)
    item:SetInheritsParentScaling(false)
    item:SetScale(GetScaledVector())
    GUIMakeFontScale(item)
    item:SetAnchor(GUIItem.Middle, GUIItem.Center)
    item:SetTextAlignmentX(GUIItem.Align_Center)
    item:SetTextAlignmentY(GUIItem.Align_Center)
end

-- attach a tier-colored name label (with a black outline) below a minimap ping
local function AttachPingName(self, ping)

    -- black outline copies sit one layer below the colored name
    ping.NameOutline = {}
    for i = 1, #kPingNameOutlineDirs do
        local outline = GUIManager:CreateTextItem()
        ConfigurePingNameItem(outline)
        outline:SetLayer(kPingNameLayer)
        outline:SetColor(Color(0, 0, 0, 1))
        ping.Frame:AddChild(outline)
        ping.NameOutline[i] = outline
    end

    local nameItem = GUIManager:CreateTextItem()
    ConfigurePingNameItem(nameItem)
    nameItem:SetLayer(kPingNameLayer + 1)
    -- child of the ping frame so it follows the ping's minimap position and
    -- is hidden together with the frame (mute / expiry just toggle the frame)
    ping.Frame:AddChild(nameItem)
    ping.Name = nameItem

end

-- teams whose TeamInfo the current update visited; reused, no per-frame alloc
local seenTeams = {}

-- Hide every slot item of one team. Used when that team's TeamInfo is no
-- longer on the client: it stops being relevant (and is deleted client-side)
-- when we change team, e.g. a countdown/round-start shuffle moving us
-- marines -> aliens. Its slots are then never visited again, so whatever they
-- last drew (a still-active pregame ping) would stay on the map forever.
local function HideTeamPingItems(pings, teamNumber)

    local guiOffset = (teamNumber - 1) * kMultiPingCount
    for slot = 1, kMultiPingCount do
        local ping = pings[guiOffset + slot]
        if ping then
            ping.Frame:SetIsVisible(false)
            -- re-evaluate the slot from scratch if this TeamInfo comes back
            ping.expiredPingTime = 0
        end
    end

end

local oldInitialize = GUIMinimap.Initialize
function GUIMinimap:Initialize()

    oldInitialize(self)

    -- teamNumber -> true while that team's slots may hold visible items
    self.pingTeamActive = {}

    self.multiPings = { self.commanderPing }
    AttachPingName(self, self.commanderPing)
    for i = 2, kMultiPingCount * 2 do

        local ping = GUICreateCommanderPing()
        ping.Frame:SetAnchor(GUIItem.Middle, GUIItem.Center)
        ping.Frame:SetLayer(kPingLayer)
        ping.expiredPingTime = 0
        self.minimap:AddChild(ping.Frame)
        AttachPingName(self, ping)
        self.multiPings[i] = ping

    end

    -- contextual ping marks: pinger name below the marked target's blip.
    -- An invisible (alpha 0) frame per mark carries the same name/outline
    -- items as the ping names; hiding is done per item so the frame can stay
    -- visible (frame visibility propagates to children).
    self.markNames = {}
    for i = 1, (kContextMarkCount or 0) do

        local frame = GUIManager:CreateGraphicItem()
        frame:SetSize(Vector(0, 0, 0))
        frame:SetColor(Color(0, 0, 0, 0))
        frame:SetAnchor(GUIItem.Middle, GUIItem.Center)
        frame:SetLayer(kPingNameLayer)
        self.minimap:AddChild(frame)

        local markName = { Frame = frame }
        AttachPingName(self, markName)
        self.markNames[i] = markName

    end

    -- Print("GUIMinimap:Initialize multi-ping with %d slots", kMultiPingCount)

end

local oldUninitialize = GUIMinimap.Uninitialize
function GUIMinimap:Uninitialize()

    oldUninitialize(self)
    -- the extra ping frames are children of self.minimap, destroyed with it
    self.multiPings = nil
    self.markNames = nil

end

local oldSetStencilFunc = GUIMinimap.SetStencilFunc
function GUIMinimap:SetStencilFunc(stencilFunc)

    oldSetStencilFunc(self, stencilFunc)

    if self.multiPings then
        -- slot 1 Mark/Border already handled by vanilla; set stencil on everything else
        for i = 1, #self.multiPings do
            local ping = self.multiPings[i]
            if ping.Location then
                ping.Location:SetStencilFunc(stencilFunc)
            end
            if ping.Name then
                ping.Name:SetStencilFunc(stencilFunc)
            end
            if ping.NameOutline then
                for _, outline in ipairs(ping.NameOutline) do
                    outline:SetStencilFunc(stencilFunc)
                end
            end
            if i > 1 then
                ping.Mark:SetStencilFunc(stencilFunc)
                ping.Border:SetStencilFunc(stencilFunc)
            end
        end
    end

    if self.markNames then
        for _, markName in ipairs(self.markNames) do
            markName.Frame:SetStencilFunc(stencilFunc)
            markName.Name:SetStencilFunc(stencilFunc)
            if markName.Ghost then
                markName.Ghost:SetStencilFunc(stencilFunc)
            end
            for _, outline in ipairs(markName.NameOutline) do
                outline:SetStencilFunc(stencilFunc)
            end
        end
    end

end

local function SetMarkNameVisible(markName, visible)
    markName.Name:SetIsVisible(visible)
    for _, outline in ipairs(markName.NameOutline) do
        outline:SetIsVisible(visible)
    end
end

-- "last seen" ghost: alpha for the ghost icon and the name while the target's
-- real blip is gone (enemy out of vision), and the ghost icon colour
local kGhostAlpha = 0.75
local kGhostIconColor = Color(1, 0, 0, kGhostAlpha)

local markBlips = {}        -- targetId -> MapBlip entity (this frame)
-- targetId -> { origin, blipType, blipTeam } of the last frame the blip existed.
-- Shared by the minimap and the big map (both are GUIMinimap instances).
local markLastSeen = {}

local function GetGhostIcon(self, markName)
    if not markName.Ghost then
        local icon = GUIManager:CreateGraphicItem()
        icon:SetAnchor(GUIItem.Middle, GUIItem.Center)
        icon:SetIsVisible(false)
        self.minimap:AddChild(icon)
        markName.Ghost = icon
    end
    return markName.Ghost
end

local function HideGhost(markName)
    if markName.Ghost then
        markName.Ghost:SetIsVisible(false)
    end
    markName.ghostTargetId = nil
end

-- Contextual ping marks: the pinger's name (tier-coloured, same style as the
-- ping names) below the marked target's blip. When the blip disappears (enemy
-- no longer sighted) a red ghost icon + name stay at the last seen position at
-- 75% opacity until the mark ends; the real blip returns at full opacity when
-- the target is sighted again. The red blip itself is ContextPingMapBlip_Client.lua.
local function UpdateMarkNames(self)

    if not self.markNames then
        return
    end

    local used = 0
    local marks, byTarget, teamInfo
    if MNGA_ContextPing_GetActiveMarks then
        marks, byTarget, teamInfo = MNGA_ContextPing_GetActiveMarks()
    end

    if marks and #marks > 0 and teamInfo then

        for targetId in pairs(markBlips) do
            markBlips[targetId] = nil
        end
        for _, blip in ientitylist(Shared.GetEntitiesWithClassname("MapBlip")) do
            local ownerId = blip.ownerEntityId
            if ownerId and byTarget[ownerId] then
                markBlips[ownerId] = blip
            end
        end

        -- forget last-seen data of marks that ended
        for targetId in pairs(markLastSeen) do
            if not byTarget[targetId] then
                markLastSeen[targetId] = nil
            end
        end

    end

    if marks and #marks > 0 and teamInfo and self.visible then

        local nameOffset = GUIScale(Vector(0, 16, 0))
        local outlinePx = GUIScale(kPingNameOutlinePx)

        for i = 1, #marks do

            local mark = marks[i]
            local blip = markBlips[mark.targetId]
            local origin, ghost

            if blip then
                origin = blip:GetOrigin()
                local lastSeen = markLastSeen[mark.targetId]
                if not lastSeen then
                    lastSeen = {}
                    markLastSeen[mark.targetId] = lastSeen
                end
                lastSeen.origin = Vector(origin)
                lastSeen.blipType = blip:GetMapBlipType()
                lastSeen.blipTeam = blip:GetMapBlipTeam(self)
            elseif markLastSeen[mark.targetId] then
                origin = markLastSeen[mark.targetId].origin
                ghost = markLastSeen[mark.targetId]
            end

            if origin and used < #self.markNames then

                used = used + 1
                local markName = self.markNames[used]
                local alpha = ghost and kGhostAlpha or 1

                local posX, posY = self:PlotToMap(origin.x, origin.z)
                markName.Frame:SetPosition(Vector(posX, posY, 0))

                -- ghost icon (the real blip is gone)
                local ghostDrawable = ghost and self.blipInfoTable and self.blipInfoTable[ghost.blipType] ~= nil
                if ghostDrawable then
                    local icon = GetGhostIcon(self, markName)
                    if markName.ghostTargetId ~= mark.targetId or markName.ghostBlipType ~= ghost.blipType then
                        self:InitMinimapIcon(icon, ghost.blipType, ghost.blipTeam)
                        markName.ghostTargetId = mark.targetId
                        markName.ghostBlipType = ghost.blipType
                    end
                    icon:SetColor(kGhostIconColor)
                    icon:SetPosition(Vector(posX - icon.blipSize.x * 0.5, posY - icon.blipSize.y * 0.5, 0))
                    icon:SetIsVisible(true)
                else
                    HideGhost(markName)
                end

                local clientIndex = teamInfo:GetMarkOwnerClientIndex(mark.slot)
                local muted = clientIndex > 0 and SSB_GetClientCallsMuted ~= nil and SSB_GetClientCallsMuted(clientIndex)

                if muted then
                    SetMarkNameVisible(markName, false)
                else

                    local name = teamInfo:GetMarkName(mark.slot) or ""

                    for j, outline in ipairs(markName.NameOutline) do
                        outline:SetText(name)
                        outline:SetScale(GetScaledVector())
                        outline:SetPosition(nameOffset + kPingNameOutlineDirs[j] * outlinePx)
                        outline:SetColor(Color(0, 0, 0, alpha))
                    end

                    markName.Name:SetText(name)
                    markName.Name:SetScale(GetScaledVector())
                    markName.Name:SetPosition(nameOffset)

                    local tierColor = (MNGA_GetSkillTierColor and MNGA_GetSkillTierColor(mark.tier)) or kTierColors[mark.tier]
                    if tierColor then
                        markName.Name:SetColor(Color(tierColor.r, tierColor.g, tierColor.b, alpha))
                    else
                        markName.Name:SetColor(Color(1, 1, 1, alpha))
                    end

                    SetMarkNameVisible(markName, true)

                end

            end

        end

    end

    for i = used + 1, #self.markNames do
        SetMarkNameVisible(self.markNames[i], false)
        HideGhost(self.markNames[i])
    end

end

local function UpdateMultiPings(self)

    if not self.multiPings then
        return
    end

    local player = Client.GetLocalPlayer()
    if not player then
        return
    end

    UpdateMarkNames(self)

    seenTeams[kTeam1Index] = false
    seenTeams[kTeam2Index] = false

    for _, entity in ientitylist(Shared.GetEntitiesWithClassname("TeamInfo")) do

        local teamNumber = entity:GetTeamNumber()
        seenTeams[teamNumber] = true
        self.pingTeamActive[teamNumber] = true

        -- mirrors the file-local kCommanderPingMinimapSize; recomputed here so
        -- resolution changes are picked up without patching UpdateItemsGUIScale
        local pingSize = GUIScale(Vector(80, 80, 0))
        -- name sits just below the ping mark (half of pingSize is GUIScale(40))
        local nameOffset = GUIScale(Vector(0, 20, 0))

        local guiOffset = (teamNumber - 1) * kMultiPingCount

        for slot = 1, math.min(entity:GetPingCount(), kMultiPingCount) do

            local ping = self.multiPings[guiOffset + slot]
            local pingTime = entity:GetPingTime(slot)

            if pingTime <= 0 then

                ping.Frame:SetIsVisible(false)
                ping.expiredPingTime = 0

            -- mute check runs before the expired guard so muting hides an
            -- already-visible ping, and unmuting mid-ping shows it again
            elseif MNGA_GetPingOwnerMuted(entity, slot) then

                ping.Frame:SetIsVisible(false)

            elseif pingTime ~= ping.expiredPingTime then

                local timeSincePing, position, _, _, _, playerName = PlayerUI_GetPingInfoForSlot(player, entity, slot, true)
                local posX, posY = self:PlotToMap(position.x, position.z)
                ping.Frame:SetPosition(Vector(posX, posY, 0))
                ping.Frame:SetIsVisible(timeSincePing <= kCommanderPingDuration and self.visible)

                local expired = GUIAnimateCommanderPing(ping.Mark, ping.Border, ping.Location, pingSize, timeSincePing, Color(1, 0, 0, 1), Color(1, 1, 1, 1))
                if expired then
                    -- block ping animation now that it has expired
                    ping.expiredPingTime = pingTime
                end

                -- tier-colored name label, fading with the ping like the mark
                if ping.Name then

                    local name = playerName or ""

                    local fade = 1 - (math.min(timeSincePing, kCommanderPingDuration) / kCommanderPingDuration)
					-- local t = math.min(timeSincePing, kCommanderPingDuration) / kCommanderPingDuration
					-- local fade
					-- if t < 0.5 then
						-- fade = 1
					-- else
						-- fade = 1 - ((t - 0.5) / 0.5)
					-- end

                    -- black outline copies behind, offset in 8 directions; fade
                    -- them faster than the text (quadratic) so the black doesn't
                    -- dominate the thin colored glyphs as the ping ages
                    local outlineFade = fade * fade
                    local outlinePx = GUIScale(kPingNameOutlinePx)
                    for i, outline in ipairs(ping.NameOutline) do
                        outline:SetText(name)
                        outline:SetScale(GetScaledVector())
                        outline:SetPosition(nameOffset + kPingNameOutlineDirs[i] * outlinePx)
                        outline:SetColor(Color(0, 0, 0, outlineFade))
                    end

                    ping.Name:SetText(name)
                    ping.Name:SetScale(GetScaledVector())
                    ping.Name:SetPosition(nameOffset)

                    local tier = entity:GetPingOwnerTier(slot)
                    local tierColor = (MNGA_GetSkillTierColor and MNGA_GetSkillTierColor(tier)) or kTierColors[tier]
                    if tierColor then
                        ping.Name:SetColor(Color(tierColor.r, tierColor.g, tierColor.b, fade))
                    else
                        ping.Name:SetColor(Color(1, 1, 1, fade))
                    end

                end

            end

        end

    end

    for teamNumber = kTeam1Index, kTeam2Index do
        if not seenTeams[teamNumber] and self.pingTeamActive[teamNumber] then
            self.pingTeamActive[teamNumber] = false
            HideTeamPingItems(self.multiPings, teamNumber)
        end
    end

end

-- UpdateCommanderPing is a local stored in the local kMiscUpdateStepFunctions table,
-- which GUIMinimap:Update closes over; swap the table entry (index 4) for our version.
local kMiscUpdateStepFunctions = debug.getupvaluex(GUIMinimap.Update, "kMiscUpdateStepFunctions")
if kMiscUpdateStepFunctions then
    kMiscUpdateStepFunctions[4] = UpdateMultiPings
else
    Print("GUIMinimapMultiPing: ERROR - kMiscUpdateStepFunctions upvalue not found!")
end