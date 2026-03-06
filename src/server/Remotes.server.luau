--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local folder = ReplicatedStorage:FindFirstChild(Net.RemotesFolderName)
if not folder then
    folder = Instance.new("Folder")
    folder.Name = Net.RemotesFolderName
    folder.Parent = ReplicatedStorage
end

local function ensureRemote(name: string): RemoteEvent
    local remote = folder:FindFirstChild(name)
    if remote and remote:IsA("RemoteEvent") then
        return remote
    end

    local created = Instance.new("RemoteEvent")
    created.Name = name
    created.Parent = folder
    return created
end

ensureRemote(Net.GunFireEventName)
ensureRemote(Net.GunReloadEventName)
ensureRemote(Net.GunCheckMagEventName)
ensureRemote(Net.GunStateEventName)

return folder