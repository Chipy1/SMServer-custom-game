dofile( "$SURVIVAL_DATA/Scripts/terrain/random_generation.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/terrain_util2.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/kinematic_util.lua" )
dofile( "$GAME_DATA/Scripts/terrain/terrain_prepare_cell_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/tile_database.lua" )

-- Version history:
-- 2:	Changes int tile id to tile uuid
--		Added 'version'

----------------------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------------------

function Init( world, generatorIndex )
	g_world = world
	g_generatorIndex = generatorIndex
	
	g_cellData = {}
	g_cellData.version = 2
	g_cellData.creations = nil
	g_cellData.tiles = nil
end

----------------------------------------------------------------------------------------------------

function Create( xMin, xMax, yMin, yMax, seed, data )
	g_cellData.creations = data.creations
	g_cellData.bounds = { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax }

	if data.tiles then
		g_cellData.tiles = {}
		for _, tile in ipairs( data.tiles ) do
			local uid = sm.terrainTile.getTileUuid( tile )
			g_cellData.tiles[tostring( uid )] = tile
			AddTile( tile )
		end
		sm.terrainGeneration.setGameStorageNoSave( "tileData"..g_world.id, GetTileDatabase() )
	end

	g_cellData.seed = seed
	math.randomseed( g_cellData.seed )
	if sm.isHost then
		sm.terrainData.save( g_cellData )
	end
end

----------------------------------------------------------------------------------------------------

function Load()
	if sm.terrainData.exists() then
		g_cellData = sm.terrainData.load()
		if g_generatorIndex == 0 and UpgradeCellData( g_cellData ) then
			sm.terrainData.save( g_cellData )
		end
		math.randomseed( g_cellData.seed )

		for uuid, tile in ipairs( g_cellData.tiles ) do
			AddTile( tile )
		end
		sm.terrainGeneration.setGameStorageNoSave( "tileData"..g_world.id, GetTileDatabase() )	

		return true
	end
	return false
end

function UpgradeCellData( cellData )
	sm.log.info( "UpgradeCellData - version: "..tostring( cellData.version or 1 ) )
	local upgraded = false
	-- 1 to 2
	if ( cellData.version or 1 ) < 2 then
		local tiles = shallowcopy( cellData.tiles )
		cellData.tiles = {}
		for _, tile in ipairs( tiles ) do
			local uid = sm.terrainTile.getTileUuid( tile )
			if not sm.uuid.isNil( uid ) then
				cellData.tiles[tostring( uid )] = tile
			else
				sm.log.error( "Tile '"..tile.."' not found" )
			end
		end
		cellData.version = 2
		upgraded = true
	end
	if upgraded then
		 sm.log.info( "	- Upgraded to version "..tostring( cellData.version ) )
	else 
		sm.log.info( "	- No upgrade needed" ) end
	return upgraded
end

----------------------------------------------------------------------------------------------------
-- Generator API Getters
----------------------------------------------------------------------------------------------------

function GetHeightAt( x, y, lod )
	return 0
end

function GetColorAt( x, y, lod )
	return 0, 0, 0
end

function GetMaterialAt( x, y, lod )
	return 0, 0, 0, 0, 0, 0, 0, 0
end

function GetClutterIdxAt( x, y )
	return -1
end

function GetEffectMaterialAt( x, y )
	return "Dirt"
end

----------------------------------------------------------------------------------------------------

blueprintTable = {}

blueprintTable["Kit_Warehouse_Hallway_Ceiling_Bend"] =					{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Hallway_Ceiling_Bend_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Hallway_Ceiling_Bend_01.blueprint" }

blueprintTable["Kit_Warehouse_Hallway_Floor"] =							{{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Hallway_Floor_01.blueprint", 89 },
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Hallway_Floor_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Hallway_Floor_03.blueprint" }

blueprintTable["Kit_Warehouse_Hallway_Wall"] =							{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Hallway_Wall_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Hallway_Wall_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Hallway_Wall_03.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Hallway_Wall_04.blueprint" }

blueprintTable["Kit_Warehouse_Hallway_Wall_InnCorner"] =				{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Hallway_Wall_InnCorner_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Hallway_Wall_InnCorner_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBasement_PipeBig_InnCorner"] =		{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBasement_PipeBig_InnCorner_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBasement_PipeBig_InnCorner_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBasement_PipeBig_Straight"] =		{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBasement_PipeBig_Straight_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBasement_PipeBig_Straight_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBlend_Floor"] =						{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBlend_Floor_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBlend_Floor_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBlend_Floor_03.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBlend_Floor_8x8"] =					{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBlend_Floor_8x8_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBlend_Floor_8x8_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_Ceiling"] =				{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Ceiling_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Ceiling_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Ceiling_03.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_Ceiling_End"] =			{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Ceiling_End_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Ceiling_End_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_Floor_Edge"] =			{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Floor_Edge_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Floor_Edge_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_Floor_InnCorner"] =		{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Floor_InnCorner_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Floor_InnCorner_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_LightStrip"] =			{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_LightStrip_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_LightStrip_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_LightStrip_Bend"] =		{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_LightStrip_Bend_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_LightStrip_Bend_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_LightStrip_End"] =		{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_LightStrip_End_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_LightStrip_End_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_Pillar"] =				{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Pillar_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Pillar_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Pillar_03.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_Scaffolding_1x1"] =		{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Scaffolding_1x1_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Scaffolding_1x1_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_Scaffolding_1x5"] =		{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Scaffolding_1x5_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Scaffolding_1x5_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_Wall"] =					{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_03.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_04.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_05.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_Wall_DoorL"] =			{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_DoorL_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_DoorL_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_Wall_DoorR"] =			{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_DoorR_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_DoorR_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_Wall_EndL"] =				{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_EndL_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_EndL_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_Wall_EndR"] =				{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_EndR_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_EndR_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_Wall_InnCorner"] =		{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_InnCorner_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_InnCorner_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_InnCorner_03.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_InnCorner_04.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_InnCorner_05.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_Wall_InnCorner_DoorL"] =	{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_InnCorner_DoorL_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_InnCorner_DoorL_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_Wall_InnCorner_DoorR"] =	{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_InnCorner_DoorR_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_InnCorner_DoorR_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeBuildsite_Wall_OutCorner"] =		{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_OutCorner_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeBuildsite_Wall_OutCorner_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeClutter_Bricks"] =					{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_Bricks_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_Bricks_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_Bricks_03.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_Bricks_04.blueprint" }

blueprintTable["Kit_Warehouse_OfficeClutter_Bucket_Paint"] =			{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_Bucket_Paint_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_Bucket_Paint_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_Bucket_Paint_03.blueprint" }

blueprintTable["Kit_Warehouse_OfficeClutter_CarpetRack"] =				{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_CarpetRack_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_CarpetRack_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeClutter_Cubicle"] =					{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_Cubicle_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_Cubicle_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_Cubicle_03.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_Cubicle_04.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_Cubicle_05.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_Cubicle_06.blueprint" }

blueprintTable["Kit_Warehouse_OfficeClutter_RebarRubble"] =				{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_RebarRubble_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_RebarRubble_02.blueprint" }

blueprintTable["Kit_Warehouse_OfficeClutter_SupplyShelf"] =				{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_SupplyShelf_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_OfficeClutter_SupplyShelf_02.blueprint" }

blueprintTable["Kit_Warehouse_Storage_Wall"] =							{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Storage_Wall_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Storage_Wall_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Storage_Wall_03.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Storage_Wall_04.blueprint" }

blueprintTable["Kit_Warehouse_Storage_Wall_InnCorner"] =				{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Storage_Wall_InnCorner_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Storage_Wall_InnCorner_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Storage_Wall_InnCorner_03.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Storage_Wall_InnCorner_04.blueprint" }

blueprintTable["Kit_Warehouse_StorageShelf_ConcreteTall"] =				{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_StorageShelf_ConcreteTall_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_StorageShelf_ConcreteTall_02.blueprint" }

blueprintTable["Kit_Warehouse_Toilets_Stall"] =							{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Toilets_Stall_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Toilets_Stall_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Toilets_Stall_03.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Toilets_Stall_04.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Toilets_Stall_05.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Toilets_Stall_06.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_Toilets_Stall_07.blueprint" }

blueprintTable["Kit_Warehouse_UtilityCrawlspace_Divider_Fan"] =			{	"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_UtilityCrawlspace_Divider_Fan_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_UtilityCrawlspace_Divider_Fan_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Kit_Warehouse_UtilityCrawlspace_Divider_Fan_03.blueprint" }

blueprintTable["Warehouse_Clutter_BoxStack_5x6"] =						{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxStack_5x6_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxStack_5x6_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxStack_5x6_03.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxStack_5x6_04.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxStack_5x6_05.blueprint" }

blueprintTable["Warehouse_Clutter_BoxStack_7x8"] =						{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxStack_7x8_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxStack_7x8_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxStack_7x8_03.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxStack_7x8_04.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxStack_7x8_05.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxStack_7x8_06.blueprint" }

blueprintTable["Warehouse_Clutter_BoxStack_9x12"] =						{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxStack_9x12_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxStack_9x12_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxStack_9x12_03.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxStack_9x12_04.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxStack_9x12_05.blueprint" }

blueprintTable["Warehouse_Clutter_BoxWood"] =							{{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxWood_01.blueprint", 10 },
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxWood_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxWood_03.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_BoxWood_04.blueprint" }

blueprintTable["Warehouse_Clutter_FruitCrate"] =						{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_FruitCrate_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_FruitCrate_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_FruitCrate_03.blueprint" }

blueprintTable["Warehouse_Clutter_FruitSpill"] =						{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_FruitSpill_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_FruitSpill_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_FruitSpill_03.blueprint" }

blueprintTable["Warehouse_Clutter_Pallet_1x1"] =						{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x1_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x1_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x1_03.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x1_04.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x1_05.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x1_06.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x1_07.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x1_08.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x1_09.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x1_10.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x1_11.blueprint" }

blueprintTable["Warehouse_Clutter_Pallet_1x2"] =						{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x2_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x2_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x2_03.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x2_04.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x2_05.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1x2_06.blueprint" }

blueprintTable["Warehouse_Clutter_Pallet_1xOverhang"] =					{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1xOverhang_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1xOverhang_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1xOverhang_03.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1xOverhang_04.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1xOverhang_05.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1xOverhang_06.blueprint" }

blueprintTable["Warehouse_Clutter_Pallet_1xTower"] =					{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1xTower_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1xTower_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_1xTower_03.blueprint" }

blueprintTable["Warehouse_Clutter_Pallet_2x3"] =						{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_2x3_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_2x3_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Pallet_2x3_03.blueprint" }

blueprintTable["Warehouse_Clutter_Poster"] =							{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Poster_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Poster_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Poster_03.blueprint" }

blueprintTable["Warehouse_Clutter_Poster_Light"] =						{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Poster_Light_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Poster_Light_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Poster_Light_03.blueprint" }

blueprintTable["Warehouse_Clutter_PottedPlant"] =						{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_PottedPlant_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_PottedPlant_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_PottedPlant_03.blueprint" }

blueprintTable["Warehouse_Clutter_PottedPlant_Small"] =					{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_PottedPlant_Small_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_PottedPlant_Small_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_PottedPlant_Small_03.blueprint" }

blueprintTable["Warehouse_Clutter_Shelf_x2"] =							{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x2_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x2_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x2_03.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x2_04.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x2_05.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x2_06.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x2_07.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x2_08.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x2_09.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x2_10.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x2_11.blueprint" }

blueprintTable["Warehouse_Clutter_Shelf_x3"] =							{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x3_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x3_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x3_03.blueprint" }

blueprintTable["Warehouse_Clutter_Shelf_x4"] =							{	"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x4_01.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x4_02.blueprint",
																			"$SURVIVAL_DATA/LocalBlueprints/Warehouse_Clutter_Shelf_x4_03.blueprint" }

----------------------------------------------------------------------------------------------------

prefabTable = {}

prefabTable["Kit_Warehouse_StorageClutter_ShelfTall_Bot"] =				{	"$SURVIVAL_DATA/LocalPrefabs/Kit_Warehouse_StorageClutter_ShelfTall_Bot_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Kit_Warehouse_StorageClutter_ShelfTall_Bot_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Kit_Warehouse_StorageClutter_ShelfTall_Bot_03.prefab" }

prefabTable["Kit_Warehouse_StorageClutter_ShelfTall_Mid"] =				{	"$SURVIVAL_DATA/LocalPrefabs/Kit_Warehouse_StorageClutter_ShelfTall_Mid_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Kit_Warehouse_StorageClutter_ShelfTall_Mid_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Kit_Warehouse_StorageClutter_ShelfTall_Mid_03.prefab" }

prefabTable["Kit_Warehouse_StorageClutter_ShelfTall_Top"] =				{	"$SURVIVAL_DATA/LocalPrefabs/Kit_Warehouse_StorageClutter_ShelfTall_Top_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Kit_Warehouse_StorageClutter_ShelfTall_Top_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Kit_Warehouse_StorageClutter_ShelfTall_Top_03.prefab" }

prefabTable["Warehouse_Ductway_Straight"] =								{	"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Ductway_Straight_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Ductway_Straight_02.prefab" }

prefabTable["Warehouse_FillerRoom_Hint"] =								{	"$SURVIVAL_DATA/LocalPrefabs/Warehouse_FillerRoom_Hint_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_FillerRoom_Hint_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_FillerRoom_Hint_03.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_FillerRoom_Hint_04.prefab" }

prefabTable["Warehouse_FillerRoom_HintLarge"] =							{	"$SURVIVAL_DATA/LocalPrefabs/Warehouse_FillerRoom_HintLarge_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_FillerRoom_HintLarge_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_FillerRoom_HintLarge_03.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_FillerRoom_HintLarge_04.prefab" }

prefabTable["Warehouse_Hallway_Short_DoorL"] =							{	"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Hallway_Short_DoorL_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Hallway_Short_DoorL_02.prefab" }

prefabTable["Warehouse_Hallway_Straight"] =								{	"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Hallway_Straight_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Hallway_Straight_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Hallway_Straight_03.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Hallway_Straight_04.prefab" }

prefabTable["Warehouse_Hallway_Straight_DoorL"] =						{	"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Hallway_Straight_DoorL_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Hallway_Straight_DoorL_02.prefab" }

prefabTable["Warehouse_Room_Packaging_4x3x2"] =							{	"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Packaging_4x3x2_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Packaging_4x3x2_02.prefab" }

prefabTable["Warehouse_Room_Packaging_4x4x2"] =							{	"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Packaging_4x4x2_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Packaging_4x4x2_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Packaging_4x4x2_03.prefab" }

prefabTable["Warehouse_Room_Packaging_4x5x2"] =							{	"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Packaging_4x5x2_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Packaging_4x5x2_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Packaging_4x5x2_03.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Packaging_4x5x2_04.prefab" }

prefabTable["Warehouse_Room_Packaging_4x6x2"] =							{	"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Packaging_4x6x2_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Packaging_4x6x2_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Packaging_4x6x2_03.prefab" }

prefabTable["Warehouse_Room_Storage_2x3x2"] =							{	"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Storage_2x3x2_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Storage_2x3x2_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Storage_2x3x2_03.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Storage_2x3x2_04.prefab" }

prefabTable["Warehouse_Room_Storage_3x5x2"] =							{	"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Storage_3x5x2_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Storage_3x5x2_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Storage_3x5x2_03.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Storage_3x5x2_04.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Storage_3x5x2_05.prefab" }

prefabTable["Warehouse_Room_Toilets_2x2x1"] =							{	"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Toilets_2x2x1_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Toilets_2x2x1_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Toilets_2x2x1_03.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Toilets_2x2x1_04.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Toilets_2x2x1_05.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Toilets_2x2x1_06.prefab" }

prefabTable["Warehouse_Room_Utility_1x2x1_Door_Ww"] =					{	"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Utility_1x2x1_Door_Ww_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Utility_1x2x1_Door_Ww_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Utility_1x2x1_Door_Ww_03.prefab" }

prefabTable["Warehouse_Room_Utility_3x4x2"] =							{	"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Utility_3x4x2_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Utility_3x4x2_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/Warehouse_Room_Utility_3x4x2_03.prefab" }

prefabTable["WarehouseOffice_Hallway_End_DoorM"] =						{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Hallway_End_DoorM_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Hallway_End_DoorM_02.prefab" }

prefabTable["WarehouseOffice_Hallway_End_DoorR"] =						{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Hallway_End_DoorR_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Hallway_End_DoorR_02.prefab" }

prefabTable["WarehouseOffice_Hallway_End_HoleM"] =						{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Hallway_End_HoleM_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Hallway_End_HoleM_02.prefab" }

prefabTable["WarehouseOffice_Hallway_Long_Bend_HoleL_PartA"] =			{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Hallway_Long_Bend_HoleL_PartA_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Hallway_Long_Bend_HoleL_PartA_02.prefab" }

prefabTable["WarehouseOffice_Hallway_Long_Bend_HoleL_PartB"] =			{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Hallway_Long_Bend_HoleL_PartB_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Hallway_Long_Bend_HoleL_PartB_02.prefab" }

prefabTable["WarehouseOffice_HallwayStair_Down"] =						{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_HallwayStair_Down_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_HallwayStair_Down_02.prefab" }

prefabTable["WarehouseOffice_HallwayStair_Upp"] =						{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_HallwayStair_Upp_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_HallwayStair_Upp_02.prefab" }

prefabTable["WarehouseOffice_HallwayStair_UppDown"] =					{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_HallwayStair_UppDown_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_HallwayStair_UppDown_02.prefab" }

prefabTable["WarehouseOffice_Room_Buildsite_2x2x1"] =					{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Buildsite_2x2x1_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Buildsite_2x2x1_02.prefab" }

prefabTable["WarehouseOffice_Room_Buildsite_3x3x1"] =					{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Buildsite_3x3x1_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Buildsite_3x3x1_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Buildsite_3x3x1_03.prefab" }

prefabTable["WarehouseOffice_Room_Buildsite_3x4x1"] =					{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Buildsite_3x4x1_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Buildsite_3x4x1_02.prefab" }

prefabTable["WarehouseOffice_Room_Buildsite_3x5x1"] =					{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Buildsite_3x5x1_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Buildsite_3x5x1_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Buildsite_3x5x1_03.prefab" }

prefabTable["WarehouseOffice_Room_Buildsite_4x4x1"] =					{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Buildsite_4x4x1_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Buildsite_4x4x1_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Buildsite_4x4x1_03.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Buildsite_4x4x1_04.prefab" }

prefabTable["WarehouseOffice_Room_Lounge_2x2x1"] =						{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Lounge_2x2x1_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Lounge_2x2x1_02.prefab" }

prefabTable["WarehouseOffice_Room_Workplace_2x1x1"] =					{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_2x1x1_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_2x1x1_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_2x1x1_03.prefab" }

prefabTable["WarehouseOffice_Room_Workplace_2x3x1"] =					{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_2x3x1_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_2x3x1_02.prefab" }

prefabTable["WarehouseOffice_Room_Workplace_3x3x1"] =					{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_3x3x1_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_3x3x1_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_3x3x1_03.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_3x3x1_04.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_3x3x1_05.prefab" }

prefabTable["WarehouseOffice_Room_Workplace_3x4x1"] =					{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_3x4x1_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_3x4x1_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_3x4x1_03.prefab" }

prefabTable["WarehouseOffice_Room_Workplace_4x4x1"] =					{	"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_4x4x1_01.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_4x4x1_02.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_4x4x1_03.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_4x4x1_04.prefab",
																			"$SURVIVAL_DATA/LocalPrefabs/WarehouseOffice_Room_Workplace_4x4x1_05.prefab" }

-- Effect Prefabs

prefabTable["EffectPrefabs/Warehouse/warehouse_encryptionhologram_beam"] =			{	"$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Warehouse/warehouse_encryptionhologram_beam_01.prefab",
																						"$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Warehouse/warehouse_encryptionhologram_beam_02.prefab" }

prefabTable["EffectPrefabs/Warehouse/warehouse_encryptionhologram_doorway"] =		{	"$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Warehouse/warehouse_encryptionhologram_doorway_01.prefab",
																						"$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Warehouse/warehouse_encryptionhologram_doorway_02.prefab" }

prefabTable["EffectPrefabs/Warehouse/warehouse_encryptionhologram_widebeam"] =		{	"$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Warehouse/warehouse_encryptionhologram_widebeam_01.prefab",
																						"$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Warehouse/warehouse_encryptionhologram_widebeam_02.prefab" }


----------------------------------------------------------------------------------------------------

colorTable = {}

--	PaintToolColors
--	0xeeeeeeff	0xf5f071ff	0xcbf66fff	0x68ff88ff	0x7eededff	0x4c6fe3ff	0xae79f0ff	0xee7bf0ff	0xf06767ff	0xeeaf5cff
--	0x7f7f7fff	0xe2db13ff	0xa0ea00ff	0x19e753ff	0x2ce6e6ff	0x0a3ee2ff	0x7514edff	0xcf11d2ff	0xd02525ff	0xdf7f00ff
--	0x4a4a4aff	0x817c00ff	0x577d07ff	0x0e8031ff	0x118787ff	0x0f2e91ff	0x500aa6ff	0x720a74ff	0x7c0000ff	0x673b00ff
--	0x222222ff	0x323000ff	0x005037ff	0x064023ff	0x0a4444ff	0x0a1d5aff	0x35086cff	0x520653ff	0x560202ff	0x472800ff

colorTable["YELLOW"] = {
	[0xdf7f00ff] = sm.color.new(0xe2db13ff)
}

colorTable["GREEN"] = {
	[0xdf7f00ff] = sm.color.new(0x0e8031ff)
}

colorTable["BLUE"] = {
	[0xdf7f00ff] = sm.color.new(0x4c6fe3ff)
}

colorTable["RED"] = {
	[0xdf7f00ff] = sm.color.new(0xd02525ff)
}

----------------------------------------------------------------------------------------------------

local randomizationTables = {
	prefabTable = prefabTable,
	blueprintTable = blueprintTable,
}

function PrepareCell( cellX, cellY, loadFlags )
	g_prefabNodes = {}
	g_connectionNodeCount = 65536 -- This value needs to be larger then the number of connection nodes in the cell
	g_prefabCreations = {}
	g_prefabHarvestables = {}
	g_prefabDecals = {}
	g_prefabAssets = {}
	g_prefabKinematics = {}

	g_zoneIndex = 0
	
	local additionalProcessing = {
		creations = function( creation, prefab, prefabIndex )
			local isElevator = valueExists( creation.tags, "ENTRANCE" )
				or valueExists( creation.tags, "UP" )
				or valueExists( creation.tags, "DOWN" )
				or valueExists( creation.tags, "EXIT" )
	
			for _, tag in ipairs( creation.tags ) do
				for key, value in pairs( colorTable ) do
					if tag == key then
						creation.changeColor = value
					end
				end
			end
	
			creation.mergeCreation = not isElevator
			creation.destructable = not isElevator
			creation.restricted = true
			creation.zoneIndex = prefabIndex
		end
	}

	if cellX == 0 and cellY == 0 then
		if g_cellData.tiles then
			for sUid, _ in pairs( g_cellData.tiles ) do
				local prefabs = sm.terrainTile.getPrefabsForCell( sm.uuid.new( sUid ), cellX, cellY )
				for _, prefab in ipairs( prefabs ) do
					if valueExists( prefab.tags, "NO_ZONE" ) then
						DefaultLoadPrefabProcedure( prefab, loadFlags, -1, prefab.name, randomizationTables, additionalProcessing )
					else
						DefaultLoadPrefabProcedure( prefab, loadFlags, g_zoneIndex, prefab.name, randomizationTables, additionalProcessing )
						g_zoneIndex = g_zoneIndex + 1
					end
				end
			end
		end
	end
end

function GetAssetsForCell( cellX, cellY, lod )
	local assets = g_prefabAssets
	g_prefabAssets = {}

	if cellX == 0 and cellY == 0 then
		if g_cellData.tiles then
			for sUid, _ in pairs( g_cellData.tiles ) do
				local tileAssets = sm.terrainTile.getAssetsForCell( sm.uuid.new( sUid ), 0, 0, lod )
				concat( assets, tileAssets )
			end
		end
	end

	return assets
end

function GetDecalsForCell( cellX, cellY )
	local decals = g_prefabDecals;
	g_prefabDecals = {}

	if cellX == 0 and cellY == 0 then
		if g_cellData.tiles then
			for sUid, _ in pairs( g_cellData.tiles ) do
				local tileDecals = sm.terrainTile.getDecalsForCell( sm.uuid.new( sUid ), 0, 0 )
				concat( decals, tileDecals )
			end
		end
	end

	return decals
end

function GetHarvestablesForCell( cellX, cellY, lod )
	local harvestables = g_prefabHarvestables;
	g_prefabHarvestables = {}
	
	if cellX == 0 and cellY == 0 then
		if g_cellData.tiles then
			for sUid, _ in pairs( g_cellData.tiles ) do
				local tileHarvestables = sm.terrainTile.getHarvestablesForCell( sm.uuid.new( sUid ), 0, 0, lod )
				concat( harvestables, tileHarvestables )
			end
		end
	end

	return harvestables
end

function GetKinematicsForCell( cellX, cellY, lod, terrainTaskTick )
	local kinematics = g_prefabKinematics;
	g_prefabKinematics = {}
	
	if cellX == 0 and cellY == 0 then
		if g_cellData.tiles then
			for sUid, _ in pairs( g_cellData.tiles ) do
				local tileKinematics = sm.terrainTile.getKinematicsForCell( sm.uuid.new( sUid ), 0, 0, lod )
				concat( kinematics, tileKinematics )
			end
		end
	end

	local tileStorageKey
	local storageData
	if #kinematics > 0 then
		tileStorageKey = CalculateIndoorTileStorageKey( g_world.id )
		storageData = sm.terrainGeneration.loadGameStorage( tileStorageKey )
	end

	for _, kinematic in pairs( kinematics ) do
		LoadKinematicFromStorage( kinematic, storageData, kinematic.pos, terrainTaskTick, g_world, cellX, cellY )
	end
	return kinematics
end

function GetCreationsForCell( cellX, cellY )
	local creations = g_prefabCreations
	g_prefabCreations = {}


	if cellX == 0 and cellY == 0 then
		-- Load creations from tile
		if g_cellData.tiles then
			for sUid, _ in pairs( g_cellData.tiles ) do
				local tileCreations = sm.terrainTile.getCreationsForCell( sm.uuid.new( sUid ), cellX, cellY )
				for _, creation in ipairs( tileCreations ) do
					
					RandomizeCreation( creation, blueprintTable )
					
					creation.mergeCreation = true
					creation.restricted = true
					creation.destructable = true
					creation.debugName = creation.pathOrJson
					creation.zoneIndex = -1
					if string.find( creation.pathOrJson, "Filler" ) or string.find( creation.pathOrJson, "Bedrock" )  then
						creation.zoneIndex = g_zoneIndex
						g_zoneIndex = g_zoneIndex + 1
					end
					
					creations[#creations + 1] = creation
				end
			end
		end

		-- Load creations from data.creations
		if g_cellData.creations then
			for _,creation in ipairs( g_cellData.creations ) do
				creations[#creations + 1] = { pathOrJson = creation, pos = sm.vec3.zero(), rot = sm.quat.identity(), bodyTransforms = true }
			end
		end
	end
	return creations
end

function GetNodesForCell( cellX, cellY )
	local nodes = g_prefabNodes
	g_prefabNodes = {}

	if cellX == 0 and cellY == 0 then
		
		if g_cellData.tiles then
			for sUid, _ in pairs( g_cellData.tiles ) do
				-- Load nodes from cell
				local tileNodes = sm.terrainTile.getNodesForCell( sm.uuid.new( sUid ), cellX, cellY )
				concat( nodes, tileNodes )
			end
		end
		for _, node in ipairs( nodes ) do
			node.pos.z = WaterNodeGridOffset( node, node.pos.z )
		end
	end
	return nodes
end

----------------------------------------------------------------------------------------------------

function GetCellGroups()
	if g_cellData.bounds then
		g_cellData.groupId = {}
		for cellY = g_cellData.bounds.yMin, g_cellData.bounds.yMax do
			g_cellData.groupId[cellY] = {}
			for cellX = g_cellData.bounds.xMin, g_cellData.bounds.xMax do
				g_cellData.groupId[cellY][cellX] = 1 -- All cells in group 1
			end
		end
	end
	if g_cellData.groupId then
		return g_cellData.groupId
	end
	return {}
end


----------------------------------------------------------------------------------------------------
-- Tile Reader Path Getter
----------------------------------------------------------------------------------------------------

function GetTilePath( uid )
	if g_cellData.tiles then
		return g_cellData.tiles[tostring( uid )]
	end
	return ""
end
