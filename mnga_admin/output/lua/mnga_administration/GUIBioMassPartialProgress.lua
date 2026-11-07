-- Draw each replicated biomass TechNode's research progress inside its own
-- segment of the top-left biomass bar. Concurrent Hive research must remain
-- visually separate rather than being summed into one continuous fill.

local kBiomassProgressTechIds =
{
    kTechId.BioMassOne,
    kTechId.BioMassTwo,
    kTechId.BioMassThree,
    kTechId.BioMassFour,
    kTechId.BioMassFive,
    kTechId.BioMassSix,
    kTechId.BioMassSeven,
    kTechId.BioMassEight,
    kTechId.BioMassNine,
    kTechId.BioMassTen,
    kTechId.BioMassEleven,
    kTechId.BioMassTwelve
}

local kBiomassLevels = #kBiomassProgressTechIds
local kTextureWidth = 1200
local kTextureHeight = 160
-- Inclusive Paint.NET pixel measurements of the visible yellow foreground art.
-- The texture-coordinate right edges below are converted to exclusive bounds.
local kBiomassYellowPixelBounds =
{
    { 29, 108 },
    { 127, 207 },
    { 223, 302 },
    { 326, 405 },
    { 424, 502 },
    { 517, 597 },
    { 623, 702 },
    { 721, 800 },
    { 815, 894 },
    { 904, 983 },
    { 1002, 1080 },
    { 1097, 1176 }
}

local kResearchingProgressColor = Color(0.6, 0.6, 0.6, 1)
local kCapacityProgressColor = Color(1, 0.7, 0.7, 0.35)
-- Translucent purple full-segment "ghost" behind an in-progress fill so
-- research is recognisable from the first second; the contrasting hue keeps
-- the yellow fill edge readable. biomass_bar.dds is baked yellow (almost no
-- blue), so tinting it cannot give purple: the ghost uses a greyscale copy of
-- its foreground row (same 1200x160 pixel layout).
local kGhostTexture = PrecacheAsset("materials/mnga_administration/biomass_bead_white.dds")
local kSegmentGhostColor = Color(0.62, 0.3, 1, 0.5)
local kCapacityGhostColor = Color(0.62, 0.3, 1, 0.25)
local kResearchSlowRangeEnd = 0.9
local kVisualSlowRangeEnd = 0.8

local baseInitialize = GUIBioMassDisplay.Initialize
local baseUninitialize = GUIBioMassDisplay.Uninitialize
local baseOnResolutionChanged = GUIBioMassDisplay.OnResolutionChanged
local baseUpdate = GUIBioMassDisplay.Update

local function ResearchProgressToVisualProgress(progress)
    if progress <= kResearchSlowRangeEnd then
        return progress * kVisualSlowRangeEnd / kResearchSlowRangeEnd
    end

    local finalResearchFraction = (progress - kResearchSlowRangeEnd)
        / (1 - kResearchSlowRangeEnd)
    return kVisualSlowRangeEnd
        + finalResearchFraction * (1 - kVisualSlowRangeEnd)
end

local function LayoutProgressItems(self)
    if not self.mngaBiomassProgressItems or not self.background then
        return
    end

    local barSize = self.background:GetSize()

    for level = 1, kBiomassLevels do
        local item = self.mngaBiomassProgressItems[level]
        local ghost = self.mngaBiomassGhostItems[level]
        local pixelBounds = kBiomassYellowPixelBounds[level]
        local screenStart = barSize.x * pixelBounds[1] / kTextureWidth
        local screenWidth = barSize.x * (pixelBounds[2] - pixelBounds[1]) / kTextureWidth
        item:SetPosition(Vector(screenStart, 0, 0))
        item:SetSize(Vector(screenWidth, barSize.y, 0))
        item:SetCropMinCornerNormalized(0, 0)
        item:SetCropMaxCornerNormalized(0, 1)
        ghost:SetPosition(Vector(screenStart, 0, 0))
        ghost:SetSize(Vector(screenWidth, barSize.y, 0))
        ghost:SetTexturePixelCoordinates(
            pixelBounds[1], 0, pixelBounds[2], kTextureHeight)
    end
end

local function CreateProgressItems(self)
    self.mngaBiomassProgressItems = {}
    self.mngaBiomassGhostItems = {}

    -- Ghosts are added first so every progress fill draws on top of them.
    for level = 1, kBiomassLevels do
        local ghost = GetGUIManager():CreateGraphicItem()
        ghost:SetTexture(kGhostTexture)
        ghost:SetColor(kSegmentGhostColor)
        ghost:SetInheritsParentAlpha(true)
        ghost:SetIsVisible(false)
        self.background:AddChild(ghost)
        self.mngaBiomassGhostItems[level] = ghost
    end

    for level = 1, kBiomassLevels do
        local item = GetGUIManager():CreateGraphicItem()
        item:SetTexture("ui/biomass_bar.dds")
        item:SetColor(kResearchingProgressColor)
        item:SetInheritsParentAlpha(true)
        item:SetIsVisible(false)
        self.background:AddChild(item)
        self.mngaBiomassProgressItems[level] = item
    end

    -- These overlays are created after vanilla's level text. Keep the label in
    -- front so a partial segment never obscures "Biomass Level: N / 12".
    self.levelText:SetLayer(kGUILayerPlayerHUD + 1)
    LayoutProgressItems(self)
end

local function DestroyProgressItems(self)
    if self.mngaBiomassProgressItems then
        for _, item in ipairs(self.mngaBiomassProgressItems) do
            GUI.DestroyItem(item)
        end
        self.mngaBiomassProgressItems = nil
    end
    if self.mngaBiomassGhostItems then
        for _, ghost in ipairs(self.mngaBiomassGhostItems) do
            GUI.DestroyItem(ghost)
        end
        self.mngaBiomassGhostItems = nil
    end
end

local function UpdateProgressItems(self)
    if not self.mngaBiomassProgressItems or not self.background then
        return
    end

    local player = Client.GetLocalPlayer()
    local teamNumber = player and player:GetTeamNumber() or 0
    local teamInfo = GetTeamInfoEntity(teamNumber)
    local completedBiomass = teamInfo and teamInfo.GetBioMassLevel
        and teamInfo:GetBioMassLevel() or 0
    local maxBiomass = teamInfo and teamInfo.GetMaxBioMassLevel
        and teamInfo:GetMaxBioMassLevel() or 0
    local techTree = GetTechTree()
    local barSize = self.background:GetSize()

    for level = 1, kBiomassLevels do
        local progress = 0
        local techNode = techTree and techTree:GetTechNode(kBiomassProgressTechIds[level])

        -- Completed levels are already drawn by vanilla's continuous bar.
        if level > completedBiomass and techNode then
            progress = Clamp(techNode:GetResearchProgress() or 0, 0, 1)
        end

        local item = self.mngaBiomassProgressItems[level]
        local pixelBounds = kBiomassYellowPixelBounds[level]
        local screenWidth = barSize.x * (pixelBounds[2] - pixelBounds[1]) / kTextureWidth
        local visualProgress = ResearchProgressToVisualProgress(progress)
        local ghost = self.mngaBiomassGhostItems[level]
        local inProgress = progress > 0 and progress < 1
        ghost:SetIsVisible(inProgress)
        item:SetIsVisible(progress > 0)
        if level > maxBiomass then
            item:SetColor(kCapacityProgressColor)
            ghost:SetColor(kCapacityGhostColor)
        else
            item:SetColor(kResearchingProgressColor)
            ghost:SetColor(kSegmentGhostColor)
        end
        item:SetSize(Vector(screenWidth, barSize.y, 0))
        item:SetCropMinCornerNormalized(0, 0)
        item:SetCropMaxCornerNormalized(visualProgress, 1)
        item:SetTexturePixelCoordinates(
            pixelBounds[1], 0, pixelBounds[2], kTextureHeight)
    end
end

-- Ability icons above the strip (Leap, Umbra, ...) are vanilla research nodes.
-- While one researches, overlay an unlocked-colour copy of its icon cropped
-- left to right by the replicated research progress.
local kAbilityFillColor = Color(kIconColors[kAlienTeamType])
local kAbilityGhostColor = Color(0.62, 0.3, 1, 0.5)

-- Icon art fills only part of its 80px ui/buildmenu.dds cell and its mass is
-- uneven, so a crop linear in cell width looked ~90% done at 75% research.
-- Normalised crop x where the visible art (alpha > 40) reaches 0%, 10%, ...,
-- 100% of its alpha-weighted area, measured offline from the vanilla atlas.
-- Progress interpolates in this table so coloured area tracks research time.
local kAbilityCoverageX =
{
    [kTechId.Leap] = { 0.175, 0.300, 0.363, 0.416, 0.484, 0.541, 0.590, 0.646, 0.697, 0.755, 0.875 },
    [kTechId.Xenocide] = { 0.125, 0.258, 0.317, 0.374, 0.433, 0.489, 0.545, 0.599, 0.654, 0.712, 0.812 },
    [kTechId.BileBomb] = { 0.200, 0.292, 0.342, 0.387, 0.429, 0.469, 0.506, 0.548, 0.596, 0.654, 0.838 },
    [kTechId.Umbra] = { 0.163, 0.251, 0.305, 0.354, 0.402, 0.448, 0.494, 0.542, 0.595, 0.655, 0.750 },
    [kTechId.Spores] = { 0.150, 0.257, 0.336, 0.420, 0.482, 0.535, 0.584, 0.621, 0.664, 0.724, 0.838 },
    [kTechId.MetabolizeEnergy] = { 0.087, 0.173, 0.228, 0.284, 0.405, 0.533, 0.642, 0.755, 0.797, 0.842, 0.912 },
    [kTechId.MetabolizeHealth] = { 0.087, 0.184, 0.248, 0.337, 0.434, 0.533, 0.593, 0.707, 0.782, 0.833, 0.912 },
    [kTechId.Stab] = { 0.175, 0.248, 0.299, 0.360, 0.431, 0.503, 0.579, 0.674, 0.788, 0.833, 0.887 },
    [kTechId.BoneShield] = { 0.150, 0.317, 0.394, 0.455, 0.505, 0.554, 0.600, 0.651, 0.716, 0.789, 0.938 },
    [kTechId.Stomp] = { 0.163, 0.282, 0.323, 0.361, 0.398, 0.434, 0.470, 0.515, 0.580, 0.655, 0.838 },
}

local function AbilityProgressToCropX(techId, progress)
    local points = kAbilityCoverageX[techId]
    if not points then
        return progress
    end

    local scaled = Clamp(progress, 0, 1) * 10
    local index = math.min(math.floor(scaled), 9)
    local fraction = scaled - index
    return points[index + 1] + (points[index + 2] - points[index + 1]) * fraction
end

local function UpdateAbilityProgress(self)
    if not self.abilityIcons or not self.background
        or not self.background:GetIsVisible() then
        return
    end

    local player = Client.GetLocalPlayer()
    local techTree = GetTechTree()
    if not player or not techTree then
        return
    end

    for _, levelIcons in ipairs(self.abilityIcons) do
        for _, levelIcon in ipairs(levelIcons) do
            local techId = levelIcon.TechId
            local techNode = techId and techTree:GetTechNode(techId)
            local progress = 0

            if techNode and not GetIsTechUnlocked(player, techId) then
                progress = techNode:GetResearchProgress() or 0
            end

            local progressing = progress > 0 and progress < 1
            local fill = levelIcon.mngaProgressFill

            if progressing and not fill and levelIcon.Graphic then
                -- Half-opacity complete icon behind the fill; added first so
                -- the fill draws on top.
                local ghost = GetGUIManager():CreateGraphicItem()
                ghost:SetTexture("ui/buildmenu.dds")
                ghost:SetColor(kAbilityGhostColor)
                ghost:SetInheritsParentAlpha(true)
                ghost:SetIsVisible(false)
                levelIcon.Graphic:AddChild(ghost)
                levelIcon.mngaProgressGhost = ghost

                fill = GetGUIManager():CreateGraphicItem()
                fill:SetTexture("ui/buildmenu.dds")
                fill:SetColor(kAbilityFillColor)
                fill:SetInheritsParentAlpha(true)
                fill:SetIsVisible(false)
                levelIcon.Graphic:AddChild(fill)
                levelIcon.mngaProgressFill = fill
            end

            if fill then
                if progressing then
                    local ghost = levelIcon.mngaProgressGhost
                    if levelIcon.mngaProgressFillTechId ~= techId then
                        local coords = GetTextureCoordinatesForIcon(techId)
                        fill:SetTexturePixelCoordinates(GUIUnpackCoords(coords))
                        ghost:SetTexturePixelCoordinates(GUIUnpackCoords(coords))
                        levelIcon.mngaProgressFillTechId = techId
                    end
                    ghost:SetSize(levelIcon.Graphic:GetSize())
                    fill:SetSize(levelIcon.Graphic:GetSize())
                    fill:SetCropMinCornerNormalized(0, 0)
                    fill:SetCropMaxCornerNormalized(
                        AbilityProgressToCropX(techId, progress), 1)
                end

                fill:SetIsVisible(progressing)
                levelIcon.mngaProgressGhost:SetIsVisible(progressing)
            end
        end
    end
end

function GUIBioMassDisplay:Initialize()
    baseInitialize(self)
    CreateProgressItems(self)
end

function GUIBioMassDisplay:Uninitialize()
    DestroyProgressItems(self)
    baseUninitialize(self)
end

function GUIBioMassDisplay:OnResolutionChanged(oldX, oldY, newX, newY)
    baseOnResolutionChanged(self, oldX, oldY, newX, newY)
    LayoutProgressItems(self)
end

function GUIBioMassDisplay:Update(deltaTime)
    baseUpdate(self, deltaTime)
    UpdateProgressItems(self)
    UpdateAbilityProgress(self)
end
