--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local fireEvent = remotes:WaitForChild(Net.GunFireEventName) :: RemoteEvent

local function hasEquippedRifle(): boolean
	local char = player.Character
	if not char then return false end
	local tool = char:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool.Name == "Rifle"
end

local function getMuzzleOrigin(): Vector3
	return camera.CFrame.Position
end

local function getAimDirection(): Vector3
	return camera.CFrame.LookVector.Unit
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not hasEquippedRifle() then
			return
		end
		fireEvent:FireServer(getMuzzleOrigin(), getAimDirection())
	end
end)