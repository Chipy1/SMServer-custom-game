dofile( "$SURVIVAL_DATA/Scripts/terrain/underground/chunk_raster.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/underground/tunnel_generation.lua" )

local CaveSizeConvert = sm.vec3.new( CHUNKS_PER_CELL, CHUNKS_PER_CELL, 1 )

function PathToZOffset( path, zSize )
	local offset = 0
	local start, _, h = string.find( path, "_h(%d+)[^%a]" )
	if start then
		offset = math.floor( h )
	end
	-- Old style compability
	local start, _, a = string.find( path, "_a(%d+)[^%a]" )
	if start then
		offset = math.floor( tonumber( a ) / 16 )
	end
	if offset >= zSize then
		sm.log.warning( "PathToZOffset: Offset greater than or equal to z-size in path:", path )
	end
	return offset
end

function AddCave( tile, pos, tag, rotation, elevatorNodes ) -- NOTE: Pos is cell/chunk 0,0,0 pos
	local anchorPos = pos
	print( "Adding cave tile", tile.path, tile.size, "-", pos, rotation, tag )
	local caveSize = ( tile.size / CaveSizeConvert ):ceil()
	local worldCaveSize = rotation % 2 == 1 and sm.vec3.new( caveSize.y, caveSize.x, caveSize.z ) or caveSize
	local zOffset = PathToZOffset( tile.path, tile.size.z )
	pos = pos + sm.vec3.new( 0, 0, -zOffset )

	local uidTile = sm.terrainTile.getTileUuid( tile.path )
	print( "  adjusted pos", "world size", worldCaveSize * CaveSizeConvert )
	if CheckIfFits( pos * CaveSizeConvert, worldCaveSize * CaveSizeConvert ) then
		--TODO: Raster grid from TUNNEL_BLOCKER nodes
		WriteChunkRaster( pos * CaveSizeConvert, worldCaveSize * CaveSizeConvert, 1 )--, nil, "400000" )
		local srcKey = "C:"..tostring( pos.x )..","..tostring( pos.y )..","..tostring( pos.z )
		local tunnelNodes = {}
		local hasSpawnableUnit = false
		for y = 0, worldCaveSize.y - 1 do
			for x = 0, worldCaveSize.x - 1 do
				local offsetX, offsetY = InverseRotateLocal2( rotation, x, y, worldCaveSize.x - 1, worldCaveSize.y - 1 )
				local cell = { x = pos.x + x, y = pos.y + y, offsetX = offsetX, offsetY = offsetY, rotation = rotation }
				AddCaveCellData( uidTile, cell, pos.z, caveSize.z )
				local cellNodes = sm.terrainTile.getNodesForCell( uidTile, cell.offsetX, cell.offsetY )
				local cellTunnelNodes = TgProcessCaveCell( uidTile, cell, pos.z, caveSize, tag, cellNodes, srcKey )
				concat( tunnelNodes, cellTunnelNodes )
				if not hasSpawnableUnit then
					for _, node in ipairs( cellNodes ) do
						if valueExists( node.tags, "SPAWNABLE_UNIT" ) and ( node.params == nil or not node.params.manualSpawn ) then
							hasSpawnableUnit = true
							break
						end
					end
				end
				if elevatorNodes then
					local nodes = FindConnectionNodes( uidTile, cell, "UNDERGROUND_ELEVATOR", UNDERGROUND_CONNECTIONS, cellNodes )
					for i = 1, #nodes do
						local node = nodes[i]
						node.pos.z = node.pos.z + pos.z * CHUNK_SIZE
					end
					concat( elevatorNodes, nodes )
				end
			end
		end






		if hasSpawnableUnit then
			-- Adds enemy spawner volume trigger
			local centerPos = pos + worldCaveSize / 2
			local cellX = math.floor( centerPos.x )
			local cellY = math.floor( centerPos.y )
			local cellSpawners = g_cellData.spawners[cellY][cellX]
			cellSpawners[#cellSpawners + 1] = {
				pos = ( centerPos - sm.vec3.new( cellX, cellY, 0 ) ) * sm.vec3.new( CELL_SIZE, CELL_SIZE, CHUNK_SIZE ),
				rot = sm.quat.identity(),
				scale = worldCaveSize * sm.vec3.new( CELL_SIZE, CELL_SIZE, CHUNK_SIZE ),
				tags = { "SPAWN_ENEMY_VOLUME_TRIGGER", "AREA_REACTION_TRIGGER" },
				params = { reactToVoxelDestruction = true, triggerName = "Auto" }
			}
		end
		return true, tunnelNodes, srcKey
	end
	--sm.debugDraw.addAabb( "VoxelProcDebug_CavePos"..anchorPos.x..","..anchorPos.y..","..anchorPos.z, anchorPos * CaveSizeConvert * CHUNK_SIZE + 1, ( anchorPos + sm.vec3.new( 1, 1, worldCaveSize.z ) ) * CaveSizeConvert * CHUNK_SIZE - 1, sm.color.new( "ff0000" ) )
	--print( "    Does not fit" )
	return false, {}, nil
end

function AddPocket( tile, pos, rotation, tag, rasterValue, padding )
	local anchorPos = pos
	local worldPocketSize = rotation % 2 == 1 and sm.vec3.new( tile.size.y, tile.size.x, tile.size.z ) or tile.size
	local zOffset = PathToZOffset( tile.path, tile.size.z )
	pos = pos + sm.vec3.new( 0, 0, -zOffset )

	local uidTile = sm.terrainTile.getTileUuid( tile.path )
	--print( "  Adding", tile.path, "pos", anchorPos, "rotation", rotation )
	--TODO: Raster grid from TUNNEL_BLOCKER nodes?
	local rasterGrid = PathToRasterGrid( tile.path )
	if rasterGrid then
		rasterGrid = RotateRasterGrid( rasterGrid, rotation, tile.size )
	end
	rasterValue = rasterValue or 1
	padding = padding or 0
	if CheckIfFits( pos, worldPocketSize, rasterGrid, rasterValue, padding ) then
		--print( "  Adding", tile.path, "pos", pos, "rotation", rotation, "blocksTunnels", tostring( blocksTunnels ) )
		WriteChunkRaster( pos, worldPocketSize, rasterValue, rasterGrid )--, "008000" )
		AddPocketCellData( pos, uidTile, rotation, sm.vec3.zero(), worldPocketSize )
		if rasterGrid then
			for y = 0, worldPocketSize.y - 1 do
				for x = 0, worldPocketSize.x - 1 do
					for z = 0, worldPocketSize.z - 1 do
						local offset = sm.vec3.new( x, y, z )
						if bit.band( rasterGrid[offset.z + 1], bit.lshift( bit.lshift( 1, offset.x ), 4 * offset.y ) ) ~= 0 then
							TgAddBlocker( pos + offset, pos + offset + 1, "Pocket", 1 )
						end
					end
				end
			end
		else
			TgAddBlocker( pos, pos + worldPocketSize, "Pocket", 1 )
		end
		local cellNodes = sm.terrainTile.getNodesForCell( uidTile, 0, 0 )
		local srcKey = "P:"..tostring( pos.x )..","..tostring( pos.y )..","..tostring( pos.z )
		local tunnelNodes = TgProcessPocket( uidTile, pos, rotation, tile.size, rasterGrid, tag, cellNodes, srcKey )








		local hasSpawnableUnit = false
		for _, node in ipairs( cellNodes ) do
			if valueExists( node.tags, "SPAWNABLE_UNIT" ) and ( node.params == nil or not node.params.manualSpawn ) then
				hasSpawnableUnit = true
				break
			end
		end
		if hasSpawnableUnit then
			-- Adds enemy spawner volume trigger
			local centerPos = pos + worldPocketSize / 2
			local cellX = math.floor( centerPos.x / CHUNKS_PER_CELL )
			local cellY = math.floor( centerPos.y / CHUNKS_PER_CELL )
			local cellSpawners = g_cellData.spawners[cellY][cellX]
			cellSpawners[#cellSpawners + 1] = {
				pos = ( centerPos - sm.vec3.new( cellX * CHUNKS_PER_CELL, cellY * CHUNKS_PER_CELL, 0 ) ) * CHUNK_SIZE,
				rot = sm.quat.identity(),
				scale = worldPocketSize * CHUNK_SIZE,
				tags = { "SPAWN_ENEMY_VOLUME_TRIGGER", "AREA_REACTION_TRIGGER" },
				params = { reactToVoxelDestruction = true, triggerName = "Auto" }
			}
		end
		return true, tunnelNodes, srcKey
	end
	--sm.debugDraw.addAabb( "VoxelProcDebug_PocketPos"..anchorPos.x..","..anchorPos.y..","..anchorPos.z, anchorPos * CHUNK_SIZE + 1, ( anchorPos + 1 ) * CHUNK_SIZE - 1, sm.color.new( "ff0000" ) )
	--print( "    Does not fit" )
	return false, {}, nil
end