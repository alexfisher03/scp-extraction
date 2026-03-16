--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local RaidStore = require(script.Parent.state.RaidStore)
local BodyLootStore = require(script.Parent.state.BodyLootStore)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local raidStateEvent = remotes:WaitForChild(Net.RaidStateEventName) :: RemoteEvent
local bodyLootSnapshotEvent = remotes:WaitForChild(Net.BodyLootSnapshotEventName) :: RemoteEvent

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
