--!strict

local RaidStore = {}

local changed = Instance.new("BindableEvent")
local state: any = {
	phase = "InRaid",
	currentExtractId = nil,
	extractEndTime = nil,
	raidEndTime = nil,
	playerCanFight = true,
	openBodyId = nil,
	availableExtracts = {},
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
