--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))

local InventoryStore = require(script.Parent.Parent.state.InventoryStore)

local player = Players.LocalPlayer

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


local function itemLabel(snapshot: any, itemId: string?): string
	if not snapshot or not itemId then
		return "[Empty]"
	end

	local item = snapshot.itemsById[itemId]
	if not item then
		return "[Missing]"
	end

	if item.category == "mag" then
		return string.format("%s (%d/%d)", item.templateId, item.ammo or 0, item.capacity or 0)
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

local function listCard(title: string, lines: {string}, position: UDim2)
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
		Size = UDim2.fromOffset(340, 220),
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
	local timedCheckMagText = useTimedCheckMagText(snapshot)

	local hpText = string.format("HP %d/%d", math.floor(health + 0.5), math.floor(maxHealth + 0.5))

	local hotbarItemIds: {string?} = { nil, nil, nil, nil, nil }
	local equippedIndex = 0
	local ammoText = "AMMO -/-"

	local reloadStatusText = ""
	if snapshot and snapshot.isReloading then
		reloadStatusText = "Reloading..."
	elseif timedCheckMagText ~= "" then
		reloadStatusText = timedCheckMagText
	end

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
	else
		local weaponRows = {
			string.format("PrimaryA: %s", snapshot and itemLabel(snapshot, snapshot.weaponSlots.PrimaryA) or "[Empty]"),
			string.format("PrimaryB: %s", snapshot and itemLabel(snapshot, snapshot.weaponSlots.PrimaryB) or "[Empty]"),
			string.format("Pistol:   %s", snapshot and itemLabel(snapshot, snapshot.weaponSlots.Pistol) or "[Empty]"),
			string.format("Melee:    %s", snapshot and itemLabel(snapshot, snapshot.weaponSlots.Melee) or "[Empty]"),
			string.format("Equipped: %s", snapshot and (snapshot.equippedSlot or "None") or "None"),
		}

		local rigRows: {string} = {}
		local backpackRows: {string} = {}

		if snapshot then
			for i, itemId in ipairs(snapshot.rig.itemIds) do
				rigRows[i] = itemLabel(snapshot, itemId)
			end
			for i, itemId in ipairs(snapshot.backpack.itemIds) do
				backpackRows[i] = itemLabel(snapshot, itemId)
			end
		end

		if #rigRows == 0 then rigRows[1] = "[Empty]" end
		if #backpackRows == 0 then backpackRows[1] = "[Empty]" end

		rootChildren.InventoryRoot = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(720, 520),
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
				Text = "Inventory (Tab to Close)",
				Font = Enum.Font.GothamBold,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromRGB(255, 225, 130),
			}),
			Weapons = listCard("Weapon Slots", weaponRows, UDim2.fromOffset(16, 44)),
			Rig = listCard("Rig", rigRows, UDim2.fromOffset(364, 44)),
			Backpack = listCard("Backpack", backpackRows, UDim2.fromOffset(16, 282)),
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
