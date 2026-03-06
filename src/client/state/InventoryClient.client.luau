--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local InventoryStore = require(script.Parent:WaitForChild("InventoryStore"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local actionEvent = remotes:WaitForChild(Net.InventoryActionEventName) :: RemoteEvent
local snapshotEvent = remotes:WaitForChild(Net.InventorySnapshotEventName) :: RemoteEvent

local controls: any = nil
local CLOSED_CAMERA_MODE = Enum.CameraMode.LockFirstPerson
local OPEN_CAMERA_MODE = Enum.CameraMode.Classic

local function getControls()
	if controls then
		return controls
	end
	local playerScripts = player:WaitForChild("PlayerScripts")
	local playerModule = require(playerScripts:WaitForChild("PlayerModule"))
	controls = playerModule:GetControls()
	return controls
end

local function applyInventoryInputMode(visible: boolean)
	local ctl = getControls()

	if visible then
		ctl:Disable()

		-- Free cursor for UI
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default

		-- Hard-freeze look
		player.CameraMode = OPEN_CAMERA_MODE
		if camera then
			camera.CameraType = Enum.CameraType.Scriptable
		end
	else
		ctl:Enable()

		-- Gameplay mouse lock
		UserInputService.MouseIconEnabled = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

		player.CameraMode = CLOSED_CAMERA_MODE
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
	end
end

local function setInventoryVisible(visible: boolean)
	player:SetAttribute("InventoryVisible", visible)
	applyInventoryInputMode(visible)
end

snapshotEvent.OnClientEvent:Connect(function(snapshot)
	InventoryStore.setSnapshot(snapshot)
end)

if typeof(player:GetAttribute("InventoryVisible")) ~= "boolean" then
	player:SetAttribute("InventoryVisible", false)
end
applyInventoryInputMode(player:GetAttribute("InventoryVisible") == true)

player:GetAttributeChangedSignal("InventoryVisible"):Connect(function()
	applyInventoryInputMode(player:GetAttribute("InventoryVisible") == true)
end)

local function sendAction(payload: {[string]: any})
	actionEvent:FireServer(payload)
end

local slotByKey = {
	[Enum.KeyCode.One] = "PrimaryA",
	[Enum.KeyCode.Two] = "PrimaryB",
	[Enum.KeyCode.Three] = "Pistol",
	[Enum.KeyCode.Four] = "Melee",
}

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.Tab then
		local current = player:GetAttribute("InventoryVisible")
		local nowVisible = not (typeof(current) == "boolean" and current)
		setInventoryVisible(nowVisible)
		return
	end

	if player:GetAttribute("InventoryVisible") == true then
		return
	end

	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		sendAction({
			kind = "Fire",
			origin = camera.CFrame.Position,
			direction = camera.CFrame.LookVector.Unit,
		})
		return
	end

	local slot = slotByKey[input.KeyCode]
	if slot then
		sendAction({ kind = "EquipSlot", slot = slot })
		return
	end

	if input.KeyCode == Enum.KeyCode.R then
		local altDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
		if altDown then
			sendAction({ kind = "CheckMag" })
		else
			sendAction({ kind = "Reload" })
		end
		return
	end

	if input.KeyCode == Enum.KeyCode.C then
		sendAction({ kind = "CheckMag" })
	end
end)
