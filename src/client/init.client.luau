--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)

local player = Players.LocalPlayer
player.CameraMode = Enum.CameraMode.LockFirstPerson

local controls: any = nil

local function getControls()
	if controls then
		return controls
	end

	local playerScripts = player:WaitForChild("PlayerScripts")
	local playerModule = require(playerScripts:WaitForChild("PlayerModule"))
	controls = playerModule:GetControls()
	return controls
end

local function resetGameplayInputMode()
	if player:GetAttribute("LobbyPostRaidOpen") == true
		or player:GetAttribute("LobbyTerminalOpen") == true
		or player:GetAttribute("InventoryVisible") == true
	then
		return
	end

	player.CameraMode = Enum.CameraMode.LockFirstPerson
	UserInputService.MouseIconEnabled = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end

	local ctl = getControls()
	ctl:Enable()
end

local function resizeMobileJumpButton()
	if not (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then
		return
	end

	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		for _ = 1, 40 do
			local touchGui = playerGui:FindFirstChild("TouchGui")
			local touchControlFrame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
			local jumpButton = touchControlFrame and touchControlFrame:FindFirstChild("JumpButton")
			if jumpButton and jumpButton:IsA("GuiButton") then
				jumpButton.Size = UDim2.fromOffset(64, 64)
				jumpButton.Position = UDim2.new(1, -78, 1, -76)
				break
			end

			task.wait(0.25)
		end
	end)
end

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

player:SetAttribute("InventoryVisible", false)
player:SetAttribute("RaidPhase", "InRaid")
player:SetAttribute("PlayerCanFight", true)
player:SetAttribute("BodyLootOpen", false)
player:SetAttribute("LobbyMatchStarting", false)

resetGameplayInputMode()
resizeMobileJumpButton()

player.CharacterAdded:Connect(function()
	task.defer(resetGameplayInputMode)
	task.defer(resizeMobileJumpButton)
end)
