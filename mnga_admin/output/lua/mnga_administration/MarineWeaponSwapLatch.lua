-- Holding Use (E) next to a dropped weapon swaps every move: the weapon thrown by the swap lands
-- in reach and is picked straight back up. After a manual pickup, hide Use from Marine:HandleButtons
-- (the only manual-pickup consumer) until the key is released. Player:UpdateUse reads the real
-- input afterwards, so construct/weld/use-while-held are untouched.
if Server then

    local useMask = Move.Use
    local notUseMask = bit.bnot(Move.Use)
    local orig = Marine.HandleButtons

    function Marine:HandleButtons(input)

        local commands = input.commands
        local usePressed = bit.band(commands, useMask) ~= 0

        if not usePressed then
            self.mngaPickupLatched = false
            return orig(self, input)
        end

        if self.mngaPickupLatched then
            input.commands = bit.band(commands, notUseMask)
            orig(self, input)
            input.commands = commands
            return
        end

        local before = self.timeOfLastPickUpWeapon
        orig(self, input)
        if self.timeOfLastPickUpWeapon ~= before and bit.band(commands, Move.Drop) == 0 then
            self.mngaPickupLatched = true
        end

    end

end
