local function dump(o)
	if type(o) == "table" then
		local s = "{ "
		for k, v in pairs(o) do
			if type(k) ~= "number" then
				k = '"' .. k .. '"'
			end
			s = s .. "[" .. k .. "] = " .. dump(v) .. ","
		end
		return s .. "} "
	else
		return tostring(o)
	end
end

local orgGUIMinimapUpdate = GUIMinimap.Update

function GUIMinimap:Update(deltaTime)
    local itstime = Shared.GetTime() > self.nextActivityUpdateTime
    orgGUIMinimapUpdate(self, deltaTime)
    if self.background:GetIsVisible() then
        --print("In update thingy")
        --print("-It's time: " .. tostring(itstime))
        if itstime then
            local player = Client.GetLocalPlayer()
            print("Name: " .. tostring(GetLocalPlayerProfileData():GetPlayerName()))
            local playerRecord = Scoreboard_GetPlayerRecordByName(GetLocalPlayerProfileData():GetPlayerName())
            --print("Status: " .. tostring(player:GetPlayerStatusDesc()))
            --print("-playerRecord: " .. dump(playerRecord))
            print("-Spectator: " .. tostring(playerRecord.IsSpectator))
            --print("-Is Spec: " .. tostring(player:GetTeamNumber()))
        end
    end
end