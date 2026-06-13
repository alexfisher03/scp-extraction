--!strict

local function requireChild(parent: Instance, baseName: string)
	local child = parent:FindFirstChild(baseName)
		or parent:FindFirstChild(baseName .. ".server")
		or parent:FindFirstChild(baseName .. ".server.luau")

	if not child then
		warn(string.format("[Server.init] Missing child '%s' under %s", baseName, parent:GetFullName()))
		return nil
	end

	return require(child)
end

requireChild(script.Parent, "Remotes")
requireChild(script.Parent, "SpawnService")
requireChild(script.Parent, "InventoryService")
requireChild(script.Parent, "RaidService")
requireChild(script.Parent, "LoadoutService")
requireChild(script.Parent:FindFirstChild("lobby") or script.Parent, "QueueService")
requireChild(script.Parent:FindFirstChild("lobby") or script.Parent, "ProfileService")
requireChild(script.Parent:FindFirstChild("lobby") or script.Parent, "StashService")
requireChild(script.Parent:FindFirstChild("lobby") or script.Parent, "QuartermasterService")
requireChild(script.Parent:FindFirstChild("lobby") or script.Parent, "PostRaidService")
