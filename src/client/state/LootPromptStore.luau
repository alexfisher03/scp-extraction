--!strict

local LootPromptStore = {}

export type PromptState = {
	kind: string?,
	target: Instance?,
	templateId: string?,
	displayName: string?,
	text: string?,
	actionText: string?,
	promptInstance: ProximityPrompt?,
}

local changed = Instance.new("BindableEvent")
local state: PromptState = {
	kind = nil,
	target = nil,
	templateId = nil,
	displayName = nil,
	text = nil,
	actionText = nil,
	promptInstance = nil,
}

function LootPromptStore.setPrompt(nextState: PromptState)
	state = nextState
	changed:Fire(nextState)
end

function LootPromptStore.clear()
	LootPromptStore.setPrompt({
		kind = nil,
		target = nil,
		templateId = nil,
		displayName = nil,
		text = nil,
		actionText = nil,
		promptInstance = nil,
	})
end

function LootPromptStore.getPrompt(): PromptState
	return state
end

function LootPromptStore.changedSignal(): RBXScriptSignal
	return changed.Event
end

return LootPromptStore
