dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

MiningManager = class( nil )

--Overworld: Clay, TBD, TBD, TBD, TBD, TBD, TBD, TBD
--UndergroundMininghub: Clay, Rock1, Rock2, Scrap1, nondestructable, nondestructable, nondestructable, Bedrock
--UndergroundOnboarding: Clay, Rock1, Rock2, Rock3, Rich, T1, T3, Bedrock
--UndergroundDrill1: Clay, Rock1, Rock2, Rock3, Rich, T1, T3, Bedrock
--UndergroundScrapyard: Clay, TBD, TBD, TBD, TBD, Scrap1, Scrap2, Bedrock
--UndergroundDrill2: Clay, Rock1, Rock2, Rock3, Rich, T4, T3, Bedrock
--Controlstation: Clay, Rock1, Rock2, Rock3, nondestructable, nondestructable, nondestructable, Bedrock

local M0 = sm.world.voxelFilter.material0
local M1 = sm.world.voxelFilter.material1
local M2 = sm.world.voxelFilter.material2
local M3 = sm.world.voxelFilter.material3
local M4 = sm.world.voxelFilter.material4
local M5 = sm.world.voxelFilter.material5
local M6 = sm.world.voxelFilter.material6
local M7 = sm.world.voxelFilter.material7

local MaterialIndexToMaterialFlag = { M0, M1, M2, M3, M4, M5, M6, M7 }

local WorldDrillLevelToVoxelMaterialMask = {
	["Overworld"] = {
		[1] = bit.bor( M0, M1, M2, M3, M4, M5, M6 ),
		[2] = bit.bor( M0, M1, M2, M3, M4, M5, M6 ),
		[3] = bit.bor( M0, M1, M2, M3, M4, M5, M6 ),
	},
	["UndergroundMininghub"] = {
		[1] = bit.bor( M0, M1, M2, M3 ),
		[2] = bit.bor( M0, M1, M2, M3 ),
		[3] = bit.bor( M0, M1, M2, M3 ),
	},
	["Controlstation"] = {
		[1] = bit.bor( M0, M1, M2, M3 ),
		[2] = bit.bor( M0, M1, M2, M3 ),
		[3] = bit.bor( M0, M1, M2, M3 ),
	},
	["UndergroundOnboarding"] = {
		[1] = bit.bor( M0, M1, M2, M3, M4, M5 ),
		[2] = bit.bor( M0, M1, M2, M3, M4, M5 ),
		[3] = bit.bor( M0, M1, M2, M3, M4, M5 ),
	},
	["UndergroundDrill1"] = {
		[1] = bit.bor( M0, M1, M2, M3, M4, M5 ),
		[2] = bit.bor( M0, M1, M2, M3, M4, M5 ),
		[3] = bit.bor( M0, M1, M2, M3, M4, M5 ),
	},
	["UndergroundScrapyard"] = {
		[1] = bit.bor( M0, M1, M2, M3 ),
		[2] = bit.bor( M0, M1, M2, M3 ),
		[3] = bit.bor( M0, M1, M2, M3 ),
	},
	["UndergroundDrill2"] = {
		[1] = bit.bor( M0, M1, M2, M3, M4, M5 ),
		[2] = bit.bor( M0, M1, M2, M3, M4, M5 ),
		[3] = bit.bor( M0, M1, M2, M3, M4, M5 ),
	},
}

 local WorldMeleeToVoxelMaterialMask = {
	["Overworld"] = {
		["Player"] = bit.bor( M0, M1, M2, M3, M4, M5, M6 )
	},
	["UndergroundMininghub"] = {
		["Player"] = bit.bor( M0, M1, M2, M3 )
	},
	["Controlstation"] = {
		["Player"] = bit.bor( M0, M1, M2, M3 )
	},
	["UndergroundOnboarding"] = {
		["Player"] = bit.bor( M0, M1, M2, M3 )
	},
	["UndergroundDrill1"] = {
		["Player"] = bit.bor( M0, M1, M2, M3 )
	},
	["UndergroundScrapyard"] = {
		["Player"] = bit.bor( M0, M1, M2, M3 )
	},
	["UndergroundDrill2"] = {
		["Player"] = bit.bor( M0, M1, M2, M3 )
	},
}

local WorldMeleeRemovedDensity = {
	["Overworld"] = {
		["Player"] = { 60, 60, 60, 30, 90, 60, 60, 0 },
	},
	["UndergroundMininghub"] = {
		["Player"] = { 60, 90, 60, 30, 0, 0, 0, 0 },
	},
	["Controlstation"] = {
		["Player"] = { 60, 90, 60, 30, 0, 0, 0, 0 },
	},
	["UndergroundOnboarding"] = {
		["Player"] = { 60, 90, 60, 30, 0, 0, 0, 0 },
	},
	["UndergroundDrill1"] = {
		["Player"] = { 60, 90, 60, 30, 0, 0, 0, 0 },
	},
	["UndergroundScrapyard"] = {
		["Player"] = { 60, 90, 60, 30, 0, 0, 0, 0 },
	},
	["UndergroundDrill2"] = {
		["Player"] = { 60, 90, 60, 30, 0, 0, 0, 0 },
	},
}

local WorldDrillLevelToRemovedDensity = {
	["Overworld"] = {
		[1] = { 40, 40, 40, 20, 40, 40, 40, 0 },
		[2] = { 60, 60, 60, 30, 60, 60, 60, 0 },
		[3] = { 90, 90, 90, 45, 90, 90, 90, 0 },
	},
	["UndergroundMininghub"] = {
		[1] = { 40, 60, 40, 40, 0, 0, 0, 0 },
		[2] = { 60, 90, 60, 60, 0, 0, 0, 0 },
		[3] = { 90, 135, 90, 90, 0, 0, 0, 0 },
	},
	["Controlstation"] = {
		[1] = { 40, 60, 40, 40, 0, 0, 0, 0 },
		[2] = { 60, 90, 60, 60, 0, 0, 0, 0 },
		[3] = { 90, 135, 90, 90, 0, 0, 0, 0 },
	},
	["UndergroundOnboarding"] = {
		[1] = { 40, 60, 40, 20, 40, 40, 0, 0 },
		[2] = { 60, 90, 60, 30, 60, 60, 0, 0 },
		[3] = { 90, 135, 90, 45, 90, 90, 0, 0 },
	},
	["UndergroundDrill1"] = {
		[1] = { 40, 60, 40, 20, 40, 40, 0, 0 },
		[2] = { 60, 90, 60, 30, 60, 60, 0, 0 },
		[3] = { 90, 135, 90, 45, 90, 90, 0, 0 },
	},
	["UndergroundScrapyard"] = {
		[1] = { 40, 40, 40, 0, 0, 0, 0, 0 },
		[2] = { 60, 60, 60, 0, 0, 0, 0, 0 },
		[3] = { 90, 90, 90, 0, 0, 0, 0, 0 },
	},
	["UndergroundDrill2"] = {
		[1] = { 40, 60, 40, 20, 40, 60, 0, 0 },
		[2] = { 60, 90, 60, 30, 60, 90, 0, 0 },
		[3] = { 90, 135, 90, 45, 90, 135, 0, 0 },
	},
}

local WorldMaterialIndexToItemUuid = {
	["Overworld"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = nil,
		[6] = nil,
		[7] = nil,
		[8] = nil,
	},
	["UndergroundMininghub"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = nil,
		[6] = nil,
		[7] = nil,
		[8] = nil,
	},
	["Controlstation"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = nil,
		[6] = nil,
		[7] = nil,
		[8] = nil,
	},
	["UndergroundOnboarding"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = ITEMS.obj_voxelmaterial_rich,
		[6] = ITEMS.obj_voxelmaterial_t1,
		[7] = ITEMS.obj_voxelmaterial_t3,
		[8] = nil,
	},
	["UndergroundDrill1"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = ITEMS.obj_voxelmaterial_rich,
		[6] = ITEMS.obj_voxelmaterial_t1,
		[7] = ITEMS.obj_voxelmaterial_t3,
		[8] = nil,
	},
	["UndergroundScrapyard"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = nil,
		[6] = nil,
		[7] = nil,
		[8] = nil,
	},
	["UndergroundDrill2"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = ITEMS.obj_voxelmaterial_rich,
		[6] = ITEMS.obj_voxelmaterial_t4,
		[7] = ITEMS.obj_voxelmaterial_t3,
		[8] = nil,
	},
}

local WorldMaterialIndexToChunkItemUuid = {
	["Overworld"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = nil,
		[6] = nil,
		[7] = nil,
		[8] = nil,
	},
	["UndergroundMininghub"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = nil,
		[6] = nil,
		[7] = nil,
		[8] = nil,
	},
	["Controlstation"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = nil,
		[6] = nil,
		[7] = nil,
		[8] = nil,
	},
	["UndergroundOnboarding"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = { ITEMS.obj_voxelmaterialchunk_rich1_small, ITEMS.obj_voxelmaterialchunk_rich1_medium, ITEMS.obj_voxelmaterialchunk_rich1_large },
		[6] = { ITEMS.obj_voxelmaterialchunk_t1_small, ITEMS.obj_voxelmaterialchunk_t1_medium, ITEMS.obj_voxelmaterialchunk_t1_large },
		[7] = { ITEMS.obj_voxelmaterialchunk_t3_small, ITEMS.obj_voxelmaterialchunk_t3_medium, ITEMS.obj_voxelmaterialchunk_t3_large },
		[8] = nil,
	},
	["UndergroundDrill1"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = { ITEMS.obj_voxelmaterialchunk_rich1_small, ITEMS.obj_voxelmaterialchunk_rich1_medium, ITEMS.obj_voxelmaterialchunk_rich1_large },
		[6] = { ITEMS.obj_voxelmaterialchunk_t1_small, ITEMS.obj_voxelmaterialchunk_t1_medium, ITEMS.obj_voxelmaterialchunk_t1_large },
		[7] = { ITEMS.obj_voxelmaterialchunk_t3_small, ITEMS.obj_voxelmaterialchunk_t3_medium, ITEMS.obj_voxelmaterialchunk_t3_large },
		[8] = nil,
	},
	["UndergroundScrapyard"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = nil,
		[6] = nil,
		[7] = nil,
		[8] = nil,
	},
	["UndergroundDrill2"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = { ITEMS.obj_voxelmaterialchunk_rich2_small, ITEMS.obj_voxelmaterialchunk_rich2_medium, ITEMS.obj_voxelmaterialchunk_rich2_large },
		[6] = { ITEMS.obj_voxelmaterialchunk_t4_small, ITEMS.obj_voxelmaterialchunk_t4_medium, ITEMS.obj_voxelmaterialchunk_t4_large },
		[7] = { ITEMS.obj_voxelmaterialchunk_t3_small, ITEMS.obj_voxelmaterialchunk_t3_medium, ITEMS.obj_voxelmaterialchunk_t3_large },
		[8] = nil,
	},
}

local function selectWeightedEntry( list )
	local totalWeight = 0
	for _, entry in ipairs( list ) do
		totalWeight = totalWeight + ( entry.weight or 1 )
	end
	local roll = math.random() * totalWeight
	for _, entry in ipairs( list ) do
		roll = roll - ( entry.weight or 1 )
		if roll <= 0 then
			return entry
		end
	end
	return list[#list]
end

local Rock2HarvestableSpawns = {
	{ hvs = hvs_farmables_golddeposit, 	weight = 3 },
	{ hvs = hvs_farmables_quartz, 		weight = 5 },
	{ hvs = hvs_farmables_mud, 			weight = 12 },
	{ hvs = nil, 						weight = 5 },
 }
 
-- NOTE: Stops on first hit.
local WorldMaterialIndexSpawnLists = {
	["Overworld"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = nil,
		[6] = nil,
		[7] = nil,
		[8] = nil,
	},
	["UndergroundMininghub"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = nil,
		[6] = nil,
		[7] = nil,
		[8] = nil,
	},
	["Controlstation"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = nil,
		[6] = nil,
		[7] = nil,
		[8] = nil,
	},
	["UndergroundOnboarding"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = nil,
		[6] = nil,
		[7] = nil,
		[8] = nil,
	},
	["UndergroundDrill1"] = {
		[1] = nil,
		[2] = nil,
		[3] = {
			{ parts = "lootsource_voxel_rock2_drill2", rule = { sizeX = 32, sizeY = 32, sizeZ = 32, seed = 521 } },
			{ harvestables = { { hvs = hvs_sparkstone, weight = 1 } }, rule = { sizeX = 2, sizeY = 2, sizeZ = 2, seed = 827, tunnelType = "TtVeinSparkstone", maxDist = 2.5 } },
			{ harvestables = Rock2HarvestableSpawns, rule = { sizeX = 8, sizeY = 8, sizeZ = 8, seed = 524 } },
		},
		[4] = nil,
		[5] = nil,
		[6] = nil,
		[7] = nil,
		[8] = nil
	},
	["UndergroundScrapyard"] = {
		[1] = nil,
		[2] = nil,
		[3] = nil,
		[4] = nil,
		[5] = nil,
		[6] = { { parts = "lootsource_voxel_scrap", useHvsContainer = true, rule = { sizeX = 2, sizeY = 2, sizeZ = 2, seed = 314 } } },
		[7] = { { parts = "lootsource_voxel_scrap", useHvsContainer = true, rule = { sizeX = 2, sizeY = 2, sizeZ = 2, seed = 314 } } },
		[8] = nil,
	},
	["UndergroundDrill2"] = {
		[1] = nil,
		[2] = nil,
		[3] = {
			{ parts = "lootsource_voxel_rock2_drill2", rule = { sizeX = 32, sizeY = 32, sizeZ = 32, seed = 521 } },
			{ harvestables = { { hvs = hvs_sparkstone, weight = 1 } }, rule = { sizeX = 2, sizeY = 2, sizeZ = 2, seed = 827, tunnelType = "TtVeinSparkstone", maxDist = 2.5 } },
			{ harvestables = Rock2HarvestableSpawns, rule = { sizeX = 8, sizeY = 8, sizeZ = 8, seed = 524 } },
		},
		[4] = nil,
		[5] = nil,
		[6] = nil,
		[7] = nil,
		[8] = nil
	},
}

local g_miningSpawnDefs = {}
local g_worldMiningConfigs = {}
do
	local nextSpawnId = 0
	for materialSetName, materialList in pairs( WorldMaterialIndexSpawnLists ) do
		local config = {}
		for materialIndex = 1, 8 do
			local spawnList = materialList[materialIndex]
			if spawnList then
				local rules = {}
				for _, spawn in ipairs( spawnList ) do
					nextSpawnId = nextSpawnId + 1
					g_miningSpawnDefs[nextSpawnId] = spawn
					local rule = spawn.rule or {}
					rules[#rules + 1] = {
						sizeX = rule.sizeX or 0,
						sizeY = rule.sizeY or 0,
						sizeZ = rule.sizeZ or 0,
						seed = rule.seed or 0,
						tunnelType = rule.tunnelType,
						maxDist = rule.maxDist or 0,
						spawnId = nextSpawnId,
					}
				end
				config[materialIndex] = rules
			end
		end
		g_worldMiningConfigs[materialSetName] = config
	end
end


local WorldMaterialIndexDrillEffects = {
-- 				ImpactEffect, 						SecondaryImpactEffect, 				CeilingEffect, 						VortexEffect
	["Overworld"] = {
		[1] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Mud_Crumble", 		"Plasmadrill - Vortex01" },--- Clay
		[2] = { "Plasmadrill - ImpactCarving01", 	nil,				 				nil,				 				nil },--Dirt
		[3] = { "Plasmadrill - ImpactCarving01", 	nil,				 				nil,				 				nil },--DirtGrass
		[4] = { "Plasmadrill - ImpactHard01", 		"Plasmadrill - ImpactHard_Sparks", 	"voxeldestruct - Rock3_Crumble", 	"Plasmadrill - Vortex02" },	-- Rock3
		[5] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Rock1_Crumble", 	"Plasmadrill - Vortex01" },	-- Rock1 / Sand B 
		[6] = { "Plasmadrill - ImpactVoxel", 		nil,				 				nil,				 				nil },--Ice
		[7] = { "Plasmadrill - ImpactVoxel", 		nil,				 				nil,				 				nil },--Scrap
		[8] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,				 				nil },--Bedrock
	},
	["UndergroundMininghub"] = {
		[1] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Mud_Crumble", 		"Plasmadrill - Vortex01" },--- Clay
		[2] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Rock1_Crumble", 	"Plasmadrill - Vortex01" },	-- Rock1 / Sand B 
		[3] = { "Plasmadrill - ImpactVoxel", 		"Plasmadrill - ImpactCarving02",	"voxeldestruct - Rock2_Crumble", 	"Plasmadrill - Vortex01" },	-- Rock2
		[4] = { "Plasmadrill - ImpactVoxel", 		nil,								nil, 								nil }, -- Trash
		[5] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,				 				nil }, -- Bedrock Mininghub rock1
		[6] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,				 				nil }, -- Bedrock Mininghub rock2
		[7] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,				 				nil }, -- Bedrock Mininghub rock3
		[8] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,				 				nil }, -- Bedrock
	},
	["Controlstation"] = {
		[1] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Mud_Crumble", 		"Plasmadrill - Vortex01" },	-- Clay
		[2] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Rock1_Crumble", 	"Plasmadrill - Vortex01" },	-- Rock1
		[3] = { "Plasmadrill - ImpactVoxel", 		"Plasmadrill - ImpactCarving02",	"voxeldestruct - Rock2_Crumble", 	"Plasmadrill - Vortex01" },	-- Rock2
		[4] = { "Plasmadrill - ImpactHard01", 		"Plasmadrill - ImpactHard_Sparks", "voxeldestruct - Rock3_Crumble", 	"Plasmadrill - Vortex02" },	-- Rock3
		[5] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,				 				nil }, -- Bedrock Mininghub rock1
		[6] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,				 				nil }, -- Bedrock Mininghub rock2
		[7] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,				 				nil }, -- Bedrock Mininghub rock3
		[8] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,				 				nil }, -- Bedrock
	},
	["UndergroundOnboarding"] = {
		[1] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Mud_Crumble", 		"Plasmadrill - Vortex01" },	-- Clay
		[2] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Rock1_Crumble", 	"Plasmadrill - Vortex01" },	-- Rock1
		[3] = { "Plasmadrill - ImpactVoxel", 		"Plasmadrill - ImpactCarving02",	"voxeldestruct - Rock2_Crumble", 	"Plasmadrill - Vortex01" },	-- Rock2
		[4] = { "Plasmadrill - ImpactHard01", 		"Plasmadrill - ImpactHard_Sparks",	"voxeldestruct - Rock3_Crumble", 	"Plasmadrill - Vortex02" },	-- Rock3
		[5] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Orerich_Crumble", 	"Plasmadrill - Vortex01" },	-- Rich
		[6] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - t1_Crumble", 		"Plasmadrill - Vortex01" },	-- T1
		[7] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,								nil },					-- T3
		[8] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,								nil },					-- Bedrock
	},
	["UndergroundDrill1"] = {
		[1] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Mud_Crumble", 		"Plasmadrill - Vortex01" },	-- Clay
		[2] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Rock1_Crumble", 	"Plasmadrill - Vortex01" },	-- Rock1
		[3] = { "Plasmadrill - ImpactVoxel", 		"Plasmadrill - ImpactCarving02",	"voxeldestruct - Rock2_Crumble", 	"Plasmadrill - Vortex01" },	-- Rock2
		[4] = { "Plasmadrill - ImpactHard01", 		"Plasmadrill - ImpactHard_Sparks",	"voxeldestruct - Rock3_Crumble", 	"Plasmadrill - Vortex02" },	-- Rock3
		[5] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Orerich_Crumble", 	"Plasmadrill - Vortex01" },	-- Rich
		[6] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - t1_Crumble", 		"Plasmadrill - Vortex01" },	-- T1
		[7] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,								nil },						-- T3
		[8] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,								nil },						-- Bedrock
	},
	["UndergroundScrapyard"] = {
		[1] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Mud_Crumble", 		"Plasmadrill - Vortex01" },	-- Clay
		[2] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Rock1_Crumble", 	"Plasmadrill - Vortex01" },	-- Rock2
		[3] = { "Plasmadrill - ImpactVoxel", 		nil,								nil, 								nil },	-- Trash
		[4] = { "Plasmadrill - ImpactBedrock", 		nil,								nil, 								nil },	-- Trash Bedrock1
		[5] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil, 								nil },	-- Trash Bedrock2
		[6] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil, 								nil },	-- Bedrock Mininghub rock1
		[7] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,								nil },					-- Bedrock Mininghub rock2		
		[8] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,								nil },					-- Bedrock
	},
	["UndergroundDrill2"] = {
		[1] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Mud_Crumble", 		"Plasmadrill - Vortex01" },	-- Clay
		[2] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Rock1_Crumble", 	"Plasmadrill - Vortex01" },	-- Rock1 C
		[3] = { "Plasmadrill - ImpactVoxel", 		"Plasmadrill - ImpactCarving02",	"voxeldestruct - Rock2_Crumble", 	"Plasmadrill - Vortex01" },	-- Rock2
		[4] = { "Plasmadrill - ImpactHard01", 		"Plasmadrill - ImpactHard_Sparks", 	"voxeldestruct - Rock3_Crumble", 	"Plasmadrill - Vortex02" },	-- Rock3
		[5] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - Orerich_Crumble", 	"Plasmadrill - Vortex01" },	-- Rich
		[6] = { "Plasmadrill - ImpactCarving01", 	nil,				 				"voxeldestruct - t4_Crumble", 		"Plasmadrill - Vortex01" },	-- T4
		[7] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,								nil },						-- T3
		[8] = { "Plasmadrill - ImpactBedrock", 		nil,				 				nil,								nil },						-- Bedrock
	},
}

function MiningManager.server_onCreate( self )
	g_mineralMiningManager = self
	self.sv = {}
	self.sv.storage = sm.storage.load( STORAGE_CHANNEL_MINERALMINING_MANAGER ) or {}
end

function MiningManager.client_onCreate( self )
	g_mineralMiningManagerClient = self
end

function MiningManager.server_onUnload( self )
	if self.sv.storageDirty then
		sm.storage.save( STORAGE_CHANNEL_MINERALMINING_MANAGER, self.sv.storage )
		self.sv.storageDirty = false
	end
end

function MiningManager.server_onFixedUpdate( self )
	if self.sv.storageDirty then
		--print("Saving diamond grid")
		sm.storage.save( STORAGE_CHANNEL_MINERALMINING_MANAGER, self.sv.storage )
		self.sv.storageDirty = false
	end
end

function MiningManager.Sv_GetDrillParams( world, drillLevel, fraction )
	local voxelMaterialSetName = ( world.publicData and world.publicData.voxelMaterialSetName ) or "Overworld"
	assert( WorldDrillLevelToVoxelMaterialMask[voxelMaterialSetName], "Voxel material set name '"..tostring( voxelMaterialSetName ).."' not found in WorldDrillLevelToVoxelMaterialMask" )
	local materialMask = WorldDrillLevelToVoxelMaterialMask[voxelMaterialSetName][drillLevel]
	local maxDensities = {}
	for i, m in ipairs( MaterialIndexToMaterialFlag ) do
		if bit.band( materialMask, m ) ~= 0 then
			maxDensities[i] = math.ceil( WorldDrillLevelToRemovedDensity[voxelMaterialSetName][drillLevel][i] * fraction )
		end
	end
	return {
		maxDensities = maxDensities,
		voxelMaterialMask = materialMask,
	}
end

function MiningManager.Sv_GetMeleeParams( world, attacker )
	local voxelMaterialSetName = ( world.publicData and world.publicData.voxelMaterialSetName ) or "Overworld"
	assert( WorldMeleeToVoxelMaterialMask[voxelMaterialSetName], "Voxel material set name '"..tostring( voxelMaterialSetName ).."' not found in WorldMeleeToVoxelMaterialMask" )
	local materialMask = WorldMeleeToVoxelMaterialMask[voxelMaterialSetName][attacker]
	local maxDensities = {}
	for i, m in ipairs( MaterialIndexToMaterialFlag ) do
		if bit.band( materialMask, m ) ~= 0 then
			maxDensities[i] = math.ceil( WorldMeleeRemovedDensity[voxelMaterialSetName][attacker][i] )
		end
	end
	return {
		maxDensities = maxDensities,
		voxelMaterialMask = materialMask,
	}
end

---@return Uuid?
function MiningManager.Sv_GetVoxelMaterialItemUuid( world, materialIndex )
	local voxelMaterialSetName = ( world.publicData and world.publicData.voxelMaterialSetName ) or "Overworld"
	return WorldMaterialIndexToItemUuid[voxelMaterialSetName][materialIndex]
end

---@return Uuid?
function MiningManager.Cl_GetVoxelMaterialItemUuid( world, materialIndex )
	local voxelMaterialSetName = ( world.clientPublicData and world.clientPublicData.voxelMaterialSetName ) or "Overworld"
	return WorldMaterialIndexToItemUuid[voxelMaterialSetName][materialIndex]
end

---@return Uuid?
function MiningManager.Sv_GetVoxelMaterialChunkItemUuid( world, materialIndex, density )
	local voxelMaterialSetName = ( world.publicData and world.publicData.voxelMaterialSetName ) or "Overworld"
	local list = WorldMaterialIndexToChunkItemUuid[voxelMaterialSetName][materialIndex]
	if list == nil then
		return nil
	end
	local index = 1
	if density > 1200 and #list >= 3 then
		index = 3
	elseif density > 400 and #list >= 2 then
		index = 2
	end
	return list[index]
end

---@return string?, string?
function MiningManager.Cl_GetVoxelDrillImpactEffect( world, materialIndex )
	local voxelMaterialSetName = ( world.clientPublicData and world.clientPublicData.voxelMaterialSetName ) or "Overworld"
	local effects = WorldMaterialIndexDrillEffects[voxelMaterialSetName] and WorldMaterialIndexDrillEffects[voxelMaterialSetName][materialIndex]
	return effects and effects[1], effects and effects[2]
end

---@return string?
function MiningManager.Cl_GetVoxelDrillCeilingEffect( world, materialIndex )
	local voxelMaterialSetName = ( world.clientPublicData and world.clientPublicData.voxelMaterialSetName ) or "Overworld"
	local effects = WorldMaterialIndexDrillEffects[voxelMaterialSetName] and WorldMaterialIndexDrillEffects[voxelMaterialSetName][materialIndex]
	return effects and effects[3]
end

---@return string?
function MiningManager.Cl_GetVoxelDrillVortexEffect( world, materialIndex )
	local voxelMaterialSetName = ( world.clientPublicData and world.clientPublicData.voxelMaterialSetName ) or "Overworld"
	local effects = WorldMaterialIndexDrillEffects[voxelMaterialSetName] and WorldMaterialIndexDrillEffects[voxelMaterialSetName][materialIndex]
	return effects and effects[4]
end

function MiningManager.Sv_SetupWorldMiningConfig( world )
	local voxelMaterialSetName = ( world.publicData and world.publicData.voxelMaterialSetName ) or "Overworld"
	local config = g_worldMiningConfigs[voxelMaterialSetName]
	if config then
		world:setMiningConfig( config )
	end
end

function MiningManager.Sv_OnMining( world, spawns )
	for _, entry in ipairs( spawns ) do
		local spawn = g_miningSpawnDefs[entry.spawnId]
		if spawn then
			local spawnPos = entry.position
			if spawn.harvestables then
				local spawnHvs = selectWeightedEntry( spawn.harvestables )
				if spawnHvs.hvs then
					local rot = sm.quat.angleAxis( math.random() * math.pi * 2, sm.vec3.new( 0, 0, 1 ) ) * sm.quat.rotX90()
					local lootHarvestable = sm.harvestable.createHarvestable( spawnHvs.hvs, spawnPos, rot )
					lootHarvestable:setParams( spawnHvs.params )
				end
			elseif spawn.parts then
				local lootList = SelectLoot( spawn.parts )
				if #lootList > 1 then
					sm.log.error( "More than one loot item: '"..spawn.parts.."'" )
				end
				if spawn.useHvsContainer then
					for _, loot in ipairs( lootList ) do
						local rot = sm.quat.angleAxis( math.random() * math.pi * 2, sm.vec3.new( 0, 0, 1 ) ) * sm.quat.rotX90()
						local lootHarvestable = sm.harvestable.createHarvestable( hvs_voxelspawncontainer, spawnPos, rot )
						lootHarvestable:setParams( { uuid = loot.uuid, quantity = loot.quantity } )
					end
				else
					local loot = lootList[1]
					if loot and loot.uuid then
						local spawnRot = sm.quat.angleAxis( math.random() * math.pi * 2, sm.vec3.new( 0, 0, 1 ) ) * sm.quat.angleAxis( math.random() * math.pi, sm.vec3.new( 1, 0, 0 ) )
						local size = sm.item.getShapeSize( loot.uuid )
						spawnPos = spawnPos - spawnRot * size * 0.125
						local spawnedPart = sm.shape.createPart( loot.uuid, spawnPos, spawnRot, false, false )
						if loot.quantity > 1 then
							if spawnedPart:getIsStackable() then
								spawnedPart.stackedAmount = loot.quantity
							else
								sm.log.error( "Loot '"..( sm.shape.getDebugName and sm.shape.getDebugName( loot.uuid ) or tostring( loot.uuid ) ).."' is not stackable" )
							end
						end
					end
				end
			end
		end
	end
end
