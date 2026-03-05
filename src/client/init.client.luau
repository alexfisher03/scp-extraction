local Players = game:GetService("Players")
local player = Players.LocalPlayer
player.CameraMode = Enum.CameraMode.LockFirstPerson

require(script.Parent:WaitForChild("GunClient"))
require(script.Parent:WaitForChild("ui"):WaitForChild("Hud"))