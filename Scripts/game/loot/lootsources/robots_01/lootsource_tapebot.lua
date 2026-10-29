
LOOT_SOURCES.lootsource_tapebot = {
	loot = {
		{
			list = {
				{ uuid = obj_consumable_component,		weight = 0.25 },
				{ uuid = nil,		                    weight = 0.75 },
			}
		}
	}
}
LOOT_SOURCES.lootsource_tapebot_growlab = {
	loot = {
		{
			list = {
				{ uuid = obj_consumable_component,		weight = 0.20 },
				{ uuid = nil,		                    weight = 0.80 },
			}
		}
	}
}
LOOT_SOURCES.lootsource_tapebot_farmraid = {
	loot = {
		{
			list = {
				{ uuid = obj_consumable_component,		weight = 0.20 },
				{ uuid = nil,		                    weight = 0.80 },
			}
		}
	}
}

LOOT_SOURCES.lootsource_tapebot_schematic = {
	loot = {
		{
			count = 1,
			list = {
				{ uuid = ITEMS.obj_consumable_component, weight = 1, quantity = { 1 } },
				{ uuid = nil, weight = 1 },
			}
		},
		{
			count = 1,
			list = {
				{ uuid = ITEMS.obj_loot_schematic, weight = 1, quantity = { 1 } },
				{ uuid = nil, weight = 3 },
			}
		}
	}
}
LOOT_SOURCES.lootsource_tapebot_underground = {
	loot = {
		{
			list = {
				{ uuid = obj_consumable_component,		weight = 0.4 },
				{ uuid = nil,		                    weight = 0.6 },
			}
		}
	}
}
LOOT_SOURCES.lootsource_tapebot_yellow = {
	loot = {
		{
			count = 1,
			list = {
				{ uuid = ITEMS.obj_consumable_component, weight = 1, quantity = { 1 } },
				{ uuid = nil, weight = 1 },
			}
		},
		{
			count = 3,
			list = {
				{ uuid = ITEMS.obj_consumable_inkammo, weight = 1, quantity = { 5, 10, 15 } },
				{ uuid = nil, weight = 1 },
			}
		},
		{
			count = 1,
			list = {
				{ uuid = ITEMS.tool_paint, weight = 0.05, quantity = { 1 } },
				{ uuid = nil, weight = 1.0 },
			}
		}
	}
}
LOOT_SOURCES.lootsource_tapebot_yellow_farmraid = {
	loot = {
		{
			count = 1,
			list = {
				{ uuid = ITEMS.obj_consumable_component, weight = 1, quantity = { 1 } },
				{ uuid = nil, weight = 2 },
			}
		},
		{
			count = 1,
			list = {
				{ uuid = ITEMS.obj_consumable_inkammo, weight = 1, quantity = { 5, 10, 15 } },
				{ uuid = nil, weight = 2 },
			}
		},
		{
			count = 1,
			list = {
				{ uuid = ITEMS.tool_paint, weight = 0.025, quantity = { 1 } },
				{ uuid = nil, weight = 1.0 },
			}
		}
	}
}