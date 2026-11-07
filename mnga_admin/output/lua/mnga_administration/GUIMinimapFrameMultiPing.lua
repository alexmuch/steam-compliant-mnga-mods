-- MNGA multi-ping: dead players get the map cursor and can right-click the big
-- map to send a ping.
--
-- Vanilla only shows the map cursor while the "SetIsRespawning" message flag is
-- set, and that message is only ever sent for aliens (vanilla TODOs in
-- GUIMinimapFrame.lua / GUIDeathScreen2.lua). Instead of adding a marine
-- message, we detect "dead team player" entirely client-side.
--
-- IMPORTANT pitfall (see .claude/docs/multiping.md): while first-person
-- spectating a teammate, Client.GetLocalPlayer() returns the *spectated alive
-- teammate*, so the local player entity cannot be trusted for dead-ness. The
-- scoreboard record for our own client index always carries our real team, and
-- Client.GetIsControllingPlayer() distinguishes the spectate case.

local function GetIsDeadTeamSpectator()

    local player = Client.GetLocalPlayer()
    if not player then
        return false
    end

    -- Our own team from the scoreboard: immune to the first-person spectate
    -- entity swap. Pure spectators (team 3) and ready room (0) are excluded.
    local record = Scoreboard_GetPlayerRecord(Client.GetLocalClientIndex())
    local teamNumber = record and record.EntityTeamNumber
    if teamNumber ~= kTeam1Index and teamNumber ~= kTeam2Index then
        return false
    end

    if not Client.GetIsControllingPlayer() then
        -- First-person spectating a teammate: on a playing team this only
        -- happens while dead and waiting for a respawn slot.
        return true
    end

    -- Waiting at the IP / egg (Following mode): we control our own
    -- MarineSpectator / AlienSpectator entity again.
    return player:isa("TeamSpectator")

end

-- True while the dead-player map cursor is being shown by GUIMinimapFrame.
-- Used by GUIFirstPersonSpectateMultiPing to stop map clicks from cycling the
-- spectated player.
function MNGA_GetMapCursorActive()

    local script = ClientUI.GetScript("GUIMinimapFrame")
    return script ~= nil and script.showingMouse == true

end

-- GUIMinimapFrame:Update is redefined wholesale (copy of the vanilla body)
-- because the cursor condition reads the file-local 'isRespawning'
-- (= GetPlayerIsSpawning()). Keeping a single computation of showMouse keeps
-- the MouseTracker push/pop stack balanced — a wrap that second-guesses
-- vanilla's decision fights it every frame (this broke mouse-look in the
-- reverted first attempt).
-- Changed vs vanilla: showMouse also true for dead team spectators (marines,
-- and both teams while waiting at the IP/egg with the map open).

-- file-local in vanilla GUIMinimapFrame.lua, re-declared for our Update copy
-- (constant, so shadowing is harmless)
local kMarineFrameTexture = PrecacheAsset("ui/marine_commander_textures.dds")

-- Default cursor position when opening the map is the screen center, which is
-- also the center of the big minimap. Ignore that exact point plus one pixel on
-- each axis so right-click spam while dead does not create accidental center
-- pings.
local kMapPingCenterDeadZoneRadius = 1

local function GetIsInMapPingCenterDeadZone(withinX, withinY, minimapSize)

    local centerX = minimapSize.x * 0.5
    local centerY = minimapSize.y * 0.5

    return math.abs(withinX - centerX) <= kMapPingCenterDeadZoneRadius
        and math.abs(withinY - centerY) <= kMapPingCenterDeadZoneRadius

end

function GUIMinimapFrame:Update(deltaTime)

    PROFILE("GUIMinimapFrame:Update")

    -- MNGA: extended cursor condition. Must check LargeMapIsVisible (background
    -- visible AND kModeBig), not just background visibility: spectators never
    -- close the map, they cycle Big <-> Small (corner) mode and the background
    -- stays visible in Small mode. A cursor left pushed there makes
    -- MouseTracker consume all mouse movement = frozen freelook after "closing"
    -- the map while waiting at the IP. Also keeps the GUIMarineHUD corner
    -- minimap instance (kModeZoom, background always visible) cursor-free.
    local showMouse = self.visible and self:LargeMapIsVisible() and (GetPlayerIsSpawning() or GetIsDeadTeamSpectator())
    if showMouse ~= self.showingMouse then

        -- Print("MNGA GUIMinimapFrame: map cursor %s", showMouse and "shown" or "hidden")
        MouseTracker_SetIsVisible(showMouse, "ui/Cursor_MenuDefault.dds", true)
        self.showingMouse = showMouse

    end

    self.chooseSpawnText:SetIsVisible(self.visible and (not self.background:GetIsVisible() and GetPlayerIsSpawning()))

    self.minimapFrame:SetIsVisible(self.visible and (PlayerUI_GetTeamType() == kMarineTeamType and self.comMode == GUIMinimapFrame.kModeMini))
    self.smokeyBackground:SetIsVisible(self.visible and (PlayerUI_GetTeamType() == kAlienTeamType and self.comMode == GUIMinimapFrame.kModeMini))

    if PlayerUI_IsOverhead() and self.comMode ~= GUIMinimapFrame.kModeBig then

        if PlayerUI_IsACommander() then

            local teamInfo = GetTeamInfoEntity( PlayerUI_GetTeamNumber() )
            if teamInfo and PlayerUI_GetTeamNumber() == kTeam1Index then
                --self.spawnQueueText:SetColor( kMarineFontColor )
                --TODO Check number respawning and adjust color if above X threshold
                --self.spawnQueueText:SetText( string.format( Locale.ResolveString("MARINES_RESPAWNING"), teamInfo:GetSpawnQueueTotal() ) )
            end

            -- Commander always sees the minimap.
            if not PlayerUI_IsCameraAnimated() then
                self.background:SetIsVisible(self.visible)
            else
                self.background:SetIsVisible(false)
            end

        else
            self.background:SetIsVisible(self.visible)
        end

        self:UpdatePlayerMinimapVisible()

    end

    if self.comMode == GUIMinimapFrame.kModeZoom then

        if self.desiredZoom ~= self.zoom then

            local currSqrt = math.sqrt(self.zoom)
            local zoomSpeed = 0.8
            if self.zoom < self.desiredZoom then

                currSqrt = currSqrt + deltaTime*zoomSpeed
                self:SetZoom(Clamp(currSqrt*currSqrt, 0, self.desiredZoom))

            else
                currSqrt = currSqrt - deltaTime*zoomSpeed
                self:SetZoom(Clamp(currSqrt*currSqrt, self.desiredZoom, 1))
            end

        end

    end

    GUIMinimap.Update(self, deltaTime)

    local newHudDetail = Client.GetHudDetail()
    if self.cachedHudDetail ~= newHudDetail then

        self.cachedHudDetail = newHudDetail
        self.smokeyBackground:SetTexture(ConditionalValue(self.cachedHudDetail == kHUDMode.Minimal, "ui/transparent.dds", "ui/alien_minimap_smkmask.dds"))
        self.minimapFrame:SetTexture(ConditionalValue(self.cachedHudDetail == kHUDMode.Minimal, "ui/transparent.dds", kMarineFrameTexture))
    end

end

-- Right-click on the big map while dead sends a ping. Runs before the vanilla
-- handler; left clicks fall through (alien spawn selection unchanged).
local oldSendKeyEvent = GUIMinimapFrame.SendKeyEvent

function GUIMinimapFrame:SendKeyEvent(key, down)

    if key == InputKey.MouseButton1 and self.visible and self:LargeMapIsVisible()
            and (GetPlayerIsSpawning() or GetIsDeadTeamSpectator()) then

        local mouseX, mouseY = Client.GetCursorPosScreen()
        local containsPoint, withinX, withinY = GUIItemContainsPoint(self.minimap, mouseX, mouseY)
        if containsPoint then

            -- act on key up, but consume the down event too (same pattern as
            -- vanilla spawn selection with mouse0)
            if not down then

                local minimapSize = self:GetMinimapSize()
                if not GetIsInMapPingCenterDeadZone(withinX, withinY, minimapSize) then

                    local pingPosition = MinimapToWorld(nil, withinX / minimapSize.x, withinY / minimapSize.y)
                    -- Print("MNGA map ping: right click -> %s", ToString(pingPosition))
                    Client.SendNetworkMessage("MNGAMapPing", { position = pingPosition }, true)

                -- else
                    -- Print("MNGA map ping: ignored center dead-zone click")

                end

            end

            self:UpdatePlayerMinimapVisible()
            return true

        end

    end

    return oldSendKeyEvent(self, key, down)

end
