--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
	saveScheduled: boolean,
	dirty: boolean,
}

local profiles: {[number]: CachedProfile} = {}
local preRaidProfileSnapshotsByUserId: {[number]: any} = {}

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

	for _, itemId in ipairs(profile.loadout.rig) do
		addItemId(itemId)
	end
	for _, itemId in ipairs(profile.loadout.backpack) do
		addItemId(itemId)
	end
	for _, itemId in ipairs(profile.loadout.secure) do
		addItemId(itemId)
	end
	for _, itemId in ipairs(profile.stash) do
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

local function pruneUnreferencedItems(profile: any)
	local referenced = collectReferencedItemIds(profile)
	for itemId in pairs(profile.items) do
		if not referenced[itemId] then
			profile.items[itemId] = nil
		end
	end
end

local function getSellDefinition(item: any): any?
	if typeof(item) ~= "table" or typeof(item.templateId) ~= "string" then
		return nil
	end

	return LootDefinitions.get(item.templateId)
end

local function removeFromArray(list: {string}, itemId: string): number?
	local index = table.find(list, itemId)
	if index then
		table.remove(list, index)
		return index
	end

	return nil
end

local function listQuartermasterItems(profile: any): {any}
	local sellableItems = {}
	local orderedContainers = {
		{ source = "rig", itemIds = profile.loadout.rig },
		{ source = "backpack", itemIds = profile.loadout.backpack },
	}

	for _, containerInfo in ipairs(orderedContainers) do
		for _, itemId in ipairs(containerInfo.itemIds) do
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
	if typeof(container) ~= "table" then
		return false, "missing_container"
	end

	if table.find(container, itemId) == nil then
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

	removeFromArray(container, itemId)
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
		if #profile.stash >= profile.stashCapacity then
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
			local rigIndex = table.find(profile.loadout.rig, itemId)
			if rigIndex then
				table.remove(profile.loadout.rig, rigIndex)
				removed = true
			end
		end

		if not removed then
			local backpackIndex = table.find(profile.loadout.backpack, itemId)
			if backpackIndex then
				table.remove(profile.loadout.backpack, backpackIndex)
				removed = true
			end
		end

		if not removed then
			return false, "item_not_carried"
		end

		table.insert(profile.stash, itemId)
		ProfileService.scheduleSave(userId, "stash_move")
		return true, nil
	end

	if kind == "MoveToInventory" then
		local itemId = action.itemId
		local destination = action.dest
		if typeof(itemId) ~= "string" or typeof(destination) ~= "string" then
			return false, "invalid_move"
		end

		local stashIndex = table.find(profile.stash, itemId)
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
			if #profile.loadout.rig >= profile.rigCapacity then
				return false, "rig_full"
			end
			table.remove(profile.stash, stashIndex)
			table.insert(profile.loadout.rig, itemId)
			ProfileService.scheduleSave(userId, "stash_move")
			return true, nil
		end

		if destination == "backpack" then
			if #profile.loadout.backpack >= profile.backpackCapacity then
				return false, "backpack_full"
			end
			table.remove(profile.stash, stashIndex)
			table.insert(profile.loadout.backpack, itemId)
			ProfileService.scheduleSave(userId, "stash_move")
			return true, nil
		end

		if not isWeaponSlotDestinationValid(item, destination) then
			return false, "invalid_slot_category"
		end
		if profile.loadout[destination] ~= nil then
			return false, "slot_occupied"
		end

		table.remove(profile.stash, stashIndex)
		profile.loadout[destination] = itemId
		ProfileService.scheduleSave(userId, "stash_move")
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
