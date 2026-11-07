local Plugin = ...
local kOptionKey = "ssbSpectatorScoreboardViewMode"
local kLegacyOptionKey = "mngaSpectatorScoreboardViewMode"
local kCountryLabelExcludedSteamIDs = {
    [1896475315] = true
}
local EnhancedPlayerData = {}
local SGUI = Shine.GUI

Plugin.ConfigGroup = { Key = "SCOREBOARD_CLIENT_CONFIG_TAB" }
Plugin.SpectatorScoreboardViewMode = table.AsEnum({
    "USE_SERVER_SETTINGS",
    "ALWAYS_SHOW_ALL"
})

local function Normalize(value)
    if value == "UseServerSettings" then return "USE_SERVER_SETTINGS" end
    if value == "AlwaysShowAll" then return "ALWAYS_SHOW_ALL" end
    if value == "USE_SERVER_SETTINGS" or value == "ALWAYS_SHOW_ALL" then return value end
    return nil
end

function Plugin:GetPersistentViewMode()
    local value = Normalize(Client.GetOptionString(kOptionKey, ""))
    if value then return value end
    local legacy = Normalize(Client.GetOptionString(kLegacyOptionKey, ""))
    if legacy then
        Print("[SSB] Migrating legacy MNGA spectator scoreboard preference: %s", legacy)
        Client.SetOptionString(kOptionKey, legacy)
        return legacy
    end
    return nil
end

function Plugin:SetPersistentViewMode(value)
    value = Normalize(value) or "USE_SERVER_SETTINGS"
    Client.SetOptionString(kOptionKey, value)
    self.Config.SpectatorScoreboardViewMode = value
    self:SaveConfig(true)
    if Scoreboard_ReloadPlayerData then Scoreboard_ReloadPlayerData() end
    return value
end

function SSB_GetSpectatorScoreboardViewMode()
    local instance = Shine and Shine.Plugins and Shine.Plugins["shimizuscoreboard"]
    if instance and instance.GetPersistentViewMode then
        return instance:GetPersistentViewMode() or "USE_SERVER_SETTINGS"
    end
    return "USE_SERVER_SETTINGS"
end

function Plugin:ReceiveEnhancedPlayerData(Data)
    local SteamID = tonumber(Data.SteamID)
    if not SteamID then return end
    EnhancedPlayerData[SteamID] = {
        Country = Data.Country, IsProxy = Data.IsProxy, IsAdmin = Data.IsAdmin
    }
    if Scoreboard_ReloadPlayerData then Scoreboard_ReloadPlayerData() end
end

function Plugin:ReceiveEnhancedPlayerRemoved(Data)
    EnhancedPlayerData[tonumber(Data.SteamID)] = nil
end

function SSB_GetQueuePosition(SteamID)
    local Instance = Shine and Shine.Plugins and Shine.Plugins.shimizuscoreboard
    if not Instance or not Instance.dt.EnableQueueInfo then return nil end
    return MNGAReadyRoomQueuePositions and MNGAReadyRoomQueuePositions[tonumber(SteamID)] or nil
end

local function StripEnhancedTooltipAnnotations(Description, SteamID)
    -- Old ESB wrappers and stale rows may hand us text that has already been
    -- decorated. Reduce it to SSB's base before adding current metadata so
    -- repeated hover updates are idempotent.
    while string.sub(Description, 1, 18) == "! Server Admin !\n\n" do
        Description = string.sub(Description, 19)
    end
    Description = string.gsub(Description, "\n\nCountry: [^\n]*", "")
    Description = string.gsub(Description, "\nVPN Detected!", "")
    Description = string.gsub(Description, "\nQueue: %d+", "")

    return Description
end

function SSB_AppendEnhancedTooltip(Description, SteamID, IsSpectator)
    if not Description then return Description end
    SteamID = tonumber(SteamID)
    Description = StripEnhancedTooltipAnnotations(Description, SteamID)
    local Instance = Shine and Shine.Plugins and Shine.Plugins.shimizuscoreboard
    local Data = EnhancedPlayerData[SteamID]
    if Data then
        if Instance and Instance.dt.EnableShowAdmin and Data.IsAdmin then
            Description = "! Server Admin !\n\n" .. Description
        end
        if Instance and Instance.dt.EnableLocationInfo then
            if not kCountryLabelExcludedSteamIDs[SteamID] then
                Description = Description .. string.format("\n\nCountry: %s", Data.Country or "Unknown")
            end
            if Data.IsProxy then Description = Description .. "\nVPN Detected!" end
        end
    end
    local Position = IsSpectator and SSB_GetQueuePosition(SteamID)
    if Position then Description = Description .. string.format("\nQueue: %d", Position) end
    return Description
end

local function HumanNumber(Number)
    if Number >= 1000000 then return string.format("%.2fm", Number / 1000000) end
    if Number >= 1000 then return string.format("%.1fk", Number / 1000) end
    return tostring(Number)
end

function SSB_AppendEnhancedTeamSkill(Header, TeamNumber)
    local Instance = Shine and Shine.Plugins and Shine.Plugins.shimizuscoreboard
    if not Instance or TeamNumber < 1 or TeamNumber > 2 then return Header end
    local GameInfo = GetGameInfoEntity and GetGameInfoEntity()
    local ShowAverage = Instance.dt.EnableTeamAvgSkill
        or (Instance.dt.EnableTeamAvgSkillPregame and (not GameInfo or not GameInfo:GetGameStarted()))
    if not ShowAverage then return Header end
    local Average = TeamNumber == 1 and Instance.dt.MarineAvgSkill or Instance.dt.AlienAvgSkill
    local Total = TeamNumber == 1 and Instance.dt.MarineTotalSkill or Instance.dt.AlienTotalSkill
    local Suffix = string.format(", %d Avg Skill", Average)
    if Instance.dt.EnableTeamTotalSkill then
        Suffix = Suffix .. string.format(", %s Total Skill", HumanNumber(Total))
    end
    return Header:sub(-1) == ")" and Header:sub(1, -2) .. Suffix .. ")" or Header .. Suffix
end

function Plugin:CloseAliasModal()
    if self.AliasModal and SGUI.IsValid(self.AliasModal) then self.AliasModal:Close() end
    self.AliasModal = nil
end

function Plugin:OpenAliasModal(SteamID, RealName)
    self:CloseAliasModal()
    local PluginInstance = self

    local Units = SGUI.Layout.Units
    local Scaled = Units.HighResScaled
    local Spacing = Units.Spacing
    local Percent = Units.Percentage
    local Font = { Family = "kAgencyFB", Size = Scaled(27) }
    local Modal = SGUI:Create("Modal")
    self.AliasModal = Modal
    Modal.TitleBarHeight = Scaled(28)
    Modal:AddTitleBar("Change Nick: " .. RealName, Font)

    local Elements = SGUI:BuildTree({
        Parent = Modal,
        { Class = "Label", Props = {
            Text = "Alias (leave blank to remove):", AutoFont = Font
        } },
        { ID = "Alias", Class = "TextEntry", Props = {
            AutoFont = Font,
            AutoSize = Units.UnitVector(Percent.ONE_HUNDRED, Scaled(36)),
            Text = SSB_GetPlayerAlias(SteamID) or "",
            Margin = Spacing(0, Scaled(4), 0, Scaled(8))
        } },
        { ID = "Error", Class = "Label", Props = {
            Text = "", AutoFont = { Family = "kAgencyFB", Size = Scaled(20) },
            Colour = Colour(1, 0.25, 0.25),
            Margin = Spacing(0, 0, 0, Scaled(5))
        } },
        { Class = "Horizontal", Type = "Layout", Props = {
            AutoSize = Units.UnitVector(Percent.ONE_HUNDRED, Scaled(36)), Fill = false
        }, Children = {
            { ID = "Cancel", Class = "Button", Props = {
                Fill = true, AutoFont = Font, Text = "Cancel"
            } },
            { ID = "Save", Class = "Button", Props = {
                Fill = true, AutoFont = Font, Text = "Save", StyleName = "SuccessButton",
                Margin = Spacing(Scaled(8), 0, 0, 0)
            } }
        } }
    })

    Modal.Layout:SetPadding(Spacing(Scaled(16), Scaled(4), Scaled(16), Scaled(10)))
    Modal:SetSize(Vector2(Scaled(440):GetValue(), Modal:GetContentSizeForAxis(2)))
    Modal:SetPos(Vector2(
        (Client.GetScreenWidth() - Modal:GetSize().x) * 0.5,
        (Client.GetScreenHeight() - Modal:GetSize().y) * 0.5
    ))
    Modal:SetDraggable(true)
    Modal:PopUp()

    local OldPlayerKeyPress = Modal.PlayerKeyPress
    function Modal:PlayerKeyPress(Key, Down)
        if Down and Key == InputKey.Escape then
            PluginInstance:CloseAliasModal()
            return true
        end
        return OldPlayerKeyPress(self, Key, Down)
    end

    local function Save()
        local ok, err = SSB_SetPlayerAlias(SteamID, Elements.Alias:GetText())
        if not ok then
            Elements.Error:SetText(err)
            return
        end
        self:CloseAliasModal()
    end
    Elements.Save.DoClick = Save
    Elements.Cancel.DoClick = function() self:CloseAliasModal() end
    Elements.Alias.OnEnter = Save
    Elements.Alias:RequestFocus()
    Elements.Alias:SelectAll()
end

function Plugin:AddAliasScoreboardAction(Scoreboard, ClientIndex)
    local record = Scoreboard_GetPlayerRecord(ClientIndex)
    local steamId = record and tonumber(record.SteamId)
    if not steamId or steamId <= 0 or steamId == Client.GetSteamId() then return end

    local menu = Scoreboard and Scoreboard.hoverMenu
    local links = menu and menu.links
    if not links then return end
    local background, highlight, text
    for i = #links, 1, -1 do
        local button = links[i]
        if not button.isSeparator and button.link then
            background = button.bgColor
            highlight = button.bgHighlightColor
            text = button.link:GetColor()
            break
        end
    end
    if not background then return end

    menu:AddSeparator("SSBPlayerAliasActions")
    menu:AddButton("Change Nick", background, highlight, text, function()
        self:OpenAliasModal(steamId, record.Name or "Unknown")
    end)
    menu:AdjustMenuSize()
end

function Plugin:SetupAliasScoreboardIntegration()
    if not SSB_RegisterScoreboardIntegration then return false end
    SSB_RegisterScoreboardIntegration("ssb_player_aliases", {
        OnMenuOpened = function(scoreboard, clientIndex)
            self:AddAliasScoreboardAction(scoreboard, clientIndex)
        end
    })
    return true
end

function Plugin:SetupViewModeCommand()
    if self:HasRegisteredCommand("sh_ssb_spectator_view") then return end
    local command = self:BindCommand("sh_ssb_spectator_view", function(value)
        self:SetPersistentViewMode(value)
    end)
    command:AddParam({
        Type = "enum",
        Values = Plugin.SpectatorScoreboardViewMode,
        Optional = true,
        Default = function() return self.Config.SpectatorScoreboardViewMode end
    })
end

Plugin.ClientConfigSettings = {
    {
        ConfigKey = "SpectatorScoreboardViewMode",
        Command = "sh_ssb_spectator_view",
        Type = "Radio",
        Options = {
            Plugin.SpectatorScoreboardViewMode.USE_SERVER_SETTINGS,
            Plugin.SpectatorScoreboardViewMode.ALWAYS_SHOW_ALL
        },
        Description = "SPECTATOR_SCOREBOARD_VIEW_MODE_DESCRIPTION",
        HelpText = "SPECTATOR_SCOREBOARD_WAIVER",
        OnChange = function(self, value) self:SetPersistentViewMode(value) end
    }
}

function Plugin:Initialise()
    local value = self:GetPersistentViewMode() or Normalize(self.Config.SpectatorScoreboardViewMode)
        or "USE_SERVER_SETTINGS"
    self:SetPersistentViewMode(value)
    self:SetupViewModeCommand()
    if not self:SetupAliasScoreboardIntegration() then
        Shine.Hook.Add("Think", "SSBAliasDeferredScoreboardIntegration", function()
            if self:SetupAliasScoreboardIntegration() then
                Shine.Hook.Remove("Think", "SSBAliasDeferredScoreboardIntegration")
            end
        end)
    end
    self.Enabled = true
    return true
end

function Plugin:Cleanup()
    self:CloseAliasModal()
    if SSB_UnregisterScoreboardIntegration then
        SSB_UnregisterScoreboardIntegration("ssb_player_aliases")
    end
    Shine.Hook.Remove("Think", "SSBAliasDeferredScoreboardIntegration")
    EnhancedPlayerData = {}
    self.BaseClass.Cleanup(self)
    self.Enabled = false
end
