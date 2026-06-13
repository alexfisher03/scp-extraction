--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local Net = require(ReplicatedStorage.Shared.Net)

if not PlaceConfig.isRaidPlace() then
	return
end

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local purchaseTrapLogEvent = remotes:WaitForChild(Net.PurchaseTrapLogEventName) :: RemoteEvent

local function stringifyValue(value: any): string
	local valueType = typeof(value)
	if valueType == "Instance" then
		local instance = value :: Instance
		return string.format("%s(%s)", instance:GetFullName(), instance.ClassName)
	end
	if valueType == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function describeArgs(args: {any}): (Player?, number?, string)
	local player: Player? = nil
	local firstNumericId: number? = nil
	local parts = table.create(#args)

	for index, value in ipairs(args) do
		if typeof(value) == "Instance" and value:IsA("Player") and player == nil then
			player = value
		end
		if typeof(value) == "number" and firstNumericId == nil then
			firstNumericId = value
		end

		parts[index] = stringifyValue(value)
	end

	return player, firstNumericId, table.concat(parts, ", ")
end

local function hookPromptEvent(eventName: string)
	local ok, signalOrError = pcall(function()
		return (MarketplaceService :: any)[eventName]
	end)
	if not ok then
		warn(string.format("[PurchasePromptTrap] unable to read event=%s error=%s", eventName, tostring(signalOrError)))
		return
	end

	local signal = signalOrError
	if typeof(signal) ~= "RBXScriptSignal" then
		warn(string.format("[PurchasePromptTrap] missing signal event=%s", eventName))
		return
	end

	(signal :: RBXScriptSignal):Connect(function(...)
		local args = { ... }
		local player, firstNumericId, argsText = describeArgs(args)
		local playerText = if player
			then string.format("%s (%d)", player.Name, player.UserId)
			else "unknown"

		warn(string.format(
			"[PurchasePromptTrap] event=%s player=%s firstNumericId=%s args=[%s]",
			eventName,
			playerText,
			tostring(firstNumericId),
			argsText
		))
		warn(debug.traceback(string.format("[PurchasePromptTrap] stack event=%s", eventName), 2))

		if player then
			purchaseTrapLogEvent:FireClient(player, {
				timestamp = Workspace:GetServerTimeNow(),
				eventName = eventName,
				firstNumericId = firstNumericId,
				argsText = argsText,
				message = string.format("%s id=%s", eventName, tostring(firstNumericId)),
			})
		end
	end)

	print(string.format("[PurchasePromptTrap] hooked event=%s", eventName))
end

for _, eventName in ipairs({
	"PromptPurchaseRequested",
	"PromptProductPurchaseRequested",
	"PromptGamePassPurchaseRequested",
	"PromptBundlePurchaseRequested",
	"PromptSubscriptionPurchaseRequested",
}) do
	hookPromptEvent(eventName)
end
