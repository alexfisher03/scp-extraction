--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local InventoryStore = require(script.Parent.state.InventoryStore)
local RaidStore = require(script.Parent.state.RaidStore)
local BodyLootStore = require(script.Parent.state.BodyLootStore)

if not PlaceConfig.isRaidPlace() then
	return
end

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local raidStateEvent = remotes:WaitForChild(Net.RaidStateEventName) :: RemoteEvent
local raidReadyRequestEvent = remotes:WaitForChild(Net.RaidReadyRequestEventName) :: RemoteEvent
local bodyLootSnapshotEvent = remotes:WaitForChild(Net.BodyLootSnapshotEventName) :: RemoteEvent

local readySent = false
local rootReadyAt: number? = nil

local function syncInventoryVisibility()
	local raidState = RaidStore.getState()
	local bodySnapshot = BodyLootStore.getSnapshot()
	local mustShowInventory = (raidState and raidState.phase == "Stash") or bodySnapshot ~= nil
	player:SetAttribute("BodyLootOpen", bodySnapshot ~= nil)

	if mustShowInventory then
		player:SetAttribute("InventoryVisible", true)
	elseif player:GetAttribute("RaidPhase") ~= "Stash" then
		player:SetAttribute("InventoryVisible", false)
	end
end

local function isLocalClientReady(): boolean
	local raidState = RaidStore.getState()
	if raidState == nil then
		rootReadyAt = nil
		return false
	end

	if raidState.phase == "InRaid" or raidState.phase == "Extracting" or raidState.phase == "Stash" then
		return false
	end

	if raidState.worldStatus ~= "World loaded: Workspace.Maps.Level0" then
		rootReadyAt = nil
		return false
	end

	if InventoryStore.getSnapshot() == nil then
		rootReadyAt = nil
		return false
	end

	local character = player.Character
	if not character then
		rootReadyAt = nil
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		rootReadyAt = nil
		return false
	end

	if rootReadyAt == nil then
		rootReadyAt = os.clock()
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }
	local nearbyParts = workspace:GetPartBoundsInBox(root.CFrame, Vector3.new(80, 40, 80), overlapParams)
	if #nearbyParts >= 12 then
		return true
	end

	return os.clock() - rootReadyAt >= 5
end

raidStateEvent.OnClientEvent:Connect(function(raidState)
	RaidStore.setState(raidState)
	player:SetAttribute("RaidPhase", raidState.phase)
	player:SetAttribute("PlayerCanFight", raidState.playerCanFight == true)
	syncInventoryVisibility()
end)

bodyLootSnapshotEvent.OnClientEvent:Connect(function(bodySnapshot)
	if bodySnapshot then
		BodyLootStore.setSnapshot(bodySnapshot)
	else
		BodyLootStore.clear()
	end

	syncInventoryVisibility()
end)

player.CharacterRemoving:Connect(function()
	rootReadyAt = nil
end)

task.spawn(function()
	while player.Parent do
		task.wait(0.25)

		local raidState = RaidStore.getState()
		if raidState == nil then
			continue
		end

		if raidState.phase == "LoadingRaid" or raidState.phase == "WaitingForPlayers" then
			if not readySent and isLocalClientReady() then
				readySent = true
				raidReadyRequestEvent:FireServer()
			end
		end
	end
end)
