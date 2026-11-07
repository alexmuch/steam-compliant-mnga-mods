Script.Load("lua/AdvancedOptions.lua")
Script.Load("lua/menu2/widgets/GUIMenuDividerWidget.lua")

-- Vanilla Advanced > HUD nameplate options mirrored here. Both widgets share one option path,
-- so the saved value is shared; these mirrors only make the other widget show the change.
local kNameplateMirrors = {
    { vanilla = "nameplates", ours = "shimizuNameplates" },
    { vanilla = "smallnps", ours = "shimizuSmallNameplates" }
}

local function MirrorValue(targetName, value)
    local menu = GetOptionsMenu and GetOptionsMenu()
    local target = menu and menu:GetOptionWidget(targetName)
    if not target then
        return false
    end
    if target:GetValue() ~= value then
        target:SetValue(value)
    end
    return true
end

local function RefreshTeamHealthBars()
    if MNGA_TeamHealthBars_Refresh then
        MNGA_TeamHealthBars_Refresh()
    end
end

local function SetNameplateOpacity(self)
    if MNGA_TeamHealthBars_SetOpacity then
        MNGA_TeamHealthBars_SetOpacity(self:GetValue())
    end
end

local function SetWeeklyQuestsVisible(self)
    if MNGA_WeeklyQuests_SetVisible then
        MNGA_WeeklyQuests_SetVisible(self:GetValue())
    end
end

-- Sub-heading inside the list; same widget as the vanilla Controls headers, coloured instead of grey.
local function CreateHeading(name, label)
    return {
        name = name,
        class = GUIMenuDividerWidget,
        properties = {
            { "Label", label }
        },
        postInit = function(self)
            self:AlignTop()
            self:SetColor(MenuStyle.kHighlight)
        end
    }
end

local kOurMirrorUpdates = {}
for i = 1, #kNameplateMirrors do
    local pair = kNameplateMirrors[i]
    local option = AdvancedOptions[pair.vanilla]
    if option then
        local originalUpdate = option.immediateUpdate
        option.immediateUpdate = function(self, value, prevValue)
            if originalUpdate then
                originalUpdate(self, value, prevValue)
            end
            MirrorValue(pair.ours, self:GetValue())
        end
        -- If the vanilla widget is missing, run its update ourselves (smallnps restarts GUIUnitStatus).
        kOurMirrorUpdates[pair.ours] = function(self, value, prevValue)
            if not MirrorValue(pair.vanilla, self:GetValue()) and originalUpdate then
                originalUpdate(self, value, prevValue)
            end
        end
    else
        Shared.Message(string.format("[teamhp] AdvancedOptions[%s] missing, no mirror", pair.vanilla))
    end
end

local kNameplatesOption = AdvancedOptions["nameplates"] or {}
local kSmallNameplatesOption = AdvancedOptions["smallnps"] or {}

local kNameplateChoices = {}
for i, v in ipairs(kNameplatesOption.choices or {}) do
    kNameplateChoices[i] = { value = i - 1, displayString = v }
end

table.insert( gModsCategories, {
    categoryName = "shimizuQoL",
    entryConfig = {
        name = "shimizuQoLEntry",
        class = GUIMenuCategoryDisplayBoxEntry,
        params = {
            label = "SHIMIZU QOL"
        }
    },
    contentsConfig = ModsMenuUtils.CreateBasicModsMenuContents {
        layoutName = "shimizuQoLOptions",
        contents = {
            CreateHeading("shimizuHeadingHud", "HUD"),
            {
                name = "shimizuShowCommanderCooldownNumbers",
                class = OP_TT_Checkbox,
                params = {
                    optionPath = "shimizu/showCommanderCooldownNumbers",
                    optionType = "bool",
                    default = true,
                    tooltip = "Show whole seconds remaining over commander ability cooldowns."
                },
                properties = {
                    { "Label", "Show Cooldown Numbers" }
                }
            },
            {
                name = "shimizuShowMutedVoiceIndicator",
                class = OP_TT_Checkbox,
                params = {
                    optionPath = "shimizu/showMutedVoiceIndicator",
                    optionType = "bool",
                    default = true,
                    tooltip = "Show a \"Muted\" voice-chat bar while a player you voice-muted is talking, so you can avoid talking over them. Their voice stays muted and their name is not shown."
                },
                properties = {
                    { "Label", "Show Muted Speakers" }
                }
            },
            {
                -- Read by mngaweeklyquests client.lua; hides the quest log only, tracking keeps running.
                name = "shimizuShowWeeklyQuests",
                class = OP_TT_Checkbox,
                params = {
                    optionPath = "shimizu/showWeeklyQuests",
                    optionType = "bool",
                    default = true,
                    tooltip = "Show the Weekly Quests log in the Ready Room. Turning this off only hides the log: quests still progress and pay out, and completions still print in chat.",
                    immediateUpdate = SetWeeklyQuestsVisible
                },
                properties = {
                    { "Label", "Show Weekly Quests" }
                }
            },
            CreateHeading("shimizuHeadingSound", "SOUND"),
            {
                -- Read/written by mngaforcednotifications (sourceshimizushine); same setting as sh_dfn.
                name = "shimizuNotificationSounds",
                class = OP_TT_Checkbox,
                params = {
                    optionPath = "shimizu/notificationSounds",
                    optionType = "bool",
                    default = true,
                    tooltip = "Play a sound when the game starts, when you enter the Ready Room from the queue, on connect and on AFK warnings. Same as the sh_dfn console command."
                },
                properties = {
                    { "Label", "Enable sound notifications for game start / enter ready-room from queue" }
                }
            },
            {
                -- Read/written by mngaforcednotifications (sourceshimizushine); same setting as sh_dfnvolume.
                name = "shimizuNotificationSoundVolume",
                class = OP_TT_Number,
                params = {
                    useResetButton = true,
                    optionPath = "shimizu/notificationSoundVolume",
                    optionType = "int",
                    default = 100,
                    minValue = 0,
                    maxValue = 200,
                    decimalPlaces = 0,
                    tooltip = "Volume of the notification sounds, in percent (0-200). Same as the sh_dfnvolume console command."
                },
                properties = {
                    { "Label", "Notification Sound Volume: " }
                }
            },
            {
                -- Read by GetMangaVolumeScale (mngaadministration client); same setting as !mangavolume.
                name = "shimizuMangaVolume",
                class = OP_TT_Number,
                params = {
                    useResetButton = true,
                    optionPath = "mngaMiniGameVolume",
                    optionType = "int",
                    default = 100,
                    minValue = 0,
                    maxValue = 100,
                    decimalPlaces = 0,
                    tooltip = "Volume of mini-game sounds (Poker, Match 3), in percent (0-100). Same as the !mangavolume command."
                },
                properties = {
                    { "Label", "Mini-game Sound Volume: " }
                }
            },
            CreateHeading("shimizuHeadingNameplates", "NAMEPLATES"),
            {
                -- Read by TeamHealthBars_Client.lua (0 Always, 1 Hold key, 2 Vanilla).
                name = "shimizuTeamHealthBarsMode",
                class = OP_TT_Choice,
                params = {
                    useResetButton = true,
                    optionPath = "shimizu/teamHealthBarsMode",
                    optionType = "int",
                    default = 0,
                    tooltip = "Show the mouse-over nameplate (name, health bar, hint) without aiming, up to 20 m: teammates, and enemies your team has spotted (on the minimap). Enemy players show a name only, like vanilla mouse-over. Always: all the time. Hold key: while the Nameplate Visibility key is held. Vanilla: only the unit under your crosshair. Commanders keep their own H toggle.",
                    immediateUpdate = RefreshTeamHealthBars
                },
                properties = {
                    { "Label", "Nameplate Visibility: " },
                    { "Choices", {
                        { value = 0, displayString = "Always" },
                        { value = 1, displayString = "Hold key" },
                        { value = 2, displayString = "Vanilla" }
                    } }
                }
            },
            {
                name = "shimizuTeamHealthBarsKey",
                class = OP_Keybind,
                params = {
                    optionPath = "input/MNGATeamHealthBars",
                    optionType = "string",
                    default = "None",
                    bindGroup = "mngaTeamHealthBars"
                },
                properties = { { "Label", "Nameplate Visibility Key (hold)" } }
            },
            {
                name = "shimizuTeamHealthBarsScope",
                class = OP_TT_Choice,
                params = {
                    useResetButton = true,
                    optionPath = "shimizu/teamHealthBarsScope",
                    optionType = "int",
                    default = 1,
                    tooltip = "Which units get the always-on nameplates.",
                    immediateUpdate = RefreshTeamHealthBars
                },
                properties = {
                    { "Label", "Nameplate Visibility For: " },
                    { "Choices", {
                        { value = 0, displayString = "Players only" },
                        { value = 1, displayString = "Players and structures" }
                    } }
                }
            },
            {
                -- Same option as Advanced > HUD > Nameplate style; kept in sync both ways.
                name = "shimizuNameplates",
                class = OP_TT_Choice,
                params = {
                    useResetButton = true,
                    optionPath = kNameplatesOption.optionPath or "CHUD_Nameplates",
                    optionType = "int",
                    default = kNameplatesOption.default or 0,
                    tooltip = kNameplatesOption.tooltip,
                    immediateUpdate = kOurMirrorUpdates.shimizuNameplates
                },
                properties = {
                    { "Label", kNameplatesOption.label or "Nameplate Style: " },
                    { "Choices", kNameplateChoices }
                }
            },
            {
                -- Same option as Advanced > HUD > Small nameplates; kept in sync both ways.
                name = "shimizuSmallNameplates",
                class = OP_TT_Checkbox,
                params = {
                    useResetButton = true,
                    optionPath = kSmallNameplatesOption.optionPath or "CHUD_SmallNameplates",
                    optionType = "bool",
                    default = kSmallNameplatesOption.default or false,
                    tooltip = kSmallNameplatesOption.tooltip,
                    immediateUpdate = kOurMirrorUpdates.shimizuSmallNameplates
                },
                properties = {
                    { "Label", kSmallNameplatesOption.label or "Small Nameplates" }
                }
            },
            {
                -- Read by TeamHealthBars_Client.lua, applied in TeamHealthBars_GUIUnitStatus.lua.
                name = "shimizuNameplateOpacity",
                class = OP_TT_Number,
                params = {
                    useResetButton = true,
                    optionPath = "shimizu/nameplateOpacity",
                    optionType = "int",
                    default = 100,
                    minValue = 0,
                    maxValue = 100,
                    decimalPlaces = 0,
                    tooltip = "Opacity of nameplates and their status icons, in percent (0-100). Applies in all Nameplate Visibility modes.",
                    immediateUpdate = SetNameplateOpacity
                },
                properties = {
                    { "Label", "Nameplate Opacity: " }
                }
            }
        }
    }
} )
