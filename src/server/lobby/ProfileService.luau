--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local InventoryGrid = require(ReplicatedStorage.Shared.InventoryGrid)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local PlayerProfile = require(ReplicatedStorage.Shared.PlayerProfile)
local ProfileInventory = require(ReplicatedStorage.Shared.ProfileInventory)
local LootDefinitions = require(ReplicatedStorage.Shared.LootDefinitions)

local ProfileService = {}

if not PlaceConfig.isLobbyPlace() then
	return ProfileService
end

local PROFILE_STORE = DataStoreService:GetDataStore("PlayerProfile_v1")
local SAVE_DEBOUNCE_SECONDS = if RunService:IsStudio() then 2 else 5
local MAX_RETRIES = 3

type CachedProfile = {
	profile: any,
	loaded: boolean,
	loading: boolean,
	saveScheduled: boolean,
	dirty: boolean,
}

local profiles: {[number]: CachedProfile} = {}
local preRaidProfileSnapshotsByUserId: {[number]: any} = {}
local pruneUnreferencedItems

local function clearCarriedLoadout(profile: any)
	profile.activeRaid = nil
	profile.loadout.primaryA = nil
	profile.loadout.primaryB = nil
	profile.loadout.pistol = nil
	profile.loadout.melee = nil
	profile.loadout.rig = {}
	profile.loadout.backpack = {}
	profile.loadout.secure = {}
end

local function deepClone(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local out = {}
	for key, nested in pairs(value) do
		out[key] = deepClone(nested)
	end
	return out
end

local function runWithRetries<T>(label: string, fn: () -> T): (boolean, T?)
	local delaySeconds = 1
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end

		warn(string.format("[ProfileService] %s failed attempt=%d error=%s", label, attempt, tostring(result)))
		if attempt < MAX_RETRIES then
			task.wait(delaySeconds)
			delaySeconds *= 2
		end
	end

	return false, nil
end

local function getCache(userId: number): CachedProfile
	local cached = profiles[userId]
	if cached then
		return cached
	end

	cached = {
		profile = PlayerProfile.createDefault(),
		loaded = false,
		loading = false,
		saveScheduled = false,
		dirty = false,
	}
	profiles[userId] = cached
	return cached
end

function ProfileService.loadProfile(userId: number): any
	local cached = getCache(userId)
	if cached.loaded then
		return cached.profile
	end

	while cached.loading and not cached.loaded do
		task.wait()
	end

	if cached.loaded then
		return cached.profile
	end

	cached.loading = true

	local success, loadedProfile = runWithRetries(string.format("load userId=%d", userId), function()
		return PROFILE_STORE:GetAsync(tostring(userId))
	end)

	if success then
		cached.profile = PlayerProfile.normalize(loadedProfile)
		cached.loaded = true
		print(string.format("[ProfileService] load success userId=%d", userId))
	else
		cached.profile = PlayerProfile.createDefault()
		cached.loaded = true
		warn(string.format("[ProfileService] load fail userId=%d using defaults", userId))
	end

	cached.loading = false
	return cached.profile
end

function ProfileService.getProfile(userId: number): any
	return ProfileService.loadProfile(userId)
end

function ProfileService.getProfileClone(userId: number): any
	return deepClone(ProfileService.loadProfile(userId))
end

function ProfileService.getInventorySnapshot(userId: number): any
	local profile = ProfileService.loadProfile(userId)
	return ProfileInventory.toInventorySnapshot(profile)
end

function ProfileService.getReqCredits(userId: number): number
	local profile = ProfileService.loadProfile(userId)
	return if typeof(profile.reqCredits) == "number" then profile.reqCredits else 0
end

function ProfileService.getPreRaidProfileSnapshot(userId: number): any
	local snapshot = preRaidProfileSnapshotsByUserId[userId]
	if snapshot == nil then
		return nil
	end

	return deepClone(snapshot)
end

function ProfileService.setPreRaidProfileSnapshot(userId: number, profileSnapshot: any)
	preRaidProfileSnapshotsByUserId[userId] = deepClone(profileSnapshot)
end

function ProfileService.clearPreRaidProfileSnapshot(userId: number)
	preRaidProfileSnapshotsByUserId[userId] = nil
end

local function saveProfileInternal(userId: number, reason: string): boolean
	local cached = getCache(userId)
	if not cached.loaded then
		return false
	end

	local profileToSave = PlayerProfile.normalize(cached.profile)
	local success = runWithRetries(string.format("save userId=%d reason=%s", userId, reason), function()
		return PROFILE_STORE:UpdateAsync(tostring(userId), function(_oldValue)
			return deepClone(profileToSave)
		end)
	end)

	if success then
		cached.dirty = false
		print(string.format("[ProfileService] save success userId=%d reason=%s", userId, reason))
		return true
	end

	warn(string.format("[ProfileService] save fail userId=%d reason=%s", userId, reason))
	return false
end

function ProfileService.forceSave(userId: number, reason: string?): boolean
	return saveProfileInternal(userId, reason or "force")
end

function ProfileService.scheduleSave(userId: number, reason: string?)
	local cached = getCache(userId)
	cached.dirty = true
	if cached.saveScheduled then
		return
	end

	cached.saveScheduled = true
	task.delay(SAVE_DEBOUNCE_SECONDS, function()
		local current = profiles[userId]
		if not current then
			return
		end

		current.saveScheduled = false
		if current.dirty then
			saveProfileInternal(userId, reason or "debounced")
		end
	end)
end

function ProfileService.applyInventorySnapshot(userId: number, snapshot: any, reason: string?)
	local cached = getCache(userId)
	cached.profile = ProfileInventory.applyInventorySnapshot(ProfileService.loadProfile(userId), snapshot)
	cached.loaded = true
	cached.dirty = true
	ProfileService.scheduleSave(userId, reason or "inventory_snapshot")
end

function ProfileService.applyExtractedSnapshot(userId: number, snapshot: any)
	local cached = getCache(userId)
	cached.profile = ProfileInventory.applyInventorySnapshot(ProfileService.loadProfile(userId), snapshot)
	cached.loaded = true
	cached.dirty = true
end

function ProfileService.restoreProfileSnapshot(userId: number, profileSnapshot: any)
	local cached = getCache(userId)
	cached.profile = PlayerProfile.normalize(profileSnapshot)
	cached.loaded = true
	cached.dirty = true
end

function ProfileService.markActiveRaid(userId: number, raidId: string, preRaidProfileSnapshot: any?)
	local profile = ProfileService.loadProfile(userId)
	profile.activeRaid = {
		raidId = raidId,
		startedAt = Workspace:GetServerTimeNow(),
		preRaidProfileSnapshot = if preRaidProfileSnapshot ~= nil then deepClone(preRaidProfileSnapshot) else nil,
	}
	local cached = getCache(userId)
	cached.profile = profile
	cached.loaded = true
	cached.dirty = true
end

function ProfileService.clearActiveRaid(userId: number)
	local profile = ProfileService.loadProfile(userId)
	if profile.activeRaid ~= nil then
		profile.activeRaid = nil
		local cached = getCache(userId)
		cached.profile = profile
		cached.loaded = true
		cached.dirty = true
	end
end

function ProfileService.consumeAbandonedRaid(userId: number): any?
	local profile = ProfileService.loadProfile(userId)
	if typeof(profile.activeRaid) ~= "table" then
		return nil
	end

	local abandonedRaid = deepClone(profile.activeRaid)
	clearCarriedLoadout(profile)
	pruneUnreferencedItems(profile)
	local cached = getCache(userId)
	cached.profile = profile
	cached.loaded = true
	cached.dirty = true
	ProfileService.forceSave(userId, "abandoned_raid_loss")
	return abandonedRaid
end

function ProfileService.applyRaidLossSnapshot(userId: number, _preRaidProfileSnapshot: any?)
	local profile = ProfileService.loadProfile(userId)
	clearCarriedLoadout(profile)
	pruneUnreferencedItems(profile)

	local cached = getCache(userId)
	cached.profile = profile
	cached.loaded = true
	cached.dirty = true
end

function ProfileService.buildRaidInventorySnapshot(userId: number): any
	local profile = ProfileService.loadProfile(userId)
	return ProfileInventory.buildRaidSnapshot(profile)
end

function ProfileService.getSnapshotSummary(snapshot: any): string
	local itemCount = ProfileInventory.countSnapshotItems(snapshot)
	local rigCount = 0
	local backpackCount = 0
	if typeof(snapshot) == "table" and typeof(snapshot.rig) == "table" and typeof(snapshot.rig.capacity) == "number" then
		for slotIndex = 1, snapshot.rig.capacity do
			local itemId = snapshot.rig.itemIds and snapshot.rig.itemIds[slotIndex] or nil
			if typeof(itemId) == "string" and itemId ~= "" then
				rigCount += 1
			end
		end
	end

	if typeof(snapshot) == "table" and typeof(snapshot.backpack) == "table" and typeof(snapshot.backpack.capacity) == "number" then
		for slotIndex = 1, snapshot.backpack.capacity do
			local itemId = snapshot.backpack.itemIds and snapshot.backpack.itemIds[slotIndex] or nil
			if typeof(itemId) == "string" and itemId ~= "" then
				backpackCount += 1
			end
		end
	end

	return string.format("items=%d rig=%d backpack=%d", itemCount, rigCount, backpackCount)
end

local function isWeaponSlotDestinationValid(item: any, destination: string): boolean
	if destination == "primaryA" or destination == "primaryB" then
		return item.category == "gun"
	end
	if destination == "pistol" then
		return item.category == "pistol"
	end
	if destination == "melee" then
		return item.category == "melee"
	end

	return false
end

local function collectReferencedItemIds(profile: any): {[string]: boolean}
	local referenced: {[string]: boolean} = {}

	local function addItemId(itemId: any)
		if typeof(itemId) == "string" and itemId ~= "" then
			referenced[itemId] = true
		end
	end

	addItemId(profile.loadout.primaryA)
	addItemId(profile.loadout.primaryB)
	addItemId(profile.loadout.pistol)
	addItemId(profile.loadout.melee)

	for _, itemId in pairs(profile.loadout.rig) do
		addItemId(itemId)
	end
	for _, itemId in pairs(profile.loadout.backpack) do
		addItemId(itemId)
	end
	for _, itemId in pairs(profile.loadout.secure) do
		addItemId(itemId)
	end
	for _, itemId in pairs(profile.stash) do
		addItemId(itemId)
	end

	local expanded = true
	while expanded do
		expanded = false
		for itemId in pairs(referenced) do
			local item = profile.items[itemId]
			if typeof(item) == "table" and typeof(item.state) == "table" then
				local attachedMagId = item.state.attachedMagId
				if typeof(attachedMagId) == "string" and attachedMagId ~= "" and not referenced[attachedMagId] then
					referenced[attachedMagId] = true
					expanded = true
				end
			end
		end
	end

	return referenced
end

function pruneUnreferencedItems(profile: any)
	local referenced = collectReferencedItemIds(profile)
	for itemId in pairs(profile.items) do
		if not referenced[itemId] then
			profile.items[itemId] = nil
		end
	end
end

local function findItemInList(list: any, itemId: string, capacity: number?): number?
	if typeof(list) ~= "table" then
		return nil
	end

	local maxIndex = capacity or #list
	for index = 1, maxIndex do
		if list[index] == itemId then
			return index
		end
	end

	return nil
end

local function findProfileGridContainer(profile: any, itemId: string): ({string?}?, number?, string?, number?)
	local stashIndex = findItemInList(profile.stash, itemId, profile.stashCapacity)
	if stashIndex then
		return profile.stash, stashIndex, "stash", profile.stashCapacity
	end

	local rigIndex = findItemInList(profile.loadout.rig, itemId, profile.rigCapacity)
	if rigIndex then
		return profile.loadout.rig, rigIndex, "rig", profile.rigCapacity
	end

	local backpackIndex = findItemInList(profile.loadout.backpack, itemId, profile.backpackCapacity)
	if backpackIndex then
		return profile.loadout.backpack, backpackIndex, "backpack", profile.backpackCapacity
	end

	return nil, nil, nil, nil
end

local function getSellDefinition(item: any): any?
	if typeof(item) ~= "table" or typeof(item.templateId) ~= "string" then
		return nil
	end

	return LootDefinitions.get(item.templateId)
end

local function removeFromGridList(list: {string?}, itemId: string, capacity: number): number?
	local index = findItemInList(list, itemId, capacity)
	if index then
		list[index] = nil
		return index
	end

	return nil
end

local function removeFromCarriedLoadout(profile: any, itemId: string): boolean
	for slotName, slotItemId in pairs({
		primaryA = profile.loadout.primaryA,
		primaryB = profile.loadout.primaryB,
		pistol = profile.loadout.pistol,
		melee = profile.loadout.melee,
	}) do
		if slotItemId == itemId then
			profile.loadout[slotName] = nil
			return true
		end
	end

	if removeFromGridList(profile.loadout.rig, itemId, profile.rigCapacity) then
		return true
	end

	if removeFromGridList(profile.loadout.backpack, itemId, profile.backpackCapacity) then
		return true
	end

	return false
end

local function listQuartermasterItems(profile: any): {any}
	local sellableItems = {}
	local orderedContainers = {
		{ source = "rig", itemIds = profile.loadout.rig, capacity = profile.rigCapacity },
		{ source = "backpack", itemIds = profile.loadout.backpack, capacity = profile.backpackCapacity },
	}

	for _, containerInfo in ipairs(orderedContainers) do
		for slotIndex = 1, containerInfo.capacity do
			local itemId = containerInfo.itemIds[slotIndex]
			local item = profile.items[itemId]
			if typeof(item) == "table" then
				local definition = getSellDefinition(item)
				local sellPolicy = if definition and typeof(definition.sellPolicy) == "string" then definition.sellPolicy else "Normal"
				local sellValue = if definition and typeof(definition.sellValue) == "number" then math.max(0, math.floor(definition.sellValue)) else 0
				if sellPolicy == "Normal" and sellValue > 0 then
					table.insert(sellableItems, {
						itemId = itemId,
						templateId = item.templateId,
						displayName = LootDefinitions.getDisplayName(item.templateId),
						category = item.category,
						source = containerInfo.source,
						value = sellValue,
						origin = if item.origin == "Looted" then "Looted" else "BroughtIn",
					})
				end
			end
		end
	end

	table.sort(sellableItems, function(a, b)
		if a.source ~= b.source then
			return a.source < b.source
		end
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.displayName < b.displayName
	end)

	return sellableItems
end

function ProfileService.getQuartermasterState(userId: number, notice: string?): any
	local profile = ProfileService.loadProfile(userId)
	return {
		reqCredits = if typeof(profile.reqCredits) == "number" then profile.reqCredits else 0,
		sellableItems = listQuartermasterItems(profile),
		notice = notice,
	}
end

function ProfileService.handleQuartermasterSell(userId: number, itemId: any, source: any): (boolean, string?, number?)
	if typeof(itemId) ~= "string" then
		return false, "invalid_item"
	end
	if source ~= "rig" and source ~= "backpack" then
		return false, "invalid_source"
	end

	local profile = ProfileService.loadProfile(userId)
	local container = if source == "rig" then profile.loadout.rig else profile.loadout.backpack
	local containerCapacity = if source == "rig" then profile.rigCapacity else profile.backpackCapacity
	if typeof(container) ~= "table" then
		return false, "missing_container"
	end

	if findItemInList(container, itemId, containerCapacity) == nil then
		return false, "item_not_owned"
	end

	local item = profile.items[itemId]
	if typeof(item) ~= "table" then
		return false, "missing_item"
	end

	local definition = getSellDefinition(item)
	local sellPolicy = if definition and typeof(definition.sellPolicy) == "string" then definition.sellPolicy else "Normal"
	local sellValue = if definition and typeof(definition.sellValue) == "number" then math.max(0, math.floor(definition.sellValue)) else 0
	if sellPolicy ~= "Normal" or sellValue <= 0 then
		return false, "not_sellable"
	end

	removeFromGridList(container, itemId, containerCapacity)
	pruneUnreferencedItems(profile)
	profile.reqCredits = (if typeof(profile.reqCredits) == "number" then profile.reqCredits else 0) + sellValue
	ProfileService.scheduleSave(userId, "quartermaster_sell")
	return true, nil, sellValue
end

function ProfileService.handleStashAction(userId: number, action: any): (boolean, string?)
	if typeof(action) ~= "table" or typeof(action.kind) ~= "string" then
		return false, "invalid_action"
	end

	local profile = ProfileService.loadProfile(userId)
	local kind = action.kind
	if kind == "MoveToStash" then
		local itemId = action.itemId
		if typeof(itemId) ~= "string" then
			return false, "invalid_item"
		end
		local destIndex = if typeof(action.destIndex) == "number" then action.destIndex else nil

		local item = profile.items[itemId]
		if typeof(item) ~= "table" then
			return false, "missing_item"
		end

		local stashDestinationIndex = InventoryGrid.placeItem(profile.stash, profile.items, profile.stashCapacity, "stash", item, destIndex, itemId)
		if not stashDestinationIndex then
			return false, "stash_full"
		end

		local removed = false
		for slotName, slotItemId in pairs({
			primaryA = profile.loadout.primaryA,
			primaryB = profile.loadout.primaryB,
			pistol = profile.loadout.pistol,
			melee = profile.loadout.melee,
		}) do
			if slotItemId == itemId then
				profile.loadout[slotName] = nil
				removed = true
				break
			end
		end

		if not removed then
			local rigIndex = findItemInList(profile.loadout.rig, itemId, profile.rigCapacity)
			if rigIndex then
				profile.loadout.rig[rigIndex] = nil
				removed = true
			end
		end

		if not removed then
			local backpackIndex = findItemInList(profile.loadout.backpack, itemId, profile.backpackCapacity)
			if backpackIndex then
				profile.loadout.backpack[backpackIndex] = nil
				removed = true
			end
		end

		if not removed then
			return false, "item_not_carried"
		end

		profile.stash[stashDestinationIndex] = itemId
		ProfileService.scheduleSave(userId, "stash_move")
		return true, nil
	end

	if kind == "MoveToInventory" then
		local itemId = action.itemId
		local destination = action.dest
		local destIndex = if typeof(action.destIndex) == "number" then action.destIndex else nil
		if typeof(itemId) ~= "string" or typeof(destination) ~= "string" then
			return false, "invalid_move"
		end

		local stashIndex = findItemInList(profile.stash, itemId, profile.stashCapacity)
		if not stashIndex then
			return false, "item_not_in_stash"
		end

		local item = profile.items[itemId]
		if typeof(item) ~= "table" then
			return false, "missing_item"
		end

		if destination == "rig" then
			if item.category ~= "mag" and item.category ~= "med" then
				return false, "invalid_rig_category"
			end
			local rigDestinationIndex = InventoryGrid.placeItem(profile.loadout.rig, profile.items, profile.rigCapacity, "rig", item, destIndex, itemId)
			if not rigDestinationIndex then
				return false, "rig_full"
			end
			profile.stash[stashIndex] = nil
			profile.loadout.rig[rigDestinationIndex] = itemId
			ProfileService.scheduleSave(userId, "stash_move")
			return true, nil
		end

		if destination == "backpack" then
			local backpackDestinationIndex = InventoryGrid.placeItem(profile.loadout.backpack, profile.items, profile.backpackCapacity, "backpack", item, destIndex, itemId)
			if not backpackDestinationIndex then
				return false, "backpack_full"
			end
			profile.stash[stashIndex] = nil
			profile.loadout.backpack[backpackDestinationIndex] = itemId
			ProfileService.scheduleSave(userId, "stash_move")
			return true, nil
		end

		if not isWeaponSlotDestinationValid(item, destination) then
			return false, "invalid_slot_category"
		end
		if profile.loadout[destination] ~= nil then
			return false, "slot_occupied"
		end

		profile.stash[stashIndex] = nil
		profile.loadout[destination] = itemId
		ProfileService.scheduleSave(userId, "stash_move")
		return true, nil
	end

	if kind == "MoveWithinInventory" then
		local itemId = action.itemId
		local destination = action.dest
		local destIndex = if typeof(action.destIndex) == "number" then action.destIndex else nil
		if typeof(itemId) ~= "string" or typeof(destination) ~= "string" then
			return false, "invalid_move"
		end

		local item = profile.items[itemId]
		if typeof(item) ~= "table" then
			return false, "missing_item"
		end

		if destination == "rig" then
			if item.category ~= "mag" and item.category ~= "med" then
				return false, "invalid_rig_category"
			end

			local destinationIndex = InventoryGrid.placeItem(profile.loadout.rig, profile.items, profile.rigCapacity, "rig", item, destIndex, itemId)
			if not destinationIndex then
				return false, "rig_full"
			end

			if not removeFromCarriedLoadout(profile, itemId) then
				return false, "item_not_carried"
			end

			profile.loadout.rig[destinationIndex] = itemId
			ProfileService.scheduleSave(userId, "stash_move")
			return true, nil
		end

		if destination == "backpack" then
			local destinationIndex = InventoryGrid.placeItem(profile.loadout.backpack, profile.items, profile.backpackCapacity, "backpack", item, destIndex, itemId)
			if not destinationIndex then
				return false, "backpack_full"
			end

			if not removeFromCarriedLoadout(profile, itemId) then
				return false, "item_not_carried"
			end

			profile.loadout.backpack[destinationIndex] = itemId
			ProfileService.scheduleSave(userId, "stash_move")
			return true, nil
		end

		if not isWeaponSlotDestinationValid(item, destination) then
			return false, "invalid_slot_category"
		end
		if profile.loadout[destination] ~= nil and profile.loadout[destination] ~= itemId then
			return false, "slot_occupied"
		end

		if not removeFromCarriedLoadout(profile, itemId) then
			return false, "item_not_carried"
		end

		profile.loadout[destination] = itemId
		ProfileService.scheduleSave(userId, "stash_move")
		return true, nil
	end

	if kind == "MoveWithinStash" then
		local itemId = action.itemId
		local destIndex = if typeof(action.destIndex) == "number" then action.destIndex else nil
		if typeof(itemId) ~= "string" then
			return false, "invalid_item"
		end

		local stashIndex = findItemInList(profile.stash, itemId, profile.stashCapacity)
		if not stashIndex then
			return false, "item_not_in_stash"
		end

		local item = profile.items[itemId]
		if typeof(item) ~= "table" then
			return false, "missing_item"
		end

		local destinationIndex = InventoryGrid.placeItem(profile.stash, profile.items, profile.stashCapacity, "stash", item, destIndex, itemId)
		if not destinationIndex then
			return false, "stash_full"
		end

		profile.stash[stashIndex] = nil
		profile.stash[destinationIndex] = itemId
		ProfileService.scheduleSave(userId, "stash_move")
		return true, nil
	end

	if kind == "RotateItem" then
		local itemId = action.itemId
		if typeof(itemId) ~= "string" then
			return false, "invalid_item"
		end

		local item = profile.items[itemId]
		if typeof(item) ~= "table" then
			return false, "missing_item"
		end

		local container, anchorIndex, containerName, capacity = findProfileGridContainer(profile, itemId)
		if not container or not anchorIndex or not containerName or not capacity then
			return false, "item_not_in_grid"
		end

		item.inventoryRotated = not (item.inventoryRotated == true)
		if not InventoryGrid.canFitAt(container, profile.items, capacity, containerName, item, anchorIndex, itemId) then
			item.inventoryRotated = not (item.inventoryRotated == true)
			return false, "rotate_blocked"
		end

		ProfileService.scheduleSave(userId, "stash_rotate")
		return true, nil
	end

	return false, "unsupported_action"
end

for _, player in ipairs(Players:GetPlayers()) do
	ProfileService.loadProfile(player.UserId)
end

Players.PlayerAdded:Connect(function(player)
	ProfileService.loadProfile(player.UserId)
end)

Players.PlayerRemoving:Connect(function(player)
	ProfileService.forceSave(player.UserId, "player_removing")
	profiles[player.UserId] = nil
	preRaidProfileSnapshotsByUserId[player.UserId] = nil
end)

return ProfileService
