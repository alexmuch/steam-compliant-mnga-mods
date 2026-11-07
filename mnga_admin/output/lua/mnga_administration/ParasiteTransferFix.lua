-- Vanilla copies the parasite flag before checking whether OnParasited should
-- run, but checks for the clean state. That skips the LOS refresh for an active
-- parasite transferred between an Exo and its dropped Exosuit.
function ParasiteMixin:TransferParasite(from)

    self.parasiteDuration = from.parasiteDuration
    self.timeParasited = from.timeParasited
    self:SetIsParasited(from.parasited)

    if Server then
        UpdateEntityForTeamBrains(self)
    end

    if self.OnParasited and self.parasited then
        -- Newly-created Exos and Exosuits initialise oldSighted to true. If an
        -- active parasite is copied in before their first LOS update, vanilla
        -- calculates sighted=true but sees no state transition, leaving
        -- visibleClient false. Force the next LOS pass to observe the change.
        if HasMixin(self, "LOS") then
            self.oldSighted = false
            self.updateLOS = true
        end

        self:OnParasited()
    end

end
