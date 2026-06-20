--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local RaidResult = require(ReplicatedStorage.Shared.RaidResult)

if not PlaceConfig.isLobbyPlace() then
	return
end

local function getDefaultSpawn(): BasePart?
	local maps = Workspace:FindFirstChild("Maps")
	local lobby = maps and maps:FindFirstChild("Lobby")
	local gameplay = lobby and lobby:FindFirstChild("Gameplay")
	local spawns = gameplay and gameplay:FindFirstChild("Spawns")
	local defaultSpawn = spawns and spawns:FindFirstChild("Lobby_DefaultSpawn")
	if defaultSpawn and defaultSpawn:IsA("BasePart") then
		return defaultSpawn
	end

	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance.Name == "Lobby_DefaultSpawn" and instance:IsA("BasePart") then
			return instance
		end
	end

	return nil
end

local function isReturningFromRaid(player: Player): boolean
	if player:GetAttribute("LobbyPostRaidOpen") == true then
		return true
	end

	local joinData = player:GetJoinData()
	local teleportData = joinData.TeleportData
	local raidResult = if typeof(teleportData) == "table" then teleportData.raidResult else nil
	return typeof(raidResult) == "table" and RaidResult.isValidStatus(raidResult.status)
end

local function moveToDefaultSpawn(player: Player, character: Model)
	if isReturningFromRaid(player) then
		return
	end

	local defaultSpawn = getDefaultSpawn()
	if not defaultSpawn then
		warn("[LobbySpawnService] Missing Workspace.Maps.Lobby.Gameplay.Spawns.Lobby_DefaultSpawn")
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		root = character:WaitForChild("HumanoidRootPart", 5)
	end
	if not root or not root:IsA("BasePart") then
		return
	end

	character:PivotTo(defaultSpawn.CFrame + Vector3.new(0, 4, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function setupPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.defer(function()
			moveToDefaultSpawn(player, character)
		end)
	end)

	if player.Character then
		task.defer(function()
			moveToDefaultSpawn(player, player.Character :: Model)
		end)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

Players.PlayerAdded:Connect(setupPlayer)
