Script.Load("lua/GUI/GUIObject.lua")
Script.Load("lua/GUI/GUIParagraph.lua")
Script.Load("lua/GUI/layouts/GUIListLayout.lua")
Script.Load("lua/GUI/style/GUIStyledText.lua")
Script.Load("lua/menu2/GUIMenuBasicBox.lua")
Script.Load("lua/menu2/GUIMenuTabbedBox.lua")
Script.Load("lua/menu2/widgets/GUIMenuTabButtonWidget.lua")
Script.Load("lua/menu2/widgets/GUIMenuScrollPane.lua")

local kInnerBackgroundSideSpacing = 32
local kInnerBackgroundTopSpacing = 212
local kInnerBackgroundBottomSpacing = 18
local kUnderlapYSize = 113
local kTabHeight = 94
local kTabMinWidth = 150

local kTabButtonFont = { family = "MicrogrammaBold", size = 48 }
local kTitleFont = { family = "AgencyBold", size = 60 }
local kTitleStyle =
{
    padding = 17,
    shader = "shaders/GUI/menu/mainBarButtonGlow.surface_shader",
    inputs =
    {
        [1] = { name = "innerGlowBlur", value = GUIStyle.TextBlur(3) },
        [2] = { name = "innerGlowColor", value = HexToColor("7df7ff", 0.1) },
        [3] = { name = "outerGlowBlur", value = GUIStyle.TextBlur(15) },
        [4] = { name = "outerGlowColor", value = HexToColor("75c6ff", 0.49) },
        [5] = { name = "baseTexture", value = "__Text" },
        [6] = { name = "textColor", value = HexToColor("ffffff") },
    }
}

local kStyleToFontsMap =
{
    [0] = { family = "Arial", size = 28 },
    [1] = { family = "AgencyBold", size = 68 },
    [2] = { family = "AgencyBold", size = 56 },
    [3] = { family = "Agency", size = 50 },
}

local kStyleToColorMap =
{
    [0] = Color(1, 1, 1),
    [1] = MenuStyle.kHighlight,
    [2] = MenuStyle.kOptionHeadingColor,
    [3] = MenuStyle.kOptionHeadingColor,
}

local baseClass = GUIMenuTabbedBox
class "GUIMNGAInfo" (baseClass)

GUIMNGAInfo:AddClassProperty("IsOpen", false)

function GUIMNGAInfo:Initialize(params, errorDepth)
    errorDepth = (errorDepth or 1) + 1
    baseClass.Initialize(self, params, errorDepth)

    self.contentObjects = {}
    self:AlignCenter()
    self:SetLayer(999)

    self.title = CreateGUIObject("title", GUIStyledText, self, { style = kTitleStyle, font = kTitleFont, align = "top" })
    self.title:SetText("MNGA INFORMATION")
    self.title:SetY(-23)
    self:InitializeContentHolders()

    self.closeButton = CreateGUIObject("closeButton", GUIMenuTabButtonWidget, self)
    self.closeButton:SetTabHeight(kTabHeight)
    self.closeButton:SetTabMinWidth(kTabMinWidth)
    self.closeButton:AlignBottom()
    self.closeButton:SetFont(kTabButtonFont)
    self.closeButton:SetLabel("CLOSE")
    self:HookEvent(self.closeButton, "OnPressed", self.Close)
    self:HookEvent(self.closeButton, "OnTabSizeChanged", self.SetTabSize)
    self:SetTabSize(self.closeButton:GetTabSize())

    self:SetSize(2300, 1600)
    self:SetY(900)
    self:Close()
end

function GUIMNGAInfo:InitializeContentHolders()
    self.innerBackground = CreateGUIObject("innerBackground", GUIMenuBasicBox, self)
    self.innerBackground:SetPosition(kInnerBackgroundSideSpacing, kInnerBackgroundTopSpacing - kUnderlapYSize)
    self:HookEvent(self, "OnSizeChanged", self.UpdateInnerBackgroundSize)

    self.scrollPane = CreateGUIObject("scrollPane", GUIMenuScrollPane, self.innerBackground)
    self.listLayout = CreateGUIObject("listLayout", GUIListLayout, self.scrollPane, { orientation = "vertical", spacing = 0 })
    self.scrollPane:HookEvent(self.listLayout, "OnSizeChanged", self.scrollPane.SetPaneSize)
end

local function AddLineGroup(self, text, style, lineNumber)
    local lineGroupObject = CreateGUIObject(string.format("lineGroup_%d", lineNumber), GUIParagraph, self.listLayout,
    {
        justification = GUIItem.Align_Min,
        font = kStyleToFontsMap[style] or kStyleToFontsMap[0],
        color = kStyleToColorMap[style] or kStyleToColorMap[0],
        paragraphSize = Vector(self.scrollPane:GetSize().x, -1, 0),
        text = text,
    })
    table.insert(self.contentObjects, lineGroupObject)
end

function GUIMNGAInfo:LoadText(infoData)
    for index = 1, #self.contentObjects do
        self.contentObjects[index]:Destroy()
    end
    self.contentObjects = {}

    local lines = string.Explode(infoData or "", "\n")
    local styleToken = GetMNGAInfoStyleToken()
    local lineGroup = ""
    local lineGroupStyle = 0

    for index = 1, #lines do
        local processedLine, style = string.gsub(lines[index], styleToken, "")
        processedLine = string.format("  %s", processedLine)
        if index == 1 then
            lineGroup = processedLine
            lineGroupStyle = style
        elseif style ~= lineGroupStyle or string.len(lineGroup) + string.len(processedLine) > 500 then
            AddLineGroup(self, lineGroup, lineGroupStyle, index)
            lineGroup = processedLine
            lineGroupStyle = style
        else
            lineGroup = string.format("%s\n%s", lineGroup, processedLine)
        end
    end

    AddLineGroup(self, lineGroup, lineGroupStyle, #lines)
end

function GUIMNGAInfo:UpdateInnerBackgroundSize()
    self.innerBackground:SetSize(self:GetSize() - Vector(kInnerBackgroundSideSpacing * 2, kInnerBackgroundBottomSpacing + kInnerBackgroundTopSpacing, 0))
    self.scrollPane:SetSize(self.innerBackground:GetSize().x, self.innerBackground:GetSize().y)
end

function GUIMNGAInfo:OnKey(key, down)
    if key == InputKey.Escape and down then
        self:Close()
        return true
    end
end

function GUIMNGAInfo:Close()
    self:StopListeningForKeyInteractions()
    self:SetVisible(false)
    self:ClearModal()
    self:SetIsOpen(false)
    self:FireEvent("Closed")
end

function GUIMNGAInfo:Open()
    self:ListenForKeyInteractions()
    self:SetVisible(true)
    self:SetModal()
    self:SetIsOpen(true)
    self:FireEvent("Opened")
end
