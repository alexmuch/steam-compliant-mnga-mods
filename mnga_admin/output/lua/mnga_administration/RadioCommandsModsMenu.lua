table.insert( gModsCategories, {
    categoryName = "mngaRadioCommands",
    entryConfig = {
        name = "mngaRadioCommandsEntry",
        class = GUIMenuCategoryDisplayBoxEntry,
        params = { label = "RADIO COMMANDS" }
    },
    contentsConfig = ModsMenuUtils.CreateBasicModsMenuContents {
        layoutName = "mngaRadioCommandsOptions",
        contents = {
            {
                name = "mngaRadioCommandsDescription",
                class = GUIMenuText,
                params = { text = "Open the numbered radio command menu." }
            },
            {
                name = "mngaRadioCommandsBind",
                class = OP_Keybind,
                params = {
                    optionPath = "input/RadioCommands",
                    optionType = "string",
                    default = "None",
                    bindGroup = "mngaRadioCommands"
                },
                properties = { { "Label", "Radio Commands" } }
            },
            {
                name = "mngaRadioCommandsVolume",
                class = OP_Number,
                params = {
                    useResetButton = true,
                    optionPath = "mnga/radioVolume",
                    optionType = "int",
                    default = 20,
                    minValue = 0,
                    maxValue = 100,
                    decimalPlaces = 0
                },
                properties = { { "Label", "Radio Volume: " } }
            }
        }
    }
} )
