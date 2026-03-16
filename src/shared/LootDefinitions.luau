--!strict

local LootDefinitions = {}

export type LootDefinition = {
	displayName: string,
	category: string,
	prefabName: string?,
	stack: number?,
	ammo: number?,
	capacity: number?,
	usesRemaining: number?,
	usesMax: number?,
}

local DEFINITIONS: {[string]: LootDefinition} = {
	mag_556_30 = {
		displayName = "5.56 Mag (30)",
		category = "mag",
		prefabName = "LootPickup_PM4Mag",
		ammo = 30,
		capacity = 30,
	},
	intel_folder_1 = {
		displayName = "Intel Folder",
		category = "loot",
		stack = 1,
	},
	med_ifak = {
		displayName = "IFAK",
		category = "med",
		prefabName = "LootPickup_Ifak",
		stack = 1,
	},
	card_omni = {
		displayName = "Omni Keycard",
		category = "keycard",
		prefabName = "LootPickup_CardOmni",
		stack = 1,
		usesRemaining = 10,
		usesMax = 10,
	},
	card_4 = {
		displayName = "Level 4 Keycard",
		category = "keycard",
		prefabName = "LootPickup_Card4",
		stack = 1,
		usesRemaining = 3,
		usesMax = 3,
	},
	card_3 = {
		displayName = "Level 3 Keycard",
		category = "keycard",
		prefabName = "LootPickup_Card3",
		stack = 1,
		usesRemaining = 3,
		usesMax = 3,
	},
	card_2 = {
		displayName = "Level 2 Keycard",
		category = "keycard",
		prefabName = "LootPickup_Card2",
		stack = 1,
		usesRemaining = 3,
		usesMax = 3,
	},
	card_1 = {
		displayName = "Level 1 Keycard",
		category = "keycard",
		prefabName = "LootPickup_Card1",
		stack = 1,
		usesRemaining = 3,
		usesMax = 3,
	},
}

function LootDefinitions.get(templateId: string): LootDefinition?
	return DEFINITIONS[templateId]
end

function LootDefinitions.getDisplayName(templateId: string): string
	local definition = DEFINITIONS[templateId]
	if definition then
		return definition.displayName
	end

	return templateId
end

return LootDefinitions
