dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/terrain_util2.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/tile_database.lua" )
dofile( "$SURVIVAL_DATA/Scripts/kinematic_util.lua" )
dofile( "$GAME_DATA/Scripts/terrain/terrain_area_util.lua" )
dofile( "$GAME_DATA/Scripts/terrain/terrain_prepare_cell_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/underground/chunk_raster.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/underground/tunnel_generation.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/underground/caves_and_pockets.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/underground/carve_tunnels.lua" )

--TODO: Raster grid from TUNNEL_BLOCKER

--TODO: Tile groups for caves

local LOCATION_STORAGE_VERSION = 2
local QUESTMARKER_STORAGE_VERSION = 1

----------------------------------------------------------------------------------------------------
-- Per-depth location and quest marker data (generated from tile nodes)
----------------------------------------------------------------------------------------------------

-- Locations per depth: { name, uuid, pos }
-- Place generated lines from the codegen block here, keyed by depth.
local DEPTH_NODE_LOCATIONS = {
	[1] = { -- Mining Hub
		{ name = "mininghub", uuid = sm.uuid.new("4ecf7c01-1254-44f4-8ea4-ee50520fafe9"), pos = sm.vec3.new( 656.74591064453, 518.47381591797, 62.988464355469 ) },
	},
	[2] = { -- Onboarding
	},
	[3] = { -- Drill 1
	},
	[4] = { -- Station 1
	},
	[5] = { -- Scrapyard
	},
	[6] = { -- Drill 2
	},
	[7] = { -- Station 2
	},
	[8] = { -- Final Boss Lobby
	},
}

-- Quest markers per depth: { name, uuid, pos, isSideQuest }
-- Place generated lines from the codegen block here, keyed by depth.
local DEPTH_QUEST_MARKERS = {
	[1] = { -- Mining Hub
		{ name = "quest_activate_mininghub.axobot", uuid = sm.uuid.new("4ecf7c01-1254-44f4-8ea4-ee50520fafe9"), pos = sm.vec3.new( 694.00213623047, 504.92224121094, 60.981819152832 ), isSideQuest = false },
		{ name = "quest_activate_mininghub.pylon", uuid = sm.uuid.new("4ecf7c01-1254-44f4-8ea4-ee50520fafe9"), pos = sm.vec3.new( 655.51239013672, 518.46997070312, 59.945594787598 ), isSideQuest = false },
		{ name = "quest_activate_mininghub.station_caster", uuid = sm.uuid.new("4ecf7c01-1254-44f4-8ea4-ee50520fafe9"), pos = sm.vec3.new( 453.45022583008, 424.79010009766, 37.984477996826 ), isSideQuest = false },
		{ name = "quest_activate_mininghub.station_dispenser", uuid = sm.uuid.new("4ecf7c01-1254-44f4-8ea4-ee50520fafe9"), pos = sm.vec3.new( 557.76965332031, 484.24572753906, 63.208450317383 ), isSideQuest = false },
		{ name = "quest_activate_mininghub.station_powerrails", uuid = sm.uuid.new("4ecf7c01-1254-44f4-8ea4-ee50520fafe9"), pos = sm.vec3.new( 505.25, 385.74996948242, 39.250007629395 ), isSideQuest = false },
		{ name = "quest_activate_mininghub.station_smelter", uuid = sm.uuid.new("4ecf7c01-1254-44f4-8ea4-ee50520fafe9"), pos = sm.vec3.new( 684.69689941406, 422.84887695312, 63.471084594727 ), isSideQuest = false },
		{ name = "quest_activate_mininghub.vault_door", uuid = sm.uuid.new("4ecf7c01-1254-44f4-8ea4-ee50520fafe9"), pos = sm.vec3.new( 686.13012695312, 518.58569335938, 60.329624176025 ), isSideQuest = false },
		{ name = "quest_activate_mininghub.vault", uuid = sm.uuid.new("4ecf7c01-1254-44f4-8ea4-ee50520fafe9"), pos = sm.vec3.new( 724.94049072266, 518.45831298828, 59.454074859619 ), isSideQuest = false },
	},
	[2] = { -- Onboarding
	},
	[3] = { -- Drill 1
	},
	[4] = { -- Station 1
	},
	[5] = { -- Scrapyard
	},
	[6] = { -- Drill 2
	},
	[7] = { -- Station 2
	},
	[8] = { -- Final Boss Lobby
	},
}

----------------------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------------------

local BedrockPadding = 0

function PathToSize( path, silent )
	local start, _, x, y, z = string.find( path, "_(%d+)x(%d+)x(%d+)[^%a]" )
	if start then
		return sm.vec3.new( tonumber( x ), tonumber( y ), tonumber( z ) )
	end
	if not silent then
		sm.log.error( "PathToSize: Invalid path format, no size found in path:", path )
	end
	return nil
end

function PathToPlacementRules( path )
	local lo, _ = string.find( path, "_lo[^%a]" )
	local c, _ = string.find( path, "_c[^%a]" )
	local hi, _ = string.find( path, "_hi[^%a]" )
	if not lo and not c and not hi then
		return true, true, true
	end
	return lo ~= nil, c ~= nil, hi ~= nil
end

local CoreTilesElevatorOnboarding = {
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Onboarding/onboarding_elevator_12x12x8.tile" }
}

local CoreTilesElevatorDrill1 = {
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/drill1_elevator_12x8x8.tile" }
}

local CoreTilesElevatorDrill2 = {
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/drill2_elevator_12x8x8.tile" }
}

local CaveTilesMainOnboarding = {
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Onboarding/onboarding_cave_first_12x8x8.tile", name = "First" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Onboarding/onboarding_midblocker_8x8x8.tile", name = "Midblocker" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Onboarding/onboarding_cave_left_8x8x8.tile", name = "Left" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Onboarding/onboarding_cave_join_12x8x8.tile", name = "Join" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Onboarding/onboarding_cave_final_12x16x8.tile", name = "Final" },
}

-- DRILL [1] CAVES
local CaveTilesDrill1 = {
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Cave/drill1_cave_3a_bot_8x8x3.tile", name = "Bot3" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Cave/drill1_cave_5a_top_8x8x5.tile", name = "Top5" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Cave/drill1_cave_4b_bot_8x8x4.tile", name = "Bot4" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Cave/drill1_cave_4a_top_8x8x4.tile", name = "Top4" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Cave/drill1_cave_8a_8x8x8.tile", name = "8" },
}

-- DRILL [2] CAVES
local CaveTilesDrill2 = {
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/Cave/drill2_cave_5b_bot_8x8x5.tile", name = "Bot5" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/Cave/drill2_cave_3b_top_8x8x3.tile", name = "Top3" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/Cave/drill2_cave_4b_bot_8x8x4.tile", name = "Bot4" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/Cave/drill2_cave_4a_top_8x8x4.tile", name = "Top4" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/Cave/drill2_cave_8a_8x8x8.tile", name = "8" }, 
}

-- DRILL [1]POCKETS
local TunnelPocketTilesDrill1Tiny = { -- 150
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_01_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_02_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_03_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_04_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_06_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_07_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_08_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_09_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_10_1x1x1.tile" },
}

local TunnelPocketTilesDrill1Small = { -- 75
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_02_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_03_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_01_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_01_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_02_2x2x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_03_2x3x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_04_2x3x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_05_2x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_06_2x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_07_2x3x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_08_2x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_09_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_10_2x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_11_2x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_12_2x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_13_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_14_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_15_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_16_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_17_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_18_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_19_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_small_passage_20_2x2x2.tile" },
}

local TunnelPocketTilesDrill1Medium = { -- 25
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_medium_01_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_medium_03_2x2x4.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_medium_04_3x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_medium_08_2x4x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/TunnelPocket/drill1_tunnelpocket_medium_10_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/TunnelPocket/drill1_tunnelpocket_medium_11_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/TunnelPocket/drill1_tunnelpocket_medium_12_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/TunnelPocket/drill1_tunnelpocket_medium_13_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Tunnelpocket/drill1_tunnelpocket_medium_t1pillarCoralium_3x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Tunnelpocket/drill1_tunnelpocket_medium_t1coraliumOpen_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Tunnelpocket/drill1_tunnelpocket_medium_coraliumtop_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Tunnelpocket/drill1_tunnelpocket_medium_coraliumthin_1x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Tunnelpocket/drill1_tunnelpocket_medium_t1veindrillspawner_3x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Tunnelpocket/drill1_tunnelpocket_medium_coraliumledge_3x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Tunnelpocket/drill1_tunnelpocket_medium_claustrophobicDiamond_4x4x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Tunnelpocket/drill1_tunnelpocket_medium_claustrophobicUnderwater_4x4x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Tunnelpocket/drill1_tunnelpocket_medium_t1Minerbot_3x3x3.tile" },
}

local TunnelPocketTilesDrill1Large = { 	--10
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_large_03_4x4x4.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_large_04_4x4x4.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_large_06_4x4x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_large_07_2x4x5.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Tunnelpocket/drill1_tunnelpocket_large_t1Dungeon_4x4x4.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Tunnelpocket/drill1_tunnelpocket_large_t1Balls_4x4x4.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Tunnelpocket/drill1_tunnelpocket_large_rock1Webb_3x3x6.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Tunnelpocket/drill1_tunnelpocket_large_vertical_3x3x6.tile" }, 
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Tunnelpocket/drill1_tunnelpocket_large_UnderwaterRock1_4x4x3.tile" }, 
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Tunnelpocket/drill1_tunnelpocket_large_square_4x4x4.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill1/Tunnelpocket/drill1_tunnelpocket_large_crystaltrees_4x4x4.tile" },












}

local PocketTilesDrill1Tiny = { -- Randomly placed 	
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_emptyRock1_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_coraliumRock1_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_emptyRock2_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_mudRock2_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_mudRock2_02_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_mudRock2_03_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_goldRock2_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_goldRock2_02_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_goldRock2_03_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_quartzRock2_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_quartzRock2_02_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_quartzRock2_03_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_cablebotsRock2_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_emptyRock3_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_goldRock3_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_goldRock3_02_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_goldRock3_03_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_mixedRock3_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_mixedRock3_02_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_mixedRock3_03_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_filledTier1_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_filledTier1_02_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_filledTier1_03_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_filledOrerich_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_potatoNimbolium_1x1x1.tile" },
}

local PocketTilesDrill1Small = {  -- Randomly placed 
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_small_t3deposit1_2x2x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_small_t3deposit2_2x2x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_small_corraliumdeposit1_2x2x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_small_corraliumdeposit2_2x2x1.tile" },
	
}

local PocketTilesDrill1TinyUniqueCount = 0
local PocketTilesDrill1SmallUniqueCount = 0

-- DRILL [2] POCKETS
local TunnelPocketTilesDrill2Tiny = {
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_01_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_02_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_03_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_04_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_06_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_07_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_08_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_09_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/TunnelPocket/tunnelpocket_tiny_10_1x1x1.tile" },
}

local TunnelPocketTilesDrill2Small = {
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_onlyt4_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_01_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_02_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_03_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_01_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_02_2x2x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_03_2x3x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_04_2x3x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_05_2x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_06_2x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_07_2x3x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_08_2x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_09_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_10_2x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_11_2x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_12_2x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_13_2x2x2.tile" }, --Saphire
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_14_2x2x2.tile" }, --Rich ore
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_15_2x2x2.tile" }, --Rich ore
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_16_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_17_2x2x2.tile" }, --Manmade
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_18_2x2x2.tile" }, --crystal Trees
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_19_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Small/drill2_tunnelpocket_small_passage_20_2x2x2.tile" },
	
}

local TunnelPocketTilesDrill2Medium = {
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Medium/drill2_tunnelpocket_medium_01_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Medium/drill2_tunnelpocket_medium_02_3x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Medium/drill2_tunnelpocket_medium_03_2x2x4.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Medium/drill2_tunnelpocket_medium_04_3x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Medium/drill2_tunnelpocket_medium_05_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Medium/drill2_tunnelpocket_medium_06_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Medium/drill2_tunnelpocket_medium_07_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Medium/drill2_tunnelpocket_medium_08_3x3x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Medium/drill2_tunnelpocket_medium_09_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Medium/drill2_tunnelpocket_medium_10_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Medium/drill2_tunnelpocket_medium_11_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Medium/drill2_tunnelpocket_medium_12_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Medium/drill2_tunnelpocket_medium_13_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Medium/drill2_tunnelpocket_medium_claustrophobic_4x4x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Medium/drill2_tunnelpocket_medium_minerbots_3x3x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Medium/drill2_tunnelpocket_medium_tree_3x3x3.tile" },

}
local TunnelPocketTilesDrill2Large = {
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Large/drill2_tunnelpocket_large_03_4x4x4.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Large/drill2_tunnelpocket_large_04_4x4x4.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/TunnelPocket/Large/drill2_tunnelpocket_large_06_4x4x3.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/Tunnelpocket/Large/drill2_tunnelpocket_large_cyrstaltrees_4x4x4.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/Tunnelpocket/Large/drill2_tunnelpocket_large_dungeon_4x4x4.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/Tunnelpocket/Large/drill2_tunnelpocket_large_formations_4x4x4.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/Tunnelpocket/Large/drill2_tunnelpocket_large_square_4x4x4.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/Tunnelpocket/Large/drill2_tunnelpocket_large_vertical_3x3x6.tile" },
	

}

local PocketTilesDrill2Tiny = {
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_gigagem_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Drill2/Pocket/drill2_pocket_tiny_01_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_emptyRock1_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_emptyRock2_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_mudRock2_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_mudRock2_02_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_mudRock2_03_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_goldRock2_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_goldRock2_02_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_goldRock2_03_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_quartzRock2_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_quartzRock2_02_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_quartzRock2_03_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_cablebotsRock2_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_emptyRock3_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_goldRock3_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_goldRock3_02_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_goldRock3_03_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_mixedRock3_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_mixedRock3_02_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_mixedRock3_03_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_filledTier1_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_filledTier1_02_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_filledTier1_03_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_filledOrerich_1x1x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_tiny_potatoNimbolium_1x1x1.tile" },
}

local PocketTilesDrill2Small = {
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_small_t4deposit1_2x2x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_small_t4deposit2_2x2x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_small_mineral4deposit1_2x2x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_small_mineral4deposit2_2x2x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_small_golddeposit1_2x2x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_small_golddeposit2_2x2x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_small_potatohole_2x2x2.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_small_passage_02_2x2x1.tile" },
	{ path = "$SURVIVAL_DATA/Terrain/Tiles/underground/Pocket/pocket_small_02_2x2x2.tile" },
}

local PocketTilesDrill2TinyUniqueCount = 1
local PocketTilesDrill2SmallUniqueCount = 0






















local UndergroundLevels = {
	-- Depth 1, Mining Hub
	{
		core = nil,
		caves = nil,
		pockets = nil,
		tunnelPockets = nil,
		tunnels = false,
	},
 	-- Depth 2, Onboarding
	{
		core = { elevator = CoreTilesElevatorOnboarding },
		caves = { onboarding = CaveTilesMainOnboarding },
		pockets = nil,
		tunnelPockets = nil,
		tunnels = false,
	},
 	-- Depth 3, Station1
	{
		core = nil,
		caves = nil,
		pockets = nil,
		tunnelPockets = nil,
		tunnels = false,
	},
 	-- Depth 4, Drill1
	{
		core = { elevator = CoreTilesElevatorDrill1 },
		caves = { stacked = CaveTilesDrill1 },
		pockets = { tiny = PocketTilesDrill1Tiny, small = PocketTilesDrill1Small },
		pocketUniqueCount = { tiny = PocketTilesDrill1TinyUniqueCount, small = PocketTilesDrill1SmallUniqueCount },
		tunnelPockets = { tiny = TunnelPocketTilesDrill1Tiny, small = TunnelPocketTilesDrill1Small, medium = TunnelPocketTilesDrill1Medium, large = TunnelPocketTilesDrill1Large },
		tunnels = true,
	},
	-- Depth 5, Scrapyard
	{
		core = nil,
		caves = nil,
		pockets = nil,
		tunnelPockets = nil,
		tunnels = false,
	},
	-- Depth 6, Drill2
	{
		core = { elevator = CoreTilesElevatorDrill2 },
		caves = { stacked = CaveTilesDrill2 },
		pockets = { tiny = PocketTilesDrill2Tiny, small = PocketTilesDrill2Small },
		pocketUniqueCount = { tiny = PocketTilesDrill2TinyUniqueCount, small = PocketTilesDrill2SmallUniqueCount },
		tunnelPockets = { tiny = TunnelPocketTilesDrill2Tiny, small = TunnelPocketTilesDrill2Small, medium = TunnelPocketTilesDrill2Medium, large = TunnelPocketTilesDrill2Large },
		tunnels = true,
	},
	-- Depth 7, Station2
	{
		core = nil,
		caves = nil,
		pockets = nil,
		tunnelPockets = nil,
		tunnels = false,
	},
	-- Depth 8, Boss Lobby
	{
		core = nil,
		caves = nil,
		pockets = nil,
		tunnelPockets = nil,
		tunnels = false,
	},
}

function Init( world, generatorIndex, data )





































	g_world = world
	g_generatorIndex = generatorIndex

	g_terrainJson = sm.json.open( data.worldPath )
	g_zones = g_terrainJson.zoneData
	g_portals = g_terrainJson.portalData

	g_depth = data.depth or 0

	-- World tiles
	for _, cell in ipairs( g_terrainJson.cellData ) do
		if cell.path and cell.path ~= "" then
			AddTile( cell.path )
		end
	end

	-- Core tiles
	for _, tileSet in pairs( UndergroundLevels[g_depth].core or {} ) do
		for _, tile in ipairs( tileSet ) do
			tile.size = PathToSize( tile.path )
			AddTile( tile.path )
		end
	end

	-- Cave tiles
	for _, tileSet in pairs( UndergroundLevels[g_depth].caves or {} ) do
		for _, tile in ipairs( tileSet ) do
			tile.size = PathToSize( tile.path )
			AddTile( tile.path )
		end
	end

	-- Pocket tiles
	for _, tileSet in pairs( UndergroundLevels[g_depth].pockets or {} ) do
		for _, tile in ipairs( tileSet ) do
			tile.size = PathToSize( tile.path )
			AddTile( tile.path )
		end
	end

	-- Tunnel pocket tiles
	for _, tileSet in pairs( UndergroundLevels[g_depth].tunnelPockets or {} ) do
		for _, tile in pairs( tileSet ) do
			tile.size = PathToSize( tile.path )
			AddTile( tile.path )
		end
	end













	TgInit()
end

function Create( xMin, xMax, yMin, yMax, seed, data )
	print( "----- terrain_underground.lua - Create world", g_world.id, "[Thread: "..g_generatorIndex.."]-----" )
















	print( "Creating underground terrain" )
	print( "Bounds X: ["..xMin..", "..xMax.."], Y: ["..yMin..", "..yMax.."]" )
	print( string.format( "Seed: %.0f", seed ) )
	print( "Depth:", g_depth )
	print( "Data:", data )
	print( "Total cells: " .. ( xMax - xMin + 1 ) * ( yMax - yMin + 1 ) )

	----------
	print( "Initializing cell data" )

	math.randomseed( seed )

	sm.debugDraw.clear( "VoxelProcDebug" )

	g_savedTileList = {}
	for _, tileSet in pairs( UndergroundLevels[g_depth].core or {} ) do
		for _, tile in ipairs( tileSet ) do
			local uid = sm.terrainTile.getTileUuid( tile.path )
			g_savedTileList[#g_savedTileList + 1] = uid
		end
	end
	for _, tileSet in pairs( UndergroundLevels[g_depth].caves or {} ) do
		for _, tile in ipairs( tileSet ) do
			local uid = sm.terrainTile.getTileUuid( tile.path )
			g_savedTileList[#g_savedTileList + 1] = uid
		end
	end
	for _, tileSet in pairs( UndergroundLevels[g_depth].pockets or {} ) do
		for _, tile in ipairs( tileSet ) do
			local uid = sm.terrainTile.getTileUuid( tile.path )
			g_savedTileList[#g_savedTileList + 1] = uid
		end
	end
	for _, tileSet in pairs( UndergroundLevels[g_depth].tunnelPockets or {} ) do
		for _, tile in pairs( tileSet ) do
			local uid = sm.terrainTile.getTileUuid( tile.path )
			g_savedTileList[#g_savedTileList + 1] = uid
		end
	end












	print( "#g_savedTileList", #g_savedTileList )

	g_randomTileLookup = {}
	for i, uid in ipairs( g_savedTileList ) do
		g_randomTileLookup[tostring( uid )] = i
	end

	g_cellData = {
		bounds = { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax },
		seed = seed,
		data = data,
		-- Per Cell
		uid = {},
		groupId = {},
		xOffset = {},
		yOffset = {},
		rotation = {},
		caves = {},
		pockets = {},
		spawners = {},
		tileList = g_savedTileList,
		tunnels = {},
	}

	g_cellTemp = {
		chunkRaster = {}
	}

	for cellY = g_cellData.bounds.yMin, g_cellData.bounds.yMax do
		g_cellData.uid[cellY] = {}
		g_cellData.xOffset[cellY] = {}
		g_cellData.yOffset[cellY] = {}
		g_cellData.rotation[cellY] = {}
		g_cellData.groupId[cellY] = {}
		g_cellData.caves[cellY] = {}
		g_cellData.pockets[cellY] = {}
		g_cellData.spawners[cellY] = {}

		g_cellTemp.chunkRaster[cellY] = {}

		for cellX = g_cellData.bounds.xMin, g_cellData.bounds.xMax do
			g_cellData.uid[cellY][cellX] = sm.uuid.getNil()
			g_cellData.xOffset[cellY][cellX] = 0
			g_cellData.yOffset[cellY][cellX] = 0
			g_cellData.rotation[cellY][cellX] = 0
			g_cellData.groupId[cellY][cellX] = 0
			g_cellData.caves[cellY][cellX] = {}
			g_cellData.pockets[cellY][cellX] = {}
			g_cellData.spawners[cellY][cellX] = {}

			g_cellTemp.chunkRaster[cellY][cellX] = {}
		end
	end

	g_groupIdCount = 0

	----------

	local xMinChunk = ( xMin ) * CHUNKS_PER_CELL + BedrockPadding
	local xMaxChunk = ( xMax + 1 ) * CHUNKS_PER_CELL - BedrockPadding - 1
	local yMinChunk = ( yMin ) * CHUNKS_PER_CELL + BedrockPadding
	local yMaxChunk = ( yMax + 1 ) * CHUNKS_PER_CELL - BedrockPadding - 1
	if g_depth == 4 or g_depth == 6 then
		yMaxChunk = yMaxChunk - 4 -- Elevator sticks 1 cell into bedrock on elevator side
	end
	print( "Chunk bounds X: ["..xMinChunk..", "..xMaxChunk.."], Y: ["..yMinChunk..", "..yMaxChunk.."]" )

	-- Shuffle core tiles
	local levelCoreTiles = {}
	for tileSetName, tileSet in pairs( UndergroundLevels[g_depth].core or {} ) do
		levelCoreTiles[tileSetName] = shallowcopy( tileSet ) -- For shuffle
		shuffle( levelCoreTiles[tileSetName] )
	end
	-- Shuffle cave tiles
	local levelCaveTiles = {}
	for tileSetName, tileSet in pairs( UndergroundLevels[g_depth].caves or {} ) do
		levelCaveTiles[tileSetName] = shallowcopy( tileSet ) -- For shuffle
		--shuffle( levelCaveTiles[tileSetName] )
	end
	-- Shuffle pocket tiles (keeping the first uniqueCount unique pockets fixed at the front)
	local levelPocketTiles = {}
	local levelPocketUniqueCount = UndergroundLevels[g_depth].pocketUniqueCount or {}
	for tileSetName, tileSet in pairs( UndergroundLevels[g_depth].pockets or {} ) do
		levelPocketTiles[tileSetName] = shallowcopy( tileSet ) -- For shuffle
		shuffle( levelPocketTiles[tileSetName], ( levelPocketUniqueCount[tileSetName] or 0 ) + 1 )
	end
	-- Shuffle tunnel pocket tiles
	local levelTunnelPocketTiles = {}
	for tunnelTypeName, tileSet in pairs( UndergroundLevels[g_depth].tunnelPockets or {} ) do
		levelTunnelPocketTiles[tunnelTypeName] = shallowcopy( tileSet )
		shuffle( levelTunnelPocketTiles[tunnelTypeName] )
	end

	local elevatorLocationStorage = sm.terrainGeneration.loadGameStorage( STORAGE_CHANNEL_ELEVATOR_LOCATIONS ) or {}
	if not elevatorLocationStorage[g_world.id] then
		elevatorLocationStorage[g_world.id] = {}
	end

	-- Tile storage keys for tiles that suppress bond builder (flavor) dialogs (elevator tiles). Keys
	-- already include the world id, so they are stored in a single global set covering all worlds.
	local bondBuilderExclusionStorage = sm.terrainGeneration.loadGameStorage( STORAGE_CHANNEL_BONDBUILDER_EXCLUSION_TILES ) or {}

	print( "Adding tiles from predefined world map" )
	for _, cell in ipairs( g_terrainJson.cellData ) do
		if g_cellData.uid[cell.y] and g_cellData.uid[cell.y][cell.x] then
			if cell.path and cell.path ~= "" then
				local uid = sm.terrainTile.getTileUuid( cell.path )
				local groupId = FindGroupIdFromNeighbor( uid, cell )
				if not groupId then
					g_groupIdCount = g_groupIdCount + 1
					groupId = g_groupIdCount
				end
				g_cellData.uid[cell.y][cell.x] = uid
				g_cellData.xOffset[cell.y][cell.x] = cell.offsetX
				g_cellData.yOffset[cell.y][cell.x] = cell.offsetY
				g_cellData.rotation[cell.y][cell.x] = cell.rotation
				g_cellData.groupId[cell.y][cell.x] = groupId
				InitChunkRaster( cell.x, cell.y, 2 )
				concat( elevatorLocationStorage[g_world.id], FindConnectionNodes( uid, cell, "UNDERGROUND_ELEVATOR", UNDERGROUND_CONNECTIONS ) )
			end
		end
	end

	print( "Initializing empty cells" )
	for cellY = yMin, yMax do
		for cellX = xMin, xMax do
			if g_cellData.uid[cellY][cellX]:isNil() then
				InitChunkRaster( cellX, cellY, 0 )
			end
		end
	end

	if g_depth == 4 or g_depth == 6 then
		local function blockBedrock( chunkPos, size )
			local ddColor = nil--"00ff00"
			WriteChunkRaster( chunkPos, size, 1, nil, ddColor )
			TgAddBlocker( chunkPos, chunkPos + size, "Bedrock" )
		end
		-- Block in front of elevator
		--blockBedrock( sm.vec3.new( -4, -6, 0 ), sm.vec3.new( 12, 2, 8 ) )
		-- Block bedrock pyramid
		blockBedrock( sm.vec3.new( -6, -6, 0 ), sm.vec3.new( 16, 6, 1 ) )
		blockBedrock( sm.vec3.new( -5, -5, 1 ), sm.vec3.new( 14, 5, 1 ) )
		-- World beveled edge
		local bevelSizeX = g_depth == 6 and 16 or 16
		local bevelSizeY = g_depth == 6 and 4 or 4
		local dx = 4
		for i = 0, bevelSizeY - 1 do
			-- SW
			blockBedrock( sm.vec3.new( xMinChunk, yMinChunk + i, 0 ), sm.vec3.new( bevelSizeX - dx * i, 1, 8 ) )
			-- SE
			blockBedrock( sm.vec3.new( xMaxChunk - bevelSizeX + dx * i + 1, yMinChunk + i, 0 ), sm.vec3.new( bevelSizeX - dx * i, 1, 8 ) )
			-- NW
			blockBedrock( sm.vec3.new( xMinChunk, yMaxChunk - i, 0 ), sm.vec3.new( bevelSizeX - dx * i, 1, 8 ) )
			-- NE
			blockBedrock( sm.vec3.new( xMaxChunk - bevelSizeX + dx * i + 1, yMaxChunk - i, 0 ), sm.vec3.new( bevelSizeX - dx * i, 1, 8 ) )
		end
	end

	-- Cave style elevators
	if levelCoreTiles.elevator and #levelCoreTiles.elevator > 0 then
		print( "Adding elevator cave" )
		local elevator = levelCoreTiles.elevator[1] -- Already shuffled
		local elevatorPos
		if g_depth == 2 then
			elevatorPos = sm.vec3.new( -1, -2, 4 )
		elseif g_depth == 4 or g_depth == 6 then
			elevatorPos = sm.vec3.new( -1, -1, 2 )
		end
		if elevatorPos then
			AddCave( elevator, elevatorPos, "Elevator", 0, elevatorLocationStorage[g_world.id] )
			-- Elevator tiles have no z-offset suffix, so the cave origin equals elevatorPos.
			local exclusionKey = CalculateCaveTileStorageKey( g_world.id, elevatorPos.x, elevatorPos.y, 0, sm.vec3.new( 0, 0, 0 ), sm.vec3.new( 0, 0, elevatorPos.z ) )
			bondBuilderExclusionStorage[exclusionKey] = true
		end
	end

	if levelCaveTiles.onboarding and #levelCaveTiles.onboarding > 0 then
		print( "Adding onboarding caves" )
		local tileNames = {}
		for _, cave in ipairs( levelCaveTiles.onboarding ) do
			if cave.name then
				tileNames[cave.name] = cave
			end
		end
		AddCave( tileNames["First"], sm.vec3.new( -1, -4, 4 ), "Cave", 0 )
		AddCave( tileNames["Midblocker"], sm.vec3.new( -1, -6, 2 ), "Cave", 0 )
		AddCave( tileNames["Left"], sm.vec3.new( 1, -6, 2 ), "Cave", 0 )
		AddCave( tileNames["Join"], sm.vec3.new( -1, -8, 2 ), "Cave", 0 )
		AddCave( tileNames["Final"], sm.vec3.new( -1, -12, 1 ), "Cave", 0 )
	end

	local caveVeinTunnelNodes = {}

	if levelCaveTiles.stacked and #levelCaveTiles.stacked > 0 then
		print( "Adding stacked caves" )
		local tileNames = {}
		for _, cave in ipairs( levelCaveTiles.stacked ) do
			if cave.name then
				tileNames[cave.name] = cave
			end
		end
		local stacks
		if g_depth == 6 then
			local configs = { { tileNames["8"] }, { tileNames["Bot5"], tileNames["Top3"] }, { tileNames["Bot4"], tileNames["Top4"] } }
			shuffle( configs, 2 )
			stacks = {
				{ x = -1, y = -7, rot = 2, config = configs[1], oxvals = { 0, 1 }, oyvals = nil }, --S
				{ x = -5, y = -6, rot = 1, config = configs[2], oxvals = nil, oyvals = { 0, 3 } }, --W
				{ x =  4, y = -6, rot = 3, config = configs[3], oxvals = nil, oyvals = { 0, 3 } }, --E
			}
		else
			local configs = { { tileNames["8"] }, { tileNames["Bot3"], tileNames["Top5"] }, { tileNames["Bot4"], tileNames["Top4"] } }
			shuffle( configs, 2 )
			stacks = {
				{ x = -1, y = -7, rot = 2, config = configs[1], oxvals = { 0, 1 }, oyvals = nil }, --S
				{ x = -5, y = -6, rot = 1, config = configs[2], oxvals = nil, oyvals = { 0, 3 } }, --W
				{ x =  4, y = -6, rot = 3, config = configs[3], oxvals = nil, oyvals = { 0, 3 } }, --E
			}
		end
		for _, stack in ipairs( stacks ) do
			sm.debugDraw.addAabb( "VoxelProcDebug_Stack"..stack.x..","..stack.y, sm.vec3.new( stack.x, stack.y, 0 ) * 4 * CHUNK_SIZE,
				( sm.vec3.new( stack.x, stack.y, 0 ) + sm.vec3.new( 2, 2, 2 ) + sm.vec3.new( stack.oxvals and stack.oxvals[#stack.oxvals] or 0, stack.oyvals and stack.oyvals[#stack.oyvals] or 0, 0 ) ) * 4 * CHUNK_SIZE,
				sm.color.new( "00ff00" ) )
			local z = 0
			if stack.oxvals then
				shuffle( stack.oxvals )
			end
			if stack.oyvals then
				shuffle( stack.oyvals )
			end
			for _, tile in ipairs( stack.config ) do
				local offset = sm.vec3.new( 0, 0, 0 )
				if stack.oxvals and stack.oxvals[#stack.oxvals] then
					offset.x = stack.oxvals[#stack.oxvals]
					stack.oxvals[#stack.oxvals] = nil
				end
				if stack.oyvals and stack.oyvals[#stack.oyvals] then
					offset.y = stack.oyvals[#stack.oyvals]
					stack.oyvals[#stack.oyvals] = nil
				end
				local added, tunnelNodes = AddCave( tile, sm.vec3.new( stack.x, stack.y, z ) + offset, "Cave", stack.rot )
				if added then
					for _, tunnelNode in ipairs( tunnelNodes ) do
						if tunnelNode.type == "Vein" then
							caveVeinTunnelNodes[#caveVeinTunnelNodes + 1] = tunnelNode
						else
							sm.debugDraw.addText( "VoxelProcDebug_CaveWrongType"..tostring(tunnelNode.pos), tunnelNode.type, tunnelNode.pos )
							sm.debugDraw.addSphere( "VoxelProcDebug_CaveWrongType"..tostring( tunnelNode.pos ), tunnelNode.pos, 1, sm.color.new( "ff0000" ) )
						end
					end
				end
				z = z + tile.size.z
			end
		end
		shuffle( caveVeinTunnelNodes )
	end

	sm.terrainGeneration.saveGameStorage( STORAGE_CHANNEL_ELEVATOR_LOCATIONS, elevatorLocationStorage )
	sm.terrainGeneration.saveGameStorage( STORAGE_CHANNEL_BONDBUILDER_EXCLUSION_TILES, bondBuilderExclusionStorage )
	sm.terrainGeneration.setGameStorageNoSave( "tileData"..g_world.id, GetTileDatabase() )

	local distancePenalty = sm.vec3.new( 1, 1, 2 ) -- Prefer horizontal connections

	local function findBestConnection( nodesA, nodesB )
		local bestNodeA = nil
		local bestNodeB = nil
		local bestDistance = nil
		for _, nodeA in ipairs( nodesA ) do
			if not nodeA.toNode then
				for _, nodeB in ipairs( nodesB ) do
					if not nodeB.toNode then
						local distance = ( ( nodeA.pos - nodeB.pos ) * distancePenalty ):length()
						if not bestDistance or distance < bestDistance then
							bestNodeA = nodeA
							bestNodeB = nodeB
							bestDistance = distance
						end
					end
				end
			end
		end
		return bestNodeA, bestNodeB, bestDistance
	end

	local function findClosestUnusedNode( tunnelNodes, referencePos )
		local bestNode = nil
		local bestDistance = nil
		for _, node in ipairs( tunnelNodes ) do
			if not node.toNode then
				local distance = ( ( referencePos - node.pos ) * distancePenalty ):length()
				if not bestDistance or distance < bestDistance then
					bestNode = node
					bestDistance = distance
				end
			end
		end
		return bestNode, bestDistance
	end

	local keyToPocket = {}
	local pocketMainTunnelNodes = {}

	if UndergroundLevels[g_depth].tunnelPockets then
		local zMaxChunk = 8
		local startTime = os.clock()
		local positions = {}
		for y = yMinChunk + 1, yMaxChunk - 1 do
			for x = xMinChunk + 1, xMaxChunk - 1 do
				for z = 1, zMaxChunk - 1 do
					local pos = sm.vec3.new( x, y, z )
					if CheckIfFits( pos, sm.vec3.one(), nil, 1, 1 ) then
						positions[#positions + 1] = pos
					end
				end
			end
		end

		local pocketTypeLimit = {
			large = 10, -- ~64 chunks
			medium = 25, -- ~27 chunks = *2.3703703703703703703703703703704
			small = 75, -- ~8 chunks  = *3.375
			tiny = 150, -- 1 chunk
		}
		local pocketTag = {
			large = "TunnelPocket",
			medium = "TunnelPocket",
			small = "TunnelPocket",
			tiny = "TinyTunnelPocket",
		}
		local pocketTypes = { "large", "medium", "small", "tiny" }
		local pocketTypeIdx = {}
		local pocketTypeCount = {}
		for _, pocketType in ipairs( pocketTypes ) do
			pocketTypeIdx[pocketType] = 1
			pocketTypeCount[pocketType] = 0
		end
		for _, pocketType in ipairs( pocketTypes ) do
			local pocketTypeStartTime = os.clock()
			local findClosestUnusedNodeTime = 0
			shuffle( positions )
			local pocketTiles = levelTunnelPocketTiles[pocketType]
			print( "Adding", pocketType, "tunnel pockets, limit:", pocketTypeLimit[pocketType] )
			local startIndex = 1
			for _ = 1, pocketTypeLimit[pocketType] or 1 do
				local failed = true
				for i = startIndex, #positions do
					local tile = pocketTiles[pocketTypeIdx[pocketType]]
					local pos = positions[i]
					local rotation = math.random( 4 ) - 1
					local pocketCenterPos = ( pos + tile.size / 2 ) * CHUNK_SIZE
					local findClosestStartTime = os.clock()
					local closestNode = findClosestUnusedNode( caveVeinTunnelNodes, pocketCenterPos )
					findClosestUnusedNodeTime = findClosestUnusedNodeTime + ( os.clock() - findClosestStartTime )
					if closestNode then
						-- -Z facing closest cave entry node
						local direction = closestNode.pos - pocketCenterPos
						if math.abs( direction.x ) >= math.abs( direction.y ) then
							rotation = direction.x > 0 and 1 or 3
						else
							rotation = direction.y > 0 and 2 or 0
						end
					end

					local worldPocketSize = rotation % 2 == 1 and sm.vec3.new( tile.size.y, tile.size.x, tile.size.z ) or tile.size

					if pos.x + ( worldPocketSize.x - 1 ) >= xMaxChunk then
						goto continue -- Skipping, pocket out of bounds
					end
					if pos.y + ( worldPocketSize.y - 1 ) >= yMaxChunk then
						goto continue -- Skipping, pocket out of bounds
					end
					if pos.z + ( worldPocketSize.z - 1 ) >= zMaxChunk then
						goto continue -- Skipping, pocket out of bounds
					end
					--print( "  Adding", tile.path, "pos", pos, "rotation", rotation )
					local added, tunnelNodes, srcKey = AddPocket( tile, pos, rotation, pocketTag[pocketType], 1, 1 )
					if added then
						if closestNode then
							--sm.debugDraw.addArrow( "VoxelProcDebug_PocketNode"..tostring(pos), pocketCenterPos, closestNode.pos, sm.color.new( "ff00ff" ) )
						end
						for _, node in ipairs( tunnelNodes ) do
							if node.type == "Main" and pocketType ~= "tiny" then
								pocketMainTunnelNodes[#pocketMainTunnelNodes + 1] = node
							end
						end
						keyToPocket[srcKey] = { pos = pos, tunnelNodes = tunnelNodes }

						pocketTypeIdx[pocketType] = pocketTiles[pocketTypeIdx[pocketType] + 1] ~= nil and pocketTypeIdx[pocketType] + 1 or 1
						pocketTypeCount[pocketType] = pocketTypeCount[pocketType] + 1
						if pocketType == "tiny" then
							startIndex = i + 1
						else
							--TODO: Respect raster grid if needed
							removeFromArray( positions, function( val ) return val.x >= pos.x - 1 and val.y >= pos.y - 1 and val.z >= pos.z and
							 val.x < pos.x + worldPocketSize.x + 1 and val.y < pos.y + worldPocketSize.y + 1 and val.z < pos.z + worldPocketSize.z end )
						end
						failed = false
						break
					end
					::continue::
				end
				if failed then
					print( "Failed to place", pocketType, "tunel pocket" )
					break
				end
			end
			print( string.format( "  Added %d %s tunnel pockets, %.3f seconds (findClosestUnusedNode: %.3f seconds)", pocketTypeCount[pocketType], pocketType, os.clock() - pocketTypeStartTime, findClosestUnusedNodeTime ) )
		end
		local endTime = os.clock()
		print( string.format( "Tunnel pocket placement: %.3f seconds", endTime - startTime ) )

		local boundsMinX = ( xMinChunk + 2 / TUNNEL_GRID_CELLS_PER_CHUNK ) * CHUNK_SIZE
		local boundsMinY = ( yMinChunk + 2 / TUNNEL_GRID_CELLS_PER_CHUNK ) * CHUNK_SIZE
		local boundsMaxX = ( xMaxChunk + 1 - 2 / TUNNEL_GRID_CELLS_PER_CHUNK ) * CHUNK_SIZE
		local boundsMaxY = ( yMaxChunk + 1 - 2 / TUNNEL_GRID_CELLS_PER_CHUNK ) * CHUNK_SIZE
		--sm.debugDraw.addBox( "VoxelProcDebug_Bounds", sm.vec3.new( boundsMinX, boundsMinY, 0 ), sm.vec3.new( boundsMaxX, boundsMaxY, 8 * CHUNK_SIZE ), sm.vec3.zero(), nil, sm.color.new( "ffff00" ) )

		local function connectToClosestTunnelNode( node, tunnelNodes )
			if node.pos.x + node.direction.x > boundsMinX and node.pos.x + node.direction.x < boundsMaxX and
			   node.pos.y + node.direction.y > boundsMinY and node.pos.y + node.direction.y < boundsMaxY then
				--sm.debugDraw.addSphere( "VoxelProcDebug_ConnectNode"..tostring( node.pos ), node.pos, 1, sm.color.new( "00ffff" ) )
				local closestNode, closestDistance = findClosestUnusedNode( tunnelNodes, node.pos )
				if closestNode and closestDistance <= 12 * TUNNEL_GRID_SIZE then
					--sm.debugDraw.addArrow( "VoxelProcDebug_TunnelNodeConnection"..tostring( node.pos ), node.pos, closestNode.pos, sm.color.new( "00ffff" ) )
					--sm.debugDraw.addText( "VoxelProcDebug_TunnelNodeDistance"..tostring( node.pos ), string.format( "%.1f", closestDistance / TUNNEL_GRID_SIZE ), ( closestNode.pos + node.pos ) / 2 )
					node.toNode = closestNode
					closestNode.toNode = node
					return closestNode
				end
			else
				-- Too close to world border
				--sm.debugDraw.addSphere( "VoxelProcDebug_ConnectNode"..tostring( node.pos ), node.pos, 1, sm.color.new( "ff0000" ) )
			end
		end

		local tier1TunnelPockets = {}
		-- Connect caves to pockets
		for _, node in ipairs( caveVeinTunnelNodes ) do
			assert( not node.toNode )
			local closestNode = connectToClosestTunnelNode( node, pocketMainTunnelNodes )
			if closestNode then
				--sm.debugDraw.addArrow( "VoxelProcDebug_TunnelNodeConnection"..tostring( node.pos ), node.pos, closestNode.pos, sm.color.new( "00ffff" ) )
				--sm.debugDraw.addText( "VoxelProcDebug_TunnelNodeConnection"..tostring( node.pos ), "1", ( closestNode.pos + node.pos ) / 2 )
				local pocket = keyToPocket[closestNode.srcKey]
				if pocket then
					local tier1Pocket = { veinTunnelNodes = {} }
					for _, tunnelNode in ipairs( pocket.tunnelNodes ) do
						if tunnelNode.type == "Vein" and not tunnelNode.toNode then
							tier1Pocket.veinTunnelNodes[#tier1Pocket.veinTunnelNodes + 1] = tunnelNode
							--sm.debugDraw.addArrow( "VoxelProcDebug_PocketNodeToCaveVein"..tostring(tunnelNode.pos), tunnelNode.pos, node.pos, sm.color.new( "ff00ff" ) )
							--sm.debugDraw.addSphere( "VoxelProcDebug_PocketVeinNode"..tostring( tunnelNode.pos ), tunnelNode.pos, 1, sm.color.new( "ff00ff" ) )
						end
					end
					tier1TunnelPockets[#tier1TunnelPockets + 1] = tier1Pocket
				end
			end
		end
		shuffle( tier1TunnelPockets )
		-- Connect tier 1 pockets to other pockets
		for _, pocket in ipairs( tier1TunnelPockets ) do
			local bestNodeA, bestNodeB, bestDistance = findBestConnection( pocket.veinTunnelNodes, pocketMainTunnelNodes )
			if bestNodeA and bestNodeB and bestDistance <= 12 * TUNNEL_GRID_SIZE then
				bestNodeA.toNode = bestNodeB
				bestNodeB.toNode = bestNodeA
				--sm.debugDraw.addArrow( "VoxelProcDebug_TunnelNodeConnection"..tostring( bestNodeA.pos ), bestNodeA.pos, bestNodeB.pos, sm.color.new( "ff00ff" ) )
				--sm.debugDraw.addText( "VoxelProcDebug_TunnelNodeConnection"..tostring( bestNodeA.pos ), "2", ( bestNodeB.pos + bestNodeA.pos ) / 2 )
			end
		end
	end

	g_cellData.tunnels = {}

	-- Tunnels
	if UndergroundLevels[g_depth].tunnels then
		local tunnels = TgCreateTunnels( xMinChunk, xMaxChunk, yMinChunk, yMaxChunk, 0, 7, seed, "Main" )
		removeFromArray( tunnels, function( tunnel ) return #tunnel.positions < 2 end ) -- Remove failed tunnels
		concat( g_cellData.tunnels, tunnels )
	end

	TgDebugDrawBlockers()

	do
		local typeCount = {}
		local one = sm.vec3.one()
		for _, tunnel in ipairs( g_cellData.tunnels ) do
			if tunnel.tunnelType == "MainVein" then
				local roll = math.random()
				if roll < 0.5 then
					tunnel.tunnelType = "TtVeinRich"
				else
					tunnel.tunnelType = g_depth == 6 and "TtVeinT4" or "TtVeinT1"
				end
			end
			if tunnel.tunnelType == "CrossVein" then
				local roll = math.random()
				if roll < 0.1 then
					tunnel.tunnelType = "TtVeinRich"
				elseif roll < 0.2 then
					tunnel.tunnelType = g_depth == 6 and "TtVeinT4" or "TtVeinT1"
				else
					tunnel.tunnelType = "TtVeinSparkstone"
				end
			end
			typeCount[tunnel.tunnelType] = ( typeCount[tunnel.tunnelType] or 0 ) + 1

			-- Loop tunnels and add blockers to prevent terrain generation from filling them in
			for i = 1, #tunnel.positions do
				local chunkPos = ( tunnel.positions[i] / CHUNK_SIZE ):floor()
				if CheckIfFits( chunkPos, one, nil, 1, 0 ) then
					local ddColor = nil--"ff8000"
					WriteChunkRaster( chunkPos, one, 1, nil, ddColor )
				end
			end

		end
		print( "Tunnel type counts:" )
		for tunnelType, count in pairs( typeCount ) do
			print( "  ", tunnelType, count )
		end
	end












































	if UndergroundLevels[g_depth].pockets then
		local zMaxChunk = 8
		local startTime = os.clock()
		local positions = {}
		for y = yMinChunk + 1, yMaxChunk - 1 do
			for x = xMinChunk + 1, xMaxChunk - 1 do
				for z = 1, zMaxChunk - 1 do
					local pos = sm.vec3.new( x, y, z )
					if CheckIfFits( pos, sm.vec3.one(), nil, 1, 0 ) then
						positions[#positions + 1] = pos
						--sm.debugDraw.addBox( "VoxelProcDebug_FreePocketPos"..tostring(pos), sm.vec3.zero(), sm.vec3.new( CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE ), pos * CHUNK_SIZE, nil, sm.color.new( "ff0000" ) )
					end
				end
			end
		end
		print( "Found", #positions, "potential free pocket positions" )

		local pocketTypeLimit = {
			small = 100, -- ~8 chunks
			tiny = 200, -- 1 chunk
		}
		local pocketTypes = { "small", "tiny" }
		local pocketTypeIdx = {}
		local pocketTypeCount = {}
		for _, pocketType in ipairs( pocketTypes ) do
			pocketTypeIdx[pocketType] = 1
			pocketTypeCount[pocketType] = 0
		end
		for _, pocketType in ipairs( pocketTypes ) do
			local pocketTypeStartTime = os.clock()
			shuffle( positions )
			local pocketTiles = levelPocketTiles[pocketType]
			local uniqueCount = levelPocketUniqueCount[pocketType] or 0
			print( "Adding", pocketType, "free pockets, limit:", pocketTypeLimit[pocketType] )
			local startIndex = 1
			for _ = 1, pocketTypeLimit[pocketType] or 1 do
				local failed = true
				for i = startIndex, #positions do
					local tile = pocketTiles[pocketTypeIdx[pocketType]]
					local pos = positions[i]
					local rotation = math.random( 4 ) - 1
					local worldPocketSize = rotation % 2 == 1 and sm.vec3.new( tile.size.y, tile.size.x, tile.size.z ) or tile.size
					if pos.x + ( worldPocketSize.x - 1 ) >= xMaxChunk then
						goto continue -- Skipping, pocket out of bounds
					end
					if pos.y + ( worldPocketSize.y - 1 ) >= yMaxChunk then
						goto continue -- Skipping, pocket out of bounds
					end
					if pos.z + ( worldPocketSize.z - 1 ) >= zMaxChunk then
						goto continue -- Skipping, pocket out of bounds
					end
					--print( "  Adding", tile.path, "pos", pos, "rotation", rotation )
					local added, tunnelNodes, srcKey = AddPocket( tile, pos, rotation, "FreePocket", 1, 0 )
					if added then
						-- Skip over the first uniqueCount unique pockets when cycling back to the start
						pocketTypeIdx[pocketType] = pocketTiles[pocketTypeIdx[pocketType] + 1] ~= nil and pocketTypeIdx[pocketType] + 1 or ( uniqueCount + 1 )
						pocketTypeCount[pocketType] = pocketTypeCount[pocketType] + 1
						if pocketType == "tiny" then
							startIndex = i + 1
						else
							--TODO: Respect raster grid if needed
							removeFromArray( positions, function( val ) return val.x >= pos.x and val.y >= pos.y and val.z >= pos.z and
							 val.x < pos.x + worldPocketSize.x and val.y < pos.y + worldPocketSize.y and val.z < pos.z + worldPocketSize.z end )
						end
						failed = false
						break
					end
					::continue::
				end
				if failed then
					print( "Failed to place", pocketType, "free pocket" )
					break
				end
			end
			print( string.format( "  Added %d %s free pockets, %.3f seconds", pocketTypeCount[pocketType], pocketType, os.clock() - pocketTypeStartTime ) )
		end
		local endTime = os.clock()
		print( string.format( "Free pocket placement: %.3f seconds", endTime - startTime ) )
	end















































	sm.terrainData.save( g_cellData )

	UpdateLocationStorage()
	UpdateTunnelCulling()

	g_cellTemp = nil
end

function Load()
	print( "----- terrain_underground.lua - Load world", g_world.id, "[Thread: "..g_generatorIndex.."]-----" )

	if g_generatorIndex == 0 and sm.isHost then
		sm.terrainGeneration.setGameStorageNoSave( "tileData"..g_world.id, GetTileDatabase() )
	end


	if sm.terrainData.exists() then
		g_cellData = sm.terrainData.load()
		print( "Bounds X: [" .. g_cellData.bounds.xMin .. ", " .. g_cellData.bounds.xMax .. "], Y: [" .. g_cellData.bounds.yMin .. ", " .. g_cellData.bounds.yMax .. "]" )
		print( "Seed: "..g_cellData.seed )

		g_savedTileList = g_cellData.tileList

		g_randomTileLookup = {}
		for i, uid in ipairs( g_savedTileList ) do
			g_randomTileLookup[tostring( uid )] = i
		end

		UpdateLocationStorage()
		UpdateTunnelCulling()

		g_zones = g_terrainJson.zoneData
		g_portals = g_terrainJson.portalData

		return true
	end

	print( "No terrain data found" )
	return false
end

function GetCullingZoneTree()
	return g_portals, g_zones
end

----------------------------------------------------------------------------------------------------
-- Generator API Getters
----------------------------------------------------------------------------------------------------

function GetCellTileUidAndOffset( cellX, cellY )
	if InsideCellBounds( cellX, cellY ) then
		return 	g_cellData.uid[cellY][cellX],
				g_cellData.xOffset[cellY][cellX],
				g_cellData.yOffset[cellY][cellX]
	end
	return sm.uuid.getNil(), 0, 0
end

----------------------------------------------------------------------------------------------------

function GetHeightAt( x, y, lod )
	local cellX, cellY = GetCell( x, y )
	local uid, xOffset, yOffset = GetCellTileUidAndOffset( cellX, cellY )

	if not uid:isNil() then
		local rx, ry = InverseRotateLocal( cellX, cellY, x - cellX * CELL_SIZE, y - cellY * CELL_SIZE )
		return sm.terrainTile.getHeightAt( uid, xOffset, yOffset, lod, rx, ry )
	end
	return 0
end

----------------------------------------------------------------------------------------------------

function GetColorAt( x, y, lod )
	local cellX, cellY = GetCell( x, y )
	local uid, xOffset, yOffset = GetCellTileUidAndOffset( cellX, cellY )

	if not uid:isNil() then
		local brightness = sm.noise.octaveNoise2d( x / 8, y / 8, 5, 45 ) * 0.25 + 0.75







		local rx, ry = InverseRotateLocal( cellX, cellY, x - cellX * CELL_SIZE, y - cellY * CELL_SIZE )
		local color = { sm.terrainTile.getColorAt( uid, xOffset, yOffset, lod, rx, ry ) }
		return color[1] * brightness, color[2] * brightness, color[3] * brightness
	end
	if InsideCellBounds( cellX, cellY ) then
		local brightness = sm.noise.octaveNoise2d( x / 8, y / 8, 5, 45 ) * 0.25 + 0.75
		return brightness, brightness, brightness
	end
	return 0, 0, 0
end

----------------------------------------------------------------------------------------------------

function GetMaterialAt( x, y, lod )
	local cellX, cellY = GetCell( x, y )
	local uid, xOffset, yOffset = GetCellTileUidAndOffset( cellX, cellY )

	if not uid:isNil() then
		local rx, ry = InverseRotateLocal( cellX, cellY, x - cellX * CELL_SIZE, y - cellY * CELL_SIZE )
		return sm.terrainTile.getMaterialAt( uid, xOffset, yOffset, lod, rx, ry )
	end
	return 0, 0, 0, 0, 0, 0, 0, 0
end

----------------------------------------------------------------------------------------------------

function GetClutterIdxAt( x, y )
	local cellX, cellY = GetCell( x * 0.5, y * 0.5 )
	local uid, xOffset, yOffset = GetCellTileUidAndOffset( cellX, cellY )

	if not uid:isNil() then
		local rx, ry = InverseRotateLocal( cellX, cellY, x - cellX * CELL_SIZE * 2, y - cellY * CELL_SIZE * 2, CELL_SIZE * 2 - 1 )
		return sm.terrainTile.getClutterIdxAt( uid, xOffset, yOffset, rx, ry )
	end
	return -1
end

function GetEffectMaterialAt( x, y )
	return "Sand"
end

----------------------------------------------------------------------------------------------------

function PrepareCell( cellX, cellY, loadFlags )
	DefaultPrepareCell( cellX, cellY, loadFlags )
end

----------------------------------------------------------------------------------------------------

function GetAssetsForCell( cellX, cellY, size )
	local assets = g_prefabAssets
	g_prefabAssets = {}

	if InsideCellBounds( cellX, cellY ) then
		local uid, xOffset, yOffset = GetCellTileUidAndOffset( cellX, cellY )
		if not uid:isNil() then
			local cellRotation = GetCellRotation( cellX, cellY )
			for _, asset in ipairs( sm.terrainTile.getAssetsForCell( uid, xOffset, yOffset, size ) ) do
				asset.pos.x, asset.pos.y = RotateLocal2( cellRotation, asset.pos.x, asset.pos.y, CELL_SIZE, CELL_SIZE )
				asset.pos.z = WaterSurfaceGridOffset( asset, asset.pos.z )
				asset.rot = GetRotationQuat2( cellRotation ) * asset.rot
				assets[#assets + 1] = asset
			end

			if #assets > 0 then
				local syncedKey = CalculateTileStorageKey( g_world.id, cellX, cellY ) .. SYNC_KEY
				if syncedKey then
					local tileStorage = sm.terrainGeneration.loadGameStorage( syncedKey ) or {}
					FilterTileStorageTaggedObjects( assets, tileStorage )
				end
			end
		else
			local caves = g_cellData.caves[cellY][cellX]
			for i = 1, #caves do
				local tileUid, rotation, srcOffset, dstOffset, srcSize = DecodeCaveCellData( caves[i] )
				local caveAssets = {}
				for _, asset in ipairs( sm.terrainTile.getAssetsForCell( tileUid, srcOffset.x, srcOffset.y, size ) ) do
					asset.pos.x, asset.pos.y = RotateLocal2( rotation, asset.pos.x, asset.pos.y, CELL_SIZE, CELL_SIZE )
					asset.pos = asset.pos + dstOffset * CHUNK_SIZE
					asset.rot = GetRotationQuat2( rotation ) * asset.rot
					caveAssets[#caveAssets + 1] = asset
				end
				if #caveAssets > 0 then
					local syncedKey = CalculateCaveTileStorageKey( g_world.id, cellX, cellY, rotation, srcOffset, dstOffset ) .. SYNC_KEY
					local caveStorage = sm.terrainGeneration.loadGameStorage( syncedKey ) or {}
					FilterTileStorageTaggedObjects( caveAssets, caveStorage )
				end
				for _, asset in ipairs( caveAssets ) do
					assets[#assets + 1] = asset
				end
			end

			local pockets = g_cellData.pockets[cellY][cellX]
			for i = 1, #pockets do
				local tileUid, rotation, srcOffset, dstOffset, srcSize = DecodePocketCellData( pockets[i] )
				local pocketAssets = {}
				for _, asset in ipairs( sm.terrainTile.getAssetsForCell( tileUid, 0, 0, size ) ) do
					asset.pos.x, asset.pos.y = RotateLocal2( rotation, asset.pos.x - srcOffset.x * CHUNK_SIZE, asset.pos.y - srcOffset.y * CHUNK_SIZE, srcSize.x * CHUNK_SIZE, srcSize.y * CHUNK_SIZE )
					asset.pos = asset.pos + dstOffset * CHUNK_SIZE
					if math.floor( asset.pos.x / CELL_SIZE ) == 0 and math.floor( asset.pos.y / CELL_SIZE ) == 0 then
						asset.rot = GetRotationQuat2( rotation ) * asset.rot
						pocketAssets[#pocketAssets + 1] = asset
					end
				end
				if #pocketAssets > 0 then
					local syncedKey = CalculatePocketTileStorageKey( g_world.id, cellX, cellY, rotation, srcOffset, dstOffset, srcSize ) .. SYNC_KEY
					local pocketStorage = sm.terrainGeneration.loadGameStorage( syncedKey ) or {}
					FilterTileStorageTaggedObjects( pocketAssets, pocketStorage )
				end
				for _, asset in ipairs( pocketAssets ) do
					assets[#assets + 1] = asset
				end
			end
		end
	end

	return assets
end

----------------------------------------------------------------------------------------------------

function GetHarvestablesForCell( cellX, cellY, size )
	local harvestables = g_prefabHarvestables
	g_prefabHarvestables = {}

	local uid, xOffset, yOffset = GetCellTileUidAndOffset( cellX, cellY )
	if not uid:isNil() then
		local cellRotation = GetCellRotation( cellX, cellY )
		for _, harvestable in ipairs( sm.terrainTile.getHarvestablesForCell( uid, xOffset, yOffset, size ) ) do
			harvestable.pos.x, harvestable.pos.y = RotateLocal2( cellRotation, harvestable.pos.x, harvestable.pos.y, CELL_SIZE, CELL_SIZE )
			harvestable.rot = GetRotationQuat2( cellRotation ) * harvestable.rot
			harvestables[#harvestables + 1] = harvestable
		end
	else
		local caves = g_cellData.caves[cellY][cellX]
		for i = 1, #caves do
			local tileUid, rotation, srcOffset, dstOffset, srcSize = DecodeCaveCellData( caves[i] )
			for _, harvestable in ipairs( sm.terrainTile.getHarvestablesForCell( tileUid, srcOffset.x, srcOffset.y, size ) ) do
				harvestable.pos.x, harvestable.pos.y = RotateLocal2( rotation, harvestable.pos.x, harvestable.pos.y, CELL_SIZE, CELL_SIZE )
				harvestable.pos = harvestable.pos + dstOffset * CHUNK_SIZE
				harvestable.rot = GetRotationQuat2( rotation ) * harvestable.rot
				harvestable.removeIfLevitating = false
				harvestables[#harvestables + 1] = harvestable
			end
		end

		local pockets = g_cellData.pockets[cellY][cellX]
		for i = 1, #pockets do
			local tileUid, rotation, srcOffset, dstOffset, srcSize = DecodePocketCellData( pockets[i] )
			for _, harvestable in ipairs( sm.terrainTile.getHarvestablesForCell( tileUid, 0, 0, size ) ) do
				harvestable.pos.x, harvestable.pos.y = RotateLocal2( rotation, harvestable.pos.x - srcOffset.x * CHUNK_SIZE, harvestable.pos.y - srcOffset.y * CHUNK_SIZE, srcSize.x * CHUNK_SIZE, srcSize.y * CHUNK_SIZE )
				harvestable.pos = harvestable.pos + dstOffset * CHUNK_SIZE
				if math.floor( harvestable.pos.x / CELL_SIZE ) == 0 and math.floor( harvestable.pos.y / CELL_SIZE ) == 0 then
					harvestable.rot = GetRotationQuat2( rotation ) * harvestable.rot
					harvestable.removeIfLevitating = false
					harvestables[#harvestables + 1] = harvestable
				end
			end
		end
	end
	return harvestables
end

----------------------------------------------------------------------------------------------------

function GetKinematicsForCell( cellX, cellY, size, terrainTaskTick )
	local kinematics = g_prefabKinematics
	g_prefabKinematics = {}

	local uid, tileCellOffsetX, tileCellOffsetY = GetCellTileUidAndOffset( cellX, cellY )
	if not uid:isNil() then
		-- If there is a tile uid, then there shouldn't be any caves or pockets.
		-- Load kinematics from cell
		local cellRotation = GetCellRotation( cellX, cellY )
		local tileStorageKey = CalculateTileStorageKey( g_world.id, cellX, cellY )
		local tileStorage = sm.terrainGeneration.loadGameStorage( tileStorageKey )
		for _, kinematic in ipairs( sm.terrainTile.getKinematicsForCell( uid, tileCellOffsetX, tileCellOffsetY, size ) ) do
			local rx, ry = RotateLocal2( cellRotation, kinematic.pos.x, kinematic.pos.y, CELL_SIZE, CELL_SIZE )
			kinematic.pos = sm.vec3.new( rx, ry, kinematic.pos.z )
			kinematic.rot = GetRotationQuat2( cellRotation ) * kinematic.rot
			local worldPos = sm.vec3.new( cellX * CELL_SIZE, cellY * CELL_SIZE, 0 ) + kinematic.pos
			LoadKinematicFromStorage( kinematic, tileStorage, worldPos, terrainTaskTick, g_world, cellX, cellY )
			kinematics[#kinematics + 1] = kinematic
		end

		if #kinematics > 0 then
			local syncedKey = CalculateTileStorageKey( g_world.id, cellX, cellY ) .. SYNC_KEY
			if syncedKey then
				local syncedStorage = sm.terrainGeneration.loadGameStorage( syncedKey ) or {}
				FilterTileStorageTaggedObjects( kinematics, syncedStorage )
			end
		end
	else
		local caves = g_cellData.caves[cellY][cellX]
		for i = 1, #caves do
			local tileUid, rotation, srcOffset, dstOffset, srcSize = DecodeCaveCellData( caves[i] )
			local caveStorageKey = CalculateCaveTileStorageKey( g_world.id, cellX, cellY, rotation, srcOffset, dstOffset )
			local caveStorage = sm.terrainGeneration.loadGameStorage( caveStorageKey )
			local caveKinematics = {}
			for _, kinematic in ipairs( sm.terrainTile.getKinematicsForCell( tileUid, srcOffset.x, srcOffset.y, size ) ) do
				kinematic.pos.x, kinematic.pos.y = RotateLocal2( rotation, kinematic.pos.x, kinematic.pos.y, CELL_SIZE, CELL_SIZE )
				local clamped = false
				if kinematic.pos.z < 0 then
					kinematic.pos.z = 0
					clamped = true
				elseif kinematic.pos.z > srcSize.z * CHUNK_SIZE then
					kinematic.pos.z = srcSize.z * CHUNK_SIZE
					clamped = true
				end
				kinematic.pos = kinematic.pos + dstOffset * CHUNK_SIZE
				kinematic.rot = GetRotationQuat2( rotation ) * kinematic.rot
				kinematic.removeIfLevitating = false
				local worldPos = sm.vec3.new( cellX * CELL_SIZE, cellY * CELL_SIZE, 0 ) + kinematic.pos
				if clamped then
					sm.log.warning( "World " .. tostring( g_world.id ) .. ": Kinematic at " .. tostring( worldPos ) .. " in cave tile at cell (" .. tostring( cellX ) .. ", " .. tostring( cellY ) .. ") was clamped to fit within cave bounds." )
				end
				LoadKinematicFromStorage( kinematic, caveStorage, worldPos, terrainTaskTick, g_world, cellX, cellY )
				caveKinematics[#caveKinematics + 1] = kinematic
			end
			if #caveKinematics > 0 then
				local syncedKey = caveStorageKey .. SYNC_KEY
				local syncedStorage = sm.terrainGeneration.loadGameStorage( syncedKey ) or {}
				FilterTileStorageTaggedObjects( caveKinematics, syncedStorage )
			end
			for _, kinematic in ipairs( caveKinematics ) do
				kinematics[#kinematics + 1] = kinematic
			end
		end
		
		local pockets = g_cellData.pockets[cellY][cellX]
		for i = 1, #pockets do
			local tileUid, rotation, srcOffset, dstOffset, srcSize = DecodePocketCellData( pockets[i] )
			local pocketStorageKey = CalculatePocketTileStorageKey( g_world.id, cellX, cellY, rotation, srcOffset, dstOffset, srcSize )
			local pocketStorage = sm.terrainGeneration.loadGameStorage( pocketStorageKey )
			local pocketKinematics = {}
			for _, kinematic in ipairs( sm.terrainTile.getKinematicsForCell( tileUid, 0, 0, size ) ) do
				kinematic.pos.x, kinematic.pos.y = RotateLocal2( rotation, kinematic.pos.x - srcOffset.x * CHUNK_SIZE, kinematic.pos.y - srcOffset.y * CHUNK_SIZE, srcSize.x * CHUNK_SIZE, srcSize.y * CHUNK_SIZE )
				local clamped = false
				if kinematic.pos.z < 0 then
					kinematic.pos.z = 0
					clamped = true
				elseif kinematic.pos.z > srcSize.z * CHUNK_SIZE then
					kinematic.pos.z = srcSize.z * CHUNK_SIZE
					clamped = true
				end
				kinematic.pos = kinematic.pos + dstOffset * CHUNK_SIZE
				if math.floor( kinematic.pos.x / CELL_SIZE ) == 0 and math.floor( kinematic.pos.y / CELL_SIZE ) == 0 then
					kinematic.rot = GetRotationQuat2( rotation ) * kinematic.rot
					kinematic.removeIfLevitating = false
					local worldPos = sm.vec3.new( cellX * CELL_SIZE, cellY * CELL_SIZE, 0 ) + kinematic.pos
					if clamped then
						sm.log.warning( "World " .. tostring( g_world.id ) .. ": Kinematic at " .. tostring( worldPos ) .. " in pocket tile at cell (" .. tostring( cellX ) .. ", " .. tostring( cellY ) .. ") was clamped to fit within pocket bounds." )
					end
					LoadKinematicFromStorage( kinematic, pocketStorage, worldPos, terrainTaskTick, g_world, cellX, cellY )
					pocketKinematics[#pocketKinematics + 1] = kinematic
				end
			end
			if #pocketKinematics > 0 then
				local syncedKey = pocketStorageKey .. SYNC_KEY
				local syncedStorage = sm.terrainGeneration.loadGameStorage( syncedKey ) or {}
				FilterTileStorageTaggedObjects( pocketKinematics, syncedStorage )
			end
			for _, kinematic in ipairs( pocketKinematics ) do
				kinematics[#kinematics + 1] = kinematic
			end
		end
	end

	return kinematics
end

----------------------------------------------------------------------------------------------------

function GetNodesForCell( cellX, cellY )
	local nodes = g_prefabNodes
	g_prefabNodes = {}

	local uid, xOffset, yOffset = GetCellTileUidAndOffset( cellX, cellY )
	if not uid:isNil() then
		local cellRotation = GetCellRotation( cellX, cellY )
		for _, node in ipairs( sm.terrainTile.getNodesForCell( uid, xOffset, yOffset ) ) do
			node.pos.x, node.pos.y = RotateLocal2( cellRotation, node.pos.x, node.pos.y, CELL_SIZE, CELL_SIZE )
			node.pos.z = WaterNodeGridOffset( node, node.pos.z )
			node.rot = GetRotationQuat2( cellRotation ) * node.rot
			nodes[#nodes + 1] = node
		end
	else
		local caves = g_cellData.caves[cellY][cellX]
		for i = 1, #caves do
			local tileUid, rotation, srcOffset, dstOffset, srcSize = DecodeCaveCellData( caves[i] )
			for _, node in ipairs( sm.terrainTile.getNodesForCell( tileUid, srcOffset.x, srcOffset.y ) ) do
				node.pos.x, node.pos.y = RotateLocal2( rotation, node.pos.x, node.pos.y, CELL_SIZE, CELL_SIZE )
				node.pos = node.pos + dstOffset * CHUNK_SIZE
				node.rot = GetRotationQuat2( rotation ) * node.rot
				if valueExists( node.tags, "SPAWNABLE_UNIT" ) and ( node.params == nil or not node.params.manualSpawn ) then
					node.params = node.params or {}
					node.params.manualSpawn = true -- Marks all spawnable units in pockets as spawned by trigger
					node.params.triggerName = "Auto"
				end
				nodes[#nodes + 1] = node
			end
		end

		local pockets = g_cellData.pockets[cellY][cellX]
		for i = 1, #pockets do
			local tileUid, rotation, srcOffset, dstOffset, srcSize = DecodePocketCellData( pockets[i] )
			for _, node in ipairs( sm.terrainTile.getNodesForCell( tileUid, 0, 0 ) ) do
				node.pos.x, node.pos.y = RotateLocal2( rotation, node.pos.x - srcOffset.x * CHUNK_SIZE, node.pos.y - srcOffset.y * CHUNK_SIZE, srcSize.x * CHUNK_SIZE, srcSize.y * CHUNK_SIZE )
				node.pos = node.pos + dstOffset * CHUNK_SIZE
				if math.floor( node.pos.x / CELL_SIZE ) == 0 and math.floor( node.pos.y / CELL_SIZE ) == 0 then
					node.rot = GetRotationQuat2( rotation ) * node.rot
					if valueExists( node.tags, "SPAWNABLE_UNIT" ) and ( node.params == nil or not node.params.manualSpawn ) then
						node.params = node.params or {}
						node.params.manualSpawn = true -- Marks all spawnable units in pockets as spawned by trigger
						node.params.triggerName = "Auto"
					end
					nodes[#nodes + 1] = node
				end
			end
		end
	end

	local spawners = g_cellData.spawners[cellY][cellX]
	for i = 1, #spawners do
		local node = spawners[i]
		nodes[#nodes + 1] = node
	end






	removeFromArray( nodes, function( val ) return val.tags[1] == "EFFECT" and val.params.effect.name == "DebugText" end )

	return nodes
end

----------------------------------------------------------------------------------------------------

function GetDecalsForCell( cellX, cellY )
	local decals = g_prefabDecals
	g_prefabDecals = {}

	local uid, xOffset, yOffset = GetCellTileUidAndOffset( cellX, cellY )
	if not uid:isNil() then
		local cellRotation = GetCellRotation( cellX, cellY )
		for _, decal in ipairs( sm.terrainTile.getDecalsForCell( uid, xOffset, yOffset ) ) do
			decal.pos.x, decal.pos.y = RotateLocal2( cellRotation, decal.pos.x, decal.pos.y, CELL_SIZE, CELL_SIZE )
			decal.rot = GetRotationQuat2( cellRotation ) * decal.rot
			decals[#decals + 1] = decal
		end

		if #decals > 0 then
			local syncedKey = CalculateTileStorageKey( g_world.id, cellX, cellY ) .. SYNC_KEY
			if syncedKey then
				local tileStorage = sm.terrainGeneration.loadGameStorage( syncedKey ) or {}
				FilterTileStorageTaggedObjects( decals, tileStorage )
			end
		end
	else
		local caves = g_cellData.caves[cellY][cellX]
		for i = 1, #caves do
			local tileUid, rotation, srcOffset, dstOffset, srcSize = DecodeCaveCellData( caves[i] )
			local caveDecals = {}
			for _, decal in ipairs( sm.terrainTile.getDecalsForCell( tileUid, srcOffset.x, srcOffset.y ) ) do
				decal.pos.x, decal.pos.y = RotateLocal2( rotation, decal.pos.x, decal.pos.y, CELL_SIZE, CELL_SIZE )
				decal.pos = decal.pos + dstOffset * CHUNK_SIZE
				decal.rot = GetRotationQuat2( rotation ) * decal.rot
				caveDecals[#caveDecals + 1] = decal
			end
			if #caveDecals > 0 then
				local syncedKey = CalculateCaveTileStorageKey( g_world.id, cellX, cellY, rotation, srcOffset, dstOffset ) .. SYNC_KEY
				local caveStorage = sm.terrainGeneration.loadGameStorage( syncedKey ) or {}
				FilterTileStorageTaggedObjects( caveDecals, caveStorage )
			end
			for _, decal in ipairs( caveDecals ) do
				decals[#decals + 1] = decal
			end
		end

		local pockets = g_cellData.pockets[cellY][cellX]
		for i = 1, #pockets do
			local tileUid, rotation, srcOffset, dstOffset, srcSize = DecodePocketCellData( pockets[i] )
			local pocketDecals = {}
			for _, decal in ipairs( sm.terrainTile.getDecalsForCell( tileUid, 0, 0 ) ) do
				decal.pos.x, decal.pos.y = RotateLocal2( rotation, decal.pos.x - srcOffset.x * CHUNK_SIZE, decal.pos.y - srcOffset.y * CHUNK_SIZE, srcSize.x * CHUNK_SIZE, srcSize.y * CHUNK_SIZE )
				decal.pos = decal.pos + dstOffset * CHUNK_SIZE
				if math.floor( decal.pos.x / CELL_SIZE ) == 0 and math.floor( decal.pos.y / CELL_SIZE ) == 0 then
					decal.rot = GetRotationQuat2( rotation ) * decal.rot
					pocketDecals[#pocketDecals + 1] = decal
				end
			end
			if #pocketDecals > 0 then
				local syncedKey = CalculatePocketTileStorageKey( g_world.id, cellX, cellY, rotation, srcOffset, dstOffset, srcSize ) .. SYNC_KEY
				local pocketStorage = sm.terrainGeneration.loadGameStorage( syncedKey ) or {}
				FilterTileStorageTaggedObjects( pocketDecals, pocketStorage )
			end
			for _, decal in ipairs( pocketDecals ) do
				decals[#decals + 1] = decal
			end
		end
	end

	return decals
end

----------------------------------------------------------------------------------------------------

function GetCreationsForCell( cellX, cellY )
	local creations = g_prefabCreations
	g_prefabCreations = {}

	local uid, xOffset, yOffset = GetCellTileUidAndOffset( cellX, cellY )
	if not uid:isNil() then
		local cellRotation = GetCellRotation( cellX, cellY )
		for _, creation in ipairs( sm.terrainTile.getCreationsForCell( uid, xOffset, yOffset ) ) do
			creation.pos.x, creation.pos.y = RotateLocal2( cellRotation, creation.pos.x, creation.pos.y, CELL_SIZE, CELL_SIZE )
			creation.rot = GetRotationQuat2( cellRotation ) * creation.rot
			creations[#creations + 1] = creation
		end
	else
		local caves = g_cellData.caves[cellY][cellX]
		for i = 1, #caves do
			local tileUid, rotation, srcOffset, dstOffset, srcSize = DecodeCaveCellData( caves[i] )
			for _, creation in ipairs( sm.terrainTile.getCreationsForCell( tileUid, srcOffset.x, srcOffset.y ) ) do
				creation.pos.x, creation.pos.y = RotateLocal2( rotation, creation.pos.x, creation.pos.y, CELL_SIZE, CELL_SIZE )
				creation.pos = creation.pos + dstOffset * CHUNK_SIZE
				creation.rot = GetRotationQuat2( rotation ) * creation.rot
				creations[#creations + 1] = creation
			end
		end

		local pockets = g_cellData.pockets[cellY][cellX]
		for i = 1, #pockets do
			local tileUid, rotation, srcOffset, dstOffset, srcSize = DecodePocketCellData( pockets[i] )
			for _, creation in ipairs( sm.terrainTile.getCreationsForCell( tileUid, 0, 0 ) ) do
				creation.pos.x, creation.pos.y = RotateLocal2( rotation, creation.pos.x - srcOffset.x * CHUNK_SIZE, creation.pos.y - srcOffset.y * CHUNK_SIZE, srcSize.x * CHUNK_SIZE, srcSize.y * CHUNK_SIZE )
				creation.pos = creation.pos + dstOffset * CHUNK_SIZE
				if math.floor( creation.pos.x / CELL_SIZE ) == 0 and math.floor( creation.pos.y / CELL_SIZE ) == 0 then
					creation.rot = GetRotationQuat2( rotation ) * creation.rot
					creations[#creations + 1] = creation
				end
			end
		end
	end

	return creations
end

function GetTagsForCell( cellX, cellY )
	return {}
end

----------------------------------------------------------------------------------------------------

local addHullBox = function( hull, box, marginMin, marginMax )
	hull[#hull + 1] = sm.vec3.new( box.min.x + marginMin, box.min.y + marginMin, box.min.z + marginMin ) * CHUNK_SIZE
	hull[#hull + 1] = sm.vec3.new( box.max.x + marginMax, box.min.y + marginMin, box.min.z + marginMin ) * CHUNK_SIZE
	hull[#hull + 1] = sm.vec3.new( box.min.x + marginMin, box.max.y + marginMax, box.min.z + marginMin ) * CHUNK_SIZE
	hull[#hull + 1] = sm.vec3.new( box.max.x + marginMax, box.max.y + marginMax, box.min.z + marginMin ) * CHUNK_SIZE
	hull[#hull + 1] = sm.vec3.new( box.min.x + marginMin, box.min.y + marginMin, box.max.z + marginMax ) * CHUNK_SIZE
	hull[#hull + 1] = sm.vec3.new( box.max.x + marginMax, box.min.y + marginMin, box.max.z + marginMax ) * CHUNK_SIZE
	hull[#hull + 1] = sm.vec3.new( box.min.x + marginMin, box.max.y + marginMax, box.max.z + marginMax ) * CHUNK_SIZE
	hull[#hull + 1] = sm.vec3.new( box.max.x + marginMax, box.max.y + marginMax, box.max.z + marginMax ) * CHUNK_SIZE



end
local addHullPoints = function( hull, points )
	for _, point in ipairs( points ) do
		hull[#hull + 1] = point * CHUNK_SIZE
	end
end

function GetVoxelTerrainForCell( cellX, cellY )
	local xMin = ( g_cellData.bounds.xMin ) * CHUNKS_PER_CELL + BedrockPadding
	local xMax = ( g_cellData.bounds.xMax + 1 ) * CHUNKS_PER_CELL - BedrockPadding
	local yMin = ( g_cellData.bounds.yMin ) * CHUNKS_PER_CELL + BedrockPadding
	local yMax = ( g_cellData.bounds.yMax + 1 ) * CHUNKS_PER_CELL - BedrockPadding

	if g_depth == 2 then
		local pad = 0 -- Padding
		do
			local hull = {}
			addHullBox( hull, { min = sm.vec3.new( -4, -16, 4 ), max = sm.vec3.new( 8, 4, 6 ) }, -pad, pad )
			sm.voxelTerrainCell.setMaterialConvexHull( hull, 0.0, 2, sm.voxelTerrainCell.voxelFilter.material7 )
		end
		do
			local hull = {}
			addHullBox( hull, { min = sm.vec3.new( -4, -24, 2 ), max = sm.vec3.new( 12, -16, 6 ) }, -pad, pad )
			sm.voxelTerrainCell.setMaterialConvexHull( hull, 0.0, 2, sm.voxelTerrainCell.voxelFilter.material7 )
		end
		do
			local hull = {}
			addHullBox( hull, { min = sm.vec3.new( -4, -48, 2 ), max = sm.vec3.new( 8, -24, 6 ) }, -pad, pad )
			sm.voxelTerrainCell.setMaterialConvexHull( hull, 0.0, 2, sm.voxelTerrainCell.voxelFilter.material7 )
		end
	elseif g_depth == 4 or g_depth == 6 then
		local noiseFrequency = 0.1
		local noiseIntensity = 2
		local margin = ( 1 + noiseIntensity ) / 16 -- Padding
		if g_depth == 4 then
			local boxWorld1 = { min = sm.vec3.new( xMin, -24, 0 ), max = sm.vec3.new( xMax, -4, 8 ) }
			local boxWorld2 = { min = sm.vec3.new( -4, yMin, 0 ), max = sm.vec3.new( 8, yMax - 4, 8 ) }
			local hull = {}
			addHullBox( hull, boxWorld1, margin, -margin )
			addHullBox( hull, boxWorld2, margin, -margin )
			sm.voxelTerrainCell.setMaterialConvexHull( hull, 0.0, 2, sm.voxelTerrainCell.voxelFilter.material7, noiseFrequency, noiseIntensity )
		end
		if g_depth == 6 then
			local boxWorld1 = { min = sm.vec3.new( xMin, -24, 0 ), max = sm.vec3.new( xMax, -4, 8 ) }
			local boxWorld2 = { min = sm.vec3.new( -4, yMin, 0 ), max = sm.vec3.new( 8, yMax - 4, 8 ) }
			local hull = {}
			addHullBox( hull, boxWorld1, margin, -margin )
			addHullBox( hull, boxWorld2, margin, -margin )
			sm.voxelTerrainCell.setMaterialConvexHull( hull, 0.0, 2, sm.voxelTerrainCell.voxelFilter.material7, noiseFrequency, noiseIntensity )
		end
		do
			local height = 4
			local topMin = -2
			local topMax = 6
			local botMin = topMin - height
			local botMax = topMax + height
			local ptsElevator = {
				sm.vec3.new( topMin, topMin, height ),
				sm.vec3.new( topMax, topMin, height ),
				sm.vec3.new( topMax, topMax, height ),
				sm.vec3.new( topMin, topMax, height ),
				sm.vec3.new( botMin, botMin, 0 ),
				sm.vec3.new( botMax, botMin, 0 ),
				sm.vec3.new( botMax, botMax, 0 ),
				sm.vec3.new( botMin, botMax, 0 ),
			}
			local hull = {}
			addHullPoints( hull, ptsElevator )
			for _, point in ipairs( hull ) do
				point.z = point.z - 1
			end
			sm.voxelTerrainCell.setMaterialConvexHull( hull, 0.0, 7, sm.voxelTerrainCell.voxelFilter.material2 )
		end
	end











	local uid, xOffset, yOffset = GetCellTileUidAndOffset( cellX, cellY )
	if not uid:isNil() then
		sm.voxelTerrainCell.copyTileCellVoxels( uid, xOffset, yOffset, GetCellRotation( cellX, cellY ) )
	end

	local caves = g_cellData.caves[cellY][cellX]
	for i = 1, #caves do
		local tileUid, rotation, srcOffset, dstOffset, srcSize = DecodeCaveCellData( caves[i] )
		sm.voxelTerrainCell.copyTileCellVoxelsOnlyAirAndMasked( tileUid, srcOffset.x, srcOffset.y, rotation, sm.vec3.zero(), dstOffset, srcSize, bit.bnot( sm.voxelTerrainCell.voxelFilter.material0 ) )
	end

	local pockets = g_cellData.pockets[cellY][cellX]
	for i = 1, #pockets do
		local tileUid, rotation, srcOffset, dstOffset, srcSize = DecodePocketCellData( pockets[i] )
		sm.voxelTerrainCell.copyTileCellVoxelsOnlyAirAndMasked( tileUid, 0, 0, rotation, srcOffset, dstOffset, srcSize, bit.bnot( sm.voxelTerrainCell.voxelFilter.material0 ) )
	end

	if g_cellData.tunnels then
		if g_cellTunnelIndices then
			if g_cellTunnelIndices[cellY] and g_cellTunnelIndices[cellY][cellX] then
				local cellTunnels = g_cellTunnelIndices[cellY][cellX]
				for _, idxTunnel in ipairs( cellTunnels ) do
					local tunnel = g_cellData.tunnels[idxTunnel]
					assert( tunnel )
					CarveTunnel( idxTunnel, tunnel )
				end
			end
		else
			for idxTunnel, tunnel in ipairs( g_cellData.tunnels ) do
				assert( tunnel )
				CarveTunnel( idxTunnel, tunnel )
			end
		end
	end















end

----------------------------------------------------------------------------------------------------

function GetCellGroups()
	if g_cellData.groupId then
		return g_cellData.groupId
	end
	return {}
end

function GetTunnels()
	if g_cellData.tunnels then
		return g_cellData.tunnels
	end
	return {}
end


----------------------------------------------------------------------------------------------------
-- Tile Reader Path Getter
----------------------------------------------------------------------------------------------------

function GetTilePath( uid )
	local path = GetPath( uid )
	if path then
		return path
	end
	return "$SURVIVAL_DATA/Terrain/Tiles/Error_1024.tile"
end

---------------------------------------------------------------------------------------------------
-- Util
---------------------------------------------------------------------------------------------------

local CellNodeCache = {}

function GetNodesForCellWithCache( uid, tileCellOffsetX, tileCellOffsetY )
	local nodes
	local hash = sm.util.hash( uid, tileCellOffsetX, tileCellOffsetY )
	if CellNodeCache[hash] then
		nodes = CellNodeCache[hash]
	else
		nodes = sm.terrainTile.getNodesForCell( uid, tileCellOffsetX, tileCellOffsetY )
		CellNodeCache[hash] = nodes
	end
	return nodes
end

function UpdateLocationStorage()
	if g_generatorIndex == 0 and sm.isHost then

-- find location and quest marker nodes, prints lines to use in DEPTH_NODE_LOCATIONS and DEPTH_QUEST_MARKERS tables

























		-- Location storage (version-gated)
		local locationStorage = sm.terrainGeneration.loadGameStorage( STORAGE_CHANNEL_LOCATIONS ) or { [g_world.id] = { version = 0 } }
		if locationStorage[g_world.id] == nil then
			locationStorage[g_world.id] = { version = 0 }
		end
		if locationStorage[g_world.id].version ~= LOCATION_STORAGE_VERSION then
			locationStorage[g_world.id] = { version = LOCATION_STORAGE_VERSION }

			local nodeLocations = DEPTH_NODE_LOCATIONS[g_depth] or {}

			function AddLocation( name, tileSize, pos, cellX, cellY )
				assert(cellX)
				assert(cellY)
				local minCellX, minCellY = GetTileMinCell( cellX, cellY, tileSize )
				local rx, ry = RotateLocal( cellX, cellY, pos.x, pos.y, tileSize * CELL_SIZE )
				local x = (cellX - (cellX - minCellX)) * CELL_SIZE + rx
				local y = (cellY - (cellY - minCellY)) * CELL_SIZE + ry
				local z = pos.z
				locationStorage[name] = { pos = sm.vec3.new( x, y, z ), world = g_world }
			end

			for cellY = g_cellData.bounds.yMin, g_cellData.bounds.yMax do
				for cellX = g_cellData.bounds.xMin, g_cellData.bounds.xMax do
					local uid = GetCellTileUid( cellX, cellY )

					for index, search in ipairs( nodeLocations ) do
						if search.uuid == uid then
							AddLocation( search.name, GetSize( uid ), search.pos, cellX, cellY )
							table.remove( nodeLocations, index )
							break
						end
					end
				end
			end

			sm.terrainGeneration.saveGameStorage( STORAGE_CHANNEL_LOCATIONS, locationStorage )
		end

		-- Quest marker precaching
		local questMarkerStorage = sm.terrainGeneration.loadGameStorage( STORAGE_CHANNEL_PRECACHED_MARKERS ) or {}
		local questMarkerVersions = questMarkerStorage["versions"] or {}
		-- Treat existing marker data without version info as current version (preserves data from prior release)
		if questMarkerStorage[g_world.id] ~= nil and questMarkerVersions[g_world.id] == nil then
			questMarkerVersions[g_world.id] = QUESTMARKER_STORAGE_VERSION
		end
		if questMarkerVersions[g_world.id] ~= QUESTMARKER_STORAGE_VERSION then
			local questMarkerNodes = DEPTH_QUEST_MARKERS[g_depth] or {}
			local questMarkers = {}

			function AddQuestMarker( name, tileSize, pos, cellX, cellY, isSideQuest )
				assert(cellX)
				assert(cellY)
				local minCellX, minCellY = GetTileMinCell( cellX, cellY, tileSize )
				local rx, ry = RotateLocal( cellX, cellY, pos.x, pos.y, tileSize * CELL_SIZE )
				local x = (cellX - (cellX - minCellX)) * CELL_SIZE + rx
				local y = (cellY - (cellY - minCellY)) * CELL_SIZE + ry
				local z = pos.z
				questMarkers[#questMarkers+1] = { pos = sm.vec3.new( x, y, z ), world = g_world, params = { name = name, isSideQuest = isSideQuest } }
			end

			for cellY = g_cellData.bounds.yMin, g_cellData.bounds.yMax do
				for cellX = g_cellData.bounds.xMin, g_cellData.bounds.xMax do
					local uid = GetCellTileUid( cellX, cellY )

					for index, search in reverse_ipairs( questMarkerNodes ) do
						if search.uuid == uid then
							AddQuestMarker( search.name, GetSize( uid ), search.pos, cellX, cellY, search.isSideQuest )
							table.remove( questMarkerNodes, index )
						end
					end
				end
			end

			questMarkerStorage["versions"] = questMarkerVersions
			questMarkerVersions[g_world.id] = QUESTMARKER_STORAGE_VERSION
			questMarkerStorage[g_world.id] = questMarkers
			sm.terrainGeneration.saveGameStorage( STORAGE_CHANNEL_PRECACHED_MARKERS, questMarkerStorage )
		end
	end
end

function UpdateTunnelCulling()
	if g_generatorIndex == 0 then
		if g_cellData.tunnels then
			g_cellTunnelIndices = {}
			TunnelCellCulling( g_cellData.tunnels, g_cellTunnelIndices, TUNNEL_MAX_WIDTH )
			sm.terrainGeneration.setTempData( "cellTunnelIndices", g_cellTunnelIndices )
		end
	else
		g_cellTunnelIndices = sm.terrainGeneration.getTempData( "cellTunnelIndices" )
	end
end