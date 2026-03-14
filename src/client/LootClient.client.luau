--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local LootDefinitions = require(ReplicatedStorage.Shared.LootDefinitions)
local LootPromptStore = require(script.Parent.state.LootPromptStore)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local pickupEvent = remotes:WaitForChild(Net.LootPickupRequestEventName) :: RemoteEvent

local MAX_DISTANCE = 15
local DETECTION_INTERVAL = 0.08

local elapsed = 0

local function getLootModelFromInstance(instance: Instance?): Model?
	local current = instance
	while current do
		if current:IsA("Model") and current:GetAttribute("TemplateId") ~= nil then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function updateLootPrompt()
	if player:GetAttribute("InventoryVisible") == true then
		LootPromptStore.clear()
		return
	end

	local character = player.Character
	if not character or not camera then
		LootPromptStore.clear()
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local result = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * MAX_DISTANCE, params)
	if not result then
		LootPromptStore.clear()
		return
	end

	local lootModel = getLootModelFromInstance(result.Instance)
	if not lootModel then
		LootPromptStore.clear()
		return
	end

	local templateId = lootModel:GetAttribute("TemplateId")
	if typeof(templateId) ~= "string" then
		LootPromptStore.clear()
		return
	end

	LootPromptStore.setPrompt({
		model = lootModel,
		templateId = templateId,
		displayName = LootDefinitions.getDisplayName(templateId),
	})
end

RunService.RenderStepped:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < DETECTION_INTERVAL then
		return
	end

	elapsed = 0
	updateLootPrompt()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.KeyCode ~= Enum.KeyCode.E then
		return
	end

	if player:GetAttribute("InventoryVisible") == true then
		return
	end

	local prompt = LootPromptStore.getPrompt()
	if not prompt.model then
		return
	end

	pickupEvent:FireServer(prompt.model)
end)
