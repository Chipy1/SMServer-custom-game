LOOT_TABLES.loottable_lootcrate_epic= {
	list = {
		{ table = "loottable_seed",							weight = 1.0, uniqueTag = "seed" },
		{ table = "loottable_resources",                  	weight = 1.0 },
		{ table = "loottable_blocks",                  		weight = 1.0 },
		{ table = "loottable_bis",                  		weight = 1.0 },
	}
}

LOOT_TABLES.loottable_lootcrate_epic_epic= {
	list = {
		{ table = "loottable_seed_epic",					weight = 1.0, uniqueTag = "seed" },
		{ table = "loottable_interactive_01",               weight = 1.0 },
		{ table = "loottable_resources_epic",               weight = 1.0},
		{ table = "loottable_blocks_epic",                	weight = 1.0 },
		{ table = "loottable_bis_epic",                		weight = 1.0 },
	}
}

LOOT_SOURCES.lootsource_lootcrate_epic = {
	loot = {
		{
			list = {
				{ table = "loottable_bis",								weight = 0.80, 		cost = 0 },
				{ table = "loottable_bis_epic",							weight = 0.20, 		cost = 0, 		epic = true }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_epic_epic",				weight = 0.60, 		cost = 0, 		epic = true },
				{ uuid = obj_outfitpackage_rare,						weight = 0.20, 		cost = 0,		quantity = { 1 }, epic = true },
				{ uuid = obj_outfitpackage_common,						weight = 0.20, 		cost = 0,		quantity = { 1 } }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_epic",					weight = 0.75, 		cost = 0  },
				{ table = "loottable_lootcrate_epic_epic",				weight = 0.75, 		cost = 0, 		epic = true },
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_epic",					weight = 1.0, 		cost = 0 },
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_epic",					weight = 1.0, 		cost = 0 },
			}
		},
	}
}

LOOT_SOURCES.lootsource_lootcrate_epic_warehouse = {
	loot = {
		{
			list = {
				{ table = "loottable_bis",								weight = 0.80, 		cost = 0 },
				{ table = "loottable_bis_epic",							weight = 0.20, 		cost = 0, 		epic = true }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_epic_epic",				weight = 0.60, 		cost = 0, 		epic = true },
				{ uuid = obj_outfitpackage_rare,						weight = 0.40, 		cost = 0,		quantity = { 1 } }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_epic",					weight = 0.75, 		cost = 0 },
				{ table = "loottable_lootcrate_epic_epic",					weight = 0.75, 		cost = 0, 	epic = true },
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_epic",					weight = 1.0, 		cost = 0 },
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_epic",					weight = 1.0, 		cost = 0 },
			}
		},
	}
}
LOOT_SOURCES.lootsource_lootcrate_epic_underground = {
	loot = {
		{
			list = {
				{ table = "loottable_bis",								weight = 0.80, 		cost = 0 },
				{ table = "loottable_bis_epic",							weight = 0.20, 		cost = 0, 		epic = true }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_epic_epic",				weight = 0.60, 		cost = 0, 		epic = true },
				{ uuid = obj_outfitpackage_rare,						weight = 0.20, 		cost = 0,		quantity = { 1 }, epic = true },
				{ uuid = obj_outfitpackage_common,						weight = 0.20, 		cost = 0,		quantity = { 1 } }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_epic",					weight = 0.75, 		cost = 0  },
				{ table = "loottable_lootcrate_epic_epic",				weight = 0.75, 		cost = 0, 		epic = true },
			}
		},
		{
			list = {
				{ uuid = obj_resource_wonkstonks,		weight = 1,		quantity = { 25, 50, 100 } },
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_epic",					weight = 1.0, 		cost = 0 },
			}
		},
	}
}