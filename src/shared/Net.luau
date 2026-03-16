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
	BodyLootOpenRequestEventName = "BodyLootOpenRequest",
	BodyLootCloseRequestEventName = "BodyLootCloseRequest",
	BodyLootTransferRequestEventName = "BodyLootTransferRequest",
	BodyLootSnapshotEventName = "BodyLootSnapshot",
}
