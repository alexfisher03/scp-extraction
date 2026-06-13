--!strict

local LootDefinitions = {}

export type LootDefinition = {
	displayName: string,
	category: string,
	prefabName: string?,
	dropPolicy: string?,
	sellPolicy: string?,
	sellValue: number?,
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
		sellValue = 15,
		ammo = 30,
		capacity = 30,
	},
	intel_folder_1 = {
		displayName = "Intel Folder",
		category = "loot",
		sellValue = 120,
		stack = 1,
	},
	med_ifak = {
		displayName = "IFAK",
		category = "med",
		prefabName = "LootPickup_Ifak",
		sellValue = 25,
		stack = 1,
	},
	card_omni = {
		displayName = "Omni Keycard",
		category = "keycard",
		prefabName = "LootPickup_CardOmni",
		sellValue = 300,
		stack = 1,
		usesRemaining = 10,
		usesMax = 10,
	},
	card_4 = {
		displayName = "Level 4 Keycard",
		category = "keycard",
		prefabName = "LootPickup_Card4",
		sellValue = 140,
		stack = 1,
		usesRemaining = 3,
		usesMax = 3,
	},
	card_3 = {
		displayName = "Level 3 Keycard",
		category = "keycard",
		prefabName = "LootPickup_Card3",
		sellValue = 90,
		stack = 1,
		usesRemaining = 3,
		usesMax = 3,
	},
	card_2 = {
		displayName = "Level 2 Keycard",
		category = "keycard",
		prefabName = "LootPickup_Card2",
		sellValue = 55,
		stack = 1,
		usesRemaining = 3,
		usesMax = 3,
	},
	card_1 = {
		displayName = "Level 1 Keycard",
		category = "keycard",
		prefabName = "LootPickup_Card1",
		sellValue = 30,
		stack = 1,
		usesRemaining = 3,
		usesMax = 3,
	},
	rifle_m4 = {
		displayName = "M4 Rifle",
		category = "gun",
		sellPolicy = "NoSell",
		sellValue = 0,
	},
	knife = {
		displayName = "Combat Knife",
		category = "melee",
		sellPolicy = "NoSell",
		sellValue = 0,
	},
}

function LootDefinitions.get(templateId: string): LootDefinition?
	local definition = DEFINITIONS[templateId]
	if not definition then
		return nil
	end

	local enriched = table.clone(definition)
	if enriched.dropPolicy == nil then
		enriched.dropPolicy = "Normal"
	end
	if enriched.sellPolicy == nil then
		enriched.sellPolicy = "Normal"
	end
	if enriched.sellValue == nil then
		enriched.sellValue = 0
	end
	return enriched
end

function LootDefinitions.getDisplayName(templateId: string): string
	local definition = DEFINITIONS[templateId]
	if definition then
		return definition.displayName
	end

	return templateId
end

return LootDefinitions
