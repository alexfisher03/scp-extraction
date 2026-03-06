--!strict
local Players = game:GetService("Players")

local HotbarState = {}
HotbarState.__index = HotbarState

export type HotbarState = {
	selectedSlot: number,
}

function HotbarState.getSelectedSlot(): number
	local player = Players.LocalPlayer
	local char = player.Character
	if not char then
		return 0
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if tool and tool.Name == "Rifle" then
		return 1
	end
	return 0
end

return HotbarState