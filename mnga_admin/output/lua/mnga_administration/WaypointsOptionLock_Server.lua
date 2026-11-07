-- Commander orders are now paced (server marker interval) and their voice
-- lines share a client cooldown, so players may no longer hide commander
-- waypoints. Vanilla's ClientConnect hook sends every DisabledClientOptions
-- entry as a DisabledOption message; the client then pins the advanced option
-- to its default (waypoints on) and ignores the menu checkbox.
if Server and DisabledClientOptions then
    if not table.icontains(DisabledClientOptions, "wps") then
        table.insert(DisabledClientOptions, "wps")
    end
end
