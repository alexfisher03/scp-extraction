-- src/server/doors/SCPDoorController.luau
--!strict

local TweenService = game:GetService("TweenService")
local InventoryAuthority = require(script.Parent.Parent.inventory.InventoryAuthority)
local RaidAuthority = require(script.Parent.Parent.raid.RaidAuthority)

local SCPDoorController = {}

local function getBoolAttr(inst: Instance, name: string, default: boolean): boolean
	local v = inst:GetAttribute(name)
	if typeof(v) == "boolean" then return v end
	return default
end

local function getRequiredKeyLevel(doorModel: Model): number
	local required = doorModel:GetAttribute("RequiredKeyLevel")

	if typeof(required) ~= "number" then
		return 0
	end

	return required
end

local function findAndConsumeKeycard(state: any, templateId: string): boolean
	for _, containerName in ipairs({ "backpack", "rig" }) do
		local container = state[containerName]
		if container then
			for slotIndex = 1, container.capacity do
				local itemId = container.itemIds[slotIndex]
				local item = itemId and state.itemsById[itemId] or nil
				if item and item.templateId == templateId and (item.usesRemaining or 0) > 0 then
					item.usesRemaining = (item.usesRemaining or 0) - 1
					return true
				end
			end
		end
	end

	return false
end

local function tryConsumeKey(player: Player, requiredLevel: number): (boolean, string?)
	if requiredLevel <= 0 then
		return true, nil
	end

	local state = InventoryAuthority.getState(player.UserId)
	if not state then
		return false, nil
	end

	local exactCardTemplateId = string.format("card_%d", requiredLevel)
	if findAndConsumeKeycard(state, exactCardTemplateId) then
		InventoryAuthority.emitSnapshot(player, state)
		return true, exactCardTemplateId
	end

	if findAndConsumeKeycard(state, "card_omni") then
		InventoryAuthority.emitSnapshot(player, state)
		return true, "card_omni"
	end

	return false, nil
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
		if not RaidAuthority.isInRaid(player.UserId) then
			return
		end

		local required = getRequiredKeyLevel(doorModel)
		local unlockedThisRaid = getBoolAttr(doorModel, "UnlockedThisRaid", false)
		local lockedAttr = doorModel:GetAttribute("Locked")
		local locked = if typeof(lockedAttr) == "boolean" then lockedAttr else required > 0

		if required <= 0 and pressedButton then
			playSound(pressedButton, "Push")
		elseif (not locked or unlockedThisRaid) and pressedButton then
			playSound(pressedButton, "Push")
		end

		if required > 0 and not unlockedThisRaid and locked then
			local consumed, _usedCard = tryConsumeKey(player, required)
			if not consumed then
				playSound(door1, "LockedSound")
				return
			end

			doorModel:SetAttribute("UnlockedThisRaid", true)
			doorModel:SetAttribute("Locked", false)
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
