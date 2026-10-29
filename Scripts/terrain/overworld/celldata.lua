dofile "tile_database.lua"

dofile "poi_types.lua"

--------------------------------------------------------------------------------
-- Cell type constants
--------------------------------------------------------------------------------





TYPE_MEADOW = 1
TYPE_FOREST = 2
TYPE_DESERT = 3
TYPE_FIELD = 4
TYPE_BURNTFOREST = 5
TYPE_AUTUMNFOREST = 6
TYPE_LAKE = 8

DEBUG_R = 243
DEBUG_G = 244
DEBUG_B = 245
DEBUG_C = 246
DEBUG_M = 247
DEBUG_Y = 248
DEBUG_BLACK = 249
DEBUG_ORANGE = 250
DEBUG_PINK = 251
DEBUG_LIME = 252
DEBUG_SPRING = 253
DEBUG_PURPLE = 254
DEBUG_LAKE = 255

----------------------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------------------

MASK_CLIFF = 0x00ff
MASK_ROADS = 0x0f00
MASK_ROADCLIFF = 0x0fff
MASK_TERRAINTYPE = 0xf000
MASK_FLAT = 0x10000

FLAG_ROAD_E = 0x0100
FLAG_ROAD_N = 0x0200
FLAG_ROAD_W = 0x0400
FLAG_ROAD_S = 0x0800

MASK_ROADS_SN = bit.bor( FLAG_ROAD_S, FLAG_ROAD_N )
MASK_ROADS_WE = bit.bor( FLAG_ROAD_W, FLAG_ROAD_E )

SHIFT_TERRAINTYPE = 12

ERROR_TILE_UUID = sm.uuid.new( "723268d4-8d59-4500-a433-7d900b61c29c" )

--------------------------------------------------------------------------------
-- Cell data
--------------------------------------------------------------------------------

-- Version history:
-- 2:	Changes integer 'tileId' to 'uid' from tile uuid
--		Renamed 'tileOffsetX' -> 'xOffset'
--		Renamed 'tileOffsetY' -> 'yOffset'
--		Added 'version'

g_cellData = g_cellData or {
	version = 2,
	bounds = { xMin=0, xMax=0, yMin=0, yMax=0 },
	padding = 0,
	seed = 0,
	-- Per corner
	elevation = {},
	cliffLevel = {},



	-- Per Cell
	uid = {},
	xOffset = {},
	yOffset = {},
	rotation = {},
	groupId = {},
	flags = {},
}

--------------------------------------------------------------------------------
-- Initializes all cells for terrain bounds
--------------------------------------------------------------------------------

function initializeCellData( xMin, xMax, yMin, yMax, seed, padding )
	g_cellData.bounds.xMin = xMin
	g_cellData.bounds.xMax = xMax
	g_cellData.bounds.yMin = yMin
	g_cellData.bounds.yMax = yMax
	g_cellData.seed = seed
	g_cellData.padding = padding
	
	-- Corners
	for cornerY = yMin, yMax + 1 do
		g_cellData.elevation[cornerY] = {}
		g_cellData.cliffLevel[cornerY] = {}



		for cornerX = xMin, xMax + 1 do
			g_cellData.elevation[cornerY][cornerX] = 0
			g_cellData.cliffLevel[cornerY][cornerX] = 0



		end
	end

	if not g_cellData.groupId then
		g_cellData.groupId = {}
	end

	-- Cells
	for cellY = yMin, yMax do
		g_cellData.uid[cellY] = {}
		g_cellData.xOffset[cellY] = {}
		g_cellData.yOffset[cellY] = {}
		g_cellData.rotation[cellY] = {}
		g_cellData.groupId[cellY] = {}
		g_cellData.flags[cellY] = {}
		for cellX = xMin, xMax do
			g_cellData.uid[cellY][cellX] = sm.uuid.getNil()
			g_cellData.xOffset[cellY][cellX] = 0
			g_cellData.yOffset[cellY][cellX] = 0
			g_cellData.rotation[cellY][cellX] = 0
			g_cellData.groupId[cellY][cellX] = 0
			g_cellData.flags[cellY][cellX] = 0
		end
	end

	g_groupIdCount = 0
end

--------------------------------------------------------------------------------
-- Corner data convenience functions
--------------------------------------------------------------------------------

function insideCornerBounds( cornerX, cornerY, padding )
	padding = padding or 0
	if cornerX < g_cellData.bounds.xMin + padding or cornerX > g_cellData.bounds.xMax - padding + 1 then
		return false
	elseif cornerY < g_cellData.bounds.yMin + padding or cornerY > g_cellData.bounds.yMax - padding + 1 then
		return false
	end
	return true
end

--------------------------------------------------------------------------------

function getCornerElevationLevel( cornerX, cornerY )
	if insideCornerBounds( cornerX, cornerY ) then
		return g_cellData.elevation[cornerY][cornerX]
	end
	return 0
end

--------------------------------------------------------------------------------

function getCornerCliffLevel( cornerX, cornerY )
	if insideCornerBounds( cornerX, cornerY ) then
		return g_cellData.cliffLevel[cornerY][cornerX]
	end
	return 0
end

--------------------------------------------------------------------------------
-- Cell data convenience functions
--------------------------------------------------------------------------------

function insideCellBounds( cellX, cellY, padding )
	padding = padding or 0
	if cellX < g_cellData.bounds.xMin + padding or cellX > g_cellData.bounds.xMax - padding then
		return false
	elseif cellY < g_cellData.bounds.yMin + padding or cellY > g_cellData.bounds.yMax - padding then
		return false
	end
	return true
end

--------------------------------------------------------------------------------

function GetCellTileUid( cellX, cellY )
	if insideCellBounds( cellX, cellY ) then
		return g_cellData.uid[cellY][cellX]
	end
	return sm.uuid.getNil()
end

--------------------------------------------------------------------------------

function getRoadCliffFlags( cellX, cellY )
	if insideCellBounds( cellX, cellY ) then
		return bit.band( g_cellData.flags[cellY][cellX], MASK_ROADCLIFF )
	end
	return 0
end

--------------------------------------------------------------------------------

function isFlat( cellX, cellY )
	if insideCellBounds( cellX, cellY ) then
		return bit.band( g_cellData.flags[cellY][cellX], MASK_FLAT ) ~= 0
	end
	return false
end

--------------------------------------------------------------------------------

function getCellType( cellX, cellY )
	if insideCellBounds( cellX, cellY ) then
		return bit.rshift( bit.band( g_cellData.flags[cellY][cellX], MASK_TERRAINTYPE ), SHIFT_TERRAINTYPE )
	end
	return 0
end

--------------------------------------------------------------------------------

function isLake( cellX, cellY )
	if insideCellBounds( cellX, cellY ) then
		return bit.rshift( bit.band( g_cellData.flags[cellY][cellX], MASK_TERRAINTYPE ), SHIFT_TERRAINTYPE ) == TYPE_LAKE
	end
	return false
end

--------------------------------------------------------------------------------

function isRoad( cellX, cellY )
	if insideCellBounds( cellX, cellY ) then
		return bit.band( g_cellData.flags[cellY][cellX], MASK_ROADS ) ~= 0
	end
	return false
end
