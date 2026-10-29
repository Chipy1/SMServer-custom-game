
function closestPoi( pois, cellX, cellY )
	local beginning = cellX < -8 and cellY < -8
	local DistanceMultiplier = {
		[TYPE_MEADOW] = 1,
		[TYPE_FOREST] = beginning and 1.6 or 1,
		[TYPE_FIELD] = 1.2,
		[TYPE_BURNTFOREST] = 1.6,
		[TYPE_AUTUMNFOREST] = 1.8,
		[TYPE_LAKE] = 2,
		[TYPE_DESERT] = 1,
	}
	local minDist = math.huge
	local poi
	for _,p in pairs( pois ) do
		assert( p.terrainType )
		local dist = distance( p.x, p.y, cellX, cellY ) * DistanceMultiplier[p.terrainType] - p.size
		--local dist = ( math.abs( p.x - cellX ) + math.abs( p.y - cellY ) ) * DistanceMultiplier[p.terrainType] - p.size
		if dist < minDist then
			minDist = dist
			poi = p
		end
	end
	return poi, minDist
end

----------------------------------------------------------------------------------------------------

function collides( xPos, yPos, size, pois )
	local xMin0 = xPos - math.floor( size / 2 )
	local xMax0 = xPos + math.floor( ( size + 1 ) / 2 )
	local yMin0 = yPos - math.floor( size / 2 )
	local yMax0 = yPos + math.floor( ( size + 1 ) / 2 )
	for _,p in ipairs( pois ) do
		local xMin1 = p.x - math.floor( p.size / 2 )
		local xMax1 = p.x + math.floor( ( p.size + 1 ) / 2 )
		local yMin1 = p.y - math.floor( p.size / 2 )
		local yMax1 = p.y + math.floor( ( p.size + 1 ) / 2 )
		if xMax0 > xMin1 and xMin0 < xMax1 and yMax0 > yMin1 and yMin0 < yMax1 then
			return p
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------

function writeTile( tileId, xPos, yPos, size, rotation, terrainType )
	assert( type( tileId ) == "Uuid" )
	g_groupIdCount = g_groupIdCount + 1
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local cellX = x + xPos
			local cellY = y + yPos
			g_cellData.uid[cellY][cellX] = tileId
			if rotation == 1 then
				g_cellData.xOffset[cellY][cellX] = y
				g_cellData.yOffset[cellY][cellX] = ( size - 1 ) - x
			elseif rotation == 2 then
				g_cellData.xOffset[cellY][cellX] = ( size - 1 ) - x
				g_cellData.yOffset[cellY][cellX] = ( size - 1 ) - y
			elseif rotation == 3 then
				g_cellData.xOffset[cellY][cellX] = ( size - 1 ) - y
				g_cellData.yOffset[cellY][cellX] = x
			else
				g_cellData.xOffset[cellY][cellX] = x
				g_cellData.yOffset[cellY][cellX] = y
			end
			g_cellData.rotation[cellY][cellX] = rotation
			g_cellData.groupId[cellY][cellX] = g_groupIdCount
			if terrainType then
				g_cellData.flags[cellY][cellX] = bit.bor( bit.band( g_cellData.flags[cellY][cellX], bit.bnot( MASK_TERRAINTYPE ) ), bit.band( bit.lshift( terrainType, SHIFT_TERRAINTYPE ), MASK_TERRAINTYPE ) )
			end
		end
	end
end

----------------------------------------------------------------------------------------------------

function writePoi( poi, padding )
	local variationNoise = poi.index and poi.index - 1 or sm.noise.intNoise2d( poi.x, poi.y, g_cellData.seed + 2854 )
	local tileId = getRandomPoiTileId( poi.type, variationNoise )
	local rotation = poi.rotation or ( sm.noise.intNoise2d( poi.x, poi.y, g_cellData.seed + 9439 ) % 4 )

	assert( tileId ~= -1, "Error: Unkown poi type!" )

	local x = poi.x - math.floor( poi.size / 2 )
	local y = poi.y - math.floor( poi.size / 2 )
	if insideCellBounds( x, y, padding ) and insideCellBounds( x + poi.size - 1, y + poi.size - 1, padding ) then
		local terrainType = math.floor( poi.type / 100 )
		writeTile( tileId, x, y, poi.size, rotation, terrainType )
	else
		sm.log.warning( "Poi out of bounds! ("..poi.x.." "..poi.y..") size: "..poi.size )
	end
end

----------------------------------------------------------------------------------------------------
















































function ddSphere( _, _, _, _, _ ) end
function ddBox( _, _, _, _, _, _ ) end
function ddArrow( _, _, _, _, _, _, _ ) end
function ddDownArrow( _, _, _, _, _ ) end

