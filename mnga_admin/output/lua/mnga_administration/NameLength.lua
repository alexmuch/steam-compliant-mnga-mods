-- Player names are additionally constrained by the server-side Name Guard
-- extension's visual-width budget. This value must be identical in every VM
-- because several network message schemas derive their capacity from it.
kMaxNameLength = 25
