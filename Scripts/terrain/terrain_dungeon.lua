dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/terrain_util2.lua" )
dofile( "$SURVIVAL_DATA/Scripts/kinematic_util.lua")
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile "$SURVIVAL_DATA/Scripts/terrain/tile_database.lua"
dofile( "$GAME_DATA/Scripts/terrain/terrain_prepare_cell_util.lua" )

local LOCATION_STORAGE_VERSION = 1

function Init( world, generatorIndex, data )
    g_world = world
    g_generatorIndex = generatorIndex

	if data.path then
		g_terrainJson = sm.json.open( data.path )
		g_zones = g_terrainJson.zoneData
		g_portals = g_terrainJson.portalData

		g_tileTable = {}
		for _, cell in ipairs( g_terrainJson.cellData ) do
			g_tileTable[tostring( sm.terrainTile.getTileUuid( cell.path ) )] = cell.path
		end

		for _, cell in ipairs( g_terrainJson.cellData ) do
			if cell.path and cell.path ~= "" then
				AddTile( cell.path, nil, nil )
			end
		end
	end
end

-------------------------------------------------------------------------------------------

function Create( xMin, xMax, yMin, yMax, seed, data )

	math.randomseed( seed )
	
	print( "----- terrain_dungeon.lua - Create world", g_world.id, "[Thread: "..g_generatorIndex.."]-----" )
	
	print( "Creating dungeon terrain" )
	print( "Bounds X: ["..xMin..", "..xMax.."], Y: ["..yMin..", "..yMax.."]" )
	print( "Seed:", seed )
	print( "Data:", data )
	print( "Total cells: " .. ( xMax - xMin + 1 ) * ( yMax - yMin + 1 ) )

	----------
	print( "Initializing cell data" )


	g_cellData = {
		bounds = { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax },
		seed = seed,
		uid = {},
		groupId = {},
		xOffset = {},
		yOffset = {},
		rotation = {},
	}
	
	for cellY = yMin, yMax do
		g_cellData.uid[cellY] = {}
		g_cellData.xOffset[cellY] = {}
		g_cellData.yOffset[cellY] = {}
		g_cellData.rotation[cellY] = {}
		g_cellData.groupId[cellY] = {}
		
		for cellX = xMin, xMax do
			g_cellData.uid[cellY][cellX] = sm.uuid.getNil()
			g_cellData.xOffset[cellY][cellX] = 0
			g_cellData.yOffset[cellY][cellX] = 0
			g_cellData.rotation[cellY][cellX] = 0
			g_cellData.groupId[cellY][cellX] = 0
		end
	end

	-----------------

	print( "Reading cell list" )
	for _, cell in ipairs( g_terrainJson.cellData ) do
		if g_cellData.uid[cell.y][cell.x] then
			if cell.path and cell.path ~= "" then
				local uid = sm.terrainTile.getTileUuid( cell.path )
				g_cellData.uid[cell.y][cell.x] = uid
				g_cellData.xOffset[cell.y][cell.x] = cell.offsetX
				g_cellData.yOffset[cell.y][cell.x] = cell.offsetY
				g_cellData.rotation[cell.y][cell.x] = cell.rotation
			end
		end
	end

	local elevatorLocationStorage = sm.terrainGeneration.loadGameStorage( STORAGE_CHANNEL_ELEVATOR_LOCATIONS ) or {}
	if not elevatorLocationStorage[g_world.id] then
		elevatorLocationStorage[g_world.id] = {}
	end
	for _, cell in ipairs( g_terrainJson.cellData ) do
		if g_cellData.uid[cell.y][cell.x] then
			if cell.path and cell.path ~= "" then
				local uid, tileCellOffsetX, tileCellOffsetY = GetCellTileUidAndOffset( cell.x, cell.y )
				if not uid:isNil() then
					local cellNodes = sm.terrainTile.getNodesForCell( uid, tileCellOffsetX, tileCellOffsetY )
					for _, node in ipairs( cellNodes ) do
						if isAnyOf( "GROWLAB_ELEVATOR", node.tags ) then
							local rx, ry = RotateLocal( cell.x, cell.y, node.pos.x, node.pos.y )
							local x = cell.x * CELL_SIZE + rx
							local y = cell.y * CELL_SIZE + ry
							local z = node.pos.z
							node.pos = sm.vec3.new( x, y, z )
							node.rot = GetRotationQuat( cell.x, cell.y ) * node.rot
							print( "found GROWLAB_ELEVATOR in cell ", cell.x, cell.y )
							table.insert( elevatorLocationStorage[g_world.id], node )
						end
					end
				end
			end
		end
	end
	sm.terrainGeneration.saveGameStorage( STORAGE_CHANNEL_ELEVATOR_LOCATIONS, elevatorLocationStorage )

	sm.terrainGeneration.setGameStorageNoSave( "tileData"..g_world.id, GetTileDatabase() )

	sm.terrainData.save( g_cellData )
	UpdateLocationStorage()
end

function Load()

	if g_generatorIndex == 0 and sm.isHost then
		sm.terrainGeneration.setGameStorageNoSave( "tileData"..g_world.id , GetTileDatabase() )
	end

    if sm.terrainData.exists() then
		g_cellData = sm.terrainData.load()
		UpdateLocationStorage()
		return true
	end
	return false
end

function GetCullingZoneTree()
	return g_portals, g_zones
end

----------------------------------------------------------------------------------------------------
-- Generator API Getters
----------------------------------------------------------------------------------------------------

function GetCellTileUidAndOffset( cellX, cellY )
	if InsideCellBounds( cellX, cellY ) then
		return 	g_cellData.uid[cellY][cellX],
				g_cellData.xOffset[cellY][cellX],
				g_cellData.yOffset[cellY][cellX]
	end
	return sm.uuid.getNil(), 0, 0
end

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

function PrepareCell( cellX, cellY, loadFlags )
	DefaultPrepareCell( cellX, cellY, loadFlags )
end

-------------------------------------------------------------------------------------------------------

function GetAssetsForCell( cellX, cellY, size )
	local prefabAssets = g_prefabAssets
	g_prefabAssets = {}

	local uid, xOffset, yOffset = GetCellTileUidAndOffset( cellX, cellY )
	if not uid:isNil() then
		local assets = sm.terrainTile.getAssetsForCell( uid, xOffset, yOffset, size )
		concat( assets, prefabAssets )
		for _, asset in ipairs( assets ) do
			asset.pos.x, asset.pos.y = RotateLocal( cellX, cellY, asset.pos.x, asset.pos.y )
			asset.pos.z = WaterSurfaceGridOffset( asset, asset.pos.z )
			asset.rot = GetRotationQuat( cellX, cellY ) * asset.rot
		end
		return assets
	end
	return {}
end

function GetDecalsForCell( cellX, cellY )
	local prefabDecals = g_prefabDecals
	g_prefabDecals = {}

	local uid, xOffset, yOffset = GetCellTileUidAndOffset( cellX, cellY )
	if not uid:isNil() then
		local decalList = sm.terrainTile.getDecalsForCell( uid, xOffset, yOffset )
		concat( decalList, prefabDecals )
		for _, decal in ipairs( decalList ) do
			decal.pos.x, decal.pos.y = RotateLocal( cellX, cellY, decal.pos.x, decal.pos.y )
			decal.rot = GetRotationQuat( cellX, cellY ) * decal.rot	
		end
		return decalList
	end
	return {}
end

function GetHarvestablesForCell( cellX, cellY, size )
	local prefabHarvestables = g_prefabHarvestables
	g_prefabHarvestables = {}

	local uid, xOffset, yOffset = GetCellTileUidAndOffset( cellX, cellY )
	if not uid:isNil() then
		local harvestableList = sm.terrainTile.getHarvestablesForCell( uid, xOffset, yOffset, size )
		concat( harvestableList, prefabHarvestables )
		for _, harvestable in ipairs( harvestableList ) do
			harvestable.pos.x, harvestable.pos.y = RotateLocal( cellX, cellY, harvestable.pos.x, harvestable.pos.y )
			harvestable.rot = GetRotationQuat( cellX, cellY ) * harvestable.rot	
		end
		return harvestableList
	end
	return {}
end

function GetKinematicsForCell( cellX, cellY, size, terrainTaskTick )
	local prefabKinematics = g_prefabKinematics
	g_prefabKinematics = {}

	local uid, tileCellOffsetX, tileCellOffsetY = GetCellTileUidAndOffset( cellX, cellY )
	if not uid:isNil() then
		-- Load kinematics from cell
		local kinematics = sm.terrainTile.getKinematicsForCell( uid, tileCellOffsetX, tileCellOffsetY, size )
		concat( kinematics, prefabKinematics )

		local tileStorageKey
		local storageData
		if #kinematics > 0 then
			tileStorageKey = CalculateTileStorageKey( g_world.id, cellX, cellY )
			storageData = sm.terrainGeneration.loadGameStorage( tileStorageKey )
		end
		
		for _, kinematic in ipairs( kinematics ) do
			local rx, ry = RotateLocal( cellX, cellY, kinematic.pos.x, kinematic.pos.y )
			local x = cellX * CELL_SIZE + rx
			local y = cellY * CELL_SIZE + ry

			kinematic.pos = sm.vec3.new( rx, ry, kinematic.pos.z )
			kinematic.rot = GetRotationQuat( cellX, cellY ) * kinematic.rot

			LoadKinematicFromStorage( kinematic, storageData, sm.vec3.new( x, y, kinematic.pos.z ), terrainTaskTick, g_world, cellX, cellY )
		end
		
		return kinematics
	end
	return {}
end

----------------------------------------------------------------------------------------------------

function GetCreationsForCell( cellX, cellY )
	local prefabCreations = g_prefabCreations
	g_prefabCreations = {}

	local uid, xOffset, yOffset = GetCellTileUidAndOffset( cellX, cellY )
	if not uid:isNil() then
		local creationList = sm.terrainTile.getCreationsForCell( uid, xOffset, yOffset )
		concat( creationList, prefabCreations )

		for _, creation in ipairs( creationList ) do
			creation.pos.x, creation.pos.y = RotateLocal( cellX, cellY, creation.pos.x, creation.pos.y )
			creation.rot = GetRotationQuat( cellX, cellY ) * creation.rot
		end
		return creationList
	end
	return {}
end

function GetNodesForCell( cellX, cellY )
	local prefabNodes = g_prefabNodes
	g_prefabNodes = {}

	local uid, xOffset, yOffset = GetCellTileUidAndOffset( cellX, cellY )
	if not uid:isNil() then
		local nodeList = sm.terrainTile.getNodesForCell( uid, xOffset, yOffset )
		concat( nodeList, prefabNodes )
		for _, node in ipairs( nodeList ) do
			node.pos.x, node.pos.y = RotateLocal( cellX, cellY, node.pos.x, node.pos.y )
			node.rot = GetRotationQuat( cellX, cellY ) * node.rot
			node.pos.z = WaterNodeGridOffset( node, node.pos.z )
		end
		return nodeList
	end
	return {}
end

----------------------------------------------------------------------------------------------------

function GetCellGroups()
	if g_cellData.groupId then
		return g_cellData.groupId
	end
	return {}
end


----------------------------------------------------------------------------------------------------
-- Tile Reader Path Getter
----------------------------------------------------------------------------------------------------

function GetTilePath( uid )
	local path = g_tileTable[tostring( uid )]
	if path then
		return path
	end
	return "$SURVIVAL_DATA/Terrain/Tiles/Error_1024.tile"
end

-----------------------------------------------------------------------------------------------------
-- Util
-----------------------------------------------------------------------------------------------------

local CellNodeCache = {}

function GetNodesForCellWithCache( uid, tileCellOffsetX, tileCellOffsetY )
	local nodes
	local hash = sm.util.hash( uid, tileCellOffsetX, tileCellOffsetY )
	if CellNodeCache[hash] then
		nodes = CellNodeCache[hash]
	else
		nodes = sm.terrainTile.getNodesForCell( uid, tileCellOffsetX, tileCellOffsetY )
		CellNodeCache[hash] = nodes
	end
	return nodes
end

function UpdateLocationStorage()
	if g_generatorIndex == 0 and sm.isHost then

		local storage = sm.terrainGeneration.loadGameStorage( STORAGE_CHANNEL_LOCATIONS ) or { [g_world.id] = { version = 0 } }
		if storage[g_world.id] == nil then
			storage[g_world.id] = { version = 0 }
		end
		if storage[g_world.id].version ~= LOCATION_STORAGE_VERSION then
			storage = { [g_world.id] = { version = LOCATION_STORAGE_VERSION } }

-- find location nodes, prints lines to use in the uuidSearch table below




















			
			local questMarkerSearch = {}
			questMarkerSearch[#questMarkerSearch+1] = { name = "quest_clear_minidungeon.endmarker", uuid = sm.uuid.new("d3d4d976-d2a6-4d21-95bd-fada26b6b371"), pos = sm.vec3.new( 367.99996948242, 216.00006103516, 1 ), isSideQuest = false }
			local questMarkers = {}
			local precacheStorage = sm.terrainGeneration.loadGameStorage( STORAGE_CHANNEL_PRECACHED_MARKERS ) or {}

			function AddQuestMarker( name, tileSize, pos, cellX, cellY, isSideQuest )
				assert(cellX)
				assert(cellY)
				local minCellX, minCellY = GetTileMinCell( cellX, cellY, tileSize )
				local rx, ry = RotateLocal( cellX, cellY, pos.x, pos.y, tileSize * CELL_SIZE )
				local x = (cellX - (cellX - minCellX)) * CELL_SIZE + rx
				local y = (cellY - (cellY - minCellY)) * CELL_SIZE + ry
				local z = pos.z
				questMarkers[#questMarkers+1] = { pos = sm.vec3.new( x, y, z ), world = g_world, params = { name = name, isSideQuest = isSideQuest } }
			end

			for cellY = g_cellData.bounds.yMin, g_cellData.bounds.yMax do
				for cellX = g_cellData.bounds.xMin, g_cellData.bounds.xMax do
					local uid = GetCellTileUid( cellX, cellY )

					for index, search in reverse_ipairs( questMarkerSearch ) do
						if search.uuid == uid then
							AddQuestMarker( search.name, GetSize( uid ), search.pos, cellX, cellY, search.isSideQuest )
							table.remove( questMarkerSearch, index )
						end
					end
				end
			end

			precacheStorage[g_world.id] = questMarkers
			sm.terrainGeneration.saveGameStorage( STORAGE_CHANNEL_PRECACHED_MARKERS, precacheStorage )
		end
	end
end