-- Edit this text to populate the MNGA main-menu information panel.
-- Prefix a line with one to three # characters to select its heading style.
function GetMNGAInfoStyleToken()
    return "#"
end

gMNGAInfoData = [[
#MNGA QoL help



##Information

Tribute system: specs can volunteer to command to skip queue. !tribute help

Start of game AFK check:  45 seconds after game starts

Multi-ping: when dead, right click on map to ping.

sh_swap: you can't use this, but admin can swap you back into game if you crash.

## Full change log

Obs and armslab cannot be placed in walls or other world geometry
Marine structures cannot overlap power nodes
No deadends: Drifters, cysts and other alien structures cannot be trapped by other alien structures, same for arcs.
Reworked evolve mechanics: you are allowed to evolve upgrades in small vents, and evolving doesn't teleport or move your egg horizontally
Multi-ping: each player has their own ping timer, and pings show up with your name
Enemy group: add player to enemy group so you don't end up on the same team.
Tribute system: specs can volunteer to command to skip queue.
25 spec slots: you are allowed to watch games / brb-afk without getting kicked
New vote types: gag, move to spec, comm-ban, ban-start-vote
Chat announcement when a player leaves team / server
sh_swap command: if your game crashes, an admin can swap you back into the game after you reconnect
Start of game AFK check: AFK players are moved to spec 45 seconds after game starts. No need to call kick votes 1 by 1.
Reworked unstuck: now it actually works when it needs to
No dodging vote kicks: using reconnect before votekick goes through results in getting the temp ban anyway
No spamming vote: starting a vote that fails stops a person from calling the same vote again for 5 minutes
Transparent ELO system: player ELO gain/loss report on round end, full details available on ns2stats
Tier 8 and Tier 9 ranks with unique emblems, and Comm Tier Insignias shown as well.
]]
