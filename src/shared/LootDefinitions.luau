--!strict

local LootDefinitions = {}

export type LootDefinition = {
	displayName: string,
	category: string,
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
		stack = 1,
	},
	card_omni = {
		displayName = "Omni Keycard",
		category = "keycard",
		stack = 1,
		usesRemaining = 10,
		usesMax = 10,
	},
	card_4 = {
		displayName = "Level 4 Keycard",
		category = "keycard",
		stack = 1,
		usesRemaining = 3,
		usesMax = 3,
	},
	card_3 = {
		displayName = "Level 3 Keycard",
		category = "keycard",
		stack = 1,
		usesRemaining = 3,
		usesMax = 3,
	},
	card_2 = {
		displayName = "Level 2 Keycard",
		category = "keycard",
		stack = 1,
		usesRemaining = 3,
		usesMax = 3,
	},
	card_1 = {
		displayName = "Level 1 Keycard",
		category = "keycard",
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
