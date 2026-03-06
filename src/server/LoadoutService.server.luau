--!strict
local Players = game:GetService("Players")

local function ensureBackpack(player: Player): Backpack
	return player:WaitForChild("Backpack") :: Backpack
end

local function createRifleTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Rifle"
	tool.RequiresHandle = false
	tool.CanBeDropped = false

	return tool
end

local function giveLoadout(player: Player)
	local backpack = ensureBackpack(player)

	-- Clear existing tools (prototype)
	for _, child in ipairs(backpack:GetChildren()) do
		if child:IsA("Tool") then
			child:Destroy()
		end
	end

	local rifle = createRifleTool()
	rifle.Parent = backpack
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(_char)
		giveLoadout(player)
	end)
end)