
--25%, 50%, 25%
LOOT_TABLES.loottable_lootcrate_common= {
	list = {
		{ table = "loottable_seed",							weight = 0.1, uniqueTag = "seed" },
		{ table = "loottable_resources",                  	weight = 0.9 },
	}
}

LOOT_TABLES.loottable_lootcrate_common_epic= {
	list = {
		{ table = "loottable_seed_epic",					weight = 0.33, uniqueTag = "seed" },
		{ table = "loottable_interactive_01",               weight = 0.33 },
		{ table = "loottable_resources_epic",               weight = 0.33 },
	}
}

LOOT_SOURCES.lootsource_lootcrate_common = {
	loot = {
		{
			list = {
				{ table = "loottable_bis",								weight = 0.75, 		cost = 0 },
				{ table = "loottable_bis_epic",							weight = 0.05, 		cost = 0, 		epic = true },
				{ table = nil,											weight = 0.20, 		cost = 0 }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_common",					weight = 0.65, 		cost = 0 },
				{ table = "loottable_lootcrate_common_epic",			weight = 0.15, 		cost = 0, 		epic = true },
				{ uuid = obj_outfitpackage_common,						weight = 0.10, 		cost = 0,		quantity = { 1 } }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_common",					weight = 0.25, 		cost = 0 },
				{ table = nil,											weight = 0.75, 		cost = 0 }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_common",					weight = 0.25, 		cost = 0 },
				{ table = nil,											weight = 0.75, 		cost = 0 }
			}
		}
	}
}

LOOT_SOURCES.lootsource_lootcrate_common_warehouse = {
	loot = {
		{
			list = {
				{ table = "loottable_bis",								weight = 0.80, 		cost = 0 },
				{ table = "loottable_bis_epic",							weight = 0.20, 		cost = 0, 		epic = true }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_common",					weight = 0.65, 		cost = 0 },
				{ table = "loottable_lootcrate_common_epic",			weight = 0.20, 		cost = 0, 		epic = true },
				{ uuid = obj_outfitpackage_common,						weight = 0.15, 		cost = 0,		quantity = { 1 } }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_common",					weight = 0.20, 		cost = 0 },
				{ table = nil,											weight = 0.80, 		cost = 0 }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_common",					weight = 0.2, 		cost = 0 },
				{ table = nil,											weight = 0.8, 		cost = 0 }
			}
		}
	}
}

LOOT_SOURCES.lootsource_lootcrate_common_startarea = {
	loot = {
		{
			list = {
				{ uuid = obj_consumable_component,		weight = 0.5 },
				{ uuid = obj_resource_circuitboard, 	weight = 1 },
				{ uuid = blk_scrapmetal,				weight = 1,		quantity = { 5, 7.5, 10 } },
			}
		},
		{
			list = {
				{ table = "loottable_random_start",	weight = 1 },
			}
		},
		{
			list = {
				{ table = "loottable_random_start",	weight = 1 },
				{ table = nil,						weight = 1 },
			}
		},
	}
}

LOOT_SOURCES.lootsource_lootcrate_common_underground = {
	loot = {
		{
			list = {
				{ table = "loottable_bis",								weight = 0.75, 		cost = 0 },
				{ table = "loottable_bis_epic",							weight = 0.05, 		cost = 0, 		epic = true },
				{ table = nil,											weight = 0.20, 		cost = 0 }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_common",					weight = 0.75, 		cost = 0 },
				{ table = "loottable_lootcrate_common_epic",			weight = 0.05, 		cost = 0, 		epic = true },
				{ uuid = obj_outfitpackage_common,						weight = 0.10, 		cost = 0,		quantity = { 1 } }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_common",					weight = 0.25, 		cost = 0 },
				{ uuid = obj_resource_wonkstonks,						weight = 0.25,		quantity = { 1, 3, 5 } },
				{ table = nil,											weight = 0.5, 		cost = 0 }
			}
		},
		{
			list = {
				{ table = "loottable_lootcrate_common",					weight = 0.25, 		cost = 0 },
				{ table = nil,											weight = 0.75, 		cost = 0 }
			}
		}
	}
}
