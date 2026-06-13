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
local terminalOpenEvent = remotes:WaitForChild(Net.TerminalOpenEventName) :: RemoteEvent
local terminalInteractRequestEvent = remotes:WaitForChild(Net.TerminalInteractRequestEventName) :: RemoteEvent
local terminalCloseEvent = remotes:WaitForChild(Net.TerminalCloseEventName) :: RemoteEvent
local quartermasterSellRequestEvent = remotes:WaitForChild(Net.QuartermasterSellRequestEventName) :: RemoteEvent
local quartermasterStateEvent = remotes:WaitForChild(Net.QuartermasterStateEventName) :: RemoteEvent

local controls: any = nil
local terminalOpen = false
local matchStarting = false
local terminalCameraConn: RBXScriptConnection? = nil
local terminalInputEnforceConn: RBXScriptConnection? = nil
local terminalCameraStart: CFrame? = nil
local terminalAnchorStartPosition: Vector3? = nil
local PROMPT_PART_ACTIVATION_DISTANCE = 10
local QUEUE_CANCEL_HOLD_SECONDS = 2
local QUARTERMASTER_KIOSK_NAME = "QuartermasterKiosk"

type QuartermasterRow = {
	itemId: string,
	templateId: string,
	displayName: string,
	category: string,
	source: string,
	value: number,
	origin: string?,
}

type TerminalMode = "deploy" | "kiosk"

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

local function stopTerminalInputEnforcement()
	if terminalInputEnforceConn then
		terminalInputEnforceConn:Disconnect()
		terminalInputEnforceConn = nil
	end
end

local function startTerminalInputEnforcement()
	stopTerminalInputEnforcement()

	terminalInputEnforceConn = RunService.RenderStepped:Connect(function()
		if not terminalOpen then
			return
		end

		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		player.CameraMode = Enum.CameraMode.Classic
		if camera then
			camera.CameraType = Enum.CameraType.Scriptable
		end
	end)
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
		startTerminalInputEnforcement()
	else
		ctl:Enable()
		stopTerminalCameraFollow()
		stopTerminalInputEnforcement()
		UserInputService.MouseIconEnabled = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
	end
end

local function setTerminalOpen(open: boolean, mode: TerminalMode?)
	terminalOpen = open
	player:SetAttribute("LobbyTerminalOpen", open)
	player:SetAttribute("LobbyTerminalMode", if open then mode else nil)
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

local function getStashTerminalPrompt(): ProximityPrompt?
	local lobby = workspace:FindFirstChild("Lobby")
	local interactables = lobby and lobby:FindFirstChild("Interactables")
	local stashTerminal = interactables and interactables:FindFirstChild("StashTerminal")
	local prompt = stashTerminal and stashTerminal:FindFirstChild("ProximityPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		return prompt
	end

	return nil
end

local function getStashTerminalPromptPart(): BasePart?
	local lobby = workspace:FindFirstChild("Lobby")
	local interactables = lobby and lobby:FindFirstChild("Interactables")
	local stashTerminal = interactables and interactables:FindFirstChild("StashTerminal")
	local promptPart = stashTerminal and stashTerminal:FindFirstChild("PromptPart")
	if promptPart and promptPart:IsA("BasePart") then
		return promptPart
	end

	return nil
end

local function getKioskPrompt(): ProximityPrompt?
	local lobby = workspace:FindFirstChild("Lobby")
	local interactables = lobby and lobby:FindFirstChild("Interactables")
	local kiosk = interactables and interactables:FindFirstChild(QUARTERMASTER_KIOSK_NAME)
	local prompt = kiosk and kiosk:FindFirstChild("ProximityPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		return prompt
	end

	return nil
end

local function getKioskPromptPart(): BasePart?
	local lobby = workspace:FindFirstChild("Lobby")
	local interactables = lobby and lobby:FindFirstChild("Interactables")
	local kiosk = interactables and interactables:FindFirstChild(QUARTERMASTER_KIOSK_NAME)
	local promptPart = kiosk and kiosk:FindFirstChild("PromptPart")
	if promptPart and promptPart:IsA("BasePart") then
		return promptPart
	end

	return nil
end

local function getPromptPartDistance(promptPart: BasePart?): number?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or not promptPart then
		return nil
	end

	return (root.Position - promptPart.Position).Magnitude
end

local function canOpenViaPromptPart(promptPart: BasePart?): boolean
	local distance = getPromptPartDistance(promptPart)
	return distance ~= nil and distance <= PROMPT_PART_ACTIVATION_DISTANCE
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

local function formatReqCredits(value: number?): string
	return string.format("%d REQ", if typeof(value) == "number" then math.max(0, math.floor(value)) else 0)
end

local function filterQuartermasterItems(rows: {QuartermasterRow}, sourceFilter: string): {QuartermasterRow}
	if sourceFilter == "all" then
		return rows
	end

	local filtered = {}
	for _, row in ipairs(rows) do
		if row.source == sourceFilter then
			table.insert(filtered, row)
		end
	end
	return filtered
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
	local terminalMode, setTerminalMode = React.useState((player:GetAttribute("LobbyTerminalMode") :: any) :: TerminalMode?)
	local loadingIntoRaid, setLoadingIntoRaid = React.useState(player:GetAttribute("LobbyMatchStarting") == true)
	local mobileDeployAvailable, setMobileDeployAvailable = React.useState(false)
	local desktopDeployAvailable, setDesktopDeployAvailable = React.useState(false)
	local mobileStashAvailable, setMobileStashAvailable = React.useState(false)
	local desktopStashAvailable, setDesktopStashAvailable = React.useState(false)
	local mobileKioskAvailable, setMobileKioskAvailable = React.useState(false)
	local desktopKioskAvailable, setDesktopKioskAvailable = React.useState(false)
	local queueCancelHeld, setQueueCancelHeld = React.useState(false)
	local queueCancelProgress, setQueueCancelProgress = React.useState(0)
	local quartermasterState, setQuartermasterState = React.useState({
		reqCredits = 0,
		sellableItems = {} :: {QuartermasterRow},
		notice = "",
	})
	local quartermasterTab, setQuartermasterTab = React.useState("all")
	local quartermasterSelectedItemId, setQuartermasterSelectedItemId = React.useState(nil :: string?)
	local quartermasterPendingItemId, setQuartermasterPendingItemId = React.useState(nil :: string?)
	local quartermasterConfirmItemId, setQuartermasterConfirmItemId = React.useState(nil :: string?)
	local queueCancelHeldRef = React.useRef(false)
	local queueCancelStartedAtRef = React.useRef(0)
	local queueCancelCompletedRef = React.useRef(false)

	local function closeTerminalUi()
		local currentMode = terminalMode
		setOpen(false)
		setTerminalMode(nil)
		setTerminalOpen(false)
		setQuartermasterPendingItemId(nil)
		setQuartermasterConfirmItemId(nil)
		if currentMode == "kiosk" then
			terminalCloseEvent:FireServer({
				terminal = QUARTERMASTER_KIOSK_NAME,
			})
		end
	end

	local function openDeployTerminalUi()
		setTerminalMode("deploy")
		setOpen(true)
		setTerminalOpen(true, "deploy")
	end

	local function requestOpenQuartermaster()
		terminalInteractRequestEvent:FireServer({
			terminal = QUARTERMASTER_KIOSK_NAME,
		})
	end

	React.useEffect(function()
		print("[LobbyClient] LobbyApp mounted")
		local queueConn = queueStatusEvent.OnClientEvent:Connect(function(nextStatus)
			print("[LobbyClient] Queue status", nextStatus.count, nextStatus.position, nextStatus.queued)
			setQueueStatus(nextStatus)
		end)
		local terminalOpenConn = terminalOpenEvent.OnClientEvent:Connect(function(payload)
			if typeof(payload) ~= "table" or payload.terminal ~= QUARTERMASTER_KIOSK_NAME then
				return
			end

			setTerminalMode("kiosk")
			setOpen(true)
			setTerminalOpen(true, "kiosk")
		end)
		local quartermasterStateConn = quartermasterStateEvent.OnClientEvent:Connect(function(payload)
			if typeof(payload) ~= "table" then
				return
			end

			local sellableItems = {}
			if typeof(payload.sellableItems) == "table" then
				for _, row in ipairs(payload.sellableItems) do
					if typeof(row) == "table" then
						table.insert(sellableItems, row)
					end
				end
			end

			setQuartermasterState({
				reqCredits = if typeof(payload.reqCredits) == "number" then payload.reqCredits else 0,
				sellableItems = sellableItems,
				notice = if typeof(payload.notice) == "string" then payload.notice else "",
			})
			setQuartermasterPendingItemId(nil)
			setQuartermasterConfirmItemId(nil)
		end)
		local noticeConn = noticeEvent.OnClientEvent:Connect(function(message)
			print("[LobbyClient] Notice", message)
			local nextMessage = tostring(message)
			if nextMessage == "Loading into raid..." then
				setLoadingIntoRaid(true)
				setOpen(false)
				setTerminalMode(nil)
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
		local deployPromptConn: RBXScriptConnection? = nil
		local stashPromptConn: RBXScriptConnection? = nil
		local promptServiceConn: RBXScriptConnection? = nil
		local function bindDeployPrompt(prompt: ProximityPrompt)
			print("[LobbyClient] Binding deploy prompt", prompt:GetFullName())
			if deployPromptConn then
				deployPromptConn:Disconnect()
			end
			deployPromptConn = prompt.Triggered:Connect(function()
				if matchStarting or player:GetAttribute("LobbyPostRaidOpen") == true then
					return
				end
				print("[LobbyClient] Deploy prompt triggered")
				openDeployTerminalUi()
			end)
		end
		local function bindStashPrompt(prompt: ProximityPrompt)
			if stashPromptConn then
				stashPromptConn:Disconnect()
			end
			stashPromptConn = prompt.Triggered:Connect(function()
				if matchStarting or player:GetAttribute("LobbyPostRaidOpen") == true then
					return
				end
				ClientActionBridge.invoke("open_inventory")
			end)
		end

		local existingPrompt = getDeployTerminalPrompt()
		if existingPrompt then
			bindDeployPrompt(existingPrompt)
		end
		local existingStashPrompt = getStashTerminalPrompt()
		if existingStashPrompt then
			bindStashPrompt(existingStashPrompt)
		end
		if not existingPrompt or not existingStashPrompt then
			print("[LobbyClient] Waiting for deploy prompt via PromptShown")
			promptServiceConn = ProximityPromptService.PromptShown:Connect(function(prompt)
				local deployPrompt = getDeployTerminalPrompt()
				if deployPrompt and prompt == deployPrompt then
					print("[LobbyClient] PromptShown matched deploy terminal")
					bindDeployPrompt(deployPrompt)
				end

				local stashPrompt = getStashTerminalPrompt()
				if stashPrompt and prompt == stashPrompt then
					bindStashPrompt(stashPrompt)
				end
			end)
		end
		local attrConn = player:GetAttributeChangedSignal("LobbyTerminalOpen"):Connect(function()
			local value = player:GetAttribute("LobbyTerminalOpen") == true
			setOpen(value)
		end)
		local terminalModeConn = player:GetAttributeChangedSignal("LobbyTerminalMode"):Connect(function()
			local value = player:GetAttribute("LobbyTerminalMode")
			if value == "deploy" or value == "kiosk" then
				setTerminalMode(value)
			else
				setTerminalMode(nil)
			end
		end)
		local matchAttrConn = player:GetAttributeChangedSignal("LobbyMatchStarting"):Connect(function()
			local value = player:GetAttribute("LobbyMatchStarting") == true
			setLoadingIntoRaid(value)
			if value then
				setOpen(false)
				setTerminalMode(nil)
			end
		end)
		local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
			if not open
				and not loadingIntoRaid
				and player:GetAttribute("LobbyPostRaidOpen") ~= true
				and player:GetAttribute("InventoryVisible") ~= true
				and input.KeyCode == Enum.KeyCode.E
			then
				local deployDistance = getPromptPartDistance(getDeployTerminalPromptPart())
				local stashDistance = getPromptPartDistance(getStashTerminalPromptPart())
				local kioskDistance = getPromptPartDistance(getKioskPromptPart())
				local deployAvailable = deployDistance ~= nil and deployDistance <= PROMPT_PART_ACTIVATION_DISTANCE
				local stashAvailable = stashDistance ~= nil and stashDistance <= PROMPT_PART_ACTIVATION_DISTANCE
				local kioskAvailable = kioskDistance ~= nil and kioskDistance <= PROMPT_PART_ACTIVATION_DISTANCE

				local closestKind = nil :: string?
				local closestDistance = math.huge
				if deployAvailable and (deployDistance :: number) < closestDistance then
					closestKind = "deploy"
					closestDistance = deployDistance :: number
				end
				if stashAvailable and (stashDistance :: number) < closestDistance then
					closestKind = "stash"
					closestDistance = stashDistance :: number
				end
				if kioskAvailable and (kioskDistance :: number) < closestDistance then
					closestKind = "kiosk"
					closestDistance = kioskDistance :: number
				end

				if closestKind == "stash" then
					ClientActionBridge.invoke("open_inventory")
					return
				end
				if closestKind == "kiosk" then
					requestOpenQuartermaster()
					return
				end
				if closestKind == "deploy" then
					print("[LobbyClient] Opened via PromptPart fallback")
					openDeployTerminalUi()
					return
				end
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
				closeTerminalUi()
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
			local deployAvailable = not open
				and not loadingIntoRaid
				and not matchStarting
				and player:GetAttribute("LobbyPostRaidOpen") ~= true
				and canOpenViaPromptPart(getDeployTerminalPromptPart())
			local stashAvailable = not open
				and not loadingIntoRaid
				and not matchStarting
				and player:GetAttribute("LobbyPostRaidOpen") ~= true
				and player:GetAttribute("InventoryVisible") ~= true
				and canOpenViaPromptPart(getStashTerminalPromptPart())
			local kioskAvailable = not open
				and not loadingIntoRaid
				and not matchStarting
				and player:GetAttribute("LobbyPostRaidOpen") ~= true
				and canOpenViaPromptPart(getKioskPromptPart())
			if isMobile then
				setMobileDeployAvailable(deployAvailable)
				setDesktopDeployAvailable(false)
				setMobileStashAvailable(stashAvailable)
				setDesktopStashAvailable(false)
				setMobileKioskAvailable(kioskAvailable)
				setDesktopKioskAvailable(false)
			else
				setDesktopDeployAvailable(deployAvailable)
				setMobileDeployAvailable(false)
				setDesktopStashAvailable(stashAvailable)
				setMobileStashAvailable(false)
				setDesktopKioskAvailable(kioskAvailable)
				setMobileKioskAvailable(false)
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
			terminalOpenConn:Disconnect()
			quartermasterStateConn:Disconnect()
			noticeConn:Disconnect()
			if deployPromptConn then
				deployPromptConn:Disconnect()
			end
			if stashPromptConn then
				stashPromptConn:Disconnect()
			end
			if promptServiceConn then
				promptServiceConn:Disconnect()
			end
			attrConn:Disconnect()
			terminalModeConn:Disconnect()
			matchAttrConn:Disconnect()
			inputConn:Disconnect()
			inputEndedConn:Disconnect()
			coreGuiConn:Disconnect()
			promptHintConn:Disconnect()
		end
	end, { open, loadingIntoRaid, matchStarting, queueStatus.queued, terminalMode })

	React.useEffect(function()
		local rows = quartermasterState.sellableItems
		if quartermasterSelectedItemId then
			for _, row in ipairs(rows) do
				if row.itemId == quartermasterSelectedItemId then
					return
				end
			end
		end

		setQuartermasterSelectedItemId(if #rows > 0 then rows[1].itemId else nil)
	end, { quartermasterState, quartermasterSelectedItemId })

	React.useEffect(function()
		applyTerminalInputMode(open)

		if not open then
			return
		end

		local charConn = player.CharacterAdded:Connect(function()
			task.defer(function()
				applyTerminalInputMode(true)
			end)
		end)

		local cameraConn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			task.defer(function()
				applyTerminalInputMode(true)
			end)
		end)

		return function()
			charConn:Disconnect()
			cameraConn:Disconnect()
		end
	end, { open, terminalMode })

	local filteredQuartermasterItems = filterQuartermasterItems(quartermasterState.sellableItems, if isMobile then (if quartermasterTab == "all" then "all" else quartermasterTab) else quartermasterTab)
	local selectedQuartermasterItem = nil :: QuartermasterRow?
	for _, row in ipairs(filteredQuartermasterItems) do
		if row.itemId == quartermasterSelectedItemId then
			selectedQuartermasterItem = row
			break
		end
	end
	if selectedQuartermasterItem == nil and #filteredQuartermasterItems > 0 then
		selectedQuartermasterItem = filteredQuartermasterItems[1]
	end

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
					Text = "Hold C for 2s to cancel queue",
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
			DesktopStash = if not isMobile and desktopStashAvailable then React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.69),
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundColor3 = Color3.fromRGB(18, 18, 18),
				BackgroundTransparency = 0.12,
				BorderSizePixel = 0,
				Text = "Stash Terminal. Press E",
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
			DesktopKiosk = if not isMobile and desktopKioskAvailable then React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.76),
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundColor3 = Color3.fromRGB(18, 18, 18),
				BackgroundTransparency = 0.12,
				BorderSizePixel = 0,
				Text = "Quartermaster Kiosk. Press E",
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
					openDeployTerminalUi()
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.1,
					Color = Color3.fromRGB(255, 225, 130),
				}),
			}) else nil,
			MobileStash = if isMobile and mobileStashAvailable then React.createElement("TextButton", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, if mobileDeployAvailable then -92 else -28),
				Size = UDim2.fromOffset(200, 50),
				BackgroundColor3 = Color3.fromRGB(18, 18, 18),
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				Text = "Open Stash",
				Font = Enum.Font.GothamBold,
				TextSize = 18,
				TextColor3 = Color3.fromRGB(255, 225, 130),
				[React.Event.Activated] = function()
					ClientActionBridge.invoke("open_inventory")
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.1,
					Color = Color3.fromRGB(255, 225, 130),
				}),
			}) else nil,
			MobileKiosk = if isMobile and mobileKioskAvailable then React.createElement("TextButton", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, if mobileDeployAvailable then (if mobileStashAvailable then -156 else -92) else (if mobileStashAvailable then -92 else -28)),
				Size = UDim2.fromOffset(220, 50),
				BackgroundColor3 = Color3.fromRGB(18, 18, 18),
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				Text = "Open Quartermaster",
				Font = Enum.Font.GothamBold,
				TextSize = 18,
				TextColor3 = Color3.fromRGB(255, 225, 130),
				[React.Event.Activated] = function()
					requestOpenQuartermaster()
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

	if terminalMode == "kiosk" then
		local function requestSell(row: QuartermasterRow)
			setQuartermasterPendingItemId(row.itemId)
			quartermasterSellRequestEvent:FireServer({
				itemId = row.itemId,
				source = row.source,
			})
		end

		local function sourceLabel(source: string): string
			if source == "rig" then
				return "Rig"
			end
			if source == "backpack" then
				return "Backpack"
			end
			return source
		end

		local function sourceColor(source: string): Color3
			if source == "rig" then
				return Color3.fromRGB(110, 190, 255)
			end
			return Color3.fromRGB(255, 225, 130)
		end

		local function makeTabButton(label: string, value: string, width: number)
			local selected = quartermasterTab == value
			return React.createElement("TextButton", {
				LayoutOrder = if value == "all" then 1 elseif value == "rig" then 2 else 3,
				Size = UDim2.fromOffset(width, if isMobile then 38 else 34),
				BackgroundColor3 = if selected then Color3.fromRGB(84, 64, 28) else Color3.fromRGB(26, 26, 26),
				BorderSizePixel = 0,
				Text = label,
				Font = Enum.Font.GothamBold,
				TextSize = if isMobile then 15 else 13,
				TextColor3 = if selected then Color3.fromRGB(255, 240, 170) else Color3.fromRGB(225, 225, 225),
				[React.Event.Activated] = function()
					setQuartermasterTab(value)
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = if selected then 1.5 else 1,
					Transparency = if selected then 0.02 else 0.25,
					Color = Color3.fromRGB(255, 225, 130),
				}),
			})
		end

		local listChildren: {[string]: any} = {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, if isMobile then 10 else 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}

		if #filteredQuartermasterItems == 0 then
			listChildren.Empty = React.createElement("Frame", {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, if isMobile then 124 else 118),
				BackgroundColor3 = Color3.fromRGB(20, 22, 26),
				BackgroundTransparency = 0.02,
				BorderSizePixel = 0,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.2,
					Color = Color3.fromRGB(255, 225, 130),
				}),
				Title = React.createElement("TextLabel", {
					Position = UDim2.fromOffset(16, 16),
					Size = UDim2.new(1, -32, 0, 24),
					BackgroundTransparency = 1,
					Text = "No sellable items",
					Font = Enum.Font.GothamBold,
					TextSize = if isMobile then 19 else 18,
					TextColor3 = Color3.fromRGB(255, 240, 170),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Body = React.createElement("TextLabel", {
					Position = UDim2.fromOffset(16, 48),
					Size = UDim2.new(1, -32, 0, 56),
					BackgroundTransparency = 1,
					Text = "Bring loot back in your rig or backpack to sell it here for REQ credits.",
					Font = Enum.Font.Gotham,
					TextSize = if isMobile then 15 else 14,
					TextWrapped = true,
					TextColor3 = Color3.fromRGB(205, 205, 205),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
				}),
			})
		else
			for index, row in ipairs(filteredQuartermasterItems) do
				local isPending = quartermasterPendingItemId == row.itemId
				listChildren["Item" .. index] = React.createElement("TextButton", {
					LayoutOrder = index,
					Size = UDim2.new(1, 0, 0, if isMobile then 108 else 94),
					BackgroundColor3 = if selectedQuartermasterItem and selectedQuartermasterItem.itemId == row.itemId then Color3.fromRGB(34, 30, 18) else Color3.fromRGB(18, 20, 24),
					BackgroundTransparency = 0.02,
					BorderSizePixel = 0,
					Text = "",
					AutoButtonColor = not isPending,
					[React.Event.Activated] = function()
						if isPending then
							return
						end
						setQuartermasterSelectedItemId(row.itemId)
						if isMobile then
							setQuartermasterConfirmItemId(row.itemId)
						end
					end,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
					Stroke = React.createElement("UIStroke", {
						Thickness = if selectedQuartermasterItem and selectedQuartermasterItem.itemId == row.itemId then 1.5 else 1,
						Transparency = if selectedQuartermasterItem and selectedQuartermasterItem.itemId == row.itemId then 0.05 else 0.2,
						Color = Color3.fromRGB(255, 225, 130),
					}),
					SourcePill = React.createElement("Frame", {
						Position = UDim2.fromOffset(14, 14),
						Size = UDim2.fromOffset(if isMobile then 78 else 70, 24),
						BackgroundColor3 = sourceColor(row.source),
						BackgroundTransparency = 0.15,
						BorderSizePixel = 0,
					}, {
						Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 999) }),
						Label = React.createElement("TextLabel", {
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							Text = sourceLabel(row.source),
							Font = Enum.Font.GothamBold,
							TextSize = if isMobile then 12 else 11,
							TextColor3 = Color3.fromRGB(18, 18, 18),
						}),
					}),
					ValuePill = React.createElement("Frame", {
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -14, 0, 14),
						Size = UDim2.fromOffset(if isMobile then 104 else 96, 28),
						BackgroundColor3 = Color3.fromRGB(20, 42, 24),
						BackgroundTransparency = 0.05,
						BorderSizePixel = 0,
					}, {
						Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 999) }),
						Label = React.createElement("TextLabel", {
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							Text = string.format("+%d REQ", row.value),
							Font = Enum.Font.GothamBold,
							TextSize = if isMobile then 14 else 13,
							TextColor3 = Color3.fromRGB(120, 255, 140),
						}),
					}),
					Name = React.createElement("TextLabel", {
						Position = UDim2.fromOffset(14, 44),
						Size = UDim2.new(1, -28, 0, if isMobile then 22 else 20),
						BackgroundTransparency = 1,
						Text = row.displayName,
						Font = Enum.Font.GothamBold,
						TextSize = if isMobile then 20 else 17,
						TextColor3 = Color3.new(1, 1, 1),
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Meta = React.createElement("TextLabel", {
						Position = UDim2.fromOffset(14, 69),
						Size = UDim2.new(1, if isMobile then -28 else -124, 0, 16),
						BackgroundTransparency = 1,
						Text = string.format("%s  |  %s", row.category, row.origin or "BroughtIn"),
						Font = Enum.Font.Code,
						TextSize = if isMobile then 13 else 12,
						TextColor3 = Color3.fromRGB(210, 210, 210),
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Hint = React.createElement("TextLabel", {
						AnchorPoint = Vector2.new(0, 1),
						Position = UDim2.new(0, 14, 1, -10),
						Size = UDim2.new(1, if isMobile then -28 else -124, 0, 14),
						BackgroundTransparency = 1,
						Text = if isMobile then "Tap to review sale" else "Select for preview or sell instantly",
						Font = Enum.Font.Gotham,
						TextSize = if isMobile then 12 else 11,
						TextColor3 = Color3.fromRGB(165, 165, 165),
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Sell = if not isMobile then React.createElement("TextButton", {
						AnchorPoint = Vector2.new(1, 1),
						Position = UDim2.new(1, -12, 1, -10),
						Size = UDim2.fromOffset(92, 36),
						BackgroundColor3 = if isPending then Color3.fromRGB(52, 52, 52) else Color3.fromRGB(84, 64, 28),
						BorderSizePixel = 0,
						Text = if isPending then "Selling..." else "Sell",
						Font = Enum.Font.GothamBold,
						TextSize = 14,
						TextColor3 = Color3.new(1, 1, 1),
						AutoButtonColor = not isPending,
						Active = not isPending,
						[React.Event.Activated] = function()
							setQuartermasterSelectedItemId(row.itemId)
							requestSell(row)
						end,
					}, {
						Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
					}) else nil,
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
				BackgroundTransparency = if isMobile then 0.78 else 0.72,
				BorderSizePixel = 0,
			}),
			CloseBands = if not isMobile then React.createElement("Frame", {
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, {
				Top = React.createElement("TextButton", {
					Position = UDim2.fromOffset(0, 0),
					Size = UDim2.new(1, 0, 0.16, 0),
					BackgroundTransparency = 1,
					Text = "",
					AutoButtonColor = false,
					[React.Event.Activated] = closeTerminalUi,
				}),
				Bottom = React.createElement("TextButton", {
					Position = UDim2.new(0, 0, 0.84, 0),
					Size = UDim2.new(1, 0, 0.16, 0),
					BackgroundTransparency = 1,
					Text = "",
					AutoButtonColor = false,
					[React.Event.Activated] = closeTerminalUi,
				}),
				Left = React.createElement("TextButton", {
					Position = UDim2.new(0, 0, 0.16, 0),
					Size = UDim2.new(0.14, 0, 0.68, 0),
					BackgroundTransparency = 1,
					Text = "",
					AutoButtonColor = false,
					[React.Event.Activated] = closeTerminalUi,
				}),
				Right = React.createElement("TextButton", {
					Position = UDim2.new(0.86, 0, 0.16, 0),
					Size = UDim2.new(0.14, 0, 0.68, 0),
					BackgroundTransparency = 1,
					Text = "",
					AutoButtonColor = false,
					[React.Event.Activated] = closeTerminalUi,
				}),
			}) else nil,
			Panel = React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = if isMobile then UDim2.new(1, -18, 1, -22) else UDim2.fromOffset(1040, 640),
				BackgroundColor3 = Color3.fromRGB(12, 14, 16),
				BackgroundTransparency = 0.02,
				BorderSizePixel = 0,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, if isMobile then 14 else 16) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1.5,
					Transparency = 0.06,
					Color = Color3.fromRGB(255, 225, 130),
				}),
				Header = React.createElement("Frame", {
					Position = UDim2.fromOffset(0, 0),
					Size = UDim2.new(1, 0, 0, if isMobile then 150 else 122),
					BackgroundColor3 = Color3.fromRGB(18, 20, 24),
					BackgroundTransparency = 0.02,
					BorderSizePixel = 0,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, if isMobile then 14 else 16) }),
					Divider = React.createElement("Frame", {
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, 0),
						Size = UDim2.new(1, -28, 0, 1),
						BackgroundColor3 = Color3.fromRGB(255, 225, 130),
						BackgroundTransparency = 0.8,
						BorderSizePixel = 0,
					}, {
						Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 999) }),
					}),
					Title = React.createElement("TextLabel", {
						Position = UDim2.fromOffset(20, if isMobile then 16 else 18),
						Size = UDim2.new(1, if isMobile then -200 else -320, 0, if isMobile then 28 else 34),
						BackgroundTransparency = 1,
						Text = "Quartermaster Kiosk",
						Font = Enum.Font.GothamBold,
						TextSize = if isMobile then 24 else 30,
						TextColor3 = Color3.fromRGB(255, 234, 168),
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Subtitle = React.createElement("TextLabel", {
						Position = UDim2.fromOffset(20, if isMobile then 48 else 58),
						Size = UDim2.new(1, if isMobile then -40 else -350, 0, if isMobile then 40 else 20),
						BackgroundTransparency = 1,
						Text = "Convert recovered gear from your rig and backpack into persistent REQ credits.",
						Font = Enum.Font.Gotham,
						TextSize = 14,
						TextWrapped = isMobile,
						TextColor3 = Color3.fromRGB(205, 205, 205),
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
					}),
					CreditCard = React.createElement("Frame", {
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, if isMobile then -64 else -72, 0, if isMobile then 18 else 20),
						Size = if isMobile then UDim2.fromOffset(132, 46) else UDim2.fromOffset(208, 54),
						BackgroundColor3 = Color3.fromRGB(24, 40, 28),
						BackgroundTransparency = 0.02,
						BorderSizePixel = 0,
					}, {
						Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 12) }),
						Stroke = React.createElement("UIStroke", {
							Thickness = 1,
							Transparency = 0.18,
							Color = Color3.fromRGB(105, 255, 125),
						}),
						Label = React.createElement("TextLabel", {
							Position = UDim2.fromOffset(12, 7),
							Size = UDim2.new(1, -24, 0, 13),
							BackgroundTransparency = 1,
							Text = "REQ CREDITS",
							Font = Enum.Font.GothamBold,
							TextSize = if isMobile then 10 else 11,
							TextColor3 = Color3.fromRGB(120, 255, 140),
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
						Value = React.createElement("TextLabel", {
							Position = UDim2.fromOffset(12, if isMobile then 20 else 22),
							Size = UDim2.new(1, -24, 0, 24),
							BackgroundTransparency = 1,
							Text = formatReqCredits(quartermasterState.reqCredits),
							Font = Enum.Font.GothamBold,
							TextSize = if isMobile then 19 else 22,
							TextColor3 = Color3.new(1, 1, 1),
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
					}),
					CloseButton = React.createElement("TextButton", {
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -20, 0, if isMobile then 18 else 20),
						Size = UDim2.fromOffset(if isMobile then 34 else 36, if isMobile then 34 else 36),
						BackgroundColor3 = Color3.fromRGB(28, 28, 28),
						BorderSizePixel = 0,
						Text = "X",
						Font = Enum.Font.GothamBold,
						TextSize = if isMobile then 16 else 18,
						TextColor3 = Color3.fromRGB(255, 225, 130),
						[React.Event.Activated] = closeTerminalUi,
					}, {
						Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
					}),
					Tabs = React.createElement("Frame", {
						Position = UDim2.fromOffset(20, if isMobile then 102 else 78),
						Size = if isMobile then UDim2.new(1, -40, 0, 38) else UDim2.new(0, 330, 0, 34),
						BackgroundTransparency = 1,
					}, {
						Layout = React.createElement("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, 8),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
						All = makeTabButton("All", "all", if isMobile then 88 else 82),
						Rig = makeTabButton("Rig", "rig", if isMobile then 88 else 82),
						Backpack = makeTabButton("Backpack", "backpack", if isMobile then 116 else 106),
					}),
				}),
				Notice = React.createElement("TextLabel", {
					Position = if isMobile then UDim2.fromOffset(20, 158) else UDim2.new(0.62, 24, 0, 134),
					Size = if isMobile then UDim2.new(1, -40, 0, 18) else UDim2.new(0.38, -44, 0, 18),
					BackgroundTransparency = 1,
					Text = quartermasterState.notice,
					Font = Enum.Font.GothamMedium,
					TextSize = if isMobile then 12 else 13,
					TextColor3 = Color3.fromRGB(255, 210, 120),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				ListShell = React.createElement("Frame", {
					Position = if isMobile then UDim2.fromOffset(20, 184) else UDim2.fromOffset(20, 146),
					Size = if isMobile then UDim2.new(1, -40, 1, -204) else UDim2.new(0.60, -30, 1, -166),
					BackgroundColor3 = Color3.fromRGB(15, 17, 21),
					BackgroundTransparency = 0.03,
					BorderSizePixel = 0,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 12) }),
					Stroke = React.createElement("UIStroke", {
						Thickness = 1,
						Transparency = 0.2,
						Color = Color3.fromRGB(255, 225, 130),
					}),
					ListTitle = React.createElement("TextLabel", {
						Position = UDim2.fromOffset(16, 12),
						Size = UDim2.new(1, -32, 0, 18),
						BackgroundTransparency = 1,
						Text = "SELLABLE INVENTORY",
						Font = Enum.Font.GothamBold,
						TextSize = if isMobile then 12 else 11,
						TextColor3 = Color3.fromRGB(255, 225, 130),
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					List = React.createElement("ScrollingFrame", {
						Position = UDim2.fromOffset(16, 38),
						Size = UDim2.new(1, -32, 1, -54),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						CanvasSize = UDim2.fromOffset(0, 0),
						ScrollingDirection = Enum.ScrollingDirection.Y,
						ScrollBarThickness = if isMobile then 5 else 6,
					}, listChildren),
				}),
				Details = if not isMobile then React.createElement("Frame", {
					Position = UDim2.new(0.62, 10, 0, 146),
					Size = UDim2.new(0.38, -30, 1, -166),
					BackgroundColor3 = Color3.fromRGB(15, 17, 21),
					BackgroundTransparency = 0.03,
					BorderSizePixel = 0,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 12) }),
					Stroke = React.createElement("UIStroke", {
						Thickness = 1,
						Transparency = 0.2,
						Color = Color3.fromRGB(255, 225, 130),
					}),
					Label = React.createElement("TextLabel", {
						Position = UDim2.fromOffset(18, 14),
						Size = UDim2.new(1, -36, 0, 16),
						BackgroundTransparency = 1,
						Text = "SALE PREVIEW",
						Font = Enum.Font.GothamBold,
						TextSize = 11,
						TextColor3 = Color3.fromRGB(255, 225, 130),
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Card = React.createElement("Frame", {
						Position = UDim2.fromOffset(18, 40),
						Size = UDim2.new(1, -36, 0, 190),
						BackgroundColor3 = Color3.fromRGB(22, 24, 30),
						BackgroundTransparency = 0.02,
						BorderSizePixel = 0,
					}, {
						Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 12) }),
						Title = React.createElement("TextLabel", {
							Position = UDim2.fromOffset(16, 18),
							Size = UDim2.new(1, -32, 0, 46),
							BackgroundTransparency = 1,
							Text = if selectedQuartermasterItem then selectedQuartermasterItem.displayName else "Select an item",
							Font = Enum.Font.GothamBold,
							TextSize = 24,
							TextWrapped = true,
							TextColor3 = Color3.new(1, 1, 1),
							TextXAlignment = Enum.TextXAlignment.Left,
							TextYAlignment = Enum.TextYAlignment.Top,
						}),
						Source = React.createElement("TextLabel", {
							Position = UDim2.fromOffset(16, 84),
							Size = UDim2.new(1, -32, 0, 18),
							BackgroundTransparency = 1,
							Text = if selectedQuartermasterItem then string.format("%s  |  %s", sourceLabel(selectedQuartermasterItem.source), selectedQuartermasterItem.category) else "Rig and backpack items can be sold here.",
							Font = Enum.Font.Code,
							TextSize = 13,
							TextColor3 = Color3.fromRGB(210, 210, 210),
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
						Origin = React.createElement("TextLabel", {
							Position = UDim2.fromOffset(16, 108),
							Size = UDim2.new(1, -32, 0, 18),
							BackgroundTransparency = 1,
							Text = if selectedQuartermasterItem then "Origin: " .. tostring(selectedQuartermasterItem.origin or "BroughtIn") else "",
							Font = Enum.Font.Gotham,
							TextSize = 13,
							TextColor3 = Color3.fromRGB(185, 185, 185),
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
						Value = React.createElement("TextLabel", {
							Position = UDim2.fromOffset(16, 136),
							Size = UDim2.new(1, -32, 0, 30),
							BackgroundTransparency = 1,
							Text = if selectedQuartermasterItem then string.format("+%d REQ", selectedQuartermasterItem.value) else "--",
							Font = Enum.Font.GothamBold,
							TextSize = 30,
							TextColor3 = Color3.fromRGB(120, 255, 140),
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
					}),
					Policy = React.createElement("TextLabel", {
						Position = UDim2.fromOffset(18, 248),
						Size = UDim2.new(1, -36, 0, 56),
						BackgroundTransparency = 1,
						Text = "Weapons in equipped slots and stash contents are excluded to prevent accidental sales.",
						Font = Enum.Font.Gotham,
						TextSize = 14,
						TextWrapped = true,
						TextColor3 = Color3.fromRGB(195, 195, 195),
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
					}),
					Sell = React.createElement("TextButton", {
						AnchorPoint = Vector2.new(0, 1),
						Position = UDim2.new(0, 18, 1, -18),
						Size = UDim2.new(1, -36, 0, 48),
						BackgroundColor3 = if selectedQuartermasterItem == nil or quartermasterPendingItemId ~= nil then Color3.fromRGB(48, 48, 48) else Color3.fromRGB(84, 64, 28),
						BorderSizePixel = 0,
						Text = if quartermasterPendingItemId ~= nil then "Processing Sale..." elseif selectedQuartermasterItem then string.format("Sell for +%d REQ", selectedQuartermasterItem.value) else "Select an item",
						Font = Enum.Font.GothamBold,
						TextSize = 17,
						TextColor3 = Color3.new(1, 1, 1),
						Active = selectedQuartermasterItem ~= nil and quartermasterPendingItemId == nil,
						AutoButtonColor = selectedQuartermasterItem ~= nil and quartermasterPendingItemId == nil,
						[React.Event.Activated] = function()
							if selectedQuartermasterItem then
								requestSell(selectedQuartermasterItem)
							end
						end,
					}, {
						Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
					}),
				}) else nil,
				Confirm = if isMobile and quartermasterConfirmItemId ~= nil then (function()
					local confirmRow = nil :: QuartermasterRow?
					for _, row in ipairs(quartermasterState.sellableItems) do
						if row.itemId == quartermasterConfirmItemId then
							confirmRow = row
							break
						end
					end
					if confirmRow == nil then
						return nil
					end
					return React.createElement("Frame", {
						Position = UDim2.fromOffset(0, 0),
						Size = UDim2.fromScale(1, 1),
						BackgroundColor3 = Color3.new(0, 0, 0),
						BackgroundTransparency = 0.35,
						BorderSizePixel = 0,
					}, {
						Modal = React.createElement("Frame", {
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromScale(0.5, 0.5),
							Size = UDim2.new(1, -36, 0, 246),
							BackgroundColor3 = Color3.fromRGB(18, 20, 24),
							BorderSizePixel = 0,
						}, {
							Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 12) }),
							Stroke = React.createElement("UIStroke", {
								Thickness = 1,
								Transparency = 0.15,
								Color = Color3.fromRGB(255, 225, 130),
							}),
							Title = React.createElement("TextLabel", {
								Position = UDim2.fromOffset(18, 20),
								Size = UDim2.new(1, -36, 0, 28),
								BackgroundTransparency = 1,
								Text = confirmRow.displayName,
								Font = Enum.Font.GothamBold,
								TextSize = 22,
								TextColor3 = Color3.new(1, 1, 1),
							}),
							Prompt = React.createElement("TextLabel", {
								Position = UDim2.fromOffset(18, 58),
								Size = UDim2.new(1, -36, 0, 68),
								BackgroundTransparency = 1,
								Text = string.format("Sell this %s item from %s for +%d REQ?", confirmRow.category, sourceLabel(confirmRow.source), confirmRow.value),
								Font = Enum.Font.GothamMedium,
								TextSize = 18,
								TextWrapped = true,
								TextColor3 = Color3.fromRGB(230, 230, 230),
							}),
							ConfirmButton = React.createElement("TextButton", {
								Position = UDim2.fromOffset(18, 156),
								Size = UDim2.new(1, -36, 0, 42),
								BackgroundColor3 = Color3.fromRGB(84, 64, 28),
								BorderSizePixel = 0,
								Text = if quartermasterPendingItemId == confirmRow.itemId then "Processing Sale..." else "Confirm Sale",
								Font = Enum.Font.GothamBold,
								TextSize = 18,
								TextColor3 = Color3.new(1, 1, 1),
								Active = quartermasterPendingItemId == nil,
								AutoButtonColor = quartermasterPendingItemId == nil,
								[React.Event.Activated] = function()
									requestSell(confirmRow)
								end,
							}, {
								Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
							}),
							CancelButton = React.createElement("TextButton", {
								Position = UDim2.fromOffset(18, 206),
								Size = UDim2.new(1, -36, 0, 34),
								BackgroundTransparency = 1,
								Text = "Cancel",
								Font = Enum.Font.GothamBold,
								TextSize = 16,
								TextColor3 = Color3.fromRGB(255, 225, 130),
								[React.Event.Activated] = function()
									setQuartermasterConfirmItemId(nil)
								end,
							}),
						}),
					})
				end)() else nil,
			}),
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
				[React.Event.Activated] = closeTerminalUi,
			}),
			Bottom = React.createElement("TextButton", {
				Position = UDim2.new(0, 0, 0.775, 0),
				Size = UDim2.new(1, 0, 0.225, 0),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				[React.Event.Activated] = closeTerminalUi,
			}),
			Left = React.createElement("TextButton", {
				Position = UDim2.new(0, 0, 0.225, 0),
				Size = UDim2.new(0.275, 0, 0.55, 0),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				[React.Event.Activated] = closeTerminalUi,
			}),
			Right = React.createElement("TextButton", {
				Position = UDim2.new(0.725, 0, 0.225, 0),
				Size = UDim2.new(0.275, 0, 0.55, 0),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				[React.Event.Activated] = closeTerminalUi,
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
				[React.Event.Activated] = closeTerminalUi,
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
player:SetAttribute("LobbyTerminalMode", nil)
player:SetAttribute("LobbyMatchStarting", false)
applyTerminalInputMode(false)

local playerGui = player:WaitForChild("PlayerGui")
print("[LobbyClient] Creating lobby UI root")
local rootGui = Instance.new("Folder")
rootGui.Name = "_LobbyUIRoot"
rootGui.Parent = playerGui

local root = ReactRoblox.createRoot(rootGui)
root:render(React.createElement(LobbyApp))

