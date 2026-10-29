
----------------------------------------------------------------------------------------------------

function writeStartArea( pois, roadNodes )
	local xPos = -46
	local yPos = -46

	local function _addPoi( tileX, tileY, index, size )
		local x = tileX + math.floor( size / 2 )
		local y = tileY + math.floor( size / 2 )
		pois[#pois + 1] = { x = x, y = y, type = POI_CRASHSITE_AREA, index = index, size = size, flat = true }
	end

	-- Crash site
	writeTile( getPoiTileId( POI_CRASHSITE_AREA, 10 ), xPos + 8, yPos + 4, 4, 0 )
	_addPoi( xPos + 8, yPos + 4, 10, 4 )

	-- Crash site tower
	writeTile( getPoiTileId( POI_CRASHSITE_AREA, 11 ), xPos + 10, yPos + 7, 2, 0 )
	_addPoi( xPos + 10, yPos + 7, 2, 2 )

	-- Crash site big ruin
	writeTile( getPoiTileId( POI_CRASHSITE_AREA, 12 ), xPos + 8, yPos + 9, 2, 0 )
	_addPoi( xPos + 8, yPos + 9, 3, 2 )

	-- Crash site tower cliff
	writeTile( getPoiTileId( POI_CRASHSITE_AREA, 4 ), xPos + 10, yPos + 8, 1, 2 )

	-- Small ruin A
	writeTile( getPoiTileId( POI_CRASHSITE_AREA, 5 ), xPos + 14, yPos + 5, 1, 0 )
	_addPoi( xPos + 14, yPos + 5, 5, 1 )

	-- Small ruin B
	writeTile( getPoiTileId( POI_CRASHSITE_AREA, 6 ), xPos + 5, yPos + 5, 1, 0 )
	_addPoi( xPos + 5, yPos + 5, 6, 1 )

	-- Small ruin C
	writeTile( getPoiTileId( POI_CRASHSITE_AREA, 7 ), xPos + 9, yPos + 2, 1, 0 )
	_addPoi( xPos + 9, yPos + 2, 7, 1 )

	-- Small ruin D
	writeTile( getPoiTileId( POI_CRASHSITE_AREA, 8 ), xPos + 6, yPos + 8, 1, 0 )
	_addPoi( xPos + 6, yPos + 8, 8, 1 )

	-- Boss Mountain
	writeTile( getPoiTileId( POI_CRASHSITE_AREA, 9 ), xPos + 6, yPos + 4, 2, 0 )
	_addPoi( xPos + 6, yPos + 4, 9, 2 )


	local M = TYPE_MEADOW
	local F = TYPE_FOREST
	local L = TYPE_LAKE
	local X = true
	local O = false
	
	-- Corner data
	local type = {
		{ L, L, L, L, L, L, L, M, M, M, M, M, M, M, M, M, L, L, L, L, L },
		{ L, L, L, L, L, L, L, M, M, M, M, M, M, M, M, M, M, L, L, L, L },
		{ L, L, L, L, L, L, L, M, M, M, M, M, M, M, M, M, M, L, L, L, L },
		{ L, L, L, L, L, M, M, M, M, M, M, M, M, M, M, M, M, M, M, L, L },
		{ L, L, L, L, M, M, M, M, M, M, M, M, M, M, M, M, M, M, M, M, L },
		{ L, L, M, M, L, M, M, F, M, M, M, M, F, M, M, M, M, M, M, M, L },
		{ L, L, L, L, L, L, M, M, M, M, M, F, F, F, M, M, M, M, M, M, L },
		{ L, L, L, L, L, L, M, M, M, M, F, F, F, F, F, M, M, L, L, L, L },
		{ L, L, L, L, L, M, M, M, M, M, F, F, F, F, F, M, M, L, L, M, L },
		{ L, L, L, M, M, M, F, F, M, F, F, F, F, F, M, M, M, L, L, M, L },
		{ L, L, L, M, M, F, F, F, F, F, F, F, F, F, M, M, M, L, L, L, L },
		{ L, L, L, L, M, M, F, F, F, F, F, F, M, M, M, M, L, L, L, L, L },
		{ L, L, L, L, L, M, M, M, M, M, M, M, M, M, M, L, L, L, L, L, L },
		{ L, L, L, L, L, L, L, M, M, M, M, M, M, M, M, L, L, L, L, L, L },
		{ L, L, L, L, M, L, L, L, L, M, M, M, M, L, L, L, L, L, L, L, L },
		{ L, L, L, L, M, M, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L },
		{ L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L }
	}
	local cliff = {
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 1, 1, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 3, 3, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 3, 3, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 1, 2, 3, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 1, 3, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 1, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
	}

	-- Cell data
	local static = {
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, X, X, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, X, X, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, X, O, O, O, X, X, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, X, X, X, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, X, X, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, X, X, X, X, X, X, O, O, O, X, O, O, O, O, O },
		{ O, O, O, O, O, O, X, X, X, X, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, X, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O }
	}
	local road = {
		{ O, O, O, O, O, O, O, O, O, O, O, X, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, X, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, X, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, X, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, X, X, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, X, X, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O },
		{ O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O, O }
	}

	-- Corners
	for y = 0, 16 do
		for x = 0, 20 do
			local cornerX = xPos + x
			local cornerY = yPos + y
			g_cornerTemp.terrainType[cornerY][cornerX] = type[17 - y][1 + x]
			g_cellData.cliffLevel[cornerY][cornerX] = cliff[17 - y][1 + x]
		end
	end

	-- Cells
	for y = 0, 15 do
		for x = 0, 19 do
			local cellX = xPos + x
			local cellY = yPos + y
			if road[16 - y][1 + x] then
				roadNodes[cellY][cellX] = { x = cellX, y = cellY, edges = {} }





			end
			if static[16 - y][1 + x] then
				g_cornerTemp.hillyness[cellY][cellX] = 0
				g_cornerTemp.hillyness[cellY][cellX + 1] = 0
				g_cornerTemp.hillyness[cellY + 1][cellX] = 0
				g_cornerTemp.hillyness[cellY + 1][cellX + 1] = 0
			else
				g_cellData.uid[cellY][cellX] = sm.uuid.getNil()
				g_cellData.xOffset[cellY][cellX] = 0
				g_cellData.yOffset[cellY][cellX] = 0
				g_cellData.rotation[cellY][cellX] = 0
				g_cellData.groupId[cellY][cellX] = 0
			end
		end
	end

	-- Connect road nodes
	for y = yPos, yPos + 15 do
		for x = xPos, xPos + 19 do
			local c = roadNodes[y][x]
			local e = roadNodes[y][x + 1]
			local n = roadNodes[y + 1][x]
			if c then
				if e then
					c.edges[#c.edges + 1] = { n = e, cost = 1, road = true }
					e.edges[#e.edges + 1] = { n = c, cost = 1, road = true }





				end
				if n then
					c.edges[#c.edges + 1] = { n = n, cost = 1, road = true }
					n.edges[#n.edges + 1] = { n = c, cost = 1, road = true }





				end
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
