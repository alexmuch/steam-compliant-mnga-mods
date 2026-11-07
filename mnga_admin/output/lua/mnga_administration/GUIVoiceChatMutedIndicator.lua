-- Muted voice indicator (.claude/docs/muted-voice-indicator.md): shows a
-- "Muted" bar under the normal voice-chat bars while a player you voice-muted
-- is talking, so you can avoid talking over them.
--
-- Uses its own bars appended after whatever bars GUIVoiceChat:Update made, so
-- it works with both vanilla GUIVoiceChat and spvc's replacement of it. When no
-- muted player is talking the per-frame cost is a single next() check.

if not Client or not GUIVoiceChat or GUIVoiceChat.MNGAMutedIndicatorWrapped then return end
GUIVoiceChat.MNGAMutedIndicatorWrapped = true

local kBackgroundTexture = "ui/%s_HUD_presbg.dds"
local kSpeakerIcon = PrecacheAsset("ui/speaker.dds")
local kMutedText = "Muted"
local kSpectatorTint = Color(1, 200/255, 150/255, 1)
local kWhite = Color(1, 1, 1, 1)

-- Same geometry as vanilla GUIVoiceChat's UpdateItemsGUIScale. Recomputed only
-- when bars are shown so team changes and resolution changes are picked up.
local function GetLayout()
    local size = Vector(GUIScale(250), GUIScale(28), 0)
    local offset = Vector(-size.x, 0, 0)
    if PlayerUI_IsOnAlienTeam() then
        offset.x = offset.x - GUIScale(70)
    elseif PlayerUI_GetIsSpecating() then
        offset.x = offset.x - GUIScale(200)
    end
    if PlayerUI_GetLifeformPopupActive() then
        offset.x = offset.x - GUIScale(200)
    end
    return size, offset, GUIScale(4)
end

local function CreateMutedBar(size)
    local iconSize = size.y

    local background = GUIManager:CreateGraphicItem()
    background:SetSize(size)
    background:SetAnchor(GUIItem.Right, GUIItem.Center)
    background:SetIsVisible(false)

    local icon = GUIManager:CreateGraphicItem()
    icon:SetSize(Vector(iconSize, iconSize, 0))
    icon:SetAnchor(GUIItem.Right, GUIItem.Center)
    icon:SetPosition(Vector(-size.y * 2, -iconSize / 2, 0))
    icon:SetTexture(kSpeakerIcon)
    background:AddChild(icon)

    local name = GUIManager:CreateTextItem()
    name:SetFontName(Fonts.kAgencyFB_Small)
    name:SetAnchor(GUIItem.Right, GUIItem.Center)
    name:SetScale(GetScaledVector())
    name:SetTextAlignmentX(GUIItem.Align_Max)
    name:SetTextAlignmentY(GUIItem.Align_Center)
    name:SetPosition(Vector(-size.y - GUIScale(6), 0, 0))
    GUIMakeFontScale(name)
    name:SetText(kMutedText)
    icon:AddChild(name)

    return { Background = background, Icon = icon, Name = name }
end

local function DestroyMutedBars(self)
    local bars = self.mngaMutedBars
    if not bars then return end
    for i = 1, #bars do
        GUI.DestroyItem(bars[i].Name)
        GUI.DestroyItem(bars[i].Icon)
        GUI.DestroyItem(bars[i].Background)
    end
    self.mngaMutedBars = nil
    self.mngaMutedShown = 0
end

local function HideMutedBars(self)
    local bars = self.mngaMutedBars
    for i = 1, (self.mngaMutedShown or 0) do
        bars[i].Background:SetIsVisible(false)
    end
    self.mngaMutedShown = 0
end

local function CountVisibleBars(self)
    local count = 0
    local chatBars = self.chatBars
    if chatBars then
        for i = 1, #chatBars do
            local background = chatBars[i].Background
            if background and background:GetIsVisible() then
                count = count + 1
            end
        end
    end
    return count
end

local function ApplyBarStyle(bar, record)
    local team = record and record.EntityTeamNumber
    local textureSet, fontColor, tint = "marine", GUIVoiceChat.kSpectatorFontColor, kSpectatorTint
    if team == kTeam1Index then
        fontColor, tint = GUIVoiceChat.kMarineFontColor, kWhite
    elseif team == kTeam2Index then
        textureSet, fontColor, tint = "alien", GUIVoiceChat.kAlienFontColor, kWhite
    end
    if record and record.IsCommander then
        fontColor = GUIVoiceChat.kCommanderFontColor
    end

    bar.Background:SetTexture(string.format(kBackgroundTexture, textureSet))
    bar.Background:SetColor(tint)
    bar.Name:SetColor(fontColor)
    bar.Icon:SetColor(fontColor)
end

local function UpdateMutedBars(self)
    local lastHeard = MNGAMutedVoiceLastHeard
    if not lastHeard or next(lastHeard) == nil then
        if (self.mngaMutedShown or 0) > 0 then
            HideMutedBars(self)
        end
        return
    end

    PROFILE("GUIVoiceChat:UpdateMutedBars")

    HideMutedBars(self)

    local now = Shared.GetTime()
    local holdTime = MNGA_MUTED_VOICE.ClientHoldTime
    local size, offset, ySpace
    local barIndex = 0
    local stackIndex

    for clientIndex, heardTime in pairs(lastHeard) do
        if now - heardTime > holdTime or not ChatUI_GetClientMuted(clientIndex) then
            -- Assigning nil to an existing key during pairs() is allowed.
            lastHeard[clientIndex] = nil
        elseif self.visible then
            if not size then
                size, offset, ySpace = GetLayout()
                stackIndex = CountVisibleBars(self)
                self.mngaMutedBars = self.mngaMutedBars or {}
            end

            barIndex = barIndex + 1
            local bar = self.mngaMutedBars[barIndex]
            if not bar then
                bar = CreateMutedBar(size)
                self.mngaMutedBars[barIndex] = bar
            end

            ApplyBarStyle(bar, Scoreboard_GetPlayerRecord(clientIndex))
            bar.Background:SetLayer(kGUILayerDeathScreen + 1)
            bar.Background:SetPosition(offset + Vector(0, (size.y + ySpace) * stackIndex, 0))
            bar.Background:SetIsVisible(true)
            stackIndex = stackIndex + 1
        end
    end

    self.mngaMutedShown = barIndex
end

local oldUpdate = GUIVoiceChat.Update
function GUIVoiceChat:Update(deltaTime)
    oldUpdate(self, deltaTime)
    UpdateMutedBars(self)
end

local oldUninitialize = GUIVoiceChat.Uninitialize
function GUIVoiceChat:Uninitialize()
    DestroyMutedBars(self)
    oldUninitialize(self)
end
