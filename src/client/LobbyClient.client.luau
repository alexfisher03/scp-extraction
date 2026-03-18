--!strict

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))

local Net = require(ReplicatedStorage.Shared.Net)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local ClientActionBridge = require(script.Parent.state.ClientActionBridge)
local InventoryStore = require(script.Parent.state.InventoryStore)

print("[LobbyClient] Booting", game.PlaceId, "isLobby=", PlaceConfig.isLobbyPlace(), "hasLobbyFolder=", workspace:FindFirstChild("Lobby") ~= nil)

if not PlaceConfig.isLobbyPlace() then
	print("[LobbyClient] Early return: place is not lobby")
	return
end

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local joinQueueEvent = remotes:WaitForChild(Net.LobbyJoinQueueEventName) :: RemoteEvent
local leaveQueueEvent = remotes:WaitForChild(Net.LobbyLeaveQueueEventName) :: RemoteEvent
local devForceStartEvent = remotes:WaitForChild(Net.LobbyDevForceStartEventName) :: RemoteEvent
local queueStatusEvent = remotes:WaitForChild(Net.LobbyQueueStatusEventName) :: RemoteEvent
local noticeEvent = remotes:WaitForChild(Net.LobbyNoticeEventName) :: RemoteEvent

local controls: any = nil
local terminalOpen = false
local matchStarting = false
local terminalCameraConn: RBXScriptConnection? = nil
local terminalCameraStart: CFrame? = nil
local terminalAnchorStartPosition: Vector3? = nil
local PROMPT_PART_ACTIVATION_DISTANCE = 10
local QUEUE_CANCEL_HOLD_SECONDS = 2

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

local function stopTerminalCameraFollow()
	if terminalCameraConn then
		terminalCameraConn:Disconnect()
		terminalCameraConn = nil
	end
	terminalCameraStart = nil
	terminalAnchorStartPosition = nil
end

local function startTerminalCameraFollow()
	stopTerminalCameraFollow()

	local anchor = getCameraAnchor()
	if not anchor or not camera then
		return
	end

	terminalCameraStart = camera.CFrame
	terminalAnchorStartPosition = anchor.Position

	terminalCameraConn = RunService.RenderStepped:Connect(function()
		local currentAnchor = getCameraAnchor()
		if not currentAnchor or not camera or not terminalCameraStart or not terminalAnchorStartPosition then
			return
		end

		local positionDelta = currentAnchor.Position - terminalAnchorStartPosition
		local targetCameraCFrame = terminalCameraStart + positionDelta
		camera.CFrame = targetCameraCFrame
		camera.Focus = targetCameraCFrame + targetCameraCFrame.LookVector
	end)
end

local function applyTerminalInputMode(open: boolean)
	local ctl = getControls()
	if open then
		ctl:Disable()
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		player.CameraMode = Enum.CameraMode.Classic
		if camera then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		startTerminalCameraFollow()
	else
		ctl:Enable()
		stopTerminalCameraFollow()
		UserInputService.MouseIconEnabled = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
	end
end

local function setTerminalOpen(open: boolean)
	terminalOpen = open
	player:SetAttribute("LobbyTerminalOpen", open)
	applyTerminalInputMode(open)
end

local function setMatchStarting(nextValue: boolean)
	matchStarting = nextValue
	player:SetAttribute("LobbyMatchStarting", nextValue)
	if nextValue then
		setTerminalOpen(false)
	end
end

local function formatWait(secondsValue: number?): string
	if typeof(secondsValue) ~= "number" then
		return "--:--"
	end

	local seconds = math.max(0, math.floor(secondsValue + 0.5))
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function getDeployTerminalPrompt(): ProximityPrompt?
	local lobby = workspace:FindFirstChild("Lobby")
	local interactables = lobby and lobby:FindFirstChild("Interactables")
	local deployTerminal = interactables and interactables:FindFirstChild("DeployTerminal")
	local prompt = deployTerminal and deployTerminal:FindFirstChild("ProximityPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		print("[LobbyClient] Found deploy terminal prompt at startup")
		return prompt
	end

	print("[LobbyClient] Deploy terminal prompt not found at startup")
	return nil
end

local function getDeployTerminalPromptPart(): BasePart?
	local lobby = workspace:FindFirstChild("Lobby")
	local interactables = lobby and lobby:FindFirstChild("Interactables")
	local deployTerminal = interactables and interactables:FindFirstChild("DeployTerminal")
	local promptPart = deployTerminal and deployTerminal:FindFirstChild("PromptPart")
	if promptPart and promptPart:IsA("BasePart") then
		return promptPart
	end

	return nil
end

local function canOpenViaPromptPart(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local promptPart = getDeployTerminalPromptPart()
	if not root or not root:IsA("BasePart") or not promptPart then
		return false
	end

	return (root.Position - promptPart.Position).Magnitude <= PROMPT_PART_ACTIVATION_DISTANCE
end

local function useInventorySnapshot()
	local snapshot, setSnapshot = React.useState(InventoryStore.getSnapshot())

	React.useEffect(function()
		local connection = InventoryStore.changedSignal():Connect(function(nextSnapshot)
			setSnapshot(nextSnapshot)
		end)

		return function()
			connection:Disconnect()
		end
	end, {})

	return snapshot
end

local function lobbyItemLabel(snapshot: any, itemId: string?): string
	if not snapshot or not itemId or itemId == "" then
		return "[Empty]"
	end

	local item = snapshot.itemsById and snapshot.itemsById[itemId] or nil
	if not item then
		return tostring(itemId)
	end

	if typeof(item.templateId) == "string" then
		return item.templateId
	end

	return tostring(itemId)
end

local function countContainerItems(containerData: any): number
	if typeof(containerData) ~= "table" or typeof(containerData.capacity) ~= "number" then
		return 0
	end

	local count = 0
	for slotIndex = 1, containerData.capacity do
		local itemId = containerData.itemIds and containerData.itemIds[slotIndex] or nil
		if typeof(itemId) == "string" and itemId ~= "" then
			count += 1
		end
	end

	return count
end

local function LobbyApp()
	local inventorySnapshot = useInventorySnapshot()
	local queueStatus, setQueueStatus = React.useState({
		position = nil,
		count = 0,
		targetSize = 1,
		estimatedWaitSeconds = nil,
		queued = false,
	})
	local notice, setNotice = React.useState("")
	local open, setOpen = React.useState(false)
	local loadingIntoRaid, setLoadingIntoRaid = React.useState(player:GetAttribute("LobbyMatchStarting") == true)
	local mobileDeployAvailable, setMobileDeployAvailable = React.useState(false)
	local desktopDeployAvailable, setDesktopDeployAvailable = React.useState(false)
	local queueCancelHeld, setQueueCancelHeld = React.useState(false)
	local queueCancelProgress, setQueueCancelProgress = React.useState(0)
	local queueCancelHeldRef = React.useRef(false)
	local queueCancelStartedAtRef = React.useRef(0)
	local queueCancelCompletedRef = React.useRef(false)

	React.useEffect(function()
		print("[LobbyClient] LobbyApp mounted")
		local queueConn = queueStatusEvent.OnClientEvent:Connect(function(nextStatus)
			print("[LobbyClient] Queue status", nextStatus.count, nextStatus.position, nextStatus.queued)
			setQueueStatus(nextStatus)
		end)
		local noticeConn = noticeEvent.OnClientEvent:Connect(function(message)
			print("[LobbyClient] Notice", message)
			local nextMessage = tostring(message)
			if nextMessage == "Loading into raid..." then
				setLoadingIntoRaid(true)
				setOpen(false)
				setMatchStarting(true)
			else
				setNotice(nextMessage)
				setLoadingIntoRaid(false)
				setMatchStarting(false)
			end
			task.delay(4, function()
				setNotice(function(current)
					if current == nextMessage then
						return ""
					end
					return current
				end)
			end)
		end)
		local promptConn: RBXScriptConnection? = nil
		local promptServiceConn: RBXScriptConnection? = nil
		local function bindPrompt(prompt: ProximityPrompt)
			print("[LobbyClient] Binding deploy prompt", prompt:GetFullName())
			if promptConn then
				promptConn:Disconnect()
			end
			promptConn = prompt.Triggered:Connect(function()
				if matchStarting or player:GetAttribute("LobbyPostRaidOpen") == true then
					return
				end
				print("[LobbyClient] Deploy prompt triggered")
				setOpen(true)
				setTerminalOpen(true)
			end)
		end

		local existingPrompt = getDeployTerminalPrompt()
		if existingPrompt then
			bindPrompt(existingPrompt)
		else
			print("[LobbyClient] Waiting for deploy prompt via PromptShown")
			promptServiceConn = ProximityPromptService.PromptShown:Connect(function(prompt)
				local deployPrompt = getDeployTerminalPrompt()
				if deployPrompt and prompt == deployPrompt then
					print("[LobbyClient] PromptShown matched deploy terminal")
					bindPrompt(deployPrompt)
				end
			end)
		end
		local attrConn = player:GetAttributeChangedSignal("LobbyTerminalOpen"):Connect(function()
			local value = player:GetAttribute("LobbyTerminalOpen") == true
			setOpen(value)
		end)
		local matchAttrConn = player:GetAttributeChangedSignal("LobbyMatchStarting"):Connect(function()
			local value = player:GetAttribute("LobbyMatchStarting") == true
			setLoadingIntoRaid(value)
			if value then
				setOpen(false)
			end
		end)
		local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
			if not open
				and not loadingIntoRaid
				and player:GetAttribute("LobbyPostRaidOpen") ~= true
				and input.KeyCode == Enum.KeyCode.E
				and canOpenViaPromptPart()
			then
				print("[LobbyClient] Opened via PromptPart fallback")
				setOpen(true)
				setTerminalOpen(true)
				return
			end

			if not isMobile
				and not open
				and not loadingIntoRaid
				and not matchStarting
				and queueStatus.queued
				and input.KeyCode == Enum.KeyCode.C
				and not UserInputService:GetFocusedTextBox()
			then
				queueCancelStartedAtRef.current = time()
				queueCancelCompletedRef.current = false
				queueCancelHeldRef.current = true
				setQueueCancelHeld(true)
				setQueueCancelProgress(0)
				return
			end

			if processed or not open then
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape then
				setOpen(false)
				setTerminalOpen(false)
			end
		end)

		local inputEndedConn = UserInputService.InputEnded:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.C then
				queueCancelStartedAtRef.current = 0
				queueCancelCompletedRef.current = false
				queueCancelHeldRef.current = false
				setQueueCancelHeld(false)
				setQueueCancelProgress(0)
			end
		end)

		local coreGuiConn = player.CharacterAdded:Connect(function()
			if open then
				applyTerminalInputMode(true)
			end
		end)
		local promptHintConn = RunService.RenderStepped:Connect(function()
			local isAvailable = not open
				and not loadingIntoRaid
				and not matchStarting
				and player:GetAttribute("LobbyPostRaidOpen") ~= true
				and canOpenViaPromptPart()
			if isMobile then
				setMobileDeployAvailable(isAvailable)
				setDesktopDeployAvailable(false)
			else
				setDesktopDeployAvailable(isAvailable)
				setMobileDeployAvailable(false)
			end

			if queueCancelHeldRef.current then
				if not queueStatus.queued or open or loadingIntoRaid or matchStarting then
					queueCancelStartedAtRef.current = 0
					queueCancelCompletedRef.current = false
					queueCancelHeldRef.current = false
					setQueueCancelHeld(false)
					setQueueCancelProgress(0)
					return
				end

				local progress = math.clamp((time() - queueCancelStartedAtRef.current) / QUEUE_CANCEL_HOLD_SECONDS, 0, 1)
				setQueueCancelProgress(progress)
				if progress >= 1 and not queueCancelCompletedRef.current then
					queueCancelCompletedRef.current = true
					queueCancelStartedAtRef.current = 0
					queueCancelHeldRef.current = false
					setQueueCancelHeld(false)
					setQueueCancelProgress(0)
					leaveQueueEvent:FireServer()
				end
			end
		end)

		return function()
			queueConn:Disconnect()
			noticeConn:Disconnect()
			if promptConn then
				promptConn:Disconnect()
			end
			if promptServiceConn then
				promptServiceConn:Disconnect()
			end
			attrConn:Disconnect()
			matchAttrConn:Disconnect()
			inputConn:Disconnect()
			inputEndedConn:Disconnect()
			coreGuiConn:Disconnect()
			promptHintConn:Disconnect()
		end
	end, { open, loadingIntoRaid, matchStarting, queueStatus.queued })

	if loadingIntoRaid then
		return React.createElement("ScreenGui", {
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
		}, {
			Loading = React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(320, 54),
				BackgroundColor3 = Color3.fromRGB(16, 16, 16),
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
				Text = "Loading into raid...",
				Font = Enum.Font.GothamBold,
				TextSize = 22,
				TextColor3 = Color3.fromRGB(255, 225, 130),
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.15,
					Color = Color3.fromRGB(255, 225, 130),
				}),
			}),
		})
	end

	if not open then
		return React.createElement("ScreenGui", {
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
		}, {
			QueueOverlay = if queueStatus.queued then React.createElement("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -16, 0, 16),
				Size = UDim2.fromOffset(if isMobile then 230 else 300, if isMobile then 96 else 132),
				BackgroundColor3 = Color3.fromRGB(16, 16, 16),
				BackgroundTransparency = 0.12,
				BorderSizePixel = 0,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.15,
					Color = Color3.fromRGB(255, 225, 130),
				}),
				Title = React.createElement("TextLabel", {
					Position = UDim2.fromOffset(12, 8),
					Size = UDim2.new(1, -94, 0, 18),
					BackgroundTransparency = 1,
					Text = "QUEUE ACTIVE",
					Font = Enum.Font.GothamBold,
					TextSize = if isMobile then 12 else 13,
					TextColor3 = Color3.fromRGB(255, 225, 130),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Count = React.createElement("TextLabel", {
					Position = UDim2.fromOffset(12, 30),
					Size = UDim2.new(1, -24, 0, 18),
					BackgroundTransparency = 1,
					Text = string.format("%d / %d queued", queueStatus.count or 0, queueStatus.targetSize or 1),
					Font = Enum.Font.Code,
					TextSize = if isMobile then 11 else 12,
					TextColor3 = Color3.new(1, 1, 1),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				PositionText = React.createElement("TextLabel", {
					Position = UDim2.fromOffset(12, 48),
					Size = UDim2.new(1, -24, 0, 18),
					BackgroundTransparency = 1,
					Text = string.format("Position %d  |  Timeout %s", queueStatus.position or 1, formatWait(queueStatus.estimatedWaitSeconds)),
					Font = Enum.Font.Code,
					TextSize = if isMobile then 11 else 12,
					TextColor3 = Color3.new(1, 1, 1),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Leave = if isMobile then React.createElement("TextButton", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -10, 0, 10),
					Size = UDim2.fromOffset(70, 28),
					BackgroundColor3 = Color3.fromRGB(46, 28, 28),
					BorderSizePixel = 0,
					Text = "Leave",
					Font = Enum.Font.GothamBold,
					TextSize = 12,
					TextColor3 = Color3.new(1, 1, 1),
					[React.Event.Activated] = function()
						leaveQueueEvent:FireServer()
					end,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
				}) else nil,
				HoldCancelText = if not isMobile then React.createElement("TextLabel", {
					Position = UDim2.fromOffset(12, 72),
					Size = UDim2.new(1, -24, 0, 18),
					BackgroundTransparency = 1,
					Text = "Hold C to cancel queue",
					Font = Enum.Font.GothamMedium,
					TextSize = 12,
					TextColor3 = Color3.fromRGB(255, 225, 130),
					TextXAlignment = Enum.TextXAlignment.Left,
				}) else nil,
				HoldTrack = if not isMobile then React.createElement("Frame", {
					Position = UDim2.fromOffset(12, 94),
					Size = UDim2.new(1, -24, 0, 12),
					BackgroundColor3 = Color3.fromRGB(34, 34, 34),
					BorderSizePixel = 0,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 999) }),
					Fill = React.createElement("Frame", {
						Size = UDim2.new(queueCancelProgress, 0, 1, 0),
						BackgroundColor3 = Color3.fromRGB(255, 225, 130),
						BorderSizePixel = 0,
					}, {
						Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 999) }),
					}),
				}) else nil,
			}) else nil,
			DesktopDeploy = if not isMobile and desktopDeployAvailable then React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.62),
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundColor3 = Color3.fromRGB(18, 18, 18),
				BackgroundTransparency = 0.12,
				BorderSizePixel = 0,
				Text = "Deploy Terminal. Press E",
				Font = Enum.Font.GothamBold,
				TextSize = 20,
				TextColor3 = Color3.new(1, 1, 1),
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.12,
					Color = Color3.fromRGB(255, 225, 130),
				}),
				Padding = React.createElement("UIPadding", {
					PaddingLeft = UDim.new(0, 18),
					PaddingRight = UDim.new(0, 18),
					PaddingTop = UDim.new(0, 10),
					PaddingBottom = UDim.new(0, 10),
				}),
			}) else nil,
			MobileDeploy = if isMobile and mobileDeployAvailable then React.createElement("TextButton", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -28),
				Size = UDim2.fromOffset(220, 54),
				BackgroundColor3 = Color3.fromRGB(18, 18, 18),
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				Text = "Open Deploy Terminal",
				Font = Enum.Font.GothamBold,
				TextSize = 18,
				TextColor3 = Color3.fromRGB(255, 225, 130),
				[React.Event.Activated] = function()
					setOpen(true)
					setTerminalOpen(true)
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.1,
					Color = Color3.fromRGB(255, 225, 130),
				}),
			}) else nil,
			LoadoutPreview = if inventorySnapshot and not isMobile then React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 16),
				Size = UDim2.fromOffset(420, 92),
				BackgroundColor3 = Color3.fromRGB(16, 16, 16),
				BackgroundTransparency = 0.12,
				BorderSizePixel = 0,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.15,
					Color = Color3.fromRGB(255, 225, 130),
				}),
				Title = React.createElement("TextLabel", {
					Position = UDim2.fromOffset(12, 8),
					Size = UDim2.new(1, -24, 0, 16),
					BackgroundTransparency = 1,
					Text = "CURRENT LOADOUT",
					Font = Enum.Font.GothamBold,
					TextSize = 12,
					TextColor3 = Color3.fromRGB(255, 225, 130),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				PrimaryA = React.createElement("TextLabel", {
					Position = UDim2.fromOffset(12, 28),
					Size = UDim2.new(0.48, -6, 0, 18),
					BackgroundTransparency = 1,
					Text = "1 " .. lobbyItemLabel(inventorySnapshot, inventorySnapshot.weaponSlots and inventorySnapshot.weaponSlots.PrimaryA or nil),
					Font = Enum.Font.Code,
					TextSize = 11,
					TextColor3 = Color3.new(1, 1, 1),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				PrimaryB = React.createElement("TextLabel", {
					Position = UDim2.new(0.52, 0, 0, 28),
					Size = UDim2.new(0.48, -12, 0, 18),
					BackgroundTransparency = 1,
					Text = "2 " .. lobbyItemLabel(inventorySnapshot, inventorySnapshot.weaponSlots and inventorySnapshot.weaponSlots.PrimaryB or nil),
					Font = Enum.Font.Code,
					TextSize = 11,
					TextColor3 = Color3.new(1, 1, 1),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Pistol = React.createElement("TextLabel", {
					Position = UDim2.fromOffset(12, 48),
					Size = UDim2.new(0.48, -6, 0, 18),
					BackgroundTransparency = 1,
					Text = "3 " .. lobbyItemLabel(inventorySnapshot, inventorySnapshot.weaponSlots and inventorySnapshot.weaponSlots.Pistol or nil),
					Font = Enum.Font.Code,
					TextSize = 11,
					TextColor3 = Color3.new(1, 1, 1),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Melee = React.createElement("TextLabel", {
					Position = UDim2.new(0.52, 0, 0, 48),
					Size = UDim2.new(0.48, -12, 0, 18),
					BackgroundTransparency = 1,
					Text = "4 " .. lobbyItemLabel(inventorySnapshot, inventorySnapshot.weaponSlots and inventorySnapshot.weaponSlots.Melee or nil),
					Font = Enum.Font.Code,
					TextSize = 11,
					TextColor3 = Color3.new(1, 1, 1),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Counts = React.createElement("TextLabel", {
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.new(1, -12, 1, -8),
					Size = UDim2.new(1, -24, 0, 16),
					BackgroundTransparency = 1,
					Text = string.format(
						"Rig %d/%d  Backpack %d/%d",
						countContainerItems(inventorySnapshot.rig),
						(inventorySnapshot.rig and inventorySnapshot.rig.capacity) or 0,
						countContainerItems(inventorySnapshot.backpack),
						(inventorySnapshot.backpack and inventorySnapshot.backpack.capacity) or 0
					),
					Font = Enum.Font.Code,
					TextSize = 11,
					TextColor3 = Color3.fromRGB(220, 220, 220),
					TextXAlignment = Enum.TextXAlignment.Right,
				}),
			}) else nil,
			InventoryButton = if player:GetAttribute("LobbyPostRaidOpen") ~= true then React.createElement("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -16, 0, if queueStatus.queued then (if isMobile then 118 else 154) else 16),
				Size = UDim2.fromOffset(if isMobile then 92 else 110, 34),
				BackgroundColor3 = Color3.fromRGB(16, 16, 16),
				BackgroundTransparency = 0.12,
				BorderSizePixel = 0,
				Text = "Inventory",
				Font = Enum.Font.GothamBold,
				TextSize = if isMobile then 12 else 13,
				TextColor3 = Color3.fromRGB(255, 225, 130),
				[React.Event.Activated] = function()
					ClientActionBridge.invoke("toggle_inventory")
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.15,
					Color = Color3.fromRGB(255, 225, 130),
				}),
			}) else nil,
		})
	end

	return React.createElement("ScreenGui", {
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
	}, {
		CloseBands = React.createElement("Frame", {
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, {
			Top = React.createElement("TextButton", {
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.new(1, 0, 0.225, 0),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				[React.Event.Activated] = function()
					setOpen(false)
					setTerminalOpen(false)
				end,
			}),
			Bottom = React.createElement("TextButton", {
				Position = UDim2.new(0, 0, 0.775, 0),
				Size = UDim2.new(1, 0, 0.225, 0),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				[React.Event.Activated] = function()
					setOpen(false)
					setTerminalOpen(false)
				end,
			}),
			Left = React.createElement("TextButton", {
				Position = UDim2.new(0, 0, 0.225, 0),
				Size = UDim2.new(0.275, 0, 0.55, 0),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				[React.Event.Activated] = function()
					setOpen(false)
					setTerminalOpen(false)
				end,
			}),
			Right = React.createElement("TextButton", {
				Position = UDim2.new(0.725, 0, 0.225, 0),
				Size = UDim2.new(0.275, 0, 0.55, 0),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				[React.Event.Activated] = function()
					setOpen(false)
					setTerminalOpen(false)
				end,
			}),
		}),
		Panel = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(420, 240),
			BackgroundColor3 = Color3.fromRGB(16, 16, 16),
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
			Stroke = React.createElement("UIStroke", {
				Thickness = 1,
				Transparency = 0.15,
				Color = Color3.fromRGB(255, 225, 130),
			}),
			Title = React.createElement("TextLabel", {
				Position = UDim2.fromOffset(18, 14),
				Size = UDim2.new(1, -72, 0, 28),
				BackgroundTransparency = 1,
				Text = "Raid Queue",
				Font = Enum.Font.GothamBold,
				TextSize = 22,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromRGB(255, 225, 130),
			}),
			CloseButton = React.createElement("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -16, 0, 14),
				Size = UDim2.fromOffset(28, 28),
				BackgroundColor3 = Color3.fromRGB(28, 28, 28),
				BackgroundTransparency = 0.08,
				BorderSizePixel = 0,
				Text = "X",
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(255, 225, 130),
				[React.Event.Activated] = function()
					setOpen(false)
					setTerminalOpen(false)
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.12,
					Color = Color3.fromRGB(255, 225, 130),
				}),
			}),
			Count = React.createElement("TextLabel", {
				Position = UDim2.fromOffset(18, 58),
				Size = UDim2.new(1, -36, 0, 22),
				BackgroundTransparency = 1,
				Text = string.format("Queued Players: %d / %d", queueStatus.count or 0, queueStatus.targetSize or 1),
				Font = Enum.Font.GothamMedium,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.new(1, 1, 1),
			}),
			QueuePosition = React.createElement("TextLabel", {
				Position = UDim2.fromOffset(18, 88),
				Size = UDim2.new(1, -36, 0, 22),
				BackgroundTransparency = 1,
				Text = if queueStatus.queued then string.format("Your Position: %d", queueStatus.position or 1) else "You are not queued",
				Font = Enum.Font.GothamMedium,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.new(1, 1, 1),
			}),
			Wait = React.createElement("TextLabel", {
				Position = UDim2.fromOffset(18, 118),
				Size = UDim2.new(1, -36, 0, 22),
				BackgroundTransparency = 1,
				Text = "Estimated Timeout Start: " .. formatWait(queueStatus.estimatedWaitSeconds),
				Font = Enum.Font.GothamMedium,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.new(1, 1, 1),
			}),
			Notice = React.createElement("TextLabel", {
				Position = UDim2.fromOffset(18, 148),
				Size = UDim2.new(1, -36, 0, 18),
				BackgroundTransparency = 1,
				Text = notice,
				Font = Enum.Font.Gotham,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromRGB(255, 210, 120),
			}),
			QueueButton = React.createElement("TextButton", {
				Position = UDim2.fromOffset(18, 182),
				Size = UDim2.fromOffset(180, 38),
				BackgroundColor3 = Color3.fromRGB(42, 42, 42),
				BorderSizePixel = 0,
				Text = if queueStatus.queued then "Leave Queue" else "Join Queue",
				Font = Enum.Font.GothamBold,
				TextSize = 15,
				TextColor3 = Color3.new(1, 1, 1),
				[React.Event.Activated] = function()
					if queueStatus.queued then
						leaveQueueEvent:FireServer()
					else
						joinQueueEvent:FireServer()
					end
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
			}),
			DevForceStart = if RunService:IsStudio() then React.createElement("TextButton", {
				Position = UDim2.fromOffset(212, 182),
				Size = UDim2.fromOffset(190, 38),
				BackgroundColor3 = Color3.fromRGB(64, 50, 22),
				BorderSizePixel = 0,
				Text = "Dev Force Start",
				Font = Enum.Font.GothamBold,
				TextSize = 15,
				TextColor3 = Color3.new(1, 1, 1),
				[React.Event.Activated] = function()
					devForceStartEvent:FireServer()
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
			}) else nil,
		}),
	})
end

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

player:SetAttribute("LobbyTerminalOpen", false)
player:SetAttribute("LobbyMatchStarting", false)
applyTerminalInputMode(false)

local playerGui = player:WaitForChild("PlayerGui")
print("[LobbyClient] Creating lobby UI root")
local rootGui = Instance.new("Folder")
rootGui.Name = "_LobbyUIRoot"
rootGui.Parent = playerGui

local root = ReactRoblox.createRoot(rootGui)
root:render(React.createElement(LobbyApp))
