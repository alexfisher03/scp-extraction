--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local actionEvent = remotes:WaitForChild(Net.InventoryActionEventName) :: RemoteEvent
local snapshotEvent = remotes:WaitForChild(Net.InventorySnapshotEventName) :: RemoteEvent

local MAX_DISTANCE = 300
local DAMAGE = 30

local FIRE_COOLDOWN = 0.15
local EQUIP_COOLDOWN = 0.05
local RELOAD_COOLDOWN = 0.2
local CHECK_MAG_COOLDOWN = 0.6
local RELOAD_SECONDS = 2.2
local CHECK_MAG_SECONDS = 1.0

type SlotName = "PrimaryA" | "PrimaryB" | "Pistol" | "Melee"

type Item = {
    itemId: string,
    templateId: string,
    category: string,
    stack: number?,
    ammo: number?,
    capacity: number?,
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
}

local states: {[number]: InventoryState} = {}

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

local function findItemContainer(state: InventoryState, itemId: string): string?
    if containerHasItem(state.rig, itemId) then return "rig" end
    if containerHasItem(state.backpack, itemId) then return "backpack" end
    return nil
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
            attachedMagId = "mag_556_1",
        },
        mag_556_1 = {
            itemId = "mag_556_1",
            templateId = "mag_556_30",
            category = "mag",
            ammo = 30,
            capacity = 30,
        },
        mag_556_2 = {
            itemId = "mag_556_2",
            templateId = "mag_556_30",
            category = "mag",
            ammo = 30,
            capacity = 30,
        },
        knife_1 = {
            itemId = "knife_1",
            templateId = "knife",
            category = "melee",
        },
        ifak_1 = {
            itemId = "ifak_1",
            templateId = "ifak",
            category = "med",
            stack = 1,
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
            itemIds = { "mag_556_2", "ifak_1" },
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
    }

    states[player.UserId] = state
    return state
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
    elseif kind == "BindQuick" then
        -- milestone A stub
    end
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
