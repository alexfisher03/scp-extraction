--!strict

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
player.CameraMode = Enum.CameraMode.LockFirstPerson

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

player:SetAttribute("InventoryVisible", false)
player:SetAttribute("RaidPhase", "InRaid")
player:SetAttribute("PlayerCanFight", true)
player:SetAttribute("BodyLootOpen", false)
