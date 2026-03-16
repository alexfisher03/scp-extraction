--!strict

local BodyLootStore = {}

local changed = Instance.new("BindableEvent")
local snapshot: any = nil

function BodyLootStore.setSnapshot(nextSnapshot: any)
	snapshot = nextSnapshot
	changed:Fire(nextSnapshot)
end

function BodyLootStore.clear()
	BodyLootStore.setSnapshot(nil)
end

function BodyLootStore.getSnapshot(): any
	return snapshot
end

function BodyLootStore.changedSignal(): RBXScriptSignal
	return changed.Event
end

return BodyLootStore
