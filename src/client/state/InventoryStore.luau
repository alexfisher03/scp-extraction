--!strict

local InventoryStore = {}

local changed = Instance.new("BindableEvent")
local snapshot: any = nil

function InventoryStore.setSnapshot(nextSnapshot: any)
    snapshot = nextSnapshot
    changed:Fire(nextSnapshot)
end

function InventoryStore.getSnapshot(): any
    return snapshot
end

function InventoryStore.changedSignal(): RBXScriptSignal
    return changed.Event
end

return InventoryStore
