
MIN_HEIGHT_IN_CHUNKS = 0
MAX_HEIGHT_IN_CHUNKS = 16
CHUNK_SIZE = 16
CHUNKS_PER_CELL = CELL_SIZE / CHUNK_SIZE

function ToChunkRasterIndex( x, y, z )
	return y * CHUNKS_PER_CELL * ( MAX_HEIGHT_IN_CHUNKS - MIN_HEIGHT_IN_CHUNKS ) + x * ( MAX_HEIGHT_IN_CHUNKS - MIN_HEIGHT_IN_CHUNKS ) + z - MIN_HEIGHT_IN_CHUNKS + 1
end

function InitChunkRaster( cellX, cellY, value )
	local chunkRaster = {}
	for y = 0, 3 do
		for x = 0, 3 do
			for z = MIN_HEIGHT_IN_CHUNKS, MAX_HEIGHT_IN_CHUNKS - 1 do
				chunkRaster[ToChunkRasterIndex( x, y, z )] = value
			end
		end
	end
	g_cellTemp.chunkRaster[cellY][cellX] = chunkRaster
end

function GetChunkRaster( x, y, z )
	if z < MIN_HEIGHT_IN_CHUNKS or z >= MAX_HEIGHT_IN_CHUNKS then
		sm.log.error( "GetChunkRaster: Out of z bounds "..z )
		return nil
	end
	local cellX = math.floor( x / CHUNKS_PER_CELL )
	local cellY = math.floor( y / CHUNKS_PER_CELL )

	local chunkRasterRow = g_cellTemp.chunkRaster[cellY]
	if chunkRasterRow then
		local chunkRaster = chunkRasterRow[cellX]
		if chunkRaster then
			x = x % CHUNKS_PER_CELL
			y = y % CHUNKS_PER_CELL
			return chunkRaster[ToChunkRasterIndex( x, y, z )]
		end
	end
	sm.log.error( "GetChunkRaster: No chunk raster for cell "..cellX..","..cellY )
	return nil
end

function PathToRasterGrid( path )
	local str = string.match( path, "r([%d,]+)" )
	if not str then
		return nil
	end
	local masks = {}
	for mask in string.gmatch( str, "(%d+)" ) do
		masks[#masks + 1] = tonumber( mask )
	end
	return masks
end

function RotateRasterGrid1( rasterGrid, size )
	local rotatedRasterGrid = {}
	for i = 1, #rasterGrid do
		local mask = rasterGrid[i]
		local rotatedMask = 0
		for j = 0, 3 do
			local row = 0
			for k = 0, size.y - 1 do
				local b = bit.band( mask, bit.lshift( bit.lshift( 1, j ), 4 * ( size.y - 1 - k ) ) ) ~= 0 and 1 or 0
				row = bit.bor( row, bit.lshift( b, k ) )
			end
			rotatedMask = bit.bor( rotatedMask, bit.lshift( row, j * 4 ) )
		end
		rotatedRasterGrid[i] = rotatedMask
	end
	return rotatedRasterGrid
end

function RotateRasterGrid( rasterGrid, rotation, size )
	if rotation == 1 then
		return RotateRasterGrid1( rasterGrid, size )
	elseif rotation == 2 then
		local rotatedRasterGrid = RotateRasterGrid1( rasterGrid, size )
		return RotateRasterGrid1( rotatedRasterGrid, sm.vec3.new( size.y, size.x, size.z ) )
	elseif rotation == 3 then
		local rotatedRasterGrid = RotateRasterGrid1( rasterGrid, size )
		rotatedRasterGrid = RotateRasterGrid1( rotatedRasterGrid, sm.vec3.new( size.y, size.x, size.z ) )
		return RotateRasterGrid1( rotatedRasterGrid, size )
	end
	return rasterGrid
end

function DebugPrintRasterGrid( rasterGrid )
	if not rasterGrid then
		return
	end
	local str = ""
	for z = 0, #rasterGrid - 1 do
		for y = 3, 0, -1 do
			for x = 0, 3 do
				if bit.band( rasterGrid[z + 1], bit.lshift( bit.lshift( 1, x ), 4 * y ) ) ~= 0 then
					str = str.."# "
				else
					str = str..". "
				end
			end
			print( str )
			str = ""
		end
		print( " " )
	end
end

function WriteChunkRaster( pos, size, value, rasterGrid, debugDrawColor )
	for y = pos.y, pos.y + size.y - 1 do
		for x = pos.x, pos.x + size.x - 1 do
			for z = pos.z, pos.z + size.z - 1 do
				local xyz = sm.vec3.new( x, y, z )
				local offset = xyz - pos
				local write = true
				if rasterGrid then
					write = bit.band( rasterGrid[offset.z + 1], bit.lshift( bit.lshift( 1, offset.x ), 4 * offset.y ) ) ~= 0
				end
				if write then







					local cellX = math.floor( x / CHUNKS_PER_CELL )
					local cellY = math.floor( y / CHUNKS_PER_CELL )
					local chunkRasterRow = g_cellTemp.chunkRaster[cellY]
					if chunkRasterRow == nil then
						break
					end
					local chunkRaster = chunkRasterRow[cellX]
					if chunkRaster == nil then
						break
					end
					chunkRaster[ToChunkRasterIndex( x % CHUNKS_PER_CELL, y % CHUNKS_PER_CELL, z )] = value
				end
			end
		end
	end
end

function CheckIfFits( pos, size, rasterGrid, minValue, padding )
	minValue = minValue or 1
	padding = padding or 0
	for z = pos.z, pos.z + size.z - 1 do
		for y = pos.y - padding, pos.y + size.y + padding - 1 do
			for x = pos.x - padding, pos.x + size.x + padding - 1 do
				local xyz = sm.vec3.new( x, y, z )
				local check = true
				if rasterGrid then
					local offset = xyz - pos
					offset = sm.vec3.max( offset, sm.vec3.zero() )
					offset = sm.vec3.min( offset, size - sm.vec3.one() )
					-- When using padding, this extends the edge outwards
					check = bit.band( rasterGrid[offset.z + 1], bit.lshift( bit.lshift( 1, offset.x ), 4 * offset.y ) ) ~= 0
				end
				if check then
					if z < MIN_HEIGHT_IN_CHUNKS or z >= MAX_HEIGHT_IN_CHUNKS then
						return false
					end
					if GetChunkRaster( x, y, z ) >= minValue then
						--sm.debugDraw.addAabb( "VoxelProcDebug_NoFitHit"..x..","..y..","..z, xyz * CHUNK_SIZE + 0.5, ( xyz + 1 ) * CHUNK_SIZE - 0.5, sm.color.new( "ff0000" ) )
						--sm.debugDraw.addAabb( "VoxelProcDebug_NoFitPocket"..x..","..y..","..z, pos * CHUNK_SIZE + 0.25, ( pos + size ) * CHUNK_SIZE - 0.25, sm.color.new( "800000" ) )
						return false
					end
				end
			end
		end
	end
	return true
end

-------------------------------------------------------------------------------

function EncodeVec3( vec3, bitsX, bitsY, bitsZ )
	assert( vec3.x >= 0 and vec3.x <= 2^bitsX - 1, "Invalid value: "..vec3.x )
	assert( vec3.y >= 0 and vec3.y <= 2^bitsY - 1, "Invalid value: "..vec3.y )
	assert( vec3.z >= 0 and vec3.z <= 2^bitsZ - 1, "Invalid value: "..vec3.z )
	local value = bit.tobit( vec3.x )
	value = bit.bor( value, bit.lshift( vec3.y, bitsX ) )
	value = bit.bor( value, bit.lshift( vec3.z, bitsX + bitsY ) )
	return value
end

function DecodeVec3( value, bitsX, bitsY, bitsZ )
	local x = bit.band( value, 2^bitsX - 1 )
	local y = bit.band( bit.rshift( value, bitsX ), 2^bitsY - 1 )
	local z = bit.band( bit.rshift( value, bitsX + bitsY ), 2^bitsZ - 1 )
	return sm.vec3.new( x, y, z )
end

-------------------------------------------------------------------------------

function AddCaveCellData( tileUid, cell, zOffset, height )
	local cellCaves = g_cellData.caves[cell.y][cell.x]
	assert( cellCaves )
	local tileIndex = g_randomTileLookup[tostring( tileUid )]
	assert( g_savedTileList[tileIndex] == tileUid )
	local value = tileIndex
	value = bit.bor( value, bit.lshift( zOffset, 8 ) )
	value = bit.bor( value, bit.lshift( height - 1, 12 ) )
	value = bit.bor( value, bit.lshift( cell.offsetX, 16 ) )
	value = bit.bor( value, bit.lshift( cell.offsetY, 18 ) )
	value = bit.bor( value, bit.lshift( cell.rotation, 20 ) )
	cellCaves[#cellCaves + 1] = value
end

function DecodeCaveCellData( value )
	local tileUid = g_savedTileList[bit.band( value, 0xff )]
	local rotation, srcOffset, dstOffset, srcSize = DecodeCaveTransform( value )
	return tileUid, rotation, srcOffset, dstOffset, srcSize
end

function DecodeCaveTransform( value )
	local dstOffset = sm.vec3.zero()
	dstOffset.z = bit.band( bit.rshift( value, 8 ), 0xf )
	local srcSize = sm.vec3.new( 4, 4, 0 )
	srcSize.z = bit.band( bit.rshift( value, 12 ), 0xf ) + 1
	local srcOffset = sm.vec3.zero()
	srcOffset.x = bit.band( bit.rshift( value, 16 ), 0x3 )
	srcOffset.y = bit.band( bit.rshift( value, 18 ), 0x3 )
	local rotation = bit.band( bit.rshift( value, 20 ), 0x3 )
	return rotation, srcOffset, dstOffset, srcSize
end

-------------------------------------------------------------------------------

function AddPocketCellData( dstPos, tileUid, rotation, srcOffset, dstSize, recursion, ppre )
	ppre = ppre or ""
	local function pprint( ... )
		--print( ppre, ... )
	end
	pprint( "-----------------------------" )
	pprint( "AddPocketCellData", dstPos, tileUid, rotation, srcOffset, dstSize )
	pprint( "-----------------------------" )
	local cellX = math.floor( dstPos.x / CHUNKS_PER_CELL )
	local cellY = math.floor( dstPos.y / CHUNKS_PER_CELL )
	local pockets = g_cellData.pockets[cellY][cellX]
	assert( pockets )

	local dstOffsetX = dstPos.x % CHUNKS_PER_CELL
	local dstOffsetY = dstPos.y % CHUNKS_PER_CELL

	local srcSize
	if rotation % 2 == 1 then
		srcSize = sm.vec3.new( dstSize.y, dstSize.x, dstSize.z )
	else
		srcSize = sm.vec3.new( dstSize.x, dstSize.y, dstSize.z )
	end
	pprint( "dstSize:", dstSize )
	pprint( "srcSize:", srcSize )

	local clampedDstSize = sm.vec3.new( dstSize.x, dstSize.y, dstSize.z )
	local clampedSrcSize = sm.vec3.new( srcSize.x, srcSize.y, srcSize.z )

	if dstOffsetY + clampedDstSize.y > CHUNKS_PER_CELL then
		clampedDstSize.y = CHUNKS_PER_CELL - dstOffsetY
		if rotation % 2 == 1 then
			clampedSrcSize.x = CHUNKS_PER_CELL - dstOffsetY
		else
			clampedSrcSize.y = CHUNKS_PER_CELL - dstOffsetY
		end
		pprint( "Y over bounds:", dstPos.y, "+", dstSize.y, "=", dstPos.y + dstSize.y, "clamped to", dstPos.y + clampedDstSize.y )

		local splitOffset = sm.vec3.zero()
		if rotation == 0 then
			splitOffset.y = clampedSrcSize.y
		elseif rotation == 1 then
			splitOffset.x = clampedSrcSize.x
		end

		if not recursion then -- Quick fix
			AddPocketCellData( sm.vec3.new( dstPos.x, dstPos.y + clampedDstSize.y, dstPos.z ),
				tileUid, rotation, srcOffset + splitOffset, dstSize - sm.vec3.new( 0, clampedDstSize.y, 0 ), true, ppre.."  " )
		end
	end
	if dstOffsetX + clampedDstSize.x > CHUNKS_PER_CELL then
		clampedDstSize.x = CHUNKS_PER_CELL - dstOffsetX
		if rotation % 2 == 1 then
			clampedSrcSize.y = CHUNKS_PER_CELL - dstOffsetX
		else
			clampedSrcSize.x = CHUNKS_PER_CELL - dstOffsetX
		end
		pprint( "X over bounds:", dstPos.x, "+", dstSize.x, "=", dstPos.x + dstSize.x, "clamped to", dstPos.x + clampedDstSize.x )

		local splitOffset = sm.vec3.zero()
		if rotation == 0 then
			splitOffset.x = clampedSrcSize.x
		elseif rotation == 3 then
			splitOffset.y = clampedSrcSize.y
		end

		AddPocketCellData( sm.vec3.new( dstPos.x + clampedDstSize.x, dstPos.y, dstPos.z ),
			tileUid, rotation, srcOffset + splitOffset, dstSize - sm.vec3.new( clampedDstSize.x, 0, 0 ), true, ppre.."  " )
	end
	pprint( "clampedDstSize", clampedDstSize )
	pprint( "clampedSrcSize", clampedSrcSize )

	local splitOffset = sm.vec3.zero()
	if rotation == 1 then
		splitOffset.y = srcSize.y - clampedSrcSize.y
	elseif rotation == 2 then
		splitOffset.x = srcSize.x - clampedSrcSize.x
		splitOffset.y = srcSize.y - clampedSrcSize.y
	elseif rotation == 3 then
		splitOffset.x = srcSize.x - clampedSrcSize.x
	end
	pprint( "splitOffset:", splitOffset )
	pprint( "<" )

	local tileIndex = g_randomTileLookup[tostring( tileUid )]
	assert( g_savedTileList[tileIndex] == tileUid )

	local value = tileIndex
	value = bit.bor( value, bit.lshift( EncodeVec3( sm.vec3.new( dstOffsetX, dstOffsetY, dstPos.z ), 2, 2, 4 ), 8 ) )
	value = bit.bor( value, bit.lshift( EncodeVec3( clampedSrcSize - sm.vec3.one(), 2, 2, 4 ), 16 ) ) --TODO: Not needed since size is known
	value = bit.bor( value, bit.lshift( srcOffset.x + splitOffset.x, 24 ) )
	value = bit.bor( value, bit.lshift( srcOffset.y + splitOffset.y, 26 ) )
	value = bit.bor( value, bit.lshift( rotation, 28 ) )
	pockets[#pockets + 1] = value
end

function DecodePocketCellData( value )
	local tileUid = g_savedTileList[bit.band( value, 0xff )]
	local rotation, srcOffset, dstOffset, srcSize = DecodePocketTransform( value )
	return tileUid, rotation, srcOffset, dstOffset, srcSize
end

function DecodePocketTransform( value )
	local dstOffset = DecodeVec3( bit.rshift( value, 8 ), 2, 2, 4 )
	local srcSize = DecodeVec3( bit.rshift( value, 16 ), 2, 2, 4 ) + sm.vec3.one()
	local srcOffset = sm.vec3.zero()
	srcOffset.x = bit.band( bit.rshift( value, 24 ), 0x3 )
	srcOffset.y = bit.band( bit.rshift( value, 26 ), 0x3 )
	local rotation = bit.band( bit.rshift( value, 28 ), 0x3 )
	return rotation, srcOffset, dstOffset, srcSize
end
