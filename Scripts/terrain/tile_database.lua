
----------------------------------------------------------------------------------------------------
-- Tile database
----------------------------------------------------------------------------------------------------

local f_idToTilePath = {}

----------------------------------------------------------------------------------------------------

function GetPath( uid )
	if not f_idToTilePath[tostring( uid )] then
		return nil
	end
	return f_idToTilePath[tostring( uid )].path
end

function GetSize( uid )
	if not f_idToTilePath[tostring( uid )] then
		return nil
	end
	return f_idToTilePath[tostring( uid )].size
end

function GetTerrainType( uid )
	if not f_idToTilePath[tostring( uid )] then
		return nil
	end
	return f_idToTilePath[tostring( uid )].terrainType
end

function GetPoiType( uid )
	if not f_idToTilePath[tostring( uid )] then
		return nil
	end
	return f_idToTilePath[tostring( uid )].poiType
end

function GetTileDatabase()
	return f_idToTilePath
end

----------------------------------------------------------------------------------------------------

function AddTile( path, terrainType, poiType, index )
	if path == "" then
		return sm.uuid.getNil()
	end
	terrainType = terrainType or 1
	local uid = sm.terrainTile.getTileUuid( path )
	local size = sm.terrainTile.getSize( path )
	local chunkSize = ( PathToSize and PathToSize( path, true ) )

	if f_idToTilePath[tostring( uid )] == nil then
		f_idToTilePath[tostring( uid )] = { path = path, size = size, chunkSize = chunkSize, terrainType = terrainType, poiType = poiType, index = index }
	end
	return uid
end