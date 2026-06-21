--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))

local Net = require(ReplicatedStorage.Shared.Net)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local InventoryGrid = require(ReplicatedStorage.Shared.InventoryGrid)
local ClientActionBridge = require(script.Parent.Parent.state.ClientActionBridge)
local InputModeController = require(script.Parent.Parent.state.InputModeController)
local InventoryStore = require(script.Parent.Parent.state.InventoryStore)
local LootPromptStore = require(script.Parent.Parent.state.LootPromptStore)
local RaidStore = require(script.Parent.Parent.state.RaidStore)
local BodyLootStore = require(script.Parent.Parent.state.BodyLootStore)

if not (PlaceConfig.isRaidPlace() or PlaceConfig.isLobbyPlace()) then
	return
end

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local moveItemEvent = remotes:WaitForChild(Net.MoveItemRequestEventName) :: RemoteEvent
local dropItemEvent = remotes:WaitForChild(Net.DropItemRequestEventName) :: RemoteEvent
local itemActionEvent = remotes:WaitForChild(Net.ItemActionRequestEventName) :: RemoteEvent
local raidLeaveRequestEvent = remotes:WaitForChild(Net.RaidLeaveRequestEventName) :: RemoteEvent
local bodyLootCloseEvent = remotes:WaitForChild(Net.BodyLootCloseRequestEventName) :: RemoteEvent
local bodyLootTransferEvent = remotes:WaitForChild(Net.BodyLootTransferRequestEventName) :: RemoteEvent
local stashActionEvent = remotes:FindFirstChild(Net.LobbyStashActionEventName) :: RemoteEvent?

type DragState = {
	itemId: string,
	fromContainer: string,
	sourceKind: string,
	bodyId: string?,
	startedAt: number?,
}

type HoverState = {
	toContainer: string,
	toIndex: number?,
}

type SelectedItemSource = {
	sourceKind: string,
	containerName: string,
	bodyId: string?,
}

local function applyRaidMenuInputMode(open: boolean)
	if not PlaceConfig.isRaidPlace() then
		return
	end

	player:SetAttribute("RaidMenuOpen", open)
	InputModeController.setUiLock("raid_menu", open)
end

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
	if PlaceConfig.isLobbyPlace() then
		return nil
	end

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

local function useServerNow()
	local now, setNow = React.useState(workspace:GetServerTimeNow())

	React.useEffect(function()
		local elapsed = 0
		local conn = RunService.RenderStepped:Connect(function(deltaTime)
			elapsed += deltaTime
			if elapsed >= 0.2 then
				elapsed = 0
				setNow(workspace:GetServerTimeNow())
			end
		end)

		return function()
			conn:Disconnect()
		end
	end, {})

	return now
end

local function useViewportSize()
	local viewportSize, setViewportSize = React.useState(
		if workspace.CurrentCamera then workspace.CurrentCamera.ViewportSize else Vector2.new(1280, 720)
	)

	React.useEffect(function()
		local conn = RunService.RenderStepped:Connect(function()
			local camera = workspace.CurrentCamera
			if camera then
				local nextSize = camera.ViewportSize
				if nextSize ~= viewportSize then
					setViewportSize(nextSize)
				end
			end
		end)

		return function()
			conn:Disconnect()
		end
	end, { viewportSize })

	return viewportSize
end

local function useRaidLoadingOverlay(raidState: any, snapshot: any)
	if PlaceConfig.isLobbyPlace() then
		return 1, "", "", false, "|", {}, false
	end

	local overlayTransparency, setOverlayTransparency = React.useState(0)
	local overlayText, setOverlayText = React.useState("Joining raid...")
	local overlayDetailText, setOverlayDetailText = React.useState("Establishing connection to the raid server.")
	local isLoading, setIsLoading = React.useState(true)
	local spinnerFrame, setSpinnerFrame = React.useState("|")
	local activeMarkerVisible, setActiveMarkerVisible = React.useState(true)
	local checklist, setChecklist = React.useState({
		"  Raid state received",
		"  World ready",
		"  Inventory synced",
		"  Character requested",
		"  Character replicated",
		"  Humanoid ready",
		"  Spawn positioned",
		"  Environment ready",
	})
	local fadeStartedRef = React.useRef(false)
	local stageStartedAtRef = React.useRef(os.clock())
	local lastStageRef = React.useRef("")
	local spinnerFrames = { "|", "/", "-", "\\" }

	React.useEffect(function()
		local fadeConn: RBXScriptConnection? = nil
		local tickConn: RBXScriptConnection? = nil

		local function cleanup()
			if fadeConn then
				fadeConn:Disconnect()
				fadeConn = nil
			end
			if tickConn then
				tickConn:Disconnect()
				tickConn = nil
			end
		end

		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude

		local function updateStage(stageName: string)
			if lastStageRef.current ~= stageName then
				lastStageRef.current = stageName
				stageStartedAtRef.current = os.clock()
			end
		end

		local function buildChecklist(currentIndex: number, completedCount: number): {string}
			local labels = {
				"Raid state received",
				"World ready",
				"Inventory synced",
				"Character requested",
				"Character replicated",
				"Humanoid ready",
				"Spawn positioned",
				"Environment ready",
			}
			local rows = table.create(#labels)
			for index, label in ipairs(labels) do
				if index <= completedCount then
					rows[index] = "[x] " .. label
				elseif index == currentIndex then
					rows[index] = "> " .. label
				else
					rows[index] = "  " .. label
				end
			end
			return rows
		end

		local function serverLoadPhaseMessage(loadPhase: string)
			if loadPhase == "InitializingRaid" then
				return "Joining raid...", "Raid server is initializing match state."
			end
			if loadPhase == "WaitingForInitialCharacter" then
				return "Requesting character...", "Server is creating your initial character."
			end
			if loadPhase == "CharacterReplicated" then
				return "Character replicated...", "Character model replicated. Binding raid systems."
			end
			if loadPhase == "CharacterBound" then
				return "Preparing character...", "Character connected. Waiting for spawn placement."
			end
			if loadPhase == "CharacterAlreadyPresent" then
				return "Preparing character...", "Character already exists on the raid server."
			end
			if loadPhase == "WaitingForHumanoidRootPart" then
				return "Preparing character...", "Waiting for movement root to initialize."
			end
			if loadPhase == "SelectingSpawn" then
				return "Selecting spawn...", "Choosing an insertion point for this raid."
			end
			if loadPhase == "PositioningCharacter" then
				return "Positioning player...", "Moving your character into the world."
			end
			if loadPhase == "CharacterPositioned" then
				return "Streaming environment...", "Character positioned. Waiting for nearby world to stream in."
			end
			if loadPhase == "WaitingForPartyReady" then
				return "Player ready...", "Waiting for the rest of the squad to finish loading."
			end
			if loadPhase == "RaidStarted" then
				return "Entering raid...", "Squad synchronized. Handing over control."
			end
			return nil
		end

		local function getLoadingState(): (boolean, string, string)
			if raidState == nil then
				updateStage("Joining raid...")
				setChecklist(buildChecklist(1, 0))
				return false, "Joining raid...", "Waiting for the raid server to send initial state."
			end

			if raidState.phase == "LeavingRaid" then
				updateStage("Leaving raid...")
				setChecklist(buildChecklist(8, 8))
				return false, "Leaving raid...", "Finalizing raid result and returning you to the lobby."
			end

			if raidState.phase == "WaitingForPlayers" then
				updateStage("Deploying into action...")
				setChecklist(buildChecklist(8, 8))
				return false, "Deploying into action...", "Synchronizing your deployment and waiting for all players to be ready."
			end

			if raidState.phase == "InRaid" and raidState.playerCanFight == true then
				updateStage("Entering raid...")
				setChecklist(buildChecklist(8, 8))
				return true, "Entering raid...", "Finalizing camera and handing over control."
			end

			local serverPhaseMessage: string? = nil
			local serverPhaseDetail: string? = nil
			if typeof(raidState.raidLoadPhase) == "string" then
				serverPhaseMessage, serverPhaseDetail = serverLoadPhaseMessage(raidState.raidLoadPhase)
			end

			if typeof(raidState.worldStatus) == "string" and raidState.worldStatus ~= "World loaded: Workspace.Maps.Level0" then
				updateStage(serverPhaseMessage or "Loading world...")
				setChecklist(buildChecklist(2, 1))
				return false, serverPhaseMessage or "Loading world...", serverPhaseDetail or raidState.worldStatus
			end

			if snapshot == nil then
				updateStage(serverPhaseMessage or "Syncing loadout...")
				setChecklist(buildChecklist(3, 2))
				return false, serverPhaseMessage or "Syncing loadout...", serverPhaseDetail or "Waiting for inventory and equipped item state."
			end

			if typeof(raidState.raidLoadPhase) == "string" and raidState.raidLoadPhase == "WaitingForInitialCharacter" then
				updateStage(serverPhaseMessage or "Requesting character...")
				setChecklist(buildChecklist(4, 3))
				return false, serverPhaseMessage or "Requesting character...", serverPhaseDetail or "Server is creating your initial character."
			end

			local character = player.Character
			if not character then
				updateStage(serverPhaseMessage or "Spawning character...")
				local waitedSeconds = math.floor(os.clock() - stageStartedAtRef.current)
				setChecklist(buildChecklist(5, 4))
				return false, serverPhaseMessage or "Spawning character...", serverPhaseDetail or string.format("World ready. Loadout synced. Waiting for your character model to replicate from the server. (%ds)", waitedSeconds)
			end

			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid then
				updateStage(serverPhaseMessage or "Preparing character...")
				setChecklist(buildChecklist(6, 5))
				return false, serverPhaseMessage or "Preparing character...", serverPhaseDetail or "Waiting for humanoid components to initialize."
			end

			local root = character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then
				updateStage(serverPhaseMessage or "Preparing character...")
				setChecklist(buildChecklist(6, 5))
				return false, serverPhaseMessage or "Preparing character...", serverPhaseDetail or "Waiting for movement and camera anchor parts."
			end

			setChecklist(buildChecklist(7, 6))

			overlapParams.FilterDescendantsInstances = { character }
			local nearbyParts = workspace:GetPartBoundsInBox(root.CFrame, Vector3.new(80, 40, 80), overlapParams)
			if #nearbyParts < 12 then
				updateStage(serverPhaseMessage or "Streaming environment...")
				setChecklist(buildChecklist(8, 7))
				local waitedSeconds = math.floor(os.clock() - stageStartedAtRef.current)
				if waitedSeconds < 5 then
					return false, serverPhaseMessage or "Streaming environment...", serverPhaseDetail or string.format("Loading nearby geometry and props. (%d/12 ready, %ds)", #nearbyParts, waitedSeconds)
				end
			end

			updateStage("Entering raid...")
			setChecklist(buildChecklist(8, 8))
			return true, "Entering raid...", "Finalizing camera and handing over control."
		end

		tickConn = RunService.RenderStepped:Connect(function()
			local ready, message, detail = getLoadingState()
			setOverlayText(message)
			setOverlayDetailText(detail)

			if ready then
				if not fadeStartedRef.current then
					fadeStartedRef.current = true
					setIsLoading(false)
					if tickConn then
						tickConn:Disconnect()
						tickConn = nil
					end

					local startedAt = os.clock()
					fadeConn = RunService.RenderStepped:Connect(function()
						local alpha = math.clamp((os.clock() - startedAt) / 0.8, 0, 1)
						setOverlayTransparency(alpha)
						if alpha >= 1 then
							if fadeConn then
								fadeConn:Disconnect()
								fadeConn = nil
							end
						end
					end)
				end
			else
				if not isLoading then
					setIsLoading(true)
				end
				fadeStartedRef.current = false
				setOverlayTransparency(0)
			end
		end)

		return function()
			cleanup()
		end
	end, { raidState, snapshot })

	React.useEffect(function()
		if not isLoading then
			setSpinnerFrame("|")
			setActiveMarkerVisible(true)
			return
		end

		local conn = RunService.RenderStepped:Connect(function()
			local frameIndex = math.floor(os.clock() * 10) % #spinnerFrames + 1
			setSpinnerFrame(spinnerFrames[frameIndex])
			setActiveMarkerVisible(math.floor(os.clock() * 2) % 2 == 0)
		end)

		return function()
			conn:Disconnect()
		end
	end, { isLoading })

	return overlayTransparency, overlayText, overlayDetailText, isLoading, spinnerFrame, checklist, activeMarkerVisible
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

local function loadingStepLabel(text: string, layoutOrder: number, activeMarkerVisible: boolean, compact: boolean?)
	local isActive = string.sub(text, 1, 1) == ">"
	local isDone = string.sub(text, 1, 3) == "[x]"
	local displayText = text
	if isActive and not activeMarkerVisible then
		displayText = "  " .. string.sub(text, 3)
	end

	return React.createElement("TextLabel", {
		LayoutOrder = layoutOrder,
		Size = UDim2.new(1, 0, 0, if compact then 15 else 18),
		BackgroundTransparency = 1,
		Text = displayText,
		Font = Enum.Font.Code,
		TextSize = if compact then 11 else 13,
		TextColor3 = if isActive
			then Color3.fromRGB(255, 225, 130)
			elseif isDone
			then Color3.fromRGB(210, 210, 210)
			else Color3.fromRGB(130, 130, 130),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 51,
	})
end

local function mobileActionButton(text: string, position: UDim2, size: UDim2, onActivated: () -> (), anchorPoint: Vector2?)
	local isCompact = size.X.Offset <= 60 or size.Y.Offset <= 52
	return React.createElement("TextButton", {
		AnchorPoint = anchorPoint or Vector2.new(1, 1),
		Position = position,
		Size = size,
		BackgroundColor3 = Color3.fromRGB(12, 14, 18),
		BackgroundTransparency = 0.28,
		BorderSizePixel = 0,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = if isCompact then 13 else 16,
		TextColor3 = Color3.fromRGB(255, 225, 130),
		AutoButtonColor = true,
		ZIndex = 40,
		[React.Event.Activated] = onActivated,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
		Fill = React.createElement("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 34, 42)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 14, 18)),
			}),
		}),
		Stroke = React.createElement("UIStroke", {
			Thickness = 1,
			Transparency = 0.18,
			Color = Color3.fromRGB(255, 225, 130),
		}),
	})
end

local function mobileRoundButton(text: string, position: UDim2, diameter: number, onActivated: () -> (), anchorPoint: Vector2?)
	return React.createElement("TextButton", {
		AnchorPoint = anchorPoint or Vector2.new(1, 1),
		Position = position,
		Size = UDim2.fromOffset(diameter, diameter),
		BackgroundColor3 = Color3.fromRGB(58, 64, 76),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = if diameter <= 58 then 12 else 14,
		TextColor3 = Color3.fromRGB(255, 236, 156),
		AutoButtonColor = true,
		ZIndex = 40,
		[React.Event.Activated] = onActivated,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Fill = React.createElement("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(92, 100, 118)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(44, 50, 62)),
			}),
		}),
		Stroke = React.createElement("UIStroke", {
			Thickness = 1,
			Transparency = 0.08,
			Color = Color3.fromRGB(255, 236, 156),
		}),
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

local function sendLobbyStashActionRequest(action: {[string]: any})
	if stashActionEvent then
		stashActionEvent:FireServer(action)
	end
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
	onActivate: (() -> ())?,
	onDragStart: (() -> ())?,
	onHoverChanged: ((boolean) -> ())?,
	onRightClick: (() -> ())?,
	compact: boolean?
)
	return React.createElement("TextButton", {
		LayoutOrder = layoutOrder,
		Size = UDim2.new(1, 0, 0, if compact then 22 else 24),
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
		TextSize = if compact then 12 else 14,
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
		[React.Event.Activated] = function()
			if onActivate then
				onActivate()
			elseif onDragStart then
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
			PaddingLeft = UDim.new(0, if compact then 6 else 8),
			PaddingRight = UDim.new(0, if compact then 6 else 8),
		}),
		Stroke = React.createElement("UIStroke", {
			Thickness = if isSelected or isHovered then 1.5 else 1,
			Transparency = if isSelected or isHovered then 0 else 0.45,
			Color = if isSelected or isHovered then Color3.fromRGB(255, 225, 130) else Color3.fromRGB(90, 90, 90),
		}),
	})
end

local function containerGridSlot(
	snapshot: any,
	itemId: string?,
	slotIndex: number,
	isDragging: boolean,
	isHovered: boolean,
	isSelected: boolean,
	onActivate: (() -> ())?,
	onDragStart: (() -> ())?,
	onHoverChanged: ((boolean) -> ())?,
	onRightClick: (() -> ())?,
	compact: boolean?
)
	local item = if snapshot and itemId then snapshot.itemsById[itemId] else nil
	local isOccupied = itemId ~= nil
	local accentColor = if isSelected
		then Color3.fromRGB(255, 225, 130)
		elseif isHovered
		then Color3.fromRGB(200, 170, 86)
		elseif isOccupied
		then Color3.fromRGB(74, 88, 104)
		else Color3.fromRGB(52, 56, 64)
	local categoryText = if item and item.category then string.upper(tostring(item.category)) else "EMPTY"
	local nameText = if isOccupied then itemLabel(snapshot, itemId) else "Empty Slot"

	return React.createElement("TextButton", {
		LayoutOrder = slotIndex,
		Size = UDim2.fromScale(1, 1),
		AutoButtonColor = false,
		BackgroundTransparency = if isSelected then 0.08 elseif isHovered then 0.12 elseif isDragging then 0.18 else 0.22,
		BackgroundColor3 = if isSelected
			then Color3.fromRGB(34, 32, 22)
			elseif isHovered
			then Color3.fromRGB(30, 28, 22)
			elseif isDragging
			then Color3.fromRGB(32, 32, 32)
			else Color3.fromRGB(16, 18, 22),
		BorderSizePixel = 0,
		Text = "",
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
		[React.Event.Activated] = function()
			if onActivate then
				onActivate()
			elseif onDragStart then
				onDragStart()
			end
		end,
		[React.Event.MouseButton2Click] = function()
			if onRightClick then
				onRightClick()
			end
		end,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, if compact then 8 else 10) }),
		Fill = React.createElement("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, if isSelected then Color3.fromRGB(42, 38, 24) else Color3.fromRGB(24, 28, 34)),
				ColorSequenceKeypoint.new(1, if isSelected then Color3.fromRGB(16, 15, 12) else Color3.fromRGB(10, 12, 16)),
			}),
		}),
		Stroke = React.createElement("UIStroke", {
			Thickness = if isSelected or isHovered then 1.5 else 1,
			Transparency = if isSelected then 0.02 elseif isHovered then 0.08 else 0.22,
			Color = if isSelected or isHovered then Color3.fromRGB(255, 225, 130) else Color3.fromRGB(76, 84, 96),
		}),
		TopAccent = React.createElement("Frame", {
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.new(1, 0, 0, 3),
			BackgroundColor3 = accentColor,
			BorderSizePixel = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 999) }),
		}),
		SlotIndex = React.createElement("TextLabel", {
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.new(0, 42, 0, 14),
			BackgroundTransparency = 1,
			Text = string.format("[%02d]", slotIndex),
			Font = Enum.Font.Code,
			TextSize = if compact then 10 else 11,
			TextColor3 = Color3.fromRGB(255, 225, 130),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Category = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 8),
			Size = UDim2.new(0, if compact then 62 else 74, 0, 16),
			BackgroundTransparency = 1,
			Text = categoryText,
			Font = Enum.Font.Code,
			TextSize = if compact then 9 else 10,
			TextColor3 = if isOccupied then Color3.fromRGB(184, 194, 206) else Color3.fromRGB(124, 128, 136),
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
		Name = React.createElement("TextLabel", {
			Position = UDim2.fromOffset(10, if compact then 28 else 30),
			Size = UDim2.new(1, -20, 1, if compact then -36 else -40),
			BackgroundTransparency = 1,
			Text = nameText,
			Font = Enum.Font.GothamBold,
			TextSize = if compact then 12 else 13,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = if isOccupied then Color3.new(1, 1, 1) else Color3.fromRGB(148, 152, 158),
			TextXAlignment = Enum.TextXAlignment.Left,
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
	openContextMenuForItem: (string, string, string, string?) -> (),
	moveDraggedItemToCell: ((string, number?) -> ())?,
	activateGridItem: ((string, string) -> ())?,
	draggedItem: any?,
	compact: boolean?,
	allowDrag: boolean?,
	displayMode: string?
)
	local container = snapshot and snapshot[containerName] or nil
	local capacity = if container then container.capacity else 0
	local itemIds = if container then container.itemIds else {}
	local useGrid = displayMode == "grid"
	local gridCellPixels = if compact then (if containerName == "stash" then 30 else 42) else if containerName == "stash" then 46 else 54
	local children: {[string]: any} = if useGrid then {} else {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, if compact then 4 else 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	if useGrid then
		local packedItems, occupiedCells, columns, rows = InventoryGrid.pack(itemIds, snapshot and snapshot.itemsById or nil, capacity, containerName)
		local previewCells: {[number]: boolean} = {}
		local previewValid = false
		if dragState and hoverState and hoverState.toContainer == containerName and hoverState.toIndex and draggedItem then
			local anchorIndex = hoverState.toIndex
			local anchorX = ((anchorIndex - 1) % columns) + 1
			local anchorY = math.floor((anchorIndex - 1) / columns) + 1
			local previewSize = InventoryGrid.getItemSize(draggedItem)
			local ignoreItemId = if dragState.sourceKind == "player" and dragState.fromContainer == containerName then dragState.itemId else nil
			previewValid = InventoryGrid.canFitAt(
				itemIds,
				snapshot and snapshot.itemsById or nil,
				capacity,
				containerName,
				draggedItem,
				anchorIndex,
				ignoreItemId
			)

			for yy = anchorY, math.min(rows, anchorY + previewSize.height - 1) do
				for xx = anchorX, math.min(columns, anchorX + previewSize.width - 1) do
					local previewIndex = (yy - 1) * columns + xx
					if previewIndex >= 1 and previewIndex <= capacity then
						previewCells[previewIndex] = true
					end
				end
			end
		end

		local cellChildren: {[string]: any} = {}
		for slotIndex = 1, capacity do
			local x = ((slotIndex - 1) % columns) + 1
			local y = math.floor((slotIndex - 1) / columns) + 1
			local cellHovered = hoverState ~= nil and hoverState.toContainer == containerName and hoverState.toIndex == slotIndex
			local cellPreviewed = previewCells[slotIndex] == true
			cellChildren["Cell" .. slotIndex] = React.createElement("Frame", {
				Position = UDim2.fromOffset((x - 1) * gridCellPixels, (y - 1) * gridCellPixels),
				Size = UDim2.fromOffset(gridCellPixels, gridCellPixels),
				BackgroundColor3 = if cellPreviewed and previewValid
					then Color3.fromRGB(39, 58, 34)
					elseif cellPreviewed
					then Color3.fromRGB(78, 30, 30)
					elseif cellHovered
					then Color3.fromRGB(56, 46, 24)
					elseif occupiedCells[slotIndex]
					then Color3.fromRGB(18, 20, 24)
					else Color3.fromRGB(8, 9, 11),
				BackgroundTransparency = if cellPreviewed or cellHovered then 0.0 else 0.04,
				BorderSizePixel = 0,
				ZIndex = 1,
			}, {
				Stroke = React.createElement("UIStroke", {
					Thickness = if cellPreviewed or cellHovered then 2 else 1,
					Transparency = if cellPreviewed or cellHovered then 0.05 else 0.38,
					Color = if cellPreviewed and previewValid
						then Color3.fromRGB(112, 220, 124)
						elseif cellPreviewed
						then Color3.fromRGB(235, 92, 82)
						elseif cellHovered
						then Color3.fromRGB(255, 225, 130)
						else Color3.fromRGB(47, 54, 64),
				}),
				Target = React.createElement("TextButton", {
					Position = UDim2.fromOffset(0, 0),
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = "",
					AutoButtonColor = false,
					ZIndex = 2,
					[React.Event.MouseEnter] = function()
						if dragState and allowDrag ~= false then
							setHoverState({
								toContainer = containerName,
								toIndex = slotIndex,
							})
						end
					end,
					[React.Event.MouseLeave] = function()
						if cellHovered then
							setHoverState(nil)
						end
					end,
					[React.Event.Activated] = function()
						if dragState and allowDrag ~= false and moveDraggedItemToCell then
							moveDraggedItemToCell(containerName, if cellPreviewed and hoverState then hoverState.toIndex else slotIndex)
						end
					end,
				}),
			})
		end

		local itemChildren: {[string]: any} = {}
		for index, packed in ipairs(packedItems) do
			local itemId = packed.itemId
			local item = snapshot and snapshot.itemsById and snapshot.itemsById[itemId] or nil
			local categoryText = if item and item.category then string.upper(tostring(item.category)) else "ITEM"
			local isSelected = selectedItemId ~= nil and selectedItemId == itemId
			local isDragging = dragState ~= nil and dragState.itemId == itemId
			local isHovered = hoverState ~= nil and hoverState.toContainer == containerName and hoverState.toIndex == nil
			local titleHeight = math.max(16, math.min(26, packed.height * gridCellPixels - 20))

			itemChildren["Item" .. index] = React.createElement("TextButton", {
				Position = UDim2.fromOffset((packed.x - 1) * gridCellPixels + 1, (packed.y - 1) * gridCellPixels + 1),
				Size = UDim2.fromOffset(packed.width * gridCellPixels - 2, packed.height * gridCellPixels - 2),
				BackgroundColor3 = if isSelected
					then Color3.fromRGB(38, 34, 22)
					elseif isDragging
					then Color3.fromRGB(34, 34, 34)
					else Color3.fromRGB(14, 16, 20),
				BackgroundTransparency = if isDragging then 0.28 else 0.02,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = itemId ~= nil,
				ZIndex = 3,
				[React.Event.MouseEnter] = function()
					if dragState and allowDrag ~= false then
						setHoverState({
							toContainer = containerName,
							toIndex = ((packed.y - 1) * columns) + packed.x,
						})
					end
				end,
				[React.Event.MouseLeave] = function()
					if isHovered then
						setHoverState(nil)
					end
				end,
				[React.Event.MouseButton1Down] = function()
					if compact or allowDrag == false or isMobile then
						return
					end

					setDragState({
						itemId = itemId,
						fromContainer = containerName,
						sourceKind = "player",
						bodyId = nil,
						startedAt = os.clock(),
					})
					setHoverState({
						toContainer = containerName,
						toIndex = ((packed.y - 1) * columns) + packed.x,
					})
				end,
				[React.Event.Activated] = function()
					if dragState and allowDrag ~= false and moveDraggedItemToCell then
						if dragState.itemId == itemId and activateGridItem then
							activateGridItem(itemId, containerName)
							return
						end
						moveDraggedItemToCell(containerName, ((packed.y - 1) * columns) + packed.x)
						return
					end
					if compact then
						openContextMenuForItem(itemId, "player", containerName, nil)
					elseif activateGridItem then
						activateGridItem(itemId, containerName)
					elseif allowDrag ~= false then
						setDragState({
							itemId = itemId,
							fromContainer = containerName,
							sourceKind = "player",
							bodyId = nil,
							startedAt = os.clock(),
						})
						setHoverState({
							toContainer = containerName,
							toIndex = nil,
						})
					else
						openContextMenuForItem(itemId, "player", containerName, nil)
					end
				end,
				[React.Event.MouseButton2Click] = function()
					openContextMenuForItem(itemId, "player", containerName, nil)
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
				Fill = React.createElement("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, if isSelected then Color3.fromRGB(46, 40, 24) else Color3.fromRGB(25, 29, 35)),
						ColorSequenceKeypoint.new(1, if isSelected then Color3.fromRGB(14, 13, 10) else Color3.fromRGB(8, 10, 13)),
					}),
				}),
				Stroke = React.createElement("UIStroke", {
					Thickness = if isSelected then 2 else 1,
					Transparency = if isSelected then 0.04 else 0.16,
					Color = if isSelected then Color3.fromRGB(255, 225, 130) else Color3.fromRGB(86, 96, 110),
				}),
				Category = React.createElement("TextLabel", {
					Position = UDim2.fromOffset(6, 5),
					Size = UDim2.new(1, -12, 0, 12),
					BackgroundTransparency = 1,
					Text = categoryText,
					Font = Enum.Font.Code,
					TextSize = if compact then 8 else 9,
					TextColor3 = Color3.fromRGB(255, 225, 130),
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 4,
				}),
				Name = React.createElement("TextLabel", {
					Position = UDim2.fromOffset(6, 20),
					Size = UDim2.new(1, -12, 0, titleHeight),
					BackgroundTransparency = 1,
					Text = itemLabel(snapshot, itemId),
					Font = Enum.Font.GothamBold,
					TextSize = if compact then 10 else 12,
					TextWrapped = true,
					TextColor3 = Color3.fromRGB(236, 238, 241),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 4,
				}),
			})
		end

		children.Cells = React.createElement("Frame", {
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromOffset(columns * gridCellPixels, rows * gridCellPixels),
			BackgroundTransparency = 1,
			ZIndex = 1,
		}, cellChildren)
		children.Items = React.createElement("Frame", {
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromOffset(columns * gridCellPixels, rows * gridCellPixels),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, itemChildren)
	else
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

			local onActivate = if isOccupied and compact then function()
				openContextMenuForItem(itemId :: string, "player", containerName, nil)
			end else nil
			local onDragStart = if isOccupied and allowDrag ~= false then function()
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
			end else nil
			local onHoverChanged = if dragState and allowDrag ~= false then function(isInside)
				if isInside then
					setHoverState({
						toContainer = containerName,
						toIndex = slotIndex,
					})
				elseif isHovered then
					setHoverState(nil)
				end
			end else nil
			local onRightClick = if isOccupied then function()
				openContextMenuForItem(itemId :: string, "player", containerName, nil)
			end else nil

			children["Slot" .. slotIndex] = containerSlot(
				if isOccupied then itemLabel(snapshot, itemId) else string.format("[%d] Empty", slotIndex),
				slotIndex,
				isOccupied,
				isDragging,
				isHovered,
				selectedItemId ~= nil and selectedItemId == itemId,
				onActivate,
				onDragStart,
				onHoverChanged,
				onRightClick,
				compact
			)
		end
	end

	return React.createElement("Frame", {
		AnchorPoint = Vector2.new(0, 0),
		Position = position,
		Size = size,
		BackgroundTransparency = 0.2,
		BackgroundColor3 = Color3.fromRGB(24, 24, 24),
		BorderSizePixel = 0,
		[React.Event.MouseEnter] = function()
			if dragState and allowDrag ~= false then
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
			Size = UDim2.new(1, -20, 0, if compact then 20 else 22),
			BackgroundTransparency = 1,
			Text = title,
			Font = Enum.Font.GothamBold,
			TextSize = if compact then 13 else 15,
			TextColor3 = Color3.fromRGB(255, 225, 130),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Count = if useGrid then React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 8),
			Size = UDim2.new(0, if compact then 72 else 86, 0, 16),
			BackgroundTransparency = 1,
			Text = string.format("%d/%d", InventoryGrid.countUsedUnits(itemIds, snapshot and snapshot.itemsById or nil), capacity),
			Font = Enum.Font.Code,
			TextSize = if compact then 10 else 11,
			TextColor3 = Color3.fromRGB(255, 225, 130),
			TextXAlignment = Enum.TextXAlignment.Right,
		}) else nil,
		List = React.createElement("ScrollingFrame", {
			Position = UDim2.fromOffset(10, if useGrid then 34 else (if compact then 30 else 34)),
			Size = UDim2.new(1, -20, 1, if useGrid then -44 else (if compact then -38 else -44)),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = if useGrid
				then UDim2.new(0, 0, 0, math.ceil(math.max(1, capacity) / InventoryGrid.getContainerColumns(capacity, containerName)) * gridCellPixels)
				else UDim2.new(0, 0, 0, math.max(0, capacity * (if compact then 26 else 30))),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = if compact then 4 else 6,
			ScrollBarImageColor3 = Color3.fromRGB(110, 110, 110),
			[React.Event.MouseEnter] = function()
				if dragState and allowDrag ~= false then
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
	setDragState: (DragState?) -> (),
	openContextMenuForItem: (string, string, string, string?) -> (),
	compact: boolean?
)
	local capacity = bodySnapshot and bodySnapshot.capacity or 0
	local itemIds = bodySnapshot and bodySnapshot.itemIds or {}
	local children: {[string]: any} = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, if compact then 4 else 6),
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
			if itemId and compact then function()
				openContextMenuForItem(itemId, "body", "body", bodySnapshot.bodyId)
			end else nil,
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
			nil,
			compact
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
			Size = UDim2.new(1, -20, 0, if compact then 20 else 22),
			BackgroundTransparency = 1,
			Text = "Body Loot",
			Font = Enum.Font.GothamBold,
			TextSize = if compact then 13 else 15,
			TextColor3 = Color3.fromRGB(255, 225, 130),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		List = React.createElement("ScrollingFrame", {
			Position = UDim2.fromOffset(10, if compact then 30 else 34),
			Size = UDim2.new(1, -20, 1, if compact then -38 else -44),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(0, 0, 0, math.max(0, capacity * (if compact then 26 else 30))),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = if compact then 4 else 6,
			ScrollBarImageColor3 = Color3.fromRGB(110, 110, 110),
		}, children),
	})
end

local function weaponSlotCard(
	snapshot: any,
	position: UDim2,
	size: UDim2,
	selectedItemId: string?,
	openContextMenuForItem: (string, string, string, string?) -> (),
	compact: boolean?
)
	local rows = {
		{ label = "PrimaryA", itemId = snapshot and snapshot.weaponSlots.PrimaryA or nil },
		{ label = "PrimaryB", itemId = snapshot and snapshot.weaponSlots.PrimaryB or nil },
		{ label = "Pistol", itemId = snapshot and snapshot.weaponSlots.Pistol or nil },
		{ label = "Melee", itemId = snapshot and snapshot.weaponSlots.Melee or nil },
	}

	local useGrid = not compact
	local children: {[string]: any} = if useGrid then {} else {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	if useGrid then
		local function attachmentBay(label: string, order: number, filledText: string?)
			return React.createElement("Frame", {
				LayoutOrder = order,
				Size = UDim2.fromOffset(38, 38),
				BackgroundColor3 = if filledText then Color3.fromRGB(18, 48, 34) else Color3.fromRGB(10, 12, 15),
				BackgroundTransparency = 0.04,
				BorderSizePixel = 0,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = if filledText then 0.06 else 0.36,
					Color = if filledText then Color3.fromRGB(58, 220, 130) else Color3.fromRGB(66, 74, 84),
				}),
				Label = React.createElement("TextLabel", {
					Position = UDim2.fromOffset(3, 3),
					Size = UDim2.new(1, -6, 0, 10),
					BackgroundTransparency = 1,
					Text = string.upper(label),
					Font = Enum.Font.Code,
					TextSize = 7,
					TextColor3 = Color3.fromRGB(255, 225, 130),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Value = React.createElement("TextLabel", {
					Position = UDim2.fromOffset(4, 15),
					Size = UDim2.new(1, -8, 1, -18),
					BackgroundTransparency = 1,
					Text = filledText or "",
					Font = Enum.Font.GothamBold,
					TextSize = 8,
					TextWrapped = true,
					TextColor3 = Color3.fromRGB(230, 235, 232),
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
				}),
			})
		end

		local function equipmentCard(row: any, position: UDim2, cardSize: UDim2, isLarge: boolean)
			local itemId = row.itemId
			if itemId == "" then
				itemId = nil
			end
			local item = itemId and snapshot and snapshot.itemsById and snapshot.itemsById[itemId] or nil
			local attachedMagId = item and item.attachedMagId or nil
			local attachedMag = attachedMagId and snapshot and snapshot.itemsById and snapshot.itemsById[attachedMagId] or nil
			local isEquipped = snapshot and snapshot.equippedSlot == row.label

			return React.createElement("TextButton", {
				Position = position,
				Size = cardSize,
				BackgroundColor3 = if isEquipped then Color3.fromRGB(20, 52, 36) elseif selectedItemId ~= nil and selectedItemId == itemId then Color3.fromRGB(38, 34, 22) else Color3.fromRGB(12, 14, 18),
				BackgroundTransparency = 0.04,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = itemId ~= nil,
				[React.Event.Activated] = function()
					if itemId then
						openContextMenuForItem(itemId, "player", row.label, nil)
					end
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Fill = React.createElement("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, if isEquipped then Color3.fromRGB(20, 84, 52) else Color3.fromRGB(22, 25, 31)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 8, 11)),
					}),
				}),
				Stroke = React.createElement("UIStroke", {
					Thickness = if isEquipped or selectedItemId == itemId then 2 else 1,
					Transparency = if isEquipped or selectedItemId == itemId then 0.03 else 0.22,
					Color = if isEquipped then Color3.fromRGB(58, 220, 130) elseif selectedItemId == itemId then Color3.fromRGB(255, 225, 130) else Color3.fromRGB(76, 84, 96),
				}),
				Title = React.createElement("TextLabel", {
					Position = UDim2.fromOffset(10, 8),
					Size = UDim2.new(1, -20, 0, 13),
					BackgroundTransparency = 1,
					Text = string.format("[%d] %s", if row.label == "PrimaryA" then 1 elseif row.label == "PrimaryB" then 2 elseif row.label == "Pistol" then 3 else 4, string.upper(row.label)),
					Font = Enum.Font.Code,
					TextSize = 9,
					TextColor3 = Color3.fromRGB(255, 225, 130),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Value = React.createElement("TextLabel", {
					Position = UDim2.fromOffset(12, if isLarge then 30 else 28),
					Size = if isLarge then UDim2.new(1, -186, 1, -40) else UDim2.new(1, -24, 0, 26),
					BackgroundTransparency = 1,
					Text = itemLabel(snapshot, itemId),
					Font = Enum.Font.GothamBold,
					TextSize = if isLarge then 15 else 12,
					TextWrapped = true,
					TextColor3 = if itemId then Color3.new(1, 1, 1) else Color3.fromRGB(150, 154, 160),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
				}),
				Active = if isEquipped then React.createElement("TextLabel", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -10, 0, 8),
					Size = UDim2.fromOffset(90, 14),
					BackgroundTransparency = 1,
					Text = "ACTIVE",
					Font = Enum.Font.Code,
					TextSize = 10,
					TextColor3 = Color3.fromRGB(58, 220, 130),
					TextXAlignment = Enum.TextXAlignment.Right,
				}) else nil,
				AttachmentBays = if isLarge then React.createElement("Frame", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -10, 0, 30),
					Size = UDim2.fromOffset(168, 86),
					BackgroundTransparency = 1,
				}, {
					Layout = React.createElement("UIGridLayout", {
						CellSize = UDim2.fromOffset(38, 38),
						CellPadding = UDim2.fromOffset(5, 5),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					Mag = attachmentBay("MAG", 1, attachedMag and tostring(attachedMag.ammo or "--") or nil),
					Optic = attachmentBay("OPTIC", 2, nil),
					Muzzle = attachmentBay("MUZ", 3, nil),
					Tac = attachmentBay("TAC", 4, nil),
				}) else nil,
			})
		end

		children.PrimaryA = equipmentCard(rows[1], UDim2.fromOffset(10, 36), UDim2.new(0.58, -18, 0, 68), true)
		children.PrimaryB = equipmentCard(rows[2], UDim2.fromOffset(10, 112), UDim2.new(0.58, -18, 0, 68), true)
		children.Pistol = equipmentCard(rows[3], UDim2.new(0.58, 4, 0, 36), UDim2.new(0.42, -14, 0, 68), false)
		children.Melee = equipmentCard(rows[4], UDim2.new(0.58, 4, 0, 112), UDim2.new(0.42, -14, 0, 68), false)
	else
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
				if itemId and compact then function()
					openContextMenuForItem(itemId, "player", row.label, nil)
				end else nil,
				nil,
				nil,
				if itemId then function()
					openContextMenuForItem(itemId, "player", row.label, nil)
				end else nil,
				compact
			)
		end

		children.Equipped = React.createElement("TextLabel", {
			LayoutOrder = 99,
			Size = UDim2.new(1, 0, 0, if compact then 20 else 22),
			BackgroundTransparency = 1,
			Text = string.format("Equipped: %s", snapshot and (snapshot.equippedSlot or "None") or "None"),
			Font = Enum.Font.Code,
			TextSize = if compact then 12 else 14,
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
			Size = UDim2.new(1, -20, 0, if compact then 20 else 22),
			BackgroundTransparency = 1,
			Text = "Equipment",
			Font = Enum.Font.GothamBold,
			TextSize = if compact then 13 else 15,
			TextColor3 = Color3.fromRGB(255, 225, 130),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		List = React.createElement("Frame", {
			Position = if useGrid then UDim2.fromOffset(0, 0) else UDim2.fromOffset(10, if compact then 30 else 34),
			Size = if useGrid then UDim2.fromScale(1, 1) else UDim2.new(1, -20, 1, if compact then -38 else -44),
			BackgroundTransparency = 1,
		}, children),
	})
end

local function mobileLobbyInventorySummaryCard(
	snapshot: any,
	position: UDim2,
	size: UDim2,
	selectedItemId: string?,
	openContextMenuForItem: (string, string, string, string?) -> ()
)
	local children: {[string]: any} = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	local layoutOrder = 1

	local function addHeader(text: string)
		children["Header" .. layoutOrder] = React.createElement("TextLabel", {
			LayoutOrder = layoutOrder,
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			Text = text,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = Color3.fromRGB(255, 225, 130),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		layoutOrder += 1
	end

	local function addSlotRow(labelText: string, itemId: string?, containerName: string)
		children["Row" .. layoutOrder] = containerSlot(
			labelText,
			layoutOrder,
			itemId ~= nil,
			false,
			false,
			selectedItemId ~= nil and selectedItemId == itemId,
			if itemId then function()
				openContextMenuForItem(itemId, "player", containerName, nil)
			end else nil,
			nil,
			nil,
			if itemId then function()
				openContextMenuForItem(itemId, "player", containerName, nil)
			end else nil,
			true
		)
		layoutOrder += 1
	end

	local weaponRows = {
		{ label = "PrimaryA", itemId = snapshot and snapshot.weaponSlots.PrimaryA or nil, container = "PrimaryA" },
		{ label = "PrimaryB", itemId = snapshot and snapshot.weaponSlots.PrimaryB or nil, container = "PrimaryB" },
		{ label = "Pistol", itemId = snapshot and snapshot.weaponSlots.Pistol or nil, container = "Pistol" },
		{ label = "Melee", itemId = snapshot and snapshot.weaponSlots.Melee or nil, container = "Melee" },
	}

	addHeader("Weapons")
	for _, row in ipairs(weaponRows) do
		addSlotRow(string.format("%s: %s", row.label, itemLabel(snapshot, row.itemId)), row.itemId, row.container)
	end

	local function addContainerSection(title: string, containerName: string)
		local container = snapshot and snapshot[containerName] or nil
		addHeader(title)
		if typeof(container) ~= "table" or typeof(container.capacity) ~= "number" then
			return
		end

		for slotIndex = 1, container.capacity do
			local itemId = container.itemIds and container.itemIds[slotIndex] or nil
			if itemId == "" then
				itemId = nil
			end
			addSlotRow(
				if itemId then itemLabel(snapshot, itemId) else string.format("[%d] Empty", slotIndex),
				itemId,
				containerName
			)
		end
	end

	addContainerSection("Rig", "rig")
	addContainerSection("Backpack", "backpack")

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
			Size = UDim2.new(1, -20, 0, 20),
			BackgroundTransparency = 1,
			Text = "Inventory",
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(255, 225, 130),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		List = React.createElement("ScrollingFrame", {
			Position = UDim2.fromOffset(10, 30),
			Size = UDim2.new(1, -20, 1, -38),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.fromOffset(0, 0),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = Color3.fromRGB(110, 110, 110),
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
	local now = useServerNow()
	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local isRaidPlace = PlaceConfig.isRaidPlace()
	local isLobbyPlace = PlaceConfig.isLobbyPlace()
	local viewportSize = useViewportSize()
	local snapshot = useSnapshot()
	local inventoryVisible = useInventoryVisible()
	local lootPrompt = useLootPrompt()
	local raidState = useRaidState()
	local bodyLootSnapshot = useBodyLootSnapshot()
	local timedCheckMagText = useTimedCheckMagText(snapshot)
	local loadingOverlayTransparency, loadingOverlayText, loadingOverlayDetailText, isRaidLoading, loadingSpinnerFrame, loadingChecklist, loadingActiveMarkerVisible = useRaidLoadingOverlay(raidState, snapshot)
	local dragState, setDragState = React.useState(nil :: DragState?)
	local hoverState, setHoverState = React.useState(nil :: HoverState?)
	local selectedItemId, setSelectedItemId = React.useState(nil :: string?)
	local selectedItemSource, setSelectedItemSource = React.useState(nil :: SelectedItemSource?)
	local lastGridClickRef = React.useRef({ itemId = "", clickedAt = 0 })
	local menuOpen, setMenuOpen = React.useState(false)
	local menuPosition, setMenuPosition = React.useState(UDim2.fromOffset(0, 0))
	local extractsVisible, setExtractsVisible = React.useState(false)
	local escapeMenuOpen, setEscapeMenuOpen = React.useState(false)
	local mobileUtilityOpen, setMobileUtilityOpen = React.useState(false)
	local mobileInventoryPage, setMobileInventoryPage = React.useState(1)
	local isWaitingForPlayers = raidState ~= nil and raidState.phase == "WaitingForPlayers"
	local isExtracting = raidState ~= nil and raidState.phase == "Extracting"
	local isLobbyStashView = isLobbyPlace and snapshot ~= nil and typeof(snapshot.stash) == "table"
	local shouldShowRaidTimer = raidState ~= nil
		and typeof(raidState.raidEndTime) == "number"
		and (raidState.phase == "InRaid" or raidState.phase == "Extracting")
		and not isRaidLoading
	local canShowMobileRaidButtons = isMobile and isRaidPlace
		and not isRaidLoading
		and raidState ~= nil
		and (raidState.phase == "InRaid" or raidState.phase == "Extracting")
	local shouldRenderLoadingOverlay = (isRaidLoading or isWaitingForPlayers or loadingOverlayTransparency < 0.98)
		and not isExtracting
		and not (raidState and raidState.phase == "InRaid" and raidState.playerCanFight == true)
	local isLeavingRaid = raidState ~= nil and raidState.phase == "LeavingRaid"

	local hpText = string.format("HP %d/%d", math.floor(health + 0.5), math.floor(maxHealth + 0.5))

	local ammoText = "AMMO -/-"

	if snapshot then
		local slot = snapshot.equippedSlot
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

	local activeDragItem = if dragState and dragState.sourceKind == "body" and bodyLootSnapshot
		then bodyLootSnapshot.itemsById and bodyLootSnapshot.itemsById[dragState.itemId]
		elseif dragState and snapshot
		then snapshot.itemsById and snapshot.itemsById[dragState.itemId]
		else nil

	local function moveDraggedItemToCell(toContainer: string, toIndex: number?)
		if not dragState then
			return
		end

		if isLobbyStashView then
			if dragState.fromContainer == "stash" then
				if toContainer == "stash" then
					sendLobbyStashActionRequest({
						kind = "MoveWithinStash",
						itemId = dragState.itemId,
						destIndex = toIndex,
					})
				elseif toContainer == "rig" or toContainer == "backpack" then
					sendLobbyStashActionRequest({
						kind = "MoveToInventory",
						itemId = dragState.itemId,
						dest = toContainer,
						destIndex = toIndex,
					})
				end
			elseif toContainer == "stash" then
				sendLobbyStashActionRequest({
					kind = "MoveToStash",
					itemId = dragState.itemId,
					destIndex = toIndex,
				})
			elseif dragState.sourceKind ~= "body" then
				sendLobbyStashActionRequest({
					kind = "MoveWithinInventory",
					itemId = dragState.itemId,
					dest = toContainer,
					destIndex = toIndex,
				})
			end
		elseif dragState.sourceKind == "body" and dragState.bodyId then
			sendBodyLootTransferRequest(dragState.bodyId, dragState.itemId, toContainer, toIndex)
		else
			sendMoveItemRequest(dragState.itemId, dragState.fromContainer, toContainer, toIndex)
		end

		setDragState(nil)
		setHoverState(nil)
	end

	local openContextMenuForItem: (string, string, string, string?) -> () = function() end
	local closeInventoryPanel: () -> () = function() end
	local toggleRaidMenuFromInput: (boolean?) -> () = function() end

	local function activateGridItem(itemId: string, containerName: string)
		if isLobbyStashView and not isMobile then
			local nowSeconds = os.clock()
			local lastClick = lastGridClickRef.current
			local isFastDoubleClick = lastClick.itemId == itemId and (nowSeconds - lastClick.clickedAt) <= 0.28
			lastGridClickRef.current = {
				itemId = itemId,
				clickedAt = nowSeconds,
			}

			if isFastDoubleClick then
				if containerName == "stash" then
					local item = snapshot and snapshot.itemsById and snapshot.itemsById[itemId] or nil
					local destination = "backpack"
					if item and (item.category == "gun" or item.category == "pistol" or item.category == "melee") then
						if item.category == "gun" then
							destination = if snapshot.weaponSlots and snapshot.weaponSlots.PrimaryA == nil then "primaryA" else "primaryB"
						elseif item.category == "pistol" then
							destination = "pistol"
						else
							destination = "melee"
						end
					elseif item and (item.category == "mag" or item.category == "med") then
						destination = "rig"
					end
					sendLobbyStashActionRequest({
						kind = "MoveToInventory",
						itemId = itemId,
						dest = destination,
					})
				elseif containerName == "rig" or containerName == "backpack" then
					sendLobbyStashActionRequest({
						kind = "MoveToStash",
						itemId = itemId,
					})
				end
				setDragState(nil)
				setHoverState(nil)
				setMenuOpen(false)
				return
			end

			setSelectedItemId(itemId)
			setSelectedItemSource({
				sourceKind = "player",
				containerName = containerName,
				bodyId = nil,
			})
			setDragState({
				itemId = itemId,
				fromContainer = containerName,
				sourceKind = "player",
				bodyId = nil,
				startedAt = os.clock(),
			})
			setHoverState({
				toContainer = containerName,
				toIndex = nil,
			})
			return
		end

		if not isMobile then
			setDragState({
				itemId = itemId,
				fromContainer = containerName,
				sourceKind = "player",
				bodyId = nil,
				startedAt = os.clock(),
			})
			setHoverState({
				toContainer = containerName,
				toIndex = nil,
			})
		else
			openContextMenuForItem(itemId, "player", containerName, nil)
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

			if dragState.startedAt and (os.clock() - dragState.startedAt) < 0.08 then
				return
			end

			local activeHover = hoverState
			if activeHover then
				moveDraggedItemToCell(activeHover.toContainer, activeHover.toIndex)
			else
				setDragState(nil)
				setHoverState(nil)
			end
		end)

		return function()
			conn:Disconnect()
		end
	end, { inventoryVisible, dragState, hoverState, isLobbyStashView, isMobile })

	React.useEffect(function()
		if not inventoryVisible then
			setDragState(nil)
			setHoverState(nil)
			setMenuOpen(false)
			setSelectedItemId(nil)
			setSelectedItemSource(nil)
			setMobileInventoryPage(1)
		end
	end, { inventoryVisible })

	React.useEffect(function()
		if dragState then
			setMenuOpen(false)
			setSelectedItemId(nil)
			setSelectedItemSource(nil)
		end
	end, { dragState })

	React.useEffect(function()
		if raidState and raidState.phase == "Extracting" then
			setExtractsVisible(true)
		end
	end, { raidState })

	React.useEffect(function()
		if inventoryVisible or isRaidLoading or isWaitingForPlayers then
			setMobileUtilityOpen(false)
			setEscapeMenuOpen(false)
		end
	end, { inventoryVisible, isRaidLoading, isWaitingForPlayers })

	React.useEffect(function()
		if isLeavingRaid then
			setEscapeMenuOpen(false)
		end
	end, { isLeavingRaid })

	React.useEffect(function()
		if not isRaidPlace then
			return
		end

		if escapeMenuOpen then
			applyRaidMenuInputMode(true)
		elseif not inventoryVisible and not bodyLootSnapshot then
			applyRaidMenuInputMode(false)
		end

		return function()
			if escapeMenuOpen and not inventoryVisible and not bodyLootSnapshot then
				applyRaidMenuInputMode(false)
			end
		end
	end, { escapeMenuOpen, isRaidPlace, inventoryVisible, bodyLootSnapshot })

	React.useEffect(function()
		local conn = UserInputService.InputBegan:Connect(function(input, _processed)
			if UserInputService:GetFocusedTextBox() then
				return
			end

			if input.KeyCode == Enum.KeyCode.O then
				setExtractsVisible(function(previous)
					return not previous
				end)
			end

			if input.KeyCode == Enum.KeyCode.M and isRaidPlace then
				toggleRaidMenuFromInput(inventoryVisible)
			end

			if input.KeyCode == Enum.KeyCode.R and inventoryVisible and selectedItemId and selectedItemSource then
				local selectedContainerName = selectedItemSource.containerName
				local selectedIsWeaponSlot = selectedContainerName == "PrimaryA"
					or selectedContainerName == "PrimaryB"
					or selectedContainerName == "Pistol"
					or selectedContainerName == "Melee"
				if selectedItemSource.sourceKind == "player" and not selectedIsWeaponSlot then
					if isLobbyStashView then
						sendLobbyStashActionRequest({
							kind = "RotateItem",
							itemId = selectedItemId,
						})
					else
						sendItemActionRequest(selectedItemId, "Rotate")
					end
				end
			end
		end)

		return function()
			conn:Disconnect()
		end
	end, { inventoryVisible, selectedItemId, selectedItemSource, isLobbyStashView, isRaidPlace, bodyLootSnapshot, isRaidLoading, isWaitingForPlayers, isLeavingRaid })

	openContextMenuForItem = function(itemId: string, sourceKind: string, containerName: string, bodyId: string?)
		local localX: number
		local localY: number
		if isMobile then
			localX = 24
			localY = 82
		else
			local mousePosition = UserInputService:GetMouseLocation()
			local camera = workspace.CurrentCamera
			local viewportSize = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
			local rootTopLeft = Vector2.new(viewportSize.X * 0.20, viewportSize.Y * 0.075)
			local rootSize = Vector2.new(viewportSize.X * 0.65, viewportSize.Y * 0.85)
			localX = math.clamp(mousePosition.X - rootTopLeft.X + 8, 16, math.max(16, rootSize.X - 166))
			localY = math.clamp(mousePosition.Y - rootTopLeft.Y + 8, 44, math.max(44, rootSize.Y - 176))
		end
		setSelectedItemId(itemId)
		setSelectedItemSource({
			sourceKind = sourceKind,
			containerName = containerName,
			bodyId = bodyId,
		})
		setMenuPosition(UDim2.fromOffset(localX, localY))
		setMenuOpen(true)
		setDragState(nil)
		setHoverState(nil)
	end

	local function closeContextMenu()
		setMenuOpen(false)
		setSelectedItemId(nil)
		setSelectedItemSource(nil)
	end

	closeInventoryPanel = function()
		closeContextMenu()
		setDragState(nil)
		setHoverState(nil)
		setMobileUtilityOpen(false)
		if bodyLootSnapshot then
			sendBodyLootCloseRequest()
			if not (raidState and raidState.phase == "Stash") then
				ClientActionBridge.invoke("close_inventory")
			end
		else
			ClientActionBridge.invoke("close_inventory")
		end
	end

	toggleRaidMenuFromInput = function(forceOpen: boolean?)
		if not isRaidPlace then
			return
		end

		if bodyLootSnapshot then
			sendBodyLootCloseRequest()
			return
		end

		if inventoryVisible then
			closeInventoryPanel()
			if forceOpen == true then
				setEscapeMenuOpen(true)
			end
			return
		end

		if not isRaidLoading and not isWaitingForPlayers and not isLeavingRaid then
			if forceOpen == true then
				setEscapeMenuOpen(true)
			else
				setEscapeMenuOpen(function(previous)
					return not previous
				end)
			end
		end
	end

	local extractCountdownText = ""
	if raidState and raidState.phase == "Extracting" and typeof(raidState.extractEndTime) == "number" then
		local remaining = math.max(0, raidState.extractEndTime - now)
		extractCountdownText = string.format("Extracting in %.1f", remaining)
	end

	local raidTimerText = "Raid --:--"
	local raidTimerRemaining = nil :: number?
	if raidState and typeof(raidState.raidEndTime) == "number" then
		raidTimerRemaining = math.max(0, raidState.raidEndTime - now)
		raidTimerText = "Raid " .. formatClock(raidTimerRemaining)
	end

	local mobileInventoryPages = if isMobile and bodyLootSnapshot
		then {
			{ id = "body", title = "Body Loot" },
		}
		elseif isMobile and isLobbyStashView
		then {
			{ id = "inventory", title = "Inventory" },
			{ id = "stash", title = "Stash" },
		}
		else {
			{ id = "weapons", title = "Weapons" },
			{ id = "rig", title = "Rig" },
			{ id = "backpack", title = "Backpack" },
		}
	if (not isMobile) and bodyLootSnapshot then
		table.insert(mobileInventoryPages, { id = "body", title = "Body" })
	end
	local currentMobilePage = math.clamp(mobileInventoryPage, 1, #mobileInventoryPages)
	local currentMobilePageId = mobileInventoryPages[currentMobilePage].id
	local selectedMenuSnapshot = if selectedItemSource and selectedItemSource.sourceKind == "body" then bodyLootSnapshot else snapshot
	local selectedMenuItem = if selectedMenuSnapshot and selectedItemId then selectedMenuSnapshot.itemsById[selectedItemId] else nil

	local function containerHasSpace(containerData: any, containerName: string, item: any): boolean
		if not containerData or not item then
			return false
		end

		return InventoryGrid.canFitItem(
			containerData.itemIds or {},
			snapshot and snapshot.itemsById or {},
			containerData.capacity or 0,
			containerName,
			item
		)
	end

	local function hasOpenWeaponSlotForItem(item: any): boolean
		if not snapshot or not item then
			return false
		end

		if item.category == "gun" then
			return snapshot.weaponSlots.PrimaryA == nil or snapshot.weaponSlots.PrimaryB == nil
		end
		if item.category == "pistol" then
			return snapshot.weaponSlots.Pistol == nil
		end
		if item.category == "melee" then
			return snapshot.weaponSlots.Melee == nil
		end

		return false
	end

	local function getOpenWeaponSlotDestination(item: any): string?
		if not snapshot or not item then
			return nil
		end

		if item.category == "gun" then
			if snapshot.weaponSlots.PrimaryA == nil then
				return "primaryA"
			end
			if snapshot.weaponSlots.PrimaryB == nil then
				return "primaryB"
			end
		end
		if item.category == "pistol" and snapshot.weaponSlots.Pistol == nil then
			return "pistol"
		end
		if item.category == "melee" and snapshot.weaponSlots.Melee == nil then
			return "melee"
		end

		return nil
	end

	local function isWeaponSlotContainer(containerName: string?): boolean
		return containerName == "PrimaryA" or containerName == "PrimaryB" or containerName == "Pistol" or containerName == "Melee"
	end

	local function itemCanUseAction(item: any, source: SelectedItemSource?): boolean
		if not item or not source then
			return false
		end

		if isLobbyPlace then
			return item.category == "gun" or item.category == "pistol" or item.category == "melee"
		end

		if item.category == "med" then
			return true
		end
		if item.category == "mag" then
			return source.containerName == "rig"
		end
		if item.category == "gun" or item.category == "pistol" or item.category == "melee" then
			return isWeaponSlotContainer(source.containerName)
		end

		return false
	end

	local menuActions = {}
	if selectedItemId and selectedItemSource and selectedMenuItem then
		if isMobile and dragState then
			table.insert(menuActions, {
				label = "Cancel Move",
				run = function()
					setDragState(nil)
					setHoverState(nil)
					closeContextMenu()
				end,
			})
		end

		if isMobile and selectedItemSource.sourceKind == "player" and not isWeaponSlotContainer(selectedItemSource.containerName) then
			table.insert(menuActions, {
				label = "Move",
				run = function()
					setDragState({
						itemId = selectedItemId,
						fromContainer = selectedItemSource.containerName,
						sourceKind = "player",
						bodyId = nil,
						startedAt = os.clock(),
					})
					setHoverState(nil)
					closeContextMenu()
				end,
			})
		end

		if selectedItemSource.sourceKind == "player" and not isWeaponSlotContainer(selectedItemSource.containerName) then
			table.insert(menuActions, {
				label = "Rotate",
				run = function()
					if isLobbyStashView then
						sendLobbyStashActionRequest({
							kind = "RotateItem",
							itemId = selectedItemId,
						})
					else
						sendItemActionRequest(selectedItemId, "Rotate")
					end
					closeContextMenu()
				end,
			})
		end

		if selectedItemSource.sourceKind == "body" and selectedItemSource.bodyId then
			if containerHasSpace(snapshot and snapshot.backpack or nil, "backpack", selectedMenuItem) then
				table.insert(menuActions, {
					label = "Add to Backpack",
					run = function()
						sendBodyLootTransferRequest(selectedItemSource.bodyId :: string, selectedItemId, "backpack", nil)
						closeContextMenu()
					end,
				})
			end

			if (selectedMenuItem.category == "mag" or selectedMenuItem.category == "med") and containerHasSpace(snapshot and snapshot.rig or nil, "rig", selectedMenuItem) then
				table.insert(menuActions, {
					label = "Add to Rig",
					run = function()
						sendBodyLootTransferRequest(selectedItemSource.bodyId :: string, selectedItemId, "rig", nil)
						closeContextMenu()
					end,
				})
			end

			if hasOpenWeaponSlotForItem(selectedMenuItem) then
				table.insert(menuActions, {
					label = "Add to Weapon Slot",
					run = function()
						sendBodyLootTransferRequest(selectedItemSource.bodyId :: string, selectedItemId, "OpenWeaponSlot", nil)
						closeContextMenu()
					end,
				})
			end
		elseif isLobbyStashView then
			if selectedItemSource.containerName == "stash" then
				if containerHasSpace(snapshot and snapshot.backpack or nil, "backpack", selectedMenuItem) then
					table.insert(menuActions, {
						label = "Move to Inventory",
						run = function()
							sendLobbyStashActionRequest({
								kind = "MoveToInventory",
								itemId = selectedItemId,
								dest = "backpack",
							})
							closeContextMenu()
						end,
					})
				end

				if (selectedMenuItem.category == "mag" or selectedMenuItem.category == "med")
					and containerHasSpace(snapshot and snapshot.rig or nil, "rig", selectedMenuItem) then
					table.insert(menuActions, {
						label = "Move to Rig",
						run = function()
							sendLobbyStashActionRequest({
								kind = "MoveToInventory",
								itemId = selectedItemId,
								dest = "rig",
							})
							closeContextMenu()
						end,
					})
				end

				local openWeaponSlotDestination = getOpenWeaponSlotDestination(selectedMenuItem)
				if openWeaponSlotDestination then
					table.insert(menuActions, {
						label = "Move to Weapon Slot",
						run = function()
							sendLobbyStashActionRequest({
								kind = "MoveToInventory",
								itemId = selectedItemId,
								dest = openWeaponSlotDestination,
							})
							closeContextMenu()
						end,
					})
				end
			else
				if selectedItemSource.containerName ~= "backpack" and containerHasSpace(snapshot and snapshot.backpack or nil, "backpack", selectedMenuItem) then
					table.insert(menuActions, {
						label = "Move to Backpack",
						run = function()
							if isLobbyStashView then
								sendLobbyStashActionRequest({
									kind = "MoveWithinInventory",
									itemId = selectedItemId,
									dest = "backpack",
								})
							else
								sendMoveItemRequest(selectedItemId, selectedItemSource.containerName, "backpack", nil)
							end
							closeContextMenu()
						end,
					})
				end

				if (selectedMenuItem.category == "mag" or selectedMenuItem.category == "med")
					and selectedItemSource.containerName ~= "rig"
					and containerHasSpace(snapshot and snapshot.rig or nil, "rig", selectedMenuItem) then
					table.insert(menuActions, {
						label = "Move to Rig",
						run = function()
							if isLobbyStashView then
								sendLobbyStashActionRequest({
									kind = "MoveWithinInventory",
									itemId = selectedItemId,
									dest = "rig",
								})
							else
								sendMoveItemRequest(selectedItemId, selectedItemSource.containerName, "rig", nil)
							end
							closeContextMenu()
						end,
					})
				end

				if not isWeaponSlotContainer(selectedItemSource.containerName) and hasOpenWeaponSlotForItem(selectedMenuItem) then
					table.insert(menuActions, {
						label = "Move to Weapon Slot",
						run = function()
							if isLobbyStashView then
								local destination = getOpenWeaponSlotDestination(selectedMenuItem)
								if destination then
									sendLobbyStashActionRequest({
										kind = "MoveWithinInventory",
										itemId = selectedItemId,
										dest = destination,
									})
								end
							else
								sendMoveItemRequest(selectedItemId, selectedItemSource.containerName, "OpenWeaponSlot", nil)
							end
							closeContextMenu()
						end,
					})
				end

				table.insert(menuActions, {
					label = "Move to Stash",
					run = function()
						sendLobbyStashActionRequest({
							kind = "MoveToStash",
							itemId = selectedItemId,
						})
						closeContextMenu()
					end,
				})
			end
		else
			local actionLabel = getItemActionLabel(selectedMenuSnapshot, selectedItemId)
			if actionLabel and itemCanUseAction(selectedMenuItem, selectedItemSource) then
				table.insert(menuActions, {
					label = actionLabel,
					run = function()
						sendItemActionRequest(selectedItemId, actionLabel)
						closeContextMenu()
					end,
				})
			end

			if selectedItemSource.containerName ~= "backpack" and containerHasSpace(snapshot and snapshot.backpack or nil, "backpack", selectedMenuItem) then
				table.insert(menuActions, {
					label = "Move to Backpack",
					run = function()
						sendMoveItemRequest(selectedItemId, selectedItemSource.containerName, "backpack", nil)
						closeContextMenu()
					end,
				})
			end

			if (selectedMenuItem.category == "mag" or selectedMenuItem.category == "med")
				and selectedItemSource.containerName ~= "rig"
				and containerHasSpace(snapshot and snapshot.rig or nil, "rig", selectedMenuItem) then
				table.insert(menuActions, {
					label = "Move to Rig",
					run = function()
						sendMoveItemRequest(selectedItemId, selectedItemSource.containerName, "rig", nil)
						closeContextMenu()
					end,
				})
			end

			if not isWeaponSlotContainer(selectedItemSource.containerName) and hasOpenWeaponSlotForItem(selectedMenuItem) then
				table.insert(menuActions, {
					label = "Move to Weapon Slot",
					run = function()
						sendMoveItemRequest(selectedItemId, selectedItemSource.containerName, "OpenWeaponSlot", nil)
						closeContextMenu()
					end,
				})
			end

			if isRaidPlace then
				table.insert(menuActions, {
					label = "Drop",
					run = function()
						sendDropItemRequest(selectedItemId)
						closeContextMenu()
					end,
				})
			end
		end

		table.insert(menuActions, {
			label = "Close",
			run = function()
				closeContextMenu()
			end,
		})
	end
	local contextMenuChildren: {[string]: any} = {
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
	}
	for actionIndex, action in ipairs(menuActions) do
		contextMenuChildren["Action" .. actionIndex] = React.createElement("TextButton", {
			LayoutOrder = actionIndex,
			Size = UDim2.new(1, 0, 0, if isMobile then 32 else 26),
			BackgroundColor3 = Color3.fromRGB(42, 42, 42),
			BorderSizePixel = 0,
			Text = action.label,
			Font = Enum.Font.GothamMedium,
			TextSize = if isMobile then 14 else 13,
			TextColor3 = Color3.new(1, 1, 1),
			ZIndex = 5,
			[React.Event.Activated] = action.run,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
		})
	end
	local contextMenuHeight = 16 + (#menuActions * (if isMobile then 38 else 32))

	if not inventoryVisible and isRaidPlace then
		rootChildren.Health = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 16, 1, if isMobile then -12 else -16),
			Size = UDim2.fromOffset(if isMobile then 142 else 240, if isMobile then 32 else 36),
			BackgroundTransparency = 0.45,
			BackgroundColor3 = Color3.fromRGB(18, 18, 18),
			BorderSizePixel = 0,
			Text = hpText,
			Font = Enum.Font.GothamBold,
			TextSize = if isMobile then 12 else 14,
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
			Position = UDim2.new(0, 16, 1, if isMobile then -40 else -56),
			Size = UDim2.fromOffset(if isMobile then 160 else 240, 32),
			BackgroundTransparency = 1,
			Text = ammoText,
			Font = Enum.Font.Gotham,
			TextSize = if isMobile then 11 else 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(220, 220, 220),
		})

		rootChildren.ReloadStatus = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 16, 1, if isMobile then -60 else -80),
			Size = UDim2.fromOffset(if isMobile then 200 else 260, 22),
			BackgroundTransparency = 1,
			Text = if snapshot and snapshot.isReloading
				then "Reloading..."
				elseif timedCheckMagText ~= ""
				then timedCheckMagText
				else "",
			Font = Enum.Font.GothamBold,
			TextSize = if isMobile then 11 else 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(255, 210, 120),
		})

		if shouldShowRaidTimer then
			local timerUrgent = raidTimerRemaining ~= nil and raidTimerRemaining <= 180
			rootChildren.RaidTimerButton = React.createElement("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -16, 0, 16),
				Size = UDim2.fromOffset(180, 38),
				BackgroundTransparency = 0.2,
				BackgroundColor3 = if timerUrgent then Color3.fromRGB(48, 16, 16) else Color3.fromRGB(18, 18, 18),
				BorderSizePixel = 0,
				Text = raidTimerText,
				Font = Enum.Font.GothamBold,
				TextSize = 16,
				TextColor3 = if timerUrgent then Color3.fromRGB(255, 140, 140) else Color3.new(1, 1, 1),
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
					Color = if timerUrgent then Color3.fromRGB(255, 110, 110) else Color3.fromRGB(255, 225, 130),
				}),
			})

			if extractsVisible then
				local extractChildren: {[string]: any} = {
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, if isMobile then 3 else 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				}

				local availableExtracts = if raidState.availableExtracts then raidState.availableExtracts else {}
				for index, extractName in ipairs(availableExtracts) do
					local isCurrentExtract = raidState.currentExtractId == extractName
					extractChildren["Extract" .. index] = React.createElement("TextLabel", {
						LayoutOrder = index,
						Size = UDim2.new(1, 0, 0, if isMobile then 17 else 20),
						BackgroundTransparency = 1,
						Text = extractName,
						Font = Enum.Font.GothamMedium,
						TextSize = if isMobile then 11 else 13,
						TextColor3 = if isCurrentExtract then Color3.fromRGB(105, 255, 125) else Color3.new(1, 1, 1),
						TextXAlignment = Enum.TextXAlignment.Left,
					})
				end

				rootChildren.ExtractList = React.createElement("Frame", {
					AnchorPoint = if isMobile then Vector2.new(0.5, 0) else Vector2.new(1, 0),
					Position = if isMobile then UDim2.new(0.5, 0, 0, 50) else UDim2.new(1, -16, 0, 60),
					Size = UDim2.fromOffset(if isMobile then 136 else 220, if isMobile then 82 else math.max(80, 22 + #availableExtracts * 26)),
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
						TextSize = if isMobile then 11 else 14,
						TextColor3 = Color3.fromRGB(255, 225, 130),
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					List = React.createElement("ScrollingFrame", {
						Position = UDim2.fromOffset(10, 30),
						Size = UDim2.new(1, -20, 1, -38),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						CanvasSize = UDim2.fromOffset(0, 0),
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						ScrollBarThickness = if isMobile then 3 else 5,
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
			local promptIsPickup = isMobile and lootPrompt.kind ~= nil
			local promptProps = {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, if isMobile then 0.52 else 0.56),
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundTransparency = 0.2,
				BackgroundColor3 = Color3.fromRGB(18, 18, 18),
				BorderSizePixel = 0,
				Text = lootPrompt.text,
				Font = Enum.Font.GothamBold,
				TextSize = if isMobile then 17 else 20,
				TextColor3 = Color3.new(1, 1, 1),
			}
			if promptIsPickup then
				(promptProps :: any).AutoButtonColor = true
				(promptProps :: any)[React.Event.Activated] = function()
					ClientActionBridge.invoke("interact")
				end
			end

			rootChildren.LootPrompt = React.createElement(if promptIsPickup then "TextButton" else "TextLabel", promptProps, {
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

	elseif inventoryVisible then
		local inventoryTitleText = "Inventory"
		if isLobbyStashView then
			inventoryTitleText = if isMobile then "Stash" else "Stash Management"
		elseif raidState and raidState.phase == "Stash" then
			inventoryTitleText = if isMobile then "Stash" else "Stash Mode"
		elseif bodyLootSnapshot then
			inventoryTitleText = if isMobile then "Body Loot" else "Inventory (Body Loot Open)"
		elseif not isMobile then
			inventoryTitleText = "Inventory (Tab to Close, drag between Rig and Backpack)"
		end

		local inventoryHintText = ""
		if dragState then
			inventoryHintText = "Dragging: " .. itemLabel(
				if dragState.sourceKind == "body" then bodyLootSnapshot else snapshot,
				dragState.itemId
			)
		elseif isLobbyStashView then
			inventoryHintText = if isMobile
				then "Tap an item to move it between your inventory and stash."
				else "Drag items between your inventory and stash, or click for move options."
		elseif isMobile then
			inventoryHintText = if bodyLootSnapshot
				then "Tap an item to choose where it goes."
				else "Tap an item to manage it. Use the arrows to switch pages."
		else
			inventoryHintText = "Drag an item to a slot in Rig or Backpack."
		end

		local inventoryPanel = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = if isMobile then UDim2.fromScale(0.56, 0.5) else UDim2.fromScale(0.54, 0.5),
			Size = if isMobile then UDim2.fromScale(0.65, 0.85) else UDim2.fromScale(0.78, 0.90),
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
				Size = UDim2.new(1, if isRaidPlace and not bodyLootSnapshot then -168 else if isMobile then -88 else -56, 0, 24),
				BackgroundTransparency = 1,
				Text = inventoryTitleText,
				Font = Enum.Font.GothamBold,
				TextSize = if isMobile then 14 else 16,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromRGB(255, 225, 130),
			}),
			RaidMenuButton = if isRaidPlace and not bodyLootSnapshot and not isRaidLoading and not isWaitingForPlayers and not isLeavingRaid then React.createElement("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -52, 0, 10),
				Size = UDim2.fromOffset(if isMobile then 66 else 74, 30),
				BackgroundColor3 = Color3.fromRGB(28, 28, 28),
				BackgroundTransparency = 0.08,
				BorderSizePixel = 0,
				Text = if isMobile then "Menu" else "Menu M",
				Font = Enum.Font.GothamBold,
				TextSize = if isMobile then 13 else 12,
				TextColor3 = Color3.fromRGB(255, 225, 130),
				[React.Event.Activated] = function()
					closeInventoryPanel()
					setEscapeMenuOpen(true)
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.12,
					Color = Color3.fromRGB(255, 225, 130),
				}),
			}) else nil,
			CloseButton = React.createElement("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -14, 0, 10),
				Size = UDim2.fromOffset(30, 30),
				BackgroundColor3 = Color3.fromRGB(28, 28, 28),
				BackgroundTransparency = 0.08,
				BorderSizePixel = 0,
				Text = "X",
				Font = Enum.Font.GothamBold,
				TextSize = 15,
				TextColor3 = Color3.fromRGB(255, 225, 130),
				[React.Event.Activated] = function()
					closeInventoryPanel()
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.12,
					Color = Color3.fromRGB(255, 225, 130),
				}),
			}),
			DragHint = React.createElement("TextLabel", {
				Position = UDim2.new(0, 16, 1, if isMobile then -26 else -28),
				Size = UDim2.new(1, -32, 0, 18),
				BackgroundTransparency = 1,
				Text = inventoryHintText,
				Font = Enum.Font.Gotham,
				TextSize = if isMobile then 11 else 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = if dragState then Color3.fromRGB(255, 225, 130) else Color3.fromRGB(180, 180, 180),
			}),
			ContextDismiss = if menuOpen and not isMobile then React.createElement("TextButton", {
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
				Size = UDim2.fromOffset(if isMobile then 220 else 170, math.max(if isMobile then 88 else 70, contextMenuHeight)),
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
			}, contextMenuChildren) else nil,
			PageLeft = if isMobile and #mobileInventoryPages > 1 then React.createElement("TextButton", {
				Position = UDim2.fromOffset(16, 44),
				Size = UDim2.fromOffset(38, 30),
				BackgroundColor3 = Color3.fromRGB(28, 28, 28),
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				Text = "<",
				Font = Enum.Font.GothamBold,
				TextSize = 18,
				TextColor3 = Color3.fromRGB(255, 225, 130),
				[React.Event.Activated] = function()
					setMobileInventoryPage(math.max(1, currentMobilePage - 1))
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
			}) else nil,
			PageRight = if isMobile and #mobileInventoryPages > 1 then React.createElement("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -16, 0, 44),
				Size = UDim2.fromOffset(38, 30),
				BackgroundColor3 = Color3.fromRGB(28, 28, 28),
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				Text = ">",
				Font = Enum.Font.GothamBold,
				TextSize = 18,
				TextColor3 = Color3.fromRGB(255, 225, 130),
				[React.Event.Activated] = function()
					setMobileInventoryPage(math.min(#mobileInventoryPages, currentMobilePage + 1))
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
			}) else nil,
			PageLabel = if isMobile and #mobileInventoryPages > 1 then React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 48),
				Size = UDim2.new(1, -120, 0, 18),
				BackgroundTransparency = 1,
				Text = string.format("%s (%d/%d)", mobileInventoryPages[currentMobilePage].title, currentMobilePage, #mobileInventoryPages),
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextColor3 = Color3.fromRGB(220, 220, 220),
				TextXAlignment = Enum.TextXAlignment.Center,
			}) else nil,
			InventorySummary = if isMobile and isLobbyStashView and currentMobilePageId == "inventory" then mobileLobbyInventorySummaryCard(
				snapshot,
				UDim2.new(0, 16, 0, 84),
				UDim2.new(1, -32, 1, -128),
				selectedItemId,
				openContextMenuForItem
			) else nil,
			Weapons = if (not isMobile) or (isMobile and not isLobbyStashView and currentMobilePageId == "weapons") then weaponSlotCard(
				snapshot,
				if isMobile
					then UDim2.new(0, 16, 0, 84)
					else UDim2.new(0, 16, 0, 44),
				if isMobile
					then UDim2.new(1, -32, 1, -128)
					else (if isLobbyStashView
						then UDim2.new(0.58, -24, 0, 194)
						elseif bodyLootSnapshot
						then UDim2.new(0.58, -24, 0, 194)
						else UDim2.new(1, -32, 0, 194)),
				selectedItemId,
				openContextMenuForItem,
				isMobile
			) else nil,
			Rig = if not isMobile or (not isLobbyStashView and currentMobilePageId == "rig") then containerCard(
				"Rig",
				"rig",
				snapshot,
				if isMobile
					then UDim2.new(0, 16, 0, 84)
					else (if isLobbyStashView
						then UDim2.new(0, 16, 0, 252)
						elseif bodyLootSnapshot
						then UDim2.new(0, 16, 0, 252)
						else UDim2.new(0, 16, 0, 252)),
				if isMobile
					then UDim2.new(1, -32, 1, -128)
					else (if isLobbyStashView
						then UDim2.new(0.58, -24, 0, 210)
						elseif bodyLootSnapshot
						then UDim2.new(0.58, -24, 0.30, -12)
						else UDim2.new(0.48, -24, 1, -312)),
				dragState,
				hoverState,
				selectedItemId,
				setHoverState,
				setDragState,
				openContextMenuForItem,
				moveDraggedItemToCell,
				activateGridItem,
				activeDragItem,
				isMobile,
				(not isMobile) or dragState ~= nil,
				"grid"
			) else nil,
			Backpack = if not isMobile or (not isLobbyStashView and currentMobilePageId == "backpack") then containerCard(
				"Backpack",
				"backpack",
				snapshot,
				if isMobile
					then UDim2.new(0, 16, 0, 84)
					else (if isLobbyStashView
						then UDim2.new(0, 16, 0, 478)
						elseif bodyLootSnapshot
						then UDim2.new(0, 16, 0.58, 44)
						else UDim2.new(0.52, 8, 0, 252)),
				if isMobile
					then UDim2.new(1, -32, 1, -128)
					else (if isLobbyStashView
						then UDim2.new(0.58, -24, 1, -532)
						elseif bodyLootSnapshot
						then UDim2.new(0.58, -24, 0.36, -80)
						else UDim2.new(0.48, -24, 1, -312)),
				dragState,
				hoverState,
				selectedItemId,
				setHoverState,
				setDragState,
				openContextMenuForItem,
				moveDraggedItemToCell,
				activateGridItem,
				activeDragItem,
				isMobile,
				(not isMobile) or dragState ~= nil,
				"grid"
			) else nil,
			Stash = if isLobbyStashView and (not isMobile or currentMobilePageId == "stash") then containerCard(
				"Stash",
				"stash",
				snapshot,
				if isMobile then UDim2.new(0, 16, 0, 84) else UDim2.new(0.62, 8, 0, 44),
				if isMobile then UDim2.new(1, -32, 1, -128) else UDim2.new(0.38, -24, 1, -92),
				dragState,
				hoverState,
				selectedItemId,
				setHoverState,
				setDragState,
				openContextMenuForItem,
				moveDraggedItemToCell,
				activateGridItem,
				activeDragItem,
				isMobile,
				(not isMobile) or dragState ~= nil,
				"grid"
			) else nil,
			BodyLoot = if bodyLootSnapshot and (not isMobile or currentMobilePageId == "body") then bodyContainerCard(
				bodyLootSnapshot,
				if isMobile then UDim2.new(0, 16, 0, 84) else UDim2.new(0.44, 8, 0, 44),
				if isMobile then UDim2.new(1, -32, 1, -128) else UDim2.new(0.56, -24, 0.88, -72),
				dragState,
				hoverState,
				setHoverState,
				setDragState,
				openContextMenuForItem,
				isMobile
			) else nil,
		})

		rootChildren.InventoryShell = React.createElement("Frame", {
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, {
			OutsideTop = if bodyLootSnapshot and not isMobile then React.createElement("TextButton", {
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.new(1, 0, 0.075, 0),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				[React.Event.Activated] = function()
					sendBodyLootCloseRequest()
				end,
			}) else nil,
			OutsideBottom = if bodyLootSnapshot and not isMobile then React.createElement("TextButton", {
				Position = UDim2.new(0, 0, 0.925, 0),
				Size = UDim2.new(1, 0, 0.075, 0),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				[React.Event.Activated] = function()
					sendBodyLootCloseRequest()
				end,
			}) else nil,
			OutsideLeft = if bodyLootSnapshot and not isMobile then React.createElement("TextButton", {
				Position = UDim2.new(0, 0, 0.075, 0),
				Size = UDim2.new(0.175, 0, 0.85, 0),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				[React.Event.Activated] = function()
					sendBodyLootCloseRequest()
				end,
			}) else nil,
			OutsideRight = if bodyLootSnapshot and not isMobile then React.createElement("TextButton", {
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

	if isMobile and isRaidPlace and not inventoryVisible and not isRaidLoading and not isWaitingForPlayers and bodyLootSnapshot == nil and (raidState == nil or raidState.phase ~= "Stash") then
		rootChildren.MobileUtilityToggle = mobileActionButton(
			if mobileUtilityOpen then "Close" else "Menu",
			UDim2.new(0, 16, 1, -88),
			UDim2.fromOffset(68, 36),
			function()
				setMobileUtilityOpen(function(previous)
					return not previous
				end)
			end,
			Vector2.new(0, 1)
		)

		if mobileUtilityOpen then
			rootChildren.MobileInventoryButton = mobileActionButton(
				"Inventory",
				UDim2.new(0, 16, 1, -132),
				UDim2.fromOffset(96, 36),
				function()
					ClientActionBridge.invoke("toggle_inventory")
				end,
				Vector2.new(0, 1)
			)

			rootChildren.MobileExtractsButton = mobileActionButton(
				"Extracts",
				UDim2.new(0, 16, 1, -176),
				UDim2.fromOffset(96, 36),
				function()
					setExtractsVisible(function(previous)
						return not previous
					end)
				end,
				Vector2.new(0, 1)
			)

			rootChildren.MobileRaidMenuButton = mobileActionButton(
				"Raid Menu",
				UDim2.new(0, 16, 1, -220),
				UDim2.fromOffset(104, 36),
				function()
					setMobileUtilityOpen(false)
					toggleRaidMenuFromInput()
				end,
				Vector2.new(0, 1)
			)
		end
	end

	if canShowMobileRaidButtons and not inventoryVisible then
		rootChildren.MobileFireButton = mobileRoundButton(
			"FIRE",
			UDim2.new(1, -24, 1, -178),
			72,
			function()
				ClientActionBridge.invoke("fire")
			end
		)

		rootChildren.MobileAimButton = mobileRoundButton(
			"AIM",
			UDim2.new(1, -102, 1, -236),
			56,
			function()
				ClientActionBridge.invoke("aim")
			end
		)

		rootChildren.MobileReloadButton = mobileRoundButton(
			"R",
			UDim2.new(1, -26, 1, -112),
			48,
			function()
				ClientActionBridge.invoke("reload")
			end
		)

		rootChildren.MobileCheckMagButton = mobileRoundButton(
			"CHK",
			UDim2.new(1, -84, 1, -118),
			54,
			function()
				ClientActionBridge.invoke("check_mag")
			end
		)

	end

	if escapeMenuOpen and isRaidPlace and not inventoryVisible and not isRaidLoading and not isWaitingForPlayers and not isLeavingRaid then
		rootChildren.RaidMenuModalCapture = React.createElement("TextButton", {
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Modal = true,
			Selectable = false,
			ZIndex = 49,
		})

		rootChildren.EscapeMenu = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(if isMobile then math.min(300, viewportSize.X - 32) else 360, if isMobile then 246 else 260),
			BackgroundColor3 = Color3.fromRGB(12, 12, 12),
			BackgroundTransparency = 0.04,
			BorderSizePixel = 0,
			ZIndex = 50,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
			Stroke = React.createElement("UIStroke", {
				Thickness = 1,
				Transparency = 0.1,
				Color = Color3.fromRGB(255, 225, 130),
			}),
			Title = React.createElement("TextLabel", {
				Position = UDim2.fromOffset(18, 16),
				Size = UDim2.new(1, -36, 0, 24),
				BackgroundTransparency = 1,
				Text = "RAID MENU",
				Font = Enum.Font.GothamBold,
				TextSize = 18,
				TextColor3 = Color3.fromRGB(255, 225, 130),
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 51,
			}),
			Warning = React.createElement("TextLabel", {
				Position = UDim2.fromOffset(18, 46),
				Size = UDim2.new(1, -36, 0, 42),
				BackgroundTransparency = 1,
				Text = "Leaving the raid counts as KIA. Your carried gear will be lost.",
				Font = Enum.Font.Gotham,
				TextSize = if isMobile then 12 else 13,
				TextWrapped = true,
				TextColor3 = Color3.fromRGB(205, 205, 205),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 51,
			}),
			Resume = React.createElement("TextButton", {
				Position = UDim2.fromOffset(18, 102),
				Size = UDim2.new(1, -36, 0, 38),
				BackgroundColor3 = Color3.fromRGB(34, 34, 34),
				BorderSizePixel = 0,
				Text = "Resume",
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Color3.new(1, 1, 1),
				ZIndex = 51,
				[React.Event.Activated] = function()
					setEscapeMenuOpen(false)
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
			}),
			Settings = React.createElement("TextButton", {
				Position = UDim2.fromOffset(18, 148),
				Size = UDim2.new(1, -36, 0, 38),
				BackgroundColor3 = Color3.fromRGB(28, 28, 28),
				BorderSizePixel = 0,
				Text = "Settings (soon)",
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(180, 180, 180),
				ZIndex = 51,
				AutoButtonColor = false,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
			}),
			LeaveRaid = React.createElement("TextButton", {
				Position = UDim2.fromOffset(18, 194),
				Size = UDim2.new(1, -36, 0, 42),
				BackgroundColor3 = Color3.fromRGB(74, 28, 24),
				BorderSizePixel = 0,
				Text = "Leave Raid - Lose Gear",
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Color3.fromRGB(255, 235, 220),
				ZIndex = 51,
				[React.Event.Activated] = function()
					setEscapeMenuOpen(false)
					raidLeaveRequestEvent:FireServer()
				end,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Stroke = React.createElement("UIStroke", {
					Thickness = 1,
					Transparency = 0.25,
					Color = Color3.fromRGB(255, 110, 90),
				}),
			}),
		})
	end

	if isWaitingForPlayers then
		local partyMembers = if raidState and raidState.partyMembers then raidState.partyMembers else {}
		local readyDeadlineText = "Waiting for other players..."
		if raidState and typeof(raidState.readyDeadline) == "number" then
			local secondsRemaining = math.max(0, math.ceil(raidState.readyDeadline - now))
			readyDeadlineText = string.format("Waiting for other players... Fallback start in %ds", secondsRemaining)
		end

		local readyListChildren: {[string]: any} = {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 6),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}

		for index, member in ipairs(partyMembers) do
			local isMemberReady = member.ready == true
			local isPresent = member.present == true
			local statusText = if isMemberReady then "[READY]" elseif isPresent then "[LOADING]" else "[JOINING]"
			readyListChildren["Member" .. index] = React.createElement("TextLabel", {
				LayoutOrder = index,
				Size = UDim2.new(1, 0, 0, 24),
				BackgroundTransparency = 1,
				Text = string.format("%s %s", statusText, tostring(member.name)),
				Font = Enum.Font.Code,
				TextSize = 15,
				TextColor3 = if isMemberReady
					then Color3.fromRGB(105, 255, 125)
					elseif isPresent
					then Color3.fromRGB(255, 225, 130)
					else Color3.fromRGB(170, 170, 170),
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 61,
			})
		end

		rootChildren.WaitingOverlay = React.createElement("Frame", {
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = if isMobile then 0 else 0.08,
			BorderSizePixel = 0,
			ZIndex = 60,
		}, {
			Title = React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, if isMobile then 0.38 else 0.42),
				Size = UDim2.fromOffset(if isMobile then math.min(320, viewportSize.X - 32) else 520, 40),
				BackgroundTransparency = 1,
				Text = "PLAYER READY",
				Font = Enum.Font.GothamBold,
				TextSize = if isMobile then 22 else 28,
				TextColor3 = Color3.fromRGB(255, 225, 130),
				ZIndex = 61,
			}),
			Detail = React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, if isMobile then 0.44 else 0.47),
				Size = UDim2.fromOffset(if isMobile then math.min(340, viewportSize.X - 24) else 760, if isMobile then 42 else 30),
				BackgroundTransparency = 1,
				Text = readyDeadlineText,
				Font = Enum.Font.Gotham,
				TextSize = if isMobile then 14 else 16,
				TextWrapped = isMobile,
				TextColor3 = Color3.fromRGB(200, 200, 200),
				ZIndex = 61,
			}),
			ReadyList = React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, if isMobile then 0.52 else 0.54),
				Size = UDim2.fromOffset(if isMobile then math.min(320, viewportSize.X - 28) else 520, math.max(if isMobile then 112 else 120, #partyMembers * (if isMobile then 26 else 30))),
				BackgroundTransparency = 1,
				ZIndex = 61,
			}, readyListChildren),
		})
	end

	if shouldRenderLoadingOverlay or isLeavingRaid then
		local overlayTitle = loadingOverlayText
		local overlayDetail = loadingOverlayDetailText
		rootChildren.LoadingOverlay = React.createElement("Frame", {
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = if isLeavingRaid then 0 else loadingOverlayTransparency,
			BorderSizePixel = 0,
			ZIndex = 50,
		}, {
			Label = if not isLeavingRaid then React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, if isMobile then 0.24 else 0.52),
				Size = UDim2.fromOffset(if isMobile then math.min(320, viewportSize.X - 36) else 560, if isMobile then 26 else 34),
				BackgroundTransparency = 1,
				Text = overlayTitle,
				Font = Enum.Font.GothamBold,
				TextSize = if isMobile then 17 else 22,
				TextColor3 = Color3.fromRGB(235, 235, 235),
				ZIndex = 51,
			}) else nil,
			Detail = if not isLeavingRaid then React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, if isMobile then 0.31 else 0.56),
				Size = UDim2.fromOffset(if isMobile then math.min(340, viewportSize.X - 30) else 700, if isMobile then 42 else 28),
				BackgroundTransparency = 1,
				Text = overlayDetail,
				Font = Enum.Font.Gotham,
				TextSize = if isMobile then 13 else 15,
				TextWrapped = isMobile,
				TextColor3 = Color3.fromRGB(180, 180, 180),
				ZIndex = 51,
			}) else nil,
			Spinner = if not isLeavingRaid then React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, if isMobile then 0.40 else 0.62),
				Size = UDim2.fromOffset(80, 40),
				BackgroundTransparency = 1,
				Text = loadingSpinnerFrame,
				Font = Enum.Font.Code,
				TextSize = if isMobile then 30 else 34,
				TextColor3 = Color3.fromRGB(255, 225, 130),
				ZIndex = 51,
			}) else nil,
			StepList = if not isLeavingRaid then React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, if isMobile then 0.46 else 0.68),
				Size = UDim2.fromOffset(if isMobile then math.min(300, viewportSize.X - 42) else 520, if isMobile then math.min(128, math.max(106, viewportSize.Y * 0.18)) else 170),
				BackgroundTransparency = 1,
				ZIndex = 51,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, if isMobile then 2 else 4),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Step1 = loadingStepLabel(loadingChecklist[1], 1, loadingActiveMarkerVisible, isMobile),
				Step2 = loadingStepLabel(loadingChecklist[2], 2, loadingActiveMarkerVisible, isMobile),
				Step3 = loadingStepLabel(loadingChecklist[3], 3, loadingActiveMarkerVisible, isMobile),
				Step4 = loadingStepLabel(loadingChecklist[4], 4, loadingActiveMarkerVisible, isMobile),
				Step5 = loadingStepLabel(loadingChecklist[5], 5, loadingActiveMarkerVisible, isMobile),
				Step6 = loadingStepLabel(loadingChecklist[6], 6, loadingActiveMarkerVisible, isMobile),
				Step7 = loadingStepLabel(loadingChecklist[7], 7, loadingActiveMarkerVisible, isMobile),
				Step8 = loadingStepLabel(loadingChecklist[8], 8, loadingActiveMarkerVisible, isMobile),
			}) else nil,
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
