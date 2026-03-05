-- src/server/doors/SCPDoorController.luau
--!strict

local TweenService = game:GetService("TweenService")

local SCPDoorController = {}

local function getBoolAttr(inst: Instance, name: string, default: boolean): boolean
	local v = inst:GetAttribute(name)
	if typeof(v) == "boolean" then return v end
	return default
end

local function getNumberAttr(inst: Instance, name: string, default: number): number
	local v = inst:GetAttribute(name)
	if typeof(v) == "number" then return v end
	return default
end

-- TODO: replace with your real inventory system later
local function playerHasKeycardAtLeast(_player: Player, requiredLevel: number): boolean
	return requiredLevel <= 0
end

local function playSound(inst: Instance?, soundName: string)
	if not inst then return end
	local s = inst:FindFirstChild(soundName)
	if s and s:IsA("Sound") then
		s:Play()
	end
end

local function playRandomSound(inst: Instance?, prefix: string, minN: number, maxN: number)
	if not inst then return end
	local n = math.random(minN, maxN)
	local s = inst:FindFirstChild(prefix .. tostring(n))
	if s and s:IsA("Sound") then
		s:Play()
	end
end

local function setDoorAssemblyPhysics(doorModel: Model, open: boolean)
	for _, inst in ipairs(doorModel:GetDescendants()) do
		if inst:IsA("BasePart") then
			-- keep buttons interactive
			if inst.Name == "Button1" or inst.Name == "Button2" then
				continue
			end
			inst.CanCollide = not open
			inst.CanQuery = not open
			inst.CanTouch = not open
		end
	end
end

function SCPDoorController.bind(doorModel: Model)
	local door1 = doorModel:WaitForChild("Door1") :: BasePart
	local door2 = doorModel:WaitForChild("Door2") :: BasePart
	local fakeD1 = doorModel:WaitForChild("FakeD1") :: BasePart
	local fakeD2 = doorModel:WaitForChild("FakeD2") :: BasePart
	local fDoor1 = doorModel:WaitForChild("FDoor1") :: BasePart
	local fDoor2 = doorModel:WaitForChild("FDoor2") :: BasePart

	-- Ensure reference parts never block
	for _, ref in ipairs({ fakeD1, fakeD2, fDoor1, fDoor2 }) do
		ref.Anchored = true
		ref.CanCollide = false
		ref.CanQuery = false
		ref.CanTouch = false
	end

	local isOpenValue = doorModel:FindFirstChild("IsOpen")
	local isOpen = if isOpenValue and isOpenValue:IsA("BoolValue") then isOpenValue else nil

	local idleValue = doorModel:FindFirstChild("Idle")
	local idle = if idleValue and idleValue:IsA("BoolValue") then idleValue else nil

	local tweenInfo = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	local function openDoor()
		if idle then idle.Value = false end

		TweenService:Create(door1, tweenInfo, { CFrame = fakeD1.CFrame }):Play()
		TweenService:Create(door2, tweenInfo, { CFrame = fakeD2.CFrame }):Play()

		-- IMPORTANT: allow shots through when open
		setDoorAssemblyPhysics(doorModel, true)

		-- Audio: Door1.Open1..3
		playRandomSound(door1, "Open", 1, 3)

		if isOpen then isOpen.Value = true end
		task.delay(1.7, function()
			if idle then idle.Value = true end
		end)
	end

	local function closeDoor()
		if idle then idle.Value = false end

		TweenService:Create(door1, tweenInfo, { CFrame = fDoor1.CFrame }):Play()
		TweenService:Create(door2, tweenInfo, { CFrame = fDoor2.CFrame }):Play()

		setDoorAssemblyPhysics(doorModel, false)

		-- Audio: Door1.Close1..3
		playRandomSound(door1, "Close", 1, 3)

		if isOpen then isOpen.Value = false end
		task.delay(1.7, function()
			if idle then idle.Value = true end
		end)
	end

	local function tryToggle(player: Player, pressedButton: Instance?)
		local locked = getBoolAttr(doorModel, "Locked", false)
		local required = getNumberAttr(doorModel, "RequiredKeycardLevel", 0)

		-- Button push sound (only if not locked)
		if not locked and pressedButton then
			playSound(pressedButton, "Push")
		end

		if locked and not playerHasKeycardAtLeast(player, required) then
			-- Audio: Door1.LockedSound if present
			playSound(door1, "LockedSound")

			-- Optional: if your model has DoorGui under the Script like before, you can re-add UI later.
			return
		end

		local currentlyOpen = (isOpen and isOpen.Value) or false
		if currentlyOpen then
			closeDoor()
		else
			openDoor()
		end
	end

	-- Hook up both click detectors and proximity prompts
	for _, btnName in ipairs({ "Button1", "Button2" }) do
		local btn = doorModel:FindFirstChild(btnName)
		if btn then
			local cd = btn:FindFirstChildOfClass("ClickDetector")
			if cd then
				cd.MouseClick:Connect(function(plr)
					tryToggle(plr, btn)
				end)
			end
			local pp = btn:FindFirstChildOfClass("ProximityPrompt")
			if pp then
				pp.Triggered:Connect(function(plr)
					tryToggle(plr, btn)
				end)
			end
		end
	end
end

return SCPDoorController