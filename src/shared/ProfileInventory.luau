--!strict

local ItemInstance = require(script.Parent.ItemInstance)
local PlayerProfile = require(script.Parent.PlayerProfile)

local ProfileInventory = {}

local function cloneArray<T>(arr: {T}?): {T}
	local out = {}
	if typeof(arr) ~= "table" then
		return out
	end

	for index, value in ipairs(arr) do
		out[index] = value
	end
	return out
end

local function makeSnapshotContainer(capacity: number, itemIds: {string}?): any
	local out = table.create(capacity)
	for slotIndex = 1, capacity do
		out[slotIndex] = itemIds and itemIds[slotIndex] or ""
	end

	return {
		capacity = capacity,
		itemIds = out,
	}
end

local function copyItemIntoSnapshot(itemsById: {[string]: any}, profileItems: {[string]: any}, itemId: string?)
	if typeof(itemId) ~= "string" or itemId == "" or itemsById[itemId] ~= nil then
		return
	end

	local item = profileItems[itemId]
	if item then
		local inventoryItem = ItemInstance.toInventoryItem(item, "stashed")
		if inventoryItem then
			itemsById[itemId] = inventoryItem
		end
	end
end

local function collectCarriedItemIds(snapshot: any): {[string]: boolean}
	local carried: {[string]: boolean} = {}
	if typeof(snapshot) ~= "table" then
		return carried
	end

	local function addItemId(itemId: any)
		if typeof(itemId) == "string" and itemId ~= "" then
			carried[itemId] = true
		end
	end

	local weaponSlots = if typeof(snapshot.weaponSlots) == "table" then snapshot.weaponSlots else {}
	addItemId(weaponSlots.PrimaryA)
	addItemId(weaponSlots.PrimaryB)
	addItemId(weaponSlots.Pistol)
	addItemId(weaponSlots.Melee)

	local function addContainer(container: any)
		if typeof(container) ~= "table" or typeof(container.capacity) ~= "number" then
			return
		end

		for slotIndex = 1, container.capacity do
			addItemId(container.itemIds and container.itemIds[slotIndex] or nil)
		end
	end

	addContainer(snapshot.rig)
	addContainer(snapshot.backpack)

	local itemsById = if typeof(snapshot.itemsById) == "table" then snapshot.itemsById else {}
	local changed = true
	while changed do
		changed = false
		for itemId in pairs(carried) do
			local item = itemsById[itemId]
			if typeof(item) == "table" then
				local attachedMagId = item.attachedMagId
				if typeof(attachedMagId) == "string" and attachedMagId ~= "" and not carried[attachedMagId] then
					carried[attachedMagId] = true
					changed = true
				end
			end
		end
	end

	return carried
end

function ProfileInventory.countSnapshotItems(snapshot: any): number
	local carried = collectCarriedItemIds(snapshot)
	local count = 0
	for _ in pairs(carried) do
		count += 1
	end
	return count
end

function ProfileInventory.toInventorySnapshot(profile: any): any
	local normalized = PlayerProfile.normalize(profile)

	local itemsById = {}

	copyItemIntoSnapshot(itemsById, normalized.items, normalized.loadout.primaryA)
	copyItemIntoSnapshot(itemsById, normalized.items, normalized.loadout.primaryB)
	copyItemIntoSnapshot(itemsById, normalized.items, normalized.loadout.pistol)
	copyItemIntoSnapshot(itemsById, normalized.items, normalized.loadout.melee)
	for _, itemId in ipairs(normalized.loadout.rig) do
		copyItemIntoSnapshot(itemsById, normalized.items, itemId)
	end
	for _, itemId in ipairs(normalized.loadout.backpack) do
		copyItemIntoSnapshot(itemsById, normalized.items, itemId)
	end
	for _, itemId in ipairs(normalized.stash) do
		copyItemIntoSnapshot(itemsById, normalized.items, itemId)
	end

	local changed = true
	while changed do
		changed = false
		for itemId, item in pairs(itemsById) do
			local attachedMagId = item.attachedMagId
			if typeof(attachedMagId) == "string" and attachedMagId ~= "" and itemsById[attachedMagId] == nil then
				copyItemIntoSnapshot(itemsById, normalized.items, attachedMagId)
				changed = true
			end
		end
	end

	return {
		version = 0,
		reqCredits = normalized.reqCredits,
		equippedSlot = "PrimaryA",
		weaponSlots = {
			PrimaryA = normalized.loadout.primaryA,
			PrimaryB = normalized.loadout.primaryB,
			Pistol = normalized.loadout.pistol,
			Melee = normalized.loadout.melee,
		},
		rig = makeSnapshotContainer(normalized.rigCapacity, normalized.loadout.rig),
		backpack = makeSnapshotContainer(normalized.backpackCapacity, normalized.loadout.backpack),
		stash = makeSnapshotContainer(normalized.stashCapacity, normalized.stash),
		quickBinds = {},
		hotbarItemIds = {
			normalized.loadout.primaryA,
			normalized.loadout.primaryB,
			normalized.loadout.pistol,
			normalized.loadout.melee,
			nil,
		},
		itemsById = itemsById,
		isReloading = false,
		lastCheckMag = nil,
		lastCheckMagSeq = 0,
	}
end

function ProfileInventory.applyInventorySnapshot(profile: any, snapshot: any): any
	local normalized = PlayerProfile.normalize(profile)
	if typeof(snapshot) ~= "table" then
		return normalized
	end

	local previousCarriedItemIds = collectCarriedItemIds(ProfileInventory.toInventorySnapshot(normalized))
	local carriedItemIds = collectCarriedItemIds(snapshot)
	local stashItemIds: {[string]: boolean} = {}
	local snapshotItemsById = if typeof(snapshot.itemsById) == "table" then snapshot.itemsById else {}
	if typeof(snapshot.stash) == "table" then
		for slotIndex = 1, math.min(normalized.stashCapacity, if typeof(snapshot.stash.capacity) == "number" then snapshot.stash.capacity else normalized.stashCapacity) do
			local itemId = snapshot.stash.itemIds and snapshot.stash.itemIds[slotIndex] or nil
			if typeof(itemId) == "string" and itemId ~= "" then
				stashItemIds[itemId] = true
			end
		end
	end
	local expanded = true
	while expanded do
		expanded = false
		for itemId in pairs(stashItemIds) do
			local item = snapshotItemsById[itemId]
			if typeof(item) == "table" then
				local attachedMagId = item.attachedMagId
				if typeof(attachedMagId) == "string" and attachedMagId ~= "" and not stashItemIds[attachedMagId] then
					stashItemIds[attachedMagId] = true
					expanded = true
				end
			end
		end
	end

	for itemId in pairs(previousCarriedItemIds) do
		local isInStash = table.find(normalized.stash, itemId) ~= nil
		if not isInStash then
			normalized.items[itemId] = nil
		end
	end

	for itemId in pairs(carriedItemIds) do
		local item = snapshotItemsById[itemId]
		if typeof(item) == "table" then
			local persistedItem = ItemInstance.fromInventoryItem(item)
			if persistedItem then
				normalized.items[itemId] = persistedItem
			end
		end
	end

	for itemId in pairs(stashItemIds) do
		local item = snapshotItemsById[itemId]
		if typeof(item) == "table" then
			local persistedItem = ItemInstance.fromInventoryItem(item)
			if persistedItem then
				normalized.items[itemId] = persistedItem
			end
		end
	end

	local weaponSlots = if typeof(snapshot.weaponSlots) == "table" then snapshot.weaponSlots else {}
	normalized.loadout.primaryA = if typeof(weaponSlots.PrimaryA) == "string" and carriedItemIds[weaponSlots.PrimaryA] then weaponSlots.PrimaryA else nil
	normalized.loadout.primaryB = if typeof(weaponSlots.PrimaryB) == "string" and carriedItemIds[weaponSlots.PrimaryB] then weaponSlots.PrimaryB else nil
	normalized.loadout.pistol = if typeof(weaponSlots.Pistol) == "string" and carriedItemIds[weaponSlots.Pistol] then weaponSlots.Pistol else nil
	normalized.loadout.melee = if typeof(weaponSlots.Melee) == "string" and carriedItemIds[weaponSlots.Melee] then weaponSlots.Melee else nil

	local function restoreContainer(containerSnapshot: any, capacity: number, allowedItemIds: {[string]: boolean}?): {string}
		local out = {}
		if typeof(containerSnapshot) ~= "table" then
			return out
		end

		for slotIndex = 1, math.min(capacity, if typeof(containerSnapshot.capacity) == "number" then containerSnapshot.capacity else capacity) do
			local itemId = containerSnapshot.itemIds and containerSnapshot.itemIds[slotIndex] or nil
			if typeof(itemId) == "string" and itemId ~= "" and (allowedItemIds == nil or allowedItemIds[itemId]) then
				table.insert(out, itemId)
			end
		end

		return out
	end

	normalized.loadout.rig = restoreContainer(snapshot.rig, normalized.rigCapacity, carriedItemIds)
	normalized.loadout.backpack = restoreContainer(snapshot.backpack, normalized.backpackCapacity, carriedItemIds)
	normalized.loadout.secure = {}
	if typeof(snapshot.stash) == "table" then
		normalized.stash = restoreContainer(snapshot.stash, normalized.stashCapacity, stashItemIds)
	end
	return normalized
end

function ProfileInventory.buildRaidSnapshot(profile: any): any
	local snapshot = ProfileInventory.toInventorySnapshot(profile)
	snapshot.stash = nil
	local carriedItemIds = collectCarriedItemIds(snapshot)
	for itemId in pairs(snapshot.itemsById) do
		if not carriedItemIds[itemId] then
			snapshot.itemsById[itemId] = nil
		end
	end
	for _, item in pairs(snapshot.itemsById) do
		item.locationState = "inRaid"
		item.origin = "BroughtIn"
	end
	return snapshot
end

return ProfileInventory
