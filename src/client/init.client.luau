local Players = game:GetService("Players")
local player = Players.LocalPlayer
player.CameraMode = Enum.CameraMode.LockFirstPerson

require(script.Parent:WaitForChild("GunClient"))