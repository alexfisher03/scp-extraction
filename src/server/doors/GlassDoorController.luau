--!strict
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

assert(RunService:IsServer(), "SlidingGlassDoorController must run on the server")

local SlidingGlassDoorController = {}

local function getHRP(plr: Player): BasePart?
	local char = plr.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function isAlive(plr: Player): boolean
	local char = plr.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function setDoorPhysics(parts: {BasePart}, open: boolean)
	for _, p in ipairs(parts) do
		-- open => do NOT block movement OR raycasts
		p.CanCollide = not open
		p.CanQuery = not open
		p.CanTouch = not open
	end
end

local function getAttrNumber(inst: Instance, name: string, default: number): number
	local v = inst:GetAttribute(name)
	if typeof(v) == "number" then return v end
	return default
end

local function getAttrString(inst: Instance, name: string, default: string): string
	local v = inst:GetAttribute(name)
	if typeof(v) == "string" then return v end
	return default
end

local function slideAxisForDoorLeaf(leaf: BasePart): Vector3
	if leaf.Size.X >= leaf.Size.Z then
		return leaf.CFrame.RightVector
	else
		return leaf.CFrame.LookVector
	end
end

function SlidingGlassDoorController.bind(root: Model)
	local slidingDoor = root:FindFirstChild("Sliding Door")
	if not (slidingDoor and slidingDoor:IsA("Model")) then
		warn("[SlideDoor] Missing Model 'Sliding Door' under:", root:GetFullName())
		return
	end

	local sliding = slidingDoor:FindFirstChild("Sliding door")
	if not (sliding and sliding:IsA("Model")) then
		warn("[SlideDoor] Missing Model 'Sliding door' under:", slidingDoor:GetFullName())
		return
	end

	local doorContainer = sliding:FindFirstChild("Door")
	if not (doorContainer and doorContainer:IsA("Model")) then
		warn("[SlideDoor] Missing Model 'Door' under:", sliding:GetFullName())
		return
	end

	local door1 = doorContainer:FindFirstChild("Door1")
	local door2 = doorContainer:FindFirstChild("Door2")
	if not (door1 and door1:IsA("BasePart") and door2 and door2:IsA("BasePart")) then
		warn("[SlideDoor] Missing Door1/Door2 BaseParts under:", doorContainer:GetFullName())
		return
	end

	-- Optional speed NumberValue (but you said it exists)
	local speedVal = sliding:FindFirstChild("Speed")
	local speed = 1.6
	if speedVal and speedVal:IsA("NumberValue") then
		speed = speedVal.Value
	end

	-- Configurable on the TOP model via Attributes
	local radius = getAttrNumber(root, "AutoRadius", 10)
	local closeDelay = getAttrNumber(root, "CloseDelay", 0.6)
	local openDistance = getAttrNumber(root, "OpenDistance", 5)

	-- Convert speed -> tween time deterministically
	local tweenTime = math.clamp(2.0 / speed, 0.15, 1.25)
	local tweenInfo = TweenInfo.new(tweenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	-- Record closed positions once
	local closed1 = door1.CFrame
	local closed2 = door2.CFrame

	-- Open positions: slide leaves apart in opposite directions
	local dir = slideAxisForDoorLeaf(door1)
    local open1 = closed1 + dir * openDistance
    local open2 = closed2 - dir * openDistance

	local parts = { door1, door2 }

	local isOpen = false
	local lastSeen = 0.0

	local function sensorPos(): Vector3
		-- use midpoint of the two doors as the proximity sensor
		return (door1.Position + door2.Position) * 0.5
	end

	local function openDoor()
		if isOpen then return end
		isOpen = true
		setDoorPhysics(parts, true)
		TweenService:Create(door1, tweenInfo, { CFrame = open1 }):Play()
		TweenService:Create(door2, tweenInfo, { CFrame = open2 }):Play()
	end

	local function closeDoor()
		if not isOpen then return end
		isOpen = false
		setDoorPhysics(parts, false)
		TweenService:Create(door1, tweenInfo, { CFrame = closed1 }):Play()
		TweenService:Create(door2, tweenInfo, { CFrame = closed2 }):Play()
	end

	task.spawn(function()
		warn("[SlideDoor] bound:", root:GetFullName())

		while root.Parent ~= nil do
			local pos = sensorPos()
			local found = false

			for _, plr in ipairs(Players:GetPlayers()) do
				local hrp = getHRP(plr)
				if hrp and isAlive(plr) and (hrp.Position - pos).Magnitude <= radius then
					found = true
					break
				end
			end

			local now = os.clock()
			if found then
				lastSeen = now
				openDoor()
			else
				if isOpen and (now - lastSeen) >= closeDelay then
					closeDoor()
				end
			end

			task.wait(0.1)
		end
	end)
end

return SlidingGlassDoorController