--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local LootDefinitions = require(ReplicatedStorage.Shared.LootDefinitions)

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local actionEvent = remotes:WaitForChild(Net.InventoryActionEventName) :: RemoteEvent
local snapshotEvent = remotes:WaitForChild(Net.InventorySnapshotEventName) :: RemoteEvent
local pickupEvent = remotes:WaitForChild(Net.LootPickupRequestEventName) :: RemoteEvent

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
    itemIds: {string},
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

local states: {[number]: InventoryState} = {}
local lootedSet: {[Instance]: boolean} = {}

local function cloneArray<T>(arr: {T}): {T}
    local out = table.create(#arr)
    for i, v in ipairs(arr) do
        out[i] = v
    end
    return out
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
            itemIds = cloneArray(state.rig.itemIds),
        },
        backpack = {
            capacity = state.backpack.capacity,
            itemIds = cloneArray(state.backpack.itemIds),
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
    for i, id in ipairs(container.itemIds) do
        if id == itemId then
            table.remove(container.itemIds, i)
            return true
        end
    end
    return false
end

local function findItemIndex(container: Container, itemId: string): number?
	for i, id in ipairs(container.itemIds) do
		if id == itemId then
			return i
		end
	end

	return nil
end

local function containerHasItem(container: Container, itemId: string): boolean
    for _, id in ipairs(container.itemIds) do
        if id == itemId then
            return true
        end
    end
    return false
end

local function canAddToContainer(container: Container): boolean
    return #container.itemIds < container.capacity
end

local function getContainerByName(state: InventoryState, containerName: string): Container?
	if containerName == "rig" then
		return state.rig
	end

	if containerName == "backpack" then
		return state.backpack
	end

	return nil
end

local function containerAcceptsItem(containerName: string, item: Item): boolean
	if containerName == "backpack" then
		return true
	end

	if containerName == "rig" then
		return item.category == "mag" or item.category == "med"
	end

	return false
end

local function getOrCreateState(player: Player): InventoryState
    local existing = states[player.UserId]
    if existing then
        return existing
    end

    local itemsById: {[string]: Item} = {
        gun_primary_1 = {
            itemId = "gun_primary_1",
            templateId = "rifle_m4",
            category = "gun",
            acceptedMagTemplateIds = { "mag_556_30" },
            attachedMagId = nil,
        },
        knife_1 = {
            itemId = "knife_1",
            templateId = "knife",
            category = "melee",
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

    states[player.UserId] = state
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
		stack = definition.stack,
		ammo = definition.ammo,
		capacity = definition.capacity,
		usesRemaining = definition.usesRemaining,
		usesMax = definition.usesMax,
	}
end

local function addItemToContainer(state: InventoryState, container: Container, item: Item): boolean
	if not canAddToContainer(container) then
		return false
	end

	state.itemsById[item.itemId] = item
	table.insert(container.itemIds, item.itemId)
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
	local lootSpawnsRoot = getLootSpawnsRoot()
	if not lootSpawnsRoot then
		return false, nil
	end

	if not lootInstance:IsDescendantOf(lootSpawnsRoot) then
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
    for _, containerName in ipairs({ "rig", "backpack" }) do
        local container = if containerName == "rig" then state.rig else state.backpack
        for _, itemId in ipairs(container.itemIds) do
            local item = state.itemsById[itemId]
            if item and item.category == "mag" and isCompatibleMag(gun, item) and (item.ammo or 0) > 0 then
                if gun.attachedMagId ~= itemId then
                    return itemId, containerName
                end
            end
        end
    end
    return nil, nil
end

local function handleReload(player: Player, state: InventoryState)
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
        local current = states[player.UserId]
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
            if canAddToContainer(srcContainer) then
                table.insert(srcContainer.itemIds, oldMagId)
            elseif canAddToContainer(current.rig) then
                table.insert(current.rig.itemIds, oldMagId)
            elseif canAddToContainer(current.backpack) then
                table.insert(current.backpack.itemIds, oldMagId)
            else
                table.insert(srcContainer.itemIds, newMagId)
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
    if isRateLimited(state, "checkMag", CHECK_MAG_COOLDOWN) then return end
    if state.isReloading then return end
    if not isAliveCharacter(player.Character) then return end

    task.delay(CHECK_MAG_SECONDS, function()
        local current = states[player.UserId]
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

local function handleUseKeycard(player: Player, state: InventoryState, payload: {[string]: any})
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

	if typeof(toIndex) ~= "number" then
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

	local requestedIndex = math.floor(toIndex)
	if requestedIndex < 1 then
		return
	end

	if fromContainer == toContainer then
		if requestedIndex > (#toContainer.itemIds + 1) then
			return
		end

		table.remove(fromContainer.itemIds, fromIndex)

		local adjustedIndex = requestedIndex
		if requestedIndex > fromIndex then
			adjustedIndex -= 1
		end

		if adjustedIndex < 1 then
			adjustedIndex = 1
		end
		if adjustedIndex > (#toContainer.itemIds + 1) then
			adjustedIndex = #toContainer.itemIds + 1
		end

		table.insert(toContainer.itemIds, adjustedIndex, itemId)
		sendSnapshot(player, state)
		return
	end

	if not containerAcceptsItem(toContainerName, item) then
		return
	end

	if not canAddToContainer(toContainer) then
		return
	end

	if requestedIndex > (#toContainer.itemIds + 1) then
		return
	end

	table.remove(fromContainer.itemIds, fromIndex)
	table.insert(toContainer.itemIds, requestedIndex, itemId)
	sendSnapshot(player, state)
end

local function handlePickupLoot(player: Player, state: InventoryState, lootInstance: Instance)
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
    elseif kind == "MoveItem" then
        handleMoveItem(player, state, payload)
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

Players.PlayerAdded:Connect(function(player)
    local state = getOrCreateState(player)
    player.CharacterAdded:Connect(function()
        state.isReloading = false
        sendSnapshot(player, state)
    end)
    sendSnapshot(player, state)
end)

Players.PlayerRemoving:Connect(function(player)
    states[player.UserId] = nil
end)
