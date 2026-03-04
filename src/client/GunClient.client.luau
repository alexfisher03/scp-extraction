--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)

local Player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local fireEvent = remotes:WaitForChild(Net.GunFireEventName) :: RemoteEvent

local function getMuzzleOrigin(): Vector3
	-- for now shoot from camera
	return camera.CFrame.Position
end

local function getAimDirection(): Vector3
	return camera.CFrame.LookVector.Unit
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		fireEvent:FireServer(getMuzzleOrigin(), getAimDirection())
	end
end)