----------------------------------------------------------------------------------------------------
-- Data
----------------------------------------------------------------------------------------------------

local f_poiTiles = {}

----------------------------------------------------------------------------------------------------

function getPoiTileId( poiType, index )
	return f_poiTiles[poiType][index]
end

function getRandomPoiTileId( poiType, noise )
	local tileCount = 0
	if f_poiTiles[poiType] then
		tileCount = #f_poiTiles[poiType]
	end

	if tileCount == 0 then
		return ERROR_TILE_UUID, 0 --error tile
	end

	return f_poiTiles[poiType][noise % tileCount + 1]
end

----------------------------------------------------------------------------------------------------

local function addPoiTile( poiType, path, terrainType )
	if f_poiTiles[poiType] == nil then
		f_poiTiles[poiType] = {}
	end
	f_poiTiles[poiType][#f_poiTiles[poiType] + 1] = AddTile( nil, path, terrainType, poiType )
end

local function addPoiTileLegacy( poiType, index, path, terrainType )
	if f_poiTiles[poiType] == nil then
		f_poiTiles[poiType] = {}
	end
	local legacyId = poiType * 100 + index
	f_poiTiles[poiType][#f_poiTiles[poiType] + 1] = AddTile( legacyId, path, terrainType, poiType )
end

local function addPoiTileRetired( poiType, index, path, terrainType )
	local legacyId = poiType * 100 + index
	AddTile( legacyId, path, terrainType, poiType )
end

----------------------------------------------------------------------------------------------------

function initPoiTiles()
	-- Add new variations at the end if lists for old world compability.

	-- Notes:
	-- 	addPoiTile is used for new tiles
	-- 	addPoiTileLegacy does AddLegacyUpgrade internally and is used for old tiles that existed before update 0.6.0 and are still added to new worlds
	--  addPoiTileRetired translates legacyId to tile uuid and is used for tiles that are not used any more but exists in old worlds (before update 0.6.0)
	-- 	Direct calls to AddLegacyUpgrade remaps legacyId tiles to uuid tiles. This effectively replaces tiles that we used to load for old save data to load new/different ones!

	-- Starting area
	addPoiTileLegacy( POI_CRASHSITE_AREA, 1, "$SURVIVAL_DATA/Terrain/Tiles/start_area/SurvivalStartArea_CrashedShip_01.tile" )
	addPoiTileLegacy( POI_CRASHSITE_AREA, 2, "$SURVIVAL_DATA/Terrain/Tiles/start_area/SurvivalStartArea_CrashedTower_01.tile" )
	addPoiTileLegacy( POI_CRASHSITE_AREA, 3, "$SURVIVAL_DATA/Terrain/Tiles/start_area/SurvivalStartArea_BigRuin_01.tile" )
	addPoiTileLegacy( POI_CRASHSITE_AREA, 4, "$SURVIVAL_DATA/Terrain/Tiles/start_area/SurvivalStartArea_CrashedTowerCliff_01.tile" )
	addPoiTileLegacy( POI_CRASHSITE_AREA, 5, "$SURVIVAL_DATA/Terrain/Tiles/start_area/SurvivalStartArea_SmallRuin_A_01.tile" )
	addPoiTileLegacy( POI_CRASHSITE_AREA, 6, "$SURVIVAL_DATA/Terrain/Tiles/start_area/SurvivalStartArea_SmallRuin_B_01.tile" )
	addPoiTileLegacy( POI_CRASHSITE_AREA, 7, "$SURVIVAL_DATA/Terrain/Tiles/start_area/SurvivalStartArea_SmallRuin_C_01.tile" )
	addPoiTileLegacy( POI_CRASHSITE_AREA, 8, "$SURVIVAL_DATA/Terrain/Tiles/start_area/SurvivalStartArea_SmallRuin_D_01.tile" )
	addPoiTile( POI_CRASHSITE_AREA, "$SURVIVAL_DATA/Terrain/Tiles/start_area/SurvivalStartArea_BossMountain_01.tile" )
	addPoiTile( POI_CRASHSITE_AREA, "$SURVIVAL_DATA/Terrain/Tiles/start_area/SurvivalStartArea_CrashedShip_01_NEW.tile" )
	addPoiTile( POI_CRASHSITE_AREA, "$SURVIVAL_DATA/Terrain/Tiles/start_area/SurvivalStartArea_CrashedTower_01_NEW.tile" )
	addPoiTile( POI_CRASHSITE_AREA, "$SURVIVAL_DATA/Terrain/Tiles/start_area/SurvivalStartArea_BigRuin_01_NEW.tile" )


	-- Unique (MEADOW)
	addPoiTile( POI_HIDEOUT_XL, "$SURVIVAL_DATA/Terrain/Tiles/poi/Hideout_512_01.tile" )
	addPoiTileRetired( POI_HIDEOUT_XL, 1, "$SURVIVAL_DATA/Terrain/Tiles/legacy/Hideout_512_01_legacy.tile" )

	addPoiTile( POI_MEADOW_GROWLAB_SILODISTRICT_XL, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/Minidungeon_OverworldEntrance_Chemical_512_01.tile" )
	addPoiTileRetired( POI_MEADOW_GROWLAB_SILODISTRICT_XL, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/SiloDistrict_512_01.tile" )

	addPoiTile( POI_RUINCITY_XL, "$SURVIVAL_DATA/Terrain/Tiles/poi/RuinCity_512_01_NEW.tile" )
	addPoiTileRetired( POI_RUINCITY_XL, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/RuinCity_512_01.tile" )

	addPoiTile( POI_BUILDERQUEST_RESOURCECAR, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_ResourceCar_64_01.tile" )

	addPoiTileLegacy( POI_CRASHEDSHIP_LARGE, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/CrashedShip_256_01.tile" )

	addPoiTileLegacy( POI_CAMP_LARGE, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/CampingSpot_WaterFront_256_01.tile" )

	addPoiTile( POI_BUNK_BURIAL_QUEST_MEDIUM, "$SURVIVAL_DATA/Terrain/Tiles/poi/BunkInvestigationQuest_128_01.tile" )
	addPoiTileRetired( POI_BUNK_BURIAL_QUEST_MEDIUM, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/SleepCapsuleBurial_128_01.tile" )

	addPoiTile( POI_LABYRINTH_MEDIUM, "$SURVIVAL_DATA/Terrain/Tiles/poi/HayBaleLabyrinth_128_01_NEW.tile" )
	addPoiTileRetired( POI_LABYRINTH_MEDIUM, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/HayBaleLabyrinth_128_01.tile" )

	-- Special (MEADOW)
	addPoiTileLegacy( POI_MECHANICSTATION_MEDIUM, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/MechanicStation_128_01.tile" )

	addPoiTile( POI_MECHANICSTATION_QUEST_MEDIUM, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/MechanicStation_QuestTile_01.tile" )

	addPoiTileLegacy( POI_PACKINGSTATIONVEG_MEDIUM, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/PackingStation_Vegetable_128_01.tile" )

	addPoiTileLegacy( POI_PACKINGSTATIONFRUIT_MEDIUM, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/PackingStation_Fruit_128_01.tile" ) --NOTE: Legacy index is always 2 for this poi type

	-- Builderguide
	--EASY
	addPoiTile( POI_BUILDERQUEST_WOCHOUSE, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Wochouse_64_01.tile" )
	addPoiTile( POI_BUILDERQUEST_CARDBOARDPOOP, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Cardboardpoop_64_01.tile" )
	addPoiTile( POI_BURNTFOREST_BUILDERQUEST_TOTEBOTKEY, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Totebotkey_64_01.tile" )
	addPoiTile( POI_FIELD_BUILDERQUEST_CORNHEART, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Cornheart_64_01.tile" )
	addPoiTile( POI_FIELD_BUILDERQUEST_COZYBED, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Cozybed_64_01.tile" )
	addPoiTile( POI_BUILDERQUEST_XYLOPHONE, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Xylophone_64_01.tile" )
	addPoiTile( POI_BUILDERQUEST_BEESUIT, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Beesuit_64_01.tile" )

	--MEDIUM
	addPoiTile( POI_DESERT_BUILDERQUEST_BIGFAN, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Bigfan_64_01.tile" )
	addPoiTile( POI_BUILDERQUEST_CAROUSEL, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Carousel_64_01.tile" )
	addPoiTile( POI_BURNTFOREST_BUILDERQUEST_CATAPULT_MEDIUM, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Catapult_128_01.tile" )
	addPoiTile( POI_BUILDERQUEST_CROWBAR, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Crowbar_64_01.tile" )
	addPoiTile( POI_BUILDERQUEST_COMPASS, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Compass_64_01.tile" )
	addPoiTile( POI_DESERT_BUILDERQUEST_GARDEN, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Garden_64_01.tile" )
	addPoiTile( POI_FOREST_BUILDERQUEST_SAWBLADEARM, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Sawbladearm_64_01.tile" )
	addPoiTile( POI_AUTUMNFOREST_BUILDERQUEST_POPCORN, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Popcorn_64_01.tile" )
	addPoiTile( POI_AUTUMNFOREST_BUILDERQUEST_MUSICBOX_MEDIUM, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Musicbox_128_01.tile" )

	--HARD
	addPoiTile( POI_BUILDERQUEST_NICEHOUSE_MEDIUM, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Nicehouse_128_01.tile" )
	addPoiTile( POI_BUILDERQUEST_SLEDGEHAMMER_MEDIUM, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Sledgehammer_128_01.tile" )
	addPoiTile( POI_BUILDERQUEST_STEELBRIDGE_MEDIUM, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Steelbridge_128_01.tile" )
	addPoiTile( POI_BUILDERQUEST_BAGUETTE_MEDIUM, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/BuilderQuest_Baguette_128_01.tile" )

	-- Large Random
	addPoiTile( POI_WAREHOUSE2_LARGE, "$SURVIVAL_DATA/Terrain/Tiles/poi/Warehouse_Exterior_2Floors_256_01_NEW.tile" )
	addPoiTile( POI_WAREHOUSE2_LARGE, "$SURVIVAL_DATA/Terrain/Tiles/poi/Warehouse_Exterior_2Floors_256_02_NEW.tile" )
	addPoiTile( POI_WAREHOUSE2_LARGE, "$SURVIVAL_DATA/Terrain/Tiles/poi/Warehouse_Exterior_2Floors_256_03_NEW.tile" )
	addPoiTile( POI_WAREHOUSE2_LARGE, "$SURVIVAL_DATA/Terrain/Tiles/poi/Warehouse_Exterior_2Floors_256_04_NEW.tile" )
	addPoiTileRetired( POI_WAREHOUSE2_LARGE, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/Warehouse_Exterior_2Floors_256_01.tile" )
	addPoiTileRetired( POI_WAREHOUSE2_LARGE, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/Warehouse_Exterior_2Floors_256_02.tile" )
	addPoiTileRetired( POI_WAREHOUSE2_LARGE, 3, "$SURVIVAL_DATA/Terrain/Tiles/poi/Warehouse_Exterior_2Floors_256_03.tile" )
	addPoiTileRetired( POI_WAREHOUSE2_LARGE, 4, "$SURVIVAL_DATA/Terrain/Tiles/poi/Warehouse_Exterior_2Floors_256_04.tile" )

	addPoiTile( POI_WAREHOUSE3_LARGE, "$SURVIVAL_DATA/Terrain/Tiles/poi/Warehouse_Exterior_3Floors_256_01_NEW.tile" )
	addPoiTileRetired( POI_WAREHOUSE3_LARGE, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/Warehouse_Exterior_3Floors_256_01.tile" )
	addPoiTileRetired( POI_WAREHOUSE3_LARGE, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/Warehouse_Exterior_4Floors_256_01.tile" )

	addPoiTile( POI_WAREHOUSE4_LARGE, "$SURVIVAL_DATA/Terrain/Tiles/poi/Warehouse_Exterior_4Floors_256_01_NEW.tile" )

	addPoiTile( POI_WAREHOUSE4_QUEST_LARGE, "$SURVIVAL_DATA/Terrain/Tiles/poi/Warehouse_Exterior_4Floors_256_Quest.tile" )

	addPoiTileLegacy( POI_BURNTFOREST_FARMBOTSCRAPYARD_LARGE, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/FarmbotGraveyard_256_01.tile" )
	addPoiTileLegacy( POI_BURNTFOREST_FARMBOTSCRAPYARD_LARGE, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/FarmbotGraveyard_256_02.tile" )


	-- Road
	addPoiTileLegacy( POI_ROAD_KIOSK, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/Kiosk_64_01.tile" )
	addPoiTileLegacy( POI_ROAD_KIOSK, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/Kiosk_64_02.tile" )
	addPoiTileLegacy( POI_ROAD_KIOSK, 3, "$SURVIVAL_DATA/Terrain/Tiles/poi/Kiosk_64_03.tile" )
	AddLegacyUpgrade( POI_ROAD_KIOSK * 100 + 4, sm.uuid.new( "f3535095-b884-4596-a432-0aee1b5d742a" ) ) --Random_Road_64_01.tile, POI_ROAD_KIOSK was generic POI_ROAD
	AddLegacyUpgrade( POI_ROAD_KIOSK * 100 + 5, sm.uuid.new( "7281c295-9748-496b-bc1e-6efe5f5f2541" ) ) --Random_Road_64_02.tile, POI_ROAD_KIOSK was generic POI_ROAD
	AddLegacyUpgrade( POI_ROAD_KIOSK * 100 + 6, sm.uuid.new( "af25cff8-1700-4842-b6f8-b486558cfefc" ) ) --Random_Road_64_03.tile, POI_ROAD_KIOSK was generic POI_ROAD
	AddLegacyUpgrade( POI_ROAD_KIOSK * 100 + 7, sm.uuid.new( "ea30c62b-944a-4763-be94-454cd03fa218" ) ) --Random_Road_64_04.tile, POI_ROAD_KIOSK was generic POI_ROAD

	addPoiTile( POI_ROAD_SCHEMATICSTATION, "$SURVIVAL_DATA/Terrain/Tiles/poi/SchematicStation_64_01.tile" )

	addPoiTile( POI_ROAD_CHEMPOOL, "$SURVIVAL_DATA/Terrain/Tiles/poi/ChemicalPlant_Road_64_01.tile" )

	addPoiTile( POI_ROAD_RANDOM, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Road_64_01.tile" )
	addPoiTile( POI_ROAD_RANDOM, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Road_64_02.tile" )
	addPoiTile( POI_ROAD_RANDOM, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Road_64_03.tile" )
	addPoiTile( POI_ROAD_RANDOM, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Road_64_04.tile" )


	-- Meadow
	addPoiTileLegacy( POI_CAMP, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/CampingSpot_Meadow_64_01.tile" )
	addPoiTile( POI_CAMP, "$SURVIVAL_DATA/Terrain/Tiles/poi/CampingSpot_Meadow_64_02.tile" )
	addPoiTile( POI_CAMP, "$SURVIVAL_DATA/Terrain/Tiles/poi/CampingSpot_Meadow_64_03.tile" )
	addPoiTile( POI_CAMP, "$SURVIVAL_DATA/Terrain/Tiles/poi/CampingSpot_Meadow_64_04.tile" )

	addPoiTileLegacy( POI_RUIN, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Meadow_64_01.tile" )
	addPoiTileLegacy( POI_RUIN, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Meadow_64_02.tile" )
	addPoiTileLegacy( POI_RUIN, 3, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Meadow_64_03.tile" )
	addPoiTileLegacy( POI_RUIN, 4, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Meadow_64_04.tile" )
	addPoiTile( POI_RUIN, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Meadow_64_05.tile" )
	addPoiTile( POI_RUIN, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Meadow_64_06.tile" )
	addPoiTile( POI_RUIN, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Meadow_64_07.tile" )
	addPoiTile( POI_RUIN, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Meadow_64_08.tile" )
	addPoiTile( POI_RUIN, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Meadow_64_09.tile" )
	addPoiTile( POI_RUIN, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Meadow_64_10.tile" )
	addPoiTile( POI_RUIN, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Meadow_64_11.tile" )

	AddLegacyUpgrade( POI_RANDOM * 100 + 1, sm.uuid.new( "68794ad2-e70f-4f68-8dc1-4b396a927d07" ) ) --Ruin_Meadow_64_01.tile
	AddLegacyUpgrade( POI_RANDOM * 100 + 2, sm.uuid.new( "ca8cce51-4e86-4c38-b2a0-e21facb13229" ) ) --Ruin_Meadow_64_02.tile
	AddLegacyUpgrade( POI_RANDOM * 100 + 3, sm.uuid.new( "1f041ba4-4fc1-49ec-bf98-63ad8e1f1b96" ) ) --Ruin_Meadow_64_03.tile
	AddLegacyUpgrade( POI_RANDOM * 100 + 4, sm.uuid.new( "240b28e9-e298-4306-8d77-aca4b2581670" ) ) --Ruin_Meadow_64_04.tile
	addPoiTileLegacy( POI_RANDOM, 5, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Meadow_64_01.tile" )
	addPoiTileLegacy( POI_RANDOM, 6, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Meadow_64_02.tile" )
	addPoiTileLegacy( POI_RANDOM, 7, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Meadow_64_03.tile" )
	addPoiTileLegacy( POI_RANDOM, 8, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Meadow_64_04.tile" )
	addPoiTileLegacy( POI_RANDOM, 9, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Meadow_64_05.tile" )

	-- Meadow medium
	addPoiTileLegacy( POI_RUIN_MEDIUM, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Meadow_128_01.tile" )
	addPoiTileLegacy( POI_RUIN_MEDIUM, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Meadow_128_02.tile" )
	addPoiTileLegacy( POI_RUIN_MEDIUM, 3, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Meadow_128_03.tile" )
	addPoiTileLegacy( POI_RUIN_MEDIUM, 4, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Meadow_128_04.tile" )

	addPoiTileLegacy( POI_RANDOM_MEDIUM, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Meadow_128_01.tile" )

	-- Added to field, but is meadow type
	addPoiTileLegacy( POI_FARMINGPATCH, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/FarmingPatch_64_01.tile" )
	addPoiTileLegacy( POI_FARMINGPATCH, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/FarmingPatch_64_02.tile" )
	addPoiTileLegacy( POI_FARMINGPATCH, 3, "$SURVIVAL_DATA/Terrain/Tiles/poi/FarmingPatch_64_03.tile" )


	-- Forest
	addPoiTileLegacy( POI_FOREST_CAMP, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/CampingSpot_Forest_64_01.tile" )
	addPoiTileLegacy( POI_FOREST_CAMP, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/CampingSpot_Forest_64_02.tile" )
	addPoiTileLegacy( POI_FOREST_CAMP, 3, "$SURVIVAL_DATA/Terrain/Tiles/poi/CampingSpot_Forest_64_03.tile" )
	addPoiTileLegacy( POI_FOREST_CAMP, 4, "$SURVIVAL_DATA/Terrain/Tiles/poi/CampingSpot_Forest_64_04.tile" )
	addPoiTileLegacy( POI_FOREST_CAMP, 5, "$SURVIVAL_DATA/Terrain/Tiles/poi/CampingSpot_Forest_64_05.tile" )
	addPoiTileLegacy( POI_FOREST_CAMP, 6, "$SURVIVAL_DATA/Terrain/Tiles/poi/CampingSpot_Forest_64_06.tile" )
	addPoiTileLegacy( POI_FOREST_CAMP, 7, "$SURVIVAL_DATA/Terrain/Tiles/poi/CampingSpot_Forest_64_07.tile" )

	addPoiTileLegacy( POI_FOREST_RUIN, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Forest_64_01.tile" )
	addPoiTileLegacy( POI_FOREST_RUIN, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Forest_64_02.tile" )
	addPoiTileLegacy( POI_FOREST_RUIN, 3, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Forest_64_03.tile" )

	addPoiTileLegacy( POI_FOREST_RANDOM, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Forest_64_01.tile" )
	addPoiTileLegacy( POI_FOREST_RANDOM, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Forest_64_02.tile" )
	addPoiTileLegacy( POI_FOREST_RANDOM, 3, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Forest_64_03.tile" )
	addPoiTileLegacy( POI_FOREST_RANDOM, 4, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Forest_64_01.tile" )
	addPoiTileLegacy( POI_FOREST_RANDOM, 5, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Forest_64_02.tile" )
	addPoiTileLegacy( POI_FOREST_RANDOM, 6, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Forest_64_03.tile" )
	addPoiTileLegacy( POI_FOREST_RANDOM, 7, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Forest_64_04.tile" )

	-- Forest medium
	addPoiTileLegacy( POI_FOREST_RUIN_MEDIUM, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Forest_128_01.tile" )
	AddLegacyUpgrade( POI_FOREST_RUIN_MEDIUM * 100 + 2, sm.uuid.new( "910e80a5-294d-41a0-930e-6887a6cab9cf" ) ) -- Random_Forest_128_01.tile
	addPoiTile( POI_FOREST_RANDOM_MEDIUM, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Forest_128_01.tile" )


	-- Desert
	addPoiTile( POI_DESERT_RANDOM, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Desert_64_01_NEW.tile" )
	addPoiTile( POI_DESERT_RANDOM, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Desert_64_02_NEW.tile" )
	addPoiTileRetired( POI_DESERT_RANDOM, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Desert_64_01.tile" )
	addPoiTileRetired( POI_DESERT_RANDOM, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Desert_64_02.tile" )

	addPoiTile( POI_DESERT_OILPOOL, "$SURVIVAL_DATA/Terrain/Tiles/poi/OilPool_Desert_64_01.tile" )
	addPoiTile( POI_DESERT_OILPOOL, "$SURVIVAL_DATA/Terrain/Tiles/poi/OilPool_Desert_64_02.tile" )


	-- Field
	addPoiTileLegacy( POI_FIELD_RUIN, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Field_64_01.tile" )
	addPoiTile( POI_FIELD_RUIN, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Field_64_02.tile" )
	addPoiTile( POI_FIELD_RUIN, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Field_64_03.tile" )

	addPoiTileLegacy( POI_FIELD_RANDOM, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Field_64_01.tile" )
	addPoiTileLegacy( POI_FIELD_RANDOM, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Field_64_02.tile" )
	addPoiTileLegacy( POI_FIELD_RANDOM, 3, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Field_64_03.tile" )

	-- Burnt forest
	addPoiTileLegacy( POI_BURNTFOREST_CAMP, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/CampingSpot_BurntForest_64_01.tile" )

	addPoiTileLegacy( POI_BURNTFOREST_RUIN, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_BurntForest_64_01.tile" )
	addPoiTile( POI_BURNTFOREST_RUIN, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_BurntForest_64_02.tile" )
	addPoiTile( POI_BURNTFOREST_RUIN, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_BurntForest_64_03.tile" )

	AddLegacyUpgrade( POI_BURNTFOREST_RANDOM * 100 + 1, sm.uuid.new( "0556fb22-cacc-4402-8d7c-6cfd6f5d39ce" ) ) --CampingSpot_BurntForest_64_01.tile
	AddLegacyUpgrade( POI_BURNTFOREST_RANDOM * 100 + 2, sm.uuid.new( "51ee58d4-5d91-4914-aa42-d35c4521a23b" ) ) --Ruin_BurntForest_64_01.tile

	-- Autumn forest
	addPoiTileLegacy( POI_AUTUMNFOREST_CAMP, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/CampingSpot_AutumnForest_64_01.tile" )
	addPoiTileLegacy( POI_AUTUMNFOREST_CAMP, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/CampingSpot_AutumnForest_64_02.tile" )
	addPoiTileLegacy( POI_AUTUMNFOREST_CAMP, 3, "$SURVIVAL_DATA/Terrain/Tiles/poi/CampingSpot_AutumnForest_64_03.tile" )

	addPoiTileLegacy( POI_AUTUMNFOREST_RUIN, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_AutumnForest_64_01.tile" )
	addPoiTile( POI_AUTUMNFOREST_RUIN, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_AutumnForest_64_02.tile" )
	addPoiTile( POI_AUTUMNFOREST_RUIN, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_AutumnForest_64_03.tile" )

	AddLegacyUpgrade( POI_AUTUMNFOREST_RANDOM * 100 + 1, sm.uuid.new( "190ac485-1f21-4490-abdb-0fb1592ab356" ) ) --Ruin_AutumnForest_64_01.tile
	AddLegacyUpgrade( POI_AUTUMNFOREST_RANDOM * 100 + 2, sm.uuid.new( "16a6315e-897a-4186-abe9-cdf83470757a" ) ) --CampingSpot_AutumnForest_64_01.tile
	AddLegacyUpgrade( POI_AUTUMNFOREST_RANDOM * 100 + 3, sm.uuid.new( "05b6d448-59fa-4abd-8986-5e331eb49af1" ) ) --CampingSpot_AutumnForest_64_02.tile
	AddLegacyUpgrade( POI_AUTUMNFOREST_RANDOM * 100 + 4, sm.uuid.new( "9b11721e-3df5-438e-92a3-9ce08c5a8e84" ) ) --CampingSpot_AutumnForest_64_03.tile

	-- Lake
	addPoiTileLegacy( POI_LAKE_RANDOM, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Lake_64_01.tile" )
	addPoiTileLegacy( POI_LAKE_RANDOM, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Lake_64_02.tile" )
	addPoiTileLegacy( POI_LAKE_RANDOM, 3, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Lake_64_03.tile" )
	AddLegacyUpgrade( POI_LAKE_RANDOM * 100 + 4, sm.uuid.new( "886a58f4-305e-458b-adff-7da04b161707" ) ) -- Random_Lake_64_01.tile
	AddLegacyUpgrade( POI_LAKE_RANDOM * 100 + 5, sm.uuid.new( "886a58f4-305e-458b-adff-7da04b161707" ) ) -- Random_Lake_64_01.tile
	AddLegacyUpgrade( POI_LAKE_RANDOM * 100 + 6, sm.uuid.new( "886a58f4-305e-458b-adff-7da04b161707" ) ) -- Random_Lake_64_01.tile
	AddLegacyUpgrade( POI_LAKE_RANDOM * 100 + 7, sm.uuid.new( "886a58f4-305e-458b-adff-7da04b161707" ) ) -- Random_Lake_64_01.tile
	AddLegacyUpgrade( POI_LAKE_RANDOM * 100 + 8, sm.uuid.new( "886a58f4-305e-458b-adff-7da04b161707" ) ) -- Random_Lake_64_01.tile
	AddLegacyUpgrade( POI_LAKE_RANDOM * 100 + 9, sm.uuid.new( "886a58f4-305e-458b-adff-7da04b161707" ) ) -- Random_Lake_64_01.tile

	addPoiTileLegacy( POI_LAKE_RANDOM_MEDIUM, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Lake_128_01.tile" )
	addPoiTileLegacy( POI_LAKE_RANDOM_MEDIUM, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Lake_128_02.tile" )
	addPoiTile( POI_LAKE_RANDOM_MEDIUM, "$SURVIVAL_DATA/Terrain/Tiles/poi/Random_Lake_128_03.tile" )
	AddLegacyUpgrade( POI_LAKE_RANDOM_MEDIUM * 100 + 3, sm.uuid.new( "9958e995-8416-4970-945f-181c0c8add04" ) ) -- Ruin_Lake_128_01.tile
	AddLegacyUpgrade( POI_LAKE_RANDOM_MEDIUM * 100 + 4, sm.uuid.new( "f3842158-55ff-4e0e-9bdc-e4e83a4c82f6" ) ) -- Random_Lake_128_02.tile
	AddLegacyUpgrade( POI_LAKE_RANDOM_MEDIUM * 100 + 5, sm.uuid.new( "0b12d848-284e-4ffb-9e1f-ddc1de9c42f0" ) ) -- Random_Lake_128_01.tile
	AddLegacyUpgrade( POI_LAKE_RANDOM_MEDIUM * 100 + 6, sm.uuid.new( "0b12d848-284e-4ffb-9e1f-ddc1de9c42f0" ) ) -- Random_Lake_128_01.tile
	AddLegacyUpgrade( POI_LAKE_RANDOM_MEDIUM * 100 + 7, sm.uuid.new( "0b12d848-284e-4ffb-9e1f-ddc1de9c42f0" ) ) -- Random_Lake_128_01.tile
	AddLegacyUpgrade( POI_LAKE_RANDOM_MEDIUM * 100 + 8, sm.uuid.new( "0b12d848-284e-4ffb-9e1f-ddc1de9c42f0" ) ) -- Random_Lake_128_01.tile
	AddLegacyUpgrade( POI_LAKE_RANDOM_MEDIUM * 100 + 9, sm.uuid.new( "0b12d848-284e-4ffb-9e1f-ddc1de9c42f0" ) ) -- Random_Lake_128_01.tile
	AddLegacyUpgrade( POI_LAKE_RANDOM_MEDIUM * 100 + 10, sm.uuid.new( "0b12d848-284e-4ffb-9e1f-ddc1de9c42f0" ) ) -- Random_Lake_128_01.tile
	AddLegacyUpgrade( POI_LAKE_RANDOM_MEDIUM * 100 + 11, sm.uuid.new( "0b12d848-284e-4ffb-9e1f-ddc1de9c42f0" ) ) -- Random_Lake_128_01.tile
	AddLegacyUpgrade( POI_LAKE_RANDOM_MEDIUM * 100 + 12, sm.uuid.new( "0b12d848-284e-4ffb-9e1f-ddc1de9c42f0" ) ) -- Random_Lake_128_01.tile

	addPoiTile( POI_LAKE_RUIN_MEDIUM, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Lake_128_01.tile" )
	addPoiTile( POI_LAKE_RUIN_MEDIUM, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Lake_128_02.tile" )
	addPoiTile( POI_LAKE_RUIN_MEDIUM, "$SURVIVAL_DATA/Terrain/Tiles/poi/Ruin_Lake_128_03.tile" )


	-- Special
	addPoiTile( POI_EXCAVATION_BRIDGE, "$SURVIVAL_DATA/Terrain/Tiles/poi/Kiosk_64_01.tile" ) --TODO: Special tile?

	addPoiTileLegacy( POI_CHEMLAKE_MEDIUM, 1, "$SURVIVAL_DATA/Terrain/Tiles/poi/ChemicalLake_128_01.tile" )
	addPoiTileLegacy( POI_CHEMLAKE_MEDIUM, 2, "$SURVIVAL_DATA/Terrain/Tiles/poi/ChemicalLake_128_02.tile" )
	addPoiTileLegacy( POI_CHEMLAKE_MEDIUM, 3, "$SURVIVAL_DATA/Terrain/Tiles/poi/ChemicalLake_128_03.tile" )

	addPoiTile( POI_OILLAKE_MEDIUM, "$SURVIVAL_DATA/Terrain/Tiles/poi/OilLake_Desert_128_01.tile" )

	addPoiTile( POI_AUTUMNFOREST_CLEARRUINSQUEST_MEDIUM, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/Ruin_AutumnForest_RuinsQuest_128_01.tile" )
	addPoiTile( POI_MEADOW_GROWLAB_QUEST_LARGE, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/Minidungeon_Overworld_Entrance_DungeonQuest_256_01.tile" )
	addPoiTile( POI_SERVICE_ELEVATOR, "$SURVIVAL_DATA/Terrain/Tiles/excavation/OverworldToUnderground_SmallElevator_64_01.tile" )

	addPoiTile( POI_BURNTFOREST_GROWLAB_FROZEN_LARGE, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/Minidungeon_Overworld_Entrance_256_03.tile" )
	addPoiTile( POI_FOREST_GROWLAB_STATION_LARGE, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/Minidungeon_Overworld_Entrance_256_04.tile" )
	addPoiTile( POI_LAKE_GROWLAB_ISLAND_XL, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/Minidungeon_OverworldEntrance_Water_512_01.tile" )
	addPoiTile( POI_DESERT_GROWLAB_CLIFFTOP_LARGE, "$SURVIVAL_DATA/Terrain/Tiles/questtiles/Minidungeon_Overworld_Entrance_256_07.tile" )

















































	-- Odd upgrade paths (for player worlds hacked with dev flag)
	AddLegacyUpgrade( POI_TEST * 100 + 1, sm.uuid.new( "68794ad2-e70f-4f68-8dc1-4b396a927d07" ) ) --Ruin_Meadow_64_01.tile
	AddLegacyUpgrade( POI_TEST * 100 + 2, sm.uuid.new( "a3b7e066-2530-404e-9c4b-d311f569748c" ) ) --Ruin_Meadow_128_01.tile
	AddLegacyUpgrade( POI_TEST * 100 + 3, sm.uuid.new( "68794ad2-e70f-4f68-8dc1-4b396a927d07" ) ) --Ruin_Meadow_64_01.tile
	AddLegacyUpgrade( POI_TEST * 100 + 4, sm.uuid.new( "68794ad2-e70f-4f68-8dc1-4b396a927d07" ) ) --Ruin_Meadow_64_01.tile
	AddLegacyUpgrade( POI_TEST * 100 + 5, sm.uuid.new( "68794ad2-e70f-4f68-8dc1-4b396a927d07" ) ) --Ruin_Meadow_64_01.tile

end
