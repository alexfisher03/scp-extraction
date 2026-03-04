--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local fireEvent = remotes:WaitForChild(Net.GunFireEventName) :: RemoteEvent

local MAX_DISTANCE = 300
local DAMAGE = 30
local COOLDOWN = 0.15

local lastShot: {[number]: number} = {}

local function isAliveCharacter(character: Model): boolean
    if not character then return false end
    local hum = character:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function getRoot(character: Model): BasePart?
    return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

fireEvent.OnServerEvent:Connect(function(player: Player, origin: Vector3, direction: Vector3)
	-- rate limit
	local now = os.clock()
	local prev = lastShot[player.UserId]
	if prev and (now - prev) < COOLDOWN then
		return
	end
	lastShot[player.UserId] = now

	if direction.Magnitude < 0.9 or direction.Magnitude > 1.1 then
		return
	end
	if not isAliveCharacter(player.Character) then
		return
	end

	local root = getRoot(player.Character :: Model)
	if not root then return end

	-- prevent "shooting from across the map" by requiring origin near player
	if (origin - root.Position).Magnitude > 10 then
		origin = root.Position
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	params.IgnoreWater = true

	local result = workspace:Raycast(origin, direction * MAX_DISTANCE, params)
	if not result then return end

	local hit = result.Instance
	local hitModel = hit:FindFirstAncestorOfClass("Model")
	if not hitModel then return end

	local humanoid = hitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	humanoid:TakeDamage(DAMAGE)
end)