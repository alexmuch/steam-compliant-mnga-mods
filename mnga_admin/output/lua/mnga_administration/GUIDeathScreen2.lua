

function GUIDeathScreen2:ShowContents(show, instant)

    local opacityTarget = show and 1 or 0

    for i = 1, #self.contentsObjs do
        local obj = self.contentsObjs[i]
        local currentOpacity = obj:GetOpacity()
        obj:ClearPropertyAnimations("Opacity")
        obj:SetOpacity(currentOpacity) -- When clearing animations, it'll set it to animation's baseValue.

        if instant then
            obj:SetOpacity(opacityTarget)
        else
            obj:AnimateProperty("Opacity", opacityTarget, MenuAnimations.Fade)
        end
    end
	
	self.skillbadge:GetIconObject():SetVisible(show and true or false)

end