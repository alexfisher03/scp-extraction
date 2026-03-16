--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))

local Net = require(ReplicatedStorage.Shared.Net)
local InventoryStore = require(script.Parent.Parent.state.InventoryStore)
local LootPromptStore = require(script.Parent.Parent.state.LootPromptStore)
local RaidStore = require(script.Parent.Parent.state.RaidStore)
local BodyLootStore = require(script.Parent.Parent.state.BodyLootStore)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local moveItemEvent = remotes:WaitForChild(Net.MoveItemRequestEventName) :: RemoteEvent
local dropItemEvent = remotes:WaitForChild(Net.DropItemRequestEventName) :: RemoteEvent
local itemActionEvent = remotes:WaitForChild(Net.ItemActionRequestEventName) :: RemoteEvent
local bodyLootCloseEvent = remotes:WaitForChild(Net.BodyLootCloseRequestEventName) :: RemoteEvent
local bodyLootTransferEvent = remotes:WaitForChild(Net.BodyLootTransferRequestEventName) :: RemoteEvent

type DragState = {
	itemId: string,
	fromContainer: string,
	sourceKind: string,
	bodyId: string?,
}

type HoverState = {
	toContainer: string,
	toIndex: number?,
}

local function useHumanoidHealth()
	local health, setHealth = React.useState(100)
	local maxHealth, setMaxHealth = React.useState(100)

	React.useEffect(function()
		local alive = true
		local healthConn: RBXScriptConnection? = nil
		local diedConn: RBXScriptConnection? = nil
		local charConn: RBXScriptConnection? = nil

		local function disconnectHumanoid()
			if healthConn then healthConn:Disconnect() end
			if diedConn then diedConn:Disconnect() end
			healthConn = nil
			diedConn = nil
		end

		local function bindCharacter(char: Model)
			disconnectHumanoid()

			local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid")
			local humanoid = hum :: Humanoid

			setHealth(humanoid.Health)
			setMaxHealth(humanoid.MaxHealth)

			healthConn = humanoid.HealthChanged:Connect(function(hp)
				if alive then
					setHealth(hp)
				end
			end)

			diedConn = humanoid.Died:Connect(function()
				if alive then
					setHealth(0)
				end
			end)
		end

		if player.Character then
			bindCharacter(player.Character)
		end

		charConn = player.CharacterAdded:Connect(function(char)
			if alive then
				bindCharacter(char)
			end
		end)

		return function()
			alive = false
			if charConn then charConn:Disconnect() end
			disconnectHumanoid()
		end
	end, {})

	return health, maxHealth
end

local function useSnapshot()
	local snapshot, setSnapshot = React.useState(InventoryStore.getSnapshot())

	React.useEffect(function()
		local conn = InventoryStore.changedSignal():Connect(function(nextSnapshot)
			setSnapshot(nextSnapshot)
		end)
		return function()
			conn:Disconnect()
		end
	end, {})

	return snapshot
end

local function useInventoryVisible()
	local visible, setVisible = React.useState(false)

	React.useEffect(function()
		local function sync()
			local v = player:GetAttribute("InventoryVisible")
			setVisible(typeof(v) == "boolean" and v or false)
		end

		local conn = player:GetAttributeChangedSignal("InventoryVisible"):Connect(sync)
		sync()

		return function()
			conn:Disconnect()
		end
	end, {})

	return visible
end

local function useLootPrompt()
	local prompt, setPrompt = React.useState(LootPromptStore.getPrompt())

	React.useEffect(function()
		local conn = LootPromptStore.changedSignal():Connect(function(nextPrompt)
			setPrompt(nextPrompt)
		end)
		return function()
			conn:Disconnect()
		end
	end, {})

	return prompt
end

local function useRaidState()
	local raidState, setRaidState = React.useState(RaidStore.getState())

	React.useEffect(function()
		local conn = RaidStore.changedSignal():Connect(function(nextState)
			setRaidState(nextState)
		end)
		return function()
			conn:Disconnect()
		end
	end, {})

	return raidState
end

local function useBodyLootSnapshot()
	local snapshot, setSnapshot = React.useState(BodyLootStore.getSnapshot())

	React.useEffect(function()
		local conn = BodyLootStore.changedSignal():Connect(function(nextSnapshot)
			setSnapshot(nextSnapshot)
		end)
		return function()
			conn:Disconnect()
		end
	end, {})

	return snapshot
end

local function formatClock(secondsRemaining: number): string
	local clamped = math.max(0, math.floor(secondsRemaining + 0.5))
	local minutes = math.floor(clamped / 60)
	local seconds = clamped % 60
	return string.format("%02d:%02d", minutes, seconds)
end


local function itemLabel(snapshot: any, itemId: string?): string
	if not snapshot or not itemId or itemId == "" then
		return "[Empty]"
	end

	local item = snapshot.itemsById[itemId]
	if not item then
		return "[Missing]"
	end

	if item.category == "mag" then
		return string.format("%s (%d/%d)", item.templateId, item.ammo or 0, item.capacity or 0)
	end

	if item.category == "keycard" then
		return string.format("%s (%d/%d uses)", item.templateId, item.usesRemaining or 0, item.usesMax or 0)
	end

	return item.templateId
end

local function hotbarSlot(index: number, text: string, selected: boolean)
	return React.createElement("Frame", {
		Size = UDim2.fromOffset(56, 56),
		BackgroundTransparency = if selected then 0.35 else 0.7,
		BackgroundColor3 = if selected then Color3.fromRGB(120, 95, 40) else Color3.fromRGB(20, 20, 20),
		BorderSizePixel = 0,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Stroke = React.createElement("UIStroke", {
			Thickness = if selected then 2 else 1,
			Transparency = if selected then 0 else 0.25,
			Color = Color3.fromRGB(255, 225, 130),
		}),
		Key = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.fromOffset(16, 14),
			BackgroundTransparency = 1,
			Text = tostring(index),
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = Color3.fromRGB(220, 220, 220),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Name = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -8, 0, 28),
			BackgroundTransparency = 1,
			Text = text,
			TextWrapped = true,
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextColor3 = Color3.new(1, 1, 1),
		}),
	})
end

local function listCard(title: string, lines: {string}, position: UDim2, size: UDim2)
	local children: {[string]: any} = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for i, line in ipairs(lines) do
		children["Line" .. i] = React.createElement("TextLabel", {
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = line,
			Font = Enum.Font.Code,
			TextSize = 14,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end

	return React.createElement("Frame", {
		AnchorPoint = Vector2.new(0, 0),
		Position = position,
		Size = size,
		BackgroundTransparency = 0.2,
		BackgroundColor3 = Color3.fromRGB(24, 24, 24),
		BorderSizePixel = 0,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Stroke = React.createElement("UIStroke", {
			Thickness = 1,
			Transparency = 0.2,
			Color = Color3.fromRGB(75, 75, 75),
		}),
		Title = React.createElement("TextLabel", {
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.new(1, -20, 0, 22),
			BackgroundTransparency = 1,
			Text = title,
			Font = Enum.Font.GothamBold,
			TextSize = 15,
			TextColor3 = Color3.fromRGB(255, 225, 130),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		List = React.createElement("Frame", {
			Position = UDim2.fromOffset(10, 34),
			Size = UDim2.new(1, -20, 1, -44),
			BackgroundTransparency = 1,
		}, children),
	})
end

local function sendMoveItemRequest(itemId: string, fromContainer: string, toContainer: string, toIndex: number?)
	moveItemEvent:FireServer(itemId, fromContainer, toContainer, toIndex)
end

local function sendDropItemRequest(itemId: string)
	dropItemEvent:FireServer(itemId)
end

local function sendItemActionRequest(itemId: string, actionType: string)
	itemActionEvent:FireServer(itemId, actionType)
end

local function sendBodyLootTransferRequest(bodyId: string, itemId: string, toContainer: string, toIndex: number?)
	bodyLootTransferEvent:FireServer(bodyId, itemId, toContainer, toIndex)
end

local function sendBodyLootCloseRequest()
	bodyLootCloseEvent:FireServer()
end

local function getItemActionLabel(snapshot: any, itemId: string?): string?
	if not snapshot or not itemId then
		return nil
	end

	local item = snapshot.itemsById[itemId]
	if not item then
		return nil
	end

	if item.category == "mag" then
		return "Load"
	end

	if item.category == "med" or item.category == "gun" or item.category == "pistol" or item.category == "melee" then
		return "Use"
	end

	return nil
end

local function containerSlot(
	labelText: string,
	layoutOrder: number,
	isOccupied: boolean,
	isDragging: boolean,
	isHovered: boolean,
	isSelected: boolean,
	onDragStart: (() -> ())?,
	onHoverChanged: ((boolean) -> ())?,
	onRightClick: (() -> ())?
)
	return React.createElement("TextButton", {
		LayoutOrder = layoutOrder,
		Size = UDim2.new(1, 0, 0, 24),
		AutoButtonColor = false,
		BackgroundTransparency = if isSelected then 0.1 elseif isHovered then 0.15 elseif isDragging then 0.25 else 0.45,
		BackgroundColor3 = if isSelected
			then Color3.fromRGB(74, 64, 26)
			elseif isHovered
			then Color3.fromRGB(90, 78, 34)
			elseif isDragging
			then Color3.fromRGB(60, 60, 60)
			else Color3.fromRGB(28, 28, 28),
		BorderSizePixel = 0,
		Text = labelText,
		Font = Enum.Font.Code,
		TextSize = 14,
		TextColor3 = if isOccupied then Color3.new(1, 1, 1) else Color3.fromRGB(145, 145, 145),
		TextXAlignment = Enum.TextXAlignment.Left,
		[React.Event.MouseEnter] = function()
			if onHoverChanged then
				onHoverChanged(true)
			end
		end,
		[React.Event.MouseLeave] = function()
			if onHoverChanged then
				onHoverChanged(false)
			end
		end,
		[React.Event.MouseButton1Down] = function()
			if onDragStart then
				onDragStart()
			end
		end,
		[React.Event.MouseButton2Click] = function()
			if onRightClick then
				onRightClick()
			end
		end,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Padding = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
		Stroke = React.createElement("UIStroke", {
			Thickness = if isSelected or isHovered then 1.5 else 1,
			Transparency = if isSelected or isHovered then 0 else 0.45,
			Color = if isSelected or isHovered then Color3.fromRGB(255, 225, 130) else Color3.fromRGB(90, 90, 90),
		}),
	})
end

local function containerCard(
	title: string,
	containerName: string,
	snapshot: any,
	position: UDim2,
	size: UDim2,
	dragState: DragState?,
	hoverState: HoverState?,
	selectedItemId: string?,
	setHoverState: (HoverState?) -> (),
	setDragState: (DragState?) -> (),
	openContextMenuForItem: (string) -> ()
)
	local container = snapshot and snapshot[containerName] or nil
	local capacity = if container then container.capacity else 0
	local itemIds = if container then container.itemIds else {}

	local children: {[string]: any} = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for slotIndex = 1, capacity do
		local itemId = itemIds[slotIndex]
		if itemId == "" then
			itemId = nil
		end
		local isOccupied = itemId ~= nil
		local isHovered = hoverState ~= nil
			and hoverState.toContainer == containerName
			and hoverState.toIndex == slotIndex
		local isDragging = dragState ~= nil and dragState.itemId == itemId

		children["Slot" .. slotIndex] = containerSlot(
			if isOccupied then itemLabel(snapshot, itemId) else string.format("[%d] Empty", slotIndex),
			slotIndex,
			isOccupied,
			isDragging,
			isHovered,
			selectedItemId ~= nil and selectedItemId == itemId,
			if isOccupied then function()
				setDragState({
					itemId = itemId :: string,
					fromContainer = containerName,
					sourceKind = "player",
					bodyId = nil,
				})
				setHoverState({
					toContainer = containerName,
					toIndex = slotIndex,
				})
			end else nil,
			if dragState then function(isInside)
				if isInside then
					setHoverState({
						toContainer = containerName,
						toIndex = slotIndex,
					})
				elseif isHovered then
					setHoverState(nil)
				end
			end else nil,
			if isOccupied then function()
				openContextMenuForItem(itemId :: string)
			end else nil
		)
	end

	return React.createElement("Frame", {
		AnchorPoint = Vector2.new(0, 0),
		Position = position,
		Size = size,
		BackgroundTransparency = 0.2,
		BackgroundColor3 = Color3.fromRGB(24, 24, 24),
		BorderSizePixel = 0,
		[React.Event.MouseEnter] = function()
			if dragState then
				setHoverState({
					toContainer = containerName,
					toIndex = nil,
				})
			end
		end,
		[React.Event.MouseLeave] = function()
			if hoverState ~= nil and hoverState.toContainer == containerName and hoverState.toIndex == nil then
				setHoverState(nil)
			end
		end,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Stroke = React.createElement("UIStroke", {
			Thickness = 1,
			Transparency = 0.2,
			Color = Color3.fromRGB(75, 75, 75),
		}),
		Title = React.createElement("TextLabel", {
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.new(1, -20, 0, 22),
			BackgroundTransparency = 1,
			Text = title,
			Font = Enum.Font.GothamBold,
			TextSize = 15,
			TextColor3 = Color3.fromRGB(255, 225, 130),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		List = React.createElement("ScrollingFrame", {
			Position = UDim2.fromOffset(10, 34),
			Size = UDim2.new(1, -20, 1, -44),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(0, 0, 0, math.max(0, capacity * 30)),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = Color3.fromRGB(110, 110, 110),
			[React.Event.MouseEnter] = function()
				if dragState then
					setHoverState({
						toContainer = containerName,
						toIndex = nil,
					})
				end
			end,
		}, children),
	})
end

local function bodyContainerCard(
	bodySnapshot: any,
	position: UDim2,
	size: UDim2,
	dragState: DragState?,
	hoverState: HoverState?,
	setHoverState: (HoverState?) -> (),
	setDragState: (DragState?) -> ()
)
	local capacity = bodySnapshot and bodySnapshot.capacity or 0
	local itemIds = bodySnapshot and bodySnapshot.itemIds or {}
	local children: {[string]: any} = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for slotIndex = 1, capacity do
		local itemId = itemIds[slotIndex]
		if itemId == "" then
			itemId = nil
		end

		children["Slot" .. slotIndex] = containerSlot(
			if itemId then itemLabel(bodySnapshot, itemId) else string.format("[%d] Empty", slotIndex),
			slotIndex,
			itemId ~= nil,
			dragState ~= nil and dragState.itemId == itemId and dragState.sourceKind == "body",
			false,
			false,
			if itemId then function()
				setDragState({
					itemId = itemId,
					fromContainer = "body",
					sourceKind = "body",
					bodyId = bodySnapshot.bodyId,
				})
				setHoverState(nil)
			end else nil,
			nil,
			nil
		)
	end

	return React.createElement("Frame", {
		Position = position,
		Size = size,
		BackgroundTransparency = 0.2,
		BackgroundColor3 = Color3.fromRGB(24, 24, 24),
		BorderSizePixel = 0,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Stroke = React.createElement("UIStroke", {
			Thickness = 1,
			Transparency = 0.2,
			Color = Color3.fromRGB(75, 75, 75),
		}),
		Title = React.createElement("TextLabel", {
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.new(1, -20, 0, 22),
			BackgroundTransparency = 1,
			Text = "Body Loot",
			Font = Enum.Font.GothamBold,
			TextSize = 15,
			TextColor3 = Color3.fromRGB(255, 225, 130),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		List = React.createElement("ScrollingFrame", {
			Position = UDim2.fromOffset(10, 34),
			Size = UDim2.new(1, -20, 1, -44),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(0, 0, 0, math.max(0, capacity * 30)),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = Color3.fromRGB(110, 110, 110),
		}, children),
	})
end

local function weaponSlotCard(
	snapshot: any,
	position: UDim2,
	size: UDim2,
	selectedItemId: string?,
	openContextMenuForItem: (string) -> ()
)
	local rows = {
		{ label = "PrimaryA", itemId = snapshot and snapshot.weaponSlots.PrimaryA or nil },
		{ label = "PrimaryB", itemId = snapshot and snapshot.weaponSlots.PrimaryB or nil },
		{ label = "Pistol", itemId = snapshot and snapshot.weaponSlots.Pistol or nil },
		{ label = "Melee", itemId = snapshot and snapshot.weaponSlots.Melee or nil },
	}

	local children: {[string]: any} = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, row in ipairs(rows) do
		local itemId = row.itemId
		if itemId == "" then
			itemId = nil
		end
		children["Slot" .. index] = containerSlot(
			string.format("%s: %s", row.label, itemLabel(snapshot, itemId)),
			index,
			itemId ~= nil,
			false,
			false,
			selectedItemId ~= nil and selectedItemId == itemId,
			nil,
			nil,
			if itemId then function()
				openContextMenuForItem(itemId)
			end else nil
		)
	end

	children.Equipped = React.createElement("TextLabel", {
		LayoutOrder = 99,
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Text = string.format("Equipped: %s", snapshot and (snapshot.equippedSlot or "None") or "None"),
		Font = Enum.Font.Code,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	return React.createElement("Frame", {
		AnchorPoint = Vector2.new(0, 0),
		Position = position,
		Size = size,
		BackgroundTransparency = 0.2,
		BackgroundColor3 = Color3.fromRGB(24, 24, 24),
		BorderSizePixel = 0,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Stroke = React.createElement("UIStroke", {
			Thickness = 1,
			Transparency = 0.2,
			Color = Color3.fromRGB(75, 75, 75),
		}),
		Title = React.createElement("TextLabel", {
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.new(1, -20, 0, 22),
			BackgroundTransparency = 1,
			Text = "Weapon Slots",
			Font = Enum.Font.GothamBold,
			TextSize = 15,
			TextColor3 = Color3.fromRGB(255, 225, 130),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		List = React.createElement("Frame", {
			Position = UDim2.fromOffset(10, 34),
			Size = UDim2.new(1, -20, 1, -44),
			BackgroundTransparency = 1,
		}, children),
	})
end

local function useTimedCheckMagText(snapshot: any)
	local text, setText = React.useState("")
	local seqRef = React.useRef(0)

	React.useEffect(function()
		if not snapshot then return end

		local seq = snapshot.lastCheckMagSeq
		local magText = snapshot.lastCheckMag

		if typeof(seq) ~= "number" then return end
		if seq == seqRef.current then return end
		seqRef.current = seq

		if typeof(magText) == "string" and magText ~= "" then
			local display = "Check: " .. magText
			setText(display)

			local thisSeq = seq
			task.delay(2.0, function()
				if seqRef.current == thisSeq then
					setText("")
				end
			end)
		end
	end, { snapshot })

	return text
end


local function HudApp()
	local health, maxHealth = useHumanoidHealth()
	local snapshot = useSnapshot()
	local inventoryVisible = useInventoryVisible()
	local lootPrompt = useLootPrompt()
	local raidState = useRaidState()
	local bodyLootSnapshot = useBodyLootSnapshot()
	local timedCheckMagText = useTimedCheckMagText(snapshot)
	local dragState, setDragState = React.useState(nil :: DragState?)
	local hoverState, setHoverState = React.useState(nil :: HoverState?)
	local selectedItemId, setSelectedItemId = React.useState(nil :: string?)
	local menuOpen, setMenuOpen = React.useState(false)
	local menuPosition, setMenuPosition = React.useState(UDim2.fromOffset(0, 0))
	local extractsVisible, setExtractsVisible = React.useState(false)

	local hpText = string.format("HP %d/%d", math.floor(health + 0.5), math.floor(maxHealth + 0.5))

	local hotbarItemIds: {string?} = { nil, nil, nil, nil, nil }
	local equippedIndex = 0
	local ammoText = "AMMO -/-"

	if snapshot then
		for i = 1, 5 do
			hotbarItemIds[i] = snapshot.hotbarItemIds and snapshot.hotbarItemIds[i] or nil
		end

		local slot = snapshot.equippedSlot
		if slot == "PrimaryA" then equippedIndex = 1 end
		if slot == "PrimaryB" then equippedIndex = 2 end
		if slot == "Pistol" then equippedIndex = 3 end
		if slot == "Melee" then equippedIndex = 4 end

		local equippedItemId = slot and snapshot.weaponSlots and snapshot.weaponSlots[slot] or nil
		local equippedItem = equippedItemId and snapshot.itemsById[equippedItemId] or nil
		if equippedItem and (equippedItem.category == "gun" or equippedItem.category == "pistol") then
			local magId = equippedItem.attachedMagId
			local mag = magId and snapshot.itemsById[magId] or nil
			if mag then
				ammoText = string.format("AMMO %d/%d", mag.ammo or 0, mag.capacity or 0)
			else
				ammoText = "AMMO 0/0"
			end
		end
	end

	local rootChildren: {[string]: any} = {}

	React.useEffect(function()
		if not inventoryVisible or not dragState then
			return
		end

		local conn = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end

			local activeHover = hoverState
			if activeHover then
				if dragState.sourceKind == "body" and dragState.bodyId then
					sendBodyLootTransferRequest(
						dragState.bodyId,
						dragState.itemId,
						activeHover.toContainer,
						activeHover.toIndex
					)
				else
					sendMoveItemRequest(
						dragState.itemId,
						dragState.fromContainer,
						activeHover.toContainer,
						activeHover.toIndex
					)
				end
			end

			setDragState(nil)
			setHoverState(nil)
		end)

		return function()
			conn:Disconnect()
		end
	end, { inventoryVisible, dragState, hoverState })

	React.useEffect(function()
		if not inventoryVisible then
			setDragState(nil)
			setHoverState(nil)
			setMenuOpen(false)
			setSelectedItemId(nil)
		end
	end, { inventoryVisible })

	React.useEffect(function()
		if dragState then
			setMenuOpen(false)
			setSelectedItemId(nil)
		end
	end, { dragState })

	React.useEffect(function()
		if raidState and raidState.phase == "Extracting" then
			setExtractsVisible(true)
		end
	end, { raidState })

	React.useEffect(function()
		local conn = UserInputService.InputBegan:Connect(function(input, processed)
			if UserInputService:GetFocusedTextBox() then
				return
			end

			if bodyLootSnapshot and input.KeyCode == Enum.KeyCode.Escape then
				sendBodyLootCloseRequest()
				return
			end

			if input.KeyCode == Enum.KeyCode.O then
				setExtractsVisible(function(previous)
					return not previous
				end)
			end
		end)

		return function()
			conn:Disconnect()
		end
	end, {})

	local function openContextMenuForItem(itemId: string)
		local mousePosition = UserInputService:GetMouseLocation()
		local camera = workspace.CurrentCamera
		local viewportSize = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
		local rootTopLeft = Vector2.new(viewportSize.X * 0.175, viewportSize.Y * 0.075)
		local rootSize = Vector2.new(viewportSize.X * 0.65, viewportSize.Y * 0.85)
		local localX = math.clamp(mousePosition.X - rootTopLeft.X + 8, 16, math.max(16, rootSize.X - 166))
		local localY = math.clamp(mousePosition.Y - rootTopLeft.Y + 8, 44, math.max(44, rootSize.Y - 116))
		setSelectedItemId(itemId)
		setMenuPosition(UDim2.fromOffset(localX, localY))
		setMenuOpen(true)
		setDragState(nil)
		setHoverState(nil)
	end

	local function closeContextMenu()
		setMenuOpen(false)
		setSelectedItemId(nil)
	end

	local extractCountdownText = ""
	if raidState and raidState.phase == "Extracting" and typeof(raidState.extractEndTime) == "number" then
		local remaining = math.max(0, raidState.extractEndTime - workspace:GetServerTimeNow())
		extractCountdownText = string.format("Extracting in %.1f", remaining)
	end

	local raidTimerText = "Raid --:--"
	if raidState and typeof(raidState.raidEndTime) == "number" then
		raidTimerText = "Raid " .. formatClock(raidState.raidEndTime - workspace:GetServerTimeNow())
	end

	if not inventoryVisible then
		local barChildren: {[string]: any} = {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 8),
			}),
		}

		for i = 1, 5 do
			barChildren["Slot" .. i] = hotbarSlot(
				i,
				itemLabel(snapshot, hotbarItemIds[i]),
				equippedIndex == i
			)
		end

		rootChildren.Health = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 16, 1, -16),
			Size = UDim2.fromOffset(240, 36),
			BackgroundTransparency = 0.45,
			BackgroundColor3 = Color3.fromRGB(18, 18, 18),
			BorderSizePixel = 0,
			Text = hpText,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.new(1, 1, 1),
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Padding = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
		})

		rootChildren.Ammo = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 16, 1, -56),
			Size = UDim2.fromOffset(240, 32),
			BackgroundTransparency = 1,
			Text = ammoText,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(220, 220, 220),
		})

		rootChildren.ReloadStatus = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 16, 1, -80),
			Size = UDim2.fromOffset(260, 22),
			BackgroundTransparency = 1,
			Text = if snapshot and snapshot.isReloading
				then "Reloading..."
				elseif timedCheckMagText ~= ""
				then timedCheckMagText
				else "",
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(255, 210, 120),
		})



		rootChildren.Hotbar = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -16),
			Size = UDim2.fromOffset(5 * 56 + 4 * 8, 56),
			BackgroundTransparency = 1,
		}, barChildren)

		if raidState and raidState.phase ~= "Stash" then
			rootChildren.RaidTimerButton = React.createElement("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -16, 0, 16),
				Size = UDim2.fromOffset(180, 38),
				BackgroundTransparency = 0.2,
				BackgroundColor3 = Color3.fromRGB(18, 18, 18),
				BorderSizePixel = 0,
				Text = raidTimerText,
				Font = Enum.Font.GothamBold,
				TextSize = 16,
				TextColor3 = Color3.new(1, 1, 1),
				[React.Event.Activated] = function()
					setExtractsVisible(function(previous)
						return not previous
					end)
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.15,
					Color = Color3.fromRGB(255, 225, 130),
				}),
			})

			if extractsVisible then
				local extractChildren: {[string]: any} = {
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				}

				local availableExtracts = if raidState.availableExtracts then raidState.availableExtracts else {}
				for index, extractName in ipairs(availableExtracts) do
					local isCurrentExtract = raidState.currentExtractId == extractName
					extractChildren["Extract" .. index] = React.createElement("TextLabel", {
						LayoutOrder = index,
						Size = UDim2.new(1, 0, 0, 20),
						BackgroundTransparency = 1,
						Text = extractName,
						Font = Enum.Font.GothamMedium,
						TextSize = 13,
						TextColor3 = if isCurrentExtract then Color3.fromRGB(105, 255, 125) else Color3.new(1, 1, 1),
						TextXAlignment = Enum.TextXAlignment.Left,
					})
				end

				rootChildren.ExtractList = React.createElement("Frame", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -16, 0, 60),
					Size = UDim2.fromOffset(220, math.max(80, 22 + #availableExtracts * 26)),
					BackgroundTransparency = 0.1,
					BackgroundColor3 = Color3.fromRGB(18, 18, 18),
					BorderSizePixel = 0,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
					Stroke = React.createElement("UIStroke", {
						Thickness = 1,
						Transparency = 0.15,
						Color = Color3.fromRGB(255, 225, 130),
					}),
					Title = React.createElement("TextLabel", {
						Position = UDim2.fromOffset(10, 8),
						Size = UDim2.new(1, -20, 0, 18),
						BackgroundTransparency = 1,
						Text = "Open Extracts",
						Font = Enum.Font.GothamBold,
						TextSize = 14,
						TextColor3 = Color3.fromRGB(255, 225, 130),
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					List = React.createElement("Frame", {
						Position = UDim2.fromOffset(10, 30),
						Size = UDim2.new(1, -20, 1, -38),
						BackgroundTransparency = 1,
					}, extractChildren),
				})
			end
		end

		if extractCountdownText ~= "" then
			rootChildren.ExtractPrompt = React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.66),
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundTransparency = 0.2,
				BackgroundColor3 = Color3.fromRGB(18, 18, 18),
				BorderSizePixel = 0,
				Text = extractCountdownText,
				Font = Enum.Font.GothamBold,
				TextSize = 20,
				TextColor3 = Color3.new(1, 1, 1),
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.15,
					Color = Color3.fromRGB(255, 225, 130),
				}),
				Padding = React.createElement("UIPadding", {
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 8),
				}),
			})
		elseif lootPrompt.text then
			rootChildren.LootPrompt = React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.56),
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundTransparency = 0.2,
				BackgroundColor3 = Color3.fromRGB(18, 18, 18),
				BorderSizePixel = 0,
				Text = lootPrompt.text,
				Font = Enum.Font.GothamBold,
				TextSize = 20,
				TextColor3 = Color3.new(1, 1, 1),
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.15,
					Color = Color3.fromRGB(255, 225, 130),
				}),
				Padding = React.createElement("UIPadding", {
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 8),
				}),
			})
		end
	else
		local inventoryPanel = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.65, 0.85),
			BackgroundTransparency = 0.12,
			BackgroundColor3 = Color3.fromRGB(12, 12, 12),
			BorderSizePixel = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
			Stroke = React.createElement("UIStroke", {
				Thickness = 1,
				Transparency = 0.25,
				Color = Color3.fromRGB(80, 80, 80),
			}),
			Title = React.createElement("TextLabel", {
				Position = UDim2.fromOffset(16, 10),
				Size = UDim2.new(1, -32, 0, 24),
				BackgroundTransparency = 1,
				Text = if raidState and raidState.phase == "Stash"
					then "Stash Mode"
					elseif bodyLootSnapshot
					then "Inventory (Body Loot Open)"
					else "Inventory (Tab to Close, drag between Rig and Backpack)",
				Font = Enum.Font.GothamBold,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromRGB(255, 225, 130),
			}),
			DragHint = React.createElement("TextLabel", {
				Position = UDim2.new(0, 16, 1, -28),
				Size = UDim2.new(1, -32, 0, 18),
				BackgroundTransparency = 1,
				Text = if dragState then ("Dragging: " .. itemLabel(if dragState.sourceKind == "body" then bodyLootSnapshot else snapshot, dragState.itemId)) else "Drag an item to a slot in Rig or Backpack.",
				Font = Enum.Font.Gotham,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = if dragState then Color3.fromRGB(255, 225, 130) else Color3.fromRGB(180, 180, 180),
			}),
			ContextDismiss = if menuOpen then React.createElement("TextButton", {
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 3,
				[React.Event.Activated] = function()
					closeContextMenu()
				end,
			}) else nil,
			ContextMenu = if menuOpen and selectedItemId then React.createElement("Frame", {
				Position = menuPosition,
				Size = UDim2.fromOffset(150, 110),
				BackgroundColor3 = Color3.fromRGB(20, 20, 20),
				BackgroundTransparency = 0.05,
				BorderSizePixel = 0,
				ZIndex = 4,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.1,
					Color = Color3.fromRGB(255, 225, 130),
				}),
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, 6),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Padding = React.createElement("UIPadding", {
					PaddingLeft = UDim.new(0, 8),
					PaddingRight = UDim.new(0, 8),
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 8),
				}),
				Action = getItemActionLabel(snapshot, selectedItemId) and React.createElement("TextButton", {
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 26),
					BackgroundColor3 = Color3.fromRGB(42, 42, 42),
					BorderSizePixel = 0,
					Text = getItemActionLabel(snapshot, selectedItemId),
					Font = Enum.Font.GothamMedium,
					TextSize = 13,
					TextColor3 = Color3.new(1, 1, 1),
					ZIndex = 5,
					[React.Event.Activated] = function()
						local actionLabel = getItemActionLabel(snapshot, selectedItemId)
						if actionLabel then
							sendItemActionRequest(selectedItemId, actionLabel)
						end
						closeContextMenu()
					end,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
				}) or nil,
				Drop = React.createElement("TextButton", {
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 26),
					BackgroundColor3 = Color3.fromRGB(42, 42, 42),
					BorderSizePixel = 0,
					Text = "Drop",
					Font = Enum.Font.GothamMedium,
					TextSize = 13,
					TextColor3 = Color3.new(1, 1, 1),
					ZIndex = 5,
					[React.Event.Activated] = function()
						sendDropItemRequest(selectedItemId)
						closeContextMenu()
					end,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
				}),
				Split = React.createElement("TextLabel", {
					LayoutOrder = 3,
					Size = UDim2.new(1, 0, 0, 20),
					BackgroundTransparency = 1,
					Text = "Split Stack (Unavailable)",
					Font = Enum.Font.Gotham,
					TextSize = 11,
					TextColor3 = Color3.fromRGB(130, 130, 130),
					ZIndex = 5,
				}),
			}) else nil,
			Weapons = weaponSlotCard(
				snapshot,
				UDim2.new(0, 16, 0, 44),
				UDim2.new(if bodyLootSnapshot then 0.42 else 0.47, -24, 0.30, -8),
				selectedItemId,
				openContextMenuForItem
			),
			Rig = containerCard(
				"Rig",
				"rig",
				snapshot,
				UDim2.new(if bodyLootSnapshot then 0 else 0.5, if bodyLootSnapshot then 16 else 8, if bodyLootSnapshot then 0.30 else 0, if bodyLootSnapshot then 52 else 44),
				UDim2.new(if bodyLootSnapshot then 0.42 else 0.5, -24, if bodyLootSnapshot then 0.28 else 0.58, if bodyLootSnapshot then -8 else -56),
				dragState,
				hoverState,
				selectedItemId,
				setHoverState,
				setDragState,
				openContextMenuForItem
			),
			Backpack = containerCard(
				"Backpack",
				"backpack",
				snapshot,
				UDim2.new(0, 16, if bodyLootSnapshot then 0.58 else 0.42, 52),
				UDim2.new(if bodyLootSnapshot then 0.42 else 0.47, -24, if bodyLootSnapshot then 0.36 else 0.58, if bodyLootSnapshot then -80 else -80),
				dragState,
				hoverState,
				selectedItemId,
				setHoverState,
				setDragState,
				openContextMenuForItem
			),
			BodyLoot = if bodyLootSnapshot then bodyContainerCard(
				bodyLootSnapshot,
				UDim2.new(0.44, 8, 0, 44),
				UDim2.new(0.56, -24, 0.88, -72),
				dragState,
				hoverState,
				setHoverState,
				setDragState
			) else nil,
		})

		rootChildren.InventoryShell = React.createElement("Frame", {
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, {
			OutsideTop = if bodyLootSnapshot then React.createElement("TextButton", {
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.new(1, 0, 0.075, 0),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				[React.Event.Activated] = function()
					sendBodyLootCloseRequest()
				end,
			}) else nil,
			OutsideBottom = if bodyLootSnapshot then React.createElement("TextButton", {
				Position = UDim2.new(0, 0, 0.925, 0),
				Size = UDim2.new(1, 0, 0.075, 0),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				[React.Event.Activated] = function()
					sendBodyLootCloseRequest()
				end,
			}) else nil,
			OutsideLeft = if bodyLootSnapshot then React.createElement("TextButton", {
				Position = UDim2.new(0, 0, 0.075, 0),
				Size = UDim2.new(0.175, 0, 0.85, 0),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				[React.Event.Activated] = function()
					sendBodyLootCloseRequest()
				end,
			}) else nil,
			OutsideRight = if bodyLootSnapshot then React.createElement("TextButton", {
				Position = UDim2.new(0.825, 0, 0.075, 0),
				Size = UDim2.new(0.175, 0, 0.85, 0),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				[React.Event.Activated] = function()
					sendBodyLootCloseRequest()
				end,
			}) else nil,
			InventoryRoot = inventoryPanel,
		})
	end

	return React.createElement("ScreenGui", {
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
	}, rootChildren)
end

local function mount()
	local playerGui = player:WaitForChild("PlayerGui")
	local rootGui = Instance.new("Folder")
	rootGui.Name = "_UIRoot"
	rootGui.Parent = playerGui

	local root = ReactRoblox.createRoot(rootGui)
	root:render(React.createElement(HudApp))
end

mount()
