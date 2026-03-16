--!strict

local InventoryAuthority = {}

local statesByUserId: {[number]: any} = {}
local snapshotEmitter: ((Player, any) -> ())? = nil

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

return InventoryAuthority
