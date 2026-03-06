--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local fireEvent = remotes:WaitForChild(Net.GunFireEventName) :: RemoteEvent
local reloadEvent = remotes:WaitForChild(Net.GunReloadEventName) :: RemoteEvent
local checkMagEvent = remotes:WaitForChild(Net.GunCheckMagEventName) :: RemoteEvent
local gunStateEvent = remotes:WaitForChild(Net.GunStateEventName) :: RemoteEvent

type GunStatePayload = {
	ammoInMag: number,
	magSize: number,
	reloading: boolean,
	magRead: string?,
}

local function hasEquippedWeapon(): boolean 
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

local function publishState(payload: GunStatePayload)
	player:SetAttribute("AmmoInMag", payload.ammoInMag)
    player:SetAttribute("MagSize", payload.magSize)
    player:SetAttribute("IsReloading", payload.reloading)
    if payload.magRead ~= nil then
        player:SetAttribute("MagRead", payload.magRead)
    end
end

gunStateEvent.OnClientEvent:Connect(function(payload: GunStatePayload)
	publishState(payload)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if hasEquippedWeapon() then
			fireEvent:FireServer(getMuzzleOrigin(), getAimDirection())
		end
		return
	end

	if input.KeyCode == Enum.KeyCode.R then
		if not hasEquippedWeapon() then return end
		local altDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
		if altDown then
			checkMagEvent:FireServer()
		else
			reloadEvent:FireServer()
		end
		return
	end

	if input.KeyCode == Enum.KeyCode.C then
		if not hasEquippedWeapon() then return end
		checkMagEvent:FireServer()
	end
end)