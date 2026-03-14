--!strict

local LootPromptStore = {}

export type PromptState = {
	model: Model?,
	templateId: string?,
	displayName: string?,
}

local changed = Instance.new("BindableEvent")
local state: PromptState = {
	model = nil,
	templateId = nil,
	displayName = nil,
}

function LootPromptStore.setPrompt(nextState: PromptState)
	state = nextState
	changed:Fire(nextState)
end

function LootPromptStore.clear()
	LootPromptStore.setPrompt({
		model = nil,
		templateId = nil,
		displayName = nil,
	})
end

function LootPromptStore.getPrompt(): PromptState
	return state
end

function LootPromptStore.changedSignal(): RBXScriptSignal
	return changed.Event
end

return LootPromptStore
