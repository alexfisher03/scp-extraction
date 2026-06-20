--!strict

local ItemInstance = require(script.Parent.ItemInstance)
local InventoryGrid = require(script.Parent.InventoryGrid)
local LootDefinitions = require(script.Parent.LootDefinitions)

local PlayerProfile = {}

PlayerProfile.SCHEMA_VERSION = 2
PlayerProfile.DEFAULT_RIG_CAPACITY = 8
PlayerProfile.DEFAULT_BACKPACK_CAPACITY = 20
PlayerProfile.DEFAULT_STASH_CAPACITY = 100
PlayerProfile.DEFAULT_SECURE_CONTAINER_CAPACITY = 0

local function cloneValue(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local out = {}
	for key, nested in pairs(value) do
		out[key] = cloneValue(nested)
	end
	return out
end

local function makeDefaultItems(): {[string]: any}
	return {
		gun_primary_1 = {
			itemId = "gun_primary_1",
			templateId = "rifle_m4",
			category = "gun",
			origin = "BroughtIn",
			state = {
				locationState = "stashed",
				acceptedMagTemplateIds = { "mag_556_30" },
				attachedMagId = nil,
			},
		},
		knife_1 = {
			itemId = "knife_1",
			templateId = "knife",
			category = "melee",
			origin = "BroughtIn",
			state = {
				locationState = "stashed",
			},
		},
	}
end

function PlayerProfile.createDefault(): any
	return {
		schemaVersion = PlayerProfile.SCHEMA_VERSION,
		reqCredits = 0,
		activeRaid = nil,
		stashCapacity = PlayerProfile.DEFAULT_STASH_CAPACITY,
		rigCapacity = PlayerProfile.DEFAULT_RIG_CAPACITY,
		backpackCapacity = PlayerProfile.DEFAULT_BACKPACK_CAPACITY,
		secureContainerCapacity = PlayerProfile.DEFAULT_SECURE_CONTAINER_CAPACITY,
		stash = {},
		loadout = {
			primaryA = "gun_primary_1",
			primaryB = nil,
			pistol = nil,
			melee = "knife_1",
			rig = {},
			backpack = {},
			secure = {},
		},
		items = makeDefaultItems(),
	}
end

function PlayerProfile.clone(profile: any): any
	if typeof(profile) ~= "table" then
		return nil
	end

	return cloneValue(profile)
end

local function normalizeItem(item: any): any?
	if typeof(item) ~= "table" then
		return nil
	end

	local itemId = item.itemId
	local templateId = item.templateId
	local category = item.category
	if typeof(itemId) ~= "string" or typeof(templateId) ~= "string" or typeof(category) ~= "string" then
		return nil
	end

	local persisted = ItemInstance.clone(item)
	if persisted == nil then
		return nil
	end

	persisted.origin = if persisted.origin == "Looted" then "Looted" else "BroughtIn"
	persisted.inventoryRotated = persisted.inventoryRotated == true
	if typeof(persisted.state) ~= "table" then
		persisted.state = {}
	end
	if typeof(persisted.inventorySize) ~= "table" then
		local definition = LootDefinitions.get(templateId)
		if definition and typeof(definition.inventorySize) == "table" then
			persisted.inventorySize = {
				width = definition.inventorySize.width,
				height = definition.inventorySize.height,
			}
		end
	end
	if typeof(persisted.state.acceptedMagTemplateIds) ~= "table" then
		local definition = LootDefinitions.get(templateId)
		if definition and typeof(definition.acceptedMagTemplateIds) == "table" then
			persisted.state.acceptedMagTemplateIds = cloneValue(definition.acceptedMagTemplateIds)
		end
	end
	return persisted
end

local function normalizeItemIdList(rawList: any, capacity: number, containerName: string, items: {[string]: any}): {string}
	local out = {}
	if typeof(rawList) ~= "table" then
		return out
	end

	for slotIndex = 1, capacity do
		local itemId = rawList[slotIndex]
		if typeof(itemId) == "string" and items[itemId] ~= nil then
			local destination = InventoryGrid.placeItem(out, items, capacity, containerName, items[itemId], slotIndex, nil)
				or InventoryGrid.placeItem(out, items, capacity, containerName, items[itemId], nil, nil)
			if destination then
				out[destination] = itemId
			end
		end
	end

	return out
end

function PlayerProfile.normalize(rawProfile: any): any
	local profile = PlayerProfile.createDefault()
	if typeof(rawProfile) ~= "table" then
		return profile
	end

	profile.schemaVersion = if typeof(rawProfile.schemaVersion) == "number" then rawProfile.schemaVersion else PlayerProfile.SCHEMA_VERSION
	profile.reqCredits = if typeof(rawProfile.reqCredits) == "number" then math.max(0, math.floor(rawProfile.reqCredits)) else 0
	profile.activeRaid = if typeof(rawProfile.activeRaid) == "table" then cloneValue(rawProfile.activeRaid) else nil
	profile.stashCapacity = if typeof(rawProfile.stashCapacity) == "number" then math.max(0, math.floor(rawProfile.stashCapacity)) else PlayerProfile.DEFAULT_STASH_CAPACITY
	profile.rigCapacity = if typeof(rawProfile.rigCapacity) == "number" then math.max(0, math.floor(rawProfile.rigCapacity)) else PlayerProfile.DEFAULT_RIG_CAPACITY
	profile.backpackCapacity = if typeof(rawProfile.backpackCapacity) == "number" then math.max(0, math.floor(rawProfile.backpackCapacity)) else PlayerProfile.DEFAULT_BACKPACK_CAPACITY
	profile.secureContainerCapacity = if typeof(rawProfile.secureContainerCapacity) == "number" then math.max(0, math.floor(rawProfile.secureContainerCapacity)) else PlayerProfile.DEFAULT_SECURE_CONTAINER_CAPACITY

	local items = makeDefaultItems()
	if typeof(rawProfile.items) == "table" then
		for itemId, item in pairs(rawProfile.items) do
			if typeof(itemId) == "string" then
				local normalized = normalizeItem(item)
				if normalized then
					items[itemId] = normalized
				end
			end
		end
	end
	profile.items = items

	local loadout = if typeof(rawProfile.loadout) == "table" then rawProfile.loadout else {}
	profile.loadout.primaryA = if typeof(loadout.primaryA) == "string" and items[loadout.primaryA] ~= nil then loadout.primaryA else nil
	profile.loadout.primaryB = if typeof(loadout.primaryB) == "string" and items[loadout.primaryB] ~= nil then loadout.primaryB else nil
	profile.loadout.pistol = if typeof(loadout.pistol) == "string" and items[loadout.pistol] ~= nil then loadout.pistol else nil
	profile.loadout.melee = if typeof(loadout.melee) == "string" and items[loadout.melee] ~= nil then loadout.melee else nil
	profile.loadout.rig = normalizeItemIdList(loadout.rig, profile.rigCapacity, "rig", items)
	profile.loadout.backpack = normalizeItemIdList(loadout.backpack, profile.backpackCapacity, "backpack", items)
	profile.loadout.secure = normalizeItemIdList(loadout.secure, profile.secureContainerCapacity, "secure", items)
	profile.stash = normalizeItemIdList(rawProfile.stash, profile.stashCapacity, "stash", items)

	return profile
end

return PlayerProfile
