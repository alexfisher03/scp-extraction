--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))

local player = Players.LocalPlayer

type Connections = {
	healthConn: RBXScriptConnection?,
	diedConn: RBXScriptConnection?,
}

local function useHumanoidHealth()
	local health, setHealth = React.useState(100)
	local maxHealth, setMaxHealth = React.useState(100)

	React.useEffect(function()
		local alive = true
		local conns: Connections = { healthConn = nil, diedConn = nil }

		local function disconnectAll()
			if conns.healthConn then conns.healthConn:Disconnect() end
			if conns.diedConn then conns.diedConn:Disconnect() end
			conns.healthConn = nil
			conns.diedConn = nil
		end

		local function bindCharacter(char: Model)
			disconnectAll()

			local hum = char:WaitForChild("Humanoid") :: Humanoid

			setMaxHealth(hum.MaxHealth)
			setHealth(hum.Health)

			conns.healthConn = hum.HealthChanged:Connect(function(hp)
				if alive then
					setHealth(hp)
				end
			end)

			conns.diedConn = hum.Died:Connect(function()
				if alive then
					setHealth(0)
				end
			end)
		end

		if player.Character then
			bindCharacter(player.Character)
		end

		local charConn = player.CharacterAdded:Connect(function(char)
			if alive then
				bindCharacter(char)
			end
		end)

		return function()
			alive = false
			charConn:Disconnect()
			disconnectAll()
		end
	end, {})

	return health, maxHealth
end

local function Slot(props: { index: number })
	return React.createElement("Frame", {
		Size = UDim2.fromOffset(48, 48),
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
	}, {
		Stroke = React.createElement("UIStroke", {
			Thickness = 1,
			Transparency = 0.35,
		}),
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 6),
		}),
		Label = React.createElement("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = tostring(props.index),
			TextScaled = true,
			TextTransparency = 0.55,
			Font = Enum.Font.GothamMedium,
		}),
	})
end

local function HudApp()
	local health, maxHealth = useHumanoidHealth()
	local hpText = string.format("HP %d/%d", math.floor(health + 0.5), math.floor(maxHealth + 0.5))

	local children = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	}

	for i = 1, 5 do
		children["Slot" .. i] = React.createElement(Slot, { index = i })
	end

	return React.createElement("ScreenGui", {
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
	}, {
		Health = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 16, 1, -16),
			Size = UDim2.fromOffset(180, 26),
			BackgroundTransparency = 0.75,
			BorderSizePixel = 0,
			Text = hpText,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamMedium,
			TextSize = 14,
		}, {
			Stroke = React.createElement("UIStroke", {
				Thickness = 1,
				Transparency = 0.35,
			}),
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 6),
			}),
			Padding = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
		}),

		Hotbar = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -16),
			Size = UDim2.fromOffset(5 * 48 + 4 * 6, 48),
			BackgroundTransparency = 1,
		}, children),
	})
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