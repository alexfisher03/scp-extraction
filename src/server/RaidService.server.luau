--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local InventoryAuthority = require(script.Parent.inventory.InventoryAuthority)
local RaidAuthority = require(script.Parent.raid.RaidAuthority)

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local extractRequestEvent = remotes:WaitForChild(Net.ExtractRequestStartEventName) :: RemoteEvent
local raidStateEvent = remotes:WaitForChild(Net.RaidStateEventName) :: RemoteEvent
local bodyLootOpenEvent = remotes:WaitForChild(Net.BodyLootOpenRequestEventName) :: RemoteEvent
local bodyLootCloseEvent = remotes:WaitForChild(Net.BodyLootCloseRequestEventName) :: RemoteEvent
local bodyLootTransferEvent = remotes:WaitForChild(Net.BodyLootTransferRequestEventName) :: RemoteEvent
local bodyLootSnapshotEvent = remotes:WaitForChild(Net.BodyLootSnapshotEventName) :: RemoteEvent

local EXTRACT_TICK = 0.1
local DEFAULT_EXTRACT_TIME = 5
local BODY_OPEN_DISTANCE = 12
local RAID_DURATION_SECONDS = 20 * 60

type RaidState = {
	phase: string,
	currentExtractId: string?,
	extractEndTime: number?,
	raidEndTime: number?,
	playerCanFight: boolean,
	openBodyId: string?,
	availableExtracts: {string}?,
}

type BodyState = {
	bodyId: string,
	ownerUserId: number,
	model: Model,
	capacity: number,
	itemIds: {string?},
	itemsById: {[string]: any},
}

local extractionTokensByUserId: {[number]: number} = {}
local raidEndTime = Workspace:GetServerTimeNow() + RAID_DURATION_SECONDS
local lastExtractScanAt = 0

local function cloneArray<T>(arr: {T}): {T}
	local out = table.create(#arr)
	for i, value in ipairs(arr) do
		out[i] = value
	end
	return out
end

local function cloneItems(itemsById: {[string]: any}): {[string]: any}
	local out: {[string]: any} = {}
	for itemId, item in pairs(itemsById) do
		local copy = table.clone(item)
		if item.acceptedMagTemplateIds then
			copy.acceptedMagTemplateIds = cloneArray(item.acceptedMagTemplateIds)
		end
		out[itemId] = copy
	end
	return out
end

local function serializeBodySnapshot(bodyState: BodyState?)
	if not bodyState then
		return nil
	end

	local itemIds = table.create(bodyState.capacity)
	for slotIndex = 1, bodyState.capacity do
		itemIds[slotIndex] = bodyState.itemIds[slotIndex] or ""
	end

	return {
		bodyId = bodyState.bodyId,
		ownerUserId = bodyState.ownerUserId,
		capacity = bodyState.capacity,
		itemIds = itemIds,
		itemsById = cloneItems(bodyState.itemsById),
	}
end

local function sendRaidState(player: Player, raidState: RaidState)
	player:SetAttribute("RaidPhase", raidState.phase)
	player:SetAttribute("PlayerCanFight", raidState.playerCanFight)
	player:SetAttribute("OpenBodyLootId", raidState.openBodyId)
	local payload = table.clone(raidState)
	if raidState.availableExtracts then
		payload.availableExtracts = cloneArray(raidState.availableExtracts)
	end
	raidStateEvent:FireClient(player, payload)
end

local function sendBodySnapshot(player: Player, bodyState: BodyState?)
	bodyLootSnapshotEvent:FireClient(player, serializeBodySnapshot(bodyState))
end

RaidAuthority.setRaidStateEmitter(sendRaidState)
RaidAuthority.setBodySnapshotEmitter(sendBodySnapshot)

local function getRoot(character: Model?): BasePart?
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getLobbySpawn(): BasePart?
	local maps = Workspace:FindFirstChild("Maps")
	local level0 = maps and maps:FindFirstChild("Level0")
	local gameplay = level0 and level0:FindFirstChild("Gameplay")
	local spawns = gameplay and gameplay:FindFirstChild("Spawns")
	if not spawns then
		return nil
	end

	local lobby = spawns:FindFirstChild("placehold_lobby")
	if lobby and lobby:IsA("BasePart") then
		return lobby
	end

	return nil
end

local function getExtractsFolder(): Folder?
	local maps = Workspace:FindFirstChild("Maps")
	local level0 = maps and maps:FindFirstChild("Level0")
	local gameplay = level0 and level0:FindFirstChild("Gameplay")
	local extracts = gameplay and gameplay:FindFirstChild("Extracts")
	if extracts and extracts:IsA("Folder") then
		return extracts
	end

	return nil
end

local function getExtractHandle(extractModel: Model): BasePart?
	local handle = extractModel:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle
	end

	return extractModel.PrimaryPart
end

local function getAvailableExtracts(): {string}
	local extractsFolder = getExtractsFolder()
	if not extractsFolder then
		return {}
	end

	local out = {}
	for _, child in ipairs(extractsFolder:GetChildren()) do
		if child:IsA("Model") then
			local extractId = child:GetAttribute("ExtractId")
			table.insert(out, typeof(extractId) == "string" and extractId or child.Name)
		end
	end

	table.sort(out)
	return out
end

local function isInsideZone(handle: BasePart, worldPosition: Vector3): boolean
	local localPosition = handle.CFrame:PointToObjectSpace(worldPosition)
	local halfSize = handle.Size * 0.5
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end

local function isPlayerInsideExtract(player: Player, extractModel: Model): boolean
	local root = getRoot(player.Character)
	local handle = getExtractHandle(extractModel)
	if not root or not handle then
		return false
	end

	return isInsideZone(handle, root.Position)
end

local function getContainingExtractForPlayer(player: Player): Model?
	local extractsFolder = getExtractsFolder()
	if not extractsFolder then
		return nil
	end

	for _, child in ipairs(extractsFolder:GetChildren()) do
		if child:IsA("Model") and isPlayerInsideExtract(player, child) then
			return child
		end
	end

	return nil
end

local function getBodyFolder(): Folder
	local existing = Workspace:FindFirstChild("RaidBodies")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "RaidBodies"
	folder.Parent = Workspace
	return folder
end

local function countOccupiedSlots(itemIds: {string?}, capacity: number): number
	local count = 0
	for slotIndex = 1, capacity do
		if itemIds[slotIndex] ~= nil then
			count += 1
		end
	end
	return count
end

local function getFirstEmptySlot(itemIds: {string?}, capacity: number): number?
	for slotIndex = 1, capacity do
		if itemIds[slotIndex] == nil then
			return slotIndex
		end
	end
	return nil
end

local function findItemIndex(itemIds: {string?}, capacity: number, itemId: string): number?
	for slotIndex = 1, capacity do
		if itemIds[slotIndex] == itemId then
			return slotIndex
		end
	end
	return nil
end

local function playerContainerAcceptsItem(containerName: string, item: any): boolean
	if containerName == "backpack" or containerName == "Backpack" then
		return true
	end

	if containerName == "rig" or containerName == "Rig" then
		return item.category == "mag" or item.category == "med"
	end

	return false
end

local function getPlayerContainer(state: any, containerName: string): any?
	if containerName == "rig" or containerName == "Rig" then
		return state.rig
	end

	if containerName == "backpack" or containerName == "Backpack" then
		return state.backpack
	end

	return nil
end

local function setPhase(player: Player, raidState: RaidState, phase: string)
	raidState.phase = phase
	raidState.playerCanFight = phase == "InRaid"
	raidState.raidEndTime = raidEndTime
	raidState.availableExtracts = getAvailableExtracts()
	if phase ~= "Extracting" then
		raidState.currentExtractId = nil
		raidState.extractEndTime = nil
	end
	if phase ~= "InRaid" then
		raidState.openBodyId = nil
	end
	RaidAuthority.emitRaidState(player, raidState)
end

local function closeBodyLoot(player: Player, raidState: RaidState)
	if raidState.openBodyId ~= nil then
		raidState.openBodyId = nil
		RaidAuthority.emitRaidState(player, raidState)
	end
	RaidAuthority.emitBodySnapshot(player, nil)
end

local function getBodyFromInstance(instance: Instance): BodyState?
	local current: Instance? = instance
	while current do
		if current:IsA("Model") then
			local bodyState = RaidAuthority.getBodyByModel(current)
			if bodyState then
				return bodyState
			end
		end
		current = current.Parent
	end

	return nil
end

local function canInteractWithBody(player: Player, bodyState: BodyState): boolean
	local root = getRoot(player.Character)
	local handle = bodyState.model:FindFirstChild("Handle")
	if not root or not handle or not handle:IsA("BasePart") then
		return false
	end

	return (handle.Position - root.Position).Magnitude <= BODY_OPEN_DISTANCE
end

local function markInventoryItemsLocation(state: any, locationState: string)
	for _, item in pairs(state.itemsById) do
		item.locationState = locationState
	end
end

local function collectBodyItemIds(inventoryState: any): {string}
	local ordered: {string} = {}
	local seen: {[string]: boolean} = {}

	local function addItemId(itemId: string?)
		if itemId and not seen[itemId] then
			seen[itemId] = true
			table.insert(ordered, itemId)
		end
	end

	for _, slotName in ipairs({ "PrimaryA", "PrimaryB", "Pistol", "Melee" }) do
		addItemId(inventoryState.weaponSlots[slotName])
	end

	for slotIndex = 1, inventoryState.rig.capacity do
		addItemId(inventoryState.rig.itemIds[slotIndex])
	end

	for slotIndex = 1, inventoryState.backpack.capacity do
		addItemId(inventoryState.backpack.itemIds[slotIndex])
	end

	for _, itemId in ipairs(ordered) do
		local item = inventoryState.itemsById[itemId]
		if item and item.attachedMagId then
			addItemId(item.attachedMagId)
		end
	end

	return ordered
end

local function makeTransferredItemId(inventoryState: any, templateId: string): string
	local itemId = string.format("%s_%d", templateId, inventoryState.nextItemId)
	inventoryState.nextItemId += 1
	return itemId
end

local function cloneBodyItemIntoInventory(inventoryState: any, bodyState: BodyState, sourceItemId: string, remap: {[string]: string}): string?
	local sourceItem = bodyState.itemsById[sourceItemId]
	if not sourceItem then
		return nil
	end

	local existingId = remap[sourceItemId]
	if existingId then
		return existingId
	end

	local copy = table.clone(sourceItem)
	local newItemId = makeTransferredItemId(inventoryState, copy.templateId)
	remap[sourceItemId] = newItemId
	copy.itemId = newItemId
	copy.locationState = "inRaid"

	if copy.attachedMagId and bodyState.itemsById[copy.attachedMagId] then
		local newAttachedMagId = cloneBodyItemIntoInventory(inventoryState, bodyState, copy.attachedMagId, remap)
		copy.attachedMagId = newAttachedMagId
	end

	inventoryState.itemsById[newItemId] = copy
	return newItemId
end

local function buildBodyStateFromInventory(player: Player, inventoryState: any, position: Vector3): BodyState?
	local bodyItemIds = collectBodyItemIds(inventoryState)
	if #bodyItemIds == 0 then
		return nil
	end

	local timestamp = math.floor(Workspace:GetServerTimeNow() * 1000)
	local bodyId = string.format("body_%d_%d", player.UserId, timestamp)
	local model = Instance.new("Model")
	model.Name = string.format("Body_%d_%d", player.UserId, timestamp)
	model:SetAttribute("BodyLootId", bodyId)
	model:SetAttribute("BodyOwnerUserId", player.UserId)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(3, 1.5, 2)
	handle.Transparency = 1
	handle.CanCollide = true
	handle.CanQuery = true
	handle.Anchored = false
	handle.CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0))
	handle.Parent = model

	local visual = Instance.new("Part")
	visual.Name = "Visual"
	visual.Size = Vector3.new(2.5, 1, 4)
	visual.Color = Color3.fromRGB(90, 40, 40)
	visual.Material = Enum.Material.SmoothPlastic
	visual.CanCollide = false
	visual.CanQuery = false
	visual.Anchored = false
	visual.CFrame = handle.CFrame * CFrame.new(0, -0.6, 0)
	visual.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = visual
	weld.Parent = handle

	model.PrimaryPart = handle
	model.Parent = getBodyFolder()

	local capacity = math.max(#bodyItemIds, 1)
	local itemIds = table.create(capacity)
	for slotIndex, itemId in ipairs(bodyItemIds) do
		itemIds[slotIndex] = itemId
	end

	local itemsById = cloneItems(inventoryState.itemsById)
	return {
		bodyId = bodyId,
		ownerUserId = player.UserId,
		model = model,
		capacity = capacity,
		itemIds = itemIds,
		itemsById = itemsById,
	}
end

local function clearInventoryForLoss(inventoryState: any)
	inventoryState.equippedSlot = nil
	inventoryState.weaponSlots.PrimaryA = nil
	inventoryState.weaponSlots.PrimaryB = nil
	inventoryState.weaponSlots.Pistol = nil
	inventoryState.weaponSlots.Melee = nil
	inventoryState.rig.itemIds = {}
	inventoryState.backpack.itemIds = {}
	inventoryState.itemsById = {}
	inventoryState.isReloading = false
	inventoryState.lastCheckMag = nil
	inventoryState.lastCheckMagSeq = (inventoryState.lastCheckMagSeq or 0) + 1
end

local function teleportCharacterToLobby(player: Player)
	local lobbySpawn = getLobbySpawn()
	local root = getRoot(player.Character)
	if not lobbySpawn or not root then
		return
	end

	player.Character:PivotTo(lobbySpawn.CFrame + Vector3.new(0, 3, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

local function finalizeExtraction(player: Player, raidState: RaidState)
	local inventoryState = InventoryAuthority.getState(player.UserId)
	if inventoryState then
		markInventoryItemsLocation(inventoryState, "stashed")
		InventoryAuthority.emitSnapshot(player, inventoryState)
	end

	closeBodyLoot(player, raidState)
	setPhase(player, raidState, "Stash")
	teleportCharacterToLobby(player)
end

local function cancelExtraction(player: Player, raidState: RaidState)
	setPhase(player, raidState, "InRaid")
end

local function startExtractionLoop(player: Player, raidState: RaidState, extractModel: Model)
	local userId = player.UserId
	local token = (extractionTokensByUserId[userId] or 0) + 1
	extractionTokensByUserId[userId] = token

	task.spawn(function()
		while extractionTokensByUserId[userId] == token do
			task.wait(EXTRACT_TICK)

			if not player.Parent then
				return
			end

			local currentState = RaidAuthority.getState(userId)
			if not currentState or currentState.phase ~= "Extracting" then
				return
			end

			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				cancelExtraction(player, currentState)
				return
			end

			if not isPlayerInsideExtract(player, extractModel) then
				cancelExtraction(player, currentState)
				return
			end

			if currentState.extractEndTime and Workspace:GetServerTimeNow() >= currentState.extractEndTime then
				finalizeExtraction(player, currentState)
				return
			end
		end
	end)
end

local function resolveExtractModel(extractInstance: Instance): Model?
	if not extractInstance:IsDescendantOf(Workspace) then
		return nil
	end

	local extractsFolder = getExtractsFolder()
	if not extractsFolder or not extractInstance:IsDescendantOf(extractsFolder) then
		return nil
	end

	if extractInstance:IsA("Model") then
		return extractInstance
	end

	local parent = extractInstance:FindFirstAncestorOfClass("Model")
	if parent and parent:IsDescendantOf(extractsFolder) then
		return parent
	end

	return nil
end

local function handleExtractRequest(player: Player, extractInstance: Instance)
	local raidState = RaidAuthority.getOrCreateState(player.UserId)
	if raidState.phase ~= "InRaid" then
		return
	end

	local extractModel = resolveExtractModel(extractInstance)
	if not extractModel then
		return
	end

	local handle = getExtractHandle(extractModel)
	if not handle then
		return
	end

	if not isPlayerInsideExtract(player, extractModel) then
		return
	end

	raidState.phase = "Extracting"
	raidState.playerCanFight = false
	raidState.currentExtractId = extractModel:GetAttribute("ExtractId") or extractModel.Name
	raidState.extractEndTime = Workspace:GetServerTimeNow() + (extractModel:GetAttribute("ExtractTime") or DEFAULT_EXTRACT_TIME)
	raidState.raidEndTime = raidEndTime
	raidState.availableExtracts = getAvailableExtracts()
	closeBodyLoot(player, raidState)
	RaidAuthority.emitRaidState(player, raidState)
	startExtractionLoop(player, raidState, extractModel)
end

local function tryAutoStartExtraction(player: Player)
	local raidState = RaidAuthority.getOrCreateState(player.UserId)
	if raidState.phase ~= "InRaid" then
		return
	end

	local extractModel = getContainingExtractForPlayer(player)
	if not extractModel then
		return
	end

	handleExtractRequest(player, extractModel)
end

local function resolveBodyOpen(player: Player, bodyInstance: Instance)
	local raidState = RaidAuthority.getOrCreateState(player.UserId)
	if raidState.phase ~= "InRaid" then
		return
	end

	local bodyState = getBodyFromInstance(bodyInstance)
	if not bodyState then
		return
	end

	if not canInteractWithBody(player, bodyState) then
		return
	end

	raidState.openBodyId = bodyState.bodyId
	RaidAuthority.emitRaidState(player, raidState)
	RaidAuthority.emitBodySnapshot(player, bodyState)
end

local function handleBodyTransfer(player: Player, bodyId: string, itemId: string, toContainerName: string, toIndex: number?)
	local raidState = RaidAuthority.getOrCreateState(player.UserId)
	if raidState.phase ~= "InRaid" then
		return
	end

	local bodyState = RaidAuthority.getBody(bodyId)
	if not bodyState or not canInteractWithBody(player, bodyState) then
		closeBodyLoot(player, raidState)
		return
	end

	local inventoryState = InventoryAuthority.getState(player.UserId)
	if not inventoryState then
		return
	end

	local item = bodyState.itemsById[itemId]
	if not item then
		return
	end

	local fromIndex = findItemIndex(bodyState.itemIds, bodyState.capacity, itemId)
	if not fromIndex then
		return
	end

	local destination = getPlayerContainer(inventoryState, toContainerName)
	if not destination then
		return
	end

	if not playerContainerAcceptsItem(toContainerName, item) then
		return
	end

	local destinationIndex: number?
	if toIndex ~= nil then
		local requestedIndex = math.floor(toIndex)
		if requestedIndex >= 1 and requestedIndex <= destination.capacity and destination.itemIds[requestedIndex] == nil then
			destinationIndex = requestedIndex
		end
	else
		destinationIndex = getFirstEmptySlot(destination.itemIds, destination.capacity)
	end

	if not destinationIndex then
		return
	end

	bodyState.itemIds[fromIndex] = nil
	local remap: {[string]: string} = {}
	local newItemId = cloneBodyItemIntoInventory(inventoryState, bodyState, itemId, remap)
	if not newItemId then
		bodyState.itemIds[fromIndex] = itemId
		return
	end

	destination.itemIds[destinationIndex] = newItemId
	for sourceItemId in pairs(remap) do
		bodyState.itemsById[sourceItemId] = nil
	end
	InventoryAuthority.emitSnapshot(player, inventoryState)
	RaidAuthority.emitBodySnapshot(player, bodyState)
end

local function handleBodyLootClose(player: Player)
	local raidState = RaidAuthority.getOrCreateState(player.UserId)
	closeBodyLoot(player, raidState)
end

local function handleCharacterDied(player: Player, character: Model)
	local raidState = RaidAuthority.getOrCreateState(player.UserId)
	if raidState.phase == "Stash" then
		return
	end

	local root = getRoot(character)
	local inventoryState = InventoryAuthority.getState(player.UserId)
	if not root or not inventoryState then
		setPhase(player, raidState, "Stash")
		return
	end

	local bodyState = buildBodyStateFromInventory(player, inventoryState, root.Position)
	if bodyState then
		RaidAuthority.setBody(bodyState.bodyId, bodyState)
	end

	clearInventoryForLoss(inventoryState)
	InventoryAuthority.emitSnapshot(player, inventoryState)
	closeBodyLoot(player, raidState)
	setPhase(player, raidState, "Stash")

	task.delay(1.0, function()
		if player.Parent then
			player:LoadCharacter()
		end
	end)
end

local function bindCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		handleCharacterDied(player, character)
	end)
end

local function setupPlayer(player: Player)
	local raidState = RaidAuthority.getOrCreateState(player.UserId)
	raidState.raidEndTime = raidEndTime
	raidState.availableExtracts = getAvailableExtracts()
	RaidAuthority.emitRaidState(player, raidState)
	RaidAuthority.emitBodySnapshot(player, nil)

	player.CharacterAdded:Connect(function(character)
		bindCharacter(player, character)
		local currentState = RaidAuthority.getOrCreateState(player.UserId)
		currentState.raidEndTime = raidEndTime
		currentState.availableExtracts = getAvailableExtracts()
		RaidAuthority.emitRaidState(player, currentState)
	end)

	if player.Character then
		bindCharacter(player, player.Character)
	end
end

function closeRaid()
	local bodyFolder = Workspace:FindFirstChild("RaidBodies")
	if bodyFolder then
		for _, child in ipairs(bodyFolder:GetChildren()) do
			child:Destroy()
		end
	end

	for bodyId in pairs(RaidAuthority.getAllBodies()) do
		RaidAuthority.removeBody(bodyId)
	end
end

extractRequestEvent.OnServerEvent:Connect(function(player: Player, extractInstance: any)
	if typeof(extractInstance) ~= "Instance" then
		return
	end

	handleExtractRequest(player, extractInstance)
end)

bodyLootOpenEvent.OnServerEvent:Connect(function(player: Player, bodyInstance: any)
	if typeof(bodyInstance) ~= "Instance" then
		return
	end

	resolveBodyOpen(player, bodyInstance)
end)

bodyLootCloseEvent.OnServerEvent:Connect(function(player: Player)
	handleBodyLootClose(player)
end)

bodyLootTransferEvent.OnServerEvent:Connect(function(player: Player, bodyId: any, itemId: any, toContainerName: any, toIndex: any)
	if typeof(bodyId) ~= "string" or typeof(itemId) ~= "string" or typeof(toContainerName) ~= "string" then
		return
	end

	if toIndex ~= nil and typeof(toIndex) ~= "number" then
		return
	end

	handleBodyTransfer(player, bodyId, itemId, toContainerName, toIndex)
end)

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

Players.PlayerAdded:Connect(function(player)
	setupPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	RaidAuthority.removeState(player.UserId)
end)

RunService.Heartbeat:Connect(function()
	local now = Workspace:GetServerTimeNow()
	if now - lastExtractScanAt < EXTRACT_TICK then
		return
	end

	lastExtractScanAt = now
	for _, player in ipairs(Players:GetPlayers()) do
		tryAutoStartExtraction(player)
	end
end)

task.delay(RAID_DURATION_SECONDS, closeRaid)
