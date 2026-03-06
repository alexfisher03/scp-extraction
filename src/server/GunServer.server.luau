--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local remotes = ReplicatedStorage:WaitForChild(Net.RemotesFolderName)
local fireEvent = remotes:WaitForChild(Net.GunFireEventName) :: RemoteEvent
local reloadEvent = remotes:WaitForChild(Net.GunReloadEventName) :: RemoteEvent
local checkMagEvent = remotes:WaitForChild(Net.GunCheckMagEventName) :: RemoteEvent
local gunStateEvent = remotes:WaitForChild(Net.GunStateEventName) :: RemoteEvent

local MAX_DISTANCE = 300
local DAMAGE = 30
local SHOT_COOLDOWN = 0.15
local RELOAD_SECONDS = 2.2
local CHECK_MAG_SECONDS = 1.0
local CHECK_MAG_COOLDOWN = 0.6

local DEFAULT_MAG_SIZE = 30

type WeaponState = {
	magSize: number,
	ammoInMag: number, 
	reloading: boolean,
	lastShotAt: number,
	lastCheckMagAt: number,
}

local states: {[number]: WeaponState} = {}

local function isAliveCharacter(character: Model?): boolean
	if not character then return false end
	local hum = character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function getRoot(character: Model): BasePart?
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function hasEquippedWeapon(player: Player): boolean
	local char = player.Character
	if not char then
		return false
	end
	local tool = char:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool.Name == "Rifle"
end

local function getOrCreateState(player: Player): WeaponState
	local existing = states[player.UserId]
	if existing then
		return existing
	end

	local created: WeaponState = {
		magSize = DEFAULT_MAG_SIZE,
		ammoInMag = DEFAULT_MAG_SIZE,
		reloading = false,
		lastShotAt = 0,
		lastCheckMagAt = 0,
	}
	states[player.UserId] = created
	return created
end

local function getMagRead(state: WeaponState): string
	local ratio = state.ammoInMag / state.magSize
	if ratio == 1 then
		return "Full"
	elseif ratio > 0.85 and ratio < 1 then
		return "Almost Full"
	elseif ratio > 0.5 and ratio <= 0.85 then
		return "More than Half"
	elseif ratio == 0.5 then
		return "Half"
	elseif ratio > 0.15 and ratio < 0.5 then
		return "Less than Half"
	elseif ratio > 0 and ratio <= 0.15 then
		return "Almost Empty"
	else
		return "Empty"
	end
end

local function sendState(player: Player, state: WeaponState, magRead: string?)
	gunStateEvent:FireClient(player, {
        ammoInMag = state.ammoInMag,
        magSize = state.magSize,
        reloading = state.reloading,
        magRead = magRead,
    })
end

local function resetForSpawn(player: Player)
    local state = getOrCreateState(player)
    state.magSize = DEFAULT_MAG_SIZE
    state.ammoInMag = DEFAULT_MAG_SIZE
    state.reloading = false
    state.lastShotAt = 0
    state.lastCheckMagAt = 0
    sendState(player, state, nil)
end

Players.PlayerAdded:Connect(function(player)
	getOrCreateState(player)
	player.CharacterAdded:Connect(function()
		resetForSpawn(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
    states[player.UserId] = nil
end)

fireEvent.OnServerEvent:Connect(function(player: Player, origin: Vector3, direction: Vector3)
    local state = getOrCreateState(player)

    local now = os.clock()
    if (now - state.lastShotAt) < SHOT_COOLDOWN then
        return
    end
    state.lastShotAt = now

    if not hasEquippedWeapon(player) then
        return
    end
    if not isAliveCharacter(player.Character) then
        return
    end
    if state.reloading then
        return
    end
    if state.ammoInMag <= 0 then
        sendState(player, state, nil)
        return
    end

    if direction.Magnitude < 0.9 or direction.Magnitude > 1.1 then
        return
    end

    local character = player.Character :: Model
    local root = getRoot(character)
    if not root then
        return
    end

    if (origin - root.Position).Magnitude > 10 then
        origin = root.Position
    end

    state.ammoInMag -= 1
    sendState(player, state, nil)

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character }
    params.IgnoreWater = true

    local result = workspace:Raycast(origin, direction * MAX_DISTANCE, params)
    if not result then
        return
    end

    local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
    if not hitModel then
        return
    end

    local humanoid = hitModel:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid:TakeDamage(DAMAGE)
    end
    -- DEBUG
    print("Gun Shot", "Player:", player.Name, "Hit:", hitModel.Name, "Humanoid:", humanoid and humanoid.Name or "None")
end)

reloadEvent.OnServerEvent:Connect(function(player: Player)
    local state = getOrCreateState(player)

    if not hasEquippedWeapon(player) then
        return
    end
    if not isAliveCharacter(player.Character) then
        return
    end
    if state.reloading then
        return
    end
    if state.ammoInMag >= state.magSize then
        return
    end

    state.reloading = true
    sendState(player, state, nil)

    task.delay(RELOAD_SECONDS, function()
        local current = states[player.UserId]
        if not current then
            return
        end
        if not player.Parent then
            return
        end

        current.ammoInMag = current.magSize
        current.reloading = false
        sendState(player, current, nil)
    end)
end)

checkMagEvent.OnServerEvent:Connect(function(player: Player)
    local state = getOrCreateState(player)
    local now = os.clock()

    if not hasEquippedWeapon(player) then
        return
    end
    if not isAliveCharacter(player.Character) then
        return
    end
    if state.reloading then
        return
    end
    if (now - state.lastCheckMagAt) < CHECK_MAG_COOLDOWN then
        return
    end
    state.lastCheckMagAt = now

    task.delay(CHECK_MAG_SECONDS, function()
        local current = states[player.UserId]
        if not current then
            return
        end
        if not player.Parent then
            return
        end

        sendState(player, current, getMagRead(current))
    end)
end)