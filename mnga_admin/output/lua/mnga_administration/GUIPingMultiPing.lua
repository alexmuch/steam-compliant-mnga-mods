
-- MNGA multi-ping: render every active ping slot in the world.

Script.Load("lua/mnga_administration/Globals.lua")

local kMaxSize = GUIScale(Vector(400, 400, 0))
local kMinSize = GUIScale(Vector(128, 128, 0))
local kMaxPingDistance = 30

local kBorderColor = Color(1, 0, 0, 0)
local kMarkColor = Color(1, 1, 1, 1)

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

-- teams whose TeamInfo the current Update visited; reused, no per-frame alloc
local seenTeams = {}

-- Hide every slot item of one team. Used when that team's TeamInfo is no
-- longer on the client: it stops being relevant (and is deleted client-side)
-- when we change team, e.g. a countdown/round-start shuffle moving us
-- marines -> aliens. Its slots are then never visited again, so whatever they
-- last drew (a still-active pregame ping) would stay on screen forever.
local function HideTeamPingItems(items, teamNumber)

    local guiOffset = (teamNumber - 1) * kMultiPingCount
    for slot = 1, kMultiPingCount do
        local item = items[guiOffset + slot]
        if item then
            item.Frame:SetIsVisible(false)
            -- re-evaluate the slot from scratch if this TeamInfo comes back
            item.expiredPingTime = 0
        end
    end

end

function GUIPing:Initialize()

    self.updateInterval = 0
    -- teamNumber -> true while that team's slots may hold visible items
    self.pingTeamActive = {}
    self.screenDiagonalLength = math.sqrt(Client.GetScreenHeight() / 2) ^ 2 + (Client.GetScreenWidth() / 2)

    self.multiPingItems = {}
    for i = 1, kMultiPingCount * 2 do

        local item = GUICreateCommanderPing()
        item.expiredPingTime = 0 -- init to 0 so it isn't shown at the beginning
        item.Frame:SetIsVisible(false)

        -- second text line for the pinger's name, colored by skill tier
        -- (mirrors the Location item created in GUICreateCommanderPing)
        local nameItem = GUIManager:CreateTextItem()
        nameItem:SetFontName(kNeutralFontName)
        nameItem:SetAnchor(GUIItem.Middle, GUIItem.Center)
        nameItem:SetTextAlignmentX(GUIItem.Align_Center)
        nameItem:SetTextAlignmentY(GUIItem.Align_Center)
        nameItem:SetColor(kNeutralFontColor)
        nameItem:SetInheritsParentAlpha(true)
        item.Frame:AddChild(nameItem)
        item.Name = nameItem

        self.multiPingItems[i] = item

    end

    -- keep the vanilla field pointing somewhere sane in case other code touches it
    self.pingItem = self.multiPingItems[1]
    self.expiredPingTime = 0

    self:SetIsVisible(true)

    -- Print("GUIPing:Initialize multi-ping with %d slots", kMultiPingCount)

end

function GUIPing:Uninitialize()

    if self.multiPingItems then

        for _, item in ipairs(self.multiPingItems) do
            GUI.DestroyItem(item.Frame)
        end
        self.multiPingItems = nil
        self.pingItem = nil

    end

end

function GUIPing:OnResolutionChanged()

    self.screenDiagonalLength = math.sqrt(Client.GetScreenHeight() / 2) ^ 2 + (Client.GetScreenWidth() / 2)
    -- these are this file's locals; the vanilla OnResolutionChanged only updates
    -- the original file's copies, which our Update below no longer reads
    kMaxSize = GUIScale(Vector(400, 400, 0))
    kMinSize = GUIScale(Vector(128, 128, 0))

end

function GUIPing:Update(deltaTime)

    PROFILE("GUIPing:Update")

    local player = Client.GetLocalPlayer()
    if not player or not self.multiPingItems then
        return
    end

    seenTeams[kTeam1Index] = false
    seenTeams[kTeam2Index] = false

    for index, entity in ientitylist(Shared.GetEntitiesWithClassname("TeamInfo")) do

        local teamNumber = entity:GetTeamNumber()
        seenTeams[teamNumber] = true
        self.pingTeamActive[teamNumber] = true

        local guiOffset = (teamNumber - 1) * kMultiPingCount

        for slot = 1, math.min(entity:GetPingCount(), kMultiPingCount) do

            local item = self.multiPingItems[guiOffset + slot]
            local pingTime = entity:GetPingTime(slot)

            if pingTime <= 0 then

                item.Frame:SetIsVisible(false)
                item.expiredPingTime = 0

            -- mute check runs before the expired guard so muting hides an
            -- already-visible ping, and unmuting mid-ping shows it again
            elseif MNGA_GetPingOwnerMuted(entity, slot) then

                item.Frame:SetIsVisible(false)

            elseif pingTime ~= item.expiredPingTime then

                local timeSincePing, position, distance, locationName, _, playerName = PlayerUI_GetPingInfoForSlot(player, entity, slot, false)

                local distanceFraction = 1 - Clamp(distance / kMaxPingDistance, 0, 1)
                local pingSize = kMinSize + distanceFraction * (kMaxSize - kMinSize)

                item.Frame:SetIsVisible(self.visible and (timeSincePing <= kCommanderPingDuration))
                local expired = GUIAnimateCommanderPing(item.Mark, item.Border, item.Location, pingSize, timeSincePing, kBorderColor, kMarkColor)

                -- Fade out when closer to screen center.
                local distanceToScreenCenter = math.abs((position - Vector(Client.GetScreenWidth() * 0.5, Client.GetScreenHeight() * 0.5, 0)):GetLength())
                item.Frame:SetColor(Color(1, 1, 1, (distanceToScreenCenter / GUIScale(400)) + 0.1 ))

                item.Frame:SetPosition(position)

                if locationName == nil then
                    locationName = ""
                end

                if playerName == nil then
                    playerName = ""
                end

                item.Location:SetText(locationName)

                -- name line below the location, colored by skill tier, with the
                -- same scale/fade GUIAnimateCommanderPing applies to the location
                item.Name:SetText(playerName)
                item.Name:SetScale(GetScaledVector())
                -- one line height below the location text (which sits at GUIScale(70))
                item.Name:SetPosition(Vector(0, GUIScale(105), 0))

                local fade = 1 - (math.min(timeSincePing, kCommanderPingDuration) / kCommanderPingDuration)
                local tier = entity:GetPingOwnerTier(slot)
                local tierColor = (MNGA_GetSkillTierColor and MNGA_GetSkillTierColor(tier)) or kTierColors[tier]
                if tierColor then
                    item.Name:SetColor(Color(tierColor.r, tierColor.g, tierColor.b, fade))
                else
                    item.Name:SetColor(Color(1, 1, 1, fade))
                end

                if expired then
                    item.expiredPingTime = pingTime
                end

            end

        end

    end

    for teamNumber = kTeam1Index, kTeam2Index do
        if not seenTeams[teamNumber] and self.pingTeamActive[teamNumber] then
            self.pingTeamActive[teamNumber] = false
            HideTeamPingItems(self.multiPingItems, teamNumber)
        end
    end

end
