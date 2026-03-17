--!strict

local RaidStore = {}

local changed = Instance.new("BindableEvent")
local state: any = {
	phase = "LoadingRaid",
	raidLoadPhase = "InitializingRaid",
	currentExtractId = nil,
	extractEndTime = nil,
	raidEndTime = nil,
	playerCanFight = false,
	openBodyId = nil,
	availableExtracts = {},
	worldStatus = nil,
	partyMembers = {},
	readyDeadline = nil,
}

function RaidStore.setState(nextState: any)
	state = nextState
	changed:Fire(nextState)
end

function RaidStore.getState(): any
	return state
end

function RaidStore.changedSignal(): RBXScriptSignal
	return changed.Event
end

return RaidStore
