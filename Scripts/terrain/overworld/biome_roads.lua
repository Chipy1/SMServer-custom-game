
local f_biomeRoadTiles = {}

local NameToTerrainType = {
	["Forest"] = TYPE_FOREST,
	["Desert"] = TYPE_DESERT,
	["Field"] = TYPE_FIELD,
	["BurntForest"] = TYPE_BURNTFOREST,
	["AutumnForest"] = TYPE_AUTUMNFOREST,
	["Lake"] = TYPE_LAKE,
}

local function toRoadBits( s, w, n, e )
	return bit.bor( bit.lshift( s, 19 ), bit.lshift( w, 18 ), bit.lshift( n, 17 ), bit.lshift( e, 16 ) )
end

local function toTypeCornerBits( t_se, t_sw, t_nw, t_ne )
	return bit.bor( bit.lshift( t_se > 1 and t_se or 0, 12 ), bit.lshift( t_sw > 1 and t_sw or 0, 8 ), bit.lshift( t_nw > 1 and t_nw or 0, 4 ), t_ne > 1 and t_ne or 0 )
end

local function pathToIndex( path, rotation )
	local _, _, r_s, r_w, r_n, r_e, type, t_se, t_sw, t_nw, t_ne = string.find( path, "Road%((%d)(%d)(%d)(%d)%)_(%a+)%((%d)(%d)(%d)(%d)%)" )
	assert( NameToTerrainType[type] )
	local terrainType = NameToTerrainType[type]
	t_se = t_se * terrainType
	t_sw = t_sw * terrainType
	t_nw = t_nw * terrainType
	t_ne = t_ne * terrainType
	if rotation == 1 then
		return bit.bor( toRoadBits( r_w, r_n, r_e, r_s ), toTypeCornerBits( t_sw, t_nw, t_ne, t_se ) )
	elseif rotation == 2 then
		return bit.bor( toRoadBits( r_n, r_e, r_s, r_w ), toTypeCornerBits( t_nw, t_ne, t_se, t_sw ) )
	elseif rotation == 3 then
		return bit.bor( toRoadBits( r_e, r_s, r_w, r_n ), toTypeCornerBits( t_ne, t_se, t_sw, t_nw ) )
	end
	return bit.bor( toRoadBits( r_s, r_w, r_n, r_e ), toTypeCornerBits( t_se, t_sw, t_nw, t_ne ) )
end

-- Adds all 4 rotations of a special road tile
local function addBiomeRoadTile( path )
	local _, _, r_s, r_w, r_n, r_e, type, t_se, t_sw, t_nw, t_ne = string.find( path, "Road%((%d)(%d)(%d)(%d)%)_(%a+)%((%d)(%d)(%d)(%d)%)" )
	assert( NameToTerrainType[type] )
	local terrainType = NameToTerrainType[type]
	t_se = t_se * terrainType
	t_sw = t_sw * terrainType
	t_nw = t_nw * terrainType
	t_ne = t_ne * terrainType

	for rotation = 0, 3 do
		local index = pathToIndex( path, rotation )
		f_biomeRoadTiles[index] = f_biomeRoadTiles[index] or { tiles = {}, rotation = rotation, terrainType = terrainType }
		f_biomeRoadTiles[index].tiles[#f_biomeRoadTiles[index].tiles + 1] = AddTile( nil, path, nil, nil )
	end
end

function initBiomeRoadTiles()
	-- Forest
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Forest(1001)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0001)_Forest(1111)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0011)_Forest(1111)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Forest(1111)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0111)_Forest(1111)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(1111)_Forest(1111)_01.tile" )
	
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Forest(0010)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Forest(0001)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Forest(1011)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Forest(0111)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Forest(0011)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0011)_Forest(0001)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0011)_Forest(1110)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0011)_Forest(1100)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0011)_Forest(0110)_01.tile" )
	-- Desert
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Desert(1001)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Desert(1001)_02.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0011)_Desert(1111)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0011)_Desert(1111)_02.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Desert(1111)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Desert(1111)_02.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Desert(1111)_03.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Desert(0010)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Desert(0001)_01.tile" )

	-- Field
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Field(1001)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0011)_Field(1111)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Field(1111)_01.tile" )
	-- BurntForest
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_BurntForest(1001)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0011)_BurntForest(1111)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_BurntForest(1111)_01.tile" )
	-- AutumnForest
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_AutumnForest(1001)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0011)_AutumnForest(1111)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_AutumnForest(1111)_01.tile" )
	-- Lake
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Lake(1001)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Lake(1001)_02.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Lake(1001)_03.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Lake(1111)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Lake(1111)_02.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0011)_Lake(0001)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0011)_Lake(0110)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0011)_Lake(1100)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0011)_Lake(1110)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Lake(0001)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Lake(0010)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Lake(0011)_01.tile" )
	addBiomeRoadTile( "$SURVIVAL_DATA/Terrain/Tiles/roads_biomes/Road(0101)_Lake(0011)_02.tile" )

end

function calculateIndex( cell )
	local roadBits = bit.lshift( bit.rshift( bit.band( g_cellData.flags[cell.y][cell.x], MASK_ROADS ), 8 ), 16 ) -- Reshift road bits
	local typeCornerBits = toTypeCornerBits( g_cornerTemp.terrainType[cell.y][cell.x + 1], g_cornerTemp.terrainType[cell.y][cell.x], g_cornerTemp.terrainType[cell.y + 1][cell.x], g_cornerTemp.terrainType[cell.y + 1][cell.x + 1] )
	return bit.bor( roadBits, typeCornerBits )
end

function getBiomeRoadTile( cell )
	return f_biomeRoadTiles[calculateIndex( cell )]
end


















































































