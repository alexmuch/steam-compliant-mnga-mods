-- Teammate health bars: lets TeamHealthBars_Client.lua raise vanilla's local 13 m
-- nearby range (kMaxUnitStatusDistanceSq in FindUnitsToDisplayStatusFor) to 20 m while
-- forced bars are active. The entity scan already covers 20 m, so this adds no scan.
-- Also applies the nameplate opacity option to all blips.

MNGA_TeamHealthBars = MNGA_TeamHealthBars or {}
local module = MNGA_TeamHealthBars

-- Nameplate opacity (doc §3.13): every item below statusBg and the status icon inherits alpha, so
-- one colour per blip fades the whole plate. At 100% nothing is touched, and vanilla writes both
-- colours back to full alpha on each update, so returning to 100% needs no reset.
local kOpaque = Color(1, 1, 1, 1)
local plateColor = Color(1, 1, 1, 1)

function module.SetPlateOpacity(opacity)
    plateColor.a = opacity
end

local function SetBlipItemsInheritAlpha(blip)
    local items = {
        blip.HealthBarBg, blip.RegenBar, blip.HealthBar, blip.ArmorBarBg, blip.ArmorBar,
        blip.NameText, blip.HintText, blip.MaturityText, blip.ProgressingIcon,
        blip.ProgressBackground, blip.ProgressText, blip.ActionTextShadow, blip.ActionText
    }
    for i = 1, #items do
        items[i]:SetInheritsParentAlpha(true)
    end
    for i = 1, #blip.Badges do
        blip.Badges[i]:SetInheritsParentAlpha(true)
    end
    blip.mngaInheritsAlpha = true
end

local originalUpdateUnitStatusBlip = GUIUnitStatus.UpdateUnitStatusBlip
function GUIUnitStatus:UpdateUnitStatusBlip(blipIndex, localPlayerIsCommander, baseResearchRot, showHints, playerTeamType)
    if plateColor.a >= 1 then
        return originalUpdateUnitStatusBlip(self, blipIndex, localPlayerIsCommander, baseResearchRot, showHints, playerTeamType)
    end

    -- Vanilla copies the icon's alpha into its colour (GUIUnitStatus.lua:581), and that colour can
    -- be the shared global kWhite or kYellow. Keep it at 1 so our opacity never leaks into them.
    local blip = self.activeBlipList[blipIndex]
    blip.GraphicsItem:SetColor(kOpaque)

    originalUpdateUnitStatusBlip(self, blipIndex, localPlayerIsCommander, baseResearchRot, showHints, playerTeamType)

    if not blip.mngaInheritsAlpha then
        SetBlipItemsInheritAlpha(blip)
    end
    -- Created on first use by vanilla, so it can appear after the rest.
    if blip.AbilityBarBg and not blip.mngaAbilityInheritsAlpha then
        blip.AbilityBarBg:SetInheritsParentAlpha(true)
        blip.AbilityBar:SetInheritsParentAlpha(true)
        blip.mngaAbilityInheritsAlpha = true
    end

    blip.statusBg:SetColor(plateColor)
    local iconColor = blip.GraphicsItem:GetColor()
    iconColor.a = plateColor.a
    blip.GraphicsItem:SetColor(iconColor)
end

module.SetPlateOpacity(module.GetPlateOpacity and module.GetPlateOpacity() or 1)

local kVanillaRangeSq = GUIUnitStatus.kMaxUnitStatusDistance * GUIUnitStatus.kMaxUnitStatusDistance
local kWideRangeSq = GUIUnitStatus.kMaxMarkedUnitStatusDistance * GUIUnitStatus.kMaxMarkedUnitStatusDistance

local _, foundIn = debug.getupvaluex(GUIUnitStatus.Update, "kMaxUnitStatusDistanceSq")
if not foundIn then
    Shared.Message("[teamhp] kMaxUnitStatusDistanceSq not found, forced bars stay at 13 m")
    return
end

function module.SetWideRange(wide)
    local value = wide and kWideRangeSq or kVanillaRangeSq
    debug.setupvaluex(GUIUnitStatus.Update, "kMaxUnitStatusDistanceSq", value)
end

module.SetWideRange(module.GetIsRangeWidened and module.GetIsRangeWidened() or false)
