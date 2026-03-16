--!strict

local RaidAuthority = {}

type RaidState = {
	phase: string,
	currentExtractId: string?,
	extractEndTime: number?,
	raidEndTime: number?,
	playerCanFight: boolean,
	openBodyId: string?,
	availableExtracts: {string}?,
}

type BodyState = {
	bodyId: string,
	ownerUserId: number,
	model: Model,
	capacity: number,
	itemIds: {string?},
	itemsById: {[string]: any},
}

local raidStateByUserId: {[number]: RaidState} = {}
local bodiesById: {[string]: BodyState} = {}
local bodyIdByModel: {[Instance]: string} = {}

local raidStateEmitter: ((Player, RaidState) -> ())? = nil
local bodySnapshotEmitter: ((Player, BodyState?) -> ())? = nil

function RaidAuthority.getDefaultState(): RaidState
	return {
		phase = "InRaid",
		currentExtractId = nil,
		extractEndTime = nil,
		raidEndTime = nil,
		playerCanFight = true,
		openBodyId = nil,
		availableExtracts = {},
	}
end

function RaidAuthority.getState(userId: number): RaidState?
	return raidStateByUserId[userId]
end

function RaidAuthority.getOrCreateState(userId: number): RaidState
	local state = raidStateByUserId[userId]
	if state then
		return state
	end

	state = RaidAuthority.getDefaultState()
	raidStateByUserId[userId] = state
	return state
end

function RaidAuthority.setState(userId: number, state: RaidState)
	raidStateByUserId[userId] = state
end

function RaidAuthority.removeState(userId: number)
	raidStateByUserId[userId] = nil
end

function RaidAuthority.isInRaid(userId: number): boolean
	local state = raidStateByUserId[userId]
	return state ~= nil and state.phase == "InRaid"
end

function RaidAuthority.setRaidStateEmitter(emitter: (Player, RaidState) -> ())
	raidStateEmitter = emitter
end

function RaidAuthority.emitRaidState(player: Player, state: RaidState)
	if raidStateEmitter then
		raidStateEmitter(player, state)
	end
end

function RaidAuthority.setBodySnapshotEmitter(emitter: (Player, BodyState?) -> ())
	bodySnapshotEmitter = emitter
end

function RaidAuthority.emitBodySnapshot(player: Player, bodyState: BodyState?)
	if bodySnapshotEmitter then
		bodySnapshotEmitter(player, bodyState)
	end
end

function RaidAuthority.setBody(bodyId: string, bodyState: BodyState)
	bodiesById[bodyId] = bodyState
	bodyIdByModel[bodyState.model] = bodyId
end

function RaidAuthority.getBody(bodyId: string): BodyState?
	return bodiesById[bodyId]
end

function RaidAuthority.getBodyByModel(model: Instance): BodyState?
	local bodyId = bodyIdByModel[model]
	if bodyId then
		return bodiesById[bodyId]
	end

	local ancestor = model:FindFirstAncestorOfClass("Model")
	if ancestor then
		local ancestorBodyId = bodyIdByModel[ancestor]
		if ancestorBodyId then
			return bodiesById[ancestorBodyId]
		end
	end

	return nil
end

function RaidAuthority.removeBody(bodyId: string)
	local bodyState = bodiesById[bodyId]
	if bodyState then
		bodyIdByModel[bodyState.model] = nil
	end
	bodiesById[bodyId] = nil
end

function RaidAuthority.getAllBodies(): {[string]: BodyState}
	return bodiesById
end

return RaidAuthority
