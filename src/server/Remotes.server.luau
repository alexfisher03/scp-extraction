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

ensureRemote(Net.InventoryActionEventName)
ensureRemote(Net.InventorySnapshotEventName)
ensureRemote(Net.LootPickupRequestEventName)
ensureRemote(Net.MoveItemRequestEventName)
ensureRemote(Net.DropItemRequestEventName)
ensureRemote(Net.ItemActionRequestEventName)
ensureRemote(Net.ExtractRequestStartEventName)
ensureRemote(Net.RaidStateEventName)
ensureRemote(Net.RaidReadyRequestEventName)
ensureRemote(Net.BodyLootOpenRequestEventName)
ensureRemote(Net.BodyLootCloseRequestEventName)
ensureRemote(Net.BodyLootTransferRequestEventName)
ensureRemote(Net.BodyLootSnapshotEventName)
ensureRemote(Net.LobbyJoinQueueEventName)
ensureRemote(Net.LobbyLeaveQueueEventName)
ensureRemote(Net.LobbyDevForceStartEventName)
ensureRemote(Net.LobbyQueueStatusEventName)
ensureRemote(Net.LobbyNoticeEventName)

return folder
