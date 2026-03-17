--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local LootDefinitions = require(ReplicatedStorage.Shared.LootDefinitions)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local ClientActionBridge = require(script.Parent.state.ClientActionBridge)
local LootPromptStore = require(script.Parent.state.LootPromptStore)
local RaidStore = require(script.Parent.state.RaidStore)

if not PlaceConfig.isRaidPlace() then
	return
end

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local pickupEvent = remotes:WaitForChild(Net.LootPickupRequestEventName) :: RemoteEvent
local extractRequestEvent = remotes:WaitForChild(Net.ExtractRequestStartEventName) :: RemoteEvent
local bodyLootOpenEvent = remotes:WaitForChild(Net.BodyLootOpenRequestEventName) :: RemoteEvent

local MAX_DISTANCE = 15
local DETECTION_INTERVAL = 0.08

local elapsed = 0
local activeExtractTarget: Model? = nil
local doorInteractBusy = false

local function getExtractsFolder(): Folder?
	local maps = workspace:FindFirstChild("Maps")
	local level0 = maps and maps:FindFirstChild("Level0")
	local gameplay = level0 and level0:FindFirstChild("Gameplay")
	local extracts = gameplay and gameplay:FindFirstChild("Extracts")
	if extracts and extracts:IsA("Folder") then
		return extracts
	end

	return nil
end

local function isInsideZone(handle: BasePart, worldPosition: Vector3): boolean
	local localPosition = handle.CFrame:PointToObjectSpace(worldPosition)
	local halfSize = handle.Size * 0.5
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end

local function getModelWithAttribute(instance: Instance?, attributeName: string): Model?
	local current = instance
	while current do
		if current:IsA("Model") and current:GetAttribute(attributeName) ~= nil then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function getDoorModel(instance: Instance?): Model?
	local current = instance
	while current do
		if current:IsA("Model") and current:FindFirstChild("Door1") and current:FindFirstChild("Door2") then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function getDoorInteractPrompt(doorModel: Model): ProximityPrompt?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local rootPosition = if root and root:IsA("BasePart") then root.Position else nil
	local bestPrompt: ProximityPrompt? = nil
	local bestDistance = math.huge

	for _, buttonName in ipairs({ "Button1", "Button2" }) do
		local button = doorModel:FindFirstChild(buttonName)
		if button then
			local prompt = button:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				if rootPosition and button:IsA("BasePart") then
					local distance = (button.Position - rootPosition).Magnitude
					if distance < bestDistance then
						bestDistance = distance
						bestPrompt = prompt
					end
				else
					return prompt
				end
			end
		end
	end

	return bestPrompt
end

local function getCrosshairPromptTarget()
	local character = player.Character
	if not character or not camera then
		return nil
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local result = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * MAX_DISTANCE, params)
	if not result then
		return nil
	end

	local bodyModel = getModelWithAttribute(result.Instance, "BodyLootId")
	if bodyModel then
		return {
			kind = "body",
			target = bodyModel,
			text = if isMobile then "LOOT BODY" else "LOOT BODY - Press E",
			actionText = "Interact",
		}
	end

	local lootModel = getModelWithAttribute(result.Instance, "TemplateId")
	if lootModel then
		local templateId = lootModel:GetAttribute("TemplateId")
		if typeof(templateId) == "string" then
			local displayName = LootDefinitions.getDisplayName(templateId)
			return {
				kind = "loot",
				target = lootModel,
				templateId = templateId,
				displayName = displayName,
				text = if isMobile
					then string.format("Pick up %s", displayName)
					else string.format("%s  Press E", displayName),
				actionText = if isMobile then nil else "Pick Up",
			}
		end
	end

	local doorModel = getDoorModel(result.Instance)
	if doorModel then
		local interactPrompt = getDoorInteractPrompt(doorModel)
		if interactPrompt then
			local requiredLevel = doorModel:GetAttribute("RequiredKeyLevel")
			local unlockedThisRaid = doorModel:GetAttribute("UnlockedThisRaid") == true
			local lockedAttr = doorModel:GetAttribute("Locked")
			local isLocked = if typeof(lockedAttr) == "boolean" then lockedAttr else (typeof(requiredLevel) == "number" and requiredLevel > 0)
			local level = if typeof(requiredLevel) == "number" then math.max(0, math.floor(requiredLevel)) else 0

			local text: string
			if level > 0 then
				if isLocked and not unlockedThisRaid then
					text = if isMobile
						then string.format("Level %d Locked", level)
						else string.format("[E] Level %d Locked", level)
				else
					text = if isMobile
						then string.format("Level %d Unlocked", level)
						else string.format("[E] Level %d Unlocked", level)
				end
			else
				text = if isMobile then "Interact" else "[E] Interact"
			end

			return {
				kind = "door",
				target = doorModel,
				text = text,
				actionText = "Interact",
				promptInstance = interactPrompt,
			}
		end
	end

	return nil
end

local function getActiveExtractZone(): Model?
	local raidState = RaidStore.getState()
	if not raidState or raidState.phase ~= "InRaid" then
		return nil
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end

	local extractsFolder = getExtractsFolder()
	if not extractsFolder then
		return nil
	end

	for _, child in ipairs(extractsFolder:GetChildren()) do
		if child:IsA("Model") then
			local handle = child:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") and isInsideZone(handle, root.Position) then
				return child
			end
		end
	end

	return nil
end

local function updatePrompt()
	if player:GetAttribute("InventoryVisible") == true then
		LootPromptStore.clear()
		return
	end

	local raidState = RaidStore.getState()
	if raidState and raidState.phase ~= "InRaid" then
		LootPromptStore.clear()
		activeExtractTarget = nil
		return
	end

	local extractZone = getActiveExtractZone()
	if extractZone then
		if activeExtractTarget ~= extractZone then
			activeExtractTarget = extractZone
			extractRequestEvent:FireServer(extractZone)
		end
	else
		activeExtractTarget = nil
	end

	local crosshairPrompt = getCrosshairPromptTarget()
	if crosshairPrompt then
		LootPromptStore.setPrompt(crosshairPrompt)
		return
	end

	LootPromptStore.clear()
end

local function interactWithCurrentPrompt()
	if player:GetAttribute("InventoryVisible") == true then
		return
	end

	local prompt = LootPromptStore.getPrompt()
	if not prompt.target or not prompt.kind then
		return
	end

	if prompt.kind == "loot" then
		pickupEvent:FireServer(prompt.target)
	elseif prompt.kind == "body" then
		bodyLootOpenEvent:FireServer(prompt.target)
	elseif prompt.kind == "door" and prompt.promptInstance then
		if doorInteractBusy then
			return
		end
		doorInteractBusy = true
		prompt.promptInstance:InputHoldBegin()
		task.delay(math.max(0.15, prompt.promptInstance.HoldDuration + 0.1), function()
			if prompt.promptInstance then
				prompt.promptInstance:InputHoldEnd()
			end
			doorInteractBusy = false
		end)
	end
end

ClientActionBridge.register("interact", interactWithCurrentPrompt)

RunService.RenderStepped:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < DETECTION_INTERVAL then
		return
	end

	elapsed = 0
	updatePrompt()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.E then
		return
	end

	if player:GetAttribute("InventoryVisible") == true then
		return
	end

	interactWithCurrentPrompt()
end)
