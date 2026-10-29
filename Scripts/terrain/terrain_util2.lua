dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
----------------------------------------------------------------------------------------------------
-- Utility
----------------------------------------------------------------------------------------------------

function InsideCellBounds( cellX, cellY )
	if cellX < g_cellData.bounds.xMin or cellX > g_cellData.bounds.xMax then
		return false
	elseif cellY < g_cellData.bounds.yMin or cellY > g_cellData.bounds.yMax then
		return false
	end
	return true
end

----------------------------------------------------------------------------------------------------

function GetCellTileUid( cellX, cellY )
	if InsideCellBounds( cellX, cellY ) then
		return g_cellData.uid[cellY][cellX]
	end
	return sm.uuid.getNil()
end

----------------------------------------------------------------------------------------------------

function GetClosestCorner( x, y )
	return math.floor( x / CELL_SIZE + 0.5 ), math.floor( y / CELL_SIZE + 0.5 )
end

----------------------------------------------------------------------------------------------------

function GetCell( x, y )
	return math.floor( x / CELL_SIZE ), math.floor( y / CELL_SIZE )
end

----------------------------------------------------------------------------------------------------

function GetFraction( x, y )
	local cellX, cellY = GetCell( x, y )
	return x / CELL_SIZE - cellX, y / CELL_SIZE - cellY
end

----------------------------------------------------------------------------------------------------

function GetCellRotation( cellX, cellY )
	if InsideCellBounds( cellX, cellY ) then
		if g_cellData.rotation then
			if g_cellData.rotation[cellY] then
				return g_cellData.rotation[cellY][cellX]
			end
		end
	end
	return 0
end

----------------------------------------------------------------------------------------------------

function RotateLocal( cellX, cellY, x, y, cellSize )
	cellSize = cellSize or CELL_SIZE

	local rotation = GetCellRotation( cellX, cellY )

	local rx, ry
	if rotation == 1 then
		rx = cellSize - y
		ry = x
	elseif rotation == 2 then
		rx = cellSize - x
		ry = cellSize - y
	elseif rotation == 3 then
		rx = y
		ry = cellSize - x
	else
		rx = x
		ry = y
	end

	return rx, ry
end

----------------------------------------------------------------------------------------------------

function RotateLocal2( rotation, x, y, sizeX, sizeY )
	local rx, ry
	if rotation == 1 then
		rx = sizeY - y
		ry = x
	elseif rotation == 2 then
		rx = sizeX - x
		ry = sizeY - y
	elseif rotation == 3 then
		rx = y
		ry = sizeX - x
	else
		rx = x
		ry = y
	end
	return rx, ry
end

----------------------------------------------------------------------------------------------------

function InverseRotateLocal( cellX, cellY, x, y, cellSize )
	cellSize = cellSize or CELL_SIZE

	local rotation = GetCellRotation( cellX, cellY )

	local rx, ry
	if rotation == 1 then
		rx = y
		ry = cellSize - x
	elseif rotation == 2 then
		rx = cellSize - x
		ry = cellSize - y
	elseif rotation == 3 then
		rx = cellSize - y
		ry = x
	else
		rx = x
		ry = y
	end

	return rx, ry
end

----------------------------------------------------------------------------------------------------

function InverseRotateLocal2( rotation, x, y, sizeX, sizeY )
	local rx, ry
	if rotation == 1 then
		rx = y
		ry = sizeX - x
	elseif rotation == 2 then
		rx = sizeX - x
		ry = sizeY - y
	elseif rotation == 3 then
		rx = sizeY - y
		ry = x
	else
		rx = x
		ry = y
	end
	return rx, ry
end

----------------------------------------------------------------------------------------------------

function GetRotationQuat( cellX, cellY )
	local rotation = GetCellRotation( cellX, cellY )
	if rotation == 1 then
		return sm.quat.new( 0, 0, 0.70710678118654752440084436210485, 0.70710678118654752440084436210485 )
	elseif rotation == 2 then
		return sm.quat.new( 0, 0, 1, 0 )
	elseif rotation == 3 then
		return sm.quat.new( 0, 0, -0.70710678118654752440084436210485, 0.70710678118654752440084436210485 )
	end

	return sm.quat.new( 0, 0, 0, 1 )
end

----------------------------------------------------------------------------------------------------

function GetRotationQuat2( rotation )
	if rotation == 1 then
		return sm.quat.new( 0, 0, 0.70710678118654752440084436210485, 0.70710678118654752440084436210485 )
	elseif rotation == 2 then
		return sm.quat.new( 0, 0, 1, 0 )
	elseif rotation == 3 then
		return sm.quat.new( 0, 0, -0.70710678118654752440084436210485, 0.70710678118654752440084436210485 )
	end
	return sm.quat.new( 0, 0, 0, 1 )
end

----------------------------------------------------------------------------------------------------

function SquareDistance( x0, y0, x1, y1 )
	return ( x0 - x1 )^2 + ( y0 - y1 )^2
end

----------------------------------------------------------------------------------------------------

function Distance( x0, y0, x1, y1 )
	return math.sqrt( dist2( x0, y0, x1, y1 ) )
end

----------------------------------------------------------------------------------------------------

function ValueExists( array, value )
	for _, v in ipairs( array ) do
		if v == value then
			return true
		end
	end
	return false
end

function Intersection( a, b )
	local intersection = {}
	for _, a in pairs( a ) do
		for _, b in pairs(b) do
			if a == b then
				intersection[#intersection + 1] = a
			end
		end
	end
	return intersection
end

----------------------------------------------------------------------------------------------------

function CreateReflectionNode( x, y, z )
	return {
		pos = sm.vec3.new( x, y, z ),
		rot = sm.quat.new( 0.707107, 0, 0, 0.707107 ),
		scale = sm.vec3.new( 64, 64, 64 ),
		tags = { "REFLECTION" }
	}
end

----------------------------------------------------------------------------------------------------

local WATER_GRID_OFFSET = 0.01
local water_asset_uuid = sm.uuid.new( "990cce84-a683-4ea6-83cc-d0aee5e71e15" )
local chemicals_asset_uuid = sm.uuid.new( "f0f2db63-1f2e-4aae-8dc4-ab7cd6fe2658" )
local oil_asset_uuid = sm.uuid.new( "40151920-f883-4d59-8f5d-c9d52222a6f8" )

local function calculateWaterGridOffset( object, height )
	local scaleZ = ( object.rot * object.scale ).z
	local waterLevel = height + scaleZ * 0.5
	local distanceFromBlockEdge = math.abs( waterLevel * 4 - round( waterLevel * 4 ) ) / 4
	if( distanceFromBlockEdge < WATER_GRID_OFFSET ) then
		waterLevel = round( waterLevel * 4 ) / 4 - WATER_GRID_OFFSET
		height = waterLevel - scaleZ * 0.5
	end
	return height
end

function WaterSurfaceGridOffset( asset, height )
	if asset.uuid == water_asset_uuid or asset.uuid == chemicals_asset_uuid or asset.uuid == oil_asset_uuid then
		return calculateWaterGridOffset( asset, height )
	end
	return height
end

function WaterNodeGridOffset( node, height )
	if ValueExists( node.tags, "WATER" ) or ValueExists( node.tags, "OIL" ) or ValueExists( node.tags, "CHEMICALS" ) then
		return calculateWaterGridOffset( node, height )
	end
	return height
end

----------------------------------------------------------------------------------------------------

-- Rotate local foreign connections
-- Waypoint connections are deprecated, keep this just in case mods use it.
function RotateLocalWaypoint( cellX, cellY, node )
	local rotationStep = GetCellRotation( cellX, cellY )
	if rotationStep ~= 0 and ValueExists( node.tags, "WAYPOINT" ) then
		for _, other in ipairs( node.params.connections.otherIds ) do
			if ( type(other) == "table" ) and other.cell then
				local cx = other.cell[1]
				local cy = other.cell[2]
				if rotationStep == 1 then
					other.cell[1] = -cy
					other.cell[2] = cx
				elseif rotationStep == 2 then
					other.cell[1] = -cx
					other.cell[2] = -cy
				elseif rotationStep == 3 then
					other.cell[1] = cy
					other.cell[2] = -cx
				end
			end
		end
	end
end

function CreateCellDataStorage()
	if g_generatorIndex == 0 and sm.isHost then
		local cellDataStorage = {}
		for cellY = g_cellData.bounds.yMin, g_cellData.bounds.yMax do
			cellDataStorage[cellY] = {}
			for cellX = g_cellData.bounds.xMin, g_cellData.bounds.xMax do
				cellDataStorage[cellY][cellX] = {}

				-- Cell tags
				cellDataStorage[cellY][cellX].tags = GetTagsForCell( cellX, cellY )

				-- Get height at the middle of the cell
				local x = ( cellX + 0.5 ) * CELL_SIZE
				local y = ( cellY + 0.5 ) * CELL_SIZE
				cellDataStorage[cellY][cellX].terrainHeight = GetHeightAt( x, y, 0 )
			end
		end
		sm.terrainGeneration.setGameStorageNoSave( "cds_"..g_world.id , cellDataStorage )
	end
end

-- Gets the cell location with the smallest world coordinates for the cell's tile ( or where that cell would be if the tile is complete )
function GetTileMinCell( cellX, cellY, tileSize )
	local xOffset =  g_cellData.xOffset[cellY][cellX]
	local yOffset =  g_cellData.yOffset[cellY][cellX]
	local rotation = g_cellData.rotation[cellY][cellX]
	local x, y
	if rotation == 0 then
		x = cellX - xOffset
		y = cellY - yOffset
	elseif rotation == 1 then
		x = cellX + yOffset - ( tileSize - 1 )
		y = cellY - xOffset
	elseif rotation == 2 then
		x = cellX + xOffset - ( tileSize - 1 )
		y = cellY + yOffset - ( tileSize - 1 )
	elseif rotation == 3 then
		x = cellX - yOffset
		y = cellY + xOffset - ( tileSize - 1 )
	end
	return x, y
end

function FilterTileStorageTaggedObjects( objects, tileStorage )
	local anyRemoved = false
	for i = 1, #objects, 1 do
		local object = objects[i]
		local shouldShow, filterFlag = ShouldShow( object.tags, tileStorage[TILESTORAGE_FLAGS_TABLE] or {} )
		if not shouldShow then
			anyRemoved = true
			objects[i] = false
		end
	end

	if anyRemoved then
		removeFromArray( objects, function( value ) return value == false end )
	end
end

function FindGroupIdFromNeighbor( uid, cell, offsetX, offsetY )
	offsetX = offsetX or 0
	offsetY = offsetY or 0
	for dy = 0, -1, -1 do
		for dx = -3, 3 do
			if not( dx == 0 and dy == 0 ) then
				local nx, ny = cell.x + offsetX + dx, cell.y + offsetY + dy
				if InsideCellBounds( nx, ny ) then
					if g_cellData.uid[ny][nx] == uid and g_cellData.rotation[ny][nx] == cell.rotation then
						local rdx, rdy = InverseRotateLocal2( cell.rotation, dx, dy, 0, 0 )
						if g_cellData.xOffset[ny][nx] == cell.offsetX + rdx and g_cellData.yOffset[ny][nx] == cell.offsetY + rdy then
							return g_cellData.groupId[ny][nx]
						end
					end
				end
			end
		end
	end
	return nil
end

function FindConnectionNodes( uidTile, cell, nodeTag, connectionTags, cellNodes )
	cellNodes = cellNodes or sm.terrainTile.getNodesForCell( uidTile, cell.offsetX, cell.offsetY )
	local connectionNodes = {}
	for _, node in ipairs( cellNodes ) do
		if ValueExists( node.tags, nodeTag ) then
			print( "Found elevator connection node in cell", cell.x, cell.y )
			print( node.tags )
			local foundTags = Intersection( node.tags, connectionTags )
			if #foundTags == 1 then
				local rx, ry = RotateLocal2( cell.rotation, node.pos.x, node.pos.y, CELL_SIZE, CELL_SIZE )
				local x = cell.x * CELL_SIZE + rx
				local y = cell.y * CELL_SIZE + ry
				node.pos = sm.vec3.new( x, y, node.pos.z )
				node.rot = GetRotationQuat2( cell.rotation ) * node.rot
				connectionNodes[#connectionNodes + 1] = node
			elseif #foundTags == 0 then
				sm.log.error( "No elevator connection tags found on the "..nodeTag.." node" )
				sm.log.error( "Node:", node )
			else
				sm.log.error( "Multiple elevator connection tags found on the same "..nodeTag.." node" )
				sm.log.error( "Node:", node )
			end
		end
	end
	return connectionNodes
end

function TunnelCellCulling( tunnels, cellTunnelIndices, maxWidth )
	for idxTunnel, tunnel in ipairs( tunnels ) do
		local cells = {}
		for _, pos in ipairs( tunnel.positions ) do
			local cellX0 = math.floor( ( pos.x - maxWidth ) / CELL_SIZE )
			local cellX1 = math.floor( ( pos.x + maxWidth ) / CELL_SIZE )
			local cellY0 = math.floor( ( pos.y - maxWidth ) / CELL_SIZE )
			local cellY1 = math.floor( ( pos.y + maxWidth ) / CELL_SIZE )
			cells[cellY0] = cells[cellY0] or {}
			cells[cellY0][cellX0] = true
			cells[cellY0][cellX1] = true
			cells[cellY1] = cells[cellY1] or {}
			cells[cellY1][cellX0] = true
			cells[cellY1][cellX1] = true
		end
		for cellY, cellsX in pairs( cells ) do
			for cellX, _ in pairs( cellsX ) do
				cellTunnelIndices[cellY] = cellTunnelIndices[cellY] or {}
				cellTunnelIndices[cellY][cellX] = cellTunnelIndices[cellY][cellX] or {}
				local cellTunnels = cellTunnelIndices[cellY][cellX]
				cellTunnels[#cellTunnels + 1] = idxTunnel
			end
		end
	end
end
