--!strict

return {
	RemotesFolderName = "_remotes",
	InventoryActionEventName = "InventoryAction",  -- client to server
	InventorySnapshotEventName = "InventorySnapshot", -- server to client
	LootPickupRequestEventName = "LootPickupRequest", -- client to server
	MoveItemRequestEventName = "MoveItemRequest",
	DropItemRequestEventName = "DropItemRequest",
	ItemActionRequestEventName = "ItemActionRequest",
	ExtractRequestStartEventName = "ExtractRequestStart",
	RaidStateEventName = "RaidState",
	RaidReadyRequestEventName = "RaidReadyRequest",
	BodyLootOpenRequestEventName = "BodyLootOpenRequest",
	BodyLootCloseRequestEventName = "BodyLootCloseRequest",
	BodyLootTransferRequestEventName = "BodyLootTransferRequest",
	BodyLootSnapshotEventName = "BodyLootSnapshot",
	LobbyJoinQueueEventName = "Lobby_JoinQueue",
	LobbyLeaveQueueEventName = "Lobby_LeaveQueue",
	LobbyDevForceStartEventName = "Lobby_DevForceStart",
	LobbyQueueStatusEventName = "Lobby_QueueStatus",
	LobbyNoticeEventName = "Lobby_Notice",
}
