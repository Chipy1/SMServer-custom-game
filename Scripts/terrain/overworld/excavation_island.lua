

function injectExcavation( injectWorld )

	local function CalculateWorldSize( worldFile )
		local xMin =  1000
		local xMax = -1000
		local yMin =  1000
		local yMax = -1000
		for _, cell in pairs( worldFile.cellData ) do
			xMin = min( xMin, cell.x )
			xMax = max( xMax, cell.x )
			yMin = min( yMin, cell.y )
			yMax = max( yMax, cell.y )
		end
		return (xMax - xMin), (yMax - yMin)
	end

	local worldFile = sm.json.open( injectWorld.worldFile )
	local sizeX, sizeY = CalculateWorldSize( worldFile )
	local offsetX = math.ceil( sizeX/2 )
	local offsetY = math.ceil( sizeY/2 )

	if injectWorld.rotation ~= 0 then
		local cellData = {}
		for _, cell in pairs( worldFile.cellData ) do
			local rx, ry = RotateLocal2( injectWorld.rotation, cell.x, cell.y, -1, -1 )
			local rotation = ( cell.rotation + injectWorld.rotation ) % 4;
			cellData[#cellData+1] = { x = rx, y = ry, path = cell.path, rotation = rotation, offsetX = cell.offsetX, offsetY = cell.offsetY }
		end
		table.sort( cellData, function( a, b ) return a.y < b.y or ( a.y == b.y and a.x < b.x ) end )
		worldFile.cellData = cellData



	end

	for _, cell in pairs( worldFile.cellData ) do
		local x = injectWorld.x + offsetX + cell.x
		local y = injectWorld.y + offsetY + cell.y
		
		local uid = sm.terrainTile.getTileUuid( cell.path )

		local groupId = FindGroupIdFromNeighbor( uid, cell, injectWorld.x + offsetX, injectWorld.y + offsetY )
		if not groupId then
			g_groupIdCount = g_groupIdCount + 1
			groupId = g_groupIdCount
		end

		g_cellData.uid[y][x] = uid
		g_cellData.xOffset[y][x] = cell.offsetX
		g_cellData.yOffset[y][x] = cell.offsetY
		g_cellData.rotation[y][x] = cell.rotation
		g_cellData.groupId[y][x] = groupId
	end

	for _, corner in pairs( worldFile.cornerData ) do
		local x = injectWorld.x + offsetX + corner.x
		local y = injectWorld.y + offsetY + corner.y
		
		g_cornerTemp.terrainType[y][x] = corner.type
		g_cellData.elevation[y][x] = 0
		g_cellData.cliffLevel[y][x] = 0
	end
end