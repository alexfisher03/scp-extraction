--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local folder = ReplicatedStorage:FindFirstChild(Net.RemotesFolderName)
if not folder then
    folder = Instance.new("Folder")
    folder.Name = Net.RemotesFolderName
    folder.Parent = ReplicatedStorage
end

local fireEvent = folder:FindFirstChild(Net.GunFireEventName)
if not fireEvent then
	fireEvent = Instance.new("RemoteEvent")
	fireEvent.Name = Net.GunFireEventName
	fireEvent.Parent = folder
end

return folder