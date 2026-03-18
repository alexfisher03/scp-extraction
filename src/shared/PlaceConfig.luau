--!strict

local PlaceConfig = {}

PlaceConfig.LOBBY_PLACE_ID = 71814662227954
PlaceConfig.RAID_PLACE_ID = 102615838851895
PlaceConfig.RAID_SIZE = 8
PlaceConfig.QUEUE_MAX_WAIT_SECONDS = 50

local function isLobbyFallback(): boolean
	return workspace:FindFirstChild("Lobby") ~= nil
end

function PlaceConfig.isLobbyPlace(): boolean
	if PlaceConfig.LOBBY_PLACE_ID ~= 0 and game.PlaceId == PlaceConfig.LOBBY_PLACE_ID then
		return true
	end

	if PlaceConfig.RAID_PLACE_ID ~= 0 and game.PlaceId == PlaceConfig.RAID_PLACE_ID then
		return false
	end

	return isLobbyFallback()
end

function PlaceConfig.isRaidPlace(): boolean
	if PlaceConfig.RAID_PLACE_ID ~= 0 and game.PlaceId == PlaceConfig.RAID_PLACE_ID then
		return true
	end

	if PlaceConfig.LOBBY_PLACE_ID ~= 0 and game.PlaceId == PlaceConfig.LOBBY_PLACE_ID then
		return false
	end

	return not isLobbyFallback()
end

return PlaceConfig
