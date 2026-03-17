--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)

if PlaceConfig.isLobbyPlace() then
	local lobbyFolder = script.Parent:FindFirstChild("lobby")
	if lobbyFolder and lobbyFolder:FindFirstChild("Main") then
		require(lobbyFolder.Main)
	end
elseif PlaceConfig.isRaidPlace() then
	local raidFolder = script.Parent:FindFirstChild("raid")
	if raidFolder and raidFolder:FindFirstChild("Main") then
		require(raidFolder.Main)
	end
end
