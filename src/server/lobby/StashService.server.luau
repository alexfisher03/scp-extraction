--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local ProfileService = require(script.Parent.ProfileService)

if not PlaceConfig.isLobbyPlace() then
	return
end

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local stashActionEvent = remotes:WaitForChild(Net.LobbyStashActionEventName) :: RemoteEvent
local snapshotEvent = remotes:WaitForChild(Net.InventorySnapshotEventName) :: RemoteEvent

local function sendLobbySnapshot(player: Player)
	snapshotEvent:FireClient(player, ProfileService.getInventorySnapshot(player.UserId))
	player:SetAttribute("LobbyInventorySyncNonce", Workspace:GetServerTimeNow())
end

stashActionEvent.OnServerEvent:Connect(function(player: Player, action: any)
	local ok, reason = ProfileService.handleStashAction(player.UserId, action)
	if not ok then
		warn(string.format("[StashService] rejected userId=%d reason=%s", player.UserId, tostring(reason)))
		return
	end

	print(string.format("[StashService] accepted userId=%d action=%s", player.UserId, tostring(action and action.kind)))
	sendLobbySnapshot(player)
end)
