--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local ProfileService = require(script.Parent.ProfileService)

if not PlaceConfig.isLobbyPlace() then
	return
end

local KIOSK_TERMINAL_NAME = "QuartermasterKiosk"
local OPEN_DISTANCE = 10

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local terminalOpenEvent = remotes:WaitForChild(Net.TerminalOpenEventName) :: RemoteEvent
local terminalInteractRequestEvent = remotes:WaitForChild(Net.TerminalInteractRequestEventName) :: RemoteEvent
local terminalCloseEvent = remotes:WaitForChild(Net.TerminalCloseEventName) :: RemoteEvent
local quartermasterSellRequestEvent = remotes:WaitForChild(Net.QuartermasterSellRequestEventName) :: RemoteEvent
local quartermasterStateEvent = remotes:WaitForChild(Net.QuartermasterStateEventName) :: RemoteEvent
local snapshotEvent = remotes:WaitForChild(Net.InventorySnapshotEventName) :: RemoteEvent

local openKioskByUserId: {[number]: boolean} = {}

local function isKioskModel(instance: Instance): boolean
	return instance:IsA("Model")
		and (
			instance:GetAttribute("TerminalType") == "kiosk"
			or instance.Name == KIOSK_TERMINAL_NAME
		)
end

local function findKioskModels(): {Model}
	local models = {}
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if isKioskModel(descendant) then
			table.insert(models, descendant)
		end
	end
	return models
end

local function getKioskPrompt(model: Model): ProximityPrompt?
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			return descendant
		end
	end
	return nil
end

local function getKioskPromptPart(model: Model): BasePart?
	local promptPart = model:FindFirstChild("PromptPart")
	if promptPart and promptPart:IsA("BasePart") then
		return promptPart
	end

	local primary = model.PrimaryPart
	if primary then
		return primary
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function getPlayerRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function getNearestKiosk(player: Player): (Model?, number?)
	local root = getPlayerRoot(player)
	if not root then
		return nil, nil
	end

	local nearestModel: Model? = nil
	local nearestDistance: number? = nil
	for _, model in ipairs(findKioskModels()) do
		local promptPart = getKioskPromptPart(model)
		if promptPart then
			local distance = (root.Position - promptPart.Position).Magnitude
			if nearestDistance == nil or distance < nearestDistance then
				nearestModel = model
				nearestDistance = distance
			end
		end
	end

	return nearestModel, nearestDistance
end

local function sendInventorySnapshot(player: Player)
	snapshotEvent:FireClient(player, ProfileService.getInventorySnapshot(player.UserId))
	player:SetAttribute("LobbyInventorySyncNonce", Workspace:GetServerTimeNow())
end

local function sendQuartermasterState(player: Player, notice: string?)
	quartermasterStateEvent:FireClient(player, ProfileService.getQuartermasterState(player.UserId, notice))
end

local function openQuartermaster(player: Player)
	openKioskByUserId[player.UserId] = true
	terminalOpenEvent:FireClient(player, {
		terminal = KIOSK_TERMINAL_NAME,
	})
	sendQuartermasterState(player, nil)
end

local function tryOpenQuartermaster(player: Player)
	local nearestModel, nearestDistance = getNearestKiosk(player)
	if nearestModel == nil or nearestDistance == nil or nearestDistance > OPEN_DISTANCE then
		return
	end

	openQuartermaster(player)
end

for _, model in ipairs(findKioskModels()) do
	local prompt = getKioskPrompt(model)
	if prompt then
		prompt.Triggered:Connect(function(player: Player)
			tryOpenQuartermaster(player)
		end)
	end
end

terminalInteractRequestEvent.OnServerEvent:Connect(function(player: Player, payload: any)
	if typeof(payload) ~= "table" or payload.terminal ~= KIOSK_TERMINAL_NAME then
		return
	end

	tryOpenQuartermaster(player)
end)

terminalCloseEvent.OnServerEvent:Connect(function(player: Player, payload: any)
	if typeof(payload) ~= "table" or payload.terminal ~= KIOSK_TERMINAL_NAME then
		return
	end

	openKioskByUserId[player.UserId] = nil
	ProfileService.forceSave(player.UserId, "quartermaster_close")
end)

quartermasterSellRequestEvent.OnServerEvent:Connect(function(player: Player, payload: any)
	if openKioskByUserId[player.UserId] ~= true then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end

	local itemId = payload.itemId
	local source = payload.source
	local profileBeforeSale = ProfileService.getProfile(player.UserId)
	local soldItem = if typeof(profileBeforeSale) == "table" and typeof(profileBeforeSale.items) == "table" then profileBeforeSale.items[itemId] else nil
	local ok, reason, sellValue = ProfileService.handleQuartermasterSell(player.UserId, itemId, source)
	if not ok then
		warn(string.format(
			"[QuartermasterService] reject userId=%d itemId=%s source=%s reason=%s",
			player.UserId,
			tostring(itemId),
			tostring(source),
			tostring(reason)
		))
		sendQuartermasterState(player, if reason == "not_sellable" then "That item cannot be sold." else "Sale rejected.")
		return
	end

	sendInventorySnapshot(player)
	sendQuartermasterState(player, string.format("Sold +%d REQ", sellValue or 0))
	ProfileService.forceSave(player.UserId, "quartermaster_sell")
	local soldTemplateId = if typeof(soldItem) == "table" then soldItem.templateId else "unknown"
	print(string.format(
		"[QuartermasterService] sale userId=%d itemId=%s templateId=%s value=%d",
		player.UserId,
		tostring(itemId),
		tostring(soldTemplateId),
		sellValue or 0
	))
end)

Players.PlayerRemoving:Connect(function(player)
	openKioskByUserId[player.UserId] = nil
end)
