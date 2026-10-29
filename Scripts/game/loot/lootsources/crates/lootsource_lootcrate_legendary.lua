LOOT_TABLES.loottable_lootcrate_legendary= {
	list = {
		{ table = "loottable_seed",							weight = 1.0, uniqueTag = "seed" },
		{ table = "loottable_resources",                  	weight = 1.0 },
		{ table = "loottable_blocks",                  		weight = 1.0 },
		{ table = "loottable_bis",                  		weight = 1.0 },
	}
}

LOOT_TABLES.loottable_lootcrate_legendary_epic= {
	list = {
		{ table = "loottable_seed_epic",					weight = 1.0, uniqueTag = "seed" },
		{ table = "loottable_interactive_01",               weight = 1.0 },
		{ table = "loottable_resources_epic",               weight = 1.0},
		{ table = "loottable_blocks_epic",                	weight = 1.0 },
		{ table = "loottable_bis_epic",                		weight = 1.0 },
	}
}

LOOT_SOURCES.lootsource_lootcrate_legendary = {
	loot = {
		{
			list = {
				{ table = "loottable_bis_epic",								weight = 0.20, 		cost = 0, 		epic = true }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_legendary_epic",				weight = 0.70, 		cost = 0, 		epic = true },
				{ uuid = obj_outfitpackage_epic,							weight = 0.30, 		cost = 0,		quantity = { 1 } }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_legendary_epic",				weight = 1.0, 		cost = 0,  		epic = true  },
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_legendary_epic",				weight = 1.0, 		cost = 0,  		epic = true  },
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_legendary_epic",				weight = 1.0, 		cost = 0,  		epic = true  },
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_legendary_epic",				weight = 1.0, 		cost = 0,  		epic = true  },
			}
		},
	}
}

LOOT_SOURCES.lootsource_lootcrate_legendary_warehouse = {
	loot = {
		{
			list = {
				{ table = "loottable_bis",									weight = 0.80, 		cost = 0 },
				{ table = "loottable_bis_epic",								weight = 0.20, 		cost = 0, 		epic = true }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_legendary_epic",				weight = 0.60, 		cost = 0, 		epic = true },
				{ uuid = obj_outfitpackage_legendary,						weight = 0.40, 		cost = 0,		quantity = { 1 } }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_legendary_epic",				weight = 1.0, 		cost = 0,  		epic = true  },
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_legendary_epic",				weight = 1.0, 		cost = 0,  		epic = true  },
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_legendary_epic",				weight = 1.0, 		cost = 0,  		epic = true  },
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_legendary_epic",				weight = 1.0, 		cost = 0,  		epic = true  },
			}
		},
	}
}

LOOT_SOURCES.lootsource_lootcrate_legendary_underground = {
	loot = {
		{
			list = {
				{ table = "loottable_bis_epic",								weight = 0.20, 		cost = 0, 		epic = true }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_legendary_epic",				weight = 0.60, 		cost = 0, 		epic = true },
				{ uuid = obj_outfitpackage_epic,							weight = 0.40, 		cost = 0,		quantity = { 1 } }
			}
		},
		{
			list = {
				{ uuid = obj_resource_wonkstonks,							weight = 1,		quantity = { 100 } },
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_legendary_epic",				weight = 1.0, 		cost = 0,  		epic = true  },
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_legendary_epic",				weight = 1.0, 		cost = 0,  		epic = true  },
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_legendary_epic",				weight = 1.0, 		cost = 0,  		epic = true  },
			}
		},
	}
}