--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))

local Net = require(ReplicatedStorage.Shared.Net)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)

if not PlaceConfig.isLobbyPlace() then
	return
end

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local continueEvent = remotes:WaitForChild(Net.LobbyPostRaidContinueEventName) :: RemoteEvent

local controls: any = nil
local overlayCameraConn: RBXScriptConnection? = nil
local overlayCameraStart: CFrame? = nil
local overlayAnchorStartPosition: Vector3? = nil

local function getControls()
	if controls then
		return controls
	end

	local playerScripts = player:WaitForChild("PlayerScripts")
	local playerModule = require(playerScripts:WaitForChild("PlayerModule"))
	controls = playerModule:GetControls()
	return controls
end

local function getCameraAnchor(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("Head") :: BasePart?
		or character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function stopOverlayCameraFollow()
	if overlayCameraConn then
		overlayCameraConn:Disconnect()
		overlayCameraConn = nil
	end
	overlayCameraStart = nil
	overlayAnchorStartPosition = nil
end

local function startOverlayCameraFollow()
	stopOverlayCameraFollow()

	local anchor = getCameraAnchor()
	local camera = workspace.CurrentCamera
	if not anchor or not camera then
		return
	end

	overlayCameraStart = camera.CFrame
	overlayAnchorStartPosition = anchor.Position
	overlayCameraConn = RunService.RenderStepped:Connect(function()
		local currentAnchor = getCameraAnchor()
		if not currentAnchor or not camera or not overlayCameraStart or not overlayAnchorStartPosition then
			return
		end

		local delta = currentAnchor.Position - overlayAnchorStartPosition
		local nextCamera = overlayCameraStart + delta
		camera.CFrame = nextCamera
		camera.Focus = nextCamera + nextCamera.LookVector
	end)
end

local function applyPostRaidInputMode(open: boolean)
	local ctl = getControls()
	local camera = workspace.CurrentCamera
	if open then
		ctl:Disable()
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		player.CameraMode = Enum.CameraMode.Classic
		if camera then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		startOverlayCameraFollow()
	else
		ctl:Enable()
		stopOverlayCameraFollow()
		UserInputService.MouseIconEnabled = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
	end
end

local function decodeEliminations(rawValue: any): {string}
	if typeof(rawValue) ~= "string" or rawValue == "" then
		return {}
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(rawValue)
	end)
	if ok and typeof(decoded) == "table" then
		local out = {}
		for _, value in ipairs(decoded) do
			if typeof(value) == "string" then
				table.insert(out, value)
			end
		end
		return out
	end

	return {}
end

local function usePostRaidState()
	local function readState()
		local isOpen = player:GetAttribute("LobbyPostRaidOpen") == true
		return {
			open = isOpen,
			status = player:GetAttribute("LobbyPostRaidStatus"),
			xpEarned = player:GetAttribute("LobbyPostRaidXP") or 0,
			kills = player:GetAttribute("LobbyPostRaidKills") or 0,
			reason = player:GetAttribute("LobbyPostRaidReason"),
			eliminations = decodeEliminations(player:GetAttribute("LobbyPostRaidEliminationsJson")),
		}
	end

	local state, setState = React.useState(readState())

	React.useEffect(function()
		local connections = {
			player:GetAttributeChangedSignal("LobbyPostRaidOpen"):Connect(function()
				setState(readState())
			end),
			player:GetAttributeChangedSignal("LobbyPostRaidStatus"):Connect(function()
				setState(readState())
			end),
			player:GetAttributeChangedSignal("LobbyPostRaidXP"):Connect(function()
				setState(readState())
			end),
			player:GetAttributeChangedSignal("LobbyPostRaidKills"):Connect(function()
				setState(readState())
			end),
			player:GetAttributeChangedSignal("LobbyPostRaidReason"):Connect(function()
				setState(readState())
			end),
			player:GetAttributeChangedSignal("LobbyPostRaidEliminationsJson"):Connect(function()
				setState(readState())
			end),
		}

		return function()
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
		end
	end, {})

	return state
end

local function PostRaidApp()
	local postRaidState = usePostRaidState()

	React.useEffect(function()
		applyPostRaidInputMode(postRaidState.open == true)
		return function()
			applyPostRaidInputMode(false)
		end
	end, { postRaidState.open })

	React.useEffect(function()
		if not postRaidState.open then
			return
		end

		local charConn = player.CharacterAdded:Connect(function()
			task.defer(function()
				applyPostRaidInputMode(true)
			end)
		end)

		local cameraConn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			task.defer(function()
				applyPostRaidInputMode(true)
			end)
		end)

		return function()
			charConn:Disconnect()
			cameraConn:Disconnect()
		end
	end, { postRaidState.open })

	if not postRaidState.open then
		return React.createElement("ScreenGui", {
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
		})
	end

	local eliminationsChildren: {[string]: any} = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	local eliminations = postRaidState.eliminations
	if #eliminations == 0 then
		eliminationsChildren.Empty = React.createElement("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = "No eliminations recorded",
			Font = Enum.Font.Code,
			TextSize = 14,
			TextColor3 = Color3.fromRGB(170, 170, 170),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	else
		for index, entry in ipairs(eliminations) do
			eliminationsChildren["Entry" .. index] = React.createElement("TextLabel", {
				LayoutOrder = index,
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Text = "- " .. entry,
				Font = Enum.Font.Code,
				TextSize = 14,
				TextColor3 = Color3.new(1, 1, 1),
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
	end

	return React.createElement("ScreenGui", {
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
	}, {
		Scrim = React.createElement("Frame", {
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
		}),
		Panel = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(520, 360),
			BackgroundColor3 = Color3.fromRGB(12, 12, 12),
			BackgroundTransparency = 0.06,
			BorderSizePixel = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 12) }),
			Stroke = React.createElement("UIStroke", {
				Thickness = 1,
				Transparency = 0.12,
				Color = Color3.fromRGB(255, 225, 130),
			}),
			Title = React.createElement("TextLabel", {
				Position = UDim2.fromOffset(24, 18),
				Size = UDim2.new(1, -48, 0, 34),
				BackgroundTransparency = 1,
				Text = tostring(postRaidState.status),
				Font = Enum.Font.GothamBlack,
				TextSize = 28,
				TextColor3 = if postRaidState.status == "EXTRACTED"
					then Color3.fromRGB(105, 255, 125)
					elseif postRaidState.status == "KIA"
					then Color3.fromRGB(255, 110, 110)
					else Color3.fromRGB(255, 190, 110),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Stats = React.createElement("TextLabel", {
				Position = UDim2.fromOffset(24, 70),
				Size = UDim2.new(1, -48, 0, 52),
				BackgroundTransparency = 1,
				Text = string.format("XP %d\nKills %d", postRaidState.xpEarned, postRaidState.kills),
				Font = Enum.Font.Code,
				TextSize = 18,
				TextColor3 = Color3.new(1, 1, 1),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),
			Reason = React.createElement("TextLabel", {
				Position = UDim2.fromOffset(24, 128),
				Size = UDim2.new(1, -48, 0, 22),
				BackgroundTransparency = 1,
				Text = tostring(postRaidState.reason or ""),
				Font = Enum.Font.Gotham,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(205, 205, 205),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			ElimTitle = React.createElement("TextLabel", {
				Position = UDim2.fromOffset(24, 166),
				Size = UDim2.new(1, -48, 0, 22),
				BackgroundTransparency = 1,
				Text = "Eliminations",
				Font = Enum.Font.GothamBold,
				TextSize = 16,
				TextColor3 = Color3.fromRGB(255, 225, 130),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Elims = React.createElement("Frame", {
				Position = UDim2.fromOffset(24, 194),
				Size = UDim2.new(1, -48, 0, 92),
				BackgroundTransparency = 1,
			}, eliminationsChildren),
			Continue = React.createElement("TextButton", {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -24, 1, -20),
				Size = UDim2.fromOffset(160, 42),
				BackgroundColor3 = Color3.fromRGB(28, 28, 28),
				BorderSizePixel = 0,
				Text = "Continue",
				Font = Enum.Font.GothamBold,
				TextSize = 16,
				TextColor3 = Color3.fromRGB(255, 225, 130),
				[React.Event.Activated] = function()
					continueEvent:FireServer()
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.1,
					Color = Color3.fromRGB(255, 225, 130),
				}),
			}),
		}),
	})
end

local playerGui = player:WaitForChild("PlayerGui")
local rootGui = Instance.new("Folder")
rootGui.Name = "_PostRaidUIRoot"
rootGui.Parent = playerGui

local root = ReactRoblox.createRoot(rootGui)
root:render(React.createElement(PostRaidApp))
