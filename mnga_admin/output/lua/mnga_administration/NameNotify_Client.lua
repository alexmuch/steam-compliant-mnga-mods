-- Name-aware Shine chat receiver (.claude/docs/player-alias-coverage.md):
-- fill each name slot with this viewer's SSB alias (by Steam ID), falling
-- back to the real name, then show the line like a Shine coloured message.

if not Client or MNGANameNotifyClientInstalled then return end
MNGANameNotifyClientInstalled = true

local StringChar = string.char
local Gsub = string.gsub

local function OnNameNotify( Message )
    if not Shine or not Shine.AddChatText then return end
    local Text = Message.Template
    for i = 1, MNGA_NAME_NOTIFY_SLOTS do
        local SteamID = Message[ "SteamID" .. i ]
        local Name = Message[ "Name" .. i ]
        local Display = Name
        if SteamID > 0 and SSB_GetPlayerDisplayNameBySteamId then
            Display = SSB_GetPlayerDisplayNameBySteamId( SteamID, Name ) or Name
        end
        -- Function replacement: a "%" in a name must not act as a capture ref.
        Text = Gsub( Text, StringChar( i ), function() return Display end )
    end
    Print( "[namenotify] shown=%s", Text )
    Shine.AddChatText( Message.RP, Message.GP, Message.BP, Message.Prefix,
        Message.R / 255, Message.G / 255, Message.B / 255, Text )
end

Client.HookNetworkMessage( "MNGANameNotify", OnNameNotify )
