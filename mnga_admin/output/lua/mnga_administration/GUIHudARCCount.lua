-- MNGA marine top bar: display the authoritative count of completed, living ARCs.

Script.Load("lua/Hud2/topBar/GUIHudTopBarObject.lua")

local baseClass = GUIHudTopBarObject
class "GUIHudARCCount" (baseClass)

-- Vanilla uses 128-step priorities; place ARC immediately after IP (640).
GUIHudARCCount.kLayoutSortPriority = 768

local kIcon = PrecacheAsset("ui/mnga_administration/arc_team_info.dds")
local kIconPxCoords = { 0, 0, 50, 50 }
local kIconTextSpacing = 4

GUIHudARCCount:AddClassProperty("ARCCount", 0)

function GUIHudARCCount:Initialize(params, errorDepth)
    errorDepth = (errorDepth or 1) + 1

    baseClass.Initialize(self, params, errorDepth)

    self.icon:SetTexture(kIcon)
    self.icon:SetTexturePixelCoordinates(kIconPxCoords)
    self.icon:SetSize(50, 50)
    self.layout:SetSpacing(kIconTextSpacing)

    self:HookEvent(self, "OnARCCountChanged", self.UpdateARCCountText)
    self:HookEvent(GetGlobalEventDispatcher(), "OnARCCountChanged", self.SetARCCount)
    self:HookEvent(self, "OnTeamInfoInitialized", self.UpdateARCCountFromTeamInfo)

    self:UpdateARCCountText()
    self:UpdateARCCountFromTeamInfo()
end

function GUIHudARCCount:UpdateARCCountText()
    self:GetTextObj():SetText(tostring(self:GetARCCount()))
end

function GUIHudARCCount:GetMaxWidthText()
    return "00"
end

function GUIHudARCCount:UpdateARCCountFromTeamInfo()
    local teamInfo = GetTeamInfoEntity(kTeam1Index)
    if teamInfo and teamInfo.numARCs ~= nil then
        self:SetARCCount(teamInfo.numARCs)
    end
end

function GUIHudARCCount.EvaluateVisibility(topBarObj)
    local teamType = GetTeamTypeFromTeamIndex(topBarObj:GetTeamNumber())
    return teamType == kMarineTeamType
end

GUIHudTopBar.AddTopBarClass("GUIHudARCCount")
