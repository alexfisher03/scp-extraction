--!strict

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
player.CameraMode = Enum.CameraMode.LockFirstPerson

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

require(script.Parent:WaitForChild("GunClient"))
require(script.Parent:WaitForChild("ui"):WaitForChild("Hud"))
require(script.Parent:WaitForChild("ui"):WaitForChild("HotbarController"))