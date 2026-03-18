--!strict

local InventoryAuthority = {}

local statesByUserId: {[number]: any} = {}
local snapshotEmitter: ((Player, any) -> ())? = nil
local snapshotSerializer: ((any) -> any)? = nil

function InventoryAuthority.getState(userId: number): any
	return statesByUserId[userId]
end

function InventoryAuthority.setState(userId: number, state: any)
	statesByUserId[userId] = state
end

function InventoryAuthority.removeState(userId: number)
	statesByUserId[userId] = nil
end

function InventoryAuthority.setSnapshotEmitter(emitter: (Player, any) -> ())
	snapshotEmitter = emitter
end

function InventoryAuthority.emitSnapshot(player: Player, state: any)
	if snapshotEmitter then
		snapshotEmitter(player, state)
	end
end

function InventoryAuthority.setSnapshotSerializer(serializer: (any) -> any)
	snapshotSerializer = serializer
end

function InventoryAuthority.serializeState(state: any): any
	if snapshotSerializer then
		return snapshotSerializer(state)
	end

	return nil
end

return InventoryAuthority
