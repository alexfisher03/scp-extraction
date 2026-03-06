--!strict 

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local function getHumanoid(): Humanoid?
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

local function findToolInBackpack(name: string): Tool?
    local backpack = player:WaitForChild("Backpack")
    if not backpack then return nil end
    for _, child in ipairs(backpack:GetChildren()) do
        if child:IsA("Tool") and child.Name == name then
            return child
        end
    end 
    return nil
end

local function findEquippedTool(): Tool?
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Tool")
end

local function equipRifle()
    local hum = getHumanoid()
    if not hum then return end

    local equipped = findEquippedTool()
    if equipped and equipped.Name == "Rifle" then
        hum:UnequipTools()
        return
    end

    local rifle = findToolInBackpack("Rifle")
    if rifle then
        hum:EquipTool(rifle)
    end
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == Enum.KeyCode.One then 
        equipRifle()
    end
end)