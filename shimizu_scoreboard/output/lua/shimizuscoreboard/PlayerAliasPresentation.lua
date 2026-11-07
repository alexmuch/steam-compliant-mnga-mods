-- Final-render aliases for name-bearing UI strings. This file is a post-hook
-- only: it never replaces network registrations or modifies network payloads.

local function WrapGUIChat(chat)
    if chat.SSBPlayerAliasAddMessageWrapped then return end
    chat.SSBPlayerAliasAddMessageWrapped = true
    local OldAddMessage = chat.AddMessage
    chat.AddMessage = function(self, playerColor, playerName, messageColor, messageText, isCommander, isRookie)
        if SSB_ApplyPlayerAliasesToText then
            playerName = SSB_ApplyPlayerAliasesToText(playerName)
        end
        return OldAddMessage(self, playerColor, playerName, messageColor, messageText, isCommander, isRookie)
    end
end

-- Shine exposes GUIChat instances after it has safely completed its own
-- source-qualified upvalue setup. Wrapping the instance here avoids a file hook
-- on GUIChat.lua, which would interfere with that setup.
if Shine and Shine.Hook and Shine.Hook.Add and not SSBPlayerAliasGUIChatHookInstalled then
    SSBPlayerAliasGUIChatHookInstalled = true
    Shine.Hook.Add("OnGUIChatInitialised", "SSBAliasGUIChatPresentation", WrapGUIChat,
        Shine.Hook.MAX_PRIORITY)
end

if ChatUI_AddSystemMessage and not SSBPlayerAliasSystemMessageWrapped then
    SSBPlayerAliasSystemMessageWrapped = true
    local OldAddSystemMessage = ChatUI_AddSystemMessage

    function ChatUI_AddSystemMessage(messageText)
        if SSB_ApplyPlayerAliasesToText then
            messageText = SSB_ApplyPlayerAliasesToText(messageText)
        end
        return OldAddSystemMessage(messageText)
    end
end

local function WrapPokerSeatNames(plugin)
    if type(plugin) ~= "table" or plugin.SSBPlayerAliasSeatStateWrapped
            or type(plugin.ReceiveSeatState) ~= "function" then return end
    plugin.SSBPlayerAliasSeatStateWrapped = true
    local OldReceiveSeatState = plugin.ReceiveSeatState

    function plugin:ReceiveSeatState(data)
        if type(data) == "table" and data.SteamID and data.SteamID ~= ""
                and SSB_GetPlayerDisplayNameBySteamId then
            data.Name = SSB_GetPlayerDisplayNameBySteamId(data.SteamID, data.Name)
        end
        return OldReceiveSeatState(self, data)
    end
end

-- Poker's seat DTO carries a stable Steam ID, so resolve it before the plugin
-- stores and renders the seat. The receiver dispatch remains owned by Shine.
if Shine and Shine.Hook and Shine.Hook.Add then
    if Shine.Plugins then WrapPokerSeatNames(Shine.Plugins.poker) end
    Shine.Hook.Add("OnPluginLoad", "SSBAliasPokerSeatPresentation", function(name, plugin)
        if name == "poker" then WrapPokerSeatNames(plugin) end
    end, Shine.Hook.MAX_PRIORITY)
end
