
LOOT_TABLES.loottable_ruinchest = {
	list = {
		{ uuid = blk_scrapwood, 				weight = 1,			quantity = 12 },
		{ uuid = blk_sand, 						weight = 1,			quantity = 12 },
		{ uuid = blk_wood1, 					weight = 1,			quantity = 12 },
		{ uuid = blk_glass, 					weight = 1,			quantity = 6 },

		{ uuid = obj_consumable_gas, 			weight = 1,			quantity = { 2, 4, 8 } },
		{ uuid = obj_consumable_water, 			weight = 1,			quantity = { 2, 4, 8 } },
		{ uuid = obj_consumable_chemical, 		weight = 1,			quantity = { 2, 4, 8 } },
		{ uuid = obj_resource_crudeoil,   		weight = 1, 		quantity = { 2, 4, 8 } },

		{ uuid = obj_consumable_fertilizer, 	weight = 1,			quantity = { 1, 2, 3 } },
		{ uuid = obj_consumable_soilbag, 		weight = 1,			quantity = { 1, 2, 3 } },
		{ uuid = obj_consumable_glue, 			weight = 1,			quantity = { 1, 2, 3 } },
		{ uuid = obj_consumable_inkammo, 		weight = 1,			quantity = { 5, 10, 15 } },
		{ uuid = obj_consumable_glowstick, 		weight = 1,			quantity = { 2, 4, 5 } },
		{ uuid = obj_consumable_tea, 			weight = 3,			quantity = { 1, 1, 2 } },

		{ uuid = obj_resource_beewax,     		weight = 1, 		quantity = { 1, 2, 4 } },
		{ uuid = obj_resource_cotton,     		weight = 1.25, 		quantity = { 2, 3, 4 } },
		{ uuid = obj_resource_glowpoop,   		weight = 1, 		quantity = { 1, 4 } },
		{ uuid = obj_consumable_battery, 		weight = 1,			quantity = { 1, 1, 2 } },
		{ uuid = obj_consumable_sunshake, 		weight = 0.5,		quantity = 1 },

		{ uuid = obj_consumable_component,		weight = 1,			quantity = { 1 } },
		{ uuid = obj_resource_circuitboard,		weight = 1,			quantity = { 1, 1, 2 } },
		{ uuid = obj_plantables_potato,			weight = 1,			quantity = { 5, 10 } },
		{ uuid = blk_scrapmetal,				weight = 1,			quantity = { 10, 20 } },
		{ uuid = blk_metal1,					weight = 1,			quantity = { 5, 15 } },
	},
}

LOOT_SOURCES.lootsource_ruinchest = {
	loot = {
		{
			list = {
				{ table = "loottable_ruinchest",	weight = 1 },
			}
		},
	}
}
LOOT_SOURCES.lootsource_ruinchest_cycling = {
	loot = {
		{
			list = {
				{ table = "loottable_ruinchest",	weight = 1 },
			}
		},
	}
}

--1 = 49.9796%
--2 = 34.1973%
--3 = 13.5404%
--4 = 2.2827%
LOOT_SOURCES.lootsource_ruinchest_startarea = {
	loot = {
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
		{
			list = {
				{ table = "loottable_random_start",	weight = 1 },
				{ table = nil,						weight = 1 },
			}
		},
		{
			list = {
				{ table = "loottable_random_start",	weight = 1 },
				{ table = nil,						weight = 1 },
			}
		}
	}
}
