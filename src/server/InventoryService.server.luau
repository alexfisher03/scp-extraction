--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local LootDefinitions = require(ReplicatedStorage.Shared.LootDefinitions)
local InventoryAuthority = require(script.Parent.inventory.InventoryAuthority)
local RaidAuthority = require(script.Parent.raid.RaidAuthority)

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

local function sendSnapshot(player: Player, state: InventoryState)
    state.version += 1
    snapshotEvent:FireClient(player, toSnapshot(state))
end

InventoryAuthority.setSnapshotEmitter(sendSnapshot)

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

local function containerAcceptsItem(containerName: string, item: Item): boolean
	if containerName == "backpack" or containerName == "Backpack" then
		return true
	end

	if containerName == "rig" or containerName == "Rig" then
		return item.category == "mag" or item.category == "med"
	end

	return false
end

local function getOrCreateState(player: Player): InventoryState
    local existing = InventoryAuthority.getState(player.UserId)
    if existing then
        return existing
    end

    local itemsById: {[string]: Item} = {
        gun_primary_1 = {
            itemId = "gun_primary_1",
            templateId = "rifle_m4",
            category = "gun",
            locationState = "inRaid",
            acceptedMagTemplateIds = { "mag_556_30" },
            attachedMagId = nil,
        },
        knife_1 = {
            itemId = "knife_1",
            templateId = "knife",
            category = "melee",
            locationState = "inRaid",
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

local function makeItemId(state: InventoryState, templateId: string): string
	local itemId = string.format("%s_%d", templateId, state.nextItemId)
	state.nextItemId += 1
	return itemId
end

local function createItemFromTemplate(state: InventoryState, templateId: string): Item?
	local definition = LootDefinitions.get(templateId)
	if not definition then
		return nil
	end

	return {
		itemId = makeItemId(state, templateId),
		templateId = templateId,
		category = definition.category,
		locationState = "inRaid",
		stack = definition.stack,
		ammo = definition.ammo,
		capacity = definition.capacity,
		usesRemaining = definition.usesRemaining,
		usesMax = definition.usesMax,
	}
end

local function applyLootModelStateToItem(lootModel: Model, item: Item)
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
	if not RaidAuthority.isInRaid(player.UserId) then
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
    if not RaidAuthority.isInRaid(player.UserId) then return end
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
    if not RaidAuthority.isInRaid(player.UserId) then return end
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
    if not RaidAuthority.isInRaid(player.UserId) then return end
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
	if not RaidAuthority.isInRaid(player.UserId) then
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

	local fromContainer = getContainerByName(state, fromContainerName)
	local toContainer = getContainerByName(state, toContainerName)
	if not fromContainer or not toContainer then
		return
	end

	local fromIndex = findItemIndex(fromContainer, itemId)
	if not fromIndex then
		return
	end

	if fromContainer == toContainer then
		local originalItemId = fromContainer.itemIds[fromIndex]
		fromContainer.itemIds[fromIndex] = nil
		local destinationIndex = resolveMoveDestinationIndex(toContainer, toIndex)
		if not destinationIndex then
			fromContainer.itemIds[fromIndex] = originalItemId
			return
		end

		if destinationIndex == fromIndex then
			fromContainer.itemIds[fromIndex] = originalItemId
			return
		end

		toContainer.itemIds[destinationIndex] = itemId
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

	fromContainer.itemIds[fromIndex] = nil
	toContainer.itemIds[destinationIndex] = itemId
	sendSnapshot(player, state)
end

local function createDroppedLootModel(templateId: string): Model?
	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
	if not sharedFolder then
		return nil
	end

	local lootPrefabs = sharedFolder:FindFirstChild("LootPrefabs")
	if not lootPrefabs then
		warn("[InventoryService] Drop failed: ReplicatedStorage.Shared.LootPrefabs is missing")
		return nil
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
		warn(string.format("[InventoryService] Drop failed: missing loot prefab for %s", templateId))
		return nil
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
	local droppedModel = createDroppedLootModel(item.templateId)
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
	if not RaidAuthority.isInRaid(player.UserId) then
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
	if not RaidAuthority.isInRaid(player.UserId) then
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
	if not RaidAuthority.isInRaid(player.UserId) then return end
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

	local item = createItemFromTemplate(state, templateId)
	if not item then
		lootedSet[lootModel] = nil
		lootModel:SetAttribute("PickedUp", false)
		return
	end

	applyLootModelStateToItem(lootModel, item)

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
	local state = getOrCreateState(player)
	player.CharacterAdded:Connect(function()
		state.isReloading = false
		sendSnapshot(player, state)
	end)
	sendSnapshot(player, state)
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
