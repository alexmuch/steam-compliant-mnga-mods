-- Research-in-progress list for dead / respawning team players.
--
-- Vanilla shows the left-side research list (GUIEvent) only through
-- GUIMarineHUD / GUIAlienHUD, which exist for living classes. While dead the
-- local player is a MarineSpectator / AlienSpectator, which has neither those
-- HUDs nor GUINotificationMixin, so the list vanishes until respawn.
--
-- This script hosts its own vanilla GUIEvent for those classes and feeds it
-- from the client tech tree (GetResearchInProgressTable) instead of the
-- player's notification queue. Polled at a low rate with reused tables; the
-- client tech tree is already replicated to team spectators (J tech map).
-- Registered for both spectator classes in DeadResearchClientUI.lua.

Script.Load("lua/GUIAnimatedScript.lua")
Script.Load("lua/Hud/GUIEvent.lua")

class 'GUIMNGADeadResearch' (GUIAnimatedScript)

local kPollInterval = 0.25
local kNotificationUpdateInterval = 1 / 30
-- Unique numeric key per research line: entity ids are small, so instanced
-- research (per-structure) cannot collide with the plain techId range.
local function GetResearchKey(techId, entityId)
    if entityId then
        return techId * 100000 + entityId
    end
    return techId
end

function GUIMNGADeadResearch:Initialize()

    GUIAnimatedScript.Initialize(self)

    -- Lets the GUIEvent handoff hook (DeadResearchHandoff.lua) tell us apart from the vanilla HUDs.
    self.mngaDeadResearch = true

    self.scale = Client.GetScreenHeight() / kBaseScreenHeight

    local player = Client.GetLocalPlayer()
    self.useMarineStyle = player ~= nil and player:isa("MarineSpectator")

    self.background = self:CreateAnimatedGraphicItem()
    self.background:SetPosition(Vector(0, 0, 0))
    self.background:SetIsScaling(false)
    self.background:SetSize(Vector(Client.GetScreenWidth(), Client.GetScreenHeight(), 0))
    self.background:SetIsVisible(true)
    self.background:SetLayer(kGUILayerPlayerHUDBackground)
    self.background:SetColor(Color(1, 1, 1, 0))

    self.eventDisplay = CreateEventDisplay(self, kGUILayerPlayerHUDForeground1, self.background, self.useMarineStyle)
    self.eventDisplay:Reset(self.scale)

    -- key -> poll generation in which it was last seen in progress
    self.knownResearch = {}
    self.pendingNotifications = {}
    self.inProgressScratch = {}
    self.pollGeneration = 0
    self.nextPollTime = 0
    self.lastNotificationUpdate = 0

end

function GUIMNGADeadResearch:Uninitialize()

    if self.eventDisplay then
        self.eventDisplay:ClearNotifications()
        self.eventDisplay:Destroy()
        self.eventDisplay = nil
    end

    GUIAnimatedScript.Uninitialize(self)

    self.background = nil
    self.knownResearch = nil
    self.pendingNotifications = nil

end

function GUIMNGADeadResearch:OnResolutionChanged(oldX, oldY, newX, newY)

    self:Uninitialize()
    self:Initialize()

end

-- Queue research that started since the last poll (or was already running
-- when this script was created) and forget research that stopped, so a
-- cancelled-then-restarted line is announced again like vanilla.
function GUIMNGADeadResearch:PollTechTree()

    local techTree = GetTechTree()
    if not techTree then
        return
    end

    local inProgress = self.inProgressScratch
    for i = #inProgress, 1, -1 do
        inProgress[i] = nil
    end
    techTree:GetResearchInProgressTable(inProgress)

    self.pollGeneration = self.pollGeneration + 1
    local generation = self.pollGeneration
    local known = self.knownResearch

    for i = 1, #inProgress do

        local entry = inProgress[i]
        local key = GetResearchKey(entry.techId, entry.entityId)
        if not known[key] then
            table.insert(self.pendingNotifications, { techId = entry.techId, entityId = entry.entityId })
        end
        known[key] = generation

    end

    for key, seen in pairs(known) do
        if seen ~= generation then
            known[key] = nil
        end
    end

end

function GUIMNGADeadResearch:Update(deltaTime)

    PROFILE("GUIMNGADeadResearch:Update")

    local now = Client.GetTime()

    if now >= self.nextPollTime then
        self.nextPollTime = now + kPollInterval
        self:PollTechTree()
    end

    if self.lastNotificationUpdate + kNotificationUpdateInterval < now then

        -- One new notification per update, same pacing as the vanilla HUDs;
        -- right after an alive<->dead swap, show everything at once instead.
        local notification = table.remove(self.pendingNotifications, 1)
        self.eventDisplay:Update(now - self.lastNotificationUpdate, notification)
        self.lastNotificationUpdate = now

        if MNGAGetResearchHandoffActive and MNGAGetResearchHandoffActive() then
            notification = table.remove(self.pendingNotifications, 1)
            while notification do
                self.eventDisplay:Update(0, notification)
                notification = table.remove(self.pendingNotifications, 1)
            end
        end

    end

    GUIAnimatedScript.Update(self, deltaTime)

end
