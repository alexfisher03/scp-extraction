--!strict

local LobbySessionService = {}

local inventorySnapshotByUserId: {[number]: any} = {}
local preRaidInventorySnapshotByUserId: {[number]: any} = {}
local postRaidResultByUserId: {[number]: any} = {}

function LobbySessionService.setInventorySnapshot(userId: number, snapshot: any)
	inventorySnapshotByUserId[userId] = snapshot
end

function LobbySessionService.getInventorySnapshot(userId: number): any
	return inventorySnapshotByUserId[userId]
end

function LobbySessionService.clearInventorySnapshot(userId: number)
	inventorySnapshotByUserId[userId] = nil
end

function LobbySessionService.setPreRaidInventorySnapshot(userId: number, snapshot: any)
	preRaidInventorySnapshotByUserId[userId] = snapshot
end

function LobbySessionService.getPreRaidInventorySnapshot(userId: number): any
	return preRaidInventorySnapshotByUserId[userId]
end

function LobbySessionService.clearPreRaidInventorySnapshot(userId: number)
	preRaidInventorySnapshotByUserId[userId] = nil
end

function LobbySessionService.setPostRaidResult(userId: number, result: any)
	postRaidResultByUserId[userId] = result
end

function LobbySessionService.getPostRaidResult(userId: number): any
	return postRaidResultByUserId[userId]
end

function LobbySessionService.clearPostRaidResult(userId: number)
	postRaidResultByUserId[userId] = nil
end

return LobbySessionService
