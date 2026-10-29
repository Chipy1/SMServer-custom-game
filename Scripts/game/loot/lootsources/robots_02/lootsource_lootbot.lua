
-- NOTE: This used to drop 10 slots, but was test, so didn't replicate behavior
LOOT_SOURCES.lootsource_lootbot_raid_default = {
	loot = {
		{
			list = {
				{ uuid = obj_plantables_broccoli, 		weight = 1,		quantity = 10 },
				{ uuid = obj_plantables_pineapple, 		weight = 1,		quantity = 10 },
			}
		}
	}
}

-- NOTE: This used to drop 10 slots, but was test, so didn't replicate behavior
LOOT_SOURCES.lootsource_lootbot_raid_outfit = {
	loot = {
		{
			list = {
				{ uuid = obj_outfitpackage_epic, 		weight = 50 ,	quantity = 1 },
				{ uuid = obj_outfitpackage_rare, 		weight = 30,	quantity = 2 },
				{ uuid = obj_outfitpackage_common, 		weight = 10,	quantity = 3 },
			}
		},
	}
}

LOOT_SOURCES.lootsource_lootbot_hit = {
	loot = {
		{
			list = {
				{ uuid = obj_consumable_component,		weight = 25,	quantity = 1 },
				{ uuid = obj_consumable_fertilizer,		weight = 25,	quantity = { 2, 3.5, 5 } },
				{ uuid = obj_decor_cone,				weight = 25 },
				{ uuid = obj_decor_boot,				weight = 25 },

				{ uuid = obj_plantables_carrot, 		weight = 15,	quantity = 1 },
				{ uuid = obj_plantables_redbeet, 		weight = 15,	quantity = 1 },
				{ uuid = obj_plantables_tomato, 		weight = 15,	quantity = 1 },
				{ uuid = obj_plantables_banana, 		weight = 10,	quantity = 1 },
				{ uuid = obj_plantables_blueberry, 		weight = 10,	quantity = 1 },
				{ uuid = obj_plantables_orange, 		weight = 10,	quantity = 1 },
				{ uuid = obj_plantables_potato, 		weight = 20,	quantity = { 3, 5, 7 } },
				{ uuid = obj_consumable_gas,			weight = 40,	quantity = { 2, 3, 4 } },
				{ uuid = obj_consumable_battery,		weight = 40,	quantity = { 1, 2, 3 } },
				{ uuid = obj_consumable_glowstick,		weight = 20,	quantity = 1 },
			}
		}
	}
}
