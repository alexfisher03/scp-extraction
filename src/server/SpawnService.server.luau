--!strict

local Players = game:GetService("Players")

local function getSpawnFolder(): Folder
    local maps = workspace:WaitForChild("Maps")
    local level0 = maps:WaitForChild("Level0")
    local gameplay = level0:WaitForChild("Gameplay")
    local spawns = gameplay:WaitForChild("Spawns")
    return spawns :: Folder
end

local function getSpawnPoints(): {BasePart}
    local spawnsFolder = getSpawnFolder()
    local points = {}

    for _, inst in ipairs(spawnsFolder:GetChildren()) do
        if inst:IsA("BasePart") then
            table.insert(points, inst)
        end
    end

    assert(#points > 0, "No spawn points found in the Spawns folder.")
    return points
end

local function chooseSpawn(points: {BasePart}): BasePart
    return points[5]
end

local function spawnCharacterAt(player: Player, character: Model)
    local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart
    local points = getSpawnPoints()
    local spawnPoint = chooseSpawn(points)

    -- Place character slightly above the marker
    local cf = spawnPoint.CFrame + Vector3.new(0, 3, 0)
    character:PivotTo(cf)

    -- reset velocity so they don't inherit weird physics
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        spawnCharacterAt(player, character)
    end)
end)