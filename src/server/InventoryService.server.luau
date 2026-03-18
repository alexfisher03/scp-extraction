--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local LootDefinitions = require(ReplicatedStorage.Shared.LootDefinitions)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local InventoryAuthority = require(script.Parent.inventory.InventoryAuthority)
local RaidAuthority = require(script.Parent.raid.RaidAuthority)
local LobbySessionService = if PlaceConfig.isLobbyPlace()
	then require(script.Parent.lobby.LobbySessionService)
	else nil

if not (PlaceConfig.isRaidPlace() or PlaceConfig.isLobbyPlace()) then
	return
end

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local actionEvent = remotes:WaitForChild(Net.InventoryActionEventName) :: RemoteEvent
local snapshotEvent = remotes:WaitForChild(Net.InventorySnapshotEventName) :: RemoteEvent
local pickupEvent = remotes:WaitForChild(Net.LootPickupRequestEventName) :: RemoteEvent
local moveItemEvent = remotes:WaitForChild(Net.MoveItemRequestEventName) :: RemoteEvent
local dropItemEvent = remotes:WaitForChild(Net.DropItemRequestEventName) :: RemoteEvent
local itemActionEvent = remotes:WaitForChild(Net.ItemActionRequestEventName) :: RemoteEvent

local MAX_DISTANCE = 300
local DAMAGE = 30

local FIRE_COOLDOWN = 0.15
local EQUIP_COOLDOWN = 0.05
local RELOAD_COOLDOWN = 0.2
local CHECK_MAG_COOLDOWN = 0.6
local PICKUP_COOLDOWN = 0.15
local RELOAD_SECONDS = 2.2
local CHECK_MAG_SECONDS = 1.0
local PICKUP_DISTANCE = 15

type SlotName = "PrimaryA" | "PrimaryB" | "Pistol" | "Melee"

type Item = {
    itemId: string,
    templateId: string,
    category: string,
    locationState: string?,
    stack: number?,
    ammo: number?,
    capacity: number?,
    usesRemaining: number?,
    usesMax: number?,
    attachedMagId: string?,
    acceptedMagTemplateIds: {string}?,
}

type Container = {
    capacity: number,
    itemIds: {string?},
}

type InventoryState = {
    version: number,
    equippedSlot: SlotName?,
    weaponSlots: {[string]: string?},
    rig: Container,
    backpack: Container,
    quickBinds: {[number]: string?},
    itemsById: {[string]: Item},
    isReloading: boolean,
    lastCheckMag: string?,
    cooldowns: {[string]: number},
    lastCheckMagSeq: number,
    nextItemId: number,
}

local lootedSet: {[Instance]: boolean} = {}

local function canUseRaidGameplay(player: Player): boolean
	return PlaceConfig.isRaidPlace() and RaidAuthority.isInRaid(player.UserId)
end

local function cloneArray<T>(arr: {T}): {T}
	local out = table.create(#arr)
	for i, v in ipairs(arr) do
		out[i] = v
	end
	return out
end

local function cloneContainerItemIds(container: Container): {string}
	local out = table.create(container.capacity)
	for slotIndex = 1, container.capacity do
		out[slotIndex] = container.itemIds[slotIndex] or ""
	end
	return out
end

local function countContainerItems(container: Container): number
	local count = 0
	for slotIndex = 1, container.capacity do
		if container.itemIds[slotIndex] ~= nil then
			count += 1
		end
	end
	return count
end

local function getFirstEmptySlot(container: Container): number?
	for slotIndex = 1, container.capacity do
		if container.itemIds[slotIndex] == nil then
			return slotIndex
		end
	end

	return nil
end

local function cloneItems(itemsById: {[string]: Item}): {[string]: Item}
    local out: {[string]: Item} = {}
    for itemId, item in pairs(itemsById) do
        local copy: Item = table.clone(item)
        if item.acceptedMagTemplateIds then
            copy.acceptedMagTemplateIds = cloneArray(item.acceptedMagTemplateIds)
        end
        out[itemId] = copy
    end
    return out
end

local function buildHotbarItemIds(state: InventoryState): {string?}
    local hotbar: {string?} = table.create(5)
    hotbar[1] = state.weaponSlots.PrimaryA
    hotbar[2] = state.weaponSlots.PrimaryB
    hotbar[3] = state.weaponSlots.Pistol
    hotbar[4] = state.weaponSlots.Melee
    hotbar[5] = state.quickBinds[1]
    return hotbar
end

local function toSnapshot(state: InventoryState)
    return {
        version = state.version,
        equippedSlot = state.equippedSlot,
        weaponSlots = table.clone(state.weaponSlots),
        rig = {
            capacity = state.rig.capacity,
            itemIds = cloneContainerItemIds(state.rig),
        },
        backpack = {
            capacity = state.backpack.capacity,
            itemIds = cloneContainerItemIds(state.backpack),
        },
        quickBinds = table.clone(state.quickBinds),
        hotbarItemIds = buildHotbarItemIds(state),
        itemsById = cloneItems(state.itemsById),
        isReloading = state.isReloading,
        lastCheckMag = state.lastCheckMag,
        lastCheckMagSeq = state.lastCheckMagSeq,
    }
end

local function getNextItemIdFromSnapshot(snapshot: any): number
	local maxSuffix = 0
	local itemsById = snapshot and snapshot.itemsById or nil
	if typeof(itemsById) ~= "table" then
		return 1
	end

	for itemId in pairs(itemsById) do
		if typeof(itemId) == "string" then
			local suffix = string.match(itemId, ".*_(%d+)$")
			local asNumber = suffix and tonumber(suffix) or nil
			if asNumber and asNumber > maxSuffix then
				maxSuffix = asNumber
			end
		end
	end

	return maxSuffix + 1
end

local function restoreStateFromSnapshot(snapshot: any): InventoryState?
	if typeof(snapshot) ~= "table" then
		return nil
	end

	local rigSnapshot = snapshot.rig
	local backpackSnapshot = snapshot.backpack
	local weaponSlotsSnapshot = snapshot.weaponSlots
	local itemsByIdSnapshot = snapshot.itemsById
	if typeof(rigSnapshot) ~= "table"
		or typeof(backpackSnapshot) ~= "table"
		or typeof(weaponSlotsSnapshot) ~= "table"
		or typeof(itemsByIdSnapshot) ~= "table"
	then
		return nil
	end

	local itemsById: {[string]: Item} = {}
	for itemId, rawItem in pairs(itemsByIdSnapshot) do
		if typeof(itemId) == "string" and typeof(rawItem) == "table" then
			local itemCopy: Item = table.clone(rawItem)
			if rawItem.acceptedMagTemplateIds then
				itemCopy.acceptedMagTemplateIds = cloneArray(rawItem.acceptedMagTemplateIds)
			end
			itemsById[itemId] = itemCopy
		end
	end

	local function restoreContainer(rawContainer: any): Container
		local capacity = if typeof(rawContainer.capacity) == "number" then math.max(0, math.floor(rawContainer.capacity)) else 0
		local restored: Container = {
			capacity = capacity,
			itemIds = table.create(capacity),
		}

		for slotIndex = 1, capacity do
			local rawItemId = rawContainer.itemIds and rawContainer.itemIds[slotIndex] or nil
			if typeof(rawItemId) == "string" and rawItemId ~= "" then
				restored.itemIds[slotIndex] = rawItemId
			else
				restored.itemIds[slotIndex] = nil
			end
		end

		return restored
	end

	return {
		version = if typeof(snapshot.version) == "number" then snapshot.version else 0,
		equippedSlot = snapshot.equippedSlot,
		weaponSlots = {
			PrimaryA = weaponSlotsSnapshot.PrimaryA,
			PrimaryB = weaponSlotsSnapshot.PrimaryB,
			Pistol = weaponSlotsSnapshot.Pistol,
			Melee = weaponSlotsSnapshot.Melee,
		},
		rig = restoreContainer(rigSnapshot),
		backpack = restoreContainer(backpackSnapshot),
		quickBinds = if typeof(snapshot.quickBinds) == "table" then table.clone(snapshot.quickBinds) else {},
		itemsById = itemsById,
		isReloading = false,
		lastCheckMag = snapshot.lastCheckMag,
		cooldowns = {},
		lastCheckMagSeq = if typeof(snapshot.lastCheckMagSeq) == "number" then snapshot.lastCheckMagSeq else 0,
		nextItemId = getNextItemIdFromSnapshot(snapshot),
	}
end

local function sendSnapshot(player: Player, state: InventoryState)
    state.version += 1
    snapshotEvent:FireClient(player, toSnapshot(state))
end

InventoryAuthority.setSnapshotEmitter(sendSnapshot)
InventoryAuthority.setSnapshotSerializer(toSnapshot)

local function isAliveCharacter(character: Model?): boolean
    if not character then return false end
    local hum = character:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local function getRoot(character: Model): BasePart?
    return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function isRateLimited(state: InventoryState, key: string, cooldown: number): boolean
    local now = os.clock()
    local prev = state.cooldowns[key]
    if prev and (now - prev) < cooldown then
        return true
    end
    state.cooldowns[key] = now
    return false
end

local function removeFromContainer(container: Container, itemId: string): boolean
	for slotIndex = 1, container.capacity do
		if container.itemIds[slotIndex] == itemId then
			container.itemIds[slotIndex] = nil
			return true
		end
	end
	return false
end

local function findItemIndex(container: Container, itemId: string): number?
	for slotIndex = 1, container.capacity do
		if container.itemIds[slotIndex] == itemId then
			return slotIndex
		end
	end

	return nil
end

local function containerHasItem(container: Container, itemId: string): boolean
	return findItemIndex(container, itemId) ~= nil
end

local function canAddToContainer(container: Container): boolean
    return countContainerItems(container) < container.capacity
end

local function getContainerByName(state: InventoryState, containerName: string): Container?
	if containerName == "rig" or containerName == "Rig" then
		return state.rig
	end

	if containerName == "backpack" or containerName == "Backpack" then
		return state.backpack
	end

	return nil
end

local function normalizeWeaponSlotName(containerName: string): SlotName?
	if containerName == "PrimaryA" then
		return "PrimaryA"
	end
	if containerName == "PrimaryB" then
		return "PrimaryB"
	end
	if containerName == "Pistol" then
		return "Pistol"
	end
	if containerName == "Melee" then
		return "Melee"
	end

	return nil
end

local function weaponSlotAcceptsItem(slotName: SlotName, item: Item): boolean
	if (slotName == "PrimaryA" or slotName == "PrimaryB") and item.category == "gun" then
		return true
	end
	if slotName == "Pistol" and item.category == "pistol" then
		return true
	end
	if slotName == "Melee" and item.category == "melee" then
		return true
	end

	return false
end

local function resolveOpenWeaponSlotName(state: InventoryState, item: Item): SlotName?
	if item.category == "gun" then
		if state.weaponSlots.PrimaryA == nil then
			return "PrimaryA"
		end
		if state.weaponSlots.PrimaryB == nil then
			return "PrimaryB"
		end
	end

	if item.category == "pistol" and state.weaponSlots.Pistol == nil then
		return "Pistol"
	end

	if item.category == "melee" and state.weaponSlots.Melee == nil then
		return "Melee"
	end

	return nil
end

local function containerAcceptsItem(containerName: string, item: Item): boolean
	if containerName == "backpack" or containerName == "Backpack" then
		return true
	end

	if containerName == "rig" or containerName == "Rig" then
		return item.category == "mag" or item.category == "med"
	end

	local slotName = normalizeWeaponSlotName(containerName)
	if slotName then
		return weaponSlotAcceptsItem(slotName, item)
	end

	return false
end

local function getOrCreateState(player: Player): InventoryState
    local existing = InventoryAuthority.getState(player.UserId)
    if existing then
        return existing
    end

	local joinData = player:GetJoinData()
	local teleportData = joinData.TeleportData
	if typeof(teleportData) == "table" and typeof(teleportData.inventorySnapshotsByUserId) == "table" then
		local transferredSnapshot = teleportData.inventorySnapshotsByUserId[tostring(player.UserId)]
		local restoredState = restoreStateFromSnapshot(transferredSnapshot)
		if restoredState then
			InventoryAuthority.setState(player.UserId, restoredState)
			return restoredState
		end
	end

    local itemsById: {[string]: Item} = {
        gun_primary_1 = {
            itemId = "gun_primary_1",
            templateId = "rifle_m4",
            category = "gun",
            locationState = if PlaceConfig.isLobbyPlace() then "stashed" else "inRaid",
            acceptedMagTemplateIds = { "mag_556_30" },
            attachedMagId = nil,
        },
        knife_1 = {
            itemId = "knife_1",
            templateId = "knife",
            category = "melee",
            locationState = if PlaceConfig.isLobbyPlace() then "stashed" else "inRaid",
        },
    }

    local state: InventoryState = {
        version = 0,
        equippedSlot = "PrimaryA",
        weaponSlots = {
            PrimaryA = "gun_primary_1",
            PrimaryB = nil,
            Pistol = nil,
            Melee = "knife_1",
        },
        rig = {
            capacity = 8,
            itemIds = {},
        },
        backpack = {
            capacity = 12,
            itemIds = {},
        },
        quickBinds = {},
        itemsById = itemsById,
        isReloading = false,
        lastCheckMag = nil,
        cooldowns = {},
        lastCheckMagSeq = 0,
        nextItemId = 1,
    }

    InventoryAuthority.setState(player.UserId, state)
    return state
end

local function syncLobbyInventoryState(player: Player): InventoryState
	local state = getOrCreateState(player)
	if not PlaceConfig.isLobbyPlace() or LobbySessionService == nil then
		return state
	end

	local lobbySnapshot = LobbySessionService.getInventorySnapshot(player.UserId)
	local restoredState = restoreStateFromSnapshot(lobbySnapshot)
	if restoredState then
		InventoryAuthority.setState(player.UserId, restoredState)
		return restoredState
	end

	return state
end

local function makeItemId(state: InventoryState, templateId: string): string
	local itemId = string.format("%s_%d", templateId, state.nextItemId)
	state.nextItemId += 1
	return itemId
end

local applyLootModelStateToItem: (lootModel: Model, item: Item) -> ()

local function createItemFromTemplate(state: InventoryState, templateId: string): Item?
	local definition = LootDefinitions.get(templateId)
	if not definition then
		return nil
	end

	return {
		itemId = makeItemId(state, templateId),
		templateId = templateId,
		category = definition.category,
		locationState = if PlaceConfig.isLobbyPlace() then "stashed" else "inRaid",
		stack = definition.stack,
		ammo = definition.ammo,
		capacity = definition.capacity,
		usesRemaining = definition.usesRemaining,
		usesMax = definition.usesMax,
	}
end

local function serializeAcceptedMagTemplateIds(item: Item): string?
	if item.acceptedMagTemplateIds and #item.acceptedMagTemplateIds > 0 then
		return table.concat(item.acceptedMagTemplateIds, ",")
	end

	return nil
end

local function parseAcceptedMagTemplateIds(rawValue: any): {string}?
	if typeof(rawValue) ~= "string" or rawValue == "" then
		return nil
	end

	local values = {}
	for value in string.gmatch(rawValue, "([^,]+)") do
		table.insert(values, value)
	end

	if #values == 0 then
		return nil
	end

	return values
end

local function createItemFromDroppedLootModel(state: InventoryState, lootModel: Model): Item?
	local templateId = lootModel:GetAttribute("TemplateId")
	if typeof(templateId) ~= "string" then
		return nil
	end

	local item = createItemFromTemplate(state, templateId)
	if item then
		applyLootModelStateToItem(lootModel, item)
		return item
	end

	local category = lootModel:GetAttribute("Category")
	if typeof(category) ~= "string" then
		return nil
	end

	return {
		itemId = makeItemId(state, templateId),
		templateId = templateId,
		category = category,
		locationState = if PlaceConfig.isLobbyPlace() then "stashed" else "inRaid",
		stack = if typeof(lootModel:GetAttribute("Stack")) == "number" then lootModel:GetAttribute("Stack") else nil,
		ammo = if typeof(lootModel:GetAttribute("Ammo")) == "number" then lootModel:GetAttribute("Ammo") else nil,
		capacity = if typeof(lootModel:GetAttribute("Capacity")) == "number" then lootModel:GetAttribute("Capacity") else nil,
		usesRemaining = if typeof(lootModel:GetAttribute("UsesRemaining")) == "number" then lootModel:GetAttribute("UsesRemaining") else nil,
		usesMax = if typeof(lootModel:GetAttribute("UsesMax")) == "number" then lootModel:GetAttribute("UsesMax") else nil,
		acceptedMagTemplateIds = parseAcceptedMagTemplateIds(lootModel:GetAttribute("AcceptedMagTemplateIds")),
	}
end

applyLootModelStateToItem = function(lootModel: Model, item: Item)
	local usesRemaining = lootModel:GetAttribute("UsesRemaining")
	if typeof(usesRemaining) == "number" then
		item.usesRemaining = usesRemaining
	end

	local usesMax = lootModel:GetAttribute("UsesMax")
	if typeof(usesMax) == "number" then
		item.usesMax = usesMax
	end

	local ammo = lootModel:GetAttribute("Ammo")
	if typeof(ammo) == "number" then
		item.ammo = ammo
	end

	local capacity = lootModel:GetAttribute("Capacity")
	if typeof(capacity) == "number" then
		item.capacity = capacity
	end
end

local function applyItemStateToLootModel(droppedModel: Model, item: Item)
	droppedModel:SetAttribute("Category", item.category)
	if item.stack ~= nil then
		droppedModel:SetAttribute("Stack", item.stack)
	end
	if item.usesRemaining ~= nil then
		droppedModel:SetAttribute("UsesRemaining", item.usesRemaining)
	end
	if item.usesMax ~= nil then
		droppedModel:SetAttribute("UsesMax", item.usesMax)
	end
	if item.ammo ~= nil then
		droppedModel:SetAttribute("Ammo", item.ammo)
	end
	if item.capacity ~= nil then
		droppedModel:SetAttribute("Capacity", item.capacity)
	end
	local acceptedMagTemplateIds = serializeAcceptedMagTemplateIds(item)
	if acceptedMagTemplateIds then
		droppedModel:SetAttribute("AcceptedMagTemplateIds", acceptedMagTemplateIds)
	end
end

local function addItemToContainer(state: InventoryState, container: Container, item: Item): boolean
	local slotIndex = getFirstEmptySlot(container)
	if not slotIndex then
		return false
	end

	state.itemsById[item.itemId] = item
	container.itemIds[slotIndex] = item.itemId
	return true
end

local function addItemByCategoryPriority(state: InventoryState, item: Item): boolean
	if item.category == "mag" or item.category == "ammo" or item.category == "med" then
		return addItemToContainer(state, state.rig, item)
			or addItemToContainer(state, state.backpack, item)
	end

	return addItemToContainer(state, state.backpack, item)
		or addItemToContainer(state, state.rig, item)
end

local function getLootHandle(lootModel: Model): BasePart?
	local handle = lootModel:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle
	end

	local primary = lootModel.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary
	end

	return nil
end

local function getLootSpawnsRoot(): Instance?
	local maps = Workspace:FindFirstChild("Maps")
	if not maps then
		return nil
	end

	local level0 = maps:FindFirstChild("Level0")
	if not level0 then
		return nil
	end

	local gameplay = level0:FindFirstChild("Gameplay")
	if not gameplay then
		return nil
	end

	local loot = gameplay:FindFirstChild("Loot")
	if not loot then
		return nil
	end

	return loot:FindFirstChild("LootSpawns")
end

local function isRecognizedLootRoot(instance: Instance): boolean
	local lootSpawnsRoot = getLootSpawnsRoot()
	if lootSpawnsRoot and instance:IsDescendantOf(lootSpawnsRoot) then
		return true
	end

	local droppedLootFolder = Workspace:FindFirstChild("DroppedLoot")
	if droppedLootFolder and instance:IsDescendantOf(droppedLootFolder) then
		return true
	end

	return false
end

local function getLootModelFromInstance(lootInstance: Instance): Model?
	if lootInstance:IsA("Model") then
		return lootInstance
	end

	local parent = lootInstance.Parent
	if parent and parent:IsA("Model") then
		return parent
	end

	return lootInstance:FindFirstAncestorOfClass("Model")
end

local function isLootModelValid(player: Player, lootInstance: Instance): (boolean, Model?)
	if not isRecognizedLootRoot(lootInstance) then
		return false, nil
	end

	local lootModel = getLootModelFromInstance(lootInstance)
	if not lootModel then
		return false, nil
	end

	if not lootModel:IsA("Model") then
		return false, nil
	end

	if not lootModel:IsDescendantOf(Workspace) then
		return false, nil
	end

	if lootedSet[lootModel] or lootModel:GetAttribute("PickedUp") == true then
		return false, nil
	end

	local templateId = lootModel:GetAttribute("TemplateId")
	if typeof(templateId) ~= "string" or not LootDefinitions.get(templateId) then
		return false, nil
	end

	local character = player.Character
	if not character then
		return false, nil
	end

	local root = getRoot(character)
	local handle = getLootHandle(lootModel)
	if not root or not handle then
		return false, nil
	end

	return (handle.Position - root.Position).Magnitude <= PICKUP_DISTANCE, lootModel
end

local function getEquippedGun(state: InventoryState): Item?
    local slot = state.equippedSlot
    if not slot then return nil end
    local itemId = state.weaponSlots[slot]
    if not itemId then return nil end

    local item = state.itemsById[itemId]
    if not item then return nil end
    if item.category == "gun" or item.category == "pistol" then
        return item
    end
    return nil
end

local function magReadText(ammo: number, capacity: number): string
    if capacity <= 0 then return "Unknown" end

    local ratio = ammo / capacity
    if ratio >= 1 then
        return "Full"
    elseif ratio > 0.85 then
        return "Almost Full"
    elseif ratio > 0.5 then
        return "More than Half"
    elseif ratio == 0.5 then
        return "Half"
    elseif ratio > 0.15 then
        return "Less than Half"
    elseif ratio > 0 then
        return "Almost Empty"
    else
        return "Empty"
    end
end

local function isCompatibleMag(gun: Item, mag: Item): boolean
    if mag.category ~= "mag" then return false end
    local accepted = gun.acceptedMagTemplateIds
    if not accepted then return false end
    for _, templateId in ipairs(accepted) do
        if templateId == mag.templateId then
            return true
        end
    end
    return false
end

local function handleEquipSlot(player: Player, state: InventoryState, payload: {[string]: any})
	if not (PlaceConfig.isLobbyPlace() or canUseRaidGameplay(player)) then
		return
	end

    if isRateLimited(state, "equip", EQUIP_COOLDOWN) then return end

    local slot = payload.slot
    if slot ~= "PrimaryA" and slot ~= "PrimaryB" and slot ~= "Pistol" and slot ~= "Melee" then
        return
    end

    local itemId = state.weaponSlots[slot]
    if not itemId then
        state.equippedSlot = nil
        sendSnapshot(player, state)
        return
    end

    local item = state.itemsById[itemId]
    if not item then return end

    local valid = false
    if (slot == "PrimaryA" or slot == "PrimaryB") and item.category == "gun" then valid = true end
    if slot == "Pistol" and item.category == "pistol" then valid = true end
    if slot == "Melee" and item.category == "melee" then valid = true end

    if not valid then return end

    state.equippedSlot = slot :: SlotName
    sendSnapshot(player, state)
end

local function handleFire(player: Player, state: InventoryState, payload: {[string]: any})
    if not canUseRaidGameplay(player) then return end
    if isRateLimited(state, "fire", FIRE_COOLDOWN) then return end
    if state.isReloading then return end
    if not isAliveCharacter(player.Character) then return end

    local origin = payload.origin
    local direction = payload.direction
    if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
        return
    end
    if direction.Magnitude < 0.9 or direction.Magnitude > 1.1 then
        return
    end

    local gun = getEquippedGun(state)
    if not gun then return end
    local magId = gun.attachedMagId
    if not magId then return end

    local mag = state.itemsById[magId]
    if not mag or mag.category ~= "mag" then return end
    local ammo = mag.ammo or 0
    if ammo <= 0 then
        sendSnapshot(player, state)
        return
    end

    local character = player.Character :: Model
    local root = getRoot(character)
    if not root then return end
    if (origin - root.Position).Magnitude > 10 then
        origin = root.Position
    end

    mag.ammo = ammo - 1
    sendSnapshot(player, state)

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character }
    params.IgnoreWater = true

    local result = workspace:Raycast(origin, direction * MAX_DISTANCE, params)
    if not result then return end

    local model = result.Instance:FindFirstAncestorOfClass("Model")
    if not model then return end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
		local targetPlayer = Players:GetPlayerFromCharacter(model)
		if targetPlayer and not RaidAuthority.isInRaid(targetPlayer.UserId) then
			return
		end

		humanoid:SetAttribute("LastDamagedByUserId", player.UserId)
        humanoid:TakeDamage(DAMAGE)
    end
end

local function findReloadCandidate(state: InventoryState, gun: Item): (string?, string?)
	for slotIndex = 1, state.rig.capacity do
		local itemId = state.rig.itemIds[slotIndex]
		local item = itemId and state.itemsById[itemId] or nil
		if item and item.category == "mag" and isCompatibleMag(gun, item) and (item.ammo or 0) > 0 then
			if gun.attachedMagId ~= itemId then
				return itemId, "rig"
			end
		end
	end

    warn("[InventoryService] Reload failed: no compatible loaded magazine in rig")
    return nil, nil
end

local function handleReload(player: Player, state: InventoryState)
    if not canUseRaidGameplay(player) then return end
    if isRateLimited(state, "reload", RELOAD_COOLDOWN) then return end
    if state.isReloading then return end
    if not isAliveCharacter(player.Character) then return end

    local gun = getEquippedGun(state)
    if not gun then return end

    local newMagId, srcName = findReloadCandidate(state, gun)
    if not newMagId or not srcName then
        return
    end

    state.isReloading = true
    state.lastCheckMag = nil
    sendSnapshot(player, state)

    task.delay(RELOAD_SECONDS, function()
        local current = InventoryAuthority.getState(player.UserId)
        if not current then return end
        if not player.Parent then return end

        local currentGun = getEquippedGun(current)
        if not currentGun then
            current.isReloading = false
            sendSnapshot(player, current)
            return
        end

        local srcContainer = if srcName == "rig" then current.rig else current.backpack
        if not removeFromContainer(srcContainer, newMagId) then
            current.isReloading = false
            sendSnapshot(player, current)
            return
        end

        local oldMagId = currentGun.attachedMagId
        if oldMagId then
            if addItemToContainer(current, srcContainer, current.itemsById[oldMagId]) then
                -- placed old mag back into the source container
            elseif addItemToContainer(current, current.rig, current.itemsById[oldMagId]) then
                -- fallback rig slot
            elseif addItemToContainer(current, current.backpack, current.itemsById[oldMagId]) then
                -- fallback backpack slot
            else
                addItemToContainer(current, srcContainer, current.itemsById[newMagId])
                current.isReloading = false
                sendSnapshot(player, current)
                return
            end
        end

        currentGun.attachedMagId = newMagId
        current.isReloading = false
        sendSnapshot(player, current)
    end)
end

local function handleCheckMag(player: Player, state: InventoryState)
    if not canUseRaidGameplay(player) then return end
    if isRateLimited(state, "checkMag", CHECK_MAG_COOLDOWN) then return end
    if state.isReloading then return end
    if not isAliveCharacter(player.Character) then return end

    task.delay(CHECK_MAG_SECONDS, function()
        local current = InventoryAuthority.getState(player.UserId)
        if not current then return end
        if not player.Parent then return end

        local gun = getEquippedGun(current)
        if not gun then return end
        local magId = gun.attachedMagId
        if not magId then return end
        local mag = current.itemsById[magId]
        if not mag then return end

        local ammo = mag.ammo or 0
        local cap = mag.capacity or 0
        current.lastCheckMag = magReadText(ammo, cap)
        current.lastCheckMagSeq += 1
        sendSnapshot(player, current)
    end)
end

local function getPrimaryGun(state: InventoryState): Item?
	local itemId = state.weaponSlots.PrimaryA
	if not itemId then
		return nil
	end

	local item = state.itemsById[itemId]
	if item and (item.category == "gun" or item.category == "pistol") then
		return item
	end

	return nil
end

local function getLoadTargetGun(state: InventoryState): Item?
	return getEquippedGun(state) or getPrimaryGun(state)
end

local function getItemContainerName(state: InventoryState, itemId: string): string?
	if containerHasItem(state.rig, itemId) then
		return "rig"
	end

	if containerHasItem(state.backpack, itemId) then
		return "backpack"
	end

	return nil
end

local function getItemWeaponSlot(state: InventoryState, itemId: string): SlotName?
	for slotName, slotItemId in pairs(state.weaponSlots) do
		if slotItemId == itemId then
			return slotName :: SlotName
		end
	end

	return nil
end

local function removeItemCompletely(state: InventoryState, itemId: string): boolean
	if removeFromContainer(state.rig, itemId) then
		state.itemsById[itemId] = nil
		return true
	end

	if removeFromContainer(state.backpack, itemId) then
		state.itemsById[itemId] = nil
		return true
	end

	local slotName = getItemWeaponSlot(state, itemId)
	if slotName then
		state.weaponSlots[slotName] = nil
		if state.equippedSlot == slotName then
			state.equippedSlot = nil
		end
		state.itemsById[itemId] = nil
		return true
	end

	return false
end

local function handleUseKeycard(player: Player, state: InventoryState, payload: {[string]: any})
	if not canUseRaidGameplay(player) then
		return
	end

	if isRateLimited(state, "useKeycard", 0.15) then
		return
	end

	local itemId = payload.itemId
	if typeof(itemId) ~= "string" then
		return
	end

	local item = state.itemsById[itemId]
	if not item or item.category ~= "keycard" then
		return
	end

	local usesRemaining = item.usesRemaining
	if typeof(usesRemaining) ~= "number" or usesRemaining <= 0 then
		return
	end

	item.usesRemaining = usesRemaining - 1
	sendSnapshot(player, state)
end

local function resolveMoveDestinationIndex(container: Container, toIndex: number?): number?
	if toIndex ~= nil then
		local requestedIndex = math.floor(toIndex)
		if requestedIndex < 1 or requestedIndex > container.capacity then
			return nil
		end

		if container.itemIds[requestedIndex] ~= nil then
			return nil
		end

		return requestedIndex
	end

	for slotIndex = 1, container.capacity do
		if container.itemIds[slotIndex] == nil then
			return slotIndex
		end
	end

	return nil
end

local function loadMagazineIntoGun(state: InventoryState, gun: Item, magItem: Item): boolean
	local sourceContainerName = getItemContainerName(state, magItem.itemId)
	if sourceContainerName ~= "rig" then
		warn("[InventoryService] Load failed: magazine is not in rig")
		return false
	end

	if not isCompatibleMag(gun, magItem) then
		return false
	end

	local rigIndex = findItemIndex(state.rig, magItem.itemId)
	if not rigIndex then
		return false
	end

	state.rig.itemIds[rigIndex] = nil

	local previousMagId = gun.attachedMagId
	if previousMagId then
		state.rig.itemIds[rigIndex] = previousMagId
	end

	gun.attachedMagId = magItem.itemId
	return true
end

local function handleMoveItem(player: Player, state: InventoryState, payload: {[string]: any})
	if isRateLimited(state, "moveItem", 0.05) then
		return
	end

	local itemId = payload.itemId
	local fromContainerName = payload.fromContainer
	local toContainerName = payload.toContainer
	local toIndex = payload.toIndex

	if typeof(itemId) ~= "string" then
		return
	end

	if typeof(fromContainerName) ~= "string" or typeof(toContainerName) ~= "string" then
		return
	end

	if toIndex ~= nil and typeof(toIndex) ~= "number" then
		return
	end

	local item = state.itemsById[itemId]
	if not item then
		return
	end

	local fromSlotName = normalizeWeaponSlotName(fromContainerName)
	local toSlotName = normalizeWeaponSlotName(toContainerName)
	local fromContainer = if fromSlotName then nil else getContainerByName(state, fromContainerName)
	local toContainer = if toSlotName or toContainerName == "OpenWeaponSlot" then nil else getContainerByName(state, toContainerName)

	local fromIndex: number? = nil
	if fromSlotName then
		if state.weaponSlots[fromSlotName] ~= itemId then
			return
		end
	else
		if not fromContainer then
			return
		end

		fromIndex = findItemIndex(fromContainer, itemId)
		if not fromIndex then
			return
		end
	end

	if toContainerName == "OpenWeaponSlot" then
		toSlotName = resolveOpenWeaponSlotName(state, item)
		if not toSlotName then
			return
		end
	end

	if toSlotName then
		if not weaponSlotAcceptsItem(toSlotName, item) then
			return
		end

		if state.weaponSlots[toSlotName] ~= nil then
			return
		end

		if fromSlotName == toSlotName then
			return
		end

		if fromSlotName then
			state.weaponSlots[fromSlotName] = nil
			if state.equippedSlot == fromSlotName then
				state.equippedSlot = nil
			end
		elseif fromContainer and fromIndex then
			fromContainer.itemIds[fromIndex] = nil
		else
			return
		end

		state.weaponSlots[toSlotName] = itemId
		sendSnapshot(player, state)
		return
	end

	if not toContainer then
		return
	end

	if fromContainer and fromContainer == toContainer then
		if not fromIndex then
			return
		end

		local originalItemId = fromContainer.itemIds[fromIndex]
		fromContainer.itemIds[fromIndex] = nil
		local sameContainerDestinationIndex = resolveMoveDestinationIndex(toContainer, toIndex)
		if not sameContainerDestinationIndex then
			fromContainer.itemIds[fromIndex] = originalItemId
			return
		end

		if sameContainerDestinationIndex == fromIndex then
			fromContainer.itemIds[fromIndex] = originalItemId
			return
		end

		toContainer.itemIds[sameContainerDestinationIndex] = itemId
		sendSnapshot(player, state)
		return
	end

	if not containerAcceptsItem(toContainerName, item) then
		return
	end

	if not canAddToContainer(toContainer) then
		return
	end

	local destinationIndex = resolveMoveDestinationIndex(toContainer, toIndex)
	if not destinationIndex then
		return
	end

	if fromSlotName then
		state.weaponSlots[fromSlotName] = nil
		if state.equippedSlot == fromSlotName then
			state.equippedSlot = nil
		end
	elseif fromContainer and fromIndex then
		fromContainer.itemIds[fromIndex] = nil
	else
		return
	end

	toContainer.itemIds[destinationIndex] = itemId
	sendSnapshot(player, state)
end

local function createGenericDroppedLootModel(templateId: string, item: Item): Model
	local model = Instance.new("Model")
	model.Name = "Dropped_" .. templateId

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1.2, 1.2, 1.2)
	handle.Shape = Enum.PartType.Block
	handle.Material = Enum.Material.Metal
	handle.Color = Color3.fromRGB(92, 92, 92)
	handle.CanCollide = true
	handle.CanTouch = true
	handle.CanQuery = true
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(160, 36)
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = handle

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 225, 130)
	label.TextStrokeTransparency = 0.6
	label.Text = LootDefinitions.getDisplayName(item.templateId)
	label.Parent = billboard

	model.PrimaryPart = handle
	return model
end

local function createDroppedLootModel(templateId: string, item: Item): Model?
	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
	if not sharedFolder then
		return createGenericDroppedLootModel(templateId, item)
	end

	local lootPrefabs = sharedFolder:FindFirstChild("LootPrefabs")
	if not lootPrefabs then
		warn("[InventoryService] Drop failed: ReplicatedStorage.Shared.LootPrefabs is missing")
		return createGenericDroppedLootModel(templateId, item)
	end

	local prefab = lootPrefabs:FindFirstChild(templateId)
	if not prefab then
		local definition = LootDefinitions.get(templateId)
		if definition and definition.prefabName then
			prefab = lootPrefabs:FindFirstChild(definition.prefabName)
		end
	end

	if not prefab then
		for _, child in ipairs(lootPrefabs:GetChildren()) do
			if child:IsA("Model") and child:GetAttribute("TemplateId") == templateId then
				prefab = child
				break
			end
		end
	end

	if not prefab or not prefab:IsA("Model") then
		return createGenericDroppedLootModel(templateId, item)
	end

	return prefab:Clone()
end

local function prepareDroppedLootModel(droppedModel: Model): BasePart?
	local handle = getLootHandle(droppedModel)
	if not handle then
		return nil
	end

	if not droppedModel.PrimaryPart then
		droppedModel.PrimaryPart = handle
	end

	for _, descendant in ipairs(droppedModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant ~= handle then
				local hasWeld = false
				for _, child in ipairs(descendant:GetChildren()) do
					if child:IsA("WeldConstraint") and ((child.Part0 == handle and child.Part1 == descendant) or (child.Part1 == handle and child.Part0 == descendant)) then
						hasWeld = true
						break
					end
				end

				if not hasWeld then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = handle
					weld.Part1 = descendant
					weld.Parent = handle
				end
			end

			descendant.Anchored = false
		end
	end

	return handle
end

local function getDroppedLootFolder(): Folder
	local existing = Workspace:FindFirstChild("DroppedLoot")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "DroppedLoot"
	folder.Parent = Workspace
	return folder
end

local function placeDroppedLoot(player: Player, item: Item)
	local droppedModel = createDroppedLootModel(item.templateId, item)
	if not droppedModel then
		return false
	end

	local character = player.Character
	local root = character and getRoot(character)
	if not root then
		return false
	end

	local dropCFrame = root.CFrame * CFrame.new(0, 1, -3)
	droppedModel:SetAttribute("TemplateId", item.templateId)
	droppedModel:SetAttribute("WorldItemId", string.format("%s_drop_%d", item.templateId, math.floor(os.clock() * 1000)))
	applyItemStateToLootModel(droppedModel, item)

	local handle = prepareDroppedLootModel(droppedModel)
	if not handle then
		warn(string.format("[InventoryService] Drop failed: prefab %s has no Handle or PrimaryPart", item.templateId))
		droppedModel:Destroy()
		return false
	end

	droppedModel.Parent = getDroppedLootFolder()
	droppedModel:PivotTo(dropCFrame)
	return true
end

local function handleDropItem(player: Player, state: InventoryState, itemId: string)
	if not canUseRaidGameplay(player) then
		return
	end

	if isRateLimited(state, "dropItem", 0.1) then
		return
	end

	if typeof(itemId) ~= "string" then
		return
	end

	local item = state.itemsById[itemId]
	if not item then
		return
	end

	if not placeDroppedLoot(player, item) then
		return
	end

	if removeItemCompletely(state, itemId) then
		sendSnapshot(player, state)
	end
end

local function handleItemAction(player: Player, state: InventoryState, itemId: string, actionType: string)
	if not (PlaceConfig.isLobbyPlace() or canUseRaidGameplay(player)) then
		return
	end

	if isRateLimited(state, "itemAction", 0.1) then
		return
	end

	local item = state.itemsById[itemId]
	if not item then
		return
	end

	if actionType == "Load" then
		if item.category ~= "mag" then
			return
		end

		local gun = getLoadTargetGun(state)
		if not gun then
			return
		end

		if loadMagazineIntoGun(state, gun, item) then
			sendSnapshot(player, state)
		end
		return
	end

	if actionType ~= "Use" then
		return
	end

	if item.category == "med" then
		if PlaceConfig.isLobbyPlace() then
			return
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 30)
		if removeItemCompletely(state, itemId) then
			sendSnapshot(player, state)
		end
		return
	end

	if item.category == "gun" or item.category == "pistol" or item.category == "melee" then
		local slotName = getItemWeaponSlot(state, itemId)
		if not slotName then
			return
		end
		state.equippedSlot = slotName
		sendSnapshot(player, state)
	end
end

local function handlePickupLoot(player: Player, state: InventoryState, lootInstance: Instance)
	if not canUseRaidGameplay(player) then return end
	if isRateLimited(state, "pickup", PICKUP_COOLDOWN) then return end
	if not isAliveCharacter(player.Character) then return end

	if typeof(lootInstance) ~= "Instance" then
		return
	end

	local isValid, lootModel = isLootModelValid(player, lootInstance)
	if not isValid or not lootModel then
		return
	end

	lootedSet[lootModel] = true
	lootModel:SetAttribute("PickedUp", true)

	local templateId = lootModel:GetAttribute("TemplateId")
	if typeof(templateId) ~= "string" then
		lootedSet[lootModel] = nil
		lootModel:SetAttribute("PickedUp", false)
		return
	end

	local item = createItemFromDroppedLootModel(state, lootModel)
	if not item then
		lootedSet[lootModel] = nil
		lootModel:SetAttribute("PickedUp", false)
		return
	end

	if not addItemByCategoryPriority(state, item) then
		lootedSet[lootModel] = nil
		lootModel:SetAttribute("PickedUp", false)
		return
	end

	lootModel:Destroy()
	sendSnapshot(player, state)
end

actionEvent.OnServerEvent:Connect(function(player: Player, payload: any)
    if typeof(payload) ~= "table" then return end

    local state = getOrCreateState(player)
    local kind = payload.kind
    if typeof(kind) ~= "string" then return end

    if kind == "EquipSlot" then
        handleEquipSlot(player, state, payload)
    elseif kind == "Fire" then
        handleFire(player, state, payload)
    elseif kind == "Reload" then
        handleReload(player, state)
    elseif kind == "CheckMag" then
        handleCheckMag(player, state)
    elseif kind == "UseKeycard" then
        handleUseKeycard(player, state, payload)
    elseif kind == "BindQuick" then
        -- milestone A stub
    end
end)

pickupEvent.OnServerEvent:Connect(function(player: Player, lootInstance: any)
	local state = getOrCreateState(player)
	handlePickupLoot(player, state, lootInstance)
end)

moveItemEvent.OnServerEvent:Connect(function(player: Player, itemId: any, fromContainer: any, toContainer: any, toIndex: any)
	local state = getOrCreateState(player)
	handleMoveItem(player, state, {
		itemId = itemId,
		fromContainer = fromContainer,
		toContainer = toContainer,
		toIndex = toIndex,
	})
end)

dropItemEvent.OnServerEvent:Connect(function(player: Player, itemId: any)
	local state = getOrCreateState(player)
	handleDropItem(player, state, itemId)
end)

itemActionEvent.OnServerEvent:Connect(function(player: Player, itemId: any, actionType: any)
	if typeof(itemId) ~= "string" or typeof(actionType) ~= "string" then
		return
	end

	local state = getOrCreateState(player)
	handleItemAction(player, state, itemId, actionType)
end)

local function setupPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		local currentState = syncLobbyInventoryState(player)
		currentState.isReloading = false
		sendSnapshot(player, currentState)
	end)
	sendSnapshot(player, syncLobbyInventoryState(player))

	if PlaceConfig.isLobbyPlace() then
		player:GetAttributeChangedSignal("LobbyInventorySyncNonce"):Connect(function()
			local nextState = syncLobbyInventoryState(player)
			sendSnapshot(player, nextState)
		end)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

Players.PlayerAdded:Connect(function(player)
	setupPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
    InventoryAuthority.removeState(player.UserId)
end)
