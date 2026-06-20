--!strict

local InventoryGrid = {}

export type ItemSize = {
	width: number,
	height: number,
}

export type PackedItem = {
	itemId: string,
	x: number,
	y: number,
	width: number,
	height: number,
}

local DEFAULT_SIZE: ItemSize = { width = 1, height = 1 }

local CATEGORY_DEFAULTS: {[string]: ItemSize} = {
	mag = { width = 1, height = 2 },
	med = { width = 1, height = 2 },
	keycard = { width = 1, height = 1 },
	loot = { width = 1, height = 1 },
	ammo = { width = 1, height = 1 },
	gun = { width = 5, height = 2 },
	pistol = { width = 2, height = 2 },
	melee = { width = 1, height = 2 },
}

local TEMPLATE_DEFAULTS: {[string]: ItemSize} = {
	intel_folder_1 = { width = 2, height = 2 },
}

local function sanitizeDimension(value: any, fallback: number): number
	if typeof(value) ~= "number" then
		return fallback
	end

	return math.max(1, math.floor(value))
end

function InventoryGrid.getItemSize(item: any): ItemSize
	local baseSize = InventoryGrid.getBaseItemSize(item)
	if typeof(item) == "table" and item.inventoryRotated == true then
		return {
			width = baseSize.height,
			height = baseSize.width,
		}
	end

	return baseSize
end

function InventoryGrid.getBaseItemSize(item: any): ItemSize
	if typeof(item) ~= "table" then
		return DEFAULT_SIZE
	end

	local rawSize = item.inventorySize
	if typeof(rawSize) == "table" then
		return {
			width = sanitizeDimension(rawSize.width, DEFAULT_SIZE.width),
			height = sanitizeDimension(rawSize.height, DEFAULT_SIZE.height),
		}
	end

	local state = item.state
	if typeof(state) == "table" and typeof(state.inventorySize) == "table" then
		return {
			width = sanitizeDimension(state.inventorySize.width, DEFAULT_SIZE.width),
			height = sanitizeDimension(state.inventorySize.height, DEFAULT_SIZE.height),
		}
	end

	local templateId = item.templateId
	if typeof(templateId) == "string" and TEMPLATE_DEFAULTS[templateId] then
		return TEMPLATE_DEFAULTS[templateId]
	end

	local category = item.category
	if typeof(category) == "string" and CATEGORY_DEFAULTS[category] then
		return CATEGORY_DEFAULTS[category]
	end

	return DEFAULT_SIZE
end

function InventoryGrid.getItemArea(item: any): number
	local size = InventoryGrid.getItemSize(item)
	return size.width * size.height
end

function InventoryGrid.countUsedUnits(itemIds: {string?}, itemsById: {[string]: any}?): number
	local used = 0
	if typeof(itemIds) ~= "table" then
		return used
	end

	for _, itemId in pairs(itemIds) do
		if typeof(itemId) == "string" and itemId ~= "" then
			local item = if itemsById then itemsById[itemId] else nil
			used += InventoryGrid.getItemArea(item)
		end
	end

	return used
end

function InventoryGrid.getContainerColumns(capacity: number, containerName: string?): number
	if containerName == "rig" then
		return 4
	end
	if containerName == "backpack" then
		return 4
	end
	if containerName == "stash" then
		return 10
	end

	return math.max(1, math.min(10, math.ceil(math.sqrt(math.max(1, capacity)))))
end

local function canPlace(occupied: {[number]: boolean}, columns: number, rows: number, x: number, y: number, width: number, height: number): boolean
	if x + width - 1 > columns or y + height - 1 > rows then
		return false
	end

	for yy = y, y + height - 1 do
		for xx = x, x + width - 1 do
			local key = (yy - 1) * columns + xx
			if occupied[key] then
				return false
			end
		end
	end

	return true
end

local function markOccupied(occupied: {[number]: boolean}, columns: number, x: number, y: number, width: number, height: number)
	for yy = y, y + height - 1 do
		for xx = x, x + width - 1 do
			occupied[(yy - 1) * columns + xx] = true
		end
	end
end

local function indexToCell(index: number, columns: number): (number, number)
	return ((index - 1) % columns) + 1, math.floor((index - 1) / columns) + 1
end

function InventoryGrid.canFitAt(
	itemIds: {string?},
	itemsById: {[string]: any}?,
	capacity: number,
	containerName: string?,
	item: any,
	anchorIndex: number,
	ignoreItemId: string?
): boolean
	if typeof(anchorIndex) ~= "number" then
		return false
	end

	local columns = InventoryGrid.getContainerColumns(capacity, containerName)
	local rows = math.max(1, math.ceil(math.max(1, capacity) / columns))
	local requestedIndex = math.floor(anchorIndex)
	if requestedIndex < 1 or requestedIndex > capacity then
		return false
	end

	local occupied: {[number]: boolean} = {}
	if typeof(itemIds) == "table" then
		for slotIndex = 1, capacity do
			local itemId = itemIds[slotIndex]
			if typeof(itemId) == "string" and itemId ~= "" and itemId ~= ignoreItemId then
				local existing = if itemsById then itemsById[itemId] else nil
				local size = InventoryGrid.getItemSize(existing)
				local x, y = indexToCell(slotIndex, columns)
				if canPlace(occupied, columns, rows, x, y, size.width, size.height) then
					markOccupied(occupied, columns, x, y, size.width, size.height)
				else
					return false
				end
			end
		end
	end

	local size = InventoryGrid.getItemSize(item)
	local x, y = indexToCell(requestedIndex, columns)
	return canPlace(occupied, columns, rows, x, y, size.width, size.height)
end

function InventoryGrid.findFirstFit(
	itemIds: {string?},
	itemsById: {[string]: any}?,
	capacity: number,
	containerName: string?,
	item: any,
	ignoreItemId: string?
): number?
	for slotIndex = 1, capacity do
		if InventoryGrid.canFitAt(itemIds, itemsById, capacity, containerName, item, slotIndex, ignoreItemId) then
			return slotIndex
		end
	end

	return nil
end

function InventoryGrid.pack(itemIds: {string?}, itemsById: {[string]: any}?, capacity: number, containerName: string?): ({PackedItem}, {[number]: boolean}, number, number)
	local columns = InventoryGrid.getContainerColumns(capacity, containerName)
	local rows = math.max(1, math.ceil(math.max(1, capacity) / columns))
	local occupied: {[number]: boolean} = {}
	local packed: {PackedItem} = {}

	if typeof(itemIds) ~= "table" then
		return packed, occupied, columns, rows
	end

	for slotIndex = 1, capacity do
		local itemId = itemIds[slotIndex]
		if typeof(itemId) == "string" and itemId ~= "" then
			local item = if itemsById then itemsById[itemId] else nil
			local size = InventoryGrid.getItemSize(item)
			local placed = false
			local requestedX, requestedY = indexToCell(slotIndex, columns)

			if canPlace(occupied, columns, rows, requestedX, requestedY, size.width, size.height) then
				markOccupied(occupied, columns, requestedX, requestedY, size.width, size.height)
				table.insert(packed, {
					itemId = itemId,
					x = requestedX,
					y = requestedY,
					width = size.width,
					height = size.height,
				})
				placed = true
			end

			if not placed then
				for y = 1, rows do
					for x = 1, columns do
						if canPlace(occupied, columns, rows, x, y, size.width, size.height) then
							markOccupied(occupied, columns, x, y, size.width, size.height)
							table.insert(packed, {
								itemId = itemId,
								x = x,
								y = y,
								width = size.width,
								height = size.height,
							})
							placed = true
							break
						end
					end
					if placed then
						break
					end
				end
			end
		end
	end

	return packed, occupied, columns, rows
end

function InventoryGrid.canFitItem(itemIds: {string?}, itemsById: {[string]: any}?, capacity: number, containerName: string?, item: any): boolean
	return InventoryGrid.findFirstFit(itemIds, itemsById, capacity, containerName, item, nil) ~= nil
end

function InventoryGrid.placeItem(
	itemIds: {string?},
	itemsById: {[string]: any}?,
	capacity: number,
	containerName: string?,
	item: any,
	anchorIndex: number?,
	ignoreItemId: string?
): number?
	if anchorIndex ~= nil then
		local requestedIndex = math.floor(anchorIndex)
		if InventoryGrid.canFitAt(itemIds, itemsById, capacity, containerName, item, requestedIndex, ignoreItemId) then
			return requestedIndex
		end
		return nil
	end

	return InventoryGrid.findFirstFit(itemIds, itemsById, capacity, containerName, item, ignoreItemId)
end

function InventoryGrid.compactItemIds(itemIds: {string?}, itemsById: {[string]: any}?, capacity: number, containerName: string?): {string?}
	local out = table.create(capacity)
	if typeof(itemIds) == "table" then
		for slotIndex = 1, capacity do
			local itemId = itemIds[slotIndex]
			if typeof(itemId) == "string" and itemId ~= "" then
				local item = if itemsById then itemsById[itemId] else nil
				local destination = InventoryGrid.placeItem(out, itemsById, capacity, containerName, item, slotIndex, nil)
					or InventoryGrid.placeItem(out, itemsById, capacity, containerName, item, nil, nil)
				if destination then
					out[destination] = itemId
				end
			end
		end
	end

	return out
end

return InventoryGrid
