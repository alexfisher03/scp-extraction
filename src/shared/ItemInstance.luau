--!strict

local ItemInstance = {}

local function cloneValue(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local out = {}
	for key, nested in pairs(value) do
		out[key] = cloneValue(nested)
	end
	return out
end

function ItemInstance.clone(item: any): any
	if typeof(item) ~= "table" then
		return nil
	end

	return cloneValue(item)
end

function ItemInstance.fromInventoryItem(item: any): any
	if typeof(item) ~= "table" then
		return nil
	end

	return {
		itemId = item.itemId,
		templateId = item.templateId,
		category = item.category,
		origin = if item.origin == "Looted" then "Looted" else "BroughtIn",
		state = {
			locationState = item.locationState,
			stack = item.stack,
			ammo = item.ammo,
			capacity = item.capacity,
			usesRemaining = item.usesRemaining,
			usesMax = item.usesMax,
			attachedMagId = item.attachedMagId,
			acceptedMagTemplateIds = cloneValue(item.acceptedMagTemplateIds),
		},
	}
end

function ItemInstance.toInventoryItem(item: any, locationState: string?): any
	if typeof(item) ~= "table" then
		return nil
	end

	local state = if typeof(item.state) == "table" then item.state else {}
	return {
		itemId = item.itemId,
		templateId = item.templateId,
		category = item.category,
		origin = if item.origin == "Looted" then "Looted" else "BroughtIn",
		locationState = locationState or state.locationState,
		stack = state.stack,
		ammo = state.ammo,
		capacity = state.capacity,
		usesRemaining = state.usesRemaining,
		usesMax = state.usesMax,
		attachedMagId = state.attachedMagId,
		acceptedMagTemplateIds = cloneValue(state.acceptedMagTemplateIds),
	}
end

return ItemInstance
