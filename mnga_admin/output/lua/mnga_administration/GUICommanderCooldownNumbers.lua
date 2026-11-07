local kOptionPath = "shimizu/showCommanderCooldownNumbers"
local kUrgentThreshold = 3
local kCooldownFontSize = 44
local kCooldownYellow = Color( 1, 0.85, 0, 1 )
local kCooldownRed = Color( 1, 0.12, 0.08, 1 )

-- Alien and marine panels each override InitializeButtons, but both finish by
-- calling this shared base implementation. Hooking it covers both concrete
-- commander panels as well as resolution-driven reinitialization.
local oldSharedInitializeButtons = GUICommanderButtons.SharedInitializeButtons
function GUICommanderButtons:SharedInitializeButtons( SettingsTable )
    oldSharedInitializeButtons( self, SettingsTable )

    self.cooldownNumberItems = {}

    for ButtonIndex, ButtonItem in ipairs( self.buttons ) do
        if ButtonIndex > self.numberOfTabs then
            local TextItem = GUIManager:CreateTextItem()
            TextItem:SetAnchor( GUIItem.Middle, GUIItem.Center )
            TextItem:SetTextAlignmentX( GUIItem.Align_Center )
            TextItem:SetTextAlignmentY( GUIItem.Align_Center )
            -- GUITextItem bitmap fonts ignore SetFontSize after a concrete font
            -- asset is selected. Let NS2 choose and scale the closest real bold
            -- Agency font to the requested screen-scaled target instead.
            GUIMakeFontScale( TextItem, "kAgencyFBBold", GUIScale( kCooldownFontSize ) )
            TextItem:SetFontIsBold( true )
            TextItem:SetDropShadowEnabled( true )
            TextItem:SetDropShadowOffset( Vector( GUIScale( 2 ), GUIScale( 2 ), 0 ) )
            TextItem:SetDropShadowColor( Color( 0, 0, 0, 0.95 ) )
            TextItem:SetColor( kCooldownYellow )
            TextItem:SetText( "" )
            TextItem:SetIsVisible( false )
            ButtonItem:AddChild( TextItem )
            self.cooldownNumberItems[ ButtonIndex ] = TextItem
        end
    end

end

local oldUpdateButtonStatus = GUICommanderButtons.UpdateButtonStatus
function GUICommanderButtons:UpdateButtonStatus( ButtonIndex )
    oldUpdateButtonStatus( self, ButtonIndex )

    local TextItem = self.cooldownNumberItems and self.cooldownNumberItems[ ButtonIndex ]
    if not TextItem then return end

    if not Client.GetOptionBoolean( kOptionPath, true ) then
        TextItem:SetIsVisible( false )
        return
    end

    local Player = Client.GetLocalPlayer()
    local TechId = Player and Player.menuTechButtons and Player.menuTechButtons[ ButtonIndex ]
    local CooldownFraction = TechId and TechId ~= kTechId.None and Player:GetCooldownFraction( TechId ) or 0
    local CooldownDuration = TechId and LookupTechData( TechId, kTechDataCooldown, 0 ) or 0
    local SecondsRemaining = CooldownFraction > 0 and CooldownDuration > 0
        and math.ceil( CooldownDuration * CooldownFraction ) or 0

    if SecondsRemaining <= 0 then
        TextItem:SetIsVisible( false )
        return
    end

    TextItem:SetText( tostring( SecondsRemaining ) )
    TextItem:SetColor( SecondsRemaining <= kUrgentThreshold and kCooldownRed or kCooldownYellow )
    TextItem:SetIsVisible( true )
end
