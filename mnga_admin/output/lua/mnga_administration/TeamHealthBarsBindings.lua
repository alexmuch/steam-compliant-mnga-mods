local Defaults = debug.getupvaluex( GetDefaultInputValue, "defaults" )
if Defaults then
    table.insert( Defaults, { "MNGATeamHealthBars", "None" } )
end
