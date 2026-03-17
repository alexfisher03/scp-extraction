--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local RaidAuthority = require(script.Parent.raid.RaidAuthority)

if not PlaceConfig.isRaidPlace() then
	return
end

local function getSpawnFolder(): Folder
    local maps = workspace:WaitForChild("Maps")
    local level0 = maps:WaitForChild("Level0")
    local gameplay = level0:WaitForChild("Gameplay")
    local spawns = gameplay:WaitForChild("Spawns")
    return spawns :: Folder
end

local function getSpawnPoints(): {BasePart}
    local spawnsFolder = getSpawnFolder()
    local points = {}

    for _, inst in ipairs(spawnsFolder:GetChildren()) do
        if inst:IsA("BasePart") then
            table.insert(points, inst)
        end
    end

    assert(#points > 0, "No spawn points found in the Spawns folder.")
    return points
end

local function chooseSpawn(points: {BasePart}): BasePart
    return points[5]
end

local function getLobbySpawnPoint(): BasePart?
	local spawnsFolder = getSpawnFolder()
	local lobby = spawnsFolder:FindFirstChild("placehold_lobby")
	if lobby and lobby:IsA("BasePart") then
		return lobby
	end

	return nil
end

local function spawnCharacterAt(player: Player, character: Model)
	local raidState = RaidAuthority.getState(player.UserId)
	if raidState then
		raidState.raidLoadPhase = "WaitingForHumanoidRootPart"
		RaidAuthority.emitRaidState(player, raidState)
	end

	local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart
	local spawnPoint: BasePart?
	if raidState and raidState.phase == "Stash" then
		spawnPoint = getLobbySpawnPoint()
	end

	if not spawnPoint then
		if raidState then
			raidState.raidLoadPhase = "SelectingSpawn"
			RaidAuthority.emitRaidState(player, raidState)
		end
		local points = getSpawnPoints()
		spawnPoint = chooseSpawn(points)
	end

	if raidState then
		raidState.raidLoadPhase = "PositioningCharacter"
		RaidAuthority.emitRaidState(player, raidState)
	end

	-- Place character slightly above the marker
	local cf = spawnPoint.CFrame + Vector3.new(0, 3, 0)
	character:PivotTo(cf)

	-- reset velocity so they don't inherit weird physics
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	if raidState then
		raidState.raidLoadPhase = "CharacterPositioned"
		RaidAuthority.emitRaidState(player, raidState)
	end
end

local function setupPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		spawnCharacterAt(player, character)
	end)

	if player.Character then
		spawnCharacterAt(player, player.Character)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

Players.PlayerAdded:Connect(function(player)
	setupPlayer(player)
end)
