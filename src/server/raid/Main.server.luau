--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)

if not PlaceConfig.isRaidPlace() then
	return
end

local function rejectToLobby(player: Player)
	if PlaceConfig.LOBBY_PLACE_ID ~= 0 then
		TeleportService:Teleport(PlaceConfig.LOBBY_PLACE_ID, player)
	else
		player:Kick("Join via Lobby")
	end
end

local function validateRaidAdmission(player: Player)
	local joinData = player:GetJoinData()
	local teleportData = joinData.TeleportData
	if typeof(teleportData) ~= "table" then
		rejectToLobby(player)
		return
	end

	local raidId = teleportData.raidId
	local partyUserIds = teleportData.partyUserIds
	if typeof(raidId) ~= "string" or typeof(partyUserIds) ~= "table" then
		rejectToLobby(player)
		return
	end

	local allowed = false
	for _, userId in ipairs(partyUserIds) do
		if userId == player.UserId then
			allowed = true
			break
		end
	end

	if not allowed then
		rejectToLobby(player)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	validateRaidAdmission(player)
end

Players.PlayerAdded:Connect(validateRaidAdmission)
