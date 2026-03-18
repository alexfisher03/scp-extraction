--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local RaidResult = require(ReplicatedStorage.Shared.RaidResult)
local LobbySessionService = require(script.Parent.LobbySessionService)

if not PlaceConfig.isLobbyPlace() then
	return
end

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local continueEvent = remotes:WaitForChild(Net.LobbyPostRaidContinueEventName) :: RemoteEvent
local snapshotEvent = remotes:WaitForChild(Net.InventorySnapshotEventName) :: RemoteEvent

local function setPostRaidAttributes(player: Player, result: any?)
	if not result then
		player:SetAttribute("LobbyPostRaidOpen", false)
		player:SetAttribute("LobbyPostRaidStatus", nil)
		player:SetAttribute("LobbyPostRaidXP", nil)
		player:SetAttribute("LobbyPostRaidKills", nil)
		player:SetAttribute("LobbyPostRaidReason", nil)
		player:SetAttribute("LobbyPostRaidEliminationsJson", nil)
		return
	end

	player:SetAttribute("LobbyPostRaidOpen", true)
	player:SetAttribute("LobbyPostRaidStatus", result.status)
	player:SetAttribute("LobbyPostRaidXP", result.xpEarned or 0)
	player:SetAttribute("LobbyPostRaidKills", result.kills or 0)
	player:SetAttribute("LobbyPostRaidReason", result.reason)
	player:SetAttribute("LobbyPostRaidEliminationsJson", HttpService:JSONEncode(result.eliminations or {}))
end

local function getStashSpawn(): BasePart?
	local maps = Workspace:FindFirstChild("Maps")
	local lobby = maps and maps:FindFirstChild("Lobby")
	local gameplay = lobby and lobby:FindFirstChild("Gameplay")
	local spawns = gameplay and gameplay:FindFirstChild("Spawns")
	local stashSpawn = spawns and spawns:FindFirstChild("Lobby_StashSpawn")
	if stashSpawn and stashSpawn:IsA("BasePart") then
		return stashSpawn
	end

	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance.Name == "Lobby_StashSpawn" and instance:IsA("BasePart") then
			return instance
		end
	end

	local lobbyFolder = Workspace:FindFirstChild("Lobby")
	local interactables = lobbyFolder and lobbyFolder:FindFirstChild("Interactables")
	local stashTerminal = interactables and interactables:FindFirstChild("StashTerminal")
	local promptPart = stashTerminal and stashTerminal:FindFirstChild("PromptPart")
	if promptPart and promptPart:IsA("BasePart") then
		return promptPart
	end

	return nil
end

local function movePlayerToStashSpawn(player: Player)
	local stashSpawn = getStashSpawn()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not stashSpawn or not character or not root or not root:IsA("BasePart") then
		return
	end

	character:PivotTo(stashSpawn.CFrame + Vector3.new(0, 3, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

local function handlePostRaidArrival(player: Player)
	local joinData = player:GetJoinData()
	local teleportData = joinData.TeleportData
	local raidResult = if typeof(teleportData) == "table" then teleportData.raidResult else nil
	if typeof(raidResult) ~= "table" or not RaidResult.isValidStatus(raidResult.status) then
		setPostRaidAttributes(player, nil)
		local existingSnapshot = LobbySessionService.getInventorySnapshot(player.UserId)
		snapshotEvent:FireClient(player, existingSnapshot)
		return
	end

	local appliedSnapshot = nil
	if raidResult.status == RaidResult.Status.EXTRACTED then
		appliedSnapshot = raidResult.inventorySnapshot
	else
		appliedSnapshot = raidResult.preRaidInventorySnapshot
	end

	if appliedSnapshot ~= nil then
		LobbySessionService.setInventorySnapshot(player.UserId, appliedSnapshot)
	else
		LobbySessionService.clearInventorySnapshot(player.UserId)
	end

	LobbySessionService.setPostRaidResult(player.UserId, raidResult)
	print(string.format("LOBBY_POST player=%s status=%s", player.Name, tostring(raidResult.status)))
	setPostRaidAttributes(player, raidResult)
	player:SetAttribute("LobbyInventorySyncNonce", Workspace:GetServerTimeNow())
	snapshotEvent:FireClient(player, appliedSnapshot)
end

continueEvent.OnServerEvent:Connect(function(player: Player)
	LobbySessionService.clearPostRaidResult(player.UserId)
	setPostRaidAttributes(player, nil)
	if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		movePlayerToStashSpawn(player)
	else
		local connection: RBXScriptConnection? = nil
		connection = player.CharacterAdded:Connect(function()
			if connection then
				connection:Disconnect()
				connection = nil
			end
			movePlayerToStashSpawn(player)
		end)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	handlePostRaidArrival(player)
end

Players.PlayerAdded:Connect(function(player)
	handlePostRaidArrival(player)
end)
