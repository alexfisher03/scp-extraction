--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local inventoryCameraConn: RBXScriptConnection? = nil
local inventoryCameraStart: CFrame? = nil
local inventoryAnchorStartPosition: Vector3? = nil

local function getControls()
	if controls then
		return controls
	end
	local playerScripts = player:WaitForChild("PlayerScripts")
	local playerModule = require(playerScripts:WaitForChild("PlayerModule"))
	controls = playerModule:GetControls()
	return controls
end

local function getCameraAnchor(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("Head") :: BasePart?
		or character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function stopInventoryCameraFollow()
	if inventoryCameraConn then
		inventoryCameraConn:Disconnect()
		inventoryCameraConn = nil
	end
	inventoryCameraStart = nil
	inventoryAnchorStartPosition = nil
end

local function startInventoryCameraFollow()
	stopInventoryCameraFollow()

	local anchor = getCameraAnchor()
	if not anchor or not camera then
		return
	end

	inventoryCameraStart = camera.CFrame
	inventoryAnchorStartPosition = anchor.Position

	inventoryCameraConn = RunService.RenderStepped:Connect(function()
		local currentAnchor = getCameraAnchor()
		if not currentAnchor or not camera or not inventoryCameraStart or not inventoryAnchorStartPosition then
			return
		end

		local positionDelta = currentAnchor.Position - inventoryAnchorStartPosition
		local targetCameraCFrame = inventoryCameraStart + positionDelta
		camera.CFrame = targetCameraCFrame
		camera.Focus = targetCameraCFrame + targetCameraCFrame.LookVector
	end)
end

local function applyInventoryInputMode(visible: boolean)
	local ctl = getControls()

	if visible then
		ctl:Disable()

		-- Free cursor for UI
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		player.CameraMode = OPEN_CAMERA_MODE
		if camera then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		startInventoryCameraFollow()
	else
		ctl:Enable()
		stopInventoryCameraFollow()

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
		if player:GetAttribute("RaidPhase") == "Stash" or player:GetAttribute("BodyLootOpen") == true then
			setInventoryVisible(true)
			return
		end

		local current = player:GetAttribute("InventoryVisible")
		local nowVisible = not (typeof(current) == "boolean" and current)
		setInventoryVisible(nowVisible)
		return
	end

	if player:GetAttribute("InventoryVisible") == true then
		return
	end

	if input.KeyCode == Enum.KeyCode.R then
		if UserInputService:GetFocusedTextBox() then return end
		sendAction({ kind = "Reload" })
		return
	end

	if input.KeyCode == Enum.KeyCode.C then
		if UserInputService:GetFocusedTextBox() then return end
		sendAction({ kind = "CheckMag" })
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
end)
