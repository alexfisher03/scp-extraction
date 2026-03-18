--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local ClientActionBridge = require(script.Parent:WaitForChild("ClientActionBridge"))
local InventoryStore = require(script.Parent:WaitForChild("InventoryStore"))

if not (PlaceConfig.isRaidPlace() or PlaceConfig.isLobbyPlace()) then
	return
end

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

local function sendAction(payload: {[string]: any})
	actionEvent:FireServer(payload)
end

local function toggleInventory()
	if PlaceConfig.isLobbyPlace() then
		local current = player:GetAttribute("InventoryVisible")
		local nowVisible = not (typeof(current) == "boolean" and current)
		setInventoryVisible(nowVisible)
		return
	end

	if player:GetAttribute("RaidPhase") == "Stash" or player:GetAttribute("BodyLootOpen") == true then
		setInventoryVisible(true)
		return
	end

	local current = player:GetAttribute("InventoryVisible")
	local nowVisible = not (typeof(current) == "boolean" and current)
	setInventoryVisible(nowVisible)
end

local function closeInventory()
	setInventoryVisible(false)
end

local function requestEquipSlot(slot: string)
	if PlaceConfig.isLobbyPlace() then
		sendAction({ kind = "EquipSlot", slot = slot })
		return
	end

	if player:GetAttribute("InventoryVisible") == true then
		return
	end

	sendAction({ kind = "EquipSlot", slot = slot })
end

local function requestReload()
	if PlaceConfig.isLobbyPlace() then
		return
	end

	if player:GetAttribute("InventoryVisible") == true then
		return
	end

	sendAction({ kind = "Reload" })
end

local function requestCheckMag()
	if PlaceConfig.isLobbyPlace() then
		return
	end

	if player:GetAttribute("InventoryVisible") == true then
		return
	end

	sendAction({ kind = "CheckMag" })
end

local function requestFire()
	if PlaceConfig.isLobbyPlace() then
		return
	end

	if player:GetAttribute("InventoryVisible") == true then
		return
	end

	if camera == nil then
		return
	end

	sendAction({
		kind = "Fire",
		origin = camera.CFrame.Position,
		direction = camera.CFrame.LookVector.Unit,
	})
end

snapshotEvent.OnClientEvent:Connect(function(snapshot)
	InventoryStore.setSnapshot(snapshot)
end)

if typeof(player:GetAttribute("InventoryVisible")) ~= "boolean" then
	player:SetAttribute("InventoryVisible", false)
end
if PlaceConfig.isLobbyPlace() and typeof(player:GetAttribute("RaidPhase")) ~= "string" then
	player:SetAttribute("RaidPhase", "Lobby")
end
applyInventoryInputMode(player:GetAttribute("InventoryVisible") == true)

player:GetAttributeChangedSignal("InventoryVisible"):Connect(function()
	applyInventoryInputMode(player:GetAttribute("InventoryVisible") == true)
end)

local slotByKey = {
	[Enum.KeyCode.One] = "PrimaryA",
	[Enum.KeyCode.Two] = "PrimaryB",
	[Enum.KeyCode.Three] = "Pistol",
	[Enum.KeyCode.Four] = "Melee",
}

ClientActionBridge.register("toggle_inventory", toggleInventory)
ClientActionBridge.register("close_inventory", closeInventory)
ClientActionBridge.register("reload", requestReload)
ClientActionBridge.register("check_mag", requestCheckMag)
ClientActionBridge.register("fire", requestFire)
ClientActionBridge.register("equip_primary_a", function()
	requestEquipSlot("PrimaryA")
end)
ClientActionBridge.register("equip_primary_b", function()
	requestEquipSlot("PrimaryB")
end)
ClientActionBridge.register("equip_pistol", function()
	requestEquipSlot("Pistol")
end)
ClientActionBridge.register("equip_melee", function()
	requestEquipSlot("Melee")
end)
ClientActionBridge.register("aim", function()
	-- Aim behavior will be implemented with the later ADS pass.
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.Tab then
		toggleInventory()
		return
	end

	if player:GetAttribute("InventoryVisible") == true then
		return
	end

	if input.KeyCode == Enum.KeyCode.R then
		if UserInputService:GetFocusedTextBox() then return end
		requestReload()
		return
	end

	if input.KeyCode == Enum.KeyCode.C then
		if UserInputService:GetFocusedTextBox() then return end
		requestCheckMag()
		return
	end

	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		requestFire()
		return
	end

	local slot = slotByKey[input.KeyCode]
	if slot then
		requestEquipSlot(slot)
		return
	end
end)
