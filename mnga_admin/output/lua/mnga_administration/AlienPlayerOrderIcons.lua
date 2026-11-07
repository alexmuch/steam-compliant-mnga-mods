-- Heal previously existed only as an automatic waypoint, without a button icon.
local offsets = debug.getupvaluex(GetMaterialXYOffset, "kTechIdToMaterialOffset")
if offsets then
    offsets[kTechId.Heal] = offsets[kTechId.NeedHealingMarker]
    offsets[kTechId.AutoHeal] = offsets[kTechId.Heal]
else
    Print("[AlienOrders] Heal icon mapping unavailable: material-offset upvalue missing")
end
