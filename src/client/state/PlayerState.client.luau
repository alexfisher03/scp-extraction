--!strict

local Players = game:GetService("Players")
local PlayerState = {}

export type Snapshot = {
    equippedSlot: number, -- 0 none, 1 rifle
    equippedName: string?,
}

local function snapshot(): Snapshot
    local player = Players.LocalPlayer
    local char = player.Character
    if not char then
        return { equippedSlot = 0, equippedName = nil }
    end

    local tool = char:FindFirstChildOfClass("Tool")
    if tool and tool.Name == "Rifle" then
        return { equippedSlot = 1, equippedName = "Rifle" }
    end

    return { equippedSlot = 0, equippedName = nil }
end

function PlayerState.getSnapshot(): Snapshot
    return snapshot()
end

return PlayerState