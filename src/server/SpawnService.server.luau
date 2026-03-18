--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local RaidAuthority = require(script.Parent.raid.RaidAuthority)

if not PlaceConfig.isRaidPlace() then
	return
end

local INITIAL_MIN_SPAWN_DISTANCE = 120
local SPAWN_DISTANCE_RELAX_STEP = 20
local PARTY_SPAWN_WAIT_SECONDS = 8
local PARTY_SPAWN_GATHER_SECONDS = 2
local ALLOWED_RAID_SPAWN_NAMES = {
	D_01 = true,
	D_02 = true,
	SS_01 = true,
	SS_02 = true,
}

local assignedSpawnByUserId: {[number]: BasePart} = {}
local assignmentPrepared = false
local assignmentInProgress = false
local expectedPartyUserIds: {number} = {}
local expectedPartySet: {[number]: boolean} = {}

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
		if inst:IsA("BasePart") and ALLOWED_RAID_SPAWN_NAMES[inst.Name] then
			table.insert(points, inst)
		end
	end

	assert(#points > 0, "No valid raid spawn points found in the Spawns folder. Expected D_01, D_02, SS_01, or SS_02.")
	return points
end

local function cloneArray<T>(arr: {T}): {T}
	local out = table.create(#arr)
	for index, value in ipairs(arr) do
		out[index] = value
	end
	return out
end

local function shuffleArray<T>(arr: {T}, rng: Random): {T}
	local out = cloneArray(arr)
	for index = #out, 2, -1 do
		local swapIndex = rng:NextInteger(1, index)
		out[index], out[swapIndex] = out[swapIndex], out[index]
	end
	return out
end

local function mergeExpectedPartyUserIds(userIds: {any}?)
	if typeof(userIds) ~= "table" then
		return
	end

	for _, userId in ipairs(userIds) do
		if typeof(userId) == "number" and not expectedPartySet[userId] then
			expectedPartySet[userId] = true
			table.insert(expectedPartyUserIds, userId)
		end
	end

	table.sort(expectedPartyUserIds)
end

local function getSortedPlayers(players: {Player}): {Player}
	table.sort(players, function(a, b)
		return a.UserId < b.UserId
	end)
	return players
end

local function getRaidPlayers(): {Player}
	local players = Players:GetPlayers()
	return getSortedPlayers(players)
end

local function hydrateExpectedPartyFromCurrentPlayers()
	for _, player in ipairs(Players:GetPlayers()) do
		local joinData = player:GetJoinData()
		local teleportData = joinData.TeleportData
		if typeof(teleportData) == "table" then
			mergeExpectedPartyUserIds(teleportData.partyUserIds)
		end
	end
end

local function getExpectedRaidPlayers(): {Player}
	if #expectedPartyUserIds == 0 then
		return getRaidPlayers()
	end

	local players = {}
	for _, userId in ipairs(expectedPartyUserIds) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			table.insert(players, player)
		end
	end

	return getSortedPlayers(players)
end

local function waitForExpectedPartyPlayers()
	hydrateExpectedPartyFromCurrentPlayers()
	local deadline = workspace:GetServerTimeNow() + PARTY_SPAWN_WAIT_SECONDS
	local gatherDeadline = workspace:GetServerTimeNow() + PARTY_SPAWN_GATHER_SECONDS

	while workspace:GetServerTimeNow() < deadline do
		hydrateExpectedPartyFromCurrentPlayers()

		if #expectedPartyUserIds == 0 then
			if workspace:GetServerTimeNow() >= gatherDeadline then
				return
			end
			task.wait(0.1)
			continue
		end

		if #getExpectedRaidPlayers() >= #expectedPartyUserIds then
			return
		end

		task.wait(0.1)
	end
end

local function getPointDistance(a: BasePart, b: BasePart): number
	return (a.Position - b.Position).Magnitude
end

local function scoreSpawnSet(points: {BasePart}): (number, number)
	if #points <= 1 then
		return math.huge, math.huge
	end

	local minDistance = math.huge
	local totalDistance = 0
	local pairCount = 0

	for i = 1, #points do
		for j = i + 1, #points do
			local distance = getPointDistance(points[i], points[j])
			minDistance = math.min(minDistance, distance)
			totalDistance += distance
			pairCount += 1
		end
	end

	local averageDistance = if pairCount > 0 then totalDistance / pairCount else math.huge
	return minDistance, averageDistance
end

local function chooseBestSpawnSet(points: {BasePart}, neededCount: number, minDistance: number, rng: Random): {BasePart}?
	local bestSet: {BasePart}? = nil
	local bestMinDistance = -1
	local bestAverageDistance = -1

	local function considerSelection(selection: {BasePart})
		local selectionMinDistance, selectionAverageDistance = scoreSpawnSet(selection)
		if selectionMinDistance < minDistance then
			return
		end

		if selectionMinDistance > bestMinDistance then
			bestSet = cloneArray(selection)
			bestMinDistance = selectionMinDistance
			bestAverageDistance = selectionAverageDistance
			return
		end

		if selectionMinDistance == bestMinDistance and selectionAverageDistance > bestAverageDistance then
			bestSet = cloneArray(selection)
			bestMinDistance = selectionMinDistance
			bestAverageDistance = selectionAverageDistance
			return
		end

		if selectionMinDistance == bestMinDistance and selectionAverageDistance == bestAverageDistance and rng:NextNumber() < 0.5 then
			bestSet = cloneArray(selection)
		end
	end

	local function search(startIndex: number, selection: {BasePart})
		if #selection == neededCount then
			considerSelection(selection)
			return
		end

		for index = startIndex, #points do
			table.insert(selection, points[index])
			search(index + 1, selection)
			table.remove(selection)
		end
	end

	search(1, {})
	return bestSet
end

local function tryBuildAssignments(players: {Player}, points: {BasePart}, minDistance: number, rng: Random): ({[number]: BasePart}?, number)
	local chosenPoints = chooseBestSpawnSet(points, #players, minDistance, rng)
	if not chosenPoints then
		return nil, 0
	end

	local shuffledPlayers = shuffleArray(players, rng)
	local shuffledPoints = shuffleArray(chosenPoints, rng)
	local assignments: {[number]: BasePart} = {}
	for index, player in ipairs(shuffledPlayers) do
		assignments[player.UserId] = shuffledPoints[index]
	end

	local achievedMinDistance = scoreSpawnSet(chosenPoints)
	return assignments, achievedMinDistance
end

local function setCharacterToSpawn(character: Model, spawnPoint: BasePart)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	local cf = spawnPoint.CFrame + Vector3.new(0, 3, 0)
	character:PivotTo(cf)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

local function repositionAssignedLoadingPlayers()
	for _, player in ipairs(Players:GetPlayers()) do
		local assigned = assignedSpawnByUserId[player.UserId]
		if not assigned then
			continue
		end

		local raidState = RaidAuthority.getState(player.UserId)
		if raidState and raidState.phase == "InRaid" then
			continue
		end

		local character = player.Character
		if character then
			setCharacterToSpawn(character, assigned)
		end
	end
end

local function resetAssignments()
	assignedSpawnByUserId = {}
	assignmentPrepared = false
	assignmentInProgress = false
end

local function prepareSpawnAssignments()
	if assignmentPrepared then
		return
	end

	if assignmentInProgress then
		while assignmentInProgress and not assignmentPrepared do
			task.wait()
		end
		return
	end

	assignmentInProgress = true
	local ok, err = pcall(function()
		waitForExpectedPartyPlayers()

		local players = getExpectedRaidPlayers()
		local points = getSpawnPoints()
		local rng = Random.new(math.floor(workspace:GetServerTimeNow() * 1000))

		local minDistance = INITIAL_MIN_SPAWN_DISTANCE
		local assignments: {[number]: BasePart}? = nil
		local usedMinDistance = 0
		local achievedMinDistance = 0

		while minDistance >= 0 do
			assignments, achievedMinDistance = tryBuildAssignments(players, points, minDistance, rng)
			if assignments then
				usedMinDistance = minDistance
				break
			end
			minDistance -= SPAWN_DISTANCE_RELAX_STEP
		end

		if not assignments then
			assignments = {}
			local shuffledPoints = shuffleArray(points, rng)
			for index, player in ipairs(players) do
				assignments[player.UserId] = shuffledPoints[((index - 1) % #shuffledPoints) + 1]
			end
			achievedMinDistance = 0
		end

		assignedSpawnByUserId = assignments
		assignmentPrepared = true
		repositionAssignedLoadingPlayers()

		local summaryParts = {}
		for _, player in ipairs(players) do
			local point = assignedSpawnByUserId[player.UserId]
			if point then
				table.insert(summaryParts, string.format("%s=%s", player.Name, point.Name))
			end
		end
		print(string.format(
			"[SpawnService] Spawn assignments requestedMinDistance=%d achievedMinDistance=%.1f expectedPlayers=%d presentPlayers=%d %s",
			usedMinDistance,
			achievedMinDistance,
			#expectedPartyUserIds,
			#players,
			table.concat(summaryParts, ", ")
		))
	end)
	assignmentInProgress = false
	if not ok then
		error(err)
	end
end

local function chooseSpawn(player: Player): BasePart
	if not assignmentPrepared or assignedSpawnByUserId[player.UserId] == nil then
		if assignmentPrepared and assignedSpawnByUserId[player.UserId] == nil then
			resetAssignments()
		end
		prepareSpawnAssignments()
	end

	local assigned = assignedSpawnByUserId[player.UserId]
	if assigned then
		return assigned
	end

	local points = getSpawnPoints()
	return points[1]
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
		spawnPoint = chooseSpawn(player)
	end

	if raidState then
		raidState.raidLoadPhase = "PositioningCharacter"
		RaidAuthority.emitRaidState(player, raidState)
	end

	setCharacterToSpawn(character, spawnPoint)

	if raidState then
		raidState.raidLoadPhase = "CharacterPositioned"
		RaidAuthority.emitRaidState(player, raidState)
	end
end

local function setupPlayer(player: Player)
	local joinData = player:GetJoinData()
	local teleportData = joinData.TeleportData
	if typeof(teleportData) == "table" then
		mergeExpectedPartyUserIds(teleportData.partyUserIds)
	end

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
