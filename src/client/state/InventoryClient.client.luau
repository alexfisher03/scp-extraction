--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local ClientActionBridge = require(script.Parent:WaitForChild("ClientActionBridge"))
local InputModeController = require(script.Parent:WaitForChild("InputModeController"))
local InventoryStore = require(script.Parent:WaitForChild("InventoryStore"))

if not (PlaceConfig.isRaidPlace() or PlaceConfig.isLobbyPlace()) then
	return
end

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local actionEvent = remotes:WaitForChild(Net.InventoryActionEventName) :: RemoteEvent
local snapshotEvent = remotes:WaitForChild(Net.InventorySnapshotEventName) :: RemoteEvent

local function applyInventoryInputMode(visible: boolean)
	InputModeController.setUiLock("inventory", visible)
end

local function setInventoryVisible(visible: boolean)
	player:SetAttribute("InventoryVisible", visible)
	applyInventoryInputMode(visible)
end

local function openInventory()
	setInventoryVisible(true)
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

local function openUiInputLock()
	InputModeController.setUiLock("external", true)
end

local function closeUiInputLock()
	if player:GetAttribute("InventoryVisible") == true then
		return
	end

	InputModeController.setUiLock("external", false)
end

local function requestEquipSlot(slot: string)
	if PlaceConfig.isLobbyPlace() then
		sendAction({ kind = "EquipSlot", slot = slot })
		return
	end

	if player:GetAttribute("InventoryVisible") == true then
		return
	end
	if player:GetAttribute("RaidMenuOpen") == true then
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
	if player:GetAttribute("RaidMenuOpen") == true then
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
	if player:GetAttribute("RaidMenuOpen") == true then
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
	if player:GetAttribute("RaidMenuOpen") == true then
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
ClientActionBridge.register("open_inventory", openInventory)
ClientActionBridge.register("close_inventory", closeInventory)
ClientActionBridge.register("open_ui_input_lock", openUiInputLock)
ClientActionBridge.register("close_ui_input_lock", closeUiInputLock)
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
