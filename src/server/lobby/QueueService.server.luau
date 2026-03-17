--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)

if not PlaceConfig.isLobbyPlace() then
	return
end

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local joinQueueEvent = remotes:WaitForChild(Net.LobbyJoinQueueEventName) :: RemoteEvent
local leaveQueueEvent = remotes:WaitForChild(Net.LobbyLeaveQueueEventName) :: RemoteEvent
local devForceStartEvent = remotes:WaitForChild(Net.LobbyDevForceStartEventName) :: RemoteEvent
local queueStatusEvent = remotes:WaitForChild(Net.LobbyQueueStatusEventName) :: RemoteEvent
local noticeEvent = remotes:WaitForChild(Net.LobbyNoticeEventName) :: RemoteEvent

type QueueEntry = {
	player: Player,
	joinedAt: number,
}

local queue: {QueueEntry} = {}
local queuedSet: {[number]: boolean} = {}
local starting = false
local effectiveMaxWaitSeconds = if RunService:IsStudio() then 15 else PlaceConfig.QUEUE_MAX_WAIT_SECONDS
local effectiveRaidSize = 2
local pendingBatches: {[string]: {entries: {QueueEntry}, restored: boolean}} = {}
local batchIdByUserId: {[number]: string} = {}
local nextRetryAt = 0
local RETRY_COOLDOWN_SECONDS = 10

local function isDevAllowed(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end

	return game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId
end

local function getQueueCount(): number
	return #queue
end

local function computeEstimatedWaitSeconds(joinedAt: number?): number?
	if not joinedAt then
		return nil
	end

	local oldestWait = Workspace:GetServerTimeNow() - joinedAt
	return math.max(0, effectiveMaxWaitSeconds - oldestWait)
end

local function sendQueueStatusTo(player: Player)
	local position: number? = nil
	local joinedAt: number? = nil
	for index, entry in ipairs(queue) do
		if entry.player == player then
			position = index
			joinedAt = entry.joinedAt
			break
		end
	end

	queueStatusEvent:FireClient(player, {
		position = position,
		count = getQueueCount(),
		targetSize = effectiveRaidSize,
		estimatedWaitSeconds = computeEstimatedWaitSeconds(joinedAt),
		queued = position ~= nil,
	})
end

local function broadcastQueueStatus()
	for _, player in ipairs(Players:GetPlayers()) do
		sendQueueStatusTo(player)
	end
end

local function notifyPlayers(players: {Player}, message: string)
	for _, player in ipairs(players) do
		if player.Parent then
			noticeEvent:FireClient(player, message)
		end
	end
end

local function removeQueueEntryByUserId(userId: number): QueueEntry?
	for index, entry in ipairs(queue) do
		if entry.player.UserId == userId then
			table.remove(queue, index)
			queuedSet[userId] = nil
			return entry
		end
	end

	return nil
end

local function joinQueue(player: Player)
	if queuedSet[player.UserId] then
		sendQueueStatusTo(player)
		return
	end

	table.insert(queue, {
		player = player,
		joinedAt = Workspace:GetServerTimeNow(),
	})
	queuedSet[player.UserId] = true
	broadcastQueueStatus()
end

local function leaveQueue(player: Player)
	removeQueueEntryByUserId(player.UserId)
	broadcastQueueStatus()
end

local function takeQueueEntries(count: number): {QueueEntry}
	local taken = {}
	for _ = 1, math.min(count, #queue) do
		local entry = table.remove(queue, 1)
		if entry then
			queuedSet[entry.player.UserId] = nil
			table.insert(taken, entry)
		end
	end
	return taken
end

local function restoreEntriesToFront(entries: {QueueEntry})
	for index = #entries, 1, -1 do
		local entry = entries[index]
		if entry.player.Parent and not queuedSet[entry.player.UserId] then
			table.insert(queue, 1, entry)
			queuedSet[entry.player.UserId] = true
		end
	end
	broadcastQueueStatus()
end

local function startMatch(entryCount: number)
	if starting or entryCount <= 0 then
		return
	end

	if Workspace:GetServerTimeNow() < nextRetryAt then
		return
	end

	starting = true
	local entries = takeQueueEntries(entryCount)
	if #entries == 0 then
		starting = false
		return
	end

	local playersToTeleport = {}
	local partyUserIds = {}
	for _, entry in ipairs(entries) do
		if entry.player.Parent then
			table.insert(playersToTeleport, entry.player)
			table.insert(partyUserIds, entry.player.UserId)
		end
	end

	if #playersToTeleport == 0 then
		starting = false
		return
	end

	local batchId = HttpService:GenerateGUID(false)
	pendingBatches[batchId] = {
		entries = entries,
		restored = false,
	}

	for _, entry in ipairs(entries) do
		batchIdByUserId[entry.player.UserId] = batchId
	end

	local accessCodeOk, accessCodeOrError = pcall(function()
		return TeleportService:ReserveServer(PlaceConfig.RAID_PLACE_ID)
	end)

	if not accessCodeOk then
		for _, entry in ipairs(entries) do
			batchIdByUserId[entry.player.UserId] = nil
		end
		pendingBatches[batchId] = nil
		restoreEntriesToFront(entries)
		nextRetryAt = Workspace:GetServerTimeNow() + RETRY_COOLDOWN_SECONDS
		notifyPlayers(playersToTeleport, if RunService:IsStudio() then "Teleport failed in Studio. Test with published places/clients." else "Teleport failed, retrying soon")
		starting = false
		return
	end

	local teleportData = {
		raidId = HttpService:GenerateGUID(false),
		partyUserIds = partyUserIds,
		createdAt = Workspace:GetServerTimeNow(),
		loadoutSeed = {},
	}

	notifyPlayers(playersToTeleport, "Loading into raid...")

	local teleportOk = pcall(function()
		TeleportService:TeleportToPrivateServer(
			PlaceConfig.RAID_PLACE_ID,
			accessCodeOrError,
			playersToTeleport,
			nil,
			teleportData
		)
	end)

	if not teleportOk then
		for _, entry in ipairs(entries) do
			batchIdByUserId[entry.player.UserId] = nil
		end
		pendingBatches[batchId] = nil
		restoreEntriesToFront(entries)
		nextRetryAt = Workspace:GetServerTimeNow() + RETRY_COOLDOWN_SECONDS
		notifyPlayers(playersToTeleport, if RunService:IsStudio() then "Teleport failed in Studio. Test with published places/clients." else "Teleport failed, retrying soon")
	end

	starting = false
	broadcastQueueStatus()
end

local function startEligibleMatch()
	if starting then
		return
	end

	if #queue >= effectiveRaidSize then
		startMatch(effectiveRaidSize)
		return
	end

	if #queue == 0 then
		return
	end

	local oldest = queue[1]
	if oldest and (Workspace:GetServerTimeNow() - oldest.joinedAt) >= effectiveMaxWaitSeconds then
		startMatch(math.min(effectiveRaidSize, #queue))
	end
end

joinQueueEvent.OnServerEvent:Connect(function(player: Player)
	joinQueue(player)
end)

leaveQueueEvent.OnServerEvent:Connect(function(player: Player)
	leaveQueue(player)
end)

devForceStartEvent.OnServerEvent:Connect(function(player: Player)
	if not isDevAllowed(player) then
		return
	end

	if #queue == 0 then
		return
	end

	startMatch(math.min(effectiveRaidSize, #queue))
end)

TeleportService.TeleportInitFailed:Connect(function(player: Player)
	local batchId = batchIdByUserId[player.UserId]
	if not batchId then
		return
	end

	local batch = pendingBatches[batchId]
	if not batch or batch.restored then
		return
	end

	batch.restored = true
	for _, entry in ipairs(batch.entries) do
		batchIdByUserId[entry.player.UserId] = nil
	end
	restoreEntriesToFront(batch.entries)
	nextRetryAt = Workspace:GetServerTimeNow() + RETRY_COOLDOWN_SECONDS
	notifyPlayers(Players:GetPlayers(), if RunService:IsStudio() then "Teleport failed in Studio. Test with published places/clients." else "Teleport failed, retrying soon")
	pendingBatches[batchId] = nil
end)

Players.PlayerRemoving:Connect(function(player)
	removeQueueEntryByUserId(player.UserId)
	broadcastQueueStatus()
end)

for _, player in ipairs(Players:GetPlayers()) do
	sendQueueStatusTo(player)
end

task.spawn(function()
	while true do
		task.wait(1)

		for index = #queue, 1, -1 do
			local entry = queue[index]
			if not entry.player.Parent then
				table.remove(queue, index)
				queuedSet[entry.player.UserId] = nil
			end
		end

		startEligibleMatch()
		broadcastQueueStatus()
	end
end)
