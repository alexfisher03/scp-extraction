--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))

local player = Players.LocalPlayer

local function useHumanoidHealth()
    local health, setHealth = React.useState(100)
    local maxHealth, setMaxHealth = React.useState(100)

    React.useEffect(function()
        local alive = true
        local healthConn: RBXScriptConnection? = nil

        local function bindCharacter(char: Model)
            local humanoid = char:WaitForChild("Humanoid") :: Humanoid
            if not alive then return end

            setMaxHealth(humanoid.MaxHealth)
            setHealth(humanoid.Health)

            healthConn = humanoid.healthChanged:Connect(function(hp)
                if alive then
                    setHealth(hp)
                end
            end)
        end

        if player.Character then
            bindCharacter(player.Character)
        end

        local charConn = player.CharacterAdded:Connect(function(char)
            if healthConn then
                healthConn:Disconnect()
            end
            bindCharacter(char) 
        end)

        return function()
            alive = false
            charConn:Disconnect()
            if healthConn then
                healthConn:Disconnect()
            end
        end
    end, {})

    return health, maxHealth
end

local function HudApp()
    local health, maxHealth = useHumanoidHealth()
    local hpText = string.format("HP: %d / %d", math.floor(health + 0.5), math.floor(maxHealth + 0.5))

    local slots = {}
	for i = 1, 5 do
		slots[i] = React.createElement("Frame", {
			Size = UDim2.fromOffset(52, 52),
			BackgroundTransparency = 0.2,
			BorderSizePixel = 1,
		}, {
			Label = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = tostring(i),
				TextScaled = true,
			}),
		})
	end

    return React.createElement("ScreenGui", {
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
	}, {
		Health = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 16, 1, -16),
			Size = UDim2.fromOffset(220, 28),
			BackgroundTransparency = 0.3,
			Text = hpText,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		Hotbar = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -16),
			Size = UDim2.fromOffset(5 * 56, 56),
			BackgroundTransparency = 1,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 4),
			}),
			S1 = slots[1],
			S2 = slots[2],
			S3 = slots[3],
			S4 = slots[4],
			S5 = slots[5],
		}),
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