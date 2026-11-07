-- Post-hook on lua/Hud/GUIEvent.lua. Hooked before DeadResearchHandoff.lua so
-- its wrapper (and its queue drain) calls through this one.
-- Vanilla bug: a new research with less time left is inserted into the shown
-- part of the list and pushes the last shown item past maxNotifications. That
-- item fades out and, when destroyed, its notificationsData entry is dropped
-- with it, so it never comes back even after a slot frees up (re-entering a
-- hive/HUD rebuilds the list from the tech tree). Easy to hit with biomass on
-- several hives plus the alien max of 3.
-- Fix: remember overflow items about to be destroyed and, if their research
-- is still in progress, put their data back at the front of the hidden queue
-- (right after the shown items) so vanilla re-shows it when a slot frees.
-- See .claude/docs/biomass-research-list.md.

local pendingOverflow = {}

local function GetHasData(self, techId, entityId)

    for i = 1, #self.notificationsData do
        local data = self.notificationsData[i]
        if data.techId == techId and data.entityId == entityId then
            return true
        end
    end
    return false

end

local function GetIsDisplayed(self, item)

    for i = 1, #self.displayedNotifications do
        if self.displayedNotifications[i] == item then
            return true
        end
    end
    return false

end

local oldUpdate = GUIEvent.Update
function GUIEvent:Update(deltaTime, newNotification)

    local numPending = 0
    local displayed = self.displayedNotifications
    for index = self.maxNotifications + 1, #displayed do
        local item = displayed[index]
        if item:GetIsReadyToBeDestroyed() and not item:GetCompleted() and not item:GetCancelled() then
            numPending = numPending + 1
            pendingOverflow[numPending] = item
        end
    end

    oldUpdate(self, deltaTime, newNotification)

    if numPending == 0 then
        return
    end

    local techTree = GetTechTree()
    for i = 1, numPending do

        local item = pendingOverflow[i]
        pendingOverflow[i] = nil

        local techId = item.techId
        local entityId = item.entityId
        if techTree and not GetIsDisplayed(self, item)
                and techTree:GetResearchInProgress(techId, entityId)
                and not GetHasData(self, techId, entityId) then

            local insertIndex = math.min(#self.displayedNotifications + 1, #self.notificationsData + 1)
            table.insert(self.notificationsData, insertIndex,
                { techId = techId, entityId = entityId, timeLeft = self:GetTimeLeftForResearch(techId, entityId) })

        end

    end

end
